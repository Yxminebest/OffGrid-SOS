import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';
import '../app/theme.dart';
import '../models/user.dart';
import '../services/nearby_mesh_service.dart';
import '../services/unified_chat_service.dart';
import '../features/chat/unified_conversation_screen.dart';
import 'app_card.dart';

/// Live radio discovery only. Historical contacts never appear as nearby.
class NearbyPeoplePanel extends StatelessWidget {
  const NearbyPeoplePanel({super.key, required this.me, this.mesh});
  final AppUser me;
  final NearbyMeshService? mesh;

  @override
  Widget build(BuildContext context) {
    final service = mesh ?? NearbyMeshService.instance;
    return ListenableBuilder(
      listenable: service,
      builder: (context, _) {
        final endpoints = service.visiblePeers.keys.toList()
          ..sort((a, b) {
            bool rescue(String id) {
              final peer = service.identities[id];
              return peer != null && service.isPeerRescueActive(peer.deviceId);
            }

            return (rescue(b) ? 1 : 0).compareTo(rescue(a) ? 1 : 0);
          });
        return AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'บุคคลใกล้เคียง · ${endpoints.length}',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              if (endpoints.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Text(
                    service.needsPermissionSettings
                        ? 'กรุณาอนุญาตอุปกรณ์ใกล้เคียงในการตั้งค่า'
                        : service.needsLocationSettings
                        ? 'กรุณาเปิดบริการตำแหน่ง'
                        : service.running || service.busy
                        ? 'กำลังค้นหาบุคคลใกล้เคียง…'
                        : service.status,
                  ),
                ),
              if (service.needsPermissionSettings)
                OutlinedButton.icon(
                  onPressed: openAppSettings,
                  icon: const Icon(Icons.settings_outlined),
                  label: const Text('เปิดการตั้งค่าสิทธิ์'),
                ),
              if (service.needsLocationSettings)
                OutlinedButton.icon(
                  onPressed: Geolocator.openLocationSettings,
                  icon: const Icon(Icons.location_on_outlined),
                  label: const Text('เปิดบริการตำแหน่ง'),
                ),
              if (!service.running &&
                  !service.busy &&
                  !service.needsPermissionSettings &&
                  !service.needsLocationSettings)
                OutlinedButton.icon(
                  onPressed: () =>
                      service.resumePreferred(me, startIfUnset: true),
                  icon: const Icon(Icons.refresh),
                  label: const Text('ลองเชื่อมต่ออีกครั้ง'),
                ),
              for (final endpoint in endpoints)
                Builder(
                  builder: (context) {
                    final peer = service.identities[endpoint];
                    final ready =
                        service.connected.contains(endpoint) && peer != null;
                    final rescue =
                        ready && service.isPeerRescueActive(peer.deviceId);
                    final color = rescue ? Colors.white : context.colors.text;
                    return Card(
                      color: rescue
                          ? AppColors.rescueStrong
                          : context.colors.surfaceSoft,
                      child: ListTile(
                        leading: Icon(
                          rescue
                              ? Icons.health_and_safety
                              : Icons.person_outline,
                          color: color,
                        ),
                        title: Text(
                          peer?.name ??
                              service.visiblePeers[endpoint] ??
                              'บุคคลใกล้เคียง',
                          style: TextStyle(color: color),
                        ),
                        subtitle: Text(
                          rescue
                              ? 'หน่วยกู้ภัย · พร้อมสนทนา'
                              : ready
                              ? 'พร้อมสนทนา'
                              : 'ยังไม่เชื่อมต่อ • เลือกเชื่อมต่อในหน้าใกล้เคียง',
                          style: TextStyle(color: color),
                        ),
                        trailing: ready
                            ? Icon(Icons.chat_bubble_outline, color: color)
                            : null,
                        onTap: !ready
                            ? null
                            : () => Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (_) => UnifiedConversationScreen(
                                    me: me,
                                    contact: ChatContact(
                                      name: peer.name,
                                      device: peer.deviceId,
                                    ),
                                  ),
                                ),
                              ),
                      ),
                    );
                  },
                ),
            ],
          ),
        );
      },
    );
  }
}
