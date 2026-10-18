import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sembast/sembast_memory.dart';

import 'package:offgrid_sos/app/theme.dart';
import 'package:offgrid_sos/app/theme_controller.dart';
import 'package:offgrid_sos/data/local/local_database.dart';
import 'package:offgrid_sos/data/models/local_sos_record.dart';
import 'package:offgrid_sos/data/repositories/sos_repository.dart';
import 'package:offgrid_sos/features/auth/login_screen.dart';
import 'package:offgrid_sos/features/home/home_shell.dart';
import 'package:offgrid_sos/features/nearby/nearby_screen.dart';
import 'package:offgrid_sos/features/profile/profile_screen.dart';
import 'package:offgrid_sos/features/sos/sos_screen.dart';
import 'package:offgrid_sos/features/rescue/rescue_screen.dart';
import 'package:offgrid_sos/models/user.dart';
import 'package:offgrid_sos/services/nearby_mesh_service.dart';
import 'package:offgrid_sos/services/location_service.dart';
import 'package:offgrid_sos/features/chat/nearby_conversation_screen.dart';
import 'package:offgrid_sos/widgets/location_actions.dart';

const guest = AppUser(
  id: 'preview-guest',
  firstName: 'พิมพ์ชนก',
  lastName: 'ใจดี',
  isMember: false,
  role: AppRole.guest,
);
const capture = bool.fromEnvironment('CAPTURE_UI');
final screenKey = GlobalKey();
String? previewFont;
late ThemeController uiController;

ThemeData theme(Brightness brightness) {
  final data = buildTheme(brightness: brightness);
  return previewFont == null
      ? data
      : data.copyWith(textTheme: data.textTheme.apply(fontFamily: previewFont));
}

