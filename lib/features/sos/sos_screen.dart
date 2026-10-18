import 'package:flutter/material.dart';

import '../../app/theme.dart';
import '../../widgets/app_card.dart';
import '../../widgets/location_actions.dart';
import '../nearby/nearby_screen.dart';
import '../../data/models/local_sos_record.dart';
import '../../data/repositories/sos_repository.dart';
import '../../models/user.dart';
import '../../services/location_service.dart';
import '../../services/nearby_mesh_service.dart';
import '../../services/sync_service.dart';
import '../rescue/rescue_case_chat_screen.dart';

class SosScreen extends StatefulWidget {
  const SosScreen({super.key, required this.me, this.repository});
  final SosRepository? repository;

  final AppUser me;

  @override
  State<SosScreen> createState() => _SosScreenState();
}

class _SosScreenState extends State<SosScreen> {
  late final SosRepository _repository = widget.repository ?? SosRepository();
  late final Stream<List<LocalSosRecord>> _records = _repository.watchForUser(
    widget.me.id,
  );
  final LocationService _locationService = const LocationService();

  bool _busy = false;

  Future<void> _activate() async {
    var note = 'ต้องการความช่วยเหลือฉุกเฉิน';

    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        icon: const Icon(
          Icons.warning_amber_rounded,
          color: AppColors.error,
          size: 38,
        ),
        title: const Text('เปิด SOS หรือไม่?'),
        content: TextFormField(
          initialValue: note,
          onChanged: (value) => note = value,
          minLines: 2,
          maxLines: 4,
          decoration: const InputDecoration(labelText: 'ข้อความ SOS'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('ยกเลิก'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.error,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('เปิด SOS'),
          ),
        ],
      ),
    );

    note = note.trim();

    if (confirm != true || !mounted) return;

    setState(() => _busy = true);

