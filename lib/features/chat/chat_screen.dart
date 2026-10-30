import 'dart:async';
import 'package:flutter/material.dart';
import '../../app/theme.dart';
import '../../data/models/local_chat_conversation.dart';
import '../../models/user.dart';
import '../../services/chat_service.dart';
import '../../services/network_service.dart';
import '../../services/unified_chat_service.dart';
import '../nearby/nearby_screen.dart';
import 'new_chat_screen.dart';
import 'unified_conversation_screen.dart';

class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key, required this.me, this.service});
  final AppUser me;
  final UnifiedChatService? service;
  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  late final chat = widget.service ?? UnifiedChatService.instance;
  late final stream = chat.watchInbox(widget.me.id);
  StreamSubscription<List<Map<String, dynamic>>>? _cloud;
  String search = '';
  bool unread = false;
  @override
  void initState() {
    super.initState();
    chat.start(widget.me);
    chat.mesh.addListener(_changed);
    unawaited(_refresh());
    if (widget.me.isMember) {
      try {
        _cloud = ChatService.instance.conversationSignalStream().listen(
          (_) => unawaited(_refresh()),
          onError: (_) {},
        );
      } catch (_) {}
    }
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  Future<void> _refresh() async {
    try {
      await chat.rememberPeers(widget.me.id);
      if (widget.me.isMember && chat.online()) {
        await ChatService.instance.refreshInbox(widget.me);
      }
      await chat.flush();
    } catch (_) {}
  }

  @override
  void dispose() {
    chat.mesh.removeListener(_changed);
    unawaited(_cloud?.cancel());
    super.dispose();
  }

  Future<void> _open(ChatContact c) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) =>
            UnifiedConversationScreen(me: widget.me, contact: c, service: chat),
      ),
    );
  }

  Future<void> _new() async {
    final choice = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.people_outline),
              title: const Text('คนใกล้ตัว'),
              subtitle: const Text('ค้นหาและจับคู่ได้โดยไม่ใช้อินเทอร์เน็ต'),
              onTap: () => Navigator.pop(ctx, 'nearby'),
            ),
            if (widget.me.isMember)
              ListTile(
                leading: const Icon(Icons.person_search_outlined),
                title: const Text('ค้นหาสมาชิก'),
                subtitle: const Text(
                  'ค้นหาผ่านอินเทอร์เน็ต แล้วสนทนาในห้องเดียวกัน',
                ),
                onTap: () => Navigator.pop(ctx, 'member'),
              ),
          ],
        ),
      ),
    );
    if (!mounted || choice == null) return;
    if (choice == 'nearby') {
      await Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => NearbyScreen(me: widget.me)),
      );
      return;
    }
    if (!NetworkService.instance.online.value) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'ค้นหาสมาชิกใหม่ต้องใช้อินเทอร์เน็ต ผู้ติดต่อเดิมยังเปิดแชทได้',
          ),
        ),
      );
      return;
    }
    final c = await Navigator.push<LocalChatConversation>(
      context,
      MaterialPageRoute(builder: (_) => NewChatScreen(me: widget.me)),
    );
    if (c != null && mounted) {
      await _open(
        ChatContact(
          name: c.displayName,
          user: c.peerUserId,
          conversation: c.id,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) => SafeArea(
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
                      style: Theme.of(context).textTheme.headlineMedium,
                    ),
                    Text(
                      'ทุกบทสนทนาในที่เดียว · อ่านได้แม้ออฟไลน์',
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
                onPressed: _new,
                icon: const Icon(Icons.edit_square),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 22),
          child: TextField(
            onChanged: (v) => setState(() => search = v.trim().toLowerCase()),
            decoration: const InputDecoration(
              hintText: 'ค้นหาผู้ติดต่อหรือข้อความ',
              prefixIcon: Icon(Icons.search),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(22, 10, 22, 4),
          child: Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              FilterChip(
                label: const Text('ทั้งหมด'),
                selected: !unread,
                onSelected: (_) => setState(() => unread = false),
              ),
              const SizedBox(width: 8),
              FilterChip(
                label: const Text('ยังไม่ได้อ่าน'),
                selected: unread,
                onSelected: (_) => setState(() => unread = true),
              ),
            ],
          ),
        ),
        Expanded(
          child: StreamBuilder<List<ChatInboxEntry>>(
            stream: stream,
            builder: (ctx, snapshot) {
              if (snapshot.hasError) {
                return const Center(
                  child: Text('อ่านประวัติไม่ได้ กรุณาลองเปิดอีกครั้ง'),
                );
              }
              final rows = (snapshot.data ?? [])
                  .where(
                    (e) =>
                        (!unread || e.unread > 0) &&
                        (search.isEmpty ||
                            e.contact.name.toLowerCase().contains(search) ||
                            e.preview.toLowerCase().contains(search)),
                  )
                  .toList();
              if (rows.isEmpty) {
                return Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.forum_outlined,
                          size: 52,
                          color: context.colors.info,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          search.isNotEmpty || unread
                              ? 'ไม่พบบทสนทนาที่ค้นหา'
                              : 'เริ่มบทสนทนาแรกของคุณ',
                          style: Theme.of(context).textTheme.titleLarge,
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          'จับคู่คนใกล้ตัว หรือเลือกสมาชิกที่ต้องการติดต่อ',
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 16),
                        FilledButton.icon(
                          onPressed: _new,
                          icon: const Icon(Icons.add_comment_outlined),
                          label: const Text('เริ่มแชทใหม่'),
                        ),
                      ],
                    ),
                  ),
                );
              }
              return RefreshIndicator(
                onRefresh: _refresh,
                child: ListView.separated(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.only(top: 8, bottom: 20),
                  itemCount: rows.length,
                  separatorBuilder: (_, _) =>
                      const Divider(indent: 84, endIndent: 22, height: 1),
                  itemBuilder: (ctx, i) {
                    final e = rows[i];
                    final p = e.contact.user != null
                        ? chat.mesh.peerForUser(e.contact.user!)
                        : e.contact.device == null
                        ? null
                        : chat.mesh.peerForDevice(e.contact.device!);
                    return ListTile(
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 22,
                        vertical: 8,
                      ),
                      leading: CircleAvatar(
                        radius: 25,
                        backgroundColor: context.colors.surfaceSoft,
                        child: Icon(
                          p == null
                              ? Icons.person_outline
                              : Icons.person_pin_circle_outlined,
                          color: context.colors.info,
                        ),
                      ),
                      title: Text(
                        e.contact.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontWeight: e.unread > 0
                              ? FontWeight.bold
                              : FontWeight.w600,
                        ),
                      ),
                      subtitle: Text(
                        e.preview,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      trailing: e.unread > 0
                          ? Badge(label: Text('${e.unread}'))
                          : Icon(
                              Icons.chevron_right,
                              color: context.colors.muted,
                            ),
                      onTap: () => _open(e.contact),
                    );
                  },
                ),
              );
            },
          ),
        ),
      ],
    ),
  );
}
