import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../bot/providers/bot_providers.dart';
import '../../knowledge/providers/knowledge_providers.dart';
import '../../tenancy/providers/tenant_providers.dart';
import '../providers/catalog_providers.dart';

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

/// Two steps: pick a business type, then answer a few questions the bot will use.
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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final packs = ref.watch(industryPacksProvider);
    final pack = _pack;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(pack == null ? 'Sektör paketi kur' : pack.name, style: theme.textTheme.titleLarge),
          const SizedBox(height: 8),
          if (pack == null) ...[
            const Text(
                'Paket; katalog türünü, işinize uygun bot talimatını ve verdiğiniz bilgilerden bot bilgi bankasını hazırlar.'),
            const SizedBox(height: 12),
            ...packs.when(
              loading: () => [const LinearProgressIndicator(minHeight: 2)],
              error: (_, __) => [
                TextButton(
                  onPressed: () => ref.invalidate(industryPacksProvider),
                  child: const Text('Paketler yüklenemedi. Tekrar dene'),
                ),
              ],
              data: (items) => [
                for (final item in items)
                  Card(
                    child: ListTile(
                      title: Text(item.name),
                      subtitle: Text(industryPackDescriptions[item.key] ?? ''),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => setState(() {
                        _pack = item;
                        for (final q in item.questions) {
                          _answers.putIfAbsent(q.key, TextEditingController.new);
                        }
                      }),
                    ),
                  ),
              ],
            ),
          ] else ...[
            const Text(
                'Botun müşterilere doğru bilgi vermesi için kısaca yanıtlayın. Boş bıraktıklarınız eklenmez; sonra Bilgi bölümünden düzenleyebilirsiniz.'),
            const SizedBox(height: 12),
            for (final q in pack.questions)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: TextField(
                  controller: _answers[q.key],
                  readOnly: _busy,
                  minLines: 1,
                  maxLines: 4,
                  maxLength: 4000,
                  decoration: InputDecoration(
                    labelText: q.title,
                    hintText: industryPackHints[q.key],
                    alignLabelWithHint: true,
                  ),
                ),
              ),
            if (_error != null)
              Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
            Wrap(alignment: WrapAlignment.end, spacing: 8, children: [
              TextButton(
                onPressed: _busy ? null : () => setState(() => _pack = null),
                child: const Text('Geri'),
              ),
              FilledButton(
                onPressed: _busy ? null : _apply,
                child: _busy
                    ? const SizedBox(
                        height: 16, width: 16, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Text('Paketi kur'),
              ),
            ]),
          ],
        ]),
      ),
    );
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
        builder: (context) => AlertDialog(
          title: const Text('Paket kuruldu'),
          content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Yeni bilgi kaydı: ${result['knowledge_added'] ?? 0}, güncellenen: ${result['knowledge_updated'] ?? 0}'),
            if (result['prompt_applied'] == true)
              const Text('Bot talimatı işinize göre ayarlandı.')
            else
              const Text('Kendi bot talimatınız korundu.'),
            const SizedBox(height: 12),
            const Text('Sıradaki adımlar:'),
            const Text('1. Katalog > Kayıtlar bölümünden oda, araç veya hizmetlerinizi ekleyin.'),
            Text(result['bot_active'] == true
                ? '2. Botunuz zaten açık; yeni bilgileri hemen kullanır.'
                : '2. Bot ayarlarından botu etkinleştirin.'),
          ]),
          actions: [
            FilledButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Tamam')),
          ],
        ),
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

/// Opens the pack wizard; shown to administrators only (the RPC also checks).
class IndustryPackButton extends ConsumerWidget {
  const IndustryPackButton({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isAdmin = ref.watch(currentMembershipProvider).valueOrNull?.isAdmin ?? false;
    if (!isAdmin) return const SizedBox.shrink();
    return FilledButton.icon(
      onPressed: () => showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        builder: (_) => const IndustryPackSheet(),
      ),
      icon: const Icon(Icons.auto_awesome),
      label: const Text('Sektör paketi kur'),
    );
  }
}
