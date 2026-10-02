import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../app/theme.dart';
import '../../models/user.dart';
import '../../services/auth_service.dart';
import '../admin/admin_rescue_requests_screen.dart';
import '../auth/rescue_verification_screen.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({
    super.key,
    required this.me,
    required this.onLogout,
  });

  final AppUser me;
  final Future<void> Function() onLogout;

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  late AppUser _me;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _me = widget.me;
  }

  String get _roleLabel => switch (_me.role) {
        AppRole.admin => 'ADMIN',
        AppRole.rescuer => 'RESCUE',
        AppRole.user => 'USER',
        AppRole.guest => 'GUEST',
      };

  Future<void> _refreshProfile() async {
    if (!_me.isMember) return;

    setState(() => _busy = true);

    try {
      final latest = await AuthService.currentMember();

      if (!mounted) return;
      setState(() => _me = latest);
    } on AuthServiceException catch (e) {
      if (!mounted) return;
      _error(e.message);
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _changePhoto() async {
    if (!_me.isMember) return;

    final file = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      maxWidth: 1200,
      imageQuality: 82,
    );

    if (file == null) return;

    final Uint8List bytes = await file.readAsBytes();
    final extension = file.name.contains('.')
        ? file.name.split('.').last.toLowerCase()
        : 'jpg';

    final mime = file.mimeType ??
        (extension == 'png'
            ? 'image/png'
            : extension == 'webp'
                ? 'image/webp'
                : 'image/jpeg');

    setState(() => _busy = true);

    try {
      final updated = await AuthService.uploadAvatar(
        bytes: bytes,
        mimeType: mime,
        extension: extension,
      );

      if (!mounted) return;
      setState(() => _me = updated);
    } on AuthServiceException catch (e) {
      if (!mounted) return;
      _error(e.message);
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  void _error(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          backgroundColor: AppColors.error,
          content: Text(message),
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    final initials = [
      if (_me.firstName.isNotEmpty) _me.firstName[0],
      if (_me.lastName.isNotEmpty) _me.lastName[0],
    ].join().toUpperCase();

    return SafeArea(
      child: RefreshIndicator(
        onRefresh: _refreshProfile,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 30),
          children: [
            Row(
              children: [
                const Expanded(
                  child: Text(
                    'โปรไฟล์',
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'รีเฟรช',
                  onPressed:
                      _busy || !_me.isMember ? null : _refreshProfile,
                  icon: const Icon(Icons.refresh_rounded),
                ),
              ],
            ),
            const SizedBox(height: 24),
            Center(
              child: InkWell(
                onTap:
                    _busy || !_me.isMember ? null : _changePhoto,
                borderRadius: BorderRadius.circular(60),
                child: CircleAvatar(
                  radius: 52,
                  backgroundColor: AppColors.surface,
                  foregroundImage: _me.photoUrl == null
                      ? null
                      : NetworkImage(_me.photoUrl!),
                  child: _me.photoUrl == null
                      ? Text(
                          initials.isEmpty ? '👤' : initials,
                          style: const TextStyle(
                            fontSize: 28,
                            fontWeight: FontWeight.w900,
                          ),
                        )
                      : null,
                ),
              ),
            ),
            const SizedBox(height: 14),
            Text(
              _me.fullName,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.w900,
              ),
            ),
            if (_me.email != null) ...[
              const SizedBox(height: 4),
              Text(
                _me.email!,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: AppColors.muted,
                ),
              ),
            ],
            const SizedBox(height: 12),
            Center(
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  Chip(label: Text(_roleLabel)),
                  if (_me.isMember)
                    Chip(
                      label: Text(
                        _me.emailVerified
                            ? 'ยืนยันอีเมลแล้ว'
                            : 'ยังไม่ยืนยันอีเมล',
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            if (_me.isMember && _me.role == AppRole.user)
              ListTile(
                leading: const Icon(
                  Icons.health_and_safety_outlined,
                ),
                title: const Text('ยืนยันสถานะหน่วยกู้ภัย'),
                subtitle: const Text(
                  'ส่งข้อมูลและเอกสารให้ Admin ตรวจสอบ',
                ),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) =>
                          const RescueVerificationScreen(),
                    ),
                  );
                },
              ),
            if (_me.isMember && _me.role == AppRole.admin)
              ListTile(
                leading: const Icon(
                  Icons.admin_panel_settings_outlined,
                ),
                title: const Text('จัดการหน่วยกู้ภัย'),
                subtitle: const Text(
                  'ตรวจสอบ อนุมัติ หรือปฏิเสธคำขอ',
                ),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () async {
                  await Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) =>
                          const AdminRescueRequestsScreen(),
                    ),
                  );

                  if (mounted) {
                    await _refreshProfile();
                  }
                },
              ),
            const Divider(height: 30),
            ListTile(
              leading: const Icon(Icons.notifications_outlined),
              title: const Text('การแจ้งเตือน'),
            ),
            ListTile(
              leading: const Icon(Icons.location_on_outlined),
              title: const Text('ตำแหน่ง'),
            ),
            ListTile(
              leading: const Icon(Icons.privacy_tip_outlined),
              title: const Text('ความเป็นส่วนตัว'),
            ),
            const SizedBox(height: 20),
            OutlinedButton.icon(
              onPressed: _busy ? null : widget.onLogout,
              icon: const Icon(Icons.logout_rounded),
              label: Text(
                _me.isMember
                    ? 'ออกจากระบบ'
                    : 'ออกจากโหมด Guest',
              ),
            ),
          ],
        ),
      ),
    );
  }
}
