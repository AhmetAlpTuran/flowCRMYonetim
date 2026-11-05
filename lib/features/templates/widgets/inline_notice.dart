import 'package:flutter/material.dart';

import '../../../ui/ui.dart';

/// A short inline message on a soft tone fill: an error to correct, a saved notice
/// or guidance. Announced to screen readers when it appears. [action] sits under
/// the text (usually one retry button).
class InlineNotice extends StatelessWidget {
  const InlineNotice(this.message, {super.key, this.tone = FlowTone.neutral, this.action});

  final String message;
  final FlowTone tone;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final c = FlowColors.of(context);
    final icon = switch (tone) {
      FlowTone.danger => Icons.error_outline,
      FlowTone.warning => Icons.warning_amber_rounded,
      FlowTone.accent => Icons.check_circle_outline,
      FlowTone.assistant => Icons.auto_awesome_outlined,
      FlowTone.info || FlowTone.neutral => Icons.info_outline,
    };
    return Semantics(
      liveRegion: true,
      container: true,
      child: Container(
        padding: const EdgeInsets.fromLTRB(FlowSpace.md, FlowSpace.md, FlowSpace.md, FlowSpace.md),
        decoration: BoxDecoration(
          color: tone == FlowTone.neutral ? c.raised : c.toneFill(tone),
          borderRadius: FlowRadius.controlAll,
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Padding(
              padding: const EdgeInsets.only(top: 1),
              child: Icon(icon, size: 18, color: c.toneText(tone)),
            ),
            const SizedBox(width: 10),
            Expanded(child: Text(message, style: Theme.of(context).textTheme.bodyMedium)),
          ]),
          if (action != null) ...[
            const SizedBox(height: FlowSpace.sm),
            Padding(padding: const EdgeInsets.only(left: 28), child: action!),
          ],
        ]),
      ),
    );
  }
}

/// One line of a checklist: a lime check for what holds, a muted info mark for notes.
class CheckLine extends StatelessWidget {
  const CheckLine(this.label, {super.key, this.ok = true, this.note = false});

  final String label;
  final bool ok;

  /// Muted informational line (no check).
  final bool note;

  @override
  Widget build(BuildContext context) {
    final c = FlowColors.of(context);
    final color = note ? c.muted : (ok ? c.accentText : c.warning);
    final icon = note ? Icons.info_outline : (ok ? Icons.check_rounded : Icons.radio_button_unchecked);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Padding(padding: const EdgeInsets.only(top: 1), child: Icon(icon, size: 18, color: color)),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            label,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: note ? c.muted : c.text, height: 1.4),
          ),
        ),
      ]),
    );
  }
}
