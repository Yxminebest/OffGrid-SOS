import 'dart:async';
import 'package:sembast/sembast.dart';
import 'package:uuid/uuid.dart';
import '../data/local/local_database.dart';
import '../data/models/local_chat_conversation.dart';
import '../data/models/local_message_record.dart';
import '../data/repositories/message_repository.dart';
import '../data/repositories/nearby_chat_repository.dart';
import '../models/chat_user.dart';
import '../models/user.dart';
import 'chat_service.dart';
import 'chat_media_cache.dart';
import 'location_service.dart';
import 'nearby_mesh_service.dart';
import 'network_service.dart';
import 'sync_service.dart';

class ChatContact {
  const ChatContact({
    required this.name,
    this.device,
    this.user,
    this.conversation,
  });
  final String name;
  final String? device, user, conversation;
  String get key => user != null ? 'user:$user' : 'device:$device';
}

class ChatItem {
  const ChatItem({
    required this.id,
    required this.at,
    required this.mine,
    required this.type,
    required this.text,
    required this.status,
    this.path,
    this.mediaPath,
    this.bytes,
    this.lat,
    this.lng,
    this.accuracy,
    this.size,
    this.name = '',
    this.read = true,
    this.lastKnown = false,
    this.locationAt,
  });
  final String id, type, text, status, name;
  final DateTime at;
  final bool mine, read, lastKnown;
  final DateTime? locationAt;
  final String? path, mediaPath;
  final List<int>? bytes;
  final double? lat, lng, accuracy;
  final int? size;
  String get preview => switch (type) {
    'image' => 'รูปภาพ',
    'video' => 'วิดีโอ',
    'location' => 'ตำแหน่งที่แชร์',
    _ => text,
  };
}

class ChatInboxEntry {
  const ChatInboxEntry(
    this.contact,
    this.messages, {
    this.cloudUnread = 0,
    this.fallbackPreview,
    this.fallbackAt,
  });
  final ChatContact contact;
  final List<ChatItem> messages;
  final int cloudUnread;
  final String? fallbackPreview;
  final DateTime? fallbackAt;
  String get preview => last?.preview ?? fallbackPreview ?? 'เริ่มสนทนา';
  DateTime get updatedAt => last?.at ?? fallbackAt ?? DateTime(2000);
  ChatItem? get last => messages.lastOrNull;
  int get unread {
    final count = messages.where((m) => !m.mine && !m.read).length;
    return count > cloudUnread ? count : cloudUnread;
  }
}

/// One inbox and message ID across radio/cloud. The existing durable queues and
/// authenticated cloud RLS remain responsible for delivery, never UI flags.
class UnifiedChatService {
  UnifiedChatService({
    LocalDatabase? local,
    NearbyMeshService? mesh,
    this.resolveCloud,
    this.syncCloud,
    bool Function()? online,
  }) : local = local ?? LocalDatabase.instance,
       mesh = mesh ?? NearbyMeshService.instance,
       online = online ?? (() => NetworkService.instance.online.value);
  static final instance = UnifiedChatService();
  final LocalDatabase local;
  final NearbyMeshService mesh;
  final bool Function() online;
  final Future<LocalChatConversation> Function(AppUser, ChatContact)?
  resolveCloud;
  final Future<void> Function()? syncCloud;
  static final contacts = stringMapStoreFactory.store('unified_contacts');
  late final messages = MessageRepository(local: local);
  AppUser? _me;
  Timer? _timer;
  bool _working = false, _rerun = false;
  Completer<void>? _activeWork;
  int _generation = 0;
  String? lastError;

  void start(AppUser me) {
    if (_me?.id == me.id) return;
    stop();
    _me = me;
    mesh.addListener(_wake);
    _timer = Timer.periodic(const Duration(seconds: 5), (_) => _wake());
    _wake();
  }

  void stop() {
    _generation++;
    _me = null;
    mesh.removeListener(_wake);
    _timer?.cancel();
    _timer = null;
  }

  void _wake() {
    unawaited(flush().catchError((_) {}));
  }

