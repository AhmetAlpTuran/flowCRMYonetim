import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../ui/ui.dart';
import '../../templates/widgets/inline_notice.dart';
import '../models/campaign.dart';
import '../providers/campaign_providers.dart';

/// Plain description of a campaign or recipient state, for detail views.
String campaignStatusLabel(String status) =>
    const {
      'draft': 'Taslak',
      'scheduled': 'Planlandı',
      'queued': 'Kuyrukta',
      'running': 'İşleniyor',
      'completed': 'Gönderim işlemi tamamlandı',
      'partial': 'Kısmen tamamlandı',
      'failed': 'Başarısız',
      'needs_attention': 'İnceleme gerekiyor',
      'cancelled': 'İptal edildi',
      'unknown': 'Sonuç doğrulanamadı',
      'blocked': 'Bağlantı bekleniyor',
      'delivery_failed': 'Teslim edilemedi',
    }[status] ??
    'Durum bilgisi bekleniyor';

/// Short badge label and tone for a campaign or recipient state.
(String, FlowTone) campaignStatusBadge(String status) => switch (status) {
      'draft' => ('Taslak', FlowTone.neutral),
      'scheduled' => ('Planlandı', FlowTone.info),
      'queued' => ('Sırada', FlowTone.info),
      'running' => ('Gönderiliyor', FlowTone.info),
      'completed' => ('Tamamlandı', FlowTone.accent),
      'partial' => ('Kısmen tamamlandı', FlowTone.warning),
      'failed' => ('Başarısız', FlowTone.danger),
      'needs_attention' => ('İnceleme gerekiyor', FlowTone.warning),
      'cancelled' => ('İptal edildi', FlowTone.neutral),
      'unknown' => ('Doğrulanamadı', FlowTone.warning),
      'blocked' => ('Bağlantı bekleniyor', FlowTone.warning),
      'delivery_failed' => ('Teslim edilemedi', FlowTone.danger),
      _ => ('Bekleniyor', FlowTone.neutral),
    };

class CampaignStatusBadge extends StatelessWidget {
  const CampaignStatusBadge(this.status, {super.key});

  final String status;

  @override
  Widget build(BuildContext context) {
    final (label, tone) = campaignStatusBadge(status);
    return StatusBadge(label, tone: tone);
  }
}

/// Saved drafts and sent campaigns, 20 per page, refreshed only on request.
class CampaignHistory extends ConsumerStatefulWidget {
  const CampaignHistory(
      {super.key, required this.tenantId, required this.onOpen});
  final String tenantId;
  final ValueChanged<CampaignDraft>? onOpen;
  @override
  ConsumerState<CampaignHistory> createState() => _CampaignHistoryState();
}

class _CampaignHistoryState extends ConsumerState<CampaignHistory> {
  int _page = 0;

  void _refresh(CampaignPage key) {
    ref.invalidate(campaignHistoryProvider(key));
    ref.invalidate(campaignProgressProvider);
  }

