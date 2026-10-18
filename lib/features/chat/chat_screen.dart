import 'dart:async';

import 'package:flutter/material.dart';

import '../../app/theme.dart';
import '../../widgets/page_header.dart';
import '../../data/models/local_chat_conversation.dart';
import '../../models/user.dart';
import '../../services/chat_service.dart';
import '../../services/sync_service.dart';
import 'conversation_screen.dart';
import 'new_chat_screen.dart';
import 'nearby_conversation_screen.dart';
import '../../services/network_service.dart';

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
    if (!widget.me.isMember ||
        _refreshing ||
        !NetworkService.instance.online.value) {
      return;
    }
    setState(() => _refreshing = true);
    try {
      await SyncService.instance.syncNow();
      await ChatService.instance.refreshInbox(widget.me);
    } catch (_) {
      // Keep saved chats available while the server is unreachable.
    } finally {
      if (mounted) setState(() => _refreshing = false);
    }
  }

  Future<void> _newChat() async {
    if (!NetworkService.instance.online.value) {
      _notice('ออฟไลน์ · เลือกผู้ติดต่อ Nearby ในรายการแชทด้านบน');
      return;
    }
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
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(22, 24, 22, 12),
              child: PageHeader(
                title: 'ข้อความ',
                subtitle: 'สนทนาผ่าน Nearby ได้แม้ไม่มีอินเทอร์เน็ต',
              ),
            ),
            Expanded(
              child: SingleChildScrollView(child: NearbyInbox(me: widget.me)),
            ),
          ],
        ),
      );
    }

    return SafeArea(
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(22, 24, 16, 16),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'ข้อความ',
                        style: TextStyle(
                          fontSize: 25,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      Text(
                        'ติดตามและพูดคุยกับคนที่คุณติดต่อ',
                        style: TextStyle(
                          color: context.colors.muted,
                          fontSize: 13,
                        ),
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
            padding: const EdgeInsets.fromLTRB(22, 0, 22, 12),
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
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 22),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'แชท Nearby',
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
          ),
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 230),
            child: SingleChildScrollView(child: NearbyInbox(me: widget.me)),
          ),
          const Divider(height: 16),
          Expanded(
            child: StreamBuilder<List<LocalChatConversation>>(
              stream: ChatService.instance.watchInbox(widget.me.id),
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return const Center(
                    child: Text('ยังเปิดรายการข้อความไม่ได้ กรุณาลองอีกครั้ง'),
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
                      child: LayoutBuilder(
                        builder: (context, constraints) => Wrap(
                          spacing: 8,
                          runSpacing: 4,
                          children: [
                            ChoiceChip(
                              visualDensity: VisualDensity.compact,
                              label: Text(
                                'ทั้งหมด (${all.length})',
                                style: const TextStyle(fontSize: 12),
                              ),
                              selected: _inboxFilter == _InboxFilter.all,
                              onSelected: (_) => setState(
                                () => _inboxFilter = _InboxFilter.all,
                              ),
                            ),
                            ChoiceChip(
                              visualDensity: VisualDensity.compact,
                              label: Text(
                                'ยังไม่ได้อ่าน ($unreadTotal)',
                                style: const TextStyle(fontSize: 12),
                              ),
                              selected: _inboxFilter == _InboxFilter.unread,
                              onSelected: (_) => setState(
                                () => _inboxFilter = _InboxFilter.unread,
                              ),
                            ),
                          ],
                        ),
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
                                padding: const EdgeInsets.fromLTRB(
                                  14,
                                  0,
                                  14,
                                  24,
                                ),
                                itemCount: list.length,
                                separatorBuilder: (context, index) =>
                                    const SizedBox(height: 8),
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
      tileColor: context.colors.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      onTap: onTap,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      leading: Stack(
        clipBehavior: Clip.none,
        children: [
          CircleAvatar(
            radius: 25,
            backgroundColor: context.colors.surfaceSoft,
            child: Text(
              initial,
              style: const TextStyle(fontWeight: FontWeight.w700),
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
                    fontSize: 12,
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
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
              ? context.colors.text
              : context.colors.muted,
          fontWeight: conversation.unreadCount > 0
              ? FontWeight.w700
              : FontWeight.w400,
        ),
      ),
      trailing: conversation.lastMessageAt == null
          ? null
          : Text(
              _time(conversation.lastMessageAt!),
              style: TextStyle(color: context.colors.muted, fontSize: 12),
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
        padding: const EdgeInsets.all(18),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.forum_outlined, size: 52, color: context.colors.info),
            const SizedBox(height: 14),
            Text(
              filtering ? 'ไม่พบแชทที่ค้นหา' : 'ยังไม่มีห้องสนทนา',
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
            ),
            if (!filtering) ...[
              const SizedBox(height: 8),
              Text(
                'เลือกผู้ใช้เพื่อเริ่มแชทแบบ 1 ต่อ 1',
                style: TextStyle(color: context.colors.muted),
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
