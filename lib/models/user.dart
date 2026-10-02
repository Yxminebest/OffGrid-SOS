enum AppRole {
  guest,
  user,
  rescuer,
  admin,
}

class AppUser {
  const AppUser({
    required this.id,
    required this.firstName,
    required this.lastName,
    required this.isMember,
    this.email,
    this.phone,
    this.photoPath,
    this.photoUrl,
    this.role = AppRole.user,
    this.emailVerified = false,
  });

  final String id;
  final String firstName;
  final String lastName;
  final bool isMember;

  final String? email;
  final String? phone;

  /// Supabase Storage object path in the private `avatars` bucket.
  final String? photoPath;

  /// Temporary signed URL generated at runtime.
  final String? photoUrl;

  final AppRole role;
  final bool emailVerified;

  String get fullName => '$firstName $lastName'.trim();

  bool get isVerifiedRescuer =>
      role == AppRole.rescuer || role == AppRole.admin;

  AppUser copyWith({
    String? firstName,
    String? lastName,
    String? email,
    String? phone,
    String? photoPath,
    String? photoUrl,
    AppRole? role,
    bool? emailVerified,
  }) {
    return AppUser(
      id: id,
      firstName: firstName ?? this.firstName,
      lastName: lastName ?? this.lastName,
      isMember: isMember,
      email: email ?? this.email,
      phone: phone ?? this.phone,
      photoPath: photoPath ?? this.photoPath,
      photoUrl: photoUrl ?? this.photoUrl,
      role: role ?? this.role,
      emailVerified: emailVerified ?? this.emailVerified,
    );
  }
}

class PendingRegistration {
  const PendingRegistration({
    required this.email,
    required this.userId,
  });

  final String email;
  final String userId;
}
