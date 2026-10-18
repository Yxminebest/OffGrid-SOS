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
  late List<Packet> queue, history;
  bool interrupt = false, corrupt = false;
  late Uint8List content;
  late File original;

  NearbyMeshService node(AppUser user) => NearbyMeshService.withDatabase(
    databases[user.id]!,
    mediaFiles: NearbyMediaFiles(root: '${temporary.path}/${user.id}'),
    sendBytes: (endpoint, bytes) async {
      expect(bytes.length, lessThanOrEqualTo(32768));
      final frame = Map<String, dynamic>.from(
        jsonDecode(utf8.decode(bytes)) as Map,
      );
      if (interrupt &&
          frame['kind'] == 'media_chunk' &&
          (frame['data'] as Map)['offset'] >= NearbyMediaFiles.chunkBytes) {
        throw StateError('simulated radio loss');
      }
      if (corrupt && frame['kind'] == 'media_chunk') {
        final chunk = base64Decode((frame['data'] as Map)['bytes']);
        chunk[0] ^= 1;
        (frame['data'] as Map)['bytes'] = base64Encode(chunk);
        corrupt = false;
      }
      final packet = (from: user.id, to: endpoint, frame: frame);
      queue.add(packet);
      history.add(packet);
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
        history.where((p) => p.frame['kind'] == 'media_chunk').length,
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
      queue.clear();
      await pair();
      await nodes[alice.id]!.retryFor(nodes[bob.id]!.deviceId);
      await pumpUntil(() => delivered(id));
      final chunks = history.where((p) => p.frame['kind'] == 'media_chunk');
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
      final start = history.firstWhere((p) => p.frame['kind'] == 'media_start');
      await nodes[bob.id]!.handleEnvelope(alice.id, start.frame);
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
      final frame = Map<String, dynamic>.from(
        history.firstWhere((p) => p.frame['kind'] == 'media_start').frame,
      );
      final before = history.length;
      frame['origin'] = 'forged';
      await nodes[bob.id]!.handleEnvelope(alice.id, frame);
      expect(history.length, before);
      frame['origin'] = nodes[alice.id]!.deviceId;
      frame['data'] = {...frame['data'] as Map, 'target': 'another-device'};
      await nodes[bob.id]!.handleEnvelope(alice.id, frame);
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
