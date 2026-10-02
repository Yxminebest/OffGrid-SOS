import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../app/theme.dart';
import '../../services/auth_service.dart';

class RescueVerificationScreen extends StatefulWidget {
  const RescueVerificationScreen({super.key});

  @override
  State<RescueVerificationScreen> createState() =>
      _RescueVerificationScreenState();
}

class _RescueVerificationScreenState extends State<RescueVerificationScreen> {
  final _organization = TextEditingController();
  final _personnelId = TextEditingController();
  final _note = TextEditingController();

  bool _busy = false;
  Map<String, dynamic>? _latest;

  Uint8List? _documentBytes;
  String? _documentName;
  String? _documentMimeType;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _organization.dispose();
    _personnelId.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final latest = await AuthService.getMyRescuerVerificationRequest();

      if (!mounted) return;
      setState(() => _latest = latest);
    } catch (_) {}
  }

  Future<void> _pickDocument() async {
    try {
      final file = await FilePicker.pickFile(
        type: FileType.custom,
        allowedExtensions: const ['jpg', 'jpeg', 'png', 'pdf'],
      );

      // ผู้ใช้กดยกเลิก
      if (file == null) return;

      // file_picker 13.x เปลี่ยน size → length()
      final fileLength = file.lengthSync() ?? await file.length();

      if (fileLength == null) {
        _showError('ไม่สามารถตรวจสอบขนาดไฟล์ได้ กรุณาเลือกไฟล์อีกครั้ง');
        return;
      }

      // จำกัด 10 MB
      if (fileLength > 10 * 1024 * 1024) {
        _showError('ไฟล์ต้องมีขนาดไม่เกิน 10 MB');
        return;
      }

      // file_picker 13.x อ่านข้อมูลแบบนี้
      final bytes = await file.readAsBytes();

      final extension = file.extension?.toLowerCase() ?? '';

      final mimeType = switch (extension) {
        'pdf' => 'application/pdf',
        'png' => 'image/png',
        'jpg' || 'jpeg' => 'image/jpeg',
        _ => 'application/octet-stream',
      };

      if (!mounted) return;

      setState(() {
        _documentBytes = bytes;
        _documentName = file.name;
        _documentMimeType = mimeType;
      });
    } catch (e) {
      if (!mounted) return;

      _showError('ไม่สามารถเลือกหรืออ่านไฟล์ได้: $e');
    }
  }

  Future<void> _submit() async {
    if (_busy) return;

    if (_documentBytes == null) {
      _showError('กรุณาแนบเอกสารหรือรูปหลักฐานยืนยันหน่วยกู้ภัย');
      return;
    }

    setState(() => _busy = true);

    try {
      await AuthService.submitRescuerVerification(
        organizationName: _organization.text,
        personnelId: _personnelId.text,
        note: _note.text,
        documentBytes: _documentBytes,
        documentName: _documentName,
        documentMimeType: _documentMimeType,
      );

      await _load();

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('ส่งคำขอยืนยันหน่วยกู้ภัยแล้ว')),
      );
    } on AuthServiceException catch (e) {
      if (!mounted) return;
      _showError(e.message);
    } catch (_) {
      if (!mounted) return;
      _showError('ส่งคำขอไม่สำเร็จ กรุณาลองใหม่');
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(backgroundColor: AppColors.error, content: Text(message)),
      );
  }

  @override
  Widget build(BuildContext context) {
    final status = _latest?['status']?.toString();
    final rejectionReason = _latest?['rejection_reason']?.toString();

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'ยืนยันสถานะหน่วยกู้ภัย',
          style: TextStyle(fontWeight: FontWeight.w900),
        ),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            const Icon(
              Icons.health_and_safety_outlined,
              size: 64,
              color: AppColors.info,
            ),
            const SizedBox(height: 14),
            const Text(
              'ขอสิทธิ์ RESCUE MODE',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 8),
            const Text(
              'เฉพาะเจ้าหน้าที่หรือหน่วยกู้ภัยที่ Admin ตรวจสอบและอนุมัติแล้ว '
              'จึงจะเปิด RESCUE MODE ได้',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.muted, height: 1.5),
            ),
            if (status != null) ...[
              const SizedBox(height: 18),
              _StatusCard(status: status, rejectionReason: rejectionReason),
            ],
            const SizedBox(height: 22),
            TextField(
              controller: _organization,
              decoration: const InputDecoration(
                labelText: 'ชื่อหน่วยงาน *',
                prefixIcon: Icon(Icons.apartment_rounded),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _personnelId,
              decoration: const InputDecoration(
                labelText: 'รหัสประจำตัวเจ้าหน้าที่ *',
                prefixIcon: Icon(Icons.badge_outlined),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _note,
              minLines: 3,
              maxLines: 5,
              decoration: const InputDecoration(
                labelText: 'หมายเหตุ',
                prefixIcon: Icon(Icons.notes_rounded),
              ),
            ),
            const SizedBox(height: 18),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: AppColors.border),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                    'เอกสารยืนยัน *',
                    style: TextStyle(fontWeight: FontWeight.w900),
                  ),
                  const SizedBox(height: 5),
                  const Text(
                    'รองรับ JPG, PNG หรือ PDF ขนาดไม่เกิน 10 MB',
                    style: TextStyle(color: AppColors.muted, fontSize: 12),
                  ),
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    onPressed: _busy ? null : _pickDocument,
                    icon: const Icon(Icons.upload_file_rounded),
                    label: Text(
                      _documentName == null ? 'เลือกเอกสาร' : 'เปลี่ยนเอกสาร',
                    ),
                  ),
                  if (_documentName != null) ...[
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        const Icon(
                          Icons.description_outlined,
                          color: AppColors.info,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            _documentName!,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        IconButton(
                          onPressed: _busy
                              ? null
                              : () {
                                  setState(() {
                                    _documentBytes = null;
                                    _documentName = null;
                                    _documentMimeType = null;
                                  });
                                },
                          icon: const Icon(Icons.close_rounded),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 18),
            FilledButton.icon(
              onPressed: _busy || status == 'pending' ? null : _submit,
              icon: const Icon(Icons.send_rounded),
              label: _busy
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.5,
                        color: Colors.white,
                      ),
                    )
                  : Text(
                      status == 'rejected' ? 'ส่งคำขอใหม่' : 'ส่งคำขอตรวจสอบ',
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatusCard extends StatelessWidget {
  const _StatusCard({required this.status, required this.rejectionReason});

  final String status;
  final String? rejectionReason;

  @override
  Widget build(BuildContext context) {
    final title = switch (status) {
      'approved' => 'อนุมัติแล้ว',
      'rejected' => 'ไม่ผ่านการอนุมัติ',
      _ => 'กำลังรอตรวจสอบ',
    };

    final icon = switch (status) {
      'approved' => Icons.verified_rounded,
      'rejected' => Icons.cancel_outlined,
      _ => Icons.schedule_rounded,
    };

    final color = switch (status) {
      'approved' => Colors.green,
      'rejected' => AppColors.error,
      _ => AppColors.info,
    };

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: .30)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(color: color, fontWeight: FontWeight.w900),
                ),
                if (status == 'pending')
                  const Text(
                    'Admin จะตรวจสอบข้อมูลและเอกสารก่อนให้สิทธิ์ RESCUE MODE',
                    style: TextStyle(color: AppColors.muted, fontSize: 12),
                  ),
                if (status == 'rejected' &&
                    rejectionReason != null &&
                    rejectionReason!.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    'เหตุผล: $rejectionReason',
                    style: const TextStyle(
                      color: AppColors.muted,
                      fontSize: 12,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
