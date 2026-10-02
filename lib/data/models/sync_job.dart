class SyncJob {
  const SyncJob({
    required this.entityType,
    required this.entityId,
    required this.operation,
    required this.ownerLocalId,
    required this.createdAt,
    required this.updatedAt,
    this.id,
    this.retryCount = 0,
    this.lastError,
    this.nextRetryAt,
  });

  final int? id;

  /// sos / message
  final String entityType;
  final String entityId;

  /// Local owner scope. For members this is the Supabase auth user id.
  final String ownerLocalId;

  /// insert / update / delete
  final String operation;

  final int retryCount;
  final String? lastError;
  final DateTime? nextRetryAt;

  final DateTime createdAt;
  final DateTime updatedAt;

  Map<String, Object?> toMap() => <String, Object?>{
    'entity_type': entityType,
    'entity_id': entityId,
    'operation': operation,
    'owner_local_id': ownerLocalId,
    'retry_count': retryCount,
    'last_error': lastError,
    'next_retry_at': nextRetryAt?.toUtc().toIso8601String(),
    'created_at': createdAt.toUtc().toIso8601String(),
    'updated_at': updatedAt.toUtc().toIso8601String(),
  };

  factory SyncJob.fromMap(int id, Map<String, Object?> map) {
    return SyncJob(
      id: id,
      entityType: map['entity_type']!.toString(),
      entityId: map['entity_id']!.toString(),
      operation: map['operation']!.toString(),
      ownerLocalId: map['owner_local_id']!.toString(),
      retryCount: (map['retry_count'] as num?)?.toInt() ?? 0,
      lastError: map['last_error']?.toString(),
      nextRetryAt: _dateOrNull(map['next_retry_at']),
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
