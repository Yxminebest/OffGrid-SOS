import 'dart:async';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:offgrid_sos/app/theme.dart';
import 'package:offgrid_sos/widgets/nearby_people_panel.dart';
import 'package:sembast/sembast_memory.dart';
import 'package:offgrid_sos/data/local/local_database.dart';
import 'package:offgrid_sos/data/repositories/sos_repository.dart';
import 'package:offgrid_sos/models/user.dart';
import 'package:offgrid_sos/services/location_service.dart';
import 'package:offgrid_sos/services/nearby_mesh_service.dart';
import 'package:offgrid_sos/services/sos_location_tracker.dart';

const me = AppUser(
  id: 'emergency-test',
  firstName: 'A',
  lastName: '',
  isMember: false,
);

class ImmediateGps extends LocationService {
  final fixes = StreamController<SavedLocation>.broadcast();
  @override
  Stream<SavedLocation> emergencyLocations() => fixes.stream;
}

class AutoMesh extends NearbyMeshService {
  AutoMesh(super.local)
    : super.withDatabase(
        disconnect: (_) async {},
        sendBytes: (String _, Uint8List bytes) async {},
      );
  final attempts = <String>[];
  @override
  Future<void> connect(String endpoint, {bool force = false}) async {
    attempts.add(endpoint);
  }
}

