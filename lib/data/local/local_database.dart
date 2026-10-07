import 'package:sembast/sembast.dart';
import 'package:uuid/uuid.dart';

import 'database_factory.dart';

class LocalDatabase {
  LocalDatabase._();

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

  Future<Database> get database async {
    return _database ??= await openOffgridDatabase();
  }

  Future<String> conversationIdFor(String ownerId) async {
    final db = await database;
    final key = 'week3_demo_conversation_$ownerId';
    final existing = await metaStore.record(key).get(db);

    final currentId = existing?['conversation_id']?.toString();

    if (currentId != null && currentId.isNotEmpty) {
      return currentId;
    }

    final id = const Uuid().v4();

    await metaStore.record(key).put(db, <String, Object?>{
      'conversation_id': id,
      'owner_id': ownerId,
      'created_at': DateTime.now().toUtc().toIso8601String(),
    });

    return id;
  }

  Future<int> pendingSyncCount() async {
    final db = await database;
    return syncQueueStore.count(db);
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

      await metaStore.delete(
        txn,
        finder: Finder(filter: Filter.equals('owner_id', ownerId)),
      );
    });
  }

  Future<void> clearWeek3DemoData() async {
    final db = await database;

    await db.transaction((txn) async {
      await sosStore.drop(txn);
      await messageStore.drop(txn);
      await conversationStore.drop(txn);
      await syncQueueStore.drop(txn);
    });
  }
}
