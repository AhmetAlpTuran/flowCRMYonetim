import 'package:flutter/material.dart';

import '../app_typography.dart';
import '../tokens.dart';

/// A KPI: caps label, a big mono numeral and a one-line footnote.
class StatTile extends StatelessWidget {
  const StatTile({
    super.key,
    required this.label,
    required this.value,
    this.footnote,
    this.tone = FlowTone.neutral,
    this.size = 48,
  });

  final String label;
  final String value;
  final String? footnote;

  /// Colors the label; neutral keeps it muted.
  final FlowTone tone;
  final double size;

  @override
  Widget build(BuildContext context) {
    final c = FlowColors.of(context);
    return Semantics(
      label: '$label: $value${footnote == null ? '' : ', $footnote'}',
      excludeSemantics: true,
      child: Container(
        padding: const EdgeInsets.all(FlowSpace.lg + 2),
        decoration: BoxDecoration(
          color: c.surface,
          borderRadius: FlowRadius.cardAll,
          border: Border.all(color: c.border),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(upperTr(label), style: FlowText.caps(context, color: c.toneText(tone)), maxLines: 1,
              overflow: TextOverflow.ellipsis),
          const SizedBox(height: FlowSpace.lg),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(value, style: FlowText.number(context, size: size)),
          ),
          if (footnote != null) ...[
            const SizedBox(height: FlowSpace.sm + 2),
            Text(footnote!, style: Theme.of(context).textTheme.bodySmall, maxLines: 2, overflow: TextOverflow.ellipsis),
          ],
        ]),
      ),
    );
  }
}

/// A labelled meter: "Kampanya mesajı   1.240 / 10.000".
class UsageBar extends StatelessWidget {
  const UsageBar({super.key, required this.label, required this.value, required this.valueLabel});

  final String label;

  /// 0..1; values at 0.8 or above turn amber.
  final double value;
  final String valueLabel;

  @override
  Widget build(BuildContext context) {
    final c = FlowColors.of(context);
    final clamped = value.clamp(0.0, 1.0);
    final warn = clamped >= 0.8;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Row(children: [
        Expanded(child: Text(label, style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: c.muted))),
        const SizedBox(width: FlowSpace.sm),
        Flexible(
          child: FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerRight,
            child: Text(valueLabel, style: FlowText.mono(context, color: warn ? c.warning : c.text)),
          ),
        ),
      ]),
      const SizedBox(height: FlowSpace.sm),
      LinearProgressIndicator(
        value: clamped,
        color: warn ? c.warning : c.meter,
        semanticsLabel: '$label: $valueLabel',
      ),
    ]);
  }
}

/// A label and value on one line; values can be mono (times, numbers).
class KeyValueRow extends StatelessWidget {
  const KeyValueRow({super.key, required this.label, required this.value, this.mono = false, this.valueColor});

  final String label;
  final String value;
  final bool mono;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    final c = FlowColors.of(context);
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Expanded(child: Text(label, style: theme.textTheme.bodyMedium?.copyWith(color: c.muted))),
        const SizedBox(width: FlowSpace.md),
        Flexible(
          child: Text(
            value,
            textAlign: TextAlign.right,
            style: mono
                ? FlowText.mono(context, color: valueColor ?? c.text)
                : theme.textTheme.bodyMedium?.copyWith(color: valueColor ?? c.text),
          ),
        ),
      ]),
    );
  }
}