    try {
      final location = await _locationService.getLatestLocation();

      final record = await _repository.create(
        user: widget.me,
        message: note,
        location: location,
      );

      // Local write succeeds even if radios are off. Nearby is best-effort.
      try {
        final mesh = NearbyMeshService.instance;
        await mesh.initializeForUser(widget.me);
        await mesh.publishSosRecord(record);
      } catch (_) {
        /* Preserve local SOS if Nearby fails. */
      }
      if (widget.me.isMember) {
        try {
          await SyncService.instance.syncNow();
        } catch (_) {
          // Queue stays local until connectivity returns.
        }
      }

      if (!mounted) return;

      _show(
        widget.me.isMember
            ? 'บันทึก SOS แล้ว ดูสถานะการส่งได้ในหน้านี้'
            : 'บันทึก SOS ในเครื่องแล้ว เชื่อมต่อ Nearby เพื่อส่งต่อ',
      );
    } catch (e) {
      if (!mounted) return;

      _show('ไม่สามารถบันทึก SOS ได้: $e', error: true);
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _edit(LocalSosRecord record) async {
    var editedMessage = record.message;

    final value = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('แก้ไขข้อความ SOS'),
        content: TextFormField(
          initialValue: editedMessage,
          onChanged: (value) => editedMessage = value,
          autofocus: true,
          minLines: 2,
          maxLines: 4,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('ยกเลิก'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, editedMessage.trim()),
            child: const Text('บันทึก'),
          ),
        ],
      ),
    );

    if (!mounted || value == null || value.isEmpty) return;

    try {
      await _repository.updateMessage(record, value);
      // Use the persisted case ID, including after an app restart.
      final mesh = NearbyMeshService.instance;
      final latest = await _repository.findById(record.id);
      if (latest != null && latest.isActive) {
        try {
          await mesh.initializeForUser(widget.me);
          await mesh.publishSosRecord(latest);
        } catch (_) {}
      }

      if (widget.me.isMember) {
        await SyncService.instance.syncNow();
      }
    } catch (e) {
      if (!mounted) return;

      _show('แก้ไข SOS ไม่สำเร็จ: $e', error: true);
    }
  }

  Future<void> _stop(LocalSosRecord record) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('หยุด SOS'),
        content: const Text('ยืนยันว่าต้องการปิดสถานะฉุกเฉินนี้หรือไม่?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('ยกเลิก'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.error,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('หยุด SOS'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    try {
      await _repository.stop(record);
      try {
        await NearbyMeshService.instance.initializeForUser(widget.me);
        await NearbyMeshService.instance.stopSos(caseId: record.id);
      } catch (_) {}

      if (widget.me.isMember) {
        await SyncService.instance.syncNow();
      }
    } catch (e) {
      if (!mounted) return;

      _show('หยุด SOS ไม่สำเร็จ: $e', error: true);
    }
  }

  void _show(String text, {bool error = false}) {
    if (!mounted) return;

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          backgroundColor: error ? AppColors.error : null,
          content: Text(text),
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('ขอความช่วยเหลือ'),
        actions: [
          if (widget.me.isMember)
            ValueListenableBuilder<SyncSnapshot>(
              valueListenable: SyncService.instance.status,
              builder: (context, value, _) {
                return IconButton(
                  tooltip: 'ซิงก์ ${value.pendingCount} รายการ',
                  onPressed: value.isBusy
                      ? null
                      : SyncService.instance.retryAll,
                  icon: value.isBusy
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.sync_rounded),
                );
              },
            ),
        ],
      ),
      body: SafeArea(
        child: ListenableBuilder(
          listenable: NearbyMeshService.instance,
          builder: (context, child) => StreamBuilder<List<LocalSosRecord>>(
            stream: _records,
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return const Center(
                  child: Text('ยังเปิดรายการ SOS ไม่ได้ กรุณาลองอีกครั้ง'),
                );
              }

              final records = snapshot.data ?? const [];

              LocalSosRecord? active;

              for (final record in records) {
                if (record.isActive) {
                  active = record;
                  break;
                }
              }

              return ListView(
                padding: const EdgeInsets.fromLTRB(20, 18, 20, 30),
                children: [
                  if (active == null)
                    _InactivePanel(busy: _busy, onActivate: _activate)
                  else
                    _ActivePanel(
                      record: active,
                      onEdit: () => _edit(active!),
                      onStop: () => _stop(active!),
                      onRetry: active.syncState == 'error'
                          ? () async {
                              await _repository.retry(active!.id);
                              await SyncService.instance.retryAll();
                            }
                          : null,
                    ),

                  if (active != null) ...[
                    const SizedBox(height: 18),
                    AppCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'ส่ง SOS ให้คนใกล้ตัว',
                            style: TextStyle(fontWeight: FontWeight.w700),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            'การบันทึกในเครื่องยังไม่ใช่การส่งถึงผู้ช่วยเหลือ เปิด Nearby และเชื่อมต่ออุปกรณ์เพื่อส่งต่อ SOS',
                            style: TextStyle(
                              color: context.colors.muted,
                              fontSize: 13,
                              height: 1.6,
                            ),
                          ),
                          const SizedBox(height: 12),
                          OutlinedButton.icon(
                            onPressed: () => Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => NearbyScreen(me: widget.me),
                              ),
                            ),
                            icon: const Icon(Icons.radar_rounded),
                            label: const Text('เปิด Nearby'),
                          ),
                        ],
                      ),
                    ),
                  ],
                  if (active != null &&
                      NearbyMeshService.instance.activeSosId != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 14),
                      child: OutlinedButton.icon(
                        icon: const Icon(Icons.chat_bubble_outline),
                        label: const Text('แชทกับหน่วยกู้ภัยผ่าน Nearby'),
                        onPressed: () {
                          final mesh = NearbyMeshService.instance;
                          final replies = mesh.inbox
                              .where(
                                (m) =>
                                    m.kind == 'case_chat' &&
                                    (m.data['data'] as Map?)?['caseId'] ==
                                        mesh.activeSosId &&
                                    (m.data['data'] as Map?)?['target'] ==
                                        mesh.deviceId &&
                                    m.data['origin'] != mesh.deviceId,
                              )
                              .toList();
                          if (replies.isEmpty) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text(
                                  'ยังไม่มีข้อความจากหน่วยกู้ภัยใน Nearby กรุณารอการติดต่อ',
                                ),
                              ),
                            );
                            return;
                          }
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => RescueCaseChatScreen(
                                me: widget.me,
                                caseId: mesh.activeSosId!,
                                otherDevice: replies.first.data['origin']
                                    .toString(),
                                title: 'แชทกับหน่วยกู้ภัย',
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  const SizedBox(height: 26),
                  Row(
                    children: [
                      const Expanded(
                        child: Text(
                          'ประวัติการขอความช่วยเหลือ',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                      Text(
                        '${records.length} รายการ',
                        style: TextStyle(color: context.colors.muted),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  if (records.isEmpty)
                    const _EmptyLocalDb()
                  else
                    ...records.map(
                      (record) => Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: _HistoryCard(
                          record: record,
                          onEdit: () => _edit(record),
                          onRetry: record.syncState == 'error'
                              ? () async {
                                  await _repository.retry(record.id);
                                  await SyncService.instance.retryAll();
                                }
                              : null,
                        ),
                      ),
                    ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

class _InactivePanel extends StatelessWidget {
  const _InactivePanel({required this.busy, required this.onActivate});
  final bool busy;
  final VoidCallback onActivate;
  @override
  Widget build(BuildContext context) => AppCard(
    padding: const EdgeInsets.all(22),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.errorContainer,
                borderRadius: BorderRadius.circular(17),
              ),
              child: Icon(
                Icons.sos_rounded,
                color: Theme.of(context).colorScheme.error,
                size: 30,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'ขอความช่วยเหลือ',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 3),
                  Text(
                    'เริ่มต้น SOS ของคุณ',
                    style: TextStyle(color: context.colors.muted, fontSize: 13),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 22),
        Text(
          'เพิ่มข้อความและพิกัด เพื่อให้คนใกล้ตัวรู้ว่าคุณต้องการความช่วยเหลือ',
          style: TextStyle(color: context.colors.muted, height: 1.7),
        ),
        const SizedBox(height: 20),
        _PreparationStep(
          number: '1',
          title: 'ระบุเหตุการณ์',
          detail: 'ตรวจข้อความและพิกัดก่อนยืนยัน',
        ),
        const SizedBox(height: 15),
        _PreparationStep(
          number: '2',
          title: 'บันทึก แล้วเชื่อมต่อเพื่อส่งต่อ',
          detail: 'บันทึกในเครื่องได้ แม้ไม่มีอินเทอร์เน็ต',
        ),
        const SizedBox(height: 24),
        FilledButton.icon(
          style: FilledButton.styleFrom(
            backgroundColor: AppColors.sos,
            foregroundColor: Colors.white,
            minimumSize: const Size(48, 58),
          ),
          onPressed: busy ? null : onActivate,
          icon: busy
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : const Icon(Icons.sos_rounded),
          label: Text(busy ? 'กำลังบันทึก SOS…' : 'เปิด SOS · ขอความช่วยเหลือ'),
        ),
        const SizedBox(height: 12),
        Text(
          'การบันทึกในเครื่องยังไม่ยืนยันว่ามีผู้รับ SOS แล้ว',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: context.colors.muted,
            fontSize: 12,
            height: 1.5,
          ),
        ),
      ],
    ),
  );
}

class _PreparationStep extends StatelessWidget {
  const _PreparationStep({
    required this.number,
    required this.title,
    required this.detail,
  });
  final String number, title, detail;
  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Container(
        width: 27,
        height: 27,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: context.colors.surfaceSoft,
          shape: BoxShape.circle,
        ),
        child: Text(
          number,
          style: TextStyle(
            color: context.colors.info,
            fontSize: 12,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      const SizedBox(width: 12),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
            ),
            const SizedBox(height: 3),
            Text(
              detail,
              style: TextStyle(
                color: context.colors.muted,
                fontSize: 12,
                height: 1.5,
              ),
            ),
          ],
        ),
      ),
    ],
  );
}

