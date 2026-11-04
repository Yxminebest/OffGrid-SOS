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
  String get qualityDescription =>
      accuracyMeters != null && accuracyMeters!.isFinite && accuracyMeters! > 0
      ? 'ความคลาดเคลื่อนที่เครื่องรายงานประมาณ ${accuracyMeters!.round()} ม.${accuracyMeters! > 30 ? ' — GPS ยังหยาบ หมุดอาจไม่ตรงจุดจริง' : ''}'
      : 'ไม่ทราบความคลาดเคลื่อนของ GPS';
  Duration get age => DateTime.now().difference(recordedAt);
}

/// Selects recent real fixes without inventing coordinates or smaller accuracy.
class LocationFixWindow {
  final _samples = <SavedLocation>[];
  static bool valid(SavedLocation p) =>
      !p.isLastKnown &&
      p.latitude.isFinite &&
      p.longitude.isFinite &&
      p.latitude.abs() <= 90 &&
      p.longitude.abs() <= 180 &&
      p.age.abs() <= const Duration(seconds: 30);
  SavedLocation? add(SavedLocation p) {
    if (!valid(p)) return null;
    _samples.removeWhere(
      (v) =>
          p.recordedAt.difference(v.recordedAt).abs() >
              const Duration(seconds: 8) ||
          !valid(v),
    );
    if (_samples.isNotEmpty) {
      final previous = _samples.first;
      final movement = Geolocator.distanceBetween(
        previous.latitude,
        previous.longitude,
        p.latitude,
        p.longitude,
      );
      if (movement > accuracy(previous) + accuracy(p)) _samples.clear();
    }
    _samples.add(p);
    _samples.sort((a, b) {
      final quality = accuracy(a).compareTo(accuracy(b));
      return quality != 0 ? quality : b.recordedAt.compareTo(a.recordedAt);
    });
    if (_samples.length > 32) _samples.removeRange(32, _samples.length);
    return _samples.first;
  }

  static double accuracy(SavedLocation p) =>
      p.accuracyMeters != null &&
          p.accuracyMeters!.isFinite &&
          p.accuracyMeters! > 0
      ? p.accuracyMeters!
      : double.infinity;
}

class LocationService {
  const LocationService({this.gpsTimeout = const Duration(seconds: 30)});
  final Duration gpsTimeout;
  static const Duration _timeout = Duration(seconds: 12);

  // Foreground preparation starts before SOS, never invents a coordinate.
  static StreamSubscription<SavedLocation>? _preparedSubscription;
  static SavedLocation? _prepared;
  static int _prepareGeneration = 0;
  SavedLocation? get preparedLocation =>
      _prepared != null && LocationFixWindow.valid(_prepared!)
      ? _prepared
      : null;

  Future<void> prepare() async {
    final generation = ++_prepareGeneration;
    try {
      if (_preparedSubscription != null) return;
      if (!await Geolocator.isLocationServiceEnabled()) return;
      final permission = await Geolocator.checkPermission();
      if (permission != LocationPermission.whileInUse &&
          permission != LocationPermission.always) {
        return;
      }
      if (generation != _prepareGeneration) return;
      _preparedSubscription = watchLocations().listen((fix) {
        _prepared = fix;
      }, onError: (Object _) {});
    } catch (_) {
      /* Permission and sensor failures must not block SOS. */
    }
  }

  static Future<void> stopPreparing() async {
    ++_prepareGeneration;
    final subscription = _preparedSubscription;
    _preparedSubscription = null;
    await subscription?.cancel();
  }

