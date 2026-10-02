import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';

class NetworkService {
  NetworkService._();

  static final NetworkService instance = NetworkService._();

  final Connectivity _connectivity = Connectivity();

  Future<bool> get hasConnection async {
    final results = await _connectivity.checkConnectivity();
    return _isConnected(results);
  }

  Stream<bool> get connectionChanges {
    return _connectivity.onConnectivityChanged.map(_isConnected).distinct();
  }

  bool _isConnected(List<ConnectivityResult> results) {
    if (results.isEmpty) return false;

    return results.any((result) => result != ConnectivityResult.none);
  }
}
