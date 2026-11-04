import 'package:flutter_test/flutter_test.dart';
import 'package:sembast/sembast_memory.dart';
import 'package:offgrid_sos/data/local/local_database.dart';
import 'package:offgrid_sos/data/repositories/sos_response_repository.dart';

Map<String, dynamic> frame(
  String id,
  int sequence, {
  String state = 'received',
  String category = 'receipt',
}) => {
  'id': id,
  'origin': 'responder',
  'sender': 'R',
  'data': {
    'caseId': 'case',
    'caseOrigin': 'victim',
    'target': 'victim',
    'revision': 1,
    'sequence': sequence,
    'category': category,
    'state': state,
  },
};
void main() {
  test(
    'receipt queue survives service recreation, ACK binds peer, and owner cleanup removes it',
    () async {
      final db = await newDatabaseFactoryMemory().openDatabase('responses');
      final local = LocalDatabase.withDatabase(db);
      final repo = SosResponseRepository(local);
      final one = await repo.queue('owner', frame('first', 1));
      final repeated = await repo.queue('owner', frame('duplicate', 1));
      expect(repeated['id'], one['id']);
      final reopened = SosResponseRepository(local);
      expect(await reopened.pending('other-owner', 'victim'), isEmpty);
      expect(await reopened.pending('owner', 'victim'), hasLength(1));
      await reopened.acknowledge('owner', 'first', 'imposter');
      expect(await reopened.pending('owner', 'victim'), hasLength(1));
      await reopened.acknowledge('owner', 'first', 'victim');
      expect(await reopened.pending('owner', 'victim'), isEmpty);
      await local.clearOwnerData('owner');
      expect(await reopened.watch('owner', 'victim', 'case').first, isEmpty);
      await db.close();
    },
  );
  test(
    'replayed older progress never overwrites latest and stopped case cancels pending responses',
    () async {
      final db = await newDatabaseFactoryMemory().openDatabase(
        'response-order',
      );
      final repo = SosResponseRepository(LocalDatabase.withDatabase(db));
      expect(
        await repo.receive(
          'victim',
          frame('second', 2, category: 'progress', state: 'helping'),
        ),
        isTrue,
      );
      expect(
        await repo.receive(
          'victim',
          frame('first', 1, category: 'progress', state: 'accepted'),
        ),
        isFalse,
      );
      expect(
        await repo.receive(
          'victim',
          frame('second', 2, category: 'progress', state: 'helping'),
        ),
        isFalse,
      );
      final rows = await repo.watch('victim', 'victim', 'case').first;
      expect(
        ((rows.single['envelope'] as Map)['data'] as Map)['state'],
        'helping',
      );
      await repo.queue('rescue-owner', frame('receipt', 1));
      await repo.cancelForCase('rescue-owner', 'victim', 'case');
      expect(await repo.pending('rescue-owner', 'victim'), isEmpty);
      await db.close();
    },
  );
}
