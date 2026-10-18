import 'dart:async';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/user.dart';
import 'app_notifications.dart';
import 'chat_service.dart';

/// Runs independently of the visible chat route on the shared Flutter engine.
class CloudInboxService {
  static final instance = CloudInboxService();
  StreamSubscription<List<Map<String, dynamic>>>? _subscription;
  final _seen = <String>{};
  String? _owner;
  bool _primed = false;
  DateTime _startedAt = DateTime.now().toUtc();
  Future<void> start(AppUser me) async {
    if (!me.isMember || _owner == me.id) return;
    await stop();
    _owner = me.id;
    _startedAt = DateTime.now().toUtc();
    _subscription = Supabase.instance.client
        .from('messages')
        .stream(primaryKey: ['id'])
        .order('created_at', ascending: false)
        .limit(100)
        .listen(
          (rows) async {
            if (_owner != me.id) return;
            for (final row in rows) {
              if (_owner != me.id) return;
              final fresh = _seen.add(row['id'].toString());
              if (!fresh ||
                  (!_primed &&
                      !(DateTime.tryParse(
                            row['created_at']?.toString() ?? '',
                          )?.isAfter(_startedAt) ??
                          false)) ||
                  row['sender_id'] == me.id ||
                  row['is_deleted'] == true) {
                continue;
              }
              await AppNotifications.instance.show(
                id: row['id'].toString(),
                title: 'ข้อความใหม่',
                text: row['content']?.toString() ?? 'มีไฟล์แนบ',
                thread: row['conversation_id']?.toString(),
              );
            }
            _primed = true;
            if (_seen.length > 2000) {
              _seen.clear();
              _seen.addAll(rows.map((r) => r['id'].toString()));
            }
            try {
              if (_owner != me.id) return;
              await ChatService.instance.refreshInbox(me);
            } catch (_) {}
          },
          onError: (_) {
            /* Local history remains usable while Realtime reconnects. */
          },
        );
  }

  Future<void> stop() async {
    _owner = null;
    await _subscription?.cancel();
    _subscription = null;
    _seen.clear();
    _primed = false;
  }
}
