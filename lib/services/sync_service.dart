import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../data/models/sync_job.dart';
import '../data/local/local_database.dart';
import '../data/repositories/message_repository.dart';
import '../data/repositories/sos_repository.dart';
import '../data/repositories/sync_queue_repository.dart';
import 'network_service.dart';
import 'chat_media_cache.dart';
import 'nearby_media_files.dart';
import '../data/repositories/nearby_chat_repository.dart';

enum SyncActivity { idle, offline, syncing, success, error }

class SyncSnapshot {
  const SyncSnapshot({
    required this.activity,
    required this.pendingCount,
    this.lastMessage,
    this.lastSyncedAt,
  });

  final SyncActivity activity;
  final int pendingCount;
  final String? lastMessage;
  final DateTime? lastSyncedAt;

  bool get isBusy => activity == SyncActivity.syncing;
}

class SyncService {
  SyncService({
    LocalDatabase? local,
    NearbyMediaFiles? nearbyFiles,
    this.client,
    Future<bool> Function()? hasConnection,
    Stream<bool>? connectionChanges,
    this.retryInterval = const Duration(seconds: 5),
    Future<void> Function(String, String, List<int>)? preserveMedia,
  }) : _nearby = NearbyChatRepository(local: local),
       _nearbyFiles = nearbyFiles ?? NearbyMediaFiles(),
       _preserveMedia = preserveMedia ?? ChatMediaCache.instance.put,
       _queue = SyncQueueRepository(local: local),
       _sos = SosRepository(local: local),
       _messages = MessageRepository(local: local),
       _hasConnection =
           hasConnection ?? (() => NetworkService.instance.hasConnection),
       _connectionChanges =
           connectionChanges ?? NetworkService.instance.connectionChanges;

  static final SyncService instance = SyncService();

  final NearbyChatRepository _nearby;
  final NearbyMediaFiles _nearbyFiles;
  final SyncQueueRepository _queue;
  final SosRepository _sos;
  final MessageRepository _messages;
  final SupabaseClient? client;
  final Future<bool> Function() _hasConnection;
  final Stream<bool> _connectionChanges;
  final Duration retryInterval;
  final Future<void> Function(String, String, List<int>) _preserveMedia;

  final ValueNotifier<SyncSnapshot> status = ValueNotifier<SyncSnapshot>(
    const SyncSnapshot(activity: SyncActivity.idle, pendingCount: 0),
  );

  StreamSubscription<bool>? _connectivitySubscription;
  Timer? _retryTimer;
  Completer<void>? _activeSync;
  Future<void>? _stopOperation;
  Future<int>? _activeRestore;
  bool _started = false;
  bool _stopping = false;
  DateTime _archiveRetryAt = DateTime.fromMillisecondsSinceEpoch(0);
  int _archiveFailures = 0;

  SupabaseClient get _supabase => client ?? Supabase.instance.client;

  Future<void> start() async {
    await _stopOperation;
    if (_started) {
      await syncNow();
      return;
    }
    _started = true;

    _connectivitySubscription = _connectionChanges.listen((online) {
      if (online) {
        unawaited(_automaticSync());
      } else {
        unawaited(
          _safeOfflineStatus(
            activity: SyncActivity.offline,
            message: 'ออฟไลน์ • ข้อมูลจะอยู่ในเครื่อง',
          ),
        );
      }
    });

    // Retry deadlines are checked even when the connection type never changes.
    _retryTimer = Timer.periodic(retryInterval, (_) {
      unawaited(_automaticSync());
    });

    final online = await _hasConnection();
    if (!_started || _stopping) return;

    if (!online) {
      await _refreshStatus(
        activity: SyncActivity.offline,
        message: 'ออฟไลน์ • Local DB พร้อมใช้งาน',
      );
      return;
    }

    await syncNow();
  }

  Future<void> stop() {
    return _stopOperation ??= _stop().whenComplete(() => _stopOperation = null);
  }