SavedLocation fix(double accuracy, {bool cached = false}) => SavedLocation(
  latitude: 14.1,
  longitude: 100.6,
  recordedAt: DateTime.now(),
  accuracyMeters: accuracy,
  isLastKnown: cached,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'first coarse fix is published promptly and a better fix replaces it',
    () async {
      final db = await newDatabaseFactoryMemory().openDatabase('fast-location');
      final local = LocalDatabase.withDatabase(db);
      final mesh = AutoMesh(local);
      await mesh.initializeForUser(me);
      final repo = SosRepository(local: local);
      final record = await repo.create(user: me, message: 'SOS');
      final gps = ImmediateGps();
      final tracker = SosLocationTracker(gps, repo, mesh)..start(record);
      gps.fixes.add(fix(48));
      await Future<void>.delayed(const Duration(milliseconds: 60));
      expect((await repo.findById(record.id))!.accuracy, 48);
      expect(mesh.mySos?['lat'], 14.1);
      gps.fixes.add(fix(6));
      gps.fixes.add(fix(80));
      await Future<void>.delayed(const Duration(milliseconds: 60));
      expect((await repo.findById(record.id))!.accuracy, 6);
      await repo.stop(record);
      gps.fixes.add(fix(3));
      await Future<void>.delayed(const Duration(milliseconds: 60));
      final stopped = (await repo.findById(record.id))!;
      expect(stopped.isActive, isFalse);
      expect(stopped.accuracy, 6);
      tracker.cancel();
      await gps.fixes.close();
      mesh.dispose();
      await db.close();
    },
  );

  test(
    'cached pin is labelled and never replaces an existing live pin',
    () async {
      final db = await newDatabaseFactoryMemory().openDatabase(
        'cache-location',
      );
      final repo = SosRepository(local: LocalDatabase.withDatabase(db));
      final record = await repo.create(user: me, message: 'SOS');
      expect(await repo.updateLocation(record, fix(20, cached: true)), isNull);
      final cache = await repo.updateLocation(
        record,
        fix(20, cached: true),
        allowLastKnown: true,
      );
      expect(cache!.isLastKnownLocation, isTrue);
      final live = await repo.updateLocation(record, fix(8));
      expect(live!.isLastKnownLocation, isFalse);
      expect(
        await repo.updateLocation(
          record,
          fix(2, cached: true),
          allowLastKnown: true,
        ),
        isNull,
      );
      await db.close();
    },
  );

  test(
    'discovered phones connect automatically without a tap; duplicate discoveries are throttled',
    () async {
      final db = await newDatabaseFactoryMemory().openDatabase(
        'auto-discovery',
      );
      final mesh = AutoMesh(LocalDatabase.withDatabase(db));
      await mesh.initializeForUser(me);
      mesh.running = true;
      mesh.discovered('phone-b', 'OG9:N:Neighbour');
      mesh.discovered('phone-b', 'OG9:N:Neighbour');
      expect(mesh.peers['phone-b'], 'Neighbour');
      await Future<void>.delayed(const Duration(milliseconds: 1300));
      expect(mesh.attempts, ['phone-b']);
      mesh.discovered('phone-b', 'OG9:N:Neighbour');
      await Future<void>.delayed(const Duration(milliseconds: 1300));
      expect(mesh.attempts, ['phone-b']);
      mesh.dispose();
      await db.close();
    },
  );

  test(
    'radio stopped during discovery cancels the delayed automatic request',
    () async {
      final db = await newDatabaseFactoryMemory().openDatabase('auto-cancel');
      final mesh = AutoMesh(LocalDatabase.withDatabase(db));
      await mesh.initializeForUser(me);
      mesh.running = true;
      mesh.discovered('phone-c', 'OG9:N:Neighbour');
      mesh.running = false;
      await Future<void>.delayed(const Duration(milliseconds: 1300));
      expect(mesh.attempts, isEmpty);
      mesh.dispose();
      await db.close();
    },
  );
  test(
    'a still-discovered phone remains reconnectable after its link drops',
    () async {
      final db = await newDatabaseFactoryMemory().openDatabase(
        'sleep-reconnect',
      );
      final mesh = AutoMesh(LocalDatabase.withDatabase(db));
      await mesh.initializeForUser(me);
      mesh.discovered('phone-b', 'OG9:N:B');
      mesh.connected.add('phone-b');
      mesh.running = true;
      await mesh.handleEnvelope('phone-b', {
        'v': 1,
        'id': 'sleep-drop',
        'kind': 'goodbye',
        'origin': 'b-device',
        'ttl': 1,
        'data': <String, dynamic>{},
      });
      expect(mesh.connected, isEmpty);
      expect(mesh.peers['phone-b'], 'B');
      await mesh.resumeConnections(me);
      await Future<void>.delayed(const Duration(milliseconds: 1300));
      expect(mesh.attempts, ['phone-b']);
      mesh.running = false;
      mesh.dispose();
      await db.close();
    },
  );

  testWidgets(
    'live list shows discovered people immediately and blue only for verified active rescue',
    (tester) async {
      final db = await newDatabaseFactoryMemory().openDatabase('people-ui');
      final mesh = AutoMesh(LocalDatabase.withDatabase(db));
      await tester.runAsync(() => mesh.initializeForUser(me));
      mesh.discovered('neighbour', 'OG9:N:Neighbour');
      mesh.discovered('rescue', 'OG9:R:Rescue');
      await tester.pumpWidget(
        MaterialApp(
          theme: buildTheme(brightness: Brightness.light),
          home: Scaffold(
            body: NearbyPeoplePanel(me: me, mesh: mesh),
          ),
        ),
      );
      expect(find.text('Neighbour'), findsOneWidget);
      expect(find.text('Rescue'), findsOneWidget);
      expect(find.text('กำลังเชื่อมต่ออัตโนมัติ…'), findsNWidgets(2));
      expect(find.text('หน่วยกู้ภัย · พร้อมสนทนา'), findsNothing);
      mesh.connected.add('rescue');
      mesh.identities['rescue'] = NearbyPeer(
        endpoint: 'rescue',
        deviceId: 'rescue-device',
        name: 'Rescue',
        verifiedRole: 'rescuer',
        attestedUntil: DateTime.now().add(const Duration(hours: 1)),
      );
      mesh.inbox.add(
        MeshMessage({
          'kind': 'rescue',
          'origin': 'rescue-device',
          'data': {'active': true},
        }),
      );
      mesh.discovered('rescue', 'OG9:R:Rescue');
      await tester.pump();
      expect(find.text('หน่วยกู้ภัย · พร้อมสนทนา'), findsOneWidget);
      expect(
        tester
            .widgetList<Card>(find.byType(Card))
            .any((card) => card.color == const Color(0xFF1859A9)),
        isTrue,
      );
      mesh.inbox.clear();
      mesh.discovered('rescue', 'OG9:N:Rescue');
      await tester.pump();
      expect(find.text('หน่วยกู้ภัย · พร้อมสนทนา'), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      mesh.dispose();
      await db.close();
    },
  );
}
