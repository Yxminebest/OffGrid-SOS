import '../app/app_palette.dart';
import '../models/user.dart';
import '../features/chat/unified_conversation_screen.dart';
import '../services/unified_chat_service.dart';
import 'package:flutter/material.dart';
import '../services/nearby_mesh_service.dart';

class SosResponsePanel extends StatefulWidget {
  const SosResponsePanel({
    super.key,
    required this.mesh,
    required this.owner,
    required this.caseOrigin,
    required this.caseId,
    this.sos,
    this.revision = 0,
    this.me,
  });
  final NearbyMeshService mesh;
  final String owner, caseOrigin, caseId;
  final int revision;
  final AppUser? me;
  final Map<String, dynamic>? sos;
  @override
  State<SosResponsePanel> createState() => _SosResponsePanelState();
}

class _SosResponsePanelState extends State<SosResponsePanel> {
  bool busy = false;
  late Stream<List<Map<String, Object?>>> responses;
  void bind() {
    responses = widget.mesh.sosResponses.watch(
      widget.owner,
      widget.caseOrigin,
      widget.caseId,
    );
  }

  @override
  void initState() {
    super.initState();
    bind();
  }

  @override
  void didUpdateWidget(covariant SosResponsePanel old) {
    super.didUpdateWidget(old);
    if (old.owner != widget.owner ||
        old.caseOrigin != widget.caseOrigin ||
        old.caseId != widget.caseId ||
        old.mesh != widget.mesh) {
      bind();
    }
  }

  static const labels = {
    'accepted': 'รับเคสแล้ว',
    'helping': 'กำลังช่วยเหลือ',
    'completed': 'แจ้งว่าช่วยเหลือเสร็จแล้ว',
    'released': 'ยกเลิกรับเคส',
  };
  Future<void> update(String state) async {
    if (busy) return;
    if (state == 'completed' || state == 'released') {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(
            state == 'completed'
                ? 'ยืนยันแจ้งช่วยเหลือเสร็จ?'
                : 'ยืนยันยกเลิกรับเคส?',
          ),
          content: state == 'completed'
              ? null
              : const Text('ผู้แจ้งจะได้รับแจ้งว่าคุณยกเลิกรับเคส'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('กลับ'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('ยืนยัน'),
            ),
          ],
        ),
      );
      if (confirmed != true || !mounted) return;
    }
    setState(() => busy = true);
    try {
      await widget.mesh.updateRescueCase(widget.sos!, state);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('$e')));
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  String _time(Object? raw) {
    final value = DateTime.tryParse(raw?.toString() ?? '')?.toLocal();
    if (value == null) return '';
    return ' · ${value.day}/${value.month} ${value.hour.toString().padLeft(2, '0')}:${value.minute.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(
    BuildContext context,
  ) => StreamBuilder<List<Map<String, Object?>>>(
    stream: responses,
    builder: (context, snapshot) {
      final rows = snapshot.data ?? [];
      final receipts = rows
          .where(
            (r) =>
                r['outgoing'] == false &&
                ((r['envelope'] as Map)['data'] as Map)['category'] ==
                    'receipt' &&
                // Ignore receipts for an older edit of the same SOS case.
                (((r['envelope'] as Map)['data'] as Map)['revision'] as int) >=
                    widget.revision,
          )
          .length;
      final progress = rows
          .where(
            (r) =>
                ((r['envelope'] as Map)['data'] as Map)['category'] ==
                'progress',
          )
          .toList();
      final own = progress.where((r) => r['outgoing'] == true).firstOrNull;
      final state = ((own?['envelope'] as Map?)?['data'] as Map?)?['state'];
      final mine = widget.caseOrigin == widget.mesh.deviceId;
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (mine)
                Text(
                  receipts == 0
                      ? 'รอเครื่องใกล้เคียงยืนยันรับ SOS'
                      : 'ได้รับ SOS แล้ว $receipts เครื่อง',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              for (final row in progress)
                Builder(
                  builder: (_) {
                    final env = row['envelope'] as Map;
                    final body = env['data'] as Map;
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          child: Text(
                            '${env['sender'] ?? 'หน่วยกู้ภัย'} · ${labels[body['state']] ?? ''}'
                            '${row['outgoing'] == true ? (row['delivery'] == 'delivered'
                                      ? ' · ผู้แจ้งได้รับแล้ว'
                                      : row['delivery'] == 'cancelled'
                                      ? ' · SOS ปิดแล้ว'
                                      : ' · ค้างส่ง') : ''}'
                            '${_time(env['at'])}',
                            style: const TextStyle(
                              color: AppColors.rescueStrong,
                            ),
                          ),
                        ),
                        if (row['outgoing'] == false && widget.me != null)
                          TextButton.icon(
                            onPressed: () => Navigator.push(
                              context,
                              MaterialPageRoute<void>(
                                builder: (_) => UnifiedConversationScreen(
                                  me: widget.me!,
                                  contact: ChatContact(
                                    name:
                                        env['sender']?.toString() ??
                                        'หน่วยกู้ภัย',
                                    device: env['origin'] as String,
                                  ),
                                  caseId: widget.caseId,
                                ),
                              ),
                            ),
                            icon: const Icon(Icons.chat_bubble_outline),
                            label: const Text('สนทนากับผู้รับเคส'),
                          ),
                      ],
                    );
                  },
                ),
              if (!mine &&
                  widget.sos != null &&
                  widget.mesh.rescueActive &&
                  widget.mesh.hasRescueAttestation)
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  children: [
                    if (state == null || state == 'released')
                      FilledButton.icon(
                        onPressed: busy ? null : () => update('accepted'),
                        icon: const Icon(Icons.health_and_safety),
                        label: const Text('รับเคสนี้'),
                      ),
                    if (state == 'accepted')
                      FilledButton(
                        onPressed: busy ? null : () => update('helping'),
                        child: const Text('กำลังช่วยเหลือ'),
                      ),
                    if (state == 'helping')
                      FilledButton(
                        onPressed: busy ? null : () => update('completed'),
                        child: const Text('แจ้งช่วยเหลือเสร็จ'),
                      ),
                    if (state == 'accepted' || state == 'helping')
                      TextButton(
                        onPressed: busy ? null : () => update('released'),
                        child: const Text('ยกเลิกรับเคส'),
                      ),
                  ],
                ),
              if (snapshot.hasError)
                const Text('อ่านสถานะรับเคสไม่ได้ ลองเปิดหน้านี้อีกครั้ง'),
            ],
          ),
        ),
      );
    },
  );
}
