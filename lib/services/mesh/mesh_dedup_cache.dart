/// จำกัดทั้งจำนวนและอายุ ใช้เวลาของเครื่องรับ ไม่ใช้ timestamp ของผู้ส่ง
class MeshDedupCache {
  MeshDedupCache({
    this.capacity = 4096,
    this.maxAge = const Duration(minutes: 15),
    DateTime Function()? now,
  }) : now = now ?? DateTime.now {
    if (capacity < 1 || maxAge <= Duration.zero) {
      throw ArgumentError('Invalid dedup limits');
    }
  }
  final int capacity;
  final Duration maxAge;
  final DateTime Function() now;
  final _seen = <String, DateTime>{};
  int get length {
    _prune();
    return _seen.length;
  }

  bool contains(String id) {
    _prune();
    return _seen.containsKey(id);
  }

  void _prune() {
    final cutoff = now().subtract(maxAge);
    _seen.removeWhere((_, at) => !at.isAfter(cutoff));
  }

  bool remember(String id) {
    _prune();
    if (_seen.containsKey(id)) return false;
    _seen[id] = now();
    while (_seen.length > capacity) {
      _seen.remove(_seen.keys.first);
    }
    return true;
  }
}
