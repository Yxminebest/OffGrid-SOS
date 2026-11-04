import 'package:sembast/sembast.dart';

import 'database_factory.dart';

class LocalDatabase {
  LocalDatabase._();

  /// Allows repositories to share an isolated database in tests.
  LocalDatabase.withDatabase(Database database) : _database = database;

  static final LocalDatabase instance = LocalDatabase._();

  final StoreRef<String, Map<String, Object?>> sosStore = stringMapStoreFactory
      .store('local_sos');

  final StoreRef<String, Map<String, Object?>> messageStore =
      stringMapStoreFactory.store('local_messages');

  final StoreRef<String, Map<String, Object?>> conversationStore =
      stringMapStoreFactory.store('local_conversations');

  final StoreRef<int, Map<String, Object?>> syncQueueStore = intMapStoreFactory
      .store('sync_queue');

  final StoreRef<String, Map<String, Object?>> metaStore = stringMapStoreFactory
      .store('local_meta');

  Database? _database;
  Future<Database>? _opening;

  Future<Database> get database async {
    if (_database != null) return _database!;
    try {
      return _database = await (_opening ??= openOffgridDatabase());
    } catch (_) {
      _opening = null;
      rethrow;
    }
  }

  Future<void> clearOwnerData(String ownerId) async {
    final db = await database;

    await db.transaction((txn) async {
      final ownerFilter = Finder(
        filter: Filter.equals('owner_local_id', ownerId),
      );

      await sosStore.delete(txn, finder: ownerFilter);
      await messageStore.delete(txn, finder: ownerFilter);
      await conversationStore.delete(txn, finder: ownerFilter);
      await syncQueueStore.delete(txn, finder: ownerFilter);

      final nearbyOwner = Finder(filter: Filter.equals('owner', ownerId));
      await stringMapStoreFactory
          .store('unified_contacts')
          .delete(txn, finder: nearbyOwner);
      await stringMapStoreFactory
          .store('range_test_results')
          .delete(txn, finder: nearbyOwner);
      await stringMapStoreFactory
          .store('nearby_messages')
          .delete(txn, finder: nearbyOwner);
      await stringMapStoreFactory
          .store('sos_responses')
          .delete(txn, finder: nearbyOwner);
      await stringMapStoreFactory
          .store('nearby_sos_states')
          .delete(txn, finder: nearbyOwner);
      await stringMapStoreFactory
          .store('nearby_rescue_states')
          .delete(txn, finder: nearbyOwner);
      await metaStore.delete(
        txn,
        finder: Finder(filter: Filter.equals('owner_id', ownerId)),
      );
    });
  }
}
