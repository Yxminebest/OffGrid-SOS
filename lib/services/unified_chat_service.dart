import 'dart:async';
import 'chat_action.dart';
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
import 'shared_snapshot.dart';

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
    this.replyToId,
    this.edited = false,
    this.retracted = false,
    this.deleted = false,
  });
  final String id, type, text, status, name;
  final String? replyToId;
  final bool edited, retracted, deleted;
  final DateTime at;
  final bool mine, read, lastKnown;
  final DateTime? locationAt;
  final String? path, mediaPath;
  final List<int>? bytes;
  final double? lat, lng, accuracy;
  final int? size;
  String get preview => retracted
      ? 'ยกเลิกข้อความแล้ว'
      : switch (type) {
          'image' => 'รูปภาพ',
          'video' => 'วิดีโอ',
          'location' => 'ตำแหน่งที่แชร์',
          _ => text,
        };
}

/// Rebuilds the visible conversation from the append-only wire history.
///
/// Chat edits, retractions, and delete-for-all operations are represented as
/// normal messages whose payload is a [ChatAction]. Keeping the history
/// append-only is important for offline delivery: an action can arrive before
/// or after its target, so this method sorts actions and applies only valid
/// same-author, same-thread changes. Retractions/deletions are terminal; a
/// delayed edit must never resurrect a removed message.
List<ChatItem> projectChatMessages(List<ChatItem> wire) {
  final originals = <String, ChatItem>{};
  final actions = <ChatItem>[];
  final replies = <String, String>{};
  for (final item in wire) {
    final action = item.type == 'text' ? ChatAction.parse(item.text) : null;
    if (action != null && action.kind != 'message') {
      actions.add(item);
    } else {
      originals[item.id] = item;
      if (action?.target.isNotEmpty ?? false) replies[item.id] = action!.target;
    }
  }
  actions.sort((a, b) {
    final time = a.at.compareTo(b.at);
    return time != 0 ? time : a.id.compareTo(b.id);
  });
  final latest = <String, ChatItem>{};
  final recalled = <String>{};
  final deleted = <String>{};
  for (final item in actions) {
    final action = ChatAction.parse(item.text)!;
    final target = originals[action.target];
    if (target == null ||
        target.mine != item.mine ||
        item.at.isBefore(target.at)) {
      continue;
    }
    if (action.kind == 'delete') {
      deleted.add(target.id);
      recalled.add(target.id);
      latest[target.id] = item;
    } else if (action.kind == 'retract' && !deleted.contains(target.id)) {
      recalled.add(target.id);
      latest[target.id] = item;
    } else if (['text', 'image', 'video', 'location'].contains(target.type) &&
        !recalled.contains(target.id)) {
      latest[target.id] = item;
    }
  }
  return originals.values.map((item) {
    final modification = latest[item.id];
    final action = modification == null
        ? null
        : ChatAction.parse(modification.text);
    final removed = recalled.contains(item.id);
    final message = item.type == 'text' ? ChatAction.parse(item.text) : null;
    return ChatItem(
      id: item.id,
      at: item.at,
      mine: item.mine,
      type: removed ? 'text' : item.type,
      text: removed
          ? 'ยกเลิกข้อความแล้ว'
          : action?.text ?? message?.text ?? item.text,
      status: modification?.status ?? item.status,
      name: item.name,
      path: removed ? null : item.path,
      mediaPath: removed ? null : item.mediaPath,
      bytes: removed ? null : item.bytes,
      lat: removed ? null : item.lat,
      lng: removed ? null : item.lng,
      accuracy: item.accuracy,
      size: item.size,
      read: item.read,
      lastKnown: item.lastKnown,
      locationAt: item.locationAt,
      replyToId: removed ? null : replies[item.id] ?? item.replyToId,
      edited: !removed && modification != null,
      retracted: removed,
      deleted: deleted.contains(item.id),
    );
  }).toList();
}

