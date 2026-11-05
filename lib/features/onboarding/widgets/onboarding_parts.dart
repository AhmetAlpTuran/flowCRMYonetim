import 'package:flutter/material.dart';

import '../../../ui/ui.dart';

/// An inline message under a form: a correction (danger) or guidance (accent, info).
/// Announced to screen readers when it appears.
class InlineNotice extends StatelessWidget {
  const InlineNotice(this.message, {super.key, this.tone = FlowTone.danger});

  final String message;
  final FlowTone tone;

  @override
  Widget build(BuildContext context) {
    final c = FlowColors.of(context);
    final icon = switch (tone) {
      FlowTone.danger => Icons.error_outline,
      FlowTone.warning => Icons.warning_amber_rounded,
      FlowTone.accent => Icons.check_circle_outline,
      _ => Icons.info_outline,
    };
    return Semantics(
      liveRegion: true,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: FlowSpace.md, vertical: 10),
        decoration: BoxDecoration(
          color: c.toneFill(tone),
          borderRadius: FlowRadius.controlAll,
          border: Border.all(color: c.toneText(tone).withValues(alpha: 0.45)),
        ),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Padding(
            padding: const EdgeInsets.only(top: 1),
            child: Icon(icon, size: 18, color: c.toneText(tone)),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(message, style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: c.text)),
          ),
        ]),
      ),
    );
  }
}

/// Progress pills for a short sequence ("adım 2 / 3"): the current step is long and
/// lime, the others short.
class StepBars extends StatelessWidget {
  const StepBars({super.key, required this.count, required this.index});

  final int count;
  final int index;

  @override
  Widget build(BuildContext context) {
    final c = FlowColors.of(context);
    final duration = FlowMotion.reduced(context) ? Duration.zero : FlowMotion.fast;
    return Semantics(
      label: 'Adım ${index + 1} / $count',
      child: ExcludeSemantics(
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          for (var i = 0; i < count; i++) ...[
            if (i > 0) const SizedBox(width: 6),
            AnimatedContainer(
              duration: duration,
              curve: FlowMotion.curve,
              width: i == index ? 32 : 12,
              height: 4,
              decoration: BoxDecoration(
                color: i == index ? c.meter : c.borderStrong,
                borderRadius: BorderRadius.circular(FlowRadius.pill),
              ),
            ),
          ],
        ]),
      ),
    );
  }
}

/// The page's one staggered entrance: fades and rises [child] after `index` steps of
/// [FlowMotion.stagger]. Renders [child] as is when motion is reduced.
class EntranceRise extends StatefulWidget {
  const EntranceRise({super.key, required this.child, this.index = 0});

  final Widget child;
  final int index;

  @override
  State<EntranceRise> createState() => _EntranceRiseState();
}

class _EntranceRiseState extends State<EntranceRise> with SingleTickerProviderStateMixin {
  AnimationController? _controller;
  Animation<double>? _progress;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_controller != null || FlowMotion.reduced(context)) return;
    final delay = FlowMotion.stagger * widget.index;
    final total = delay + FlowMotion.entrance;
    final controller = AnimationController(vsync: this, duration: total);
    _controller = controller;
    _progress = CurvedAnimation(
      parent: controller,
      curve: Interval(delay.inMicroseconds / total.inMicroseconds, 1, curve: FlowMotion.curve),
    );
    controller.forward();
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final progress = _progress;
    if (progress == null) return widget.child;
    return AnimatedBuilder(
      animation: progress,
      builder: (context, child) => Opacity(
        opacity: progress.value,
        child: Transform.translate(offset: Offset(0, 10 * (1 - progress.value)), child: child),
      ),
      child: widget.child,
    );
  }
}