  @override
  Widget build(BuildContext context) {
    final key = (tenantId: widget.tenantId, page: _page);
    final history = ref.watch(campaignHistoryProvider(key));
    final c = FlowColors.of(context);
    final theme = Theme.of(context);
    return SectionCard(
      title: 'Son kampanyalar',
      subtitle: 'Taslakları açıp düzenleyin, gönderilenlerin sonucunu inceleyin.',
      flush: true,
      trailing: TextButton.icon(
          onPressed: () => _refresh(key),
          icon: const Icon(Icons.refresh, size: 18),
          label: const Text('Yenile')),
      child: history.when(
          loading: () => const Padding(
              padding: EdgeInsets.symmetric(horizontal: 20, vertical: 8),
              child: LoadingList(rows: 3)),
          error: (_, __) => Padding(
              padding: const EdgeInsets.all(20),
              child: InlineNotice(
                  'Kampanya geçmişi yüklenemedi. Bağlantınızı kontrol edip yenileyin.',
                  tone: FlowTone.danger,
                  action: OutlinedButton.icon(
                      onPressed: () => _refresh(key),
                      icon: const Icon(Icons.refresh, size: 18),
                      label: const Text('Tekrar dene')))),
          data: (rows) => LayoutBuilder(builder: (context, constraints) {
                final table = constraints.maxWidth >= 720;
                return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (rows.isEmpty)
                        Padding(
                            padding: const EdgeInsets.fromLTRB(20, 24, 20, 8),
                            child: Column(children: [
                              Text(
                                  _page == 0
                                      ? 'Henüz kampanya yok'
                                      : 'Bu sayfada kampanya bulunamadı',
                                  style: theme.textTheme.titleMedium,
                                  textAlign: TextAlign.center),
                              if (_page == 0) ...[
                                const SizedBox(height: 4),
                                Text(
                                    'Yukarıdaki formdan ilk taslağınızı kaydedin.',
                                    style: theme.textTheme.bodySmall,
                                    textAlign: TextAlign.center),
                              ],
                            ])),
                      if (rows.isNotEmpty && table) const _TableHeader(),
                      for (var i = 0; i < rows.length; i++)
                        DecoratedBox(
                          decoration: BoxDecoration(
                              border: i == 0 && !table
                                  ? null
                                  : Border(top: BorderSide(color: c.border))),
                          child: _HistoryRow(
                              tenantId: widget.tenantId,
                              row: rows[i],
                              table: table,
                              onOpen: widget.onOpen),
                        ),
                      Container(
                        decoration: BoxDecoration(
                            border: Border(top: BorderSide(color: c.border))),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 4),
                        child: _PageControls(
                            page: _page,
                            hasMore: rows.length == 20,
                            onPage: (value) => setState(() => _page = value)),
                      ),
                    ]);
              })),
    );
  }
}

const _countWidth = 112.0;
const _readWidth = 84.0;
const _actionWidth = 180.0;

class _TableHeader extends StatelessWidget {
  const _TableHeader();

  @override
  Widget build(BuildContext context) {
    final style = FlowText.caps(context, size: 11);
    return ExcludeSemantics(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 4, 12, 10),
        child: Row(children: [
          Expanded(flex: 3, child: Text('KAMPANYA', style: style)),
          const SizedBox(width: FlowSpace.md),
          Expanded(flex: 2, child: Text('DURUM', style: style)),
          SizedBox(
              width: _countWidth,
              child: Text('İLETİLDİ', style: style, textAlign: TextAlign.right)),
          SizedBox(
              width: _readWidth,
              child: Text('OKUNDU', style: style, textAlign: TextAlign.right)),
          const SizedBox(width: _actionWidth),
        ]),
      ),
    );
  }
}

class _HistoryRow extends ConsumerWidget {
  const _HistoryRow(
      {required this.tenantId,
      required this.row,
      required this.table,
      required this.onOpen});

  final String tenantId;
  final CampaignDraft row;
  final bool table;
  final ValueChanged<CampaignDraft>? onOpen;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = FlowColors.of(context);
    final theme = Theme.of(context);
    // Drafts have no recipients yet; sent campaigns read their queue counters.
    final progress = row.editable
        ? null
        : ref
            .watch(campaignProgressProvider((tenantId: tenantId, id: row.id)))
            .valueOrNull;
    final counted = progress != null && !progress.legacy;
    final status = counted ? progress.status : row.status;
    final delivered = counted
        ? '${formatCount(progress.count('delivered'))} / ${formatCount(progress.count('total'))}'
        : '—';
    final read = counted ? formatCount(progress.count('read')) : '—';
    final valueStyle =
        FlowText.mono(context, size: 14, color: counted ? c.text : c.faint);

