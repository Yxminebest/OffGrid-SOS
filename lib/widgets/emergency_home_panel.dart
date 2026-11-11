import 'dart:async';
import 'package:flutter/material.dart';
import '../app/theme.dart';
import '../data/models/local_sos_record.dart';
import '../data/repositories/sos_repository.dart';
import '../models/user.dart';
import '../services/location_service.dart';
import '../services/sos_location_tracker.dart';
import '../services/nearby_mesh_service.dart';
import '../services/sync_service.dart';

/// A quick request is persisted before GPS or radio work starts.
class EmergencyHomePanel extends StatefulWidget {
  const EmergencyHomePanel({
    super.key,
    required this.me,
    required this.onDetails,
    this.record,
    this.repository,
    this.mesh,
    this.location = const LocationService(),
  });
  final AppUser me;
  final LocalSosRecord? record;
  final VoidCallback onDetails;
  final SosRepository? repository;
  final NearbyMeshService? mesh;
  final LocationService location;
  @override
  State<EmergencyHomePanel> createState() => _EmergencyHomePanelState();
}

class _EmergencyHomePanelState extends State<EmergencyHomePanel>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late final AnimationController hold;
  int? holdingPointer;
  bool suppressReleaseTap = false;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    hold =
        AnimationController(vsync: this, duration: const Duration(seconds: 1))
          ..addStatusListener((status) {
            if (status == AnimationStatus.completed && holdingPointer != null) {
              suppressReleaseTap = true;
              cancelHold();
              unawaited(requestSos());
            }
          });
  }

  void cancelHold() {
    holdingPointer = null;
    hold.reset();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) cancelHold();
  }

  @override
  void deactivate() {
    holdingPointer = null;
    hold.stop();
    super.deactivate();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _locationTracker.cancel();
    hold.dispose();
    super.dispose();
  }

  bool busy = false;
  late final repository = widget.repository ?? SosRepository();
  late final mesh = widget.mesh ?? NearbyMeshService.instance;
  void notice(String text) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
    }
  }

  Future<void> publish(LocalSosRecord record) async {
    try {
      // Never send an old request through a new account's radio session.
      if (mesh.ownerId != record.ownerLocalId) return;
      await mesh.publishSosRecord(record);
      if (!mesh.running) {
        await mesh.resumePreferred(widget.me, startIfUnset: true);
      }
    } catch (_) {
      /* Durable record remains available for reconnect. */
    }
    if (widget.me.isMember) {
      try {
        unawaited(SyncService.instance.syncNow().catchError((_) {}));
      } catch (_) {}
    }
  }

  late final _locationTracker = SosLocationTracker(
    widget.location,
    repository,
    mesh,
  );
  Future<void> locate(LocalSosRecord record) async {
    _locationTracker.start(record);
  }

  Future<void> requestSos() async {
    if (busy) return;
    setState(() => busy = true);
    try {
      final existing = await repository.latestActive(widget.me.id);
      if (existing != null) {
        if (mounted) widget.onDetails();
        return;
      }
      if (!mounted) return;
      final record = await repository.create(
        user: widget.me,
        message: 'ต้องการความช่วยเหลือฉุกเฉิน',
        location: widget.location.preparedLocation,
      );
      // เปิดรายละเอียดหลังบันทึกในเครื่อง; GPS/วิทยุช้าต้องไม่หน่วงการแจ้งเหตุ
      unawaited(startDelivery(record));
      widget.onDetails();
    } catch (_) {
      notice('บันทึก SOS ไม่สำเร็จ กรุณาลองอีกครั้ง');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> startDelivery(LocalSosRecord record) async {
    try {
      if (!mounted ||
          (mesh.ownerId != null && mesh.ownerId != record.ownerLocalId)) {
        return;
      }
      if (mesh.ownerId != record.ownerLocalId) {
        await mesh.initializeForUser(widget.me);
      }
      if (mesh.ownerId != record.ownerLocalId) return;
      unawaited(publish(record));
      unawaited(locate(record));
    } catch (_) {
      /* Reconnect will recover the saved request. */
    }
  }

  Future<void> stop() async {
    if (busy) return;
    final record = widget.record;
    if (record == null) return;
    setState(() => busy = true);
    try {
      _locationTracker.cancel();
      await repository.stop(record);
      final stopped = await repository.findById(record.id);
      if (stopped != null) unawaited(publish(stopped));
      notice('หยุด SOS แล้ว');
    } catch (_) {
      notice('หยุด SOS ไม่สำเร็จ กรุณาลองอีกครั้ง');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final active = widget.record?.isActive == true;
    return Column(
      children: [
        Text(
          active ? 'คุณกำลังขอความช่วยเหลือ' : 'ต้องการความช่วยเหลือฉุกเฉิน?',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 12),
        Center(
          child: Listener(
            onPointerDown: (event) {
              if (holdingPointer == null) suppressReleaseTap = false;
              if (busy || active || holdingPointer != null) return;
              holdingPointer = event.pointer;
              hold.forward(from: 0);
            },
            onPointerUp: (event) {
              if (event.pointer == holdingPointer) cancelHold();
            },
            onPointerCancel: (event) {
              if (event.pointer == holdingPointer) cancelHold();
            },
            onPointerMove: (event) {
              if (event.pointer == holdingPointer &&
                  (event.localPosition - const Offset(86, 86)).distance > 86) {
                cancelHold();
              }
            },
            child: SizedBox.square(
              dimension: 172,
              child: AnimatedBuilder(
                animation: hold,
                builder: (context, _) => Stack(
                  fit: StackFit.expand,
                  children: [
                    CircularProgressIndicator(
                      value: hold.value,
                      strokeWidth: 6,
                      color: AppColors.sos,
                      backgroundColor: AppColors.sos.withValues(alpha: .12),
                    ),
                    Padding(
                      padding: const EdgeInsets.all(10),
                      child: FilledButton(
                        onPressed: busy
                            ? null
                            : active
                            ? () {
                                if (!suppressReleaseTap) widget.onDetails();
                              }
                            : () {},
                        style: FilledButton.styleFrom(
                          shape: const CircleBorder(),
                          padding: const EdgeInsets.all(16),
                          backgroundColor: AppColors.sos,
                          foregroundColor: Colors.white,
                        ),
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              if (busy)
                                const CircularProgressIndicator(
                                  color: Colors.white,
                                )
                              else
                                const Icon(
                                  Icons.warning_amber_rounded,
                                  size: 34,
                                ),
                              const Text(
                                'SOS',
                                style: TextStyle(
                                  fontSize: 38,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        if (active) ...[
          const SizedBox(height: 12),
          Text(
            'SOS กำลังทำงาน',
            textAlign: TextAlign.center,
            style: TextStyle(color: context.colors.muted),
          ),
        ],
        const SizedBox(height: 8),
        Wrap(
          alignment: WrapAlignment.center,
          spacing: 12,
          runSpacing: 4,
          children: [
            TextButton.icon(
              onPressed: busy ? null : widget.onDetails,
              icon: const Icon(Icons.edit_note_rounded),
              label: Text(
                active
                    ? 'เพิ่ม / แก้ไขรายละเอียด'
                    : 'เลือกเหตุ / เพิ่มรายละเอียด',
              ),
            ),
            if (active)
              OutlinedButton.icon(
                onPressed: busy ? null : stop,
                style: OutlinedButton.styleFrom(foregroundColor: AppColors.sos),
                icon: const Icon(Icons.stop_circle_outlined),
                label: const Text('หยุด SOS'),
              ),
          ],
        ),
      ],
    );
  }
}
