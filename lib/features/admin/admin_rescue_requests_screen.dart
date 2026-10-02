import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../app/theme.dart';
import '../../services/auth_service.dart';

class AdminRescueRequestsScreen extends StatefulWidget {
  const AdminRescueRequestsScreen({super.key});

  @override
  State<AdminRescueRequestsScreen> createState() =>
      _AdminRescueRequestsScreenState();
}

class _AdminRescueRequestsScreenState extends State<AdminRescueRequestsScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _all = const [];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _load();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    if (mounted) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }

    try {
      final rows = await AuthService.getRescueVerificationRequests();

      if (!mounted) return;
      setState(() => _all = rows);
    } on AuthServiceException catch (e) {
      if (!mounted) return;
      setState(() => _error = e.message);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = 'โหลดคำขอไม่สำเร็จ: $e');
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  List<Map<String, dynamic>> _forStatus(String status) {
    return _all.where((item) => item['status']?.toString() == status).toList();
  }

  Future<void> _openDocument(Map<String, dynamic> request) async {
    final path = request['document_path']?.toString();

    if (path == null || path.isEmpty) {
      _snack('คำขอนี้ไม่มีเอกสารแนบ');
      return;
    }

    try {
      final url = await AuthService.createRescueDocumentSignedUrl(path);

      final opened = await launchUrl(
        Uri.parse(url),
        mode: LaunchMode.platformDefault,
      );

      if (!opened) {
        _snack('ไม่สามารถเปิดเอกสารได้');
      }
    } on AuthServiceException catch (e) {
      _snack(e.message, error: true);
    } catch (_) {
      _snack('ไม่สามารถเปิดเอกสารได้', error: true);
    }
  }

  Future<void> _approve(Map<String, dynamic> request) async {
    final name = _fullName(request);

    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        icon: const Icon(Icons.verified_user_outlined, color: Colors.green),
        title: const Text('อนุมัติหน่วยกู้ภัย'),
        content: Text(
          'ยืนยันอนุมัติ $name เป็นหน่วยกู้ภัยหรือไม่?\n\n'
          'หลังอนุมัติ ระบบจะเปลี่ยน role เป็น rescuer',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('ยกเลิก'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('อนุมัติ'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    try {
      await AuthService.reviewRescueRequest(
        requestId: request['id'].toString(),
        approve: true,
      );

      _snack('อนุมัติ $name เป็นหน่วยกู้ภัยแล้ว');
      await _load();
    } on AuthServiceException catch (e) {
      _snack(e.message, error: true);
    } catch (e) {
      _snack('อนุมัติไม่สำเร็จ: $e', error: true);
    }
  }

  Future<void> _reject(Map<String, dynamic> request) async {
    final reason = TextEditingController();

    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        icon: const Icon(Icons.cancel_outlined, color: AppColors.error),
        title: const Text('ปฏิเสธคำขอ'),
        content: TextField(
          controller: reason,
          autofocus: true,
          minLines: 3,
          maxLines: 5,
          decoration: const InputDecoration(
            labelText: 'เหตุผลที่ปฏิเสธ *',
            hintText: 'เช่น เอกสารไม่ชัดเจน หรือข้อมูลไม่ตรงกัน',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('ยกเลิก'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.error),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('ปฏิเสธ'),
          ),
        ],
      ),
    );

    final reasonText = reason.text.trim();
    reason.dispose();

    if (confirm != true) return;

    if (reasonText.isEmpty) {
      _snack('กรุณาระบุเหตุผลที่ปฏิเสธ', error: true);
      return;
    }

    try {
      await AuthService.reviewRescueRequest(
        requestId: request['id'].toString(),
        approve: false,
        rejectionReason: reasonText,
      );

      _snack('ปฏิเสธคำขอแล้ว');
      await _load();
    } on AuthServiceException catch (e) {
      _snack(e.message, error: true);
    } catch (e) {
      _snack('ปฏิเสธคำขอไม่สำเร็จ: $e', error: true);
    }
  }

  Future<void> _revoke(Map<String, dynamic> request) async {
    final userId = request['user_id']?.toString();
    if (userId == null || userId.isEmpty) return;

    final name = _fullName(request);

    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('เพิกถอนสิทธิ์หน่วยกู้ภัย'),
        content: Text('ต้องการเปลี่ยน $name กลับเป็นผู้ใช้ทั่วไปหรือไม่?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('ยกเลิก'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.error),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('เพิกถอนสิทธิ์'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    try {
      await AuthService.revokeRescuer(userId);
      _snack('เพิกถอนสิทธิ์หน่วยกู้ภัยแล้ว');
      await _load();
    } on AuthServiceException catch (e) {
      _snack(e.message, error: true);
    }
  }

  String _fullName(Map<String, dynamic> request) {
    final profile = request['profile'];

    if (profile is Map) {
      final first = profile['first_name']?.toString() ?? '';
      final last = profile['last_name']?.toString() ?? '';
      final name = '$first $last'.trim();
      if (name.isNotEmpty) return name;
    }

    return request['user_id']?.toString() ?? 'ไม่ทราบชื่อ';
  }

  void _snack(String text, {bool error = false}) {
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
    final pending = _forStatus('pending');
    final approved = _forStatus('approved');
    final rejected = _forStatus('rejected');

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'จัดการหน่วยกู้ภัย',
          style: TextStyle(fontWeight: FontWeight.w900),
        ),
        actions: [
          IconButton(
            tooltip: 'รีเฟรช',
            onPressed: _loading ? null : _load,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          tabs: [
            Tab(text: 'รอตรวจ (${pending.length})'),
            Tab(text: 'อนุมัติ (${approved.length})'),
            Tab(text: 'ปฏิเสธ (${rejected.length})'),
          ],
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
          ? _ErrorView(message: _error!, onRetry: _load)
          : TabBarView(
              controller: _tabController,
              children: [
                _RequestList(
                  requests: pending,
                  emptyText: 'ไม่มีคำขอที่รอตรวจสอบ',
                  onDocument: _openDocument,
                  onApprove: _approve,
                  onReject: _reject,
                ),
                _RequestList(
                  requests: approved,
                  emptyText: 'ยังไม่มีคำขอที่อนุมัติ',
                  onDocument: _openDocument,
                  onRevoke: _revoke,
                ),
                _RequestList(
                  requests: rejected,
                  emptyText: 'ยังไม่มีคำขอที่ปฏิเสธ',
                  onDocument: _openDocument,
                ),
              ],
            ),
    );
  }
}