    final name = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(row.name,
              style: theme.textTheme.titleSmall,
              maxLines: 2,
              overflow: TextOverflow.ellipsis),
          if (row.queuedAt != null) ...[
            const SizedBox(height: 2),
            Text(formatDateTime(row.queuedAt!),
                style: FlowText.mono(context, size: 12)),
          ],
        ]);
    final action = row.editable
        ? TextButton(
            onPressed: onOpen == null ? null : () => onOpen!(row),
            child: const Text('Taslağı aç'))
        : TextButton(
            onPressed: () => showDialog<void>(
                context: context,
                builder: (context) => AlertDialog(
                        title: Text(row.name),
                        scrollable: true,
                        content: SizedBox(
                            width: 620,
                            child: CampaignProgressPanel(
                                tenantId: tenantId, campaignId: row.id)),
                        actions: [
                          TextButton(
                              onPressed: () => Navigator.pop(context),
                              child: const Text('Kapat'))
                        ])),
            child: const Text('Gönderim durumu'));

    if (table) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(20, 10, 12, 10),
        child: Row(children: [
          Expanded(flex: 3, child: name),
          const SizedBox(width: FlowSpace.md),
          Expanded(
              flex: 2,
              child: Align(
                  alignment: Alignment.centerLeft,
                  child: CampaignStatusBadge(status))),
          SizedBox(
              width: _countWidth,
              child: Text(delivered,
                  style: valueStyle, textAlign: TextAlign.right)),
          SizedBox(
              width: _readWidth,
              child: Text(read, style: valueStyle, textAlign: TextAlign.right)),
          SizedBox(
              width: _actionWidth,
              child: Align(alignment: Alignment.centerRight, child: action)),
        ]),
      );
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 14, 12, 6),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(child: name),
          const SizedBox(width: FlowSpace.sm),
          Padding(
              padding: const EdgeInsets.only(right: 8),
              child: CampaignStatusBadge(status)),
        ]),
        if (counted) ...[
          const SizedBox(height: FlowSpace.sm),
          Wrap(spacing: FlowSpace.lg, runSpacing: FlowSpace.xs, children: [
            _InlineCount(label: 'İletildi', value: delivered),
            _InlineCount(label: 'Okundu', value: read),
          ]),
        ],
        action,
      ]),
    );
  }
}

class _InlineCount extends StatelessWidget {
  const _InlineCount({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Semantics(
        label: '$label: $value',
        excludeSemantics: true,
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Text(upperTr(label), style: FlowText.caps(context, size: 10)),
          const SizedBox(width: 6),
          Text(value,
              style: FlowText.mono(context,
                  size: 13, color: FlowColors.of(context).text)),
        ]),
      );
}

/// A sent campaign's queue counters and the recipients that need review.
class CampaignProgressPanel extends ConsumerStatefulWidget {
  const CampaignProgressPanel(
      {super.key, required this.tenantId, required this.campaignId});
  final String tenantId, campaignId;
  @override
  ConsumerState<CampaignProgressPanel> createState() =>
      _CampaignProgressPanelState();
}

class _CampaignProgressPanelState extends ConsumerState<CampaignProgressPanel> {
  int _page = 0;

  static const _primary = {
    'total': 'Alıcı',
    'accepted': 'API kabulü',
    'delivered': 'Teslim edildi',
    'read': 'Okundu',
  };
  static const _secondary = {
    'queued': 'Kuyrukta',
    'leased': 'Hazırlanıyor',
    'sending': 'Gönderiliyor',
    'retry_wait': 'Tekrar bekliyor',
    'blocked': 'Bağlantı bekliyor',
    'failed': 'Başarısız',
    'unknown': 'Doğrulanamadı',
    'cancelled': 'İptal',
    'delivery_failed': 'Teslim edilemedi',
  };
  static const _problemTones = {
    'blocked': FlowTone.warning,
    'failed': FlowTone.danger,
    'unknown': FlowTone.warning,
    'delivery_failed': FlowTone.danger,
  };

