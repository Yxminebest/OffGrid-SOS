import 'package:flutter/material.dart';
import '../../app/theme.dart';
import '../../services/chat_action.dart';
import '../../services/nearby_mesh_service.dart';

class MeshRoomScreen extends StatefulWidget {
  const MeshRoomScreen({super.key, required this.mesh});
  final NearbyMeshService mesh;
  @override
  State<MeshRoomScreen> createState() => _MeshRoomScreenState();
}

class _MeshRoomScreenState extends State<MeshRoomScreen> {
  final input = TextEditingController();
  late final messages = widget.mesh.room.watch(widget.mesh.ownerId!);
  Map<String, dynamic>? reply;
  bool sending = false;

  Future<bool> send(String wire) async {
    try {
      await widget.mesh.sendRoom(wire);
      return true;
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('บันทึกข้อความไม่ได้ กรุณาลองใหม่')),
        );
      }
      return false;
    }
  }

  Future<void> actions(Map<String, dynamic> message) async {
    final own = message['origin'] == widget.mesh.deviceId;
    final choice = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              title: const Text('ตอบกลับ'),
              leading: const Icon(Icons.reply),
              onTap: () => Navigator.pop(ctx, 'reply'),
            ),
            if (own && message['retracted'] != true) ...[
              ListTile(
                title: const Text('แก้ไขข้อความ'),
                leading: const Icon(Icons.edit_outlined),
                onTap: () => Navigator.pop(ctx, 'edit'),
              ),
              ListTile(
                title: const Text('ยกเลิกส่งข้อความ'),
                leading: const Icon(Icons.undo),
                onTap: () => Navigator.pop(ctx, 'retract'),
              ),
            ],
            if (own)
              ListTile(
                title: const Text('ลบข้อความ'),
                leading: const Icon(Icons.delete_outline),
                onTap: () => Navigator.pop(ctx, 'delete'),
              ),
          ],
        ),
      ),
    );
    if (!mounted || choice == null) return;
    final id = message['id'] as String;
    if (choice == 'reply') {
      setState(() => reply = message);
    } else if (choice == 'edit') {
      var edited = message['text'] as String;
      final value = await showDialog<String>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('แก้ไขข้อความ'),
          content: TextFormField(
            initialValue: edited,
            onChanged: (value) => edited = value,
            maxLength: 4000,
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('กลับ'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, edited.trim()),
              child: const Text('บันทึก'),
            ),
          ],
        ),
      );
      if (value != null && value.isNotEmpty) {
        await send(ChatAction.edit(id, value));
      }
    } else {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(
            choice == 'delete'
                ? 'ลบข้อความจากทุกเครื่อง?'
                : 'ยกเลิกส่งข้อความนี้?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('กลับ'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('ยืนยัน'),
            ),
          ],
        ),
      );
      if (confirmed == true) {
        await send(
          choice == 'delete' ? ChatAction.delete(id) : ChatAction.retract(id),
        );
      }
    }
  }

  @override
  void dispose() {
    input.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('ห้องสนทนาส่วนกลาง')),
    body: SafeArea(
      child: Column(
        children: [
          ListenableBuilder(
            listenable: widget.mesh,
            builder: (ctx, _) => Padding(
              padding: const EdgeInsets.all(12),
              child: Text(
                widget.mesh.connected.isEmpty
                    ? 'ยังไม่มีเส้นทาง • เก็บข้อความไว้ส่งเมื่อเชื่อมต่อ'
                    : 'ทุกเครื่องในเครือข่ายอ่านห้องนี้ได้ • ${widget.mesh.reachablePeers.length} เครื่องที่ติดต่อได้',
              ),
            ),
          ),
          Expanded(
            child: StreamBuilder<List<Map<String, dynamic>>>(
              stream: messages,
              builder: (ctx, snapshot) {
                if (snapshot.hasError) {
                  return const Center(
                    child: Text('อ่านประวัติไม่ได้ กรุณาเปิดห้องอีกครั้ง'),
                  );
                }
                final rows = snapshot.data ?? [];
                return ListView.builder(
                  reverse: true,
                  padding: const EdgeInsets.all(16),
                  itemCount: rows.length,
                  itemBuilder: (ctx, i) {
                    final m = rows[rows.length - 1 - i];
                    final own = m['origin'] == widget.mesh.deviceId;
                    final quoted = rows
                        .where((r) => r['id'] == m['replyTo'])
                        .firstOrNull;
                    return Align(
                      alignment: own
                          ? Alignment.centerRight
                          : Alignment.centerLeft,
                      child: GestureDetector(
                        onLongPress: () => actions(m),
                        child: Container(
                          constraints: BoxConstraints(
                            maxWidth: MediaQuery.sizeOf(context).width * .85,
                          ),
                          margin: const EdgeInsets.only(bottom: 10),
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: own
                                ? context.colors.surfaceSoft
                                : context.colors.surface,
                            border: Border.all(color: context.colors.border),
                            borderRadius: BorderRadius.circular(18),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                m['sender'].toString(),
                                style: Theme.of(context).textTheme.labelMedium,
                              ),
                              if (m['replyTo'] != null && m['replyTo'] != '')
                                Padding(
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 8,
                                  ),
                                  child: Text(
                                    'ตอบกลับ: ${quoted?['text'] ?? 'ข้อความเดิม'}',
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              Text(m['text'] as String),
                              if (m['edited'] == true)
                                const Text(
                                  'แก้ไขแล้ว',
                                  style: TextStyle(fontSize: 11),
                                ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
          if (reply != null)
            ListTile(
              title: Text('ตอบกลับ ${reply!['sender']}'),
              trailing: IconButton(
                onPressed: () => setState(() => reply = null),
                icon: const Icon(Icons.close),
              ),
            ),
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: input,
                    minLines: 1,
                    maxLines: 4,
                    maxLength: 4000,
                    decoration: const InputDecoration(
                      hintText: 'ส่งข่าวถึงทุกเครื่อง...',
                      counterText: '',
                    ),
                  ),
                ),
                IconButton.filled(
                  tooltip: 'ส่งข้อความ',
                  icon: const Icon(Icons.send),
                  onPressed: sending
                      ? null
                      : () async {
                          final text = input.text.trim();
                          if (text.isEmpty) return;
                          setState(() => sending = true);
                          final ok = await send(
                            ChatAction.message(
                              text,
                              replyTo: reply?['id'] as String?,
                            ),
                          );
                          if (!mounted) return;
                          setState(() {
                            sending = false;
                            if (ok) {
                              input.clear();
                              reply = null;
                            }
                          });
                        },
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}
