import 'package:flutter_test/flutter_test.dart';
import 'package:sembast/sembast_memory.dart';
import 'package:offgrid_sos/data/local/local_database.dart';
import 'package:offgrid_sos/models/user.dart';
import 'package:offgrid_sos/services/nearby_mesh_service.dart';

void main() {
  test(
    'old persisted SOS is history until origin has a live direct or relay route',
    () async {
      final db = await newDatabaseFactoryMemory().openDatabase('stale-sos');
      final mesh = NearbyMeshService.withDatabase(
        LocalDatabase.withDatabase(db),
      );
      const me = AppUser(
        id: 'owner',
        firstName: 'A',
        lastName: '',
        isMember: false,
      );
      final old = <String, dynamic>{
        'id': 'old',
        'kind': 'sos',
        'origin': 'chiti',
        'sender': 'Chiti',
        'at': '2026-10-30T05:28:23Z',
        'data': {
          'caseId': 'old-case',
          'active': true,
          'revision': 1,
          'text': 'ขาดน้ำมาก',
        },
      };
      await mesh.chats.saveSos(me.id, old);
      await mesh.initializeForUser(me);
      expect(mesh.inbox.where((m) => m.kind == 'sos'), hasLength(1));
      expect(mesh.currentSosCases, isEmpty);
      // Internet/session restore alone must not promote a saved case.
      await mesh.initializeForUser(me);
      expect(mesh.currentSosCases, isEmpty);
      mesh.connected.add('direct');
      mesh.identities['direct'] = const NearbyPeer(
        endpoint: 'direct',
        deviceId: 'chiti',
        name: 'Chiti',
      );
      expect(mesh.currentSosCases, hasLength(1));
      mesh.connected.clear();
      expect(mesh.currentSosCases, isEmpty);
      mesh.connected.add('bridge');
      mesh.routes['chiti'] = MeshRoute(
        {'name': 'Chiti'},
        'bridge',
        2,
        DateTime.now().add(const Duration(minutes: 1)),
        ['bridge', 'chiti'],
      );
      expect(mesh.currentSosCases, hasLength(1));
      mesh.routes['chiti']!.expires = DateTime.now().subtract(
        const Duration(seconds: 1),
      );
      expect(mesh.currentSosCases, isEmpty);
      mesh.routes['chiti']!.expires = DateTime.now().add(
        const Duration(minutes: 1),
      );
      mesh.inbox.insert(
        0,
        MeshMessage({
          ...old,
          'id': 'stop',
          'data': {'caseId': 'old-case', 'active': false, 'revision': 2},
        }),
      );
      expect(mesh.currentSosCases, isEmpty);
      expect(await mesh.chats.loadSos(me.id), hasLength(1));
      mesh.dispose();
      await db.close();
    },
  );
}