  @override
  void didUpdateWidget(covariant CampaignProgressPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.campaignId != widget.campaignId ||
        oldWidget.tenantId != widget.tenantId) {
      _page = 0;
    }
  }

  @override
  Widget build(BuildContext context) {
    final key = (tenantId: widget.tenantId, id: widget.campaignId);
    final progress = ref.watch(campaignProgressProvider(key));
    final failureKey =
        (tenantId: widget.tenantId, id: widget.campaignId, page: _page);
    final failures = ref.watch(campaignFailuresProvider(failureKey));
    final theme = Theme.of(context);
    final c = FlowColors.of(context);
    final data = progress.valueOrNull;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Row(children: [
        Expanded(
          child: Wrap(
              spacing: FlowSpace.sm,
              runSpacing: FlowSpace.xs,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text('Gönderim durumu', style: theme.textTheme.titleMedium),
                if (data != null && !data.legacy)
                  CampaignStatusBadge(data.status),
              ]),
        ),
        TextButton.icon(
            onPressed: () {
              ref.invalidate(campaignProgressProvider(key));
              ref.invalidate(campaignFailuresProvider(failureKey));
            },
            icon: const Icon(Icons.refresh, size: 18),
            label: const Text('Yenile')),
      ]),
      const SizedBox(height: FlowSpace.sm),
      progress.when(
          loading: () => const LinearProgressIndicator(
              semanticsLabel: 'Gönderim durumu yükleniyor'),
          error: (_, __) => const InlineNotice(
              'Güncel durum alınamadı. Yenileyin; kampanyayı yeniden oluşturmayın.',
              tone: FlowTone.danger),
          data: (data) => data.legacy
              ? const InlineNotice(
                  'Bu kampanya eski gönderim sistemiyle oluşturuldu. Yeni kuyruk sayaçları geçmiş teslimatları göstermez.')
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                      Text(campaignStatusLabel(data.status),
                          style: theme.textTheme.bodyMedium
                              ?.copyWith(color: c.muted)),
                      const SizedBox(height: FlowSpace.md),
                      LayoutBuilder(builder: (context, constraints) {
                        final columns = constraints.maxWidth >= 480 ? 4 : 2;
                        final width = (constraints.maxWidth -
                                (columns - 1) * FlowSpace.sm) /
                            columns;
                        return Wrap(
                            spacing: FlowSpace.sm,
                            runSpacing: FlowSpace.sm,
                            children: [
                              for (final metric in _primary.entries)
                                SizedBox(
                                    width: width,
                                    child: _MetricTile(
                                        label: metric.value,
                                        value: data.count(metric.key))),
                            ]);
                      }),
                      const SizedBox(height: FlowSpace.sm),
                      Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          children: [
                            for (final metric in _secondary.entries)
                              _MetricPill(
                                  label: metric.value,
                                  value: data.count(metric.key),
                                  tone: _problemTones[metric.key]),
                          ]),
                      const SizedBox(height: FlowSpace.sm),
                      const CheckLine(
                          'API kabulü teslimat onayı değildir. Doğrulanamayan mesajlar otomatik tekrar gönderilmez.',
                          note: true),
                    ])),
      const SizedBox(height: FlowSpace.lg),
      Text('İncelenecek alıcılar', style: theme.textTheme.titleSmall),
      const SizedBox(height: FlowSpace.xs),
      failures.when(
          loading: () => const LinearProgressIndicator(
              semanticsLabel: 'Alıcı sonuçları yükleniyor'),
          error: (_, __) => const InlineNotice(
              'Alıcı sonuçları yüklenemedi. Yenileyerek tekrar deneyin.',
              tone: FlowTone.danger),
          data: (rows) => Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (rows.isEmpty)
                      Text('Bu sayfada hata veya belirsiz sonuç yok.',
                          style: theme.textTheme.bodySmall),
                    for (final row in rows) _FailureRow(row: row),
                    _PageControls(
                        page: _page,
                        hasMore: rows.length == 20,
                        onPage: (value) => setState(() => _page = value)),
                  ])),
    ]);
  }
}

class _MetricTile extends StatelessWidget {
  const _MetricTile({required this.label, required this.value});

  final String label;
  final int value;

  @override
  Widget build(BuildContext context) {
    final c = FlowColors.of(context);
    return Semantics(
      label: '$label: $value',
      excludeSemantics: true,
      child: Container(
        padding: const EdgeInsets.all(FlowSpace.md),
        decoration: BoxDecoration(
          color: c.canvas,
          borderRadius: FlowRadius.controlAll,
          border: Border.all(color: c.border),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(upperTr(label),
              style: FlowText.caps(context, size: 10),
              maxLines: 1,
              overflow: TextOverflow.ellipsis),
          const SizedBox(height: FlowSpace.sm),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(formatCount(value),
                style: FlowText.number(context, size: 28)),
          ),
        ]),
      ),
    );
  }
}

