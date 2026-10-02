import 'package:flutter/material.dart';

import '../../app/theme.dart';
import '../../models/user.dart';

class NearbyScreen extends StatelessWidget {
  const NearbyScreen({
    super.key,
    required this.me,
  });

  final AppUser me;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 30),
        children: [
          const Text(
            'อุปกรณ์ใกล้เคียง',
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'Nearby / Relay จะค้นหาอุปกรณ์และส่งต่อข้อมูลแบบ Offline Mesh',
            style: TextStyle(
              color: AppColors.muted,
              height: 1.45,
            ),
          ),
          const SizedBox(height: 18),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppColors.border),
            ),
            child: const Row(
              children: [
                Icon(
                  Icons.radar_rounded,
                  color: AppColors.info,
                  size: 30,
                ),
                SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'กำลังรอเชื่อม MultipeerConnectivity\n'
                    'Week 3–4: peer discovery + message UUID + TTL',
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          const _PeerPreview(
            icon: Icons.warning_amber_rounded,
            title: 'SOS',
            subtitle: 'ตัวอย่างอุปกรณ์สถานะฉุกเฉิน • 25 ม.',
          ),
          const SizedBox(height: 10),
          const _PeerPreview(
            icon: Icons.health_and_safety_outlined,
            title: 'RESCUE',
            subtitle: 'ตัวอย่างหน่วยกู้ภัยที่ตรวจสอบแล้ว • 80 ม.',
          ),
          const SizedBox(height: 10),
          const _PeerPreview(
            icon: Icons.person_outline_rounded,
            title: 'USER',
            subtitle: 'ตัวอย่างผู้ใช้ทั่วไป • 120 ม.',
          ),
        ],
      ),
    );
  }
}

class _PeerPreview extends StatelessWidget {
  const _PeerPreview({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          Icon(icon, color: AppColors.info),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontWeight: FontWeight.w900,
                  ),
                ),
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
    );
  }
}
