import 'package:flutter/material.dart';

import '../../app/theme.dart';
import '../../models/user.dart';
import '../../services/auth_service.dart';

class GuestScreen extends StatefulWidget {
  const GuestScreen({
    super.key,
    required this.onDone,
  });

  final void Function(AppUser identity) onDone;

  @override
  State<GuestScreen> createState() => _GuestScreenState();
}

class _GuestScreenState extends State<GuestScreen> {
  final _first = TextEditingController();
  final _last = TextEditingController();

  bool _busy = false;

  @override
  void dispose() {
    _first.dispose();
    _last.dispose();
    super.dispose();
  }

  Future<void> _start() async {
    if (_busy) return;

    setState(() => _busy = true);

    try {
      final user = await AuthService.createGuest(
        _first.text,
        _last.text,
      );

      if (!mounted) return;
      widget.onDone(user);
    } on AuthServiceException catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: AppColors.error,
          content: Text(e.message),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'ใช้งานแบบไม่เป็นสมาชิก',
          style: TextStyle(fontWeight: FontWeight.w900),
        ),
      ),
      body: SafeArea(
        child: ListView(
          keyboardDismissBehavior:
              ScrollViewKeyboardDismissBehavior.onDrag,
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
          children: [
            const Icon(
              Icons.person_outline_rounded,
              size: 66,
              color: AppColors.info,
            ),
            const SizedBox(height: 16),
            const Text(
              'เริ่มใช้งานแบบ Offline',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'ข้อมูลตัวตนจะถูกเก็บในอุปกรณ์ '
              'และจะไม่สร้างบัญชีบน Supabase',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: AppColors.muted,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 28),
            TextField(
              controller: _first,
              textInputAction: TextInputAction.next,
              decoration: const InputDecoration(
                labelText: 'ชื่อจริง *',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _last,
              textInputAction: TextInputAction.done,
              onSubmitted: (_) {
                if (!_busy) _start();
              },
              decoration: const InputDecoration(
                labelText: 'นามสกุล *',
              ),
            ),
            const SizedBox(height: 22),
            SizedBox(
              height: 52,
              child: OutlinedButton.icon(
                onPressed: _busy ? null : _start,
                icon: const Icon(Icons.arrow_forward_rounded),
                label: _busy
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.5,
                        ),
                      )
                    : const Text(
                        'เริ่มใช้งานแบบไม่เป็นสมาชิก',
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                        ),
                      ),
              ),
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppColors.info.withValues(alpha: .08),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: AppColors.info.withValues(alpha: .25),
                ),
              ),
              child: const Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.info_outline_rounded,
                    color: AppColors.info,
                  ),
                  SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Guest ไม่มี Cloud role และไม่ถือว่าเป็นหน่วยกู้ภัยที่ผ่านการยืนยัน '
                      'สามารถสมัครสมาชิกภายหลังได้',
                      style: TextStyle(
                        color: AppColors.muted,
                        height: 1.45,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
