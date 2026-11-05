import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../ui/ui.dart';
import '../../billing/models/billing_overview.dart' show BillingOverview;
import '../../billing/providers/billing_providers.dart';
import '../../templates/models/message_template.dart';
import '../../templates/widgets/inline_notice.dart';
import '../../templates/widgets/template_badges.dart';
import '../../templates/widgets/template_preview_bubble.dart';
import '../../tenancy/providers/tenant_providers.dart';
import '../models/campaign.dart';
import '../models/template_input.dart';
import '../providers/campaign_providers.dart';
import '../widgets/campaign_history.dart';
import '../widgets/campaign_stepper.dart';
import '../widgets/template_parameter_fields.dart';

/// Kampanyalar → Kampanyalar: a numbered composer (template, audience, values,
/// confirm and send), the sent campaign's progress and the campaign history.
class CampaignsScreen extends ConsumerWidget {
  const CampaignsScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tenant = ref.watch(selectedTenantProvider);
    if (tenant == null) {
      return const AppPage(children: [
        EmptyState(
            title: 'İşletme seçin',
            message: 'Kampanya oluşturmak için önce bir işletme seçin.',
            icon: Icons.storefront_outlined),
      ]);
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
  final _sections = List.generate(4, (_) => GlobalKey());
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
  static const _stepLabels = ['Şablon', 'Kitle', 'Değerler', 'Onay ve gönderim'];
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

  /// This month's campaign allowance, for admins (the billing overview is
  /// admin-only); null hides the meter.
  BillingOverview? _plan() {
    final admin =
        ref.watch(currentMembershipProvider).valueOrNull?.isAdmin ?? false;
    if (!admin) return null;
    final overview = ref.watch(billingOverviewProvider).valueOrNull;
    if (overview == null || overview.limits.campaignMessagesMonthly <= 0) {
      return null;
    }
    return overview;
  }

  @override
  Widget build(BuildContext context) {
    final action = ref.watch(campaignActionsProvider(widget.tenantId));
    final options = ref.watch(campaignOptionsProvider(widget.tenantId));
    final audienceKey =
        (tenantId: widget.tenantId, filter: jsonEncode(_filter));
    final audience = ref.watch(campaignAudienceProvider(audienceKey));
    final plan = _plan();
    final c = FlowColors.of(context);
    final theme = Theme.of(context);
    final sent = action.saved?.queuedAt != null || action.progress != null;
    final eyebrow = action.saved == null
        ? 'Yeni kampanya'
        : sent || !action.saved!.editable
            ? 'Gönderilen kampanya'
            : 'Taslak · sürüm ${action.revision}';
    return AppPage(
        toolbar: PageToolbar(
          leading: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Eyebrow(eyebrow, color: c.muted),
                const SizedBox(height: 6),
                Text(
                    _name.text.trim().isEmpty
                        ? 'Adsız kampanya'
                        : _name.text.trim(),
                    style: theme.textTheme.headlineSmall,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis),
              ]),
          actions: [
            OutlinedButton.icon(
                onPressed:
                    action.busy || action.canRetry ? null : () => _open(null),
                icon: const Icon(Icons.add, size: 18),
                label: const Text('Yeni kampanya')),
          ],
        ),
        children: [
          if (action.locked && !action.canRetry && action.error == null)
            const InlineNotice(
                'Gönderilmiş kampanyanın alıcıları ve şablon değerleri değiştirilemez. Yeni gönderim için yeni kampanya oluşturun.',
                tone: FlowTone.info),
          options.when(
            loading: () => const SectionCard(
                child: LinearProgressIndicator(
                    semanticsLabel:
                        'WhatsApp hesapları ve şablonlar yükleniyor')),
            error: (_, __) => ErrorState(
                title: 'Hesaplar ve şablonlar yüklenemedi',
                message:
                    'WhatsApp hesapları ve şablonlar alınamadı. Bağlantınızı kontrol edip tekrar deneyin.',
                onRetry: () =>
                    ref.invalidate(campaignOptionsProvider(widget.tenantId))),
            data: (data) =>
                _composer(context, data, action, audience, audienceKey, plan),
          ),
          if (sent)
            SectionCard(
                child: CampaignProgressPanel(
                    tenantId: widget.tenantId, campaignId: action.id)),
          CampaignHistory(
              tenantId: widget.tenantId, onOpen: action.busy ? null : _open),
        ]);
  }

  Widget _composer(
      BuildContext context,
      CampaignOptions data,
      CampaignActionState action,
      AsyncValue<int> audience,
      ({String tenantId, String filter}) audienceKey,
      BillingOverview? plan) {
    final enabled = !action.busy && !action.locked;
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
    final inputs =
        inputsKey == null ? null : ref.watch(campaignInputsProvider(inputsKey));
    final manifest = inputs?.asData?.value;
    final bindings = <String, dynamic>{
      for (final input in manifest ?? [])
        input.key: _bindings[input.key] ??
            {'source': input.isMedia ? 'media_link' : 'literal', 'value': ''}
    };
    final ready =
        enabled && selected != null && connection != null && manifest != null;
    final count = audience.asData?.value;
    final canSend = ready && count != null && count > 0;
    final sent = action.saved?.queuedAt != null || action.progress != null;
    final valuesDone = manifest != null && _valuesComplete(manifest, bindings);
    final done = [
      _name.text.trim().isNotEmpty && connection != null && selected != null,
      (count ?? 0) > 0,
      valuesDone,
      sent,
    ];
    final current = done.indexOf(false);
    final steps = [
      for (var i = 0; i < 4; i++)
        CampaignStep(
            '0${i + 1}',
            _stepLabels[i],
            done[i]
                ? CampaignStepState.done
                : i == current
                    ? CampaignStepState.current
                    : CampaignStepState.upcoming),
    ];

    final templateSection = CampaignStepSection(
      key: _sections[0],
      number: '01',
      title: 'Şablon ve gönderen',
      subtitle:
          'Kampanyaya bir ad verin, gönderen WhatsApp hesabını ve Meta onaylı şablonu seçin.',
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        TextFormField(
            controller: _name,
            enabled: enabled,
            maxLength: 200,
            decoration: const InputDecoration(
                labelText: 'Kampanya adı', hintText: 'Örnek: Yaz indirimi'),
            validator: (value) => value == null || value.trim().isEmpty
                ? 'Kampanya adı girin.'
                : null,
            onChanged: (_) => setState(() => _dirty = true)),
        const SizedBox(height: FlowSpace.md),
        DropdownButtonFormField<String>(
            key: ValueKey('connection:$_formVersion:${connection?.id}'),
            initialValue: connection?.id,
            isExpanded: true,
            decoration:
                const InputDecoration(labelText: 'Gönderen WhatsApp hesabı'),
            items: [
              for (final item in data.connections)
                DropdownMenuItem(
                    value: item.id,
                    child: Text(item.label, overflow: TextOverflow.ellipsis))
            ],
            onChanged: enabled
                ? (value) => setState(() {
                      _connectionId = value;
                      _templateId = null;
                      _bindings = {};
                      _dirty = true;
                    })
                : null),
        if (data.connections.isEmpty) ...[
          const SizedBox(height: FlowSpace.sm),
          const InlineNotice(
              'Gönderim için bir yönetici bu işletmenin WhatsApp hesabını bağlamalı.',
              tone: FlowTone.warning),
        ],
        const SizedBox(height: FlowSpace.md),
        DropdownButtonFormField<String>(
            key: ValueKey('template:$_formVersion:${selected?.id}'),
            initialValue: selected?.id,
            isExpanded: true,
            decoration:
                const InputDecoration(labelText: 'Onaylı WhatsApp şablonu'),
            items: [
              for (final item in templates)
                DropdownMenuItem(
                    value: item.id,
                    child: Text('${item.name} · ${item.language}',
                        overflow: TextOverflow.ellipsis))
            ],
            onChanged: enabled
                ? (value) => setState(() {
                      _templateId = value;
                      _bindings = {};
                      _dirty = true;
                    })
                : null),
        if (connection != null && templates.isEmpty) ...[
          const SizedBox(height: FlowSpace.sm),
          const InlineNotice(
              'Bu hesap için onaylı şablon bulunamadı. Şablonlar sekmesinden eşitleyin.',
              tone: FlowTone.warning),
        ],
        if (selected != null) ...[
          const SizedBox(height: FlowSpace.lg),
          _TemplateMeta(template: selected),
          const SizedBox(height: FlowSpace.md),
          TemplatePreviewBubble(
            data: TemplatePreviewData.fromTemplate(selected),
            bodyValues: _previewValues(manifest, bindings, 'body'),
            headerValues: _previewValues(manifest, bindings, 'header'),
          ),
        ],
      ]),
    );

    final audienceSection = CampaignStepSection(
      key: _sections[1],
      number: '02',
      title: 'Kime gidecek?',
      subtitle:
          'Yalnızca kayıtlı pazarlama izni olan ve listeden çıkmamış kişiler mesaj alır.',
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        DropdownButtonFormField<String>(
            key: ValueKey('preset:$_formVersion'),
            initialValue: _preset,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'Kişiler'),
            items: [
              for (final entry in _presets.entries)
                DropdownMenuItem(
                    value: entry.key,
                    child: Text(entry.value, overflow: TextOverflow.ellipsis))
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
              onChanged: () => setState(() => _dirty = true),
              onRemove: () => setState(() {
                    _custom.remove(rule);
                    _dirty = true;
                  })),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
              onPressed: enabled && _custom.length < 20
                  ? () => setState(() {
                        _custom.add(
                            {'field': 'Etiket', 'operator': 'icerir', 'value': ''});
                        _dirty = true;
                      })
                  : null,
              icon: const Icon(Icons.add, size: 18),
              label: const Text('Özel filtre ekle')),
        ),
        const SizedBox(height: FlowSpace.sm),
        _AudienceResult(
            audience: audience,
            onRetry: () => ref.invalidate(campaignAudienceProvider(audienceKey))),
      ]),
    );

    final valuesSection = CampaignStepSection(
      key: _sections[2],
      number: '03',
      title: 'Mesajdaki değerler',
      subtitle:
          'Şablondaki boşlukları sabit bir metinle ya da kişinin bilgisiyle doldurun.',
      child: selected == null
          ? Text('Önce bir şablon seçin; doldurulacak değerler burada görünür.',
              style: Theme.of(context).textTheme.bodyMedium)
          : Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              if (inputs?.isLoading == true)
                const LinearProgressIndicator(
                    semanticsLabel: 'Şablon değerleri yükleniyor'),
              if (inputs?.hasError == true)
                InlineNotice(
                    'Şablon alanları yüklenemedi. Onay durumunu ve desteklenen şablon türünü kontrol edin.',
                    tone: FlowTone.danger,
                    action: OutlinedButton.icon(
                        onPressed: () =>
                            ref.invalidate(campaignInputsProvider(inputsKey!)),
                        icon: const Icon(Icons.refresh, size: 18),
                        label: const Text('Tekrar dene'))),
              if (manifest != null)
                TemplateParameterFields(
                    key: ValueKey('values:$_formVersion:${selected.id}'),
                    inputs: manifest,
                    bindings: bindings,
                    enabled: enabled,
                    onChanged: (value) => setState(() {
                          _bindings = value;
                          _dirty = true;
                        })),
            ]),
    );

    final summary = _SummaryPanel(
      key: _sections[3],
      action: action,
      audience: audience,
      plan: plan,
      templateReady: selected != null,
      valuesReady: valuesDone,
      dirty: _dirty,
      onSave: ready
          ? () => _submit(connection!, selected, bindings, false, count)
          : null,
      onSend: canSend
          ? () => _submit(connection!, selected, bindings, true, count)
          : null,
      onRetry: action.busy
          ? null
          : () async {
              if (await _actions.retry() && mounted) _afterSave();
            },
    );

    return Form(
        key: _form,
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          CampaignStepper(steps: steps, onTap: _scrollTo),
          const SizedBox(height: FlowSpace.lg),
          LayoutBuilder(builder: (context, constraints) {
            final column =
                Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              templateSection,
              const SizedBox(height: FlowSpace.lg),
              audienceSection,
              const SizedBox(height: FlowSpace.lg),
              valuesSection,
            ]);
            if (constraints.maxWidth >= 880) {
              return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Expanded(child: column),
                const SizedBox(width: FlowSpace.lg),
                SizedBox(width: 340, child: summary),
              ]);
            }
            return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              column,
              const SizedBox(height: FlowSpace.lg),
              summary,
            ]);
          }),
        ]));
  }

  static bool _valuesComplete(
          List<CampaignTemplateInput> inputs, Map<String, dynamic> bindings) =>
      inputs.every((input) {
        final binding = bindings[input.key];
        if (binding is! Map) return false;
        if (binding['source'] == 'contact') return true;
        final value = binding['value'];
        return value is String && value.trim().isNotEmpty;
      });

  /// Chip labels for the preview: the contact field or the typed value.
  static Map<String, String> _previewValues(List<CampaignTemplateInput>? inputs,
      Map<String, dynamic> bindings, String component) {
    final values = <String, String>{};
    for (final input in inputs ?? const <CampaignTemplateInput>[]) {
      final variable = input.variable;
      if (input.component != component || input.isMedia || variable == null) {
        continue;
      }
      final binding = bindings[input.key];
      if (binding is! Map) continue;
      if (binding['source'] == 'contact') {
        values[variable] = switch (binding['field']) {
          'phone' => 'Telefon',
          'email' => 'E-posta',
          _ => 'Ad soyad',
        };
      } else if (binding['value'] is String &&
          (binding['value'] as String).trim().isNotEmpty) {
        final text = (binding['value'] as String).trim();
        values[variable] = text.length > 32 ? '${text.substring(0, 32)}…' : text;
      }
    }
    return values;
  }

  void _scrollTo(int index) {
    final target = _sections[index].currentContext;
    if (target == null) return;
    Scrollable.ensureVisible(target,
        duration: FlowMotion.reduced(context) ? Duration.zero : FlowMotion.entrance,
        curve: FlowMotion.curve,
        alignment: 0.05);
  }

  Future<void> _submit(CampaignConnection connection, MessageTemplate template,
      Map<String, dynamic> bindings, bool send, int? count) async {
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
      final recipients = count == null
          ? 'Filtreye uyan izinli kişiler'
          : 'Tahmini ${formatCount(count)} izinli kişi';
      final confirmed = await confirmAction(context,
          title: 'Kampanyayı başlat?',
          message:
              '${connection.label} hesabından ${template.name} (${template.language}) gönderilecek. '
              '$recipients gönderim kuyruğuna alınır. Gönderilmiş mesajlar geri alınamaz.',
          confirmLabel: 'Kampanyayı başlat');
      if (!mounted || !confirmed) return;
    }
    if (await _actions.save(draft, send: send) && mounted) _afterSave();
  }

  void _afterSave() {
    setState(() => _dirty = false);
    ref.invalidate(campaignHistoryProvider);
    final action = ref.read(campaignActionsProvider(widget.tenantId));
    ref.invalidate(
        campaignProgressProvider((tenantId: widget.tenantId, id: action.id)));
    // A queued send uses this month's campaign allowance.
    if (action.progress != null) ref.invalidate(billingOverviewProvider);
  }

  Future<void> _open(CampaignDraft? draft) async {
    final action = ref.read(campaignActionsProvider(widget.tenantId));
    if (action.canRetry) {
      showAppSnack(context,
          'Önce sonuçlanmamış işlemi aynı kampanya için tekrar deneyin.',
          error: true);
      return;
    }
    if (_dirty) {
      final discard = await confirmAction(context,
          title: 'Kaydedilmemiş değişiklikler var',
          message:
              'Bu formdaki değişiklikleri bırakıp seçilen kampanyayı açmak istiyor musunuz?',
          confirmLabel: 'Değişiklikleri bırak',
          cancelLabel: 'Formda kal',
          destructive: true);
      if (!mounted || !discard) return;
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

/// Template name in mono with its category, language and review status.
class _TemplateMeta extends StatelessWidget {
  const _TemplateMeta({required this.template});

  final MessageTemplate template;

  @override
  Widget build(BuildContext context) {
    final c = FlowColors.of(context);
    return Wrap(
        spacing: FlowSpace.sm,
        runSpacing: FlowSpace.xs,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Text('ŞABLON', style: FlowText.caps(context, size: 11)),
          Text(template.name,
              style: FlowText.mono(context,
                  size: 14, color: c.text, weight: FontWeight.w500)),
          TemplateCategoryBadge(template.category),
          StatusBadge(templateLanguageLabel(template.language)),
          TemplateStatusBadge(template.status),
        ]);
  }
}

/// The audience estimate inside the Kitle step.
class _AudienceResult extends StatelessWidget {
  const _AudienceResult({required this.audience, required this.onRetry});

  final AsyncValue<int> audience;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final c = FlowColors.of(context);
    final theme = Theme.of(context);
    return audience.when(
        loading: () => Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                  color: c.canvas,
                  borderRadius: FlowRadius.controlAll,
                  border: Border.all(color: c.border)),
              child: Row(children: [
                const SizedBox.square(
                    dimension: 16,
                    child: CircularProgressIndicator(strokeWidth: 2)),
                const SizedBox(width: FlowSpace.md),
                Expanded(
                    child: Text('Tahmini erişim hesaplanıyor…',
                        style: theme.textTheme.bodyMedium)),
              ]),
            ),
        error: (_, __) => InlineNotice(
            'Kitle hesaplanamadı. Filtre değerlerini kontrol edin.',
            tone: FlowTone.danger,
            action: OutlinedButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh, size: 18),
                label: const Text('Tekrar hesapla'))),
        data: (count) => Semantics(
              label: 'Tahmini erişim: $count izinli kişi',
              excludeSemantics: true,
              child: Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                    color: c.canvas,
                    borderRadius: FlowRadius.controlAll,
                    border: Border.all(color: c.border)),
                child: Row(children: [
                  Expanded(
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Filtreye uyan izinli kişi',
                              style: theme.textTheme.titleSmall),
                          const SizedBox(height: 2),
                          Text(
                              'Tahmini; alıcılar kuyruğa alındığında kesinleşir.',
                              style: theme.textTheme.bodySmall),
                        ]),
                  ),
                  const SizedBox(width: FlowSpace.md),
                  Text(formatCount(count),
                      style: FlowText.number(context,
                          size: 32, color: count > 0 ? c.text : c.faint)),
                ]),
              ),
            ));
  }
}