class ChatInboxEntry {
  const ChatInboxEntry(
    this.contact,
    this.messages, {
    this.cloudUnread = 0,
    this.fallbackPreview,
    this.fallbackAt,
    this.wireMessages,
  });
  final ChatContact contact;
  final List<ChatItem> messages;
  final List<ChatItem>? wireMessages;
  List<ChatItem> get transportMessages {
    final removed = [
      ...messages,
      ...projectChatMessages(wireMessages ?? []),
    ].where((m) => m.retracted || m.deleted).map((m) => m.id).toSet();
    // A cloud/local message may not have a Nearby row yet.  The old
    // implementation preferred `wireMessages` whenever it was non-null,
    // which meant an empty Nearby list hid pending offline cloud messages and
    // they never drained through a Bluetooth/Mesh route. Merge both stores by
    // ID; the wire row wins when it exists because it has the latest delivery
    // state and attachment path.
    final merged = <String, ChatItem>{
      for (final message in messages) message.id: message,
      for (final message in wireMessages ?? <ChatItem>[]) message.id: message,
    };
    return merged.values
        .where((m) => !removed.contains(m.id))
        .toList();
  }

  final int cloudUnread;
  final String? fallbackPreview;
  final DateTime? fallbackAt;
  String get preview => last?.preview ?? fallbackPreview ?? 'เริ่มสนทนา';
  DateTime get updatedAt => last?.at ?? fallbackAt ?? DateTime(2000);
  ChatItem? get last => messages.lastOrNull;
  int get unread {
    final count = messages
        .where((m) => !m.mine && !m.read && !m.retracted)
        .length;
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
    this.lookupExistingUsers,
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
  final Future<Set<String>> Function(AppUser, Set<String>)? lookupExistingUsers;
  DateTime? _directoryChecked;
  static final contacts = stringMapStoreFactory.store('unified_contacts');
  late final messages = MessageRepository(local: local);
  AppUser? _me;
  Timer? _timer;
  final _inboxes = <String, SharedSnapshot<List<ChatInboxEntry>>>{};
  bool _working = false, _rerun = false;
  Completer<void>? _activeWork;
  int _generation = 0;
  String? lastError;

  /// Starts the single per-user worker that drains radio first, then cloud.
  ///
  /// [start] is intentionally idempotent for the same account. When the
  /// account changes, [stop] invalidates the previous generation so an
  /// in-flight async callback cannot write data for the new account.
  void start(AppUser me) {
    if (_me?.id == me.id) return;
    stop();
    _me = me;
    mesh.addListener(_radioChanged);
    NetworkService.instance.online.addListener(_wake);
    // Sends and topology/network changes wake immediately. The fallback only
    // retries when a delivery path exists; idle offline phones do no DB scans.
    _timer = Timer.periodic(const Duration(seconds: 15), (_) {
      if (online() || mesh.reachablePeers.isNotEmpty) _wake();
    });
    _wake();
  }

  void stop() {
    _generation++;
    _me = null;
    mesh.removeListener(_radioChanged);
    _radioSignature = null;
    NetworkService.instance.online.removeListener(_wake);
    _directoryChecked = null;
    _timer?.cancel();
    _timer = null;
  }

  String? _radioSignature;
  void _radioChanged() {
    final peers =
        mesh.reachablePeers
            .map((p) => '${p.deviceId}:${p.userId}:${p.attestedUntil}')
            .toList()
          ..sort();
    final signature = peers.join('|');
    if (_radioSignature == signature) return;
    _radioSignature = signature;
    _wake();
  }

  /// This phone's Internet status, independent of the contact's cloud binding.
  static String deliveryLabel({required bool nearby, required bool cloud}) =>
      cloud ? 'ออนไลน์' : 'ออฟไลน์';

  void _wake() {
    unawaited(flush().catchError((_) {}));
  }

  /// Resolve notification identifiers only against this account's local inbox.
  /// Radio device IDs and cloud conversation IDs are different namespaces.
  Future<ChatContact?> notificationContact(
    String owner,
    String thread, {
    required String transport,
  }) async {
    if (mesh.ownerId != owner ||
        thread.isEmpty ||
        !['nearby', 'cloud'].contains(transport)) {
      return null;
    }
    final entries = await inbox(owner);
    if (mesh.ownerId != owner) return null;
    final direct = entries
        .where(
          (entry) => transport == 'cloud'
              ? entry.contact.conversation == thread
              : entry.contact.device == thread,
        )
        .firstOrNull;
    if (direct != null) return direct.contact;
    if (transport == 'nearby') {
      final binding = await contacts
          .record('$owner:$thread')
          .get(await local.database);
      if (mesh.ownerId != owner) return null;
      if (binding?['verified'] == true && binding?['user'] is String) {
        return entries
            .where((entry) => entry.contact.user == binding!['user'])
            .firstOrNull
            ?.contact;
      }
    }
    return null;
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
        'user': p.userId ?? (old?['verified'] == true ? (old?['user']) : null),
        'verified': p.userId != null || old?['verified'] == true,
        'attestedUntil': p.userId != null
            ? p.attestedUntil?.toIso8601String()
            : old?['attestedUntil'],
        'name': p.userId == null && old?['verified'] == true
            ? (old?['name'])
            : p.name,
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
      // A previously proven account ID is a cloud address, not a current
      // rescue/radio authorization. Live radio still checks current proof.
      if (value['verified'] != true) value['user'] = null;
      return value;
    }).toList();
    final byDevice = {for (final b in bindings) b['device'] as String: b};
    final hidden = await local.metaStore
        .record('deleted_chat_users:$owner')
        .get(db);
    final deletedUsers = Set<String>.from((hidden?['users'] as List?) ?? []);
    final hiddenMessageRows = await local.metaStore.find(
      db,
      finder: Finder(
        filter: Filter.and([
          Filter.equals('owner_id', owner),
          Filter.equals('kind', 'hidden_chat_message'),
        ]),
      ),
    );
    final hiddenMessageIds = hiddenMessageRows
        .map((r) => r.value['message_id'])
        .toSet();
    final hiddenDevices = Set<String>.from((hidden?['devices'] as List?) ?? []);
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
    final cloudMessages = cloud
        .map((row) => LocalMessageRecord.fromLocalMap(row.value))
        .toList();
    final incomingByConversation = <String, List<LocalMessageRecord>>{};
    for (final message in cloudMessages) {
      if (message.senderUserId != owner) {
        (incomingByConversation[message.conversationId] ??= []).add(message);
      }
    }
    final unreadCloudIds = <String>{};
    for (final c in convById.values) {
      final remote = incomingByConversation[c.id] ?? <LocalMessageRecord>[];
      remote.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      unreadCloudIds.addAll(remote.take(c.unreadCount).map((m) => m.id));
    }
    for (final m in cloudMessages) {
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
        replyToId: m.replyToId,
      );
      (groups[key] ??= {})[m.id] = item;
    }
    final archivedRows = await local.metaStore.find(
      db,
      finder: Finder(
        filter: Filter.and([
          Filter.equals('owner_id', owner),
          Filter.equals('kind', 'hidden_chat'),
        ]),
      ),
    );
    final archived = {
      for (final row in archivedRows)
        row.value['key']: DateTime.tryParse(row.value['at']?.toString() ?? ''),
    };
    final result =
        people.entries
            .where(
              (e) =>
                  !deletedUsers.contains(e.value.user) &&
                  !hiddenDevices.contains(e.value.device),
            )
            .map((e) {
              final list = (groups[e.key]?.values.toList() ?? <ChatItem>[])
                ..sort((a, b) => a.at.compareTo(b.at));
              final conv = convById.values
                  .where((v) => v.peerUserId == e.value.user)
                  .firstOrNull;
              final projected = projectChatMessages(list);
              final displayed = projected
                  .where((m) => !m.deleted && !hiddenMessageIds.contains(m.id))
                  .toList();
              final removed = projected
                  .where((m) => m.retracted)
                  .map((m) => m.id)
                  .toSet();
              final hiddenUnread = list.where((m) {
                final action = m.type == 'text'
                    ? ChatAction.parse(m.text)
                    : null;
                return !m.mine &&
                    !m.read &&
                    (removed.contains(m.id) ||
                        hiddenMessageIds.contains(m.id) ||
                        (action != null && action.kind != 'message'));
              }).length;
              final cloudUnread = (conv?.unreadCount ?? 0) - hiddenUnread;
              return ChatInboxEntry(
                e.value,
                displayed,
                wireMessages: list
                    .where((m) => !removed.contains(m.id))
                    .toList(),
                cloudUnread: cloudUnread > 0 ? cloudUnread : 0,
                fallbackPreview: list.isNotEmpty || conv?.lastMessage == null
                    ? null
                    : ChatAction.preview(conv!.lastMessage!),
                fallbackAt: conv?.lastMessageAt,
              );
            })
            .toList()
          ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return result.where((entry) {
      final times = [
        if (entry.contact.user != null) archived['user:${entry.contact.user}'],
        if (entry.contact.device != null)
          archived['device:${entry.contact.device}'],
      ].whereType<DateTime>();
      return times.every((at) => entry.updatedAt.isAfter(at));
    }).toList();
  }

  Stream<List<ChatInboxEntry>> watchInbox(String owner) => _inboxes
      .putIfAbsent(owner, () => SharedSnapshot(() => _watchInbox(owner)))
      .stream;

  Stream<List<ChatInboxEntry>> _watchInbox(String owner) => Stream.multi((
    events,
  ) {
    final subscriptions = <StreamSubscription>[];
    Timer? debounce;
    var cancelled = false;
    var reading = false;
    var dirty = false;

    Future<void> read() async {
      if (cancelled || reading) return;
      reading = true;
      try {
        do {
          dirty = false;
          try {
            final snapshot = await inbox(owner);
            if (!cancelled) events.add(snapshot);
          } catch (error, stack) {
            if (!cancelled) events.addError(error, stack);
          }
        } while (dirty && !cancelled);
      } finally {
        reading = false;
      }
    }

    void changed() {
      if (cancelled) return;
      dirty = true;
      debounce ??= Timer(const Duration(milliseconds: 40), () {
        debounce = null;
        unawaited(read());
      });
    }

    events.onCancel = () {
      cancelled = true;
      debounce?.cancel();
      for (final subscription in subscriptions) {
        unawaited(subscription.cancel());
      }
    };
    unawaited(() async {
      try {
        final db = await local.database;
        if (cancelled) return;
        final queries = [
          contacts.query(finder: Finder(filter: Filter.equals('owner', owner))),
          NearbyChatRepository.messages.query(
            finder: Finder(filter: Filter.equals('owner', owner)),
          ),
          local.messageStore.query(
            finder: Finder(filter: Filter.equals('owner_local_id', owner)),
          ),
          local.conversationStore.query(
            finder: Finder(filter: Filter.equals('owner_local_id', owner)),
          ),
          local.metaStore.query(),
        ];
        for (final query in queries) {
          subscriptions.add(
            query
                .onSnapshots(db)
                .listen(
                  (_) => changed(),
                  onError: (Object error, StackTrace stack) {
                    if (!cancelled) events.addError(error, stack);
                  },
                ),
          );
        }
        await read();
      } catch (error, stack) {
        if (!cancelled) events.addError(error, stack);
      }
    }());
  });

  Future<void> hideConversation(String owner, ChatContact contact) async {
    final db = await local.database;
    for (final key in [
      if (contact.user != null) 'user:${contact.user}',
      if (contact.device != null) 'device:${contact.device}',
    ]) {
      await local.metaStore.record('hidden_chat:$owner:$key').put(db, {
        'owner_id': owner,
        'kind': 'hidden_chat',
        'key': key,
        'at': DateTime.now().toUtc().toIso8601String(),
      });
    }
  }

  Future<void> _unhide(String owner, ChatContact contact) async {
    final db = await local.database;
    for (final key in [
      if (contact.user != null) 'user:${contact.user}',
      if (contact.device != null) 'device:${contact.device}',
    ]) {
      await local.metaStore.record('hidden_chat:$owner:$key').delete(db);
    }
  }

  Future<bool> unavailable(String owner, ChatContact contact) async {
    final row = await local.metaStore
        .record('deleted_chat_users:$owner')
        .get(await local.database);
    return ((row?['users'] as List?) ?? []).contains(contact.user) ||
        ((row?['devices'] as List?) ?? []).contains(contact.device);
  }

  Future<void> reconcileDeletedContacts(
    AppUser me, {
    bool force = false,
  }) async {
    if (!online() || !me.isMember || mesh.ownerId != me.id) return;
    if (!force &&
        _directoryChecked != null &&
        DateTime.now().difference(_directoryChecked!) <
            const Duration(minutes: 1)) {
      return;
    }
    final entries = await inbox(me.id);
    final users = entries
        .map((e) => e.contact.user)
        .whereType<String>()
        .toSet();
    if (users.isEmpty) return;
    final existing =
        await (lookupExistingUsers ?? ChatService.instance.existingUsers)(
          me,
          users,
        ).timeout(const Duration(seconds: 5));
    if (mesh.ownerId != me.id || !online()) return;
    _directoryChecked = DateTime.now();
    final missing = users.difference(existing);
    if (missing.isEmpty) return;
    final db = await local.database;
    await db.transaction((txn) async {
      final ref = local.metaStore.record('deleted_chat_users:${me.id}');
      final old = await ref.get(txn);
      final hiddenUsers = {
        ...List<String>.from((old?['users'] as List?) ?? []),
        ...missing,
      };
      final devices = {
        ...List<String>.from((old?['devices'] as List?) ?? []),
        ...entries
            .where((e) => missing.contains(e.contact.user))
            .map((e) => e.contact.device)
            .whereType<String>(),
      };
      await ref.put(txn, {
        'owner_id': me.id,
        'users': hiddenUsers.toList(),
        'devices': devices.toList(),
      });
      final rooms = await local.conversationStore.find(
        txn,
        finder: Finder(filter: Filter.equals('owner_local_id', me.id)),
      );
      final roomIds = rooms
          .where((r) => missing.contains(r.value['peer_user_id']))
          .map((r) => r.value['id'])
          .toSet();
      final messagesToCancel = await local.messageStore.find(
        txn,
        finder: Finder(filter: Filter.equals('owner_local_id', me.id)),
      );
      final ids = messagesToCancel
          .where((r) => roomIds.contains(r.value['conversation_id']))
          .map((r) => r.value['id'])
          .toSet();
      await local.syncQueueStore.delete(
        txn,
        finder: Finder(
          filter: Filter.and([
            Filter.equals('owner_local_id', me.id),
            Filter.equals('entity_type', 'message'),
            Filter.inList('entity_id', ids.whereType<String>().toList()),
          ]),
        ),
      );
      if (devices.isNotEmpty) {
        await NearbyChatRepository.messages.update(
          txn,
          {'historical': true, 'delivery': 'cancelled'},
          finder: Finder(
            filter: Filter.and([
              Filter.equals('owner', me.id),
              Filter.inList('peer', devices.toList()),
              Filter.equals('incoming', false),
            ]),
          ),
        );
      }
    });
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
    String? replyToId,
  }) async {
    if (path == null &&
        location == null &&
        (text.trim().isEmpty || text.length > 4000)) {
      throw ArgumentError('ข้อความต้องมี 1–4,000 ตัวอักษร');
    }
    if (replyToId != null) {
      final entry = (await inbox(me.id))
          .where(
            (e) =>
                (requested.user != null && e.contact.user == requested.user) ||
                (requested.device != null &&
                    e.contact.device == requested.device),
          )
          .firstOrNull;
      if (entry == null ||
          !entry.messages.any((m) => m.id == replyToId && !m.retracted)) {
        throw StateError('ไม่พบข้อความที่ต้องการตอบกลับ');
      }
    }
    await _sendWire(
      me,
      requested,
      text: path == null && location == null
          ? ChatAction.message(text, replyTo: replyToId)
          : text,
      location: location,
      path: path,
      name: name,
      type: type,
      messageId: messageId,
      caseId: caseId,
    );
  }

  Future<void> changeMessage(
    AppUser me,
    ChatContact requested,
    String id, {
    String? text,
    bool retract = false,
  }) => _changeMessage(me, requested, id, text: text, retract: retract);

  Future<void> _changeMessage(
    AppUser me,
    ChatContact requested,
    String id, {
    String? text,
    bool retract = false,
    bool deleteForAll = false,
  }) async {
    // The action is queued through the same durable path as ordinary chat
    // messages. This makes edit/retract/delete work offline and lets SyncService
    // replay it to Supabase later using the original message ID as its target.
    if (mesh.ownerId != me.id) throw StateError('บัญชีเปลี่ยนแล้ว');
    final entry = (await inbox(me.id))
        .where(
          (e) =>
              (requested.user != null && e.contact.user == requested.user) ||
              (requested.device != null &&
                  e.contact.device == requested.device),
        )
        .firstOrNull;
    final original = entry?.messages.where((m) => m.id == id).firstOrNull;
    if (original == null ||
        !original.mine ||
        (!deleteForAll && original.retracted)) {
      throw StateError('แก้ไขหรือยกเลิกได้เฉพาะข้อความของคุณ');
    }
    if (!retract &&
        !deleteForAll &&
        (!['text', 'image', 'video', 'location'].contains(original.type) ||
            text == null ||
            text.trim().isEmpty ||
            text.length > 4000)) {
      throw ArgumentError('ข้อความต้องมี 1–4,000 ตัวอักษร');
    }
    if (retract || deleteForAll) mesh.media.cancelMessage(id);
    await _sendWire(
      me,
      entry!.contact,
      text: deleteForAll
          ? ChatAction.delete(id)
          : retract
          ? ChatAction.retract(id)
          : ChatAction.edit(id, text!.trim()),
    );
    if (retract || deleteForAll) {
      // Stop the original durable radio queue as well as an active transfer.
      final db = await local.database;
      final row = await mesh.chats.find(me.id, id);
      if (row != null && row['incoming'] == false) {
        await NearbyChatRepository.messages.record('${me.id}:$id').update(db, {
          'historical': true,
          'cloudState': 'pending',
          'revision': (row['revision'] as int? ?? 0) + 1,
        });
      }
      final stored = await messages.findById(id);
      if (stored != null &&
          stored.ownerLocalId == me.id &&
          stored.senderUserId == me.id) {
        await messages.delete(stored);
      }
      _wake();
    }
  }

  /// Queues a delete-for-all action. The receiver projects that action locally
  /// and Supabase receives the same action during the next authenticated sync.
  Future<void> deleteMessage(AppUser me, ChatContact contact, String id) =>
      _changeMessage(me, contact, id, deleteForAll: true);

  Future<void> _sendWire(
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
        (text.trim().isEmpty || !ChatAction.validWire(text))) {
      throw ArgumentError('ข้อความต้องมี 1–4,000 ตัวอักษร');
    }
    if (await unavailable(me.id, requested)) {
      throw StateError('บัญชีผู้ติดต่อนี้ถูกลบแล้ว');
    }
    await _unhide(me.id, requested);
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
    final conv = c.conversation != null || c.device == null
        ? await _conversation(me, c)
        : null;
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
          recipientUser: c.user,
        );
      } else {
        await mesh.sendDirect(
          target: c.device!,
          text: location == null ? text : 'ตำแหน่งของฉัน',
          location: location,
          peerName: c.name,
          messageId: id,
          caseId: caseId,
          recipientUser: c.user,
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
    var retried = false;
    for (final m in entry.transportMessages.where(
      (m) =>
          m.mine && m.status != 'synced' && !m.status.startsWith('delivered'),
    )) {
      if (!current()) return;
      if (await mesh.chats.find(me.id, m.id) != null) {
        if (!retried) {
          retried = true;
          await mesh.retryFor(peer.deviceId);
        }
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
            recipientUser: c.user,
          );
        }
      } else {
        await mesh.sendDirect(
          target: peer.deviceId,
          text: m.text.isEmpty ? 'ตำแหน่งของฉัน' : m.text,
          messageId: m.id,
          recipientUser: c.user,
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
      var entries = await inbox(me.id);
      // Drain reachable radio queues before optional HTTP work. A slow cloud
      // request for one contact must not delay an SOS/chat peer nearby.
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
      if (current() && online() && me.isMember) {
        try {
          await reconcileDeletedContacts(me);
          entries = await inbox(me.id);
        } catch (_) {
          /* Directory failure never implies a deleted account. */
        }
      }
      for (final entry in entries) {
        if (!current()) return;
        try {
          var c = entry.contact;
          // Online is optional. Failure leaves the durable radio queue untouched.
          if (online() &&
              me.isMember &&
              c.user != null &&
              entry.transportMessages.any(
                (m) =>
                    m.mine &&
                    m.status != 'synced' &&
                    m.status != 'delivered_synced',
              )) {
            final conv = await _conversation(me, c);
            if (!current()) return;
            if (conv != null) {
              c = ChatContact(
                name: c.name,
                user: c.user,
                device: c.device,
                conversation: conv.id,
              );
              for (final m in entry.transportMessages.where(
                (m) =>
                    m.mine &&
                    m.status != 'synced' &&
                    m.status != 'delivered_synced',
              )) {
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
