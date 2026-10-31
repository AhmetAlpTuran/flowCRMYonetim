import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../templates/models/message_template.dart';
import '../../tenancy/providers/tenant_providers.dart';
import '../data/supabase_campaign_repository.dart';
import '../models/template_input.dart';
import '../widgets/template_parameter_fields.dart';

class CampaignsScreen extends ConsumerWidget {
  const CampaignsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tenant = ref.watch(selectedTenantProvider);
    if (tenant == null) {
      return const Center(
          child: Text('Kampanya oluşturmak için işletme seçin.'));
    }
    return _TenantCampaignForm(key: ValueKey(tenant.id));
  }
}

class _TenantCampaignForm extends ConsumerStatefulWidget {
  const _TenantCampaignForm({super.key});

  @override
  ConsumerState<_TenantCampaignForm> createState() => _CampaignsScreenState();
}

class _CampaignsScreenState extends ConsumerState<_TenantCampaignForm> {
  late final SupabaseCampaignRepository _repository;
  final TextEditingController _campaignNameController = TextEditingController();
  final _parameterFormKey = GlobalKey<FormState>();
  List<CampaignTemplateInput> _templateInputs = [];
  Map<String, dynamic> _templateBindings = {};
  bool _templateLoading = false;
  String? _templateError;
  int _templateRevision = 0;

  String _selectedFilter = 'Son 7 gunde gorusulenler';
  MessageTemplate? _selectedTemplate;
  int _audienceCount = 0;
  bool _loading = true;
  bool _sending = false;
  String? _error;
  int _audienceRevision = 0;

  final List<String> _filters = const [
    'Son 7 gunde gorusulenler',
    'Son 30 gunde aktif olanlar',
    '3+ kez alisveris yapanlar',
    'Son kampanyaya cevap verenler',
  ];

  final List<MessageTemplate> _templates = [];

  final List<_CustomFilter> _customFilters = [];

