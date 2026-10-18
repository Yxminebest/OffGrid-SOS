import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import '../../app/theme.dart';
import '../../models/user.dart';
import '../../services/nearby_mesh_service.dart';
import 'rescue_case_chat_screen.dart';
import '../../widgets/location_actions.dart';

class RescueScreen extends StatefulWidget {
  const RescueScreen({super.key, required this.me, this.service});
  final AppUser me;
  final NearbyMeshService? service;
  @override
  State<RescueScreen> createState() => _RescueScreenState();
}

class _RescueScreenState extends State<RescueScreen> {
  late final mesh = widget.service ?? NearbyMeshService.instance;
  bool changing = false;
  @override
  void initState() {
    super.initState();
    mesh.addListener(_onChange);
  }

  void _onChange() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    mesh.removeListener(_onChange);
    super.dispose();
  }

  List<MeshMessage> get cases {
    // Latest state for each origin + caseId, including cancellation updates.
    final latest = <String, MeshMessage>{};
    for (final m in mesh.inbox) {
      if (m.kind != 'sos' || m.data['origin'] == mesh.deviceId) {
        continue;
      }
      final body = m.data['data'];
      if (body is! Map || body['caseId'] is! String) {
        continue;
      }
      final key = '${m.data['origin']}:${body['caseId']}';
      latest.putIfAbsent(key, () => m);
    }
    return latest.values
        .where((m) => (m.data['data'] as Map)['active'] == true)
        .toList();
  }

  Future<void> toggle() async {
    if (changing || !widget.me.isVerifiedRescuer) {
      return;
    }
    setState(() => changing = true);
    try {
      if (!mesh.running) {
        await mesh.start(widget.me.fullName, user: widget.me);
        if (!mesh.running) {
          throw StateError(mesh.status);
        }
      }
      await mesh.setRescue(!mesh.rescueActive);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('เปิด Rescue ไม่สำเร็จ: $e')));
      }
    } finally {
      if (mounted) setState(() => changing = false);
    }
  }

  Future<void> openMap(BuildContext context, double lat, double lng) async {
    await LocationActions.show(context, lat, lng);
  }

  void showCase(BuildContext context, MeshMessage m) {
    final body = m.data['data'] as Map;
    final lat = double.tryParse(body['lat']?.toString() ?? '');
    final lng = double.tryParse(body['lng']?.toString() ?? '');
    final origin = m.data['origin']?.toString() ?? '';
    final caseId = body['caseId']?.toString() ?? '';
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                '🚨 รายละเอียด SOS',
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w900,
                  color: Colors.redAccent,
                ),
              ),
              const SizedBox(height: 12),
              Text('จาก: ${m.data['sender'] ?? 'อุปกรณ์ใกล้เคียง'}'),
              const SizedBox(height: 8),
              Text(
                body['text']?.toString() ?? 'ต้องการความช่วยเหลือ',
                style: const TextStyle(fontSize: 18),
              ),
              const SizedBox(height: 10),
              Text(
                lat == null || lng == null ? 'ไม่มีพิกัด' : 'พิกัด: $lat, $lng',
              ),
              if (body['lastKnown'] == true)
                const Text(
                  'พิกัดล่าสุด ไม่ใช่ตำแหน่งปัจจุบัน',
                  style: TextStyle(color: Colors.orangeAccent),
                ),
              if (body['recordedAt'] != null)
                Text(
                  'เวลาที่บันทึกพิกัด: ${body['recordedAt']}',
                  style: TextStyle(color: context.colors.muted, fontSize: 12),
                ),
              const SizedBox(height: 16),
              if (lat != null && lng != null)
                OutlinedButton.icon(
                  onPressed: () => openMap(sheetContext, lat, lng),
                  icon: const Icon(Icons.map_outlined),
                  label: const Text('เปิดตำแหน่งบนแผนที่'),
                ),
              FilledButton.icon(
                onPressed: origin.isEmpty || caseId.isEmpty
                    ? null
                    : () {
                        Navigator.pop(sheetContext);
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => Theme(
                              data: Theme.of(context),
                              child: RescueCaseChatScreen(
                                me: widget.me,
                                caseId: caseId,
                                otherDevice: origin,
                                title:
                                    'แชท SOS • ${m.data['sender'] ?? 'ผู้แจ้งเหตุ'}',
                              ),
                            ),
                          ),
                        );
                      },
                icon: const Icon(Icons.chat_bubble_outline),
                label: const Text('แชทกับผู้แจ้ง SOS'),
              ),
              const SizedBox(height: 8),
              Text(
                mesh.isDemoOrigin(origin)
                    ? 'โหมดจำลอง: ไม่ได้ส่งผ่าน Nearby และไม่บันทึก Supabase'
                    : 'แชทผ่าน Nearby เก็บประวัติในเครื่อง และส่งเมื่อเชื่อมต่อกับผู้แจ้งเหตุ',
                style: TextStyle(fontSize: 12, color: context.colors.muted),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => _buildPage(context);

  Widget _buildPage(BuildContext context) {
    final allowed = widget.me.isVerifiedRescuer;
    final onDuty = allowed && mesh.rescueActive;
    final active = cases;
    return Scaffold(
      appBar: AppBar(
        title: const Text('ศูนย์กู้ภัย'),
        actions: [
          if (allowed)
            Padding(
              padding: const EdgeInsets.only(right: 16),
              child: Center(
                child: Text(
                  onDuty ? '● เปิดโหมดกู้ภัย' : 'ปิดโหมดกู้ภัย',
                  style: TextStyle(
                    color: onDuty
                        ? context.colors.rescue
                        : context.colors.muted,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            if (!allowed)
              const Card(
                child: Padding(
                  padding: EdgeInsets.all(20),
                  child: Text(
                    'บัญชีนี้ยังไม่มีสิทธิ์ผู้ช่วยเหลือที่ผ่านการยืนยัน',
                  ),
                ),
              )
            else ...[
              Card(
                color: onDuty
                    ? const Color(0xFF1859A9)
                    : context.colors.surface,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          Icon(
                            Icons.health_and_safety,
                            size: 30,
                            color: onDuty ? Colors.white : context.colors.muted,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              mesh.rescueActive
                                  ? 'กำลังปฏิบัติหน้าที่'
                                  : 'ยังไม่เปิดรับเคส',
                              style: TextStyle(
                                color: onDuty
                                    ? Colors.white
                                    : context.colors.text,
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        mesh.running
                            ? 'Nearby ทำงาน • เชื่อมต่อ ${mesh.connected.length} เครื่อง'
                            : 'Nearby ยังไม่ได้เริ่ม เครื่องอื่นจึงส่ง SOS มาที่หน้านี้ไม่ได้',
                        style: TextStyle(
                          color: onDuty
                              ? const Color(0xFFE1EEFF)
                              : context.colors.muted,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'RESCUE MODE · หน่วยกู้ภัย',
                        style: TextStyle(
                          color: onDuty ? Colors.white : context.colors.muted,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 1,
                        ),
                      ),
                      const SizedBox(height: 14),
                      FilledButton.icon(
                        style: onDuty
                            ? FilledButton.styleFrom(
                                backgroundColor: Colors.white,
                                foregroundColor: const Color(0xFF1859A9),
                              )
                            : null,
                        onPressed: changing ? null : toggle,
                        icon: Icon(
                          mesh.rescueActive
                              ? Icons.stop_circle
                              : Icons.play_arrow,
                        ),
                        label: Text(
                          changing
                              ? 'กำลังเปลี่ยนสถานะ...'
                              : mesh.rescueActive
                              ? 'หยุดปฏิบัติหน้าที่'
                              : 'เริ่มปฏิบัติหน้าที่',
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 20),
              if (kDebugMode)
                Card(
                  color: context.colors.surfaceSoft,
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          'EMULATOR LAB • จำลองเหตุ SOS',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: context.colors.pending,
                          ),
                        ),
                        const SizedBox(height: 6),
                        const Text(
                          'สร้างเคสจำลองจากผู้แจ้งเหตุอีกเครื่อง เพื่อทดสอบรายการแดง พิกัด และแชท โดยไม่ใช้ Bluetooth หรือ Cloud',
                          style: TextStyle(fontSize: 12),
                        ),
                        const SizedBox(height: 8),
                        FilledButton.icon(
                          onPressed: mesh.createDemoSos,
                          icon: const Icon(Icons.science_outlined),
                          label: const Text('จำลอง SOS เข้ามา'),
                        ),
                      ],
                    ),
                  ),
                ),
              const SizedBox(height: 20),
              Row(
                children: [
                  const Expanded(
                    child: Text(
                      'SOS ที่ได้รับจาก Nearby',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      color: active.isEmpty
                          ? context.colors.surfaceSoft
                          : AppColors.error,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Text(
                      '${active.length} เคส',
                      style: TextStyle(
                        color: active.isEmpty
                            ? context.colors.text
                            : Colors.white,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              if (!mesh.rescueActive)
                Text(
                  'เปิดโหมดปฏิบัติหน้าที่เพื่อเตรียมรับ SOS',
                  style: TextStyle(color: context.colors.muted),
                ),
              if (active.isEmpty)
                Card(
                  child: Padding(
                    padding: EdgeInsets.all(24),
                    child: Column(
                      children: [
                        Icon(
                          Icons.notifications_none,
                          size: 40,
                          color: context.colors.muted,
                        ),
                        SizedBox(height: 10),
                        Text('ยังไม่มี SOS จากอุปกรณ์ที่เชื่อมต่อ'),
                        SizedBox(height: 4),
                        Text(
                          'SOS ที่ส่งผ่าน Cloud ยังไม่รวมอยู่ในรายการนี้',
                          style: TextStyle(
                            color: context.colors.muted,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              for (final m in active)
                Card(
                  color: Theme.of(context).colorScheme.errorContainer,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(15),
                    side: const BorderSide(color: Colors.redAccent),
                  ),
                  child: InkWell(
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => RescueCaseChatScreen(
                          me: widget.me,
                          caseId: (m.data['data'] as Map)['caseId'].toString(),
                          otherDevice: m.data['origin'].toString(),
                          title: 'SOS • ${m.data['sender']}',
                        ),
                      ),
                    ),
                    borderRadius: BorderRadius.circular(15),
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (m.data['simulation'] == true)
                            Text(
                              'SIMULATION • ไม่ใช่เหตุจริง',
                              style: TextStyle(
                                color: context.colors.pending,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          Row(
                            children: [
                              Icon(
                                Icons.warning_amber_rounded,
                                color: Colors.redAccent,
                              ),
                              SizedBox(width: 8),
                              Text(
                                'SOS • ต้องการความช่วยเหลือ',
                                style: TextStyle(
                                  fontWeight: FontWeight.w900,
                                  color: Theme.of(
                                    context,
                                  ).colorScheme.onErrorContainer,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Text(
                            '${m.data['sender'] ?? 'ผู้แจ้งเหตุ'} • ${m.data['at'] ?? ''}',
                            style: TextStyle(
                              color: context.colors.muted,
                              fontSize: 12,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            '${(m.data['data'] as Map)['text'] ?? ''}',
                            maxLines: 3,
                            overflow: TextOverflow.ellipsis,
                          ),
                          TextButton.icon(
                            onPressed: () => showCase(context, m),
                            icon: const Icon(Icons.location_on_outlined),
                            label: const Text('ดูรายละเอียดและพิกัด'),
                          ),
                          const SizedBox(height: 10),
                          Text(
                            'แตะการ์ดเพื่อเริ่มแชท →',
                            style: TextStyle(color: context.colors.info),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              const SizedBox(height: 16),
              Text(
                'ข้อจำกัด: รับเฉพาะ SOS ผ่าน Nearby ที่จับคู่กันแล้ว • ไม่ใช่ระบบแจ้งเตือนฉุกเฉินที่รับประกันการส่ง • แผนที่ต้องใช้แอปที่มีข้อมูลแผนที่รองรับ',
                style: TextStyle(
                  color: context.colors.muted,
                  fontSize: 12,
                  height: 1.5,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
