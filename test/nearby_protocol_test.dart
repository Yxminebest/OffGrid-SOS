import 'dart:async';
import 'package:offgrid_sos/services/mesh_room.dart';
import 'package:offgrid_sos/services/chat_action.dart';
import 'support/mesh_issuer.dart';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:sembast/sembast_memory.dart';
import 'package:offgrid_sos/data/local/local_database.dart';
import 'package:offgrid_sos/data/repositories/nearby_chat_repository.dart';
import 'package:offgrid_sos/data/repositories/sos_repository.dart';
import 'package:offgrid_sos/data/repositories/sos_response_repository.dart';
import 'package:offgrid_sos/models/user.dart';
import 'package:offgrid_sos/services/nearby_mesh_service.dart';
import 'package:offgrid_sos/services/location_service.dart';

const a = AppUser(id: 'a', firstName: 'A', lastName: 'Tester', isMember: true);
const b = AppUser(id: 'b', firstName: 'B', lastName: 'Tester', isMember: true);
const c = AppUser(id: 'c', firstName: 'C', lastName: 'Tester', isMember: true);

class Packet {
  Packet(this.from, this.to, this.data);
  final String from, to;
  final Map<String, dynamic> data;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Map<String, NearbyMeshService> nodes;
  late Map<String, LocalDatabase> dbs;
  late List<Packet> queue;
  late List<Packet> history;
  Completer<void>? stalledBroadcast;
  setUp(() async {
    nodes = {};
    dbs = {};
    queue = [];
    history = [];
    stalledBroadcast = null;
    for (final user in [a, b, c]) {
      final database = await newDatabaseFactoryMemory().openDatabase(user.id);
      dbs[user.id] = LocalDatabase.withDatabase(database);
      nodes[user.id] = NearbyMeshService.withDatabase(
        dbs[user.id]!,
        verifyAttestation: verifyTestAttestation,
        sendBytes: (String endpoint, Uint8List bytes) async {
          final packet = Packet(
            user.id,
            endpoint,
            Map<String, dynamic>.from(jsonDecode(utf8.decode(bytes)) as Map),
          );
          queue.add(packet);
          history.add(packet);
          if (user.id == 'a' &&
              endpoint == 'b' &&
              packet.data['kind'] == 'sos') {
            await stalledBroadcast?.future;
          }
        },
      );
      await nodes[user.id]!.initializeForUser(user);
      await grantTestAttestation(nodes[user.id]!, user);
    }
  });
  Future<void> drain() async {
    var count = 0;
    while (queue.isNotEmpty) {
      expect(++count, lessThan(300), reason: 'protocol must not loop');
      final p = queue.removeAt(0);
      await nodes[p.to]!.handleEnvelope(p.from, p.data);
    }
  }

  Future<Map<String, dynamic>> clearPacket(Packet packet) async {
    if (packet.data['kind'] != 'routed') return packet.data;
    final body = Map<String, dynamic>.from(packet.data['data'] as Map);
    final target = body['target'] as String;
    final sender = nodes[packet.from]!;
    return sender.crypto.open(
      sender.routes[target]!.certificate,
      body,
      '${packet.data['origin']}|$target|${packet.data['id']}',
    );
  }

  Future<void> pair(String first, String second) async {
    await nodes[first]!.transportConnected(second);
    await nodes[second]!.transportConnected(first);
    await drain();
  }

  tearDown(() async {
    for (final node in nodes.values) {
      node.dispose();
    }
    for (final local in dbs.values) {
      await (await local.database).close();
    }
  });

  test(
    'public room reaches every node once through relay and rejects tampering',
    () async {
      await pair('a', 'b');
      await pair('b', 'c');
      await nodes['a']!.sendRoom('ข่าวจาก A');
      await drain();
      for (final id in ['a', 'b', 'c']) {
        expect(
          MeshRoom.project(await nodes[id]!.room.events(id)).single['text'],
          'ข่าวจาก A',
        );
      }
      final event = (await nodes['a']!.room.events('a')).single;
      await nodes['c']!.handleEnvelope('b', event);
      expect(await nodes['c']!.room.events('c'), hasLength(1));
      await nodes['c']!.handleEnvelope('b', {
        ...event,
        'id': 'forged',
        'data': {'text': 'ปลอม'},
      });
      expect(await nodes['c']!.room.events('c'), hasLength(1));
    },
  );

