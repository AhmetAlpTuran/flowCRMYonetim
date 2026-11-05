import 'package:flutter/material.dart';

import '../../../ui/ui.dart';
import '../models/bot_config.dart';

/// Quick picks for the free-text tone and language fields.
const botTonePresets = ['Samimi ve sıcak', 'Profesyonel ve net', 'Sakin ve kısa'];
const botLanguagePresets = ['Türkçe', 'Müşterinin dilinde'];

/// Field limits enforced by `bot_settings` and `save_bot_profile`.
const botNameMaxLength = 80;
const botToneMaxLength = 200;
const botLanguageMaxLength = 80;
const botInstructionsMaxLength = 8000;

/// One assistant's settings (main or extra): name, tone, reply language, instructions,
/// on/off and the advanced memory settings. Switching the assistant on or off only
/// takes effect when the form is saved.
class BotConfigForm extends StatefulWidget {
  const BotConfigForm({
    super.key,
    required this.initial,
    required this.onSave,
    this.header,
    this.kindLabel,
    this.headerAction,
    this.onCancel,
    this.onDirtyChanged,
    this.saveLabel = 'Değişiklikleri kaydet',
    this.emptyTitle = 'Yeni asistan',
  });

  final BotConfig initial;
  final Future<void> Function(BotConfig config) onSave;

  /// Shown above the settings card.
  final Widget? header;

  /// Small caps line under the name, such as "Ana asistan".
  final String? kindLabel;

  /// Placed after the on/off switch, such as a delete button.
  final Widget? headerAction;

  /// Shows "Vazgeç" when set.
  final VoidCallback? onCancel;

  /// Reports whether the fields differ from [initial].
  final ValueChanged<bool>? onDirtyChanged;
  final String saveLabel;

  /// Heading while the name field is empty.
  final String emptyTitle;

  @override
  State<BotConfigForm> createState() => _BotConfigFormState();
}

