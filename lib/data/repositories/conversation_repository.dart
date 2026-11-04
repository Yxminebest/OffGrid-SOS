import 'package:flutter/foundation.dart';
import 'package:sembast/sembast.dart';

import '../local/local_database.dart';
import '../models/local_chat_conversation.dart';

class ConversationRepository {
  ConversationRepository({LocalDatabase? local})
    : _local = local ?? LocalDatabase.instance;
  final LocalDatabase _local;

  Future<List<LocalChatConversation>> listForUser(String ownerLocalId) async {
    final db = await _local.database;
    final rows = await _local.conversationStore.find(
      db,
      finder: Finder(filter: Filter.equals('owner_local_id', ownerLocalId)),
    );
    return rows
        .map((row) => LocalChatConversation.fromLocalMap(row.value))
        .toList();
  }

  Stream<List<LocalChatConversation>> watchForUser(String ownerLocalId) async* {
    final db = await _local.database;
    final query = _local.conversationStore.query(
      finder: Finder(
        filter: Filter.equals('owner_local_id', ownerLocalId),
        sortOrders: [
          SortOrder('last_message_at', false),
          SortOrder('updated_at', false),
        ],
      ),
    );

    yield* query
        .onSnapshots(db)
        .map(
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
      final remaining = {for (final row in old) row.key: row.value};
      for (final conversation in conversations) {
        final key = '$ownerLocalId:${conversation.id}';
        final value = conversation.toLocalMap();
        if (!mapEquals(remaining.remove(key), value)) {
          await _local.conversationStore.record(key).put(txn, value);
        }
      }
      for (final key in remaining.keys) {
        await _local.conversationStore.record(key).delete(txn);
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
