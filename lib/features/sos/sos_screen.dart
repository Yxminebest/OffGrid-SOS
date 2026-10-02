import 'package:flutter/material.dart';

import '../../app/theme.dart';
import '../../data/models/local_sos_record.dart';
import '../../data/repositories/sos_repository.dart';
import '../../models/user.dart';
import '../../services/location_service.dart';
import '../../services/sync_service.dart';

class SosScreen extends StatefulWidget {
  const SosScreen({super.key, required this.me});

  final AppUser me;

  @override
  State<SosScreen> createState() => _SosScreenState();
}

class _SosScreenState extends State<SosScreen> {
  final SosRepository _repository = SosRepository();
  final LocationService _locationService = const LocationService();

  bool _busy = false;

  Future<void> _activate() async {
    final noteController = TextEditingController(
      text: 'ต้องการความช่วยเหลือฉุกเฉิน',
    );

    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        icon: const Icon(
          Icons.warning_amber_rounded,
          color: AppColors.error,
          size: 38,
        ),
        title: const Text('เปิด SOS หรือไม่?'),
        content: TextField(
          controller: noteController,
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
            style: FilledButton.styleFrom(backgroundColor: AppColors.error),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('เปิด SOS'),
          ),
        ],
      ),
    );

    final note = noteController.text.trim();
    noteController.dispose();

    if (confirm != true || !mounted) return;

    setState(() => _busy = true);

    try {
      final location = await _locationService.getLatestLocation();

      await _repository.create(
        user: widget.me,
        message: note,
        location: location,
      );

      if (widget.me.isMember) {
        await SyncService.instance.syncNow();
      }

      if (!mounted) return;

      _show(
        widget.me.isMember
            ? 'บันทึก SOS ลง Local DB แล้ว และกำลังซิงก์'
            : 'บันทึก SOS ลง Local DB แล้ว (Guest: local-only)',
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
    final controller = TextEditingController(text: record.message);

    final value = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('แก้ไขข้อความ SOS'),
        content: TextField(
          controller: controller,
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
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('บันทึก'),
          ),
        ],
      ),
    );

    controller.dispose();

    if (value == null || value.isEmpty) return;

    try {
      await _repository.updateMessage(record, value);

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
            style: FilledButton.styleFrom(backgroundColor: AppColors.error),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('หยุด SOS'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    try {
      await _repository.stop(record);

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
        title: const Text('SOS • Offline-first'),
        actions: [
          ValueListenableBuilder<SyncSnapshot>(
            valueListenable: SyncService.instance.status,
            builder: (context, value, _) {
              return IconButton(
                tooltip: 'ซิงก์ ${value.pendingCount} รายการ',
                onPressed: value.isBusy ? null : SyncService.instance.retryAll,
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
        child: StreamBuilder<List<LocalSosRecord>>(
          stream: _repository.watchForUser(widget.me.id),
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return const Center(child: Text('อ่าน Local DB ไม่สำเร็จ'));
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
                const SizedBox(height: 26),
                Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'ประวัติ SOS ใน Local DB',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                    Text(
                      '${records.length} รายการ',
                      style: const TextStyle(color: AppColors.muted),
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
    );
  }
}

class _InactivePanel extends StatelessWidget {
  const _InactivePanel({required this.busy, required this.onActivate});

  final bool busy;
  final VoidCallback onActivate;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const Icon(
          Icons.warning_amber_rounded,
          color: AppColors.error,
          size: 76,
        ),
        const SizedBox(height: 18),
        const Text(
          'ขอความช่วยเหลือฉุกเฉิน',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 26, fontWeight: FontWeight.w900),
        ),
        const SizedBox(height: 10),
        const Text(
          'เมื่อกด SOS ระบบจะเขียนลง Local DB ก่อนเสมอ '
          'จากนั้นจึงพยายาม Sync ไป Supabase ถ้ามีอินเทอร์เน็ต',
          textAlign: TextAlign.center,
          style: TextStyle(color: AppColors.muted, height: 1.5),
        ),
        const SizedBox(height: 26),
        SizedBox(
          width: 170,
          height: 170,
          child: FilledButton(
            style: FilledButton.styleFrom(
              shape: const CircleBorder(),
              backgroundColor: AppColors.error,
            ),
            onPressed: busy ? null : onActivate,
            child: busy
                ? const CircularProgressIndicator(color: Colors.white)
                : const Text(
                    'SOS',
                    style: TextStyle(
                      fontSize: 32,
                      fontWeight: FontWeight.w900,
                      color: Colors.white,
                    ),
                  ),
          ),
        ),
      ],
    );
  }
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
    final locationText = record.latitude == null
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
            '⚠ SOS ACTIVE • บันทึกอยู่ใน Local DB',
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
        const SizedBox(height: 10),
        _InfoLine(
          icon: Icons.sync_rounded,
          title: 'สถานะ Sync',
          value: record.syncState,
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
            label: const Text('Retry Sync'),
          ),
        ],
        const SizedBox(height: 8),
        FilledButton.icon(
          style: FilledButton.styleFrom(backgroundColor: AppColors.error),
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
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(
                record.isActive
                    ? Icons.warning_amber_rounded
                    : Icons.check_circle_outline,
                color: record.isActive ? AppColors.error : AppColors.muted,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  record.message,
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
              _SyncChip(state: record.syncState),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            '${time.day.toString().padLeft(2, '0')}/'
            '${time.month.toString().padLeft(2, '0')}/'
            '${time.year} '
            '${time.hour.toString().padLeft(2, '0')}:'
            '${time.minute.toString().padLeft(2, '0')}',
            style: const TextStyle(color: AppColors.muted, fontSize: 12),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              TextButton.icon(
                onPressed: onEdit,
                icon: const Icon(Icons.edit_outlined, size: 18),
                label: const Text('แก้ไข'),
              ),
              if (onRetry != null)
                TextButton.icon(
                  onPressed: onRetry,
                  icon: const Icon(Icons.refresh_rounded, size: 18),
                  label: const Text('Retry'),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SyncChip extends StatelessWidget {
  const _SyncChip({required this.state});

  final String state;

  @override
  Widget build(BuildContext context) {
    final color = switch (state) {
      'synced' => Colors.green,
      'error' => AppColors.error,
      _ => AppColors.info,
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .10),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: .30)),
      ),
      child: Text(
        state.toUpperCase(),
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
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: AppColors.info),
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
                  style: const TextStyle(color: AppColors.muted, fontSize: 12),
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
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: const Text(
        'ยังไม่มี SOS ใน Local DB',
        textAlign: TextAlign.center,
        style: TextStyle(color: AppColors.muted),
      ),
    );
  }
}
