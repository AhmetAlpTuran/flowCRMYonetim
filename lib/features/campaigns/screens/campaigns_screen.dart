import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../templates/models/message_template.dart';
import '../../tenancy/providers/tenant_providers.dart';
import '../data/supabase_campaign_repository.dart';

class CampaignsScreen extends ConsumerStatefulWidget {
  const CampaignsScreen({super.key});

  @override
  ConsumerState<CampaignsScreen> createState() => _CampaignsScreenState();
}

class _CampaignsScreenState extends ConsumerState<CampaignsScreen> {
  late final SupabaseCampaignRepository _repository;
  final TextEditingController _campaignNameController = TextEditingController();

  String _selectedFilter = 'Son 7 gunde gorusulenler';
  MessageTemplate? _selectedTemplate;
  int _audienceCount = 0;
  bool _loading = false;
  bool _sending = false;
  String? _error;
  String? _currentTenantId;

  final List<String> _filters = const [
    'Son 7 gunde gorusulenler',
    'Son 30 gunde aktif olanlar',
    '3+ kez alisveris yapanlar',
    'Son kampanyaya cevap verenler',
  ];

  final List<MessageTemplate> _templates = [];

  final List<_CustomFilter> _customFilters = [
    _CustomFilter(field: 'Son iletisim', operatorValue: '>', value: '7 gun'),
  ];

  @override
  void initState() {
    super.initState();
    _repository = SupabaseCampaignRepository(Supabase.instance.client);
  }

