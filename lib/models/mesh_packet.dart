import 'dart:convert';
import 'package:uuid/uuid.dart';

/// ข้อมูลกลางของ router; ไม่อ้างอิง Bluetooth, Nearby หรือ Supabase
class MeshPacket {
  MeshPacket({
    required this.id,
    required this.senderId,
    required this.destinationId,
    required Map<String, dynamic> payload,
    required DateTime timestamp,
    this.ttl = 8,
    this.hopCount = 0,
  }) : payload = Map<String, dynamic>.unmodifiable(
         jsonDecode(jsonEncode(payload)) as Map<String, dynamic>,
       ),
       timestamp = timestamp.toUtc() {
    if (!Uuid.isValidUUID(fromString: id) ||
        senderId.isEmpty ||
        senderId.length > 128 ||
        destinationId.isEmpty ||
        destinationId.length > 128 ||
        ttl < 0 ||
        ttl > 32 ||
        hopCount < 0 ||
        hopCount > 32 ||
        ttl + hopCount > 32) {
      throw const FormatException('Invalid mesh packet');
    }
  }
  static const broadcast = '*';
  final String id, senderId, destinationId;
  final Map<String, dynamic> payload;
  final DateTime timestamp;
  final int ttl, hopCount;

  factory MeshPacket.create({
    required String senderId,
    String destinationId = broadcast,
    required Map<String, dynamic> payload,
    DateTime? timestamp,
    int ttl = 8,
  }) => MeshPacket(
    id: const Uuid().v4(),
    senderId: senderId,
    destinationId: destinationId,
    payload: payload,
    timestamp: timestamp ?? DateTime.now(),
    ttl: ttl,
  );

  /// ลด TTL เฉพาะเมื่อข้ามลิงก์ ไม่ลดซ้ำเมื่อเก็บคิวหรือ retry ลิงก์เดิม
  MeshPacket forwarded() => MeshPacket(
    id: id,
    senderId: senderId,
    destinationId: destinationId,
    payload: payload,
    timestamp: timestamp,
    ttl: ttl - 1,
    hopCount: hopCount + 1,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'senderId': senderId,
    'destinationId': destinationId,
    'payload': payload,
    'timestamp': timestamp.toIso8601String(),
    'ttl': ttl,
    'hopCount': hopCount,
  };
  factory MeshPacket.fromJson(Map<String, dynamic> json) => MeshPacket(
    id: json['id'] as String,
    senderId: json['senderId'] as String,
    destinationId: json['destinationId'] as String,
    payload: Map<String, dynamic>.from(json['payload'] as Map),
    timestamp: DateTime.parse(json['timestamp'] as String),
    ttl: json['ttl'] as int,
    hopCount: json['hopCount'] as int,
  );

  /// adapter สำหรับ envelope เดิม เพื่อไม่สร้างโปรโตคอลแชทขึ้นมาซ้ำอีกชุด
  factory MeshPacket.fromEnvelope(Map<String, dynamic> env) => MeshPacket(
    id: env['id'] as String,
    senderId: env['origin'] as String,
    destinationId: MeshPacket.broadcast,
    payload: env,
    timestamp: DateTime.parse(env['at'] as String),
    ttl: env['ttl'] as int,
    hopCount: env['hopCount'] as int? ?? 0,
  );
  Map<String, dynamic> toEnvelope() => {
    ...payload,
    'ttl': ttl,
    'hopCount': hopCount,
  };
}
