import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../app/theme.dart';
import '../../models/user.dart';
import '../../services/auth_service.dart';
import 'verify_email_screen.dart';

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({
    super.key,
    required this.onDone,
  });

  final void Function(AppUser identity) onDone;

  @override
  State<RegisterScreen> createState() =>
      _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _first = TextEditingController();
  final _last = TextEditingController();
  final _email = TextEditingController();
  final _phone = TextEditingController();
  final _password = TextEditingController();
  final _confirm = TextEditingController();

  bool _accepted = false;
  bool _busy = false;
  bool _hidePassword = true;
  bool _hideConfirm = true;

  Uint8List? _avatarBytes;
  String? _avatarMime;
  String? _avatarExtension;

  @override
  void dispose() {
    _first.dispose();
    _last.dispose();
    _email.dispose();
    _phone.dispose();
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _pickAvatar() async {
    final image = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      maxWidth: 1200,
      imageQuality: 82,
    );

    if (image == null) return;

    final bytes = await image.readAsBytes();
    final name = image.name;
    final extension =
        name.contains('.') ? name.split('.').last : 'jpg';

    if (!mounted) return;

    setState(() {
      _avatarBytes = bytes;
      _avatarExtension = extension.toLowerCase();
      _avatarMime = image.mimeType ??
          (_avatarExtension == 'png'
              ? 'image/png'
              : _avatarExtension == 'webp'
                  ? 'image/webp'
                  : 'image/jpeg');
    });
  }

  Future<void> _register() async {
    if (_busy) return;

    if (_password.text != _confirm.text) {
      _showError('รหัสผ่านและยืนยันรหัสผ่านไม่ตรงกัน');
      return;
    }

    if (!_accepted) {
      _showError(
        'กรุณายอมรับเงื่อนไขการใช้งานและนโยบายความเป็นส่วนตัว',
      );
      return;
    }

    setState(() => _busy = true);

    try {
      final pending = await AuthService.registerMember(
        email: _email.text,
        password: _password.text,
        firstName: _first.text,
        lastName: _last.text,
        phone: _phone.text,
      );

      if (!mounted) return;

      await Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => VerifyEmailScreen(
            email: pending.email,
            avatarBytes: _avatarBytes,
            avatarMimeType: _avatarMime,
            avatarExtension: _avatarExtension,
            onDone: widget.onDone,
          ),
        ),
      );
    } on AuthServiceException catch (e) {
      if (!mounted) return;
      _showError(e.message);
    } catch (_) {
      if (!mounted) return;
      _showError('ไม่สามารถสมัครสมาชิกได้');
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          backgroundColor: AppColors.error,
          content: Text(message),
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'สมัครสมาชิก',
          style: TextStyle(fontWeight: FontWeight.w900),
        ),
      ),
      body: SafeArea(
        child: ListView(
          keyboardDismissBehavior:
              ScrollViewKeyboardDismissBehavior.onDrag,
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
          children: [
            const Text(
              'สร้างบัญชี offgrid-sos',
              style: TextStyle(
                fontSize: 26,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              'ระบบใช้ชื่อจริงและนามสกุลจริงในการแสดงตัวตน '
              'เพื่อช่วยลดความสับสนในการสื่อสารฉุกเฉิน',
              style: TextStyle(
                color: AppColors.muted,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 22),
            Center(
              child: InkWell(
                borderRadius: BorderRadius.circular(60),
                onTap: _busy ? null : _pickAvatar,
                child: Column(
                  children: [
                    CircleAvatar(
                      radius: 48,
                      backgroundColor: AppColors.surface,
                      foregroundImage: _avatarBytes == null
                          ? null
                          : MemoryImage(_avatarBytes!),
                      child: _avatarBytes == null
                          ? const Icon(
                              Icons.person_rounded,
                              size: 48,
                              color: AppColors.muted,
                            )
                          : null,
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      '+ เพิ่มรูปโปรไฟล์',
                      style: TextStyle(
                        color: AppColors.info,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const Text(
                      'ไม่บังคับ • อัปโหลดหลังยืนยันอีเมล',
                      style: TextStyle(
                        color: AppColors.muted,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 22),
            TextField(
              controller: _first,
              textInputAction: TextInputAction.next,
              decoration: const InputDecoration(
                labelText: 'ชื่อจริง *',
                prefixIcon: Icon(Icons.person_outline),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _last,
              textInputAction: TextInputAction.next,
              decoration: const InputDecoration(
                labelText: 'นามสกุล *',
                prefixIcon: Icon(Icons.badge_outlined),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _email,
              keyboardType: TextInputType.emailAddress,
              textInputAction: TextInputAction.next,
              decoration: const InputDecoration(
                labelText: 'อีเมล *',
                prefixIcon: Icon(Icons.email_outlined),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _phone,
              keyboardType: TextInputType.phone,
              textInputAction: TextInputAction.next,
              decoration: const InputDecoration(
                labelText: 'เบอร์โทรศัพท์ (ไม่บังคับ)',
                prefixIcon: Icon(Icons.phone_outlined),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _password,
              obscureText: _hidePassword,
              textInputAction: TextInputAction.next,
              decoration: InputDecoration(
                labelText: 'รหัสผ่าน *',
                helperText:
                    'อย่างน้อย 8 ตัวอักษร และต้องตรงตามเงื่อนไขของระบบ',
                prefixIcon:
                    const Icon(Icons.lock_outline_rounded),
                suffixIcon: IconButton(
                  onPressed: () {
                    setState(() {
                      _hidePassword = !_hidePassword;
                    });
                  },
                  icon: Icon(
                    _hidePassword
                        ? Icons.visibility_outlined
                        : Icons.visibility_off_outlined,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _confirm,
              obscureText: _hideConfirm,
              textInputAction: TextInputAction.done,
              onSubmitted: (_) {
                if (!_busy) _register();
              },
              decoration: InputDecoration(
                labelText: 'ยืนยันรหัสผ่าน *',
                prefixIcon:
                    const Icon(Icons.lock_reset_rounded),
                suffixIcon: IconButton(
                  onPressed: () {
                    setState(() {
                      _hideConfirm = !_hideConfirm;
                    });
                  },
                  icon: Icon(
                    _hideConfirm
                        ? Icons.visibility_outlined
                        : Icons.visibility_off_outlined,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              value: _accepted,
              onChanged: _busy
                  ? null
                  : (value) {
                      setState(() {
                        _accepted = value ?? false;
                      });
                    },
              controlAffinity:
                  ListTileControlAffinity.leading,
              title: const Text(
                'ฉันยอมรับเงื่อนไขการใช้งานและนโยบายความเป็นส่วนตัว',
                style: TextStyle(fontSize: 13),
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              height: 52,
              child: FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.info,
                ),
                onPressed: _busy ? null : _register,
                child: _busy
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.5,
                          color: Colors.white,
                        ),
                      )
                    : const Text(
                        'สร้างบัญชี',
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
