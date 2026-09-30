import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';
import '../../app/theme.dart';
import '../../models/local_identity.dart';
import '../../models/message.dart';
import '../../widgets/app_card.dart';
import '../../widgets/status_badge.dart';

class ChatHubScreen extends StatelessWidget {
  const ChatHubScreen({super.key, required this.me});

  final LocalIdentity me;

  @override
  Widget build(BuildContext context) {
    const chats = [
      ('Somchai', PeerKind.sos, 'ช่วยด้วยครับ ผมติดอยู่ในอาคาร', 'ตอนนี้'),
      ('Rescue Team', PeerKind.rescue, 'กำลังเดินทางไปยังจุดนัดพบ', '5 นาที'),
    ];

    return Scaffold(
      appBar: AppBar(title: const Text('แชท')),
      body: ListView.separated(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 110),
        itemCount: chats.length,
        separatorBuilder: (_, __) => const SizedBox(height: 10),
        itemBuilder: (context, index) {
          final chat = chats[index];
          final color = chat.$2 == PeerKind.sos ? AppColors.sos : AppColors.rescue;
          return AppCard(
            padding: EdgeInsets.zero,
            borderColor: color.withOpacity(.75),
            child: ListTile(
              minTileHeight: 76,
              leading: CircleAvatar(
                backgroundColor: color.withOpacity(.14),
                child: Icon(
                  chat.$2 == PeerKind.sos
                      ? Icons.warning_amber_rounded
                      : Icons.health_and_safety_outlined,
                  color: color,
                ),
              ),
              title: Row(
                children: [
                  Expanded(
                    child: Text(chat.$1,
                        style: const TextStyle(fontWeight: FontWeight.w800)),
                  ),
                  Text(chat.$4,
                      style: const TextStyle(color: AppColors.muted, fontSize: 12)),
                ],
              ),
              subtitle: Text(
                chat.$3,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: AppColors.muted),
              ),
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => ChatScreen(
                    me: me,
                    peerName: chat.$1,
                    peerKind: chat.$2,
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class ChatScreen extends StatefulWidget {
  const ChatScreen({
    super.key,
    required this.me,
    required this.peerName,
    required this.peerKind,
  });

  final LocalIdentity me;
  final String peerName;
  final PeerKind peerKind;

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _controller = TextEditingController();
  late final List<Message> _messages;

  @override
  void initState() {
    super.initState();
    _messages = [
      Message(
        id: 'incoming-help',
        senderId: 'peer',
        senderName: widget.peerName,
        kind: MessageKind.text,
        createdAt: DateTime.now(),
        text: 'ช่วยด้วยครับ\nผมติดอยู่ในอาคาร\n📍 ตำแหน่งล่าสุดแนบมากับ SOS',
        status: DeliveryStatus.sent,
        isMine: false,
      ),
      Message(
        id: 'sent-demo',
        senderId: widget.me.id,
        senderName: widget.me.fullName,
        kind: MessageKind.text,
        createdAt: DateTime.now(),
        text: 'กำลังไปช่วย',
        status: DeliveryStatus.sent,
      ),
      Message(
        id: 'synced-demo',
        senderId: widget.me.id,
        senderName: widget.me.fullName,
        kind: MessageKind.text,
        createdAt: DateTime.now(),
        text: 'รับทราบตำแหน่งแล้ว',
        status: DeliveryStatus.synced,
      ),
      Message(
        id: 'pending-demo',
        senderId: widget.me.id,
        senderName: widget.me.fullName,
        kind: MessageKind.text,
        createdAt: DateTime.now(),
        text: 'กำลังส่งพิกัดของฉัน',
        status: DeliveryStatus.pending,
      ),
      Message(
        id: 'error-demo',
        senderId: widget.me.id,
        senderName: widget.me.fullName,
        kind: MessageKind.image,
        createdAt: DateTime.now(),
        status: DeliveryStatus.error,
      ),
    ];
  }

  void _queue(Message message) {
    setState(() => _messages.add(message));
    _simulateSend(message);
  }

  void _simulateSend(Message message) {
    // Week 2 mock: Local DB -> Nearby/Relay -> Cloud Sync.
    // Week 3-4: replace with real repositories/services.
    Future.delayed(const Duration(seconds: 1), () {
      if (!mounted || message.status == DeliveryStatus.error) return;
      setState(() => message.status = DeliveryStatus.sent);
    });
    Future.delayed(const Duration(seconds: 3), () {
      if (!mounted || message.status == DeliveryStatus.error) return;
      setState(() => message.status = DeliveryStatus.synced);
    });
  }

  void _sendText() {
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    _queue(Message(
      id: const Uuid().v4(),
      senderId: widget.me.id,
      senderName: widget.me.fullName,
      kind: MessageKind.text,
      createdAt: DateTime.now(),
      text: text,
      status: DeliveryStatus.pending,
    ));
    _controller.clear();
  }

  void _retry(Message message) {
    setState(() => message.status = DeliveryStatus.pending);
    _simulateSend(message);
  }

  void _addAttachment(MessageKind kind) {
    final message = Message(
      id: const Uuid().v4(),
      senderId: widget.me.id,
      senderName: widget.me.fullName,
      kind: kind,
      createdAt: DateTime.now(),
      status: DeliveryStatus.pending,
      text: kind == MessageKind.voice ? 'คำถอดความ: ต้องการน้ำดื่ม' : null,
      durationSeconds: kind == MessageKind.voice ? 8 : null,
      lat: kind == MessageKind.location ? 13.7563 : null,
      lon: kind == MessageKind.location ? 100.5018 : null,
    );
    _queue(message);
  }

  void _openAttachMenu() {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surface,
      showDragHandle: true,
      builder: (sheetContext) {
        Widget item(IconData icon, String label, MessageKind kind) {
          return ListTile(
            minTileHeight: 56,
            leading: Icon(icon, color: AppColors.info),
            title: Text(label),
            onTap: () {
              Navigator.pop(sheetContext);
              _addAttachment(kind);
            },
          );
        }

        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              item(Icons.image_outlined, 'รูปภาพ', MessageKind.image),
              item(Icons.videocam_outlined, 'วิดีโอ', MessageKind.video),
              item(Icons.mic_none_rounded, 'ข้อความเสียง', MessageKind.voice),
              item(Icons.location_on_outlined, 'ตำแหน่ง', MessageKind.location),
            ],
          ),
        );
      },
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = switch (widget.peerKind) {
      PeerKind.sos => AppColors.sos,
      PeerKind.rescue => AppColors.rescue,
      PeerKind.normal => AppColors.muted,
    };
    final status = switch (widget.peerKind) {
      PeerKind.sos => '⚠ SOS',
      PeerKind.rescue => '🛟 RESCUE',
      PeerKind.normal => '👤 USER',
    };

    return Scaffold(
      appBar: AppBar(
        title: Column(
          children: [
            Text(widget.peerName,
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
            Text(status,
                style: TextStyle(fontSize: 11, color: color, fontWeight: FontWeight.w900)),
          ],
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.fromLTRB(14, 14, 14, 8),
              itemCount: _messages.length,
              itemBuilder: (_, index) {
                final message = _messages[index];
                return MessageBubble(
                  message: message,
                  onRetry: message.status == DeliveryStatus.error
                      ? () => _retry(message)
                      : null,
                );
              },
            ),
          ),
          Container(
            width: double.infinity,
            margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.border),
            ),
            child: const Text(
              '＋ แนบ: 🖼 รูป · 🎥 วิดีโอ · 🎤 เสียง · 📍 ตำแหน่ง',
              style: TextStyle(color: AppColors.muted, fontSize: 13),
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
              child: Row(
                children: [
                  IconButton(
                    tooltip: 'แนบไฟล์หรือตำแหน่ง',
                    onPressed: _openAttachMenu,
                    icon: const Icon(Icons.add_circle_outline_rounded),
                  ),
                  Expanded(
                    child: TextField(
                      controller: _controller,
                      minLines: 1,
                      maxLines: 4,
                      textInputAction: TextInputAction.send,
                      onSubmitted: (_) => _sendText(),
                      decoration: const InputDecoration(hintText: 'พิมพ์ข้อความ...'),
                    ),
                  ),
                  const SizedBox(width: 6),
                  IconButton.filled(
                    tooltip: 'ส่งข้อความ',
                    style: IconButton.styleFrom(
                      backgroundColor: const Color(0xFF17344A),
                      foregroundColor: AppColors.text,
                    ),
                    onPressed: _sendText,
                    icon: const Icon(Icons.send_rounded),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class MessageBubble extends StatelessWidget {
  const MessageBubble({super.key, required this.message, this.onRetry});

  final Message message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final isError = message.status == DeliveryStatus.error;
    final bg = message.isMine
        ? (isError ? AppColors.error.withOpacity(.18) : const Color(0xFF17344A))
        : AppColors.surface;
    final border = isError ? AppColors.error : AppColors.border;

    return Align(
      alignment: message.isMine ? Alignment.centerRight : Alignment.centerLeft,
      child: GestureDetector(
        onTap: onRetry,
        child: Container(
          constraints: const BoxConstraints(maxWidth: 300),
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 10),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _content(),
              if (message.isMine) ...[
                const SizedBox(height: 6),
                _status(),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _content() {
    switch (message.kind) {
      case MessageKind.text:
        return Text(message.text ?? '', style: const TextStyle(fontSize: 16));
      case MessageKind.image:
        return const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.image_outlined),
            SizedBox(width: 7),
            Text('รูปภาพ', style: TextStyle(fontWeight: FontWeight.w700)),
          ],
        );
      case MessageKind.video:
        return const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.videocam_outlined),
            SizedBox(width: 7),
            Text('วิดีโอ', style: TextStyle(fontWeight: FontWeight.w700)),
          ],
        );
      case MessageKind.voice:
        return Text('🎤 ข้อความเสียง 0:${(message.durationSeconds ?? 0).toString().padLeft(2, '0')}\n${message.text ?? ''}');
      case MessageKind.location:
        return const Text('📍 ตำแหน่งล่าสุด\nแตะเพื่อดูตำแหน่งที่บันทึกไว้');
    }
  }

  Widget _status() {
    final (icon, text, color) = switch (message.status) {
      DeliveryStatus.pending =>
        (Icons.schedule_rounded, 'ค้างส่ง', AppColors.pending),
      DeliveryStatus.sent =>
        (Icons.done_rounded, 'ส่งถึงอุปกรณ์', AppColors.success),
      DeliveryStatus.synced =>
        (Icons.done_all_rounded, 'ซิงก์แล้ว', AppColors.info),
      DeliveryStatus.error =>
        (Icons.warning_amber_rounded, 'เกิดข้อผิดพลาด · แตะเพื่อลองใหม่', AppColors.error),
    };

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: color, size: 15),
        const SizedBox(width: 4),
        Flexible(
          child: Text(
            text,
            style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w800),
          ),
        ),
      ],
    );
  }
}
