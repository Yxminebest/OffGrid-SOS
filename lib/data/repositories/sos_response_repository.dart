import 'package:sembast/sembast.dart';
import '../local/local_database.dart';

/// Durable SOS receipts and each responder's progress, scoped to a local owner.
class SosResponseRepository {
  SosResponseRepository(this.local);
  final LocalDatabase local;
  static final store = stringMapStoreFactory.store('sos_responses');

  Future<Map<String, dynamic>?> stored(
    String owner,
    String origin,
    String caseId,
    String actor,
    String category,
  ) async {
    final row = await store
        .record('$owner:$origin:$caseId:$actor:$category')
        .get(await local.database);
    return row == null
        ? null
        : Map<String, dynamic>.from(row['envelope'] as Map);
  }

  Future<Set<String>> completedCases(String owner) async {
    final rows = await store.find(
      await local.database,
      finder: Finder(
        filter: Filter.and([
          Filter.equals('owner', owner),
          Filter.equals('outgoing', true),
        ]),
      ),
    );
    return rows
        .where((row) {
          final body = (row.value['envelope'] as Map)['data'] as Map;
          return body['category'] == 'progress' && body['state'] == 'completed';
        })
        .map((row) => '${row.value['caseOrigin']}:${row.value['caseId']}')
        .toSet();
  }

  Future<Map<String, dynamic>> queue(
    String owner,
    Map<String, dynamic> envelope,
  ) async {
    final body = envelope['data'] as Map;
    final key =
        '$owner:${body['caseOrigin']}:${body['caseId']}:${envelope['origin']}:${body['category']}';
    final db = await local.database;
    return db.transaction((txn) async {
      final ref = store.record(key);
      final old = await ref.get(txn);
      final previous = old?['envelope'] as Map?;
      final oldBody = previous?['data'] as Map?;
      if (oldBody != null &&
          oldBody['state'] == body['state'] &&
          oldBody['revision'] == body['revision']) {
        return Map<String, dynamic>.from(previous!);
      }
      if (body['category'] == 'progress') {
        final allowed = switch (oldBody?['state']) {
          null || 'released' => ['accepted'],
          'accepted' => ['helping', 'released'],
          'helping' => ['completed', 'released'],
          _ => <String>[],
        };
        if (!allowed.contains(body['state'])) {
          throw StateError('ลำดับสถานะเคสไม่ถูกต้อง');
        }
      }
      body['sequence'] = (oldBody?['sequence'] as int? ?? 0) + 1;
      await ref.put(txn, {
        'owner': owner,
        'caseId': body['caseId'],
        'caseOrigin': body['caseOrigin'],
        'actor': envelope['origin'],
        'outgoing': true,
        'delivery': 'pending',
        'envelope': envelope,
      });
      return envelope;
    });
  }

  Future<bool> receive(String owner, Map<String, dynamic> envelope) async {
    final body = envelope['data'] as Map;
    final key =
        '$owner:${body['caseOrigin']}:${body['caseId']}:${envelope['origin']}:${body['category']}';
    final db = await local.database;
    return db.transaction((txn) async {
      final ref = store.record(key);
      final old = await ref.get(txn);
      final previous = (old?['envelope'] as Map?)?['data'] as Map?;
      if (previous != null &&
          (previous['sequence'] as int) >= (body['sequence'] as int)) {
        return false;
      }
      await ref.put(txn, {
        'owner': owner,
        'caseId': body['caseId'],
        'caseOrigin': body['caseOrigin'],
        'actor': envelope['origin'],
        'outgoing': false,
        'delivery': 'delivered',
        'envelope': envelope,
      });
      return true;
    });
  }

  Future<List<Map<String, dynamic>>> pending(
    String owner,
    String target,
  ) async {
    final rows = await store.find(
      await local.database,
      finder: Finder(
        filter: Filter.and([
          Filter.equals('owner', owner),
          Filter.equals('outgoing', true),
          Filter.equals('delivery', 'pending'),
        ]),
      ),
    );
    return rows
        .map((r) => Map<String, dynamic>.from(r.value['envelope'] as Map))
        .where((e) => (e['data'] as Map)['target'] == target)
        .toList();
  }

  Future<void> acknowledge(String owner, String messageId, String peer) async {
    final db = await local.database;
    final rows = await store.find(
      db,
      finder: Finder(
        filter: Filter.and([
          Filter.equals('owner', owner),
          Filter.equals('outgoing', true),
        ]),
      ),
    );
    for (final r in rows) {
      final env = r.value['envelope'] as Map;
      if (env['id'] == messageId && (env['data'] as Map)['target'] == peer) {
        await store.record(r.key).update(db, {'delivery': 'delivered'});
      }
    }
  }

  Future<void> cancelForCase(String owner, String origin, String caseId) async {
    await store.update(
      await local.database,
      {'delivery': 'cancelled'},
      finder: Finder(
        filter: Filter.and([
          Filter.equals('owner', owner),
          Filter.equals('caseOrigin', origin),
          Filter.equals('caseId', caseId),
          Filter.equals('outgoing', true),
          Filter.equals('delivery', 'pending'),
        ]),
      ),
    );
  }

  Stream<List<Map<String, Object?>>> watch(
    String owner,
    String origin,
    String caseId,
  ) async* {
    yield* store
        .query(
          finder: Finder(
            filter: Filter.and([
              Filter.equals('owner', owner),
              Filter.equals('caseOrigin', origin),
              Filter.equals('caseId', caseId),
            ]),
          ),
        )
        .onSnapshots(await local.database)
        .map((rows) => rows.map((r) => r.value).toList());
  }
}
