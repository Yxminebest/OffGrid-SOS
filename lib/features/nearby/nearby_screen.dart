import 'package:flutter/material.dart';
import '../../app/theme.dart';
import '../../models/local_identity.dart';
import '../../widgets/status_badge.dart';
import '../chat/chat_screen.dart';

class NearbyPeer {
  const NearbyPeer({
    required this.name,
    required this.kind,
    required this.meters,
    required this.description,
  });

  final String name;
  final PeerKind kind;
  final int meters;
  final String description;
}

const demoPeers = <NearbyPeer>[
  NearbyPeer(
    name: 'Somchai',
    kind: PeerKind.sos,
    meters: 25,
    description: 'ผู้ขอความช่วยเหลือ',
  ),
  NearbyPeer(
    name: 'Rescue Team',
    kind: PeerKind.rescue,
    meters: 80,
    description: 'RESCUE MODE ACTIVE',
  ),
  NearbyPeer(
    name: 'ผู้ใช้ใกล้เคียง',
    kind: PeerKind.normal,
    meters: 120,
    description: 'ผู้ใช้ทั่วไป · พร้อมช่วย Relay',
  ),
];

class NearbyScreen extends StatefulWidget {
  const NearbyScreen({super.key, required this.me});

  final LocalIdentity me;

  @override
  State<NearbyScreen> createState() => _NearbyScreenState();
}

class _NearbyScreenState extends State<NearbyScreen> {
  bool _searching = true;

  void _openChat(NearbyPeer peer) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ChatScreen(
          me: widget.me,
          peerName: peer.name,
          peerKind: peer.kind,
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
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: AppColors.border),
              ),
              child: Row(
                children: [
                  Icon(
                    _searching ? Icons.radar_rounded : Icons.check_circle_outline,
                    color: _searching ? AppColors.info : AppColors.success,
                  ),
                  const SizedBox(width: 9),
                  Text(
                    _searching ? 'กำลังค้นหา...' : 'ค้นหาเสร็จแล้ว',
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            for (final peer in demoPeers) ...[
              StatusBadge(
                kind: peer.kind,
                name: peer.name,
                detail: '${peer.meters} ม.',
                description: peer.description,
                actionLabel: peer.kind == PeerKind.sos ? 'เปิดการสนทนา' : null,
                onTap: () => _openChat(peer),
              ),
              const SizedBox(height: 12),
            ],
            const SizedBox(height: 8),
            const Text(
              'ทุกสถานะใช้ icon + text + สี และแตะอุปกรณ์เพื่อเปิด Chat ได้',
              style: TextStyle(color: AppColors.muted, fontSize: 13),
            ),
            const SizedBox(height: 6),
            const Text(
              'ข้อมูลหน้านี้เป็น Mock Data สำหรับ Week 2; Week 3 จะเชื่อม MultipeerConnectivity จริง',
              style: TextStyle(color: AppColors.muted, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }
}
