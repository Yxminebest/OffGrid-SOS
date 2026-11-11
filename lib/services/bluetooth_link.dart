import 'package:flutter/services.dart';

class BluetoothLink {
  static final instance = BluetoothLink();
  static const _channel = MethodChannel('com.offgridsos/bluetooth');
  bool running = false;
  int _generation = 0;
  Future<void> Function(String id, String name)? onConnected;
  void Function(String id)? onDisconnected;
  void Function(String id, Uint8List bytes)? onBytes;
  void Function(String id, String name)? onRequest;
  void Function(String id)? onRequestClosed;
  Future<bool> start() async {
    final generation = ++_generation;
    _channel.setMethodCallHandler((call) async {
      if (generation != _generation || call.method != 'event') return;
      final args = Map<String, dynamic>.from(call.arguments as Map);
      final id = args['id'] as String;
      switch (args['kind']) {
        case 'request':
          onRequest?.call(id, args['name'] as String);
        case 'requestClosed':
          onRequestClosed?.call(id);
        case 'connected':
          await onConnected?.call(id, args['name'] as String);
        case 'disconnected':
          onDisconnected?.call(id);
        case 'bytes':
          onBytes?.call(id, args['bytes'] as Uint8List);
      }
    });
    try {
      final started = await _channel.invokeMethod<bool>('start') ?? false;
      if (generation != _generation) return false;
      running = started;
    } catch (_) {
      if (generation != _generation) return false;
      running = false;
    }
    return running;
  }

  Future<List<Map<String, String>>> paired() async {
    final rows = await _channel.invokeListMethod<dynamic>('paired') ?? [];
    return rows.map((r) => Map<String, String>.from(r as Map)).toList();
  }

  Future<void> connect(String id) =>
      _channel.invokeMethod('connect', {'id': id});
  Future<List<Map<String, String>>> discover() async {
    final rows = await _channel.invokeListMethod<dynamic>('discover') ?? [];
    return rows.map((r) => Map<String, String>.from(r as Map)).toList();
  }

  Future<void> stopDiscovery() => _channel.invokeMethod('stopDiscovery');
  Future<void> discoverable() => _channel.invokeMethod('discoverable');
  Future<void> approve(String id, bool accepted) =>
      _channel.invokeMethod('approve', {'id': id, 'accepted': accepted});
  Future<void> send(String id, Uint8List bytes) =>
      _channel.invokeMethod('send', {'id': id, 'bytes': bytes});
  Future<void> disconnect(String id) =>
      _channel.invokeMethod('disconnect', {'id': id});
  Future<void> settings() => _channel.invokeMethod('settings');
  Future<void> stop() async {
    _generation++;
    running = false;
    try {
      await _channel.invokeMethod<void>('stop');
    } catch (_) {}
    running = false;
  }
}
