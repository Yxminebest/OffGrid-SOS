import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:offgrid_sos/features/rescue/rescue_verification_history_screen.dart';
import 'package:sembast/sembast_memory.dart';
import 'package:offgrid_sos/data/local/local_database.dart';
import 'package:offgrid_sos/models/user.dart';
import 'package:offgrid_sos/services/rescue_status_service.dart';

const member = AppUser(
  id: 'member-a',
  firstName: 'Test',
  lastName: 'Member',
  isMember: true,
);
Map<String, dynamic> request(String status) => {
  'id': 'request-1',
  'organization_name': 'Test rescue',
  'status': status,
  'submitted_at': '2026-10-18T08:00:00Z',
  if (status != 'pending') 'reviewed_at': '2026-10-19T08:00:00Z',
  if (status == 'rejected') 'rejection_reason': 'เอกสารไม่ครบ',
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'approval refreshes role, alerts once, and keeps history offline after restart',
    () async {
      final db = await newDatabaseFactoryMemory().openDatabase('approval');
      final local = LocalDatabase.withDatabase(db);
      var status = 'pending';
      var online = true;
      final alerts = <String>[];
      RescueStatusService makeService() => RescueStatusService(
        local: local,
        fetchRequests: () async {
          if (!online) throw StateError('offline');
          return [request(status)];
        },
        fetchMember: () async => member.copyWith(
          role: status == 'approved' ? AppRole.rescuer : AppRole.user,
        ),
        notify: (id, title, text) async => alerts.add(title),
      );
      var service = makeService();
      await service.start(member, monitor: false);
      expect(alerts, isEmpty);
      status = 'approved';
      await service.refresh();
      expect(service.member!.isVerifiedRescuer, isTrue);
      expect(alerts, ['อนุมัติสิทธิ์หน่วยกู้ภัยแล้ว']);
      await service.refresh();
      expect(alerts, hasLength(1));
      service.dispose();
      service = makeService();
      online = false;
      await service.start(member, monitor: false);
      expect(service.requests.single['status'], 'approved');
      expect(service.error, isNotNull);
      online = true;
      await service.refresh();
      expect(alerts, hasLength(1));
      service.dispose();
      await db.close();
    },
  );

  test(
    'existing approval gets one notice and another account cannot see its cache',
    () async {
      final db = await newDatabaseFactoryMemory().openDatabase(
        'approval-isolation',
      );
      var online = true;
      final alerts = <String>[];
      final service = RescueStatusService(
        local: LocalDatabase.withDatabase(db),
        fetchRequests: () async {
          if (!online) throw StateError('offline');
          return [request('approved')];
        },
        fetchMember: () async => member.copyWith(role: AppRole.rescuer),
        notify: (id, title, text) async => alerts.add(title),
      );
      await service.start(member, monitor: false);
      expect(alerts, hasLength(1));
      online = false;
      await service.start(
        const AppUser(
          id: 'member-b',
          firstName: 'B',
          lastName: 'Test',
          isMember: true,
        ),
        monitor: false,
      );
      expect(service.requests, isEmpty);
      expect(service.notice, isNull);
      service.dispose();
      await db.close();
    },
  );

  test(
    'rejection reason remains available when notification delivery fails',
    () async {
      final db = await newDatabaseFactoryMemory().openDatabase('rejection');
      final service = RescueStatusService(
        local: LocalDatabase.withDatabase(db),
        fetchRequests: () async => [request('rejected')],
        fetchMember: () async => member,
        notify: (_, _, _) async => throw StateError('permission denied'),
      );
      await service.start(member, monitor: false);
      expect(service.requests.single['rejection_reason'], 'เอกสารไม่ครบ');
      expect(service.member!.isVerifiedRescuer, isFalse);
      expect(service.error, isNull);
      service.dispose();
      await db.close();
    },
  );

  test(
    'old approval cannot grant a role or announce a revoked rescue permission',
    () async {
      final db = await newDatabaseFactoryMemory().openDatabase('revoked');
      var alerts = 0;
      final service = RescueStatusService(
        local: LocalDatabase.withDatabase(db),
        fetchRequests: () async => [request('approved')],
        fetchMember: () async => member,
        notify: (_, _, _) async {
          alerts++;
        },
      );
      await service.start(member, monitor: false);
      expect(service.member!.isVerifiedRescuer, isFalse);
      expect(service.requests.single['status'], 'approved');
      expect(alerts, 0);
      service.dispose();
      await db.close();
    },
  );

  testWidgets(
    'verification history displays approval, organization and local dates',
    (tester) async {
      final db = await newDatabaseFactoryMemory().openDatabase('history-ui');
      final service = RescueStatusService(
        local: LocalDatabase.withDatabase(db),
        fetchRequests: () async => [request('approved')],
        fetchMember: () async => member.copyWith(role: AppRole.rescuer),
        notify: (_, _, _) async {},
      );
      await tester.runAsync(() => service.start(member, monitor: false));
      await tester.pumpWidget(
        MaterialApp(
          home: RescueVerificationHistoryScreen(me: member, service: service),
        ),
      );
      await tester.pumpAndSettle();
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pumpAndSettle();
      expect(find.text('อนุมัติสิทธิ์หน่วยกู้ภัยแล้ว'), findsOneWidget);
      expect(find.text('Test rescue'), findsOneWidget);
      expect(find.textContaining('ตรวจสอบ: 19/10/2026'), findsOneWidget);
      expect(
        find.text('สิทธิ์ปัจจุบัน: หน่วยกู้ภัยที่ยืนยันแล้ว'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      service.dispose();
      await db.close();
    },
  );

  test('a result that arrives after account change is discarded', () async {
    final db = await newDatabaseFactoryMemory().openDatabase('approval-race');
    final fetch = Completer<List<Map<String, dynamic>>>();
    var reads = 0;
    var alerts = 0;
    final service = RescueStatusService(
      local: LocalDatabase.withDatabase(db),
      fetchRequests: () {
        reads++;
        return fetch.future;
      },
      fetchMember: () async => member.copyWith(role: AppRole.rescuer),
      notify: (_, _, _) async {
        alerts++;
      },
    );
    final starting = service.start(member, monitor: false);
    while (reads == 0) {
      await Future<void>.delayed(Duration.zero);
    }
    service.stop();
    fetch.complete([request('approved')]);
    await starting;
    expect(service.requests, isEmpty);
    expect(service.member, isNull);
    expect(alerts, 0);
    service.dispose();
    await db.close();
  });
}
