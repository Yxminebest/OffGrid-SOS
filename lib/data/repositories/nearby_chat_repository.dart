import 'package:sembast/sembast.dart';
import '../local/local_database.dart';

class NearbyThread {
  const NearbyThread({
    required this.peerId,
    required this.name,
    required this.preview,
    required this.updatedAt,
    required this.unread,
  });
  final String peerId, name, preview;
  final DateTime updatedAt;
  final int unread;
}

/// Nearby records are isolated from cloud messages and scoped to the local user.
class NearbyChatRepository {
  NearbyChatRepository({LocalDatabase? local})
    : _local = local ?? LocalDatabase.instance;
  final LocalDatabase _local;
  static final messages = stringMapStoreFactory.store('nearby_messages');
  static final states = stringMapStoreFactory.store('nearby_sos_states');

  Future<bool> save(
    String owner,
    String peer,
    Map<String, dynamic> envelope, {
    required bool incoming,
    String delivery = 'pending',
    String? localPath,
  }) async {
    final db = await _local.database;
    return db.transaction((txn) async {
      final key = '$owner:${envelope['id']}';
      if (await messages.record(key).exists(txn)) return false;
      await messages.record(key).put(txn, {
        'owner': owner,
        'peer': peer,
        'incoming': incoming,
        'read': !incoming,
        'delivery': delivery,
        'cloudState': 'pending',
        'revision': 1,
        'envelope': envelope,
        'localPath': ?localPath,
      });
      return true;
    });
  }

  Stream<List<Map<String, Object?>>> watchMessages(
    String owner,
    String peer,
  ) async* {
    final db = await _local.database;
    yield* messages
        .query(
          finder: Finder(
            filter: Filter.and([
              Filter.equals('owner', owner),
              Filter.equals('peer', peer),
            ]),
          ),
        )
        .onSnapshots(db)
        .map((rows) {
          final list = rows.map((r) => r.value).toList();
          list.sort((a, b) => _time(a).compareTo(_time(b)));
          return list;
        });
  }

  Stream<List<NearbyThread>> watchThreads(String owner) async* {
    final db = await _local.database;
    yield* messages
        .query(finder: Finder(filter: Filter.equals('owner', owner)))
        .onSnapshots(db)
        .map((rows) {
          final groups = <String, List<Map<String, Object?>>>{};
          for (final row in rows) {
            (groups[row.value['peer'] as String] ??= []).add(row.value);
          }
          final result = <NearbyThread>[];
          for (final entry in groups.entries) {
            entry.value.sort((a, b) => _time(a).compareTo(_time(b)));
            final latest = entry.value.last;
            final env = Map<String, dynamic>.from(latest['envelope'] as Map);
            final incoming = entry.value
                .where((r) => r['incoming'] == true)
                .toList();
            final named = incoming.isEmpty
                ? env['peerName']
                : (incoming.last['envelope'] as Map)['sender'];
            result.add(
              NearbyThread(
                peerId: entry.key,
                name: named?.toString() ?? 'อุปกรณ์ใกล้เคียง',
                preview: env['kind'] == 'media'
                    ? ((env['data'] as Map)['type'] == 'image'
                          ? 'รูปภาพ'
                          : 'วิดีโอ')
                    : (env['data'] as Map)['text']?.toString() ?? '',
                updatedAt: _time(latest),
                unread: entry.value
                    .where((r) => r['incoming'] == true && r['read'] != true)
                    .length,
              ),
            );
          }
          result.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
          return result;
        });
  }

  static DateTime _time(Map<String, Object?> record) =>
      DateTime.tryParse((record['envelope'] as Map)['at']?.toString() ?? '') ??
      DateTime.fromMillisecondsSinceEpoch(0);

  Future<void> markRead(String owner, String peer) async {
    final db = await _local.database;
    await messages.update(
      db,
      {'read': true},
      finder: Finder(
        filter: Filter.and([
          Filter.equals('owner', owner),
          Filter.equals('peer', peer),
        ]),
      ),
    );
  }

  Future<void> markDelivery(String owner, String id, String delivery) async {
    final db = await _local.database;
    final ref = messages.record('$owner:$id');
    await db.transaction((txn) async {
      final row = await ref.get(txn);
      if (row != null &&
          row['incoming'] == false &&
          row['delivery'] != 'delivered') {
        await ref.update(txn, {
          'delivery': delivery,
          'cloudState': 'pending',
          'revision': (row['revision'] as int? ?? 0) + 1,
        });
      }
    });
  }