class _ActivePanel extends StatelessWidget {
  const _ActivePanel({
    required this.record,
    required this.onEdit,
    required this.onStop,
    this.onRetry,
  });

  final LocalSosRecord record;
  final VoidCallback onEdit;
  final VoidCallback onStop;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final locationText = record.latitude == null || record.longitude == null
        ? 'ไม่มีพิกัดใหม่ • SOS ยังบันทึกได้'
        : '${record.latitude!.toStringAsFixed(5)}, '
              '${record.longitude!.toStringAsFixed(5)}';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AppColors.error.withValues(alpha: .12),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.error.withValues(alpha: .45)),
          ),
          child: const Text(
            'SOS กำลังทำงาน • บันทึกในเครื่องแล้ว',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: AppColors.error,
              fontWeight: FontWeight.w900,
            ),
          ),
        ),
        const SizedBox(height: 18),
        _InfoLine(
          icon: Icons.message_outlined,
          title: 'ข้อความ',
          value: record.message,
        ),
        const SizedBox(height: 10),
        _InfoLine(
          icon: Icons.location_on_outlined,
          title: 'ตำแหน่งล่าสุด',
          value: locationText,
        ),
        if (record.latitude != null && record.longitude != null) ...[
          LocationActions(
            latitude: record.latitude!,
            longitude: record.longitude!,
          ),
          if (record.isLastKnownLocation || record.locationRecordedAt == null)
            const Text(
              'พิกัดที่เคยบันทึกไว้ ไม่ใช่ตำแหน่งปัจจุบัน',
              style: TextStyle(color: Colors.orangeAccent),
            ),
          if (record.locationRecordedAt != null)
            Text(
              'เวลาพิกัด: ${LocationActions.recordedAt(record.locationRecordedAt!)}',
              style: TextStyle(color: context.colors.muted, fontSize: 12),
            ),
        ],
        const SizedBox(height: 10),
        _InfoLine(
          icon: Icons.sync_rounded,
          title: 'การซิงก์คลาวด์',
          value: switch (record.syncState) {
            'synced' =>
              record.ownerUserId == null
                  ? 'เก็บในอุปกรณ์นี้'
                  : 'ซิงก์คลาวด์แล้ว · ยังไม่ใช่การยืนยันจากหน่วยกู้ภัย',
            'error' => 'ยังส่งไม่สำเร็จ จะลองอีกครั้ง',
            _ =>
              record.ownerUserId == null
                  ? 'เก็บในอุปกรณ์นี้'
                  : 'รออินเทอร์เน็ตเพื่อซิงก์คลาวด์',
          },
        ),
        if (record.lastError != null) ...[
          const SizedBox(height: 10),
          _InfoLine(
            icon: Icons.error_outline_rounded,
            title: 'ข้อผิดพลาด',
            value: record.lastError!,
          ),
        ],
        const SizedBox(height: 14),
        OutlinedButton.icon(
          onPressed: onEdit,
          icon: const Icon(Icons.edit_outlined),
          label: const Text('แก้ไขข้อความ SOS'),
        ),
        if (onRetry != null) ...[
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh_rounded),
            label: const Text('ลองส่งข้อมูลอีกครั้ง'),
          ),
        ],
        const SizedBox(height: 8),
        FilledButton.icon(
          style: FilledButton.styleFrom(
            backgroundColor: AppColors.error,
            foregroundColor: Colors.white,
          ),
          onPressed: onStop,
          icon: const Icon(Icons.stop_circle_outlined),
          label: const Text('หยุด SOS'),
        ),
      ],
    );
  }
}

