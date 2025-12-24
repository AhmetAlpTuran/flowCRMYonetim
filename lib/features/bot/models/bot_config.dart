class BotConfig {
  const BotConfig({
    required this.name,
    required this.tone,
    required this.language,
    required this.isActive,
  });

  final String name;
  final String tone;
  final String language;
  final bool isActive;
}