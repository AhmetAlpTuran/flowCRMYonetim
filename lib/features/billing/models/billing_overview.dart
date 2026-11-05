/// One plan of the price list (`billing_plans`).
class BillingPlan {
  const BillingPlan({
    required this.key,
    required this.name,
    required this.description,
    required this.monthlyPrice,
    required this.yearlyPrice,
    required this.limits,
    this.onlineMonthly = false,
    this.onlineYearly = false,
  });

  factory BillingPlan.fromJson(Map<String, dynamic> json) => BillingPlan(
        key: json['key'] as String,
        name: json['name'] as String? ?? '',
        description: json['description'] as String? ?? '',
        monthlyPrice: (json['monthly_price_try'] as num?)?.toDouble() ?? 0,
        yearlyPrice: (json['yearly_price_try'] as num?)?.toDouble(),
        limits: PlanLimits.fromJson(json),
        onlineMonthly: json['online_monthly'] == true,
        onlineYearly: json['online_yearly'] == true,
      );

  final String key;
  final String name;
  final String description;
  final double monthlyPrice;
  final double? yearlyPrice;
  final PlanLimits limits;

  /// Whether the plan can be paid online (an iyzico pricing plan exists) per period.
  final bool onlineMonthly;
  final bool onlineYearly;

  bool online(String period) => period == 'yearly' ? onlineYearly : onlineMonthly;
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
    this.provider,
    this.hasBillingProfile = false,
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
      provider: json['provider'] as String?,
      hasBillingProfile: json['has_billing_profile'] == true,
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

  /// `iyzico` for online subscriptions, `manual` for owner-managed ones.
  final String? provider;
  final bool hasBillingProfile;
  final DateTime? trialEndsAt;
  final DateTime? currentPeriodEnd;
  final DateTime? graceEndsAt;
  final PlanLimits limits;
  final BillingUsage usage;
  final List<BillingPlan> plans;

  /// An iyzico subscription that is being paid: plan changes and cancellation go
  /// through iyzico instead of a new checkout.
  bool get hasOnlineSubscription => provider == 'iyzico' && (status == 'active' || status == 'past_due');
}

/// Billing details iyzico requires (`tenant_billing_profiles`).
class BillingProfile {
  const BillingProfile({
    required this.contactName,
    required this.contactSurname,
    required this.email,
    required this.phone,
    required this.identityNumber,
    required this.address,
    required this.city,
    this.companyName,
    this.taxOffice,
    this.zipCode,
  });

  factory BillingProfile.fromJson(Map<String, dynamic> json) => BillingProfile(
        contactName: json['contact_name'] as String? ?? '',
        contactSurname: json['contact_surname'] as String? ?? '',
        email: json['email'] as String? ?? '',
        phone: json['phone'] as String? ?? '',
        identityNumber: json['identity_number'] as String? ?? '',
        address: json['address'] as String? ?? '',
        city: json['city'] as String? ?? '',
        companyName: json['company_name'] as String?,
        taxOffice: json['tax_office'] as String?,
        zipCode: json['zip_code'] as String?,
      );

  final String contactName;
  final String contactSurname;
  final String email;
  final String phone;
  final String identityNumber;
  final String address;
  final String city;
  final String? companyName;
  final String? taxOffice;
  final String? zipCode;
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
