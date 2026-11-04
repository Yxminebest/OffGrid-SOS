import 'dart:async';
import 'chat_action.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/user.dart';
import 'app_notifications.dart';
import 'chat_service.dart';
import 'offline_media_service.dart';
import 'network_service.dart';
import 'unified_chat_service.dart';

/// Runs independently of the visible chat route on the shared Flutter engine.
class CloudInboxService {
  static final instance = CloudInboxService();
  StreamSubscription<List<Map<String, dynamic>>>? _subscription;
  final _seen = <String>{};
  String? _owner;
  bool _primed = false;
  Timer? _poll;
  AppUser? _me;
  bool _polling = false;

  void wake() {
    final me = _me;
    if (me != null) unawaited(_snapshot(me));
  }

  Future<void> _snapshot(AppUser me) async {
    if (_polling || _owner != me.id || !NetworkService.instance.online.value) {
      return;
    }
    _polling = true;
    try {
      try {
        await UnifiedChatService.instance.reconcileDeletedContacts(me);
      } catch (_) {
        /* Directory errors must not block incoming messages. */
      }
      if (_owner != me.id) return;
      await ChatService.instance.refreshInbox(me);
      final rows = await Supabase.instance.client
          .from('messages')
          .select()
          .order('created_at', ascending: false)
          .limit(100);
      if (_owner != me.id) return;
      await ChatService.instance.cacheInboxMessages(me, rows);
      OfflineMediaService.instance.wake();
    } catch (_) {
      /* Retry; a failed HTTP request is never a deletion. */
    } finally {
      _polling = false;
    }
  }

  DateTime _startedAt = DateTime.now().toUtc();
  Future<void> start(AppUser me) async {
    if (!me.isMember || _owner == me.id) return;
    await stop();
    _owner = me.id;
    _me = me;
    NetworkService.instance.online.addListener(wake);
    _poll = Timer.periodic(const Duration(seconds: 15), (_) => wake());
    wake();
    _startedAt = DateTime.now().toUtc();
    _subscription = Supabase.instance.client
        .from('messages')
        .stream(primaryKey: ['id'])
        .order('created_at', ascending: false)
        .limit(100)
        .listen(
          (rows) async {
            if (_owner != me.id) return;
            try {
              await ChatService.instance.refreshInbox(me);
              if (_owner != me.id) return;
              await ChatService.instance.cacheInboxMessages(me, rows);
              OfflineMediaService.instance.wake();
            } catch (_) {
              // Realtime may arrive before the inbox RPC on reconnect. Keep
              // notifications working and retry persistence on the next batch.
            }
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
                text: ChatAction.preview(
                  row['content']?.toString() ?? 'มีไฟล์แนบ',
                ),
                thread: row['conversation_id']?.toString(),
                owner: me.id,
                transport: 'cloud',
              );
            }
            _primed = true;
            if (_seen.length > 2000) {
              _seen.clear();
              _seen.addAll(rows.map((r) => r['id'].toString()));
            }
          },
          onError: (_) {
            /* Local history remains usable while Realtime reconnects. */
          },
        );
  }

  Future<void> stop() async {
    _owner = null;
    _me = null;
    _poll?.cancel();
    _poll = null;
    NetworkService.instance.online.removeListener(wake);
    await _subscription?.cancel();
    _subscription = null;
    _seen.clear();
    _primed = false;
  }
}
