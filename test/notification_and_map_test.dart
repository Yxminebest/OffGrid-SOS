import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:offgrid_sos/services/app_notifications.dart';
import 'package:offgrid_sos/widgets/location_actions.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
    AppNotifications.instance.foreground = true;
    AppNotifications.instance.activeThread = null;
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
    'location sheet shows coordinates and copies them without opening Maps',
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
        const MaterialApp(
          home: Scaffold(
            body: LocationActions(latitude: 13.730000, longitude: 100.541000),
          ),
        ),
      );
      await tester.tap(find.text('เปิดตำแหน่งบนแผนที่'));
      await tester.pumpAndSettle();
      expect(find.text('13.730000, 100.541000'), findsOneWidget);
      expect(find.text('เปิดแอปแผนที่'), findsOneWidget);
      await tester.tap(find.text('คัดลอกพิกัด'));
      await tester.pumpAndSettle();
      expect(copied, '13.730000, 100.541000');
      await tester.pumpWidget(const SizedBox());
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null);
    },
  );
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
