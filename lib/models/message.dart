enum MessageKind { text, image, video, voice, location }

/// pending = ค้างส่ง, sent = ส่งถึงอุปกรณ์, synced = ซิงก์ Cloud สำเร็จ,
/// error = ส่งไม่สำเร็จแต่ยังเก็บอยู่ใน Local DB เพื่อให้ลองใหม่.
enum DeliveryStatus { pending, sent, synced, error }

class Message {
  Message({
    required this.id,
    required this.senderId,
    required this.senderName,
    required this.kind,
    required this.createdAt,
    this.text,
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

  final String id;
  final String senderId;
  final String senderName;
  final MessageKind kind;
  final DateTime createdAt;
  final String? text;
  final String? mediaPath;
  final int? durationSeconds;
  final double? lat;
  final double? lon;
  final double? accuracy;
  DeliveryStatus status;
  int ttl;
  int hops;
  bool isMine;

  Map<String, dynamic> toJson() => {
        'id': id,
        'senderId': senderId,
        'senderName': senderName,
        'kind': kind.name,
        'createdAt': createdAt.toIso8601String(),
        'text': text,
        'durationSeconds': durationSeconds,
        'lat': lat,
        'lon': lon,
        'accuracy': accuracy,
        'status': status.name,
        'ttl': ttl,
        'hops': hops,
      };
}
