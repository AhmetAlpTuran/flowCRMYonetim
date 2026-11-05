import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../ui/ui.dart';
import '../../bot/providers/bot_providers.dart';
import '../../knowledge/providers/knowledge_providers.dart';
import '../../tenancy/providers/tenant_providers.dart';
import '../providers/catalog_providers.dart';
import 'catalog_layout.dart';

class IndustryPack {
  const IndustryPack({required this.key, required this.name, required this.questions});

  factory IndustryPack.fromJson(Map<String, dynamic> json) => IndustryPack(
        key: json['key'] as String,
        name: json['name'] as String,
        questions: [
          for (final q in (json['questions'] as List? ?? const []))
            if (q is Map) (key: q['key'] as String, title: q['title'] as String),
        ],
      );

  final String key;
  final String name;
  final List<({String key, String title})> questions;
}

const industryPackDescriptions = {
  'rental': 'Otel, pansiyon, villa, apart: gecelik oda kataloğu, müsaitlik ve ön rezervasyon.',
  'auto_dealer': 'İkinci el / sıfır araç: stok arama, test sürüşü, takas ve kredi talepleri.',
  'appointments': 'Klinik, kuaför, servis: saatlik randevu ve hizmet bilgileri.',
};

const industryPackHints = {
  'checkin': 'Örn. Giriş 14:00, çıkış 11:00. Erken giriş müsaitliğe bağlıdır.',
  'address': 'Örn. Bağdat Cd. No:1, Kadıköy. Hafta içi 09:00-19:00, Cumartesi 10:00-16:00.',
  'payment': 'Örn. Rezervasyon için %30 kapora havale ile alınır; kalan girişte ödenir.',
  'cancellation': 'Örn. 7 gün öncesine kadar ücretsiz iptal; sonrasında kapora iade edilmez.',
  'amenities': 'Örn. Ücretsiz Wi-Fi ve otopark, evcil hayvan kabul edilmez.',
  'test_drive': 'Örn. Ehliyet ile, randevulu ve yaklaşık 30 dakika.',
  'financing': 'Örn. Anlaşmalı bankalarla 36 aya kadar kredi; peşinat en az %20.',
  'trade_in': 'Örn. Takas kabul edilir; ekspertiz sonrası değer belirlenir.',
  'warranty': 'Örn. Tüm araçlar ekspertizli; 6 ay motor-şanzıman garantisi.',
  'services': 'Örn. Saç kesimi 400 ₺ (45 dk), boya 1.200 ₺ (2 saat).',
  'preparation': 'Örn. Randevudan 10 dakika önce gelin; kimlik getirin.',
};

final industryPacksProvider = FutureProvider<List<IndustryPack>>((ref) async {
  final data = await Supabase.instance.client
      .rpc('industry_packs')
      .timeout(const Duration(seconds: 20));
  return [
    for (final item in (data as List? ?? const []))
      if (item is Map) IndustryPack.fromJson(Map<String, dynamic>.from(item)),
  ];
});

/// Applies a pack through `apply_industry_pack`; overridable in tests.
typedef ApplyIndustryPack = Future<Map<String, dynamic>> Function(
    String tenantId, String pack, Map<String, String> answers);

final applyIndustryPackProvider = Provider<ApplyIndustryPack>((ref) {
  return (tenantId, pack, answers) async {
    final data = await Supabase.instance.client.rpc('apply_industry_pack', params: {
      'p_tenant_id': tenantId,
      'p_pack': pack,
      'p_answers': answers,
    }).timeout(const Duration(seconds: 30));
    return Map<String, dynamic>.from(data as Map);
  };
});

/// Two steps: pick a business type, then answer a few questions the assistant will use.
class IndustryPackSheet extends ConsumerStatefulWidget {
  const IndustryPackSheet({super.key});

  @override
  ConsumerState<IndustryPackSheet> createState() => _IndustryPackSheetState();
}

