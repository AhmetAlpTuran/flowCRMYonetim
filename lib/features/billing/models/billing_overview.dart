/// One plan of the price list (`billing_plans`).
class BillingPlan {
  const BillingPlan({
    required this.key,
    required this.name,
    required this.description,
    required this.monthlyPrice,
    required this.yearlyPrice,
    required this.limits,
  });

  factory BillingPlan.fromJson(Map<String, dynamic> json) => BillingPlan(
        key: json['key'] as String,
        name: json['name'] as String? ?? '',
        description: json['description'] as String? ?? '',
        monthlyPrice: (json['monthly_price_try'] as num?)?.toDouble() ?? 0,
        yearlyPrice: (json['yearly_price_try'] as num?)?.toDouble(),
        limits: PlanLimits.fromJson(json),
      );

  final String key;
  final String name;
  final String description;
  final double monthlyPrice;
  final double? yearlyPrice;
  final PlanLimits limits;
}

class PlanLimits {
  const PlanLimits({
    required this.seats,
    required this.whatsappNumbers,
    required this.bots,
    required this.aiMonthlyTokens,
    required this.campaignMessagesMonthly,
  });

  factory PlanLimits.fromJson(Map<String, dynamic> json) => PlanLimits(
        seats: (json['seats'] as num?)?.toInt() ?? 0,
        whatsappNumbers: (json['whatsapp_numbers'] as num?)?.toInt() ?? 0,
        bots: (json['bots'] as num?)?.toInt() ?? 0,
        aiMonthlyTokens: (json['ai_monthly_tokens'] as num?)?.toInt() ?? 0,
        campaignMessagesMonthly: (json['campaign_messages_monthly'] as num?)?.toInt() ?? 0,
      );

  final int seats;
  final int whatsappNumbers;
  final int bots;
  final int aiMonthlyTokens;
  final int campaignMessagesMonthly;
}

class BillingUsage {
  const BillingUsage({
    required this.seats,
    required this.whatsappNumbers,
    required this.bots,
    required this.aiTokens,
    required this.campaignMessages,
  });

  factory BillingUsage.fromJson(Map<String, dynamic> json) => BillingUsage(
        seats: (json['seats'] as num?)?.toInt() ?? 0,
        whatsappNumbers: (json['whatsapp_numbers'] as num?)?.toInt() ?? 0,
        bots: (json['bots'] as num?)?.toInt() ?? 0,
        aiTokens: (json['ai_tokens'] as num?)?.toInt() ?? 0,
        campaignMessages: (json['campaign_messages'] as num?)?.toInt() ?? 0,
      );

  final int seats;
  final int whatsappNumbers;
  final int bots;
  final int aiTokens;
  final int campaignMessages;
}

/// `tenant_billing_overview`: the subscription, the limits that apply now and this
/// month's usage.
class BillingOverview {
  const BillingOverview({
    required this.status,
    required this.planKey,
    required this.planName,
    required this.monthlyPrice,
    required this.limits,
    required this.usage,
    required this.plans,
    this.billingPeriod,
    this.trialEndsAt,
    this.currentPeriodEnd,
    this.graceEndsAt,
  });

  factory BillingOverview.fromJson(Map<String, dynamic> json) {
    DateTime? date(String key) =>
        json[key] is String ? DateTime.parse(json[key] as String).toLocal() : null;
    final plan = Map<String, dynamic>.from(json['plan'] as Map? ?? const {});
    return BillingOverview(
      status: json['status'] as String? ?? 'expired',
      planKey: plan['key'] as String? ?? '',
      planName: plan['name'] as String? ?? '',
      monthlyPrice: (plan['monthly_price_try'] as num?)?.toDouble() ?? 0,
      billingPeriod: json['billing_period'] as String?,
      trialEndsAt: date('trial_ends_at'),
      currentPeriodEnd: date('current_period_end'),
      graceEndsAt: date('grace_ends_at'),
      limits: PlanLimits.fromJson(Map<String, dynamic>.from(json['limits'] as Map? ?? const {})),
      usage: BillingUsage.fromJson(Map<String, dynamic>.from(json['usage'] as Map? ?? const {})),
      plans: [
        for (final item in (json['plans'] as List? ?? const []))
          BillingPlan.fromJson(Map<String, dynamic>.from(item as Map)),
      ],
    );
  }

  /// `pilot`, `trialing`, `active`, `past_due`, `canceled` or `expired`.
  final String status;
  final String planKey;
  final String planName;
  final double monthlyPrice;
  final String? billingPeriod;
  final DateTime? trialEndsAt;
  final DateTime? currentPeriodEnd;
  final DateTime? graceEndsAt;
  final PlanLimits limits;
  final BillingUsage usage;
  final List<BillingPlan> plans;
}

/// Average tokens of one bot reply, used to show the AI allowance as replies.
const tokensPerReply = 3000;

String formatCount(int value) {
  final digits = value.abs().toString();
  final buffer = StringBuffer(value < 0 ? '-' : '');
  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) buffer.write('.');
    buffer.write(digits[i]);
  }
  return buffer.toString();
}

String formatPrice(double value) => '₺${formatCount(value.round())}';

String formatDate(DateTime value) {
  String two(int n) => n.toString().padLeft(2, '0');
  return '${two(value.day)}.${two(value.month)}.${value.year}';
}
