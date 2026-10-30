import 'dart:async';
import 'package:sembast/sembast.dart';
import '../data/local/local_database.dart';
import '../models/user.dart';
import 'chat_media_cache.dart';
import 'chat_service.dart';
import 'network_service.dart';

/// Downloads recent cloud attachments sequentially while online. Local D2D,
/// notifications, and text persistence never wait for this optional worker.
class OfflineMediaService {
  static final instance = OfflineMediaService();
  AppUser? _owner;
  Timer? _timer;
  bool _working = false, _rerun = false;
  int _generation = 0;
  final _retryAfter = <String, DateTime>{};

  void start(AppUser user) {
    if (_owner?.id == user.id) return;
    stop();
    if (!user.isMember) return;
    _owner = user;
    NetworkService.instance.online.addListener(wake);
    _timer = Timer.periodic(const Duration(seconds: 60), (_) => wake());
    wake();
  }

  void stop() {
    _generation++;
    _owner = null;
    _timer?.cancel();
    _timer = null;
    _retryAfter.clear();
    NetworkService.instance.online.removeListener(wake);
  }

  void wake() {
    if (_working) {
      _rerun = true;
      return;
    }
    unawaited(_drain());
  }

  Future<void> _drain() async {
    final user = _owner;
    final generation = _generation;
    bool current() =>
        _owner?.id == user?.id &&
        generation == _generation &&
        NetworkService.instance.online.value;
    if (user == null || !current()) return;
    _working = true;
    _rerun = false;
    try {
      final local = LocalDatabase.instance;
      final rows = await local.messageStore.find(
        await local.database,
        finder: Finder(
          filter: Filter.and([
            Filter.equals('owner_local_id', user.id),
            Filter.equals('is_deleted', false),
          ]),
          sortOrders: [SortOrder('created_at', false)],
          limit: 200,
        ),
      );
      var selected = 0;
      for (final row in rows) {
        if (!current()) return;
        final data = row.value;
        final id = data['id'] as String;
        final path = data['media_path'];
        final size = data['media_size'];
        if (path is! String ||
            !['image', 'video'].contains(data['message_type']) ||
            size is! num ||
            size <= 0 ||
            size > 25 * 1024 * 1024) {
          continue;
        }
        if (++selected > 10) break;
        if (_retryAfter[id]?.isAfter(DateTime.now()) ?? false) continue;
        try {
          if (await ChatMediaCache.instance.local(user.id, id) != null) {
            continue;
          }
          if (_retryAfter.length > 200) _retryAfter.clear();
          _retryAfter[id] = DateTime.now().add(const Duration(minutes: 5));
          await ChatMediaCache.instance.resolve(
            user.id,
            id,
            () async => current()
                ? await ChatService.instance.signedMediaUrl(path)
                : null,
          );
        } catch (_) {
          // A missing file, storage quota, or an outage keeps the text usable.
        }
      }
    } catch (_) {
      // The next connectivity event or timer retries opening local data.
    } finally {
      _working = false;
      if (_rerun) {
        _rerun = false;
        wake();
      }
    }
  }
}
