import 'package:flutter/material.dart';

import '../../app/theme.dart';
import '../../services/auth_service.dart';
import '../../widgets/password_strength_indicator.dart';

class ResetPasswordScreen extends StatefulWidget {
  const ResetPasswordScreen({
    super.key,
    required this.onDone,
    required this.onCancel,
  });

  final Future<void> Function() onDone;
  final Future<void> Function() onCancel;

  @override
  State<ResetPasswordScreen> createState() => _ResetPasswordScreenState();
}

class _ResetPasswordScreenState extends State<ResetPasswordScreen> {
  final _password = TextEditingController();
  final _confirm = TextEditingController();

  bool _busy = false;
  bool _hidePassword = true;
  bool _hideConfirm = true;

  @override
  void dispose() {
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_busy) return;

    if (_password.text != _confirm.text) {
      _show('รหัสผ่านใหม่และยืนยันรหัสผ่านไม่ตรงกัน', error: true);
      return;
    }

    final error = AuthService.validatePassword(_password.text);
    if (error != null) {
      _show(error, error: true);
      return;
    }

    setState(() => _busy = true);

    try {
      await AuthService.completePasswordRecovery(_password.text);

      if (!mounted) return;

      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (context) => AlertDialog(
          title: const Text('ตั้งรหัสผ่านใหม่สำเร็จ'),
          content: const Text(
            'รหัสผ่านถูกเปลี่ยนแล้ว กรุณาเข้าสู่ระบบอีกครั้งด้วยรหัสผ่านใหม่',
          ),
          actions: [
            FilledButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('ไปหน้าเข้าสู่ระบบ'),
            ),
          ],
        ),
      );

      if (!mounted) return;
      await widget.onDone();
    } on AuthServiceException catch (e) {
      _show(e.message, error: true);
    } catch (_) {
      _show('ตั้งรหัสผ่านใหม่ไม่สำเร็จ กรุณาลองอีกครั้ง', error: true);
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
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title: const Text('ตั้งรหัสผ่านใหม่'),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 24, 20, 36),
          children: [
            const Icon(Icons.password_rounded, size: 68, color: AppColors.info),
            const SizedBox(height: 18),
            const Text(
              'สร้างรหัสผ่านใหม่',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 26, fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 10),
            const Text(
              'ลิงก์กู้คืนได้รับการยืนยันแล้ว '
              'กรุณาตั้งรหัสผ่านใหม่สำหรับบัญชีของคุณ',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.muted, height: 1.45),
            ),
            const SizedBox(height: 24),
            TextField(
              controller: _password,
              obscureText: _hidePassword,
              enabled: !_busy,
              textInputAction: TextInputAction.next,
              autofillHints: const [AutofillHints.newPassword],
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                labelText: 'รหัสผ่านใหม่',
                prefixIcon: const Icon(Icons.lock_outline_rounded),
                suffixIcon: IconButton(
                  onPressed: _busy
                      ? null
                      : () => setState(() {
                          _hidePassword = !_hidePassword;
                        }),
                  icon: Icon(
                    _hidePassword
                        ? Icons.visibility_outlined
                        : Icons.visibility_off_outlined,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 10),
            PasswordStrengthIndicator(password: _password.text),
            const SizedBox(height: 14),
            TextField(
              controller: _confirm,
              obscureText: _hideConfirm,
              enabled: !_busy,
              textInputAction: TextInputAction.done,
              onSubmitted: (_) {
                if (!_busy) _save();
              },
              decoration: InputDecoration(
                labelText: 'ยืนยันรหัสผ่านใหม่',
                prefixIcon: const Icon(Icons.lock_reset_rounded),
                errorText:
                    _confirm.text.isNotEmpty && _password.text != _confirm.text
                    ? 'รหัสผ่านไม่ตรงกัน'
                    : null,
                suffixIcon: IconButton(
                  onPressed: _busy
                      ? null
                      : () => setState(() {
                          _hideConfirm = !_hideConfirm;
                        }),
                  icon: Icon(
                    _hideConfirm
                        ? Icons.visibility_outlined
                        : Icons.visibility_off_outlined,
                  ),
                ),
              ),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: _busy ? null : _save,
              icon: _busy
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.check_circle_outline_rounded),
              label: const Text('บันทึกรหัสผ่านใหม่'),
            ),
            const SizedBox(height: 12),
            TextButton(
              onPressed: _busy
                  ? null
                  : () async {
                      await widget.onCancel();
                    },
              child: const Text('ยกเลิกและกลับหน้าเข้าสู่ระบบ'),
            ),
          ],
        ),
      ),
    );
  }
}
