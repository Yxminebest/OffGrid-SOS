enum MessageKind { text, image, video, voice, location }

/// pending = ค้างส่ง, sent = ส่งแล้ว, synced = ซิงก์ขึ้นคลาวด์แล้ว
enum DeliveryStatus { pending, sent, synced }

class Message {
  Message({
    required this.id,
    required this.senderId,
    required this.senderName,
    required this.kind,
    required this.createdAt,
    this.text, // ข้อความ หรือ "คำถอดความ" ของเสียง
    this.mediaPath,
    this.durationSeconds,
    this.lat,
    this.lon,
    this.accuracy,
    this.status = DeliveryStatus.pending,
    this.ttl = 5,
    this.hops = 0,
    this.isMine = true,
  });

  final String id; // UUID ใช้กันข้อความซ้ำตอน relay
  final String senderId;
  final String senderName;
  final MessageKind kind;
  final DateTime createdAt;
  final String? text;
  final String? mediaPath;
  final int? durationSeconds;
  final double? lat, lon, accuracy;
  DeliveryStatus status;
  int ttl, hops;
  bool isMine;

  Map<String, dynamic> toJson() => {
        'id': id, 'senderId': senderId, 'senderName': senderName,
        'kind': kind.name, 'createdAt': createdAt.toIso8601String(),
        'text': text, 'durationSeconds': durationSeconds,
        'lat': lat, 'lon': lon, 'accuracy': accuracy,
        'ttl': ttl, 'hops': hops,
      };

  factory Message.fromJson(Map<String, dynamic> j) => Message(
        id: j['id'], senderId: j['senderId'], senderName: j['senderName'],
        kind: MessageKind.values.byName(j['kind']),
        createdAt: DateTime.parse(j['createdAt']),
        text: j['text'], durationSeconds: j['durationSeconds'],
        lat: (j['lat'] as num?)?.toDouble(), lon: (j['lon'] as num?)?.toDouble(),
        accuracy: (j['accuracy'] as num?)?.toDouble(),
        ttl: j['ttl'] ?? 5, hops: j['hops'] ?? 0,
        status: DeliveryStatus.sent, isMine: false,
      );
}
