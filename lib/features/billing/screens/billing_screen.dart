import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../config/app_links.dart';
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

  void _say(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
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
      if (!quiet) _say(billingErrorMessage(error));
    }
  }

  Future<bool?> _editProfile(BillingProfile? initial) => showModalBottomSheet<bool>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        builder: (_) => BillingProfileSheet(initial: initial),
      );

  Future<void> _run(Future<void> Function() action) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
    } catch (error) {
      _say(billingErrorMessage(error));
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
    final confirmed = await _confirm('Plan değiştirilsin mi?',
        '${plan.name} planına hemen geçilir. Ücret farkını iyzico kayıtlı kartınızdan tahsil eder.', 'Planı değiştir');
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
    final confirmed = await _confirm(
      'Abonelik iptal edilsin mi?',
      'Yeni ödeme alınmaz. $until kadar planınızı kullanmaya devam edersiniz.',
      'İptal et',
    );
    if (!confirmed) return;
    await _run(() async {
      await ref.read(billingRepositoryProvider).cancel(tenant.id);
      _say('Aboneliğiniz iptal edildi.');
    });
  }

  Future<bool> _confirm(String title, String text, String action) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(text),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Vazgeç')),
          FilledButton(onPressed: () => Navigator.of(context).pop(true), child: Text(action)),
        ],
      ),
    );
    return result == true;
  }

  @override
  Widget build(BuildContext context) {
    final overview = ref.watch(billingOverviewProvider);
    return overview.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (_, __) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Text('Abonelik bilgileri yüklenemedi. Bağlantınızı kontrol edip tekrar deneyin.',
                textAlign: TextAlign.center),
            const SizedBox(height: 12),
            OutlinedButton(
              onPressed: () => ref.invalidate(billingOverviewProvider),
              child: const Text('Tekrar dene'),
            ),
          ]),
        ),
      ),
      data: (data) => data == null ? const SizedBox.shrink() : _content(context, data),
    );
  }

  Widget _content(BuildContext context, BillingOverview data) {
    final theme = Theme.of(context);
    final purchase = ref.watch(onlinePurchaseAllowedProvider);
    final online = data.plans.any((p) => p.onlineMonthly || p.onlineYearly);
    final period = data.hasOnlineSubscription ? (data.billingPeriod ?? 'monthly') : _period;
    String? actionFor(BillingPlan plan) {
      if (!purchase || _busy || !plan.online(period)) return null;
      if (data.hasOnlineSubscription) return plan.key == data.planKey ? null : 'Bu plana geç';
      return 'Satın al';
    }

    return RefreshIndicator(
      onRefresh: () async {
        await _refreshPayment();
        ref.invalidate(billingOverviewProvider);
        await ref.read(billingOverviewProvider.future);
      },
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text('Abonelik', style: theme.textTheme.titleLarge),
          const SizedBox(height: 12),
          _StatusCard(overview: data),
          const SizedBox(height: 16),
          Text('Bu ayki kullanım', style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          _UsageCard(overview: data),
          const SizedBox(height: 16),
          Card(
            elevation: 0,
            child: ListTile(
              leading: const Icon(Icons.receipt_long_outlined),
              title: const Text('Fatura bilgileri'),
              subtitle: Text(data.hasBillingProfile ? 'Kayıtlı' : 'Eksik: online ödeme için gerekli'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () async {
                BillingProfile? profile;
                try {
                  profile = await ref.read(billingProfileProvider.future);
                } catch (_) {
                  profile = null;
                }
                if (!mounted) return;
                if (await _editProfile(profile) == true) _say('Fatura bilgileri kaydedildi.');
              },
            ),
          ),
          const SizedBox(height: 24),
          Text('Planlar', style: theme.textTheme.titleMedium),
          const SizedBox(height: 4),
          Text('Fiyatlar KDV hariçtir.', style: theme.textTheme.bodySmall),
          if (purchase && online && !data.hasOnlineSubscription) ...[
            const SizedBox(height: 8),
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'monthly', label: Text('Aylık')),
                ButtonSegment(value: 'yearly', label: Text('Yıllık')),
              ],
              selected: {_period},
              onSelectionChanged: (value) => setState(() => _period = value.first),
            ),
          ],
          const SizedBox(height: 8),
          for (final plan in data.plans)
            _PlanCard(
              plan: plan,
              current: plan.key == data.planKey,
              action: actionFor(plan),
              onAction: () => data.hasOnlineSubscription ? _changePlan(plan) : _buy(data, plan),
            ),
          if (data.hasOnlineSubscription) ...[
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: _busy ? null : () => _cancel(data),
              icon: const Icon(Icons.cancel_outlined),
              label: const Text('Aboneliği iptal et'),
            ),
          ],
          if (!purchase || !online) ...[
            const SizedBox(height: 8),
            Text(
              AppLinks.supportEmail.isEmpty
                  ? 'Plan değişikliği için hesap yöneticinizle iletişime geçin.'
                  : 'Plan değişikliği için bize yazın: ${AppLinks.supportEmail}',
              style: theme.textTheme.bodySmall,
            ),
          ],
        ],
      ),
    );
  }
}

