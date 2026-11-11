import '../data/repositories/sos_response_repository.dart';
import 'radio_send_queue.dart';
import 'dart:async';
import 'chat_action.dart';
import 'mesh_room.dart';
import '../models/mesh_packet.dart';
import 'mesh/mesh_router.dart';
import 'mesh/mesh_router_store.dart';
import 'mesh/callback_mesh_transport.dart';
import 'sync_service.dart';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:nearby_connections/nearby_connections.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:sembast/sembast.dart';
import 'package:uuid/uuid.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'mesh_crypto.dart';
import 'mesh_attestation.dart';
import 'network_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show Supabase;
import 'location_service.dart';

import '../data/local/local_database.dart';
import '../data/models/local_sos_record.dart';
import '../data/repositories/sos_repository.dart';
import '../models/user.dart';
import 'android_permissions.dart';
import 'app_notifications.dart';
import 'bluetooth_link.dart';
import 'nearby_media_files.dart';
import 'nearby_media_transfer.dart';
import '../data/repositories/nearby_chat_repository.dart';

/// Paired Nearby links, durable direct chats, and revisioned SOS relay.
class MeshMessage {
  MeshMessage(this.data);
  final Map<String, dynamic> data;
  String get kind => data['kind']?.toString() ?? '';
  String get id => data['id']?.toString() ?? '';
}

class NearbyPeer {
  const NearbyPeer({
    required this.endpoint,
    required this.deviceId,
    required this.name,
    String? userId,
    this.hops = 1,
    this.verifiedRole,
    this.attestedUntil,
    // Keep the public constructor name while the getter enforces expiration.
    // ignore: prefer_initializing_formals
  }) : _userId = userId;
  final String endpoint, deviceId, name;
  final String? _userId;
  String? get userId =>
      attestedUntil == null || DateTime.now().isBefore(attestedUntil!)
      ? _userId
      : null;
  final int hops;
  final String? verifiedRole;
  final DateTime? attestedUntil;
  bool get verifiedRescuer =>
      attestedUntil != null &&
      DateTime.now().isBefore(attestedUntil!) &&
      (verifiedRole == 'rescuer' || verifiedRole == 'admin');
}

class MeshRoute {
  MeshRoute(this.certificate, this.via, this.hops, this.expires, this.path);
  final Map<String, dynamic> certificate;
  final String via;
  final int hops;
  DateTime expires;
  final List<String> path;
}

class NearbyMeshService extends ChangeNotifier {
  NearbyMeshService._()
    : _local = LocalDatabase.instance,
      _sendOverride = null,
      _disconnectOverride = null,
      _testStorage = false,
      _verifyAttestation = MeshAttestation.verify,
      _mediaFiles = null;
  NearbyMeshService.withDatabase(
    LocalDatabase local, {
    Future<void> Function(String, Uint8List)? sendBytes,
    Future<void> Function(String)? disconnect,
    this._mediaFiles,
    Future<MeshAttestationClaims?> Function(Object?, Map<String, dynamic>)?
    verifyAttestation,
  }) : _local = local,
       _testStorage = true,
       _verifyAttestation = verifyAttestation ?? MeshAttestation.verify,
       _sendOverride = sendBytes,
       _disconnectOverride = disconnect;
  static final instance = NearbyMeshService._();
  static const serviceId = 'com.offgridsos.nearby';
  Nearby? _nearbyInstance;
  Nearby get _nearby => _nearbyInstance ??= Nearby();
  final LocalDatabase _local;
  final Future<void> Function(String, Uint8List)? _sendOverride;
  final Future<void> Function(String)? _disconnectOverride;
  final NearbyMediaFiles? _mediaFiles;
  final bool _testStorage;
  final Future<MeshAttestationClaims?> Function(Object?, Map<String, dynamic>)
  _verifyAttestation;
  late final crypto = MeshCrypto(
    read: (key) async {
      if (!_testStorage) return const FlutterSecureStorage().read(key: key);
      return (await _local.metaStore
              .record(key)
              .get(await _local.database))?['value']
          as String?;
    },
    write: (key, value) async {
      if (!_testStorage) {
        await const FlutterSecureStorage().write(key: key, value: value);
        return;
      }
      await _local.metaStore.record(key).put(await _local.database, {
        'owner_id': _ownerId,
        'value': value,
      });
    },
  );
  final routes = <String, MeshRoute>{};
  final _routeCandidates = <String, Map<String, MeshRoute>>{};
  final _retryingTargets = <String>{};
  final _connectingSince = <String, DateTime>{};
  final _passiveSince = <String, DateTime>{};
  final _bluetoothReconnect = <String>{};

  /// One automatic initiator per stable device pair avoids crossed requests.
  static bool initiatesAutomatically(
    String local,
    String remote, {
    Duration waited = Duration.zero,
  }) =>
      local.isEmpty ||
      remote.isEmpty ||
      discoveryHint(local).compareTo(remote) < 0 ||
      // A short deterministic fallback keeps the two phones from racing while
      // avoiding the long delay users experienced when the preferred initiator
      // was slow to receive the discovery callback.
      waited >= const Duration(seconds: 5);

  Set<String> _removeRoutes(bool Function(String, MeshRoute) invalid) {
    final affected = <String>{};
    for (final entry in _routeCandidates.entries.toList()) {
      entry.value.removeWhere((_, route) {
        final remove = invalid(entry.key, route);
        if (remove) affected.add(entry.key);
        return remove;
      });
      _selectRoute(entry.key);
    }
    // Also handle legacy/test routes installed without a candidate table.
    for (final entry in routes.entries.toList()) {
      if (!_routeCandidates.containsKey(entry.key) &&
          invalid(entry.key, entry.value)) {
        routes.remove(entry.key);
        affected.add(entry.key);
      }
    }
    return affected;
  }

  void _selectRoute(String target) {
    final candidates = _routeCandidates[target];
    if (candidates == null) return;
    candidates.removeWhere(
      (_, r) =>
          !connected.contains(r.via) || r.expires.isBefore(DateTime.now()),
    );
    if (candidates.isEmpty) {
      _routeCandidates.remove(target);
      routes.remove(target);
      return;
    }
    final old = routes[target];
    final choices = candidates.values.toList()
      ..sort((a, b) {
        if (identical(a, b)) return 0;
        final distance = a.hops.compareTo(b.hops);
        if (distance != 0) return distance;
        if (a.via == old?.via) return -1;
        if (b.via == old?.via) return 1;
        return a.via.compareTo(b.via);
      });
    routes[target] = choices.first;
  }

  final _routeSeen = <String, int>{};
  DateTime _lastAdvertised = DateTime.fromMillisecondsSinceEpoch(0);
  bool _canRescue = false;
  Map<String, dynamic>? _attestation;
  MeshAttestationClaims? _ownClaims;
  final _verifiedPeers = <String, MeshAttestationClaims>{};
  final _verifiedKeys = <String, String>{};
  final _identityChallenges =
      <String, ({String nonce, String keys, DateTime expires})>{};
  DateTime _nextAttestation = DateTime.fromMillisecondsSinceEpoch(0);
  bool _refreshingAttestation = false;
  bool get hasRescueAttestation => _ownClaims?.rescuer == true;
  Future<bool> installAttestation(Map<String, dynamic> proof) async {
    final owner = _ownerId;
    final generation = _sessionGeneration;
    if (owner == null || _memberId == null) return false;
    final cert = await crypto.certificate(deviceId, displayName, _memberId);
    final claims = await _verifyAttestation(proof, cert);
    if (claims == null ||
        generation != _sessionGeneration ||
        _ownerId != owner) {
      return false;
    }
    await crypto.write('mesh_attestation_$owner', jsonEncode(proof));
    if (generation != _sessionGeneration || _ownerId != owner) return false;
    _attestation = Map<String, dynamic>.from(proof);
    _ownClaims = claims;
    notifyListeners();
    return true;
  }

  String get attestationStatus => hasRescueAttestation
      ? 'ใบรับรองกู้ภัยพร้อมใช้แบบออฟไลน์'
      : 'เชื่อมต่ออินเทอร์เน็ตเพื่อรับหรือต่ออายุใบรับรองกู้ภัย';

  /// Optional online renewal; cached proofs are verified locally on startup.
  /// No network request is awaited by discovery, SOS, or a radio chat send.
  Future<void> refreshAttestation({bool force = false}) async {
    if (_testStorage ||
        _memberId == null ||
        _ownerId == null ||
        _refreshingAttestation ||
        !NetworkService.instance.online.value ||
        (!force && DateTime.now().isBefore(_nextAttestation))) {
      return;
    }
    final owner = _ownerId!;
    final generation = _sessionGeneration;
    _refreshingAttestation = true;
    _nextAttestation = DateTime.now().add(const Duration(seconds: 20));
    try {
      final client = Supabase.instance.client;
      if (client.auth.currentUser?.id != owner) return;
      final cert = await crypto.certificate(deviceId, displayName, _memberId);
      final response = await client.functions
          .invoke('mesh-attestation', body: {'certificate': cert})
          .timeout(const Duration(seconds: 12));
      final proof = Map<String, dynamic>.from(response.data as Map);
      final claims = await MeshAttestation.verify(proof, cert);
      if (claims == null ||
          generation != _sessionGeneration ||
          _ownerId != owner ||
          client.auth.currentUser?.id != owner) {
        return;
      }
      await crypto.write('mesh_attestation_$owner', jsonEncode(proof));
      if (generation != _sessionGeneration || _ownerId != owner) return;
      _attestation = proof;
      _ownClaims = claims;
      _nextAttestation = DateTime.now().add(const Duration(hours: 6));
      if (!claims.rescuer && rescueActive) await setRescue(false);
      await _advertise();
      notifyListeners();
    } catch (_) {
      // An outage never replaces a valid cached proof with an unverified claim.
    } finally {
      _refreshingAttestation = false;
    }
  }

  int _rescueRevision = 0;
  late final chats = NearbyChatRepository(local: _local);
  late final room = MeshRoom(_local);
  MeshRouter? _roomRouter;
  CallbackMeshTransport? _roomTransport;

  Future<void> _initializeRoomRouter() async {
    final owner = _ownerId!;
    final generation = _sessionGeneration;
    final transport = CallbackMeshTransport(
      connectPeer: (id) => connect(id),
      disconnectPeer: _disconnect,
      sendPacket: (id, packet) async {
        if (generation != _sessionGeneration || _ownerId != owner) {
          throw StateError('Mesh session ended');
        }
        await _direct(id, packet.toEnvelope());
      },
    );
    final router = MeshRouter(
      nodeId: deviceId,
      transport: transport,
      store: LocalMeshRouterStore(_local, '$owner:$deviceId'),
      validate: (packet) async {
        final event = packet.toEnvelope();
        final certificate = event['certificate'];
        final body = event['data'];
        return generation == _sessionGeneration &&
            _ownerId == owner &&
            event['kind'] == 'room' &&
            certificate is Map &&
            body is Map &&
            body['text'] is String &&
            (body['text'] as String).trim().isNotEmpty &&
            ChatAction.validWire(body['text'] as String) &&
            await crypto.accept(Map<String, dynamic>.from(certificate)) &&
            await crypto.verifyStatus(certificate, event);
      },
      onDeliver: (packet) async {
        if (generation == _sessionGeneration && _ownerId == owner) {
          await room.save(
            owner,
            packet.toEnvelope(),
            incoming: packet.senderId != deviceId,
          );
        }
      },
    );
    _roomTransport = transport;
    _roomRouter = router;
    await router.start();
    transport.updatePeers(connected);
  }

