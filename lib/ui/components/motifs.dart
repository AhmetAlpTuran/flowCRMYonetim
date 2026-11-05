import 'package:flutter/material.dart';

import '../app_typography.dart';
import '../tokens.dart';

/// The 16 px dot grid behind welcome surfaces, empty states and hero cards.
/// Never use it behind dense lists.
class DotGrid extends StatelessWidget {
  const DotGrid({super.key, required this.child, this.color, this.spacing = 16});

  final Widget child;
  final Color? color;
  final double spacing;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _DotGridPainter(color ?? FlowColors.of(context).dot, spacing),
      child: child,
    );
  }
}

class _DotGridPainter extends CustomPainter {
  _DotGridPainter(this.color, this.spacing);

  final Color color;
  final double spacing;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color;
    for (var y = spacing / 2; y < size.height; y += spacing) {
      for (var x = spacing / 2; x < size.width; x += spacing) {
        canvas.drawCircle(Offset(x, y), 1, paint);
      }
    }
  }

  @override
  bool shouldRepaint(_DotGridPainter old) => old.color != color || old.spacing != spacing;
}

/// Concentric "signal" rings, the brand motif. Decorative only.
class SignalRings extends StatelessWidget {
  const SignalRings({super.key, required this.size, this.rings = 4, this.color, this.dot = false});

  final double size;
  final int rings;
  final Color? color;

  /// Fills the center with a lime dot, as in the logomark.
  final bool dot;

  @override
  Widget build(BuildContext context) {
    final c = FlowColors.of(context);
    return ExcludeSemantics(
      child: CustomPaint(
        size: Size.square(size),
        painter: _RingsPainter(color ?? c.ring, rings, dot ? c.lime : null),
      ),
    );
  }
}

class _RingsPainter extends CustomPainter {
  _RingsPainter(this.color, this.rings, this.dotColor);

  final Color color;
  final int rings;
  final Color? dotColor;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final maxRadius = size.shortestSide / 2 - 1;
    for (var i = 0; i < rings; i++) {
      final radius = maxRadius * (i + 1) / rings;
      final fade = 1 - i / (rings + 0.5);
      canvas.drawCircle(
        center,
        radius,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5
          ..color = color.withValues(alpha: color.a * fade),
      );
    }
    if (dotColor != null) {
      canvas.drawCircle(center, maxRadius / rings * 0.6, Paint()..color = dotColor!);
    }
  }

  @override
  bool shouldRepaint(_RingsPainter old) => old.color != color || old.rings != rings || old.dotColor != dotColor;
}

/// The interim logomark: three lime rings and the "flow" wordmark.
class FlowLogo extends StatelessWidget {
  const FlowLogo({super.key, this.size = 26, this.wordmark = true, this.color});

  final double size;
  final bool wordmark;

  /// Wordmark color; defaults to the theme text color.
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final mark = ExcludeSemantics(
      child: CustomPaint(size: Size.square(size), painter: _LogoPainter()),
    );
    if (!wordmark) return Semantics(label: 'Flow CRM', child: mark);
    return Semantics(
      label: 'Flow CRM',
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          mark,
          SizedBox(width: size * 0.36),
          ExcludeSemantics(
            child: Text(
              'flow',
              style: TextStyle(
                fontFamily: FlowFonts.display,
                fontWeight: FontWeight.w800,
                fontSize: size * 0.88,
                height: 1,
                letterSpacing: -size * 0.034,
                color: color ?? FlowColors.of(context).text,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _LogoPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    const lime = Color(0xFFC6F432);
    final center = size.center(Offset.zero);
    final unit = size.shortestSide / 30;
    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5 * unit;
    canvas.drawCircle(center, 13.5 * unit, stroke..color = lime.withValues(alpha: 0.35));
    canvas.drawCircle(center, 8.5 * unit, stroke..color = lime.withValues(alpha: 0.75));
    canvas.drawCircle(center, 4 * unit, Paint()..color = lime);
  }

  @override
  bool shouldRepaint(_LogoPainter oldDelegate) => false;
}

/// The pulsing lime dot. Static when animations are disabled.
class LiveDot extends StatefulWidget {
  const LiveDot({super.key, this.size = 8, this.color});

  final double size;
  final Color? color;

  @override
  State<LiveDot> createState() => _LiveDotState();
}

class _LiveDotState extends State<LiveDot> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(vsync: this, duration: FlowMotion.pulse);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (FlowMotion.reduced(context)) {
      _controller.stop();
    } else if (!_controller.isAnimating) {
      _controller.repeat();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = FlowColors.of(context);
    final color = widget.color ?? c.lime;
    final dot = Container(
      width: widget.size,
      height: widget.size,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        border: c.isDark ? null : Border.all(color: c.limeEdge),
      ),
    );
    return ExcludeSemantics(
      child: SizedBox.square(
        dimension: widget.size * 2.4,
        child: Center(
          child: AnimatedBuilder(
            animation: _controller,
            builder: (context, child) {
              final t = Curves.easeOut.transform((_controller.value / 0.7).clamp(0, 1));
              return Stack(
                alignment: Alignment.center,
                children: [
                  if (_controller.isAnimating)
                    Container(
                      width: widget.size * (1 + 1.2 * t),
                      height: widget.size * (1 + 1.2 * t),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: color.withValues(alpha: 0.5 * (1 - t)),
                      ),
                    ),
                  child!,
                ],
              );
            },
            child: dot,
          ),
        ),
      ),
    );
  }
}

/// "● CANLI · 3 SOHBET BEKLİYOR": the live status line.
class LiveLine extends StatelessWidget {
  const LiveLine(this.label, {super.key, this.color});

  final String label;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final c = FlowColors.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const LiveDot(),
        const SizedBox(width: 6),
        Flexible(
          child: Text(
            upperTr(label),
            style: FlowText.caps(context, color: color ?? c.accentText),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}
