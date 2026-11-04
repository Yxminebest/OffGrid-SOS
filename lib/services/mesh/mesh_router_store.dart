import 'package:sembast/sembast.dart';
import '../../data/local/local_database.dart';

abstract interface class MeshRouterStore {
  Future<List<Map<String, dynamic>>> load();
  Future<void> put(String id, Map<String, dynamic> record);
  Future<void> remove(String id);
}

class MemoryMeshRouterStore implements MeshRouterStore {
  final records = <String, Map<String, dynamic>>{};
  @override
  Future<List<Map<String, dynamic>>> load() async => records.values.toList();
  @override
  Future<void> put(String id, Map<String, dynamic> record) async {
    records[id] = record;
  }

  @override
  Future<void> remove(String id) async {
    records.remove(id);
  }
}

/// คิวแยกตามบัญชีและ device เพื่อไม่ส่งข้อความข้ามบัญชีเมื่อสลับผู้ใช้
class LocalMeshRouterStore implements MeshRouterStore {
  LocalMeshRouterStore(this.local, this.scope);
  final LocalDatabase local;
  final String scope;
  static final store = stringMapStoreFactory.store('mesh_relay_queue_v1');
  @override
  Future<List<Map<String, dynamic>>> load() async => (await store.find(
    await local.database,
    finder: Finder(filter: Filter.equals('scope', scope)),
  )).map((r) => Map<String, dynamic>.from(r.value['record'] as Map)).toList();
  @override
  Future<void> put(String id, Map<String, dynamic> record) async {
    await store.record('$scope:$id').put(await local.database, {
      'scope': scope,
      'record': record,
    });
  }

  @override
  Future<void> remove(String id) async {
    await store.record('$scope:$id').delete(await local.database);
  }
}
