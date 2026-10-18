import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';
import '../../app/theme.dart';
import '../../models/user.dart';
import '../../services/nearby_mesh_service.dart';
import '../../services/app_notifications.dart';
import '../../services/bluetooth_link.dart';
import '../../widgets/app_card.dart';
import '../../widgets/page_header.dart';
import '../../widgets/location_actions.dart';
import '../chat/nearby_conversation_screen.dart';

class NearbyScreen extends StatefulWidget {
  const NearbyScreen({super.key, required this.me, this.service});
  final AppUser me;
  final NearbyMeshService? service;
  @override
  State<NearbyScreen> createState() => _NearbyScreenState();
}

class _NearbyScreenState extends State<NearbyScreen> {
  late final mesh = widget.service ?? NearbyMeshService.instance;
  String? _dialogFor;
  String? _chatAfterPairing;
  @override
  void initState() {
    super.initState();
    mesh.addListener(_changed);
  }

  void _changed() {
    if (!mounted) return;
    setState(() {});
    final endpoint = _chatAfterPairing;
    final ready = mesh.identities[endpoint];
    if (ready != null) {
      _chatAfterPairing = null;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) chat(ready);
      });
    }
    final peer = mesh.pendingPeer;
    if (peer == null || _dialogFor != null) return;
    _dialogFor = peer;
    final name = mesh.pendingName, token = mesh.pendingToken;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      final accepted = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => AlertDialog(
          title: const Text('ตรวจสอบรหัสการจับคู่'),
          content: Text(
            'อุปกรณ์: $name\nรหัส: $token\nยืนยันรหัสตรงกันทั้งสองเครื่อง',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('ปฏิเสธ'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('รหัสตรงกัน'),
            ),
          ],
        ),
      );
      if (mesh.pendingPeer == peer) await mesh.approve(accepted == true);
      _dialogFor = null;
    });
  }

  @override
  void dispose() {
    mesh.removeListener(_changed);
    super.dispose();
  }

  void chat(NearbyPeer peer) => Navigator.of(context).push(
    MaterialPageRoute(
      builder: (_) => NearbyConversationScreen(
        me: widget.me,
        service: mesh,
        peerId: peer.deviceId,
        name: peer.name,
      ),
    ),
  );

  Future<void> bluetooth() async {
    try {
      if (!await mesh.startBluetooth(widget.me)) return;
      final devices = await BluetoothLink.instance.paired();
      if (!mounted) return;
      final id = await showModalBottomSheet<String>(
        context: context,
        isScrollControlled: true,
        builder: (ctx) => SafeArea(
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.sizeOf(ctx).height * .75,
            ),
            child: ListView(
              shrinkWrap: true,
              padding: const EdgeInsets.all(22),
              children: [
                Text(
                  'Bluetooth โดยตรง',
                  style: Theme.of(ctx).textTheme.titleLarge,
                ),
                const SizedBox(height: 10),
                const Text(
                  'จับคู่โทรศัพท์สองเครื่องในตั้งค่า Bluetooth ก่อน แล้วเปิดรับ Bluetooth ในแอปทั้งคู่ จากนั้นเลือกเครื่องที่จะเชื่อมต่อ ใช้ได้แม้ปิด Wi-Fi',
                ),
                const SizedBox(height: 12),
                TextButton.icon(
                  onPressed: BluetoothLink.instance.settings,
                  icon: const Icon(Icons.settings_bluetooth),
                  label: const Text('เปิดตั้งค่า Bluetooth'),
                ),
                if (devices.isEmpty)
                  const Padding(
                    padding: EdgeInsets.all(16),
                    child: Text('ยังไม่มีอุปกรณ์ที่จับคู่ในระบบ'),
                  ),
                for (final device in devices)
                  ListTile(
                    leading: const Icon(Icons.bluetooth_rounded),
                    title: Text(device['name']!),
                    trailing: const Icon(Icons.chevron_right_rounded),
                    onTap: () => Navigator.pop(ctx, device['id']),
                  ),
              ],
            ),
          ),
        ),
      );
      if (id != null) await mesh.connect(id);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'เปิด Bluetooth โดยตรงไม่ได้ กรุณาตรวจสิทธิ์และเปิด Bluetooth',
            ),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final supported =
        !kIsWeb && defaultTargetPlatform == TargetPlatform.android;
    final cases = <String, MeshMessage>{};
    for (final message in mesh.inbox) {
      final data = message.data['data'];
      if (message.kind == 'sos' &&
          data is Map &&
          data['caseId'] is String &&
          message.data['origin'] != mesh.deviceId) {
        cases.putIfAbsent(
          '${message.data['origin']}:${data['caseId']}',
          () => message,
        );
      }
    }
    final activeCases = cases.values
        .where((m) => (m.data['data'] as Map)['active'] == true)
        .toList();
    final rescuers = <String, MeshMessage>{};
    for (final m in mesh.inbox.where(
      (m) => m.kind == 'rescue' && m.data['origin'] != mesh.deviceId,
    )) {
      rescuers.putIfAbsent(m.data['origin'].toString(), () => m);
    }
    return Scaffold(
      appBar: Navigator.of(context).canPop()
          ? AppBar(title: const Text('คนใกล้เคียง'))
          : null,
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 700),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(22, 24, 22, 28),
              children: [
                const PageHeader(
                  title: 'คนใกล้เคียง',
                  subtitle: 'จับคู่อุปกรณ์ แล้วสนทนาในแท็บแชท',
                ),
                AppCard(
                  backgroundColor: context.colors.surfaceSoft,
                  borderColor: Colors.transparent,
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          Icon(
                            Icons.radar_rounded,
                            color: context.colors.info,
                            size: 32,
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  mesh.running
                                      ? 'Nearby กำลังทำงาน'
                                      : 'เริ่มต้นการเชื่อมต่อ',
                                  style: Theme.of(
                                    context,
                                  ).textTheme.titleMedium,
                                ),
                                Text(
                                  '${mesh.connected.length} เครื่องที่เชื่อมต่อ',
                                  style: TextStyle(
                                    color: context.colors.muted,
                                    fontSize: 13,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      Text(
                        supported ? mesh.status : 'Nearby รองรับ Android',
                        style: TextStyle(
                          color: context.colors.muted,
                          fontSize: 13,
                        ),
                      ),
                      const SizedBox(height: 18),
                      if (supported)
                        FilledButton.icon(
                          onPressed: mesh.busy
                              ? null
                              : mesh.running
                              ? mesh.stop
                              : () => mesh.start(
                                  widget.me.fullName,
                                  user: widget.me,
                                ),
                          icon: Icon(
                            mesh.running
                                ? Icons.stop_circle_outlined
                                : Icons.radar_rounded,
                          ),
                          label: Text(
                            mesh.busy
                                ? 'กำลังเตรียมการเชื่อมต่อ…'
                                : mesh.running
                                ? 'หยุดค้นหาและเชื่อมต่อ'
                                : 'เริ่มค้นหาอุปกรณ์',
                          ),
                        ),
                      if (mesh.needsPermissionSettings)
                        TextButton.icon(
                          onPressed: openAppSettings,
                          icon: const Icon(Icons.settings_outlined),
                          label: const Text('เปิดการตั้งค่าสิทธิ์'),
                        ),
                      if (mesh.needsLocationSettings)
                        TextButton.icon(
                          onPressed: Geolocator.openLocationSettings,
                          icon: const Icon(Icons.location_on_outlined),
                          label: const Text('เปิดบริการตำแหน่ง'),
                        ),
                      const SizedBox(height: 10),
                      Text(
                        'ไม่ต้องมีอินเทอร์เน็ต • เปิด Bluetooth และวิทยุ Wi-Fi เพื่อให้ Nearby เลือกช่องทางที่ใช้ได้',
                        style: TextStyle(
                          color: context.colors.muted,
                          fontSize: 12,
                          height: 1.6,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 10),
                if (supported)
                  OutlinedButton.icon(
                    onPressed: bluetooth,
                    icon: const Icon(Icons.bluetooth_rounded),
                    label: const Text('ใช้ Bluetooth เมื่อปิด Wi-Fi'),
                  ),
                const SizedBox(height: 20),
                ValueListenableBuilder<bool>(
                  valueListenable: AppNotifications.instance.enabled,
                  builder: (context, allowed, _) => allowed
                      ? const SizedBox.shrink()
                      : ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: Icon(
                            Icons.notifications_off_outlined,
                            color: context.colors.pending,
                          ),
                          title: const Text(
                            'เปิดการแจ้งเตือนข้อความ',
                            style: TextStyle(fontSize: 14),
                          ),
                          subtitle: const Text(
                            'รับการแจ้งเตือนเมื่อออกจากหน้าจอแอป',
                          ),
                          onTap: () async {
                            if (!await AppNotifications.instance.request()) {
                              await openAppSettings();
                            }
                          },
                        ),
                ),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'อุปกรณ์ที่พบ',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ),
                    Text(
                      '${mesh.peers.length} เครื่อง',
                      style: TextStyle(
                        color: context.colors.muted,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                if (mesh.peers.isEmpty)
                  const AppCard(
                    child: EmptyState(
                      icon: Icons.devices_other_outlined,
                      title: 'ยังไม่มีอุปกรณ์ใกล้เคียง',
                      description:
                          'กดเริ่มค้นหาบน Android ทั้งสองเครื่อง\nจากนั้นจับคู่และยืนยันรหัสให้ตรงกัน',
                    ),
                  ),
                for (final entry in mesh.peers.entries)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: AppCard(
                      padding: EdgeInsets.zero,
                      backgroundColor: mesh.discoveredModes[entry.key] == 'S'
                          ? Theme.of(context).colorScheme.errorContainer
                          : mesh.discoveredModes[entry.key] == 'R'
                          ? const Color(0xFF1859A9)
                          : null,
                      child: ListTile(
                        textColor: mesh.discoveredModes[entry.key] == 'R'
                            ? Colors.white
                            : null,
                        leading: Icon(
                          mesh.connected.contains(entry.key)
                              ? Icons.bluetooth_connected_rounded
                              : Icons.phone_android_rounded,
                          color: context.colors.info,
                        ),
                        title: Text(entry.value),
                        subtitle: Text(
                          mesh.connected.contains(entry.key)
                              ? 'เชื่อมต่อแล้ว • แตะเพื่อแชท'
                              : switch (mesh.discoveredModes[entry.key]) {
                                  'S' =>
                                    'SOS ขอความช่วยเหลือ • แตะเพื่อจับคู่และแชท',
                                  'R' =>
                                    'ประกาศโหมดกู้ภัย • แตะเพื่อจับคู่และแชท',
                                  _ => 'พร้อมจับคู่',
                                },
                        ),
                        trailing: mesh.connected.contains(entry.key)
                            ? const Icon(Icons.chat_bubble_outline_rounded)
                            : TextButton(
                                onPressed: () {
                                  _chatAfterPairing = entry.key;
                                  mesh.connect(entry.key);
                                },
                                child: const Text('เชื่อมต่อ'),
                              ),
                        onTap: () {
                          final peer = mesh.identities[entry.key];
                          if (peer != null) {
                            chat(peer);
                          } else {
                            _chatAfterPairing = entry.key;
                            mesh.connect(entry.key);
                          }
                        },
                      ),
                    ),
                  ),
                for (final peer in mesh.reachablePeers.where((p) => p.hops > 1))
                  ListTile(
                    leading: const Icon(Icons.alt_route_rounded),
                    title: Text(peer.name),
                    subtitle: Text('ผ่านเครื่องตัวกลาง • ${peer.hops} ทอด'),
                    trailing: const Icon(Icons.chat_bubble_outline),
                    onTap: () => chat(peer),
                  ),
                for (final entry in rescuers.entries.where(
                  (e) =>
                      (e.value.data['data'] as Map)['active'] == true &&
                      mesh.peerForDevice(e.key) != null,
                ))
                  Card(
                    color: const Color(0xFF1859A9),
                    child: ListTile(
                      textColor: Colors.white,
                      iconColor: Colors.white,
                      leading: const Icon(Icons.health_and_safety_rounded),
                      title: Text(
                        entry.value.data['sender']?.toString() ?? 'หน่วยกู้ภัย',
                      ),
                      subtitle: const Text('เปิดโหมดกู้ภัย • แตะเพื่อแชท'),
                      onTap: () => chat(mesh.peerForDevice(entry.key)!),
                    ),
                  ),
                const SizedBox(height: 16),
                AppCard(
                  padding: const EdgeInsets.all(18),
                  child: Row(
                    children: [
                      Icon(Icons.forum_outlined, color: context.colors.info),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'ข้อความ Nearby อยู่ในแท็บแชท พร้อมประวัติและสถานะการส่ง',
                          style: TextStyle(
                            color: context.colors.muted,
                            fontSize: 13,
                            height: 1.6,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                if (activeCases.isNotEmpty) ...[
                  const SizedBox(height: 24),
                  Text(
                    'SOS ใกล้เคียง',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 12),
                  for (final message in activeCases)
                    Builder(
                      builder: (context) {
                        final body = message.data['data'] as Map;
                        final lat = (body['lat'] as num?)?.toDouble(),
                            lng = (body['lng'] as num?)?.toDouble();
                        return AppCard(
                          margin: const EdgeInsets.only(bottom: 12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              InkWell(
                                onTap: () => Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => NearbyConversationScreen(
                                      me: widget.me,
                                      service: mesh,
                                      peerId: message.data['origin'].toString(),
                                      name:
                                          message.data['sender']?.toString() ??
                                          'ผู้ขอความช่วยเหลือ',
                                      caseId: body['caseId']?.toString(),
                                    ),
                                  ),
                                ),
                                child: Text(
                                  'SOS · ${message.data['sender'] ?? 'คนใกล้เคียง'}',
                                  style: TextStyle(
                                    color: Theme.of(context).colorScheme.error,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                body['text']?.toString() ??
                                    'ต้องการความช่วยเหลือ',
                              ),
                              TextButton.icon(
                                onPressed: () => Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => NearbyConversationScreen(
                                      me: widget.me,
                                      service: mesh,
                                      peerId: message.data['origin'].toString(),
                                      name:
                                          message.data['sender']?.toString() ??
                                          'ผู้ขอความช่วยเหลือ',
                                      caseId: body['caseId']?.toString(),
                                    ),
                                  ),
                                ),
                                icon: const Icon(Icons.chat_outlined),
                                label: const Text('สนทนากับผู้ขอความช่วยเหลือ'),
                              ),
                              if (lat != null && lng != null) ...[
                                const SizedBox(height: 10),
                                Text(
                                  '$lat, $lng',
                                  style: TextStyle(
                                    color: context.colors.muted,
                                    fontSize: 12,
                                  ),
                                ),
                                if (body['lastKnown'] == true)
                                  Text(
                                    'พิกัดที่เคยบันทึกไว้',
                                    style: TextStyle(
                                      color: context.colors.pending,
                                      fontSize: 12,
                                    ),
                                  ),
                                LocationActions(latitude: lat, longitude: lng),
                              ],
                            ],
                          ),
                        );
                      },
                    ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
