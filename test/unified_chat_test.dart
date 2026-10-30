import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:sembast/sembast_memory.dart';
import 'package:offgrid_sos/data/local/local_database.dart';
import 'package:offgrid_sos/data/models/local_chat_conversation.dart';
import 'package:offgrid_sos/models/user.dart';
import 'package:offgrid_sos/services/location_service.dart';
import 'package:offgrid_sos/services/mesh_crypto.dart';
import 'package:offgrid_sos/services/nearby_mesh_service.dart';
import 'package:offgrid_sos/services/unified_chat_service.dart';

const user = AppUser(
  id: 'user-a',
  firstName: 'A',
  lastName: '',
  isMember: true,
);
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late LocalDatabase local;
  late NearbyMeshService mesh;
  late UnifiedChatService chat;
  late bool online;
  late int syncs;
  late List<Map<String, dynamic>> sent;
  late Map<String, MeshCrypto> remoteCrypto;
  late Map<String, Map<String, dynamic>> remoteCertificates;
  setUp(() async {
    local = LocalDatabase.withDatabase(
      await newDatabaseFactoryMemory().openDatabase('unified'),
    );
    sent = [];
    online = false;
    syncs = 0;
    remoteCrypto = {};
    remoteCertificates = {};
    for (final suffix in ['b', 'c']) {
      final store = <String, String>{};
      final crypto = MeshCrypto(
        read: (k) async => store[k],
        write: (k, v) async {
          store[k] = v;
        },
      );
      await crypto.initialize('user-$suffix');
      remoteCrypto['device-$suffix'] = crypto;
      remoteCertificates['device-$suffix'] = await crypto.certificate(
        'device-$suffix',
        suffix.toUpperCase(),
        'user-$suffix',
      );
    }
    mesh = NearbyMeshService.withDatabase(
      local,
      sendBytes: (String endpoint, Uint8List bytes) async {
        var packet = Map<String, dynamic>.from(
          jsonDecode(utf8.decode(bytes)) as Map,
        );
        if (packet['kind'] == 'routed') {
          final own = await mesh.crypto.certificate(
            mesh.deviceId,
            user.fullName,
            user.id,
          );
          packet = await remoteCrypto[endpoint]!.open(
            own,
            packet['data'] as Map,
            '${packet['origin']}|$endpoint|${packet['id']}',
          );
        }
        sent.add(packet);
      },
    );
    await mesh.initializeForUser(user);
    chat = UnifiedChatService(
      local: local,
      mesh: mesh,
      online: () => online,
      syncCloud: () async {
        syncs++;
      },
      resolveCloud: (me, c) async {
        final conv = LocalChatConversation(
          id: 'conv-${c.user}',
          ownerLocalId: me.id,
          peerUserId: c.user!,
          displayName: c.name,
          updatedAt: DateTime.now(),
        );
        await local.conversationStore
            .record('${me.id}:${conv.id}')
            .put(await local.database, conv.toLocalMap());
        return conv;
      },
    );
  });
  tearDown(() async {
    chat.stop();
    mesh.dispose();
    await (await local.database).close();
  });
  void connect({
    String device = 'device-b',
    String? account = 'user-b',
    String name = 'B',
  }) {
    mesh.connected.add(device);
    mesh.routes[device] = MeshRoute(
      remoteCertificates[device]!,
      device,
      1,
      DateTime.now().add(const Duration(seconds: 40)),
      [device],
    );
    mesh.identities[device] = NearbyPeer(
      endpoint: device,
      deviceId: device,
      name: name,
      userId: account,
      attestedUntil: DateTime.now().add(const Duration(days: 1)),
    );
  }

  Future<void> settle() async {
    await Future<void>.delayed(const Duration(milliseconds: 30));
  }

  test('device and member history merge by paired ID, never by name', () async {
    connect();
    await chat.rememberPeers(user.id);
    await mesh.sendDirect(
      target: 'device-b',
      text: 'offline',
      messageId: 'same-id',
      peerName: 'B',
    );
    online = true;
    chat.start(user);
    await settle();
    await chat.flush();
    final rows = await chat.inbox(user.id);
    expect(rows, hasLength(1));
    expect(rows.single.contact.user, 'user-b');
    expect(rows.single.messages, hasLength(1));
    expect(rows.single.messages.single.id, 'same-id');
    expect(await chat.messages.findById('same-id'), isNotNull);
    connect(device: 'device-c', account: 'user-c', name: 'B');
    await chat.rememberPeers(user.id);
    expect(await chat.inbox(user.id), hasLength(2));
  });
  test(
    'offline queued message later uploads same ID and original timestamp',
    () async {
      connect();
      await chat.rememberPeers(user.id);
      mesh.connected.clear();
      chat.start(user);
      await settle();
      await chat.send(
        user,
        const ChatContact(name: 'B', device: 'device-b'),
        text: 'queued',
        messageId: 'queue-id',
      );
      expect(
        (await chat.inbox(user.id)).single.messages.single.status,
        'pending',
      );
      final at = (await chat.inbox(user.id)).single.messages.single.at;
      expect(await chat.messages.findById('queue-id'), isNull);
      online = true;
      await chat.flush();
      final saved = await chat.messages.findById('queue-id');
      expect(saved!.content, 'queued');
      expect(saved.createdAt.toUtc(), at.toUtc());
      expect((await chat.inbox(user.id)).single.messages, hasLength(1));
      expect(syncs, greaterThan(0));
    },
  );
  test('cloud room offline queue finds paired radio after reconnect', () async {
    final conv = LocalChatConversation(
      id: 'cloud-room',
      ownerLocalId: user.id,
      peerUserId: 'user-b',
      displayName: 'B',
      updatedAt: DateTime.now(),
    );
    await local.conversationStore
        .record('room')
        .put(await local.database, conv.toLocalMap());
    chat.start(user);
    await settle();
    await chat.send(
      user,
      const ChatContact(name: 'B', user: 'user-b', conversation: 'cloud-room'),
      text: 'no internet',
      messageId: 'offline-cloud-id',
    );
    expect(await mesh.chats.find(user.id, 'offline-cloud-id'), isNull);
    await settle();
    connect();
    await chat.flush();
    final radio = await mesh.chats.find(user.id, 'offline-cloud-id');
    expect((radio!['envelope'] as Map)['id'], 'offline-cloud-id');
    expect(sent.any((e) => e['id'] == 'offline-cloud-id'), isTrue);
    expect((await chat.inbox(user.id)).single.messages, hasLength(1));
  });
  test('offline location keeps coordinates accuracy and timestamp', () async {
    chat.start(user);
    await settle();
    final point = SavedLocation(
      latitude: 14.1,
      longitude: 100.6,
      accuracyMeters: 8,
      recordedAt: DateTime.now(),
    );
    await chat.send(
      user,
      const ChatContact(name: 'B', device: 'device-b'),
      location: point,
      messageId: 'gps-id',
    );
    final item = (await chat.inbox(user.id)).single.messages.single;
    expect(item.type, 'location');
    expect(item.lat, 14.1);
    expect(item.accuracy, 8);
    expect(item.status, 'pending');
  });
  test('new owner cannot send into previous owners radio session', () async {
    await expectLater(
      chat.send(
        const AppUser(
          id: 'wrong',
          firstName: 'Wrong',
          lastName: '',
          isMember: true,
        ),
        const ChatContact(name: 'B', device: 'device-b'),
        text: 'private',
      ),
      throwsStateError,
    );
    expect(await chat.inbox('wrong'), isEmpty);
  });
  test('radio retry proceeds while cloud room resolution is pending', () async {
    connect();
    await chat.rememberPeers(user.id);
    mesh.connected.clear();
    await mesh.sendDirect(
      target: 'device-b',
      text: 'urgent',
      messageId: 'urgent',
    );
    await mesh.sendDirect(
      target: 'device-c',
      text: 'also urgent',
      messageId: 'urgent-c',
    );
    connect();
    connect(device: 'device-c', account: 'user-c', name: 'C');
    online = true;
    final gate = Completer<LocalChatConversation>();
    var cloudLookupStarted = false;
    chat = UnifiedChatService(
      local: local,
      mesh: mesh,
      online: () => online,
      resolveCloud: (_, _) {
        cloudLookupStarted = true;
        return gate.future;
      },
      syncCloud: () async {},
    );
    chat.start(user);
    try {
      final deadline = DateTime.now().add(const Duration(seconds: 3));
      while (DateTime.now().isBefore(deadline) &&
          (!cloudLookupStarted ||
              !sent.any((e) => e['id'] == 'urgent') ||
              !sent.any((e) => e['id'] == 'urgent-c'))) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
      expect(sent.any((e) => e['id'] == 'urgent'), isTrue);
      expect(sent.any((e) => e['id'] == 'urgent-c'), isTrue);
      expect(cloudLookupStarted, isTrue);
    } finally {
      gate.completeError(StateError('cloud unavailable'));
      await chat.flush();
    }
    expect(chat.lastError, contains('cloud unavailable'));
    expect(await mesh.chats.find(user.id, 'urgent'), isNotNull);
  });
  test('cloud queued old location remains labelled old on radio', () async {
    final db = await local.database;
    final conv = LocalChatConversation(
      id: 'old-location-room',
      ownerLocalId: user.id,
      peerUserId: 'user-b',
      displayName: 'B',
      updatedAt: DateTime.now(),
    );
    await local.conversationStore
        .record('old-location-room')
        .put(db, conv.toLocalMap());
    await chat.messages.create(
      user: user,
      conversationId: conv.id,
      messageId: 'old-gps',
      type: 'location',
      content: 'ตำแหน่งที่แชร์ · พิกัดเก่า',
      latitude: 14.1,
      longitude: 100.6,
      accuracy: 49,
    );
    connect();
    chat.start(user);
    await chat.flush();
    final row = await mesh.chats.find(user.id, 'old-gps');
    final body = (row!['envelope'] as Map)['data'] as Map;
    expect(body['lastKnown'], isTrue);
    expect(body['accuracy'], 49);
    expect(
      (await chat.inbox(user.id)).single.messages.single.lastKnown,
      isTrue,
    );
  });
  test('account change during contact lookup blocks queued send', () async {
    final gate = Completer<ChatContact>();
    chat = _DelayedContactChat(local, mesh, gate);
    final send = chat.send(
      user,
      const ChatContact(name: 'B', device: 'device-b'),
      text: 'private',
      messageId: 'switched',
    );
    final checked = expectLater(send, throwsStateError);
    await mesh.initializeForUser(
      const AppUser(
        id: 'other-owner',
        firstName: 'Other',
        lastName: '',
        isMember: false,
      ),
    );
    gate.complete(const ChatContact(name: 'B', device: 'device-b'));
    await checked;
    expect(await mesh.chats.find('other-owner', 'switched'), isNull);
    expect(await mesh.chats.find(user.id, 'switched'), isNull);
  });
  test('duplicate transport retries preserve one message ID', () async {
    await mesh.sendDirect(
      target: 'device-b',
      text: 'hello',
      messageId: 'dedup',
    );
    await mesh.sendDirect(
      target: 'device-b',
      text: 'hello',
      messageId: 'dedup',
    );
    expect((await chat.inbox(user.id)).single.messages, hasLength(1));
  });
  test(
    'oversized radio text is rejected instead of silently disappearing',
    () async {
      await expectLater(
        chat.send(
          user,
          const ChatContact(name: 'B', device: 'device-b'),
          text: List.filled(4001, 'a').join(),
          messageId: 'too-long',
        ),
        throwsArgumentError,
      );
      expect(await mesh.chats.find(user.id, 'too-long'), isNull);
    },
  );
  test('blank text cannot report a successful queue write', () async {
    await expectLater(
      chat.send(
        user,
        const ChatContact(name: 'B', device: 'device-b'),
        text: '   ',
        messageId: 'blank',
      ),
      throwsArgumentError,
    );
    expect(await mesh.chats.find(user.id, 'blank'), isNull);
  });
  test('stopping service prevents background cloud work', () async {
    connect();
    await chat.rememberPeers(user.id);
    online = true;
    chat.start(user);
    await settle();
    chat.stop();
    final before = syncs;
    await chat.flush();
    expect(syncs, before);
  });
  test(
    'online inbox preview and unread work before room history is downloaded',
    () async {
      final c = LocalChatConversation(
        id: 'new-room',
        ownerLocalId: user.id,
        peerUserId: 'new-peer',
        displayName: 'New',
        updatedAt: DateTime.now(),
        lastMessage: 'new hello',
        lastMessageAt: DateTime.now(),
        unreadCount: 2,
      );
      await local.conversationStore
          .record('new-room')
          .put(await local.database, c.toLocalMap());
      final entry = (await chat.inbox(user.id)).single;
      expect(entry.preview, 'new hello');
      expect(entry.unread, 2);
      expect(entry.messages, isEmpty);
    },
  );
  test(
    'contact bindings are private to their local owner and clear with account data',
    () async {
      connect();
      await chat.rememberPeers(user.id);
      expect(await chat.inbox('other-account'), isEmpty);
      await local.clearOwnerData(user.id);
      expect(await chat.inbox(user.id), isEmpty);
    },
  );
}

class _DelayedContactChat extends UnifiedChatService {
  _DelayedContactChat(LocalDatabase db, NearbyMeshService mesh, this.gate)
    : super(local: db, mesh: mesh, online: () => false);
  final Completer<ChatContact> gate;
  @override
  Future<ChatContact> resolve(AppUser me, ChatContact requested) => gate.future;
}
