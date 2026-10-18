import 'package:sembast/sembast.dart';
import 'package:uuid/uuid.dart';

import '../../models/user.dart';
import '../../services/location_service.dart';
import '../local/local_database.dart';
import '../models/local_sos_record.dart';
import 'sync_queue_repository.dart';

class SosRepository {
  SosRepository({LocalDatabase? local})
    : _local = local ?? LocalDatabase.instance,
      _queue = SyncQueueRepository(local: local);

  final LocalDatabase _local;
  final SyncQueueRepository _queue;

  Stream<List<LocalSosRecord>> watchForUser(String ownerLocalId) async* {
    final db = await _local.database;

    final query = _local.sosStore.query(
      finder: Finder(
        filter: Filter.equals('owner_local_id', ownerLocalId),
        sortOrders: [SortOrder('created_at', false)],
      ),
    );

    yield* query
        .onSnapshots(db)
        .map(
          (snapshots) => snapshots
              .map(
                (snapshot) => LocalSosRecord.fromLocalMap(
                  Map<String, Object?>.from(snapshot.value),
                ),
              )
              .toList(),
        );
  }

  Future<LocalSosRecord?> latestActive(String ownerLocalId) async {
    final db = await _local.database;

    final snapshot = await _local.sosStore.findFirst(
      db,
      finder: Finder(
        filter: Filter.and([
          Filter.equals('owner_local_id', ownerLocalId),
          Filter.equals('is_active', true),
        ]),
        sortOrders: [SortOrder('created_at', false)],
      ),
    );

    if (snapshot == null) return null;

    return LocalSosRecord.fromLocalMap(
      Map<String, Object?>.from(snapshot.value),
    );
  }

  Future<LocalSosRecord> create({
    required AppUser user,
    required String message,
    SavedLocation? location,
  }) async {
    final now = DateTime.now();

    final record = LocalSosRecord(
      id: const Uuid().v4(),
      ownerLocalId: user.id,
      ownerUserId: user.isMember ? user.id : null,
      message: message.trim().isEmpty
          ? 'ต้องการความช่วยเหลือฉุกเฉิน'
          : message.trim(),
      latitude: location?.latitude,
      longitude: location?.longitude,
      accuracy: location?.accuracyMeters,
      locationRecordedAt: location?.recordedAt,
      isLastKnownLocation: location?.isLastKnown ?? false,
      createdAt: now,
      updatedAt: now,
      syncState: 'pending',
    );

    final db = await _local.database;
    await db.transaction((txn) => _save(txn, record, 'insert'));

    return record;
  }

  Future<void> updateMessage(LocalSosRecord record, String message) async {
    await _mutate(
      record.id,
      (current) => current.copyWith(
        message: message.trim(),
        syncState: 'pending',
        clearLastError: true,
        updatedAt: DateTime.now(),
      ),
    );
  }

  Future<void> stop(LocalSosRecord record) async {
    final now = DateTime.now();

    await _mutate(
      record.id,
      (current) => current.copyWith(
        isActive: false,
        endedAt: now,
        syncState: 'pending',
        clearLastError: true,
        updatedAt: now,
      ),
    );
  }

  Future<void> _save(
    Transaction txn,
    LocalSosRecord record,
    String operation,
  ) async {
    await _local.sosStore.record(record.id).put(txn, record.toLocalMap());
    if (record.ownerUserId != null) {
      await _queue.enqueue(
        entityType: 'sos',
        entityId: record.id,
        ownerLocalId: record.ownerLocalId,
        operation: operation,
        transaction: txn,
      );
    }
  }

  Future<void> _mutate(
    String id,
    LocalSosRecord Function(LocalSosRecord) change,
  ) async {
    final db = await _local.database;
    await db.transaction((txn) async {
      final value = await _local.sosStore.record(id).get(txn);
      if (value == null) return;
      final current = LocalSosRecord.fromLocalMap(value);
      await _save(
        txn,
        change(current).copyWith(revision: current.revision + 1),
        'update',
      );
    });
  }

  Future<LocalSosRecord?> findById(String id) async {
    final db = await _local.database;
    final map = await _local.sosStore.record(id).get(db);

    if (map == null) return null;

    return LocalSosRecord.fromLocalMap(Map<String, Object?>.from(map));
  }

  Future<List<LocalSosRecord>> recentForUser(String owner) async {
    final db = await _local.database;
    final rows = await _local.sosStore.find(
      db,
      finder: Finder(
        filter: Filter.equals('owner_local_id', owner),
        sortOrders: [SortOrder('updated_at', false)],
        limit: 100,
      ),
    );
    return rows.map((row) => LocalSosRecord.fromLocalMap(row.value)).toList();
  }

  Future<void> retry(String id) async {
    await _mutate(
      id,
      (record) => record.copyWith(syncState: 'pending', clearLastError: true),
    );
  }
}
