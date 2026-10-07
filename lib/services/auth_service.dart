import 'dart:typed_data';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../app/supabase_config.dart';
import '../data/local/local_database.dart';
import '../models/user.dart';

class AuthService {
  static const FlutterSecureStorage _store = FlutterSecureStorage();

  static SupabaseClient get _supabase => Supabase.instance.client;

  static Stream<AuthState> get authStateChanges =>
      _supabase.auth.onAuthStateChange;

  static User? get currentAuthUser => _supabase.auth.currentUser;

  static bool isValidEmail(String value) {
    final email = value.trim().toLowerCase();
    return RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(email);
  }

  static String? validatePassword(String password) {
    if (password.length < 8) {
      return 'รหัสผ่านต้องมีอย่างน้อย 8 ตัวอักษร';
    }
    if (password.length > 128) {
      return 'รหัสผ่านต้องไม่เกิน 128 ตัวอักษร';
    }
    return null;
  }

  static Future<String> _getOrCreateDeviceId() async {
    final existing = await _store.read(key: 'deviceId');
    if (existing != null && existing.isNotEmpty) return existing;

    final id = const Uuid().v4();
    await _store.write(key: 'deviceId', value: id);
    return id;
  }

  static Future<AppUser> createGuest(String first, String last) async {
    final firstName = first.trim();
    final lastName = last.trim();

    if (firstName.isEmpty || lastName.isEmpty) {
      throw const AuthServiceException('กรุณากรอกชื่อจริงและนามสกุล');
    }

    final deviceId = await _getOrCreateDeviceId();
    await _store.write(key: 'firstName', value: firstName);
    await _store.write(key: 'lastName', value: lastName);
    await _store.write(key: 'isMember', value: '0');
    await _store.delete(key: 'email');
    await _store.delete(key: 'supabaseUserId');
    await _store.delete(key: 'role');

    return AppUser(
      id: deviceId,
      firstName: firstName,
      lastName: lastName,
      isMember: false,
      role: AppRole.guest,
    );
  }

  static Future<PendingRegistration> registerMember({
    required String email,
    required String password,
    required String firstName,
    required String lastName,
    String? phone,
  }) async {
    final cleanEmail = email.trim().toLowerCase();
    final cleanFirst = firstName.trim();
    final cleanLast = lastName.trim();
    final cleanPhone = phone?.trim();

    if (cleanFirst.isEmpty) {
      throw const AuthServiceException('กรุณากรอกชื่อจริง');
    }
    if (cleanLast.isEmpty) {
      throw const AuthServiceException('กรุณากรอกนามสกุล');
    }
    if (!isValidEmail(cleanEmail)) {
      throw const AuthServiceException('กรุณากรอกอีเมลให้ถูกต้อง');
    }
    final passwordError = validatePassword(password);
    if (passwordError != null) {
      throw AuthServiceException(passwordError);
    }

    try {
      final response = await _supabase.auth.signUp(
        email: cleanEmail,
        password: password,
        emailRedirectTo: SupabaseConfig.emailRedirectTo,
        data: {
          'first_name': cleanFirst,
          'last_name': cleanLast,
          'phone': cleanPhone,
        },
      );

      final user = response.user;
      if (user == null) {
        throw const AuthServiceException('ไม่สามารถสร้างบัญชีได้');
      }

      return PendingRegistration(email: cleanEmail, userId: user.id);
    } on AuthException catch (e) {
      throw AuthServiceException(_authMessage(e.message));
    } catch (e) {
      if (e is AuthServiceException) rethrow;
      throw AuthServiceException(
        _unexpectedAuthMessage(
          e,
          fallback: 'สมัครสมาชิกไม่สำเร็จ กรุณาลองอีกครั้ง',
        ),
      );
    }
  }

