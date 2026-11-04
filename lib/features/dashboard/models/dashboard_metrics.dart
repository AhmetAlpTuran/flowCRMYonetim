/// Aggregates from `dashboard_metrics` (see supabase/migrations/20261105110000).
class DashboardMetrics {
  const DashboardMetrics({
    required this.periodDays,
    required this.openConversations,
    required this.pendingConversations,
    required this.handoffConversations,
    required this.unassignedWaiting,
    required this.startedConversations,
    required this.inboundMessages,
    required this.humanReplies,
    required this.botReplies,
    required this.failedReplies,
    required this.supportOpened,
    required this.supportResolved,
    required this.medianFirstResponse,
    required this.medianFirstHumanResponse,
    required this.medianResolution,
    required this.handoffs,
    required this.campaignAccepted,
    required this.campaignDelivered,
    required this.campaignRead,
    required this.campaignFailed,
    required this.daily,
  });

  factory DashboardMetrics.fromJson(Map<String, dynamic> json) {
    Map<String, dynamic> section(String key) =>
        json[key] is Map ? Map<String, dynamic>.from(json[key] as Map) : const {};
    int count(Map<String, dynamic> map, String key) => (map[key] as num?)?.toInt() ?? 0;
    Duration? seconds(Map<String, dynamic> map, String key) => map[key] is num
        ? Duration(milliseconds: ((map[key] as num) * 1000).round())
        : null;
    final conversations = section('conversations');
    final messages = section('messages');
    final support = section('support');
    final campaigns = section('campaigns');
    return DashboardMetrics(
      periodDays: (json['period_days'] as num?)?.toInt() ?? 7,
      openConversations: count(conversations, 'open'),
      pendingConversations: count(conversations, 'pending'),
      handoffConversations: count(conversations, 'handoff'),
      unassignedWaiting: count(conversations, 'unassigned_waiting'),
      startedConversations: count(conversations, 'started'),
      inboundMessages: count(messages, 'inbound'),
      humanReplies: count(messages, 'human_replies'),
      botReplies: count(messages, 'bot_replies'),
      failedReplies: count(messages, 'failed_replies'),
      supportOpened: count(support, 'opened'),
      supportResolved: count(support, 'resolved'),
      medianFirstResponse: seconds(support, 'median_first_response_seconds'),
      medianFirstHumanResponse: seconds(support, 'median_first_human_response_seconds'),
      medianResolution: seconds(support, 'median_resolution_seconds'),
      handoffs: (json['handoffs'] as num?)?.toInt() ?? 0,
      campaignAccepted: count(campaigns, 'accepted'),
      campaignDelivered: count(campaigns, 'delivered'),
      campaignRead: count(campaigns, 'read'),
      campaignFailed: count(campaigns, 'failed'),
      daily: [
        for (final item in (json['daily'] as List? ?? const []))
          if (item is Map)
            DailyActivity(
              day: DateTime.parse(item['day'].toString()),
              inbound: (item['inbound'] as num?)?.toInt() ?? 0,
              replies: (item['replies'] as num?)?.toInt() ?? 0,
            ),
      ],
    );
  }

  final int periodDays;
  final int openConversations;
  final int pendingConversations;
  final int handoffConversations;
  final int unassignedWaiting;
  final int startedConversations;
  final int inboundMessages;
  final int humanReplies;
  final int botReplies;
  final int failedReplies;
  final int supportOpened;
  final int supportResolved;
  final Duration? medianFirstResponse;
  final Duration? medianFirstHumanResponse;
  final Duration? medianResolution;
  final int handoffs;
  final int campaignAccepted;
  final int campaignDelivered;
  final int campaignRead;
  final int campaignFailed;
  final List<DailyActivity> daily;

  /// Share of replies sent by the bot, or null when there were no replies.
  double? get botShare {
    final total = botReplies + humanReplies;
    return total == 0 ? null : botReplies / total;
  }

  double? get deliveryRate =>
      campaignAccepted == 0 ? null : campaignDelivered / campaignAccepted;
  double? get readRate =>
      campaignAccepted == 0 ? null : campaignRead / campaignAccepted;
}

class DailyActivity {
  const DailyActivity({required this.day, required this.inbound, required this.replies});
  final DateTime day;
  final int inbound;
  final int replies;
}

/// "45 sn", "3 dk", "1,5 sa", "2 gün"; "—" when unknown.
String formatDuration(Duration? value) {
  if (value == null) return '—';
  final seconds = value.inSeconds;
  if (seconds < 60) return '$seconds sn';
  if (seconds < 3600) return '${(seconds / 60).round()} dk';
  if (seconds < 86400) {
    final hours = seconds / 3600;
    return '${hours < 10 ? hours.toStringAsFixed(1).replaceAll('.', ',') : hours.round()} sa';
  }
  return '${(seconds / 86400).round()} gün';
}

String formatPercent(double? value) =>
    value == null ? '—' : '%${(value * 100).round()}';
