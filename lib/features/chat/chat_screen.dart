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
    const conversations = [
      ('Somchai', PeerKind.sos, 'ช่วยด้วยครับ ผมติดอยู่ในอาคาร', 'ตอนนี้'),
      ('Rescue Team', PeerKind.rescue, 'กำลังเดินทางไปยังจุดนัดพบ', '5 นาที'),
    ];

    return Scaffold(
      appBar: AppBar(title: const Text('แชท')),
      body: ListView.separated(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 110),
        itemCount: conversations.length,
        separatorBuilder: (_, __) => const SizedBox(height: 10),
        itemBuilder: (context, i) {
          final c = conversations[i];
          final color = c.$2 == PeerKind.sos ? AppColors.sos : AppColors.rescue;
          return AppCard(
            padding: EdgeInsets.zero,
            borderColor: color.withOpacity(.7),
            child: ListTile(
              minTileHeight: 78,
              leading: CircleAvatar(
                backgroundColor: color.withOpacity(.15),
                child: Icon(
                  c.$2 == PeerKind.sos
                      ? Icons.warning_amber_rounded
                      : Icons.health_and_safety_outlined,
                  color: color,
                ),
              ),
              title: Row(children: [
                Expanded(child: Text(c.$1, style: const TextStyle(fontWeight: FontWeight.w700))),
                Text(c.$4, style: const TextStyle(color: AppColors.muted, fontSize: 12)),
              ]),
              subtitle: Text(c.$3,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: AppColors.muted)),
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => ChatScreen(me: me, peerName: c.$1, peerKind: c.$2),
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
  static const _quick = ['ต้องการน้ำ', 'บาดเจ็บ', 'ปลอดภัย'];

  @override
  void initState() {
    super.initState();
    _messages = [
      Message(
        id: 'demo-in-1',
        senderId: 'peer',
        senderName: widget.peerName,
        kind: MessageKind.text,
        createdAt: DateTime.now(),
        text: 'ช่วยด้วยครับ ผมติดอยู่ในอาคาร',
        status: DeliveryStatus.sent,
        isMine: false,
      ),
      Message(
        id: 'demo-out-1',
        senderId: widget.me.id,
        senderName: widget.me.fullName,
        kind: MessageKind.text,
        createdAt: DateTime.now(),
        text: 'กำลังไปช่วย รออยู่ที่เดิมนะครับ',
        status: DeliveryStatus.sent,
        isMine: true,
      ),
    ];
  }

  void _add(MessageKind kind,
      {String? text, int? seconds, double? lat, double? lon}) {
    final m = Message(
      id: const Uuid().v4(),
      senderId: widget.me.id,
      senderName: widget.me.fullName,
      kind: kind,
      createdAt: DateTime.now(),
      text: text,
      durationSeconds: seconds,
      lat: lat,
      lon: lon,
      accuracy: lat == null ? null : 10,
    );
    setState(() => _messages.add(m));

    // TODO Week 3-4: persist to local DB, send via mesh, then cloud sync.
    Future.delayed(const Duration(seconds: 1), () {
      if (mounted) setState(() => m.status = DeliveryStatus.sent);
    });
    Future.delayed(const Duration(seconds: 3), () {
      if (mounted) setState(() => m.status = DeliveryStatus.synced);
    });
  }

  void _sendText([String? preset]) {
    final t = (preset ?? _controller.text).trim();
    if (t.isEmpty) return;
    _add(MessageKind.text, text: t);
    _controller.clear();
  }

  void _openAttachMenu() {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surface,
      showDragHandle: true,
      builder: (ctx) {
        Widget item(IconData icon, String label, VoidCallback onTap) => ListTile(
              minTileHeight: 56,
              leading: Icon(icon, size: 28, color: AppColors.info),
              title: Text(label, style: const TextStyle(fontSize: 17)),
              onTap: () {
                Navigator.pop(ctx);
                onTap();
              },
            );
        return SafeArea(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            item(Icons.image_outlined, 'รูปภาพ', () => _add(MessageKind.image)),
            item(Icons.videocam_outlined, 'วิดีโอ', () => _add(MessageKind.video)),
            item(Icons.mic_none_rounded, 'ข้อความเสียง',
                () => _add(MessageKind.voice, seconds: 8, text: 'ต้องการน้ำดื่ม')),
            item(Icons.location_on_outlined, 'ตำแหน่งล่าสุด',
                () => _add(MessageKind.location, lat: 13.7563, lon: 100.5018)),
          ]),
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
    final statusColor = widget.peerKind == PeerKind.sos
        ? AppColors.sos
        : widget.peerKind == PeerKind.rescue
            ? AppColors.rescue
            : AppColors.muted;
    final statusText = widget.peerKind == PeerKind.sos
        ? '⚠ SOS'
        : widget.peerKind == PeerKind.rescue
            ? 'RESCUE'
            : 'USER';

    return Scaffold(
      appBar: AppBar(
        title: Column(
          children: [
            Text(widget.peerName,
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
            Text(statusText,
                style: TextStyle(fontSize: 11, color: statusColor, fontWeight: FontWeight.w800)),
          ],
        ),
      ),
      body: Column(
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: const BoxDecoration(
              color: AppColors.surface,
              border: Border(bottom: BorderSide(color: AppColors.border)),
            ),
            child: const Row(children: [
              Icon(Icons.wifi_off_rounded, size: 17, color: AppColors.pending),
              SizedBox(width: 8),
              Text('ออฟไลน์ · ส่งผ่าน Nearby ได้',
                  style: TextStyle(color: AppColors.muted, fontSize: 13)),
            ]),
          ),
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.fromLTRB(14, 14, 14, 8),
              itemCount: _messages.length,
              itemBuilder: (_, i) => _Bubble(_messages[i]),
            ),
          ),
          SizedBox(
            height: 48,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              children: [
                for (final q in _quick)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ActionChip(label: Text(q), onPressed: () => _sendText(q)),
                  ),
              ],
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(8, 6, 8, 8),
              child: Row(children: [
                IconButton(
                  tooltip: 'แนบไฟล์หรือตำแหน่ง',
                  icon: const Icon(Icons.add_circle_outline_rounded),
                  onPressed: _openAttachMenu,
                ),
                Expanded(
                  child: TextField(
                    controller: _controller,
                    minLines: 1,
                    maxLines: 4,
                    textInputAction: TextInputAction.send,
                    decoration: const InputDecoration(hintText: 'พิมพ์ข้อความ...'),
                    onSubmitted: (_) => _sendText(),
                  ),
                ),
                const SizedBox(width: 4),
                IconButton(
                  tooltip: 'พูดเป็นข้อความ',
                  icon: const Icon(Icons.mic_none_rounded),
                  onPressed: () {},
                ),
                IconButton(
                  tooltip: 'ส่งข้อความ',
                  style: IconButton.styleFrom(
                    backgroundColor: AppColors.rescue,
                    foregroundColor: AppColors.text,
                  ),
                  icon: const Icon(Icons.send_rounded),
                  onPressed: _sendText,
                ),
              ]),
            ),
          ),
        ],
      ),
    );
  }
}

