import 'dart:convert';
import 'dart:async';
import 'dart:ui' as ui;
import 'package:flutter_map/flutter_map.dart';
import 'package:offgrid_sos/widgets/location_map_screen.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:offgrid_sos/services/app_notifications.dart';
import 'package:offgrid_sos/widgets/location_actions.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'chat notification carries owner, thread and transport and tap is consumed once',
    () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      final calls = <MethodCall>[];
      Map<String, String>? pending;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(AppNotifications.channel, (call) async {
            calls.add(call);
            if (call.method == 'takeChatTap') {
              final tap = pending;
              pending = null;
              return tap;
            }
            return null;
          });
      final notifications = AppNotifications();
      for (final transport in ['nearby', 'cloud']) {
        await notifications.show(
          id: 'message-$transport',
          title: 'B',
          text: 'hello',
          owner: 'account',
          thread: 'room-$transport',
          transport: transport,
        );
        final arguments = calls.last.arguments as Map;
        expect(arguments['owner'], 'account');
        expect(arguments['thread'], 'room-$transport');
        expect(arguments['transport'], transport);
        pending = {
          'owner': 'account',
          'thread': 'room-$transport',
          'transport': transport,
        };
        expect(
          (await notifications.takeChatTap())?['thread'],
          'room-$transport',
        );
        expect(await notifications.takeChatTap(), isNull);
      }
      pending = {'owner': 'account', 'thread': 'bad', 'transport': 'unknown'};
      expect(await notifications.takeChatTap(), isNull);
    },
  );
  test(
    'foreground notification tap wakes Flutter without a lifecycle resume',
    () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      final notifications = AppNotifications();
      notifications.listenForTaps();
      final response = Completer<void>();
      ui.channelBuffers.push(
        AppNotifications.channel.name,
        const StandardMethodCodec().encodeMethodCall(
          const MethodCall('notificationTap'),
        ),
        (_) => response.complete(),
      );
      await response.future;
      expect(notifications.taps.value, 1);
      AppNotifications.channel.setMethodCallHandler(null);
    },
  );
  test(
    'notification sound persists via native settings independently of background receiving',
    () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      var savedSound = true;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(AppNotifications.channel, (call) async {
            if (call.method == 'setNotificationSound') {
              savedSound = (call.arguments as Map)['enabled'] as bool;
              return savedSound;
            }
            if (call.method == 'notificationSound') return savedSound;
            if (call.method == 'notificationsEnabled') return true;
            return null;
          });
      final notifications = AppNotifications();
      notifications.background.value = true;
      await notifications.setSound(false);
      expect(notifications.sound.value, isFalse);
      expect(notifications.background.value, isTrue);
      final reopened = AppNotifications();
      await reopened.refresh();
      expect(reopened.sound.value, isFalse);
      await reopened.setSound(true);
      expect(reopened.sound.value, isTrue);
    },
  );
  test(
    'SOS notification carries device and account, tap is consumed once',
    () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      final calls = <MethodCall>[];
      var taken = false;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(AppNotifications.channel, (call) async {
            calls.add(call);
            if (call.method == 'takeSosTap' && !taken) {
              taken = true;
              return {'device': 'peer-device', 'owner': 'my-account'};
            }
            return null;
          });
      await AppNotifications.instance.show(
        id: 'sos:peer:case',
        title: 'SOS',
        text: 'ต้องการยา',
        sosDevice: 'peer-device',
        owner: 'my-account',
      );
      expect((calls.first.arguments as Map)['owner'], 'my-account');
      expect((calls.first.arguments as Map)['sosDevice'], 'peer-device');
      expect(await AppNotifications.instance.takeSosTap(), {
        'device': 'peer-device',
        'owner': 'my-account',
      });
      expect(await AppNotifications.instance.takeSosTap(), isNull);
    },
  );
  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
    AppNotifications.instance.foreground = true;
    AppNotifications.instance.activeThread = null;
    AppNotifications.instance.activeThreadAliases.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(AppNotifications.channel, null);
  });
  test('map opens geo coordinates first and falls back to a browser', () async {
    final attempted = <Uri>[];
    final result = await LocationActions.open(
      14.11,
      100.66,
      launcher: (uri) async {
        attempted.add(uri);
        return uri.scheme == 'https';
      },
    );
    expect(result, isTrue);
    expect(attempted.first.scheme, 'geo');
    expect(attempted.last.queryParameters['query'], '14.11,100.66');
  });
  test('invalid coordinates never launch another app', () async {
    var launched = false;
    expect(
      await LocationActions.open(
        double.nan,
        100,
        launcher: (_) async {
          launched = true;
          return true;
        },
      ),
      isFalse,
    );
    expect(launched, isFalse);
  });

  testWidgets(
    'location opens an internal map and copies coordinates without another app',
    (tester) async {
      String? copied;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, (call) async {
            if (call.method == 'Clipboard.setData') {
              copied = (call.arguments as Map)['text'];
            }
            return null;
          });
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => LocationActions.show(
                  context,
                  13.73,
                  100.541,
                  tileProvider: _TestTiles(),
                ),
                child: const Text('เปิดตำแหน่งบนแผนที่'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('เปิดตำแหน่งบนแผนที่'));
      await tester.pumpAndSettle();
      expect(find.text('13.730000, 100.541000'), findsOneWidget);
      expect(find.byType(FlutterMap), findsOneWidget);
      expect(find.text('ตำแหน่งบนแผนที่'), findsOneWidget);
      final marker = tester
          .widget<MarkerLayer>(find.byType(MarkerLayer))
          .markers
          .single;
      expect(marker.point.latitude, 13.73);
      expect(marker.point.longitude, 100.541);
      await tester.tap(find.text('คัดลอกพิกัด'));
      await tester.pumpAndSettle();
      expect(copied, '13.730000, 100.541000');
      await tester.pumpWidget(const SizedBox());
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null);
    },
  );
  testWidgets(
    'map controls preserve the saved point and recover tile failures',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: LocationMapScreen(
            latitude: 13.73,
            longitude: 100.541,
            tileProvider: _TestTiles(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      var layer = tester.widget<TileLayer>(find.byType(TileLayer));
      layer.errorTileCallback!(
        _FakeTile(),
        StateError('offline'),
        StackTrace.current,
      );
      await tester.pump();
      await tester.pump();
      expect(find.textContaining('โหลดภาพแผนที่บางส่วนไม่ได้'), findsOneWidget);
      expect(find.text('13.730000, 100.541000'), findsOneWidget);
      await tester.ensureVisible(find.text('ลองโหลดแผนที่อีกครั้ง'));
      await tester.tap(find.text('ลองโหลดแผนที่อีกครั้ง'));
      await tester.pumpAndSettle();
      expect(find.textContaining('โหลดภาพแผนที่บางส่วนไม่ได้'), findsNothing);
      await tester.tap(find.byTooltip('ซูมเข้า'));
      await tester.pumpAndSettle();
      final map = tester.widget<FlutterMap>(find.byType(FlutterMap));
      expect(map.mapController!.camera.zoom, 17);
      await tester.tap(find.byTooltip('กลับไปยังหมุด'));
      await tester.pumpAndSettle();
      expect(map.mapController!.camera.zoom, 16);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('map fits a small screen with large text', (tester) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: const TextScaler.linear(1.8)),
          child: child!,
        ),
        home: LocationMapScreen(
          latitude: 13.73,
          longitude: 100.541,
          tileProvider: _TestTiles(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.byType(FlutterMap), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
  test(
    'active foreground thread suppresses alerts but background receipt posts a notification',
    () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      final calls = <MethodCall>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(AppNotifications.channel, (call) async {
            calls.add(call);
            return null;
          });
      final notifications = AppNotifications.instance;
      notifications.foreground = true;
      notifications.activeThread = 'peer';
      await notifications.show(
        id: 'm1',
        title: 'Peer',
        text: 'hello',
        thread: 'peer',
      );
      expect(calls, isEmpty);
      notifications.foreground = false;
      await notifications.show(
        id: 'm2',
        title: 'Peer',
        text: 'background text',
        thread: 'peer',
      );
      expect(calls.single.method, 'showMessage');
      expect((calls.single.arguments as Map)['text'], 'background text');
    },
  );
  test(
    'unified active room suppresses both radio and cloud alerts only in foreground',
    () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      final calls = <MethodCall>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(AppNotifications.channel, (call) async {
            calls.add(call);
            return null;
          });
      final n = AppNotifications.instance;
      n.activeThreadAliases.addAll(['device-peer', 'cloud-conversation']);
      n.foreground = true;
      for (final thread in ['device-peer', 'cloud-conversation']) {
        await n.show(
          id: 'same-id',
          title: 'Peer',
          text: 'hello',
          thread: thread,
        );
      }
      expect(calls, isEmpty);
      n.foreground = false;
      await n.show(
        id: 'same-id',
        title: 'Peer',
        text: 'hello',
        thread: 'cloud-conversation',
      );
      expect(calls, hasLength(1));
    },
  );
  test('notification platform failures do not lose chat processing', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(AppNotifications.channel, (_) async {
          throw PlatformException(code: 'denied');
        });
    await AppNotifications.instance.show(
      id: 'm',
      title: 'Peer',
      text: 'retained',
    );
  });
}

class _TestTiles extends TileProvider {
  @override
  ImageProvider getImage(
    TileCoordinates coordinates,
    TileLayer options,
  ) => MemoryImage(
    base64Decode(
      'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=',
    ),
  );
}

class _FakeTile extends Fake implements TileImage {}
