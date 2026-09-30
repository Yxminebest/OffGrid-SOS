import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../app/theme.dart';
import '../../widgets/app_card.dart';

class SosScreen extends StatefulWidget {
  const SosScreen({super.key});

  @override
  State<SosScreen> createState() => _SosScreenState();
}

class _SosScreenState extends State<SosScreen> {
  final _message = TextEditingController(text: 'ฉันต้องการความช่วยเหลือ');
  bool _active = false;
  DateTime? _startedAt;

  @override
  void dispose() {
    _message.dispose();
    super.dispose();
  }

  void _activate() {
    HapticFeedback.heavyImpact();
    setState(() {
      _active = true;
      _startedAt = DateTime.now();
    });
    // TODO Week 3: broadcast SOS + last known location via MeshService.
  }

  void _stop() {
    HapticFeedback.mediumImpact();
    setState(() {
      _active = false;
      _startedAt = null;
    });
    // TODO Week 3: broadcast SOS stop event.
  }

  String _time(DateTime? value) {
    final d = value ?? DateTime.now();
    return '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    return _active ? _activeView() : _confirmView();
  }

  Widget _confirmView() {
    return Scaffold(
      appBar: AppBar(title: const Text('ขอความช่วยเหลือ')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 10, 20, 24),
          children: [
            const SizedBox(height: 14),
            Center(
              child: Container(
                width: 86,
                height: 86,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppColors.sos.withOpacity(.14),
                  border: Border.all(color: AppColors.sos, width: 2),
                ),
                child: const Icon(Icons.warning_amber_rounded,
                    size: 48, color: AppColors.sos),
              ),
            ),
            const SizedBox(height: 20),
            const Text('เปิด SOS หรือไม่?',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800)),
            const SizedBox(height: 8),
            const Text(
              'อุปกรณ์ใกล้เคียงจะเห็นว่า\nคุณกำลังขอความช่วยเหลือ',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.muted, fontSize: 16),
            ),
            const SizedBox(height: 24),
            const AppCard(
              child: Row(children: [
                Icon(Icons.location_on_outlined, color: AppColors.info),
                SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('ตำแหน่งล่าสุด',
                          style: TextStyle(fontWeight: FontWeight.w700)),
                      SizedBox(height: 4),
                      Text('บันทึกไว้พร้อมส่งเมื่อเปิด SOS',
                          style: TextStyle(color: AppColors.muted)),
                    ],
                  ),
                ),
                Icon(Icons.check_circle_outline, color: AppColors.success),
              ]),
            ),
            const SizedBox(height: 16),
            const Text('ข้อความเพิ่มเติม',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            TextField(
              controller: _message,
              minLines: 2,
              maxLines: 4,
              decoration: const InputDecoration(
                hintText: 'อธิบายสิ่งที่ต้องการความช่วยเหลือ',
              ),
            ),
            const SizedBox(height: 20),
            Semantics(
              button: true,
              label: 'SOS ขอความช่วยเหลือ',
              hint: 'แตะสองครั้งเพื่อยืนยันเปิด SOS',
              child: FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.sos,
                  foregroundColor: AppColors.text,
                  minimumSize: const Size(double.infinity, 62),
                ),
                onPressed: _activate,
                icon: const Icon(Icons.warning_amber_rounded, size: 28),
                label: const Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('เปิด SOS', style: TextStyle(fontSize: 20)),
                    Text('ขอความช่วยเหลือ', style: TextStyle(fontSize: 13)),
                  ],
                ),
              ),
            ),
            TextButton(
              onPressed: () => Navigator.maybePop(context),
              child: const Text('ยกเลิก', style: TextStyle(color: AppColors.muted)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _activeView() {
    return Scaffold(
      appBar: AppBar(title: const Text('SOS เปิดอยู่')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 24),
          children: [
            Center(
              child: Container(
                width: 112,
                height: 112,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppColors.sos,
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.sos.withOpacity(.22),
                      blurRadius: 28,
                      spreadRadius: 8,
                    ),
                  ],
                ),
                child: const Icon(Icons.warning_amber_rounded,
                    size: 58, color: AppColors.text),
              ),
            ),
            const SizedBox(height: 18),
            const Text('SOS ACTIVE',
                textAlign: TextAlign.center,
                style: TextStyle(
                    fontSize: 26,
                    fontWeight: FontWeight.w900,
                    color: AppColors.sos,
                    letterSpacing: .8)),
            const Text('ขอความช่วยเหลือ',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
            const SizedBox(height: 24),
            _statusRow(Icons.location_on_outlined, 'ส่งตำแหน่งล่าสุด',
                '✓ ส่งไปแล้ว 2 อุปกรณ์', AppColors.success),
            const SizedBox(height: 10),
            _statusRow(Icons.radar_rounded, 'อุปกรณ์ใกล้เคียง', '2 เครื่อง',
                AppColors.info),
            const SizedBox(height: 10),
            _statusRow(Icons.schedule_outlined, 'เปิด SOS เวลา',
                '${_time(_startedAt)} น.', AppColors.pending),
            const SizedBox(height: 26),
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.text,
                side: const BorderSide(color: AppColors.error, width: 1.5),
                minimumSize: const Size(double.infinity, 58),
              ),
              onPressed: _stop,
              icon: const Icon(Icons.stop_circle_outlined, color: AppColors.error),
              label: const Text('หยุด SOS'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _statusRow(IconData icon, String title, String detail, Color color) {
    return AppCard(
      child: Row(children: [
        Icon(icon, color: color, size: 28),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
              const SizedBox(height: 3),
              Text(detail, style: const TextStyle(color: AppColors.muted)),
            ],
          ),
        ),
      ]),
    );
  }
}

