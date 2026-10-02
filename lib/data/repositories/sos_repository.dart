import 'package:sembast/sembast.dart';
import 'package:uuid/uuid.dart';

import '../../models/user.dart';
import '../../services/location_service.dart';
import '../local/local_database.dart';
import '../models/local_sos_record.dart';
import 'sync_queue_repository.dart';

class SosRepository {
  final LocalDatabase _local = LocalDatabase.instance;
  final SyncQueueRepository _queue = SyncQueueRepository();

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
    final db = await _local.database;
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
      createdAt: now,
      updatedAt: now,
      syncState: user.isMember ? 'pending' : 'pending',
    );

    await _local.sosStore.record(record.id).put(db, record.toLocalMap());

    if (user.isMember) {
      await _queue.enqueue(
        entityType: 'sos',
        entityId: record.id,
        ownerLocalId: record.ownerLocalId,
        operation: 'insert',
      );
    }

    return record;
  }

  Future<void> updateMessage(LocalSosRecord record, String message) async {
    final db = await _local.database;
    final updated = record.copyWith(
      message: message.trim(),
      syncState: record.ownerUserId == null ? 'pending' : 'pending',
      clearLastError: true,
      updatedAt: DateTime.now(),
    );

    await _local.sosStore.record(record.id).put(db, updated.toLocalMap());

    if (record.ownerUserId != null) {
      await _queue.enqueue(
        entityType: 'sos',
        entityId: record.id,
        ownerLocalId: record.ownerLocalId,
        operation: 'update',
      );
    }
  }

  Future<void> stop(LocalSosRecord record) async {
    final db = await _local.database;
    final now = DateTime.now();

    final updated = record.copyWith(
      isActive: false,
      endedAt: now,
      syncState: record.ownerUserId == null ? 'pending' : 'pending',
      clearLastError: true,
      updatedAt: now,
    );

    await _local.sosStore.record(record.id).put(db, updated.toLocalMap());

    if (record.ownerUserId != null) {
      await _queue.enqueue(
        entityType: 'sos',
        entityId: record.id,
        ownerLocalId: record.ownerLocalId,
        operation: 'update',
      );
    }
  }

  Future<LocalSosRecord?> findById(String id) async {
    final db = await _local.database;
    final map = await _local.sosStore.record(id).get(db);

    if (map == null) return null;

    return LocalSosRecord.fromLocalMap(Map<String, Object?>.from(map));
  }

  Future<void> markSynced(String id) async {
    final record = await findById(id);
    if (record == null) return;

    final db = await _local.database;

    await _local.sosStore
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

    await _local.sosStore
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
    if (record == null || record.ownerUserId == null) return;

    final db = await _local.database;

    await _local.sosStore
        .record(id)
        .put(
          db,
          record
              .copyWith(syncState: 'pending', clearLastError: true)
              .toLocalMap(),
        );

    await _queue.enqueue(
      entityType: 'sos',
      entityId: id,
      ownerLocalId: record.ownerLocalId,
      operation: 'update',
    );
  }
}
