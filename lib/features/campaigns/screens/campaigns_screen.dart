import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../templates/models/message_template.dart';
import '../../tenancy/providers/tenant_providers.dart';
import '../models/campaign.dart';
import '../providers/campaign_providers.dart';
import '../widgets/campaign_history.dart';
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
    return _CampaignEditor(key: ValueKey(tenant.id), tenantId: tenant.id);
  }
}

class _CampaignEditor extends ConsumerStatefulWidget {
  const _CampaignEditor({super.key, required this.tenantId});
  final String tenantId;
  @override
  ConsumerState<_CampaignEditor> createState() => _CampaignEditorState();
}

class _CampaignEditorState extends ConsumerState<_CampaignEditor> {
  final _name = TextEditingController();
  final _form = GlobalKey<FormState>();
  String? _connectionId, _templateId;
  String _preset = 'all';
  Map<String, dynamic> _bindings = {};
  final List<Map<String, dynamic>> _custom = [];
  bool _dirty = false;
  int _formVersion = 0;
  static const _presets = {
    'all': 'Tüm izinli kişiler',
    '7d': 'Son 7 günde görüşülenler',
    '30d': 'Son 30 günde görüşülenler',
    'VIP': 'VIP etiketli kişiler',
    'Kampanya': 'Kampanya etiketli kişiler'
  };
  CampaignActions get _actions =>
      ref.read(campaignActionsProvider(widget.tenantId).notifier);
  Map<String, dynamic> get _filter => {
        if (_preset == '7d' || _preset == '30d') 'last_contacted': _preset,
        if (_preset == 'VIP' || _preset == 'Kampanya') 'segment': _preset,
        'custom':
            _custom.map((rule) => Map<String, dynamic>.from(rule)).toList(),
      };
  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final action = ref.watch(campaignActionsProvider(widget.tenantId));
    final options = ref.watch(campaignOptionsProvider(widget.tenantId));
    final audienceKey =
        (tenantId: widget.tenantId, filter: jsonEncode(_filter));
    final audience = ref.watch(campaignAudienceProvider(audienceKey));
    final enabled = !action.busy && !action.locked;
    return ListView(padding: const EdgeInsets.all(20), children: [
      Wrap(
          alignment: WrapAlignment.spaceBetween,
          spacing: 16,
          runSpacing: 8,
          children: [
            Text('Kampanyalar',
                style: Theme.of(context).textTheme.headlineSmall),
            OutlinedButton.icon(
                onPressed:
                    action.busy || action.canRetry ? null : () => _open(null),
                icon: const Icon(Icons.add),
                label: const Text('Yeni kampanya')),
          ]),
      const Text('İzinli kişilere onaylı WhatsApp şablonları gönderin.'),
      const SizedBox(height: 16),
      if (action.error != null) _notice(action.error!, error: true),
      if (action.notice != null && !_dirty) _notice(action.notice!),
      if (action.canRetry)
        Align(
            alignment: Alignment.centerLeft,
            child: FilledButton.icon(
                onPressed: action.busy
                    ? null
                    : () async {
                        if (await _actions.retry() && mounted) _afterSave();
                      },
                icon: const Icon(Icons.refresh),
                label: const Text('Aynı işlemi tekrar dene'))),
      if (action.locked && !action.canRetry && action.error == null)
        _notice(
            'Gönderilmiş kampanyanın alıcıları ve şablon değerleri değiştirilemez. Yeni gönderim için yeni kampanya oluşturun.'),
      options.when(
        loading: () => const LinearProgressIndicator(
            semanticsLabel: 'WhatsApp hesapları ve şablonlar yükleniyor'),
        error: (_, __) =>
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          _notice('WhatsApp hesapları ve şablonlar yüklenemedi.', error: true),
          TextButton(
              onPressed: () =>
                  ref.invalidate(campaignOptionsProvider(widget.tenantId)),
              child: const Text('Tekrar dene')),
        ]),
        data: (data) {
          CampaignConnection? connection;
          for (final item in data.connections) {
            if (item.id == _connectionId ||
                (_connectionId == null &&
                    (item.isDefault || data.connections.length == 1))) {
              connection = item;
            }
          }
          final templates = data.templates
              .where((item) => item.wabaId == connection?.wabaId)
              .toList();
          MessageTemplate? template;
          for (final item in templates) {
            if (item.id == _templateId) template = item;
          }
          final selected = template;
          final inputsKey = selected == null
              ? null
              : (tenantId: widget.tenantId, id: selected.id);
          final inputs = inputsKey == null
              ? null
              : ref.watch(campaignInputsProvider(inputsKey));
          final manifest = inputs?.asData?.value;
          final bindings = <String, dynamic>{
            for (final input in manifest ?? [])
              input.key: _bindings[input.key] ??
                  {
                    'source': input.isMedia ? 'media_link' : 'literal',
                    'value': ''
                  }
          };
          final ready = enabled &&
              selected != null &&
              connection != null &&
              manifest != null;
          final canSend =
              ready && audience.asData != null && audience.asData!.value > 0;
          return Form(
              key: _form,
              child: Column(children: [
                Card(
                    child: Padding(
                        padding: const EdgeInsets.all(20),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Kampanya bilgileri',
                                style: Theme.of(context).textTheme.titleMedium),
                            const SizedBox(height: 12),
                            TextFormField(
                                controller: _name,
                                enabled: enabled,
                                maxLength: 200,
                                decoration: const InputDecoration(
                                    labelText: 'Kampanya adı',
                                    hintText: 'Örnek: Yaz indirimi'),
                                validator: (value) =>
                                    value == null || value.trim().isEmpty
                                        ? 'Kampanya adı girin.'
                                        : null,
                                onChanged: (_) => _dirty = true),
                            const SizedBox(height: 12),
                            DropdownButtonFormField<String>(
                                key: ValueKey(
                                    'connection:$_formVersion:${connection?.id}'),
                                initialValue: connection?.id,
                                isExpanded: true,
                                decoration: const InputDecoration(
                                    labelText: 'Gönderen WhatsApp hesabı'),
                                items: [
                                  for (final item in data.connections)
                                    DropdownMenuItem(
                                        value: item.id,
                                        child: Text(item.label,
                                            overflow: TextOverflow.ellipsis))
                                ],
                                onChanged: enabled
                                    ? (value) => setState(() {
                                          _connectionId = value;
                                          _templateId = null;
                                          _bindings = {};
                                          _dirty = true;
                                        })
                                    : null),
                            if (data.connections.isEmpty)
                              const Padding(
                                  padding: EdgeInsets.only(top: 8),
                                  child: Text(
                                      'Gönderim için bir yönetici bu işletmenin WhatsApp hesabını bağlamalı.')),
                            const SizedBox(height: 20),
                            Text('Kitle filtresi',
                                style: Theme.of(context).textTheme.titleMedium),
                            const SizedBox(height: 12),
                            DropdownButtonFormField<String>(
                                key: ValueKey('preset:$_formVersion'),
                                initialValue: _preset,
                                isExpanded: true,
                                decoration:
                                    const InputDecoration(labelText: 'Kişiler'),
                                items: [
                                  for (final entry in _presets.entries)
                                    DropdownMenuItem(
                                        value: entry.key,
                                        child: Text(entry.value))
                                ],
                                onChanged: enabled
                                    ? (value) => setState(() {
                                          _preset = value!;
                                          _dirty = true;
                                        })
                                    : null),
                            for (final rule in _custom)
                              _AudienceRule(
                                  key: ObjectKey(rule),
                                  rule: rule,
                                  enabled: enabled,
                                  onChanged: () =>
                                      setState(() => _dirty = true),
                                  onRemove: () => setState(() {
                                        _custom.remove(rule);
                                        _dirty = true;
                                      })),
                            TextButton.icon(
                                onPressed: enabled && _custom.length < 20
                                    ? () => setState(() {
                                          _custom.add({
                                            'field': 'Etiket',
                                            'operator': 'icerir',
                                            'value': ''
                                          });
                                          _dirty = true;
                                        })
                                    : null,
                                icon: const Icon(Icons.add),
                                label: const Text('Özel filtre ekle')),
                            audience.when(
                                loading: () =>
                                    const Text('Tahmini erişim hesaplanıyor…'),
                                error: (_, __) => Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          _notice(
                                              'Kitle hesaplanamadı. Filtre değerlerini kontrol edin.',
                                              error: true),
                                          TextButton(
                                              onPressed: () => ref.invalidate(
                                                  campaignAudienceProvider(
                                                      audienceKey)),
                                              child:
                                                  const Text('Tekrar hesapla')),
                                        ]),
                                data: (count) => Text(
                                    'Tahmini erişim: $count kişi. Alıcılar kuyruğa alındığında kesinleşir.')),
                          ],
                        ))),
                const SizedBox(height: 12),
                Card(
                    child: Padding(
                        padding: const EdgeInsets.all(20),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Şablon ve gönderim değerleri',
                                style: Theme.of(context).textTheme.titleMedium),
                            const SizedBox(height: 12),
                            DropdownButtonFormField<String>(
                                key: ValueKey(
                                    'template:$_formVersion:${selected?.id}'),
                                initialValue: selected?.id,
                                isExpanded: true,
                                decoration: const InputDecoration(
                                    labelText: 'Onaylı WhatsApp şablonu'),
                                items: [
                                  for (final item in templates)
                                    DropdownMenuItem(
                                        value: item.id,
                                        child: Text(
                                            '${item.name} · ${item.language}',
                                            overflow: TextOverflow.ellipsis))
                                ],
                                onChanged: enabled
                                    ? (value) => setState(() {
                                          _templateId = value;
                                          _bindings = {};
                                          _dirty = true;
                                        })
                                    : null),
                            if (connection != null && templates.isEmpty)
                              const Padding(
                                  padding: EdgeInsets.only(top: 8),
                                  child: Text(
                                      'Bu hesap için onaylı şablon bulunamadı. Şablonlar ekranından eşitleyin.')),
                            if (selected != null) ...[
                              const SizedBox(height: 12),
                              Text(selected.body),
                              const SizedBox(height: 16),
                              if (inputs?.isLoading == true)
                                const LinearProgressIndicator(
                                    semanticsLabel:
                                        'Şablon değerleri yükleniyor'),
                              if (inputs?.hasError == true) ...[
                                _notice(
                                    'Şablon alanları yüklenemedi. Onay durumunu ve desteklenen şablon türünü kontrol edin.',
                                    error: true),
                                TextButton(
                                    onPressed: () => ref.invalidate(
                                        campaignInputsProvider(inputsKey!)),
                                    child: const Text('Tekrar dene')),
                              ],
                              if (manifest != null)
                                TemplateParameterFields(
                                    key: ValueKey(
                                        'values:$_formVersion:${selected.id}'),
                                    inputs: manifest,
                                    bindings: bindings,
                                    enabled: enabled,
                                    onChanged: (value) => setState(() {
                                          _bindings = value;
                                          _dirty = true;
                                        })),
                            ],
                            const SizedBox(height: 16),
                            Wrap(spacing: 12, runSpacing: 8, children: [
                              TextButton(
                                  onPressed: ready
                                      ? () => _submit(connection!, selected,
                                          bindings, false)
                                      : null,
                                  child: const Text('Taslağı kaydet')),
                              FilledButton(
                                  onPressed: canSend
                                      ? () => _submit(
                                          connection!, selected, bindings, true)
                                      : null,
                                  child: Text(action.busy
                                      ? 'İşlem sürüyor…'
                                      : 'Kampanyayı başlat')),
                            ]),
                            if (action.busy)
                              const Padding(
                                  padding: EdgeInsets.only(top: 8),
                                  child: LinearProgressIndicator()),
                          ],
                        ))),
              ]));
        },
      ),
      if (action.progress != null || action.saved?.queuedAt != null) ...[
        const SizedBox(height: 16),
        CampaignProgressPanel(tenantId: widget.tenantId, campaignId: action.id),
      ],
      const SizedBox(height: 24),
      CampaignHistory(
          tenantId: widget.tenantId, onOpen: action.busy ? null : _open),
    ]);
  }

  Widget _notice(String message, {bool error = false}) => Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Semantics(
          liveRegion: true,
          child: Text(message,
              style: error
                  ? TextStyle(color: Theme.of(context).colorScheme.error)
                  : null)));

  Future<void> _submit(CampaignConnection connection, MessageTemplate template,
      Map<String, dynamic> bindings, bool send) async {
    if (_name.text.trim().isEmpty ||
        (send && !(_form.currentState?.validate() ?? false))) {
      _form.currentState?.validate();
      return;
    }
    final action = ref.read(campaignActionsProvider(widget.tenantId));
    final draft = CampaignDraft(
        id: action.id,
        tenantId: widget.tenantId,
        revision: action.revision,
        name: _name.text.trim(),
        templateId: template.id,
        connectionId: connection.id,
        audienceFilter: _filter,
        templateBindings: bindings);
    if (send) {
      final confirmed = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
                title: const Text('Kampanyayı başlat?'),
                content: Text(
                    '${connection.label} hesabından ${template.name} (${template.language}) gönderilecek. '
                    'Filtreye uyan izinli kişiler gönderim kuyruğuna alınır. Gönderilmiş mesajlar geri alınamaz.'),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(context, false),
                      child: const Text('Vazgeç')),
                  FilledButton(
                      onPressed: () => Navigator.pop(context, true),
                      child: const Text('Kampanyayı başlat'))
                ],
              ));
      if (!mounted || confirmed != true) return;
    }
    if (await _actions.save(draft, send: send) && mounted) _afterSave();
  }

  void _afterSave() {
    setState(() => _dirty = false);
    ref.invalidate(campaignHistoryProvider);
    final action = ref.read(campaignActionsProvider(widget.tenantId));
    ref.invalidate(
        campaignProgressProvider((tenantId: widget.tenantId, id: action.id)));
  }

  Future<void> _open(CampaignDraft? draft) async {
    final action = ref.read(campaignActionsProvider(widget.tenantId));
    if (action.canRetry) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text(
              'Önce sonuçlanmamış işlemi aynı kampanya için tekrar deneyin.')));
      return;
    }
    if (_dirty) {
      final discard = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
                title: const Text('Kaydedilmemiş değişiklikler var'),
                content: const Text(
                    'Bu formdaki değişiklikleri bırakıp seçilen kampanyayı açmak istiyor musunuz?'),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(context, false),
                      child: const Text('Formda kal')),
                  FilledButton(
                      onPressed: () => Navigator.pop(context, true),
                      child: const Text('Değişiklikleri bırak'))
                ],
              ));
      if (!mounted || discard != true) return;
    }
    _actions.open(draft);
    setState(() {
      _formVersion++;
      _dirty = false;
      _name.text = draft?.name ?? '';
      _connectionId = draft?.connectionId;
      _templateId = draft?.templateId;
      _bindings = draft?.templateBindings ?? {};
      final filter = draft?.audienceFilter ?? {};
      final preset = filter['last_contacted'] ?? filter['segment'] ?? 'all';
      _preset = _presets.containsKey(preset) ? preset as String : 'all';
      _custom.clear();
      _custom.addAll((filter['custom'] as List? ?? [])
          .map((item) => Map<String, dynamic>.from(item as Map)));
      if (filter['segment'] != null && _preset != filter['segment']) {
        _custom.add(
            {'field': 'Etiket', 'operator': '=', 'value': filter['segment']});
      }
      if (filter['last_contacted'] != null &&
          _preset != filter['last_contacted']) {
        _custom.add({
          'field': 'Son iletisim',
          'operator': '<',
          'value': (filter['last_contacted'] as String).replaceAll('d', '')
        });
      }
    });
  }
}

