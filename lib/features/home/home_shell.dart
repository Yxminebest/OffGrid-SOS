import 'package:flutter/material.dart';
import '../../app/theme.dart';
import '../../models/local_identity.dart';
import '../../widgets/app_card.dart';
import '../../widgets/status_badge.dart';
import '../chat/chat_screen.dart';
import '../nearby/nearby_screen.dart';
import '../profile/profile_screen.dart';
import '../rescue/rescue_screen.dart';
import '../sos/sos_screen.dart';

class HomeShell extends StatefulWidget {
  const HomeShell({
    super.key,
    required this.me,
    required this.onLogout,
  });

  final LocalIdentity me;
  final VoidCallback onLogout;

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _tab = 0;

  void _goTo(int index) => setState(() => _tab = index);

  @override
  Widget build(BuildContext context) {
    final pages = [
      HomeScreen(me: widget.me, onOpenNearby: () => _goTo(1)),
      NearbyScreen(me: widget.me),
      ChatHubScreen(me: widget.me),
      ProfileScreen(me: widget.me, onLogout: widget.onLogout),
    ];

    return Scaffold(
      body: IndexedStack(index: _tab, children: pages),
      bottomNavigationBar: NavigationBar(
        height: 72,
        backgroundColor: AppColors.surface,
        indicatorColor: AppColors.surfaceSoft,
        selectedIndex: _tab,
        onDestinationSelected: _goTo,
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home_rounded, color: AppColors.sos),
            label: 'หน้าหลัก',
          ),
          NavigationDestination(
            icon: Icon(Icons.radar_rounded),
            selectedIcon: Icon(Icons.radar_rounded, color: AppColors.sos),
            label: 'ใกล้ฉัน',
          ),
          NavigationDestination(
            icon: Icon(Icons.chat_bubble_outline_rounded),
            selectedIcon: Icon(Icons.chat_bubble_rounded, color: AppColors.sos),
            label: 'แชท',
          ),
          NavigationDestination(
            icon: Icon(Icons.person_outline_rounded),
            selectedIcon: Icon(Icons.person_rounded, color: AppColors.sos),
            label: 'โปรไฟล์',
          ),
        ],
      ),
    );
  }
}

class HomeScreen extends StatelessWidget {
  const HomeScreen({
    super.key,
    required this.me,
    required this.onOpenNearby,
  });

  final LocalIdentity me;
  final VoidCallback onOpenNearby;

  void _openChat(BuildContext context, NearbyPeer peer) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ChatScreen(
          me: me,
          peerName: peer.name,
          peerKind: peer.kind,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final sosPeer = demoPeers.firstWhere((p) => p.kind == PeerKind.sos);
    final rescuePeer = demoPeers.firstWhere((p) => p.kind == PeerKind.rescue);

    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 18, 16, 110),
          children: [
            Row(
              children: [
                const Expanded(
                  child: Text('RescueLink',
                      style: TextStyle(fontSize: 27, fontWeight: FontWeight.w900)),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: AppColors.pending.withOpacity(.10),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: AppColors.pending),
                  ),
                  child: const Text(
                    '⚠ OFFLINE',
                    style: TextStyle(
                      color: AppColors.pending,
                      fontSize: 12,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            const AppCard(
              borderColor: AppColors.pending,
              child: Row(
                children: [
                  Icon(Icons.warning_amber_rounded,
                      color: AppColors.pending, size: 26),
                  SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('ไม่มีอินเทอร์เน็ต',
                            style: TextStyle(fontWeight: FontWeight.w900)),
                        Text('Nearby ยังใช้งานได้',
                            style: TextStyle(color: AppColors.muted)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18),
            Row(
              children: [
                const Expanded(
                  child: Text('อุปกรณ์ใกล้เคียง',
                      style: TextStyle(fontSize: 19, fontWeight: FontWeight.w900)),
                ),
                TextButton(onPressed: onOpenNearby, child: const Text('ดูทั้งหมด')),
              ],
            ),
            const SizedBox(height: 8),
            StatusBadge(
              kind: sosPeer.kind,
              name: sosPeer.name,
              detail: '${sosPeer.meters} ม.',
              description: 'ต้องการความช่วยเหลือ',
              actionLabel: 'เปิดการสนทนา',
              onTap: () => _openChat(context, sosPeer),
            ),
            const SizedBox(height: 10),
            StatusBadge(
              kind: rescuePeer.kind,
              name: rescuePeer.name,
              detail: '${rescuePeer.meters} ม.',
              description: 'Rescue Team',
              onTap: () => _openChat(context, rescuePeer),
            ),
            const SizedBox(height: 20),
            Center(
              child: Semantics(
                button: true,
                label: 'SOS ขอความช่วยเหลือ',
                hint: 'เปิดหน้ายืนยัน SOS ก่อนเริ่มสถานะฉุกเฉิน',
                child: SizedBox(
                  width: 146,
                  height: 146,
                  child: FilledButton(
                    style: FilledButton.styleFrom(
                      padding: EdgeInsets.zero,
                      backgroundColor: AppColors.sos,
                      shape: const CircleBorder(),
                    ),
                    onPressed: () => Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => SosConfirmScreen(me: me)),
                    ),
                    child: const Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.warning_amber_rounded, size: 34),
                        SizedBox(height: 3),
                        Text('SOS',
                            style: TextStyle(fontSize: 27, fontWeight: FontWeight.w900)),
                        Text('ขอความช่วยเหลือ',
                            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'แตะ SOS เพื่อไปหน้ายืนยันก่อนเปิดจริง',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.muted, fontSize: 12),
            ),
            const SizedBox(height: 14),
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.info,
                side: const BorderSide(color: AppColors.rescue),
              ),
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => RescueConfirmScreen(me: me)),
              ),
              icon: const Icon(Icons.health_and_safety_outlined),
              label: const Text('เปิด RESCUE MODE'),
            ),
          ],
        ),
      ),
    );
  }
}
