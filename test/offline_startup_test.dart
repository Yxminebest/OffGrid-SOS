import 'dart:async';
import 'package:flutter/services.dart';
import 'package:offgrid_sos/services/bluetooth_link.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sembast/sembast_memory.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:offgrid_sos/data/local/local_database.dart';
import 'package:offgrid_sos/models/user.dart';
import 'package:offgrid_sos/services/auth_service.dart';
import 'package:offgrid_sos/services/nearby_mesh_service.dart';

const userA = AppUser(
  id: 'offline-a',
  firstName: 'A',
  lastName: 'Local',
  isMember: true,
);
const userB = AppUser(
  id: 'offline-b',
  firstName: 'B',
  lastName: 'Local',
  isMember: false,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));

  test(
    'cached member opens without initializing a cloud SDK or accessing a network',
    () async {
      FlutterSecureStorage.setMockInitialValues({
        'isMember': '1',
        'supabaseUserId': 'offline-a',
        'firstName': 'A',
        'lastName': 'Local',
        'email': 'a@example.com',
        'role': 'rescuer',
      });
      final restored = await AuthService.restoreIdentity();
      expect(restored!.id, 'offline-a');
      expect(restored.isVerifiedRescuer, isTrue);
    },
  );

  test('retired guest cache cannot restore an app session', () async {
    FlutterSecureStorage.setMockInitialValues({
      'isMember': '0',
      'deviceId': 'old-device',
      'firstName': 'Old',
      'lastName': 'Visitor',
    });
    expect(await AuthService.restoreLocalIdentity(), isNull);
  });

  test(
    'removed identity marker prevents old cached fields from logging in again',
    () async {
      FlutterSecureStorage.setMockInitialValues({
        'supabaseUserId': 'old-member',
        'firstName': 'Old',
        'lastName': 'User',
        'email': 'old@example.com',
        'role': 'rescuer',
      });
      expect(await AuthService.restoreLocalIdentity(), isNull);
    },
  );

  test(
    'incomplete cached identity does not create an unusable member',
    () async {
      FlutterSecureStorage.setMockInitialValues({
        'isMember': '1',
        'role': 'rescuer',
      });
      expect(await AuthService.restoreIdentity(), isNull);
    },
  );

  test(
    'radio preference survives process/session initialization and manual stop is respected',
    () async {
      final db = await newDatabaseFactoryMemory().openDatabase(
        'radio-preferences',
      );
      final local = LocalDatabase.withDatabase(db);
      await local.metaStore.record('nearby_radio:${userA.id}').put(db, {
        'owner_id': userA.id,
        'mode': 'bluetooth',
      });
      await local.metaStore.record('nearby_radio:${userB.id}').put(db, {
        'owner_id': userB.id,
        'mode': 'nearby',
      });
      final mesh = NearbyMeshService.withDatabase(local);
      await mesh.initializeForUser(userA);
      expect(await mesh.preferredTransport(userA.id), 'bluetooth');
      await mesh.initializeForUser(userB);
      expect(await mesh.preferredTransport(userB.id), 'nearby');
      await mesh.stop();
      expect(await mesh.preferredTransport(userB.id), isNull);
      expect(await mesh.preferredTransport(userA.id), 'bluetooth');
      mesh.dispose();
      final reopened = NearbyMeshService.withDatabase(local);
      await reopened.initializeForUser(userA);
      expect(await reopened.preferredTransport(userA.id), 'bluetooth');
      reopened.dispose();
      await db.close();
    },
  );

  test('automatic startup preserves the saved Bluetooth transport', () async {
    SharedPreferences.setMockInitialValues({'background_messaging': false});
    final db = await newDatabaseFactoryMemory().openDatabase('resume-bt');
    final local = LocalDatabase.withDatabase(db);
    await local.metaStore.record('nearby_radio:${userA.id}').put(db, {
      'owner_id': userA.id,
      'mode': 'bluetooth',
    });
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    final calls = <String>[];
    messenger.setMockMethodCallHandler(
      const MethodChannel('com.offgridsos/platform'),
      (_) async => 30,
    );
    messenger.setMockMethodCallHandler(
      const MethodChannel('com.offgridsos/bluetooth'),
      (call) async {
        calls.add(call.method);
        if (call.method == 'start') return true;
        if (call.method == 'paired') return <dynamic>[];
        return null;
      },
    );
    final mesh = NearbyMeshService.withDatabase(local);
    try {
      await mesh.resumePreferred(userA, startIfUnset: true);
      expect(mesh.running, isTrue);
      expect(calls, contains('start'));
      expect(await mesh.preferredTransport(userA.id), 'bluetooth');
      calls.clear();
      // Even without a bonded peer, the listener must be recovered on resume.
      await mesh.resumeConnections(userA);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(calls, contains('start'));
    } finally {
      mesh.dispose();
      await BluetoothLink.instance.stop();
      messenger.setMockMethodCallHandler(
        const MethodChannel('com.offgridsos/platform'),
        null,
      );
      messenger.setMockMethodCallHandler(
        const MethodChannel('com.offgridsos/bluetooth'),
        null,
      );
      await db.close();
    }
  });

  test(
    'manual stop cancels Bluetooth startup while permission checks are pending',
    () async {
      final db = await newDatabaseFactoryMemory().openDatabase(
        'bluetooth-stop-permission',
      );
      final mesh = NearbyMeshService.withDatabase(
        LocalDatabase.withDatabase(db),
      );
      final requested = Completer<void>();
      final sdk = Completer<int>();
      var nativeStarts = 0;
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(
        const MethodChannel('com.offgridsos/platform'),
        (call) async {
          requested.complete();
          return sdk.future;
        },
      );
      messenger.setMockMethodCallHandler(
        const MethodChannel('com.offgridsos/bluetooth'),
        (call) async {
          if (call.method == 'start') {
            nativeStarts++;
            return true;
          }
          return null;
        },
      );
      final starting = mesh.startBluetooth(userA);
      await requested.future;
      await mesh.stop();
      sdk.complete(30);
      expect(await starting, isFalse);
      expect(mesh.running, isFalse);
      expect(nativeStarts, 0);
      mesh.dispose();
      await db.close();
      messenger.setMockMethodCallHandler(
        const MethodChannel('com.offgridsos/platform'),
        null,
      );
      messenger.setMockMethodCallHandler(
        const MethodChannel('com.offgridsos/bluetooth'),
        null,
      );
    },
  );

  test(
    'late native Bluetooth startup cannot resurrect a stopped transport',
    () async {
      final nativeStarted = Completer<void>();
      final result = Completer<bool>();
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(
        const MethodChannel('com.offgridsos/bluetooth'),
        (call) async {
          if (call.method == 'start') {
            nativeStarted.complete();
            return result.future;
          }
          return null;
        },
      );
      final link = BluetoothLink.instance;
      final starting = link.start();
      await nativeStarted.future;
      await link.stop();
      result.complete(true);
      expect(await starting, isFalse);
      expect(link.running, isFalse);
      messenger.setMockMethodCallHandler(
        const MethodChannel('com.offgridsos/bluetooth'),
        null,
      );
    },
  );

  test(
    'relay phone queues simultaneous pairing confirmations with separate security codes',
    () async {
      final db = await newDatabaseFactoryMemory().openDatabase('pairing-queue');
      final mesh = NearbyMeshService.withDatabase(
        LocalDatabase.withDatabase(db),
      );
      final methods = <MethodCall>[];
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(
        const MethodChannel('nearby_connections/events'),
        (_) async => null,
      );
      messenger.setMockMethodCallHandler(
        const MethodChannel('nearby_connections'),
        (call) async {
          methods.add(call);
          return true;
        },
      );
      await mesh.initializeForUser(userA);
      mesh.requestPairing(id: 'endpoint-b', name: 'Phone B', token: '1234');
      mesh.requestPairing(id: 'endpoint-c', name: 'Phone C', token: '5678');
      mesh.requestPairing(id: 'endpoint-b', name: 'Duplicate', token: '9999');
      expect(mesh.pendingPeer, 'endpoint-b');
      expect(mesh.pendingToken, '1234');
      await mesh.approve(false);
      expect(mesh.pendingPeer, 'endpoint-c');
      expect(mesh.pendingToken, '5678');
      await mesh.approve(false);
      expect(mesh.pendingPeer, isNull);
      expect(
        methods.where((m) => m.method == 'rejectConnection'),
        hasLength(2),
      );
      mesh.dispose();
      await db.close();
      messenger.setMockMethodCallHandler(
        const MethodChannel('nearby_connections'),
        null,
      );
      messenger.setMockMethodCallHandler(
        const MethodChannel('nearby_connections/events'),
        null,
      );
    },
  );
}
