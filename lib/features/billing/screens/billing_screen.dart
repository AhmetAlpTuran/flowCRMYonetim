import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../config/app_links.dart';
import '../../../ui/ui.dart';
import '../../tenancy/providers/tenant_providers.dart';
import '../data/billing_repository.dart';
import '../models/billing_overview.dart';
import '../providers/billing_providers.dart';
import '../widgets/billing_profile_sheet.dart';

/// "Abonelik" (administrators): the plan and its status, this month's usage against
/// the limits, billing details, and the plans with online payment through iyzico.
class BillingScreen extends ConsumerStatefulWidget {
  const BillingScreen({super.key});

  @override
  ConsumerState<BillingScreen> createState() => _BillingScreenState();
}

class _BillingScreenState extends ConsumerState<BillingScreen> with WidgetsBindingObserver {
  final _plansKey = GlobalKey();
  String _period = 'monthly';
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // A payment whose callback never arrived is confirmed when the screen opens.
    WidgetsBinding.instance.addPostFrameCallback((_) => _refreshPayment(quiet: true));
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Back from the payment page in the browser.
    if (state == AppLifecycleState.resumed) _refreshPayment(quiet: true);
  }

  void _say(String message, {bool error = false}) {
    if (!mounted) return;
    showAppSnack(context, message, error: error);
  }

  Future<void> _refreshPayment({bool quiet = false}) async {
    if (!mounted) return;
    final tenant = ref.read(selectedTenantProvider);
    if (tenant == null || !ref.read(onlinePurchaseAllowedProvider)) return;
    try {
      final outcome = await ref.read(billingRepositoryProvider).refresh(tenant.id);
      if (!mounted) return;
      if (outcome == 'completed') _say('Ödemeniz alındı; aboneliğiniz etkin.');
      if (outcome != 'none') ref.invalidate(billingOverviewProvider);
    } catch (error) {
      if (!quiet) _say(billingErrorMessage(error), error: true);
    }
  }

  Future<bool?> _editProfile(BillingProfile? initial) => showModalBottomSheet<bool>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        showDragHandle: true,
        builder: (_) => BillingProfileSheet(initial: initial),
      );

  Future<void> _openProfile() async {
    BillingProfile? profile;
    try {
      profile = await ref.read(billingProfileProvider.future);
    } catch (_) {
      profile = null;
    }
    if (!mounted) return;
    if (await _editProfile(profile) == true) _say('Fatura bilgileri kaydedildi.');
  }

  Future<void> _run(Future<void> Function() action) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
    } catch (error) {
      _say(billingErrorMessage(error), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
      ref.invalidate(billingOverviewProvider);
    }
  }

  Future<void> _buy(BillingOverview overview, BillingPlan plan) async {
    final tenant = ref.read(selectedTenantProvider);
    if (tenant == null) return;
    if (!overview.hasBillingProfile && await _editProfile(null) != true) return;
    if (!mounted) return;
    await _run(() async {
      final url = await ref.read(billingRepositoryProvider).startCheckout(tenant.id, plan.key, _period);
      final opened = await ref.read(openPaymentPageProvider)(url);
      if (!opened) throw const BillingFailure('billing_unconfirmed');
      _say('Ödeme sayfası tarayıcıda açıldı. Ödemeden sonra uygulamaya dönün.');
    });
  }

  Future<void> _changePlan(BillingPlan plan) async {
    final tenant = ref.read(selectedTenantProvider);
    if (tenant == null) return;
    final confirmed = await confirmAction(
      context,
      title: 'Plan değiştirilsin mi?',
      message: '${plan.name} planına hemen geçilir. Ücret farkını iyzico kayıtlı kartınızdan tahsil eder.',
      confirmLabel: 'Planı değiştir',
    );
    if (!confirmed) return;
    await _run(() async {
      await ref.read(billingRepositoryProvider).changePlan(tenant.id, plan.key);
      _say('Planınız ${plan.name} olarak değiştirildi.');
    });
  }

  Future<void> _cancel(BillingOverview overview) async {
    final tenant = ref.read(selectedTenantProvider);
    if (tenant == null) return;
    final end = overview.currentPeriodEnd;
    final until = end == null ? 'dönem sonuna' : '${formatDate(end)} tarihine';
    final confirmed = await confirmAction(
      context,
      title: 'Abonelik iptal edilsin mi?',
      message: 'Yeni ödeme alınmaz. $until kadar planınızı kullanmaya devam edersiniz.',
      confirmLabel: 'İptal et',
      destructive: true,
    );
    if (!confirmed) return;
    await _run(() async {
      await ref.read(billingRepositoryProvider).cancel(tenant.id);
      _say('Aboneliğiniz iptal edildi.');
    });
  }

  void _showPlans() {
    final target = _plansKey.currentContext;
    if (target == null) return;
    Scrollable.ensureVisible(
      target,
      duration: FlowMotion.reduced(context) ? Duration.zero : FlowMotion.entrance,
      curve: FlowMotion.curve,
    );
  }

  @override
  Widget build(BuildContext context) {
    final overview = ref.watch(billingOverviewProvider);
    return overview.when(
      loading: () => const AppPage(children: [LoadingList(rows: 3)]),
      error: (_, __) => AppPage(children: [
        ErrorState(
          title: 'Abonelik bilgileri yüklenemedi',
          onRetry: () => ref.invalidate(billingOverviewProvider),
        ),
      ]),
      data: (data) => data == null ? const SizedBox.shrink() : _content(context, data),
    );
  }

  Widget _content(BuildContext context, BillingOverview data) {
    final theme = Theme.of(context);
    final c = FlowColors.of(context);
    final purchase = ref.watch(onlinePurchaseAllowedProvider);
    final online = data.plans.any((p) => p.onlineMonthly || p.onlineYearly);
    final period = data.hasOnlineSubscription ? (data.billingPeriod ?? 'monthly') : _period;
    final canPick = purchase && online && !data.hasOnlineSubscription;
    String? actionFor(BillingPlan plan) {
      if (!purchase || _busy || !plan.online(period)) return null;
      if (data.hasOnlineSubscription) return plan.key == data.planKey ? null : 'Bu plana geç';
      return 'Satın al';
    }

    final pickButton = canPick ? FilledButton(onPressed: _showPlans, child: const Text('Plan seç')) : null;

    return RefreshIndicator(
      onRefresh: () async {
        await _refreshPayment();
        ref.invalidate(billingOverviewProvider);
        await ref.read(billingOverviewProvider.future);
      },
      child: ScrollConfiguration(
        behavior: ScrollConfiguration.of(context).copyWith(
          physics: AlwaysScrollableScrollPhysics(parent: ScrollConfiguration.of(context).getScrollPhysics(context)),
        ),
        child: AppPage(gap: FlowSpace.xl - 4, children: [
          data.status == 'trialing'
              ? _TrialHero(overview: data, action: pickButton)
              : _StatusPanel(overview: data, action: pickButton),
          _UsagePanel(overview: data),
          Column(key: _plansKey, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Wrap(
              spacing: FlowSpace.md,
              runSpacing: FlowSpace.md,
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text('Planlar', style: theme.textTheme.headlineSmall),
                if (canPick)
                  SegmentedButton<String>(
                    showSelectedIcon: false,
                    segments: const [
                      ButtonSegment(value: 'monthly', label: Text('Aylık')),
                      ButtonSegment(value: 'yearly', label: Text('Yıllık')),
                    ],
                    selected: {_period},
                    onSelectionChanged: (value) => setState(() => _period = value.first),
                  ),
              ],
            ),
            const SizedBox(height: FlowSpace.md + 2),
            _Grid(minTileWidth: 280, children: [
              for (final plan in data.plans)
                _PlanCard(
                  plan: plan,
                  period: period,
                  current: plan.key == data.planKey,
                  trialing: data.status == 'trialing',
                  action: actionFor(plan),
                  onAction: () => data.hasOnlineSubscription ? _changePlan(plan) : _buy(data, plan),
                ),
            ]),
            const SizedBox(height: FlowSpace.md),
            Text(
              purchase && online
                  ? 'Fiyatlara KDV dahil değildir. Ödeme iyzico güvenli ödeme sayfasında alınır; '
                      'kart bilgileriniz Flow\'da saklanmaz.'
                  : 'Fiyatlara KDV dahil değildir.',
              style: theme.textTheme.bodySmall?.copyWith(color: c.faint),
            ),
            if (!purchase || !online) ...[
              const SizedBox(height: FlowSpace.sm),
              Text(
                AppLinks.supportEmail.isEmpty
                    ? 'Plan değişikliği için hesap yöneticinizle iletişime geçin.'
                    : 'Plan değişikliği için bize yazın: ${AppLinks.supportEmail}',
                style: theme.textTheme.bodySmall,
              ),
            ],
            if (data.hasOnlineSubscription) ...[
              const SizedBox(height: FlowSpace.md),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: _busy ? null : () => _cancel(data),
                  style: TextButton.styleFrom(foregroundColor: c.danger),
                  icon: const Icon(Icons.cancel_outlined, size: 18),
                  label: const Text('Aboneliği iptal et'),
                ),
              ),
            ],
          ]),
          _Grid(minTileWidth: 420, children: [
            _BillingProfilePanel(hasProfile: data.hasBillingProfile, onEdit: _openProfile),
            const EmptyState(
              compact: true,
              icon: Icons.receipt_long_outlined,
              title: 'Henüz fatura yok',
              message: 'İlk ödemenizden sonra faturalarınız burada listelenir.',
            ),
          ]),
        ]),
      ),
    );
  }
}

