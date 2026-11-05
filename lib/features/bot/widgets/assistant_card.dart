import 'package:flutter/material.dart';

import '../../../ui/ui.dart';

/// One assistant on the Asistanlar list: a teal sparkle tile, the name, whether it is
/// the main or an extra assistant, on/off, and the WhatsApp numbers it answers on.
class AssistantCard extends StatelessWidget {
  const AssistantCard({
    super.key,
    required this.name,
    required this.isMain,
    required this.isActive,
    required this.phones,
    required this.onTap,
    this.selected = false,
  });

  final String name;
  final bool isMain;
  final bool isActive;

  /// Display numbers of the WhatsApp numbers this assistant answers on.
  final List<String> phones;
  final VoidCallback onTap;

  /// Highlighted as the one open in the editor beside the list.
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final c = FlowColors.of(context);
    final theme = Theme.of(context);
    final kind = isMain ? 'Ana asistan' : 'Ek asistan';
    final state = isActive ? 'Açık' : 'Kapalı';
    final numbers = phones.isEmpty ? 'Numara atanmadı' : phones.map(formatPhone).join(' · ');
    return Semantics(
      button: true,
      selected: selected,
      label: '$name, $kind, $state, $numbers',
      excludeSemantics: true,
      child: Material(
        color: c.surface,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: FlowRadius.cardAll,
          side: BorderSide(
            color: selected ? (c.isDark ? c.lime : c.text) : c.border,
            width: selected ? 1.5 : 1,
          ),
        ),
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(FlowSpace.lg),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Row(children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: isActive ? c.tealSoft : c.raised,
                    borderRadius: FlowRadius.controlAll,
                  ),
                  child: Icon(Icons.auto_awesome, size: 20, color: isActive ? c.tealText : c.muted),
                ),
                const SizedBox(width: FlowSpace.md),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(
                      name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleMedium?.copyWith(fontSize: 17, fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 2),
                    Text(upperTr(kind), style: FlowText.caps(context, size: 10)),
                  ]),
                ),
                const SizedBox(width: FlowSpace.sm),
                StatusBadge(state, tone: isActive ? FlowTone.accent : FlowTone.neutral),
              ]),
              const SizedBox(height: FlowSpace.md),
              Text(
                phones.isEmpty ? upperTr(numbers) : numbers,
                style: FlowText.mono(context, size: 12),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}
