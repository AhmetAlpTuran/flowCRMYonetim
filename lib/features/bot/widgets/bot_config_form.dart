import 'package:flutter/material.dart';

import '../models/bot_config.dart';

/// Name, tone, language, instructions, model and memory of one bot (main or extra).
class BotConfigForm extends StatefulWidget {
  const BotConfigForm({super.key, required this.initial, required this.onSave, this.header});

  final BotConfig initial;
  final Future<void> Function(BotConfig config) onSave;
  final Widget? header;

  @override
  State<BotConfigForm> createState() => _BotConfigFormState();
}

class _BotConfigFormState extends State<BotConfigForm> {
  final _formKey = GlobalKey<FormState>();
  late final _name = TextEditingController(text: widget.initial.name);
  late final _tone = TextEditingController(text: widget.initial.tone);
  late final _language = TextEditingController(text: widget.initial.language);
  late final _prompt = TextEditingController(text: widget.initial.systemPrompt);
  late bool _isActive = widget.initial.isActive;
  late double _temperature = widget.initial.temperature.clamp(0, 1).toDouble();
  late String _model = widget.initial.model;
  late int _memoryHours = widget.initial.memoryHours.clamp(1, 24);
  late int _maxHistoryMessages = widget.initial.maxHistoryMessages.clamp(4, 40);
  bool _saving = false;

  @override
  void dispose() {
    _name.dispose();
    _tone.dispose();
    _language.dispose();
    _prompt.dispose();
    super.dispose();
  }

  String? _required(String? value, String message) =>
      value == null || value.trim().isEmpty ? message : null;

  Future<void> _save() async {
    if (_saving || !(_formKey.currentState?.validate() ?? false)) return;
    setState(() => _saving = true);
    try {
      await widget.onSave(BotConfig(
        name: _name.text.trim(),
        tone: _tone.text.trim(),
        language: _language.text.trim(),
        systemPrompt: _prompt.text.trim(),
        model: _model,
        temperature: _temperature,
        memoryHours: _memoryHours,
        maxHistoryMessages: _maxHistoryMessages,
        isActive: _isActive,
      ));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Form(
      key: _formKey,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (widget.header != null) widget.header!,
          Card(
            elevation: 0,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Bot kimliği', style: text.titleMedium),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _name,
                  maxLength: 80,
                  decoration: const InputDecoration(labelText: 'Bot adı', prefixIcon: Icon(Icons.smart_toy_outlined)),
                  validator: (v) => _required(v, 'Bot adı zorunludur.'),
                ),
                const SizedBox(height: 4),
                TextFormField(
                  controller: _tone,
                  maxLength: 200,
                  decoration: const InputDecoration(labelText: 'Ton', prefixIcon: Icon(Icons.tune_outlined)),
                  validator: (v) => _required(v, 'Ton zorunludur.'),
                ),
                const SizedBox(height: 4),
                TextFormField(
                  controller: _language,
                  maxLength: 80,
                  decoration: const InputDecoration(labelText: 'Dil', prefixIcon: Icon(Icons.language_outlined)),
                  validator: (v) => _required(v, 'Dil zorunludur.'),
                ),
              ]),
            ),
          ),
          const SizedBox(height: 12),
          Card(
            elevation: 0,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('AI ayarları', style: text.titleMedium),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _prompt,
                  maxLines: 5,
                  maxLength: 8000,
                  decoration: const InputDecoration(
                    labelText: 'Talimatlar',
                    helperText: 'Botun nasıl davranacağını ve neleri yapmayacağını yazın.',
                    alignLabelWithHint: true,
                    prefixIcon: Icon(Icons.text_snippet_outlined),
                  ),
                  validator: (v) => _required(v, 'Talimat zorunludur.'),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: _model,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Model', prefixIcon: Icon(Icons.auto_awesome_outlined)),
                  items: {'gpt-4o-mini', _model}
                      .map((m) => DropdownMenuItem(value: m, child: Text(m)))
                      .toList(),
                  onChanged: (value) {
                    if (value != null) setState(() => _model = value);
                  },
                ),
                const SizedBox(height: 12),
                Text('Yaratıcılık: ${_temperature.toStringAsFixed(1)}', style: text.labelLarge),
                Slider(
                  value: _temperature,
                  max: 1,
                  divisions: 10,
                  onChanged: (value) => setState(() => _temperature = value),
                ),
                Text('Hafıza süresi: $_memoryHours saat', style: text.labelLarge),
                Slider(
                  value: _memoryHours.toDouble(),
                  min: 1,
                  max: 24,
                  divisions: 23,
                  label: '$_memoryHours',
                  onChanged: (value) => setState(() => _memoryHours = value.round()),
                ),
                Text('Hafızada tutulacak mesaj: $_maxHistoryMessages', style: text.labelLarge),
                Slider(
                  value: _maxHistoryMessages.toDouble(),
                  min: 4,
                  max: 40,
                  divisions: 9,
                  label: '$_maxHistoryMessages',
                  onChanged: (value) => setState(() => _maxHistoryMessages = value.round()),
                ),
              ]),
            ),
          ),
          const SizedBox(height: 12),
          Card(
            elevation: 0,
            child: SwitchListTile(
              value: _isActive,
              onChanged: (value) => setState(() => _isActive = value),
              title: const Text('Bot aktif'),
              subtitle: const Text('Kapalıyken bu botun numaralarındaki mesajları temsilciler yanıtlar.'),
              secondary: const Icon(Icons.power_settings_new_outlined),
            ),
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: _saving ? null : _save,
            icon: _saving
                ? const SizedBox.square(dimension: 16, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.save_outlined),
            label: const Text('Kaydet'),
          ),
        ],
      ),
    );
  }
}
