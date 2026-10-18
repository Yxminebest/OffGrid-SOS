import 'package:sembast/sembast.dart';
import 'package:uuid/uuid.dart';

import '../../models/user.dart';
import '../local/local_database.dart';
import '../models/local_message_record.dart';
import 'sync_queue_repository.dart';

class MessageRepository {
  MessageRepository({LocalDatabase? local})
    : _local = local ?? LocalDatabase.instance,
      _queue = SyncQueueRepository(local: local);

  final LocalDatabase _local;
  final SyncQueueRepository _queue;

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

    yield* query
        .onSnapshots(db)
        .map(
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
    String? messageId,
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
      id: messageId ?? const Uuid().v4(),
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

    return db.transaction((txn) async {
      final old = await _local.messageStore.record(record.id).get(txn);
      if (old != null) {
        final existing = LocalMessageRecord.fromLocalMap(old);
        if (existing.ownerLocalId != user.id ||
            existing.conversationId != conversationId) {
          throw StateError('Message destination mismatch');
        }
        return existing;
      }
      await _save(txn, record, 'insert');
      return record;
    });
  }

  Future<void> updateText(LocalMessageRecord record, String content) async {
    final now = DateTime.now();
    await _mutate(
      record.id,
      (current) => current.copyWith(
        content: content.trim(),
        syncState: 'pending',
        clearLastError: true,
        editedAt: now,
        updatedAt: now,
      ),
    );
  }

  Future<void> delete(LocalMessageRecord record) async {
    await _mutate(
      record.id,
      (current) => current.copyWith(
        isDeleted: true,
        syncState: 'pending',
        clearLastError: true,
        updatedAt: DateTime.now(),
      ),
    );
  }

  Future<void> _save(
    Transaction txn,
    LocalMessageRecord record,
    String operation,
  ) async {
    await _local.messageStore.record(record.id).put(txn, record.toLocalMap());
    if (record.senderUserId != null) {
      await _queue.enqueue(
        entityType: 'message',
        entityId: record.id,
        ownerLocalId: record.ownerLocalId,
        operation: record.isDeleted ? 'delete' : operation,
        transaction: txn,
      );
    }
  }

  Future<void> _mutate(
    String id,
    LocalMessageRecord Function(LocalMessageRecord) change,
  ) async {
    final db = await _local.database;
    await db.transaction((txn) async {
      final value = await _local.messageStore.record(id).get(txn);
      if (value == null) return;
      await _save(
        txn,
        change(LocalMessageRecord.fromLocalMap(value)),
        'update',
      );
    });
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
    await db.transaction((txn) async {
      final ref = _local.messageStore.record(id);
      final existing = await ref.get(txn);
      // Check and write atomically with respect to local edits and uploads.
      if (existing != null && existing['sync_state'] != 'synced') return;
      if (cloud['is_deleted'] == true) {
        await ref.delete(txn);
        return;
      }
      final record = LocalMessageRecord.fromCloudMap(
        map: cloud,
        ownerLocalId: ownerLocalId,
        senderName: senderName,
      );
      await ref.put(txn, record.toLocalMap());
    });
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
    await db.transaction((txn) async {
      final local = await _local.messageStore.find(
        txn,
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
          await _local.messageStore.record(record.id).delete(txn);
        }
      }
    });
  }

  Future<void> attachUploadedMedia({
    required String id,
    required String mediaPath,
  }) async {
    final db = await _local.database;
    await db.transaction((txn) async {
      // Merge upload metadata into the latest row, retaining edits/deletions.
      await _local.messageStore.record(id).update(txn, {
        'media_path': mediaPath,
        'media_bytes': null,
      });
    });
  }

  Future<void> retry(String id) async {
    await _mutate(
      id,
      (record) => record.copyWith(syncState: 'pending', clearLastError: true),
    );
  }
}