class _IndustryPackSheetState extends ConsumerState<IndustryPackSheet> {
  IndustryPack? _pack;
  final _answers = <String, TextEditingController>{};
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    for (final c in _answers.values) {
      c.dispose();
    }
    super.dispose();
  }

  void _choose(IndustryPack pack) => setState(() {
        _pack = pack;
        _error = null;
        for (final q in pack.questions) {
          _answers.putIfAbsent(q.key, TextEditingController.new);
        }
      });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final c = FlowColors.of(context);
    final pack = _pack;
    final step = pack == null ? 1 : 2;
    return CatalogSheet(
      eyebrow: pack == null ? 'Adım 1 / 2 · İşiniz' : 'Adım 2 / 2 · Bilgiler',
      title: pack == null ? 'Sektör paketi kur' : pack.name,
      progress: _StepBar(step: step, of: 2),
      leadingAction: pack == null
          ? null
          : TextButton.icon(
              onPressed: _busy ? null : () => setState(() => _pack = null),
              style: TextButton.styleFrom(foregroundColor: c.muted),
              icon: const Icon(Icons.arrow_back, size: 18),
              label: const Text('Geri'),
            ),
      actions: [
        if (pack != null)
          FilledButton(
            onPressed: _busy ? null : _apply,
            child: _busy
                ? const Row(mainAxisSize: MainAxisSize.min, children: [
                    CatalogSpinner(size: 16),
                    SizedBox(width: FlowSpace.sm),
                    Text('Kuruluyor'),
                  ])
                : const Text('Paketi kur'),
          ),
      ],
      child: pack == null ? _sectors(theme, c) : _questions(pack, theme),
    );
  }

  Widget _sectors(ThemeData theme, FlowColors c) {
    final packs = ref.watch(industryPacksProvider);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Text('İşiniz hangisi?', style: theme.textTheme.titleLarge),
      const SizedBox(height: 4),
      Text(
        'Paket; kayıt türünü, işinize uygun asistan talimatını ve verdiğiniz bilgilerden bilgi bankasını hazırlar.',
        style: theme.textTheme.bodyMedium?.copyWith(color: c.muted),
      ),
      const SizedBox(height: FlowSpace.lg),
      packs.when(
        loading: () => const LoadingList(rows: 3),
        error: (_, __) => ErrorState(
          title: 'Paketler yüklenemedi',
          onRetry: () => ref.invalidate(industryPacksProvider),
        ),
        data: (items) => LayoutBuilder(builder: (context, constraints) {
          final columns = constraints.maxWidth >= 600 && items.length > 1 ? (items.length >= 3 ? 3 : 2) : 1;
          final width = columns == 1
              ? constraints.maxWidth
              : ((constraints.maxWidth - FlowSpace.md * (columns - 1)) / columns).floorToDouble();
          return Wrap(spacing: FlowSpace.md, runSpacing: FlowSpace.md, children: [
            for (final item in items)
              SizedBox(
                width: width,
                child: _SectorCard(pack: item, stacked: columns > 1, onTap: () => _choose(item)),
              ),
          ]);
        }),
      ),
    ]);
  }

  Widget _questions(IndustryPack pack, ThemeData theme) {
    final c = FlowColors.of(context);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Text('Birkaç soruyu yanıtlayın', style: theme.textTheme.titleLarge),
      const SizedBox(height: 4),
      Text(
        'Asistan müşterilere bu bilgilerle yanıt verir. Boş bıraktıklarınız eklenmez; '
        'sonra Asistan → Bilgi bankası bölümünden düzenleyebilirsiniz.',
        style: theme.textTheme.bodyMedium?.copyWith(color: c.muted),
      ),
      const SizedBox(height: FlowSpace.xl - 4),
      if (pack.questions.isEmpty)
        const CatalogNotice('Bu paket için soru yok; doğrudan kurabilirsiniz.', tone: FlowTone.info),
      for (final (index, q) in pack.questions.indexed)
        Padding(
          padding: const EdgeInsets.only(bottom: FlowSpace.md),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Padding(
              padding: const EdgeInsets.only(top: 17),
              child: SizedBox(
                width: 26,
                child: Text((index + 1).toString().padLeft(2, '0'), style: FlowText.mono(context, size: 12, color: c.faint)),
              ),
            ),
            Expanded(
              child: TextField(
                controller: _answers[q.key],
                readOnly: _busy,
                minLines: 1,
                maxLines: 4,
                maxLength: 4000,
                textCapitalization: TextCapitalization.sentences,
                decoration: InputDecoration(
                  labelText: q.title,
                  hintText: industryPackHints[q.key],
                  hintMaxLines: 3,
                  alignLabelWithHint: true,
                  floatingLabelBehavior: FloatingLabelBehavior.always,
                ),
              ),
            ),
          ]),
        ),
      if (_error != null) ...[const SizedBox(height: FlowSpace.sm), CatalogNotice(_error!)],
    ]);
  }

  Future<void> _apply() async {
    final tenant = ref.read(selectedTenantProvider);
    final pack = _pack;
    if (tenant == null || pack == null) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final result = await ref.read(applyIndustryPackProvider)(tenant.id, pack.key, {
        for (final entry in _answers.entries)
          if (entry.value.text.trim().isNotEmpty) entry.key: entry.value.text.trim(),
      });
      ref.invalidate(resourceTypesProvider);
      ref.invalidate(botConfigProvider);
      ref.invalidate(knowledgeEntriesProvider);
      if (!mounted) return;
      Navigator.of(context).pop();
      await showDialog<void>(
        context: context,
        builder: (context) => _PackResultDialog(result: result),
      );
    } catch (error) {
      if (mounted) {
        setState(() => _error = error is PostgrestException && error.code == '42501'
            ? 'Paketi yalnızca işletme yöneticileri kurabilir.'
            : error is TimeoutException
                ? 'Sunucu yanıt vermedi. Tekrar deneyin.'
                : 'Paket kurulamadı. Tekrar deneyin.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }
}

class _StepBar extends StatelessWidget {
  const _StepBar({required this.step, required this.of});

  final int step;
  final int of;

  @override
  Widget build(BuildContext context) {
    final c = FlowColors.of(context);
    return Semantics(
      label: 'Adım $step / $of',
      excludeSemantics: true,
      child: Row(children: [
        for (var i = 1; i <= of; i++) ...[
          if (i > 1) const SizedBox(width: 6),
          Expanded(
            child: Container(
              height: 4,
              decoration: BoxDecoration(
                color: i <= step ? c.meter : c.raised,
                borderRadius: BorderRadius.circular(FlowRadius.pill),
              ),
            ),
          ),
        ],
      ]),
    );
  }
}

class _SectorCard extends StatelessWidget {
  const _SectorCard({required this.pack, required this.stacked, required this.onTap});

  final IndustryPack pack;

  /// Icon above the text (grid) instead of beside it (list).
  final bool stacked;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = FlowColors.of(context);
    final theme = Theme.of(context);
    final icon = Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(color: c.raised, borderRadius: FlowRadius.controlAll),
      child: Icon(presetIcon(pack.key), color: c.accentText),
    );
    final text = Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(pack.name, style: theme.textTheme.titleMedium),
      const SizedBox(height: 4),
      Text(industryPackDescriptions[pack.key] ?? '', style: theme.textTheme.bodySmall),
      if (pack.questions.isNotEmpty) ...[
        const SizedBox(height: FlowSpace.sm),
        Text(upperTr('${pack.questions.length} soru'), style: FlowText.caps(context, size: 10, color: c.faint)),
      ],
    ]);
    return Material(
      color: c.canvas,
      shape: RoundedRectangleBorder(borderRadius: FlowRadius.cardAll, side: BorderSide(color: c.border)),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(FlowSpace.lg),
          child: stacked
              ? Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  icon,
                  const SizedBox(height: FlowSpace.md),
                  text,
                ])
              : Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  icon,
                  const SizedBox(width: FlowSpace.md),
                  Expanded(child: text),
                  const SizedBox(width: FlowSpace.sm),
                  Padding(
                    padding: const EdgeInsets.only(top: 10),
                    child: Icon(Icons.chevron_right, color: c.muted),
                  ),
                ]),
        ),
      ),
    );
  }
}

