import 'dart:async';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../app/supabase_config.dart';

/// An interface may be an offline D2D link. Probe our cloud, not the radio.
class NetworkService {
  NetworkService({
    Future<bool> Function()? probe,
    Future<List<ConnectivityResult>> Function()? interfaces,
    Stream<List<ConnectivityResult>>? changes,
  }) : _probe = probe ?? _cloudReachable,
       _interfaces = interfaces ?? Connectivity().checkConnectivity,
       _changes = changes ?? Connectivity().onConnectivityChanged;
  static final instance = NetworkService();
  final Future<bool> Function() _probe;
  final Future<List<ConnectivityResult>> Function() _interfaces;
  final Stream<List<ConnectivityResult>> _changes;
  final online = ValueNotifier<bool>(false);
  final _events = StreamController<bool>.broadcast();
  StreamSubscription<List<ConnectivityResult>>? _monitor;
  Timer? _timer;
  Future<bool>? _checking;
  static Future<bool> _cloudReachable() async {
    final client = http.Client();
    try {
      final response = await client
          .get(
            Uri.parse('${SupabaseConfig.url}/auth/v1/health'),
            headers: {'apikey': SupabaseConfig.publishableKey},
          )
          .timeout(const Duration(seconds: 4));
      return response.statusCode == 200;
    } catch (_) {
      return false;
    } finally {
      client.close();
    }
  }

  void start() {
    _monitor ??= _changes.listen((_) => unawaited(hasConnection));
    _timer ??= Timer.periodic(
      const Duration(seconds: 15),
      (_) => unawaited(hasConnection),
    );
    unawaited(hasConnection);
  }

  Future<bool> get hasConnection => _checking ??= _check().whenComplete(() {
    _checking = null;
  });
  Future<bool> _check() async {
    var reachable = false;
    try {
      final links = await _interfaces();
      reachable =
          links.any((r) => r != ConnectivityResult.none) && await _probe();
    } catch (_) {
      reachable = false;
    }
    if (online.value != reachable) {
      online.value = reachable;
      _events.add(reachable);
    }
    return reachable;
  }

  Stream<bool> get connectionChanges => _events.stream;

  Future<void> dispose() async {
    _timer?.cancel();
    await _monitor?.cancel();
    await _events.close();
    online.dispose();
  }
}
