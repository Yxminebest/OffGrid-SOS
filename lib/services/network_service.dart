import 'dart:async';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../app/supabase_config.dart';

/// A Wi-Fi interface can be an offline D2D link; verify Internet access.
class NetworkService {
  NetworkService({
    Future<bool> Function()? probe,
    Future<List<ConnectivityResult>> Function()? interfaces,
    Stream<List<ConnectivityResult>>? changes,
    http.Client Function()? clientFactory,
  }) : _probe =
           probe ??
           (() => _internetReachable(clientFactory ?? http.Client.new)),
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
  int _revision = 0;
  bool _disposed = false;
  static Future<bool> _internetReachable(
    http.Client Function() createClient,
  ) async {
    final client = createClient();
    try {
      // A cloud outage must not label a working Internet connection offline.
      for (final url in [
        '${SupabaseConfig.url}/auth/v1/health',
        'https://connectivitycheck.gstatic.com/generate_204',
      ]) {
        try {
          final request = http.Request('GET', Uri.parse(url))
            ..followRedirects = false;
          final cloud = url.startsWith(SupabaseConfig.url);
          if (cloud) request.headers['apikey'] = SupabaseConfig.publishableKey;
          final response = await client
              .send(request)
              .timeout(const Duration(seconds: 4));
          final body = await response.stream.toBytes().timeout(
            const Duration(seconds: 2),
          );
          if (cloud
              ? response.statusCode == 200
              : response.statusCode == 204 && body.isEmpty) {
            return true;
          }
        } catch (_) {
          // Try the independent Internet probe, retaining queued cloud work.
        }
      }
      return false;
    } finally {
      client.close();
    }
  }

  void start() {
    if (_disposed) return;
    _monitor ??= _changes.listen((links) {
      _revision++;
      if (links.isEmpty || links.every((r) => r == ConnectivityResult.none)) {
        _publish(false);
      }
      unawaited(hasConnection);
    });
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
    int revision;
    do {
      revision = _revision;
      try {
        final links = await _interfaces();
        reachable =
            links.any((r) => r != ConnectivityResult.none) && await _probe();
      } catch (_) {
        reachable = false;
      }
    } while (!_disposed && revision != _revision);
    if (!_disposed) _publish(reachable);
    return reachable;
  }

  void _publish(bool reachable) {
    if (online.value != reachable) {
      online.value = reachable;
      _events.add(reachable);
    }
  }

  Stream<bool> get connectionChanges => _events.stream;

  Future<void> dispose() async {
    _disposed = true;
    _timer?.cancel();
    await _monitor?.cancel();
    await _events.close();
    online.dispose();
  }
}
