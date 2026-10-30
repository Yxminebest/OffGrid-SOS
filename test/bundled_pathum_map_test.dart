import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_map_vector_tiles/flutter_map_vector_tiles.dart' as vt;
import 'package:flutter_map_vector_tiles/src/render/tile_rasterizer.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:offgrid_sos/services/bundled_pathum_map.dart';
import 'package:offgrid_sos/services/location_service.dart';
import 'package:offgrid_sos/widgets/location_map_screen.dart';

class _Gps extends LocationService {
  _Gps({
    this.enabled = true,
    this.blocked = false,
    this.stale = false,
    this.outside = false,
    this.accuracy = 12,
  });
  final bool enabled, blocked, stale, outside;
  final double accuracy;
  bool opened = false;
  @override
  Stream<SavedLocation> watchLocations() => const Stream.empty();
  @override
  Future<bool> isEnabled() async => enabled;
  @override
  Future<bool> isPermissionBlocked() async => blocked;
  @override
  Future<bool> openGpsSettings() async => opened = true;
  @override
  Future<bool> openPermissionSettings() async => opened = true;
  @override
  Future<SavedLocation?> getLatestLocation() async => blocked
      ? null
      : SavedLocation(
          latitude: outside ? 12 : 14.05,
          longitude: 100.65,
          recordedAt: DateTime.now().subtract(
            stale ? const Duration(hours: 1) : Duration.zero,
          ),
          accuracyMeters: accuracy,
          isLastKnown: stale,
        );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late BundledPathumMap data;
  setUpAll(() async {
    data = await BundledPathumMap.load();
    final font = FontLoader('NotoSansThai')
      ..addFont(rootBundle.load('${BundledPathumMap.folder}/NotoSansThai.ttf'));
    await font.load();
    await (FontLoader(
      'MaterialIcons',
    )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
  });

  test(
    'bundled pack passes digest and serves every indexed tile without HTTP',
    () async {
      expect(data.tiles.length, 783);
      final provider = data.provider();
      expect(provider.cacheBytesToDisk, isFalse);
      expect(provider.maximumZoom, 14);
      for (final key in data.tiles.keys) {
        final response = await provider.load(key);
        expect(response, isA<vt.TileResponseData>());
        final bytes = (response as vt.TileResponseData).bytes;
        expect(gzip.decode(bytes).length, greaterThan(10));
      }
      expect(
        await provider.load(const vt.TileKey(14, 0, 0)),
        isA<vt.TileResponseNotFound>(),
      );
      for (final point in [
        const LatLng(13.91628, 100.33161),
        const LatLng(14.27603, 100.95206),
        const LatLng(14.05, 100.65),
      ]) {
        expect(BundledPathumMap.contains(point), isTrue);
      }
      expect(BundledPathumMap.contains(const LatLng(13.73, 100.54)), isFalse);
    },
  );

  test(
    'both styles compile every layer, have Thai fonts and no remote dependencies',
    () async {
      for (final mode in ['light', 'dark']) {
        final raw =
            jsonDecode(
                  await rootBundle.loadString(
                    '${BundledPathumMap.folder}/$mode.json',
                  ),
                )
                as Map<String, dynamic>;
        final warnings = <String>[];
        final theme = vt.ThemeReader(
          logger: vt.Logger.custom(onWarn: warnings.add),
        ).read(raw);
        expect(warnings, isEmpty);
        expect(theme.layers.length, (raw['layers'] as List).length);
        expect(raw.containsKey('glyphs'), isFalse);
        expect(raw.containsKey('sprite'), isFalse);
        expect(raw.toString(), isNot(contains('http')));
        expect(raw.toString(), contains('NotoSansThai'));
      }
    },
  );

  Future<void> render(
    WidgetTester tester,
    _Gps gps, {
    bool dark = false,
    bool overview = false,
  }) async {
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(
          brightness: dark ? Brightness.dark : Brightness.light,
          fontFamily: 'NotoSansThai',
        ),
        home: overview
            ? LocationMapScreen.overview(locationService: gps)
            : LocationMapScreen(
                latitude: 14.05,
                longitude: 100.65,
                locationService: gps,
              ),
      ),
    );
    // Real vector decoding/rasterizing uses background isolates and wall time.
    for (var i = 0; i < 30; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(find.byType(vt.VectorTileLayer), findsOneWidget);
    expect(find.byType(TileLayer), findsNothing); // no raster HTTP fallback
    expect(tester.takeException(), isNull);
    expect(TileRasterizer.debugRasterizeCount, greaterThan(0));
  }

