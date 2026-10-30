import 'dart:async';
import 'package:flutter/widgets.dart';
import 'package:sembast/sembast.dart';
import '../data/local/local_database.dart';
import '../models/user.dart';
import 'app_notifications.dart';
import 'auth_service.dart';
import 'network_service.dart';

/// Account-scoped verification history and once-per-decision local alerts.
class RescueStatusService extends ChangeNotifier with WidgetsBindingObserver {
  RescueStatusService({
    LocalDatabase? local,
    Future<List<Map<String, dynamic>>> Function()? fetchRequests,
    Future<AppUser> Function()? fetchMember,
    Future<void> Function(String id, String title, String text)? notify,
  }) : _local = local ?? LocalDatabase.instance,
       _fetchRequests =
           fetchRequests ?? AuthService.getMyRescueVerificationHistory,
       _fetchMember = fetchMember ?? AuthService.currentMember,
       _notify =
           notify ??
           ((id, title, text) => AppNotifications.instance.show(
             id: id,
             title: title,
             text: text,
           ));

  static final instance = RescueStatusService();
  final LocalDatabase _local;
  final Future<List<Map<String, dynamic>>> Function() _fetchRequests;
  final Future<AppUser> Function() _fetchMember;
  final Future<void> Function(String, String, String) _notify;
  AppUser? member;
  List<Map<String, dynamic>> requests = [];
  ({String id, String title, String text})? notice;
  String? error;
  bool refreshing = false;
  Timer? _timer;
  int _generation = 0;
  bool _monitoring = false;
  Set<String> _notified = {};

  Future<void> start(AppUser user, {bool monitor = true}) async {
    stop();
    if (!user.isMember) return;
    final generation = _generation;
    member = user;
    try {
      final db = await _local.database;
      final cached = await _local.metaStore
          .record('rescue_status:${user.id}')
          .get(db);
      if (generation != _generation) return;
      requests = (cached?['requests'] as List? ?? [])
          .map((row) => Map<String, dynamic>.from(row as Map))
          .toList();
      _notified = (cached?['notified'] as List? ?? []).cast<String>().toSet();
    } catch (_) {
      if (generation != _generation) return;
      error = 'อ่านประวัติในเครื่องไม่ได้ กำลังตรวจสอบข้อมูลล่าสุด';
    }
    notifyListeners();
    if (monitor) {
      _monitoring = true;
      WidgetsBinding.instance.addObserver(this);
      NetworkService.instance.online.addListener(_onNetwork);
      _timer = Timer.periodic(const Duration(seconds: 30), (_) {
        if (NetworkService.instance.online.value) unawaited(refresh());
      });
    }
    await refresh();
  }

  void _onNetwork() {
    if (NetworkService.instance.online.value) unawaited(refresh());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) unawaited(refresh());
  }

  Future<void> refresh() async {
    final owner = member?.id;
    if (owner == null || refreshing) return;
    final generation = _generation;
    refreshing = true;
    error = null;
    notifyListeners();
    try {
      final rows = await _fetchRequests().timeout(const Duration(seconds: 15));
      if (generation != _generation) return;
      final updated = await _fetchMember().timeout(const Duration(seconds: 15));
      if (generation != _generation || updated.id != owner) return;
      requests = rows;
      member = updated;
      final alerts = <({String id, String title, String text})>[];
      for (final row in rows.reversed) {
        final status = row['status'];
        if (status != 'approved' && status != 'rejected') continue;
        final key = '${row['id']}:$status:${row['reviewed_at']}';
        if (!_notified.add(key)) continue;
        // An old approval is history, not a grant if the role was revoked.
        if (status == 'approved' && !updated.isVerifiedRescuer) continue;
        alerts.add((
          id: 'rescue:$key',
          title: status == 'approved'
              ? 'อนุมัติสิทธิ์หน่วยกู้ภัยแล้ว'
              : 'ผลตรวจสอบสิทธิ์หน่วยกู้ภัย',
          text: status == 'approved'
              ? 'คุณเปิดโหมดกู้ภัยได้แล้ว ดูรายละเอียดและประวัติในโปรไฟล์'
              : 'คำขอไม่ผ่านการอนุมัติ ดูเหตุผลและส่งคำขอใหม่ได้ในโปรไฟล์',
        ));
      }
      final db = await _local.database;
      if (generation != _generation) return;
      await _local.metaStore.record('rescue_status:$owner').put(db, {
        'owner_id': owner,
        'requests': rows,
        'notified': _notified.toList(),
      });
      if (generation != _generation) return;
      for (final alert in alerts) {
        notice = alert;
        notifyListeners();
        try {
          await _notify(alert.id, alert.title, alert.text);
        } catch (_) {}
        if (generation != _generation) return;
      }
    } catch (_) {
      if (generation == _generation) {
        error = 'ยังอัปเดตสถานะไม่ได้ แสดงประวัติที่บันทึกในเครื่อง';
      }
    } finally {
      if (generation == _generation) {
        refreshing = false;
        notifyListeners();
      }
    }
  }

  void stop() {
    _generation++;
    _timer?.cancel();
    _timer = null;
    if (_monitoring) {
      WidgetsBinding.instance.removeObserver(this);
      NetworkService.instance.online.removeListener(_onNetwork);
    }
    _monitoring = false;
    refreshing = false;
    member = null;
    requests = [];
    _notified = {};
    notice = null;
    error = null;
  }

  @override
  void dispose() {
    stop();
    super.dispose();
  }
}
