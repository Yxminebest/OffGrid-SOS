import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:uuid/uuid.dart';

/// ตัวตนผู้ใช้ในเครื่อง — ใช้สำหรับ UI Week 2 และเตรียมต่อ Firebase ใน Week 3.
class LocalIdentity {
  const LocalIdentity({
    required this.id,
    required this.firstName,
    required this.lastName,
    this.email,
    this.isMember = false,
  });

  final String id;
  final String firstName;
  final String lastName;
  final String? email;
  final bool isMember;

  String get fullName {
    final name = '$firstName $lastName'.trim();
    if (name.isNotEmpty) return name;
    return email?.split('@').first ?? 'RescueLink User';
  }
}

class IdentityService {
  static const _store = FlutterSecureStorage();

  /// Week 2: จำข้อมูลไว้ใน Keychain แต่ยังให้เริ่มจาก Welcome/Login ทุกครั้ง
  /// เพื่อให้ Main Flow ตรงกับ Wireframe. Week 3 สามารถเพิ่ม auto-login ได้ภายหลัง.
  static Future<LocalIdentity> createGuest(String first, String last) async {
    final id = await _store.read(key: 'deviceId') ?? const Uuid().v4();
    await _store.write(key: 'deviceId', value: id);
    await _store.write(key: 'firstName', value: first.trim());
    await _store.write(key: 'lastName', value: last.trim());
    await _store.write(key: 'isMember', value: '0');
    await _store.delete(key: 'email');
    return LocalIdentity(
      id: id,
      firstName: first.trim(),
      lastName: last.trim(),
      isMember: false,
    );
  }

  /// UI demo login for Week 2. Replace this with Firebase Auth in Week 3.
  static Future<LocalIdentity> createDemoMember(String email) async {
    final id = await _store.read(key: 'deviceId') ?? const Uuid().v4();
    final alias = email.trim().split('@').first;
    await _store.write(key: 'deviceId', value: id);
    await _store.write(key: 'firstName', value: alias);
    await _store.write(key: 'lastName', value: '');
    await _store.write(key: 'email', value: email.trim());
    await _store.write(key: 'isMember', value: '1');
    return LocalIdentity(
      id: id,
      firstName: alias,
      lastName: '',
      email: email.trim(),
      isMember: true,
    );
  }

  static Future<void> clear() async {
    await _store.delete(key: 'firstName');
    await _store.delete(key: 'lastName');
    await _store.delete(key: 'email');
    await _store.delete(key: 'isMember');
    // deviceId intentionally stays on-device for future Mesh identity.
  }
}
