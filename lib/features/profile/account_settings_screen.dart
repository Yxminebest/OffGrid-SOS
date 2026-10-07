import 'package:flutter/material.dart';

import '../../app/theme.dart';
import '../../models/user.dart';
import '../../services/auth_service.dart';
import '../../widgets/password_strength_indicator.dart';

class AccountSettingsScreen extends StatefulWidget {
  const AccountSettingsScreen({
    super.key,
    required this.user,
    required this.onUpdated,
    required this.onDeleted,
  });

  final AppUser user;
  final ValueChanged<AppUser> onUpdated;
  final Future<void> Function() onDeleted;

  @override
  State<AccountSettingsScreen> createState() => _AccountSettingsScreenState();
}

class _AccountSettingsScreenState extends State<AccountSettingsScreen> {
  late AppUser _current;

  late final TextEditingController _firstName;
  late final TextEditingController _lastName;
  late final TextEditingController _phone;

  final _newEmail = TextEditingController();
  final _emailCurrentPassword = TextEditingController();

  final _currentPassword = TextEditingController();
  final _newPassword = TextEditingController();
  final _confirmPassword = TextEditingController();

  bool _busy = false;

  bool _hideEmailPassword = true;
  bool _hideCurrentPassword = true;
  bool _hideNewPassword = true;
  bool _hideConfirmPassword = true;

  String? _pendingEmail;

  @override
  void initState() {
    super.initState();

    _current = widget.user;

    _firstName = TextEditingController(text: widget.user.firstName);

    _lastName = TextEditingController(text: widget.user.lastName);

    _phone = TextEditingController(text: widget.user.phone ?? '');
  }

  @override
  void dispose() {
    _firstName.dispose();
    _lastName.dispose();
    _phone.dispose();

    _newEmail.dispose();
    _emailCurrentPassword.dispose();

    _currentPassword.dispose();
    _newPassword.dispose();
    _confirmPassword.dispose();

    super.dispose();
  }