  void _closeRoomRouter() {
    final router = _roomRouter;
    final transport = _roomTransport;
    _roomRouter = null;
    _roomTransport = null;
    if (router != null) unawaited(router.close());
    if (transport != null) unawaited(transport.close());
  }

  String _roomKey(Map<String, dynamic> event) =>
      '${event['origin']}:${event['id']}';

  Future<void> _syncRoom(String endpoint) async {
    final owner = _ownerId;
    if (owner == null) return;
    final events = await room.events(owner);
    // Small inventories repair dropped broadcasts without retransmitting the
    // entire history on every health tick. Requests/replays are idempotent.
    for (var i = 0; i < events.length; i += 64) {
      if (_ownerId != owner || !connected.contains(endpoint)) return;
      await _direct(
        endpoint,
        _envelope('room_inventory', {
          'keys': events.skip(i).take(64).map(_roomKey).toList(),
        }),
      );
    }
  }

  /// Public disaster bulletin: every relay persists and forwards signed events.
  /// Unlike private chat, all participating phones can read this room.
  Future<void> sendRoom(String text) async {
    await _sessionWork;
    final owner = _ownerId;
    final generation = _sessionGeneration;
    if (owner == null) throw StateError('กรุณาเข้าสู่ระบบก่อน');
    if (text.trim().isEmpty || !ChatAction.validWire(text)) {
      throw ArgumentError('ข้อความว่างหรือยาวเกินกำหนด');
    }
    final event = _envelope('room', {'text': text}, ttl: 6);
    event['certificate'] = await crypto.certificate(
      deviceId,
      displayName,
      _memberId,
    );
    await crypto.signStatus(event);
    if (utf8.encode(jsonEncode(event)).length > 32768) {
      throw ArgumentError('ข้อความยาวเกินขนาดที่ส่งผ่านเครือข่ายได้');
    }
    if (generation != _sessionGeneration) return;
    if (generation == _sessionGeneration) {
      await _roomRouter!.send(MeshPacket.fromEnvelope(event));
    }
  }

  late final sosResponses = SosResponseRepository(_local);
  final _radioSendQueue = RadioSendQueue();
  late final media = NearbyMediaTransfer(
    chats: chats,
    files: _mediaFiles ?? NearbyMediaFiles(),
    owner: () => _ownerId,
    device: () => deviceId,
    makeFrame: (kind, body) => _envelope(kind, body),
    sendFrame: (target, frame) async {
      await _sendTo(target, frame);
    },
    changed: _mediaChanged,
    received: (env) async {
      _remember(env);
      await AppNotifications.instance.show(
        id: env['id'],
        title: env['sender']?.toString() ?? 'ไฟล์ Nearby',
        text: (env['data'] as Map)['type'] == 'image'
            ? 'ส่งรูปภาพให้คุณ'
            : 'ส่งวิดีโอให้คุณ',
        thread: env['origin'],
        owner: _ownerId,
        transport: 'nearby',
      );
    },
  );
  String? get ownerId => _ownerId;
  LocalDatabase get localDatabase => _local;
  String? _memberId;
  final identities = <String, NearbyPeer>{};
  final _lastSeen = <String, DateTime>{};
  final _probeFailures = <String, int>{};
  Timer? _healthTimer;
  Future<void> _receiveWork = Future<void>.value();
  DateTime _lastRetry = DateTime.fromMillisecondsSinceEpoch(0);
  bool _checkingHealth = false;
  DateTime _lastHealthTick = DateTime.now();
  NearbyPeer? peerForDevice(String id) {
    for (final peer in identities.values) {
      if (peer.deviceId == id && connected.contains(peer.endpoint)) return peer;
    }
    final route = routes[id];
    if (route == null ||
        !connected.contains(route.via) ||
        route.expires.isBefore(DateTime.now())) {
      return null;
    }
    return NearbyPeer(
      endpoint: route.via,
      deviceId: id,
      name: route.certificate['name'] as String,
      userId: _verifiedPeers[id]?.current == true
          ? _verifiedPeers[id]!.userId
          : null,
      verifiedRole: _verifiedPeers[id]?.role,
      attestedUntil: _verifiedPeers[id]?.expiresAt,
      hops: route.hops,
    );
  }

  Iterable<NearbyPeer> get reachablePeers => {
    ...identities.values.map((p) => p.deviceId),
    ...routes.keys,
  }.map(peerForDevice).whereType<NearbyPeer>();

  NearbyPeer? peerForUser(String id) {
    for (final peer in reachablePeers) {
      if (peer.userId == id && connected.contains(peer.endpoint)) return peer;
    }
    return null;
  }

  String deviceId = '';
  String? _ownerId;
  Future<void> _sessionWork = Future<void>.value();
  int _sessionGeneration = 0;
  // sessionGeneration กันงานบัญชีเก่า; radioGeneration กัน callback จากวิทยุรอบเก่า
  int _radioGeneration = 0;
  bool needsPermissionSettings = false;
  bool needsLocationSettings = false;
  String? activeSosId;
  final Map<String, String> peers = {};
  final Set<String> connected = {};
  final List<MeshMessage> inbox = [];
  final Set<String> _seen = {};
  String status = 'ยังไม่ได้เริ่มค้นหา';
  String displayName = 'SOSBROO';
  bool running = false;
  bool busy = false;
  bool rescueActive = false;
  final _completedRescueCases = <String>{};

  /// Persisted active state is history, not evidence of current proximity.
  List<MeshMessage> get currentSosCases {
    final latest = <String, MeshMessage>{};
    for (final message in inbox) {
      final body = message.data['data'];
      final origin = message.data['origin']?.toString();
      if (message.kind != 'sos' ||
          body is! Map ||
          body['caseId'] is! String ||
          origin == null ||
          origin == deviceId) {
        continue;
      }
      latest.putIfAbsent('$origin:${body['caseId']}', () => message);
    }
    return latest.values
        .where(
          (m) =>
              (m.data['data'] as Map)['active'] == true &&
              !_completedRescueCases.contains(
                '${m.data['origin']}:${(m.data['data'] as Map)['caseId']}',
              ) &&
              peerForDevice(m.data['origin'].toString()) != null,
        )
        .toList();
  }

  /// Nearby chooses its radio internally; do not claim it is Wi-Fi.
  String get connectionLabel {
    final bluetooth = connected.where((id) => id.startsWith('bt:')).length;
    final nearby = connected.length - bluetooth;
    if (bluetooth > 0 && nearby > 0) return 'Bluetooth โดยตรง + Nearby';
    if (bluetooth > 0) return 'Bluetooth โดยตรง';
    if (nearby > 0) return 'Nearby Connections';
    return 'ยังไม่เชื่อมต่อ';
  }

  /// A case conversation does not imply that the other participant is rescue.
  bool isPeerRescueActive(String device) {
    if (peerForDevice(device)?.verifiedRescuer != true) return false;
    for (final message in inbox) {
      if (message.kind == 'rescue' && message.data['origin'] == device) {
        return (message.data['data'] as Map?)?['active'] == true;
      }
    }
    return false;
  }

  String chatPeerName(String device, {String? fallback}) {
    final peer = peerForDevice(device);
    if (peer != null && peer.name.trim().isNotEmpty) return peer.name;
    for (final message in inbox) {
      if (message.data['origin'] == device) {
        final name = message.data['sender']?.toString().trim();
        if (name != null && name.isNotEmpty) return name;
      }
    }
    final name = fallback?.trim() ?? '';
    // Legacy releases stored the SOS action title as the contact name.
    return name.isEmpty ||
            name == 'แชทกับหน่วยกู้ภัย' ||
            name == 'แชทกับบุคคลใกล้เคียง'
        ? 'บุคคลใกล้เคียง'
        : name;
  }

  Map<String, dynamic>? mySos;
  LocalSosRecord? ownSosRecord;
  final _pairingQueue = <({String id, String name, String token})>[];
  String? pendingPeer;
  String? pendingToken;
  String? pendingName;

  Future<void> _queueSessionWork(Future<void> Function() action) {
    final operation = _sessionWork.then((_) => action());
    // Keep later lifecycle operations usable even if initialization failed.
    _sessionWork = operation.then<void>(
      (_) {},
      onError: (Object error, StackTrace stack) {},
    );
    return operation;
  }

  Future<void> initializeForUser(AppUser user) {
    return _queueSessionWork(() async {
      if (_ownerId != user.id) {
        await _loadSession(user);
      } else {
        _canRescue = user.isVerifiedRescuer;
        displayName = user.fullName;
        if (!_canRescue && rescueActive) await setRescue(false);
      }
    });
  }

  Future<void> _loadSession(AppUser user) async {
    final generation = ++_sessionGeneration;
    await stop(remember: false);
    final db = await _local.database;
    final identity = await db.transaction((txn) async {
      final key = 'nearby_identity_${user.id}';
      final existing = await _local.metaStore.record(key).get(txn);
      final stored = existing?['device_id']?.toString();
      if (stored != null && stored.isNotEmpty) return stored;
      final id = const Uuid().v4();
      await _local.metaStore.record(key).put(txn, {
        'owner_id': user.id,
        'device_id': id,
      });
      return id;
    });
    final active = await SosRepository(local: _local).latestActive(user.id);
    if (generation != _sessionGeneration) return;
    _clearSession();
    _ownerId = user.id;
    _canRescue = user.isVerifiedRescuer;
    await crypto.initialize(user.id);
    if (generation != _sessionGeneration) return;
    _rescueRevision = DateTime.now().microsecondsSinceEpoch;
    _memberId = user.isMember ? user.id : null;
    deviceId = identity;
    displayName = user.fullName;
    final cachedProof = await crypto.read('mesh_attestation_${user.id}');
    if (generation != _sessionGeneration) return;
    if (cachedProof != null) {
      try {
        final cert = await crypto.certificate(deviceId, displayName, _memberId);
        final proof = Map<String, dynamic>.from(jsonDecode(cachedProof) as Map);
        final claims = await _verifyAttestation(proof, cert);
        if (generation != _sessionGeneration) return;
        if (claims != null) {
          _attestation = proof;
          _ownClaims = claims;
        }
      } catch (_) {}
    }
    if (active != null) _restoreSos(active);
    final savedStates = await chats.loadSos(user.id);
    if (generation != _sessionGeneration) return;
    inbox.addAll(savedStates.map(MeshMessage.new));
    final completed = await sosResponses.completedCases(user.id);
    if (generation != _sessionGeneration) return;
    _completedRescueCases.addAll(completed);
    await _initializeRoomRouter();
    _notify('พร้อมใช้งาน Nearby • กดเริ่มเพื่อค้นหาอุปกรณ์');
  }

