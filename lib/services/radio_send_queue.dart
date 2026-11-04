import 'dart:async';

class _Frame {
  _Frame(this.send, this.priority);
  final Future<void> Function() send;
  final bool priority;
  final result = Completer<void>();
}

/// One in-flight frame per transport endpoint. Control traffic overtakes queued
/// media, never interrupts bytes already being written to a socket.
class RadioSendQueue {
  final _queues = <String, List<_Frame>>{};
  final _active = <String>{};
  Future<void> add(
    String endpoint,
    Future<void> Function() send, {
    bool priority = true,
  }) {
    final queue = _queues.putIfAbsent(endpoint, () => []);
    if (queue.length >= (priority ? 256 : 64)) {
      return Future.error(StateError('คิววิทยุเต็ม จะลองส่งอีกครั้ง'));
    }
    final frame = _Frame(send, priority);
    if (priority) {
      final index = queue.indexWhere((f) => !f.priority);
      queue.insert(index < 0 ? queue.length : index, frame);
    } else {
      queue.add(frame);
    }
    if (_active.add(endpoint)) unawaited(_drain(endpoint));
    return frame.result.future;
  }

  Future<void> _drain(String endpoint) async {
    final queue = _queues[endpoint]!;
    while (queue.isNotEmpty) {
      final frame = queue.removeAt(0);
      try {
        await frame.send();
        frame.result.complete();
      } catch (e, st) {
        frame.result.completeError(e, st);
      }
    }
    _queues.remove(endpoint);
    _active.remove(endpoint);
  }
}