/// Label, detail and whether the status needs attention.
(String, String?, bool) statusTexts(BillingOverview overview, DateTime now) {
  switch (overview.status) {
    case 'pilot':
      return ('Pilot', 'Pilot programındasınız. Plan değişikliği için bizimle iletişime geçin.', false);
    case 'trialing':
      final end = overview.trialEndsAt;
      final days = trialDaysLeft(overview, now);
      return (
        'Deneme',
        end == null ? null : 'Deneme süreniz $days gün sonra (${formatDate(end)}) bitiyor.',
        days <= 3,
      );
    case 'active':
      final end = overview.currentPeriodEnd;
      return ('Aktif', end == null ? null : 'Sonraki yenileme: ${formatDate(end)}', false);
    case 'past_due':
      final end = overview.graceEndsAt ?? overview.currentPeriodEnd;
      return (
        'Ödeme alınamadı',
        end == null
            ? 'Kartınızı kontrol edin; iyzico ödemeyi yeniden deneyecek.'
            : 'Kartınızı kontrol edin; iyzico ödemeyi yeniden deneyecek. Hizmet ${formatDate(end)} tarihine kadar sürer.',
        true,
      );
    case 'canceled':
      final end = overview.currentPeriodEnd;
      return ('İptal edildi', end == null ? null : '${formatDate(end)} tarihine kadar kullanabilirsiniz.', true);
    default:
      return (
        'Süresi doldu',
        'Bot yanıtları ve kampanyalar durdu; gelen kutusu çalışmaya devam ediyor. Devam etmek için bir plan seçin.',
        true,
      );
  }
}

