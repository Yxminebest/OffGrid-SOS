// Run with: flutter test tool/export_brand_test.dart
// Exports the same vector painter used by the UI, with no image dependencies.
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter_test/flutter_test.dart';
import 'package:offgrid_sos/widgets/brand_mark.dart';

Future<void> exportIcon(String path, int size, {bool opaque = false}) async {
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder);
  if (opaque) {
    canvas.drawColor(const ui.Color(0xFFF4C84B), ui.BlendMode.src);
  }
  const BrandMarkPainter().paint(canvas, ui.Size.square(size.toDouble()));
  final picture = recorder.endRecording();
  final image = await picture.toImage(size, size);
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  final file = File(path);
  await file.parent.create(recursive: true);
  await file.writeAsBytes(data!.buffer.asUint8List());
  image.dispose();
  picture.dispose();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('export brand from the shared vector artwork', () async {
    for (final entry in {
      'mdpi': 48,
      'hdpi': 72,
      'xhdpi': 96,
      'xxhdpi': 144,
      'xxxhdpi': 192,
    }.entries) {
      await exportIcon(
        'android/app/src/main/res/mipmap-${entry.key}/ic_launcher.png',
        entry.value,
      );
    }
    await exportIcon('assets/branding/offgrid-icon.png', 1024);
    await exportIcon('web/favicon.png', 48);
    for (final size in [192, 512]) {
      await exportIcon('web/icons/Icon-$size.png', size);
      await exportIcon('web/icons/Icon-maskable-$size.png', size, opaque: true);
    }
  });
}
