class BotConfig {
  const BotConfig({
    required this.name,
    required this.tone,
    required this.language,
    required this.systemPrompt,
    required this.model,
    required this.temperature,
    required this.memoryHours,
    required this.maxHistoryMessages,
    required this.isActive,
  });

  final String name;
  final String tone;
  final String language;
  final String systemPrompt;
  final String model;
  final double temperature;
  final int memoryHours;
  final int maxHistoryMessages;
  final bool isActive;

  BotConfig copyWith({
    String? name,
    String? tone,
    String? language,
    String? systemPrompt,
    String? model,
    double? temperature,
    int? memoryHours,
    int? maxHistoryMessages,
    bool? isActive,
  }) {
    return BotConfig(
      name: name ?? this.name,
      tone: tone ?? this.tone,
      language: language ?? this.language,
      systemPrompt: systemPrompt ?? this.systemPrompt,
      model: model ?? this.model,
      temperature: temperature ?? this.temperature,
      memoryHours: memoryHours ?? this.memoryHours,
      maxHistoryMessages: maxHistoryMessages ?? this.maxHistoryMessages,
      isActive: isActive ?? this.isActive,
    );
  }

  static BotConfig defaults() {
    return const BotConfig(
      name: 'Ava',
      tone: 'Profesyonel ve net',
      language: 'Turkce',
      systemPrompt: 'Kisa, profesyonel bir musteri temsilcisi gibi yanit ver.',
      model: 'gpt-4o-mini',
      temperature: 0.3,
      memoryHours: 6,
      maxHistoryMessages: 12,
      isActive: true,
    );
  }
}
