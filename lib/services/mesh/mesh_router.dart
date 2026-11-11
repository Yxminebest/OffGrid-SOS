import 'dart:async';
import '../../models/mesh_packet.dart';
import 'mesh_transport.dart';
import 'mesh_dedup_cache.dart';
import 'mesh_router_store.dart';

/// Flooding relay กลาง: การเข้ารหัส/ตรวจลายเซ็นอยู่ที่ validate ของแอป
/// เก็บ packet เดิมไว้ จึง retry/forward โดยไม่เปลี่ยน UUID หรือเวลาส่ง
class MeshRouter {
  MeshRouter({
    required this.nodeId,
    required this.transport,
    required this.store,
    required this.onDeliver,
    this.validate,
    MeshDedupCache? dedup,
    DateTime Function()? now,
    this.maxStored = 1024,
    this.retention = const Duration(hours: 24),
    this.retryInterval = const Duration(seconds: 5),
  }) : dedup = dedup ?? MeshDedupCache(),
       now = now ?? DateTime.now {
    if (nodeId.isEmpty || maxStored < 1 || retention <= Duration.zero) {
      throw ArgumentError('Invalid router limits');
    }
  }
  final String nodeId;
  final MeshTransport transport;
  final MeshRouterStore store;
  final MeshDedupCache dedup;
  final DateTime Function() now;
  final int maxStored;
  final Duration retention, retryInterval;
  final Future<void> Function(MeshPacket) onDeliver;
  final Future<bool> Function(MeshPacket)? validate;
  final _records = <String, Map<String, dynamic>>{};
  final _errors = StreamController<Object>.broadcast();
  Stream<Object> get errors => _errors.stream;
  StreamSubscription<MeshReception>? _messages;
  StreamSubscription<Set<String>>? _peers;
  Timer? _retry;
  Future<void> _work = Future.value();
  bool _started = false, _closed = false;
  int get storedCount => _records.length;

  Future<void> _serial(Future<void> Function() action) {
    final result = _work.then((_) async {
      if (!_closed) await action();
    });
    _work = result.catchError((Object e) {
      if (!_errors.isClosed) _errors.add(e);
    });
    return result;
  }

  Future<void> get idle => _work;

  Future<void> start() => _serial(() async {
    if (_started) return;
    for (final record in await store.load()) {
      final packet = MeshPacket.fromJson(
        Map<String, dynamic>.from(record['message'] as Map),
      );
      _records[packet.id] = record;
    }
    await _prune();
    _started = true;
    _messages = transport.onMessage.listen((event) {
      unawaited(receive(event.peerId, event.message).catchError((Object _) {}));
    });
    _peers = transport.onPeerChanged.listen((_) {
      unawaited(flush().catchError((Object _) {}));
    });
    if (retryInterval > Duration.zero) {
      _retry = Timer.periodic(
        retryInterval,
        (_) => unawaited(flush().catchError((Object _) {})),
      );
    }
    await _flush();
  });

  Future<void> send(MeshPacket message) => _serial(() async {
    if (!_started) throw StateError('Start router before sending');
    if (message.senderId != nodeId) throw ArgumentError('Wrong sender');
    await _accept(null, message);
  });
  Future<void> receive(String from, MeshPacket message) => _serial(() async {
    if (!_started || !transport.peers.contains(from)) return;
    await _accept(from, message);
  });

  Future<void> _accept(String? from, MeshPacket message) async {
    // TTL=0 ทิ้งก่อนส่งให้ UI; ไม่เติม TTL เมื่อ retry หรือมี peer ใหม่
    if (message.ttl == 0) return;
    await _prune();
    if (_records.containsKey(message.id)) return;
    if (validate != null && !await validate!(message)) return;
    if (dedup.contains(message.id)) return;
    if (_records.length >= maxStored) throw StateError('Mesh queue full');
    final record = <String, dynamic>{
      'message': message.toJson(),
      'from': from,
      'storedAt': now().toUtc().toIso8601String(),
      'delivered': false,
      'sent': <String>[],
    };
    // เก็บก่อนส่งให้ UI/relay เพื่อให้เปิดแอปใหม่แล้วยัง retry packet เดิมได้
    await store.put(message.id, record);
    dedup.remember(message.id);
    _records[message.id] = record;
    await _deliver(record);
    await _forward(record);
  }

  Future<void> _deliver(Map<String, dynamic> record) async {
    final message = MeshPacket.fromJson(
      Map<String, dynamic>.from(record['message'] as Map),
    );
    if (record['delivered'] != true &&
        (message.destinationId == nodeId ||
            message.destinationId == MeshPacket.broadcast)) {
      await onDeliver(message);
      record['delivered'] = true;
      await store.put(message.id, record);
    }
  }

  Future<void> _forward(Map<String, dynamic> record) async {
    final message = MeshPacket.fromJson(
      Map<String, dynamic>.from(record['message'] as Map),
    );
    if (message.destinationId == nodeId || message.ttl <= 1) return;
    final sent = Set<String>.from(record['sent'] as List);
    // ส่งทุก peer ยกเว้นต้นทางและลิงก์ที่ส่งสำเร็จแล้ว โหนดปลายทางไม่ relay ต่อ
    await Future.wait(
      transport.peers
          .where((p) => p != record['from'] && !sent.contains(p))
          .map((peer) async {
            try {
              await transport.send(peer, message.forwarded());
              sent.add(peer);
            } catch (error) {
              if (!_errors.isClosed) _errors.add(error);
              // ส่งล้มเหลวคงคิวไว้ ให้ timer หรือ peer-changed ลองใหม่
            }
          }),
    );
    record['sent'] = sent.toList();
    await store.put(message.id, record);
  }

  Future<void> _prune() async {
    final cutoff = now().subtract(retention);
    for (final entry in _records.entries.toList()) {
      if (!DateTime.parse(entry.value['storedAt'] as String).isAfter(cutoff)) {
        await store.remove(entry.key);
        _records.remove(entry.key);
      }
    }
  }

  Future<void> flush() => _serial(_flush);
  Future<void> _flush() async {
    await _prune();
    for (final record in _records.values.toList()) {
      await _deliver(record);
      await _forward(record);
    }
  }

  Future<void> close() async {
    _closed = true;
    _retry?.cancel();
    await _messages?.cancel();
    await _peers?.cancel();
    await _work;
    await _errors.close();
  }
}