  @override
  void dispose() {
    _campaignNameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tenant = ref.watch(selectedTenantProvider);
    if (_currentTenantId != tenant?.id) {
      _currentTenantId = tenant?.id;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _loadData();
      });
    }

    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        _HeaderSection(
          title: 'Kampanya Yoneticisi',
          subtitle:
              'KVKK izinli kitleyi secin, sablonu belirleyin ve gonderimi baslatin.',
          icon: Icons.campaign_outlined,
        ),
        const SizedBox(height: 16),
        _StatsRow(
          audienceCount: _audienceCount,
          isLoading: _loading,
        ),
        const SizedBox(height: 16),
        if (_error != null) ...[
          Text(
            _error!,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
          const SizedBox(height: 12),
        ],
        Card(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _SectionTitle(
                  icon: Icons.edit_outlined,
                  title: 'Kampanya Bilgileri',
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _campaignNameController,
                  decoration: const InputDecoration(
                    labelText: 'Kampanya adi',
                    hintText: 'Ornek: Yaz Indirimi',
                  ),
                ),
                const SizedBox(height: 16),
                _SectionTitle(
                  icon: Icons.filter_alt_outlined,
                  title: 'Kitle Filtresi',
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  value: _selectedFilter,
                  items: [
                    for (final filter in _filters)
                      DropdownMenuItem(
                        value: filter,
                        child: Text(filter),
                      ),
                  ],
                  onChanged: (value) {
                    if (value != null) {
                      setState(() {
                        _selectedFilter = value;
                      });
                      _refreshAudienceCount();
                    }
                  },
                  decoration: const InputDecoration(
                    labelText: 'Varsayilan filtre',
                  ),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    FilterChip(
                      label: Text('Filtre: $_selectedFilter'),
                      selected: true,
                      onSelected: null,
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                _SectionTitle(icon: Icons.tune, title: 'Ozel filtreler'),
                const SizedBox(height: 8),
                for (final filter in _customFilters)
                  _CustomFilterRow(
                    filter: filter,
                    onRemove: () {
                      setState(() {
                        _customFilters.remove(filter);
                      });
                    },
                  ),
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton.icon(
                    onPressed: () {
                      setState(() {
                        _customFilters.add(
                          _CustomFilter(
                            field: 'Etiket',
                            operatorValue: 'icerir',
                            value: 'VIP',
                          ),
                        );
                      });
                    },
                    icon: const Icon(Icons.add),
                    label: const Text('Filtre ekle'),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _SectionTitle(
                  icon: Icons.article_outlined,
                  title: 'Sablon Secimi',
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<MessageTemplate>(
                  value: _selectedTemplate,
                  items: [
                    for (final template in _templates)
                      DropdownMenuItem(
                        value: template,
                        child: Text(
                          '${template.name} • ${template.status}',
                        ),
                      ),
                  ],
                  onChanged: (value) {
                    setState(() {
                      _selectedTemplate = value;
                      if (value != null &&
                          _campaignNameController.text.trim().isEmpty) {
                        _campaignNameController.text =
                            '${value.name} Kampanyasi';
                      }
                    });
                  },
                  decoration: const InputDecoration(
                    labelText: 'WhatsApp sablonu',
                  ),
                ),
                const SizedBox(height: 12),
                if (_selectedTemplate != null)
                  Card(
                    color: Theme.of(context).colorScheme.primaryContainer,
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _selectedTemplate!.name,
                            style: Theme.of(context)
                                .textTheme
                                .titleMedium
                                ?.copyWith(
                                  color: Theme.of(context)
                                      .colorScheme
                                      .onPrimaryContainer,
                                ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            _selectedTemplate!.body,
                            style: Theme.of(context)
                                .textTheme
                                .bodyMedium
                                ?.copyWith(
                                  color: Theme.of(context)
                                      .colorScheme
                                      .onPrimaryContainer,
                                ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Kategori: ${_selectedTemplate!.category} • Dil: ${_selectedTemplate!.language}',
                            style: Theme.of(context)
                                .textTheme
                                .labelMedium
                                ?.copyWith(
                                  color: Theme.of(context)
                                      .colorScheme
                                      .onPrimaryContainer,
                                ),
                          ),
                        ],
                      ),
                    ),
                  ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    TextButton(
                      onPressed: _sending ? null : _saveDraft,
                      child: const Text('Taslak olarak kaydet'),
                    ),
                    const Spacer(),
                    FilledButton(
                      onPressed: _sending ? null : _startCampaign,
                      child: _sending
                          ? const SizedBox(
                              height: 16,
                              width: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Text('Kampanya baslat'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _loadData() async {
    final tenant = ref.read(selectedTenantProvider);
    if (tenant == null) {
      return;
    }
    setState(() {
      _loading = true;
    });
    try {
      final templates = await _repository.fetchTemplates(tenant.id);
      setState(() {
        _templates
          ..clear()
          ..addAll(templates);
      });
      await _refreshAudienceCount();
    } catch (error) {
      setState(() {
        _error = 'Veriler yuklenemedi: $error';
      });
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
    }
  }

  Future<void> _refreshAudienceCount() async {
    final tenant = ref.read(selectedTenantProvider);
    if (tenant == null) {
      return;
    }
    final filter = _buildAudienceFilter();
    final count = await _repository.countAudience(
      tenantId: tenant.id,
      segment: filter['segment'] as String?,
      lastContacted: filter['last_contacted'] as String?,
    );
    if (mounted) {
      setState(() {
        _audienceCount = count;
      });
    }
  }

  Map<String, dynamic> _buildAudienceFilter() {
    final filter = <String, dynamic>{};
    switch (_selectedFilter) {
      case 'Son 7 gunde gorusulenler':
        filter['last_contacted'] = '7d';
        break;
      case 'Son 30 gunde aktif olanlar':
        filter['last_contacted'] = '30d';
        break;
      case '3+ kez alisveris yapanlar':
        filter['segment'] = 'VIP';
        break;
      case 'Son kampanyaya cevap verenler':
        filter['segment'] = 'Kampanya';
        break;
      default:
        break;
    }
    if (_customFilters.isNotEmpty) {
      filter['custom'] = _customFilters
          .map((item) => {
                'field': item.field,
                'operator': item.operatorValue,
                'value': item.value,
              })
          .toList();
    }
    return filter;
  }

  Future<void> _saveDraft() async {
    final tenant = ref.read(selectedTenantProvider);
    final template = _selectedTemplate;
    if (tenant == null || template == null) {
      return;
    }
    final name = _campaignNameController.text.trim().isEmpty
        ? '${template.name} Kampanyasi'
        : _campaignNameController.text.trim();
    await Supabase.instance.client.from('campaigns').insert({
      'tenant_id': tenant.id,
      'name': name,
      'audience_filter': _buildAudienceFilter(),
      'template_id': template.id,
      'status': 'draft',
    });
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Taslak kaydedildi.')),
      );
    }
  }

  Future<void> _startCampaign() async {
    final tenant = ref.read(selectedTenantProvider);
    final template = _selectedTemplate;
    if (tenant == null || template == null) {
      return;
    }
    final name = _campaignNameController.text.trim().isEmpty
        ? '${template.name} Kampanyasi'
        : _campaignNameController.text.trim();
    setState(() {
      _sending = true;
      _error = null;
    });
    try {
      final campaignId = await _repository.createCampaign(
        tenantId: tenant.id,
        name: name,
        audienceFilter: _buildAudienceFilter(),
        templateId: template.id,
      );
      final result = await _repository.sendCampaign(campaignId);
      final sent = result['sent'] ?? 0;
      final failed = result['failed'] ?? 0;
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Gonderim tamamlandi. $sent basarili, $failed hatali.'),
          ),
        );
      }
    } catch (error) {
      setState(() {
        _error = 'Kampanya baslatilamadi: $error';
      });
    } finally {
      if (mounted) {
        setState(() {
          _sending = false;
        });
      }
    }
  }
}

class _HeaderSection extends StatelessWidget {
  const _HeaderSection({
    required this.title,
    required this.subtitle,
    required this.icon,
  });

  final String title;
  final String subtitle;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        CircleAvatar(
          radius: 22,
          backgroundColor: Theme.of(context).colorScheme.primaryContainer,
          child: Icon(icon, color: Theme.of(context).colorScheme.primary),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: Theme.of(context).textTheme.headlineSmall),
              const SizedBox(height: 4),
              Text(subtitle, style: Theme.of(context).textTheme.bodyMedium),
            ],
          ),
        ),
      ],
    );
  }
}

