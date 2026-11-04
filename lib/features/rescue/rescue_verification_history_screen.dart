import '../../app/app_palette.dart';
import 'dart:async';
import 'package:flutter/material.dart';
import '../../models/user.dart';
import '../../services/rescue_status_service.dart';
import '../../widgets/location_actions.dart';

class RescueVerificationHistoryScreen extends StatefulWidget {
  const RescueVerificationHistoryScreen({
    super.key,
    required this.me,
    this.service,
  });
  final AppUser me;
  final RescueStatusService? service;
  @override
  State<RescueVerificationHistoryScreen> createState() => _HistoryState();
}

class _HistoryState extends State<RescueVerificationHistoryScreen> {
  late final status = widget.service ?? RescueStatusService.instance;
  @override
  void initState() {
    super.initState();
    if (status.member?.id != widget.me.id) {
      unawaited(status.start(widget.me));
    } else {
      unawaited(status.refresh());
    }
  }

  String time(Object? value) {
    final parsed = DateTime.tryParse(value?.toString() ?? '');
    return parsed == null ? 'ไม่ระบุ' : LocationActions.recordedAt(parsed);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('ประวัติการขอสิทธิ์กู้ภัย')),
    body: SafeArea(
      child: ListenableBuilder(
        listenable: status,
        builder: (context, _) {
          final ownerMatches = status.member?.id == widget.me.id;
          final rows = ownerMatches
              ? status.requests
              : <Map<String, dynamic>>[];
          return RefreshIndicator(
            onRefresh: status.refresh,
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(16),
              children: [
                if (status.refreshing) const LinearProgressIndicator(),
                Text(
                  ownerMatches && status.member!.isVerifiedRescuer
                      ? 'สิทธิ์ปัจจุบัน: หน่วยกู้ภัยที่ยืนยันแล้ว'
                      : 'สิทธิ์ปัจจุบัน: ยังไม่เปิดใช้โหมดกู้ภัย',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 8),

                if (status.error != null) Text(status.error!),
                TextButton.icon(
                  onPressed: status.refreshing ? null : status.refresh,
                  icon: const Icon(Icons.refresh),
                  label: const Text('อัปเดตสถานะ'),
                ),
                if (rows.isEmpty && !status.refreshing)
                  const Padding(
                    padding: EdgeInsets.all(24),
                    child: Text('ยังไม่มีประวัติคำขอที่บันทึกไว้'),
                  ),
                for (final row in rows)
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            switch (row['status']) {
                              'approved' => 'อนุมัติสิทธิ์หน่วยกู้ภัยแล้ว',
                              'rejected' => 'ไม่ผ่านการอนุมัติ',
                              _ => 'กำลังรอตรวจสอบ',
                            },
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: row['status'] == 'approved'
                                  ? AppColors.rescueStrong
                                  : null,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            row['organization_name']?.toString() ??
                                'หน่วยงานไม่ระบุ',
                          ),
                          Text('ส่งคำขอ: ${time(row['submitted_at'])}'),
                          if (row['reviewed_at'] != null)
                            Text('ตรวจสอบ: ${time(row['reviewed_at'])}'),
                          if (row['rejection_reason']?.toString().isNotEmpty ==
                              true)
                            Text('เหตุผล: ${row['rejection_reason']}'),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    ),
  );
}