  Future<void> rememberPeers(String owner) async {
    if (mesh.ownerId != owner) return;
    final db = await local.database;
    for (final p in mesh.reachablePeers.toList()) {
      if (mesh.ownerId != owner) return;
      final ref = contacts.record('$owner:${p.deviceId}');
      final old = await ref.get(db);
      if (mesh.ownerId != owner) return;
      final value = <String, Object?>{
        'owner': owner,
        'device': p.deviceId,
        'user': p.userId,
        'verified': p.userId != null,
        'attestedUntil': p.attestedUntil?.toIso8601String(),
        'name': p.name,
      };
      // Only a server-attested account can bridge radio and cloud identities;
      // never merge by display name, role, or a network endpoint address.
      if (old?['user'] != value['user'] ||
          old?['name'] != value['name'] ||
          old?['verified'] != value['verified'] ||
          old?['attestedUntil'] != value['attestedUntil']) {
        await ref.put(db, value);
      }
    }
  }

  Future<List<ChatInboxEntry>> inbox(String owner) async {
    final db = await local.database;
    final bindingRows = await contacts.find(
      db,
      finder: Finder(filter: Filter.equals('owner', owner)),
    );
    // Legacy contact rows were based on hello claims, not server signatures.
    // Keep their device history, but never use those claims for cloud routing.
    final bindings = bindingRows.map((row) {
      final value = Map<String, Object?>.from(row.value);
      final until = DateTime.tryParse(value['attestedUntil']?.toString() ?? '');
      if (value['verified'] != true ||
          until == null ||
          !DateTime.now().isBefore(until)) {
        value['user'] = null;
      }
      return value;
    }).toList();
    final byDevice = {for (final b in bindings) b['device'] as String: b};
    final convs = await local.conversationStore.find(
      db,
      finder: Finder(filter: Filter.equals('owner_local_id', owner)),
    );
    final convById = {
      for (final c in convs)
        c.value['id'] as String: LocalChatConversation.fromLocalMap(c.value),
    };
    final people = <String, ChatContact>{};
    for (final c in convById.values) {
      final device =
          bindings
                  .where((b) => b['user'] == c.peerUserId)
                  .firstOrNull?['device']
              as String?;
      people['user:${c.peerUserId}'] = ChatContact(
        name: c.displayName,
        device: device,
        user: c.peerUserId,
        conversation: c.id,
      );
    }
    for (final b in bindings) {
      final c = ChatContact(
        name: b['name'] as String? ?? 'คนใกล้เคียง',
        device: b['device'] as String,
        user: b['user'] as String?,
      );
      people.putIfAbsent(c.key, () => c);
    }
    final groups = <String, Map<String, ChatItem>>{};
    final near = await NearbyChatRepository.messages.find(
      db,
      finder: Finder(filter: Filter.equals('owner', owner)),
    );
    for (final r in near) {
      final row = r.value;
      final device = row['peer'] as String;
      final binding = byDevice[device];
      final env = Map<String, dynamic>.from(row['envelope'] as Map);
      final body = Map<String, dynamic>.from(env['data'] as Map);
      final incoming = row['incoming'] == true;
      final c = ChatContact(
        device: device,
        user: binding?['user'] as String?,
        name:
            binding?['name'] as String? ??
            (incoming ? env['sender'] : env['peerName'])?.toString() ??
            'คนใกล้เคียง',
      );
      people.putIfAbsent(c.key, () => c);
      final item = ChatItem(
        id: env['id'] as String,
        mine: !incoming,
        type: env['kind'] == 'media'
            ? body['type'] as String
            : body['type'] as String? ?? 'text',
        text: body['text'] as String? ?? '',
        at: DateTime.tryParse(env['at']?.toString() ?? '') ?? DateTime(2000),
        status: row['delivery'] as String? ?? 'pending',
        path: row['localPath'] as String?,
        lat: (body['lat'] as num?)?.toDouble(),
        lng: (body['lng'] as num?)?.toDouble(),
        accuracy: (body['accuracy'] as num?)?.toDouble(),
        size: (body['size'] as num?)?.toInt(),
        name: body['name'] as String? ?? '',
        read: row['read'] == true,
        lastKnown: body['lastKnown'] == true,
        locationAt: DateTime.tryParse(body['recordedAt']?.toString() ?? ''),
      );
      (groups[c.key] ??= {})[item.id] = item;
    }
    final cloud = await local.messageStore.find(
      db,
      finder: Finder(
        filter: Filter.and([
          Filter.equals('owner_local_id', owner),
          Filter.equals('is_deleted', false),
        ]),
      ),
    );
    final unreadCloudIds = <String>{};
    for (final c in convById.values) {
      final remote =
          cloud
              .map((r) => LocalMessageRecord.fromLocalMap(r.value))
              .where((m) => m.conversationId == c.id && m.senderUserId != owner)
              .toList()
            ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
      unreadCloudIds.addAll(remote.take(c.unreadCount).map((m) => m.id));
    }
    for (final r in cloud) {
      final m = LocalMessageRecord.fromLocalMap(r.value);
      final c = convById[m.conversationId];
      if (c == null) continue;
      final key = 'user:${c.peerUserId}';
      final old = groups[key]?[m.id];
      final item = ChatItem(
        id: m.id,
        at: m.createdAt,
        mine: m.senderUserId == owner,
        type: m.messageType,
        text: m.content,
        path: old?.path,
        mediaPath: m.mediaPath,
        bytes: m.mediaBytes,
        lat: m.latitude,
        lng: m.longitude,
        accuracy: m.accuracy,
        name: m.mediaName ?? '',
        size: m.mediaSize,
        status: (old?.status.startsWith('delivered') ?? false)
            ? (m.syncState == 'synced' ? 'delivered_synced' : 'delivered')
            : m.syncState == 'synced'
            ? 'synced'
            : old?.status ?? m.syncState,
        read: old?.read ?? !unreadCloudIds.contains(m.id),
        lastKnown: old?.lastKnown ?? m.content.contains('พิกัดเก่า'),
        locationAt: old?.locationAt,
      );
      (groups[key] ??= {})[m.id] = item;
    }
    final result = people.entries.map((e) {
      final list = (groups[e.key]?.values.toList() ?? <ChatItem>[])
        ..sort((a, b) => a.at.compareTo(b.at));
      final conv = convById.values
          .where((v) => v.peerUserId == e.value.user)
          .firstOrNull;
      return ChatInboxEntry(
        e.value,
        list,
        cloudUnread: conv?.unreadCount ?? 0,
        fallbackPreview: conv?.lastMessage,
        fallbackAt: conv?.lastMessageAt,
      );
    }).toList()..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return result;
  }