  static Future<AppUser> signInMember({
    required String email,
    required String password,
  }) async {
    final cleanEmail = email.trim().toLowerCase();

    if (cleanEmail.isEmpty || password.isEmpty) {
      throw const AuthServiceException('กรุณากรอกอีเมลและรหัสผ่าน');
    }

    try {
      final response = await _supabase.auth.signInWithPassword(
        email: cleanEmail,
        password: password,
      );

      if (response.user == null || response.session == null) {
        throw const AuthServiceException('ไม่สามารถเข้าสู่ระบบได้');
      }

      return _loadSignedInMember();
    } on AuthException catch (e) {
      throw AuthServiceException(_authMessage(e.message));
    } catch (e) {
      throw AuthServiceException(
        _unexpectedAuthMessage(
          e,
          fallback: 'ไม่สามารถเข้าสู่ระบบได้ กรุณาลองอีกครั้ง',
        ),
      );
    }
  }

  static bool get isCurrentEmailVerified {
    final user = _supabase.auth.currentUser;
    return user?.emailConfirmedAt != null;
  }

  static Future<void> resendVerificationEmail(String email) async {
    final cleanEmail = email.trim().toLowerCase();

    if (!isValidEmail(cleanEmail)) {
      throw const AuthServiceException('กรุณากรอกอีเมลให้ถูกต้อง');
    }

    try {
      await _supabase.auth.resend(
        type: OtpType.signup,
        email: cleanEmail,
        emailRedirectTo: SupabaseConfig.emailRedirectTo,
      );
    } on AuthException catch (e) {
      throw AuthServiceException(_authMessage(e.message));
    } catch (e) {
      throw AuthServiceException(
        _unexpectedAuthMessage(
          e,
          fallback: 'ส่งอีเมลยืนยันไม่สำเร็จ กรุณาลองอีกครั้ง',
        ),
      );
    }
  }

  static Future<AppUser?> completeEmailVerification() async {
    final session = _supabase.auth.currentSession;
    final user = _supabase.auth.currentUser;

    if (session == null || user == null) return null;
    if (user.emailConfirmedAt == null) return null;

    return _loadSignedInMember();
  }

  static Future<void> sendPasswordResetEmail(String email) async {
    final cleanEmail = email.trim().toLowerCase();

    if (!isValidEmail(cleanEmail)) {
      throw const AuthServiceException('กรุณากรอกอีเมลให้ถูกต้อง');
    }

    try {
      await _supabase.auth.resetPasswordForEmail(
        cleanEmail,
        redirectTo: SupabaseConfig.passwordRecoveryRedirectTo,
      );
    } on AuthException catch (e) {
      throw AuthServiceException(_authMessage(e.message));
    } catch (e) {
      throw AuthServiceException(
        _unexpectedAuthMessage(
          e,
          fallback: 'ส่งคำขอรีเซ็ตรหัสผ่านไม่สำเร็จ กรุณาลองอีกครั้ง',
        ),
      );
    }
  }

  static Future<void> completePasswordRecovery(String newPassword) async {
    final passwordError = validatePassword(newPassword);
    if (passwordError != null) {
      throw AuthServiceException(passwordError);
    }

    if (_supabase.auth.currentSession == null ||
        _supabase.auth.currentUser == null) {
      throw const AuthServiceException(
        'ลิงก์รีเซ็ตรหัสผ่านหมดอายุหรือไม่ถูกต้อง กรุณาขอลิงก์ใหม่',
      );
    }

    try {
      await _supabase.auth.updateUser(UserAttributes(password: newPassword));

      // Force a clean login with the new password after recovery.
      await clear();
    } on AuthException catch (e) {
      throw AuthServiceException(_authMessage(e.message));
    } catch (e) {
      if (e is AuthServiceException) rethrow;
      throw AuthServiceException(
        _unexpectedAuthMessage(
          e,
          fallback: 'ตั้งรหัสผ่านใหม่ไม่สำเร็จ กรุณาลองอีกครั้ง',
        ),
      );
    }
  }

  static Future<void> cancelPasswordRecovery() async {
    await clear();
  }

  static Future<AppUser?> restoreIdentity() async {
    if (_supabase.auth.currentSession != null &&
        _supabase.auth.currentUser != null) {
      try {
        return await _loadSignedInMember();
      } catch (_) {
        final cached = await _restoreCachedMember();
        if (cached != null) return cached;
      }
    }

    final isMember = await _store.read(key: 'isMember');
    if (isMember == '0') {
      final id = await _store.read(key: 'deviceId');
      final first = await _store.read(key: 'firstName');
      final last = await _store.read(key: 'lastName');

      if (id != null &&
          first != null &&
          first.isNotEmpty &&
          last != null &&
          last.isNotEmpty) {
        return AppUser(
          id: id,
          firstName: first,
          lastName: last,
          isMember: false,
          role: AppRole.guest,
        );
      }
    }

    return null;
  }

