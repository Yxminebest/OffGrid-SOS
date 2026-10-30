import 'package:flutter/material.dart';
import '../../data/models/local_chat_conversation.dart';
import '../../models/user.dart';
import '../../services/unified_chat_service.dart';
import 'unified_conversation_screen.dart';

/// Saved cloud links and notification routes open the same room as radio chats.
class ConversationScreen extends StatelessWidget {
  const ConversationScreen({
    super.key,
    required this.me,
    required this.conversation,
  });
  final AppUser me;
  final LocalChatConversation conversation;
  @override
  Widget build(BuildContext context) => UnifiedConversationScreen(
    me: me,
    contact: ChatContact(
      name: conversation.displayName,
      user: conversation.peerUserId,
      conversation: conversation.id,
    ),
  );
}
