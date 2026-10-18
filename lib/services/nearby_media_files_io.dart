import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Private application files, never remote filenames or paths. Bytes stay off DB.
class NearbyMediaFiles {
  NearbyMediaFiles({this.root});
  final String? root;
  static const maxBytes = 25 * 1024 * 1024;
  static const chunkBytes = 12 * 1024;

  Future<File> _file(String owner, String key, String suffix) async {
    final base =
        root ??
        p.join((await getApplicationSupportDirectory()).path, 'nearby_media');
    final directory = Directory(
      p.join(base, sha256.convert(utf8.encode(owner)).toString()),
    );
    await directory.create(recursive: true);
    return File(
      p.join(directory.path, '${sha256.convert(utf8.encode(key))}$suffix'),
    );
  }

  Future<Map<String, dynamic>> importFile(
    String owner,
    String id,
    String source,
    String type,
  ) async {
    final input = File(source);
    final size = await input.length();
    if (size <= 0 || size > maxBytes) {
      throw StateError('ไฟล์ต้องมีขนาด 1 byte ถึง 25 MB');
    }
    final output = await _file(
      owner,
      'out:$id',
      type == 'image' ? '.jpg' : '.mp4',
    );
    await input.copy('${output.path}.tmp');
    final saved = await File('${output.path}.tmp').rename(output.path);
    return {
      'path': saved.path,
      'size': size,
      'sha256': (await sha256.bind(saved.openRead()).first).toString(),
    };
  }

  Future<File> _partial(String owner, String peer, Map body, String id) =>
      _file(owner, 'in:$peer:$id:${body['sha256']}', '.part');

  Future<int> begin(String owner, String peer, Map body, String id) async {
    final partial = await _partial(owner, peer, body, id);
    if (!await partial.exists()) await partial.create();
    final size = await partial.length();
    if (size > (body['size'] as int)) {
      await partial.writeAsBytes([], flush: true);
      return 0;
    }
    return size;
  }

  Future<int> append(
    String owner,
    String peer,
    Map body,
    String id,
    int offset,
    Uint8List bytes,
  ) async {
    final partial = await _partial(owner, peer, body, id);
    final length = await partial.length();
    if (offset < length) {
      return length; // Lost acknowledgment: don't append twice.
    }
    if (offset != length || length + bytes.length > (body['size'] as int)) {
      throw StateError('ลำดับส่วนไฟล์ไม่ถูกต้อง');
    }
    await partial.writeAsBytes(bytes, mode: FileMode.append, flush: true);
    return length + bytes.length;
  }

  Future<String> finish(String owner, String peer, Map body, String id) async {
    final partial = await _partial(owner, peer, body, id);
    if (await partial.length() != body['size']) {
      throw StateError('ไฟล์ยังรับไม่ครบ');
    }
    final hash = (await sha256.bind(partial.openRead()).first).toString();
    if (hash != body['sha256']) {
      await partial.delete();
      throw StateError('ไฟล์เสียหาย กำลังรอส่งใหม่');
    }
    final output = await _file(
      owner,
      'in:$peer:$id:${body['sha256']}',
      body['type'] == 'image' ? '.jpg' : '.mp4',
    );
    await partial.rename(output.path);
    return output.path;
  }

  Future<Uint8List> read(String path, int offset) async {
    final file = await File(path).open();
    try {
      await file.setPosition(offset);
      return await file.read(chunkBytes);
    } finally {
      await file.close();
    }
  }

  Future<Uint8List> allBytes(String path) async {
    if (await File(path).length() > maxBytes) {
      throw StateError('File too large');
    }
    return File(path).readAsBytes();
  }

  Future<String> restore(
    String owner,
    String id,
    List<int> bytes,
    String type,
  ) async {
    if (bytes.isEmpty || bytes.length > maxBytes) {
      throw StateError('Invalid media');
    }
    final file = await _file(
      owner,
      'archive:$id',
      type == 'image' ? '.jpg' : '.mp4',
    );
    await file.writeAsBytes(bytes, flush: true);
    return file.path;
  }

  Future<void> deleteOwner(String owner) async {
    final base =
        root ??
        p.join((await getApplicationSupportDirectory()).path, 'nearby_media');
    final directory = Directory(
      p.join(base, sha256.convert(utf8.encode(owner)).toString()),
    );
    if (await directory.exists()) await directory.delete(recursive: true);
  }

  Future<bool> exists(String path) => File(path).exists();
}
