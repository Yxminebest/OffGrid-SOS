import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:nearby_connections/nearby_connections.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:sembast/sembast.dart';
import 'package:uuid/uuid.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'mesh_crypto.dart';

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
    this.userId,
    this.hops = 1,
  });
  final String endpoint, deviceId, name;
  final String? userId;
  final int hops;
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
      _mediaFiles = null;
  NearbyMeshService.withDatabase(
    LocalDatabase local, {
    Future<void> Function(String, Uint8List)? sendBytes,
    Future<void> Function(String)? disconnect,
    this._mediaFiles,
  }) : _local = local,
       _testStorage = true,
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
  final _routeSeen = <String, int>{};
  DateTime _lastAdvertised = DateTime.fromMillisecondsSinceEpoch(0);
  bool _canRescue = false;
  int _rescueRevision = 0;
  late final chats = NearbyChatRepository(local: _local);
  late final media = NearbyMediaTransfer(
    chats: chats,
    files: _mediaFiles ?? NearbyMediaFiles(),
    owner: () => _ownerId,
    device: () => deviceId,
    makeFrame: (kind, body) => _envelope(kind, body),
    sendFrame: (target, frame) async {
      await _sendTo(target, frame);
    },
    changed: notifyListeners,
    received: (env) async {
      _remember(env);
      await AppNotifications.instance.show(
        id: env['id'],
        title: env['sender']?.toString() ?? 'ไฟล์ Nearby',
        text: (env['data'] as Map)['type'] == 'image'
            ? 'ส่งรูปภาพให้คุณ'
            : 'ส่งวิดีโอให้คุณ',
        thread: env['origin'],
      );
    },
  );
  String? get ownerId => _ownerId;
  String? _memberId;
  final identities = <String, NearbyPeer>{};
  final _lastSeen = <String, DateTime>{};
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
      userId: route.certificate['userId'] as String?,
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
  int _radioGeneration = 0;
  bool needsPermissionSettings = false;
  bool needsLocationSettings = false;
  String? activeSosId;
  final Map<String, String> peers = {};
  final Set<String> connected = {};
  final List<MeshMessage> inbox = [];
  final Set<String> _seen = {};
  String status = 'ยังไม่ได้เริ่มค้นหา';
  String displayName = 'offgrid-sos';
  bool running = false;
  bool busy = false;
  bool rescueActive = false;
  Map<String, dynamic>? mySos;
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
    await stop();
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
    if (active != null) _restoreSos(active);
    final savedStates = await chats.loadSos(user.id);
    if (generation != _sessionGeneration) return;
    inbox.addAll(savedStates.map(MeshMessage.new));
    _notify('พร้อมใช้งาน Nearby • กดเริ่มเพื่อค้นหาอุปกรณ์');
  }

  void _restoreSos(LocalSosRecord record) {
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
    _ownerId = null;
    _memberId = null;
    identities.clear();
    routes.clear();
    _routeSeen.clear();
    _canRescue = false;
    _lastSeen.clear();
    deviceId = '';
    activeSosId = null;
    mySos = null;
    rescueActive = false;
    inbox.clear();
    _seen.clear();
    peers.clear();
    discoveredModes.clear();
    connected.clear();
    pendingPeer = null;
    pendingName = null;
    pendingToken = null;
    displayName = 'offgrid-sos';
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
  String _advertisedName = '';
  Future<void> _advertisingWork = Future.value();
  String get discoveryName {
    final mode = mySos?['active'] == true
        ? 'S'
        : rescueActive
        ? 'R'
        : 'N';
    final name = String.fromCharCodes(displayName.runes.take(24));
    return 'OG9:$mode:$name';
  }

  static ({String name, String mode}) parseDiscoveryName(String raw) {
    final match = RegExp(r'^OG9:([SRN]):(.*)$').firstMatch(raw);
    return (name: match?.group(2) ?? raw, mode: match?.group(1) ?? 'N');
  }

  void discovered(String endpoint, String raw) {
    final value = parseDiscoveryName(raw);
    peers[endpoint] = value.name;
    discoveredModes[endpoint] = value.mode;
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
    displayName = name.isEmpty ? 'offgrid-sos' : name;
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
      final d = await _nearby.startDiscovery(
        displayName,
        Strategy.P2P_CLUSTER,
        onEndpointFound: (id, name, service) {
          if (generation != _radioGeneration) return;
          discovered(id, name);
        },
        onEndpointLost: (id) {
          if (generation != _radioGeneration) return;
          if (id != null && !connected.contains(id)) {
            peers.remove(id);
            discoveredModes.remove(id);
          }
          notifyListeners();
        },
        serviceId: serviceId,
      );
      if (generation != _radioGeneration) {
        await _shutdownRadios();
        return;
      }
      running = a || d;
      if (running) {
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
    if (!await AndroidPermissions.requestBluetooth()) {
      _notify('กรุณาอนุญาตสิทธิ์อุปกรณ์ Bluetooth ก่อน');
      return false;
    }
    final link = BluetoothLink.instance;
    link.onConnected = (id, name) async {
      peers[id] = name;
      _result(id, Status.CONNECTED);
    };
    link.onDisconnected = _disconnected;
    link.onBytes = _receivedBytes;
    if (!await link.start()) {
      _notify('เปิด Bluetooth บนโทรศัพท์ก่อนเริ่มรับข้อความ');
      return false;
    }
    running = true;
    _healthTimer ??= Timer.periodic(
      const Duration(seconds: 5),
      (_) => unawaited(_healthCheck()),
    );
    unawaited(AppNotifications.instance.startBackground());
    _notify('พร้อมรับ Bluetooth โดยตรง • ใช้ได้แม้ปิด Wi-Fi');
    return true;
  }

  Future<void> connect(String id) async {
    final generation = _radioGeneration;
    try {
      if (id.startsWith('bt:')) {
        await BluetoothLink.instance.connect(id);
        return;
      }
      await _nearby.requestConnection(
        displayName,
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
      _notify('เชื่อมต่อไม่สำเร็จ: $e');
    }
  }

  void _initiated(String id, ConnectionInfo info) {
    if (_ownerId == null) return;
    pendingPeer = id;
    pendingName = parseDiscoveryName(info.endpointName).name;
    pendingToken = info.authenticationToken;
    _notify('มีคำขอเชื่อมต่อ: $pendingName');
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
      if (accepted) {
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
    }
  }

  void _result(String id, Status result) {
    if (_ownerId == null) return;
    if (result == Status.CONNECTED) {
      unawaited(transportConnected(id));
    } else {
      _disconnected(id);
    }
  }

  Future<void> transportConnected(String endpoint) async {
    if (_ownerId == null) return;
    connected.add(endpoint);
    _lastSeen[endpoint] = DateTime.now();
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
    final cert = await crypto.certificate(deviceId, displayName, _memberId);
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

  Future<void> _receiveRoute(String from, Map<String, dynamic> packet) async {
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
    if (seenHops != null && seenHops <= path.length) return;
    if (!await crypto.accept(cert)) {
      _notify('รหัสความปลอดภัยของอุปกรณ์เปลี่ยน กรุณาตรวจสอบคู่เชื่อมต่อ');
      return;
    }
    _routeSeen[packet['id']] = path.length;
    if (_routeSeen.length > 2048) _routeSeen.remove(_routeSeen.keys.first);
    final old = routes[origin];
    if (old == null ||
        old.via == from ||
        old.hops >= path.length ||
        old.expires.isBefore(DateTime.now())) {
      routes[origin] = MeshRoute(
        cert,
        from,
        path.length,
        DateTime.now().add(const Duration(seconds: 40)),
        path,
      );
    }
    if (routes.length > 512) routes.remove(routes.keys.first);
    notifyListeners();
    unawaited(retryFor(origin));
    if (packet['ttl'] > 0 && path.length < 6) {
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
    if (identities[peer.endpoint]?.deviceId == target) {
      await _direct(peer.endpoint, message);
      return;
    }
    final route = routes[target];
    if (route == null) throw StateError('ยังไม่พบกุญแจของผู้รับ');
    final packet = _envelope('routed', {'target': target}, ttl: 6);
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
    final lost = routes.entries
        .where((e) => e.value.via == id)
        .map((e) => e.key)
        .toSet();
    if (peerId != null) lost.add(peerId);
    for (final device in lost) {
      media.disconnected(device);
    }
    connected.remove(id);
    peers.remove(id);
    discoveredModes.remove(id);
    identities.remove(id);
    routes.removeWhere((_, route) => route.via == id);
    if (lost.isNotEmpty && connected.isNotEmpty) {
      unawaited(
        _broadcast(_envelope('route_withdraw', {'devices': lost.toList()})),
      );
    }
    _lastSeen.remove(id);
    if (pendingPeer == id) {
      pendingPeer = null;
      pendingName = null;
      pendingToken = null;
    }
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
    routes.removeWhere(
      (_, r) => r.expires.isBefore(now) || !connected.contains(r.via),
    );
    if (now.difference(_lastAdvertised) > const Duration(seconds: 15)) {
      _lastAdvertised = now;
      await _advertise();
      await send('rescue', {
        'active': rescueActive,
        'revision': _rescueRevision,
      });
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
          const Duration(seconds: 20)) {
        await _disconnect(id);
        continue;
      }
      try {
        await _direct(id, _envelope('ping', {}));
      } catch (_) {
        await _disconnect(id);
      }
    }
    if (DateTime.now().difference(_lastRetry) > const Duration(seconds: 15)) {
      _lastRetry = DateTime.now();
      for (final peer in reachablePeers) {
        await retryFor(peer.deviceId);
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
        final generation = _sessionGeneration;
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
    final trusted =
        authenticatedOrigin == origin || identities[from]?.deviceId == origin;
    if (kind == 'route_withdraw') {
      if (identities[from]?.deviceId != origin || body['devices'] is! List) {
        return;
      }
      final lost = (body['devices'] as List)
          .whereType<String>()
          .take(512)
          .toSet();
      final removed = routes.entries
          .where(
            (e) =>
                e.value.via == from &&
                (lost.contains(e.key) || e.value.path.any(lost.contains)),
          )
          .map((e) => e.key)
          .toList();
      for (final id in removed) {
        routes.remove(id);
        media.disconnected(id);
      }
      if (removed.isNotEmpty) {
        await _broadcast(
          _envelope('route_withdraw', {'devices': removed}),
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
        userId: body['userId'] as String?,
      );
      peers[from] = identities[from]!.name;
      if (first) await _direct(from, _envelope('hello', {'userId': _memberId}));
      await retryFor(origin);
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
          (body['text'] as String).length > 4000) {
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
        _envelope('ack', {'target': origin, 'messageId': data['id']}),
      );
      if (!fresh || _ownerId != owner) return;
      _remember(data);
      await AppNotifications.instance.show(
        id: data['id'],
        title: data['sender']?.toString() ?? 'ข้อความ Nearby',
        text: body['text'] as String,
        thread: origin,
      );
      return;
    }
    if (kind != 'sos' && kind != 'rescue') return;
    if (!_seen.add(data['id'])) return;
    _trimSeen();
    if (kind == 'sos') {
      if (body['caseId'] is! String ||
          body['active'] is! bool ||
          !await chats.saveSos(owner, data)) {
        return;
      }
    }
    if (kind == 'rescue') {
      if (body['active'] is! bool || body['revision'] is! int) return;
      final old = inbox
          .where((m) => m.kind == 'rescue' && m.data['origin'] == origin)
          .firstOrNull;
      final previous = old?.data['data'] as Map?;
      if (previous != null &&
          body['revision'] < (previous['revision'] as int? ?? 0)) {
        return;
      }
    }
    if (_ownerId != owner) return;
    _remember(data);
    if (kind == 'sos' && body['active'] == true) {
      await AppNotifications.instance.show(
        id: data['id'],
        title: 'SOS จาก ${data['sender'] ?? 'คนใกล้เคียง'}',
        text: body['text']?.toString() ?? 'ต้องการความช่วยเหลือ',
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
    final bytes = Uint8List.fromList(utf8.encode(jsonEncode(data)));
    if (bytes.length > 32768) throw StateError('ข้อความยาวเกินกำหนด');
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
  }

  Future<int> sendDirect({
    required String target,
    required String text,
    String? caseId,
    String? peerName,
  }) async {
    await _sessionWork;
    final owner = _ownerId;
    if (owner == null ||
        target.isEmpty ||
        text.trim().isEmpty ||
        text.length > 4000) {
      return 0;
    }
    final env = _envelope(caseId == null ? 'direct' : 'case_chat', {
      'target': target,
      'text': text.trim(),
      'caseId': ?caseId,
    });
    env['peerName'] = peerName ?? peerForDevice(target)?.name ?? 'คนใกล้เคียง';
    await chats.save(owner, target, env, incoming: false);
    _remember(env);
    return _deliver(owner, target, env);
  }

  Future<int> _deliver(
    String owner,
    String target,
    Map<String, dynamic> env,
  ) async {
    final peer = peerForDevice(target);
    if (peer == null || _ownerId != owner) return 0;
    if (env['kind'] == 'media') {
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

  Future<void> retryFor(String target) async {
    final owner = _ownerId;
    if (owner == null || peerForDevice(target) == null) return;
    for (final env in await chats.pending(owner, target)) {
      await _deliver(owner, target, env);
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
    if (messageId != null) env['id'] = messageId;
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
    final bytes = Uint8List.fromList(utf8.encode(jsonEncode(data)));
    if (bytes.length > 32768) {
      _notify('ข้อความยาวเกินกำหนด Nearby');
      return 0;
    }
    var ok = 0;
    for (final peer in connected.toList()) {
      if (peer == except) {
        continue;
      }
      try {
        await _direct(peer, data);
        ok++;
      } catch (e) {
        _notify('ส่งถึง $peer ไม่สำเร็จ: $e');
      }
    }
    notifyListeners();
    return ok;
  }

  Future<int> stopSos({String? caseId}) async {
    final id = caseId ?? activeSosId;
    mySos = null;
    activeSosId = null;
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

  @override
  void dispose() {
    _healthTimer?.cancel();
    media.cancel();
    super.dispose();
  }

  Future<void> stop() async {
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
    peers.clear();
    discoveredModes.clear();
    _advertisedName = '';
    identities.clear();
    routes.clear();
    _lastSeen.clear();
    pendingPeer = null;
    pendingToken = null;
    pendingName = null;
    _notify('หยุด Nearby แล้ว');
  }
}
