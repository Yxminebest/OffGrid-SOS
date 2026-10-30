import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import '../services/location_service.dart';
import 'location_actions.dart';

class OfflineDirection {
  OfflineDirection(SavedLocation from, double latitude, double longitude)
    : meters = Geolocator.distanceBetween(
        from.latitude,
        from.longitude,
        latitude,
        longitude,
      ),
      degrees =
          (Geolocator.bearingBetween(
                from.latitude,
                from.longitude,
                latitude,
                longitude,
              ) +
              360) %
          360;
  final double meters, degrees;
  String get cardinal => const [
    'เหนือ',
    'ตะวันออกเฉียงเหนือ',
    'ตะวันออก',
    'ตะวันออกเฉียงใต้',
    'ใต้',
    'ตะวันตกเฉียงใต้',
    'ตะวันตก',
    'ตะวันตกเฉียงเหนือ',
  ][((degrees + 22.5) / 45).floor() % 8];
}

/// GPS and saved coordinates only: no tile server, network or external app.
class OfflineLocationGuide extends StatefulWidget {
  const OfflineLocationGuide({
    super.key,
    required this.latitude,
    required this.longitude,
    this.locationService = const LocationService(),
  });
  final double latitude, longitude;
  final LocationService locationService;
  @override
  State<OfflineLocationGuide> createState() => _GuideState();
}

class _GuideState extends State<OfflineLocationGuide> {
  SavedLocation? _from;
  bool _busy = false;
  String? _error;

  Future<void> _locate() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final location = await widget.locationService.getLatestLocation();
      if (!mounted) return;
      setState(() {
        if (location == null ||
            !LocationActions.valid(location.latitude, location.longitude)) {
          _error =
              'ยังหาตำแหน่งของคุณไม่ได้ เปิด GPS และอนุญาตตำแหน่ง แล้วลองใหม่ในที่โล่ง';
        } else {
          _from = location;
        }
      });
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'อ่านตำแหน่งไม่ได้ กรุณาตรวจสิทธิ์และลองใหม่');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final from = _from;
    final direction = from == null
        ? null
        : OfflineDirection(from, widget.latitude, widget.longitude);
    return Scaffold(
      appBar: AppBar(title: const Text('ระยะและทิศทางออฟไลน์')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Text(
              'พิกัดปลายทาง',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            SelectableText(
              '${widget.latitude.toStringAsFixed(6)}, ${widget.longitude.toStringAsFixed(6)}',
            ),
            const SizedBox(height: 12),
            const Text(
              'คำนวณจาก GPS ของเครื่องและพิกัดที่ได้รับ โดยไม่ใช้อินเทอร์เน็ต',
            ),
            const SizedBox(height: 20),
            if (direction != null)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    children: [
                      const Text('เหนือ ↑'),
                      const SizedBox(height: 8),
                      Transform.rotate(
                        angle: direction.degrees * math.pi / 180,
                        child: const Icon(Icons.navigation_rounded, size: 96),
                      ),
                      Text(
                        'ทิศ${direction.cardinal} • ${direction.degrees.toStringAsFixed(0)}°',
                      ),
                      const SizedBox(height: 16),
                      Text(
                        direction.meters < 1000
                            ? 'ระยะเส้นตรงประมาณ ${direction.meters.toStringAsFixed(0)} เมตร'
                            : 'ระยะเส้นตรงประมาณ ${(direction.meters / 1000).toStringAsFixed(2)} กิโลเมตร',
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'เวลาพิกัดของฉัน: ${LocationActions.recordedAt(from!.recordedAt)}',
                      ),
                      if (from.accuracyMeters != null)
                        Text(
                          'ความแม่นยำ GPS ประมาณ ±${from.accuracyMeters!.toStringAsFixed(0)} เมตร',
                        ),
                      if (from.isLastKnown)
                        const Text(
                          'ใช้พิกัดเก่าที่บันทึกไว้ อาจไม่ใช่ตำแหน่งปัจจุบัน',
                        ),
                    ],
                  ),
                ),
              ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Text(_error!),
              ),
            FilledButton.icon(
              onPressed: _busy ? null : _locate,
              icon: _busy
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.my_location),
              label: Text(_busy ? 'กำลังอ่าน GPS...' : 'คำนวณจากตำแหน่งของฉัน'),
            ),
            const SizedBox(height: 16),
            const Text(
              'ลูกศรอ้างอิงทิศเหนือด้านบนของหน้าจอ ไม่ใช่เข็มทิศที่หมุนตามโทรศัพท์ ระยะเป็นเส้นตรง ไม่รวมถนนหรือสิ่งกีดขวาง พิกัดปลายทางเป็นตำแหน่งที่บันทึกไว้',
            ),
          ],
        ),
      ),
    );
  }
}
