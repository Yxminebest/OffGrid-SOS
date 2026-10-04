import 'dart:async';

import 'package:flutter/material.dart';

import '../../app/theme.dart';
import '../../data/models/local_chat_conversation.dart';
import '../../models/user.dart';
import '../../services/chat_service.dart';
import '../../services/sync_service.dart';
import 'conversation_screen.dart';
import 'new_chat_screen.dart';

class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key, required this.me});

  final AppUser me;

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

enum _InboxFilter { all, unread }

class _ChatScreenState extends State<ChatScreen> {
  StreamSubscription<List<Map<String, dynamic>>>? _conversationSignal;
  bool _refreshing = false;
  String _filter = '';
  _InboxFilter _inboxFilter = _InboxFilter.all;

  @override
  void initState() {
    super.initState();
    if (widget.me.isMember) {
      unawaited(_refresh());
      _conversationSignal = ChatService.instance
          .conversationSignalStream()
          .listen((_) => unawaited(_refresh()), onError: (_) {});
    }
  }

  @override
  void dispose() {
    _conversationSignal?.cancel();
    super.dispose();
  }

  Future<void> _refresh() async {
    if (!widget.me.isMember || _refreshing) return;
    setState(() => _refreshing = true);
    try {
      await SyncService.instance.syncNow();
      await ChatService.instance.refreshInbox(widget.me);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('รีเฟรชแชทไม่สำเร็จ: $e')));
    } finally {
      if (mounted) setState(() => _refreshing = false);
    }
  }

  Future<void> _newChat() async {
    if (!widget.me.isMember) {
      _notice('แชทกับผู้ใช้อื่นต้องเข้าสู่ระบบด้วยบัญชีสมาชิก');
      return;
    }

    final conversation = await Navigator.of(context)
        .push<LocalChatConversation>(
          MaterialPageRoute(builder: (_) => NewChatScreen(me: widget.me)),
        );
    if (!mounted || conversation == null) return;

    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) =>
            ConversationScreen(me: widget.me, conversation: conversation),
      ),
    );
    if (mounted) unawaited(_refresh());
  }

  Future<void> _open(LocalChatConversation conversation) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) =>
            ConversationScreen(me: widget.me, conversation: conversation),
      ),
    );
    if (mounted) unawaited(_refresh());
  }

  void _notice(String text) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.me.isMember) {
      return SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.chat_bubble_outline_rounded,
                  size: 52,
                  color: AppColors.info,
                ),
                const SizedBox(height: 16),
                const Text(
                  'แชทระหว่างผู้ใช้',
                  style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Guest ใช้งาน Local SOS ได้ แต่การส่งข้อความถึงผู้ใช้อื่นต้องเข้าสู่ระบบเพื่อยืนยันตัวตนและรักษาความปลอดภัยของห้องสนทนา',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: AppColors.muted, height: 1.5),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return SafeArea(
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 18, 10, 8),
            child: Row(
              children: [
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'แชท',
                        style: TextStyle(
                          fontSize: 27,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      Text(
                        'ข้อความส่วนตัว • Local-first • Realtime',
                        style: TextStyle(color: AppColors.muted, fontSize: 11),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: 'เริ่มแชทใหม่',
                  onPressed: _newChat,
                  icon: const Icon(Icons.edit_square),
                ),
                IconButton(
                  tooltip: 'รีเฟรช',
                  onPressed: _refreshing ? null : _refresh,
                  icon: _refreshing
                      ? const SizedBox(
                          width: 19,
                          height: 19,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.sync_rounded),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 4, 14, 10),
            child: TextField(
              onChanged: (value) =>
                  setState(() => _filter = value.trim().toLowerCase()),
              decoration: const InputDecoration(
                hintText: 'ค้นหาชื่อหรือข้อความล่าสุด',
                prefixIcon: Icon(Icons.search_rounded),
                contentPadding: EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 12,
                ),
              ),
            ),
          ),
          Expanded(
            child: StreamBuilder<List<LocalChatConversation>>(
              stream: ChatService.instance.watchInbox(widget.me.id),
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return const Center(
                    child: Text('อ่านรายการแชทจาก Local DB ไม่สำเร็จ'),
                  );
                }

                final all = snapshot.data ?? const [];
                final unreadTotal = all.fold<int>(
                  0,
                  (sum, item) => sum + item.unreadCount,
                );

                final searched = all.where(
                  (item) =>
                      _filter.isEmpty ||
                      item.displayName.toLowerCase().contains(_filter) ||
                      (item.lastMessage ?? '').toLowerCase().contains(_filter),
                );

                final list = searched.where((item) {
                  return switch (_inboxFilter) {
                    _InboxFilter.all => true,
                    _InboxFilter.unread => item.unreadCount > 0,
                  };
                }).toList();

                final filtering =
                    _filter.isNotEmpty || _inboxFilter != _InboxFilter.all;

                return Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(14, 0, 14, 8),
                      child: Row(
                        children: [
                          ChoiceChip(
                            label: Text('ทั้งหมด (${all.length})'),
                            selected: _inboxFilter == _InboxFilter.all,
                            onSelected: (_) {
                              setState(() => _inboxFilter = _InboxFilter.all);
                            },
                          ),
                          const SizedBox(width: 8),
                          ChoiceChip(
                            label: Text('ยังไม่ได้อ่าน ($unreadTotal)'),
                            selected: _inboxFilter == _InboxFilter.unread,
                            onSelected: (_) {
                              setState(
                                () => _inboxFilter = _InboxFilter.unread,
                              );
                            },
                          ),
                        ],
                      ),
                    ),
                    Expanded(
                      child: list.isEmpty
                          ? _EmptyInbox(
                              onNewChat: _newChat,
                              filtering: filtering,
                            )
                          : RefreshIndicator(
                              onRefresh: _refresh,
                              child: ListView.separated(
                                physics: const AlwaysScrollableScrollPhysics(),
                                padding: const EdgeInsets.fromLTRB(8, 0, 8, 24),
                                itemCount: list.length,
                                separatorBuilder: (context, index) =>
                                    const Divider(height: 1),
                                itemBuilder: (context, index) {
                                  final conversation = list[index];
                                  return _ConversationTile(
                                    conversation: conversation,
                                    onTap: () => _open(conversation),
                                  );
                                },
                              ),
                            ),
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _ConversationTile extends StatelessWidget {
  const _ConversationTile({required this.conversation, required this.onTap});

  final LocalChatConversation conversation;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final initial = conversation.displayName.trim().isEmpty
        ? '?'
        : conversation.displayName.trim().characters.first.toUpperCase();
    return ListTile(
      onTap: onTap,
      contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      leading: Stack(
        clipBehavior: Clip.none,
        children: [
          CircleAvatar(
            radius: 25,
            backgroundColor: AppColors.surfaceSoft,
            child: Text(
              initial,
              style: const TextStyle(fontWeight: FontWeight.w900),
            ),
          ),
          if (conversation.unreadCount > 0)
            Positioned(
              right: -3,
              top: -3,
              child: Container(
                constraints: const BoxConstraints(minWidth: 20, minHeight: 20),
                padding: const EdgeInsets.symmetric(horizontal: 5),
                decoration: const BoxDecoration(
                  color: AppColors.error,
                  shape: BoxShape.circle,
                ),
                alignment: Alignment.center,
                child: Text(
                  conversation.unreadCount > 99
                      ? '99+'
                      : '${conversation.unreadCount}',
                  style: const TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ),
        ],
      ),
      title: Text(
        conversation.displayName,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontWeight: conversation.unreadCount > 0
              ? FontWeight.w900
              : FontWeight.w700,
        ),
      ),
      subtitle: Text(
        conversation.lastMessage ?? 'เริ่มการสนทนา',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: conversation.unreadCount > 0
              ? AppColors.text
              : AppColors.muted,
          fontWeight: conversation.unreadCount > 0
              ? FontWeight.w700
              : FontWeight.w400,
        ),
      ),
      trailing: conversation.lastMessageAt == null
          ? null
          : Text(
              _time(conversation.lastMessageAt!),
              style: const TextStyle(color: AppColors.muted, fontSize: 10),
            ),
    );
  }

  String _time(DateTime value) {
    final now = DateTime.now();
    if (now.year == value.year &&
        now.month == value.month &&
        now.day == value.day) {
      return '${value.hour.toString().padLeft(2, '0')}:${value.minute.toString().padLeft(2, '0')}';
    }
    return '${value.day}/${value.month}';
  }
}

class _EmptyInbox extends StatelessWidget {
  const _EmptyInbox({required this.onNewChat, required this.filtering});

  final VoidCallback onNewChat;
  final bool filtering;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.forum_outlined, size: 52, color: AppColors.info),
            const SizedBox(height: 14),
            Text(
              filtering ? 'ไม่พบแชทที่ค้นหา' : 'ยังไม่มีห้องสนทนา',
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900),
            ),
            if (!filtering) ...[
              const SizedBox(height: 8),
              const Text(
                'เลือกผู้ใช้เพื่อเริ่มแชทแบบ 1 ต่อ 1',
                style: TextStyle(color: AppColors.muted),
              ),
              const SizedBox(height: 18),
              FilledButton.icon(
                onPressed: onNewChat,
                icon: const Icon(Icons.add_comment_outlined),
                label: const Text('เริ่มแชทใหม่'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
