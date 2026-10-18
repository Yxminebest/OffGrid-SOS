import 'package:flutter/services.dart';

class BluetoothLink {
  static final instance = BluetoothLink();
  static const _channel = MethodChannel('com.offgridsos/bluetooth');
  bool running = false;
  Future<void> Function(String id, String name)? onConnected;
  void Function(String id)? onDisconnected;
  void Function(String id, Uint8List bytes)? onBytes;
  Future<bool> start() async {
    _channel.setMethodCallHandler((call) async {
      if (call.method != 'event') return;
      final args = Map<String, dynamic>.from(call.arguments as Map);
      final id = args['id'] as String;
      switch (args['kind']) {
        case 'connected':
          await onConnected?.call(id, args['name'] as String);
        case 'disconnected':
          onDisconnected?.call(id);
        case 'bytes':
          onBytes?.call(id, args['bytes'] as Uint8List);
      }
    });
    try {
      running = await _channel.invokeMethod<bool>('start') ?? false;
    } catch (_) {
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
  Future<void> send(String id, Uint8List bytes) =>
      _channel.invokeMethod('send', {'id': id, 'bytes': bytes});
  Future<void> disconnect(String id) =>
      _channel.invokeMethod('disconnect', {'id': id});
  Future<void> settings() => _channel.invokeMethod('settings');
  Future<void> stop() async {
    try {
      await _channel.invokeMethod<void>('stop');
    } catch (_) {}
    running = false;
  }
}
