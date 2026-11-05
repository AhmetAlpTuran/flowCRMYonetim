import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../ui/ui.dart';
import '../models/message.dart';
import 'message_delivery_status.dart';
import 'message_media_view.dart';

/// Who wrote a message. The server records `sent_by` only for employee replies
/// (`enqueue_inbox_message`); assistant replies are written by the bot worker
/// without it, and customer input has `is_from_customer`.
enum MessageRole { customer, bot, agent }

MessageRole messageRoleOf(Message message) {
  if (message.isFromCustomer) return MessageRole.customer;
  return message.sentBy == null ? MessageRole.bot : MessageRole.agent;
}

DateTime _utcDay(DateTime time) {
  final local = time.toLocal();
  return DateTime.utc(local.year, local.month, local.day);
}

/// Day divider text in Turkish caps: "BUGÜN", "DÜN", "5 KASIM" or "5 KASIM 2025".
String dayDividerLabel(DateTime time, {DateTime? now}) {
  final today = _utcDay(now ?? DateTime.now());
  final day = _utcDay(time);
  final days = today.difference(day).inDays;
  if (days == 0) return 'BUGÜN';
  if (days == 1) return 'DÜN';
  return upperTr(day.year == today.year ? formatDayMonth(time) : formatDate(time));
}

/// Centered caps label between days of a conversation.
class ChatDayDivider extends StatelessWidget {
  const ChatDayDivider(this.time, {super.key});

  final DateTime time;

  @override
  Widget build(BuildContext context) {
    final c = FlowColors.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: FlowSpace.md),
      child: Row(children: [
        Expanded(child: Divider(color: c.border)),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: FlowSpace.md),
          child: Semantics(
            header: true,
            child: Text(dayDividerLabel(time), style: FlowText.caps(context, color: c.faint)),
          ),
        ),
        Expanded(child: Divider(color: c.border)),
      ]),
    );
  }
}

/// A small outlined caps note in the conversation ("GÖRÜLDÜ 11:52 · YÖNETİCİ").
class ChatSystemNote extends StatelessWidget {
  const ChatSystemNote(this.text, {super.key, this.icon});

  final String text;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final c = FlowColors.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        border: Border.all(color: c.border),
        borderRadius: BorderRadius.circular(FlowRadius.pill),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        if (icon != null) ...[Icon(icon, size: 13, color: c.muted), const SizedBox(width: 6)],
        Flexible(
          child: Text(
            upperTr(text),
            style: FlowText.caps(context, size: 10),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
          ),
        ),
      ]),
    );
  }
}

/// One message: customers on the left on a raised surface, the assistant on the
/// right with a teal outline and "BOT", team members on the right in a lime tint
/// with their initials. Times are local and in mono.
class MessageBubble extends StatelessWidget {
  const MessageBubble({
    super.key,
    required this.message,
    this.mine = false,
    this.footer,
  });

  final Message message;

  /// Written by the signed-in employee (labelled "Siz").
  final bool mine;

  /// Extra controls under the bubble (e.g. cancelling a queued reply).
  final Widget? footer;

  @override
  Widget build(BuildContext context) {
    final c = FlowColors.of(context);
    final theme = Theme.of(context);
    final role = messageRoleOf(message);
    final outbound = role != MessageRole.customer;
    const tail = Radius.circular(4);
    const round = Radius.circular(FlowRadius.card);
    final (Color fill, Color edge) = switch (role) {
      MessageRole.customer => (c.raised, c.border),
      MessageRole.bot => (c.tealSoft, c.teal),
      MessageRole.agent => (c.accentSoft, c.borderStrong),
    };
    final body = message.media != null
        ? Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
            MessageMediaView(media: message.media!),
            if (mediaBubbleText(message.text, message.media!) case final caption?) ...[
              const SizedBox(height: 6),
              Text(caption, style: theme.textTheme.bodyMedium),
            ],
          ])
        : Text(message.text, style: theme.textTheme.bodyMedium);
    final author = switch (role) {
      MessageRole.customer => null,
      MessageRole.bot => message.sender,
      MessageRole.agent => mine ? 'Siz' : message.sender,
    };

    return LayoutBuilder(builder: (context, constraints) {
      final maxWidth = math.min(constraints.maxWidth * (outbound ? 0.84 : 0.8), 560.0);
      return Align(
        alignment: outbound ? Alignment.centerRight : Alignment.centerLeft,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: maxWidth),
          child: Column(
            crossAxisAlignment: outbound ? CrossAxisAlignment.end : CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (author != null) ...[
                Row(mainAxisSize: MainAxisSize.min, children: [
                  role == MessageRole.bot ? const RoleTag.bot() : RoleTag.agent(initialsOf(message.sender)),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      upperTr(author),
                      style: FlowText.caps(context, size: 10),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ]),
                const SizedBox(height: 6),
              ],
              Semantics(
                label: switch (role) {
                  MessageRole.customer => 'Müşteri',
                  MessageRole.bot => 'Asistan',
                  MessageRole.agent => mine ? 'Siz' : 'Ekip',
                },
                container: true,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 10),
                  decoration: BoxDecoration(
                    color: fill,
                    border: Border.all(color: edge),
                    borderRadius: BorderRadius.only(
                      topLeft: round,
                      topRight: round,
                      bottomLeft: outbound ? round : tail,
                      bottomRight: outbound ? tail : round,
                    ),
                  ),
                  child: body,
                ),
              ),
              const SizedBox(height: 5),
              Wrap(
                spacing: 6,
                runSpacing: 2,
                alignment: outbound ? WrapAlignment.end : WrapAlignment.start,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text(formatClock(message.sentAt), style: FlowText.mono(context, size: 11, color: c.faint)),
                  if (outbound) ...[
                    ExcludeSemantics(child: Text('·', style: FlowText.mono(context, size: 11, color: c.faint))),
                    MessageDeliveryStatus(message: message),
                  ],
                ],
              ),
              if (footer != null) footer!,
            ],
          ),
        ),
      );
    });
  }
}
