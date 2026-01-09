import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../tenancy/providers/tenant_providers.dart';
import '../models/bot_config.dart';
import '../providers/bot_providers.dart';

class BotScreen extends ConsumerStatefulWidget {
  const BotScreen({super.key});

  @override
  ConsumerState<BotScreen> createState() => _BotScreenState();
}

class _BotScreenState extends ConsumerState<BotScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _toneController = TextEditingController();
  final _languageController = TextEditingController();
  final _promptController = TextEditingController();
  bool _isActive = true;
  double _temperature = 0.3;
  String _model = 'gpt-4o-mini';
  int _memoryHours = 6;
  int _maxHistoryMessages = 12;
  BotConfig? _current;

  @override
  void dispose() {
    _nameController.dispose();
    _toneController.dispose();
    _languageController.dispose();
    _promptController.dispose();
    super.dispose();
  }

  bool _sameConfig(BotConfig a, BotConfig b) {
    return a.name == b.name &&
        a.tone == b.tone &&
        a.language == b.language &&
        a.systemPrompt == b.systemPrompt &&
        a.model == b.model &&
        a.temperature == b.temperature &&
        a.isActive == b.isActive;
  }

  void _syncFromConfig(BotConfig config) {
    if (_current != null && _sameConfig(_current!, config)) {
      return;
    }
    _current = config;
    _nameController.text = config.name;
    _toneController.text = config.tone;
    _languageController.text = config.language;
    _promptController.text = config.systemPrompt;
    _isActive = config.isActive;
    _temperature = config.temperature;
    _model = config.model;
    _memoryHours = config.memoryHours;
    _maxHistoryMessages = config.maxHistoryMessages;
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) {
      return;
    }
    final tenant = ref.read(selectedTenantProvider);
    if (tenant == null) {
      return;
    }
    final repository = ref.read(botRepositoryProvider);
    final config = BotConfig(
      name: _nameController.text.trim(),
      tone: _toneController.text.trim(),
      language: _languageController.text.trim(),
      systemPrompt: _promptController.text.trim(),
      model: _model,
      temperature: _temperature,
      memoryHours: _memoryHours,
      maxHistoryMessages: _maxHistoryMessages,
      isActive: _isActive,
    );
    await repository.saveBotConfig(tenant.id, config);
    ref.invalidate(botConfigProvider);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Bot ayarlari kaydedildi.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final config = ref.watch(botConfigProvider);

    return config.when(
      data: (bot) {
        _syncFromConfig(bot);
        return Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Card(
                elevation: 0,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Bot kimligi',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _nameController,
                        decoration: const InputDecoration(
                          labelText: 'Bot adi',
                          prefixIcon: Icon(Icons.smart_toy_outlined),
                        ),
                        validator: (value) {
                          if (value == null || value.trim().isEmpty) {
                            return 'Bot adi zorunludur.';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _toneController,
                        decoration: const InputDecoration(
                          labelText: 'Ton',
                          prefixIcon: Icon(Icons.tune_outlined),
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _languageController,
                        decoration: const InputDecoration(
                          labelText: 'Dil',
                          prefixIcon: Icon(Icons.language_outlined),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Card(
                elevation: 0,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'AI ayarlari',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _promptController,
                        maxLines: 4,
                        decoration: const InputDecoration(
                          labelText: 'System prompt',
                          alignLabelWithHint: true,
                          prefixIcon: Icon(Icons.text_snippet_outlined),
                        ),
                        validator: (value) {
                          if (value == null || value.trim().isEmpty) {
                            return 'Prompt zorunludur.';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 12),
                      DropdownButtonFormField<String>(
                        value: _model,
                        decoration: const InputDecoration(
                          labelText: 'Model',
                          prefixIcon: Icon(Icons.auto_awesome_outlined),
                        ),
                        items: const [
                          DropdownMenuItem(
                            value: 'gpt-4o-mini',
                            child: Text('gpt-4o-mini'),
                          ),
                        ],
                        onChanged: (value) {
                          if (value == null) {
                            return;
                          }
                          setState(() => _model = value);
                        },
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'Yaraticilik (temperature): ${_temperature.toStringAsFixed(2)}',
                        style: Theme.of(context).textTheme.labelLarge,
                      ),
                      Slider(
                        value: _temperature,
                        min: 0,
                        max: 1,
                        divisions: 10,
                        onChanged: (value) {
                          setState(() => _temperature = value);
                        },
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'Hafiza suresi (saat): $_memoryHours',
                        style: Theme.of(context).textTheme.labelLarge,
                      ),
                      Slider(
                        value: _memoryHours.toDouble(),
                        min: 1,
                        max: 24,
                        divisions: 23,
                        label: '$_memoryHours',
                        onChanged: (value) {
                          setState(() => _memoryHours = value.round());
                        },
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'Hafizada tutulacak mesaj: $_maxHistoryMessages',
                        style: Theme.of(context).textTheme.labelLarge,
                      ),
                      Slider(
                        value: _maxHistoryMessages.toDouble(),
                        min: 4,
                        max: 40,
                        divisions: 9,
                        label: '$_maxHistoryMessages',
                        onChanged: (value) {
                          setState(() => _maxHistoryMessages = value.round());
                        },
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Card(
                elevation: 0,
                child: SwitchListTile(
                  value: _isActive,
                  onChanged: (value) => setState(() => _isActive = value),
                  title: const Text('Bot aktif'),
                  secondary: const Icon(Icons.power_settings_new_outlined),
                ),
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: _save,
                icon: const Icon(Icons.save_outlined),
                label: const Text('Kaydet'),
              ),
            ],
          ),
        );
      },
      error: (error, _) => Center(
        child: Text('Bot ayarlari yuklenemedi: $error'),
      ),
      loading: () => const Center(child: CircularProgressIndicator()),
    );
  }
}
