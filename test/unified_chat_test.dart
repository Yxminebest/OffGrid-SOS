import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:offgrid_sos/services/nearby_media_files.dart';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:sembast/sembast_memory.dart';
import 'package:offgrid_sos/data/local/local_database.dart';
import 'package:offgrid_sos/data/models/local_chat_conversation.dart';
import 'package:offgrid_sos/models/user.dart';
import 'package:offgrid_sos/services/location_service.dart';
import 'package:offgrid_sos/services/mesh_crypto.dart';
import 'package:offgrid_sos/services/network_service.dart';
import 'package:offgrid_sos/services/nearby_mesh_service.dart';
import 'package:offgrid_sos/services/unified_chat_service.dart';
import 'package:offgrid_sos/services/chat_action.dart';

const user = AppUser(
  id: 'user-a',
  firstName: 'A',
  lastName: '',
  isMember: true,
);
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late LocalDatabase local;
  late Directory temporary;
  late NearbyMeshService mesh;
  late UnifiedChatService chat;
  late bool online;
  late int syncs;
  late List<Map<String, dynamic>> sent;
  late Map<String, MeshCrypto> remoteCrypto;
  late Map<String, Map<String, dynamic>> remoteCertificates;
  setUp(() async {
    temporary = await Directory.systemTemp.createTemp('offgrid-unified-');
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
      mediaFiles: NearbyMediaFiles(root: temporary.path),
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
    final root = temporary.absolute.path;
    final expected =
        '${Directory.systemTemp.absolute.path}${Platform.pathSeparator}offgrid-unified-';
    if (!root.startsWith(expected)) {
      throw StateError('Unexpected test directory');
    }
    await temporary.delete(recursive: true);
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

  test(
    'offline notification selects the persisted radio contact and rejects a different account',
    () async {
      connect();
      await chat.rememberPeers(user.id);
      await chat.send(
        user,
        const ChatContact(name: 'B', device: 'device-b'),
        text: 'hello',
      );
      mesh.connected.clear();
      mesh.routes.clear();
      expect(
        (await chat.notificationContact(
          user.id,
          'device-b',
          transport: 'nearby',
        ))?.name,
        'B',
      );
      expect(
        await chat.notificationContact(user.id, 'device-b', transport: 'cloud'),
        isNull,
      );
      expect(
        await chat.notificationContact(
          'another-account',
          'device-b',
          transport: 'nearby',
        ),
        isNull,
      );
      expect(
        await chat.notificationContact(
          user.id,
          'unknown-peer',
          transport: 'nearby',
        ),
        isNull,
      );
    },
  );
  test(
    'cloud notification opens its cached conversation when Internet is absent',
    () async {
      online = true;
      await chat.send(
        user,
        const ChatContact(name: 'B', user: 'user-b'),
        text: 'cloud',
      );
      final room = (await chat.inbox(user.id)).single.contact.conversation!;
      online = false;
      final contact = await chat.notificationContact(
        user.id,
        room,
        transport: 'cloud',
      );
      expect(contact?.user, 'user-b');
      expect(contact?.conversation, room);
      expect(
        await chat.notificationContact(
          user.id,
          'missing-room',
          transport: 'cloud',
        ),
        isNull,
      );
    },
  );
  test(
    'previously verified cloud identity survives an unverified reconnect',
    () async {
      connect();
      await chat.rememberPeers(user.id);
      mesh.identities['device-b'] = const NearbyPeer(
        endpoint: 'device-b',
        deviceId: 'device-b',
        name: 'B',
      );
      await chat.rememberPeers(user.id);
      expect((await chat.inbox(user.id)).single.contact.user, 'user-b');
      chat.start(user);
      await settle();
      online = true;
      await chat.send(
        user,
        const ChatContact(name: 'B', device: 'device-b'),
        text: 'internet fallback',
        messageId: 'fallback-proof',
      );
      await chat.flush();
      expect(
        (await chat.messages.findById('fallback-proof'))!.content,
        'internet fallback',
      );
      expect(sent.any((m) => m['id'] == 'fallback-proof'), isFalse);
    },
  );

  test(
    'online member without a radio device resolves a room and persists message',
    () async {
      online = true;
      await chat.send(
        user,
        const ChatContact(name: 'B', user: 'user-b'),
        text: 'cloud only',
        messageId: 'cloud-only',
      );
      expect(
        (await chat.messages.findById('cloud-only'))!.conversationId,
        'conv-user-b',
      );
    },
  );

  test(
    'server-confirmed deleted peer is hidden, cancels retries, and cannot be sent to',
    () async {
      connect();
      await chat.rememberPeers(user.id);
      mesh.connected.clear();
      await chat.send(
        user,
        const ChatContact(name: 'B', device: 'device-b'),
        text: 'pending',
        messageId: 'deleted-target',
      );
      chat.stop();
      chat = UnifiedChatService(
        local: local,
        mesh: mesh,
        online: () => online,
        lookupExistingUsers: (_, _) async => <String>{},
      );
      online = true;
      await chat.reconcileDeletedContacts(user, force: true);
      expect(await chat.inbox(user.id), isEmpty);
      expect(await mesh.chats.pending(user.id, 'device-b'), isEmpty);
      await expectLater(
        chat.send(
          user,
          const ChatContact(name: 'B', device: 'device-b'),
          text: 'must not send',
        ),
        throwsStateError,
      );
      expect(await chat.inbox('different-owner'), isEmpty);
    },
  );

  test(
    'failed directory request never hides offline history or cancels messages',
    () async {
      connect();
      await chat.rememberPeers(user.id);
      mesh.connected.clear();
      await chat.send(
        user,
        const ChatContact(name: 'B', device: 'device-b'),
        text: 'keep',
        messageId: 'keep-offline',
      );
      chat.stop();
      chat = UnifiedChatService(
        local: local,
        mesh: mesh,
        online: () => true,
        lookupExistingUsers: (_, _) async =>
            throw StateError('network unavailable'),
      );
      await expectLater(
        chat.reconcileDeletedContacts(user, force: true),
        throwsStateError,
      );
      expect((await chat.inbox(user.id)).single.messages.single.text, 'keep');
      expect(await mesh.chats.pending(user.id, 'device-b'), hasLength(1));
    },
  );

  test(
    'legacy conversation can be hidden locally and sending again restores it',
    () async {
      connect();
      await chat.rememberPeers(user.id);
      mesh.connected.clear();
      const contact = ChatContact(name: 'B', device: 'device-b');
      await chat.send(user, contact, text: 'old', messageId: 'old-hidden');
      await chat.hideConversation(user.id, contact);
      expect(await chat.inbox(user.id), isEmpty);
      await chat.send(user, contact, text: 'new', messageId: 'new-unhidden');
      expect((await chat.inbox(user.id)).single.messages, hasLength(2));
    },
  );

  test(
    'offline photo and video use the same IDs and bytes when cloud returns',
    () async {
      connect();
      await chat.rememberPeers(user.id);
      mesh.connected.clear();
      chat.start(user);
      await settle();
      for (final type in ['image', 'video']) {
        final bytes = List<int>.generate(2300, (i) => (i * 7) % 251);
        final source = await File(
          '${temporary.path}/source-$type',
        ).writeAsBytes(bytes);
        await chat.send(
          user,
          const ChatContact(name: 'B', device: 'device-b'),
          path: source.path,
          name: type == 'image' ? 'photo.jpg' : 'clip.mp4',
          type: type,
          messageId: 'fallback-$type',
        );
      }
      online = true;
      await chat.flush();
      await chat.flush();
      for (final type in ['image', 'video']) {
        final saved = (await chat.messages.findById('fallback-$type'))!;
        expect(saved.messageType, type);
        expect(
          saved.mediaBytes,
          List<int>.generate(2300, (i) => (i * 7) % 251),
        );
        expect(saved.conversationId, 'conv-user-b');
      }
      expect((await chat.inbox(user.id)).single.messages, hasLength(2));
    },
  );

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
  test('video starts directly on radio even when sender has Internet', () async {
    connect();
    online = true;
    final network = NetworkService.instance.online;
    final previous = network.value;
    network.value = true;
    addTearDown(() => network.value = previous);
    chat.start(user);
    await chat.flush();
    final file = File('${temporary.path}/sample.mp4');
    await file.writeAsBytes(List.generate(100, (i) => i));
    await chat.send(
      user,
      const ChatContact(name: 'B', device: 'device-b', user: 'user-b'),
      path: file.path,
      name: 'sample.mp4',
      type: 'video',
      messageId: 'cloud-first-video',
    );
    await chat.flush();
    expect(await chat.messages.findById('cloud-first-video'), isNotNull);
    await settle();
    expect(sent.any((m) => m['kind'] == 'media_start'), isTrue);
    // Server storage must not discard delivery to a receiver without Internet.
    final db = await local.database;
    final ref = local.messageStore.record('cloud-first-video');
    await ref.update(db, {'sync_state': 'synced'});

    online = false;
    network.value = false;
    await mesh.retryFor('device-b');
    await settle();
    expect(sent.any((m) => m['kind'] == 'media_start'), isTrue);
    mesh.media.cancel();
  });
  test(
    'media progress notifications do not restart whole-inbox cloud sync',
    () async {
      connect();
      online = true;
      chat.start(user);
      await chat.flush();
      mesh.notifyListeners();
      await chat.flush();
      final before = syncs;
      for (var i = 0; i < 200; i++) {
        mesh.notifyListeners();
      }
      await settle();
      expect(syncs, before);
    },
  );
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
  test(
    'offline replies and edits persist and later mirror their command IDs to cloud',
    () async {
      connect();
      await chat.rememberPeers(user.id);
      const contact = ChatContact(
        name: 'B',
        device: 'device-b',
        user: 'user-b',
      );
      mesh.connected.clear();
      mesh.routes.clear();
      await chat.send(user, contact, text: 'first', messageId: 'editable');
      await chat.send(
        user,
        contact,
        text: 'answer',
        messageId: 'reply',
        replyToId: 'editable',
      );
      await chat.changeMessage(user, contact, 'editable', text: 'updated');
      final entry = (await chat.inbox(user.id)).single;
      expect(entry.messages.map((m) => m.text), ['updated', 'answer']);
      expect(entry.messages.last.replyToId, 'editable');
      expect(entry.transportMessages, hasLength(3));
      final reloaded = UnifiedChatService(
        local: local,
        mesh: mesh,
        online: () => false,
      );
      expect(
        (await reloaded.inbox(user.id)).single.messages.first.text,
        'updated',
      );
      chat.start(user);
      online = true;
      await chat.flush();
      for (final wire in entry.transportMessages) {
        expect((await chat.messages.findById(wire.id))!.content, wire.text);
      }
    },
  );
  test(
    'global deletion persists through reload and sync without resending the original',
    () async {
      connect();
      await chat.rememberPeers(user.id);
      const contact = ChatContact(
        name: 'B',
        device: 'device-b',
        user: 'user-b',
      );
      mesh.connected.clear();
      mesh.routes.clear();
      await chat.send(user, contact, text: 'hide me', messageId: 'hide-me');
      await chat.deleteMessage(user, contact, 'hide-me');
      final entry = (await chat.inbox(user.id)).single;
      expect(entry.messages, isEmpty);
      expect(entry.preview, isNot('hide me'));
      expect(
        entry.transportMessages.map((m) => m.id),
        isNot(contains('hide-me')),
      );
      final reopened = UnifiedChatService(
        local: local,
        mesh: mesh,
        online: () => false,
      );
      expect((await reopened.inbox(user.id)).single.messages, isEmpty);
      chat.start(user);
      online = true;
      await chat.flush();
      expect((await chat.inbox(user.id)).single.messages, isEmpty);
      expect(await chat.messages.findById('hide-me'), isNull);
      await expectLater(
        chat.deleteMessage(
          user,
          const ChatContact(name: 'C', device: 'device-c'),
          'hide-me',
        ),
        throwsStateError,
      );
    },
  );
  test(
    'online deletion stores its command without a radio link and survives reload',
    () async {
      online = true;
      const contact = ChatContact(name: 'B', user: 'user-b');
      await chat.send(
        user,
        contact,
        text: 'remove online',
        messageId: 'online-delete',
      );
      await chat.deleteMessage(user, contact, 'online-delete');
      final entry = (await chat.inbox(user.id)).single;
      expect(entry.messages, isEmpty);
      expect(
        entry.transportMessages.any(
          (m) => ChatAction.parse(m.text)?.kind == 'delete',
        ),
        isTrue,
      );
      expect(mesh.connected, isEmpty);
      final reopened = UnifiedChatService(
        local: local,
        mesh: mesh,
        online: () => false,
      );
      expect((await reopened.inbox(user.id)).single.messages, isEmpty);
    },
  );
  test(
    'cloud-only media captions persist without changing the original attachment',
    () async {
      online = true;
      const contact = ChatContact(name: 'B', user: 'user-b');
      for (final type in ['image', 'video']) {
        final file = File('${temporary.path}/caption-$type');
        await file.writeAsBytes([1, 2, 3, 4]);
        final id = 'cloud-caption-$type';
        await chat.send(
          user,
          contact,
          type: type,
          path: file.path,
          name: type == 'image' ? 'image.jpg' : 'video.mp4',
          messageId: id,
        );
        await chat.changeMessage(user, contact, id, text: 'updated $type');
        final item = (await chat.inbox(
          user.id,
        )).single.messages.singleWhere((m) => m.id == id);
        expect(item.text, 'updated $type');
        expect(item.type, type);
        expect(item.bytes, [1, 2, 3, 4]);
        expect(item.edited, isTrue);
      }
      final reopened = UnifiedChatService(
        local: local,
        mesh: mesh,
        online: () => false,
      );
      expect(
        (await reopened.inbox(user.id)).single.messages.every((m) => m.edited),
        isTrue,
      );
    },
  );
  test(
    'cloud-only chat edits replies and retracts without a nearby link',
    () async {
      online = true;
      const contact = ChatContact(name: 'B', user: 'user-b');
      await chat.send(
        user,
        contact,
        text: 'cloud first',
        messageId: 'cloud-edit',
      );
      await chat.changeMessage(
        user,
        contact,
        'cloud-edit',
        text: 'cloud updated',
      );
      await chat.send(
        user,
        contact,
        text: 'reply',
        messageId: 'cloud-reply',
        replyToId: 'cloud-edit',
      );
      var entry = (await chat.inbox(user.id)).single;
      expect(entry.messages.first.text, 'cloud updated');
      expect(entry.messages.last.replyToId, 'cloud-edit');
      await chat.changeMessage(user, contact, 'cloud-edit', retract: true);
      entry = (await chat.inbox(user.id)).single;
      expect(entry.messages.any((m) => m.text == 'cloud updated'), isFalse);
      expect(entry.transportMessages.any((m) => m.id == 'cloud-edit'), isFalse);
      expect(mesh.connected, isEmpty);
    },
  );
  test(
    'offline retract stops the original queue and cannot be edited again',
    () async {
      connect();
      await chat.rememberPeers(user.id);
      const contact = ChatContact(
        name: 'B',
        device: 'device-b',
        user: 'user-b',
      );
      mesh.connected.clear();
      mesh.routes.clear();
      await chat.send(user, contact, text: 'first', messageId: 'retracted');
      await chat.changeMessage(user, contact, 'retracted', retract: true);
      final entry = (await chat.inbox(user.id)).single;
      expect(entry.messages.single.retracted, isTrue);
      expect(
        (await mesh.chats.pending(
          user.id,
          'device-b',
        )).any((e) => e['id'] == 'retracted'),
        isFalse,
      );
      expect(entry.transportMessages, hasLength(1));
      await expectLater(
        chat.changeMessage(user, contact, 'retracted', text: 'restore'),
        throwsStateError,
      );
      await expectLater(
        chat.changeMessage(user, contact, 'unknown', retract: true),
        throwsStateError,
      );
      await expectLater(
        chat.send(user, contact, text: 'reply', replyToId: 'retracted'),
        throwsStateError,
      );
      // Removing the local cancellation bubble must not resurrect the original
      // message in the cloud/radio worker's transport list.
      await chat.deleteMessage(user, contact, 'retracted');
      final hidden = (await chat.inbox(user.id)).single;
      expect(hidden.messages, isEmpty);
      expect(hidden.transportMessages.any((m) => m.id == 'retracted'), isFalse);
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
