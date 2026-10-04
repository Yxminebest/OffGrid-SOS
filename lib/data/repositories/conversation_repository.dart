import 'package:sembast/sembast.dart';

import '../local/local_database.dart';
import '../models/local_chat_conversation.dart';

class ConversationRepository {
  final LocalDatabase _local = LocalDatabase.instance;

  Stream<List<LocalChatConversation>> watchForUser(String ownerLocalId) async* {
    final db = await _local.database;
    final query = _local.conversationStore.query(
      finder: Finder(
        filter: Filter.equals('owner_local_id', ownerLocalId),
        sortOrders: [SortOrder('last_message_at', false), SortOrder('updated_at', false)],
      ),
    );

    yield* query.onSnapshots(db).map(
          (items) => items
              .map(
                (item) => LocalChatConversation.fromLocalMap(
                  Map<String, Object?>.from(item.value),
                ),
              )
              .toList(),
        );
  }

  Future<void> replaceForUser(
    String ownerLocalId,
    List<LocalChatConversation> conversations,
  ) async {
    final db = await _local.database;
    await db.transaction((txn) async {
      final old = await _local.conversationStore.find(
        txn,
        finder: Finder(filter: Filter.equals('owner_local_id', ownerLocalId)),
      );
      for (final row in old) {
        await _local.conversationStore.record(row.key).delete(txn);
      }
      for (final conversation in conversations) {
        await _local.conversationStore
            .record('$ownerLocalId:${conversation.id}')
            .put(txn, conversation.toLocalMap());
      }
    });
  }

  Future<void> upsert(LocalChatConversation conversation) async {
    final db = await _local.database;
    await _local.conversationStore
        .record('${conversation.ownerLocalId}:${conversation.id}')
        .put(db, conversation.toLocalMap());
  }
}