  static Future<AppUser?> _restoreCachedMember() async {
    final id = await _store.read(key: 'supabaseUserId');
    final first = await _store.read(key: 'firstName');
    final last = await _store.read(key: 'lastName');
    final email = await _store.read(key: 'email');
    final phone = await _store.read(key: 'phone');
    final photoPath = await _store.read(key: 'photoPath');
    final roleValue = await _store.read(key: 'role');

    if (id == null || first == null || last == null || email == null) {
      return null;
    }

    return AppUser(
      id: id,
      firstName: first,
      lastName: last,
      email: email,
      phone: phone,
      photoPath: photoPath,
      isMember: true,
      role: _roleFromString(roleValue),
      emailVerified: true,
    );
  }

  static Future<AppUser> currentMember() async {
    if (_supabase.auth.currentUser == null) {
      throw const AuthServiceException('ยังไม่ได้เข้าสู่ระบบ');
    }
    return _loadSignedInMember();
  }

  static Future<AppUser> _loadSignedInMember() async {
    final authUser = _supabase.auth.currentUser;
    if (authUser == null) {
      throw const AuthServiceException('ไม่พบ session ของผู้ใช้');
    }

    final results = await Future.wait<dynamic>([
      _supabase
          .from('profiles')
          .select('id, first_name, last_name, photo_path')
          .eq('id', authUser.id)
          .single(),
      _supabase
          .from('user_private')
          .select('phone')
          .eq('user_id', authUser.id)
          .maybeSingle(),
      _supabase
          .from('user_roles')
          .select('role')
          .eq('user_id', authUser.id)
          .single(),
    ]);

    final profile = Map<String, dynamic>.from(results[0] as Map);
    final privateData = results[1] == null
        ? <String, dynamic>{}
        : Map<String, dynamic>.from(results[1] as Map);
    final roleData = Map<String, dynamic>.from(results[2] as Map);

    final photoPath = profile['photo_path']?.toString();
    String? signedPhotoUrl;

    if (photoPath != null && photoPath.isNotEmpty) {
      try {
        signedPhotoUrl = await _supabase.storage
            .from('avatars')
            .createSignedUrl(photoPath, const Duration(hours: 1).inSeconds);
      } catch (_) {
        signedPhotoUrl = null;
      }
    }

    final member = AppUser(
      id: authUser.id,
      firstName: profile['first_name']?.toString() ?? '',
      lastName: profile['last_name']?.toString() ?? '',
      email: authUser.email,
      phone: privateData['phone']?.toString(),
      photoPath: photoPath,
      photoUrl: signedPhotoUrl,
      isMember: true,
      role: _roleFromString(roleData['role']?.toString()),
      emailVerified: authUser.emailConfirmedAt != null,
    );

    await _cacheMember(member);
    return member;
  }

  static AppRole _roleFromString(String? value) {
    switch (value) {
      case 'admin':
        return AppRole.admin;
      case 'rescuer':
        return AppRole.rescuer;
      case 'user':
        return AppRole.user;
      default:
        return AppRole.user;
    }
  }

  static Future<void> _cacheMember(AppUser member) async {
    await _getOrCreateDeviceId();
    await _store.write(key: 'supabaseUserId', value: member.id);
    await _store.write(key: 'firstName', value: member.firstName);
    await _store.write(key: 'lastName', value: member.lastName);
    await _store.write(key: 'email', value: member.email ?? '');
    await _store.write(key: 'phone', value: member.phone ?? '');
    await _store.write(key: 'photoPath', value: member.photoPath ?? '');
    await _store.write(key: 'role', value: member.role.name);
    await _store.write(key: 'isMember', value: '1');
  }

