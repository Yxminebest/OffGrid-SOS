import 'dart:async';
import 'package:flutter/material.dart';
import '../../services/bluetooth_link.dart';

/// Bonded history and a fresh scan are distinct; neither initiates a link.
class BluetoothDeviceSheet extends StatefulWidget {
  const BluetoothDeviceSheet({super.key, this.link});
  final BluetoothLink? link;

  @override
  State<BluetoothDeviceSheet> createState() => _BluetoothDeviceSheetState();
}

class _BluetoothDeviceSheetState extends State<BluetoothDeviceSheet> {
  late final link = widget.link ?? BluetoothLink.instance;
  List<Map<String, String>> devices = [];
  bool scanning = false;
  String? error;

  @override
  void initState() {
    super.initState();
    unawaited(loadPaired());
  }

  Future<void> loadPaired() async {
    try {
      final rows = await link.paired();
      if (mounted && !scanning) {
        setState(() => devices = rows);
      }
    } catch (_) {
      if (mounted) {
        setState(() => error = 'อ่านรายการเครื่องที่เคยจับคู่ไม่ได้');
      }
    }
  }

  Future<void> scan() async {
    setState(() {
      scanning = true;
      error = null;
    });
    try {
      final rows = await link.discover();
      if (mounted) setState(() => devices = rows);
    } catch (_) {
      if (mounted) {
        setState(
          () => error =
              'ค้นหาไม่ได้ กรุณาเปิด Bluetooth และบริการตำแหน่ง แล้วลองอีกครั้ง',
        );
      }
    } finally {
      if (mounted) {
        setState(() => scanning = false);
      }
    }
  }

  Future<void> makeDiscoverable() async {
    try {
      await link.discoverable();
    } catch (_) {
      if (mounted) {
        setState(() => error = 'เปิดการค้นพบไม่ได้ กรุณาตรวจสิทธิ์ Bluetooth');
      }
    }
  }

  Future<void> select(Map<String, String> device) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('เชื่อมต่อ Bluetooth?'),
        content: Text(
          'เครื่อง: ${device['name']}\n${device['id']!.replaceFirst('bt:', '')}\n\nอีกเครื่องต้องกดยืนยันก่อนจึงจะเชื่อมต่อได้',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('ยกเลิก'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('ขอเชื่อมต่อ'),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) Navigator.pop(context, device['id']);
  }

  @override
  void dispose() {
    unawaited(link.stopDiscovery().catchError((_) {}));
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SafeArea(
    child: ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * .85,
      ),
      child: ListView(
        shrinkWrap: true,
        padding: const EdgeInsets.all(22),
        children: [
          Text(
            'Bluetooth โดยตรง',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: makeDiscoverable,
            icon: const Icon(Icons.visibility),
            label: const Text('ให้เครื่องอื่นค้นพบ 5 นาที'),
          ),
          FilledButton.icon(
            onPressed: scanning ? null : scan,
            icon: const Icon(Icons.search),
            label: Text(scanning ? 'กำลังค้นหา…' : 'ค้นหาเครื่องใหม่ / รีเฟรช'),
          ),
          if (scanning) const LinearProgressIndicator(),
          if (error != null)
            Padding(padding: const EdgeInsets.all(12), child: Text(error!)),
          if (devices.isEmpty && !scanning)
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text('ยังไม่มีเครื่องในรายการ กดค้นหาเครื่องใหม่'),
            ),
          for (final device in devices)
            ListTile(
              leading: const Icon(Icons.bluetooth),
              title: Text(device['name'] ?? 'Bluetooth'),
              subtitle: Text(
                '${device['id']!.replaceFirst('bt:', '')}\n${device['bonded'] == 'false' ? 'เครื่องใหม่ที่ค้นพบ' : 'เคยจับคู่ในระบบ • อาจไม่ได้อยู่ใกล้'}',
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: scanning ? null : () => select(device),
            ),
        ],
      ),
    ),
  );
}
