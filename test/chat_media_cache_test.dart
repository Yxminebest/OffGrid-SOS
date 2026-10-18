import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:offgrid_sos/services/chat_media_cache.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory temporary;
  late HttpServer server;
  late ChatMediaCache cache;
  var requests = 0;
  var failRequest = false;
  setUp(() async {
    HttpOverrides.global = null;
    temporary = await Directory.systemTemp.createTemp('offgrid-cloud-cache-');
    cache = ChatMediaCache(root: temporary.path);
    requests = 0;
    failRequest = false;
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      requests++;
      if (failRequest) {
        request.response.statusCode = 503;
      } else {
        request.response.add(List.generate(64000, (i) => i % 251));
      }
      await request.response.close();
    });
  });
  tearDown(() async {
    await server.close(force: true);
    await temporary.delete(recursive: true);
  });
  Future<String?> url() async => 'http://127.0.0.1:${server.port}/media';

  test('deleting one account removes only its durable media', () async {
    await cache.put('owner-a', 'photo', [1, 2, 3]);
    await cache.put('owner-b', 'photo', [4, 5, 6]);
    final deletedPath = await cache.local('owner-a', 'photo');
    final keptPath = await cache.local('owner-b', 'photo');
    await cache.deleteOwner('owner-a');
    expect(await File(deletedPath!).exists(), false);
    expect(await File(keptPath!).readAsBytes(), [4, 5, 6]);
  });

  test(
    'download survives cache service restart and opens without requesting a URL',
    () async {
      final first = await cache.resolve('owner-a', 'photo', url);
      expect(await File(first!).length(), 64000);
      final reopened = ChatMediaCache(root: temporary.path);
      expect(
        await reopened.resolve(
          'owner-a',
          'photo',
          () async => throw StateError('offline'),
        ),
        first,
      );
      expect(requests, 1);
    },
  );
  test('accounts cannot reuse another accounts cached attachment', () async {
    await cache.resolve('owner-a', 'same-id', url);
    expect(await cache.local('owner-b', 'same-id'), isNull);
    expect(await cache.resolve('owner-b', 'same-id', () async => null), isNull);
  });
  test('concurrent renders share one complete download', () async {
    final paths = await Future.wait(
      List.generate(4, (_) => cache.resolve('a', 'video', url)),
    );
    expect(paths.toSet(), hasLength(1));
    expect(requests, 1);
    expect(
      await File(paths.first!).readAsBytes(),
      List.generate(64000, (i) => i % 251),
    );
  });
  test('failed download leaves no complete file and can be retried', () async {
    failRequest = true;
    await expectLater(cache.resolve('a', 'image', url), throwsStateError);
    expect(await cache.local('a', 'image'), isNull);
    failRequest = false;
    expect(await cache.resolve('a', 'image', url), isNotNull);
  });
  test(
    'outgoing original stays local and concurrent saves do not conflict',
    () async {
      await Future.wait([
        cache.put('a', 'camera', [1, 2, 3]),
        cache.put('a', 'camera', [1, 2, 3]),
      ]);
      final path = await cache.resolve(
        'a',
        'camera',
        () async => throw StateError('offline'),
      );
      expect(await File(path!).readAsBytes(), [1, 2, 3]);
      expect(requests, 0);
    },
  );
}