class _PackResultDialog extends StatelessWidget {
  const _PackResultDialog({required this.result});

  final Map<String, dynamic> result;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final c = FlowColors.of(context);
    Widget next(int number, String text) => Padding(
          padding: const EdgeInsets.only(top: FlowSpace.sm),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            SizedBox(
              width: 24,
              child: Text('$number', style: FlowText.mono(context, size: 13, color: c.accentText, weight: FontWeight.w600)),
            ),
            Expanded(child: Text(text, style: theme.textTheme.bodyMedium)),
          ]),
        );
    return AlertDialog(
      title: const Text('Paket kuruldu'),
      content: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          KeyValueRow(label: 'Yeni bilgi kaydı', value: formatCount((result['knowledge_added'] as num?) ?? 0), mono: true),
          KeyValueRow(
              label: 'Güncellenen bilgi', value: formatCount((result['knowledge_updated'] as num?) ?? 0), mono: true),
          const SizedBox(height: FlowSpace.sm),
          Text(
            result['prompt_applied'] == true
                ? 'Asistan talimatı işinize göre ayarlandı.'
                : 'Kendi asistan talimatınız korundu.',
            style: theme.textTheme.bodyMedium,
          ),
          const SizedBox(height: FlowSpace.lg),
          const Eyebrow('Sıradaki adımlar'),
          next(1, 'Katalog → Kayıtlar bölümünden oda, araç veya hizmetlerinizi ekleyin.'),
          next(
            2,
            result['bot_active'] == true
                ? 'Asistanınız zaten açık; yeni bilgileri hemen kullanır.'
                : 'Asistan → Asistanlar bölümünden asistanı açın.',
          ),
        ]),
      ),
      actions: [
        FilledButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Tamam')),
      ],
    );
  }
}

/// Opens the pack wizard; shown to administrators only (the RPC also checks).
/// Pass `primary: false` where the screen already has its one lime button.
class IndustryPackButton extends ConsumerWidget {
  const IndustryPackButton({super.key, this.primary = true});

  final bool primary;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isAdmin = ref.watch(currentMembershipProvider).valueOrNull?.isAdmin ?? false;
    if (!isAdmin) return const SizedBox.shrink();
    void open() => showCatalogSheet<void>(context, const IndustryPackSheet(), maxWidth: 760);
    const icon = Icon(Icons.auto_awesome, size: 18);
    const label = Text('Sektör paketi kur');
    return primary
        ? FilledButton.icon(onPressed: open, icon: icon, label: label)
        : OutlinedButton.icon(onPressed: open, icon: icon, label: label);
  }
}
