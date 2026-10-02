import 'dart:async';

import 'package:flutter/material.dart';

import '../../app/theme.dart';
import '../../models/user.dart';
import '../../services/sync_service.dart';
import '../auth/rescue_verification_screen.dart';
import '../chat/chat_screen.dart';
import '../nearby/nearby_screen.dart';
import '../profile/profile_screen.dart';
import '../rescue/rescue_screen.dart';
import '../sos/sos_screen.dart';

class HomeShell extends StatefulWidget {
  const HomeShell({super.key, required this.me, required this.onLogout});

  final AppUser me;
  final Future<void> Function() onLogout;

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _index = 0;

  @override
  void initState() {
    super.initState();
    unawaited(SyncService.instance.start());
  }

  @override
  void dispose() {
    unawaited(SyncService.instance.stop());
    super.dispose();
  }

  Future<void> _openSos() async {
    await Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => SosScreen(me: widget.me)));
  }

  Future<void> _openRescue() async {
    if (!widget.me.isMember) {
      _notice('ต้องสมัครสมาชิกก่อนใช้งาน RESCUE MODE');
      return;
    }

    if (!widget.me.isVerifiedRescuer) {
      final openVerification = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('ยังไม่มีสิทธิ์ RESCUE MODE'),
          content: const Text(
            'RESCUE MODE ใช้ได้เฉพาะบัญชีหน่วยกู้ภัยที่ผ่านการตรวจสอบจาก Admin เท่านั้น',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('ปิด'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('ยื่นคำขอยืนยัน'),
            ),
          ],
        ),
      );

      if (!mounted || openVerification != true) return;

      await Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const RescueVerificationScreen()),
      );
      return;
    }

    await Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => RescueScreen(me: widget.me)));
  }

  void _notice(String text) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  @override
  Widget build(BuildContext context) {
    final pages = <Widget>[
      _HomeDashboard(
        me: widget.me,
        onSos: _openSos,
        onRescue: _openRescue,
        onNearby: () => setState(() => _index = 1),
        onChat: () => setState(() => _index = 2),
      ),
      NearbyScreen(me: widget.me),
      ChatScreen(me: widget.me),
      ProfileScreen(me: widget.me, onLogout: widget.onLogout),
    ];

    return Scaffold(
      body: IndexedStack(index: _index, children: pages),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (value) {
          setState(() => _index = value);
        },
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home_rounded),
            label: 'หน้าหลัก',
          ),
          NavigationDestination(
            icon: Icon(Icons.radar_outlined),
            selectedIcon: Icon(Icons.radar_rounded),
            label: 'ใกล้เคียง',
          ),
          NavigationDestination(
            icon: Icon(Icons.chat_bubble_outline_rounded),
            selectedIcon: Icon(Icons.chat_bubble_rounded),
            label: 'แชท',
          ),
          NavigationDestination(
            icon: Icon(Icons.person_outline_rounded),
            selectedIcon: Icon(Icons.person_rounded),
            label: 'โปรไฟล์',
          ),
        ],
      ),
    );
  }
}

class _HomeDashboard extends StatelessWidget {
  const _HomeDashboard({
    required this.me,
    required this.onSos,
    required this.onRescue,
    required this.onNearby,
    required this.onChat,
  });

  final AppUser me;
  final VoidCallback onSos;
  final VoidCallback onRescue;
  final VoidCallback onNearby;
  final VoidCallback onChat;