  Stream<List<ChatInboxEntry>> watchInbox(String owner) async* {
    final db = await local.database;
    final signal = StreamController<void>();
    final subscriptions = <StreamSubscription>[];
    for (final store in [
      contacts,
      NearbyChatRepository.messages,
      local.messageStore,
      local.conversationStore,
    ]) {
      subscriptions.add(
        store
            .query()
            .onSnapshots(db)
            .listen(
              (_) {
                if (!signal.isClosed) signal.add(null);
              },
              onError: (Object e, StackTrace st) {
                if (!signal.isClosed) signal.addError(e, st);
              },
            ),
      );
    }
    try {
      yield await inbox(owner);
      await for (final _ in signal.stream) {
        yield await inbox(owner);
      }
    } finally {
      for (final sub in subscriptions) {
        await sub.cancel();
      }
      await signal.close();
    }
  }

  Future<ChatContact> resolve(AppUser me, ChatContact requested) async {
    await rememberPeers(me.id);
    final entries = await inbox(me.id);
    return entries
            .where(
              (e) =>
                  (requested.user != null &&
                      e.contact.user == requested.user) ||
                  (requested.device != null &&
                      e.contact.device == requested.device),
            )
            .firstOrNull
            ?.contact ??
        requested;
  }

  Future<LocalChatConversation?> _conversation(
    AppUser me,
    ChatContact c,
  ) async {
    if (!me.isMember || c.user == null) return null;
    if (c.conversation != null) {
      return LocalChatConversation(
        id: c.conversation!,
        ownerLocalId: me.id,
        peerUserId: c.user!,
        displayName: c.name,
        updatedAt: DateTime.now(),
      );
    }
    if (!online()) return null;
    return (resolveCloud ??
            ((user, contact) => ChatService.instance.getOrCreateDirect(
              me: user,
              peer: ChatUser(
                id: contact.user!,
                firstName: contact.name,
                lastName: '',
              ),
            )))(me, c)
        .timeout(const Duration(seconds: 8));
  }