  @override
  void initState() {
    super.initState();
    _repository = SupabaseCampaignRepository(Supabase.instance.client);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _loadData();
    });
  }

  @override
  void dispose() {
    _campaignNameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tenant = ref.watch(selectedTenantProvider);
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        const _HeaderSection(
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
                const _SectionTitle(
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
                const _SectionTitle(
                  icon: Icons.filter_alt_outlined,
                  title: 'Kitle Filtresi',
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: _selectedFilter,
                  isExpanded: true,
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
                const _SectionTitle(icon: Icons.tune, title: 'Ozel filtreler'),
                const SizedBox(height: 8),
                for (final filter in _customFilters)
                  _CustomFilterRow(
                    key: ObjectKey(filter),
                    filter: filter,
                    onChanged: _refreshAudienceCount,
                    onRemove: () {
                      setState(() {
                        _customFilters.remove(filter);
                      });
                      _refreshAudienceCount();
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
                      _refreshAudienceCount();
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
                const _SectionTitle(
                  icon: Icons.article_outlined,
                  title: 'Sablon Secimi',
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<MessageTemplate>(
                  key: ValueKey('${tenant?.id}:${_selectedTemplate?.id}'),
                  initialValue: _selectedTemplate,
                  isExpanded: true,
                  items: [
                    for (final template in _templates)
                      DropdownMenuItem(
                        value: template,
                        child: Text(
                          '${template.name} • ${template.status}',
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                  ],
                  onChanged: _sending ? null : _selectTemplate,
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
                if (_templateLoading)
                  const LinearProgressIndicator(
                      semanticsLabel: 'Şablon alanları yükleniyor'),
                if (_templateError != null) ...[
                  Text(_templateError!,
                      style: TextStyle(
                          color: Theme.of(context).colorScheme.error)),
                  TextButton(
                    onPressed: () => _selectTemplate(_selectedTemplate),
                    child: const Text('Tekrar dene'),
                  ),
                ],
                if (_selectedTemplate != null &&
                    !_templateLoading &&
                    _templateError == null)
                  Form(
                    key: _parameterFormKey,
                    child: TemplateParameterFields(
                      key: ValueKey(_selectedTemplate!.id),
                      inputs: _templateInputs,
                      bindings: _templateBindings,
                      enabled: !_sending,
                      onChanged: (value) =>
                          setState(() => _templateBindings = value),
                    ),
                  ),
                const SizedBox(height: 16),
                Wrap(
                  spacing: 12,
                  runSpacing: 8,
                  alignment: WrapAlignment.end,
                  children: [
                    TextButton(
                      onPressed: _canSubmit ? _saveDraft : null,
                      child: const Text('Taslak olarak kaydet'),
                    ),
                    FilledButton(
                      onPressed: _canSubmit ? _startCampaign : null,
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

  bool get _canSubmit =>
      !_sending &&
      !_loading &&
      !_templateLoading &&
      _selectedTemplate != null &&
      _templateError == null;

  Future<void> _selectTemplate(MessageTemplate? template) async {
    final tenantId = ref.read(selectedTenantProvider)?.id;
    final revision = ++_templateRevision;
    setState(() {
      _selectedTemplate = template;
      _templateInputs = [];
      _templateBindings = {};
      _templateError = null;
      _templateLoading = template != null && tenantId != null;
      if (template != null && _campaignNameController.text.trim().isEmpty) {
        _campaignNameController.text = '${template.name} Kampanyasi';
      }
    });
    if (template == null || tenantId == null) return;
    try {
      final inputs = await _repository.fetchTemplateInputs(
          tenantId: tenantId, templateId: template.id);
      if (!mounted ||
          revision != _templateRevision ||
          ref.read(selectedTenantProvider)?.id != tenantId) {
        return;
      }
      setState(() {
        _templateInputs = inputs;
        _templateBindings = {
          for (final input in inputs)
            input.key: {
              'source': input.isMedia ? 'media_link' : 'literal',
              'value': '',
            },
        };
      });
    } catch (_) {
      if (mounted &&
          revision == _templateRevision &&
          ref.read(selectedTenantProvider)?.id == tenantId) {
        setState(() => _templateError =
            'Şablon alanları yüklenemedi. Onay durumunu ve desteklenen şablon türünü kontrol edin.');
      }
    } finally {
      if (mounted &&
          revision == _templateRevision &&
          ref.read(selectedTenantProvider)?.id == tenantId) {
        setState(() => _templateLoading = false);
      }
    }
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
      if (!mounted || ref.read(selectedTenantProvider)?.id != tenant.id) return;
      setState(() {
        _templates
          ..clear()
          ..addAll(templates);
      });
      await _refreshAudienceCount();
    } catch (_) {
      if (mounted && ref.read(selectedTenantProvider)?.id == tenant.id) {
        setState(
            () => _error = 'Şablonlar yüklenemedi. Lütfen tekrar deneyin.');
      }
    } finally {
      if (mounted && ref.read(selectedTenantProvider)?.id == tenant.id) {
        setState(() {
          _loading = false;
        });
      }
    }
  }

  Future<void> _refreshAudienceCount() async {
    final revision = ++_audienceRevision;
    final tenant = ref.read(selectedTenantProvider);
    if (tenant == null) {
      return;
    }
    final filter = _buildAudienceFilter();
    try {
      final count = await _repository.countAudience(
        tenantId: tenant.id,
        segment: filter['segment'] as String?,
        lastContacted: filter['last_contacted'] as String?,
        custom: (filter['custom'] as List<Map<String, dynamic>>?) ?? const [],
      );
      if (mounted &&
          revision == _audienceRevision &&
          ref.read(selectedTenantProvider)?.id == tenant.id) {
        setState(() {
          _audienceCount = count;
          _error = null;
        });
      }
    } catch (_) {
      if (mounted &&
          revision == _audienceRevision &&
          ref.read(selectedTenantProvider)?.id == tenant.id) {
        setState(() {
          _audienceCount = 0;
          _error =
              'Kitle hesaplanamadı. Filtreleri kontrol edip tekrar deneyin.';
        });
      }
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
    if (!_canSubmit) return;
    final tenant = ref.read(selectedTenantProvider);
    final template = _selectedTemplate;
    if (tenant == null || template == null) {
      return;
    }
    final name = _campaignNameController.text.trim().isEmpty
        ? '${template.name} Kampanyasi'
        : _campaignNameController.text.trim();
    setState(() => _sending = true);
    try {
      await _repository.createCampaign(
        tenantId: tenant.id,
        name: name,
        audienceFilter: _buildAudienceFilter(),
        templateId: template.id,
        templateBindings: _templateBindings,
      );
      if (mounted && ref.read(selectedTenantProvider)?.id == tenant.id) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Taslak kaydedildi.')),
        );
      }
    } catch (_) {
      if (mounted && ref.read(selectedTenantProvider)?.id == tenant.id) {
        setState(() =>
            _error = 'Taslak kaydedilemedi. Girdiğiniz değerler korunuyor.');
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _startCampaign() async {
    if (!_canSubmit || !(_parameterFormKey.currentState?.validate() ?? false)) {
      return;
    }
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
        templateBindings: _templateBindings,
      );
      final result = await _repository.sendCampaign(campaignId);
      final progress = result['progress'] as Map<String, dynamic>?;
      final total = progress?['total'] ?? 0;
      if (mounted && ref.read(selectedTenantProvider)?.id == tenant.id) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(result['status'] == 'queued'
                ? 'Kampanya kuyruğa alındı. $total alıcı arka planda işlenecek.'
                : 'Bu kampanya daha önce kuyruğa alındı. $total kayıtlı alıcı var.'),
          ),
        );
      }
    } catch (_) {
      if (mounted && ref.read(selectedTenantProvider)?.id == tenant.id) {
        setState(() => _error =
            'Gönderim sonucu alınamadı. Tekrar göndermeden önce kampanya durumunu kontrol edin.');
      }
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
              backgroundColor:
                  Theme.of(context).colorScheme.surfaceContainerHighest,
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
    super.key,
    required this.filter,
    required this.onChanged,
    required this.onRemove,
  });

  final _CustomFilter filter;
  final VoidCallback onChanged;
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
      child: LayoutBuilder(
        builder: (context, constraints) {
          final isNarrow = constraints.maxWidth < 640;
          const hSpacing = SizedBox(width: 8);
          const vSpacing = SizedBox(height: 8);

          if (isNarrow) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                DropdownButtonFormField<String>(
                  initialValue: widget.filter.field,
                  items: const [
                    DropdownMenuItem(
                        value: 'Son iletisim', child: Text('Son iletisim')),
                    DropdownMenuItem(value: 'Etiket', child: Text('Etiket')),
                  ],
                  onChanged: (value) {
                    if (value != null) {
                      setState(() => widget.filter.field = value);
                      widget.onChanged();
                    }
                  },
                  decoration: const InputDecoration(labelText: 'Alan'),
                ),
                vSpacing,
                DropdownButtonFormField<String>(
                  initialValue: widget.filter.operatorValue,
                  items: const [
                    DropdownMenuItem(value: '=', child: Text('=')),
                    DropdownMenuItem(value: '>', child: Text('>')),
                    DropdownMenuItem(value: '<', child: Text('<')),
                    DropdownMenuItem(value: 'icerir', child: Text('icerir')),
                  ],
                  onChanged: (value) {
                    if (value != null) {
                      setState(() => widget.filter.operatorValue = value);
                      widget.onChanged();
                    }
                  },
                  decoration: const InputDecoration(labelText: 'Operator'),
                ),
                vSpacing,
                TextField(
                  controller: _valueController,
                  decoration: const InputDecoration(labelText: 'Deger'),
                  onChanged: (value) {
                    widget.filter.value = value;
                    widget.onChanged();
                  },
                ),
                vSpacing,
                Align(
                  alignment: Alignment.centerRight,
                  child: IconButton(
                    onPressed: widget.onRemove,
                    icon: const Icon(Icons.close),
                    tooltip: 'Kaldir',
                  ),
                ),
              ],
            );
          }

          return Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<String>(
                  initialValue: widget.filter.field,
                  items: const [
                    DropdownMenuItem(
                        value: 'Son iletisim', child: Text('Son iletisim')),
                    DropdownMenuItem(value: 'Etiket', child: Text('Etiket')),
                  ],
                  onChanged: (value) {
                    if (value != null) {
                      setState(() => widget.filter.field = value);
                      widget.onChanged();
                    }
                  },
                  decoration: const InputDecoration(labelText: 'Alan'),
                ),
              ),
              hSpacing,
              SizedBox(
                width: 120,
                child: DropdownButtonFormField<String>(
                  initialValue: widget.filter.operatorValue,
                  items: const [
                    DropdownMenuItem(value: '=', child: Text('=')),
                    DropdownMenuItem(value: '>', child: Text('>')),
                    DropdownMenuItem(value: '<', child: Text('<')),
                    DropdownMenuItem(value: 'icerir', child: Text('icerir')),
                  ],
                  onChanged: (value) {
                    if (value != null) {
                      setState(() => widget.filter.operatorValue = value);
                      widget.onChanged();
                    }
                  },
                  decoration: const InputDecoration(labelText: 'Operator'),
                ),
              ),
              hSpacing,
              Expanded(
                child: TextField(
                  controller: _valueController,
                  decoration: const InputDecoration(labelText: 'Deger'),
                  onChanged: (value) {
                    widget.filter.value = value;
                    widget.onChanged();
                  },
                ),
              ),
              hSpacing,
              IconButton(
                onPressed: widget.onRemove,
                icon: const Icon(Icons.close),
                tooltip: 'Kaldir',
              ),
            ],
          );
        },
      ),
    );
  }
}
