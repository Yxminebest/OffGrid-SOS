import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../app/theme.dart';
import '../../models/user.dart';
import '../../services/auth_service.dart';

class VerifyEmailScreen extends StatefulWidget {
  const VerifyEmailScreen({
    super.key,
    required this.email,
    required this.onDone,
    this.avatarBytes,
    this.avatarMimeType,
    this.avatarExtension,
  });

  final String email;
  final void Function(AppUser identity) onDone;

  final Uint8List? avatarBytes;
  final String? avatarMimeType;
  final String? avatarExtension;

  @override
  State<VerifyEmailScreen> createState() =>
      _VerifyEmailScreenState();
}

class _VerifyEmailScreenState
    extends State<VerifyEmailScreen> {
  StreamSubscription<AuthState>? _subscription;
  bool _busy = false;

  @override
  void initState() {
    super.initState();

    _subscription = AuthService.authStateChanges.listen(
      (data) async {
        if (data.event == AuthChangeEvent.signedIn ||
            data.event == AuthChangeEvent.initialSession ||
            data.event == AuthChangeEvent.userUpdated ||
            data.event == AuthChangeEvent.tokenRefreshed) {
          await _finishIfVerified();
        }
      },
      onError: (Object error, StackTrace stackTrace) {
        // Offline/network refresh errors are handled by UI actions.
      },
    );
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }

  Future<void> _finishIfVerified() async {
    if (_busy) return;

    setState(() => _busy = true);

    try {
      final verifiedUser =
          await AuthService.completeEmailVerification();

      if (verifiedUser == null) {
        if (!mounted) return;

        _show(
          'ยังไม่พบการยืนยันอีเมล กรุณากดลิงก์ในอีเมลก่อน',
          error: true,
        );
        return;
      }

      AppUser finalUser = verifiedUser;

      if (widget.avatarBytes != null) {
        try {
          finalUser = await AuthService.uploadAvatar(
            bytes: widget.avatarBytes!,
            mimeType:
                widget.avatarMimeType ?? 'image/jpeg',
            extension:
                widget.avatarExtension ?? 'jpg',
          );
        } catch (_) {
          // รูปโปรไฟล์เป็น optional
          // บัญชีใช้งานต่อได้แม้อัปโหลดรูปไม่สำเร็จ
        }
      }

      if (!mounted) return;
      widget.onDone(finalUser);
    } on AuthServiceException catch (e) {
      if (!mounted) return;
      _show(e.message, error: true);
    } catch (_) {
      if (!mounted) return;
      _show(
        'ตรวจสอบการยืนยันอีเมลไม่สำเร็จ กรุณาลองอีกครั้ง',
        error: true,
      );
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _resend() async {
    if (_busy) return;

    setState(() => _busy = true);

    try {
      await AuthService.resendVerificationEmail(
        widget.email,
      );

      if (!mounted) return;

      _show('ส่งอีเมลยืนยันอีกครั้งแล้ว');
    } on AuthServiceException catch (e) {
      if (!mounted) return;
      _show(e.message, error: true);
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  void _show(
    String message, {
    bool error = false,
  }) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          backgroundColor:
              error ? AppColors.error : null,
          content: Text(message),
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'ยืนยันอีเมล',
          style: TextStyle(
            fontWeight: FontWeight.w900,
          ),
        ),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            const SizedBox(height: 44),
            Center(
              child: Container(
                width: 94,
                height: 94,
                decoration: BoxDecoration(
                  color:
                      AppColors.info.withValues(alpha: .10),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.mark_email_read_outlined,
                  size: 50,
                  color: AppColors.info,
                ),
              ),
            ),
            const SizedBox(height: 24),
            const Text(
              'ยืนยันอีเมลของคุณ',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 27,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              'เราได้ส่งลิงก์ยืนยันไปที่',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: AppColors.muted,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              widget.email,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 16,
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'เปิดอีเมล → กดลิงก์ยืนยัน → '
              'กลับมาที่แอป แล้วกดตรวจสอบอีกครั้ง',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: AppColors.muted,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 28),
            SizedBox(
              height: 52,
              child: FilledButton.icon(
                onPressed:
                    _busy ? null : _finishIfVerified,
                icon:
                    const Icon(Icons.verified_outlined),
                label: _busy
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.5,
                          color: Colors.white,
                        ),
                      )
                    : const Text(
                        'ฉันยืนยันอีเมลแล้ว',
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                        ),
                      ),
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: 48,
              child: OutlinedButton(
                onPressed: _busy ? null : _resend,
                child: const Text(
                  'ส่งอีเมลยืนยันอีกครั้ง',
                ),
              ),
            ),
            const SizedBox(height: 10),
            TextButton(
              onPressed: _busy
                  ? null
                  : () async {
                      await AuthService.clear();

                      if (!context.mounted) return;

                      Navigator.of(context).popUntil(
                        (route) => route.isFirst,
                      );
                    },
              child: const Text(
                'กลับไปหน้าเข้าสู่ระบบ',
              ),
            ),
          ],
        ),
      ),
    );
  }
}
