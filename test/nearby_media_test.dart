import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:sembast/sembast_memory.dart';
import 'package:offgrid_sos/data/local/local_database.dart';
import 'package:offgrid_sos/models/user.dart';
import 'package:offgrid_sos/services/nearby_mesh_service.dart';
import 'package:offgrid_sos/services/nearby_media_files.dart';

const alice = AppUser(
  id: 'media-a',
  firstName: 'A',
  lastName: 'Camera',
  isMember: false,
);
const bob = AppUser(
  id: 'media-b',
  firstName: 'B',
  lastName: 'Receiver',
  isMember: false,
);
typedef Packet = ({String from, String to, Map<String, dynamic> frame});

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory temporary;
  late Map<String, NearbyMeshService> nodes;
  late Map<String, LocalDatabase> databases;
  late List<Packet> queue, history, clearHistory;
  bool interrupt = false, corrupt = false;
  late Uint8List content;
  late File original;

  Future<Map<String, dynamic>> openFrame(Packet packet) async {
    final frame = packet.frame;
    final sender = nodes[packet.from]!;
    if (frame['kind'] != 'routed' || frame['origin'] != sender.deviceId) {
      return frame;
    }
    final body = Map<String, dynamic>.from(frame['data'] as Map);
    final target = body['target'] as String;
    return sender.crypto.open(
      sender.routes[target]!.certificate,
      body,
      '${frame['origin']}|$target|${frame['id']}',
    );
  }

  Future<Map<String, dynamic>> sealFrame(
    Packet packet,
    Map<String, dynamic> clear,
  ) async {
    final frame = Map<String, dynamic>.from(packet.frame);
    final body = Map<String, dynamic>.from(frame['data'] as Map);
    final target = body['target'] as String;
    final sender = nodes[packet.from]!;
    frame['data'] = {
      'target': target,
      ...await sender.crypto.seal(
        sender.routes[target]!.certificate,
        clear,
        '${frame['origin']}|$target|${frame['id']}',
      ),
    };
    return frame;
  }

  NearbyMeshService node(AppUser user) => NearbyMeshService.withDatabase(
    databases[user.id]!,
    mediaFiles: NearbyMediaFiles(root: '${temporary.path}/${user.id}'),
    sendBytes: (endpoint, bytes) async {
      expect(bytes.length, lessThanOrEqualTo(32768));
      var frame = Map<String, dynamic>.from(
        jsonDecode(utf8.decode(bytes)) as Map,
      );
      final packet = (from: user.id, to: endpoint, frame: frame);
      final clear = Map<String, dynamic>.from(await openFrame(packet));
      if (interrupt &&
          clear['kind'] == 'media_chunk' &&
          (clear['data'] as Map)['offset'] >= NearbyMediaFiles.chunkBytes) {
        throw StateError('simulated radio loss');
      }
      if (corrupt && clear['kind'] == 'media_chunk') {
        final chunk = base64Decode((clear['data'] as Map)['bytes']);
        chunk[0] ^= 1;
        (clear['data'] as Map)['bytes'] = base64Encode(chunk);
        frame = await sealFrame(packet, clear);
        corrupt = false;
      }
      clearHistory.add((from: user.id, to: endpoint, frame: clear));
      final outgoing = (from: user.id, to: endpoint, frame: frame);
      queue.add(outgoing);
      history.add(outgoing);
    },
  );

  Future<void> pumpUntil(Future<bool> Function() done) async {
    final end = DateTime.now().add(const Duration(seconds: 10));
    while (DateTime.now().isBefore(end)) {
      while (queue.isNotEmpty) {
        final packet = queue.removeAt(0);
        await nodes[packet.to]!.handleEnvelope(packet.from, packet.frame);
      }
      if (await done()) {
        await Future<void>.delayed(const Duration(milliseconds: 5));
        return;
      }
      await Future<void>.delayed(const Duration(milliseconds: 2));
    }
    fail('transfer did not reach the expected state');
  }

  Future<void> pair() async {
    await nodes[alice.id]!.transportConnected(bob.id);
    await nodes[bob.id]!.transportConnected(alice.id);
    await pumpUntil(
      () async => [
        nodes[alice.id]!,
        nodes[bob.id]!,
      ].every((n) => n.identities.isNotEmpty),
    );
  }

  Future<String> send({String type = 'image'}) async {
    await nodes[alice.id]!.sendAttachment(
      target: nodes[bob.id]!.deviceId,
      path: original.path,
      name: type == 'image' ? 'กล้อง.jpg' : 'clip.mp4',
      type: type,
    );
    final rows = await nodes[alice.id]!.chats
        .watchMessages(alice.id, nodes[bob.id]!.deviceId)
        .first;
    return (rows.last['envelope'] as Map)['id'] as String;
  }

  Future<bool> delivered(String id) async =>
      (await nodes[alice.id]!.chats.find(alice.id, id))?['delivery'] ==
      'delivered';

  setUp(() async {
    temporary = await Directory.systemTemp.createTemp('offgrid-media-test-');
    nodes = {};
    databases = {};
    queue = [];
    history = [];
    clearHistory = [];
    interrupt = false;
    corrupt = false;
    content = Uint8List.fromList(List.generate(64001, (i) => (i * 17) % 251));
    original = await File(
      '${temporary.path}/camera-cache.jpg',
    ).writeAsBytes(content);
    for (final user in [alice, bob]) {
      databases[user.id] = LocalDatabase.withDatabase(
        await newDatabaseFactoryMemory().openDatabase(user.id),
      );
      nodes[user.id] = node(user);
      await nodes[user.id]!.initializeForUser(user);
    }
  });
  tearDown(() async {
    for (final n in nodes.values) {
      n.dispose();
    }
    await Future<void>.delayed(const Duration(milliseconds: 30));
    for (final db in databases.values) {
      await (await db.database).close();
    }
    await temporary.delete(recursive: true);
  });

  test(
    'photo and video travel A to C through B with bounded encrypted frames',
    () async {
      const carol = AppUser(
        id: 'media-c',
        firstName: 'C',
        lastName: 'Relay receiver',
        isMember: false,
      );
      databases[carol.id] = LocalDatabase.withDatabase(
        await newDatabaseFactoryMemory().openDatabase(carol.id),
      );
      nodes[carol.id] = node(carol);
      await nodes[carol.id]!.initializeForUser(carol);
      await pair();
      await nodes[bob.id]!.transportConnected(carol.id);
      await nodes[carol.id]!.transportConnected(bob.id);
      await pumpUntil(
        () async =>
            nodes[alice.id]!.peerForDevice(nodes[carol.id]!.deviceId) != null,
      );
      for (final type in ['image', 'video']) {
        await nodes[alice.id]!.sendAttachment(
          target: nodes[carol.id]!.deviceId,
          path: original.path,
          name: 'attachment.$type',
          type: type,
        );
        final rows = await nodes[alice.id]!.chats
            .watchMessages(alice.id, nodes[carol.id]!.deviceId)
            .first;
        final id = (rows.last['envelope'] as Map)['id'] as String;
        await pumpUntil(() => delivered(id));
        final row = await nodes[carol.id]!.chats.find(carol.id, id);
        expect(await File(row!['localPath'] as String).readAsBytes(), content);
        expect(await nodes[bob.id]!.chats.find(bob.id, id), isNull);
      }
      expect(history.where((p) => p.frame['kind'] == 'routed'), isNotEmpty);
      expect(history.where((p) => p.frame['kind'] == 'media_chunk'), isEmpty);
    },
  );

  test(
    'three-node media transfer resumes when the relay returns without Internet',
    () async {
      const carol = AppUser(
        id: 'media-c',
        firstName: 'C',
        lastName: 'Receiver',
        isMember: false,
      );
      databases[carol.id] = LocalDatabase.withDatabase(
        await newDatabaseFactoryMemory().openDatabase(carol.id),
      );
      nodes[carol.id] = node(carol);
      await nodes[carol.id]!.initializeForUser(carol);
      await pair();
      await nodes[bob.id]!.transportConnected(carol.id);
      await nodes[carol.id]!.transportConnected(bob.id);
      await pumpUntil(
        () async =>
            nodes[alice.id]!.peerForDevice(nodes[carol.id]!.deviceId) != null,
      );
      await nodes[alice.id]!.sendAttachment(
        target: nodes[carol.id]!.deviceId,
        path: original.path,
        name: 'offline-bridge.mp4',
        type: 'video',
      );
      final rows = await nodes[alice.id]!.chats
          .watchMessages(alice.id, nodes[carol.id]!.deviceId)
          .first;
      final id = (rows.single['envelope'] as Map)['id'] as String;
      await pumpUntil(
        () async =>
            (nodes[carol.id]!.media.progress[id]?.bytes ?? 0) >=
            NearbyMediaFiles.chunkBytes,
      );
      await nodes[bob.id]!.stop();
      await pumpUntil(
        () async =>
            nodes[alice.id]!.media.progress[id]?.error != null ||
            await delivered(id),
      );
      expect(await delivered(id), isFalse);
      queue.clear();
      nodes[bob.id]!.dispose();
      nodes[bob.id] = node(bob);
      await nodes[bob.id]!.initializeForUser(bob);
      await pair();
      await nodes[bob.id]!.transportConnected(carol.id);
      await nodes[carol.id]!.transportConnected(bob.id);
      await pumpUntil(() => delivered(id));
      final saved = await nodes[carol.id]!.chats.find(carol.id, id);
      expect(await File(saved!['localPath'] as String).readAsBytes(), content);
      expect(
        await nodes[carol.id]!.chats
            .watchMessages(carol.id, nodes[alice.id]!.deviceId)
            .first,
        hasLength(1),
      );
      expect(await nodes[bob.id]!.chats.watchThreads(bob.id).first, isEmpty);
    },
  );

  test(
    'camera recovery with the same message ID does not create duplicates',
    () async {
      for (var n = 0; n < 2; n++) {
        await nodes[alice.id]!.sendAttachment(
          target: nodes[bob.id]!.deviceId,
          path: original.path,
          name: 'camera.jpg',
          type: 'image',
          messageId: 'stable-capture',
        );
      }
      final rows = await nodes[alice.id]!.chats
          .watchMessages(alice.id, nodes[bob.id]!.deviceId)
          .first;
      expect(rows, hasLength(1));
    },
  );

  test(
    'photo is copied out of camera cache, chunked, verified and saved without cloud',
    () async {
      await pair();
      final id = await send();
      await original.delete();
      await pumpUntil(() => delivered(id));
      final row = await nodes[bob.id]!.chats.find(bob.id, id);
      expect(row?['delivery'], 'delivered');
      expect(await File(row!['localPath'] as String).readAsBytes(), content);
      expect(
        clearHistory.where((p) => p.frame['kind'] == 'media_chunk').length,
        greaterThan(1),
      );
      expect(
        jsonEncode(history.map((p) => p.frame).toList()),
        isNot(contains(temporary.path)),
      );
      final outgoing = await nodes[alice.id]!.chats.find(alice.id, id);
      expect(outgoing!.containsKey('media_bytes'), isFalse);
    },
  );

  test('video queued without a link sends after receiver connects', () async {
    final id = await send(type: 'video');
    expect(queue, isEmpty);
    expect(await delivered(id), isFalse);
    await pair();
    await pumpUntil(() => delivered(id));
    final row = await nodes[bob.id]!.chats.find(bob.id, id);
    expect(((row!['envelope'] as Map)['data'] as Map)['type'], 'video');
    expect(await File(row['localPath'] as String).readAsBytes(), content);
  });

  test(
    'interrupted transfer resumes persisted bytes after receiver restarts',
    () async {
      await pair();
      interrupt = true;
      final id = await send();
      await pumpUntil(
        () async => nodes[alice.id]!.media.progress[id]?.error != null,
      );
      expect(await nodes[bob.id]!.chats.find(bob.id, id), isNull);
      nodes[bob.id]!.dispose();
      nodes[bob.id] = node(bob);
      await nodes[bob.id]!.initializeForUser(bob);
      nodes[alice.id]!.media.cancel();
      interrupt = false;
      history.clear();
      clearHistory.clear();
      queue.clear();
      await pair();
      await nodes[alice.id]!.retryFor(nodes[bob.id]!.deviceId);
      await pumpUntil(() => delivered(id));
      final chunks = clearHistory.where(
        (p) => p.frame['kind'] == 'media_chunk',
      );
      expect(
        (chunks.first.frame['data'] as Map)['offset'],
        NearbyMediaFiles.chunkBytes,
      );
      final row = await nodes[bob.id]!.chats.find(bob.id, id);
      expect(await File(row!['localPath'] as String).readAsBytes(), content);
    },
  );

  test(
    'corrupted file never becomes delivered and clean retry creates one message',
    () async {
      await pair();
      corrupt = true;
      final id = await send();
      await pumpUntil(
        () async => nodes[alice.id]!.media.progress[id]?.error != null,
      );
      expect(await delivered(id), isFalse);
      expect(await nodes[bob.id]!.chats.find(bob.id, id), isNull);
      await nodes[alice.id]!.retryFor(nodes[bob.id]!.deviceId);
      await pumpUntil(() => delivered(id));
      final index = clearHistory.indexWhere(
        (p) => p.frame['kind'] == 'media_start',
      );
      final start = clearHistory[index];
      await nodes[bob.id]!.handleEnvelope(
        alice.id,
        await sealFrame(history[index], start.frame),
      );
      await pumpUntil(() async => queue.isEmpty);
      expect(
        await nodes[bob.id]!.chats
            .watchMessages(bob.id, nodes[alice.id]!.deviceId)
            .first,
        hasLength(1),
      );
    },
  );

  test(
    'wrong recipient and unpaired identity cannot start a file transfer',
    () async {
      await pair();
      final id = await send();
      await pumpUntil(() => delivered(id));
      final index = clearHistory.indexWhere(
        (p) => p.frame['kind'] == 'media_start',
      );
      final clear = Map<String, dynamic>.from(clearHistory[index].frame);
      final before = history.length;
      clear['origin'] = 'forged';
      await nodes[bob.id]!.handleEnvelope(
        alice.id,
        await sealFrame(history[index], clear),
      );
      expect(history.length, before);
      clear['origin'] = nodes[alice.id]!.deviceId;
      clear['data'] = {...clear['data'] as Map, 'target': 'another-device'};
      await nodes[bob.id]!.handleEnvelope(
        alice.id,
        await sealFrame(history[index], clear),
      );
      expect(history.length, before);
    },
  );

  test('empty and oversized files are rejected before queuing', () async {
    await original.writeAsBytes([]);
    await expectLater(send(), throwsStateError);
    final handle = await original.open(mode: FileMode.write);
    await handle.truncate(NearbyMediaFiles.maxBytes + 1);
    await handle.close();
    await expectLater(send(), throwsStateError);
    expect(await nodes[alice.id]!.chats.watchThreads(alice.id).first, isEmpty);
  });
}
