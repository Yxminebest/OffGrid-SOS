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
    this.messageType = 'text',
    this.replyToId,
    this.latitude,
    this.longitude,
    this.accuracy,
    this.mediaPath,
    this.mediaName,
    this.mediaMime,
    this.mediaSize,
    this.mediaBytes,
    this.editedAt,
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
  final String messageType;
  final String? replyToId;
  final double? latitude;
  final double? longitude;
  final double? accuracy;
  final String? mediaPath;
  final String? mediaName;
  final String? mediaMime;
  final int? mediaSize;
  final List<int>? mediaBytes;
  final DateTime? editedAt;
  final bool isDeleted;

  /// pending / synced / error
  final String syncState;
  final String? lastError;

  final DateTime createdAt;
  final DateTime updatedAt;

  bool get hasAttachment => mediaPath != null || (mediaBytes?.isNotEmpty ?? false);

  LocalMessageRecord copyWith({
    String? content,
    String? messageType,
    String? replyToId,
    bool clearReplyToId = false,
    double? latitude,
    double? longitude,
    double? accuracy,
    String? mediaPath,
    String? mediaName,
    String? mediaMime,
    int? mediaSize,
    List<int>? mediaBytes,
    bool clearMediaBytes = false,
    DateTime? editedAt,
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
      messageType: messageType ?? this.messageType,
      replyToId: clearReplyToId ? null : (replyToId ?? this.replyToId),
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      accuracy: accuracy ?? this.accuracy,
      mediaPath: mediaPath ?? this.mediaPath,
      mediaName: mediaName ?? this.mediaName,
      mediaMime: mediaMime ?? this.mediaMime,
      mediaSize: mediaSize ?? this.mediaSize,
      mediaBytes: clearMediaBytes ? null : (mediaBytes ?? this.mediaBytes),
      editedAt: editedAt ?? this.editedAt,
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
    'message_type': messageType,
    'reply_to_id': replyToId,
    'latitude': latitude,
    'longitude': longitude,
    'accuracy': accuracy,
    'media_path': mediaPath,
    'media_name': mediaName,
    'media_mime': mediaMime,
    'media_size': mediaSize,
    'media_bytes': mediaBytes,
    'edited_at': editedAt?.toUtc().toIso8601String(),
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
    'type': messageType,
    'content': content,
    'reply_to_id': replyToId,
    'latitude': latitude,
    'longitude': longitude,
    'accuracy': accuracy,
    'media_path': mediaPath,
    'media_name': mediaName,
    'media_mime': mediaMime,
    'media_size': mediaSize,
    'status': 'synced',
    'is_deleted': false,
    'edited_at': editedAt?.toUtc().toIso8601String(),
    'created_at': createdAt.toUtc().toIso8601String(),
    'updated_at': updatedAt.toUtc().toIso8601String(),
  };

  factory LocalMessageRecord.fromLocalMap(Map<String, Object?> map) {
    DateTime? parseDate(Object? value) {
      final text = value?.toString();
      if (text == null || text.isEmpty) return null;
      return DateTime.tryParse(text)?.toLocal();
    }

    double? parseDouble(Object? value) {
      if (value == null) return null;
      if (value is num) return value.toDouble();
      return double.tryParse(value.toString());
    }

    List<int>? parseBytes(Object? value) {
      if (value is List) {
        return value.map((item) => (item as num).toInt()).toList();
      }
      return null;
    }

    return LocalMessageRecord(
      id: map['id']!.toString(),
      ownerLocalId: map['owner_local_id']!.toString(),
      senderUserId: map['sender_user_id']?.toString(),
      conversationId: map['conversation_id']!.toString(),
      senderName: map['sender_name']?.toString() ?? 'ผู้ใช้',
      content: map['content']?.toString() ?? '',
      messageType: map['message_type']?.toString() ?? 'text',
      replyToId: map['reply_to_id']?.toString(),
      latitude: parseDouble(map['latitude']),
      longitude: parseDouble(map['longitude']),
      accuracy: parseDouble(map['accuracy']),
      mediaPath: map['media_path']?.toString(),
      mediaName: map['media_name']?.toString(),
      mediaMime: map['media_mime']?.toString(),
      mediaSize: int.tryParse(map['media_size']?.toString() ?? ''),
      mediaBytes: parseBytes(map['media_bytes']),
      editedAt: parseDate(map['edited_at']),
      isDeleted: map['is_deleted'] == true,
      syncState: map['sync_state']?.toString() ?? 'pending',
      lastError: map['last_error']?.toString(),
      createdAt:
          DateTime.tryParse(map['created_at']?.toString() ?? '')?.toLocal() ??
          DateTime.now(),
      updatedAt:
          DateTime.tryParse(map['updated_at']?.toString() ?? '')?.toLocal() ??
          DateTime.now(),
    );
  }

  factory LocalMessageRecord.fromCloudMap({
    required Map<String, dynamic> map,
    required String ownerLocalId,
    required String senderName,
  }) {
    DateTime? parseDate(Object? value) {
      final text = value?.toString();
      if (text == null || text.isEmpty) return null;
      return DateTime.tryParse(text)?.toLocal();
    }

    double? parseDouble(Object? value) {
      if (value == null) return null;
      if (value is num) return value.toDouble();
      return double.tryParse(value.toString());
    }

    return LocalMessageRecord(
      id: map['id'].toString(),
      ownerLocalId: ownerLocalId,
      senderUserId: map['sender_id']?.toString(),
      conversationId: map['conversation_id'].toString(),
      senderName: senderName,
      content: map['content']?.toString() ?? '',
      messageType: map['type']?.toString() ?? 'text',
      replyToId: map['reply_to_id']?.toString(),
      latitude: parseDouble(map['latitude']),
      longitude: parseDouble(map['longitude']),
      accuracy: parseDouble(map['accuracy']),
      mediaPath: map['media_path']?.toString(),
      mediaName: map['media_name']?.toString(),
      mediaMime: map['media_mime']?.toString(),
      mediaSize: int.tryParse(map['media_size']?.toString() ?? ''),
      editedAt: parseDate(map['edited_at']),
      isDeleted: map['is_deleted'] == true,
      syncState: 'synced',
      createdAt: parseDate(map['created_at']) ?? DateTime.now(),
      updatedAt: parseDate(map['updated_at']) ?? DateTime.now(),
    );
  }
}
