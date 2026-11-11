import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:offgrid_sos/features/nearby/bluetooth_device_sheet.dart';
import 'package:offgrid_sos/services/bluetooth_link.dart';

class FakeBluetooth extends BluetoothLink {
  int scans = 0;
  int connections = 0;
  @override
  Future<List<Map<String, String>>> paired() async => [];
  @override
  Future<List<Map<String, String>>> discover() async {
    scans++;
    return [
      {'id': 'bt:AA:BB:CC:DD:EE:FF', 'name': 'New phone', 'bonded': 'false'},
    ];
  }

  @override
  Future<void> stopDiscovery() async {}
  @override
  Future<void> connect(String id) async {
    connections++;
  }
}

void main() {
  testWidgets(
    'new unbonded phone is selectable only after explicit named confirmation',
    (tester) async {
      final link = FakeBluetooth();
      String? selected;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () async {
                  selected = await showModalBottomSheet<String>(
                    context: context,
                    isScrollControlled: true,
                    builder: (_) => BluetoothDeviceSheet(link: link),
                  );
                  if (selected != null) await link.connect(selected!);
                },
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      expect(link.connections, 0);
      await tester.tap(find.text('ค้นหาเครื่องใหม่ / รีเฟรช'));
      await tester.pumpAndSettle();
      expect(link.scans, 1);
      expect(link.connections, 0);
      await tester.ensureVisible(find.text('New phone'));
      await tester.tap(find.text('New phone'));
      await tester.pumpAndSettle();
      expect(find.textContaining('เครื่อง: New phone'), findsOneWidget);
      expect(link.connections, 0);
      await tester.tap(find.text('ยกเลิก'));
      await tester.pumpAndSettle();
      expect(selected, isNull);
      expect(link.connections, 0);
      await tester.tap(find.text('New phone'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('ขอเชื่อมต่อ'));
      await tester.pumpAndSettle();
      expect(selected, 'bt:AA:BB:CC:DD:EE:FF');
      expect(link.connections, 1);
    },
  );
}
