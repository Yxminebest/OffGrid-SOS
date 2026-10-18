import 'package:flutter/material.dart';
import '../../app/theme.dart';
import '../../services/nearby_mesh_service.dart';
import '../../models/user.dart';
import '../chat/nearby_conversation_screen.dart';

/// Real cases use durable direct chats; debug simulations stay in memory.
class RescueCaseChatScreen extends StatefulWidget {
  const RescueCaseChatScreen({
    super.key,
    required this.me,
    required this.caseId,
    required this.otherDevice,
    required this.title,
  });
  final AppUser me;
  final String caseId;
  final String otherDevice;
  final String title;
  @override
  State<RescueCaseChatScreen> createState() => _RescueCaseChatScreenState();
}

class _RescueCaseChatScreenState extends State<RescueCaseChatScreen> {
  final mesh = NearbyMeshService.instance;
  final input = TextEditingController();
  bool sending = false;
  @override
  void initState() {
    super.initState();
    mesh.addListener(_changed);
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    mesh.removeListener(_changed);
    input.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final text = input.text.trim();
    final demo = mesh.isDemoOrigin(widget.otherDevice);
    if (text.isEmpty || (!demo && mesh.connected.isEmpty) || sending) {
      return;
    }
    setState(() => sending = true);
    try {
      final count = demo
          ? await mesh.sendDemoCaseReply(
              caseId: widget.caseId,
              target: widget.otherDevice,
              text: text,
            )
          : await mesh.sendCaseReply(
              caseId: widget.caseId,
              target: widget.otherDevice,
              text: text,
            );
      if (count == 0) {
        throw StateError('ไม่มีอุปกรณ์ที่เชื่อมต่อ');
      }
      input.clear();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('ส่งข้อความไม่ได้: $e')));
      }
    } finally {
      if (mounted) setState(() => sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final demo = mesh.isDemoOrigin(widget.otherDevice);
    if (!demo) {
      return NearbyConversationScreen(
        me: widget.me,
        peerId: widget.otherDevice,
        name: widget.title,
        caseId: widget.caseId,
      );
    }
    final messages = mesh.inbox
        .where((m) {
          if (m.kind != 'case_chat') {
            return false;
          }
          final body = m.data['data'];
          if (body is! Map || body['caseId'] != widget.caseId) {
            return false;
          }
          final origin = m.data['origin']?.toString();
          final target = body['target']?.toString();
          return (origin == mesh.deviceId && target == widget.otherDevice) ||
              (origin == widget.otherDevice && target == mesh.deviceId);
        })
        .toList()
        .reversed
        .toList();
    return Scaffold(
      appBar: AppBar(title: Text(widget.title)),
      body: SafeArea(
        child: Column(
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              color: context.colors.surface,
              child: Text(
                demo
                    ? 'SIMULATION • ข้อความไม่ส่งออก ไม่เก็บบน Cloud'
                    : mesh.connected.isEmpty
                    ? 'ออฟไลน์: ยังไม่มีอุปกรณ์เชื่อมต่อ ส่งไม่ได้'
                    : 'Nearby: เชื่อมต่อ ${mesh.connected.length} เครื่อง • ข้อความยังไม่บันทึกถาวร',
                style: TextStyle(color: context.colors.muted, fontSize: 12),
              ),
            ),
            Expanded(
              child: messages.isEmpty
                  ? const Center(child: Text('ยังไม่มีข้อความในเคสนี้'))
                  : ListView.builder(
                      padding: const EdgeInsets.all(12),
                      itemCount: messages.length,
                      itemBuilder: (context, i) {
                        final m = messages[i];
                        final mine = m.data['origin'] == mesh.deviceId;
                        final data = m.data['data'] as Map;
                        return Align(
                          alignment: mine
                              ? Alignment.centerRight
                              : Alignment.centerLeft,
                          child: Card(
                            color: mine
                                ? context.colors.surfaceSoft
                                : context.colors.surface,
                            child: Padding(
                              padding: const EdgeInsets.all(12),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    mine
                                        ? 'ฉัน'
                                        : (m.data['sender']?.toString() ??
                                              'ผู้แจ้งเหตุ'),
                                    style: TextStyle(
                                      color: context.colors.info,
                                      fontSize: 12,
                                    ),
                                  ),
                                  Text(data['text']?.toString() ?? ''),
                                ],
                              ),
                            ),
                          ),
                        );
                      },
                    ),
            ),
            Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: input,
                      maxLength: 1000,
                      decoration: const InputDecoration(
                        hintText: 'ส่งข้อความถึงเคสนี้',
                        counterText: '',
                      ),
                    ),
                  ),
                  IconButton.filled(
                    icon: const Icon(Icons.send),
                    onPressed: sending || (!demo && mesh.connected.isEmpty)
                        ? null
                        : _send,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