  test(
    'public room queues without links and replays edits and terminal deletes to late joiners',
    () async {
      await nodes['a']!.sendRoom('ข้อความแรก');
      final original = (await nodes['a']!.room.events('a')).single;
      await nodes['a']!.sendRoom(ChatAction.edit(original['id'], 'แก้แล้ว'));
      await pair('a', 'b');
      expect(
        MeshRoom.project(await nodes['b']!.room.events('b')).single['text'],
        'แก้แล้ว',
      );
      await nodes['b']!.sendRoom(ChatAction.delete(original['id']));
      await drain();
      expect(
        MeshRoom.project(await nodes['a']!.room.events('a')),
        hasLength(1),
        reason: 'another author cannot delete A',
      );
      await nodes['a']!.sendRoom(ChatAction.retract(original['id']));
      await nodes['a']!.sendRoom(ChatAction.delete(original['id']));
      await drain();
      await pair('b', 'c');
      for (final id in ['a', 'b', 'c']) {
        expect(MeshRoom.project(await nodes[id]!.room.events(id)), isEmpty);
      }
    },
  );

  test(
    'public room inventory repairs a lost broadcast without reconnecting',
    () async {
      await pair('a', 'b');
      await nodes['a']!.sendRoom('packet lost');
      queue.clear();
      expect(await nodes['b']!.room.events('b'), isEmpty);
      final event = (await nodes['a']!.room.events('a')).single;
      await nodes['b']!.handleEnvelope('a', {
        'v': 1,
        'id': 'inventory',
        'kind': 'room_inventory',
        'origin': nodes['a']!.deviceId,
        'ttl': 0,
        'data': {
          'keys': ['${event['origin']}:${event['id']}'],
        },
      });
      await drain();
      expect(
        MeshRoom.project(await nodes['b']!.room.events('b')).single['text'],
        'packet lost',
      );
    },
  );

  test(
    'one stalled peer does not delay SOS broadcast to other devices',
    () async {
      await pair('a', 'b');
      await pair('a', 'c');
      final record = await SosRepository(
        local: dbs['a'],
      ).create(user: a, message: 'urgent');
      stalledBroadcast = Completer<void>();
      final sending = nodes['a']!.publishSosRecord(record);
      await Future<void>.delayed(const Duration(milliseconds: 30));
      final reached = history.any(
        (p) => p.from == 'a' && p.to == 'c' && p.data['kind'] == 'sos',
      );
      stalledBroadcast!.complete();
      await sending;
      await drain();
      expect(reached, isTrue);
    },
  );

  test(
    'SOS durable receipt crosses relay and verified rescuer progress returns offline',
    () async {
      final rescuer = c.copyWith(role: AppRole.rescuer);
      await nodes['c']!.initializeForUser(rescuer);
      await grantTestAttestation(nodes['c']!, rescuer);
      await pair('a', 'b');
      await pair('b', 'c');
      await nodes['c']!.setRescue(true);
      await drain();
      final repo = SosRepository(local: dbs['a']);
      final record = await repo.create(user: a, message: 'need water');
      await nodes['a']!.publishSosRecord(record);
      await drain();
      final source = nodes['a']!;
      final responseRows = await source.sosResponses
          .watch('a', source.deviceId, record.id)
          .first;
      expect(
        responseRows
            .where(
              (r) =>
                  ((r['envelope'] as Map)['data'] as Map)['category'] ==
                  'receipt',
            )
            .length,
        2,
      );
      expect(
        await nodes['c']!.sosResponses.pending('c', source.deviceId),
        isEmpty,
      );
      final sos = nodes['c']!.currentSosCases.single.data;
      await nodes['c']!.updateRescueCase(sos, 'accepted');
      await drain();
      await nodes['c']!.updateRescueCase(sos, 'helping');
      await drain();
      final progress =
          (await source.sosResponses
                  .watch('a', source.deviceId, record.id)
                  .first)
              .where(
                (r) =>
                    ((r['envelope'] as Map)['data'] as Map)['category'] ==
                    'progress',
              )
              .single;
      expect(
        ((progress['envelope'] as Map)['data'] as Map)['state'],
        'helping',
      );
      await nodes['c']!.updateRescueCase(sos, 'completed');
      await drain();
      expect(
        (await repo.findById(record.id))!.isActive,
        isFalse,
        reason: 'Verified rescue completion closes the same SOS case',
      );
      expect(source.mySos, isNull);
      expect(nodes['b']!.currentSosCases, isEmpty);
      expect(nodes['c']!.currentSosCases, isEmpty);
      final endedRevision = (await repo.findById(record.id))!.revision;
      await expectLater(
        nodes['c']!.updateRescueCase(sos, 'accepted'),
        throwsStateError,
      );
      final next = await repo.create(user: a, message: 'a new emergency');
      await source.publishSosRecord(next);
      await drain();
      await SosResponseRepository.store
          .record(
            'c:${source.deviceId}:${record.id}:${nodes['c']!.deviceId}:progress',
          )
          .update(await dbs['c']!.database, {'delivery': 'pending'});
      await nodes['c']!.retryFor(source.deviceId);
      await drain();
      expect(
        await nodes['c']!.sosResponses.pending('c', source.deviceId),
        isEmpty,
      );
      expect(source.activeSosId, next.id);
      expect((await repo.findById(next.id))!.isActive, isTrue);
      expect((await repo.findById(record.id))!.revision, endedRevision);
      expect(
        nodes['c']!.currentSosCases.single.data['data']['caseId'],
        next.id,
      );
      await expectLater(
        nodes['c']!.updateRescueCase(sos, 'helping'),
        throwsStateError,
      );
    },
  );

