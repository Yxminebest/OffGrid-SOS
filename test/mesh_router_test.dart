import 'package:flutter_test/flutter_test.dart';
import 'package:sembast/sembast_memory.dart';
import 'package:offgrid_sos/data/local/local_database.dart';
import 'package:offgrid_sos/models/mesh_packet.dart';
import 'package:offgrid_sos/services/mesh/mesh_router.dart';
import 'package:offgrid_sos/services/mesh/mesh_router_store.dart';
import 'package:offgrid_sos/services/mesh/mesh_dedup_cache.dart';
import 'support/fake_mesh_transport.dart';

void main() {
  late FakeNetwork network;
  late Map<String, MeshRouter> routers;
  late Map<String, List<MeshPacket>> delivered;
  final sentAt = DateTime.utc(2026, 11, 4, 3, 20);
  MeshPacket message(String from, String to, {int ttl = 8}) =>
      MeshPacket.create(
        senderId: from,
        destinationId: to,
        payload: {'text': 'ข่าว'},
        timestamp: sentAt,
        ttl: ttl,
      );
  Future<void> settle() => network.drain(routers.values);
  setUp(() async {
    network = FakeNetwork();
    routers = {};
    delivered = {};
    for (final id in ['A', 'B', 'C']) {
      delivered[id] = [];
      routers[id] = MeshRouter(
        nodeId: id,
        transport: network.node(id),
        store: MemoryMeshRouterStore(),
        retryInterval: Duration.zero,
        onDeliver: (packet) async => delivered[id]!.add(packet),
      );
      await routers[id]!.start();
    }
  });
  tearDown(() async {
    for (final router in routers.values) {
      await router.close();
    }
    for (final transport in network.nodes.values) {
      await transport.close();
    }
  });

  test(
    'A and B communicate directly in both directions with original time',
    () async {
      await network.node('A').connect('B');
      await routers['A']!.send(message('A', 'B'));
      await routers['B']!.send(message('B', 'A'));
      await settle();
      expect(delivered['A'], hasLength(1));
      expect(delivered['B'], hasLength(1));
      expect(delivered['B']!.single.timestamp, sentAt);
      expect(delivered['B']!.single.hopCount, 1);
    },
  );
  test(
    'after A-B breaks, C relays queued B-A and A-B without duplicate delivery',
    () async {
      await network.node('A').connect('B');
      await routers['A']!.send(message('A', 'B'));
      await settle();
      await network.node('A').disconnect('B');
      final packet = message('B', 'A');
      await routers['B']!.send(packet);
      await settle();
      expect(delivered['A'], isEmpty);
      await network.node('A').connect('C');
      await network.node('C').connect('B');
      await settle();
      expect(delivered['A']!.single.id, packet.id);
      expect(delivered['A']!.single.hopCount, 2);
      await routers['A']!.send(message('A', 'B'));
      await settle();
      expect(delivered['B'], hasLength(2));
    },
  );
  test(
    'dedup suppresses repeated packets and TTL zero is dropped before delivery',
    () async {
      await network.node('A').connect('B');
      final packet = message('A', 'B');
      network.node('B').inject('A', packet);
      network.node('B').inject('A', packet);
      network.node('B').inject('A', message('A', 'B', ttl: 0));
      await settle();
      expect(delivered['B'], hasLength(1));
    },
  );
  test(
    'TTL cannot cross more hops than its budget and is never reset by queue',
    () async {
      await network.node('A').connect('C');
      await routers['A']!.send(message('A', 'B', ttl: 2));
      await settle();
      await network.node('C').connect('B');
      await settle();
      expect(delivered['B'], isEmpty);
    },
  );
  test(
    'A-B-C-A cycle delivers broadcast once per node and terminates',
    () async {
      await network.node('A').connect('B');
      await network.node('B').connect('C');
      await network.node('C').connect('A');
      await routers['A']!.send(message('A', MeshPacket.broadcast));
      await settle();
      for (final list in delivered.values) {
        expect(list, hasLength(1));
      }
      expect(network.transmissions, lessThanOrEqualTo(6));
    },
  );
  test(
    'failed send retries after link recovers and preserves UUID/time/ttl',
    () async {
      final transport = network.node('A');
      transport.failSend = true;
      await transport.connect('B');
      final packet = message('A', 'B');
      await routers['A']!.send(packet);
      await settle();
      expect(delivered['B'], isEmpty);
      transport.failSend = false;
      await routers['A']!.flush();
      await settle();
      expect(delivered['B']!.single.id, packet.id);
      expect(delivered['B']!.single.timestamp, sentAt);
      expect(delivered['B']!.single.ttl, packet.ttl - 1);
    },
  );
  test(
    'store-and-forward survives router restart with a persistent local queue',
    () async {
      final db = await newDatabaseFactoryMemory().openDatabase('relay-queue');
      final store = LocalMeshRouterStore(
        LocalDatabase.withDatabase(db),
        'owner:A',
      );
      await routers['A']!.close();
      MeshRouter create() => MeshRouter(
        nodeId: 'A',
        transport: network.node('A'),
        store: store,
        retryInterval: Duration.zero,
        onDeliver: (_) async {},
      );
      routers['A'] = create();
      await routers['A']!.start();
      final packet = message('A', 'B');
      await routers['A']!.send(packet);
      await routers['A']!.close();
      routers['A'] = create();
      await routers['A']!.start();
      await network.node('A').connect('B');
      await settle();
      expect(delivered['B']!.single.id, packet.id);
      await routers['A']!.close();
      await db.close();
    },
  );
  test('dedup cache is bounded and expires using injected receive clock', () {
    var clock = sentAt;
    final cache = MeshDedupCache(
      capacity: 2,
      maxAge: const Duration(seconds: 10),
      now: () => clock,
    );
    expect(cache.remember('1'), isTrue);
    expect(cache.remember('1'), isFalse);
    cache.remember('2');
    cache.remember('3');
    expect(cache.length, 2);
    expect(cache.contains('1'), isFalse);
    clock = clock.add(const Duration(seconds: 10));
    expect(cache.length, 0);
    expect(cache.remember('3'), isTrue);
  });
  test(
    'model JSON preserves offline timestamp and rejects invalid TTL/UUID',
    () {
      final packet = message('A', 'B');
      expect(MeshPacket.fromJson(packet.toJson()).timestamp, sentAt);
      expect(
        () => MeshPacket.fromJson({...packet.toJson(), 'id': 'invalid'}),
        throwsFormatException,
      );
      expect(
        () => MeshPacket.fromJson({...packet.toJson(), 'ttl': -1}),
        throwsFormatException,
      );
    },
  );
}
