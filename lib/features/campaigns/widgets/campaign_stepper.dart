import 'package:flutter/material.dart';

import '../../../ui/ui.dart';

enum CampaignStepState { done, current, upcoming }

class CampaignStep {
  const CampaignStep(this.number, this.label, this.state);

  /// "01".."04".
  final String number;
  final String label;
  final CampaignStepState state;
}

/// The composer's numbered steps. Tapping a step scrolls to its section; the form
/// stays one page, so every step can be edited in any order.
class CampaignStepper extends StatelessWidget {
  const CampaignStepper({super.key, required this.steps, this.onTap});

  final List<CampaignStep> steps;
  final ValueChanged<int>? onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      label: 'Adımlar',
      child: LayoutBuilder(builder: (context, constraints) {
        final columns = constraints.maxWidth >= 640 ? steps.length : 2;
        final width = (constraints.maxWidth - (columns - 1) * FlowSpace.sm) / columns;
        return Wrap(spacing: FlowSpace.sm, runSpacing: FlowSpace.sm, children: [
          for (var i = 0; i < steps.length; i++)
            SizedBox(
              width: width,
              child: _StepTile(step: steps[i], onTap: onTap == null ? null : () => onTap!(i)),
            ),
        ]);
      }),
    );
  }
}

class _StepTile extends StatelessWidget {
  const _StepTile({required this.step, this.onTap});

  final CampaignStep step;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = FlowColors.of(context);
    final theme = Theme.of(context);
    final emphasis = c.isDark ? c.lime : c.text;
    final current = step.state == CampaignStepState.current;
    final done = step.state == CampaignStepState.done;
    final stateLabel = switch (step.state) {
      CampaignStepState.done => 'tamamlandı',
      CampaignStepState.current => 'şu an',
      CampaignStepState.upcoming => 'sırada',
    };
    final marker = Container(
      width: 28,
      height: 28,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: done ? c.lime : null,
        border: done
            ? (c.isDark ? null : Border.all(color: c.limeEdge))
            : Border.all(color: current ? emphasis : c.borderStrong, width: current ? 2 : 1),
      ),
      child: done
          ? Icon(Icons.check_rounded, size: 16, color: c.onLime)
          : Text(
              step.number,
              style: FlowText.mono(context,
                  size: 11, weight: FontWeight.w600, color: current ? c.accentText : c.muted),
            ),
    );
    return Semantics(
      button: onTap != null,
      label: 'Adım ${step.number}, ${step.label}, $stateLabel',
      excludeSemantics: true,
      child: Material(
        color: step.state == CampaignStepState.upcoming ? c.canvas : c.surface,
        shape: RoundedRectangleBorder(
          borderRadius: FlowRadius.cardAll,
          side: BorderSide(color: current ? emphasis : c.border),
        ),
        child: InkWell(
          onTap: onTap,
          customBorder: RoundedRectangleBorder(borderRadius: FlowRadius.cardAll),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 60),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: FlowSpace.md, vertical: 10),
              child: Row(children: [
                marker,
                const SizedBox(width: 10),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                    Text(
                      current ? 'ŞU AN' : step.number,
                      style: FlowText.caps(context, size: 10, color: current ? c.accentText : c.muted),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      step.label,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleSmall?.copyWith(
                        color: step.state == CampaignStepState.upcoming ? c.muted : c.text,
                      ),
                    ),
                  ]),
                ),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}

/// A numbered composer section: "ADIM 01" eyebrow, a heading, a plain helper line
/// and the step's fields.
class CampaignStepSection extends StatelessWidget {
  const CampaignStepSection({
    super.key,
    required this.number,
    required this.title,
    this.subtitle,
    this.trailing,
    required this.child,
  });

  final String number;
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SectionCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Eyebrow('Adım $number'),
              const SizedBox(height: 6),
              Semantics(header: true, child: Text(title, style: theme.textTheme.titleLarge)),
              if (subtitle != null) ...[
                const SizedBox(height: 4),
                Text(subtitle!, style: theme.textTheme.bodySmall),
              ],
            ]),
          ),
          if (trailing != null) ...[const SizedBox(width: FlowSpace.md), trailing!],
        ]),
        const SizedBox(height: FlowSpace.lg),
        child,
      ]),
    );
  }
}