  static Future<AppUser> updateProfile({
    required String firstName,
    required String lastName,
    String? phone,
  }) async {
    final user = _supabase.auth.currentUser;
    if (user == null) {
      throw const AuthServiceException('กรุณาเข้าสู่ระบบก่อน');
    }

    final cleanFirst = firstName.trim();
    final cleanLast = lastName.trim();
    final cleanPhone = phone?.trim();

    if (cleanFirst.isEmpty || cleanLast.isEmpty) {
      throw const AuthServiceException('ชื่อจริงและนามสกุลห้ามว่าง');
    }

    try {
      await _supabase.auth.updateUser(
        UserAttributes(
          data: {
            'first_name': cleanFirst,
            'last_name': cleanLast,
            'phone': cleanPhone,
          },
        ),
      );

      await _supabase
          .from('profiles')
          .update({'first_name': cleanFirst, 'last_name': cleanLast})
          .eq('id', user.id);

      await _supabase
          .from('user_private')
          .update({'phone': cleanPhone})
          .eq('user_id', user.id);

      return _loadSignedInMember();
    } on AuthException catch (e) {
      throw AuthServiceException(_authMessage(e.message));
    } on PostgrestException catch (_) {
      throw const AuthServiceException(
        'บันทึกข้อมูลบัญชีไม่สำเร็จ กรุณาลองอีกครั้ง',
      );
    } catch (e) {
      if (e is AuthServiceException) rethrow;
      throw AuthServiceException(
        _unexpectedAuthMessage(
          e,
          fallback: 'บันทึกข้อมูลบัญชีไม่สำเร็จ กรุณาลองอีกครั้ง',
        ),
      );
    }
  }

  static Future<void> verifyCurrentPassword(String currentPassword) async {
    final user = _supabase.auth.currentUser;
    final email = user?.email;

    if (user == null || email == null || email.isEmpty) {
      throw const AuthServiceException('กรุณาเข้าสู่ระบบก่อน');
    }
    if (currentPassword.isEmpty) {
      throw const AuthServiceException('กรุณากรอกรหัสผ่านปัจจุบัน');
    }

    try {
      final response = await _supabase.auth.signInWithPassword(
        email: email,
        password: currentPassword,
      );

      if (response.user == null || response.user!.id != user.id) {
        throw const AuthServiceException('รหัสผ่านปัจจุบันไม่ถูกต้อง');
      }
    } on AuthException catch (e) {
      final raw = e.message.toLowerCase();
      if (raw.contains('invalid login credentials') ||
          raw.contains('password')) {
        throw const AuthServiceException('รหัสผ่านปัจจุบันไม่ถูกต้อง');
      }
      throw AuthServiceException(_authMessage(e.message));
    } catch (e) {
      if (e is AuthServiceException) rethrow;
      throw AuthServiceException(
        _unexpectedAuthMessage(
          e,
          fallback: 'ตรวจสอบรหัสผ่านปัจจุบันไม่สำเร็จ กรุณาลองอีกครั้ง',
        ),
      );
    }
  }

  static Future<void> requestEmailChange({
    required String newEmail,
    required String currentPassword,
  }) async {
    final user = _supabase.auth.currentUser;
    if (user == null) {
      throw const AuthServiceException('กรุณาเข้าสู่ระบบก่อน');
    }

    final cleanEmail = newEmail.trim().toLowerCase();
    final currentEmail = user.email?.trim().toLowerCase() ?? '';

    if (!isValidEmail(cleanEmail)) {
      throw const AuthServiceException('กรุณากรอกอีเมลใหม่ให้ถูกต้อง');
    }
    if (cleanEmail == currentEmail) {
      throw const AuthServiceException('อีเมลใหม่ต้องไม่ซ้ำกับอีเมลปัจจุบัน');
    }

    await verifyCurrentPassword(currentPassword);

    try {
      await _supabase.auth.updateUser(
        UserAttributes(email: cleanEmail),
        emailRedirectTo: SupabaseConfig.emailRedirectTo,
      );
    } on AuthException catch (e) {
      throw AuthServiceException(_authMessage(e.message));
    } catch (e) {
      throw AuthServiceException(
        _unexpectedAuthMessage(
          e,
          fallback: 'ส่งคำขอเปลี่ยนอีเมลไม่สำเร็จ กรุณาลองอีกครั้ง',
        ),
      );
    }
  }

