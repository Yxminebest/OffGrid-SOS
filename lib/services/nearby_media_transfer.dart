import 'dart:async';
import 'dart:convert';
import '../data/repositories/nearby_chat_repository.dart';
import 'nearby_media_files.dart';

class MediaProgress {
  const MediaProgress(
    this.peer,
    this.bytes,
    this.total,
    this.incoming, {
    this.error,
  });
  final String peer;
  final int bytes, total;
  final bool incoming;
  final String? error;
  double get fraction => total == 0 ? 0 : bytes / total;
}

/// Stop-and-wait chunks share the existing paired transport (Nearby or RFCOMM).
/// A chunk ACK means persisted bytes; a message ACK means hash verified + DB saved.
class NearbyMediaTransfer {
  NearbyMediaTransfer({
    required this.chats,
    required this.files,
    required this.owner,
    required this.device,
    required this.sendFrame,
    required this.makeFrame,
    required this.changed,
    required this.received,
    this.timeout = const Duration(seconds: 20),
  });
  final NearbyChatRepository chats;
  final NearbyMediaFiles files;
  final String? Function() owner;
  final String Function() device;
  final Future<void> Function(String peer, Map<String, dynamic> frame)
  sendFrame;
  final Map<String, dynamic> Function(String kind, Map<String, dynamic> body)
  makeFrame;
  final void Function() changed;
  final Future<void> Function(Map<String, dynamic> envelope) received;
  final Duration timeout;
  final progress = <String, MediaProgress>{};
  final _waiting = <String, ({String peer, Completer<Map?> result})>{};
  final _incoming = <String, Map<String, dynamic>>{};
  final _busyPeers = <String>{};
  int _generation = 0;

  void disconnected(String peer) {
    for (final pending in _waiting.values.where((p) => p.peer == peer)) {
      if (!pending.result.isCompleted) pending.result.complete(null);
    }
    _incoming.removeWhere((_, env) => env['origin'] == peer);
    progress.removeWhere((_, p) => p.peer == peer && p.incoming);
  }

  void cancel() {
    _generation++;
    for (final pending in _waiting.values) {
      if (!pending.result.isCompleted) pending.result.complete(null);
    }
    _waiting.clear();
    _incoming.clear();
    progress.clear();
  }

  Future<Map> _request(
    String peer,
    String kind,
    Map<String, dynamic> body,
  ) async {
    final request = makeFrame(kind, {...body, 'target': peer});
    final id = request['id'] as String;
    final result = Completer<Map?>();
    _waiting[id] = (peer: peer, result: result);
    try {
      await sendFrame(peer, request);
      final reply = await result.future.timeout(timeout);
      if (reply == null || reply['error'] != null) {
        throw StateError('รอเชื่อมต่อเพื่อส่งไฟล์ต่อ');
      }
      return reply;
    } finally {
      _waiting.remove(id);
    }
  }

  Future<bool> send(String target, Map<String, dynamic> envelope) async {
    final who = owner();
    if (who == null) return false;
    final busyKey = '$who:$target';
    if (!_busyPeers.add(busyKey)) return false;
    final epoch = _generation;
    final id = envelope['id'] as String;
    final body = envelope['data'] as Map;
    var offset = 0;
    final size = body['size'] as int;
    bool current() => epoch == _generation && owner() == who;
    try {
      final row = await chats.find(who, id);
      final path = row?['localPath'] as String?;
      if (path == null || !await files.exists(path)) {
        throw StateError('ไม่พบไฟล์ในเครื่อง');
      }
      if (!current()) return false;
      var response = await _request(target, 'media_start', {
        'message': envelope,
      });
      if (!current()) return false;
      offset = response['offset'] as int;
      if (offset < 0 || offset > size) {
        throw StateError('ขนาดไฟล์ตอบกลับไม่ถูกต้อง');
      }
      while (offset < size) {
        if (!current()) return false;
        final bytes = await files.read(path, offset);
        if (bytes.isEmpty) throw StateError('อ่านไฟล์ไม่ครบ');
        response = await _request(target, 'media_chunk', {
          'messageId': id,
          'offset': offset,
          'bytes': base64Encode(bytes),
        });
        if (!current()) return false;
        final next = response['offset'];
        if (next is! int || next != offset + bytes.length || next > size) {
          throw StateError('ยืนยันส่วนไฟล์ไม่ถูกต้อง');
        }
        offset = next;
        progress[id] = MediaProgress(target, offset, size, false);
        changed();
      }
      await chats.markDelivery(who, id, 'sent');
      if (!current()) return false;
      response = await _request(target, 'media_end', {'messageId': id});
      if (!current() || response['done'] != true) return false;
      await chats.acknowledge(who, id, target);
      progress.remove(id);
      changed();
      return true;
    } catch (e) {
      if (current()) {
        progress[id] = MediaProgress(
          target,
          offset,
          size,
          false,
          error: 'ค้างส่ง · จะส่งต่อเมื่อเชื่อมต่ออีกครั้ง',
        );
        changed();
      }
      return false;
    } finally {
      _busyPeers.remove(busyKey);
    }
  }

