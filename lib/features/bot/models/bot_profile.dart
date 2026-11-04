import 'bot_config.dart';

/// An extra bot (`bot_profiles`). The main bot lives in `bot_settings`.
class BotProfile {
  const BotProfile({required this.id, required this.config});

  factory BotProfile.fromRow(Map<String, dynamic> row) => BotProfile(
        id: row['id'] as String,
        config: BotConfig(
          name: row['name'] as String? ?? '',
          tone: row['tone'] as String? ?? '',
          language: row['language'] as String? ?? '',
          systemPrompt: row['system_prompt'] as String? ?? '',
          model: row['model'] as String? ?? 'gpt-4o-mini',
          temperature: (row['temperature'] as num?)?.toDouble() ?? 0.3,
          memoryHours: (row['memory_hours'] as num?)?.toInt() ?? 6,
          maxHistoryMessages: (row['max_history_messages'] as num?)?.toInt() ?? 12,
          isActive: row['is_active'] as bool? ?? false,
        ),
      );

  final String id;
  final BotConfig config;
}

/// A WhatsApp number and the bot answering on it.
class BotNumber {
  const BotNumber({
    required this.id,
    required this.displayPhone,
    required this.verifiedName,
    required this.botEnabled,
    this.botProfileId,
  });

  factory BotNumber.fromRow(Map<String, dynamic> row) => BotNumber(
        id: row['id'] as String,
        displayPhone: row['display_phone_number'] as String? ?? '',
        verifiedName: row['verified_name'] as String? ?? '',
        botEnabled: row['bot_enabled'] as bool? ?? true,
        botProfileId: row['bot_profile_id'] as String?,
      );

  final String id;
  final String displayPhone;
  final String verifiedName;
  final bool botEnabled;

  /// Null means the main bot.
  final String? botProfileId;

  String get title => verifiedName.trim().isNotEmpty ? verifiedName : displayPhone;

  /// Dropdown key: `main`, `off` or the extra bot's ID.
  String get assignment => !botEnabled ? 'off' : (botProfileId ?? 'main');
}