  static Future<void> changePassword({
    required String currentPassword,
    required String newPassword,
  }) async {
    final user = _supabase.auth.currentUser;

    if (user == null) {
      throw const AuthServiceException('กรุณาเข้าสู่ระบบก่อน');
    }

    if (currentPassword.isEmpty) {
      throw const AuthServiceException('กรุณากรอกรหัสผ่านปัจจุบัน');
    }

    final passwordError = validatePassword(newPassword);

    if (passwordError != null) {
      throw AuthServiceException(passwordError);
    }

    if (currentPassword == newPassword) {
      throw const AuthServiceException(
        'รหัสผ่านใหม่ต้องไม่ซ้ำกับรหัสผ่านปัจจุบัน',
      );
    }

    try {
      await _supabase.auth.updateUser(
        UserAttributes(password: newPassword, currentPassword: currentPassword),
      );
    } on AuthException catch (e) {
      final raw = e.message.toLowerCase();

      if (raw.contains('invalid login credentials') ||
          raw.contains('password does not match') ||
          raw.contains('incorrect password') ||
          raw.contains('invalid current password')) {
        throw const AuthServiceException('รหัสผ่านปัจจุบันไม่ถูกต้อง');
      }

      if (raw.contains('current password required')) {
        throw const AuthServiceException(
          'ระบบไม่สามารถตรวจสอบรหัสผ่านปัจจุบันได้ กรุณาลองอีกครั้ง',
        );
      }

      if (raw.contains('same password') ||
          raw.contains('different from the old password')) {
        throw const AuthServiceException(
          'รหัสผ่านใหม่ต้องไม่ซ้ำกับรหัสผ่านปัจจุบัน',
        );
      }

      if (raw.contains('weak password') ||
          raw.contains('password should') ||
          raw.contains('password must')) {
        throw const AuthServiceException(
          'รหัสผ่านใหม่ไม่ผ่านเงื่อนไขความปลอดภัย',
        );
      }

      throw AuthServiceException(_authMessage(e.message));
    } catch (e) {
      if (e is AuthServiceException) {
        rethrow;
      }

      throw AuthServiceException(
        _unexpectedAuthMessage(
          e,
          fallback: 'เปลี่ยนรหัสผ่านไม่สำเร็จ กรุณาลองอีกครั้ง',
        ),
      );
    }
  }

  static Future<void> deleteMyAccount({required String currentPassword}) async {
    final user = _supabase.auth.currentUser;
    if (user == null) {
      throw const AuthServiceException('กรุณาเข้าสู่ระบบก่อน');
    }

    final userId = user.id;

    try {
      final response = await _supabase.functions.invoke(
        'delete-account',
        body: const <String, dynamic>{'confirm': true},
      );

      if (response.status < 200 || response.status >= 300) {
        if (response.status == 401) {
          throw const AuthServiceException(
            'ต้องยืนยันตัวตนใหม่ก่อนลบบัญชี กรุณากรอกรหัสผ่านอีกครั้ง',
          );
        }
        throw const AuthServiceException('ลบบัญชีไม่สำเร็จ กรุณาลองอีกครั้ง');
      }

      await LocalDatabase.instance.clearOwnerData(userId);
      await clear();
    } catch (e) {
      if (e is AuthServiceException) rethrow;
      throw AuthServiceException(
        _unexpectedAuthMessage(
          e,
          fallback: 'ลบบัญชีไม่สำเร็จ กรุณาลองอีกครั้ง',
        ),
      );
    }
  }

  static Future<AppUser> uploadAvatar({
    required Uint8List bytes,
    required String mimeType,
    required String extension,
  }) async {
    final user = _supabase.auth.currentUser;
    if (user == null) {
      throw const AuthServiceException('กรุณาเข้าสู่ระบบก่อน');
    }

    final safeExtension = extension.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '');
    final path =
        '${user.id}/profile.${safeExtension.isEmpty ? 'jpg' : safeExtension}';

    await _supabase.storage
        .from('avatars')
        .uploadBinary(
          path,
          bytes,
          fileOptions: FileOptions(
            upsert: true,
            contentType: mimeType,
            cacheControl: '3600',
          ),
        );