/// Whole days until the trial ends, rounded up; 0 once it has ended.
int trialDaysLeft(BillingOverview overview, DateTime now) {
  final end = overview.trialEndsAt;
  if (end == null) return 0;
  return (end.difference(now).inHours / 24).ceil().clamp(0, 999);
}

FlowTone _statusTone(String status) => switch (status) {
      'active' => FlowTone.accent,
      'trialing' || 'canceled' => FlowTone.warning,
      'pilot' => FlowTone.info,
      _ => FlowTone.danger,
    };

/// Trial: the days left in big mono numerals on a dot grid with signal rings.
class _TrialHero extends StatelessWidget {
  const _TrialHero({required this.overview, this.action});

  final BillingOverview overview;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final c = FlowColors.of(context);
    final days = trialDaysLeft(overview, DateTime.now());
    final urgent = days <= 3;
    final end = overview.trialEndsAt;

    final counter = Semantics(
      label: 'Denemenin bitmesine $days gün',
      excludeSemantics: true,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
        Text(upperTr('Denemenin bitmesine'), style: FlowText.caps(context)),
        const SizedBox(height: FlowSpace.sm),
        Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Text('$days', style: FlowText.number(context, size: 76, color: urgent ? c.warning : c.text)),
            const SizedBox(width: 6),
            Text('GÜN', style: FlowText.mono(context, size: 22, color: c.muted)),
          ],
        ),
      ]),
    );

    final details = Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Wrap(spacing: FlowSpace.sm, runSpacing: FlowSpace.xs, crossAxisAlignment: WrapCrossAlignment.center, children: [
        Text(overview.planName, style: theme.textTheme.headlineMedium),
        const StatusBadge('Deneme', tone: FlowTone.warning),
      ]),
      const SizedBox(height: FlowSpace.sm),
      ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: Text(
          '${end == null ? 'Deneme süreniz yakında bitiyor.' : 'Deneme süreniz ${formatDate(end)} tarihinde bitiyor.'} '
          'Plan seçmezseniz verileriniz saklanır ve gelen kutusu çalışmaya devam eder; '
          'asistan yanıtları ve kampanyalar durur.',
          style: theme.textTheme.bodyMedium?.copyWith(color: c.muted),
        ),
      ),
      if (action != null) ...[const SizedBox(height: FlowSpace.lg + 2), action!],
    ]);

    return Container(
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: FlowRadius.panelAll,
        border: Border.all(color: urgent ? c.warning : c.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: DotGrid(
        child: Stack(children: [
          // Smaller rings on phones so they stay clear of the counter.
          if (MediaQuery.sizeOf(context).width < 600)
            const Positioned(right: -120, top: -120, child: SignalRings(size: 240, rings: 3))
          else
            const Positioned(right: -110, top: -120, child: SignalRings(size: 420, rings: 3)),
          Padding(
            padding: const EdgeInsets.all(FlowSpace.xl + 4),
            child: LayoutBuilder(builder: (context, constraints) {
              if (constraints.maxWidth < 600) {
                return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  counter,
                  const SizedBox(height: FlowSpace.xl),
                  details,
                ]);
              }
              return Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
                counter,
                const SizedBox(width: FlowSpace.xl + 4),
                Expanded(child: details),
              ]);
            }),
          ),
        ]),
      ),
    );
  }
}

