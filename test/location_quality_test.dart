import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:offgrid_sos/services/location_service.dart';

SavedLocation fix(double accuracy, {double lat = 14, int seconds = 0}) =>
    SavedLocation(
      latitude: lat,
      longitude: 100,
      accuracyMeters: accuracy,
      recordedAt: DateTime.now().subtract(Duration(seconds: seconds)),
    );
void main() {
  test(
    'poor jitter keeps recent real better fix without changing accuracy or time',
    () {
      final window = LocationFixWindow();
      final good = fix(5);
      expect(window.add(good), same(good));
      expect(window.add(fix(49, lat: 14.0001)), same(good));
      expect(good.accuracyMeters, 5);
      final newer = fix(3);
      expect(window.add(newer), same(newer));
    },
  );
  test('real movement and expired window do not freeze old position', () {
    final window = LocationFixWindow();
    window.add(fix(5, seconds: 9));
    final moved = fix(8, lat: 14.001);
    expect(window.add(moved), same(moved));
    final farther = fix(8, lat: 14.002);
    expect(window.add(farther), same(farther));
    expect(window.add(fix(1, seconds: 60)), isNull);
    expect(window.add(fix(1, lat: double.nan)), isNull);
  });
  test('collection selects best fix and cancels stream at deadline', () async {
    var cancelled = false;
    final stream = StreamController<SavedLocation>(
      onCancel: () {
        cancelled = true;
      },
    );
    final result = const LocationService(
      gpsTimeout: Duration(milliseconds: 30),
    ).collectFix(stream.stream);
    stream.add(fix(49));
    stream.add(fix(6));
    stream.add(fix(70));
    expect((await result)!.accuracyMeters, 6);
    expect(cancelled, isTrue);
    await stream.close();
  });
  test(
    'no readings returns null, stream failure keeps real poor accuracy',
    () async {
      expect(
        await const LocationService().collectFix(const Stream.empty()),
        isNull,
      );
      final result = await const LocationService().collectFix(
        Stream.fromIterable([fix(49)]),
      );
      expect(result!.accuracyMeters, 49);
    },
  );
  test(
    'three distinct good fixes settle early without lowering reported accuracy',
    () async {
      var cancelled = false;
      final stream = StreamController<SavedLocation>(
        onCancel: () {
          cancelled = true;
        },
      );
      final result = const LocationService().collectFix(stream.stream);
      stream.add(fix(8, seconds: 2));
      stream.add(fix(7, seconds: 1));
      stream.add(fix(6));
      expect((await result)!.accuracyMeters, 6);
      expect(cancelled, isTrue);
      await stream.close();
    },
  );
}
