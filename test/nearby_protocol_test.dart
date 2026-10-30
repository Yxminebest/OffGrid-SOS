import 'support/mesh_issuer.dart';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:sembast/sembast_memory.dart';
import 'package:offgrid_sos/data/local/local_database.dart';
import 'package:offgrid_sos/data/repositories/nearby_chat_repository.dart';
import 'package:offgrid_sos/data/repositories/sos_repository.dart';
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
  setUp(() async {
    nodes = {};
    dbs = {};
    queue = [];
    history = [];
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
}