/// Every status other than the trial: plan, status badge and what applies now.
class _StatusPanel extends StatelessWidget {
  const _StatusPanel({required this.overview, this.action});

  final BillingOverview overview;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final c = FlowColors.of(context);
    final (label, detail, warning) = statusTexts(overview, DateTime.now());
    final tone = _statusTone(overview.status);
    return Container(
      padding: const EdgeInsets.all(FlowSpace.xl),
      decoration: BoxDecoration(
        color: warning ? c.toneFill(tone) : c.surface,
        borderRadius: FlowRadius.panelAll,
        border: Border.all(color: warning ? c.toneText(tone) : c.border),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(upperTr('Mevcut plan'), style: FlowText.caps(context)),
        const SizedBox(height: FlowSpace.sm),
        Wrap(spacing: FlowSpace.sm, runSpacing: FlowSpace.xs, crossAxisAlignment: WrapCrossAlignment.center, children: [
          Text(overview.planName, style: theme.textTheme.headlineMedium),
          StatusBadge(label, tone: tone),
        ]),
        if (detail != null) ...[
          const SizedBox(height: FlowSpace.sm),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: Text(detail, style: theme.textTheme.bodyMedium?.copyWith(color: warning ? c.text : c.muted)),
          ),
        ],
        if (action != null) ...[const SizedBox(height: FlowSpace.lg), action!],
      ]),
    );
  }
}