class _StatusCard extends StatelessWidget {
  const _StatusCard({required this.overview});

  final BillingOverview overview;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final (label, detail, warning) = statusTexts(overview, DateTime.now());
    return Card(
      elevation: 0,
      color: warning ? theme.colorScheme.errorContainer : null,
      child: ListTile(
        leading: Icon(warning ? Icons.warning_amber_outlined : Icons.workspace_premium_outlined),
        title: Text('${overview.planName} · $label'),
        subtitle: detail == null ? null : Text(detail),
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
      final days = end == null ? 0 : (end.difference(now).inHours / 24).ceil().clamp(0, 999);
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

class _UsageCard extends StatelessWidget {
  const _UsageCard({required this.overview});

  final BillingOverview overview;

  @override
  Widget build(BuildContext context) {
    final limits = overview.limits;
    final usage = overview.usage;
    return Card(
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(children: [
          UsageMeter(label: 'Kullanıcılar', used: usage.seats, limit: limits.seats),
          UsageMeter(label: 'WhatsApp numaraları', used: usage.whatsappNumbers, limit: limits.whatsappNumbers),
          UsageMeter(label: 'Botlar', used: usage.bots, limit: limits.bots),
          UsageMeter(
            label: 'AI yanıtları',
            used: usage.aiTokens,
            limit: limits.aiMonthlyTokens,
            text: limits.aiMonthlyTokens == 0
                ? 'Yok'
                : '%${(usage.aiTokens * 100 / limits.aiMonthlyTokens).clamp(0, 100).round()} · aylık yaklaşık '
                    '${formatCount(limits.aiMonthlyTokens ~/ tokensPerReply)} yanıt',
          ),
          UsageMeter(
            label: 'Kampanya mesajları',
            used: usage.campaignMessages,
            limit: limits.campaignMessagesMonthly,
          ),
        ]),
      ),
    );
  }
}

class UsageMeter extends StatelessWidget {
  const UsageMeter({super.key, required this.label, required this.used, required this.limit, this.text});

  final String label;
  final int used;
  final int limit;
  final String? text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final ratio = limit <= 0 ? 1.0 : (used / limit).clamp(0.0, 1.0);
    final full = limit <= 0 || used >= limit;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Expanded(child: Text(label, style: theme.textTheme.bodyMedium)),
          Flexible(
            child: Text(
              text ?? (limit <= 0 ? 'Yok' : '${formatCount(used)} / ${formatCount(limit)}'),
              textAlign: TextAlign.end,
              style: theme.textTheme.bodySmall?.copyWith(color: full ? theme.colorScheme.error : null),
            ),
          ),
        ]),
        const SizedBox(height: 4),
        LinearProgressIndicator(
          value: ratio,
          color: full ? theme.colorScheme.error : null,
          semanticsLabel: label,
        ),
      ]),
    );
  }
}

class _PlanCard extends StatelessWidget {
  const _PlanCard({required this.plan, required this.current, this.action, this.onAction});

  final BillingPlan plan;
  final bool current;
  final String? action;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final limits = plan.limits;
    return Card(
      elevation: 0,
      shape: current
          ? RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: BorderSide(color: theme.colorScheme.primary, width: 2),
            )
          : null,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Wrap(spacing: 8, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
            Text(plan.name, style: theme.textTheme.titleMedium),
            if (current) const Chip(label: Text('Mevcut plan'), visualDensity: VisualDensity.compact),
          ]),
          const SizedBox(height: 4),
          Text('${formatPrice(plan.monthlyPrice)} / ay'
              '${plan.yearlyPrice == null ? '' : ' veya ${formatPrice(plan.yearlyPrice!)} / yıl'}'),
          if (plan.description.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(plan.description, style: theme.textTheme.bodySmall),
          ],
          const SizedBox(height: 8),
          for (final line in [
            '${limits.seats} kullanıcı',
            '${limits.whatsappNumbers} WhatsApp numarası',
            '${limits.bots} bot',
            'Aylık yaklaşık ${formatCount(limits.aiMonthlyTokens ~/ tokensPerReply)} AI yanıtı',
            'Aylık ${formatCount(limits.campaignMessagesMonthly)} kampanya mesajı',
          ])
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Icon(Icons.check, size: 16),
                const SizedBox(width: 6),
                Expanded(child: Text(line)),
              ]),
            ),
          if (action != null) ...[
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: FilledButton(onPressed: onAction, child: Text(action!)),
            ),
          ],
        ]),
      ),
    );
  }
}
