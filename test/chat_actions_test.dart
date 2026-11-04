import 'package:flutter_test/flutter_test.dart';
import 'package:offgrid_sos/services/chat_action.dart';
import 'package:offgrid_sos/services/unified_chat_service.dart';

ChatItem item(
  String id,
  String text, {
  bool mine = true,
  int time = 0,
  String type = 'text',
}) => ChatItem(
  id: id,
  text: text,
  at: DateTime.utc(2026, 11, 3).add(Duration(seconds: time)),
  mine: mine,
  type: type,
  status: 'pending',
);

void main() {
  test(
    'delete hides the original and its media and cannot be undone by late edits',
    () {
      final raw = [
        item('a', 'video', type: 'video'),
        item('d', ChatAction.delete('a'), time: 2),
        item('late', ChatAction.edit('a', 'restore'), time: 3),
      ];
      final projected = projectChatMessages(raw);
      expect(projected.single.deleted, isTrue);
      expect(projected.single.path, isNull);
      expect(projected.where((m) => !m.deleted), isEmpty);
      final entry = ChatInboxEntry(
        const ChatContact(name: 'B'),
        projected,
        wireMessages: raw,
      );
      expect(entry.transportMessages.any((m) => m.id == 'a'), isFalse);
      expect(ChatAction.preview(ChatAction.delete('a')), 'ลบข้อความแล้ว');
    },
  );
  test('a peer cannot delete a message written by the other author', () {
    final projected = projectChatMessages([
      item('a', 'keep'),
      item('forged', ChatAction.delete('a'), mine: false, time: 1),
    ]);
    expect(projected.single.deleted, isFalse);
    expect(projected.single.text, 'keep');
  });
  test(
    'ordinary text stays backward compatible and reserved text is escaped',
    () {
      expect(ChatAction.message('hello'), 'hello');
      final literal = ChatAction.edit('target', 'not a command');
      final projected = projectChatMessages([
        item('a', ChatAction.message(literal)),
      ]);
      expect(projected.single.text, literal);
      expect(projected.single.edited, isFalse);
    },
  );
  test(
    'reply retains the original ID without copying stale quoted content',
    () {
      final projected = projectChatMessages([
        item('a', 'hello', mine: false),
        item('b', ChatAction.message('answer', replyTo: 'a'), time: 1),
      ]);
      expect(projected.last.text, 'answer');
      expect(projected.last.replyToId, 'a');
    },
  );
  test('out of order edits choose latest and hide control messages', () {
    final projected = projectChatMessages([
      item('last', ChatAction.edit('a', 'latest'), time: 3),
      item('a', 'first'),
      item('early', ChatAction.edit('a', 'older'), time: 1),
    ]);
    expect(projected, hasLength(1));
    expect(projected.single.text, 'latest');
    expect(projected.single.edited, isTrue);
  });
  test('a peer cannot edit or retract the other authors message', () {
    final projected = projectChatMessages([
      item('a', 'private'),
      item('b', ChatAction.edit('a', 'forged'), mine: false, time: 1),
      item('c', ChatAction.retract('a'), mine: false, time: 2),
    ]);
    expect(projected.single.text, 'private');
    expect(projected.single.retracted, isFalse);
  });
  test('retraction is terminal even when later edits arrive', () {
    final projected = projectChatMessages([
      item('a', 'first'),
      item('b', ChatAction.retract('a'), time: 1),
      item('c', ChatAction.edit('a', 'resurrect'), time: 2),
    ]);
    expect(projected.single.retracted, isTrue);
    expect(projected.single.text, 'ยกเลิกข้อความแล้ว');
  });
  test(
    'media retraction removes access in presentation and outbound queue',
    () {
      final raw = [
        item('a', 'video', type: 'video'),
        item('b', ChatAction.retract('a'), time: 1),
      ];
      final entry = ChatInboxEntry(
        const ChatContact(name: 'B'),
        projectChatMessages(raw),
        wireMessages: raw,
      );
      expect(entry.messages.single.type, 'text');
      expect(entry.messages.single.path, isNull);
      expect(entry.transportMessages.map((m) => m.id), ['b']);
    },
  );
  test('caption edits preserve media type and ignore absent targets', () {
    final projected = projectChatMessages([
      item('a', 'video', type: 'video'),
      item('b', ChatAction.edit('a', 'replace'), time: 1),
      item('c', ChatAction.retract('missing'), time: 2),
    ]);
    expect(projected.single.type, 'video');
    expect(projected.single.edited, isTrue);
    expect(projected.single.text, 'replace');
  });
  test(
    'malformed or oversized structured content does not become a command',
    () {
      expect(ChatAction.parse('${ChatAction.prefix}{broken'), isNull);
      expect(
        ChatAction.parse(
          '${ChatAction.prefix}{"kind":"retract","target":3,"text":""}',
        ),
        isNull,
      );
      expect(ChatAction.validWire('a' * 4001), isFalse);
      final text = 'ก' * 4000;
      expect(ChatAction.validWire(ChatAction.edit('id', text)), isTrue);
    },
  );
  test('notification previews never show encoded command payloads', () {
    expect(
      ChatAction.preview(ChatAction.message('hello', replyTo: 'id')),
      'hello',
    );
    expect(
      ChatAction.preview(ChatAction.edit('id', 'secret')),
      'แก้ไขข้อความแล้ว',
    );
    expect(ChatAction.preview(ChatAction.retract('id')), 'ยกเลิกข้อความแล้ว');
  });
}
