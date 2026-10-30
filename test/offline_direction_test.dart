import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:offgrid_sos/services/location_service.dart';
import 'package:offgrid_sos/widgets/offline_location_guide.dart';

class _Gps extends LocationService {
  _Gps({this.available = true});
  final bool available;
  @override
  Future<SavedLocation?> getLatestLocation() async => available
      ? SavedLocation(
          latitude: 0,
          longitude: 0,
          recordedAt: DateTime.utc(2026, 10, 19),
          accuracyMeters: 10,
          isLastKnown: true,
        )
      : null;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'distance and north/east bearings are calculated entirely from coordinates',
    () {
      final origin = SavedLocation(
        latitude: 0,
        longitude: 0,
        recordedAt: DateTime.utc(2026),
      );
      final north = OfflineDirection(origin, 1, 0);
      expect(north.meters, closeTo(111195, 1000));
      expect(north.cardinal, 'เหนือ');
      expect(north.degrees, closeTo(0, .01));
      final east = OfflineDirection(origin, 0, 1);
      expect(east.cardinal, 'ตะวันออก');
      expect(east.degrees, closeTo(90, .01));
    },
  );

  testWidgets(
    'offline GPS guide shows distance, direction and stale-location warning',
    (tester) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: const TextScaler.linear(1.5)),
            child: child!,
          ),
          home: OfflineLocationGuide(
            latitude: 0,
            longitude: 1,
            locationService: _Gps(),
          ),
        ),
      );
      await tester.tap(find.text('คำนวณจากตำแหน่งของฉัน'));
      await tester.pumpAndSettle();
      expect(find.textContaining('ทิศตะวันออก'), findsOneWidget);
      expect(find.textContaining('ระยะเส้นตรงประมาณ'), findsOneWidget);
      expect(find.textContaining('ใช้พิกัดเก่าที่บันทึกไว้'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'missing GPS leaves target coordinates readable and permits retry',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: OfflineLocationGuide(
            latitude: 13.73,
            longitude: 100.541,
            locationService: _Gps(available: false),
          ),
        ),
      );
      await tester.tap(find.text('คำนวณจากตำแหน่งของฉัน'));
      await tester.pumpAndSettle();
      expect(find.textContaining('ยังหาตำแหน่งของคุณไม่ได้'), findsOneWidget);
      expect(find.text('13.730000, 100.541000'), findsOneWidget);
      expect(
        tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNotNull,
      );
    },
  );
}
