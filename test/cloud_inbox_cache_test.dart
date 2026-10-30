import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:sembast/sembast_memory.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:offgrid_sos/data/local/local_database.dart';
import 'package:offgrid_sos/data/models/local_chat_conversation.dart';
import 'package:offgrid_sos/data/repositories/conversation_repository.dart';
import 'package:offgrid_sos/data/repositories/message_repository.dart';
import 'package:offgrid_sos/models/user.dart';
import 'package:offgrid_sos/services/chat_service.dart';

const me = AppUser(id: 'owner', firstName: 'A', lastName: '', isMember: true);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late LocalDatabase local;
  late SupabaseClient client;
  late ChatService chat;
  late MessageRepository messages;
  Map<String, dynamic> row(
    String id, {
    String room = 'room',
    bool deleted = false,
  }) => {
    'id': id,
    'conversation_id': room,
    'sender_id': 'peer',
    'type': 'text',
    'content': 'read without opening room',
    'is_deleted': deleted,
    'created_at': DateTime.now().toUtc().toIso8601String(),
  };
  setUp(() async {
    local = LocalDatabase.withDatabase(
      await newDatabaseFactoryMemory().openDatabase('inbox-cache'),
    );
    client = SupabaseClient(
      'https://example.invalid',
      'test',
      authOptions: const AuthClientOptions(autoRefreshToken: false),
    );
    final payload = base64Url
        .encode(
          utf8.encode(
            jsonEncode({
              'exp': DateTime.now().millisecondsSinceEpoch ~/ 1000 + 3600,
              'sub': me.id,
            }),
          ),
        )
        .replaceAll('=', '');
    await client.auth.recoverSession(
      jsonEncode({
        'access_token': 'eyJhbGciOiJIUzI1NiJ9.$payload.test',
        'refresh_token': 'test',
        'token_type': 'bearer',
        'expires_in': 3600,
        'user': {
          'id': me.id,
          'aud': 'authenticated',
          'app_metadata': {},
          'user_metadata': {},
          'created_at': DateTime.now().toUtc().toIso8601String(),
        },
      }),
    );
    await ConversationRepository(local: local).upsert(
      LocalChatConversation(
        id: 'room',
        ownerLocalId: me.id,
        peerUserId: 'peer',
        displayName: 'B',
        updatedAt: DateTime.now(),
        unreadCount: 2,
      ),
    );
    messages = MessageRepository(local: local);
    chat = ChatService(client: client, local: local);
  });
  tearDown(() async {
    await client.dispose();
    await (await local.database).close();
  });
  test(
    'incoming text persists without opening room or marking it read',
    () async {
      await chat.cacheInboxMessages(me, [row('received')]);
      final saved = await messages.findById('received');
      expect(saved!.content, 'read without opening room');
      expect(saved.ownerLocalId, me.id);
      expect(saved.senderName, 'B');
      expect(
        (await ConversationRepository(
          local: local,
        ).listForUser(me.id)).single.unreadCount,
        2,
      );
    },
  );
  test(
    'partial inbox batch retains older history and local pending edits',
    () async {
      await chat.cacheInboxMessages(me, [row('old'), row('edited')]);
      await messages.updateText(
        (await messages.findById('edited'))!,
        'local pending',
      );
      await chat.cacheInboxMessages(me, [row('new'), row('edited')]);
      expect(await messages.findById('old'), isNotNull);
      expect((await messages.findById('edited'))!.content, 'local pending');
      expect(await messages.findById('new'), isNotNull);
    },
  );
  test(
    'unknown room and stale account callbacks never enter local history',
    () async {
      await chat.cacheInboxMessages(me, [row('unknown', room: 'foreign')]);
      const other = AppUser(
        id: 'other',
        firstName: 'Other',
        lastName: '',
        isMember: true,
      );
      await chat.cacheInboxMessages(other, [row('wrong-owner')]);
      expect(await messages.findById('unknown'), isNull);
      expect(await messages.findById('wrong-owner'), isNull);
    },
  );
  test('explicit deleted cloud row clears only that synced message', () async {
    await chat.cacheInboxMessages(me, [row('delete'), row('keep')]);
    await chat.cacheInboxMessages(me, [row('delete', deleted: true)]);
    expect(await messages.findById('delete'), isNull);
    expect(await messages.findById('keep'), isNotNull);
  });
}