class _BotConfigFormState extends State<BotConfigForm> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _tone = TextEditingController();
  final _language = TextEditingController();
  final _prompt = TextEditingController();
  late bool _isActive;
  late double _temperature;
  late String _model;
  late int _memoryHours;
  late int _maxHistoryMessages;
  late BotConfig _baseline;
  bool _saving = false;
  bool _dirty = false;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _load(widget.initial);
    for (final controller in [_name, _tone, _language, _prompt]) {
      controller.addListener(_changed);
    }
  }

  @override
  void didUpdateWidget(BotConfigForm oldWidget) {
    super.didUpdateWidget(oldWidget);
    final next = _normalized(widget.initial);
    if (_same(_normalized(oldWidget.initial), next)) return;
    // Fresh server values replace untouched fields; edits in progress are kept.
    if (_dirty) {
      _baseline = next;
    } else {
      _load(widget.initial);
    }
    final dirty = !_same(_current, _baseline);
    if (dirty != _dirty) {
      _dirty = dirty;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) widget.onDirtyChanged?.call(_dirty);
      });
    }
  }

  @override
  void dispose() {
    _name.dispose();
    _tone.dispose();
    _language.dispose();
    _prompt.dispose();
    super.dispose();
  }

  static BotConfig _normalized(BotConfig config) => config.copyWith(
        name: config.name.trim(),
        tone: config.tone.trim(),
        language: config.language.trim(),
        systemPrompt: config.systemPrompt.trim(),
        temperature: config.temperature.clamp(0, 1).toDouble(),
        memoryHours: config.memoryHours.clamp(1, 24),
        maxHistoryMessages: config.maxHistoryMessages.clamp(4, 40),
      );

  static bool _same(BotConfig a, BotConfig b) =>
      a.name == b.name &&
      a.tone == b.tone &&
      a.language == b.language &&
      a.systemPrompt == b.systemPrompt &&
      a.model == b.model &&
      a.temperature == b.temperature &&
      a.memoryHours == b.memoryHours &&
      a.maxHistoryMessages == b.maxHistoryMessages &&
      a.isActive == b.isActive;

  void _load(BotConfig config) {
    final value = _normalized(config);
    _loading = true;
    _name.text = config.name;
    _tone.text = config.tone;
    _language.text = config.language;
    _prompt.text = config.systemPrompt;
    _loading = false;
    _isActive = value.isActive;
    _temperature = value.temperature;
    _model = value.model;
    _memoryHours = value.memoryHours;
    _maxHistoryMessages = value.maxHistoryMessages;
    _baseline = value;
    _dirty = false;
  }

  BotConfig get _current => BotConfig(
        name: _name.text.trim(),
        tone: _tone.text.trim(),
        language: _language.text.trim(),
        systemPrompt: _prompt.text.trim(),
        model: _model,
        temperature: _temperature,
        memoryHours: _memoryHours,
        maxHistoryMessages: _maxHistoryMessages,
        isActive: _isActive,
      );

  void _changed() {
    if (_loading || !mounted) return;
    final dirty = !_same(_current, _baseline);
    if (dirty != _dirty) {
      _dirty = dirty;
      widget.onDirtyChanged?.call(dirty);
    }
    setState(() {});
  }

  void _update(VoidCallback change) {
    setState(change);
    _changed();
  }

  String? _required(String? value, String message) => value == null || value.trim().isEmpty ? message : null;

  Future<void> _save() async {
    if (_saving || !(_formKey.currentState?.validate() ?? false)) return;
    setState(() => _saving = true);
    try {
      await widget.onSave(_current);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  static Widget? _noCounter(BuildContext context,
          {required int currentLength, required int? maxLength, required bool isFocused}) =>
      null;

  @override
  Widget build(BuildContext context) {
    final c = FlowColors.of(context);
    final theme = Theme.of(context);
    final name = _name.text.trim();
    return Form(
      key: _formKey,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        if (widget.header != null) ...[widget.header!, const SizedBox(height: FlowSpace.lg)],
        SectionCard(
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            LayoutBuilder(builder: (context, constraints) {
              final heading = Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(
                  name.isEmpty ? widget.emptyTitle : name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.headlineSmall,
                ),
                if (widget.kindLabel != null) ...[
                  const SizedBox(height: 4),
                  Text(upperTr(widget.kindLabel!), style: FlowText.caps(context, size: 10)),
                ],
              ]);
              final toggle = _ActiveSwitch(value: _isActive, onChanged: (value) => _update(() => _isActive = value));
              final action = widget.headerAction;
              if (constraints.maxWidth >= 520) {
                return Row(children: [
                  Expanded(child: heading),
                  const SizedBox(width: FlowSpace.md),
                  ConstrainedBox(constraints: BoxConstraints(maxWidth: constraints.maxWidth / 2), child: toggle),
                  if (action != null) ...[const SizedBox(width: FlowSpace.xs), action],
                ]);
              }
              return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Expanded(child: heading),
                  if (action != null) ...[const SizedBox(width: FlowSpace.xs), action],
                ]),
                const SizedBox(height: FlowSpace.md),
                Align(alignment: Alignment.centerLeft, child: toggle),
              ]);
            }),
            const SizedBox(height: FlowSpace.sm),
            Text(
              'Kapalıyken bu asistanın numaralarına gelen mesajları ekibiniz yanıtlar. '
              'Açıp kapatmak, kaydettiğinizde geçerli olur.',
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: FlowSpace.xl),
            LayoutBuilder(builder: (context, constraints) {
              final nameField = TextFormField(
                controller: _name,
                maxLength: botNameMaxLength,
                buildCounter: _noCounter,
                textInputAction: TextInputAction.next,
                decoration: const InputDecoration(labelText: 'Asistanın adı', hintText: 'Örneğin Ava'),
                validator: (v) => _required(v, 'Asistanın adı boş olamaz.'),
              );
              final toneField = Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                TextFormField(
                  controller: _tone,
                  maxLength: botToneMaxLength,
                  buildCounter: _noCounter,
                  textInputAction: TextInputAction.next,
                  decoration: const InputDecoration(labelText: 'Ton'),
                  validator: (v) => _required(v, 'Ton boş olamaz.'),
                ),
                const SizedBox(height: FlowSpace.sm),
                _Presets(label: 'Ton önerileri', options: botTonePresets, controller: _tone),
              ]);
              final languageField = Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                TextFormField(
                  controller: _language,
                  maxLength: botLanguageMaxLength,
                  buildCounter: _noCounter,
                  textInputAction: TextInputAction.next,
                  decoration: const InputDecoration(labelText: 'Yanıt dili'),
                  validator: (v) => _required(v, 'Yanıt dili boş olamaz.'),
                ),
                const SizedBox(height: FlowSpace.sm),
                _Presets(label: 'Dil önerileri', options: botLanguagePresets, controller: _language),
              ]);
              const gap = SizedBox.square(dimension: FlowSpace.lg);
              // Phones stack the fields; wider forms pair name and language and give the
              // tone a full row so its suggestions stay on one line.
              if (constraints.maxWidth < 440) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [nameField, gap, toneField, gap, languageField],
                );
              }
              return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Expanded(child: nameField),
                  gap,
                  Expanded(child: languageField),
                ]),
                gap,
                toneField,
              ]);
            }),
            const SizedBox(height: FlowSpace.xl),
            TextFormField(
              controller: _prompt,
              minLines: 5,
              maxLines: 12,
              maxLength: botInstructionsMaxLength,
              keyboardType: TextInputType.multiline,
              decoration: const InputDecoration(
                labelText: 'Talimatlar',
                helperText: 'Asistana ne yapmasını ve neyi yapmamasını, bir çalışana anlatır gibi yazın.',
                helperMaxLines: 3,
                alignLabelWithHint: true,
              ),
              buildCounter: (context, {required currentLength, required maxLength, required isFocused}) => Text(
                '${formatCount(currentLength)} / ${formatCount(maxLength ?? botInstructionsMaxLength)}',
                style: FlowText.mono(context, size: 11, color: c.faint),
              ),
              validator: (v) => _required(v, 'Talimatlar boş olamaz.'),
            ),
            const SizedBox(height: FlowSpace.sm),
            ExpansionTile(
              tilePadding: EdgeInsets.zero,
              childrenPadding: const EdgeInsets.only(bottom: FlowSpace.sm),
              expandedCrossAxisAlignment: CrossAxisAlignment.stretch,
              title: Text('Gelişmiş ayarlar', style: theme.textTheme.titleSmall),
              subtitle: Text('Yaratıcılık, sohbet hafızası ve yapay zekâ modeli', style: theme.textTheme.bodySmall),
              children: [
                _SliderRow(
                  label: 'Yaratıcılık',
                  value: _temperature.toStringAsFixed(1).replaceAll('.', ','),
                  helper: 'Düşük değer daha tutarlı, yüksek değer daha serbest yanıtlar verir.',
                  slider: Slider(
                    value: _temperature,
                    max: 1,
                    divisions: 10,
                    label: _temperature.toStringAsFixed(1).replaceAll('.', ','),
                    onChanged: (value) => _update(() => _temperature = value),
                  ),
                ),
                _SliderRow(
                  label: 'Sohbeti hatırlama süresi',
                  value: '$_memoryHours saat',
                  helper: 'Bu süreden eski mesajlar yanıt yazılırken dikkate alınmaz.',
                  slider: Slider(
                    value: _memoryHours.toDouble(),
                    min: 1,
                    max: 24,
                    divisions: 23,
                    label: '$_memoryHours saat',
                    onChanged: (value) => _update(() => _memoryHours = value.round()),
                  ),
                ),
                _SliderRow(
                  label: 'Hatırlanan mesaj sayısı',
                  value: '$_maxHistoryMessages mesaj',
                  helper: 'Yanıt yazılırken okunan son mesaj sayısı.',
                  slider: Slider(
                    value: _maxHistoryMessages.toDouble(),
                    min: 4,
                    max: 40,
                    divisions: 9,
                    label: '$_maxHistoryMessages mesaj',
                    onChanged: (value) => _update(() => _maxHistoryMessages = value.round()),
                  ),
                ),
                const SizedBox(height: FlowSpace.xl),
                DropdownButtonFormField<String>(
                  initialValue: _model,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Yapay zekâ modeli'),
                  items: [
                    for (final model in {'gpt-4o-mini', _model})
                      DropdownMenuItem(
                        value: model,
                        child: Text(model, style: FlowText.mono(context, size: 14, color: c.text)),
                      ),
                  ],
                  onChanged: (value) {
                    if (value != null) _update(() => _model = value);
                  },
                ),
              ],
            ),
            const SizedBox(height: FlowSpace.md),
            Divider(height: 1, color: c.border),
            const SizedBox(height: FlowSpace.lg),
            Wrap(
              alignment: WrapAlignment.end,
              spacing: FlowSpace.sm,
              runSpacing: FlowSpace.sm,
              children: [
                if (widget.onCancel != null)
                  TextButton(
                    onPressed: _saving ? null : widget.onCancel,
                    style: TextButton.styleFrom(foregroundColor: c.muted),
                    child: const Text('Vazgeç'),
                  ),
                FilledButton(
                  onPressed: _saving ? null : _save,
                  child: _saving
                      ? const Row(mainAxisSize: MainAxisSize.min, children: [
                          SizedBox.square(dimension: 16, child: CircularProgressIndicator(strokeWidth: 2)),
                          SizedBox(width: FlowSpace.sm),
                          Text('Kaydediliyor…'),
                        ])
                      : Text(widget.saveLabel),
                ),
              ],
            ),
          ]),
        ),
      ]),
    );
  }
}