  /// Yield cache immediately and then every real live fix; do not wait for
  /// navigation-grade accuracy before attaching the first available SOS pin.
  Stream<SavedLocation> emergencyLocations() => Stream.multi((events) {
    StreamSubscription<SavedLocation>? live;
    var cancelled = false;
    final prepared = preparedLocation;
    if (prepared != null) events.add(prepared);
    // Read the OS cache in parallel; a slow cache lookup never holds up GPS.
    unawaited(
      _lastKnown().then((previous) {
        if (!cancelled && prepared == null && previous != null) {
          events.add(previous);
        }
      }),
    );
    unawaited(() async {
      try {
        if (!await isEnabled() || cancelled) return;
        final permission = await Geolocator.checkPermission();
        if (cancelled ||
            (permission != LocationPermission.whileInUse &&
                permission != LocationPermission.always)) {
          return;
        }
        live = watchLocations().listen(
          events.add,
          onError: (Object error) {
            if (!cancelled) events.addError(error);
          },
        );
      } catch (error) {
        if (!cancelled) events.addError(error);
      }
    }());
    events.onCancel = () {
      cancelled = true;
      unawaited(live?.cancel());
    };
  });

  Future<bool> isEnabled() =>
      Geolocator.isLocationServiceEnabled().timeout(_timeout);
  Future<bool> isPermissionBlocked() async =>
      await Geolocator.checkPermission().timeout(_timeout) ==
      LocationPermission.deniedForever;
  Future<bool> openGpsSettings() => Geolocator.openLocationSettings();
  Future<bool> openPermissionSettings() => Geolocator.openAppSettings();

  Stream<SavedLocation> watchLocations() async* {
    final window = LocationFixWindow();
    await for (final p in Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.bestForNavigation,
        distanceFilter: 0,
      ),
    )) {
      final selected = window.add(
        SavedLocation(
          latitude: p.latitude,
          longitude: p.longitude,
          recordedAt: p.timestamp,
          accuracyMeters: p.accuracy,
        ),
      );
      if (selected != null) yield selected;
    }
  }

  /// Wait for multiple good fixes, or return the best real fix at the deadline.
  /// Stream cancellation releases GPS; poor fixes retain their reported accuracy.
  Future<SavedLocation?> collectFix(Stream<SavedLocation> fixes) async {
    SavedLocation? best;
    final window = LocationFixWindow();
    DateTime? firstGood;
    var goodCount = 0;
    final done = Completer<SavedLocation?>();
    final timer = Timer(
      gpsTimeout,
      () => done.complete(
        best != null && LocationFixWindow.valid(best!) ? best : null,
      ),
    );
    final sub = fixes.listen(
      (p) {
        if (!LocationFixWindow.valid(p) || done.isCompleted) return;
        best = window.add(p);
        if (LocationFixWindow.accuracy(p) <= 10) {
          firstGood ??= p.recordedAt;
          goodCount++;
          if (goodCount >= 3 &&
              p.recordedAt.difference(firstGood!) >=
                  const Duration(seconds: 2)) {
            done.complete(best);
          }
        }
      },
      onError: (Object _) {
        if (!done.isCompleted) done.complete(best);
      },
      onDone: () {
        if (!done.isCompleted) done.complete(best);
      },
    );
    try {
      return await done.future;
    } finally {
      timer.cancel();
      await sub.cancel();
    }
  }

  /// Chat sharing should not wait for navigation-grade convergence. Keep the
  /// reported uncertainty and timestamp; the confirmation UI shows both.
  Future<SavedLocation?> firstFix(
    Stream<SavedLocation> fixes, {
    Duration timeout = const Duration(seconds: 8),
  }) async {
    try {
      return await fixes
          .where(LocationFixWindow.valid)
          .timeout(timeout, onTimeout: (sink) => sink.close())
          .first;
    } on StateError {
      return null;
    }
  }

  Future<SavedLocation?> getQuickLocation() async {
    try {
      if (!await isEnabled()) return await _lastKnown();
      var permission = await Geolocator.checkPermission().timeout(_timeout);
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission().timeout(_timeout);
      }
      if (permission != LocationPermission.whileInUse &&
          permission != LocationPermission.always) {
        return null;
      }
      final cached = preparedLocation;
      if (cached != null) return cached;
      return await firstFix(emergencyLocations()) ?? await _lastKnown();
    } on Exception {
      return await _lastKnown();
    }
  }

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
        return await collectFix(watchLocations()) ?? await _lastKnown();
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