  for (final dark in [false, true]) {
    testWidgets(
      'real offline streets render and GPS marker appears (${dark ? 'dark' : 'light'})',
      (tester) async {
        await render(tester, _Gps(), dark: dark);
        await tester.tap(find.text('หาตำแหน่งของฉัน (GPS)'));
        await tester.pump(const Duration(milliseconds: 300));
        expect(find.text('หมุดสีน้ำเงิน: ตำแหน่งของคุณ'), findsOneWidget);
        expect(
          tester.widget<MarkerLayer>(find.byType(MarkerLayer)).markers.length,
          2,
        );
        expect(find.byType(CircleLayer), findsOneWidget);
        if (const bool.fromEnvironment('CAPTURE_UI')) {
          final boundary = tester.firstRenderObject<RenderRepaintBoundary>(
            find.byType(RepaintBoundary).first,
          );
          await tester.runAsync(() async {
            final image = await boundary.toImage(pixelRatio: 1);
            final png = await image.toByteData(format: ui.ImageByteFormat.png);
            final file = File(
              'build/ui-previews/pathum-${dark ? 'dark' : 'light'}.png',
            );
            await file.parent.create(recursive: true);
            await file.writeAsBytes(png!.buffer.asUint8List());
            image.dispose();
          });
        }
        await tester.pumpWidget(const SizedBox());
      },
    );
  }

  testWidgets('poor GPS shows honest uncertainty and recenters on own pin', (
    tester,
  ) async {
    await render(tester, _Gps(accuracy: 49), overview: true);
    await tester.tap(find.text('หาตำแหน่งของฉัน (GPS)'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.textContaining('GPS ยังหยาบ:'), findsOneWidget);
    expect(
      find.text('วงกลมแสดงความไม่แน่นอนของ GPS ไม่ใช่ระยะที่คุณเดิน'),
      findsOneWidget,
    );
    await tester.tap(find.byTooltip('กลับไปยังหมุด'));
    await tester.pump();
    final map = tester.widget<FlutterMap>(find.byType(FlutterMap));
    expect(map.mapController!.camera.center.latitude, closeTo(14.05, .00001));
    expect(map.mapController!.camera.zoom, 15);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'GPS disabled retains real map and exposes system setting with stale warning',
    (tester) async {
      final gps = _Gps(enabled: false, stale: true);
      await render(tester, gps);
      await tester.tap(find.text('หาตำแหน่งของฉัน (GPS)'));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.textContaining('GPS ปิดอยู่'), findsOneWidget);
      expect(find.textContaining('ไม่ใช่ GPS ปัจจุบัน'), findsOneWidget);
      expect(find.byType(CircleLayer), findsNothing);
      await tester.ensureVisible(find.text('เปิดการตั้งค่า GPS'));
      await tester.tap(find.text('เปิดการตั้งค่า GPS'));
      expect(gps.opened, isTrue);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'denied permission offers app settings and does not invent a position',
    (tester) async {
      final gps = _Gps(blocked: true);
      await render(tester, gps);
      await tester.tap(find.text('หาตำแหน่งของฉัน (GPS)'));
      await tester.pump(const Duration(milliseconds: 300));
      expect(
        tester.widget<MarkerLayer>(find.byType(MarkerLayer)).markers.length,
        1,
      );
      await tester.ensureVisible(find.text('เปิดสิทธิ์ตำแหน่ง'));
      await tester.tap(find.text('เปิดสิทธิ์ตำแหน่ง'));
      expect(gps.opened, isTrue);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'province overview has no fabricated destination and explains outside GPS coverage',
    (tester) async {
      await render(tester, _Gps(outside: true), overview: true);
      if (const bool.fromEnvironment('CAPTURE_UI')) {
        final boundary = tester.firstRenderObject<RenderRepaintBoundary>(
          find.byType(RepaintBoundary).first,
        );
        await tester.runAsync(() async {
          final image = await boundary.toImage(pixelRatio: 1);
          final png = await image.toByteData(format: ui.ImageByteFormat.png);
          await File(
            'build/ui-previews/pathum-overview.png',
          ).writeAsBytes(png!.buffer.asUint8List());
          image.dispose();
        });
      }
      expect(
        tester.widget<MarkerLayer>(find.byType(MarkerLayer)).markers,
        isEmpty,
      );
      await tester.tap(find.text('หาตำแหน่งของฉัน (GPS)'));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.textContaining('อยู่นอกชุดแผนที่ปทุมธานี'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('offline map remains usable on a small display with large text', (
    tester,
  ) async {
    await render(tester, _Gps());
    tester.view.physicalSize = const Size(320, 640);
    tester.platformDispatcher.textScaleFactorTestValue = 1.8;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await tester.pump(const Duration(milliseconds: 300));
    expect(tester.takeException(), isNull);
    await tester.ensureVisible(find.text('หาตำแหน่งของฉัน (GPS)'));
    await tester.tap(find.text('หาตำแหน่งของฉัน (GPS)'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('หมุดสีน้ำเงิน: ตำแหน่งของคุณ'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}