class _StatsRow extends StatelessWidget {
  const _StatsRow({
    required this.audienceCount,
    required this.isLoading,
  });

  final int audienceCount;
  final bool isLoading;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _StatCard(
            title: 'Tahmini erisim',
            value: isLoading ? '...' : '$audienceCount kisi',
            icon: Icons.people_alt_outlined,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _StatCard(
            title: 'Durum',
            value: isLoading ? 'Yukleniyor' : 'Hazir',
            icon: Icons.insights_outlined,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _StatCard(
            title: 'KVKK izinli',
            value: isLoading ? '...' : 'Aktif',
            icon: Icons.verified_user_outlined,
          ),
        ),
      ],
    );
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({
    required this.title,
    required this.value,
    required this.icon,
  });

  final String title;
  final String value;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            CircleAvatar(
              backgroundColor: Theme.of(context).colorScheme.surfaceContainerHighest,
              child: Icon(icon, color: Theme.of(context).colorScheme.primary),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: Theme.of(context).textTheme.labelMedium),
                  const SizedBox(height: 6),
                  Text(value, style: Theme.of(context).textTheme.titleLarge),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.icon, required this.title});

  final IconData icon;
  final String title;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, color: Theme.of(context).colorScheme.primary),
        const SizedBox(width: 8),
        Text(title, style: Theme.of(context).textTheme.titleMedium),
      ],
    );
  }
}

class _CustomFilter {
  _CustomFilter({
    required this.field,
    required this.operatorValue,
    required this.value,
  });

  String field;
  String operatorValue;
  String value;
}

class _CustomFilterRow extends StatefulWidget {
  const _CustomFilterRow({
    required this.filter,
    required this.onRemove,
  });

  final _CustomFilter filter;
  final VoidCallback onRemove;

  @override
  State<_CustomFilterRow> createState() => _CustomFilterRowState();
}

class _CustomFilterRowState extends State<_CustomFilterRow> {
  late final TextEditingController _valueController =
      TextEditingController(text: widget.filter.value);

  @override
  void dispose() {
    _valueController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          Expanded(
            child: DropdownButtonFormField<String>(
              value: widget.filter.field,
              items: const [
                DropdownMenuItem(value: 'Son iletisim', child: Text('Son iletisim')),
                DropdownMenuItem(value: 'Etiket', child: Text('Etiket')),
                DropdownMenuItem(value: 'Ulke', child: Text('Ulke')),
                DropdownMenuItem(
                  value: 'Siparis adedi',
                  child: Text('Siparis adedi'),
                ),
              ],
              onChanged: (value) {
                if (value != null) {
                  setState(() {
                    widget.filter.field = value;
                  });
                }
              },
              decoration: const InputDecoration(labelText: 'Alan'),
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 120,
            child: DropdownButtonFormField<String>(
              value: widget.filter.operatorValue,
              items: const [
                DropdownMenuItem(value: '=', child: Text('=')),
                DropdownMenuItem(value: '>', child: Text('>')),
                DropdownMenuItem(value: '<', child: Text('<')),
                DropdownMenuItem(value: 'icerir', child: Text('icerir')),
              ],
              onChanged: (value) {
                if (value != null) {
                  setState(() {
                    widget.filter.operatorValue = value;
                  });
                }
              },
              decoration: const InputDecoration(labelText: 'Operator'),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: TextField(
              controller: _valueController,
              decoration: const InputDecoration(labelText: 'Deger'),
              onChanged: (value) => widget.filter.value = value,
            ),
          ),
          const SizedBox(width: 8),
          IconButton(
            onPressed: widget.onRemove,
            icon: const Icon(Icons.close),
            tooltip: 'Kaldir',
          ),
        ],
      ),
    );
  }
}