  void _restoreSos(LocalSosRecord record) {
    ownSosRecord = record;
    activeSosId = record.id;
    final recordedAt = record.locationRecordedAt;
    mySos = {
      'active': true,
      'revision': record.revision,
      'caseId': record.id,
      'text': record.message,
      'lat': record.latitude,
      'lng': record.longitude,
      'accuracy': record.accuracy,
      'recordedAt': recordedAt?.toUtc().toIso8601String(),
      'lastKnown':
          record.isLastKnownLocation ||
          recordedAt == null ||
          DateTime.now().difference(recordedAt).abs() >
              const Duration(minutes: 2),
    };
  }

  Future<int> publishSosRecord(LocalSosRecord record) async {
    await _sessionWork;
    if (_ownerId != record.ownerLocalId) {
      throw StateError('SOS owner does not match Nearby session.');
    }
    final generation = _sessionGeneration;
    final latest = await SosRepository(local: _local).findById(record.id);
    if (generation != _sessionGeneration || _ownerId != record.ownerLocalId) {
      return 0;
    }
    if (latest == null) return 0;
    if (!latest.isActive) return stopSos(caseId: latest.id);
    _restoreSos(latest);
    return send('sos', mySos!);
  }

  void _clearSession() {
    _closeRoomRouter();
    _completedRescueCases.clear();
    _ownerId = null;
    _memberId = null;
    identities.clear();
    routes.clear();
    _routeCandidates.clear();
    _connectingSince.clear();
    _passiveSince.clear();
    _bluetoothReconnect.clear();
    _routeSeen.clear();
    _canRescue = false;
    _attestation = null;
    _ownClaims = null;
    _verifiedPeers.clear();
    _verifiedKeys.clear();
    _identityChallenges.clear();
    _nextAttestation = DateTime.fromMillisecondsSinceEpoch(0);
    _lastSeen.clear();
    deviceId = '';
    activeSosId = null;
    mySos = null;
    ownSosRecord = null;
    rescueActive = false;
    inbox.clear();
    _seen.clear();
    peers.clear();
    _discoveryHints.clear();
    _discoveredAt.clear();
    _visibleEndpoints.clear();
    discoveredModes.clear();
    connected.clear();
    _pairingQueue.clear();
    pendingPeer = null;
    pendingName = null;
    pendingToken = null;
    displayName = 'SOSBROO';
    needsPermissionSettings = false;
    needsLocationSettings = false;
  }

  Future<void> resetSession() {
    ++_sessionGeneration;
    ++_radioGeneration;
    return _queueSessionWork(() async {
      await stop();
      _clearSession();
      _notify('ยังไม่ได้เริ่มค้นหา');
    });
  }

  Future<void> deleteIdentity(String owner) async {
    if (_testStorage) return;
    const store = FlutterSecureStorage();
    for (final key in (await store.readAll()).keys) {
      if (key == 'mesh_keys_v1_$owner' ||
          key == 'mesh_attestation_$owner' ||
          key.startsWith('mesh_pin_${owner}_')) {
        await store.delete(key: key);
      }
    }
  }

  // Debug-only local demo. Never uses Nearby radios or writes cloud data.
  static const String demoOrigin = 'debug-emulator-requester';
  bool get hasDemoCase => inbox.any(
    (m) =>
        m.kind == 'sos' &&
        m.data['origin'] == demoOrigin &&
        (m.data['data'] as Map?)?['active'] == true,
  );
  bool isDemoOrigin(String origin) => kDebugMode && origin == demoOrigin;

  void createDemoSos() {
    if (!kDebugMode) {
      return;
    }
    final now = DateTime.now().toUtc().toIso8601String();
    final caseId = const Uuid().v4();
    // Location intentionally uses the standard Android emulator coordinates.
    _addDemoEnvelope('sos', demoOrigin, {
      'caseId': caseId,
      'active': true,
      'text': '[ทดสอบ] ต้องการความช่วยเหลือบริเวณนี้',
      'lat': 37.4219983,
      'lng': -122.084,
      'accuracy': 5,
      'lastKnown': true,
      'recordedAt': now,
    });
  }

  void closeDemoSos(String caseId) {
    if (!kDebugMode) {
      return;
    }
    _addDemoEnvelope('sos', demoOrigin, {'caseId': caseId, 'active': false});
  }

  void _addDemoEnvelope(String kind, String origin, Map<String, dynamic> body) {
    if (!kDebugMode) {
      return;
    }
    final envelope = <String, dynamic>{
      'v': 1,
      'id': const Uuid().v4(),
      'kind': kind,
      'origin': origin,
      'sender': origin == demoOrigin
          ? 'ผู้แจ้งเหตุจำลอง'
          : 'หน่วยกู้ภัย (ทดสอบ)',
      'at': DateTime.now().toUtc().toIso8601String(),
      'ttl': 0,
      'data': body,
      'simulation': true,
    };
    inbox.insert(0, MeshMessage(envelope));
    if (inbox.length > 150) {
      inbox.removeLast();
    }
    notifyListeners();
  }

  Future<int> sendDemoCaseReply({
    required String caseId,
    required String target,
    required String text,
  }) async {
    if (!kDebugMode || target != demoOrigin) {
      return 0;
    }
    _addDemoEnvelope('case_chat', deviceId, {
      'caseId': caseId,
      'target': target,
      'text': text,
    });
    // This represents a simulated incoming response, not real delivery.
    _addDemoEnvelope('case_chat', demoOrigin, {
      'caseId': caseId,
      'target': deviceId,
      'text': 'รับข้อความแล้ว (การตอบกลับจำลอง)',
    });
    return 1;
  }

  void _notify([String? text]) {
    if (text != null) status = text;
    notifyListeners();
  }

  final discoveredModes = <String, String>{};
  final _visibleEndpoints = <String>{};
  String _advertisedName = '';
  Future<void> _advertisingWork = Future.value();
  String get discoveryName {
    final mode = mySos?['active'] == true
        ? 'S'
        : rescueActive
        ? 'R'
        : 'N';
    final name = String.fromCharCodes(displayName.runes.take(24));
    final hint = discoveryHint(deviceId);
    return hint.isEmpty ? 'OG9:$mode:$name' : 'OG10:$mode:$hint:$name';
  }

  static ({String name, String mode}) parseDiscoveryName(String raw) {
    final modern = RegExp(
      r'^OG10:([SRN]):([A-Za-z0-9_-]{1,64}):(.*)$',
    ).firstMatch(raw);
    if (modern != null) return (name: modern.group(3)!, mode: modern.group(1)!);
    final match = RegExp(r'^OG9:([SRN]):(.*)$').firstMatch(raw);
    return (name: match?.group(2) ?? raw, mode: match?.group(1) ?? 'N');
  }