class _HistoryCard extends StatelessWidget {
  const _HistoryCard({
    required this.record,
    required this.onEdit,
    this.onRetry,
  });

  final LocalSosRecord record;
  final VoidCallback onEdit;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final time = record.createdAt;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: context.colors.surfaceSoft,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(
                record.isActive
                    ? Icons.warning_amber_rounded
                    : Icons.stop_circle_outlined,
                color: record.isActive ? AppColors.error : context.colors.muted,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  record.message,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
              _SyncChip(
                state: record.syncState,
                localOnly: record.ownerUserId == null,
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            '${record.isActive ? 'กำลังขอความช่วยเหลือ' : 'ปิด SOS แล้ว'} · '
            '${time.day.toString().padLeft(2, '0')}/'
            '${time.month.toString().padLeft(2, '0')}/'
            '${time.year} '
            '${time.hour.toString().padLeft(2, '0')}:'
            '${time.minute.toString().padLeft(2, '0')}',
            style: TextStyle(color: context.colors.muted, fontSize: 12),
          ),
          Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              if (record.latitude != null && record.longitude != null)
                LocationActions(
                  latitude: record.latitude!,
                  longitude: record.longitude!,
                  compact: true,
                ),
              TextButton.icon(
                onPressed: onEdit,
                icon: const Icon(Icons.edit_outlined, size: 18),
                label: const Text('แก้ไข'),
              ),
              if (onRetry != null)
                TextButton.icon(
                  onPressed: onRetry,
                  icon: const Icon(Icons.refresh_rounded, size: 18),
                  label: const Text('ลองอีกครั้ง'),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SyncChip extends StatelessWidget {
  const _SyncChip({required this.state, this.localOnly = false});

  final String state;
  final bool localOnly;

  @override
  Widget build(BuildContext context) {
    final color = switch (state) {
      'synced' => context.colors.success,
      'error' => AppColors.error,
      _ => context.colors.info,
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .10),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: .30)),
      ),
      child: Text(
        localOnly
            ? 'ในเครื่อง'
            : switch (state) {
                'synced' => 'ซิงก์แล้ว',
                'error' => 'รอลองอีกครั้ง',
                _ => 'รอซิงก์',
              },
        style: TextStyle(
          color: color,
          fontSize: 10,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }
}

class _InfoLine extends StatelessWidget {
  const _InfoLine({
    required this.icon,
    required this.title,
    required this.value,
  });

  final IconData icon;
  final String title;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: context.colors.surfaceSoft,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: context.colors.info),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: TextStyle(color: context.colors.muted, fontSize: 12),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyLocalDb extends StatelessWidget {
  const _EmptyLocalDb();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: context.colors.surfaceSoft,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Text(
        'ยังไม่มีประวัติ SOS',
        textAlign: TextAlign.center,
        style: TextStyle(color: context.colors.muted),
      ),
    );
  }
}
