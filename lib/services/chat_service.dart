import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../data/models/local_chat_conversation.dart';
import '../data/repositories/conversation_repository.dart';
import '../data/repositories/message_repository.dart';
import '../models/chat_user.dart';
import '../models/user.dart';

class ChatService {
  ChatService._();

  static final ChatService instance = ChatService._();

  final ConversationRepository _conversations = ConversationRepository();
  final MessageRepository _messages = MessageRepository();

  SupabaseClient get _supabase => Supabase.instance.client;

  Stream<List<LocalChatConversation>> watchInbox(String ownerLocalId) {
    return _conversations.watchForUser(ownerLocalId);
  }

  Future<void> refreshInbox(AppUser me) async {
    if (!me.isMember) return;

    final rows = await _supabase.rpc('chat_list_conversations');
    final list = <LocalChatConversation>[];

    for (final raw in (rows as List)) {
      final map = Map<String, dynamic>.from(raw as Map);
      list.add(
        LocalChatConversation(
          id: map['conversation_id'].toString(),
          ownerLocalId: me.id,
          peerUserId: map['other_user_id'].toString(),
          displayName: map['display_name']?.toString() ?? 'ผู้ใช้',
          photoPath: map['photo_path']?.toString(),
          lastMessage: map['last_message']?.toString(),
          lastMessageAt: _parseDate(map['last_message_at']),
          unreadCount:
              int.tryParse(map['unread_count']?.toString() ?? '') ?? 0,
          peerLastReadAt: _parseDate(map['peer_last_read_at']),
          updatedAt: _parseDate(map['updated_at']) ?? DateTime.now(),
        ),
      );
    }

    await _conversations.replaceForUser(me.id, list);
  }

  Future<List<ChatUser>> searchUsers(String query) async {
    final rows = await _supabase.rpc(
      'chat_search_users',
      params: <String, dynamic>{'p_query': query.trim()},
    );

    return (rows as List)
        .map((raw) => ChatUser.fromMap(Map<String, dynamic>.from(raw as Map)))
        .toList();
  }

  Future<LocalChatConversation> getOrCreateDirect({
    required AppUser me,
    required ChatUser peer,
  }) async {
    final conversationId = await _supabase.rpc(
      'chat_get_or_create_direct',
      params: <String, dynamic>{'p_other_user': peer.id},
    );

    final conversation = LocalChatConversation(
      id: conversationId.toString(),
      ownerLocalId: me.id,
      peerUserId: peer.id,
      displayName: peer.fullName,
      photoPath: peer.photoPath,
      updatedAt: DateTime.now(),
    );

    await _conversations.upsert(conversation);
    await refreshInbox(me);
    return conversation;
  }

  StreamSubscription<List<Map<String, dynamic>>> subscribeMessages({
    required AppUser me,
    required LocalChatConversation conversation,
    required void Function(Object error) onError,
  }) {
    return _supabase
        .from('messages')
        .stream(primaryKey: ['id'])
        .eq('conversation_id', conversation.id)
        .order('created_at')
        .listen((rows) async {
          try {
            await _messages.reconcileCloud(
              ownerLocalId: me.id,
              conversationId: conversation.id,
              cloudRows: rows,
              currentUserId: me.id,
              currentUserName: me.fullName,
              peerName: conversation.displayName,
            );
            await markRead(conversation.id);
            unawaited(refreshInbox(me));
          } catch (e) {
            onError(e);
          }
        }, onError: onError);
  }


  Stream<List<Map<String, dynamic>>> conversationSignalStream() {
    return _supabase
        .from('conversations')
        .stream(primaryKey: ['id'])
        .order('updated_at', ascending: false);
  }

  Stream<List<Map<String, dynamic>>> memberStateStream(String conversationId) {
    return _supabase
        .from('conversation_members')
        .stream(primaryKey: ['conversation_id', 'user_id'])
        .eq('conversation_id', conversationId);
  }

  Stream<List<Map<String, dynamic>>> reactionStream(String conversationId) {
    return _supabase
        .from('message_reactions')
        .stream(primaryKey: ['conversation_id', 'message_id', 'user_id', 'emoji'])
        .eq('conversation_id', conversationId);
  }

  Stream<List<Map<String, dynamic>>> typingStream(String conversationId) {
    return _supabase
        .from('chat_typing')
        .stream(primaryKey: ['conversation_id', 'user_id'])
        .eq('conversation_id', conversationId);
  }

  Future<void> markRead(String conversationId) async {
    await _supabase.rpc(
      'chat_mark_read',
      params: <String, dynamic>{'p_conversation_id': conversationId},
    );
  }

  Future<void> setTyping(String conversationId, bool isTyping) async {
    final user = _supabase.auth.currentUser;
    if (user == null) return;

    if (!isTyping) {
      await _supabase
          .from('chat_typing')
          .delete()
          .eq('conversation_id', conversationId)
          .eq('user_id', user.id);
      return;
    }

    await _supabase.from('chat_typing').upsert(
      <String, dynamic>{
        'conversation_id': conversationId,
        'user_id': user.id,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      },
      onConflict: 'conversation_id,user_id',
    );
  }

  Future<void> toggleReaction({
    required String conversationId,
    required String messageId,
    required String emoji,
  }) async {
    final user = _supabase.auth.currentUser;
    if (user == null) return;

    final existing = await _supabase
        .from('message_reactions')
        .select('emoji')
        .eq('message_id', messageId)
        .eq('user_id', user.id)
        .eq('emoji', emoji)
        .maybeSingle();

    if (existing != null) {
      await _supabase
          .from('message_reactions')
          .delete()
          .eq('message_id', messageId)
          .eq('user_id', user.id)
          .eq('emoji', emoji);
      return;
    }

    await _supabase.from('message_reactions').insert(<String, dynamic>{
      'conversation_id': conversationId,
      'message_id': messageId,
      'user_id': user.id,
      'emoji': emoji,
    });
  }

  Future<String?> signedAvatarUrl(String? path) async {
    if (path == null || path.isEmpty) return null;
    try {
      return await _supabase.storage
          .from('avatars')
          .createSignedUrl(path, const Duration(hours: 1).inSeconds);
    } catch (_) {
      return null;
    }
  }

  Future<String?> signedMediaUrl(String? path) async {
    if (path == null || path.isEmpty) return null;
    try {
      return await _supabase.storage
          .from('chat-media')
          .createSignedUrl(path, const Duration(hours: 1).inSeconds);
    } catch (_) {
      return null;
    }
  }

  DateTime? _parseDate(Object? value) {
    final text = value?.toString();
    if (text == null || text.isEmpty) return null;
    return DateTime.tryParse(text)?.toLocal();
  }
}