class _UsagePanel extends StatelessWidget {
  const _UsagePanel({required this.overview});

  final BillingOverview overview;

  @override
  Widget build(BuildContext context) {
    final limits = overview.limits;
    final usage = overview.usage;
    final replyLimit = limits.aiMonthlyTokens ~/ tokensPerReply;
    final repliesUsed = (usage.aiTokens / tokensPerReply).round();
    return SectionCard(
      title: 'Bu ayki kullanım',
      subtitle: 'Sınıra yaklaşan kalemler sarıya döner.',
      child: _Grid(minTileWidth: 300, gap: FlowSpace.xl - 4, children: [
        _meter('Kullanıcı', usage.seats, limits.seats),
        _meter('WhatsApp numarası', usage.whatsappNumbers, limits.whatsappNumbers),
        _meter('Asistan', usage.bots, limits.bots),
        UsageBar(
          label: 'Yapay zekâ yanıtı',
          value: _ratio(usage.aiTokens, limits.aiMonthlyTokens),
          valueLabel: limits.aiMonthlyTokens <= 0 ? 'Yok' : '~${formatCount(repliesUsed)} / ${formatCount(replyLimit)}',
        ),
        _meter('Kampanya mesajı', usage.campaignMessages, limits.campaignMessagesMonthly),
      ]),
    );
  }

  static double _ratio(int used, int limit) => limit <= 0 ? 1 : used / limit;

  static Widget _meter(String label, int used, int limit) => UsageBar(
        label: label,
        value: _ratio(used, limit),
        valueLabel: limit <= 0 ? 'Yok' : '${formatCount(used)} / ${formatCount(limit)}',
      );
}

class _PlanCard extends StatelessWidget {
  const _PlanCard({
    required this.plan,
    required this.period,
    required this.current,
    required this.trialing,
    this.action,
    this.onAction,
  });

  final BillingPlan plan;
  final String period;
  final bool current;
  final bool trialing;
  final String? action;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final c = FlowColors.of(context);
    final limits = plan.limits;
    final yearly = period == 'yearly' && plan.yearlyPrice != null;
    final price = yearly ? plan.yearlyPrice! : plan.monthlyPrice;
    final whole = price == price.roundToDouble();
    final other = yearly
        ? 'Aylık ödemede ${formatPrice(plan.monthlyPrice)} / ay'
        : plan.yearlyPrice == null
            ? 'Yalnızca aylık ödeme'
            : 'Yıllık ödemede ${formatPrice(plan.yearlyPrice!)} / yıl';
    final saving = plan.yearlyPrice == null ? 0 : plan.monthlyPrice * 12 - plan.yearlyPrice!;
    final summary = [
      '${formatCount(limits.seats)} kullanıcı',
      '${formatCount(limits.whatsappNumbers)} numara',
      '${formatCount(limits.bots)} asistan',
      'ayda ~${formatCount(limits.aiMonthlyTokens ~/ tokensPerReply)} yapay zekâ yanıtı',
      '${formatCount(limits.campaignMessagesMonthly)} kampanya mesajı',
    ].join(' · ');