  void _show(String message, {bool error = false}) {
    if (!mounted) return;

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          backgroundColor: error ? AppColors.error : null,
          content: Text(message),
        ),
      );
  }

  Future<void> _reload() async {
    if (_busy) return;

    setState(() {
      _busy = true;
    });

    try {
      final latest = await AuthService.currentMember();

      if (!mounted) return;

      setState(() {
        _current = latest;

        _firstName.text = latest.firstName;
        _lastName.text = latest.lastName;
        _phone.text = latest.phone ?? '';
      });

      widget.onUpdated(latest);

      _show('อ่านข้อมูลบัญชีจากฐานข้อมูลสำเร็จ');
    } on AuthServiceException catch (e) {
      _show(e.message, error: true);
    } catch (_) {
      _show('อ่านข้อมูลบัญชีไม่สำเร็จ กรุณาลองอีกครั้ง', error: true);
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
        });
      }
    }
  }

  Future<void> _saveProfile() async {
    if (_busy) return;

    setState(() {
      _busy = true;
    });

    try {
      final updated = await AuthService.updateProfile(
        firstName: _firstName.text,
        lastName: _lastName.text,
        phone: _phone.text,
      );

      if (!mounted) return;

      setState(() {
        _current = updated;
      });

      widget.onUpdated(updated);

      _show('บันทึกชื่อและข้อมูลติดต่อสำเร็จ');
    } on AuthServiceException catch (e) {
      _show(e.message, error: true);
    } catch (_) {
      _show('บันทึกข้อมูลบัญชีไม่สำเร็จ กรุณาลองอีกครั้ง', error: true);
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
        });
      }
    }
  }

  Future<void> _changeEmail() async {
    if (_busy) return;

    final newEmail = _newEmail.text.trim().toLowerCase();

    if (!AuthService.isValidEmail(newEmail)) {
      _show('กรุณากรอกอีเมลใหม่ให้ถูกต้อง', error: true);
      return;
    }

    if (_emailCurrentPassword.text.isEmpty) {
      _show('กรุณากรอกรหัสผ่านปัจจุบันเพื่อยืนยันการเปลี่ยนอีเมล', error: true);
      return;
    }

    setState(() {
      _busy = true;
    });

    try {
      await AuthService.requestEmailChange(
        newEmail: newEmail,
        currentPassword: _emailCurrentPassword.text,
      );

      if (!mounted) return;

      setState(() {
        _pendingEmail = newEmail;
      });

      _newEmail.clear();
      _emailCurrentPassword.clear();

      _show(
        'ส่งคำขอเปลี่ยนอีเมลแล้ว '
        'กรุณาตรวจอีเมลเดิมและอีเมลใหม่เพื่อยืนยัน',
      );
    } on AuthServiceException catch (e) {
      _show(e.message, error: true);
    } catch (_) {
      _show('เปลี่ยนอีเมลไม่สำเร็จ กรุณาลองอีกครั้ง', error: true);
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
        });
      }
    }
  }

  Future<void> _changePassword() async {
    if (_busy) return;

    if (_currentPassword.text.isEmpty) {
      _show('กรุณากรอกรหัสผ่านปัจจุบัน', error: true);
      return;
    }

    if (_newPassword.text != _confirmPassword.text) {
      _show('รหัสผ่านใหม่และยืนยันรหัสผ่านไม่ตรงกัน', error: true);
      return;
    }

    final passwordError = AuthService.validatePassword(_newPassword.text);

    if (passwordError != null) {
      _show(passwordError, error: true);
      return;
    }

    setState(() {
      _busy = true;
    });

    try {
      await AuthService.changePassword(
        currentPassword: _currentPassword.text,
        newPassword: _newPassword.text,
      );

      if (!mounted) return;

      _currentPassword.clear();
      _newPassword.clear();
      _confirmPassword.clear();

      setState(() {});

      _show('เปลี่ยนรหัสผ่านสำเร็จ');
    } on AuthServiceException catch (e) {
      _show(e.message, error: true);
    } catch (_) {
      _show('เปลี่ยนรหัสผ่านไม่สำเร็จ กรุณาลองอีกครั้ง', error: true);
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
        });
      }
    }
  }

  Future<void> _deleteAccount() async {
    if (_busy) return;

    final confirm = TextEditingController();
    final password = TextEditingController();

    var hidePassword = true;

    final deleteRequest = await showDialog<_DeleteAccountConfirmation>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (dialogContext, setDialogState) {
            return AlertDialog(
              title: const Text('ลบบัญชีถาวร'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'การลบบัญชีไม่สามารถย้อนกลับได้ '
                      'ระบบจะลบข้อมูลสมาชิก ไฟล์ที่เป็นของบัญชี '
                      'และข้อมูล Local ของบัญชีนี้บนเครื่องนี้',
                    ),
                    const SizedBox(height: 14),
                    const Text(
                      'เพื่อความปลอดภัย '
                      'กรุณากรอกรหัสผ่านปัจจุบันและพิมพ์ DELETE',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: password,
                      autofocus: true,
                      obscureText: hidePassword,
                      decoration: InputDecoration(
                        labelText: 'รหัสผ่านปัจจุบัน',
                        suffixIcon: IconButton(
                          onPressed: () {
                            setDialogState(() {
                              hidePassword = !hidePassword;
                            });
                          },
                          icon: Icon(
                            hidePassword
                                ? Icons.visibility_outlined
                                : Icons.visibility_off_outlined,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: confirm,
                      decoration: const InputDecoration(
                        labelText: 'พิมพ์ DELETE',
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () {
                    Navigator.pop(dialogContext);
                  },
                  child: const Text('ยกเลิก'),
                ),
                FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.error,
                  ),
                  onPressed: () {
                    Navigator.pop(
                      dialogContext,
                      _DeleteAccountConfirmation(
                        currentPassword: password.text,
                        typedDelete: confirm.text.trim(),
                      ),
                    );
                  },
                  child: const Text('ลบบัญชีถาวร'),
                ),
              ],
            );
          },
        );
      },
    );

    confirm.dispose();
    password.dispose();

    if (deleteRequest == null) {
      return;
    }

    if (deleteRequest.typedDelete != 'DELETE') {
      _show('กรุณาพิมพ์ DELETE ให้ถูกต้อง', error: true);
      return;
    }

    if (deleteRequest.currentPassword.isEmpty) {
      _show('กรุณากรอกรหัสผ่านปัจจุบัน', error: true);
      return;
    }

    if (!mounted) return;

    /*
     * เก็บ NavigatorState ไว้ก่อนเริ่ม async operation
     *
     * เหตุผล:
     * หลัง delete สำเร็จ onDeleted() อาจเปลี่ยน Auth State
     * และทำให้ AccountSettingsScreen ถูก rebuild/dispose
     * เราจึงไม่ควรเรียก Navigator.of(context) หลังจากนั้นแบบตรง ๆ
     */
    final rootNavigator = Navigator.of(context, rootNavigator: true);

    setState(() {
      _busy = true;
    });

    try {
      await AuthService.deleteMyAccount(
        currentPassword: deleteRequest.currentPassword,
      );

      /*
       * แจ้ง App/Main ว่าบัญชีถูกลบแล้ว
       * เพื่อให้ user state ถูก reset
       */
      await widget.onDeleted();

      /*
       * ถ้า Navigator เดิมยังอยู่
       * ให้ล้างหน้าที่ถูก push ค้างไว้ทั้งหมด
       * เช่น:
       *
       * Home
       *   → Profile
       *     → AccountSettings
       *
       * กลับไป route แรก
       *
       * เมื่อ auth state เป็น null แล้ว
       * root UI จะกลายเป็น Login
       */
      if (rootNavigator.mounted) {
        rootNavigator.popUntil((route) => route.isFirst);
      }
    } on AuthServiceException catch (e) {
      _show(e.message, error: true);
    } catch (_) {
      _show('ลบบัญชีไม่สำเร็จ กรุณาลองอีกครั้ง', error: true);
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
        });
      }
    }
  }

  Widget _section({
    required String title,
    required String subtitle,
    required IconData icon,
    required List<Widget> children,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, color: AppColors.info),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        color: AppColors.muted,
                        fontSize: 12,
                        height: 1.4,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          ...children,
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final currentEmail = _current.email ?? '-';

    return Scaffold(
      appBar: AppBar(title: const Text('จัดการบัญชี')),
      body: SafeArea(
        child: ListView(
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 32),
          children: [
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: AppColors.border),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Account CRUD',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'Create = สมัครสมาชิก • '
                    'Read = โหลดข้อมูลบัญชี • '
                    'Update = แก้ไขข้อมูล • '
                    'Delete = ลบบัญชีถาวร',
                    style: TextStyle(color: AppColors.muted, height: 1.45),
                  ),
                  const SizedBox(height: 10),
                  SelectableText(
                    'User ID: ${_current.id}',
                    style: const TextStyle(
                      fontSize: 11,
                      color: AppColors.muted,
                    ),
                  ),
                  const SizedBox(height: 10),
                  OutlinedButton.icon(
                    onPressed: _busy ? null : _reload,
                    icon: const Icon(Icons.refresh_rounded),
                    label: const Text('อ่านข้อมูลจากฐานข้อมูลอีกครั้ง'),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18),

            // -------------------------------------------------
            // Personal information
            // -------------------------------------------------
            _section(
              title: 'ข้อมูลส่วนตัว',
              subtitle: 'แก้ชื่อจริง นามสกุล และเบอร์โทรศัพท์',
              icon: Icons.person_outline_rounded,
              children: [
                TextField(
                  controller: _firstName,
                  enabled: !_busy,
                  textInputAction: TextInputAction.next,
                  decoration: const InputDecoration(labelText: 'ชื่อจริง'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _lastName,
                  enabled: !_busy,
                  textInputAction: TextInputAction.next,
                  decoration: const InputDecoration(labelText: 'นามสกุล'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _phone,
                  enabled: !_busy,
                  keyboardType: TextInputType.phone,
                  textInputAction: TextInputAction.done,
                  decoration: const InputDecoration(labelText: 'เบอร์โทรศัพท์'),
                ),
                const SizedBox(height: 14),
                FilledButton.icon(
                  onPressed: _busy ? null : _saveProfile,
                  icon: const Icon(Icons.save_outlined),
                  label: const Text('บันทึกข้อมูลส่วนตัว'),
                ),
              ],
            ),

            const SizedBox(height: 16),

            // -------------------------------------------------
            // Change email
            // -------------------------------------------------
            _section(
              title: 'เปลี่ยนอีเมล',
              subtitle:
                  'เพื่อป้องกันการยึดบัญชี '
                  'ต้องยืนยันรหัสผ่านปัจจุบันก่อน',
              icon: Icons.alternate_email_rounded,
              children: [
                Text(
                  'อีเมลปัจจุบัน: $currentEmail',
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
                if (_pendingEmail != null) ...[
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: AppColors.pending.withValues(alpha: .10),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: AppColors.pending.withValues(alpha: .35),
                      ),
                    ),
                    child: Text(
                      'รอยืนยันอีเมลใหม่: '
                      '$_pendingEmail\n'
                      'กรุณาตรวจทั้งอีเมลเดิมและอีเมลใหม่',
                      style: const TextStyle(fontSize: 12, height: 1.4),
                    ),
                  ),
                ],
                const SizedBox(height: 12),
                TextField(
                  controller: _newEmail,
                  enabled: !_busy,
                  keyboardType: TextInputType.emailAddress,
                  textInputAction: TextInputAction.next,
                  autofillHints: const [AutofillHints.email],
                  decoration: const InputDecoration(labelText: 'อีเมลใหม่'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _emailCurrentPassword,
                  enabled: !_busy,
                  obscureText: _hideEmailPassword,
                  textInputAction: TextInputAction.done,
                  decoration: InputDecoration(
                    labelText: 'รหัสผ่านปัจจุบัน',
                    suffixIcon: IconButton(
                      onPressed: _busy
                          ? null
                          : () {
                              setState(() {
                                _hideEmailPassword = !_hideEmailPassword;
                              });
                            },
                      icon: Icon(
                        _hideEmailPassword
                            ? Icons.visibility_outlined
                            : Icons.visibility_off_outlined,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                OutlinedButton.icon(
                  onPressed: _busy ? null : _changeEmail,
                  icon: const Icon(Icons.mark_email_read_outlined),
                  label: const Text('ส่งคำขอเปลี่ยนอีเมล'),
                ),
              ],
            ),

            const SizedBox(height: 16),

            // -------------------------------------------------
            // Change password
            // -------------------------------------------------
            _section(
              title: 'เปลี่ยนรหัสผ่าน',
              subtitle:
                  'ต้องกรอกรหัสผ่านเดิมก่อนทุกครั้ง '
                  'แล้วจึงตั้งรหัสผ่านใหม่',
              icon: Icons.password_rounded,
              children: [
                TextField(
                  controller: _currentPassword,
                  enabled: !_busy,
                  obscureText: _hideCurrentPassword,
                  textInputAction: TextInputAction.next,
                  autofillHints: const [AutofillHints.password],
                  decoration: InputDecoration(
                    labelText: 'รหัสผ่านปัจจุบัน',
                    suffixIcon: IconButton(
                      onPressed: _busy
                          ? null
                          : () {
                              setState(() {
                                _hideCurrentPassword = !_hideCurrentPassword;
                              });
                            },
                      icon: Icon(
                        _hideCurrentPassword
                            ? Icons.visibility_outlined
                            : Icons.visibility_off_outlined,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _newPassword,
                  enabled: !_busy,
                  obscureText: _hideNewPassword,
                  textInputAction: TextInputAction.next,
                  autofillHints: const [AutofillHints.newPassword],
                  onChanged: (_) {
                    setState(() {});
                  },
                  decoration: InputDecoration(
                    labelText: 'รหัสผ่านใหม่',
                    suffixIcon: IconButton(
                      onPressed: _busy
                          ? null
                          : () {
                              setState(() {
                                _hideNewPassword = !_hideNewPassword;
                              });
                            },
                      icon: Icon(
                        _hideNewPassword
                            ? Icons.visibility_outlined
                            : Icons.visibility_off_outlined,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                PasswordStrengthIndicator(password: _newPassword.text),
                const SizedBox(height: 12),
                TextField(
                  controller: _confirmPassword,
                  enabled: !_busy,
                  obscureText: _hideConfirmPassword,
                  textInputAction: TextInputAction.done,
                  onChanged: (_) {
                    setState(() {});
                  },
                  decoration: InputDecoration(
                    labelText: 'ยืนยันรหัสผ่านใหม่',
                    errorText:
                        _confirmPassword.text.isNotEmpty &&
                            _newPassword.text != _confirmPassword.text
                        ? 'รหัสผ่านไม่ตรงกัน'
                        : null,
                    suffixIcon: IconButton(
                      onPressed: _busy
                          ? null
                          : () {
                              setState(() {
                                _hideConfirmPassword = !_hideConfirmPassword;
                              });
                            },
                      icon: Icon(
                        _hideConfirmPassword
                            ? Icons.visibility_outlined
                            : Icons.visibility_off_outlined,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                FilledButton.icon(
                  onPressed: _busy ? null : _changePassword,
                  icon: const Icon(Icons.lock_reset_rounded),
                  label: const Text('เปลี่ยนรหัสผ่าน'),
                ),
              ],
            ),

            const SizedBox(height: 28),

            const Divider(),

            const SizedBox(height: 10),

            // -------------------------------------------------
            // Danger zone
            // -------------------------------------------------
            const Text(
              'Danger zone',
              style: TextStyle(
                color: AppColors.error,
                fontSize: 18,
                fontWeight: FontWeight.w900,
              ),
            ),

            const SizedBox(height: 8),

            const Text(
              'การลบบัญชีเป็นการลบถาวร '
              'ต้องยืนยันด้วยรหัสผ่านปัจจุบันและคำว่า DELETE',
              style: TextStyle(color: AppColors.muted, height: 1.45),
            ),

            const SizedBox(height: 12),

            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(foregroundColor: AppColors.error),
              onPressed: _busy ? null : _deleteAccount,
              icon: const Icon(Icons.delete_forever_outlined),
              label: const Text('ลบบัญชีถาวร'),
            ),
          ],
        ),
      ),
    );
  }
}

class _DeleteAccountConfirmation {
  const _DeleteAccountConfirmation({
    required this.currentPassword,
    required this.typedDelete,
  });

  final String currentPassword;
  final String typedDelete;
}
