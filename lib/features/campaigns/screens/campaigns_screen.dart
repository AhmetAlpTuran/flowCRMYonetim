import 'package:flutter/material.dart';

import '../../templates/models/message_template.dart';

class CampaignsScreen extends StatefulWidget {
  const CampaignsScreen({super.key});

  @override
  State<CampaignsScreen> createState() => _CampaignsScreenState();
}

class _CampaignsScreenState extends State<CampaignsScreen> {
  String _selectedFilter = 'Son 7 gunde gorusulenler';
  MessageTemplate? _selectedTemplate;

  final List<String> _filters = const [
    'Son 7 gunde gorusulenler',
    'Son 30 gunde aktif olanlar',
    '3+ kez alisveris yapanlar',
    'Son kampanyaya cevap verenler',
  ];

  final List<MessageTemplate> _templates = const [
    MessageTemplate(
      id: 't1',
      name: 'Kampanya Duyurusu',
      category: 'MARKETING',
      language: 'tr',
      body: 'Merhaba {{1}}, yeni kampanyamiz basladi! Detaylar icin tiklayin.',
      status: 'Onaylandi',
    ),
    MessageTemplate(
      id: 't2',
      name: 'Sepet Hatirlatma',
      category: 'MARKETING',
      language: 'tr',
      body: 'Merhaba {{1}}, sepetinizdeki urunler sizi bekliyor.',
      status: 'Onaylandi',
    ),
    MessageTemplate(
      id: 't3',
      name: 'Siparis Guncelleme',
      category: 'UTILITY',
      language: 'tr',
      body: 'Siparisiniz hazirlaniyor. Takip no: {{1}}',
      status: 'Taslak',
    ),
  ];

  final List<_CustomFilter> _customFilters = [
    _CustomFilter(field: 'Son iletisim', operatorValue: '>', value: '7 gun'),
  ];

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        _HeaderSection(
          title: 'Kampanya Yoneticisi',
          subtitle: 'Hedef kitleyi secin, sablonu belirleyin ve gonderimi baslatin.',
          icon: Icons.campaign_outlined,
        ),
        const SizedBox(height: 16),
        _StatsRow(),
        const SizedBox(height: 16),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _SectionTitle(icon: Icons.filter_alt_outlined, title: 'Kitle Filtresi'),
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
                  children: const [
                    FilterChip(
                      label: Text('Son iletisim: 7 gun'),
                      selected: true,
                      onSelected: null,
                    ),
                    FilterChip(
                      label: Text('Aktif'),
                      selected: true,
                      onSelected: null,
                    ),
                    FilterChip(
                      label: Text('Segment: VIP'),
                      selected: false,
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
                _SectionTitle(icon: Icons.article_outlined, title: 'Sablon Secimi'),
                const SizedBox(height: 12),
                DropdownButtonFormField<MessageTemplate>(
                  value: _selectedTemplate,
                  items: [
                    for (final template in _templates)
                      DropdownMenuItem(
                        value: template,
                        child: Text('${template.name} • ${template.status}'),
                      ),
                  ],
                  onChanged: (value) {
                    setState(() {
                      _selectedTemplate = value;
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
                      onPressed: () {},
                      child: const Text('Taslak olarak kaydet'),
                    ),
                    const Spacer(),
                    FilledButton(
                      onPressed: _selectedTemplate == null ? null : () {},
                      child: const Text('Kampanya baslat'),
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
  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _StatCard(
            title: 'Tahmini erisim',
            value: '4.820 kisi',
            icon: Icons.people_alt_outlined,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _StatCard(
            title: 'Ortalama acilma',
            value: '%63',
            icon: Icons.insights_outlined,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _StatCard(
            title: 'Butce kullanimi',
            value: '%42',
            icon: Icons.account_balance_wallet_outlined,
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