    return Container(
      padding: const EdgeInsets.all(FlowSpace.xl - 2),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: FlowRadius.cardAll,
        // Lime is a fill only in light mode; its outline there is olive.
        border: Border.all(color: current ? (c.isDark ? c.lime : c.accentText) : c.border, width: current ? 1.5 : 1),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Wrap(spacing: FlowSpace.sm, runSpacing: FlowSpace.xs, crossAxisAlignment: WrapCrossAlignment.center, children: [
          Text(plan.name, style: theme.textTheme.titleLarge),
          if (current) StatusBadge(trialing ? 'Denemedesiniz' : 'Mevcut plan', tone: FlowTone.accent),
        ]),
        const SizedBox(height: FlowSpace.md + 2),
        Wrap(crossAxisAlignment: WrapCrossAlignment.end, spacing: 6, children: [
          // Whole lira: big digits, "₺ / ay" small beside them (the ₺ falls back to Bricolage).
          Text(whole ? formatCount(price) : formatPrice(price), style: FlowText.number(context, size: 36)),
          Padding(
            padding: const EdgeInsets.only(bottom: 3),
            child: Text('${whole ? '₺ ' : ''}${yearly ? '/ yıl' : '/ ay'}', style: FlowText.mono(context, size: 13)),
          ),
        ]),
        const SizedBox(height: 6),
        Text(other, style: FlowText.mono(context, size: 12)),
        if (yearly && saving > 0) ...[
          const SizedBox(height: FlowSpace.xs),
          Text('Yıllıkta ${formatPrice(saving)} tasarruf',
              style: FlowText.mono(context, size: 12, color: c.accentText, weight: FontWeight.w500)),
        ],
        const SizedBox(height: FlowSpace.md + 2),
        if (plan.description.isNotEmpty) ...[
          Text(plan.description, style: theme.textTheme.bodyMedium),
          const SizedBox(height: 6),
        ],
        Text(summary, style: theme.textTheme.bodySmall),
        if (action != null) ...[
          const SizedBox(height: FlowSpace.lg),
          OutlinedButton(onPressed: onAction, child: Text(action!)),
        ],
      ]),
    );
  }
}

class _BillingProfilePanel extends StatelessWidget {
  const _BillingProfilePanel({required this.hasProfile, required this.onEdit});

  final bool hasProfile;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final c = FlowColors.of(context);
    final button = OutlinedButton(
      onPressed: onEdit,
      child: Text(hasProfile ? 'Bilgileri düzenle' : 'Bilgileri ekle'),
    );
    return SectionCard(
      title: 'Fatura bilgileri',
      child: hasProfile
          ? Wrap(
              spacing: FlowSpace.md,
              runSpacing: FlowSpace.md,
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.check_circle_outline, size: 20, color: c.accentText),
                  const SizedBox(width: FlowSpace.sm),
                  Flexible(child: Text('Kayıtlı. Faturalarınızda bu bilgiler kullanılır.', style: theme.textTheme.bodyMedium)),
                ]),
                button,
              ],
            )
          : Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: c.warningSoft,
                borderRadius: FlowRadius.controlAll,
                border: Border.all(color: c.warning),
              ),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Icon(Icons.error_outline, size: 20, color: c.warning),
                  const SizedBox(width: FlowSpace.md),
                  Expanded(
                    child: Text(
                      'Ödeme yapabilmek için vergi ya da T.C. kimlik numarası ve fatura adresi gerekli.',
                      style: theme.textTheme.bodyMedium,
                    ),
                  ),
                ]),
                const SizedBox(height: FlowSpace.md),
                button,
              ]),
            ),
    );
  }
}

/// Equal-width columns that fit [minTileWidth]; one column on phones.
class _Grid extends StatelessWidget {
  const _Grid({required this.minTileWidth, required this.children, this.gap = FlowSpace.md});

  final double minTileWidth;
  final double gap;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) {
      final columns = ((constraints.maxWidth + gap) / (minTileWidth + gap)).floor().clamp(1, children.length);
      if (columns == 1) {
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          for (var i = 0; i < children.length; i++) ...[if (i > 0) SizedBox(height: gap), children[i]],
        ]);
      }
      // Rows share the tallest tile's height so card borders line up.
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        for (var start = 0; start < children.length; start += columns) ...[
          if (start > 0) SizedBox(height: gap),
          IntrinsicHeight(
            child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              for (var i = start; i < start + columns; i++) ...[
                if (i > start) SizedBox(width: gap),
                Expanded(child: i < children.length ? children[i] : const SizedBox.shrink()),
              ],
            ]),
          ),
        ],
      ]);
    });
  }
}
