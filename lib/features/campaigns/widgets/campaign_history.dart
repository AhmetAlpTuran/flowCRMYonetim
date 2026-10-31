import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/campaign.dart';
import '../providers/campaign_providers.dart';

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
    }[status] ??
    'Durum bilgisi bekleniyor';

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
  @override
  Widget build(BuildContext context) {
    final key = (tenantId: widget.tenantId, page: _page);
    final history = ref.watch(campaignHistoryProvider(key));
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Wrap(
          spacing: 16,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text('Taslaklar ve geçmiş',
                style: Theme.of(context).textTheme.titleLarge),
            TextButton.icon(
                onPressed: () => ref.invalidate(campaignHistoryProvider(key)),
                icon: const Icon(Icons.refresh),
                label: const Text('Yenile')),
          ]),
      history.when(
          loading: () => const LinearProgressIndicator(
              semanticsLabel: 'Kampanyalar yükleniyor'),
          error: (_, __) => const Text(
              'Kampanya geçmişi yüklenemedi. Yenile düğmesiyle tekrar deneyin.'),
          data: (rows) =>
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                if (rows.isEmpty)
                  Text(_page == 0
                      ? 'Henüz kampanya yok. Yukarıdan ilk taslağınızı kaydedin.'
                      : 'Bu sayfada kampanya bulunamadı.'),
                for (final row in rows)
                  Card(
                      child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(row.name,
                                  style:
                                      Theme.of(context).textTheme.titleMedium),
                              const SizedBox(height: 4),
                              Text(
                                  'Kaydedilen durum: ${campaignStatusLabel(row.status)}'),
                              Wrap(spacing: 12, runSpacing: 4, children: [
                                if (row.editable)
                                  TextButton(
                                      onPressed: widget.onOpen == null
                                          ? null
                                          : () => widget.onOpen!(row),
                                      child: const Text('Taslağı aç')),
                                if (!row.editable)
                                  TextButton(
                                      onPressed: () => showDialog<void>(
                                          context: context,
                                          builder: (context) =>
                                              AlertDialog(
                                                  title: Text(row.name),
                                                  scrollable: true,
                                                  content: SizedBox(
                                                      width: 620,
                                                      child:
                                                          CampaignProgressPanel(
                                                              tenantId: widget
                                                                  .tenantId,
                                                              campaignId:
                                                                  row.id)),
                                                  actions: [
                                                    TextButton(
                                                        onPressed: () =>
                                                            Navigator.pop(
                                                                context),
                                                        child:
                                                            const Text('Kapat'))
                                                  ])),
                                      child: const Text('Gönderim durumu')),
                              ]),
                            ],
                          ))),
                _PageControls(
                    page: _page,
                    hasMore: rows.length == 20,
                    onPage: (value) => setState(() => _page = value)),
              ])),
    ]);
  }
}

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
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Wrap(
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 12,
          children: [
            Text('Gönderim durumu',
                style: Theme.of(context).textTheme.titleMedium),
            TextButton.icon(
                onPressed: () {
                  ref.invalidate(campaignProgressProvider(key));
                  ref.invalidate(campaignFailuresProvider(failureKey));
                },
                icon: const Icon(Icons.refresh),
                label: const Text('Yenile')),
          ]),
      progress.when(
          loading: () => const LinearProgressIndicator(
              semanticsLabel: 'Gönderim durumu yükleniyor'),
          error: (_, __) => const Text(
              'Güncel durum alınamadı. Yenileyin; kampanyayı yeniden oluşturmayın.'),
          data: (data) =>
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                if (data.legacy)
                  const Text(
                      'Bu kampanya eski gönderim sistemiyle oluşturuldu. Yeni kuyruk sayaçları geçmiş teslimatları göstermez.')
                else ...[
                  Text(campaignStatusLabel(data.status)),
                  const SizedBox(height: 8),
                  Wrap(spacing: 8, runSpacing: 8, children: [
                    for (final metric in const {
                      'total': 'Alıcı',
                      'queued': 'Kuyrukta',
                      'leased': 'Hazırlanıyor',
                      'sending': 'Gönderiliyor',
                      'accepted': 'API kabulü',
                      'retry_wait': 'Tekrar bekliyor',
                      'blocked': 'Bağlantı bekliyor',
                      'failed': 'Başarısız',
                      'unknown': 'Doğrulanamadı',
                      'cancelled': 'İptal',
                      'delivered': 'Teslim edildi',
                      'read': 'Okundu',
                      'delivery_failed': 'Teslim edilemedi',
                    }.entries)
                      Chip(
                          label: Text(
                              '${metric.value}: ${data.count(metric.key)}'))
                  ]),
                  const SizedBox(height: 8),
                  const Text(
                      'API kabulü teslimat onayı değildir. Doğrulanamayan mesajlar otomatik tekrar gönderilmez.'),
                ],
              ])),
      const SizedBox(height: 16),
      Text('İncelenecek alıcılar',
          style: Theme.of(context).textTheme.titleSmall),
      failures.when(
          loading: () => const LinearProgressIndicator(
              semanticsLabel: 'Alıcı sonuçları yükleniyor'),
          error: (_, __) => const Text(
              'Alıcı sonuçları yüklenemedi. Yenileyerek tekrar deneyin.'),
          data: (rows) =>
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                if (rows.isEmpty)
                  const Text('Bu sayfada hata veya belirsiz sonuç yok.'),
                for (final row in rows)
                  Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            SelectableText(
                                '${row['recipient_phone']} · ${campaignStatusLabel(row['state'] as String)}'),
                            Text(_failureMessage(row['error_code'] as String?)),
                            Text('Deneme: ${row['attempts'] ?? 0}'),
                          ])),
                _PageControls(
                    page: _page,
                    hasMore: rows.length == 20,
                    onPage: (value) => setState(() => _page = value)),
              ])),
    ]);
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
        : 'Gönderim tamamlanamadı. Hata kodu: $code';
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
          spacing: 12,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            TextButton(
                onPressed: page > 0 ? () => onPage(page - 1) : null,
                child: const Text('Önceki')),
            Text('Sayfa ${page + 1}'),
            TextButton(
                onPressed: hasMore ? () => onPage(page + 1) : null,
                child: const Text('Sonraki')),
          ]);
}