  test(
    'lost completion ACK retries without reopening SOS or incrementing its close revision',
    () async {
      final rescuer = c.copyWith(role: AppRole.rescuer);
      await nodes['c']!.initializeForUser(rescuer);
      await grantTestAttestation(nodes['c']!, rescuer);
      await pair('a', 'c');
      await nodes['c']!.setRescue(true);
      await drain();
      final repo = SosRepository(local: dbs['a']);
      final record = await repo.create(user: a, message: 'help');
      await nodes['a']!.publishSosRecord(record);
      await drain();
      final sos = nodes['c']!.currentSosCases.single.data;
      await nodes['c']!.updateRescueCase(sos, 'accepted');
      await drain();
      await nodes['c']!.updateRescueCase(sos, 'helping');
      await drain();
      await nodes['c']!.updateRescueCase(sos, 'completed');
      var count = 0;
      // Simulate restart between saving the response and closing the SOS.
      final savedCompletion = await nodes['c']!.sosResponses.stored(
        'c',
        nodes['a']!.deviceId,
        record.id,
        nodes['c']!.deviceId,
        'progress',
      );
      await nodes['a']!.sosResponses.receive('a', savedCompletion!);
      while (queue.isNotEmpty) {
        expect(++count, lessThan(100));
        final packet = queue.removeAt(0);
        if (packet.from != 'a') {
          await nodes[packet.to]!.handleEnvelope(packet.from, packet.data);
        }
      }
      final closed = (await repo.findById(record.id))!;
      expect(closed.isActive, isFalse);
      expect(nodes['c']!.currentSosCases, isEmpty);
      expect(
        await nodes['c']!.sosResponses.pending('c', nodes['a']!.deviceId),
        hasLength(1),
      );
      expect(
        await nodes['c']!.sosResponses.completedCases('c'),
        contains('${nodes['a']!.deviceId}:${record.id}'),
      );
      final restored = NearbyMeshService.withDatabase(
        dbs['c']!,
        verifyAttestation: verifyTestAttestation,
      );
      await restored.initializeForUser(rescuer);
      restored.routes.addAll(nodes['c']!.routes);
      restored.connected.addAll(nodes['c']!.connected);
      expect(restored.peerForDevice(nodes['a']!.deviceId), isNotNull);
      expect(restored.currentSosCases, isEmpty);
      restored.dispose();
      await nodes['c']!.retryFor(nodes['a']!.deviceId);
      await drain();
      expect((await repo.findById(record.id))!.revision, closed.revision);
      expect(nodes['a']!.mySos, isNull);
      expect(
        await nodes['c']!.sosResponses.pending('c', nodes['a']!.deviceId),
        isEmpty,
      );
    },
  );

  test(
    'ordinary peer cannot accept SOS and unauthenticated receipt is ignored',
    () async {
      await pair('a', 'b');
      final record = await SosRepository(
        local: dbs['a'],
      ).create(user: a, message: 'help');
      await nodes['a']!.publishSosRecord(record);
      await drain();
      await expectLater(
        nodes['b']!.updateRescueCase(
          nodes['b']!.currentSosCases.single.data,
          'accepted',
        ),
        throwsStateError,
      );
      await nodes['a']!.handleEnvelope('b', {
        'v': 1,
        'id': 'forged-response',
        'kind': 'sos_response',
        'origin': nodes['b']!.deviceId,
        'ttl': 3,
        'data': {
          'target': nodes['a']!.deviceId,
          'caseOrigin': nodes['a']!.deviceId,
          'caseId': record.id,
          'category': 'progress',
          'state': 'completed',
          'revision': record.revision,
          'sequence': 999,
        },
      });
      final rows = await nodes['a']!.sosResponses
          .watch('a', nodes['a']!.deviceId, record.id)
          .first;
      expect(
        rows.where(
          (r) =>
              ((r['envelope'] as Map)['data'] as Map)['category'] == 'progress',
        ),
        isEmpty,
      );
      expect(
        (await SosRepository(local: dbs['a']).findById(record.id))!.isActive,
        isTrue,
      );
    },
  );

