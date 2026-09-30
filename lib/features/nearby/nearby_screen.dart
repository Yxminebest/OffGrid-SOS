import 'package:flutter/material.dart';
import '../../app/theme.dart';
import '../../models/local_identity.dart';
import '../../widgets/status_badge.dart';
import '../chat/chat_screen.dart';

class NearbyPeer {
  const NearbyPeer(this.name, this.kind, this.meters);
  final String name;
  final PeerKind kind;
  final int meters;
}

const demoPeers = <NearbyPeer>[
  NearbyPeer('Somchai', PeerKind.sos, 25),
  NearbyPeer('Rescue Team', PeerKind.rescue, 80),
  NearbyPeer('ผู้ใช้ใกล้เคียง', PeerKind.normal, 120),
];

class NearbyScreen extends StatefulWidget {
  const NearbyScreen({super.key, required this.me});
  final LocalIdentity me;

  @override
  State<NearbyScreen> createState() => _NearbyScreenState();
}

class _NearbyScreenState extends State<NearbyScreen> {
  bool _searching = true;

  void _openChat(NearbyPeer p) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ChatScreen(
          me: widget.me,
          peerName: p.name,
          peerKind: p.kind,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('อุปกรณ์ใกล้ฉัน')),
      body: RefreshIndicator(
        onRefresh: () async {
          setState(() => _searching = true);
          await Future<void>.delayed(const Duration(milliseconds: 700));
          if (mounted) setState(() => _searching = false);
        },
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 110),
          children: [
            Row(children: [
              Icon(_searching ? Icons.radar_rounded : Icons.check_circle_outline,
                  color: _searching ? AppColors.info : AppColors.success),
              const SizedBox(width: 8),
              Text(_searching ? 'กำลังค้นหาอุปกรณ์ใกล้เคียง…' : 'ค้นหาเสร็จแล้ว',
                  style: const TextStyle(color: AppColors.muted)),
            ]),
            const SizedBox(height: 16),
            for (final p in demoPeers) ...[
              StatusBadge(
                kind: p.kind,
                name: p.name,
                detail: '${p.meters} เมตร',
                actionLabel: p.kind == PeerKind.sos ? 'เปิดการสนทนา' : null,
                onTap: () => _openChat(p),
              ),
              const SizedBox(height: 12),
            ],
            const SizedBox(height: 8),
            const Text(
              'หมายเหตุ: รายการนี้เป็นข้อมูลจำลองสำหรับ UI — Week 3 จะเชื่อมกับ MultipeerConnectivity',
              style: TextStyle(color: AppColors.muted, fontSize: 13),
            ),
          ],
        ),
      ),
    );
  }
}
