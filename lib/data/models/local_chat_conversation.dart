class LocalChatConversation {
  const LocalChatConversation({
    required this.id,
    required this.ownerLocalId,
    required this.peerUserId,
    required this.displayName,
    required this.updatedAt,
    this.photoPath,
    this.lastMessage,
    this.lastMessageAt,
    this.unreadCount = 0,
    this.peerLastReadAt,
  });

  final String id;
  final String ownerLocalId;
  final String peerUserId;
  final String displayName;
  final String? photoPath;
  final String? lastMessage;
  final DateTime? lastMessageAt;
  final int unreadCount;
  final DateTime? peerLastReadAt;
  final DateTime updatedAt;

  Map<String, Object?> toLocalMap() => <String, Object?>{
    'id': id,
    'owner_local_id': ownerLocalId,
    'peer_user_id': peerUserId,
    'display_name': displayName,
    'photo_path': photoPath,
    'last_message': lastMessage,
    'last_message_at': lastMessageAt?.toUtc().toIso8601String(),
    'unread_count': unreadCount,
    'peer_last_read_at': peerLastReadAt?.toUtc().toIso8601String(),
    'updated_at': updatedAt.toUtc().toIso8601String(),
  };

  factory LocalChatConversation.fromLocalMap(Map<String, Object?> map) {
    DateTime? parseNullable(Object? value) {
      final text = value?.toString();
      if (text == null || text.isEmpty) return null;
      return DateTime.tryParse(text)?.toLocal();
    }

    return LocalChatConversation(
      id: map['id']!.toString(),
      ownerLocalId: map['owner_local_id']!.toString(),
      peerUserId: map['peer_user_id']!.toString(),
      displayName: map['display_name']?.toString() ?? 'ผู้ใช้',
      photoPath: map['photo_path']?.toString(),
      lastMessage: map['last_message']?.toString(),
      lastMessageAt: parseNullable(map['last_message_at']),
      unreadCount: int.tryParse(map['unread_count']?.toString() ?? '') ?? 0,
      peerLastReadAt: parseNullable(map['peer_last_read_at']),
      updatedAt:
          DateTime.tryParse(map['updated_at']?.toString() ?? '')?.toLocal() ??
          DateTime.now(),
    );
  }
}