  test(
    'lost SOS receipt ACK retries from durable storage with same ID',
    () async {
      await pair('a', 'b');
      final record = await SosRepository(
        local: dbs['a'],
      ).create(user: a, message: 'help');
      await nodes['a']!.publishSosRecord(record);
      while (queue.isNotEmpty) {
        final p = queue.removeAt(0);
        final clear = await clearPacket(p);
        if (clear['kind'] == 'sos_response_ack') continue;
        await nodes[p.to]!.handleEnvelope(p.from, p.data);
      }
      final pending = await nodes['b']!.sosResponses.pending(
        'b',
        nodes['a']!.deviceId,
      );
      expect(pending, hasLength(1));
      await nodes['b']!.retryFor(nodes['a']!.deviceId);
      await drain();
      expect(
        await nodes['b']!.sosResponses.pending('b', nodes['a']!.deviceId),
        isEmpty,
      );
      expect(
        await nodes['a']!.sosResponses
            .watch('a', nodes['a']!.deviceId, record.id)
            .first,
        hasLength(1),
      );
    },
  );

  test(
    'fresh SOS coordinates reach peer and refresh never reactivates cancelled case',
    () async {
      await pair('a', 'b');
      final repo = SosRepository(local: dbs['a']);
      final record = await repo.create(
        user: a,
        message: 'help',
        location: SavedLocation(
          latitude: 14,
          longitude: 100.6,
          accuracyMeters: 49,
          recordedAt: DateTime.now(),
        ),
      );
      await nodes['a']!.publishSosRecord(record);
      await drain();
      final updated = await repo.updateLocation(
        record,
        SavedLocation(
          latitude: 14.001,
          longitude: 100.601,
          accuracyMeters: 5,
          recordedAt: DateTime.now(),
        ),
      );
      await nodes['a']!.publishSosRecord(updated!);
      await drain();
      final body =
          nodes['b']!.inbox.firstWhere((m) => m.kind == 'sos').data['data']
              as Map;
      expect(body['lat'], 14.001);
      expect(body['accuracy'], 5);
      expect(body['caseId'], record.id);
      expect(body['revision'], greaterThan(record.revision));
      await repo.stop(updated);
      expect(
        await repo.updateLocation(
          updated,
          SavedLocation(
            latitude: 14.002,
            longitude: 100.602,
            accuracyMeters: 4,
            recordedAt: DateTime.now(),
          ),
        ),
        isNull,
      );
      expect((await repo.findById(record.id))!.isActive, isFalse);
    },
  );

  test(
    'discovery advertises SOS and rescue before pairing without broadcasting coordinates',
    () async {
      await nodes['a']!.initializeForUser(a.copyWith(role: AppRole.rescuer));
      await grantTestAttestation(
        nodes['a']!,
        a.copyWith(role: AppRole.rescuer),
      );
      await nodes['a']!.setRescue(true);
      nodes['b']!.discovered('endpoint-a', nodes['a']!.discoveryName);
      expect(nodes['b']!.discoveredModes['endpoint-a'], 'R');
      final record = await SosRepository(
        local: dbs['a'],
      ).create(user: a, message: 'help');
      await nodes['a']!.publishSosRecord(record);
      expect(
        NearbyMeshService.parseDiscoveryName(nodes['a']!.discoveryName).mode,
        'S',
      );
      expect(nodes['a']!.discoveryName, isNot(contains('14.1')));
      await nodes['a']!.stopSos();
      await nodes['a']!.setRescue(false);
      expect(
        NearbyMeshService.parseDiscoveryName(nodes['a']!.discoveryName).mode,
        'N',
      );
      expect(
        NearbyMeshService.parseDiscoveryName('Older phone').name,
        'Older phone',
      );
    },
  );

  test(
    'multi-hop private text is encrypted through B and ACK returns to A',
    () async {
      await pair('a', 'b');
      await pair('b', 'c');
      expect(nodes['a']!.peerForDevice(nodes['c']!.deviceId)?.hops, 2);
      history.clear();
      await nodes['a']!.sendDirect(
        target: nodes['c']!.deviceId,
        text: 'secret across two hops',
      );
      await drain();
      final received = await nodes['c']!.chats
          .watchMessages('c', nodes['a']!.deviceId)
          .first;
      expect(received, hasLength(1));
      expect(
        (received.single['envelope'] as Map)['data']['text'],
        'secret across two hops',
      );
      expect(await nodes['b']!.chats.watchThreads('b').first, isEmpty);
      expect(history.where((p) => p.data['kind'] == 'routed'), isNotEmpty);
      expect(
        history.map((p) => jsonEncode(p.data)).join(),
        isNot(contains('secret across two hops')),
      );
      final sent = await nodes['a']!.chats
          .watchMessages('a', nodes['c']!.deviceId)
          .first;
      expect(sent.single['delivery'], 'delivered');
    },
  );

