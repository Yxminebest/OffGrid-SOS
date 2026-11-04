import 'dart:async';
import 'package:offgrid_sos/models/mesh_packet.dart';
import 'package:offgrid_sos/services/mesh/mesh_transport.dart';
import 'package:offgrid_sos/services/mesh/mesh_router.dart';

/// ไม่มี radio หรือ cloud; ควบคุม topology/packet loss ได้อย่างแน่นอนในเทสต์
class FakeNetwork {
  final nodes = <String, FakeTransport>{};
  final frames = <({String from, String to, MeshPacket packet})>[];
  int transmissions = 0;
  FakeTransport node(String id) =>
      nodes.putIfAbsent(id, () => FakeTransport(this, id));
  Future<void> drain(Iterable<MeshRouter> routers) async {
    for (var round = 0; round < 200; round++) {
      await Future.wait(routers.map((r) => r.idle));
      if (frames.isEmpty) return;
      final batch = frames.toList();
      frames.clear();
      for (final frame in batch) {
        if (nodes[frame.from]!.peers.contains(frame.to)) {
          nodes[frame.to]!._messages.add(
            MeshReception(frame.from, frame.packet),
          );
        }
      }
    }
    throw StateError('Possible routing loop');
  }
}

class FakeTransport implements MeshTransport {
  FakeTransport(this.network, this.id);
  final FakeNetwork network;
  final String id;
  final _peers = <String>{};
  final _messages = StreamController<MeshReception>.broadcast(sync: true);
  final _changes = StreamController<Set<String>>.broadcast(sync: true);
  bool failSend = false;
  @override
  Set<String> get peers => Set.unmodifiable(_peers);
  @override
  Stream<MeshReception> get onMessage => _messages.stream;
  @override
  Stream<Set<String>> get onPeerChanged => _changes.stream;
  @override
  Future<void> connect(String peerId) async {
    final other = network.node(peerId);
    _peers.add(peerId);
    other._peers.add(id);
    _changes.add(peers);
    other._changes.add(other.peers);
  }

  @override
  Future<void> disconnect(String peerId) async {
    final other = network.node(peerId);
    _peers.remove(peerId);
    other._peers.remove(id);
    _changes.add(peers);
    other._changes.add(other.peers);
  }

  @override
  Future<void> send(String peerId, MeshPacket message) async {
    if (failSend || !_peers.contains(peerId)) {
      throw StateError('Link unavailable');
    }
    network.transmissions++;
    network.frames.add((from: id, to: peerId, packet: message));
  }

  void inject(String from, MeshPacket packet) =>
      _messages.add(MeshReception(from, packet));
  Future<void> close() async {
    await _messages.close();
    await _changes.close();
  }
}