    await _supabase
        .from('profiles')
        .update({'photo_path': path})
        .eq('id', user.id);

    return _loadSignedInMember();
  }

  static Future<String> uploadRescueVerificationDocument({
    required Uint8List bytes,
    required String fileName,
    required String mimeType,
  }) async {
    final user = _supabase.auth.currentUser;
    if (user == null) {
      throw const AuthServiceException('กรุณาเข้าสู่ระบบก่อน');
    }

    final safeName = fileName
        .replaceAll(RegExp(r'[^a-zA-Z0-9._-]'), '_')
        .replaceAll(RegExp(r'_+'), '_');

    final path =
        '${user.id}/${DateTime.now().millisecondsSinceEpoch}_$safeName';

    await _supabase.storage
        .from('rescue-verification')
        .uploadBinary(
          path,
          bytes,
          fileOptions: FileOptions(
            upsert: false,
            contentType: mimeType,
            cacheControl: '3600',
          ),
        );

    return path;
  }

  static Future<void> submitRescuerVerification({
    required String organizationName,
    required String personnelId,
    String? note,
    Uint8List? documentBytes,
    String? documentName,
    String? documentMimeType,
  }) async {
    final user = _supabase.auth.currentUser;
    if (user == null) {
      throw const AuthServiceException('กรุณาเข้าสู่ระบบก่อน');
    }

    if (organizationName.trim().isEmpty || personnelId.trim().isEmpty) {
      throw const AuthServiceException('กรุณากรอกหน่วยงานและรหัสประจำตัว');
    }

    String? uploadedPath;

    try {
      if (documentBytes != null &&
          documentName != null &&
          documentMimeType != null) {
        uploadedPath = await uploadRescueVerificationDocument(
          bytes: documentBytes,
          fileName: documentName,
          mimeType: documentMimeType,
        );
      }

      await _supabase.from('rescue_verification_requests').insert({
        'user_id': user.id,
        'organization_name': organizationName.trim(),
        'personnel_id': personnelId.trim(),
        'document_path': uploadedPath,
        'note': note?.trim(),
      });
    } catch (e) {
      if (uploadedPath != null) {
        try {
          await _supabase.storage.from('rescue-verification').remove([
            uploadedPath,
          ]);
        } catch (_) {}
      }

      if (e is AuthServiceException) rethrow;
      throw AuthServiceException('ส่งคำขอยืนยันหน่วยกู้ภัยไม่สำเร็จ: $e');
    }
  }

  static Future<Map<String, dynamic>?> getMyRescuerVerificationRequest() async {
    final user = _supabase.auth.currentUser;
    if (user == null) return null;

    final data = await _supabase
        .from('rescue_verification_requests')
        .select()
        .eq('user_id', user.id)
        .order('submitted_at', ascending: false)
        .limit(1)
        .maybeSingle();

    if (data == null) return null;
    return Map<String, dynamic>.from(data);
  }

  static Future<List<Map<String, dynamic>>> getRescueVerificationRequests({
    String? status,
  }) async {
    final user = await currentMember();
    if (user.role != AppRole.admin) {
      throw const AuthServiceException('ต้องเป็น Admin เท่านั้น');
    }

    final dynamic rawRows;
    if (status == null) {
      rawRows = await _supabase
          .from('rescue_verification_requests')
          .select()
          .order('submitted_at', ascending: false);
    } else {
      rawRows = await _supabase
          .from('rescue_verification_requests')
          .select()
          .eq('status', status)
          .order('submitted_at', ascending: false);
    }

    final result = <Map<String, dynamic>>[];

    for (final raw in rawRows as List) {
      final row = Map<String, dynamic>.from(raw as Map);
      final userId = row['user_id']?.toString();

      if (userId != null && userId.isNotEmpty) {
        try {
          final profile = await _supabase
              .from('profiles')
              .select('id, first_name, last_name, photo_path')
              .eq('id', userId)
              .maybeSingle();

          if (profile != null) {
            row['profile'] = Map<String, dynamic>.from(profile);
          }

          final role = await _supabase
              .from('user_roles')
              .select('role')
              .eq('user_id', userId)
              .maybeSingle();

          if (role != null) {
            row['current_role'] = role['role']?.toString();
          }
        } catch (_) {}
      }

      result.add(row);
    }

    return result;
  }

  static Future<String> createRescueDocumentSignedUrl(
    String path, {
    int expiresInSeconds = 600,
  }) async {
    final me = await currentMember();
    if (me.role != AppRole.admin) {
      throw const AuthServiceException('ต้องเป็น Admin เท่านั้น');
    }

    return _supabase.storage
        .from('rescue-verification')
        .createSignedUrl(path, expiresInSeconds);
  }

  static Future<void> reviewRescueRequest({
    required String requestId,
    required bool approve,
    String? rejectionReason,
  }) async {
    final me = await currentMember();
    if (me.role != AppRole.admin) {
      throw const AuthServiceException('ต้องเป็น Admin เท่านั้น');
    }

    if (!approve &&
        (rejectionReason == null || rejectionReason.trim().isEmpty)) {
      throw const AuthServiceException('กรุณาระบุเหตุผลที่ปฏิเสธ');
    }

    await _supabase.rpc(
      'review_rescue_request',
      params: {
        'p_request_id': requestId,
        'p_approve': approve,
        'p_rejection_reason': approve ? null : rejectionReason!.trim(),
      },
    );
  }

  static Future<void> revokeRescuer(String userId) async {
    final me = await currentMember();
    if (me.role != AppRole.admin) {
      throw const AuthServiceException('ต้องเป็น Admin เท่านั้น');
    }

    await _supabase.rpc('revoke_rescuer', params: {'p_user_id': userId});
  }

  static Future<void> clear() async {
    try {
      await _supabase.auth.signOut();
    } catch (_) {}

    await _store.delete(key: 'firstName');
    await _store.delete(key: 'lastName');
    await _store.delete(key: 'email');
    await _store.delete(key: 'phone');
    await _store.delete(key: 'photoPath');
    await _store.delete(key: 'role');
    await _store.delete(key: 'supabaseUserId');
    await _store.delete(key: 'isMember');
  }

  static String _unexpectedAuthMessage(
    Object error, {
    required String fallback,
  }) {
    final message = error.toString().toLowerCase();
    if (message.contains('failed to fetch') ||
        message.contains('socketexception') ||
        message.contains('network') ||
        message.contains('connection') ||
        message.contains('clientexception')) {
      return 'ไม่สามารถเชื่อมต่ออินเทอร์เน็ตได้ กรุณาตรวจสอบเครือข่ายแล้วลองอีกครั้ง';
    }
    return fallback;
  }

  static String _authMessage(String raw) {
    final message = raw.toLowerCase();

    if (message.contains('invalid login credentials')) {
      return 'อีเมลหรือรหัสผ่านไม่ถูกต้อง';
    }
    if (message.contains('email not confirmed')) {
      return 'กรุณายืนยันอีเมลก่อนเข้าสู่ระบบ';
    }
    if (message.contains('already registered') ||
        message.contains('already been registered')) {
      return 'อีเมลนี้ถูกสมัครใช้งานแล้ว';
    }
    if (message.contains('current password') ||
        message.contains('password does not match')) {
      return 'รหัสผ่านปัจจุบันไม่ถูกต้อง';
    }
    if (message.contains('same password') ||
        message.contains('different from the old password')) {
      return 'รหัสผ่านใหม่ต้องไม่ซ้ำกับรหัสผ่านปัจจุบัน';
    }
    if (message.contains('new email should be different')) {
      return 'อีเมลใหม่ต้องไม่ซ้ำกับอีเมลปัจจุบัน';
    }
    if (message.contains('rate limit') ||
        message.contains('too many requests')) {
      return 'มีการร้องขอหลายครั้งเกินไป กรุณารอสักครู่แล้วลองใหม่';
    }
    if (message.contains('weak password') ||
        message.contains('password should') ||
        message.contains('password must')) {
      return 'รหัสผ่านไม่ผ่านเงื่อนไขที่กำหนด';
    }

    return 'ดำเนินการยืนยันตัวตนไม่สำเร็จ กรุณาลองอีกครั้ง';
  }
}

class AuthServiceException implements Exception {
  const AuthServiceException(this.message);
  final String message;

  @override
  String toString() => message;
}