class _AudienceRule extends StatelessWidget {
  const _AudienceRule(
      {super.key,
      required this.rule,
      required this.enabled,
      required this.onChanged,
      required this.onRemove});
  final Map<String, dynamic> rule;
  final bool enabled;
  final VoidCallback onChanged, onRemove;
  @override
  Widget build(BuildContext context) {
    final operators =
        rule['field'] == 'Etiket' ? ['=', 'icerir'] : ['=', '>', '<'];
    final field = DropdownButtonFormField<String>(
        initialValue: rule['field'] as String,
        isExpanded: true,
        decoration: const InputDecoration(labelText: 'Alan'),
        items: const [
          DropdownMenuItem(value: 'Etiket', child: Text('Etiket')),
          DropdownMenuItem(value: 'Son iletisim', child: Text('Son iletişim'))
        ],
        onChanged: enabled
            ? (value) {
                rule['field'] = value;
                rule['operator'] = '=';
                onChanged();
              }
            : null);
    final operator = DropdownButtonFormField<String>(
        key: ValueKey('${rule['field']}:${rule['operator']}'),
        initialValue: operators.contains(rule['operator'])
            ? rule['operator'] as String
            : null,
        isExpanded: true,
        decoration: const InputDecoration(labelText: 'Koşul'),
        items: [
          for (final item in operators)
            DropdownMenuItem(
                value: item, child: Text(item == 'icerir' ? 'İçerir' : item))
        ],
        onChanged: enabled
            ? (value) {
                rule['operator'] = value;
                onChanged();
              }
            : null);
    final value = TextFormField(
        initialValue: rule['value'] as String? ?? '',
        enabled: enabled,
        decoration: InputDecoration(
            labelText:
                rule['field'] == 'Etiket' ? 'Etiket değeri' : 'Gün sayısı'),
        onChanged: (value) {
          rule['value'] = value;
          onChanged();
        });
    final remove = IconButton(
        onPressed: enabled ? onRemove : null,
        tooltip: 'Filtreyi kaldır',
        icon: const Icon(Icons.close));
    return Padding(
        padding: const EdgeInsets.only(top: 12),
        child: LayoutBuilder(builder: (context, size) {
          if (size.maxWidth < 640) {
            return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  field,
                  const SizedBox(height: 8),
                  operator,
                  const SizedBox(height: 8),
                  value,
                  Align(alignment: Alignment.centerRight, child: remove)
                ]);
          }
          return Row(children: [
            Expanded(child: field),
            const SizedBox(width: 8),
            SizedBox(width: 120, child: operator),
            const SizedBox(width: 8),
            Expanded(child: value),
            remove
          ]);
        }));
  }
}
