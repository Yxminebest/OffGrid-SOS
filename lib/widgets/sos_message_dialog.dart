import 'package:flutter/material.dart';

const sosQuickNeeds = [
  'ติดอยู่บนหลังคา',
  'ติดอยู่ในบ้านชั้นสอง',
  'ขาดน้ำมาก',
  'ต้องการยา',
  'มีผู้ป่วยหนัก',
  'มีผู้บาดเจ็บ',
  'ต้องการอพยพ',
];

/// A plain message keeps presets compatible with existing offline SOS peers.
String composeSosMessage(Set<String> selected, String details) => [
  if (selected.isNotEmpty) sosQuickNeeds.where(selected.contains).join(' • '),
  if (details.trim().isNotEmpty) details.trim(),
].join('\n');

class SosQuickNeeds extends StatelessWidget {
  const SosQuickNeeds({
    super.key,
    required this.selected,
    required this.onChanged,
  });
  final Set<String> selected;
  final void Function(String, bool) onChanged;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const Text(
        'เลือกเหตุฉุกเฉิน',
        style: TextStyle(fontWeight: FontWeight.w700),
      ),
      const Text('เลือกได้หลายข้อ ไม่จำเป็นต้องพิมพ์'),
      const SizedBox(height: 8),
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final need in sosQuickNeeds)
            FilterChip(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
              showCheckmark: true,
              label: Text(need),
              labelStyle: Theme.of(context).textTheme.bodyMedium,
              selected: selected.contains(need),
              onSelected: (value) => onChanged(need, value),
            ),
        ],
      ),
    ],
  );
}

class SosMessageDialog extends StatefulWidget {
  const SosMessageDialog({
    super.key,
    this.initialMessage = '',
    this.selected = const {},
    this.editing = false,
  });
  final String initialMessage;
  final Set<String> selected;
  final bool editing;
  @override
  State<SosMessageDialog> createState() => _SosMessageDialogState();
}

class _SosMessageDialogState extends State<SosMessageDialog> {
  late final Set<String> _selected = {...widget.selected};
  late final TextEditingController _details;
  String? _error;
  @override
  void initState() {
    super.initState();
    var details = widget.initialMessage;
    final lines = details.split('\n');
    final first = lines.first.split(' • ');
    // Only extract an exact preset prefix; preserve all other existing text.
    if (first.isNotEmpty && first.every(sosQuickNeeds.contains)) {
      _selected.addAll(first);
      details = lines.skip(1).join('\n');
    }
    _details = TextEditingController(text: details);
  }

  @override
  void dispose() {
    _details.dispose();
    super.dispose();
  }

  void _submit() {
    final message = composeSosMessage(_selected, _details.text);
    if (message.length > 1000) {
      setState(() => _error = 'ข้อความรวมต้องไม่เกิน 1,000 ตัวอักษร');
      return;
    }
    Navigator.pop(
      context,
      message.isEmpty ? 'ต้องการความช่วยเหลือฉุกเฉิน' : message,
    );
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.editing ? 'แก้ไขข้อความ SOS' : 'ยืนยันขอความช่วยเหลือ'),
    content: SizedBox(
      width: 420,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (widget.editing || widget.selected.isEmpty)
              SosQuickNeeds(
                selected: _selected,
                onChanged: (need, value) => setState(() {
                  value ? _selected.add(need) : _selected.remove(need);
                }),
              ),
            if (!widget.editing && widget.selected.isNotEmpty)
              Text(
                composeSosMessage(_selected, ''),
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  height: 1.6,
                ),
              ),
            const SizedBox(height: 16),
            TextField(
              controller: _details,
              minLines: 2,
              maxLines: 4,
              maxLength: 1000,
              decoration: InputDecoration(
                labelText: 'รายละเอียดเพิ่มเติม (ไม่บังคับ)',
                errorText: _error,
              ),
            ),
            const Text(
              'บันทึกในเครื่องและส่งต่อเมื่อมีอุปกรณ์เชื่อมต่อ ไม่ต้องใช้อินเทอร์เน็ต',
            ),
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('ยกเลิก'),
      ),
      FilledButton(
        onPressed: _submit,
        style: FilledButton.styleFrom(
          backgroundColor: Theme.of(context).colorScheme.error,
          foregroundColor: Colors.white,
        ),
        child: Text(widget.editing ? 'บันทึก' : 'เปิด SOS'),
      ),
    ],
  );
}