Future<void> pumpScreen(
  WidgetTester tester,
  Widget screen, {
  Size size = const Size(390, 844),
  double textScale = 1,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    RepaintBoundary(
      key: screenKey,
      child: ThemeControllerScope(
        controller: uiController,
        child: ListenableBuilder(
          listenable: uiController,
          builder: (context, _) => MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: theme(Brightness.light),
            darkTheme: theme(Brightness.dark),
            themeMode: uiController.mode,
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: TextScaler.linear(textScale)),
              child: child!,
            ),
            home: Scaffold(body: screen),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> snapshot(WidgetTester tester, String name) async {
  if (!capture) return;
  final boundary =
      screenKey.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 2);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    final output = Directory('build/ui-previews');
    await output.create(recursive: true);
    await File(
      '${output.path}/$name.png',
    ).writeAsBytes(bytes!.buffer.asUint8List());
    image.dispose();
  });
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    // Optional local font is for review images only; it is not bundled in the app.
    if (capture) {
      final font = File('C:/Windows/Fonts/LeelawUI.ttf');
      if (await font.exists()) {
        final data = ByteData.sublistView(await font.readAsBytes());
        for (final family in ['PreviewThai', 'Roboto']) {
          final loader = FontLoader(family)..addFont(Future.value(data));
          await loader.load();
        }
        final icons = File(
          'C:/flutter/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
        );
        if (await icons.exists()) {
          final loader = FontLoader('MaterialIcons')
            ..addFont(
              Future.value(ByteData.sublistView(await icons.readAsBytes())),
            );
          await loader.load();
        }
        previewFont = 'PreviewThai';
      }
    }
  });
  setUp(() async {
    uiController = ThemeController();
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    await uiController.setMode(ThemeMode.light);
    await uiController.load();
  });

  test(
    'theme choice survives restarting the controller and rapid toggles',
    () async {
      final controller = ThemeController();
      await controller.setMode(ThemeMode.dark);
      final restored = ThemeController();
      await restored.load();
      expect(restored.mode, ThemeMode.dark);
      await Future.wait([
        controller.setMode(ThemeMode.light),
        controller.setMode(ThemeMode.dark),
        controller.setMode(ThemeMode.light),
      ]);
      await restored.load();
      expect(restored.mode, ThemeMode.light);
      controller.dispose();
      restored.dispose();
    },
  );

  test('both palettes keep readable body and secondary text', () {
    double ratio(Color a, Color b) {
      final x = a.computeLuminance(), y = b.computeLuminance();
      return x > y ? (x + .05) / (y + .05) : (y + .05) / (x + .05);
    }

    for (final p in [AppPalette.light, AppPalette.dark]) {
      expect(ratio(p.text, p.surface), greaterThanOrEqualTo(7));
      expect(ratio(p.muted, p.surface), greaterThanOrEqualTo(4.5));
      expect(ratio(p.muted, p.background), greaterThanOrEqualTo(4.5));
    }
  });

  testWidgets('login validates empty fields and theme toggle preserves input', (
    tester,
  ) async {
    await pumpScreen(tester, LoginScreen(onDone: (_) {}));
    await tester.enterText(
      find.byType(TextFormField).first,
      'person@example.com',
    );
    await tester.tap(find.byTooltip('เปลี่ยนเป็นโหมดมืด'));
    await tester.pumpAndSettle();
    expect(uiController.mode, ThemeMode.dark);
    expect(find.text('person@example.com'), findsOneWidget);
    await tester.ensureVisible(
      find.widgetWithText(FilledButton, 'เข้าสู่ระบบ'),
    );
    await tester.tap(find.widgetWithText(FilledButton, 'เข้าสู่ระบบ'));
    await tester.pumpAndSettle();
    expect(find.text('กรอกรหัสผ่านของคุณ'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('guest entry returns to the root and completes identity setup', (
    tester,
  ) async {
    AppUser? identity;
    await pumpScreen(tester, LoginScreen(onDone: (user) => identity = user));
    await tester.scrollUntilVisible(
      find.text('ใช้งานโดยไม่สมัครสมาชิก'),
      220,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('ใช้งานโดยไม่สมัครสมาชิก'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, 'นิดา');
    await tester.enterText(find.byType(TextField).last, 'ใจดี');
    await tester.ensureVisible(find.text('เริ่มใช้งานแบบไม่เป็นสมาชิก'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('เริ่มใช้งานแบบไม่เป็นสมาชิก'));
    await tester.pumpAndSettle();
    expect(identity?.firstName, 'นิดา');
    expect(identity?.isMember, isFalse);
    expect(find.text('เริ่มต้นโดยไม่สมัครสมาชิก'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  for (final mode in [ThemeMode.light, ThemeMode.dark]) {
    final suffix = mode == ThemeMode.light ? 'light' : 'dark';
    testWidgets('login $suffix renders on phone and with keyboard', (
      tester,
    ) async {
      await tester.runAsync(() => uiController.setMode(mode));
      await pumpScreen(tester, LoginScreen(onDone: (_) {}));
      await snapshot(tester, 'login_$suffix');
      await tester.showKeyboard(find.byType(TextFormField).last);
      tester.view.viewInsets = const FakeViewPadding(bottom: 300);
      addTearDown(tester.view.resetViewInsets);
      await tester.pumpAndSettle();
      await tester.ensureVisible(
        find.widgetWithText(FilledButton, 'เข้าสู่ระบบ'),
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('dashboard $suffix keeps SOS accessible and opens it', (
      tester,
    ) async {
      await tester.runAsync(() => uiController.setMode(mode));
      var opened = false;
      await pumpScreen(
        tester,
        HomeDashboard(
          me: guest,
          unreadCount: 0,
          sosRecords: Stream.value(const <LocalSosRecord>[]),
          onSos: () => opened = true,
          onRescue: () {},
          onNearby: () {},
          onChat: () {},
        ),
      );
      await snapshot(tester, 'home_$suffix');
      await tester.tap(find.text('เปิดหน้า SOS'));
      expect(opened, isTrue);
      expect(tester.takeException(), isNull);
    });

    testWidgets('profile $suffix provides a working appearance picker', (
      tester,
    ) async {
      await tester.runAsync(() => uiController.setMode(mode));
      await pumpScreen(tester, ProfileScreen(me: guest, onLogout: () async {}));
      await snapshot(tester, 'profile_$suffix');
      await tester.tap(find.text(mode == ThemeMode.light ? 'มืด' : 'สว่าง'));
      await tester.pumpAndSettle();
      expect(
        uiController.mode,
        mode == ThemeMode.light ? ThemeMode.dark : ThemeMode.light,
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('Nearby $suffix explains the empty state', (tester) async {
      await tester.runAsync(() => uiController.setMode(mode));
      await pumpScreen(tester, const NearbyScreen(me: guest));
      await snapshot(tester, 'nearby_$suffix');
      expect(find.text('ยังไม่มีอุปกรณ์ใกล้เคียง'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets(
      'SOS $suffix can open and cancel confirmation without sending',
      (tester) async {
        final db = await newDatabaseFactoryMemory().openDatabase('sos-ui');
        final repo = SosRepository(local: LocalDatabase.withDatabase(db));
        await tester.runAsync(() => uiController.setMode(mode));
        await pumpScreen(tester, SosScreen(me: guest, repository: repo));
        await snapshot(tester, 'sos_$suffix');
        await tester.tap(find.text('เปิด SOS · ขอความช่วยเหลือ'));
        await tester.pumpAndSettle();
        expect(find.text('เปิด SOS หรือไม่?'), findsOneWidget);
        await tester.tap(find.text('ยกเลิก'));
        await tester.pumpAndSettle();
        expect(await repo.latestActive(guest.id), isNull);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
        await db.close();
      },
    );
  }

  testWidgets('small phone and enlarged text keep login and dashboard usable', (
    tester,
  ) async {
    await pumpScreen(
      tester,
      LoginScreen(onDone: (_) {}),
      size: const Size(320, 640),
      textScale: 1.5,
    );
    await tester.scrollUntilVisible(
      find.text('ใช้งานโดยไม่สมัครสมาชิก'),
      220,
      scrollable: find.byType(Scrollable).first,
    );
    expect(tester.takeException(), isNull);
    await pumpScreen(
      tester,
      HomeDashboard(
        me: guest,
        unreadCount: 12,
        sosRecords: Stream.value(const <LocalSosRecord>[]),
        onSos: () {},
        onRescue: () {},
        onNearby: () {},
        onChat: () {},
      ),
      size: const Size(320, 640),
      textScale: 1.5,
    );
    await tester.scrollUntilVisible(
      find.text('ข้อความของคุณ'),
      220,
      scrollable: find.byType(Scrollable).first,
    );
    expect(tester.takeException(), isNull);
  });
  testWidgets('grouped home actions keep their own destinations', (
    tester,
  ) async {
    final actions = <String>[];
    await pumpScreen(
      tester,
      HomeDashboard(
        me: guest,
        unreadCount: 3,
        sosRecords: Stream.value(const <LocalSosRecord>[]),
        onSos: () => actions.add('sos'),
        onNearby: () => actions.add('nearby'),
        onChat: () => actions.add('chat'),
        onRescue: () => actions.add('rescue'),
      ),
    );
    for (final label in [
      'เปิดหน้า SOS',
      'คนใกล้เคียง',
      'ข้อความของคุณ',
      'หน่วยกู้ภัย',
    ]) {
      await tester.ensureVisible(find.text(label));
      await tester.tap(find.text(label));
      await tester.pump();
    }
    expect(actions, ['sos', 'nearby', 'chat', 'rescue']);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'compact appearance and SOS support large Thai text on small phones',
    (tester) async {
      await tester.runAsync(() => uiController.setMode(ThemeMode.dark));
      await pumpScreen(
        tester,
        ProfileScreen(me: guest, onLogout: () async {}),
        size: const Size(320, 640),
        textScale: 1.5,
      );
      await tester.ensureVisible(find.text('สว่าง'));
      await tester.tap(find.text('สว่าง'));
      await tester.pumpAndSettle();
      expect(uiController.mode, ThemeMode.light);
      expect(tester.takeException(), isNull);
      final db = await newDatabaseFactoryMemory().openDatabase('sos-small');
      final repo = SosRepository(local: LocalDatabase.withDatabase(db));
      await pumpScreen(
        tester,
        SosScreen(me: guest, repository: repo),
        size: const Size(320, 640),
        textScale: 1.5,
      );
      await tester.scrollUntilVisible(
        find.text('เปิด SOS · ขอความช่วยเหลือ'),
        180,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('เปิด SOS · ขอความช่วยเหลือ'));
      await tester.pumpAndSettle();
      expect(find.text('เปิด SOS หรือไม่?'), findsOneWidget);
      await tester.tap(find.text('ยกเลิก'));
      await tester.pumpAndSettle();
      expect(await repo.latestActive(guest.id), isNull);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await db.close();
    },
  );
  testWidgets('SOS with saved coordinates offers an actionable map button', (
    tester,
  ) async {
    final db = await newDatabaseFactoryMemory().openDatabase('sos-map-ui');
    final repo = SosRepository(local: LocalDatabase.withDatabase(db));
    await tester.runAsync(
      () => repo.create(
        user: guest,
        message: 'ทดสอบ SOS',
        location: SavedLocation(
          latitude: 14.1122,
          longitude: 100.6677,
          recordedAt: DateTime.now(),
        ),
      ),
    );
    await pumpScreen(tester, SosScreen(me: guest, repository: repo));
    await snapshot(tester, 'sos_active_yellow');
    expect(find.byType(LocationActions), findsWidgets);
    final button = tester.widget<OutlinedButton>(
      find.widgetWithText(OutlinedButton, 'เปิดตำแหน่งบนแผนที่').first,
    );
    expect(button.onPressed, isNotNull);
    await tester.pumpWidget(const SizedBox());
    await db.close();
  });

  testWidgets(
    'Nearby chat retains history and queues messages when disconnected',
    (tester) async {
      final db = await newDatabaseFactoryMemory().openDatabase(
        'nearby-chat-ui',
      );
      final mesh = NearbyMeshService.withDatabase(
        LocalDatabase.withDatabase(db),
      );
      await tester.runAsync(() => mesh.initializeForUser(guest));
      await tester.runAsync(
        () => mesh.chats.save(
          guest.id,
          'other-device',
          {
            'id': 'incoming-1',
            'kind': 'direct',
            'origin': 'other-device',
            'sender': 'เพื่อนร่วมทาง',
            'at': DateTime.now().toUtc().toIso8601String(),
            'data': {'text': 'ได้รับข้อความแล้ว', 'target': mesh.deviceId},
          },
          incoming: true,
          delivery: 'delivered',
        ),
      );
      await pumpScreen(
        tester,
        NearbyConversationScreen(
          me: guest,
          peerId: 'other-device',
          name: 'เพื่อนร่วมทาง',
          service: mesh,
        ),
      );
      expect(find.text('ได้รับข้อความแล้ว'), findsOneWidget);
      await tester.tap(find.byTooltip('แนบรูปหรือวิดีโอ'));
      await tester.pumpAndSettle();
      expect(find.text('ถ่ายรูป'), findsOneWidget);
      expect(find.text('รูปภาพจากเครื่อง'), findsOneWidget);
      expect(find.text('วิดีโอจากเครื่อง'), findsOneWidget);
      Navigator.of(tester.element(find.text('ถ่ายรูป'))).pop();
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'ฉันอยู่ตรงนี้');
      await tester.runAsync(() async {
        await tester.tap(find.byTooltip('ส่งข้อความ'));
        await Future<void>.delayed(const Duration(milliseconds: 80));
      });
      await tester.pumpAndSettle();
      expect(
        await tester.runAsync(
          () => mesh.chats.pending(guest.id, 'other-device'),
        ),
        hasLength(1),
      );
      expect(find.text('ฉันอยู่ตรงนี้'), findsOneWidget);
      await snapshot(tester, 'nearby_chat_yellow');
      await tester.pumpWidget(const SizedBox());
      mesh.dispose();
      await db.close();
    },
  );

  testWidgets('offline photo opens from a local file with large text', (
    tester,
  ) async {
    final db = await newDatabaseFactoryMemory().openDatabase('local-photo-ui');
    final mesh = NearbyMeshService.withDatabase(LocalDatabase.withDatabase(db));
    await tester.runAsync(() async {
      await mesh.initializeForUser(guest);
      await mesh.chats.save(
        guest.id,
        'photo-peer',
        {
          'id': 'photo-ui-1',
          'kind': 'media',
          'origin': 'photo-peer',
          'sender': 'เพื่อน',
          'at': DateTime.now().toUtc().toIso8601String(),
          'data': {
            'type': 'image',
            'name': 'ภาพในเครื่อง.png',
            'size': 8192,
            'target': mesh.deviceId,
          },
        },
        incoming: true,
        delivery: 'delivered',
        localPath: File('assets/branding/offgrid-icon.png').absolute.path,
      );
    });
    await tester.pumpWidget(const MaterialApp(home: SizedBox()));
    final imageProvider = ResizeImage(
      FileImage(File('assets/branding/offgrid-icon.png').absolute),
      width: 720,
    );
    await tester.runAsync(
      () => precacheImage(
        imageProvider,
        tester.element(find.byType(SizedBox).first),
      ),
    );
    await pumpScreen(
      tester,
      NearbyConversationScreen(
        me: guest,
        peerId: 'photo-peer',
        name: 'เพื่อน',
        service: mesh,
      ),
      size: const Size(320, 640),
      textScale: 1.5,
    );
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 80));
    });
    await tester.pumpAndSettle();
    expect(find.text('ภาพในเครื่อง.png'), findsOneWidget);
    expect(
      tester.widget<RawImage>(find.byType(RawImage).first).image,
      isNotNull,
    );
    expect(tester.takeException(), isNull);
    await snapshot(tester, 'nearby_photo_v5');
    await tester.ensureVisible(find.byType(Image).first);
    await tester.pumpAndSettle();
    final visiblePhoto = tester
        .getRect(find.byType(Image).first)
        .intersect(tester.getRect(find.byType(ListView).first));
    expect(visiblePhoto.height, greaterThan(0));
    await tester.tapAt(visiblePhoto.center);
    await tester.pumpAndSettle();
    expect(find.byType(InteractiveViewer), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    mesh.dispose();
    await db.close();
  });

  for (final dark in [false, true]) {
    testWidgets(
      'rescue mode uses blue and toggles duty in ${dark ? 'dark' : 'light'} appearance',
      (tester) async {
        const rescuer = AppUser(
          id: 'verified-rescue',
          firstName: 'หน่วยกู้ภัย',
          lastName: 'ทดสอบ',
          isMember: true,
          role: AppRole.rescuer,
        );
        final db = await newDatabaseFactoryMemory().openDatabase(
          'rescue-blue-$dark',
        );
        late NearbyMeshService mesh;
        await tester.runAsync(() async {
          await uiController.setMode(dark ? ThemeMode.dark : ThemeMode.light);
          mesh = NearbyMeshService.withDatabase(LocalDatabase.withDatabase(db));
          await mesh.initializeForUser(rescuer);
        });
        mesh.running =
            true; // Stub radio state; no native discovery in a widget test.
        await pumpScreen(tester, RescueScreen(me: rescuer, service: mesh));
        final localTheme = Theme.of(
          tester.element(find.text('RESCUE MODE · หน่วยกู้ภัย')),
        );
        expect(
          localTheme.scaffoldBackgroundColor,
          dark ? AppPalette.dark.background : AppPalette.light.background,
        );
        await tester.runAsync(() async {
          await tester.tap(find.text('เริ่มปฏิบัติหน้าที่'));
          await Future<void>.delayed(const Duration(milliseconds: 30));
        });
        await tester.pumpAndSettle();
        expect(mesh.rescueActive, isTrue);
        expect(
          Theme.of(
            tester.element(find.text('RESCUE MODE · หน่วยกู้ภัย')),
          ).scaffoldBackgroundColor,
          dark ? AppPalette.dark.background : AppPalette.light.background,
        );
        expect(
          tester
              .widget<Card>(
                find
                    .ancestor(
                      of: find.text('RESCUE MODE · หน่วยกู้ภัย'),
                      matching: find.byType(Card),
                    )
                    .first,
              )
              .color,
          const Color(0xFF1859A9),
        );
        expect(find.text('กำลังปฏิบัติหน้าที่'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await snapshot(
          tester,
          dark ? 'rescue_active_dark' : 'rescue_active_light',
        );
        await tester.runAsync(() async {
          await tester.tap(find.text('หยุดปฏิบัติหน้าที่'));
          await Future<void>.delayed(const Duration(milliseconds: 30));
        });
        await tester.pumpAndSettle();
        expect(mesh.rescueActive, isFalse);
        expect(
          tester
              .widget<Card>(
                find
                    .ancestor(
                      of: find.text('RESCUE MODE · หน่วยกู้ภัย'),
                      matching: find.byType(Card),
                    )
                    .first,
              )
              .color,
          dark ? AppPalette.dark.surface : AppPalette.light.surface,
        );
        await tester.pumpWidget(const SizedBox());
        mesh.dispose();
        await db.close();
      },
    );
  }

  testWidgets(
    'remote rescue card is blue only while active and SOS opens chat directly',
    (tester) async {
      late Database db;
      late NearbyMeshService mesh;
      await tester.runAsync(() async {
        db = await newDatabaseFactoryMemory().openDatabase('nearby-status-ui');
        mesh = NearbyMeshService.withDatabase(
          LocalDatabase.withDatabase(db),
          sendBytes: (_, _) async {},
        );
        await mesh.initializeForUser(guest);
        mesh.connected.add('endpoint');
        mesh.identities['endpoint'] = const NearbyPeer(
          endpoint: 'endpoint',
          deviceId: 'rescue-device',
          name: 'Rescue Team',
        );
        mesh.inbox.add(
          MeshMessage({
            'kind': 'rescue',
            'origin': 'rescue-device',
            'sender': 'Rescue Team',
            'data': {'active': true, 'revision': 1},
          }),
        );
        mesh.inbox.add(
          MeshMessage({
            'kind': 'sos',
            'origin': 'victim',
            'sender': 'Victim',
            'data': {'caseId': 'sos-test', 'active': true, 'text': 'Need help'},
          }),
        );
      });
      await pumpScreen(tester, NearbyScreen(me: guest, service: mesh));
      await tester.scrollUntilVisible(
        find.text('Rescue Team'),
        180,
        scrollable: find.byType(Scrollable).first,
      );
      final card = tester.widget<Card>(
        find
            .ancestor(of: find.text('Rescue Team'), matching: find.byType(Card))
            .first,
      );
      expect(card.color, const Color(0xFF1859A9));
      mesh.inbox.removeWhere((m) => m.kind == 'rescue');
      mesh.inbox.add(
        MeshMessage({
          'kind': 'rescue',
          'origin': 'rescue-device',
          'data': {'active': false, 'revision': 2},
        }),
      );
      mesh.notifyListeners();
      await tester.pumpAndSettle();
      expect(find.text('เปิดโหมดกู้ภัย • แตะเพื่อแชท'), findsNothing);
      await tester.scrollUntilVisible(
        find.text('SOS · Victim'),
        180,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.text('SOS · Victim'));
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 30));
      });
      await tester.pumpAndSettle();
      expect(find.byType(NearbyConversationScreen), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      mesh.dispose();
      await tester.runAsync(() => db.close());
    },
  );

  testWidgets('ordinary user cannot activate rescue mode', (tester) async {
    await pumpScreen(tester, const RescueScreen(me: guest));
    expect(
      find.text('บัญชีนี้ยังไม่มีสิทธิ์ผู้ช่วยเหลือที่ผ่านการยืนยัน'),
      findsOneWidget,
    );
    expect(find.text('เริ่มปฏิบัติหน้าที่'), findsNothing);
  });

  testWidgets('standalone Nearby route handles dark mode and enlarged text', (
    tester,
  ) async {
    await tester.runAsync(() => uiController.setMode(ThemeMode.dark));
    await pumpScreen(
      tester,
      const NearbyScreen(me: guest),
      size: const Size(320, 640),
      textScale: 1.5,
    );
    await tester.scrollUntilVisible(
      find.text('ใช้ Bluetooth เมื่อปิด Wi-Fi'),
      160,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
