import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sembast/sembast_memory.dart';
import 'package:offgrid_sos/data/local/local_database.dart';
import 'package:offgrid_sos/features/chat/unified_conversation_screen.dart';
import 'package:offgrid_sos/models/user.dart';
import 'package:offgrid_sos/services/location_service.dart';
import 'package:offgrid_sos/services/nearby_mesh_service.dart';
import 'package:offgrid_sos/services/unified_chat_service.dart';
import 'package:offgrid_sos/services/app_notifications.dart';

const me = AppUser(id: 'guest', firstName: 'A', lastName: '', isMember: false);
const contact = ChatContact(name: 'B', device: 'b');

class MenuChat extends UnifiedChatService {
  MenuChat(
    LocalDatabase db,
    NearbyMeshService radio, {
    bool connected = false,
    this.type = 'text',
    this.mine = true,
  }) : super(local: db, mesh: radio, online: () => connected);
  String? reply, edited, recalled, deleted;
  final String type;
  final bool mine;
  @override
  Future<void> deleteMessage(AppUser me, ChatContact contact, String id) async {
    deleted = id;
  }

  @override
  void start(AppUser me) {}
  @override
  Future<void> rememberPeers(String owner) async {}
  @override
  Stream<List<ChatInboxEntry>> watchInbox(String owner) => Stream.value([
    ChatInboxEntry(contact, [
      ChatItem(
        id: 'one',
        at: DateTime(2026),
        mine: mine,
        type: type,
        text: 'hello',
        status: 'delivered',
      ),
    ]),
  ]);
  @override
  Future<void> send(
    AppUser me,
    ChatContact requested, {
    String text = '',
    SavedLocation? location,
    String? path,
    String? name,
    String type = 'text',
    String? messageId,
    String? caseId,
    String? replyToId,
  }) async {
    reply = replyToId;
  }

  @override
  Future<void> changeMessage(
    AppUser me,
    ChatContact requested,
    String id, {
    String? text,
    bool retract = false,
  }) async {
    if (retract) {
      recalled = id;
    } else {
      edited = text;
    }
  }
}

