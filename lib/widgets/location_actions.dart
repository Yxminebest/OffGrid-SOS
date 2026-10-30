import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:url_launcher/url_launcher.dart';
import 'location_map_screen.dart';

class LocationActions extends StatelessWidget {
  const LocationActions({
    super.key,
    required this.latitude,
    required this.longitude,
    this.compact = false,
    this.accuracy,
  });
  final double latitude, longitude;
  final bool compact;
  final double? accuracy;
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

  static Future<void> show(
    BuildContext context,
    double lat,
    double lng, {
    TileProvider? tileProvider,
    double? accuracy,
  }) async {
    if (!valid(lat, lng)) return;
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => LocationMapScreen(
          latitude: lat,
          longitude: lng,
          targetAccuracy: accuracy,
          tileProvider: tileProvider,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => compact
      ? TextButton.icon(
          onPressed: valid(latitude, longitude)
              ? () => show(context, latitude, longitude, accuracy: accuracy)
              : null,
          icon: const Icon(Icons.location_on_outlined, size: 18),
          label: const Text('พิกัด / แผนที่'),
        )
      : OutlinedButton.icon(
          onPressed: valid(latitude, longitude)
              ? () => show(context, latitude, longitude, accuracy: accuracy)
              : null,
          icon: const Icon(Icons.map_outlined),
          label: const Text('เปิดตำแหน่งบนแผนที่'),
        );
}
