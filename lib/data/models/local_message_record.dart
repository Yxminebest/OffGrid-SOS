class LocalMessageRecord {
  const LocalMessageRecord({
    required this.id,
    required this.ownerLocalId,
    required this.conversationId,
    required this.senderName,
    required this.content,
    required this.createdAt,
    required this.updatedAt,
    this.senderUserId,
    this.isDeleted = false,
    this.syncState = 'pending',
    this.lastError,
  });

  final String id;
  final String ownerLocalId;
  final String? senderUserId;
  final String conversationId;
  final String senderName;
  final String content;
  final bool isDeleted;

  /// pending / synced / error
  final String syncState;
  final String? lastError;

  final DateTime createdAt;
  final DateTime updatedAt;

  LocalMessageRecord copyWith({
    String? content,
    bool? isDeleted,
    String? syncState,
    String? lastError,
    bool clearLastError = false,
    DateTime? updatedAt,
  }) {
    return LocalMessageRecord(
      id: id,
      ownerLocalId: ownerLocalId,
      senderUserId: senderUserId,
      conversationId: conversationId,
      senderName: senderName,
      content: content ?? this.content,
      isDeleted: isDeleted ?? this.isDeleted,
      syncState: syncState ?? this.syncState,
      lastError: clearLastError ? null : (lastError ?? this.lastError),
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, Object?> toLocalMap() => <String, Object?>{
    'id': id,
    'owner_local_id': ownerLocalId,
    'sender_user_id': senderUserId,
    'conversation_id': conversationId,
    'sender_name': senderName,
    'content': content,
    'is_deleted': isDeleted,
    'sync_state': syncState,
    'last_error': lastError,
    'created_at': createdAt.toUtc().toIso8601String(),
    'updated_at': updatedAt.toUtc().toIso8601String(),
  };

  Map<String, dynamic> toSupabaseMap() => <String, dynamic>{
    'id': id,
    'conversation_id': conversationId,
    'sender_id': senderUserId,
    'type': 'text',
    'content': content,
    'status': 'synced',
    'is_deleted': false,
    'created_at': createdAt.toUtc().toIso8601String(),
    'updated_at': updatedAt.toUtc().toIso8601String(),
  };

  factory LocalMessageRecord.fromLocalMap(Map<String, Object?> map) {
    return LocalMessageRecord(
      id: map['id']!.toString(),
      ownerLocalId: map['owner_local_id']!.toString(),
      senderUserId: map['sender_user_id']?.toString(),
      conversationId: map['conversation_id']!.toString(),
      senderName: map['sender_name']?.toString() ?? '',
      content: map['content']?.toString() ?? '',
      isDeleted: map['is_deleted'] as bool? ?? false,
      syncState: map['sync_state']?.toString() ?? 'pending',
      lastError: map['last_error']?.toString(),
      createdAt: _date(map['created_at']),
      updatedAt: _date(map['updated_at']),
    );
  }

  static DateTime _date(Object? value) {
    return DateTime.tryParse(value?.toString() ?? '')?.toLocal() ??
        DateTime.now();
  }
}
