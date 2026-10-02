import 'package:flutter/material.dart';

import '../../app/theme.dart';
import '../../models/user.dart';

class RescueScreen extends StatefulWidget {
  const RescueScreen({
    super.key,
    required this.me,
  });

  final AppUser me;

  @override
  State<RescueScreen> createState() => _RescueScreenState();
}

class _RescueScreenState extends State<RescueScreen> {
  bool _active = false;

  @override
  Widget build(BuildContext context) {
    final allowed = widget.me.isVerifiedRescuer;

    return Scaffold(
      appBar: AppBar(
        title: const Text('RESCUE MODE'),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Icon(
              Icons.health_and_safety_outlined,
              size: 72,
              color: allowed ? AppColors.info : AppColors.muted,
            ),
            const SizedBox(height: 16),
            Text(
              allowed
                  ? 'หน่วยกู้ภัยที่ผ่านการยืนยัน'
                  : 'ไม่มีสิทธิ์ RESCUE MODE',
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              allowed
                  ? 'ฐานข้อมูลตรวจ role = rescuer/admin ก่อนอนุญาตให้เปิดโหมดนี้'
                  : 'บัญชีผู้ใช้ทั่วไปไม่สามารถเปิดสถานะหน่วยกู้ภัยได้',
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: AppColors.muted,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 24),
            if (allowed) ...[
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: AppColors.border),
                ),
                child: Row(
                  children: [
                    Icon(
                      _active
                          ? Icons.radio_button_checked_rounded
                          : Icons.radio_button_off_rounded,
                      color: _active
                          ? AppColors.error
                          : AppColors.muted,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        _active
                            ? 'RESCUE MODE ACTIVE'
                            : 'RESCUE MODE ยังไม่เปิด',
                        style: const TextStyle(
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor:
                      _active ? AppColors.error : AppColors.info,
                ),
                onPressed: () {
                  setState(() => _active = !_active);
                },
                icon: Icon(
                  _active
                      ? Icons.stop_circle_outlined
                      : Icons.play_circle_outline_rounded,
                ),
                label: Text(
                  _active
                      ? 'ปิด RESCUE MODE'
                      : 'เปิด RESCUE MODE',
                ),
              ),
              const SizedBox(height: 18),
              const Text(
                'ขั้น Vertical Slice ถัดไปจะเชื่อมปุ่มนี้กับ '
                'Local DB → Supabase rescue_sessions และ Nearby broadcasting',
                style: TextStyle(
                  color: AppColors.muted,
                  height: 1.45,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
