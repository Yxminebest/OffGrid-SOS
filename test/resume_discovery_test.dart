import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sembast/sembast_memory.dart';
import 'package:offgrid_sos/data/local/local_database.dart';
import 'package:offgrid_sos/data/models/local_sos_record.dart';
import 'package:offgrid_sos/data/repositories/sos_repository.dart';
import 'package:offgrid_sos/features/home/home_shell.dart';
import 'package:offgrid_sos/models/user.dart';
import 'package:offgrid_sos/services/location_service.dart';
import 'package:offgrid_sos/services/nearby_mesh_service.dart';

const user = AppUser(
  id: 'resume-guest',
  firstName: 'A',
  lastName: '',
  isMember: false,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('rotated endpoints with one stable hint show one device', () async {
    final db = await newDatabaseFactoryMemory().openDatabase('dedup');
    final mesh = NearbyMeshService.withDatabase(LocalDatabase.withDatabase(db));
    mesh.discovered('old', 'OG10:N:device-b:Same name');
    mesh.discovered('new', 'OG10:S:device-b:Same name');
    expect(mesh.visiblePeers, hasLength(1));
    mesh.discovered('other', 'OG10:N:device-c:Same name');
    expect(mesh.visiblePeers, hasLength(2));
    mesh.connected.addAll(['old', 'new']);
    mesh.identities['old'] = const NearbyPeer(
      endpoint: 'old',
      deviceId: 'device-b',
      name: 'B',
    );
    mesh.identities['new'] = const NearbyPeer(
      endpoint: 'new',
      deviceId: 'device-b',
      name: 'B',
    );
    expect(mesh.connectedDeviceCount, 1);
    expect(mesh.visiblePeers, hasLength(2));
    mesh.dispose();
    await db.close();
  });
  test(
    'discovery hints do not grant a rescuer role and OG9 remains readable',
    () async {
      final db = await newDatabaseFactoryMemory().openDatabase('hint-role');
      final mesh = NearbyMeshService.withDatabase(
        LocalDatabase.withDatabase(db),
      );
      mesh.discovered('fake', 'OG10:R:device-b:Rescue');
      expect(mesh.isPeerRescueActive('device-b'), isFalse);
      expect(
        NearbyMeshService.parseDiscoveryName('OG9:S:Old phone').name,
        'Old phone',
      );
      expect(
        NearbyMeshService.parseDiscoveryName('OG10:S:device-b:New phone').mode,
        'S',
      );
      mesh.dispose();
      await db.close();
    },
  );
  test(
    'wake restores own SOS from local DB before radio/cloud recovery',
    () async {
      final db = await newDatabaseFactoryMemory().openDatabase('resume-sos');
      final local = LocalDatabase.withDatabase(db);
      final mesh = NearbyMeshService.withDatabase(
        local,
        sendBytes: (String _, Uint8List _) async {},
      );
      final repo = SosRepository(local: local);
      final active = await repo.create(user: user, message: 'Help');
      await mesh.initializeForUser(user);
      expect(mesh.ownSosRecord?.id, active.id);
      mesh.ownSosRecord = null;
      mesh.mySos = null;
      mesh.activeSosId = null;
      mesh.running = true;
      await mesh.resumeConnections(user);
      expect(mesh.ownSosRecord?.id, active.id);
      expect(mesh.mySos?['active'], isTrue);
      await repo.stop(active);
      await mesh.resumeConnections(user);
      expect(mesh.ownSosRecord, isNull);
      expect(mesh.mySos, isNull);
      mesh.dispose();
      await db.close();
    },
  );
  testWidgets(
    'own SOS remains active while its resumed DB snapshot is waiting',
    (tester) async {
      final fixture = await tester.runAsync(() async {
        final db = await newDatabaseFactoryMemory().openDatabase('home-resume');
        final local = LocalDatabase.withDatabase(db);
        final active = await SosRepository(
          local: local,
        ).create(user: user, message: 'Help');
        final mesh = NearbyMeshService.withDatabase(local);
        await mesh.initializeForUser(user);
        return (db, active, mesh);
      });
      final (db, active, mesh) = fixture!;
      final records = StreamController<List<LocalSosRecord>>.broadcast();
      Widget home() => MaterialApp(
        home: Scaffold(
          body: HomeDashboard(
            me: user,
            unreadCount: 0,
            service: mesh,
            sosRecords: records.stream,
            onSos: () {},
            onRescue: () {},
            onNearby: () {},
            onChat: () {},
          ),
        ),
      );
      await tester.pumpWidget(home());
      await tester.pump();
      expect(find.text('คุณกำลังขอความช่วยเหลือ'), findsOneWidget);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpWidget(home());
      await tester.pump();
      expect(find.text('คุณกำลังขอความช่วยเหลือ'), findsOneWidget);
      records.add([active.copyWith(isActive: false)]);
      await tester.pumpAndSettle();
      expect(find.text('ต้องการความช่วยเหลือฉุกเฉิน?'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      await records.close();
      mesh.dispose();
      await db.close();
    },
  );
  test(
    'quick location returns first real fix and cancels GPS listener',
    () async {
      var cancelled = false;
      final source = StreamController<SavedLocation>(
        onCancel: () {
          cancelled = true;
        },
      );
      final result = const LocationService().firstFix(source.stream);
      final point = SavedLocation(
        latitude: 14.1,
        longitude: 100.6,
        recordedAt: DateTime.now(),
        accuracyMeters: 48,
      );
      source.add(point);
      expect(await result, same(point));
      expect(cancelled, isTrue);
      await source.close();
    },
  );
  test(
    'quick location timeout cancels a silent GPS without inventing a pin',
    () async {
      var cancelled = false;
      final source = StreamController<SavedLocation>(
        onCancel: () {
          cancelled = true;
        },
      );
      expect(
        await const LocationService().firstFix(
          source.stream,
          timeout: const Duration(milliseconds: 20),
        ),
        isNull,
      );
      expect(cancelled, isTrue);
      await source.close();
    },
  );
}
