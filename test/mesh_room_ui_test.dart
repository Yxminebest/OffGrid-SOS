import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sembast/sembast_memory.dart';
import 'package:offgrid_sos/app/theme.dart';
import 'package:offgrid_sos/data/local/local_database.dart';
import 'package:offgrid_sos/features/chat/mesh_room_screen.dart';
import 'package:offgrid_sos/models/user.dart';
import 'package:offgrid_sos/services/nearby_mesh_service.dart';

void main() {
  testWidgets(
    'public room persists offline text and exposes four own-message actions',
    (tester) async {
      final db = await newDatabaseFactoryMemory().openDatabase('room-ui');
      final mesh = NearbyMeshService.withDatabase(
        LocalDatabase.withDatabase(db),
      );
      await tester.runAsync(
        () => mesh.initializeForUser(
          const AppUser(
            id: 'a',
            firstName: 'A',
            lastName: 'Tester',
            isMember: true,
          ),
        ),
      );
      await tester.pumpWidget(
        MaterialApp(
          theme: buildTheme(),
          home: MeshRoomScreen(mesh: mesh),
        ),
      );
      await tester.enterText(find.byType(TextField), 'ข่าวทดสอบ');
      await tester.tap(find.byTooltip('ส่งข้อความ'));
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 100));
      });
      await tester.pumpAndSettle();
      expect(find.text('ข่าวทดสอบ'), findsOneWidget);
      expect(await tester.runAsync(() => mesh.room.events('a')), hasLength(1));
      await tester.longPress(find.text('ข่าวทดสอบ'));
      await tester.pumpAndSettle();
      for (final action in [
        'ตอบกลับ',
        'แก้ไขข้อความ',
        'ยกเลิกส่งข้อความ',
        'ลบข้อความ',
      ]) {
        expect(find.text(action), findsOneWidget);
      }
      await tester.pumpWidget(const SizedBox());
      mesh.dispose();
      await db.close();
    },
  );
}
