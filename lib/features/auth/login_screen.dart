import 'package:flutter/material.dart';

import '../../app/theme.dart';
import '../../widgets/appearance_picker.dart';
import '../../widgets/brand_mark.dart';

import '../../models/user.dart';

import '../../services/auth_service.dart';

import 'forgot_password_screen.dart';

import 'guest_screen.dart';

import 'register_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key, required this.onDone});

  final void Function(AppUser identity) onDone;

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _form = GlobalKey<FormState>();
  final _email = TextEditingController();

  final _password = TextEditingController();

  bool _busy = false;

  bool _hidePassword = true;

  @override
  void dispose() {
    _email.dispose();

    _password.dispose();

    super.dispose();
  }

  Future<void> _login() async {
    if (_busy || !(_form.currentState?.validate() ?? false)) return;
    FocusScope.of(context).unfocus();

    setState(() => _busy = true);

    try {
      final user = await AuthService.signInMember(
        email: _email.text,

        password: _password.text,
      );

      if (!mounted) return;

      widget.onDone(user);
    } on AuthServiceException catch (e) {
      if (!mounted) return;

      _showError(e.message);
    } catch (_) {
      if (!mounted) return;

      _showError('ไม่สามารถเข้าสู่ระบบได้ กรุณาลองอีกครั้ง');
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _resendVerification() async {
    final email = _email.text.trim();

    if (!AuthService.isValidEmail(email)) {
      _showError('กรุณากรอกอีเมลให้ถูกต้อง');

      return;
    }

    setState(() => _busy = true);

    try {
      await AuthService.resendVerificationEmail(email);

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'ส่งอีเมลยืนยันอีกครั้งแล้ว กรุณาตรวจ Inbox และ Spam/Junk',
          ),
        ),
      );
    } on AuthServiceException catch (e) {
      if (!mounted) return;

      _showError(e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _openForgotPassword() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ForgotPasswordScreen(initialEmail: _email.text),
      ),
    );
  }

  Future<void> _openRegister() async {
    final navigator = Navigator.of(context);
    final onDone = widget.onDone;
    await navigator.push(
      MaterialPageRoute(
        builder: (_) => RegisterScreen(
          onDone: (identity) {
            navigator.popUntil((route) => route.isFirst);
            onDone(identity);
          },
        ),
      ),
    );
  }

  Future<void> _openGuest() async {
    final navigator = Navigator.of(context);
    final onDone = widget.onDone;
    await navigator.push(
      MaterialPageRoute(
        builder: (_) => GuestScreen(
          onDone: (identity) {
            navigator.popUntil((route) => route.isFirst);
            onDone(identity);
          },
        ),
      ),
    );
  }

  void _showError(String message) {
    final needsVerification = message.contains('ยืนยันอีเมล');

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          backgroundColor: AppColors.error,

          content: Text(message),

          action: needsVerification
              ? SnackBarAction(
                  label: 'ส่งอีกครั้ง',

                  textColor: Colors.white,

                  onPressed: () {
                    _resendVerification();
                  },
                )
              : null,
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    final p = context.colors;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: ListView(
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              padding: const EdgeInsets.fromLTRB(24, 18, 24, 28),
              children: [
                Row(
                  children: [
                    const Expanded(child: BrandLockup()),
                    const ThemeModeButton(),
                  ],
                ),
                const SizedBox(height: 32),
                Text(
                  'อุ่นใจได้\nแม้ไกลสัญญาณ',
                  style: Theme.of(context).textTheme.headlineLarge?.copyWith(
                    fontSize: 30,
                    height: 1.3,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  'บันทึก SOS และเชื่อมต่อคนใกล้ตัว\nแม้อินเทอร์เน็ตไม่พร้อม',
                  style: TextStyle(color: p.muted, height: 1.65),
                ),
                const SizedBox(height: 28),
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: AutofillGroup(
                    child: Form(
                      key: _form,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(
                            'เริ่มต้นด้วยบัญชีของคุณ',
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          const SizedBox(height: 5),
                          Text(
                            'ใช้บัญชีของคุณเพื่อติดตามข้อมูลและการสนทนา',
                            style: TextStyle(color: p.muted, fontSize: 13),
                          ),
                          const SizedBox(height: 22),
                          TextFormField(
                            controller: _email,
                            enabled: !_busy,
                            keyboardType: TextInputType.emailAddress,
                            textInputAction: TextInputAction.next,
                            autofillHints: const [
                              AutofillHints.username,
                              AutofillHints.email,
                            ],
                            validator: (value) =>
                                AuthService.isValidEmail(value ?? '')
                                ? null
                                : 'กรอกอีเมลให้ถูกต้อง',
                            decoration: const InputDecoration(
                              labelText: 'อีเมล',
                              hintText: 'you@example.com',
                              prefixIcon: Icon(Icons.alternate_email_rounded),
                            ),
                          ),
                          const SizedBox(height: 16),
                          TextFormField(
                            controller: _password,
                            enabled: !_busy,
                            obscureText: _hidePassword,
                            textInputAction: TextInputAction.done,
                            autofillHints: const [AutofillHints.password],
                            validator: (value) => value == null || value.isEmpty
                                ? 'กรอกรหัสผ่านของคุณ'
                                : null,
                            onFieldSubmitted: (_) => _login(),
                            decoration: InputDecoration(
                              labelText: 'รหัสผ่าน',
                              prefixIcon: const Icon(
                                Icons.lock_outline_rounded,
                              ),
                              suffixIcon: IconButton(
                                tooltip: _hidePassword
                                    ? 'แสดงรหัสผ่าน'
                                    : 'ซ่อนรหัสผ่าน',
                                onPressed: _busy
                                    ? null
                                    : () => setState(
                                        () => _hidePassword = !_hidePassword,
                                      ),
                                icon: Icon(
                                  _hidePassword
                                      ? Icons.visibility_outlined
                                      : Icons.visibility_off_outlined,
                                ),
                              ),
                            ),
                          ),
                          Align(
                            alignment: Alignment.centerRight,
                            child: TextButton(
                              onPressed: _busy ? null : _openForgotPassword,
                              child: const Text('ลืมรหัสผ่าน?'),
                            ),
                          ),
                          FilledButton(
                            onPressed: _busy ? null : _login,
                            child: _busy
                                ? const SizedBox(
                                    width: 22,
                                    height: 22,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : const Text('เข้าสู่ระบบ'),
                          ),
                          const SizedBox(height: 10),
                          Wrap(
                            alignment: WrapAlignment.center,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              Text(
                                'ยังไม่มีบัญชี?',
                                style: TextStyle(color: p.muted, fontSize: 13),
                              ),
                              TextButton(
                                onPressed: _busy ? null : _openRegister,
                                child: const Text('สมัครสมาชิก'),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                Row(
                  children: [
                    Expanded(child: Divider(color: p.border)),
                    Flexible(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 14),
                        child: Text(
                          'เริ่มต้นได้ทันที',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: p.muted, fontSize: 12),
                        ),
                      ),
                    ),
                    Expanded(child: Divider(color: p.border)),
                  ],
                ),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: _busy ? null : _openGuest,
                  icon: const Icon(Icons.person_outline_rounded),
                  label: const Text('ใช้งานโดยไม่สมัครสมาชิก'),
                ),
                const SizedBox(height: 12),
                Text(
                  'บันทึก SOS ในเครื่องได้ แม้ไม่ได้เข้าสู่ระบบ',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: p.muted, fontSize: 12),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
