import 'dart:ui' show PathMetric;

import 'package:flutter/material.dart';

import '../../../ui/ui.dart';

/// A dashed "add another" action, such as "Asistan ekle", with an optional mono note
/// ("1 HAK KALDI"). Lighter than a button, so the view keeps a single primary.
class DashedActionButton extends StatelessWidget {
  const DashedActionButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.note,
    this.icon = Icons.add,
  });

  final String label;
  final String? note;
  final IconData icon;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final c = FlowColors.of(context);
    final enabled = onPressed != null;
    final foreground = enabled ? c.text : c.faint;
    return Semantics(
      button: true,
      enabled: enabled,
      label: note == null ? label : '$label, $note',
      excludeSemantics: true,
      child: CustomPaint(
        painter: _DashedBorderPainter(color: c.borderStrong),
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            onTap: onPressed,
            borderRadius: FlowRadius.cardAll,
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 52),
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: FlowSpace.lg, vertical: FlowSpace.sm),
                  child: Wrap(
                    alignment: WrapAlignment.center,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    spacing: FlowSpace.sm,
                    runSpacing: FlowSpace.xs,
                    children: [
                      Row(mainAxisSize: MainAxisSize.min, children: [
                        Icon(icon, size: 18, color: foreground),
                        const SizedBox(width: FlowSpace.sm),
                        Text(label, style: Theme.of(context).textTheme.labelLarge?.copyWith(color: foreground)),
                      ]),
                      if (note != null) Text(upperTr(note!), style: FlowText.caps(context, color: c.muted)),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _DashedBorderPainter extends CustomPainter {
  const _DashedBorderPainter({required this.color});

  final Color color;
  static const _dash = 6.0;
  static const _gap = 4.0;
  static const _stroke = 1.5;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = (Offset.zero & size).deflate(_stroke / 2);
    final path = Path()..addRRect(RRect.fromRectAndRadius(rect, const Radius.circular(FlowRadius.card)));
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = _stroke;
    for (final PathMetric metric in path.computeMetrics()) {
      for (var distance = 0.0; distance < metric.length; distance += _dash + _gap) {
        canvas.drawPath(metric.extractPath(distance, distance + _dash), paint);
      }
    }
  }

  @override
  bool shouldRepaint(_DashedBorderPainter oldDelegate) => oldDelegate.color != color;
}
