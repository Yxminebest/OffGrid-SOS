import 'dart:async';
import 'package:geolocator/geolocator.dart';

class SavedLocation {
  const SavedLocation({
    required this.latitude,
    required this.longitude,
    required this.recordedAt,
    this.accuracyMeters,
    this.isLastKnown = false,
  });
  final double latitude;
  final double longitude;
  final DateTime recordedAt;
  final double? accuracyMeters;
  final bool isLastKnown;
  Duration get age => DateTime.now().difference(recordedAt);
}

class LocationService {
  const LocationService();
  static const Duration _timeout = Duration(seconds: 12);

  Future<SavedLocation?> getLatestLocation() async {
    try {
      if (!await Geolocator.isLocationServiceEnabled().timeout(_timeout)) {
        return await _lastKnown();
      }
      var permission = await Geolocator.checkPermission().timeout(_timeout);
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission().timeout(_timeout);
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever ||
          permission == LocationPermission.unableToDetermine) {
        return null;
      }
      try {
        final p = await Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.high,
            timeLimit: _timeout,
          ),
        ).timeout(const Duration(seconds: 15));
        return SavedLocation(
          latitude: p.latitude,
          longitude: p.longitude,
          accuracyMeters: p.accuracy,
          recordedAt: p.timestamp,
        );
      } on Exception {
        return await _lastKnown();
      }
    } on Exception {
      return await _lastKnown();
    }
  }

  Future<SavedLocation?> _lastKnown() async {
    try {
      final p = await Geolocator.getLastKnownPosition().timeout(
        const Duration(seconds: 4),
      );
      if (p == null) {
        return null;
      }
      // Do not silently treat stale coordinates as a current rescue position.
      if (DateTime.now().difference(p.timestamp).abs() >
          const Duration(hours: 24)) {
        return null;
      }
      return SavedLocation(
        latitude: p.latitude,
        longitude: p.longitude,
        accuracyMeters: p.accuracy,
        recordedAt: p.timestamp,
        isLastKnown: true,
      );
    } on Exception {
      return null;
    }
  }
}
