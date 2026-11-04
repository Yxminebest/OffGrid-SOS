import 'dart:async';
import '../../models/mesh_packet.dart';
import 'mesh_transport.dart';

/// เชื่อม radio เดิมกับ router โดยไม่ให้แกน relay อ้างอิง plugin โดยตรง
class CallbackMeshTransport implements MeshTransport {
  CallbackMeshTransport({
    required this.connectPeer,
    required this.disconnectPeer,
    required this.sendPacket,
  });
  final Future<void> Function(String) connectPeer, disconnectPeer;
  final Future<void> Function(String, MeshPacket) sendPacket;
  final _messages = StreamController<MeshReception>.broadcast(sync: true);
  final _changes = StreamController<Set<String>>.broadcast(sync: true);
  Set<String> _peers = {};
  @override
  Set<String> get peers => Set.unmodifiable(_peers);
  void updatePeers(Iterable<String> peers) {
    _peers = peers.toSet();
    if (!_changes.isClosed) _changes.add(this.peers);
  }

  void accept(String from, MeshPacket message) {
    if (!_messages.isClosed) _messages.add(MeshReception(from, message));
  }

  @override
  Stream<MeshReception> get onMessage => _messages.stream;
  @override
  Stream<Set<String>> get onPeerChanged => _changes.stream;
  @override
  Future<void> connect(String peerId) => connectPeer(peerId);
  @override
  Future<void> disconnect(String peerId) => disconnectPeer(peerId);
  @override
  Future<void> send(String peerId, MeshPacket message) =>
      sendPacket(peerId, message);
  Future<void> close() async {
    await _messages.close();
    await _changes.close();
  }
}
