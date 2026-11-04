import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sembast/sembast_memory.dart';
import 'package:offgrid_sos/data/local/local_database.dart';
import 'package:offgrid_sos/data/repositories/sos_repository.dart';
import 'package:offgrid_sos/models/user.dart';
import 'package:offgrid_sos/services/location_service.dart';
import 'package:offgrid_sos/services/nearby_mesh_service.dart';
import 'package:offgrid_sos/widgets/emergency_home_panel.dart';
import 'package:offgrid_sos/data/models/local_sos_record.dart';

class WaitingGps extends LocationService {
  final result = Completer<SavedLocation?>();
  @override
  Future<SavedLocation?> getLatestLocation() => result.future;
  @override
  Stream<SavedLocation> emergencyLocations() async* {
    final fix = await result.future;
    if (fix != null) yield fix;
  }
}

void main() {
  testWidgets(
    'hold SOS requires one second and opens details once after saving, stop survives late GPS',
    (tester) async {
      final db = await newDatabaseFactoryMemory().openDatabase('quick-home');
      final local = LocalDatabase.withDatabase(db);
      final repo = SosRepository(local: local);
      final mesh = NearbyMeshService.withDatabase(local);
      const me = AppUser(
        id: 'home-guest',
        firstName: 'Guest',
        lastName: '',
        isMember: false,
      );
      await tester.runAsync(() => mesh.initializeForUser(me));
      final gps = WaitingGps();
      final stream = repo.watchForUser(me.id);
      var opened = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StreamBuilder<List<LocalSosRecord>>(
              stream: stream,
              builder: (context, snapshot) => EmergencyHomePanel(
                me: me,
                repository: repo,
                mesh: mesh,
                location: gps,
                record: (snapshot.data ?? [])
                    .where((r) => r.isActive)
                    .firstOrNull,
                onDetails: () => opened++,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      // Tap and a short hold must never send an emergency request.
      await tester.tap(find.text('SOS'));
      var press = await tester.startGesture(tester.getCenter(find.text('SOS')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await press.up();
      await tester.pump();
      await tester.runAsync(() async {
        expect(await repo.latestActive(me.id), isNull);
      });
      final ring = tester
          .widgetList<CircularProgressIndicator>(
            find.byType(CircularProgressIndicator),
          )
          .first;
      expect(ring.value, 0);
      press = await tester.startGesture(tester.getCenter(find.text('SOS')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(
        tester
            .widgetList<CircularProgressIndicator>(
              find.byType(CircularProgressIndicator),
            )
            .first
            .value,
        closeTo(.5, .05),
      );
      await tester.runAsync(() async {
        await tester.pump(const Duration(milliseconds: 550));
      });
      await press.up();
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
      await tester.pumpAndSettle();
      expect(opened, 1);
      expect(find.text('กดค้าง 3 วินาทีเพื่อขอความช่วยเหลือ'), findsNothing);
      await tester.runAsync(() async {
        final record = await repo.latestActive(me.id);
        expect(record, isNotNull);
        expect(record!.message, 'ต้องการความช่วยเหลือฉุกเฉิน');
        expect(record.latitude, isNull);
        expect((await repo.watchForUser(me.id).first).length, 1);
      });
      expect(find.byType(TextField), findsNothing);
      expect(find.byType(AlertDialog), findsNothing);
      await tester.tap(find.text('หยุด SOS'));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
      await tester.pumpAndSettle();
      gps.result.complete(
        SavedLocation(
          latitude: 14.04,
          longitude: 100.72,
          accuracyMeters: 5,
          recordedAt: DateTime.now(),
        ),
      );
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pumpAndSettle();
      await tester.runAsync(() async {
        expect(await repo.latestActive(me.id), isNull);
      });
      await tester.pumpWidget(const SizedBox());
      await tester.runAsync(() async {
        mesh.dispose();
        await db.close();
      });
    },
  );
}
