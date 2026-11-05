import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../../billing/plan_limit.dart';
import '../models/bot_config.dart';
import '../models/bot_profile.dart';

/// Turkish guidance for bot failures; raw server text is never shown.
String botErrorMessage(Object error) {
  final limit = planLimitKind(error);
  if (limit != null) return planLimitMessage(limit == 'plan' ? 'bots' : limit);
  if (error is PostgrestException) {
    if (error.hint == 'bot_limit') return 'En fazla 10 ek bot oluşturabilirsiniz.';
    switch (error.code) {
      case '42501':
        return 'Bu işlem için yetkiniz yok.';
      case '22023':
        return 'Bilgileri kontrol edin: ad, ton, dil ve talimat boş olamaz.';
    }
  }
  if (error is TimeoutException) {
    return 'Sunucu yanıt vermedi. Bağlantınızı kontrol edip tekrar deneyin.';
  }
  return 'İşlem tamamlanamadı. Tekrar deneyin.';
}

abstract class BotRepository {
  Future<BotConfig> fetchBotConfig(String tenantId);
  Future<void> saveBotConfig(String tenantId, BotConfig config);
  Future<List<BotProfile>> fetchProfiles(String tenantId);

  /// Creates or updates an extra bot under a stable client ID.
  Future<void> saveProfile(String tenantId, String profileId, BotConfig config);
  Future<void> deleteProfile(String tenantId, String profileId);
  Future<List<BotNumber>> fetchNumbers(String tenantId);

  /// `profileId` null = the main bot; `enabled` false = no bot on this number.
  Future<void> setNumberBot(String tenantId, String connectionId, {required bool enabled, String? profileId});
}

class SupabaseBotRepository implements BotRepository {
  SupabaseBotRepository(this._client);

  final SupabaseClient _client;
  static const _timeout = Duration(seconds: 20);

  @override
  Future<BotConfig> fetchBotConfig(String tenantId) async {
    final response = await _client
        .from('bot_settings')
        .select()
        .eq('tenant_id', tenantId)
        .maybeSingle();

    if (response == null) {
      return BotConfig.defaults();
    }

    return _fromRow(response);
  }

  @override
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
    }).timeout(_timeout);
  }

  @override
  Future<List<BotProfile>> fetchProfiles(String tenantId) async {
    final rows = await _client
        .from('bot_profiles')
        .select()
        .eq('tenant_id', tenantId)
        .order('created_at')
        .timeout(_timeout);
    return rows.map<BotProfile>(BotProfile.fromRow).toList();
  }

  @override
  Future<void> saveProfile(String tenantId, String profileId, BotConfig config) async {
    await _client.rpc('save_bot_profile', params: {
      'p_tenant_id': tenantId,
      'p_profile_id': profileId,
      'p_name': config.name,
      'p_tone': config.tone,
      'p_language': config.language,
      'p_system_prompt': config.systemPrompt,
      'p_model': config.model,
      'p_temperature': config.temperature,
      'p_memory_hours': config.memoryHours,
      'p_max_history_messages': config.maxHistoryMessages,
      'p_is_active': config.isActive,
    }).timeout(_timeout);
  }

  @override
  Future<void> deleteProfile(String tenantId, String profileId) async {
    await _client.rpc('delete_bot_profile', params: {
      'p_tenant_id': tenantId,
      'p_profile_id': profileId,
    }).timeout(_timeout);
  }

  @override
  Future<List<BotNumber>> fetchNumbers(String tenantId) async {
    final rows = await _client
        .from('whatsapp_connections')
        .select('id, display_phone_number, verified_name, bot_enabled, bot_profile_id')
        .eq('tenant_id', tenantId)
        .order('is_default', ascending: false)
        .order('created_at')
        .timeout(_timeout);
    return rows.map<BotNumber>(BotNumber.fromRow).toList();
  }

  @override
  Future<void> setNumberBot(String tenantId, String connectionId, {required bool enabled, String? profileId}) async {
    await _client.rpc('set_connection_bot', params: {
      'p_tenant_id': tenantId,
      'p_connection_id': connectionId,
      'p_bot_enabled': enabled,
      'p_profile_id': profileId,
    }).timeout(_timeout);
  }

  BotConfig _fromRow(Map<String, dynamic> row) {
    return BotConfig(
      name: row['name'] as String? ?? 'Ava',
      tone: row['tone'] as String? ?? 'Profesyonel ve net',
      language: row['language'] as String? ?? 'Turkce',
      systemPrompt: row['system_prompt'] as String? ??
          'Kisa, profesyonel bir musteri temsilcisi gibi yanit ver.',
      model: row['model'] as String? ?? 'gpt-4o-mini',
      temperature: (row['temperature'] as num?)?.toDouble() ?? 0.3,
      memoryHours: (row['memory_hours'] as int?) ?? 6,
      maxHistoryMessages: (row['max_history_messages'] as int?) ?? 12,
      isActive: row['is_active'] as bool? ?? false,
    );
  }
}
