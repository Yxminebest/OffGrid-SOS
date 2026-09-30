import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../app/theme.dart';
import '../../models/local_identity.dart';
import '../../widgets/app_card.dart';
import '../nearby/nearby_screen.dart';

class RescueConfirmScreen extends StatelessWidget {
  const RescueConfirmScreen({super.key, required this.me});

  final LocalIdentity me;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('โหมดหน่วยกู้ภัย')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
          children: [
            const SizedBox(height: 16),
            const Center(
              child: Icon(Icons.health_and_safety_outlined,
                  size: 64, color: AppColors.rescue),
            ),
            const SizedBox(height: 14),
            const Text(
              'RESCUE MODE',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 25, fontWeight: FontWeight.w900),
            ),
            const Text(
              'โหมดช่วยเหลือ',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 22),
            const AppCard(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.health_and_safety_outlined, color: AppColors.rescue),
                  SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('การประกาศสถานะ',
                            style: TextStyle(fontWeight: FontWeight.w800)),
                        SizedBox(height: 3),
                        Text('เครื่องอื่นในระยะจะเห็นว่าอุปกรณ์นี้เป็นหน่วยกู้ภัย',
                            style: TextStyle(color: AppColors.muted)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
            const AppCard(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.radar_rounded, color: AppColors.info),
                  SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Nearby / Relay',
                            style: TextStyle(fontWeight: FontWeight.w800)),
                        SizedBox(height: 3),
                        Text('ยังสามารถค้นหา SOS และช่วยส่งต่อข้อความได้',
                            style: TextStyle(color: AppColors.muted)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18),
            FilledButton.icon(
              style: FilledButton.styleFrom(backgroundColor: AppColors.rescue),
              onPressed: () {
                HapticFeedback.mediumImpact();
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => RescueActiveScreen(me: me)),
                );
              },
              icon: const Icon(Icons.health_and_safety_outlined),
              label: const Text('เปิด RESCUE MODE'),
            ),
            const SizedBox(height: 8),
            OutlinedButton(
              onPressed: () => Navigator.maybePop(context),
              child: const Text('ยกเลิก'),
            ),
            const SizedBox(height: 12),
            const Text(
              '○ สถานะ: ยังไม่เปิด',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.muted),
            ),
          ],
        ),
      ),
    );
  }
}

class RescueActiveScreen extends StatelessWidget {
  const RescueActiveScreen({super.key, required this.me});

  final LocalIdentity me;

  void _stop(BuildContext context) {
    HapticFeedback.mediumImpact();
    Navigator.of(context).popUntil((route) => route.isFirst);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 24),
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: AppColors.rescue.withOpacity(.12),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppColors.rescue),
              ),
              child: const Row(
                children: [
                  Icon(Icons.health_and_safety_outlined,
                      color: AppColors.rescue, size: 18),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text('RESCUE MODE ACTIVE',
                        style: TextStyle(
                            color: AppColors.info, fontWeight: FontWeight.w900)),
                  ),
                  Text('LIVE',
                      style: TextStyle(
                          color: AppColors.info, fontWeight: FontWeight.w900)),
                ],
              ),
            ),
            const SizedBox(height: 26),
            Center(
              child: Container(
                width: 108,
                height: 108,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppColors.rescue,
                ),
                child: const Icon(Icons.health_and_safety_outlined,
                    color: AppColors.text, size: 56),
              ),
            ),
            const SizedBox(height: 16),
            const Text('RESCUE ACTIVE',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 25, fontWeight: FontWeight.w900)),
            const Text('กำลังประกาศสถานะหน่วยกู้ภัย',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
            const SizedBox(height: 22),
            const AppCard(
              child: Row(
                children: [
                  Icon(Icons.radar_rounded, color: AppColors.info),
                  SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('อุปกรณ์ใกล้เคียง',
                            style: TextStyle(fontWeight: FontWeight.w800)),
                        Text('พบ 4 เครื่อง · มี SOS 1 รายการ',
                            style: TextStyle(color: AppColors.muted)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
            const AppCard(
              child: Row(
                children: [
                  Icon(Icons.schedule_outlined, color: AppColors.pending),
                  SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('เปิดโหมดเวลา',
                            style: TextStyle(fontWeight: FontWeight.w800)),
                        Text('10:12 น.', style: TextStyle(color: AppColors.muted)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => NearbyScreen(me: me)),
              ),
              icon: const Icon(Icons.warning_amber_rounded, color: AppColors.sos),
              label: const Text('ดู SOS ใกล้ฉัน / เปิดแชท'),
            ),
            const SizedBox(height: 10),
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.info,
                side: const BorderSide(color: AppColors.rescue),
              ),
              onPressed: () => _stop(context),
              icon: const Icon(Icons.stop_circle_outlined),
              label: const Text('หยุด RESCUE MODE'),
            ),
            const SizedBox(height: 12),
            const Text(
              'ใช้ไอคอน + ข้อความ RESCUE เสมอ ไม่สื่อสถานะด้วยสีฟ้าอย่างเดียว',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.muted, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }
}
