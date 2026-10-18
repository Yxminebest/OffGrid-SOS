import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Durable account-scoped files. A partial download is never served as complete.
class ChatMediaCache {
  ChatMediaCache({this.root});
  static final instance = ChatMediaCache();
  final String? root;
  final _deletedOwners = <String>{};
  final _active = <String, Future<String?>>{};
  final _writes = <String, Future<void>>{};
  static const maxBytes = 100 * 1024 * 1024;

  Future<void> deleteOwner(String owner) async {
    _deletedOwners.add(owner);
    await Future.wait(
      _active.entries
          .where((e) => e.key.startsWith('$owner:'))
          .map((e) => e.value.catchError((_) => null)),
    );
    await Future.wait(
      _writes.entries
          .where((e) => e.key.startsWith('$owner:'))
          .map((e) => e.value),
    );
    final base =
        root ??
        p.join(
          (await getApplicationSupportDirectory()).path,
          'cloud_chat_media',
        );
    final directory = Directory(
      p.join(base, sha256.convert(utf8.encode(owner)).toString()),
    );
    if (await directory.exists()) await directory.delete(recursive: true);
  }

  Future<File> _file(String owner, String id) async {
    if (_deletedOwners.contains(owner)) throw StateError('Account deleted');
    final base =
        root ??
        p.join(
          (await getApplicationSupportDirectory()).path,
          'cloud_chat_media',
        );
    final directory = Directory(
      p.join(base, sha256.convert(utf8.encode(owner)).toString()),
    );
    await directory.create(recursive: true);
    return File(
      p.join(directory.path, '${sha256.convert(utf8.encode(id))}.media'),
    );
  }

  Future<String?> local(String owner, String id) async {
    final file = await _file(owner, id);
    return await file.exists() ? file.path : null;
  }

  Future<void> put(String owner, String id, List<int> bytes) {
    final key = '$owner:$id';
    return _writes.putIfAbsent(
      key,
      () => _put(owner, id, bytes).whenComplete(() {
        _writes.remove(key);
      }),
    );
  }

  Future<void> _put(String owner, String id, List<int> bytes) async {
    if (bytes.isEmpty || bytes.length > maxBytes) {
      throw StateError('ขนาดไฟล์ไม่ถูกต้อง');
    }
    final file = await _file(owner, id);
    if (await file.exists()) return;
    final temporary = File('${file.path}.save');
    await temporary.writeAsBytes(bytes, flush: true);
    await temporary.rename(file.path);
  }

  Future<String?> resolve(
    String owner,
    String id,
    Future<String?> Function() url,
  ) {
    final key = '$owner:$id';
    return _active.putIfAbsent(
      key,
      () => _download(owner, id, url).whenComplete(() {
        _active.remove(key);
      }),
    );
  }

  Future<String?> _download(
    String owner,
    String id,
    Future<String?> Function() url,
  ) async {
    final existing = await local(owner, id);
    if (existing != null) return existing;
    final signed = await url();
    if (signed == null) return null;
    final uri = Uri.parse(signed);
    if (uri.scheme != 'https' && uri.scheme != 'http') {
      throw StateError('URL ไม่ถูกต้อง');
    }
    final file = await _file(owner, id);
    final temporary = File('${file.path}.download');
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 15);
    IOSink? sink;
    try {
      final response = await (await client.getUrl(
        uri,
      )).close().timeout(const Duration(seconds: 20));
      if (response.statusCode != 200 || response.contentLength > maxBytes) {
        throw StateError('ดาวน์โหลดไฟล์ไม่สำเร็จ');
      }
      sink = temporary.openWrite();
      var total = 0;
      await for (final bytes in response.timeout(const Duration(seconds: 30))) {
        total += bytes.length;
        if (total > maxBytes) throw StateError('ไฟล์ใหญ่เกินกำหนด');
        sink.add(bytes);
        await sink.flush();
      }
      await sink.close();
      sink = null;
      if (total == 0 ||
          (response.contentLength >= 0 && total != response.contentLength)) {
        throw StateError('ไฟล์ไม่ครบ');
      }
      if (!await file.exists()) await temporary.rename(file.path);
      return file.path;
    } finally {
      await sink?.close();
      client.close(force: true);
      if (await temporary.exists()) await temporary.delete();
    }
  }
}