/// Step 04: the recipient count, consent checks, plan usage and the send action.
class _SummaryPanel extends StatelessWidget {
  const _SummaryPanel({
    super.key,
    required this.action,
    required this.audience,
    required this.plan,
    required this.templateReady,
    required this.valuesReady,
    required this.dirty,
    required this.onSave,
    required this.onSend,
    required this.onRetry,
  });

  final CampaignActionState action;
  final AsyncValue<int> audience;
  final BillingOverview? plan;
  final bool templateReady, valuesReady, dirty;
  final VoidCallback? onSave, onSend, onRetry;

  @override
  Widget build(BuildContext context) {
    final c = FlowColors.of(context);
    final theme = Theme.of(context);
    final count = audience.asData?.value;
    final plan = this.plan;
    final used = plan?.usage.campaignMessages ?? 0;
    final limit = plan?.limits.campaignMessagesMonthly ?? 0;
    final adding = count ?? 0;
    final usageLabel = adding > 0
        ? '${formatCount(used)} + ${formatCount(adding)} / ${formatCount(limit)}'
        : '${formatCount(used)} / ${formatCount(limit)}';
    return SectionCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        const Eyebrow('Adım 04 · Özet'),
        const SizedBox(height: 6),
        Semantics(
            header: true,
            child: Text('Onay ve gönderim', style: theme.textTheme.titleLarge)),
        const SizedBox(height: FlowSpace.lg),
        Semantics(
          label: count == null
              ? 'Alıcı sayısı hesaplanıyor'
              : 'Tahmini ${formatCount(count)} kişiye gidecek',
          excludeSemantics: true,
          child: Wrap(
              spacing: 10,
              runSpacing: 4,
              crossAxisAlignment: WrapCrossAlignment.end,
              children: [
                Text(count == null ? '—' : formatCount(count),
                    style: FlowText.number(context,
                        size: 56, color: count == null ? c.faint : c.text)),
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Text(
                      count == null ? 'kişi hesaplanıyor' : 'kişiye gidecek',
                      style: theme.textTheme.bodyLarge?.copyWith(color: c.muted)),
                ),
              ]),
        ),
        const SizedBox(height: FlowSpace.md),
        const CheckLine('Yalnızca kayıtlı pazarlama izni olan kişiler'),
        const CheckLine('Listeden çıkan kişiler otomatik olarak hariç'),
        CheckLine(
            templateReady ? 'Şablon Meta onaylı' : 'Onaylı bir şablon seçin',
            ok: templateReady),
        CheckLine(
            valuesReady
                ? 'Mesajdaki değerler hazır'
                : 'Mesajdaki değerleri doldurun',
            ok: valuesReady),
        const CheckLine('Şablon mesaj ücretini Meta işletmenize faturalar.',
            note: true),
        if (plan != null) ...[
          const SizedBox(height: FlowSpace.md),
          Divider(color: c.border),
          const SizedBox(height: FlowSpace.md),
          // The long "used + adding / limit" label needs room; phones show the total.
          LayoutBuilder(
              builder: (context, constraints) => UsageBar(
                  label: 'Bu ayki kampanya mesajı',
                  value: (used + adding) / limit,
                  valueLabel: constraints.maxWidth >= 290
                      ? usageLabel
                      : '${formatCount(used + adding)} / ${formatCount(limit)}')),
          const SizedBox(height: FlowSpace.sm),
          Text(
              upperTr([
                if (adding > 0) 'Bu gönderim +${formatCount(adding)}',
                plan.planName.isEmpty ? 'Plan' : '${plan.planName} plan',
                'aylık ${formatCount(limit)}',
              ].join(' · ')),
              style: FlowText.caps(context, size: 10, color: c.faint)),
          if (used + adding > limit) ...[
            const SizedBox(height: FlowSpace.sm),
            const InlineNotice(
                'Tahmini alıcı sayısı bu ayki kalan hakkınızdan fazla. Abonelik ekranından planınızı yükseltebilirsiniz.',
                tone: FlowTone.warning),
          ],
        ],
        if (action.error != null) ...[
          const SizedBox(height: FlowSpace.lg),
          InlineNotice(action.error!, tone: FlowTone.danger),
        ],
        if (action.notice != null && !dirty) ...[
          const SizedBox(height: FlowSpace.lg),
          InlineNotice(action.notice!, tone: FlowTone.accent),
        ],
        const SizedBox(height: FlowSpace.lg),
        if (action.canRetry)
          FilledButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh, size: 18),
              label: const Text('Aynı işlemi tekrar dene'))
        else
          FilledButton(
              onPressed: onSend,
              child: Text(action.busy ? 'İşlem sürüyor…' : 'Kampanyayı başlat')),
        const SizedBox(height: FlowSpace.sm),
        OutlinedButton(onPressed: onSave, child: const Text('Taslağı kaydet')),
        if (action.busy) ...[
          const SizedBox(height: FlowSpace.md),
          const LinearProgressIndicator(semanticsLabel: 'Kampanya kaydediliyor'),
        ],
      ]),
    );
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

  static const _tagOperators = {'=': 'Tam eşleşme', 'icerir': 'İçerir'};
  static const _dayOperators = {
    '<': 'Son … gün içinde',
    '>': '… günden önce',
    '=': 'Tam … gün önce',
  };

  @override
  Widget build(BuildContext context) {
    final c = FlowColors.of(context);
    final operators =
        rule['field'] == 'Etiket' ? _tagOperators : _dayOperators;
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
        initialValue: operators.containsKey(rule['operator'])
            ? rule['operator'] as String
            : null,
        isExpanded: true,
        decoration: const InputDecoration(labelText: 'Koşul'),
        items: [
          for (final item in operators.entries)
            DropdownMenuItem(
                value: item.key,
                child: Text(item.value, overflow: TextOverflow.ellipsis))
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
    return Container(
        margin: const EdgeInsets.only(top: FlowSpace.md),
        padding: const EdgeInsets.all(FlowSpace.md),
        decoration: BoxDecoration(
            borderRadius: FlowRadius.controlAll,
            border: Border.all(color: c.border)),
        child: LayoutBuilder(builder: (context, size) {
          if (size.maxWidth < 600) {
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
            SizedBox(width: 180, child: operator),
            const SizedBox(width: 8),
            Expanded(child: value),
            remove
          ]);
        }));
  }
}