  Future<void> _stop() async {
    _stopping = true;
    _started = false;
    _retryTimer?.cancel();
    _retryTimer = null;
    final subscription = _connectivitySubscription;
    _connectivitySubscription = null;
    await subscription?.cancel();
    await _activeSync?.future;
    try {
      await _activeRestore;
    } catch (_) {}
    _stopping = false;
    _archiveRetryAt = DateTime.fromMillisecondsSinceEpoch(0);
    _archiveFailures = 0;
    status.value = const SyncSnapshot(
      activity: SyncActivity.idle,
      pendingCount: 0,
    );
  }

  Future<void> _automaticSync() async {
    if (!_started || _stopping) return;
    try {
      final userId = _supabase.auth.currentUser?.id;
      if (userId == null) return;
      if (await _queue.countFor(userId) == 0 &&
          (DateTime.now().isBefore(_archiveRetryAt) ||
              await _nearby.unsyncedCount(userId) == 0)) {
        return;
      }
      if (_started && !_stopping) await syncNow();
    } catch (e) {
      if (_started && !_stopping) {
        status.value = SyncSnapshot(
          activity: SyncActivity.error,
          pendingCount: status.value.pendingCount,
          lastMessage: 'ซิงก์ไม่สำเร็จ • จะลองใหม่อัตโนมัติ: $e',
          lastSyncedAt: status.value.lastSyncedAt,
        );
      }
    }
  }

  Future<void> _safeOfflineStatus({
    required SyncActivity activity,
    String? message,
  }) async {
    try {
      await _refreshStatus(activity: activity, message: message);
    } catch (_) {
      // The next scheduled attempt can retry opening the local database.
    }
  }

  Future<void> syncNow() async {
    if (_stopping) return;
    if (_activeSync != null) {
      await _activeSync!.future;
      return;
    }
    // Take the lock before the first await, including connectivity checks.
    final completion = Completer<void>();
    _activeSync = completion;
    try {
      await _runSync();
    } finally {
      _activeSync = null;
      completion.complete();
    }
  }