  Future<bool> acknowledge(String owner, String id, String peer) async {
    final db = await _local.database;
    return db.transaction((txn) async {
      final ref = messages.record('$owner:$id');
      final row = await ref.get(txn);
      if (row == null || row['incoming'] != false || row['peer'] != peer) {
        return false;
      }
      await ref.update(txn, {
        'delivery': 'delivered',
        'cloudState': 'pending',
        'revision': (row['revision'] as int? ?? 0) + 1,
      });
      return true;
    });
  }

  Future<List<Map<String, dynamic>>> pending(String owner, String peer) async {
    final db = await _local.database;
    final rows = await messages.find(
      db,
      finder: Finder(
        filter: Filter.and([
          Filter.equals('owner', owner),
          Filter.equals('peer', peer),
          Filter.equals('incoming', false),
          Filter.notEquals('historical', true),
          Filter.notEquals('delivery', 'delivered'),
        ]),
      ),
    );
    return rows
        .map((r) => Map<String, dynamic>.from(r.value['envelope'] as Map))
        .toList();
  }

  Future<Map<String, Object?>?> find(String owner, String id) async =>
      messages.record('$owner:$id').get(await _local.database);

  Future<int> unsyncedCount(String owner) async => messages.count(
    await _local.database,
    filter: Filter.and([
      Filter.equals('owner', owner),
      Filter.notEquals('cloudState', 'synced'),
    ]),
  );

  Future<List<Map<String, Object?>>> unsynced(String owner) async {
    final rows = await messages.find(
      await _local.database,
      finder: Finder(
        filter: Filter.and([
          Filter.equals('owner', owner),
          Filter.notEquals('cloudState', 'synced'),
        ]),
        limit: 100,
      ),
    );
    return rows.map((r) => r.value).toList();
  }

  Future<void> archiveMediaUploaded(
    String owner,
    String id,
    String path,
  ) async {
    await messages.record('$owner:$id').update(await _local.database, {
      'archiveMediaPath': path,
    });
  }

  Future<void> archived(String owner, String id, Object? revision) async {
    final db = await _local.database;
    await db.transaction((txn) async {
      final ref = messages.record('$owner:$id');
      final row = await ref.get(txn);
      if (row != null && row['revision'] == revision) {
        await ref.update(txn, {'cloudState': 'synced'});
      }
    });
  }

  Future<void> restoreArchive(
    String owner,
    Map<String, dynamic> cloud, {
    String? localPath,
  }) async {
    final envelope = Map<String, dynamic>.from(cloud['envelope'] as Map);
    final db = await _local.database;
    await db.transaction((txn) async {
      final ref = messages.record('$owner:${envelope['id']}');
      if (await ref.exists(txn)) return;
      await ref.put(txn, {
        'owner': owner,
        'peer': cloud['peer'],
        'incoming': cloud['incoming'],
        'read': true,
        'delivery': cloud['delivery'],
        'envelope': envelope,
        'cloudState': 'synced',
        'historical': true,
        'revision': cloud['revision'],
        'localPath': ?localPath,
      });
    });
  }

  Future<List<Map<String, dynamic>>> loadSos(String owner) async {
    final db = await _local.database;
    final rows = await states.find(
      db,
      finder: Finder(filter: Filter.equals('owner', owner)),
    );
    return rows
        .map((r) => Map<String, dynamic>.from(r.value['envelope'] as Map))
        .toList();
  }

  Future<bool> saveSos(String owner, Map<String, dynamic> envelope) async {
    final body = envelope['data'] as Map;
    final revision = (body['revision'] as num?)?.toInt() ?? 0;
    final db = await _local.database;
    return db.transaction((txn) async {
      final ref = states.record(
        '$owner:${envelope['origin']}:${body['caseId']}',
      );
      final previous = await ref.get(txn);
      if (previous != null) {
        final old = (previous['envelope'] as Map)['data'] as Map;
        final oldRevision = (old['revision'] as num?)?.toInt() ?? 0;
        if (revision < oldRevision ||
            (revision == oldRevision &&
                (oldRevision > 0 || old['active'] == false))) {
          return false;
        }
      }
      await ref.put(txn, {'owner': owner, 'envelope': envelope});
      return true;
    });
  }
}