class _Bubble extends StatelessWidget {
  const _Bubble(this.m);
  final Message m;

  (IconData, String, Color) get _status => switch (m.status) {
        DeliveryStatus.pending => (Icons.schedule_rounded, 'ค้างส่ง', AppColors.pending),
        DeliveryStatus.sent => (Icons.check_rounded, 'ส่งถึงอุปกรณ์', AppColors.success),
        DeliveryStatus.synced => (Icons.done_all_rounded, 'ซิงก์แล้ว', AppColors.info),
      };

  Widget _content() {
    switch (m.kind) {
      case MessageKind.text:
        return Text(m.text ?? '', style: const TextStyle(fontSize: 16));
      case MessageKind.image:
        return const _MediaLine(Icons.image_outlined, 'รูปภาพ');
      case MessageKind.video:
        return const _MediaLine(Icons.videocam_outlined, 'วิดีโอ');
      case MessageKind.voice:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _MediaLine(Icons.play_circle_outline_rounded,
                'ข้อความเสียง 0:${(m.durationSeconds ?? 0).toString().padLeft(2, '0')}'),
            if (m.text != null)
              Text('คำถอดความ: ${m.text}',
                  style: const TextStyle(color: AppColors.muted, fontSize: 14)),
          ],
        );
      case MessageKind.location:
        return const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _MediaLine(Icons.location_on_outlined, 'ตำแหน่งล่าสุด'),
            SizedBox(height: 3),
            Text('แตะเพื่อดูตำแหน่งที่บันทึกไว้',
                style: TextStyle(color: AppColors.muted, fontSize: 13)),
          ],
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final (icon, label, color) = _status;
    return Align(
      alignment: m.isMine ? Alignment.centerRight : Alignment.centerLeft,
      child: Semantics(
        label: '${m.isMine ? 'คุณ' : m.senderName}, $label',
        child: Container(
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
          constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * .78),
          decoration: BoxDecoration(
            color: m.isMine ? const Color(0xFF163C54) : AppColors.surface,
            borderRadius: BorderRadius.only(
              topLeft: const Radius.circular(16),
              topRight: const Radius.circular(16),
              bottomLeft: Radius.circular(m.isMine ? 16 : 4),
              bottomRight: Radius.circular(m.isMine ? 4 : 16),
            ),
            border: Border.all(color: AppColors.border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Align(alignment: Alignment.centerLeft, child: _content()),
              const SizedBox(height: 6),
              Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(icon, size: 15, color: color),
                const SizedBox(width: 4),
                Text(label, style: TextStyle(color: color, fontSize: 12)),
              ]),
            ],
          ),
        ),
      ),
    );
  }
}

class _MediaLine extends StatelessWidget {
  const _MediaLine(this.icon, this.text);
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) => Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 24),
        const SizedBox(width: 8),
        Flexible(child: Text(text, style: const TextStyle(fontSize: 16))),
      ]);
}
