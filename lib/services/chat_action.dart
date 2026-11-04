import 'dart:convert';

/// Versioned chat content travels through the existing authenticated, durable
/// text transport on radio and cloud, without a separate unreliable channel.
class ChatAction {
  const ChatAction(this.kind, this.target, this.text);
  final String kind, target, text;
  static const prefix = '\u2063OFFGRID_CHAT_V1:';
  static const maxWireLength = 16000;

  static String message(String text, {String? replyTo}) =>
      replyTo == null && !text.startsWith(prefix)
      ? text
      : _encode('message', replyTo ?? '', text);
  static String edit(String target, String text) =>
      _encode('edit', target, text);
  static String retract(String target) => _encode('retract', target, '');
  static String delete(String target) => _encode('delete', target, '');
  static String _encode(String kind, String target, String text) =>
      '$prefix${jsonEncode({'kind': kind, 'target': target, 'text': text})}';

  static ChatAction? parse(String wire) {
    if (!wire.startsWith(prefix) || wire.length > maxWireLength) return null;
    try {
      final body = jsonDecode(wire.substring(prefix.length));
      if (body is! Map ||
          !['message', 'edit', 'retract', 'delete'].contains(body['kind']) ||
          body['target'] is! String ||
          (body['target'] as String).length > 200 ||
          body['text'] is! String ||
          (body['text'] as String).length > 4000) {
        return null;
      }
      final action = ChatAction(body['kind'], body['target'], body['text']);
      if (action.kind != 'message' && action.target.isEmpty) return null;
      if (action.kind != 'retract' &&
          action.kind != 'delete' &&
          action.text.trim().isEmpty) {
        return null;
      }
      return action;
    } catch (_) {
      return null;
    }
  }

  static bool validWire(String text) =>
      text.length <= 4000 || parse(text) != null;
  static String preview(String wire) {
    final action = parse(wire);
    return switch (action?.kind) {
      'edit' => 'แก้ไขข้อความแล้ว',
      'retract' => 'ยกเลิกข้อความแล้ว',
      'delete' => 'ลบข้อความแล้ว',
      'message' => action!.text,
      _ => wire,
    };
  }
}
