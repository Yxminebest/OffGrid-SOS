import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../app/theme.dart';
import '../../widgets/appearance_picker.dart';
import '../../widgets/page_header.dart';
import '../../widgets/app_card.dart';
import '../../services/app_notifications.dart';
import 'package:flutter/foundation.dart';
import 'package:permission_handler/permission_handler.dart';
import '../../models/user.dart';
import '../../services/auth_service.dart';
import '../admin/admin_rescue_requests_screen.dart';
import '../auth/rescue_verification_screen.dart';
import 'account_settings_screen.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key, required this.me, required this.onLogout});

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

    final mime =
        file.mimeType ??
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
        SnackBar(backgroundColor: AppColors.error, content: Text(message)),
      );
  }

  Future<void> _privacyInfo() => showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('ข้อมูลและความเป็นส่วนตัว'),
      content: const SingleChildScrollView(
        child: Text(
          'SOS ถูกบันทึกในอุปกรณ์ก่อนเสมอ บัญชีสมาชิกจะส่งข้อมูลขึ้นระบบเมื่อเชื่อมต่อได้\n\nเมื่อส่ง SOS ผ่าน Nearby ข้อความ ชื่อ และพิกัดที่คุณเลือกส่งจะถูกส่งให้อุปกรณ์ที่เชื่อมต่อ และอาจถูกส่งต่อในเครือข่าย\n\nข้อความ Nearby ยังไม่บันทึกถาวร การออกจากระบบจะหยุดการเชื่อมต่อ แต่ SOS และข้อมูลที่บันทึกไว้ในเครื่องยังอยู่สำหรับบัญชีเดิม',
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('เข้าใจแล้ว'),
        ),
      ],
    ),
  );

  Future<void> _logout() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(_me.isMember ? 'ออกจากระบบ?' : 'ออกจากโหมดผู้เยี่ยมชม?'),
        content: const Text(
          'Nearby จะหยุดการเชื่อมต่อ ข้อมูลที่บันทึกในเครื่องจะยังอยู่',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('อยู่หน้านี้'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('ออกจากระบบ'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _busy = true);
    try {
      await widget.onLogout();
    } catch (_) {
      if (mounted) _error('ออกจากระบบไม่สำเร็จ กรุณาลองอีกครั้ง');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final initial = _me.firstName.isEmpty
        ? '?'
        : _me.firstName.characters.first;
    final role = switch (_me.role) {
      AppRole.admin => 'ผู้ดูแลระบบ',
      AppRole.rescuer => 'หน่วยกู้ภัยที่ยืนยันแล้ว',
      AppRole.user => 'สมาชิก',
      AppRole.guest => 'ผู้เยี่ยมชม',
    };
    return SafeArea(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 760),
          child: RefreshIndicator(
            onRefresh: _refreshProfile,
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(22, 24, 22, 28),
              children: [
                PageHeader(
                  title: 'โปรไฟล์',
                  subtitle: 'บัญชีและการตั้งค่าของคุณ',
                  action: _me.isMember
                      ? IconButton(
                          tooltip: 'รีเฟรชโปรไฟล์',
                          onPressed: _busy ? null : _refreshProfile,
                          icon: const Icon(Icons.refresh_rounded),
                        )
                      : null,
                ),
                AppCard(
                  padding: const EdgeInsets.all(22),
                  child: Row(
                    children: [
                      Semantics(
                        button: _me.isMember,
                        label: 'เปลี่ยนรูปโปรไฟล์',
                        child: InkWell(
                          onTap: _busy || !_me.isMember ? null : _changePhoto,
                          borderRadius: BorderRadius.circular(32),
                          child: Stack(
                            children: [
                              CircleAvatar(
                                radius: 30,
                                backgroundColor: context.colors.info.withValues(
                                  alpha: .12,
                                ),
                                foregroundImage: _me.photoUrl == null
                                    ? null
                                    : NetworkImage(_me.photoUrl!),
                                child: Text(
                                  initial,
                                  style: TextStyle(
                                    color: context.colors.info,
                                    fontSize: 24,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                              if (_me.isMember)
                                Positioned(
                                  right: 0,
                                  bottom: 0,
                                  child: Container(
                                    padding: const EdgeInsets.all(4),
                                    decoration: BoxDecoration(
                                      color: context.colors.surface,
                                      shape: BoxShape.circle,
                                      border: Border.all(
                                        color: context.colors.border,
                                      ),
                                    ),
                                    child: Icon(
                                      Icons.camera_alt_outlined,
                                      size: 13,
                                      color: context.colors.info,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _me.fullName,
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                            if (_me.email != null)
                              Text(
                                _me.email!,
                                style: TextStyle(
                                  color: context.colors.muted,
                                  fontSize: 12,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            const SizedBox(height: 8),
                            Text(
                              role,
                              style: TextStyle(
                                color: context.colors.info,
                                fontWeight: FontWeight.w600,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 26),
                const AppearancePicker(),
                const SizedBox(height: 24),
                Text(
                  'บัญชีและการใช้งาน',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 12),
                AppCard(
                  padding: EdgeInsets.zero,
                  child: Column(
                    children: [
                      if (_me.isMember)
                        ListTile(
                          leading: const Icon(Icons.manage_accounts_outlined),
                          title: const Text('จัดการบัญชี'),
                          subtitle: const Text(
                            'ข้อมูลส่วนตัว อีเมล และรหัสผ่าน',
                          ),
                          trailing: const Icon(Icons.chevron_right_rounded),
                          onTap: _busy
                              ? null
                              : () async {
                                  await Navigator.of(context).push(
                                    MaterialPageRoute<void>(
                                      builder: (_) => AccountSettingsScreen(
                                        user: _me,
                                        onUpdated: (updated) {
                                          if (mounted) {
                                            setState(() => _me = updated);
                                          }
                                        },
                                        onDeleted: widget.onLogout,
                                      ),
                                    ),
                                  );
                                  if (mounted && _me.isMember) {
                                    await _refreshProfile();
                                  }
                                },
                        ),
                      if (_me.isMember && _me.role == AppRole.user)
                        ListTile(
                          leading: const Icon(Icons.health_and_safety_outlined),
                          title: const Text('ยืนยันสถานะหน่วยกู้ภัย'),
                          subtitle: const Text(
                            'ส่งข้อมูลให้ผู้ดูแลระบบตรวจสอบ',
                          ),
                          trailing: const Icon(Icons.chevron_right_rounded),
                          onTap: () => Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => const RescueVerificationScreen(),
                            ),
                          ),
                        ),
                      if (_me.role == AppRole.admin)
                        ListTile(
                          leading: const Icon(
                            Icons.admin_panel_settings_outlined,
                          ),
                          title: const Text('จัดการหน่วยกู้ภัย'),
                          subtitle: const Text('ตรวจสอบและอนุมัติคำขอ'),
                          trailing: const Icon(Icons.chevron_right_rounded),
                          onTap: () async {
                            await Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) =>
                                    const AdminRescueRequestsScreen(),
                              ),
                            );
                            if (mounted) await _refreshProfile();
                          },
                        ),
                      if (!kIsWeb) ...[
                        ValueListenableBuilder<bool>(
                          valueListenable: AppNotifications.instance.enabled,
                          builder: (context, enabled, _) => ListTile(
                            leading: const Icon(Icons.notifications_outlined),
                            title: const Text('การแจ้งเตือนข้อความ'),
                            subtitle: Text(
                              enabled ? 'เปิดอยู่' : 'ปิดอยู่ · แตะเพื่ออนุญาต',
                            ),
                            onTap: () async {
                              if (!await AppNotifications.instance.request()) {
                                await openAppSettings();
                              }
                            },
                          ),
                        ),
                        ValueListenableBuilder<bool>(
                          valueListenable: AppNotifications.instance.background,
                          builder: (context, enabled, _) => SwitchListTile(
                            secondary: const Icon(
                              Icons.mark_chat_unread_outlined,
                            ),
                            title: const Text('รับข้อความเบื้องหลัง'),
                            subtitle: const Text('มีแถบสถานะขณะบริการทำงาน'),
                            value: enabled,
                            onChanged: (v) =>
                                AppNotifications.instance.setBackground(v),
                          ),
                        ),
                      ],
                      if (!kIsWeb)
                        ListTile(
                          leading: const Icon(Icons.tune_rounded),
                          title: const Text('สิทธิ์ของแอป'),
                          subtitle: const Text(
                            'จัดการตำแหน่งและอุปกรณ์ใกล้เคียง',
                          ),
                          trailing: const Icon(
                            Icons.open_in_new_rounded,
                            size: 18,
                          ),
                          onTap: openAppSettings,
                        ),
                      ListTile(
                        leading: const Icon(Icons.privacy_tip_outlined),
                        title: const Text('ข้อมูลและความเป็นส่วนตัว'),
                        subtitle: const Text(
                          'เข้าใจวิธีเก็บและส่งข้อมูลของคุณ',
                        ),
                        trailing: const Icon(Icons.chevron_right_rounded),
                        onTap: _privacyInfo,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                OutlinedButton.icon(
                  onPressed: _busy ? null : _logout,
                  icon: const Icon(Icons.logout_rounded),
                  label: Text(
                    _me.isMember ? 'ออกจากระบบ' : 'ออกจากโหมดผู้เยี่ยมชม',
                  ),
                ),
                const SizedBox(height: 20),
                Text(
                  'Offgrid SOS · อยู่ใกล้ แม้ไกลสัญญาณ',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: context.colors.muted, fontSize: 12),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
