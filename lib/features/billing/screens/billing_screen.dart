import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../config/app_links.dart';
import '../models/billing_overview.dart';
import '../providers/billing_providers.dart';

/// Whether this build may link to the web plan page (never on iOS).
final billingLinkAllowedProvider = Provider<bool>(
  (ref) => AppLinks.billingUrl.isNotEmpty && defaultTargetPlatform != TargetPlatform.iOS,
);

/// "Abonelik" (administrators): the plan and its status, this month's usage against
/// the limits, and the plans available.
class BillingScreen extends ConsumerWidget {
  const BillingScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
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
      data: (data) => data == null
          ? const SizedBox.shrink()
          : RefreshIndicator(
              onRefresh: () async {
                ref.invalidate(billingOverviewProvider);
                await ref.read(billingOverviewProvider.future);
              },
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  Text('Abonelik', style: Theme.of(context).textTheme.titleLarge),
                  const SizedBox(height: 12),
                  _StatusCard(overview: data),
                  const SizedBox(height: 16),
                  Text('Bu ayki kullanım', style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 8),
                  _UsageCard(overview: data),
                  const SizedBox(height: 24),
                  Text('Planlar', style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 4),
                  Text('Fiyatlar KDV hariçtir.', style: Theme.of(context).textTheme.bodySmall),
                  const SizedBox(height: 8),
                  for (final plan in data.plans) _PlanCard(plan: plan, current: plan.key == data.planKey),
                  const SizedBox(height: 8),
                  const _ChangePlan(),
                ],
              ),
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
            ? 'Ödeme bilgilerinizi güncelleyin.'
            : 'Ödeme bilgilerinizi güncelleyin; hizmet ${formatDate(end)} tarihine kadar sürer.',
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
  const _PlanCard({required this.plan, required this.current});

  final BillingPlan plan;
  final bool current;

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
        ]),
      ),
    );
  }
}

class _ChangePlan extends ConsumerWidget {
  const _ChangePlan();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (ref.watch(billingLinkAllowedProvider)) {
      return FilledButton.icon(
        onPressed: () => launchUrl(Uri.parse(AppLinks.billingUrl), mode: LaunchMode.externalApplication),
        icon: const Icon(Icons.open_in_new),
        label: const Text('Planı değiştir'),
      );
    }
    const email = AppLinks.supportEmail;
    return Text(
      email.isEmpty
          ? 'Plan değişikliği için hesap yöneticinizle iletişime geçin.'
          : 'Plan değişikliği için bize yazın: $email',
      style: Theme.of(context).textTheme.bodySmall,
    );
  }
}