/// The on/off switch in a pill with its label, as in the approved design.
class _ActiveSwitch extends StatelessWidget {
  const _ActiveSwitch({required this.value, required this.onChanged});

  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final c = FlowColors.of(context);
    const shape = StadiumBorder();
    return MergeSemantics(
      child: Material(
        color: c.canvas,
        shape: shape.copyWith(side: BorderSide(color: c.borderStrong)),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          customBorder: shape,
          onTap: () => onChanged(!value),
          child: Padding(
            padding: const EdgeInsets.only(left: 2, right: 14),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Switch(value: value, onChanged: onChanged),
              const SizedBox(width: 2),
              Flexible(
                child: Text(
                  value ? 'Asistan açık' : 'Asistan kapalı',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.labelLarge,
                ),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}

/// Suggested values that fill a free-text field; the field stays editable.
class _Presets extends StatelessWidget {
  const _Presets({required this.label, required this.options, required this.controller});

  final String label;
  final List<String> options;
  final TextEditingController controller;

  @override
  Widget build(BuildContext context) {
    final current = controller.text.trim();
    return Semantics(
      label: label,
      container: true,
      child: Wrap(spacing: 6, runSpacing: 6, children: [
        for (final option in options)
          ChoiceChip(
            label: Text(option),
            selected: current == option,
            onSelected: (_) => controller.text = option,
          ),
      ]),
    );
  }
}

/// A labelled slider with its value in mono and one line of explanation.
class _SliderRow extends StatelessWidget {
  const _SliderRow({required this.label, required this.value, required this.helper, required this.slider});

  final String label;
  final String value;
  final String helper;
  final Widget slider;

  @override
  Widget build(BuildContext context) {
    final c = FlowColors.of(context);
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: FlowSpace.lg),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Expanded(child: Text(label, style: theme.textTheme.labelLarge)),
          Text(upperTr(value), style: FlowText.mono(context, color: c.text, weight: FontWeight.w500)),
        ]),
        slider,
        Text(helper, style: theme.textTheme.bodySmall),
      ]),
    );
  }
}
