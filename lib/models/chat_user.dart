class ChatUser {
  const ChatUser({
    required this.id,
    required this.firstName,
    required this.lastName,
    this.photoPath,
    this.role,
  });

  final String id;
  final String firstName;
  final String lastName;
  final String? photoPath;
  final String? role;

  String get fullName => '$firstName $lastName'.trim();

  factory ChatUser.fromMap(Map<String, dynamic> map) {
    return ChatUser(
      id: map['id'].toString(),
      firstName: map['first_name']?.toString() ?? '',
      lastName: map['last_name']?.toString() ?? '',
      photoPath: map['photo_path']?.toString(),
      role: map['role']?.toString(),
    );
  }
}
