import 'package:flutter/material.dart';
import '../../app/theme.dart';
import '../../models/local_identity.dart';
import '../../widgets/app_card.dart';
import '../../widgets/status_badge.dart';
import '../chat/chat_screen.dart';
import '../nearby/nearby_screen.dart';
import '../profile/profile_screen.dart';
import '../sos/sos_screen.dart';

class HomeShell extends StatefulWidget {
  const HomeShell({super.key, required this.me});
  final LocalIdentity me;

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
      ProfileScreen(me: widget.me),
    ];

    return Scaffold(
      body: IndexedStack(index: _tab, children: pages),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: _goTo,
        destinations: const [
          NavigationDestination(
              icon: Icon(Icons.home_outlined),
              selectedIcon: Icon(Icons.home_rounded),
              label: 'หน้าหลัก'),
          NavigationDestination(icon: Icon(Icons.radar_rounded), label: 'ใกล้ฉัน'),
          NavigationDestination(
              icon: Icon(Icons.chat_bubble_outline_rounded), label: 'แชท'),
          NavigationDestination(
              icon: Icon(Icons.person_outline_rounded), label: 'โปรไฟล์'),
        ],
      ),
    );
  }
}

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key, required this.me, required this.onOpenNearby});
  final LocalIdentity me;
  final VoidCallback onOpenNearby;

  @override
  Widget build(BuildContext context) {
    final sosPeer = demoPeers.firstWhere((e) => e.kind == PeerKind.sos);
    final rescuePeer = demoPeers.firstWhere((e) => e.kind == PeerKind.rescue);

    void openChat(NearbyPeer p) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => ChatScreen(
            me: me,
            peerName: p.name,
            peerKind: p.kind,
          ),
        ),
      );
    }

    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 18, 16, 110),
          children: [
            Row(
              children: [
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('RescueLink',
                          style: TextStyle(fontSize: 27, fontWeight: FontWeight.w900)),
                      SizedBox(height: 2),
                      Text('Personal Safety',
                          style: TextStyle(color: AppColors.muted, fontSize: 13)),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
                  decoration: BoxDecoration(
                    color: AppColors.pending.withOpacity(.12),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: AppColors.pending.withOpacity(.6)),
                  ),
                  child: const Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.wifi_off_rounded, size: 16, color: AppColors.pending),
                    SizedBox(width: 6),
                    Text('OFFLINE',
                        style: TextStyle(
                            color: AppColors.pending,
                            fontWeight: FontWeight.w800,
                            fontSize: 12)),
                  ]),
                ),
              ],
            ),
            const SizedBox(height: 18),
            const AppCard(
              borderColor: AppColors.pending,
              child: Row(children: [
                Icon(Icons.warning_amber_rounded,
                    color: AppColors.pending, size: 28),
                SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('ไม่มีอินเทอร์เน็ต',
                          style: TextStyle(fontWeight: FontWeight.w800)),
                      SizedBox(height: 3),
                      Text('Nearby ยังใช้งานได้ผ่านการเชื่อมต่ออุปกรณ์ใกล้เคียง',
                          style: TextStyle(color: AppColors.muted)),
                    ],
                  ),
                ),
              ]),
            ),
            const SizedBox(height: 22),
            Row(children: [
              const Expanded(
                child: Text('อุปกรณ์ใกล้เคียง',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
              ),
              TextButton(onPressed: onOpenNearby, child: const Text('ดูทั้งหมด')),
            ]),
            const SizedBox(height: 8),
            StatusBadge(
              kind: sosPeer.kind,
              name: sosPeer.name,
              detail: '${sosPeer.meters} เมตร',
              actionLabel: 'เปิดการสนทนา',
              onTap: () => openChat(sosPeer),
            ),
            const SizedBox(height: 12),
            StatusBadge(
              kind: rescuePeer.kind,
              name: rescuePeer.name,
              detail: '${rescuePeer.meters} เมตร',
              onTap: () => openChat(rescuePeer),
            ),
            const SizedBox(height: 26),
            Semantics(
              button: true,
              label: 'SOS ขอความช่วยเหลือ',
              hint: 'แตะสองครั้งเพื่อเปิดหน้ายืนยัน SOS',
              child: SizedBox(
                height: 148,
                child: FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.sos,
                    foregroundColor: AppColors.text,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(26)),
                  ),
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const SosScreen()),
                  ),
                  child: const Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.warning_amber_rounded, size: 42),
                      SizedBox(height: 6),
                      Text('SOS',
                          style: TextStyle(fontSize: 30, fontWeight: FontWeight.w900)),
                      Text('ขอความช่วยเหลือ',
                          style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),
            const AppCard(
              child: Row(children: [
                Icon(Icons.location_on_outlined, color: AppColors.info, size: 28),
                SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('ตำแหน่งล่าสุด',
                          style: TextStyle(fontWeight: FontWeight.w700)),
                      Text('บันทึกไว้เมื่อ 20:42 น.',
                          style: TextStyle(color: AppColors.muted)),
                    ],
                  ),
                ),
                Text('ดูตำแหน่ง',
                    style: TextStyle(color: AppColors.info, fontWeight: FontWeight.w700)),
              ]),
            ),
          ],
        ),
      ),
    );
  }
}
