import 'dart:async';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:offgrid_sos/services/network_service.dart';

void main() {
  test(
    'interface loss during a probe cannot publish stale online state',
    () async {
      var links = [ConnectivityResult.wifi];
      final changes = StreamController<List<ConnectivityResult>>(sync: true);
      final gate = Completer<bool>();
      final started = Completer<void>();
      final service = NetworkService(
        interfaces: () async => links,
        changes: changes.stream,
        probe: () {
          started.complete();
          return gate.future;
        },
      );
      service.start();
      await started.future;
      final check = service.hasConnection;
      links = [ConnectivityResult.none];
      changes.add(links);
      gate.complete(true);
      expect(await check, isFalse);
      expect(service.online.value, isFalse);
      await service.dispose();
      await changes.close();
    },
  );
  test(
    'cloud outage uses independent probe without leaking cloud key',
    () async {
      final service = NetworkService(
        interfaces: () async => [ConnectivityResult.wifi],
        changes: const Stream.empty(),
        clientFactory: () => MockClient((request) async {
          if (request.url.host == 'connectivitycheck.gstatic.com') {
            expect(request.headers.containsKey('apikey'), isFalse);
            expect(request.followRedirects, isFalse);
            return http.Response('', 204);
          }
          return http.Response('unavailable', 503);
        }),
      );
      expect(await service.hasConnection, isTrue);
      await service.dispose();
    },
  );
  test('captive portal cannot make offline Wi-Fi appear online', () async {
    final service = NetworkService(
      interfaces: () async => [ConnectivityResult.wifi],
      changes: const Stream.empty(),
      clientFactory: () => MockClient((_) async => http.Response('login', 302)),
    );
    expect(await service.hasConnection, isFalse);
    await service.dispose();
  });
  test(
    'Wi-Fi D2D without Internet stays offline; cloud recovery needs no radio change',
    () async {
      var reachable = false;
      final service = NetworkService(
        interfaces: () async => [ConnectivityResult.wifi],
        changes: const Stream.empty(),
        probe: () async => reachable,
      );
      expect(await service.hasConnection, false);
      reachable = true;
      expect(await service.hasConnection, true);
      expect(service.online.value, true);
      await service.dispose();
    },
  );
  test(
    'no interface does not probe cloud and exceptions leave offline mode usable',
    () async {
      var probed = false;
      final service = NetworkService(
        interfaces: () async => [ConnectivityResult.none],
        changes: const Stream.empty(),
        probe: () async {
          probed = true;
          throw StateError('offline');
        },
      );
      expect(await service.hasConnection, false);
      expect(probed, false);
      await service.dispose();
    },
  );
}
