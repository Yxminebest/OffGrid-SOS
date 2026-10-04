import 'package:sembast/sembast.dart';
import 'package:uuid/uuid.dart';

import '../../models/user.dart';
import '../local/local_database.dart';
import '../models/local_message_record.dart';
import 'sync_queue_repository.dart';

class MessageRepository {
  final LocalDatabase _local = LocalDatabase.instance;
  final SyncQueueRepository _queue = SyncQueueRepository();

  Stream<List<LocalMessageRecord>> watchConversation({
    required String ownerLocalId,
    required String conversationId,
  }) async* {
    final db = await _local.database;
    final query = _local.messageStore.query(
      finder: Finder(
        filter: Filter.and([
          Filter.equals('owner_local_id', ownerLocalId),
          Filter.equals('conversation_id', conversationId),
          Filter.equals('is_deleted', false),
        ]),
        sortOrders: [SortOrder('created_at')],
      ),
    );

    yield* query.onSnapshots(db).map(
          (items) => items
              .map(
                (item) => LocalMessageRecord.fromLocalMap(
                  Map<String, Object?>.from(item.value),
                ),
              )
              .toList(),
        );
  }

  Future<LocalMessageRecord> create({
    required AppUser user,
    required String conversationId,
    String content = '',
    String type = 'text',
    String? replyToId,
    double? latitude,
    double? longitude,
    double? accuracy,
    String? mediaName,
    String? mediaMime,
    List<int>? mediaBytes,
  }) async {
    final db = await _local.database;
    final now = DateTime.now();

    final record = LocalMessageRecord(
      id: const Uuid().v4(),
      ownerLocalId: user.id,
      senderUserId: user.isMember ? user.id : null,
      conversationId: conversationId,
      senderName: user.fullName,
      content: content.trim(),
      messageType: type,
      replyToId: replyToId,
      latitude: latitude,
      longitude: longitude,
      accuracy: accuracy,
      mediaName: mediaName,
      mediaMime: mediaMime,
      mediaSize: mediaBytes?.length,
      mediaBytes: mediaBytes,
      createdAt: now,
      updatedAt: now,
      syncState: user.isMember ? 'pending' : 'synced',
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
    final now = DateTime.now();
    final updated = record.copyWith(
      content: content.trim(),
      syncState: 'pending',
      clearLastError: true,
      editedAt: now,
      updatedAt: now,
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

  Future<void> upsertFromCloud({
    required String ownerLocalId,
    required Map<String, dynamic> cloud,
    required String senderName,
  }) async {
    final db = await _local.database;
    final id = cloud['id'].toString();
    final existing = await findById(id);

    // Never overwrite an unsynced local edit with an older cloud snapshot.
    if (existing != null && existing.syncState != 'synced') return;

    if (cloud['is_deleted'] == true) {
      await _local.messageStore.record(id).delete(db);
      return;
    }

    final record = LocalMessageRecord.fromCloudMap(
      map: cloud,
      ownerLocalId: ownerLocalId,
      senderName: senderName,
    );
    await _local.messageStore.record(id).put(db, record.toLocalMap());
  }

  Future<void> reconcileCloud({
    required String ownerLocalId,
    required String conversationId,
    required List<Map<String, dynamic>> cloudRows,
    required String currentUserId,
    required String currentUserName,
    required String peerName,
  }) async {
    final cloudIds = <String>{};
    for (final row in cloudRows) {
      cloudIds.add(row['id'].toString());
      final senderId = row['sender_id']?.toString();
      await upsertFromCloud(
        ownerLocalId: ownerLocalId,
        cloud: row,
        senderName: senderId == currentUserId ? currentUserName : peerName,
      );
    }

    final db = await _local.database;
    final local = await _local.messageStore.find(
      db,
      finder: Finder(
        filter: Filter.and([
          Filter.equals('owner_local_id', ownerLocalId),
          Filter.equals('conversation_id', conversationId),
        ]),
      ),
    );

    for (final row in local) {
      final record = LocalMessageRecord.fromLocalMap(
        Map<String, Object?>.from(row.value),
      );
      if (record.syncState == 'synced' && !cloudIds.contains(record.id)) {
        await _local.messageStore.record(record.id).delete(db);
      }
    }
  }

  Future<void> attachUploadedMedia({
    required String id,
    required String mediaPath,
  }) async {
    final record = await findById(id);
    if (record == null) return;
    final db = await _local.database;
    await _local.messageStore.record(id).put(
          db,
          record
              .copyWith(mediaPath: mediaPath, clearMediaBytes: true)
              .toLocalMap(),
        );
  }

  Future<void> markSynced(String id) async {
    final record = await findById(id);
    if (record == null) return;
    final db = await _local.database;

    if (record.isDeleted) {
      await _local.messageStore.record(id).delete(db);
      return;
    }

    await _local.messageStore.record(id).put(
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
    await _local.messageStore.record(id).put(
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
    await _local.messageStore.record(id).put(
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
