import 'package:flutter/material.dart';
import '../../app/theme.dart';
import '../../models/local_identity.dart';
import '../../widgets/app_card.dart';

class WelcomeScreen extends StatefulWidget {
  const WelcomeScreen({super.key, required this.onDone});
  final void Function(LocalIdentity) onDone;

  @override
  State<WelcomeScreen> createState() => _WelcomeScreenState();
}

class _WelcomeScreenState extends State<WelcomeScreen> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _first = TextEditingController();
  final _last = TextEditingController();

  @override
  void initState() {
    super.initState();
    _first.addListener(_refresh);
    _last.addListener(_refresh);
  }

  void _refresh() => setState(() {});

  @override
  void dispose() {
    for (final c in [_email, _password, _first, _last]) {
      c.dispose();
    }
    super.dispose();
  }

  bool get _guestReady =>
      _first.text.trim().isNotEmpty && _last.text.trim().isNotEmpty;

  Future<void> _startGuest() async {
    final id = await IdentityService.createGuest(_first.text, _last.text);
    widget.onDone(id);
  }

  void _login() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('ระบบสมาชิกจะเชื่อม Firebase ใน Week 3')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            const SizedBox(height: 24),
            const Center(
              child: CircleAvatar(
                radius: 42,
                backgroundColor: AppColors.surface,
                child: Icon(Icons.health_and_safety_outlined,
                    size: 46, color: AppColors.rescue),
              ),
            ),
            const SizedBox(height: 16),
            const Text('RescueLink',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 30, fontWeight: FontWeight.w900)),
            const SizedBox(height: 6),
            const Text(
              'ขอความช่วยเหลือและสื่อสารกับอุปกรณ์ใกล้เคียงได้ แม้อินเทอร์เน็ตไม่พร้อมใช้งาน',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.muted, fontSize: 16),
            ),
            const SizedBox(height: 26),
            AppCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text('เป็นสมาชิก',
                      style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800)),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _email,
                    keyboardType: TextInputType.emailAddress,
                    autofillHints: const [AutofillHints.email],
                    decoration: const InputDecoration(labelText: 'อีเมล'),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: _password,
                    obscureText: true,
                    decoration: const InputDecoration(labelText: 'รหัสผ่าน'),
                  ),
                  const SizedBox(height: 12),
                  FilledButton(
                    style: FilledButton.styleFrom(backgroundColor: AppColors.rescue),
                    onPressed: _login,
                    child: const Text('เข้าสู่ระบบ'),
                  ),
                ],
              ),
            ),
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 18),
              child: Row(children: [
                Expanded(child: Divider()),
                Padding(
                  padding: EdgeInsets.symmetric(horizontal: 12),
                  child: Text('หรือ', style: TextStyle(color: AppColors.muted)),
                ),
                Expanded(child: Divider()),
              ]),
            ),
            AppCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text('ใช้งานโดยไม่สมัครสมาชิก',
                      style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800)),
                  const SizedBox(height: 6),
                  const Text('กรอกชื่อจริงและนามสกุลเพื่อใช้งานแบบออฟไลน์',
                      style: TextStyle(color: AppColors.muted)),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _first,
                    decoration: const InputDecoration(labelText: 'ชื่อจริง *'),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: _last,
                    decoration: const InputDecoration(labelText: 'นามสกุล *'),
                  ),
                  const SizedBox(height: 12),
                  FilledButton.tonal(
                    onPressed: _guestReady ? _startGuest : null,
                    child: const Text('ใช้งานโดยไม่สมัครสมาชิก'),
                  ),
                  const SizedBox(height: 8),
                  const Text('ใช้ได้ตอนออฟไลน์ · สมัครและผูกบัญชีภายหลังได้',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: AppColors.muted, fontSize: 13)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
