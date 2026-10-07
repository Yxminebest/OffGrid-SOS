import 'dart:async';

import 'package:flutter/material.dart';

import '../../app/theme.dart';
import '../../services/auth_service.dart';

class ForgotPasswordScreen extends StatefulWidget {
  const ForgotPasswordScreen({super.key, this.initialEmail = ''});

  final String initialEmail;

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  late final TextEditingController _email;

  bool _busy = false;
  bool _sent = false;
  int _cooldown = 0;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _email = TextEditingController(text: widget.initialEmail.trim());
  }

  @override
  void dispose() {
    _timer?.cancel();
    _email.dispose();
    super.dispose();
  }

  void _startCooldown() {
    _timer?.cancel();
    setState(() => _cooldown = 60);

    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }

      if (_cooldown <= 1) {
        timer.cancel();
        setState(() => _cooldown = 0);
      } else {
        setState(() => _cooldown -= 1);
      }
    });
  }

  Future<void> _send() async {
    if (_busy || _cooldown > 0) return;

    final email = _email.text.trim();
    if (!AuthService.isValidEmail(email)) {
      _show('กรุณากรอกอีเมลให้ถูกต้อง', error: true);
      return;
    }

    setState(() => _busy = true);

    try {
      await AuthService.sendPasswordResetEmail(email);

      if (!mounted) return;
      setState(() => _sent = true);
      _startCooldown();
    } on AuthServiceException catch (e) {
      _show(e.message, error: true);
    } catch (_) {
      _show('ส่งคำขอรีเซ็ตรหัสผ่านไม่สำเร็จ กรุณาลองอีกครั้ง', error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _show(String message, {bool error = false}) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          backgroundColor: error ? AppColors.error : null,
          content: Text(message),
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('ลืมรหัสผ่าน')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 28, 20, 36),
          children: [
            const Icon(
              Icons.lock_reset_rounded,
              size: 68,
              color: AppColors.info,
            ),
            const SizedBox(height: 18),
            const Text(
              'รีเซ็ตรหัสผ่าน',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 26, fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 10),
            const Text(
              'กรอกอีเมลที่ใช้สมัคร ระบบจะส่งลิงก์สำหรับตั้งรหัสผ่านใหม่ให้',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.muted, height: 1.45),
            ),
            const SizedBox(height: 24),
            TextField(
              controller: _email,
              enabled: !_busy,
              keyboardType: TextInputType.emailAddress,
              textInputAction: TextInputAction.done,
              autofillHints: const [AutofillHints.email],
              onSubmitted: (_) {
                if (!_busy && _cooldown == 0) _send();
              },
              decoration: const InputDecoration(
                labelText: 'อีเมล',
                prefixIcon: Icon(Icons.email_outlined),
              ),
            ),
            const SizedBox(height: 14),
            if (_sent)
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: AppColors.success.withValues(alpha: .10),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: AppColors.success.withValues(alpha: .35),
                  ),
                ),
                child: const Text(
                  'หากอีเมลนี้มีบัญชีอยู่ ระบบจะส่งลิงก์รีเซ็ตรหัสผ่านให้ '
                  'กรุณาตรวจ Inbox และ Spam/Junk ด้วย',
                  style: TextStyle(height: 1.45),
                ),
              ),
            if (_sent) const SizedBox(height: 14),
            FilledButton.icon(
              onPressed: _busy || _cooldown > 0 ? null : _send,
              icon: _busy
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.send_outlined),
              label: Text(
                _cooldown > 0
                    ? 'ส่งอีกครั้งใน $_cooldown วินาที'
                    : _sent
                    ? 'ส่งลิงก์อีกครั้ง'
                    : 'ส่งลิงก์รีเซ็ตรหัสผ่าน',
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              'เพื่อความเป็นส่วนตัว ระบบจะไม่บอกว่าอีเมลนี้มีบัญชีอยู่หรือไม่',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: AppColors.muted,
                fontSize: 12,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 18),
            TextButton.icon(
              onPressed: _busy ? null : () => Navigator.of(context).pop(),
              icon: const Icon(Icons.arrow_back_rounded),
              label: const Text('กลับไปเข้าสู่ระบบ'),
            ),
          ],
        ),
      ),
    );
  }
}