class _RequestList extends StatelessWidget {
  const _RequestList({
    required this.requests,
    required this.emptyText,
    required this.onDocument,
    this.onApprove,
    this.onReject,
    this.onRevoke,
  });

  final List<Map<String, dynamic>> requests;
  final String emptyText;
  final Future<void> Function(Map<String, dynamic>) onDocument;
  final Future<void> Function(Map<String, dynamic>)? onApprove;
  final Future<void> Function(Map<String, dynamic>)? onReject;
  final Future<void> Function(Map<String, dynamic>)? onRevoke;

  @override
  Widget build(BuildContext context) {
    if (requests.isEmpty) {
      return Center(
        child: Text(emptyText, style: const TextStyle(color: AppColors.muted)),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 30),
      itemCount: requests.length,
      separatorBuilder: (context, index) => const SizedBox(height: 12),
      itemBuilder: (context, index) {
        final request = requests[index];

        return _RequestCard(
          request: request,
          onDocument: () => onDocument(request),
          onApprove: onApprove == null ? null : () => onApprove!(request),
          onReject: onReject == null ? null : () => onReject!(request),
          onRevoke: onRevoke == null ? null : () => onRevoke!(request),
        );
      },
    );
  }
}

class _RequestCard extends StatelessWidget {
  const _RequestCard({
    required this.request,
    required this.onDocument,
    this.onApprove,
    this.onReject,
    this.onRevoke,
  });

  final Map<String, dynamic> request;
  final VoidCallback onDocument;
  final VoidCallback? onApprove;
  final VoidCallback? onReject;
  final VoidCallback? onRevoke;

  String get _name {
    final profile = request['profile'];

    if (profile is Map) {
      final first = profile['first_name']?.toString() ?? '';
      final last = profile['last_name']?.toString() ?? '';
      final value = '$first $last'.trim();
      if (value.isNotEmpty) return value;
    }

    return 'ไม่ทราบชื่อ';
  }

  String _dateText(dynamic value) {
    if (value == null) return '-';

    final date = DateTime.tryParse(value.toString());
    if (date == null) return value.toString();

    final local = date.toLocal();
    String two(int n) => n.toString().padLeft(2, '0');

    return '${two(local.day)}/${two(local.month)}/${local.year} '
        '${two(local.hour)}:${two(local.minute)}';
  }

  @override
  Widget build(BuildContext context) {
    final documentPath = request['document_path']?.toString();
    final role = request['current_role']?.toString() ?? 'user';

    return Container(
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            _name,
            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w900),
          ),
          Text(
            'role ปัจจุบัน: $role',
            style: const TextStyle(color: AppColors.muted, fontSize: 12),
          ),
          const SizedBox(height: 14),
          _DataLine(
            label: 'หน่วยงาน',
            value: request['organization_name']?.toString() ?? '-',
          ),
          _DataLine(
            label: 'รหัสเจ้าหน้าที่',
            value: request['personnel_id']?.toString() ?? '-',
          ),
          _DataLine(
            label: 'ส่งเมื่อ',
            value: _dateText(request['submitted_at']),
          ),
          if ((request['note']?.toString().trim().isNotEmpty ?? false))
            _DataLine(label: 'หมายเหตุ', value: request['note'].toString()),
          if ((request['rejection_reason']?.toString().trim().isNotEmpty ??
              false))
            _DataLine(
              label: 'เหตุผลปฏิเสธ',
              value: request['rejection_reason'].toString(),
            ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: documentPath == null || documentPath.isEmpty
                ? null
                : onDocument,
            icon: const Icon(Icons.description_outlined),
            label: Text(
              documentPath == null || documentPath.isEmpty
                  ? 'ไม่มีเอกสารแนบ'
                  : 'เปิดเอกสารยืนยัน',
            ),
          ),
          if (onApprove != null || onReject != null) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                if (onReject != null)
                  Expanded(
                    child: OutlinedButton(
                      onPressed: onReject,
                      child: const Text('ปฏิเสธ'),
                    ),
                  ),
                if (onReject != null && onApprove != null)
                  const SizedBox(width: 8),
                if (onApprove != null)
                  Expanded(
                    child: FilledButton(
                      onPressed: onApprove,
                      child: const Text('อนุมัติ'),
                    ),
                  ),
              ],
            ),
          ],
          if (onRevoke != null && role == 'rescuer') ...[
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: onRevoke,
              icon: const Icon(Icons.block_rounded),
              label: const Text('เพิกถอนสิทธิ์หน่วยกู้ภัย'),
            ),
          ],
        ],
      ),
    );
  }
}

class _DataLine extends StatelessWidget {
  const _DataLine({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 7),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 104,
            child: Text(
              label,
              style: const TextStyle(color: AppColors.muted, fontSize: 12),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.error_outline_rounded,
              color: AppColors.error,
              size: 52,
            ),
            const SizedBox(height: 12),
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('ลองใหม่'),
            ),
          ],
        ),
      ),
    );
  }
}
