import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:sembast/sembast_memory.dart';
import 'package:offgrid_sos/data/local/local_database.dart';
import 'package:offgrid_sos/services/nearby_mesh_service.dart';
import 'package:offgrid_sos/services/unified_chat_service.dart';

class CountingInbox extends UnifiedChatService {
  CountingInbox(LocalDatabase db, NearbyMeshService radio)
    : super(local: db, mesh: radio, online: () => false);
  int reads = 0;
  @override
  Future<List<ChatInboxEntry>> inbox(String owner) {
    reads++;
    return super.inbox(owner);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('home and chat share each DB snapshot and release it on exit', () async {
    final db = await newDatabaseFactoryMemory().openDatabase('shared-inbox');
    final local = LocalDatabase.withDatabase(db);
    final mesh = NearbyMeshService.withDatabase(local);
    final chat = CountingInbox(local, mesh);
    final homeValues = <List<ChatInboxEntry>>[];
    final chatValues = <List<ChatInboxEntry>>[];
    final first = chat.watchInbox('a').listen(homeValues.add);
    // Let Sembast's initial snapshots and the debounce settle.
    await Future<void>.delayed(const Duration(milliseconds: 150));
    final before = chat.reads;
    final second = chat.watchInbox('a').listen(chatValues.add);
    await Future<void>.delayed(Duration.zero);
    expect(chat.reads, before);
    expect(identical(homeValues.last, chatValues.last), isTrue);
    final updated = Completer<void>();
    final third = chat.watchInbox('a').listen((entries) {
      if (entries.any((e) => e.contact.device == 'b') && !updated.isCompleted) {
        updated.complete();
      }
    });
    await UnifiedChatService.contacts.record('a:b').put(db, {
      'owner': 'a',
      'device': 'b',
      'name': 'B',
      'verified': false,
    });
    await updated.future.timeout(const Duration(seconds: 3));
    expect(chat.reads, before + 1);
    expect(identical(homeValues.last, chatValues.last), isTrue);
    await first.cancel();
    await second.cancel();
    await third.cancel();
    await Future<void>.delayed(const Duration(milliseconds: 100));
    final afterExit = chat.reads;
    await UnifiedChatService.contacts.record('a:c').put(db, {
      'owner': 'a',
      'device': 'c',
      'name': 'C',
      'verified': false,
    });
    await Future<void>.delayed(const Duration(milliseconds: 100));
    expect(chat.reads, afterExit);
    final fresh = await chat.watchInbox('a').first;
    expect(fresh.map((e) => e.contact.device), containsAll(['b', 'c']));
    mesh.dispose();
    await db.close();
  });
}