  Future<void> _runSync() async {
    final authUser = _supabase.auth.currentUser;

    if (authUser == null) {
      await _refreshStatus(
        activity: SyncActivity.idle,
        message: 'Guest • เก็บข้อมูลไว้ในเครื่อง',
      );
      return;
    }

    final online = await _hasConnection();

    if (!online) {
      await _refreshStatus(
        activity: SyncActivity.offline,
        message: 'ออฟไลน์ • รอซิงก์เมื่อกลับมาออนไลน์',
      );
      return;
    }

    await _refreshStatus(
      activity: SyncActivity.syncing,
      message: 'กำลังซิงก์...',
    );

    var success = 0;
    var failures = 0;

    final jobs = await _queue.readyJobs(authUser.id);

    for (final job in jobs) {
      if (_stopping || _supabase.auth.currentUser?.id != authUser.id) break;
      try {
        await _process(job, authUser.id);

        if (await _queue.complete(job)) {
          success++;
        }
      } catch (e) {
        await _queue.fail(job, e);
        failures++;
      }
    }

    if (_stopping) return;
    final archiveRows = DateTime.now().isBefore(_archiveRetryAt)
        ? <Map<String, Object?>>[]
        : await _nearby.unsynced(authUser.id);
    var archiveFailed = false;
    if (archiveRows.isNotEmpty) {
      try {
        // Check migration/RLS before uploading any attachment bytes.
        await _supabase
            .from('nearby_archive')
            .select('message_id')
            .eq('owner_id', authUser.id)
            .limit(1);
      } catch (_) {
        archiveFailed = true;
        failures++;
      }
    }
    for (final row in archiveFailed ? <Map<String, Object?>>[] : archiveRows) {
      try {
        _requireSession(authUser.id);
        final env = Map<String, dynamic>.from(row['envelope'] as Map);
        String? path = row['archiveMediaPath'] as String?;
        final localPath = row['localPath'];
        if (env['kind'] == 'media' && path == null) {
          if (localPath is! String || !await _nearbyFiles.exists(localPath)) {
            throw StateError('Missing local attachment');
          }
          path = '${authUser.id}/${env['id']}';
          await _supabase.storage
              .from('nearby-archive')
              .uploadBinary(
                path,
                await _nearbyFiles.allBytes(localPath),
                fileOptions: const FileOptions(upsert: true),
              );
          _requireSession(authUser.id);
          await _nearby.archiveMediaUploaded(authUser.id, env['id'], path);
        }
        _requireSession(authUser.id);
        await _supabase.from('nearby_archive').upsert({
          'owner_id': authUser.id,
          'message_id': env['id'],
          'peer': row['peer'],
          'incoming': row['incoming'],
          'delivery': row['delivery'],
          'envelope': env,
          'revision': row['revision'],
          'media_path': path,
        }, onConflict: 'owner_id,message_id');
        await _nearby.archived(authUser.id, env['id'], row['revision']);
        success++;
      } catch (_) {
        archiveFailed = true;
        failures++;
      }
    }
    if (archiveFailed) {
      _archiveFailures++;
      final delay = [5, 15, 30, 60, 300][(_archiveFailures - 1).clamp(0, 4)];
      _archiveRetryAt = DateTime.now().add(Duration(seconds: delay));
    } else if (archiveRows.isNotEmpty) {
      _archiveFailures = 0;
    }
    if (_stopping) return;
    final pending =
        await _queue.countFor(authUser.id) +
        await _nearby.unsyncedCount(authUser.id);
    if (failures > 0) {
      await _refreshStatus(
        activity: SyncActivity.error,
        message: 'ซิงก์บางรายการไม่สำเร็จ • จะลองใหม่อัตโนมัติ',
      );
    } else {
      await _refreshStatus(
        activity: pending > 0 ? SyncActivity.idle : SyncActivity.success,
        message: pending > 0
            ? 'รอซิงก์ $pending รายการ • จะลองใหม่อัตโนมัติ'
            : success == 0
            ? 'ข้อมูล Local/Cloud เป็นปัจจุบัน'
            : 'ซิงก์สำเร็จ $success รายการ',
        lastSyncedAt: DateTime.now(),
      );
    }
  }

  /// Explicit restore: never replaces an unsent local record. Called from account settings.
  Future<int> restoreNearbyArchive() {
    if (_stopping) return Future.error(StateError('Session ending'));
    return _activeRestore ??= _restoreArchive().whenComplete(() {
      _activeRestore = null;
    });
  }

  Future<int> _restoreArchive() async {
    final owner = _supabase.auth.currentUser?.id;
    if (owner == null || !await _hasConnection()) {
      throw StateError('กรุณาออนไลน์และเข้าสู่ระบบ');
    }
    var count = 0, offset = 0;
    while (true) {
      _requireSession(owner);
      final rows = await _supabase
          .from('nearby_archive')
          .select()
          .eq('owner_id', owner)
          .order('message_id')
          .range(offset, offset + 99);
      for (final row in rows) {
        _requireSession(owner);
        final id = row['message_id'].toString();
        if (await _nearby.find(owner, id) != null) continue;
        String? localPath;
        if (row['media_path'] is String) {
          final bytes = await _supabase.storage
              .from('nearby-archive')
              .download(row['media_path']);
          _requireSession(owner);
          localPath = await _nearbyFiles.restore(
            owner,
            id,
            bytes,
            (row['envelope']['data']['type']).toString(),
          );
        }
        _requireSession(owner);
        await _nearby.restoreArchive(owner, row, localPath: localPath);
        count++;
      }
      if (rows.length < 100) return count;
      offset += rows.length;
    }
  }

