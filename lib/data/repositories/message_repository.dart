import 'package:sembast/sembast.dart';
import 'package:uuid/uuid.dart';

import '../../models/user.dart';
import '../local/local_database.dart';
import '../models/local_message_record.dart';
import 'sync_queue_repository.dart';

class MessageRepository {
  final LocalDatabase _local = LocalDatabase.instance;
  final SyncQueueRepository _queue = SyncQueueRepository();

  Future<String> conversationIdFor(AppUser user) {
    return _local.conversationIdFor(user.id);
  }

  Stream<List<LocalMessageRecord>> watchForUser(String ownerLocalId) async* {
    final db = await _local.database;

    final query = _local.messageStore.query(
      finder: Finder(
        filter: Filter.and([
          Filter.equals('owner_local_id', ownerLocalId),
          Filter.equals('is_deleted', false),
        ]),
        sortOrders: [SortOrder('created_at')],
      ),
    );

    yield* query
        .onSnapshots(db)
        .map(
          (snapshots) => snapshots
              .map(
                (snapshot) => LocalMessageRecord.fromLocalMap(
                  Map<String, Object?>.from(snapshot.value),
                ),
              )
              .toList(),
        );
  }

  Future<LocalMessageRecord> create({
    required AppUser user,
    required String content,
  }) async {
    final db = await _local.database;
    final now = DateTime.now();
    final conversationId = await conversationIdFor(user);

    final record = LocalMessageRecord(
      id: const Uuid().v4(),
      ownerLocalId: user.id,
      senderUserId: user.isMember ? user.id : null,
      conversationId: conversationId,
      senderName: user.fullName,
      content: content.trim(),
      createdAt: now,
      updatedAt: now,
      syncState: 'pending',
    );

    await _local.messageStore.record(record.id).put(db, record.toLocalMap());

    if (user.isMember) {
      await _queue.enqueue(
        entityType: 'message',
        entityId: record.id,
        ownerLocalId: record.ownerLocalId,
        operation: 'insert',
      );
    }

    return record;
  }

  Future<void> updateText(LocalMessageRecord record, String content) async {
    final db = await _local.database;

    final updated = record.copyWith(
      content: content.trim(),
      syncState: 'pending',
      clearLastError: true,
      updatedAt: DateTime.now(),
    );

    await _local.messageStore.record(record.id).put(db, updated.toLocalMap());

    if (record.senderUserId != null) {
      await _queue.enqueue(
        entityType: 'message',
        entityId: record.id,
        ownerLocalId: record.ownerLocalId,
        operation: 'update',
      );
    }
  }

  Future<void> delete(LocalMessageRecord record) async {
    final db = await _local.database;

    final updated = record.copyWith(
      isDeleted: true,
      syncState: 'pending',
      clearLastError: true,
      updatedAt: DateTime.now(),
    );

    await _local.messageStore.record(record.id).put(db, updated.toLocalMap());

    if (record.senderUserId != null) {
      await _queue.enqueue(
        entityType: 'message',
        entityId: record.id,
        ownerLocalId: record.ownerLocalId,
        operation: 'delete',
      );
    }
  }

  Future<LocalMessageRecord?> findById(String id) async {
    final db = await _local.database;
    final map = await _local.messageStore.record(id).get(db);

    if (map == null) return null;

    return LocalMessageRecord.fromLocalMap(Map<String, Object?>.from(map));
  }

  Future<void> markSynced(String id) async {
    final record = await findById(id);
    if (record == null) return;

    final db = await _local.database;

    if (record.isDeleted) {
      await _local.messageStore.record(id).delete(db);
      return;
    }

    await _local.messageStore
        .record(id)
        .put(
          db,
          record
              .copyWith(syncState: 'synced', clearLastError: true)
              .toLocalMap(),
        );
  }

  Future<void> markError(String id, Object error) async {
    final record = await findById(id);
    if (record == null) return;

    final db = await _local.database;

    await _local.messageStore
        .record(id)
        .put(
          db,
          record
              .copyWith(syncState: 'error', lastError: error.toString())
              .toLocalMap(),
        );
  }

  Future<void> retry(String id) async {
    final record = await findById(id);
    if (record == null || record.senderUserId == null) return;

    final db = await _local.database;

    await _local.messageStore
        .record(id)
        .put(
          db,
          record
              .copyWith(syncState: 'pending', clearLastError: true)
              .toLocalMap(),
        );

    await _queue.enqueue(
      entityType: 'message',
      entityId: id,
      ownerLocalId: record.ownerLocalId,
      operation: record.isDeleted ? 'delete' : 'update',
    );
  }
}