  Future<void> send(
    AppUser me,
    ChatContact requested, {
    String text = '',
    SavedLocation? location,
    String? path,
    String? name,
    String type = 'text',
    String? messageId,
    String? caseId,
  }) async {
    if (mesh.ownerId != me.id) throw StateError('บัญชีเปลี่ยนแล้ว');
    if (path == null &&
        location == null &&
        (text.trim().isEmpty || text.length > 4000)) {
      throw ArgumentError('ข้อความต้องมี 1–4,000 ตัวอักษร');
    }
    final resolved = await resolve(me, requested);
    if (mesh.ownerId != me.id) throw StateError('บัญชีเปลี่ยนแล้ว');
    final available = resolved.user == null
        ? null
        : mesh.peerForUser(resolved.user!);
    final c = available == null
        ? resolved
        : ChatContact(
            name: resolved.name,
            user: resolved.user,
            device: available.deviceId,
            conversation: resolved.conversation,
          );
    final id = messageId ?? const Uuid().v4();
    final conv = c.conversation == null ? null : await _conversation(me, c);
    // Persist before network calls, and use exactly the same ID on both paths.
    if (c.device != null) {
      if (path != null) {
        await mesh.sendAttachment(
          target: c.device!,
          path: path,
          name: name ?? 'ไฟล์แนบ',
          type: type,
          peerName: c.name,
          messageId: id,
          caseId: caseId,
        );
      } else {
        await mesh.sendDirect(
          target: c.device!,
          text: location == null ? text : 'ตำแหน่งของฉัน',
          location: location,
          peerName: c.name,
          messageId: id,
          caseId: caseId,
        );
      }
    } else if (conv != null) {
      final bytes = path == null ? null : await mesh.media.files.allBytes(path);
      if (mesh.ownerId != me.id) throw StateError('บัญชีเปลี่ยนแล้ว');
      await messages.create(
        user: me,
        conversationId: conv.id,
        messageId: id,
        content: location != null
            ? (location.isLastKnown
                  ? 'ตำแหน่งที่แชร์ · พิกัดเก่า'
                  : 'ตำแหน่งที่แชร์')
            : type == 'image'
            ? 'รูปภาพ'
            : type == 'video'
            ? 'วิดีโอ'
            : text,
        type: location != null ? 'location' : type,
        latitude: location?.latitude,
        longitude: location?.longitude,
        accuracy: location?.accuracyMeters,
        mediaBytes: bytes,
        mediaName: name,
        mediaMime: mime(type, name),
      );
    } else {
      throw StateError('ยังไม่มีผู้ติดต่อที่บันทึกไว้ กรุณาจับคู่ก่อน');
    }
    _wake();
  }

  static String? mime(String type, String? name) => type == 'video'
      ? ((name ?? '').toLowerCase().endsWith('.mov')
            ? 'video/quicktime'
            : 'video/mp4')
      : type == 'image'
      ? ((name ?? '').toLowerCase().endsWith('.png')
            ? 'image/png'
            : 'image/jpeg')
      : null;

  /// Await the complete current pass, including one coalesced reconnect pass.
  /// Timer ticks never create overlapping workers or an unbounded retry loop.
  Future<void> flush() async {
    if (_working) {
      _rerun = true;
      await _activeWork?.future;
      return;
    }
    _working = true;
    final done = Completer<void>();
    _activeWork = done;
    try {
      for (var pass = 0; pass < 2; pass++) {
        _rerun = false;
        await _flushOnce();
        if (!_rerun) break;
      }
    } finally {
      _working = false;
      _activeWork = null;
      done.complete();
    }
  }