  test(
    'location queues offline, reaches its peer encrypted, and receives an ACK',
    () async {
      final target = nodes['c']!.deviceId;
      final location = SavedLocation(
        latitude: 13.73,
        longitude: 100.541,
        recordedAt: DateTime.utc(2026, 10, 19, 8),
        isLastKnown: true,
        accuracyMeters: 15,
      );
      await nodes['a']!.sendLocation(
        target: target,
        location: location,
        caseId: 'case-1',
      );
      expect(
        (await nodes['a']!.chats.watchMessages('a', target).first)
            .single['delivery'],
        'pending',
      );
      await pair('a', 'b');
      await pair('b', 'c');
      await nodes['a']!.retryFor(target);
      await drain();
      final rows = await nodes['c']!.chats
          .watchMessages('c', nodes['a']!.deviceId)
          .first;
      final body = (rows.single['envelope'] as Map)['data'] as Map;
      expect(body['type'], 'location');
      expect(body['lat'], 13.73);
      expect(body['lng'], 100.541);
      expect(body['caseId'], 'case-1');
      expect(body['lastKnown'], isTrue);
      expect(body['recordedAt'], '2026-10-19T08:00:00.000Z');
      expect(
        (await nodes['a']!.chats.watchMessages('a', target).first)
            .single['delivery'],
        'delivered',
      );
      expect(await nodes['b']!.chats.watchThreads('b').first, isEmpty);
      expect(
        history
            .where((p) => p.data['kind'] == 'routed')
            .map((p) => jsonEncode(p.data))
            .join(),
        isNot(contains('100.541')),
      );
    },
  );

  test('invalid shared coordinates never enter the send queue', () async {
    await expectLater(
      nodes['a']!.sendLocation(
        target: nodes['b']!.deviceId,
        location: SavedLocation(
          latitude: double.nan,
          longitude: 100,
          recordedAt: DateTime.now(),
        ),
      ),
      throwsArgumentError,
    );
    expect(await nodes['a']!.chats.watchThreads('a').first, isEmpty);
  });

  test(
    'three offline nodes recover a queued message after the relay restarts',
    () async {
      await pair('a', 'b');
      await pair('b', 'c');
      final target = nodes['c']!.deviceId;
      final relayIdentity = nodes['b']!.deviceId;
      await nodes['b']!.stop();
      await drain();
      expect(nodes['a']!.peerForDevice(target), isNull);
      await nodes['a']!.sendDirect(
        target: target,
        text: 'waiting for the bridge',
      );
      expect(
        await nodes['c']!.chats.watchMessages('c', nodes['a']!.deviceId).first,
        isEmpty,
      );
      nodes['b']!.dispose();
      nodes['b'] = NearbyMeshService.withDatabase(
        dbs['b']!,
        verifyAttestation: verifyTestAttestation,
        sendBytes: (endpoint, bytes) async {
          final packet = Packet(
            'b',
            endpoint,
            Map<String, dynamic>.from(jsonDecode(utf8.decode(bytes)) as Map),
          );
          queue.add(packet);
          history.add(packet);
        },
      );
      await nodes['b']!.initializeForUser(b);
      expect(nodes['b']!.deviceId, relayIdentity);
      await pair('a', 'b');
      await pair('b', 'c');
      final deadline = DateTime.now().add(const Duration(seconds: 3));
      while (DateTime.now().isBefore(deadline)) {
        await drain();
        final sent = await nodes['a']!.chats.watchMessages('a', target).first;
        if (sent.single['delivery'] == 'delivered') break;
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }
      final sent = await nodes['a']!.chats.watchMessages('a', target).first;
      expect(sent.single['delivery'], 'delivered');
      expect(
        await nodes['c']!.chats.watchMessages('c', nodes['a']!.deviceId).first,
        hasLength(1),
      );
      expect(await nodes['b']!.chats.watchThreads('b').first, isEmpty);
    },
  );