void main() {
  testWidgets(
    'disposing the previous chat cannot clear the new notification target',
    (tester) async {
      final db = await newDatabaseFactoryMemory().openDatabase(
        'notification-replacement',
      );
      final local = LocalDatabase.withDatabase(db);
      final mesh = NearbyMeshService.withDatabase(local);
      final service = MenuChat(local, mesh);
      await tester.pumpWidget(
        MaterialApp(
          home: UnifiedConversationScreen(
            me: me,
            contact: contact,
            service: service,
          ),
        ),
      );
      await tester.pumpAndSettle();
      final navigator = Navigator.of(
        tester.element(find.byType(UnifiedConversationScreen)),
      );
      navigator.pushReplacement(
        MaterialPageRoute<void>(
          builder: (_) => UnifiedConversationScreen(
            me: me,
            contact: const ChatContact(name: 'C', device: 'c'),
            service: service,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(AppNotifications.instance.activeThread, 'c');
      await tester.pumpWidget(const SizedBox());
      expect(AppNotifications.instance.activeThread, isNull);
      mesh.dispose();
      await db.close();
    },
  );
  for (final online in [false, true]) {
    testWidgets(
      'video menu has exactly four actions and edits its caption online=$online',
      (tester) async {
        final db = await newDatabaseFactoryMemory().openDatabase(
          'video-menu-$online',
        );
        final local = LocalDatabase.withDatabase(db);
        final mesh = NearbyMeshService.withDatabase(local);
        final service = MenuChat(local, mesh, connected: online, type: 'video');
        await tester.pumpWidget(
          MaterialApp(
            home: UnifiedConversationScreen(
              me: me,
              contact: contact,
              service: service,
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.byIcon(Icons.more_horiz), findsNothing);
        await tester.longPress(
          find.byWidgetPredicate((w) => w is InkWell && w.onLongPress != null),
        );
        await tester.pumpAndSettle();
        final tiles = tester
            .widgetList<ListTile>(
              find.descendant(
                of: find.byType(BottomSheet),
                matching: find.byType(ListTile),
              ),
            )
            .toList();
        expect(tiles.map((t) => (t.title as Text).data), [
          'ยกเลิกส่งข้อความ',
          'ลบข้อความ',
          'แก้ไขข้อความ',
          'ตอบกลับ',
        ]);
        expect(tiles.every((t) => t.enabled), isTrue);
        await tester.tap(find.text('แก้ไขข้อความ'));
        await tester.pumpAndSettle();
        await tester.enterText(
          find.descendant(
            of: find.byType(AlertDialog),
            matching: find.byType(TextField),
          ),
          'คำบรรยายใหม่',
        );
        await tester.tap(find.text('บันทึก'));
        await tester.pumpAndSettle();
        expect(service.edited, 'คำบรรยายใหม่');
        await tester.pumpWidget(const SizedBox());
        mesh.dispose();
        await db.close();
      },
    );
  }
  testWidgets(
    'received messages offer reply but cannot mutate the sender message',
    (tester) async {
      final db = await newDatabaseFactoryMemory().openDatabase('received-menu');
      final local = LocalDatabase.withDatabase(db);
      final mesh = NearbyMeshService.withDatabase(local);
      final service = MenuChat(local, mesh, mine: false);
      await tester.pumpWidget(
        MaterialApp(
          home: UnifiedConversationScreen(
            me: me,
            contact: contact,
            service: service,
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.longPress(
        find.byWidgetPredicate((w) => w is InkWell && w.onLongPress != null),
      );
      await tester.pumpAndSettle();
      final tiles = tester
          .widgetList<ListTile>(
            find.descendant(
              of: find.byType(BottomSheet),
              matching: find.byType(ListTile),
            ),
          )
          .toList();
      expect(tiles.map((t) => t.enabled), [false, false, false, true]);
      expect(find.text('คัดลอก'), findsNothing);
      await tester.pumpWidget(const SizedBox());
      mesh.dispose();
      await db.close();
    },
  );
  testWidgets(
    'Internet label ignores missing cloud binding and menu requests global delete',
    (tester) async {
      final db = await newDatabaseFactoryMemory().openDatabase('online-ui');
      final local = LocalDatabase.withDatabase(db);
      final mesh = NearbyMeshService.withDatabase(local);
      final service = MenuChat(local, mesh, connected: true);
      await tester.pumpWidget(
        MaterialApp(
          home: UnifiedConversationScreen(
            me: me,
            contact: contact,
            service: service,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('ออนไลน์'), findsOneWidget);
      await tester.longPress(
        find.byWidgetPredicate((w) => w is InkWell && w.onLongPress != null),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('ลบข้อความ'));
      await tester.pumpAndSettle();
      expect(service.deleted, isNull);
      await tester.tap(find.text('ลบข้อความ'));
      await tester.pumpAndSettle();
      expect(service.deleted, 'one');
      await tester.pumpWidget(const SizedBox());
      mesh.dispose();
      await db.close();
    },
  );
  testWidgets('long press reply has a cancellable quote and sends its ID', (
    tester,
  ) async {
    final db = await newDatabaseFactoryMemory().openDatabase('reply-ui');
    final local = LocalDatabase.withDatabase(db);
    final mesh = NearbyMeshService.withDatabase(local);
    final service = MenuChat(local, mesh);
    await tester.pumpWidget(
      MaterialApp(
        home: UnifiedConversationScreen(
          me: me,
          contact: contact,
          service: service,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.longPress(find.text('hello'));
    await tester.pumpAndSettle();
    expect(find.text('แก้ไขข้อความ'), findsOneWidget);
    expect(find.text('ยกเลิกส่งข้อความ'), findsOneWidget);
    expect(find.text('คัดลอก'), findsNothing);
    expect(
      find.descendant(
        of: find.byType(BottomSheet),
        matching: find.byType(ListTile),
      ),
      findsNWidgets(4),
    );
    await tester.tap(find.text('ตอบกลับ'));
    await tester.pumpAndSettle();
    expect(find.byTooltip('ยกเลิกการตอบกลับ'), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'answer');
    await tester.tap(find.byTooltip('ส่งข้อความ'));
    await tester.pumpAndSettle();
    expect(service.reply, 'one');
    expect(find.byTooltip('ยกเลิกการตอบกลับ'), findsNothing);
    await tester.pumpWidget(const SizedBox());
    mesh.dispose();
    await db.close();
  });

  testWidgets('edit saves text and retract requires confirmation', (
    tester,
  ) async {
    final db = await newDatabaseFactoryMemory().openDatabase('edit-ui');
    final local = LocalDatabase.withDatabase(db);
    final mesh = NearbyMeshService.withDatabase(local);
    final service = MenuChat(local, mesh);
    await tester.pumpWidget(
      MaterialApp(
        home: UnifiedConversationScreen(
          me: me,
          contact: contact,
          service: service,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.longPress(find.text('hello'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('แก้ไขข้อความ'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.byType(TextField),
      ),
      'updated',
    );
    await tester.tap(find.text('บันทึก'));
    await tester.pumpAndSettle();
    expect(service.edited, 'updated');
    expect(tester.takeException(), isNull);
    await tester.longPress(find.text('hello'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('ยกเลิกส่งข้อความ'));
    await tester.pumpAndSettle();
    expect(service.recalled, isNull);
    await tester.tap(find.text('ยกเลิกส่ง'));
    await tester.pumpAndSettle();
    expect(service.recalled, 'one');
    await tester.pumpWidget(const SizedBox());
    mesh.dispose();
    await db.close();
  });
}
