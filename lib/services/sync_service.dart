import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../data/models/sync_job.dart';
import '../data/repositories/message_repository.dart';
import '../data/repositories/sos_repository.dart';
import '../data/repositories/sync_queue_repository.dart';
import 'network_service.dart';

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
  SyncService._();

  static final SyncService instance = SyncService._();

  final SyncQueueRepository _queue = SyncQueueRepository();
  final SosRepository _sos = SosRepository();
  final MessageRepository _messages = MessageRepository();

  final ValueNotifier<SyncSnapshot> status = ValueNotifier<SyncSnapshot>(
    const SyncSnapshot(activity: SyncActivity.idle, pendingCount: 0),
  );

  StreamSubscription<bool>? _connectivitySubscription;
  bool _started = false;
  bool _syncing = false;

  SupabaseClient get _supabase => Supabase.instance.client;

  Future<void> start() async {
    if (_started) {
      await syncNow();
      return;
    }
    _started = true;

    _connectivitySubscription = NetworkService.instance.connectionChanges
        .listen((online) {
          if (online) {
            unawaited(syncNow());
          } else {
            unawaited(
              _refreshStatus(
                activity: SyncActivity.offline,
                message: 'ออฟไลน์ • ข้อมูลจะอยู่ในเครื่อง',
              ),
            );
          }
        });

    final online = await NetworkService.instance.hasConnection;

    if (!online) {
      await _refreshStatus(
        activity: SyncActivity.offline,
        message: 'ออฟไลน์ • Local DB พร้อมใช้งาน',
      );
      return;
    }

    await syncNow();
  }

  Future<void> stop() async {
    await _connectivitySubscription?.cancel();
    _connectivitySubscription = null;
    _started = false;
  }

  Future<void> syncNow() async {
    if (_syncing) return;

    final authUser = _supabase.auth.currentUser;

    if (authUser == null) {
      await _refreshStatus(
        activity: SyncActivity.idle,
        message: 'Guest • เก็บข้อมูลไว้ในเครื่อง',
      );
      return;
    }

    final online = await NetworkService.instance.hasConnection;

    if (!online) {
      await _refreshStatus(
        activity: SyncActivity.offline,
        message: 'ออฟไลน์ • รอซิงก์เมื่อกลับมาออนไลน์',
      );
      return;
    }

    _syncing = true;

    await _refreshStatus(
      activity: SyncActivity.syncing,
      message: 'กำลังซิงก์...',
    );

    var success = 0;
    var failures = 0;

    try {
      final jobs = await _queue.readyJobs(authUser.id);

      for (final job in jobs) {
        try {
          await _process(job, authUser.id);

          if (job.id != null) {
            await _queue.complete(job.id!);
          }

          success++;
        } catch (e) {
          await _queue.fail(job, e);
          await _markEntityError(job, e);
          failures++;
        }
      }

      if (failures > 0) {
        await _refreshStatus(
          activity: SyncActivity.error,
          message: 'ซิงก์บางรายการไม่สำเร็จ • กด Retry ได้',
        );
      } else {
        await _refreshStatus(
          activity: SyncActivity.success,
          message: success == 0
              ? 'ข้อมูล Local/Cloud เป็นปัจจุบัน'
              : 'ซิงก์สำเร็จ $success รายการ',
          lastSyncedAt: DateTime.now(),
        );
      }
    } finally {
      _syncing = false;
    }
  }

  Future<void> retryAll() async {
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

    await _supabase
        .from('sos_events')
        .upsert(record.toSupabaseMap(), onConflict: 'id');

    await _sos.markSynced(record.id);
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

    await _ensureDemoConversation(conversationId: record.conversationId);

    if (job.operation == 'delete' || record.isDeleted) {
      await _supabase.from('messages').delete().eq('id', record.id);

      await _messages.markSynced(record.id);
      return;
    }

    await _supabase
        .from('messages')
        .upsert(record.toSupabaseMap(), onConflict: 'id');

    await _messages.markSynced(record.id);
  }

  Future<void> _ensureDemoConversation({required String conversationId}) async {
    await _supabase.rpc(
      'ensure_week3_conversation',
      params: <String, dynamic>{'p_conversation_id': conversationId},
    );
  }

  Future<void> _markEntityError(SyncJob job, Object error) async {
    switch (job.entityType) {
      case 'sos':
        await _sos.markError(job.entityId, error);
        return;

      case 'message':
        await _messages.markError(job.entityId, error);
        return;
    }
  }

  Future<void> _refreshStatus({
    required SyncActivity activity,
    String? message,
    DateTime? lastSyncedAt,
  }) async {
    final authUserId = _supabase.auth.currentUser?.id;
    final pending = authUserId == null ? 0 : await _queue.countFor(authUserId);

    status.value = SyncSnapshot(
      activity: activity,
      pendingCount: pending,
      lastMessage: message,
      lastSyncedAt: lastSyncedAt ?? status.value.lastSyncedAt,
    );
  }
}
