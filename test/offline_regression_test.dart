import 'package:flutter_test/flutter_test.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:sembast/sembast_memory.dart';

import 'package:offgrid_sos/data/local/local_database.dart';
import 'package:offgrid_sos/data/models/local_sos_record.dart';
import 'package:offgrid_sos/data/repositories/message_repository.dart';
import 'package:offgrid_sos/data/repositories/sos_repository.dart';
import 'package:offgrid_sos/data/repositories/sync_queue_repository.dart';
import 'package:offgrid_sos/models/user.dart';
import 'package:offgrid_sos/services/android_permissions.dart';
import 'package:offgrid_sos/services/location_service.dart';
import 'package:offgrid_sos/services/nearby_mesh_service.dart';

const member = AppUser(
  id: 'member-a',
  firstName: 'A',
  lastName: 'User',
  isMember: true,
);
const other = AppUser(
  id: 'member-b',
  firstName: 'B',
  lastName: 'User',
  isMember: true,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Database db;
  late LocalDatabase local;
  late SosRepository sos;
  late MessageRepository messages;
  late SyncQueueRepository queue;

  setUp(() async {
    db = await newDatabaseFactoryMemory().openDatabase('regression');
    local = LocalDatabase.withDatabase(db);
    sos = SosRepository(local: local);
    messages = MessageRepository(local: local);
    queue = SyncQueueRepository(local: local);
  });
  tearDown(() => db.close());

  test(
    'stable cloud camera ID makes retry atomic and destination-bound',
    () async {
      final first = await messages.create(
        user: member,
        conversationId: 'room',
        messageId: 'capture-id',
        type: 'image',
        mediaBytes: [1, 2, 3],
      );
      final again = await messages.create(
        user: member,
        conversationId: 'room',
        messageId: 'capture-id',
        type: 'image',
        mediaBytes: [1, 2, 3],
      );
      expect(again.id, first.id);
      expect(await queue.countFor(member.id), 1);
      await expectLater(
        messages.create(
          user: other,
          conversationId: 'room',
          messageId: 'capture-id',
        ),
        throwsStateError,
      );
    },
  );

  test(
    'old SOS upload cannot acknowledge an edit made while uploading',
    () async {
      final record = await sos.create(user: member, message: 'old');
      final uploading = (await queue.readyJobs(member.id)).single;
      await sos.updateMessage(record, 'new');
      expect(await queue.complete(uploading), isFalse);
      expect((await sos.findById(record.id))!.message, 'new');
      expect((await sos.findById(record.id))!.syncState, 'pending');
      final latest = (await queue.readyJobs(member.id)).single;
      expect(await queue.complete(latest), isTrue);
      expect(await queue.countFor(member.id), 0);
      expect((await sos.findById(record.id))!.syncState, 'synced');
    },
  );

  test('stopping SOS during an upload retains the cancellation job', () async {
    final record = await sos.create(user: member, message: 'help');
    final uploading = (await queue.readyJobs(member.id)).single;
    await sos.stop(record);
    expect(await queue.complete(uploading), isFalse);
    expect((await sos.findById(record.id))!.isActive, isFalse);
    expect(await queue.countFor(member.id), 1);
  });

  test('old failed upload does not delay a newer local edit', () async {
    final record = await sos.create(user: member, message: 'old');
    final uploading = (await queue.readyJobs(member.id)).single;
    await sos.updateMessage(record, 'new');
    await queue.fail(uploading, StateError('old network failure'));
    final latest = (await queue.readyJobs(member.id)).single;
    expect(latest.retryCount, 0);
    expect(latest.nextRetryAt, isNull);
    expect((await sos.findById(record.id))!.syncState, 'pending');
  });

  test(
    'concurrent edits and stop preserve both changes in one queue job',
    () async {
      final record = await sos.create(user: member, message: 'old');
      await Future.wait([sos.updateMessage(record, 'new'), sos.stop(record)]);
      final latest = (await sos.findById(record.id))!;
      expect(latest.message, 'new');
      expect(latest.isActive, isFalse);
      expect((await queue.readyJobs(member.id)).single.revision, 3);
    },
  );

  test('old message upload cannot delete a pending deletion locally', () async {
    final record = await messages.create(
      user: member,
      conversationId: 'room',
      content: 'hello',
    );
    final uploading = (await queue.readyJobs(member.id)).single;
    await messages.delete(record);
    expect(await queue.complete(uploading), isFalse);
    expect((await messages.findById(record.id))!.isDeleted, isTrue);
    final deleting = (await queue.readyJobs(member.id)).single;
    expect(deleting.operation, 'delete');
    expect(await queue.complete(deleting), isTrue);
    expect(await messages.findById(record.id), isNull);
  });

  test(
    'finishing media upload preserves newer edits and pending deletion',
    () async {
      final record = await messages.create(
        user: member,
        conversationId: 'room',
        content: 'old',
        mediaBytes: [1, 2, 3],
      );
      await messages.updateText(record, 'new');
      await messages.delete(record);
      await messages.attachUploadedMedia(
        id: record.id,
        mediaPath: 'uploaded/file',
      );
      final latest = (await messages.findById(record.id))!;
      expect(latest.content, 'new');
      expect(latest.isDeleted, isTrue);
      expect(latest.mediaPath, 'uploaded/file');
      expect(latest.mediaBytes, isNull);
      expect(latest.syncState, 'pending');
    },
  );

  test(
    'retry backoff blocks jobs until due and manual retry is owner scoped',
    () async {
      await sos.create(user: member, message: 'A');
      await sos.create(user: other, message: 'B');
      await queue.fail(
        (await queue.readyJobs(member.id)).single,
        StateError('offline'),
      );
      await queue.fail(
        (await queue.readyJobs(other.id)).single,
        StateError('offline'),
      );
      expect(await queue.readyJobs(member.id), isEmpty);
      await queue.retryEverythingNow(member.id);
      expect(await queue.readyJobs(member.id), hasLength(1));
      expect(await queue.readyJobs(other.id), isEmpty);
    },
  );

  test(
    'Guest SOS stays local and preserves the age of a cached location',
    () async {
      const guest = AppUser(
        id: 'guest',
        firstName: 'G',
        lastName: 'User',
        isMember: false,
      );
      final at = DateTime.now().subtract(const Duration(hours: 3));
      final record = await sos.create(
        user: guest,
        message: 'help',
        location: SavedLocation(
          latitude: 13.7,
          longitude: 100.5,
          recordedAt: at,
          accuracyMeters: 20,
          isLastKnown: true,
        ),
      );
      final restored = (await sos.findById(record.id))!;
      expect(restored.locationRecordedAt, at);
      expect(restored.isLastKnownLocation, isTrue);
      expect(await queue.countFor(guest.id), 0);
      expect(restored.copyWith(message: 'edited').locationRecordedAt, at);
    },
  );

  test('legacy SOS rows do not claim their location is current', () {
    final now = DateTime.now();
    final map = LocalSosRecord(
      id: 'old',
      ownerLocalId: member.id,
      message: 'help',
      latitude: 13.7,
      longitude: 100.5,
      createdAt: now,
      updatedAt: now,
    ).toLocalMap();
    map.remove('location_recorded_at');
    map.remove('is_last_known_location');
    final restored = LocalSosRecord.fromLocalMap(map);
    expect(restored.locationRecordedAt, isNull);
    expect(restored.isLastKnownLocation, isTrue);
  });

  test(
    'new Nearby service restores the same identity and active case',
    () async {
      final record = await sos.create(
        user: member,
        message: 'help',
        location: SavedLocation(
          latitude: 13.7,
          longitude: 100.5,
          recordedAt: DateTime.now().subtract(const Duration(hours: 3)),
          isLastKnown: true,
        ),
      );
      final first = NearbyMeshService.withDatabase(local);
      await first.initializeForUser(member);
      final identity = first.deviceId;
      final restarted = NearbyMeshService.withDatabase(local);
      await restarted.initializeForUser(member);
      expect(restarted.deviceId, identity);
      expect(restarted.activeSosId, record.id);
      expect(restarted.mySos!['text'], 'help');
      expect(restarted.mySos!['lastKnown'], isTrue);
      await restarted.stopSos();
      expect((restarted.inbox.first.data['data'] as Map)['caseId'], record.id);
      first.dispose();
      restarted.dispose();
    },
  );

  test(
    'cancellation retains the persisted case ID even without a restored active SOS',
    () async {
      final record = await sos.create(user: member, message: 'help');
      await sos.stop(record);
      final mesh = NearbyMeshService.withDatabase(local);
      await mesh.initializeForUser(member);
      expect(mesh.activeSosId, isNull);
      await mesh.stopSos(caseId: record.id);
      expect((mesh.inbox.first.data['data'] as Map)['caseId'], record.id);
      expect((mesh.inbox.first.data['data'] as Map)['active'], isFalse);
      mesh.dispose();
    },
  );

  test(
    'publishing an old SOS snapshot cannot reactivate a cancelled case',
    () async {
      final record = await sos.create(user: member, message: 'help');
      final mesh = NearbyMeshService.withDatabase(local);
      await mesh.initializeForUser(member);
      await sos.stop(record);
      await mesh.publishSosRecord(record);
      expect(mesh.mySos, isNull);
      expect((mesh.inbox.first.data['data'] as Map)['active'], isFalse);
      mesh.dispose();
    },
  );

  test(
    'overlapping initialization, logout and login finish on the new account',
    () async {
      await sos.create(user: member, message: 'private');
      final mesh = NearbyMeshService.withDatabase(local);
      await Future.wait([
        mesh.initializeForUser(member),
        mesh.resetSession(),
        mesh.initializeForUser(other),
      ]);
      final expected = NearbyMeshService.withDatabase(local);
      await expected.initializeForUser(other);
      expect(mesh.deviceId, expected.deviceId);
      expect(mesh.mySos, isNull);
      expect(mesh.rescueActive, isFalse);
      mesh.dispose();
      expected.dispose();
    },
  );

  test('reset and account switch clear private Nearby state', () async {
    final mesh = NearbyMeshService.withDatabase(local);
    await sos.create(user: member, message: 'private');
    await mesh.initializeForUser(member.copyWith(role: AppRole.rescuer));
    final oldIdentity = mesh.deviceId;
    await mesh.setRescue(true);
    mesh.pendingPeer = 'pending';
    mesh.pendingToken = 'secret';
    await mesh.resetSession();
    expect(mesh.deviceId, isEmpty);
    expect(mesh.mySos, isNull);
    expect(mesh.activeSosId, isNull);
    expect(mesh.rescueActive, isFalse);
    expect(mesh.inbox, isEmpty);
    expect(mesh.pendingPeer, isNull);
    expect(mesh.pendingToken, isNull);
    await mesh.initializeForUser(other);
    expect(mesh.deviceId, isNot(oldIdentity));
    expect(mesh.mySos, isNull);
    await mesh.initializeForUser(member);
    expect(mesh.deviceId, oldIdentity);
    mesh.dispose();
  });

  test(
    'Android 11 requests location without unsupported modern permissions',
    () {
      expect(AndroidPermissions.nearbyPermissionsForSdk(30), [
        Permission.locationWhenInUse,
      ]);
    },
  );
  test(
    'Android 12 and 12L request Bluetooth but not Android 13 Wi-Fi permission',
    () {
      for (final sdk in [31, 32]) {
        expect(AndroidPermissions.nearbyPermissionsForSdk(sdk), [
          Permission.locationWhenInUse,
          Permission.bluetoothAdvertise,
          Permission.bluetoothConnect,
          Permission.bluetoothScan,
        ]);
      }
    },
  );
  test(
    'Android 13+ requests nearby Wi-Fi as well as Bluetooth and location',
    () {
      expect(
        AndroidPermissions.nearbyPermissionsForSdk(33),
        contains(Permission.nearbyWifiDevices),
      );
      expect(AndroidPermissions.nearbyPermissionsForSdk(36), hasLength(5));
    },
  );
}
