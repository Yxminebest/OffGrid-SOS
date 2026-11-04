import 'package:sembast/sembast.dart';
import '../data/local/local_database.dart';
import 'chat_action.dart';

/// Signed public room events are separate from private/cloud conversations.
/// Keep tombstones: a phone returning after an outage must not revive a delete.
class MeshRoom {
  MeshRoom(this.local);
  final LocalDatabase local;
  static final store = stringMapStoreFactory.store('mesh_public_room_v1');

  Future<bool> save(String owner, Map<String, dynamic> event) async {
    final db = await local.database;
    return db.transaction((txn) async {
      final record = store.record('$owner:${event['origin']}:${event['id']}');
      if (await record.exists(txn)) return false;
      await record.put(txn, {'owner': owner, 'event': event});
      return true;
    });
  }

  Future<List<Map<String, dynamic>>> events(String owner) async {
    final rows = await store.find(
      await local.database,
      finder: Finder(filter: Filter.equals('owner', owner)),
    );
    return _events(rows);
  }

  Stream<List<Map<String, dynamic>>> watch(String owner) async* {
    yield* store
        .query(finder: Finder(filter: Filter.equals('owner', owner)))
        .onSnapshots(await local.database)
        .map((rows) => project(_events(rows)));
  }

  static List<Map<String, dynamic>> _events(
    List<RecordSnapshot<String, Map<String, Object?>>> rows,
  ) =>
      rows
          .map((r) => Map<String, dynamic>.from(r.value['event'] as Map))
          .toList()
        ..sort((a, b) {
          final time = a['at'].toString().compareTo(b['at'].toString());
          return time != 0
              ? time
              : a['id'].toString().compareTo(b['id'].toString());
        });

  static List<Map<String, dynamic>> project(List<Map<String, dynamic>> events) {
    final messages = <String, Map<String, dynamic>>{};
    final actions = <Map<String, dynamic>>[];
    for (final event in events) {
      final wire = (event['data'] as Map)['text'] as String;
      final action = ChatAction.parse(wire);
      if (action != null && action.kind != 'message') {
        actions.add(event);
      } else {
        messages['${event['origin']}:${event['id']}'] = {
          ...event,
          'text': action?.text ?? wire,
          'replyTo': action?.target,
        };
      }
    }
    for (final event in actions) {
      final action = ChatAction.parse(
        (event['data'] as Map)['text'] as String,
      )!;
      // Only the signing author can change their own message. Deletion and
      // retraction are terminal even if an older edit arrives afterwards.
      final message = messages['${event['origin']}:${action.target}'];
      if (message == null ||
          message['deleted'] == true ||
          (message['retracted'] == true && action.kind != 'delete')) {
        continue;
      }
      switch (action.kind) {
        case 'delete':
          message['deleted'] = true;
        case 'retract':
          message['retracted'] = true;
          message['text'] = 'ยกเลิกข้อความแล้ว';
        case 'edit':
          message['text'] = action.text;
          message['edited'] = true;
      }
    }
    return messages.values.where((m) => m['deleted'] != true).toList();
  }
}
