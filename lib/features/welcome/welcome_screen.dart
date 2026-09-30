import 'package:flutter/material.dart';
import '../../app/theme.dart';
import '../../models/local_identity.dart';
import '../../widgets/app_card.dart';

class WelcomeScreen extends StatefulWidget {
  const WelcomeScreen({super.key, required this.onDone});

  final void Function(LocalIdentity identity) onDone;

  @override
  State<WelcomeScreen> createState() => _WelcomeScreenState();
}

class _WelcomeScreenState extends State<WelcomeScreen> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _first = TextEditingController();
  final _last = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    _first.dispose();
    _last.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    if (_email.text.trim().isEmpty || _password.text.isEmpty) {
      _show('กรุณากรอกอีเมลและรหัสผ่าน');
      return;
    }
    setState(() => _busy = true);
    final identity = await IdentityService.createDemoMember(_email.text);
    if (!mounted) return;
    setState(() => _busy = false);
    widget.onDone(identity);
  }

  Future<void> _guest() async {
    if (_first.text.trim().isEmpty || _last.text.trim().isEmpty) {
      _show('กรุณากรอกชื่อจริงและนามสกุล');
      return;
    }
    setState(() => _busy = true);
    final identity = await IdentityService.createGuest(_first.text, _last.text);
    if (!mounted) return;
    setState(() => _busy = false);
    widget.onDone(identity);
  }

  void _show(String text) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 28, 20, 28),
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'RescueLink',
                  style: TextStyle(fontSize: 28, fontWeight: FontWeight.w900),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: const Text(
                    'OFF-GRID READY',
                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 28),
            const Center(
              child: Icon(Icons.health_and_safety_outlined,
                  size: 52, color: AppColors.rescue),
            ),
            const SizedBox(height: 8),
            const Text(
              'ยินดีต้อนรับ',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 24),
            AppCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text('เป็นสมาชิก',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _email,
                    keyboardType: TextInputType.emailAddress,
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
                    onPressed: _busy ? null : _login,
                    child: const Text('เข้าสู่ระบบ'),
                  ),
                ],
              ),
            ),
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 16),
              child: Row(
                children: [
                  Expanded(child: Divider()),
                  Padding(
                    padding: EdgeInsets.symmetric(horizontal: 12),
                    child: Text('หรือ', style: TextStyle(color: AppColors.muted)),
                  ),
                  Expanded(child: Divider()),
                ],
              ),
            ),
            AppCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text('ยังไม่เป็นสมาชิก',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
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
                  OutlinedButton(
                    onPressed: _busy ? null : _guest,
                    child: const Text('ใช้งานโดยไม่สมัคร'),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Guest ใช้งานฟังก์ชัน Offline-First ได้ และผูกบัญชีภายหลังได้',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: AppColors.muted, fontSize: 13),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              'Week 2: ปุ่มเข้าสู่ระบบจำลองการผ่านหน้า Login เพื่อทดสอบ Flow; Firebase Auth จะเชื่อมใน Week 3',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.muted, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }
}
