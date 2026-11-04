import 'package:flutter_test/flutter_test.dart';
import 'package:sembast/sembast_memory.dart';
import 'package:offgrid_sos/data/local/local_database.dart';
import 'package:offgrid_sos/services/nearby_mesh_service.dart';

void main() {
  test(
    'transport labels reflect connected endpoints without guessing Nearby radio',
    () async {
      final db = await newDatabaseFactoryMemory().openDatabase(
        'transport-label',
      );
      final mesh = NearbyMeshService.withDatabase(
        LocalDatabase.withDatabase(db),
      );
      expect(mesh.connectionLabel, 'ยังไม่เชื่อมต่อ');
      mesh.connected.add('bt:phone');
      expect(mesh.connectionLabel, 'Bluetooth โดยตรง');
      mesh.connected.add('nearby-endpoint');
      expect(mesh.connectionLabel, 'Bluetooth โดยตรง + Nearby');
      mesh.connected.remove('bt:phone');
      expect(mesh.connectionLabel, 'Nearby Connections');
      mesh.dispose();
      await db.close();
    },
  );
}