  Future<void> _flushRadio(
    AppUser me,
    ChatInboxEntry entry,
    bool Function() current,
  ) async {
    final c = entry.contact;
    final peer = c.user == null
        ? (c.device == null ? null : mesh.peerForDevice(c.device!))
        : mesh.peerForUser(c.user!);
    if (peer == null) return;
    for (final m in entry.messages.where(
      (m) =>
          m.mine && m.status != 'synced' && !m.status.startsWith('delivered'),
    )) {
      if (!current()) return;
      if (await mesh.chats.find(me.id, m.id) != null) {
        await mesh.retryFor(peer.deviceId);
        continue;
      }
      if (m.type == 'image' || m.type == 'video') {
        final path = m.path ?? await ChatMediaCache.instance.local(me.id, m.id);
        final stored =
            path ??
            (m.bytes == null
                ? null
                : await mesh.media.files.restore(
                    me.id,
                    m.id,
                    m.bytes!,
                    m.type,
                  ));
        if (!current()) return;
        if (stored != null) {
          await mesh.sendAttachment(
            target: peer.deviceId,
            path: stored,
            name: m.name,
            type: m.type,
            peerName: c.name,
            messageId: m.id,
          );
        }
      } else {
        await mesh.sendDirect(
          target: peer.deviceId,
          text: m.text.isEmpty ? 'ตำแหน่งของฉัน' : m.text,
          messageId: m.id,
          peerName: c.name,
          location: m.type == 'location' && m.lat != null && m.lng != null
              ? SavedLocation(
                  latitude: m.lat!,
                  longitude: m.lng!,
                  accuracyMeters: m.accuracy,
                  recordedAt: m.locationAt ?? m.at,
                  isLastKnown: m.lastKnown,
                )
              : null,
        );
      }
    }
  }

  Future<void> _flushOnce() async {
    final me = _me;
    if (me == null || mesh.ownerId != me.id) return;
    final generation = _generation;
    bool current() =>
        generation == _generation && _me?.id == me.id && mesh.ownerId == me.id;
    String? passError;
    try {
      await rememberPeers(me.id);
      final entries = await inbox(me.id);
      // Drain all reachable radio queues before any optional HTTP work, so a
      // slow cloud request for one contact cannot delay a different SOS peer.
      for (final entry in entries) {
        if (!current()) return;
        try {
          await _flushRadio(me, entry, current);
        } catch (e) {
          if (current()) passError = e.toString();
        }
      }
      if (current() && online() && me.isMember) {
        unawaited(mesh.refreshAttestation());
      }
      for (final entry in entries) {
        if (!current()) return;
        try {
          var c = entry.contact;
          // Online is optional. Failure leaves the durable radio queue untouched.
          if (online() &&
              me.isMember &&
              c.user != null &&
              entry.messages.any((m) => m.mine)) {
            final conv = await _conversation(me, c);
            if (!current()) return;
            if (conv != null) {
              c = ChatContact(
                name: c.name,
                user: c.user,
                device: c.device,
                conversation: conv.id,
              );
              for (final m in entry.messages.where((m) => m.mine)) {
                if (!current()) return;
                if (await messages.findById(m.id) != null) continue;
                if ((m.type == 'image' || m.type == 'video') &&
                    m.path == null) {
                  continue;
                }
                final bytes = m.path == null
                    ? null
                    : await mesh.media.files.allBytes(m.path!);
                if (!current()) return;
                await messages.create(
                  user: me,
                  conversationId: conv.id,
                  messageId: m.id,
                  createdAt: m.at,
                  content: m.type == 'location'
                      ? (m.lastKnown
                            ? 'ตำแหน่งที่แชร์ · พิกัดเก่า'
                            : 'ตำแหน่งที่แชร์')
                      : m.preview,
                  type: m.type,
                  latitude: m.lat,
                  longitude: m.lng,
                  accuracy: m.accuracy,
                  mediaBytes: bytes,
                  mediaName: m.name,
                  mediaMime: mime(m.type, m.name),
                );
              }
            }
          }
        } catch (e) {
          if (current()) passError = e.toString();
        }
      }
      if (current() && online() && me.isMember) {
        await (syncCloud ?? SyncService.instance.syncNow)();
      }
      if (current()) lastError = passError;
    } catch (e) {
      if (current()) lastError = e.toString();
    }
  }
}
