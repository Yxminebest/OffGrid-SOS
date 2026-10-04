class LocalSosRecord {
  const LocalSosRecord({
    required this.id,
    required this.ownerLocalId,
    required this.message,
    required this.createdAt,
    required this.updatedAt,
    this.ownerUserId,
    this.latitude,
    this.longitude,
    this.accuracy,
    this.isActive = true,
    this.endedAt,
    this.syncState = 'pending',
    this.lastError,
  });

  final String id;

  /// Guest device id or signed-in user id used to scope local records.
  final String ownerLocalId;

  /// Supabase auth user id. Null for Guest.
  final String? ownerUserId;

  final String message;
  final double? latitude;
  final double? longitude;
  final double? accuracy;

  final bool isActive;
  final DateTime? endedAt;

  /// pending / synced / error
  final String syncState;
  final String? lastError;

  final DateTime createdAt;
  final DateTime updatedAt;

  LocalSosRecord copyWith({
    String? message,
    double? latitude,
    double? longitude,
    double? accuracy,
    bool? isActive,
    DateTime? endedAt,
    String? syncState,
    String? lastError,
    bool clearLastError = false,
    DateTime? updatedAt,
  }) {
    return LocalSosRecord(
      id: id,
      ownerLocalId: ownerLocalId,
      ownerUserId: ownerUserId,
      message: message ?? this.message,
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      accuracy: accuracy ?? this.accuracy,
      isActive: isActive ?? this.isActive,
      endedAt: endedAt ?? this.endedAt,
      syncState: syncState ?? this.syncState,
      lastError: clearLastError ? null : (lastError ?? this.lastError),
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, Object?> toLocalMap() => <String, Object?>{
    'id': id,
    'owner_local_id': ownerLocalId,
    'owner_user_id': ownerUserId,
    'message': message,
    'latitude': latitude,
    'longitude': longitude,
    'accuracy': accuracy,
    'is_active': isActive,
    'ended_at': endedAt?.toUtc().toIso8601String(),
    'sync_state': syncState,
    'last_error': lastError,
    'created_at': createdAt.toUtc().toIso8601String(),
    'updated_at': updatedAt.toUtc().toIso8601String(),
  };

  Map<String, dynamic> toSupabaseMap() => <String, dynamic>{
    'id': id,
    'owner_id': ownerUserId,
    'message': message,
    'latitude': latitude,
    'longitude': longitude,
    'accuracy': accuracy,
    'is_active': isActive,
    'ended_at': endedAt?.toUtc().toIso8601String(),
    'created_at': createdAt.toUtc().toIso8601String(),
    'updated_at': updatedAt.toUtc().toIso8601String(),
  };

  factory LocalSosRecord.fromLocalMap(Map<String, Object?> map) {
    return LocalSosRecord(
      id: map['id']!.toString(),
      ownerLocalId: map['owner_local_id']!.toString(),
      ownerUserId: map['owner_user_id']?.toString(),
      message: map['message']?.toString() ?? '',
      latitude: (map['latitude'] as num?)?.toDouble(),
      longitude: (map['longitude'] as num?)?.toDouble(),
      accuracy: (map['accuracy'] as num?)?.toDouble(),
      isActive: map['is_active'] as bool? ?? true,
      endedAt: _dateOrNull(map['ended_at']),
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

  static DateTime? _dateOrNull(Object? value) {
    if (value == null) return null;
    return DateTime.tryParse(value.toString())?.toLocal();
  }
}