  test(
    'a lost receipt retries the same offline message without duplicating receiver history',
    () async {
      await pair('a', 'b');
      final target = nodes['b']!.deviceId;
      await nodes['a']!.sendDirect(target: target, text: 'receipt loss');
      while (queue.isNotEmpty) {
        final packet = queue.removeAt(0);
        if ((await clearPacket(packet))['kind'] != 'ack') {
          await nodes[packet.to]!.handleEnvelope(packet.from, packet.data);
        }
      }
      expect(
        (await nodes['a']!.chats.watchMessages('a', target).first)
            .single['delivery'],
        'sent',
      );
      await nodes['a']!.retryFor(target);
      await drain();
      expect(
        (await nodes['a']!.chats.watchMessages('a', target).first)
            .single['delivery'],
        'delivered',
      );
      expect(
        await nodes['b']!.chats.watchMessages('b', nodes['a']!.deviceId).first,
        hasLength(1),
      );
    },
  );

  test(
    'SOS and its cancellation cross three offline nodes and stay cancelled after reopening',
    () async {
      final repo = SosRepository(local: dbs['a']);
      final sos = await repo.create(user: a, message: 'three phone SOS');
      await nodes['a']!.publishSosRecord(sos);
      await pair('a', 'b');
      await pair('b', 'c');
      final received = await nodes['c']!.chats.watchSos('c').first;
      expect((received.single['data'] as Map)['active'], isTrue);
      await repo.stop(sos);
      await nodes['a']!.stopSos(caseId: sos.id);
      await drain();
      expect(
        ((await nodes['c']!.chats.watchSos('c').first).single['data']
            as Map)['active'],
        isFalse,
      );
      final reopened = NearbyMeshService.withDatabase(
        dbs['c']!,
        verifyAttestation: verifyTestAttestation,
      );
      await reopened.initializeForUser(c);
      final reopenedSos = reopened.inbox.where(
        (message) =>
            message.kind == 'sos' &&
            (message.data['data'] as Map)['caseId'] == sos.id,
      );
      expect(reopenedSos, hasLength(1));
      expect((reopenedSos.single.data['data'] as Map)['active'], isFalse);
      reopened.dispose();
    },
  );

  test('tampered routed ciphertext cannot enter recipient history', () async {
    await pair('a', 'b');
    await pair('b', 'c');
    await nodes['a']!.sendDirect(
      target: nodes['c']!.deviceId,
      text: 'authentic',
    );
    final packet = queue.firstWhere((p) => p.data['kind'] == 'routed');
    queue.clear();
    final body = Map<String, dynamic>.from(packet.data['data']);
    body['mac'] = base64Encode(List.filled(16, 0));
    await nodes['b']!.handleEnvelope('a', {...packet.data, 'data': body});
    await drain();
    expect(await nodes['c']!.chats.watchThreads('c').first, isEmpty);
  });

  test('ordinary member cannot enable rescue through service', () async {
    await expectLater(nodes['a']!.setRescue(true), throwsStateError);
    expect(nodes['a']!.rescueActive, isFalse);
  });

  test(
    'route withdrawal removes unreachable C from A when B loses C',
    () async {
      await pair('a', 'b');
      await pair('b', 'c');
      expect(nodes['a']!.peerForDevice(nodes['c']!.deviceId), isNotNull);
      await nodes['c']!.stop();
      await drain();
      expect(nodes['a']!.peerForDevice(nodes['c']!.deviceId), isNull);
    },
  );

  test(
    'rescue state replays on late join and off replaces active state',
    () async {
      await nodes['a']!.initializeForUser(a.copyWith(role: AppRole.rescuer));
      await grantTestAttestation(
        nodes['a']!,
        a.copyWith(role: AppRole.rescuer),
      );
      await nodes['a']!.setRescue(true);
      await pair('a', 'b');
      var status = nodes['b']!.inbox
          .where(
            (m) =>
                m.kind == 'rescue' && m.data['origin'] == nodes['a']!.deviceId,
          )
          .single;
      expect(status.data['data']['active'], true);
      await nodes['a']!.setRescue(false);
      await drain();
      status = nodes['b']!.inbox
          .where(
            (m) =>
                m.kind == 'rescue' && m.data['origin'] == nodes['a']!.deviceId,
          )
          .single;
      expect(status.data['data']['active'], false);
    },
  );

