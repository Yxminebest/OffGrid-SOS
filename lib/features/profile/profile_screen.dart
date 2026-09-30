import 'package:flutter/material.dart';
import '../../app/theme.dart';
import '../../models/local_identity.dart';
import '../../widgets/app_card.dart';
import '../sos/sos_screen.dart';

class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key, required this.me});
  final LocalIdentity me;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('โปรไฟล์')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 110),
        children: [
          const SizedBox(height: 12),
          const Center(
            child: CircleAvatar(
              radius: 44,
              backgroundColor: AppColors.surfaceSoft,
              child: Icon(Icons.person_outline_rounded,
                  size: 48, color: AppColors.text),
            ),
          ),
          const SizedBox(height: 12),
          Text(me.fullName,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800)),
          Text(me.isMember ? 'สมาชิก RescueLink' : 'ใช้งานโดยไม่สมัครสมาชิก',
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppColors.muted)),
          const SizedBox(height: 22),
          const AppCard(
            child: Row(children: [
              Icon(Icons.radar_rounded, color: AppColors.success),
              SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('สถานะอุปกรณ์',
                        style: TextStyle(fontWeight: FontWeight.w700)),
                    Text('✓ เชื่อมต่อ Nearby พร้อมใช้งาน',
                        style: TextStyle(color: AppColors.muted)),
                  ],
                ),
              ),
            ]),
          ),
          const SizedBox(height: 14),
          _menu(context, Icons.health_and_safety_outlined, 'โหมดหน่วยกู้ภัย',
              'ประกาศสถานะ RESCUE ให้เครื่องรอบตัว', () {
            Navigator.push(context,
                MaterialPageRoute(builder: (_) => const RescueModeScreen()));
          }),
          _menu(context, Icons.notifications_none_rounded, 'การแจ้งเตือน',
              'เสียง สั่น และการเตือนฉุกเฉิน', () => _notReady(context)),
          _menu(context, Icons.location_on_outlined, 'ตำแหน่ง',
              'สิทธิ์และตำแหน่งล่าสุด', () => _notReady(context)),
          _menu(context, Icons.lock_outline_rounded, 'ความเป็นส่วนตัว',
              'จัดการข้อมูลและสิทธิ์', () => _notReady(context)),
          _menu(context, Icons.settings_outlined, 'การตั้งค่า',
              'การเข้าถึงและการซิงก์', () => _notReady(context)),
          const SizedBox(height: 12),
          TextButton.icon(
            onPressed: () => _notReady(context),
            icon: const Icon(Icons.logout_rounded, color: AppColors.error),
            label: const Text('ออกจากระบบ',
                style: TextStyle(color: AppColors.error, fontSize: 16)),
          ),
        ],
      ),
    );
  }

  Widget _menu(BuildContext context, IconData icon, String title, String subtitle,
      VoidCallback onTap) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: AppCard(
        padding: EdgeInsets.zero,
        child: ListTile(
          minTileHeight: 68,
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          leading: Icon(icon, color: AppColors.info),
          title: Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
          subtitle: Text(subtitle, style: const TextStyle(color: AppColors.muted)),
          trailing: const Icon(Icons.chevron_right_rounded, color: AppColors.muted),
          onTap: onTap,
        ),
      ),
    );
  }

  void _notReady(BuildContext context) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('ส่วนนี้เตรียม UI ไว้แล้ว และจะเชื่อมฟังก์ชันใน Week 3–4')),
    );
  }
}
