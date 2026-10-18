import 'dart:async';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:offgrid_sos/services/network_service.dart';

void main() {
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