  static String discoveryHint(String id) {
    final safe = id.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '');
    return safe.length > 48 ? safe.substring(0, 48) : safe;
  }

  final _discoveryHints = <String, String>{};
  final _discoveredAt = <String, DateTime>{};

  String _visibleKey(String endpoint) {
    final identity = identities[endpoint];
    final hint = identity == null
        ? _discoveryHints[endpoint]
        : discoveryHint(identity.deviceId);
    return hint == null || hint.isEmpty ? 'endpoint:$endpoint' : 'device:$hint';
  }

  /// Never merge by display name: different people can have the same name.
  Map<String, String> get visiblePeers {
    final grouped = <String, String>{};
    final endpoints = {
      ...peers.keys,
      ...identities.keys.where(connected.contains),
    };
    for (final endpoint in endpoints) {
      if (identities[endpoint]?.deviceId == deviceId) continue;
      final hint = _discoveryHints[endpoint];
      if (!connected.contains(endpoint) &&
          hint != null &&
          reachablePeers.any(
            (p) => p.hops > 1 && discoveryHint(p.deviceId) == hint,
          )) {
        continue;
      }
      final key = _visibleKey(endpoint);
      final previous = grouped[key];
      int rank(String id) =>
          (connected.contains(id) ? 2 : 0) +
          (identities.containsKey(id) ? 1 : 0);
      if (previous == null ||
          rank(endpoint) > rank(previous) ||
          (rank(endpoint) == rank(previous) &&
              (_discoveredAt[endpoint] ?? DateTime(2000)).isAfter(
                _discoveredAt[previous] ?? DateTime(2000),
              ))) {
        grouped[key] = endpoint;
      }
    }
    return {
      for (final endpoint in grouped.values)
        endpoint:
            identities[endpoint]?.name ?? peers[endpoint] ?? 'บุคคลใกล้เคียง',
    };
  }

  int get connectedDeviceCount => connected.map(_visibleKey).toSet().length;

  final _autoAttempts = <String, DateTime>{};
  final _autoPending = <String>{};
  // Discovery is passive: every new radio link requires a user request and
  // approval on the receiving phone, including previously paired devices.
  final bool automaticConnections = false;

  Future<void> _connectAutomatically(String endpoint) async {
    final generation = _radioGeneration;
    final last = _autoAttempts[endpoint];
    final hint = _discoveryHints[endpoint];
    final waitingSince = _passiveSince.putIfAbsent(endpoint, DateTime.now);
    if (hint != null &&
        !initiatesAutomatically(
          deviceId,
          hint,
          waited: DateTime.now().difference(waitingSince),
        )) {
      return;
    }
    if (connected.any(
      (id) => id != endpoint && _visibleKey(id) == _visibleKey(endpoint),
    )) {
      return;
    }
    if (!automaticConnections ||
        !running ||
        connected.contains(endpoint) ||
        _autoPending.contains(endpoint) ||
        connected.length >= 8 ||
        _autoPending.length >= 6 ||
        (last != null &&
            DateTime.now().difference(last) < const Duration(seconds: 6))) {
      return;
    }
    _autoPending.add(endpoint);
    _autoAttempts[endpoint] = DateTime.now();
    try {
      // Different short delays reduce simultaneous cross-requests while making
      // the first connection feel immediate after discovery.
      await Future<void>.delayed(
        Duration(milliseconds: 100 + endpoint.hashCode.abs() % 300),
      );
      if (generation != _radioGeneration ||
          !running ||
          !peers.containsKey(endpoint) ||
          connected.contains(endpoint)) {
        return;
      }
      await connect(endpoint);
    } finally {
      _autoPending.remove(endpoint);
    }
  }

  Future<void> _acceptAutomatically(String id) async {
    final generation = _radioGeneration;
    try {
      if (connected.length >= 8) {
        await _nearby.rejectConnection(id);
        return;
      }
      await _nearby.acceptConnection(
        id,
        onPayLoadRecieved: (from, payload) {
          if (generation == _radioGeneration) _received(from, payload);
        },
      );
    } catch (_) {
      /* Discovery will retry a failed radio handshake. */
    }
  }

  void discovered(String endpoint, String raw) {
    _visibleEndpoints.add(endpoint);
    final value = parseDiscoveryName(raw);
    peers[endpoint] = value.name;
    _discoveredAt[endpoint] = DateTime.now();
    final modern = RegExp(
      r'^OG10:[SRN]:([A-Za-z0-9_-]{1,64}):',
    ).firstMatch(raw);
    if (modern != null) {
      final hint = modern.group(1)!;
      // Android rotates endpoint IDs after advertising restarts. Retire the
      // previous discovery, not just its visible row, so retries use the new ID.
      for (final old in _discoveryHints.keys.toList()) {
        if (old == endpoint ||
            _discoveryHints[old] != hint ||
            connected.contains(old)) {
          continue;
        }
        _visibleEndpoints.remove(old);
        peers.remove(old);
        discoveredModes.remove(old);
        _discoveryHints.remove(old);
        _discoveredAt.remove(old);
        _autoAttempts.remove(old);
        _passiveSince.remove(old);
      }
      _discoveryHints[endpoint] = hint;
    }
    discoveredModes[endpoint] = value.mode;
    unawaited(_connectAutomatically(endpoint));
    notifyListeners();
  }

  Future<bool> _startAdvertising(int generation) async {
    final name = discoveryName;
    final result = await _nearby.startAdvertising(
      name,
      Strategy.P2P_CLUSTER,
      onConnectionInitiated: (id, info) {
        if (generation == _radioGeneration) _initiated(id, info);
      },
      onConnectionResult: (id, result) {
        if (generation == _radioGeneration) _result(id, result);
      },
      onDisconnected: (id) {
        if (generation == _radioGeneration) _disconnected(id);
      },
      serviceId: serviceId,
    );
    if (result) _advertisedName = name;
    return result;
  }

  Future<void> _refreshDiscovery() {
    final generation = _radioGeneration;
    return _advertisingWork = _advertisingWork.then((_) async {
      if (_nearbyInstance == null ||
          !running ||
          generation != _radioGeneration ||
          _advertisedName == discoveryName) {
        return;
      }
      try {
        await _nearby.stopAdvertising();
        if (generation == _radioGeneration && running) {
          await _startAdvertising(generation);
        }
      } catch (_) {
        _notify('ปรับสถานะประกาศไม่สำเร็จ กรุณาเริ่ม Nearby ใหม่');
      }
    });
  }

  Future<String?> preferredTransport(String owner) async {
    final row = await _local.metaStore
        .record('nearby_radio:$owner')
        .get(await _local.database);
    final mode = row?['mode'];
    return mode == 'nearby' || mode == 'bluetooth' ? mode as String : null;
  }

  Future<void> _rememberTransport(String? mode) async {
    final owner = _ownerId;
    if (owner == null) return;
    await _local.metaStore.record('nearby_radio:$owner').put(
      await _local.database,
      {'owner_id': owner, 'mode': mode},
    );
  }

  Future<void> resumePreferred(
    AppUser user, {
    bool startIfUnset = false,
  }) async {
    await initializeForUser(user);
    final generation = _sessionGeneration;
    final mode = await preferredTransport(user.id);
    if (_ownerId != user.id ||
        generation != _sessionGeneration ||
        running ||
        busy) {
      return;
    }
    if (mode == 'bluetooth') {
      await startBluetooth(user);
    } else if (mode == 'nearby' || startIfUnset) {
      await start(user.fullName, user: user);
    }
  }

  Future<bool> _startDiscovery(int generation) async {
    return _nearby.startDiscovery(
      displayName,
      Strategy.P2P_CLUSTER,
      onEndpointFound: (id, name, service) {
        if (generation != _radioGeneration) return;
        discovered(id, name);
      },
      onEndpointLost: (id) {
        if (generation != _radioGeneration) return;
        _visibleEndpoints.remove(id);
        if (id != null && !connected.contains(id)) {
          peers.remove(id);
          discoveredModes.remove(id);
        }
        notifyListeners();
      },
      serviceId: serviceId,
    );
  }

  Future<void> start(String name, {AppUser? user}) async {
    if (user != null) await initializeForUser(user);
    await _sessionWork;
    if (_ownerId == null || (user != null && _ownerId != user.id)) return;
    if (running || busy) {
      return;
    }
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
      _notify('Nearby รองรับเฉพาะ Android');
      return;
    }
    busy = true;
    final generation = _radioGeneration;
    displayName = name.isEmpty ? 'SOSBROO' : name;
    notifyListeners();
    try {
      needsPermissionSettings = false;
      needsLocationSettings = false;
      final req = await AndroidPermissions.requestNearby();
      if (generation != _radioGeneration) return;
      if (req.values.any((p) => !p.isGranted)) {
        needsPermissionSettings = req.values.any((p) => p.isPermanentlyDenied);
        _notify(
          needsPermissionSettings
              ? 'สิทธิ์ถูกปฏิเสธถาวร • เปิด Settings เพื่ออนุญาต'
              : 'ต้องอนุญาต Bluetooth, Wi-Fi และตำแหน่งก่อน',
        );
        return;
      }
      if (!await Geolocator.isLocationServiceEnabled()) {
        needsLocationSettings = true;
        _notify('กรุณาเปิดบริการตำแหน่งของ Android ก่อนเริ่ม Nearby');
        return;
      }
      if (generation != _radioGeneration) return;
      final a = await _startAdvertising(generation);
      if (generation != _radioGeneration) {
        await _shutdownRadios();
        return;
      }
      final d = await _startDiscovery(generation);
      if (generation != _radioGeneration) {
        await _shutdownRadios();
        return;
      }
      running = a || d;
      for (final endpoint in peers.keys.toList()) {
        unawaited(_connectAutomatically(endpoint));
      }
      if (running) {
        await _rememberTransport('nearby');
        _healthTimer?.cancel();
        _healthTimer = Timer.periodic(
          const Duration(seconds: 5),
          (_) => unawaited(_healthCheck()),
        );
        unawaited(AppNotifications.instance.startBackground());
      }
      _notify(
        running ? 'กำลังค้นหา / ประกาศตัวแบบออฟไลน์' : 'เริ่ม Nearby ไม่สำเร็จ',
      );
    } catch (e) {
      await _shutdownRadios();
      running = false;
      _notify('Nearby เริ่มไม่สำเร็จ: $e');
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  Future<bool> startBluetooth(AppUser user) async {
    await initializeForUser(user);
    final generation = _radioGeneration;
    final allowed = await AndroidPermissions.requestBluetooth();
    if (generation != _radioGeneration || _ownerId != user.id) return false;
    if (!allowed) {
      _notify('กรุณาอนุญาตสิทธิ์อุปกรณ์ Bluetooth ก่อน');
      return false;
    }
    final link = BluetoothLink.instance;
    link.onRequest = (id, name) {
      if (generation == _radioGeneration) {
        requestPairing(id: id, name: name, token: '');
      }
    };
    link.onRequestClosed = (id) {
      if (generation != _radioGeneration) return;
      _pairingQueue.removeWhere((request) => request.id == id);
      if (pendingPeer == id) {
        pendingPeer = null;
        pendingName = null;
        pendingToken = null;
        _nextPairing();
        notifyListeners();
      }
    };
    link.onConnected = (id, name) async {
      if (generation != _radioGeneration) return;
      peers[id] = name;
      _result(id, Status.CONNECTED);
    };
    link.onDisconnected = (id) {
      if (generation == _radioGeneration) _disconnected(id);
    };
    link.onBytes = (id, bytes) {
      if (generation == _radioGeneration) _receivedBytes(id, bytes);
    };
    final started = await link.start();
    if (generation != _radioGeneration || _ownerId != user.id) return false;
    if (!started) {
      _notify('เปิด Bluetooth บนโทรศัพท์ก่อนเริ่มรับข้อความ');
      return false;
    }
    running = true;
    await _rememberTransport('bluetooth');
    // Bonded devices are history, not proof that a phone is currently nearby.
    // The picker scans for new phones; only an explicit tap starts a connection.
    _healthTimer ??= Timer.periodic(
      const Duration(seconds: 5),
      (_) => unawaited(_healthCheck()),
    );
    unawaited(AppNotifications.instance.startBackground());
    _notify('พร้อมรับ Bluetooth โดยตรง • ใช้ได้แม้ปิด Wi-Fi');
    return true;
  }

  Future<void> connect(String id, {bool force = false}) async {
    final generation = _radioGeneration;
    final started = _connectingSince[id];
    if (connected.contains(id) ||
        (id.startsWith('bt:') && started != null) ||
        (!force &&
            started != null &&
            DateTime.now().difference(started) < const Duration(seconds: 25))) {
      return;
    }
    // A user pressing “เชื่อมต่อ” must be able to retry an automatic attempt
    // that is stuck in the Nearby plugin's handshake state.
    if (force) {
      _connectingSince.remove(id);
      _autoAttempts.remove(id);
    }
    _connectingSince[id] = DateTime.now();
    _notify('กำลังขอเชื่อมต่อ • รออีกเครื่องกดยืนยัน');
    try {
      if (id.startsWith('bt:')) {
        await BluetoothLink.instance.connect(id);
        return;
      }
      await _nearby.requestConnection(
        discoveryName,
        id,
        onConnectionInitiated: (id, info) {
          if (generation == _radioGeneration) _initiated(id, info);
        },
        onConnectionResult: (id, result) {
          if (generation == _radioGeneration) _result(id, result);
        },
        onDisconnected: (id) {
          if (generation == _radioGeneration) _disconnected(id);
        },
      );
    } catch (e) {
      _connectingSince.remove(id);
      _notify('เชื่อมต่อไม่สำเร็จ: $e');
    } finally {
      if (id.startsWith('bt:')) {
        _connectingSince.remove(id);
        if (generation == _radioGeneration) notifyListeners();
      }
    }
  }

  void _initiated(String id, ConnectionInfo info) {
    if (automaticConnections && (running || busy)) {
      peers[id] = parseDiscoveryName(info.endpointName).name;
      unawaited(_acceptAutomatically(id));
    } else {
      requestPairing(
        id: id,
        name: parseDiscoveryName(info.endpointName).name,
        token: info.authenticationToken,
      );
    }
  }

  /// Keep simultaneous requests from two neighbours separate on a relay phone.
  void requestPairing({
    required String id,
    required String name,
    required String token,
  }) {
    if (_ownerId == null ||
        pendingPeer == id ||
        _pairingQueue.any((r) => r.id == id)) {
      return;
    }
    if (_pairingQueue.length >= 8) return;
    _pairingQueue.add((id: id, name: name, token: token));
    _nextPairing();
    _notify('มีคำขอเชื่อมต่อ: $pendingName');
  }

  void _nextPairing() {
    if (pendingPeer != null || _pairingQueue.isEmpty) return;
    final next = _pairingQueue.removeAt(0);
    pendingPeer = next.id;
    pendingName = next.name;
    pendingToken = next.token;
  }

  Future<void> approve(bool accepted) async {
    final id = pendingPeer;
    pendingPeer = null;
    pendingToken = null;
    pendingName = null;
    notifyListeners();
    if (id == null) {
      return;
    }
    try {
      if (id.startsWith('bt:')) {
        await BluetoothLink.instance.approve(id, accepted);
      } else if (accepted) {
        final generation = _radioGeneration;
        await _nearby.acceptConnection(
          id,
          onPayLoadRecieved: (from, payload) {
            if (generation == _radioGeneration) _received(from, payload);
          },
        );
      } else {
        await _nearby.rejectConnection(id);
      }
    } catch (e) {
      _notify('จับคู่ไม่สำเร็จ: $e');
    } finally {
      _nextPairing();
      notifyListeners();
    }
  }

  void _result(String id, Status result) {
    _connectingSince.remove(id);
    if (_ownerId == null) return;
    if (result == Status.CONNECTED) {
      unawaited(transportConnected(id));
    } else {
      _disconnected(id);
    }
  }

  Future<void> transportConnected(String endpoint) async {
    if (_ownerId == null) return;
    _connectingSince.remove(endpoint);
    _passiveSince.remove(endpoint);
    if (endpoint.startsWith('bt:')) _bluetoothReconnect.add(endpoint);
    connected.add(endpoint);
    _roomTransport?.updatePeers(connected);
    _lastSeen[endpoint] = DateTime.now();
    _probeFailures.remove(endpoint);
    _notify('เชื่อมต่อ ${connected.length} เครื่อง');
    await _announce(endpoint);
  }

  Future<void> _announce(String endpoint) async {
    try {
      await _direct(endpoint, _envelope('hello', {'userId': _memberId}));
      await _advertise(endpoint: endpoint);
      await _direct(
        endpoint,
        _envelope('rescue', {
          'active': rescueActive,
          'revision': _rescueRevision,
        }),
      );
      final owner = _ownerId;
      if (owner == null) return;
      // Durable replay includes room edits/deletes and messages written while
      // isolated. Self-contained certificates let late joiners verify authors.
      await _syncRoom(endpoint);
      // Replay tombstones as well as active cases after a radio outage/restart.
      for (final record in await SosRepository(
        local: _local,
      ).recentForUser(owner)) {
        if (_ownerId != owner || !connected.contains(endpoint)) return;
        final body = _sosBody(record);
        await _direct(endpoint, _envelope('sos', body));
      }
      for (final message in inbox.toList().reversed) {
        if (message.data['origin'] != deviceId &&
            (message.kind == 'sos' || message.kind == 'rescue')) {
          await _direct(endpoint, {...message.data, 'ttl': 3});
        }
      }
    } catch (_) {
      _notify('กำลังเตรียมข้อมูลการเชื่อมต่อ');
    }
  }

  Future<void> _advertise({String? endpoint}) async {
    if (_ownerId == null || deviceId.isEmpty || connected.isEmpty) return;
    final cert = await crypto.certificate(
      deviceId,
      displayName,
      _memberId,
      attestation: _ownClaims?.current == true ? _attestation : null,
    );
    final packet = _envelope('route_ad', {
      'certificate': cert,
      'path': [deviceId],
    }, ttl: 6);
    if (endpoint == null) {
      await _broadcast(packet);
    } else {
      await _direct(endpoint, packet);
      for (final entry in routes.entries.toList()) {
        final r = entry.value;
        if (r.via == endpoint ||
            r.expires.isBefore(DateTime.now()) ||
            r.path.contains(deviceId) ||
            r.hops >= 6) {
          continue;
        }
        final ad = _envelope('route_ad', {
          'certificate': r.certificate,
          'path': [...r.path, deviceId],
        }, ttl: 6 - r.hops);
        ad['origin'] = entry.key;
        await _direct(endpoint, ad);
      }
    }
  }

  Future<void>? _routeRefresh;
  Future<void> refreshRoutes() => _routeRefresh ??= _refreshRoutes()
      .whenComplete(() => _routeRefresh = null);
  Future<void> _refreshRoutes() async {
    final generation = _sessionGeneration;
    await Future.wait(
      connected.toList().map((endpoint) async {
        if (generation != _sessionGeneration || !connected.contains(endpoint)) {
          return;
        }
        try {
          await _advertise(endpoint: endpoint);
        } catch (_) {}
      }),
    );
  }

  Future<void> _receiveRoute(String from, Map<String, dynamic> packet) async {
    final generation = _sessionGeneration;
    final body = packet['data'] as Map;
    if (body['certificate'] is! Map || body['path'] is! List) return;
    final cert = Map<String, dynamic>.from(body['certificate'] as Map);
    final path = (body['path'] as List).whereType<String>().toList();
    final origin = packet['origin'] as String;
    if (origin == deviceId ||
        cert['device'] != origin ||
        path.isEmpty ||
        path.length > 6 ||
        path.first != origin ||
        path.last != identities[from]?.deviceId ||
        path.contains(deviceId) ||
        path.toSet().length != path.length) {
      return;
    }
    final seenHops = _routeSeen[packet['id']];
    final forward = seenHops == null || path.length < seenHops;
    if (!forward && _routeCandidates[origin]?.containsKey(from) == true) return;
    if (!await crypto.accept(cert)) {
      _notify('รหัสความปลอดภัยของอุปกรณ์เปลี่ยน กรุณาตรวจสอบคู่เชื่อมต่อ');
      return;
    }
    final verified = await _verifyAttestation(cert['attestation'], cert);
    if (generation != _sessionGeneration || !connected.contains(from)) return;
    final keys = '${cert['ed']}:${cert['x']}';
    if (verified != null &&
        _verifiedKeys[origin] == keys &&
        _verifiedPeers[origin]?.current == true) {
      _verifiedPeers[origin] = verified;
    } else {
      _verifiedPeers.remove(origin);
    }
    final direct = identities[from];
    if (direct?.deviceId == origin) {
      identities[from] = NearbyPeer(
        endpoint: from,
        deviceId: origin,
        name: direct!.name,
        userId: _verifiedPeers[origin]?.userId,
        verifiedRole: _verifiedPeers[origin]?.role,
        attestedUntil: _verifiedPeers[origin]?.expiresAt,
      );
    }
    if (forward) _routeSeen[packet['id']] = path.length;
    if (_routeSeen.length > 2048) _routeSeen.remove(_routeSeen.keys.first);
    final candidates = _routeCandidates.putIfAbsent(origin, () => {});
    candidates[from] = MeshRoute(
      cert,
      from,
      path.length,
      DateTime.now().add(const Duration(seconds: 90)),
      path,
    );
    _selectRoute(origin);
    if (_routeCandidates.length > 512) {
      final oldest = _routeCandidates.keys.first;
      _routeCandidates.remove(oldest);
      routes.remove(oldest);
    }
    if (verified != null &&
        _verifiedPeers[origin] == null &&
        !(_identityChallenges[origin]?.expires.isAfter(DateTime.now()) ??
            false)) {
      final challenge = (
        nonce: const Uuid().v4(),
        keys: keys,
        expires: DateTime.now().add(const Duration(seconds: 30)),
      );
      _identityChallenges[origin] = challenge;
      try {
        await _sendTo(
          origin,
          _envelope('identity_challenge', {
            'target': origin,
            'nonce': challenge.nonce,
          }),
        );
      } catch (_) {
        /* A later advertisement retries the challenge. */
      }
    }
    notifyListeners();
    unawaited(retryFor(origin));
    if (forward && packet['ttl'] > 0 && path.length < 6) {
      await _broadcast({
        ...packet,
        'ttl': packet['ttl'] - 1,
        'data': {
          ...body,
          'path': [...path, deviceId],
        },
      }, except: from);
    }
  }

  Future<void> _sendTo(String target, Map<String, dynamic> message) async {
    final peer = peerForDevice(target);
    if (peer == null) throw StateError('รอเส้นทางถึงผู้รับ');
    // Encrypt direct links as well as relays. Replaying a public certificate
    // never lets a different device read private content or forge an ACK.
    final route = routes[target];
    if (route == null) throw StateError('ยังไม่พบกุญแจของผู้รับ');
    final packet = _envelope('routed', {'target': target}, ttl: 6);
    if (message['kind'] == 'media_chunk') packet['bulk'] = true;
    final binding = '$deviceId|$target|${packet['id']}';
    final box = await crypto.seal(route.certificate, message, binding);
    packet['data'] = {'target': target, ...box};
    await _direct(peer.endpoint, packet);
  }

  Future<void> _receiveRouted(String from, Map<String, dynamic> packet) async {
    if (identities[from] == null || !_seen.add(packet['id'])) return;
    _trimSeen();
    final body = packet['data'] as Map;
    final target = body['target'];
    if (target is! String || packet['ttl'] < 0 || packet['ttl'] > 6) return;
    if (target != deviceId) {
      final peer = peerForDevice(target);
      if (peer == null || peer.endpoint == from || packet['ttl'] <= 0) return;
      await _direct(peer.endpoint, {...packet, 'ttl': packet['ttl'] - 1});
      return;
    }
    final origin = packet['origin'] as String;
    final route = routes[origin];
    if (route == null) return;
    try {
      final clear = await crypto.open(
        route.certificate,
        body,
        '$origin|$target|${packet['id']}',
      );
      final kind = clear['kind']?.toString() ?? '';
      if (clear['origin'] != origin ||
          (clear['data'] as Map?)?['target'] != deviceId ||
          !(kind == 'direct' ||
              kind == 'case_chat' ||
              kind == 'ack' ||
              kind == 'identity_challenge' ||
              kind == 'identity_response' ||
              kind == 'status_request' ||
              kind == 'sos_response' ||
              kind == 'sos_response_ack' ||
              kind.startsWith('media_'))) {
        return;
      }
      await _handleEnvelope(from, clear, authenticatedOrigin: origin);
    } catch (_) {
      /* Invalid ciphertext never reaches local chat storage. */
    }
  }

  Map<String, dynamic> _sosBody(LocalSosRecord r) => {
    'caseId': r.id,
    'revision': r.revision,
    'active': r.isActive,
    'text': r.message,
    'lat': r.latitude,
    'lng': r.longitude,
    'accuracy': r.accuracy,
    'recordedAt': r.locationRecordedAt?.toUtc().toIso8601String(),
    'lastKnown':
        r.isLastKnownLocation ||
        r.locationRecordedAt == null ||
        DateTime.now().difference(r.locationRecordedAt!).abs() >
            const Duration(minutes: 2),
  };

  void _disconnected(String id) {
    final peerId = identities[id]?.deviceId;
    connected.remove(id);
    _roomTransport?.updatePeers(connected);
    _connectingSince.remove(id);
    _autoAttempts.remove(id);
    final lost = _removeRoutes((_, route) => route.via == id);
    if (peerId != null) lost.add(peerId);
    for (final device in lost) {
      if (routes.containsKey(device)) continue;
      media.disconnected(device);
      _verifiedPeers.remove(device);
      _verifiedKeys.remove(device);
      _identityChallenges.remove(device);
    }
    if (!_visibleEndpoints.contains(id) &&
        !(running && _bluetoothReconnect.contains(id))) {
      peers.remove(id);
      discoveredModes.remove(id);
    }
    identities.remove(id);

    if (lost.isNotEmpty && connected.isNotEmpty) {
      unawaited(
        _broadcast(_envelope('route_withdraw', {'devices': lost.toList()})),
      );
    }
    unawaited(refreshRoutes().catchError((_) {}));
    _lastSeen.remove(id);
    _probeFailures.remove(id);
    _pairingQueue.removeWhere((request) => request.id == id);
    if (pendingPeer == id) {
      pendingPeer = null;
      pendingName = null;
      pendingToken = null;
    }
    _nextPairing();
    _notify('ตัดการเชื่อมต่อแล้ว • ${connected.length} เครื่องที่ยังเชื่อมต่อ');
  }

  Future<void> _disconnect(String id) async {
    _disconnected(id);
    try {
      if (id.startsWith('bt:')) {
        await BluetoothLink.instance.disconnect(id);
        return;
      }
      if (_disconnectOverride != null) {
        await _disconnectOverride(id);
      } else if (_nearbyInstance != null) {
        await _nearby.disconnectFromEndpoint(id);
      }
    } catch (_) {}
  }

  Future<void> resumeConnections(AppUser user) async {
    if (_ownerId != user.id) return;
    final generation = _sessionGeneration;
    final active = await SosRepository(local: _local).latestActive(user.id);
    if (_ownerId != user.id || generation != _sessionGeneration) return;
    if (active != null) {
      _restoreSos(active);
    } else {
      ownSosRecord = null;
      mySos = null;
      activeSosId = null;
    }
    notifyListeners();
    unawaited(refreshRoutes());
    if (!running) {
      await resumePreferred(user, startIfUnset: true);
    } else {
      if (_nearbyInstance != null && !BluetoothLink.instance.running) {
        final generation = _radioGeneration;
        try {
          await _nearby.stopDiscovery();
          if (generation == _radioGeneration && running) {
            await _startDiscovery(generation);
          }
        } catch (_) {
          /* Existing links remain usable while discovery recovers. */
        }
      }
      // Keep still-discovered endpoints available for reconnect after sleep.
      for (final endpoint in peers.keys.toList()) {
        if (!endpoint.startsWith('bt:') ||
            _bluetoothReconnect.contains(endpoint)) {
          unawaited(_connectAutomatically(endpoint));
        }
      }
      unawaited(_healthCheck());
    }
  }

  Future<void> _healthCheck() async {
    if (_checkingHealth) return;
    _checkingHealth = true;
    try {
      await _runHealthCheck();
    } finally {
      _checkingHealth = false;
    }
  }

  Future<void> _runHealthCheck() async {
    final generation = _radioGeneration;
    final now = DateTime.now();
    // The native RFCOMM accept loop can end when Android closes the server
    // socket (Bluetooth toggled, adapter recovered, or the process was briefly
    // backgrounded) while the Dart session is still marked as running.  Start
    // it again before retrying peers so a reconnect does not depend on the user
    // reopening the Bluetooth screen.
    if (running &&
        ((BluetoothLink.instance.running &&
                (await preferredTransport(_ownerId ?? '') == 'bluetooth')) ||
            _bluetoothReconnect.isNotEmpty ||
            connected.any((id) => id.startsWith('bt:')))) {
      try {
        await BluetoothLink.instance.start();
      } catch (_) {
        // A transient adapter state is handled by the next health tick.
      }
    }
    for (final endpoint in peers.keys.toList()) {
      final seen = _discoveredAt[endpoint];
      final connecting = _connectingSince[endpoint];
      if (!connected.contains(endpoint) &&
          !_visibleEndpoints.contains(endpoint) &&
          !_bluetoothReconnect.contains(endpoint) &&
          (connecting == null ||
              now.difference(connecting) > const Duration(seconds: 25)) &&
          seen != null &&
          now.difference(seen) > const Duration(seconds: 30)) {
        peers.remove(endpoint);
        discoveredModes.remove(endpoint);
        _discoveryHints.remove(endpoint);
        _discoveredAt.remove(endpoint);
        _visibleEndpoints.remove(endpoint);
        continue;
      }
      if (!endpoint.startsWith('bt:') ||
          _bluetoothReconnect.contains(endpoint)) {
        unawaited(_connectAutomatically(endpoint));
      }
    }
    if (rescueActive && !hasRescueAttestation) await setRescue(false);
    final expired = _removeRoutes(
      (_, r) => r.expires.isBefore(now) || !connected.contains(r.via),
    );
    if (expired.isNotEmpty) notifyListeners();
    if (now.difference(_lastAdvertised) > const Duration(seconds: 15)) {
      _lastAdvertised = now;
      await _advertise();
      await send('rescue', {
        'active': rescueActive,
        'revision': _rescueRevision,
      });
      await Future.wait(
        connected.toList().map((endpoint) async {
          try {
            await _syncRoom(endpoint);
          } catch (_) {}
        }),
      );
      notifyListeners();
    }
    // Android may suspend timers while asleep. Give the link a chance to
    // answer a fresh ping rather than treating CPU suspension as radio loss.
    if (now.difference(_lastHealthTick) > const Duration(seconds: 12)) {
      for (final id in connected) {
        _lastSeen[id] = now;
      }
    }
    _lastHealthTick = now;
    for (final id in connected.toList()) {
      if (generation != _radioGeneration) return;
      if (DateTime.now().difference(_lastSeen[id] ?? DateTime.now()) >
          const Duration(seconds: 60)) {
        await _disconnect(id);
        continue;
      }
      try {
        await _direct(id, _envelope('ping', {}));
        _probeFailures.remove(id);
      } catch (_) {
        // A single busy radio/write timeout is not proof of a broken link.
        // Android's transport callback still removes a genuinely closed socket.
        final failures = (_probeFailures[id] ?? 0) + 1;
        _probeFailures[id] = failures;
        if (failures >= 3) await _disconnect(id);
      }
    }
    if (DateTime.now().difference(_lastRetry) > const Duration(seconds: 15)) {
      _lastRetry = DateTime.now();
      for (final peer in reachablePeers) {
        unawaited(retryFor(peer.deviceId));
      }
    }
  }

  void _received(String from, Payload payload) {
    if (payload.bytes != null) _receivedBytes(from, payload.bytes!);
  }

  void _receivedBytes(String from, Uint8List bytes) {
    if (_ownerId == null || bytes.length > 32768) return;
    try {
      final raw = jsonDecode(utf8.decode(bytes));
      if (raw is Map) {
        if (connected.contains(from) &&
            raw['v'] == 1 &&
            raw['kind'] is String &&
            raw['origin'] is String &&
            raw['data'] is Map) {
          _lastSeen[from] = DateTime.now();
        }
        final generation = _sessionGeneration;
        // Keepalive must not sit behind file writes, signatures and history
        // replay in the receive queue, which can cause healthy links to expire.
        if (raw['kind'] == 'ping' || raw['kind'] == 'pong') {
          unawaited(
            handleEnvelope(
              from,
              Map<String, dynamic>.from(raw),
            ).catchError((Object _) {}),
          );
          return;
        }
        _receiveWork = _receiveWork
            .then((_) async {
              if (generation == _sessionGeneration) {
                await handleEnvelope(from, Map<String, dynamic>.from(raw));
              }
            })
            .catchError((Object e) {
              _notify('ยังบันทึกข้อความ Nearby ไม่ได้ กรุณาลองใหม่');
            });
      }
    } catch (_) {
      _notify('ได้รับข้อมูล Nearby รูปแบบไม่ถูกต้อง');
    }
  }

  /// Protocol boundary shared by the plugin and deterministic transport tests.
  Future<void> handleEnvelope(String from, Map<String, dynamic> data) =>
      _handleEnvelope(from, data);

  Future<void> _handleEnvelope(
    String from,
    Map<String, dynamic> data, {
    String? authenticatedOrigin,
  }) async {
    final owner = _ownerId;
    if (owner == null ||
        !connected.contains(from) ||
        data['v'] != 1 ||
        data['id'] is! String ||
        (data['id'] as String).length > 128 ||
        data['kind'] is! String ||
        data['data'] is! Map ||
        data['origin'] is! String ||
        (data['origin'] as String).length > 128 ||
        data['ttl'] is! int) {
      return;
    }
    _lastSeen[from] = DateTime.now();
    final kind = data['kind'] as String;
    final body = Map<String, dynamic>.from(data['data'] as Map);
    final origin = data['origin'] as String;
    if (kind == 'route_ad') {
      await _receiveRoute(from, data);
      return;
    }
    if (kind == 'routed') {
      await _receiveRouted(from, data);
      return;
    }
    final trusted = authenticatedOrigin == origin;
    if (kind == 'identity_challenge' &&
        trusted &&
        body['target'] == deviceId &&
        body['nonce'] is String &&
        (body['nonce'] as String).length <= 128) {
      await _sendTo(
        origin,
        _envelope('identity_response', {
          'target': origin,
          'nonce': body['nonce'],
        }),
      );
      return;
    }
    if (kind == 'identity_response' && trusted && body['target'] == deviceId) {
      final challenge = _identityChallenges[origin];
      final cert = routes[origin]?.certificate;
      if (challenge == null ||
          cert == null ||
          body['nonce'] != challenge.nonce ||
          challenge.expires.isBefore(DateTime.now()) ||
          challenge.keys != '${cert['ed']}:${cert['x']}') {
        return;
      }
      final claims = await _verifyAttestation(cert['attestation'], cert);
      if (_ownerId != owner || claims == null) return;
      _identityChallenges.remove(origin);
      _verifiedKeys[origin] = challenge.keys;
      _verifiedPeers[origin] = claims;
      final direct = identities[from];
      if (direct?.deviceId == origin) {
        identities[from] = NearbyPeer(
          endpoint: from,
          deviceId: origin,
          name: direct!.name,
          userId: claims.userId,
          verifiedRole: claims.role,
          attestedUntil: claims.expiresAt,
        );
      }
      notifyListeners();
      await _sendTo(origin, _envelope('status_request', {'target': origin}));
      return;
    }
    if (kind == 'status_request' && trusted && body['target'] == deviceId) {
      await send('rescue', {
        'active': rescueActive && hasRescueAttestation,
        'revision': _rescueRevision,
      });
      return;
    }
    if (kind == 'route_withdraw') {
      if (identities[from]?.deviceId != origin || body['devices'] is! List) {
        return;
      }
      final lost = (body['devices'] as List)
          .whereType<String>()
          .take(512)
          .toSet();
      final removed = _removeRoutes(
        (target, route) =>
            route.via == from &&
            (lost.contains(target) || route.path.any(lost.contains)),
      );
      for (final id in removed) {
        if (!routes.containsKey(id)) media.disconnected(id);
      }
      if (removed.isNotEmpty) {
        await _broadcast(
          _envelope('route_withdraw', {'devices': removed.toList()}),
          except: from,
        );
      }
      notifyListeners();
      return;
    }
    if (kind == 'hello') {
      final current = identities[from];
      if (current != null && current.deviceId != origin) {
        await _disconnect(from);
        return;
      }
      final first = current == null;
      identities[from] = NearbyPeer(
        endpoint: from,
        deviceId: origin,
        name: data['sender']?.toString() ?? peers[from] ?? 'คนใกล้เคียง',
        // A hello is transport discovery, never proof of a cloud account.
        userId: _verifiedPeers[origin]?.current == true
            ? _verifiedPeers[origin]!.userId
            : null,
        verifiedRole: _verifiedPeers[origin]?.role,
        attestedUntil: _verifiedPeers[origin]?.expiresAt,
      );
      peers[from] = identities[from]!.name;
      if (first) await _direct(from, _envelope('hello', {'userId': _memberId}));
      unawaited(retryFor(origin));
      notifyListeners();
      return;
    }
    if (kind == 'goodbye') {
      await _disconnect(from);
      return;
    }
    if (kind == 'ping') {
      await _direct(from, _envelope('pong', {}));
      return;
    }
    if (kind == 'pong') return;
    if (kind == 'sos_response' || kind == 'sos_response_ack') {
      if (!trusted || body['target'] != deviceId) return;
      if (kind == 'sos_response_ack') {
        if (body['messageId'] is String) {
          await sosResponses.acknowledge(owner, body['messageId'], origin);
        }
        return;
      }
      final caseId = body['caseId'];
      final category = body['category'];
      final state = body['state'];
      if (body['caseOrigin'] != deviceId ||
          caseId is! String ||
          caseId.length > 128 ||
          body['revision'] is! int ||
          body['sequence'] is! int ||
          body['sequence'] < 1 ||
          !((category == 'receipt' && state == 'received') ||
              (category == 'progress' &&
                  [
                    'accepted',
                    'helping',
                    'completed',
                    'released',
                  ].contains(state)))) {
        return;
      }
      final record = await SosRepository(local: _local).findById(caseId);
      final previous = category == 'progress' && state == 'completed'
          ? await sosResponses.stored(
              owner,
              deviceId,
              caseId,
              origin,
              'progress',
            )
          : null;
      final previousBody = previous?['data'] as Map?;
      final completionRetry =
          previous?['id'] == data['id'] &&
          previousBody?['state'] == 'completed' &&
          previousBody?['sequence'] == body['sequence'] &&
          previousBody?['revision'] == body['revision'];
      if (record == null ||
          record.ownerLocalId != owner ||
          body['revision'] > record.revision ||
          body['revision'] < 1 ||
          (category == 'progress' &&
              ((!record.isActive && !completionRetry) ||
                  (!completionRetry &&
                      _verifiedPeers[origin]?.rescuer != true)))) {
        return;
      }
      final fresh = await sosResponses.receive(owner, data);
      if (_ownerId != owner) return;
      if (category == 'progress' &&
          state == 'completed' &&
          (fresh || completionRetry)) {
        final closed = await SosRepository(
          local: _local,
        ).complete(caseId, owner);
        if (_ownerId != owner) return;
        if (closed != null) {
          await publishSosRecord(closed);
          if (closed.ownerUserId != null) {
            unawaited(() async {
              try {
                await SyncService.instance.syncNow();
              } catch (_) {}
            }());
          }
        }
      }
      await _sendTo(
        origin,
        _envelope('sos_response_ack', {
          'target': origin,
          'messageId': data['id'],
        }),
      );
      if (fresh) notifyListeners();
      return;
    }
    if (kind.startsWith('media_')) {
      if (!trusted) return;
      await media.handle(origin, data);
      return;
    }
    if (kind == 'ack') {
      if (trusted &&
          body['target'] == deviceId &&
          body['messageId'] is String) {
        await chats.acknowledge(owner, body['messageId'] as String, origin);
      }
      return;
    }
    if (kind == 'direct' || kind == 'case_chat') {
      if (!trusted ||
          body['target'] != deviceId ||
          body['text'] is! String ||
          !ChatAction.validWire(body['text'] as String)) {
        return;
      }
      final fresh = await chats.save(
        owner,
        origin,
        data,
        incoming: true,
        delivery: 'delivered',
      );
      await _sendTo(
        origin,
        // ACK หลังบันทึกสำเร็จ และตอบซ้ำได้หาก ACK รอบก่อนหายระหว่างทาง
        _envelope('ack', {'target': origin, 'messageId': data['id']}),
      );
      if (!fresh || _ownerId != owner) return;
      final action = ChatAction.parse(body['text'] as String);
      if (action?.kind == 'retract' || action?.kind == 'delete') {
        media.cancelIncoming(origin, action!.target);
      }
      _remember(data);
      await AppNotifications.instance.show(
        id: data['id'],
        title: data['sender']?.toString() ?? 'ข้อความ Nearby',
        text: ChatAction.preview(body['text'] as String),
        thread: origin,
        owner: owner,
        transport: 'nearby',
      );
      return;
    }
    if (kind == 'room_inventory' || kind == 'room_request') {
      final keys = body['keys'];
      if (keys is! List ||
          keys.length > 64 ||
          keys.any((k) => k is! String || k.length > 260)) {
        return;
      }
      final events = await room.events(owner);
      if (_ownerId != owner) return;
      if (kind == 'room_inventory') {
        final known = events.map(_roomKey).toSet();
        final missing = keys.where((key) => !known.contains(key)).toList();
        if (missing.isNotEmpty) {
          await _direct(from, _envelope('room_request', {'keys': missing}));
        }
      } else {
        for (final event in events.where((e) => keys.contains(_roomKey(e)))) {
          if (_ownerId != owner) return;
          final packet = MeshPacket.fromEnvelope(event);
          if (packet.ttl > 1) {
            await _direct(from, packet.forwarded().toEnvelope());
          }
        }
      }
      return;
    }
    if (kind == 'room') {
      try {
        await _roomRouter?.receive(from, MeshPacket.fromEnvelope(data));
      } on FormatException {
        // ข้อมูลเสียหายไม่ถูกเก็บในประวัติหรือ cache dedup
      } on TypeError {
        // ข้อมูลผิดชนิดต้องไม่ทำให้เส้นทางรับวิทยุหยุดทำงาน
      }
      return;
    }
    if (kind != 'sos' && kind != 'rescue') return;
    final statusCertificate = routes[origin]?.certificate;
    if (statusCertificate == null ||
        !await crypto.verifyStatus(statusCertificate, data) ||
        _ownerId != owner) {
      return;
    }
    if (!_seen.add(data['id'])) return;
    _trimSeen();
    if (kind == 'sos') {
      if (body['caseId'] is! String || body['active'] is! bool) return;
      final fresh = await chats.saveSos(owner, data);
      // Repeated broadcasts must replay a durable receipt if its ACK was lost.
      // A receipt never proves that a human rescuer has accepted the case.
      if (body['active'] == true && (body['revision'] as int? ?? 0) > 0) {
        final saved = (await chats.loadSos(owner))
            .where(
              (e) =>
                  e['origin'] == origin &&
                  (e['data'] as Map)['caseId'] == body['caseId'],
            )
            .firstOrNull;
        if (saved != null &&
            (saved['data'] as Map)['revision'] == body['revision']) {
          await _queueSosResponse(saved, 'receipt', 'received');
        }
      }
      if (!fresh) return;
    }
    if (kind == 'rescue') {
      if (body['active'] is! bool || body['revision'] is! int) return;
      if (body['active'] == true && _verifiedPeers[origin]?.rescuer != true) {
        return;
      }
      final old = inbox
          .where((m) => m.kind == 'rescue' && m.data['origin'] == origin)
          .firstOrNull;
      final previous = old?.data['data'] as Map?;
      if (previous != null &&
          body['revision'] < (previous['revision'] as int? ?? 0)) {
        return;
      }
      if (!await chats.saveRescue(owner, data)) return;
    }
    if (_ownerId != owner) return;
    _remember(data);
    if (kind == 'sos' && body['active'] == false) {
      await sosResponses.cancelForCase(owner, origin, body['caseId'] as String);
      await AppNotifications.instance.cancel('sos:$origin:${body['caseId']}');
    }
    if (kind == 'sos' && body['active'] == true) {
      await AppNotifications.instance.show(
        id: 'sos:$origin:${body['caseId']}',
        title: 'SOS จาก ${data['sender'] ?? 'คนใกล้เคียง'}',
        text: body['text']?.toString() ?? 'ต้องการความช่วยเหลือ',
        sosDevice: origin,
        owner: owner,
      );
    }
    final ttl = data['ttl'] as int;
    if (ttl > 0 && ttl <= 6) {
      await _broadcast({...data, 'ttl': ttl - 1}, except: from);
    }
  }

  void _trimSeen() {
    while (_seen.length > 4096) {
      _seen.remove(_seen.first);
    }
  }

  void _remember(Map<String, dynamic> data) {
    if (data['kind'] == 'rescue' || data['kind'] == 'sos') {
      inbox.removeWhere(
        (m) =>
            m.kind == data['kind'] &&
            m.data['origin'] == data['origin'] &&
            (data['kind'] == 'rescue' ||
                (m.data['data'] as Map)['caseId'] ==
                    (data['data'] as Map)['caseId']),
      );
    }
    inbox.insert(0, MeshMessage(data));
    if (inbox.length > 150) inbox.removeLast();
    if (data['kind'] == 'sos' || data['kind'] == 'rescue') {
      final origin = data['origin'];
      final sos = inbox.any(
        (m) =>
            m.kind == 'sos' &&
            m.data['origin'] == origin &&
            (m.data['data'] as Map)['active'] == true,
      );
      final rescue = inbox.any(
        (m) =>
            m.kind == 'rescue' &&
            m.data['origin'] == origin &&
            (m.data['data'] as Map)['active'] == true,
      );
      for (final peer in identities.values.where((p) => p.deviceId == origin)) {
        discoveredModes[peer.endpoint] = sos
            ? 'S'
            : rescue
            ? 'R'
            : 'N';
      }
    }
    notifyListeners();
  }

  Map<String, dynamic> _envelope(
    String kind,
    Map<String, dynamic> body, {
    int ttl = 0,
  }) => {
    'v': 1,
    'id': const Uuid().v4(),
    'kind': kind,
    'sender': displayName,
    'origin': deviceId,
    'at': DateTime.now().toUtc().toIso8601String(),
    'ttl': ttl,
    'data': body,
  };
  Future<void> _direct(String endpoint, Map<String, dynamic> data) async {
    final generation = _sessionGeneration;
    if (data['origin'] == deviceId &&
        (data['kind'] == 'sos' || data['kind'] == 'rescue') &&
        data['statusSignature'] == null) {
      await crypto.signStatus(data);
    }
    final bytes = Uint8List.fromList(utf8.encode(jsonEncode(data)));
    if (bytes.length > 32768) throw StateError('ข้อความยาวเกินกำหนด');
    await _radioSendQueue.add(endpoint, () async {
      if (generation != _sessionGeneration) {
        throw StateError('บัญชีเปลี่ยนแล้ว');
      }
      if (_sendOverride != null) {
        await _sendOverride(endpoint, bytes);
      } else if (endpoint.startsWith('bt:')) {
        await BluetoothLink.instance
            .send(endpoint, bytes)
            .timeout(const Duration(seconds: 5));
      } else {
        await _nearby
            .sendBytesPayload(endpoint, bytes)
            .timeout(const Duration(seconds: 5));
      }
    }, priority: data['bulk'] != true);
  }

  Future<int> sendDirect({
    required String target,
    required String text,
    String? caseId,
    String? peerName,
    SavedLocation? location,
    String? messageId,
    String? recipientUser,
    DateTime? createdAt,
  }) async {
    if (location != null &&
        (!location.latitude.isFinite ||
            !location.longitude.isFinite ||
            location.latitude.abs() > 90 ||
            location.longitude.abs() > 180)) {
      throw ArgumentError('Invalid location');
    }
    await _sessionWork;
    final owner = _ownerId;
    if (owner == null ||
        target.isEmpty ||
        text.trim().isEmpty ||
        !ChatAction.validWire(text)) {
      return 0;
    }
    if (messageId != null && await chats.find(owner, messageId) != null) {
      return 0;
    }
    final env = _envelope(caseId == null ? 'direct' : 'case_chat', {
      'target': target,
      'text': text.trim(),
      if (location != null) ...{
        'type': 'location',
        'lat': location.latitude,
        'lng': location.longitude,
        'recordedAt': location.recordedAt.toUtc().toIso8601String(),
        'lastKnown': location.isLastKnown,
        'accuracy': ?location.accuracyMeters,
      },
      'caseId': ?caseId,
    });
    if (messageId != null) env['id'] = messageId;
    if (createdAt != null) env['at'] = createdAt.toUtc().toIso8601String();
    if (recipientUser != null) env['recipientUser'] = recipientUser;
    env['peerName'] = peerName ?? peerForDevice(target)?.name ?? 'คนใกล้เคียง';
    await chats.save(owner, target, env, incoming: false);
    _remember(env);
    return _deliver(owner, target, env);
  }

  Future<int> sendLocation({
    required String target,
    required SavedLocation location,
    String? caseId,
    String? peerName,
  }) => sendDirect(
    target: target,
    text:
        'ตำแหน่งของฉัน: ${location.latitude.toStringAsFixed(6)}, ${location.longitude.toStringAsFixed(6)}',
    caseId: caseId,
    peerName: peerName,
    location: location,
  );

  Future<int> _deliver(
    String owner,
    String target,
    Map<String, dynamic> env,
  ) async {
    final peer = peerForDevice(target);
    if (peer == null || _ownerId != owner) return 0;
    if (env['recipientUser'] != null && peer.userId != env['recipientUser']) {
      return 0;
    }
    if (env['kind'] == 'media') {
      // A reachable device always gets the file directly. Internet/cloud
      // availability must never delay Bluetooth/Nearby delivery, including
      // legacy queue entries that contain a cloudFirstUntil field.
      // Do not block the serialized receive loop: file replies arrive on it.
      unawaited(
        media.send(target, env).then((sent) async {
          if (sent && _ownerId == owner) await retryFor(target);
        }),
      );
      return 1;
    }
    try {
      await _sendTo(target, env);
      await chats.markDelivery(owner, env['id'], 'sent');
      return 1;
    } catch (_) {
      return 0;
    }
  }

  Future<void> _queueSosResponse(
    Map<String, dynamic> sos,
    String category,
    String state,
  ) async {
    final owner = _ownerId;
    if (owner == null) return;
    final body = sos['data'] as Map;
    final env = _envelope('sos_response', {
      'target': sos['origin'],
      'caseOrigin': sos['origin'],
      'caseId': body['caseId'],
      'revision': body['revision'],
      'category': category,
      'state': state,
    });
    final queued = await sosResponses.queue(owner, env);
    if (_ownerId != owner) return;
    if (category == 'progress' && state == 'completed') {
      _completedRescueCases.add('${sos['origin']}:${body['caseId']}');
      notifyListeners();
    }
    try {
      await _sendTo(sos['origin'] as String, queued);
    } catch (_) {
      /* Retry on reconnect. */
    }
    notifyListeners();
  }

  Future<void> updateRescueCase(Map<String, dynamic> sos, String state) async {
    if (!hasRescueAttestation || !rescueActive) {
      throw StateError('เปิดโหมดกู้ภัยก่อนรับเคส');
    }
    if (!['accepted', 'helping', 'completed', 'released'].contains(state)) {
      throw ArgumentError('สถานะเคสไม่ถูกต้อง');
    }
    final body = sos['data'] as Map;
    final current = currentSosCases
        .where(
          (m) =>
              m.data['origin'] == sos['origin'] &&
              (m.data['data'] as Map)['caseId'] == body['caseId'],
        )
        .firstOrNull;
    if (current == null) {
      throw StateError('เคสนี้ไม่อยู่ในรายการที่ติดต่อได้แล้ว');
    }
    await _queueSosResponse(current.data, 'progress', state);
  }

  Future<void> retryFor(String target) async {
    final owner = _ownerId;
    final generation = _sessionGeneration;
    final key = '$generation:$target';
    if (owner == null ||
        peerForDevice(target) == null ||
        !_retryingTargets.add(key)) {
      return;
    }
    bool current() =>
        owner == _ownerId &&
        generation == _sessionGeneration &&
        peerForDevice(target) != null;
    try {
      for (final response in await sosResponses.pending(owner, target)) {
        if (!current()) return;
        try {
          await _sendTo(target, response);
        } catch (_) {}
      }
      for (final env in await chats.pending(owner, target)) {
        if (!current()) return;
        await _deliver(owner, target, env);
      }
    } catch (_) {
      // Local rows remain queued if storage/session changes during a retry.
    } finally {
      _retryingTargets.remove(key);
    }
  }

  Future<void> sendAttachment({
    required String target,
    required String path,
    required String name,
    required String type,
    String? peerName,
    String? caseId,
    String? messageId,
    String? recipientUser,
    DateTime? createdAt,
  }) async {
    await _sessionWork;
    final owner = _ownerId;
    final generation = _sessionGeneration;
    if (owner == null ||
        target.isEmpty ||
        (type != 'image' && type != 'video')) {
      throw StateError('ยังไม่พร้อมส่งไฟล์');
    }
    if (messageId != null && await chats.find(owner, messageId) != null) return;
    final env = _envelope('media', {});
    if (createdAt != null) env['at'] = createdAt.toUtc().toIso8601String();
    if (messageId != null) env['id'] = messageId;
    if (recipientUser != null) env['recipientUser'] = recipientUser;
    final stored = await media.files.importFile(owner, env['id'], path, type);
    if (_ownerId != owner || generation != _sessionGeneration) {
      throw StateError('บัญชีเปลี่ยนระหว่างบันทึกไฟล์');
    }
    env['data'] = {
      'target': target,
      'type': type,
      'name': name.length <= 180 ? name : name.substring(0, 180),
      'size': stored['size'],
      'sha256': stored['sha256'],
      'caseId': ?caseId,
    };
    env['peerName'] = peerName ?? peerForDevice(target)?.name ?? 'คนใกล้เคียง';
    await chats.save(
      owner,
      target,
      env,
      incoming: false,
      localPath: stored['path'],
    );
    if (_ownerId != owner || generation != _sessionGeneration) return;
    _remember(env);
    await _deliver(owner, target, env);
  }

  Future<int> send(
    String kind,
    Map<String, dynamic> body, {
    int ttl = 3,
  }) async {
    if (_ownerId == null || deviceId.isEmpty) return 0;
    if (kind != 'sos' && kind != 'rescue') {
      throw ArgumentError('Use sendDirect for private messages');
    }
    final data = <String, dynamic>{
      'v': 1,
      'id': const Uuid().v4(),
      'kind': kind,
      'sender': displayName,
      'origin': deviceId,
      'at': DateTime.now().toUtc().toIso8601String(),
      'ttl': ttl,
      'data': body,
    };
    _seen.add(data['id'] as String);
    _trimSeen();
    _remember(data);
    notifyListeners();
    final count = await _broadcast(data);
    await _refreshDiscovery();
    return count;
  }

  Future<int> _broadcast(Map<String, dynamic> data, {String? except}) async {
    if (data['origin'] == deviceId &&
        (data['kind'] == 'sos' || data['kind'] == 'rescue') &&
        data['statusSignature'] == null) {
      await crypto.signStatus(data);
    }
    final bytes = Uint8List.fromList(utf8.encode(jsonEncode(data)));
    if (bytes.length > 32768) {
      _notify('ข้อความยาวเกินกำหนด Nearby');
      return 0;
    }
    final results = await Future.wait(
      connected.toList().where((peer) => peer != except).map((peer) async {
        try {
          await _direct(peer, data);
          return 1;
        } catch (e) {
          _notify('ส่งถึง $peer ไม่สำเร็จ: $e');
          return 0;
        }
      }),
    );
    final ok = results.fold<int>(0, (total, value) => total + value);
    notifyListeners();
    return ok;
  }

  Future<int> stopSos({String? caseId}) async {
    final id = caseId ?? activeSosId;
    if (caseId == null || activeSosId == id) {
      mySos = null;
      activeSosId = null;
      ownSosRecord = null;
    }
    final record = id == null
        ? null
        : await SosRepository(local: _local).findById(id);
    return send('sos', {
      'active': false,
      'caseId': id,
      'revision': record == null
          ? 1
          : record.revision + (record.isActive ? 1 : 0),
    });
  }

  /// Text reply addressed to a specific SOS origin over a paired direct link.
  Future<int> sendCaseReply({
    required String caseId,
    required String target,
    required String text,
  }) => sendDirect(target: target, text: text, caseId: caseId);

  Future<int> setRescue(bool value) async {
    if (value && !_canRescue) {
      throw StateError('บัญชีนี้ยังไม่มีสิทธิ์หน่วยกู้ภัย');
    }
    if (value && !hasRescueAttestation) {
      await refreshAttestation(force: true);
      if (!hasRescueAttestation) {
        throw StateError(
          'กรุณาออนไลน์เพื่อรับหรือต่ออายุใบรับรองกู้ภัยก่อน เปิด SOS และแชทใกล้เคียงยังใช้ออฟไลน์ได้',
        );
      }
    }
    rescueActive = value;
    _rescueRevision = DateTime.now().microsecondsSinceEpoch;
    notifyListeners();
    return send('rescue', {'active': value, 'revision': _rescueRevision});
  }

  Future<void> _shutdownRadios() async {
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      await BluetoothLink.instance.stop();
    }
    if (_nearbyInstance == null) return;
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;
    // Attempt every shutdown operation, even if one plugin call fails.
    for (final shutdown in <Future<void> Function()>[
      () async {
        await _nearby.stopDiscovery();
      },
      () async {
        await _nearby.stopAdvertising();
      },
      () async {
        await _nearby.stopAllEndpoints();
      },
    ]) {
      try {
        await shutdown();
      } catch (_) {}
    }
  }

  Timer? _mediaNotifyTimer;
  void _mediaChanged() {
    // Progress frames must not rebuild every screen for every 12 KB packet.
    _mediaNotifyTimer ??= Timer(const Duration(milliseconds: 200), () {
      _mediaNotifyTimer = null;
      notifyListeners();
    });
  }

  @override
  void dispose() {
    _closeRoomRouter();
    _healthTimer?.cancel();
    _mediaNotifyTimer?.cancel();
    media.cancel();
    super.dispose();
  }

  Future<void> stop({bool remember = true}) async {
    if (remember) await _rememberTransport(null);
    media.cancel();
    if (rescueActive && _ownerId != null) await setRescue(false);
    _healthTimer?.cancel();
    _healthTimer = null;
    for (final endpoint in connected.toList()) {
      try {
        await _direct(
          endpoint,
          _envelope('goodbye', {}),
        ).timeout(const Duration(seconds: 2));
      } catch (_) {}
    }
    ++_radioGeneration;
    await _shutdownRadios();
    running = false;
    connected.clear();
    _roomTransport?.updatePeers(connected);
    peers.clear();
    _discoveryHints.clear();
    _discoveredAt.clear();
    _visibleEndpoints.clear();
    discoveredModes.clear();
    _advertisedName = '';
    _autoAttempts.clear();
    _autoPending.clear();
    identities.clear();
    routes.clear();
    _routeCandidates.clear();
    _connectingSince.clear();
    _passiveSince.clear();
    _bluetoothReconnect.clear();
    _lastSeen.clear();
    _probeFailures.clear();
    _pairingQueue.clear();
    pendingPeer = null;
    pendingToken = null;
    pendingName = null;
    _notify('หยุด Nearby แล้ว');
  }
}
