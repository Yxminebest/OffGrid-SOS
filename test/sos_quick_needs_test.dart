import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sembast/sembast_memory.dart';
import 'package:offgrid_sos/data/local/local_database.dart';
import 'package:offgrid_sos/data/repositories/sos_repository.dart';
import 'package:offgrid_sos/features/sos/sos_screen.dart';
import 'package:offgrid_sos/features/chat/nearby_conversation_screen.dart';
import 'package:offgrid_sos/models/user.dart';
import 'package:offgrid_sos/services/location_service.dart';
import 'package:offgrid_sos/services/nearby_mesh_service.dart';
import 'package:offgrid_sos/widgets/sos_message_dialog.dart';

const guest = AppUser(
  id: 'quick-guest',
  firstName: 'Guest',
  lastName: '',
  isMember: false,
);

class _NoGps extends LocationService {
  @override
  Future<SavedLocation?> getLatestLocation() async => null;
  @override
  Stream<SavedLocation> emergencyLocations() => const Stream.empty();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'multiple urgent needs are combined in a stable order without network data',
    () {
      expect(
        composeSosMessage({'ต้องการยา', 'ติดอยู่บนหลังคา'}, '  มีเด็กด้วย  '),
        'ติดอยู่บนหลังคา • ต้องการยา\nมีเด็กด้วย',
      );
    },
  );

  testWidgets(
    'SOS presets are selectable without keyboard and edit keeps details without duplicates',
    (tester) async {
      String? saved;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () async {
                  saved = await showDialog<String>(
                    context: context,
                    builder: (_) => const SosMessageDialog(
                      initialMessage: 'ติดอยู่บนหลังคา • ต้องการยา\nมีเด็กด้วย',
                      editing: true,
                    ),
                  );
                },
                child: const Text('edit'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('edit'));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<FilterChip>(
              find.widgetWithText(FilterChip, 'ติดอยู่บนหลังคา'),
            )
            .selected,
        isTrue,
      );
      await tester.tap(find.widgetWithText(FilterChip, 'มีผู้ป่วยหนัก'));
      await tester.tap(find.widgetWithText(FilterChip, 'ต้องการยา'));
      await tester.tap(find.widgetWithText(FilledButton, 'บันทึก'));
      await tester.pumpAndSettle();
      expect(saved, 'ติดอยู่บนหลังคา • มีผู้ป่วยหนัก\nมีเด็กด้วย');
    },
  );

  testWidgets(
    'blank SOS still allows a general emergency request and cancel does not submit',
    (tester) async {
      String? result;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () async {
                  result = await showDialog<String>(
                    context: context,
                    builder: (_) => const SosMessageDialog(),
                  );
                },
                child: const Text('new'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('new'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('ยกเลิก'));
      await tester.pumpAndSettle();
      expect(result, isNull);
      await tester.tap(find.text('new'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'เปิด SOS'));
      await tester.pumpAndSettle();
      expect(result, 'ต้องการความช่วยเหลือฉุกเฉิน');
    },
  );

  testWidgets(
    'quick choice on SOS page persists and publishes offline with no GPS fix',
    (tester) async {
      late LocalDatabase local;
      late NearbyMeshService mesh;
      await tester.runAsync(() async {
        local = LocalDatabase.withDatabase(
          await newDatabaseFactoryMemory().openDatabase('quick-sos'),
        );
        mesh = NearbyMeshService.withDatabase(
          local,
          sendBytes: (_, _) async {},
        );
        await mesh.initializeForUser(guest);
        mesh.running = true;
      });
      final repo = SosRepository(local: local);
      await tester.pumpWidget(
        MaterialApp(
          home: SosScreen(
            me: guest,
            repository: repo,
            meshService: mesh,
            locationService: _NoGps(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.widgetWithText(FilterChip, 'ขาดน้ำมาก'));
      await tester.tap(find.widgetWithText(FilterChip, 'ขาดน้ำมาก'));
      await tester.ensureVisible(
        find.widgetWithText(FilterChip, 'มีผู้ป่วยหนัก'),
      );
      await tester.tap(find.widgetWithText(FilterChip, 'มีผู้ป่วยหนัก'));
      await tester.ensureVisible(find.text('เปิด SOS · ขอความช่วยเหลือ'));
      await tester.tap(find.text('เปิด SOS · ขอความช่วยเหลือ'));
      await tester.pumpAndSettle();
      await tester.runAsync(() async {
        await tester.tap(find.widgetWithText(FilledButton, 'เปิด SOS'));
      });
      await tester.pumpAndSettle();
      for (var i = 0; i < 30 && mesh.mySos == null; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)),
        );
        await tester.pump(const Duration(milliseconds: 20));
      }
      await tester.runAsync(() async {
        final record = await repo.latestActive(guest.id);
        expect(record!.message, 'ขาดน้ำมาก • มีผู้ป่วยหนัก');
        expect(record.latitude, isNull);
        expect(record.syncState, 'pending');
        expect(mesh.mySos?['text'], 'ขาดน้ำมาก • มีผู้ป่วยหนัก');
      });
      await tester.pumpWidget(const SizedBox());
      await tester.runAsync(() async {
        mesh.dispose();
        await (await local.database).close();
      });
    },
  );

  testWidgets(
    'legacy rescue title resolves to member and rescue badge does not change transport label',
    (tester) async {
      late LocalDatabase local;
      late NearbyMeshService mesh;
      await tester.runAsync(() async {
        local = LocalDatabase.withDatabase(
          await newDatabaseFactoryMemory().openDatabase('role-title'),
        );
        mesh = NearbyMeshService.withDatabase(
          local,
          sendBytes: (_, _) async {},
        );
        await mesh.initializeForUser(guest);
        mesh.connected.add('link');
        mesh.identities['link'] = NearbyPeer(
          endpoint: 'link',
          deviceId: 'member',
          name: 'Nearby Member',
          verifiedRole: 'rescuer',
          attestedUntil: DateTime.now().add(const Duration(hours: 1)),
        );
      });
      expect(
        mesh.chatPeerName('missing', fallback: 'แชทกับหน่วยกู้ภัย'),
        'บุคคลใกล้เคียง',
      );
      await tester.pumpWidget(
        MaterialApp(
          home: NearbyConversationScreen(
            me: guest,
            peerId: 'member',
            name: 'แชทกับหน่วยกู้ภัย',
            service: mesh,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Nearby Member'), findsOneWidget);
      expect(find.text('ออฟไลน์'), findsOneWidget);
      expect(find.text('แชทกับหน่วยกู้ภัย'), findsNothing);
      mesh.inbox.insert(
        0,
        MeshMessage({
          'kind': 'rescue',
          'origin': 'member',
          'data': {'active': true, 'revision': 1},
        }),
      );
      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(
        MaterialApp(
          home: NearbyConversationScreen(
            me: guest,
            peerId: 'member',
            name: 'Nearby Member',
            service: mesh,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byTooltip('หน่วยกู้ภัยกำลังปฏิบัติหน้าที่'), findsOneWidget);
      expect(find.text('ออฟไลน์'), findsOneWidget);
      mesh.inbox.insert(
        0,
        MeshMessage({
          'kind': 'rescue',
          'origin': 'member',
          'data': {'active': false, 'revision': 2},
        }),
      );
      expect(mesh.isPeerRescueActive('member'), isFalse);
      mesh.connected.clear();
      expect(mesh.isPeerRescueActive('member'), isFalse);
      await tester.pumpWidget(const SizedBox());
      await tester.runAsync(() async {
        mesh.dispose();
        await (await local.database).close();
      });
    },
  );

  testWidgets(
    'SOS picker scrolls on small display with large text and permits submit',
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
            ).copyWith(textScaler: const TextScaler.linear(1.8)),
            child: child!,
          ),
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => showDialog<String>(
                  context: context,
                  builder: (_) => const SosMessageDialog(),
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(
        find.widgetWithText(FilterChip, 'มีผู้ป่วยหนัก'),
      );
      await tester.tap(find.widgetWithText(FilterChip, 'มีผู้ป่วยหนัก'));
      expect(find.widgetWithText(FilledButton, 'เปิด SOS'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
