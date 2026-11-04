import '../../models/mesh_packet.dart';

class MeshReception {
  const MeshReception(this.peerId, this.message);
  final String peerId;
  final MeshPacket message;
}

/// peerId เป็นรหัสลิงก์ ไม่จำเป็นต้องเท่ากับ senderId ซึ่งเป็นรหัสโหนด
abstract interface class MeshTransport {
  Set<String> get peers;
  Stream<MeshReception> get onMessage;
  Stream<Set<String>> get onPeerChanged;
  Future<void> connect(String peerId);
  Future<void> disconnect(String peerId);
  Future<void> send(String peerId, MeshPacket message);
}
