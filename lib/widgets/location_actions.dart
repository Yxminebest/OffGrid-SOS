import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

class LocationActions extends StatelessWidget {
  const LocationActions({
    super.key,
    required this.latitude,
    required this.longitude,
    this.compact = false,
  });
  final double latitude, longitude;
  final bool compact;
  static String recordedAt(DateTime value) {
    final time = value.toLocal();
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(time.day)}/${two(time.month)}/${time.year} ${two(time.hour)}:${two(time.minute)}';
  }

  static bool valid(double lat, double lng) =>
      lat.isFinite &&
      lng.isFinite &&
      lat >= -90 &&
      lat <= 90 &&
      lng >= -180 &&
      lng <= 180;

  static Future<bool> open(
    double lat,
    double lng, {
    Future<bool> Function(Uri)? launcher,
  }) async {
    if (!valid(lat, lng)) return false;
    final point = '$lat,$lng';
    for (final uri in [
      Uri.parse('geo:$point?q=${Uri.encodeComponent(point)}'),
      Uri.https('www.google.com', '/maps/search/', {
        'api': '1',
        'query': point,
      }),
    ]) {
      try {
        if (await (launcher?.call(uri) ??
            launchUrl(uri, mode: LaunchMode.externalApplication))) {
          return true;
        }
      } catch (_) {}
    }
    return false;
  }

  static Future<void> show(BuildContext context, double lat, double lng) async {
    if (!valid(lat, lng)) return;
    final point = '${lat.toStringAsFixed(6)}, ${lng.toStringAsFixed(6)}';
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (sheet) => SafeArea(
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'พิกัดที่บันทึกไว้',
                  style: Theme.of(sheet).textTheme.titleLarge,
                ),
                const SizedBox(height: 12),
                SelectableText(point),
                const SizedBox(height: 12),
                const Text(
                  'พิกัดนี้อ่านและคัดลอกได้แม้ออฟไลน์ ส่วนภาพแผนที่และเส้นทางขึ้นกับข้อมูลออฟไลน์ที่มีในแอปแผนที่',
                ),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  icon: const Icon(Icons.copy_outlined),
                  label: const Text('คัดลอกพิกัด'),
                  onPressed: () async {
                    await Clipboard.setData(ClipboardData(text: point));
                    if (sheet.mounted) {
                      ScaffoldMessenger.of(sheet).showSnackBar(
                        const SnackBar(content: Text('คัดลอกพิกัดแล้ว')),
                      );
                    }
                  },
                ),
                FilledButton.icon(
                  icon: const Icon(Icons.map_outlined),
                  label: const Text('เปิดแอปแผนที่'),
                  onPressed: () async {
                    final opened = await open(lat, lng);
                    if (!opened && sheet.mounted) {
                      ScaffoldMessenger.of(sheet).showSnackBar(
                        const SnackBar(
                          content: Text(
                            'เปิดแอปแผนที่ไม่ได้ ยังสามารถคัดลอกพิกัดด้านบนได้',
                          ),
                        ),
                      );
                    }
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => compact
      ? TextButton.icon(
          onPressed: valid(latitude, longitude)
              ? () => show(context, latitude, longitude)
              : null,
          icon: const Icon(Icons.location_on_outlined, size: 18),
          label: const Text('พิกัด / แผนที่'),
        )
      : OutlinedButton.icon(
          onPressed: valid(latitude, longitude)
              ? () => show(context, latitude, longitude)
              : null,
          icon: const Icon(Icons.map_outlined),
          label: const Text('เปิดตำแหน่งบนแผนที่'),
        );
}
