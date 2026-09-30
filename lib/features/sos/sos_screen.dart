import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../app/theme.dart';
import '../../models/local_identity.dart';
import '../../widgets/app_card.dart';
import '../nearby/nearby_screen.dart';

class SosConfirmScreen extends StatefulWidget {
  const SosConfirmScreen({super.key, required this.me});

  final LocalIdentity me;

  @override
  State<SosConfirmScreen> createState() => _SosConfirmScreenState();
}

class _SosConfirmScreenState extends State<SosConfirmScreen> {
  final _message = TextEditingController(text: 'ฉันต้องการความช่วยเหลือ');

  @override
  void dispose() {
    _message.dispose();
    super.dispose();
  }

  void _activate() {
    HapticFeedback.heavyImpact();
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => SosActiveScreen(
          me: widget.me,
          message: _message.text.trim(),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('ขอความช่วยเหลือ')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 10, 20, 24),
          children: [
            const SizedBox(height: 18),
            const Center(
              child: Icon(Icons.warning_amber_rounded,
                  size: 58, color: AppColors.sos),
            ),
            const SizedBox(height: 16),
            const Text(
              'เปิด SOS หรือไม่?',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 26, fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 8),
            const Text(
              'อุปกรณ์ใกล้เคียงจะเห็นว่าคุณกำลังขอความช่วยเหลือ',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.muted, fontSize: 16),
            ),
            const SizedBox(height: 22),
            const AppCard(
              child: Row(
                children: [
                  Icon(Icons.location_on_outlined, color: AppColors.info),
                  SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('ตำแหน่งล่าสุด',
                            style: TextStyle(fontWeight: FontWeight.w800)),
                        SizedBox(height: 4),
                        Text('บันทึกเมื่อ 20:42 น.',
                            style: TextStyle(color: AppColors.muted)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            const Text('ข้อความเพิ่มเติม',
                style: TextStyle(fontWeight: FontWeight.w800)),
            const SizedBox(height: 8),
            TextField(
              controller: _message,
              minLines: 2,
              maxLines: 4,
              decoration: const InputDecoration(
                hintText: 'ฉันต้องการความช่วยเหลือ',
              ),
            ),
            const SizedBox(height: 18),
            FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.sos,
                minimumSize: const Size(double.infinity, 60),
              ),
              onPressed: _activate,
              icon: const Icon(Icons.warning_amber_rounded, size: 26),
              label: const Text('เปิด SOS'),
            ),
            const SizedBox(height: 8),
            OutlinedButton(
              onPressed: () => Navigator.maybePop(context),
              child: const Text('ยกเลิก'),
            ),
            const SizedBox(height: 10),
            const Text(
              'ยืนยันก่อนเปิดจริง เพื่อลดความเสี่ยงจากการกดพลาด',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.muted, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }
}

class SosActiveScreen extends StatefulWidget {
  const SosActiveScreen({
    super.key,
    required this.me,
    required this.message,
  });

  final LocalIdentity me;
  final String message;

  @override
  State<SosActiveScreen> createState() => _SosActiveScreenState();
}

class _SosActiveScreenState extends State<SosActiveScreen> {
  late final DateTime _startedAt;
  Timer? _timer;
  int _elapsed = 0;

  @override
  void initState() {
    super.initState();
    _startedAt = DateTime.now();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _elapsed++);
    });
    // TODO Week 3: broadcast SOS + short message + last location via MeshService.
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  String get _elapsedText {
    final m = (_elapsed ~/ 60).toString().padLeft(2, '0');
    final s = (_elapsed % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  String _time(DateTime value) =>
      '${value.hour.toString().padLeft(2, '0')}:${value.minute.toString().padLeft(2, '0')}';

  void _stop() {
    HapticFeedback.mediumImpact();
    Navigator.of(context).popUntil((route) => route.isFirst);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 24),
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: AppColors.sos.withOpacity(.12),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppColors.sos),
              ),
              child: const Row(
                children: [
                  Icon(Icons.warning_amber_rounded,
                      size: 18, color: AppColors.sos),
                  SizedBox(width: 7),
                  Expanded(
                    child: Text('EMERGENCY ACTIVATED',
                        style: TextStyle(
                            color: AppColors.sos, fontWeight: FontWeight.w900)),
                  ),
                  Text('LIVE',
                      style: TextStyle(
                          color: AppColors.sos, fontWeight: FontWeight.w900)),
                ],
              ),
            ),
            const SizedBox(height: 24),
            Center(
              child: Container(
                width: 118,
                height: 118,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppColors.sos,
                ),
                alignment: Alignment.center,
                child: Text(
                  _elapsedText,
                  style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w900),
                ),
              ),
            ),
            const SizedBox(height: 16),
            const Text('SOS ACTIVE',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 25, fontWeight: FontWeight.w900)),
            const Text('ขอความช่วยเหลือ',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
            const SizedBox(height: 22),
            _status(Icons.location_on_outlined, 'ส่งตำแหน่งล่าสุด',
                '✓ ส่งไปแล้ว 2 อุปกรณ์', AppColors.success),
            const SizedBox(height: 10),
            _status(Icons.radar_rounded, 'อุปกรณ์ใกล้เคียง', '2 เครื่อง', AppColors.info),
            const SizedBox(height: 10),
            _status(Icons.schedule_outlined, 'เปิด SOS เวลา',
                '${_time(_startedAt)} น.', AppColors.pending),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => NearbyScreen(me: widget.me)),
              ),
              icon: const Icon(Icons.radar_rounded),
              label: const Text('ดูอุปกรณ์ใกล้เคียง / เปิดแชท'),
            ),
            const SizedBox(height: 10),
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.sos,
                side: const BorderSide(color: AppColors.sos),
              ),
              onPressed: _stop,
              icon: const Icon(Icons.stop_circle_outlined),
              label: const Text('หยุด SOS'),
            ),
            const SizedBox(height: 12),
            const Text(
              'ไม่ใช้ animation กระพริบเร็ว เพื่อลดการรบกวนผู้ใช้',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.muted, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }

  Widget _status(IconData icon, String title, String detail, Color color) {
    return AppCard(
      child: Row(
        children: [
          Icon(icon, color: color, size: 26),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
                const SizedBox(height: 3),
                Text(detail, style: const TextStyle(color: AppColors.muted)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
