import 'package:flutter/material.dart';

import '../app_typography.dart';
import '../format.dart';
import '../tokens.dart';

/// One status label for the whole app: mono caps on a soft tone fill.
class StatusBadge extends StatelessWidget {
  const StatusBadge(this.label, {super.key, this.tone = FlowTone.neutral});

  final String label;
  final FlowTone tone;

  @override
  Widget build(BuildContext context) {
    final c = FlowColors.of(context);
    final outlined = tone == FlowTone.neutral;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: c.toneFill(tone),
        borderRadius: BorderRadius.circular(FlowRadius.pill),
        border: outlined ? Border.all(color: c.borderStrong) : null,
      ),
      child: Text(
        upperTr(label),
        style: FlowText.caps(context, size: 10, color: c.toneText(tone)),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }
}

/// Who wrote a message: the bot ("BOT", teal) or a team member (initials, lime).
class RoleTag extends StatelessWidget {
  const RoleTag.bot({super.key}) : initials = null;

  const RoleTag.agent(this.initials, {super.key});

  final String? initials;

  @override
  Widget build(BuildContext context) {
    final c = FlowColors.of(context);
    final bot = initials == null;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
      decoration: BoxDecoration(
        color: bot ? c.teal : c.accentSoft,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        bot ? 'BOT' : initials!,
        style: FlowText.caps(context, size: 10, color: bot ? c.onLime : c.accentText)
            .copyWith(fontWeight: FontWeight.w600),
      ),
    );
  }
}

/// A rounded square with initials, or the business's identity color.
class InitialsAvatar extends StatelessWidget {
  const InitialsAvatar(this.name, {super.key, this.size = 40, this.color, this.accent = false});

  final String name;
  final double size;

  /// Solid identity color (a business); white initials.
  final Color? color;

  /// Lime-tinted (the signed-in user).
  final bool accent;

  @override
  Widget build(BuildContext context) {
    final c = FlowColors.of(context);
    final background = color ?? (accent ? c.accentSoft : c.raised);
    final foreground = color != null ? const Color(0xFFFFFFFF) : (accent ? c.accentText : c.text);
    return ExcludeSemantics(
      child: Container(
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(size * 0.28),
          border: color == null && !accent ? Border.all(color: c.border) : null,
        ),
        child: Text(
          initialsOf(name),
          style: TextStyle(
            fontFamily: FlowFonts.text,
            fontWeight: FontWeight.w700,
            fontSize: size * 0.34,
            color: foreground,
            height: 1,
          ),
        ),
      ),
    );
  }
}

/// A small mono counter pill ("3", "2 YENİ").
class CountPill extends StatelessWidget {
  const CountPill(this.label, {super.key, this.strong = true});

  final String label;

  /// Lime fill; otherwise an outlined neutral pill.
  final bool strong;

  @override
  Widget build(BuildContext context) {
    final c = FlowColors.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 1),
      decoration: BoxDecoration(
        color: strong ? c.lime : null,
        borderRadius: BorderRadius.circular(FlowRadius.pill),
        border: Border.all(color: strong ? c.limeEdge : c.borderStrong),
      ),
      child: Text(
        upperTr(label),
        style: FlowText.mono(context, size: 11, color: strong ? c.onLime : c.muted, weight: FontWeight.w600),
      ),
    );
  }
}
