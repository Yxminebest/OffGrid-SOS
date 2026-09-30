import 'package:flutter/material.dart';
import '../../app/theme.dart';
import '../../models/local_identity.dart';
import '../../widgets/app_card.dart';

class ProfileScreen extends StatelessWidget {
  const ProfileScreen({
    super.key,
    required this.me,
    required this.onLogout,
  });

  final LocalIdentity me;
  final VoidCallback onLogout;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('โปรไฟล์')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 110),
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
          Text(
            me.fullName,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w900),
          ),
          if (me.email != null)
            Text(me.email!,
                textAlign: TextAlign.center,
                style: const TextStyle(color: AppColors.muted)),
          const SizedBox(height: 18),
          const AppCard(
            child: Row(
              children: [
                Icon(Icons.radar_rounded, color: AppColors.success),
                SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('สถานะอุปกรณ์',
                          style: TextStyle(fontWeight: FontWeight.w800)),
                      Text('✓ เชื่อมต่อ Nearby พร้อมใช้งาน',
                          style: TextStyle(color: AppColors.muted)),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          _menu(Icons.notifications_none_rounded, 'การแจ้งเตือน'),
          _menu(Icons.location_on_outlined, 'ตำแหน่ง'),
          _menu(Icons.lock_outline_rounded, 'ความเป็นส่วนตัว'),
          _menu(Icons.settings_outlined, 'การตั้งค่า'),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.error,
              side: const BorderSide(color: AppColors.error),
            ),
            onPressed: onLogout,
            icon: const Icon(Icons.logout_rounded),
            label: const Text('ออกจากระบบ'),
          ),
        ],
      ),
    );
  }

  Widget _menu(IconData icon, String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: AppCard(
        padding: EdgeInsets.zero,
        child: ListTile(
          minTileHeight: 62,
          leading: Icon(icon, color: AppColors.info),
          title: Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
          trailing: const Icon(Icons.chevron_right_rounded, color: AppColors.muted),
          onTap: () {},
        ),
      ),
    );
  }
}