  test(
    'direct messages and case replies reach only their recipient and survive restart',
    () async {
      await pair('a', 'b');
      await pair('a', 'c');
      history.clear();
      await nodes['a']!.sendDirect(
        target: nodes['b']!.deviceId,
        text: 'private B',
        peerName: 'B',
      );
      await drain();
      final encryptedForB = history.where(
        (p) =>
            p.from == 'a' &&
            p.data['kind'] == 'routed' &&
            (p.data['data'] as Map)['target'] == nodes['b']!.deviceId,
      );
      expect(encryptedForB, isNotEmpty);
      expect(
        history.where((p) => p.from == 'a' && p.data['kind'] == 'direct'),
        isEmpty,
      );
      expect(await nodes['c']!.chats.watchThreads('c').first, isEmpty);
      var received = await nodes['b']!.chats
          .watchMessages('b', nodes['a']!.deviceId)
          .first;
      expect(received, hasLength(1));
      final sent = await nodes['a']!.chats
          .watchMessages('a', nodes['b']!.deviceId)
          .first;
      expect(sent.single['delivery'], 'delivered');
      final original = history.firstWhere(
        (p) =>
            p.from == 'a' &&
            p.data['kind'] == 'routed' &&
            (p.data['data'] as Map)['target'] == nodes['b']!.deviceId,
      );
      await nodes['b']!.handleEnvelope('a', original.data);
      await drain();
      received = await NearbyChatRepository(
        local: dbs['b'],
      ).watchMessages('b', nodes['a']!.deviceId).first;
      expect(
        received,
        hasLength(1),
        reason: 'retries must not duplicate messages',
      );
      await nodes['a']!.sendCaseReply(
        caseId: 'case-1',
        target: nodes['b']!.deviceId,
        text: 'case private',
      );
      await drain();
      expect(await nodes['c']!.chats.watchThreads('c').first, isEmpty);
      expect(
        (await nodes['b']!.chats
            .watchMessages('b', nodes['a']!.deviceId)
            .first),
        hasLength(2),
      );
    },
  );

  test(
    'disconnected messages remain queued then receive a matching acknowledgment',
    () async {
      final target = nodes['b']!.deviceId;
      expect(
        await nodes['a']!.sendDirect(
          target: target,
          text: 'offline draft',
          peerName: 'B',
        ),
        0,
      );
      expect(await nodes['a']!.chats.pending('a', target), hasLength(1));
      await pair('a', 'b');
      expect(await nodes['a']!.chats.pending('a', target), isEmpty);
      expect(
        (await nodes['b']!.chats
            .watchMessages('b', nodes['a']!.deviceId)
            .first),
        hasLength(1),
      );
    },
  );

  test('a third peer cannot acknowledge another recipients message', () async {
    await pair('a', 'c');
    final target = nodes['b']!.deviceId;
    await nodes['a']!.sendDirect(target: target, text: 'queued for B');
    final pending = (await nodes['a']!.chats.pending('a', target)).single;
    await nodes['a']!.handleEnvelope('c', {
      'v': 1,
      'id': 'false-ack',
      'kind': 'ack',
      'origin': nodes['c']!.deviceId,
      'ttl': 0,
      'data': {'messageId': pending['id'], 'target': nodes['a']!.deviceId},
    });
    expect(await nodes['a']!.chats.pending('a', target), hasLength(1));
  });

  test(
    'cancelled SOS replays after disconnect and stale active revision is rejected',
    () async {
      final repo = SosRepository(local: dbs['a']);
      final record = await repo.create(user: a, message: 'TEST SOS');
      await pair('a', 'b');
      final oldActive = Map<String, dynamic>.from(
        history.firstWhere((p) => p.to == 'b' && p.data['kind'] == 'sos').data,
      );
      bool sosActive(NearbyMeshService node) =>
          (node.inbox
                  .firstWhere((message) => message.kind == 'sos')
                  .data['data']
              as Map)['active'] ==
          true;
      expect(sosActive(nodes['b']!), isTrue);
      nodes['a']!.connected.clear();
      nodes['b']!.connected.clear();
      await repo.stop(record);
      await nodes['a']!.stopSos(caseId: record.id);
      expect(nodes['a']!.mySos, isNull);
      await pair('a', 'b');
      expect(sosActive(nodes['b']!), isFalse);
      await nodes['b']!.handleEnvelope('a', {
        ...oldActive,
        'id': 'late-active',
      });
      expect(sosActive(nodes['b']!), isFalse);
      final reopened = NearbyMeshService.withDatabase(
        dbs['b']!,
        verifyAttestation: verifyTestAttestation,
      );
      await reopened.initializeForUser(b);
      expect(sosActive(reopened), isFalse);
      final storedHistory = await reopened.chats.watchSos('b').first;
      expect(storedHistory, hasLength(1));
      expect((storedHistory.single['data'] as Map)['active'], isFalse);
      expect(await reopened.chats.watchSos('other-owner').first, isEmpty);
      reopened.dispose();
    },
  );

  test(
    'stopping one endpoint immediately removes it from the other peer list',
    () async {
      await pair('a', 'b');
      nodes['b']!.peers['a'] = 'A';
      await nodes['a']!.stop();
      await drain();
      expect(nodes['b']!.connected, isEmpty);
      expect(nodes['b']!.peers.containsKey('a'), isFalse);
      expect(nodes['b']!.identities.containsKey('a'), isFalse);
    },
  );

