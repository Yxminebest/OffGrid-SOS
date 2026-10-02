import 'package:sembast/sembast.dart';

import '../local/local_database.dart';
import '../models/sync_job.dart';

class SyncQueueRepository {
  final LocalDatabase _local = LocalDatabase.instance;

  Future<void> enqueue({
    required String entityType,
    required String entityId,
    required String ownerLocalId,
    required String operation,
  }) async {
    final db = await _local.database;

    final existing = await _local.syncQueueStore.findFirst(
      db,
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
        db,
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
        .update(db, <String, Object?>{
          'operation': effectiveOperation,
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

  Future<void> complete(int id) async {
    final db = await _local.database;
    await _local.syncQueueStore.record(id).delete(db);
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

    await _local.syncQueueStore.record(job.id!).update(db, <String, Object?>{
      'retry_count': retry,
      'last_error': error.toString(),
      'next_retry_at': now
          .add(Duration(seconds: seconds))
          .toUtc()
          .toIso8601String(),
      'updated_at': now.toUtc().toIso8601String(),
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