  @override
  Widget build(BuildContext context) {
    final roleLabel = switch (me.role) {
      AppRole.admin => 'ADMIN',
      AppRole.rescuer => 'RESCUE',
      AppRole.user => 'USER',
      AppRole.guest => 'GUEST',
    };

    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 22, 20, 30),
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  'offgrid-sos',
                  style: TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.w900,
                    letterSpacing: -1,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: AppColors.border),
                ),
                child: Text(
                  roleLabel,
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 11,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(me.fullName, style: const TextStyle(color: AppColors.muted)),
          const SizedBox(height: 18),
          ValueListenableBuilder<SyncSnapshot>(
            valueListenable: SyncService.instance.status,
            builder: (context, sync, _) {
              final icon = switch (sync.activity) {
                SyncActivity.offline => Icons.cloud_off_outlined,
                SyncActivity.syncing => Icons.sync_rounded,
                SyncActivity.error => Icons.sync_problem_rounded,
                _ => Icons.offline_bolt_outlined,
              };

              final color = sync.activity == SyncActivity.error
                  ? AppColors.error
                  : AppColors.info;

              return Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AppColors.border),
                ),
                child: Row(
                  children: [
                    Icon(icon, color: color),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'OFF-GRID READY • Local-first',
                            style: TextStyle(fontWeight: FontWeight.w800),
                          ),
                          Text(
                            sync.lastMessage ?? 'Local DB พร้อมใช้งาน',
                            style: const TextStyle(
                              color: AppColors.muted,
                              fontSize: 11,
                            ),
                          ),
                          if (sync.pendingCount > 0)
                            Text(
                              'รอซิงก์ ${sync.pendingCount} รายการ',
                              style: TextStyle(
                                color: color,
                                fontSize: 11,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                        ],
                      ),
                    ),
                    IconButton(
                      tooltip: 'Retry Sync',
                      onPressed: sync.isBusy
                          ? null
                          : SyncService.instance.retryAll,
                      icon: const Icon(Icons.refresh_rounded),
                    ),
                  ],
                ),
              );
            },
          ),
          const SizedBox(height: 18),
          _FeatureCard(
            icon: Icons.warning_amber_rounded,
            title: 'SOS',
            subtitle: 'CRUD Local DB + GPS + Supabase Sync',
            accent: AppColors.error,
            onTap: onSos,
          ),
          const SizedBox(height: 10),
          _FeatureCard(
            icon: Icons.health_and_safety_outlined,
            title: 'RESCUE',
            subtitle: me.isVerifiedRescuer
                ? 'เปิดโหมดหน่วยกู้ภัย'
                : 'ต้องผ่านการตรวจสอบสิทธิ์ก่อนใช้งาน',
            accent: AppColors.info,
            onTap: onRescue,
          ),
          const SizedBox(height: 10),
          _FeatureCard(
            icon: Icons.radar_rounded,
            title: 'Nearby / Relay',
            subtitle: 'โครง UI พร้อมต่อ Mesh ใน Week 4',
            accent: AppColors.info,
            onTap: onNearby,
          ),
          const SizedBox(height: 10),
          _FeatureCard(
            icon: Icons.chat_bubble_outline_rounded,
            title: 'Chat',
            subtitle: 'Text CRUD • Local DB → Supabase',
            accent: AppColors.info,
            onTap: onChat,
          ),
          const SizedBox(height: 28),
          Center(
            child: SizedBox(
              width: 154,
              height: 154,
              child: FilledButton(
                style: FilledButton.styleFrom(
                  shape: const CircleBorder(),
                  backgroundColor: AppColors.error,
                ),
                onPressed: onSos,
                child: const Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.warning_amber_rounded,
                      size: 34,
                      color: Colors.white,
                    ),
                    SizedBox(height: 6),
                    Text(
                      'SOS',
                      style: TextStyle(
                        fontSize: 27,
                        fontWeight: FontWeight.w900,
                        color: Colors.white,
                      ),
                    ),
                    Text(
                      'Local-first',
                      style: TextStyle(fontSize: 11, color: Colors.white),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _FeatureCard extends StatelessWidget {
  const _FeatureCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.accent,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final Color accent;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.all(15),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.border),
          ),
          child: Row(
            children: [
              Icon(icon, color: accent, size: 30),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        color: AppColors.muted,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right_rounded),
            ],
          ),
        ),
      ),
    );
  }
}