  bool _valid(Map env, String origin) {
    final body = env['data'];
    return env['kind'] == 'media' &&
        env['origin'] == origin &&
        env['id'] is String &&
        RegExp(r'^[A-Za-z0-9_-]{1,128}$').hasMatch(env['id']) &&
        body is Map &&
        body['target'] == device() &&
        (body['type'] == 'image' || body['type'] == 'video') &&
        body['size'] is int &&
        body['size'] > 0 &&
        body['size'] <= NearbyMediaFiles.maxBytes &&
        body['sha256'] is String &&
        RegExp(r'^[a-f0-9]{64}$').hasMatch(body['sha256']) &&
        body['name'] is String &&
        (body['name'] as String).length <= 180;
  }

  /// Caller must authenticate origin against the currently paired endpoint.
  Future<void> handle(String origin, Map<String, dynamic> frame) async {
    final who = owner();
    final epoch = _generation;
    final body = frame['data'] as Map;
    if (who == null || body['target'] != device()) return;
    if (frame['kind'] == 'media_reply') {
      final waiting = _waiting[body['replyTo']];
      if (waiting != null &&
          waiting.peer == origin &&
          !waiting.result.isCompleted) {
        waiting.result.complete(body);
      }
      return;
    }
    final reply = <String, dynamic>{'replyTo': frame['id'], 'target': origin};
    try {
      final start = frame['kind'] == 'media_start';
      final env = start && body['message'] is Map
          ? Map<String, dynamic>.from(body['message'] as Map)
          : null;
      final id = start ? (env == null ? null : env['id']) : body['messageId'];
      if (id is! String) return;
      final key = '$origin:$id';
      if (start) {
        if (env == null || !_valid(env, origin)) return;
        if (!_incoming.containsKey(key) && _incoming.length >= 4) {
          throw StateError('กำลังรับไฟล์อื่น');
        }
        final saved = await chats.find(who, id);
        if (saved != null &&
            (saved['incoming'] != true ||
                saved['peer'] != origin ||
                ((saved['envelope'] as Map)['data'] as Map)['sha256'] !=
                    (env['data'] as Map)['sha256'])) {
          return;
        }
        _incoming[key] = env;
        final complete =
            saved?['incoming'] == true &&
            saved?['localPath'] is String &&
            await files.exists(saved!['localPath'] as String);
        final offset = complete
            ? (env['data'] as Map)['size'] as int
            : await files.begin(who, origin, env['data'] as Map, id);
        reply['offset'] = offset;
        progress[id] = MediaProgress(
          origin,
          offset,
          (env['data'] as Map)['size'],
          true,
        );
      } else {
        final message = _incoming[key];
        if (message == null) throw StateError('กรุณาเริ่มส่งไฟล์ใหม่');
        final meta = message['data'] as Map;
        if (frame['kind'] == 'media_chunk') {
          final encoded = body['bytes'];
          if (encoded is! String ||
              encoded.length > 16384 ||
              body['offset'] is! int ||
              body['offset'] < 0) {
            return;
          }
          final bytes = base64Decode(encoded);
          if (bytes.isEmpty || bytes.length > NearbyMediaFiles.chunkBytes) {
            return;
          }
          final offset = await files.append(
            who,
            origin,
            meta,
            id,
            body['offset'],
            bytes,
          );
          reply['offset'] = offset;
          progress[id] = MediaProgress(origin, offset, meta['size'], true);
        } else if (frame['kind'] == 'media_end') {
          final saved = await chats.find(who, id);
          final exists =
              saved?['incoming'] == true &&
              saved?['localPath'] is String &&
              await files.exists(saved!['localPath'] as String);
          final path = exists
              ? saved['localPath'] as String
              : await files.finish(who, origin, meta, id);
          if (owner() != who || epoch != _generation) return;
          final fresh = await chats.save(
            who,
            origin,
            message,
            incoming: true,
            delivery: 'delivered',
            localPath: path,
          );
          if (owner() != who || epoch != _generation) return;
          reply['done'] = true;
          _incoming.remove(key);
          progress.remove(id);
          if (fresh) await received(message);
        } else {
          return;
        }
      }
    } catch (_) {
      reply['error'] = 'รับไฟล์ไม่สำเร็จ จะลองใหม่เมื่อเชื่อมต่อ';
    }
    if (owner() != who || epoch != _generation) return;
    changed();
    await sendFrame(origin, makeFrame('media_reply', reply));
  }
}
