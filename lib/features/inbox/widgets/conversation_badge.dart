import 'package:flutter/material.dart';

import '../../../ui/ui.dart';
import '../models/conversation.dart';

/// The one status label a conversation shows in the list and the chat header.
/// [userId] is the signed-in employee, for "Size atandı".
({String label, FlowTone tone}) conversationBadge(Conversation conversation, String? userId) {
  switch (conversation.status) {
    case ConversationStatus.closed:
      return (label: 'Kapalı', tone: FlowTone.neutral);
    case ConversationStatus.handoff:
      return (label: 'Temsilci bekliyor', tone: FlowTone.warning);
    case ConversationStatus.pending:
      return (label: 'Beklemede', tone: FlowTone.info);
    case ConversationStatus.open:
      if (userId != null && conversation.assignedTo == userId) {
        return (label: 'Size atandı', tone: FlowTone.accent);
      }
      if (conversation.unreadCount > 0) return (label: 'Yanıt bekliyor', tone: FlowTone.info);
      return (label: 'Açık', tone: FlowTone.neutral);
  }
}

class ConversationStatusBadge extends StatelessWidget {
  const ConversationStatusBadge({super.key, required this.conversation, required this.userId});

  final Conversation conversation;
  final String? userId;

  @override
  Widget build(BuildContext context) {
    final badge = conversationBadge(conversation, userId);
    return StatusBadge(badge.label, tone: badge.tone);
  }
}

/// An inline message inside a panel: an icon and plain text on a soft tone fill.
/// Announced to screen readers when it appears.
class InboxNotice extends StatelessWidget {
  const InboxNotice(this.text, {super.key, this.tone = FlowTone.danger, this.icon});

  final String text;
  final FlowTone tone;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final c = FlowColors.of(context);
    final color = tone == FlowTone.neutral ? c.muted : c.toneText(tone);
    return Semantics(
      liveRegion: true,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: FlowSpace.md, vertical: 10),
        decoration: BoxDecoration(
          color: tone == FlowTone.neutral ? c.raised : c.toneFill(tone),
          borderRadius: FlowRadius.controlAll,
        ),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(
            icon ?? (tone == FlowTone.danger ? Icons.error_outline : Icons.info_outline),
            size: 18,
            color: color,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(color: c.text),
            ),
          ),
        ]),
      ),
    );
  }
}
