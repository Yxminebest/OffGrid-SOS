import 'package:sembast/sembast.dart';

import '../local/local_database.dart';
import '../models/sync_job.dart';

class SyncQueueRepository {
  SyncQueueRepository({LocalDatabase? local})
    : _local = local ?? LocalDatabase.instance;

  final LocalDatabase _local;

  Future<void> enqueue({
    required String entityType,
    required String entityId,
    required String ownerLocalId,
    required String operation,
    Transaction? transaction,
  }) async {
    if (transaction != null) {
      await _enqueue(
        transaction,
        entityType,
        entityId,
        ownerLocalId,
        operation,
      );
      return;
    }
    final db = await _local.database;
    await db.transaction(
      (txn) => _enqueue(txn, entityType, entityId, ownerLocalId, operation),
    );
  }

  Future<void> _enqueue(
    Transaction txn,
    String entityType,
    String entityId,
    String ownerLocalId,
    String operation,
  ) async {
    final existing = await _local.syncQueueStore.findFirst(
      txn,
      finder: Finder(
        filter: Filter.and([
          Filter.equals('entity_type', entityType),
          Filter.equals('entity_id', entityId),
          Filter.equals('owner_local_id', ownerLocalId),
        ]),
      ),
    );

    final now = DateTime.now();

    if (existing == null) {
      await _local.syncQueueStore.add(
        txn,
        SyncJob(
          entityType: entityType,
          entityId: entityId,
          operation: operation,
          ownerLocalId: ownerLocalId,
          createdAt: now,
          updatedAt: now,
        ).toMap(),
      );
      return;
    }

    final current = SyncJob.fromMap(
      existing.key,
      Map<String, Object?>.from(existing.value),
    );

    final effectiveOperation = operation == 'delete'
        ? 'delete'
        : current.operation == 'insert'
        ? 'insert'
        : operation;

    await _local.syncQueueStore
        .record(existing.key)
        .update(txn, <String, Object?>{
          'operation': effectiveOperation,
          'revision': current.revision + 1,
          'retry_count': 0,
          'last_error': null,
          'next_retry_at': null,
          'updated_at': now.toUtc().toIso8601String(),
        });
  }

  Future<List<SyncJob>> readyJobs(String ownerLocalId) async {
    final db = await _local.database;
    final snapshots = await _local.syncQueueStore.find(
      db,
      finder: Finder(
        filter: Filter.equals('owner_local_id', ownerLocalId),
        sortOrders: [SortOrder('created_at')],
      ),
    );

    final now = DateTime.now();

    return snapshots
        .map(
          (item) =>
              SyncJob.fromMap(item.key, Map<String, Object?>.from(item.value)),
        )
        .where(
          (job) => job.nextRetryAt == null || !job.nextRetryAt!.isAfter(now),
        )
        .toList();
  }

  Future<int> countFor(String ownerLocalId) async {
    final db = await _local.database;
    return _local.syncQueueStore.count(
      db,
      filter: Filter.equals('owner_local_id', ownerLocalId),
    );
  }

  Future<bool> complete(SyncJob job) async {
    if (job.id == null) return false;
    final db = await _local.database;
    return db.transaction((txn) async {
      if (!await _isCurrent(txn, job)) return false;
      final entity = _entityStore(job).record(job.entityId);
      final value = await entity.get(txn);
      if (value != null && value['owner_local_id'] == job.ownerLocalId) {
        if (job.entityType == 'message' && value['is_deleted'] == true) {
          await entity.delete(txn);
        } else {
          await entity.update(txn, {
            'sync_state': 'synced',
            'last_error': null,
          });
        }
      }
      await _local.syncQueueStore.record(job.id!).delete(txn);
      return true;
    });
  }

  StoreRef<String, Map<String, Object?>> _entityStore(SyncJob job) =>
      switch (job.entityType) {
        'sos' => _local.sosStore,
        'message' => _local.messageStore,
        _ => throw StateError('Unknown sync entity: ${job.entityType}'),
      };

  Future<bool> _isCurrent(Transaction txn, SyncJob job) async {
    final current = await _local.syncQueueStore.record(job.id!).get(txn);
    return current != null &&
        current['entity_id'] == job.entityId &&
        current['owner_local_id'] == job.ownerLocalId &&
        ((current['revision'] as num?)?.toInt() ?? 1) == job.revision;
  }

  Future<void> fail(SyncJob job, Object error) async {
    if (job.id == null) return;

    final db = await _local.database;
    final retry = job.retryCount + 1;

    final seconds = switch (retry) {
      <= 1 => 5,
      2 => 15,
      3 => 30,
      4 => 60,
      _ => 300,
    };

    final now = DateTime.now();

    await db.transaction((txn) async {
      // An old failed request must not postpone or mark a newer edit as failed.
      if (!await _isCurrent(txn, job)) return;
      await _local.syncQueueStore.record(job.id!).update(txn, <String, Object?>{
        'retry_count': retry,
        'last_error': error.toString(),
        'next_retry_at': now
            .add(Duration(seconds: seconds))
            .toUtc()
            .toIso8601String(),
        'updated_at': now.toUtc().toIso8601String(),
      });
      final entity = _entityStore(job).record(job.entityId);
      final value = await entity.get(txn);
      if (value != null && value['owner_local_id'] == job.ownerLocalId) {
        await entity.update(txn, {
          'sync_state': 'error',
          'last_error': error.toString(),
        });
      }
    });
  }

  Future<void> retryEverythingNow(String ownerLocalId) async {
    final db = await _local.database;

    await _local.syncQueueStore.update(db, <String, Object?>{
      'next_retry_at': null,
      'last_error': null,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    }, finder: Finder(filter: Filter.equals('owner_local_id', ownerLocalId)));
  }
}
