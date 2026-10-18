class ChatMediaCache {
  ChatMediaCache({String? root});
  static final instance = ChatMediaCache();
  Future<void> deleteOwner(String owner) async {}
  Future<String?> local(String owner, String id) async => null;
  Future<void> put(String owner, String id, List<int> bytes) async {}
  Future<String?> resolve(
    String owner,
    String id,
    Future<String?> Function() url,
  ) async => null;
}