class RescueModeScreen extends StatefulWidget {
  const RescueModeScreen({super.key});

  @override
  State<RescueModeScreen> createState() => _RescueModeScreenState();
}

class _RescueModeScreenState extends State<RescueModeScreen> {
  bool _active = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('โหมดหน่วยกู้ภัย')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            const SizedBox(height: 16),
            Center(
              child: Container(
                width: 92,
                height: 92,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppColors.rescue.withOpacity(.16),
                  border: Border.all(color: AppColors.rescue, width: 2),
                ),
                child: const Icon(Icons.health_and_safety_outlined,
                    color: AppColors.rescue, size: 48),
              ),
            ),
            const SizedBox(height: 18),
            Text(_active ? 'RESCUE MODE ACTIVE' : 'RESCUE MODE',
                textAlign: TextAlign.center,
                style: const TextStyle(
                    color: AppColors.rescue,
                    fontSize: 24,
                    fontWeight: FontWeight.w900)),
            const Text('โหมดช่วยเหลือ',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
            const SizedBox(height: 16),
            const Text(
              'คุณกำลังแสดงสถานะ “หน่วยกู้ภัย” ให้เครื่องอื่นเห็น โดยใช้ทั้งไอคอนและข้อความ ไม่พึ่งสีเพียงอย่างเดียว',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.muted, fontSize: 16),
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.rescue,
                foregroundColor: AppColors.text,
                minimumSize: const Size(double.infinity, 58),
              ),
              onPressed: () {
                HapticFeedback.mediumImpact();
                setState(() => _active = !_active);
              },
              icon: Icon(_active
                  ? Icons.stop_circle_outlined
                  : Icons.health_and_safety_outlined),
              label: Text(_active ? 'ปิด Rescue Mode' : 'เปิด Rescue Mode'),
            ),
            const SizedBox(height: 18),
            AppCard(
              child: Row(children: [
                Icon(_active ? Icons.check_circle : Icons.radio_button_unchecked,
                    color: _active ? AppColors.success : AppColors.muted),
                const SizedBox(width: 12),
                Text(_active ? 'สถานะ: เปิดอยู่' : 'สถานะ: ยังไม่เปิด',
                    style: const TextStyle(fontWeight: FontWeight.w700)),
              ]),
            ),
          ],
        ),
      ),
    );
  }
}
