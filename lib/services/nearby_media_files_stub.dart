import 'dart:typed_data';

class NearbyMediaFiles {
  NearbyMediaFiles({String? root});
  static const maxBytes = 25 * 1024 * 1024;
  static const chunkBytes = 12 * 1024;
  Never _unsupported() =>
      throw UnsupportedError('ส่งไฟล์ Nearby ได้บน Android');
  Future<Map<String, dynamic>> importFile(
    String owner,
    String id,
    String source,
    String type,
  ) async => _unsupported();
  Future<int> begin(String owner, String peer, Map body, String id) async =>
      _unsupported();
  Future<int> append(
    String owner,
    String peer,
    Map body,
    String id,
    int offset,
    Uint8List bytes,
  ) async => _unsupported();
  Future<String> finish(String owner, String peer, Map body, String id) async =>
      _unsupported();
  Future<Uint8List> read(String path, int offset) async => _unsupported();
  Future<Uint8List> allBytes(String path) async => _unsupported();
  Future<String> restore(
    String owner,
    String id,
    List<int> bytes,
    String type,
  ) async => _unsupported();
  Future<void> deleteOwner(String owner) async {}
  Future<bool> exists(String path) async => false;
}
