import 'package:flutter/material.dart';
import '../../models/user.dart';
import '../../services/nearby_mesh_service.dart';
import '../../widgets/location_actions.dart';
import '../chat/nearby_conversation_screen.dart';

/// Latest received state per case, including SOS cancellation; stored locally.
class RescueHistoryScreen extends StatelessWidget {
  const RescueHistoryScreen({super.key, required this.me, this.service});
  final AppUser me;
  final NearbyMeshService? service;

  @override
  Widget build(BuildContext context) {
    final mesh = service ?? NearbyMeshService.instance;
    return Scaffold(
      appBar: AppBar(title: const Text('ประวัติเคส SOS ที่ได้รับ')),
      body: SafeArea(
        child: StreamBuilder<List<Map<String, dynamic>>>(
          stream: mesh.chats.watchSos(me.id),
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return const Center(
                child: Text('อ่านประวัติไม่ได้ กรุณาเปิดหน้านี้อีกครั้ง'),
              );
            }
            if (!snapshot.hasData) {
              return const Center(child: CircularProgressIndicator());
            }
            final rows =
                snapshot.data!
                    .where((row) => row['origin'] != mesh.deviceId)
                    .toList()
                  ..sort(
                    (a, b) => (b['at']?.toString() ?? '').compareTo(
                      a['at']?.toString() ?? '',
                    ),
                  );
            return ListView(
              padding: const EdgeInsets.all(16),
              children: [
                const SizedBox(height: 12),
                if (rows.isEmpty)
                  const Padding(
                    padding: EdgeInsets.all(24),
                    child: Text('ยังไม่มีประวัติเคส SOS ที่ได้รับ'),
                  ),
                for (final row in rows) _caseCard(context, row),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _caseCard(BuildContext context, Map<String, dynamic> row) {
    final body = row['data'] as Map;
    final lat = double.tryParse(body['lat']?.toString() ?? '');
    final lng = double.tryParse(body['lng']?.toString() ?? '');
    final at = DateTime.tryParse(row['at']?.toString() ?? '');
    final name = row['sender']?.toString() ?? 'ผู้แจ้งเหตุ';
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(name, style: Theme.of(context).textTheme.titleMedium),
            Text(
              body['active'] == true
                  ? 'สถานะที่ได้รับล่าสุด: เปิด SOS · ยังไม่ยืนยันปัจจุบัน'
                  : 'ผู้แจ้งหยุด SOS แล้ว',
            ),
            if (at != null) Text('อัปเดต: ${LocationActions.recordedAt(at)}'),
            const SizedBox(height: 8),
            Text(body['text']?.toString() ?? ''),
            if (lat != null && lng != null)
              LocationActions(latitude: lat, longitude: lng),
            OutlinedButton.icon(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => NearbyConversationScreen(
                    me: me,
                    peerId: row['origin'].toString(),
                    name: name,
                    caseId: body['caseId'].toString(),
                    service: service,
                  ),
                ),
              ),
              icon: const Icon(Icons.chat_bubble_outline),
              label: const Text('ดูบทสนทนาของเคส'),
            ),
          ],
        ),
      ),
    );
  }
}
