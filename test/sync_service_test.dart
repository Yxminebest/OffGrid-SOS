import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:offgrid_sos/services/nearby_media_files.dart';

import 'package:flutter_test/flutter_test.dart';
import 'package:sembast/sembast_memory.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:offgrid_sos/data/local/local_database.dart';
import 'package:offgrid_sos/data/repositories/sos_repository.dart';
import 'package:offgrid_sos/data/repositories/message_repository.dart';
import 'package:offgrid_sos/data/repositories/sync_queue_repository.dart';
import 'package:offgrid_sos/models/user.dart';
import 'package:offgrid_sos/services/sync_service.dart';
import 'package:offgrid_sos/data/repositories/nearby_chat_repository.dart';

const me = AppUser(
  id: 'member-a',
  firstName: 'A',
  lastName: 'User',
  isMember: true,
);

Future<void> waitUntil(Future<bool> Function() ready) async {
  final deadline = DateTime.now().add(const Duration(seconds: 5));
  while (!await ready()) {
    if (DateTime.now().isAfter(deadline)) {
      throw TimeoutException('Sync did not finish');
    }
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}

class ArchiveFiles extends NearbyMediaFiles {
  @override
  Future<bool> exists(String path) async => true;
  @override
  Future<Uint8List> allBytes(String path) async =>
      Uint8List.fromList([1, 2, 3]);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late HttpServer server;
  late SupabaseClient client;
  late LocalDatabase local;
  late SosRepository sos;
  late SyncQueueRepository queue;
  late SyncService sync;
  late Future<void> Function(HttpRequest) handle;
  late Future<bool> Function() hasConnection;
  late List<Map<String, dynamic>> uploaded;
  late List<int> preserved;

  setUp(() async {
    // These integration tests use a loopback server, not widget HTTP mocks.
    HttpOverrides.global = null;
    final db = await newDatabaseFactoryMemory().openDatabase('sync');
    local = LocalDatabase.withDatabase(db);
    sos = SosRepository(local: local);
    queue = SyncQueueRepository(local: local);
    uploaded = [];
    preserved = [];
    hasConnection = () async => true;
    handle = (request) async {
      request.response.statusCode = 200;
      request.response.headers.contentType = ContentType.json;
      request.response.write('[]');
      await request.response.close();
    };
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      final bytes = await request.fold<List<int>>(
        [],
        (all, chunk) => all..addAll(chunk),
      );
      final body = request.uri.path.startsWith('/storage/')
          ? ''
          : utf8.decode(bytes);
      if (body.isNotEmpty) {
        uploaded.add(Map<String, dynamic>.from(jsonDecode(body) as Map));
      }
      await handle(request);
    });
    client = SupabaseClient(
      'http://127.0.0.1:${server.port}',
      'test-key',
      authOptions: const AuthClientOptions(autoRefreshToken: false),
    );
    final expiration = DateTime.now().millisecondsSinceEpoch ~/ 1000 + 3600;
    final payload = base64Url
        .encode(utf8.encode(jsonEncode({'exp': expiration, 'sub': me.id})))
        .replaceAll('=', '');
    await client.auth.recoverSession(
      jsonEncode({
        'access_token': 'eyJhbGciOiJIUzI1NiJ9.$payload.test',
        'refresh_token': 'test-refresh',
        'token_type': 'bearer',
        'expires_in': 3600,
        'user': {
          'id': me.id,
          'aud': 'authenticated',
          'app_metadata': {},
          'user_metadata': {},
          'created_at': DateTime.now().toUtc().toIso8601String(),
        },
      }),
    );
    sync = SyncService(
      preserveMedia: (_, _, bytes) async {
        preserved = List.of(bytes);
      },
      local: local,
      client: client,
      hasConnection: () => hasConnection(),
      connectionChanges: const Stream<bool>.empty(),
      retryInterval: const Duration(milliseconds: 20),
    );
  });

  tearDown(() async {
    await sync.stop();
    sync.status.dispose();
    await client.dispose();
    await server.close(force: true);
    await (await local.database).close();
  });

  test(
    'archive media uploads once even if metadata upsert must retry',
    () async {
      await sync.stop();
      sync.status.dispose();
      sync = SyncService(
        local: local,
        client: client,
        nearbyFiles: ArchiveFiles(),
        hasConnection: () async => true,
        connectionChanges: const Stream.empty(),
      );
      final nearby = NearbyChatRepository(local: local);
      await nearby.save(
        me.id,
        'peer',
        {
          'id': 'archive-photo',
          'kind': 'media',
          'data': {'type': 'image'},
        },
        incoming: false,
        localPath: '/private/photo',
      );
      var storageUploads = 0, metadataAttempts = 0;
      handle = (request) async {
        request.response.headers.contentType = ContentType.json;
        if (request.uri.path.startsWith('/storage/')) {
          storageUploads++;
          request.response.write(
            '{"Key":"nearby-archive/member-a/archive-photo"}',
          );
        } else if (request.method == 'POST') {
          metadataAttempts++;
          if (metadataAttempts == 1) {
            request.response.statusCode = 503;
            request.response.write('{"message":"temporary database failure"}');
          } else {
            request.response.write('[]');
          }
        } else {
          request.response.write('[]');
        }
        await request.response.close();
      };
      await sync.syncNow();
      expect(storageUploads, 1);
      expect(
        (await nearby.find(me.id, 'archive-photo'))!['cloudState'],
        'pending',
      );
      await sync.retryAll();
      expect(storageUploads, 1);
      expect(metadataAttempts, 2);
      expect(
        (await nearby.find(me.id, 'archive-photo'))!['cloudState'],
        'synced',
      );
    },
  );

  test(
    'Nearby-only outbox archives automatically and ACK changes requeue safely',
    () async {
      final nearby = NearbyChatRepository(local: local);
      final env = <String, dynamic>{
        'id': 'nearby-id',
        'kind': 'direct',
        'origin': 'device-a',
        'at': DateTime.now().toUtc().toIso8601String(),
        'data': {'target': 'device-b', 'text': 'offline'},
      };
      await nearby.save(me.id, 'device-b', env, incoming: false);
      await sync.start();
      expect(uploaded.single['owner_id'], me.id);
      expect(uploaded.single['envelope']['data']['text'], 'offline');
      expect((await nearby.find(me.id, 'nearby-id'))!['cloudState'], 'synced');
      await nearby.acknowledge(me.id, 'nearby-id', 'device-b');
      await waitUntil(() async => uploaded.length >= 2);
      await waitUntil(
        () async =>
            (await nearby.find(me.id, 'nearby-id'))!['cloudState'] == 'synced',
      );
      expect(uploaded.last['delivery'], 'delivered');
    },
  );

  test(
    'archive completion cannot clear a newer local acknowledgment',
    () async {
      final nearby = NearbyChatRepository(local: local);
      await nearby.save(me.id, 'peer', {
        'id': 'race',
        'kind': 'direct',
        'at': '2026-10-18',
        'data': {'text': 'x'},
      }, incoming: false);
      final original = (await nearby.unsynced(me.id)).single;
      await nearby.acknowledge(me.id, 'race', 'peer');
      await nearby.archived(me.id, 'race', original['revision']);
      expect((await nearby.find(me.id, 'race'))!['cloudState'], 'pending');
    },
  );

  test(
    'restore imports account archive without replacing a pending local message',
    () async {
      final nearby = NearbyChatRepository(local: local);
      await nearby.save(me.id, 'peer', {
        'id': 'local-pending',
        'kind': 'direct',
        'at': '2026-10-18',
        'data': {'text': 'local'},
      }, incoming: false);
      handle = (request) async {
        request.response.headers.contentType = ContentType.json;
        request.response.write(
          jsonEncode([
            {
              'owner_id': me.id,
              'message_id': 'restored',
              'peer': 'peer',
              'incoming': true,
              'delivery': 'delivered',
              'revision': 1,
              'envelope': {
                'id': 'restored',
                'kind': 'direct',
                'at': '2026-10-18',
                'data': {'text': 'backup'},
              },
            },
            {
              'owner_id': me.id,
              'message_id': 'local-pending',
              'peer': 'peer',
              'incoming': false,
              'delivery': 'delivered',
              'revision': 1,
              'envelope': {
                'id': 'local-pending',
                'kind': 'direct',
                'at': '2026-10-18',
                'data': {'text': 'old copy'},
              },
            },
          ]),
        );
        await request.response.close();
      };
      expect(await sync.restoreNearbyArchive(), 1);
      expect((await nearby.find(me.id, 'restored'))!['cloudState'], 'synced');
      final pending = (await nearby.find(me.id, 'local-pending'))!;
      expect(pending['delivery'], 'pending');
      expect((pending['envelope'] as Map)['data']['text'], 'local');
    },
  );

  test(
    'missing archive migration retains local data and retries rather than marking synced',
    () async {
      final nearby = NearbyChatRepository(local: local);
      await nearby.save(me.id, 'peer', {
        'id': 'offline',
        'kind': 'direct',
        'data': {'text': 'keep'},
      }, incoming: false);
      handle = (request) async {
        request.response.statusCode = 404;
        request.response.headers.contentType = ContentType.json;
        request.response.write('{"code":"PGRST205","message":"missing table"}');
        await request.response.close();
      };
      await sync.syncNow();
      expect((await nearby.find(me.id, 'offline'))!['cloudState'], 'pending');
      expect(sync.status.value.activity, SyncActivity.error);
      expect(sync.status.value.pendingCount, 1);
    },
  );

  test(
    'concurrent sync calls share a lock during the connectivity await',
    () async {
      await sos.create(user: me, message: 'help');
      final online = Completer<bool>();
      var connectivityChecks = 0;
      hasConnection = () {
        connectivityChecks++;
        return online.future;
      };
      final first = sync.syncNow();
      final second = sync.syncNow();
      expect(connectivityChecks, 1);
      online.complete(true);
      await Future.wait([first, second]);
      expect(uploaded, hasLength(1));
      expect(await queue.countFor(me.id), 0);
    },
  );

  test(
    'attachment original is preserved before upload clears database bytes',
    () async {
      final messages = MessageRepository(local: local);
      final message = await messages.create(
        user: me,
        conversationId: 'room',
        type: 'image',
        mediaBytes: [1, 2, 3],
        mediaName: 'camera.jpg',
        mediaMime: 'image/jpeg',
      );
      handle = (request) async {
        expect(preserved, [1, 2, 3]);
        request.response.headers.contentType = ContentType.json;
        request.response.write(
          request.uri.path.startsWith('/storage/')
              ? '{"Key":"camera.jpg"}'
              : '[]',
        );
        await request.response.close();
      };
      await sync.syncNow();
      final stored = await messages.findById(message.id);
      expect(stored?.syncState, 'synced');
      expect(stored?.mediaBytes, isNull);
      expect(stored?.mediaPath, isNotNull);
      expect(preserved, [1, 2, 3]);
    },
  );

  test(
    'edit during a real pending response is uploaded on the next pass',
    () async {
      final record = await sos.create(user: me, message: 'old');
      final received = Completer<void>();
      final release = Completer<void>();
      handle = (request) async {
        if (!received.isCompleted) {
          received.complete();
          await release.future;
        }
        request.response.write('[]');
        await request.response.close();
      };
      final inFlight = sync.syncNow();
      await received.future.timeout(const Duration(seconds: 5));
      await sos.updateMessage(record, 'new');
      release.complete();
      await inFlight;
      expect(await queue.countFor(me.id), 1);
      expect((await sos.findById(record.id))!.syncState, 'pending');
      await sync.syncNow();
      expect(uploaded.map((row) => row['message']), ['old', 'new']);
      expect(await queue.countFor(me.id), 0);
    },
  );

  test('automatic retry runs without a connectivity change', () async {
    await sos.create(user: me, message: 'retry');
    var failed = false;
    handle = (request) async {
      request.response.headers.contentType = ContentType.json;
      if (!failed) {
        failed = true;
        request.response.statusCode = 400;
        request.response.write('{"message":"temporary failure","code":"test"}');
      } else {
        request.response.write('[]');
      }
      await request.response.close();
    };
    await sync.start();
    expect(sync.status.value.activity, SyncActivity.error);
    expect(await queue.countFor(me.id), 1);
    final db = await local.database;
    final job = (await local.syncQueueStore.find(db)).single;
    // Make the retry due; the timer must discover it without a stream event.
    await local.syncQueueStore.record(job.key).update(db, {
      'next_retry_at': DateTime.now()
          .subtract(const Duration(seconds: 1))
          .toUtc()
          .toIso8601String(),
    });
    await waitUntil(() async => await queue.countFor(me.id) == 0);
    expect(uploaded, hasLength(2));
  });

  test(
    'stop waits for an in-flight upload and leaves other jobs pending',
    () async {
      await sos.create(user: me, message: 'first');
      await sos.create(user: me, message: 'second');
      final received = Completer<void>();
      final release = Completer<void>();
      handle = (request) async {
        received.complete();
        await release.future;
        request.response.write('[]');
        await request.response.close();
      };
      final inFlight = sync.syncNow();
      await received.future.timeout(const Duration(seconds: 5));
      var stopped = false;
      final stopping = sync.stop().then((_) => stopped = true);
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(stopped, isFalse);
      release.complete();
      await Future.wait([inFlight, stopping]);
      expect(uploaded, hasLength(1));
      expect(await queue.countFor(me.id), 1);
      expect(sync.status.value.activity, SyncActivity.idle);
    },
  );
}