class _MetricPill extends StatelessWidget {
  const _MetricPill({required this.label, required this.value, this.tone});

  final String label;
  final int value;
  final FlowTone? tone;

  @override
  Widget build(BuildContext context) {
    final c = FlowColors.of(context);
    final active = tone != null && value > 0;
    final color = active ? c.toneText(tone!) : c.muted;
    return Semantics(
      label: '$label: $value',
      excludeSemantics: true,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: active ? c.toneFill(tone!) : null,
          borderRadius: BorderRadius.circular(FlowRadius.pill),
          border: active ? null : Border.all(color: c.border),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Text(label,
              style: Theme.of(context)
                  .textTheme
                  .labelSmall
                  ?.copyWith(color: color)),
          const SizedBox(width: 6),
          Text(formatCount(value),
              style: FlowText.mono(context,
                  size: 12, color: active ? color : c.text)),
        ]),
      ),
    );
  }
}

class _FailureRow extends StatelessWidget {
  const _FailureRow({required this.row});

  final Map<String, dynamic> row;

  @override
  Widget build(BuildContext context) {
    final c = FlowColors.of(context);
    final deliveryFailed = row['delivery_status'] == 'failed';
    final state = deliveryFailed ? 'delivery_failed' : row['state'] as String;
    final phone = row['recipient_phone'] as String? ?? '';
    return Container(
      padding: const EdgeInsets.symmetric(vertical: FlowSpace.md),
      decoration:
          BoxDecoration(border: Border(bottom: BorderSide(color: c.border))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Wrap(
            spacing: FlowSpace.sm,
            runSpacing: FlowSpace.xs,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              SelectableText(formatPhone(phone),
                  style: FlowText.mono(context, size: 14, color: c.text)),
              CampaignStatusBadge(state),
            ]),
        const SizedBox(height: FlowSpace.xs),
        Text(
            _failureMessage((deliveryFailed
                ? row['delivery_error_code']
                : row['error_code']) as String?),
            style: Theme.of(context).textTheme.bodyMedium),
        const SizedBox(height: 2),
        Text('Deneme: ${row['attempts'] ?? 0}',
            style: FlowText.mono(context, size: 12)),
      ]),
    );
  }

  String _failureMessage(String? code) {
    if (code == 'invalid_phone') {
      return 'Telefon numarası uluslararası biçimde olmalı.';
    }
    if (code?.contains('unknown') == true) {
      return 'Mesaj gönderilmiş olabilir. Teslimat kaydını incelemeden tekrar göndermeyin.';
    }
    if (code?.contains('connection') == true || code == 'meta_190') {
      return 'İşletmenin WhatsApp bağlantısını kontrol edin.';
    }
    if (code == 'meta_100') {
      return 'WhatsApp şablon parametrelerini reddetti. Şablonu eşitleyip gönderim değerlerini kontrol edin.';
    }
    if (code == 'meta_130429' || code == 'meta_131056') {
      return 'WhatsApp gönderim sınırına ulaşıldı.';
    }
    return code == null
        ? 'Alıcı durumunu inceleyin.'
        : 'Gönderim tamamlanamadı. Destek için kod: $code';
  }
}

class _PageControls extends StatelessWidget {
  const _PageControls(
      {required this.page, required this.hasMore, required this.onPage});
  final int page;
  final bool hasMore;
  final ValueChanged<int> onPage;
  @override
  Widget build(BuildContext context) => Wrap(
          spacing: FlowSpace.sm,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            TextButton.icon(
                onPressed: page > 0 ? () => onPage(page - 1) : null,
                icon: const Icon(Icons.chevron_left, size: 18),
                label: const Text('Önceki')),
            Semantics(
              label: 'Sayfa ${page + 1}',
              excludeSemantics: true,
              child: Text('SAYFA ${page + 1}',
                  style: FlowText.caps(context, size: 11)),
            ),
            TextButton(
                onPressed: hasMore ? () => onPage(page + 1) : null,
                child: const Row(mainAxisSize: MainAxisSize.min, children: [
                  Text('Sonraki'),
                  SizedBox(width: 4),
                  Icon(Icons.chevron_right, size: 18),
                ])),
          ]);
}
