import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';
import '../../app/theme.dart';
import '../../models/user.dart';
import '../../services/nearby_mesh_service.dart';
import '../../services/app_notifications.dart';
import '../../services/android_permissions.dart';
import 'bluetooth_device_sheet.dart';
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
            peer.startsWith('bt:')
                ? 'เครื่อง: $name\n${peer.substring(3)}\n\nอนุญาตให้เครื่องนี้เชื่อมต่อและรับส่งข้อมูลหรือไม่?'
                : 'อุปกรณ์: $name\nรหัส: $token\nยืนยันรหัสตรงกันทั้งสองเครื่อง',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('ปฏิเสธ'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(peer.startsWith('bt:') ? 'อนุญาต' : 'รหัสตรงกัน'),
            ),
          ],
        ),
      );
      if (mesh.pendingPeer == peer) await mesh.approve(accepted == true);
      _dialogFor = null;
      if (mounted) _changed();
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
      if (!await AndroidPermissions.requestBluetoothDiscovery()) {
        throw StateError('Bluetooth permissions required');
      }
      if (!mounted) return;
      final id = await showModalBottomSheet<String>(
        context: context,
        isScrollControlled: true,
        builder: (_) => const BluetoothDeviceSheet(),
      );
      if (id != null) await mesh.connect(id, force: true);
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
    final activeCases = mesh.currentSosCases;
    final relayed = mesh.reachablePeers.where((p) => p.hops > 1).toList();
    final devices = mesh.visiblePeers;
    bool sosPeer(String endpoint) =>
        mesh.discoveredModes[endpoint] == 'S' ||
        mesh.currentSosCases.any(
          (m) => m.data['origin'] == mesh.identities[endpoint]?.deviceId,
        );
    bool activeRescuer(String endpoint) {
      final peer = mesh.identities[endpoint];
      return peer != null && mesh.isPeerRescueActive(peer.deviceId);
    }

    bool highlighted(String endpoint) =>
        sosPeer(endpoint) || activeRescuer(endpoint);

    return Scaffold(
      appBar: Navigator.of(context).canPop()
          ? AppBar(title: const Text('บุคคลใกล้เคียง'))
          : null,
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 700),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(22, 24, 22, 28),
              children: [
                const PageHeader(title: 'บุคคลใกล้เคียง', subtitle: ''),
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
                                      ? (mesh.connected.isNotEmpty
                                            ? 'พร้อมสนทนา'
                                            : 'กำลังค้นหาบุคคลใกล้เคียง')
                                      : 'เริ่มต้นการเชื่อมต่อ',
                                  style: Theme.of(
                                    context,
                                  ).textTheme.titleMedium,
                                ),
                                Text(
                                  relayed.isEmpty
                                      ? '${mesh.connectedDeviceCount} เครื่องที่เชื่อมต่อ'
                                      : '${mesh.connectedDeviceCount} เชื่อมตรง · ${relayed.length} ผ่านตัวกลาง',
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
                      const SizedBox(height: 18),
                      Text(
                        mesh.status,
                        style: TextStyle(
                          color: context.colors.muted,
                          fontSize: 12,
                        ),
                      ),
                      const SizedBox(height: 8),
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
                const SizedBox(height: 18),
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
                      '${devices.length + relayed.length} เครื่อง',
                      style: TextStyle(
                        color: context.colors.muted,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                if (devices.isEmpty && relayed.isEmpty)
                  const AppCard(
                    child: EmptyState(
                      icon: Icons.devices_other_outlined,
                      title: 'ยังไม่มีอุปกรณ์ใกล้เคียง',
                      description: '',
                    ),
                  ),
                for (final entry in devices.entries)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: AppCard(
                      padding: EdgeInsets.zero,
                      backgroundColor: sosPeer(entry.key)
                          ? AppColors.sos
                          : activeRescuer(entry.key)
                          ? AppColors.rescueStrong
                          : null,
                      child: ListTile(
                        iconColor: highlighted(entry.key) ? Colors.white : null,
                        textColor: highlighted(entry.key) ? Colors.white : null,
                        leading: Icon(
                          mesh.connected.contains(entry.key)
                              ? Icons.bluetooth_connected_rounded
                              : Icons.phone_android_rounded,
                          color: highlighted(entry.key)
                              ? Colors.white
                              : context.colors.info,
                        ),
                        title: Text(entry.value),
                        subtitle: Text(
                          mesh.connected.contains(entry.key)
                              ? 'เชื่อมต่อแล้ว • แตะเพื่อแชท'
                              : switch (mesh.discoveredModes[entry.key]) {
                                  'S' =>
                                    'SOS ขอความช่วยเหลือ • แตะเพื่อจับคู่และแชท',
                                  'R' =>
                                    'ประกาศกู้ภัย • จับคู่เพื่อตรวจใบรับรองและแชท',
                                  _ => 'พร้อมจับคู่',
                                },
                        ),
                        trailing: mesh.connected.contains(entry.key)
                            ? Icon(
                                Icons.chat_bubble_outline_rounded,
                                color: highlighted(entry.key)
                                    ? Colors.white
                                    : context.colors.info,
                              )
                            : TextButton(
                                onPressed: () {
                                  _chatAfterPairing = entry.key;
                                  mesh.connect(entry.key, force: true);
                                },
                                style: TextButton.styleFrom(
                                  foregroundColor: highlighted(entry.key)
                                      ? Colors.white
                                      : null,
                                ),
                                child: const Text('เชื่อมต่อ'),
                              ),
                        onTap: () {
                          final peer = mesh.identities[entry.key];
                          if (peer != null) {
                            chat(peer);
                          } else {
                            _chatAfterPairing = entry.key;
                            mesh.connect(entry.key, force: true);
                          }
                        },
                      ),
                    ),
                  ),
                for (final peer in relayed)
                  ListTile(
                    leading: const Icon(Icons.alt_route_rounded),
                    title: Text(peer.name),
                    subtitle: Text('ผ่านเครื่องตัวกลาง • ${peer.hops} ทอด'),
                    trailing: const Icon(Icons.chat_bubble_outline),
                    onTap: () => chat(peer),
                  ),
                const SizedBox(height: 16),
                if (activeCases.isNotEmpty) ...[
                  const SizedBox(height: 24),
                  Text(
                    'SOS ที่ติดต่อได้',
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
                          borderColor: AppColors.sos,
                          backgroundColor: AppColors.sos.withValues(alpha: .12),
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
                                  'SOS · ${message.data['sender'] ?? 'บุคคลใกล้เคียง'}',
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
