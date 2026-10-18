import 'package:flutter/material.dart';

/// High-contrast SOS and warning triangle, readable without brand familiarity.
class BrandMark extends StatelessWidget {
  const BrandMark({super.key, this.size = 44});
  final double size;

  @override
  Widget build(BuildContext context) => Semantics(
    image: true,
    label: 'โลโก้ Offgrid SOS',
    child: SizedBox.square(
      dimension: size,
      child: const CustomPaint(painter: BrandMarkPainter()),
    ),
  );
}

class BrandMarkPainter extends CustomPainter {
  const BrandMarkPainter({this.foregroundOnly = false});
  final bool foregroundOnly;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / 100, size.height / 100);
    if (!foregroundOnly) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          const Rect.fromLTWH(0, 0, 100, 100),
          const Radius.circular(26),
        ),
        Paint()..color = const Color(0xFFF4C84B),
      );
    }
    final triangle = Path()
      ..fillType = PathFillType.evenOdd
      ..moveTo(50, 14)
      ..lineTo(73, 49)
      ..quadraticBezierTo(75, 53, 70, 53)
      ..lineTo(30, 53)
      ..quadraticBezierTo(25, 53, 27, 49)
      ..close()
      ..addRect(const Rect.fromLTWH(48, 27, 4, 12))
      ..addRect(const Rect.fromLTWH(48, 43, 4, 4));
    canvas.drawPath(triangle, Paint()..color = const Color(0xFF30250D));
    final letters = Path()
      ..moveTo(35, 63)
      ..lineTo(26, 63)
      ..quadraticBezierTo(22, 63, 22, 67)
      ..quadraticBezierTo(22, 71, 27, 71)
      ..lineTo(30, 71)
      ..quadraticBezierTo(35, 71, 35, 75)
      ..quadraticBezierTo(35, 79, 31, 79)
      ..lineTo(22, 79)
      ..addRRect(
        RRect.fromRectAndRadius(
          const Rect.fromLTWH(42, 63, 16, 16),
          const Radius.circular(5),
        ),
      )
      ..moveTo(78, 63)
      ..lineTo(69, 63)
      ..quadraticBezierTo(65, 63, 65, 67)
      ..quadraticBezierTo(65, 71, 70, 71)
      ..lineTo(73, 71)
      ..quadraticBezierTo(78, 71, 78, 75)
      ..quadraticBezierTo(78, 79, 74, 79)
      ..lineTo(65, 79);
    canvas.drawPath(
      letters,
      Paint()
        ..color = const Color(0xFF30250D)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 4.4
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(BrandMarkPainter oldDelegate) =>
      foregroundOnly != oldDelegate.foregroundOnly;
}

class BrandLockup extends StatelessWidget {
  const BrandLockup({super.key});

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      const BrandMark(size: 42),
      const SizedBox(width: 11),
      Flexible(
        child: Text(
          'offgrid',
          style: Theme.of(context).textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.w800,
            letterSpacing: -.6,
          ),
        ),
      ),
      const SizedBox(width: 5),
      Text(
        'SOS',
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          fontWeight: FontWeight.w800,
          letterSpacing: 1.4,
        ),
      ),
    ],
  );
}
