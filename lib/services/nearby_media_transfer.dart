import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import '../data/repositories/nearby_chat_repository.dart';
import 'nearby_media_files.dart';

typedef _MediaRequest = ({String id, Future<Map?> reply});

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

/// A bounded four-chunk window shares the paired transport (Nearby or RFCOMM).
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
  final _waiting =
      <String, ({String peer, String? messageId, Completer<Map?> result})>{};
  final _incoming = <String, Map<String, dynamic>>{};
  final _incomingOffsets = <String, int>{};
  // At most four transfers, each holding at most four 12 KB chunks.
  final _aheadChunks =
      <String, Map<int, ({Uint8List bytes, Map<String, dynamic> reply})>>{};
  final _busyPeers = <String>{};

  void _forgetIncoming(String key) {
    _incoming.remove(key);
    _incomingOffsets.remove(key);
    _aheadChunks.remove(key);
  }

  int _generation = 0;

  void disconnected(String peer) {
    for (final pending in _waiting.values.where((p) => p.peer == peer)) {
      if (!pending.result.isCompleted) pending.result.complete(null);
    }
    for (final key
        in _incoming.keys.where((k) => k.startsWith('$peer:')).toList()) {
      _forgetIncoming(key);
    }
    progress.removeWhere((_, p) => p.peer == peer && p.incoming);
  }

  final _activeMessages = <String>{};
  final _cancelledMessages = <String>{};
  void cancelMessage(String id) {
    if (_activeMessages.contains(id)) _cancelledMessages.add(id);
    for (final pending in _waiting.values.where((p) => p.messageId == id)) {
      if (!pending.result.isCompleted) pending.result.complete(null);
    }
    progress.remove(id);
    changed();
  }

  void cancelIncoming(String peer, String id) {
    _forgetIncoming('$peer:$id');
    final transfer = progress[id];
    if (transfer != null && transfer.incoming && transfer.peer == peer) {
      progress.remove(id);
      changed();
    }
  }

  void cancel() {
    _generation++;
    for (final pending in _waiting.values) {
      if (!pending.result.isCompleted) pending.result.complete(null);
    }
    _waiting.clear();
    _incoming.clear();
    _incomingOffsets.clear();
    _aheadChunks.clear();
    progress.clear();
  }

  Future<_MediaRequest> _beginRequest(
    String peer,
    String kind,
    Map<String, dynamic> body,
  ) async {
    final request = makeFrame(kind, {...body, 'target': peer});
    final id = request['id'] as String;
    final result = Completer<Map?>();
    final message = body['message'];
    final messageId =
        body['messageId'] ?? (message is Map ? message['id'] : null);
    _waiting[id] = (
      peer: peer,
      messageId: messageId as String?,
      result: result,
    );
    try {
      await sendFrame(peer, request);
      return (id: id, reply: result.future);
    } catch (_) {
      _waiting.remove(id);
      rethrow;
    }
  }

  Future<Map> _finishRequest(_MediaRequest request) async {
    try {
      final reply = await request.reply.timeout(timeout);
      if (reply == null || reply['error'] != null) {
        throw StateError('รอเชื่อมต่อเพื่อส่งไฟล์ต่อ');
      }
      return reply;
    } finally {
      _waiting.remove(request.id);
    }
  }

  Future<Map> _request(
    String peer,
    String kind,
    Map<String, dynamic> body,
  ) async => _finishRequest(await _beginRequest(peer, kind, body));

  Future<bool> send(String target, Map<String, dynamic> envelope) async {
    final who = owner();
    if (who == null) return false;
    final busyKey = '$who:$target';
    if (!_busyPeers.add(busyKey)) return false;
    final epoch = _generation;
    final id = envelope['id'] as String;
    _activeMessages.add(id);
    final body = envelope['data'] as Map;
    var offset = 0;
    StreamIterator<Uint8List>? reader;
    final pendingRequests = <String>{};
    final size = body['size'] as int;
    bool current() =>
        epoch == _generation &&
        owner() == who &&
        !_cancelledMessages.contains(id);
    try {
      final row = await chats.find(who, id);
      if (row?['historical'] == true) return false;
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
      reader = StreamIterator(files.chunks(path, offset));
      while (offset < size) {
        final window = <({int end, _MediaRequest request})>[];
        var cursor = offset;
        // Dispatch in order, with at most four chunks awaiting ACKs. SOS/control
        // still has priority in RadioSendQueue, including between these frames.
        for (var i = 0; i < 4 && cursor < size; i++) {
          if (!current()) return false;
          if (!await reader.moveNext()) throw StateError('อ่านไฟล์ไม่ครบ');
          final bytes = reader.current;
          if (bytes.isEmpty || cursor + bytes.length > size) {
            throw StateError('ขนาดไฟล์ไม่ตรง');
          }
          final request = await _beginRequest(target, 'media_chunk', {
            'messageId': id,
            'offset': cursor,
            'bytes': base64Encode(bytes),
          });
          pendingRequests.add(request.id);
          cursor += bytes.length;
          window.add((end: cursor, request: request));
        }
        final responses = await Future.wait(
          window.map((part) => _finishRequest(part.request)),
        );
        if (!current()) return false;
        for (var i = 0; i < window.length; i++) {
          pendingRequests.remove(window[i].request.id);
          final next = responses[i]['offset'];
          if (next is! int || next != window[i].end || next > size) {
            throw StateError('ยืนยันส่วนไฟล์ไม่ถูกต้อง');
          }
          offset = next;
        }
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
      await reader?.cancel();
      for (final request in pendingRequests) {
        _waiting.remove(request);
      }
      _busyPeers.remove(busyKey);
      _activeMessages.remove(id);
      _cancelledMessages.remove(id);
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
        _incomingOffsets[key] = offset;
        _aheadChunks.remove(key);
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
          final position = body['offset'] as int;
          final expected = _incomingOffsets[key]!;
          if (position + bytes.length > (meta['size'] as int)) return;
          if (position > expected) {
            final ahead = _aheadChunks.putIfAbsent(key, () => {});
            if (position > expected + 4 * NearbyMediaFiles.chunkBytes ||
                (!ahead.containsKey(position) && ahead.length >= 4)) {
              throw StateError('ส่วนไฟล์เกินคิวรับ');
            }
            ahead[position] = (bytes: bytes, reply: reply);
            // Do not ACK until the gap is filled and bytes are written.
            // Returning lets the serialized receive loop process that gap.
            return;
          }
          final offset = await files.append(
            who,
            origin,
            meta,
            id,
            position,
            bytes,
          );
          if (owner() != who ||
              epoch != _generation ||
              !_incoming.containsKey(key)) {
            return;
          }
          _incomingOffsets[key] = offset;
          reply['offset'] = position + bytes.length;
          await sendFrame(origin, makeFrame('media_reply', reply));
          var next = _aheadChunks[key]?.remove(offset);
          while (next != null) {
            final end = await files.append(
              who,
              origin,
              meta,
              id,
              _incomingOffsets[key]!,
              next.bytes,
            );
            if (owner() != who ||
                epoch != _generation ||
                !_incoming.containsKey(key)) {
              return;
            }
            _incomingOffsets[key] = end;
            next.reply['offset'] = end;
            await sendFrame(origin, makeFrame('media_reply', next.reply));
            next = _aheadChunks[key]?.remove(end);
          }
          progress[id] = MediaProgress(
            origin,
            _incomingOffsets[key]!,
            meta['size'],
            true,
          );
          changed();
          return;
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
          _forgetIncoming(key);
          progress.remove(id);
          // Receipt is based on verified bytes + saved DB row, not the speed
          // of the OS notification channel.
          if (fresh) unawaited(received(message).catchError((_) {}));
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
