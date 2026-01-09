import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/bot_config.dart';

class SupabaseBotRepository {
  SupabaseBotRepository(this._client);

  final SupabaseClient _client;

  Future<BotConfig> fetchBotConfig(String tenantId) async {
    final response = await _client
        .from('bot_settings')
        .select()
        .eq('tenant_id', tenantId)
        .maybeSingle();

    if (response == null) {
      final defaults = BotConfig.defaults();
      await saveBotConfig(tenantId, defaults);
      return defaults;
    }

    return _fromRow(response);
  }

  Future<void> saveBotConfig(String tenantId, BotConfig config) async {
    await _client.from('bot_settings').upsert({
      'tenant_id': tenantId,
      'name': config.name,
      'tone': config.tone,
      'language': config.language,
      'system_prompt': config.systemPrompt,
      'model': config.model,
      'temperature': config.temperature,
      'memory_hours': config.memoryHours,
      'max_history_messages': config.maxHistoryMessages,
      'is_active': config.isActive,
      'updated_at': DateTime.now().toIso8601String(),
    });
  }

  BotConfig _fromRow(Map<String, dynamic> row) {
    return BotConfig(
      name: row['name'] as String? ?? 'Ava',
      tone: row['tone'] as String? ?? 'Profesyonel ve net',
      language: row['language'] as String? ?? 'Turkce',
      systemPrompt:
          row['system_prompt'] as String? ??
              'Kisa, profesyonel bir musteri temsilcisi gibi yanit ver.',
      model: row['model'] as String? ?? 'gpt-4o-mini',
      temperature: (row['temperature'] as num?)?.toDouble() ?? 0.3,
      memoryHours: (row['memory_hours'] as int?) ?? 6,
      maxHistoryMessages: (row['max_history_messages'] as int?) ?? 12,
      isActive: row['is_active'] as bool? ?? true,
    );
  }
}
