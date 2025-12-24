import 'package:flutter/material.dart';

class ChartPlaceholder extends StatelessWidget {
  const ChartPlaceholder({super.key});

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: 2.4,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(16),
        ),
        child: CustomPaint(
          painter: _ChartPainter(
            primary: Theme.of(context).colorScheme.primary,
            secondary: Theme.of(context).colorScheme.tertiary,
          ),
        ),
      ),
    );
  }
}

class _ChartPainter extends CustomPainter {
  _ChartPainter({required this.primary, required this.secondary});

  final Color primary;
  final Color secondary;

  @override
  void paint(Canvas canvas, Size size) {
    final linePaint = Paint()
      ..color = primary.withOpacity(0.6)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3;
    final accentPaint = Paint()
      ..color = secondary.withOpacity(0.4)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;

    final linePath = Path()
      ..moveTo(0, size.height * 0.7)
      ..cubicTo(size.width * 0.25, size.height * 0.35, size.width * 0.5,
          size.height * 0.85, size.width * 0.75, size.height * 0.5)
      ..quadraticBezierTo(
          size.width * 0.9, size.height * 0.3, size.width, size.height * 0.45);

    final accentPath = Path()
      ..moveTo(0, size.height * 0.4)
      ..quadraticBezierTo(size.width * 0.35, size.height * 0.2,
          size.width * 0.6, size.height * 0.35)
      ..quadraticBezierTo(
          size.width * 0.8, size.height * 0.5, size.width, size.height * 0.25);

    canvas.drawPath(linePath, linePaint);
    canvas.drawPath(accentPath, accentPaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}