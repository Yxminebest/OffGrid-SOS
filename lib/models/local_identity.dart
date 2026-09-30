import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:uuid/uuid.dart';

/// ตัวตนในเครื่อง ใช้ได้ตั้งแต่เปิดแอพครั้งแรก ไม่ต้องมีอินเทอร์เน็ต
class LocalIdentity {
  const LocalIdentity({
    required this.id,
    required this.firstName,
    required this.lastName,
    this.isMember = false,
  });
  final String id, firstName, lastName;
  final bool isMember;
  String get fullName => '$firstName $lastName'.trim();
}

class IdentityService {
  static const _store = FlutterSecureStorage();

  static Future<LocalIdentity?> load() async {
    final id = await _store.read(key: 'deviceId');
    final first = await _store.read(key: 'firstName');
    final last = await _store.read(key: 'lastName');
    if (id == null || first == null || last == null) return null;
    final member = await _store.read(key: 'isMember') == '1';
    return LocalIdentity(id: id, firstName: first, lastName: last, isMember: member);
  }

  /// ใช้งานโดยไม่สมัครสมาชิก: ต้องกรอกชื่อจริงและนามสกุล
  static Future<LocalIdentity> createGuest(String first, String last) async {
    final id = await _store.read(key: 'deviceId') ?? const Uuid().v4();
    await _store.write(key: 'deviceId', value: id);
    await _store.write(key: 'firstName', value: first.trim());
    await _store.write(key: 'lastName', value: last.trim());
    return LocalIdentity(id: id, firstName: first.trim(), lastName: last.trim());
  }
}