  Future<void> retryAll() async {
    _archiveRetryAt = DateTime.fromMillisecondsSinceEpoch(0);
    _archiveFailures = 0;
    final userId = _supabase.auth.currentUser?.id;

    if (userId != null) {
      await _queue.retryEverythingNow(userId);
    }

    await syncNow();
  }

  Future<void> _process(SyncJob job, String currentUserId) async {
    switch (job.entityType) {
      case 'sos':
        await _syncSos(job, currentUserId);
        return;

      case 'message':
        await _syncMessage(job, currentUserId);
        return;

      default:
        throw StateError('Unknown sync entity: ${job.entityType}');
    }
  }

  Future<void> _syncSos(SyncJob job, String currentUserId) async {
    final record = await _sos.findById(job.entityId);

    if (record == null) {
      return;
    }

    if (record.ownerUserId == null) {
      return;
    }

    if (record.ownerUserId != currentUserId) {
      throw StateError('SOS owner does not match current user.');
    }

    _requireSession(currentUserId);

    await _supabase
        .from('sos_events')
        .upsert(record.toSupabaseMap(), onConflict: 'id');
  }

  Future<void> _syncMessage(SyncJob job, String currentUserId) async {
    final record = await _messages.findById(job.entityId);

    if (record == null) {
      return;
    }

    if (record.senderUserId == null) {
      return;
    }

    if (record.senderUserId != currentUserId) {
      throw StateError('Message sender does not match current user.');
    }

    _requireSession(currentUserId);

    if (job.operation == 'delete' || record.isDeleted) {
      await _supabase.from('messages').delete().eq('id', record.id);
      final mediaPath = record.mediaPath;
      if (mediaPath != null && mediaPath.isNotEmpty) {
        try {
          await _supabase.storage.from('chat-media').remove([mediaPath]);
        } catch (_) {
          // Message deletion is authoritative; orphan cleanup can retry later.
        }
      }
      return;
    }

    var uploadRecord = record;
    final pendingBytes = record.mediaBytes;
    if (pendingBytes != null &&
        pendingBytes.isNotEmpty &&
        record.mediaPath == null) {
      final safeName = (record.mediaName ?? 'attachment').replaceAll(
        RegExp(r'[^a-zA-Z0-9._-]'),
        '_',
      );
      // Keep the original before upload clears media_bytes from local DB.
      await _preserveMedia(record.ownerLocalId, record.id, pendingBytes);
      final path =
          '$currentUserId/${record.conversationId}/${record.id}/$safeName';

      await _supabase.storage
          .from('chat-media')
          .uploadBinary(
            path,
            Uint8List.fromList(pendingBytes),
            fileOptions: FileOptions(
              upsert: true,
              contentType: record.mediaMime ?? 'application/octet-stream',
              cacheControl: '3600',
            ),
          );

      await _messages.attachUploadedMedia(id: record.id, mediaPath: path);
      uploadRecord = record.copyWith(mediaPath: path, clearMediaBytes: true);
    }

    _requireSession(currentUserId);
    await _supabase
        .from('messages')
        .upsert(uploadRecord.toSupabaseMap(), onConflict: 'id');
  }

  void _requireSession(String userId) {
    if (_stopping || _supabase.auth.currentUser?.id != userId) {
      throw StateError('Sync session ended.');
    }
  }

  Future<void> _refreshStatus({
    required SyncActivity activity,
    String? message,
    DateTime? lastSyncedAt,
  }) async {
    final authUserId = _supabase.auth.currentUser?.id;
    final pending = authUserId == null
        ? 0
        : await _queue.countFor(authUserId) +
              await _nearby.unsyncedCount(authUserId);

    status.value = SyncSnapshot(
      activity: activity,
      pendingCount: pending,
      lastMessage: message,
      lastSyncedAt: lastSyncedAt ?? status.value.lastSyncedAt,
    );
  }
}