  test(
    'wrong target private envelopes are neither stored nor relayed',
    () async {
      await pair('a', 'b');
      history.clear();
      await nodes['b']!.handleEnvelope('a', {
        'v': 1,
        'id': 'wrong-target',
        'kind': 'direct',
        'origin': nodes['a']!.deviceId,
        'ttl': 3,
        'data': {'target': nodes['c']!.deviceId, 'text': 'not B'},
      });
      expect(await nodes['b']!.chats.watchThreads('b').first, isEmpty);
      expect(history, isEmpty);
    },
  );
  test(
    'relay reachability suppresses a duplicate unconnected discovery row',
    () async {
      await pair('a', 'b');
      await pair('b', 'c');
      final mesh = nodes['a']!;
      final remote = nodes['c']!;
      mesh.discovered(
        'c-discovery',
        'OG10:N:${NearbyMeshService.discoveryHint(remote.deviceId)}:C Tester',
      );
      expect(mesh.peerForDevice(remote.deviceId)?.hops, 2);
      expect(mesh.visiblePeers.containsKey('c-discovery'), isFalse);
      expect(
        mesh.reachablePeers.where((p) => p.deviceId == remote.deviceId),
        hasLength(1),
      );
    },
  );

  test('a live alternate path survives loss of the direct link', () async {
    await pair('a', 'b');
    await pair('b', 'c');
    await pair('a', 'c');
    await nodes['b']!.refreshRoutes();
    await drain();
    final target = nodes['a']!.deviceId;
    expect(nodes['c']!.peerForDevice(target)?.endpoint, 'a');
    await nodes['c']!.handleEnvelope('a', {
      'v': 1,
      'id': 'lose-a',
      'kind': 'goodbye',
      'origin': target,
      'ttl': 0,
      'data': <String, dynamic>{},
    });
    expect(nodes['c']!.peerForDevice(target)?.endpoint, 'b');
    await nodes['a']!.handleEnvelope('c', {
      'v': 1,
      'id': 'lose-c',
      'kind': 'goodbye',
      'origin': nodes['c']!.deviceId,
      'ttl': 0,
      'data': <String, dynamic>{},
    });
    await Future<void>.delayed(const Duration(milliseconds: 15));
    await drain();
    await nodes['c']!.sendDirect(target: target, text: 'through backup');
    await drain();
    final rows = await nodes['a']!.chats
        .watchMessages('a', nodes['c']!.deviceId)
        .first;
    expect((rows.single['envelope'] as Map)['data']['text'], 'through backup');
  });

  test(
    'route refresh repairs expired relay paths without restarting radios',
    () async {
      await pair('a', 'b');
      await pair('b', 'c');
      final target = nodes['c']!.deviceId;
      nodes['a']!.routes[target]!.expires = DateTime.now().subtract(
        const Duration(seconds: 1),
      );
      expect(nodes['a']!.peerForDevice(target), isNull);
      await nodes['b']!.refreshRoutes();
      await drain();
      expect(nodes['a']!.peerForDevice(target)?.hops, 2);
      expect(nodes['a']!.connected, contains('b'));
    },
  );

  test(
    'automatic pairing elects one initiator with a bounded passive fallback',
    () {
      expect(NearbyMeshService.initiatesAutomatically('a', 'b'), isTrue);
      expect(NearbyMeshService.initiatesAutomatically('b', 'a'), isFalse);
      expect(
        NearbyMeshService.initiatesAutomatically(
          'b',
          'a',
          waited: const Duration(seconds: 5),
        ),
        isTrue,
      );
    },
  );
  test(
    'losing both links to A withdraws alternates without a routing loop',
    () async {
      await pair('a', 'b');
      await pair('b', 'c');
      await pair('a', 'c');
      await nodes['b']!.refreshRoutes();
      await nodes['c']!.refreshRoutes();
      await drain();
      final target = nodes['a']!.deviceId;
      for (final id in ['b', 'c']) {
        await nodes[id]!.handleEnvelope('a', {
          'v': 1,
          'id': 'lose-a-$id',
          'kind': 'goodbye',
          'origin': target,
          'ttl': 0,
          'data': <String, dynamic>{},
        });
      }
      await Future<void>.delayed(const Duration(milliseconds: 20));
      await drain();
      expect(nodes['b']!.peerForDevice(target), isNull);
      expect(nodes['c']!.peerForDevice(target), isNull);
      expect(nodes['b']!.peerForDevice(nodes['c']!.deviceId), isNotNull);
    },
  );
}
