import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/whatsapp_connection.dart';

/// A failure from `manage-whatsapp-connection`, carrying the server's code.
class ConnectionFailure implements Exception {
  const ConnectionFailure(this.code);
  final String code;

  String get message => connectionErrorMessage(code);

  @override
  String toString() => message;
}

class ConnectionsRepository {
  ConnectionsRepository(this._client);

  final SupabaseClient _client;

  Future<List<WhatsAppConnection>> fetch(String tenantId) async {
    final rows = await _client
        .from('whatsapp_connections')
        .select(
            'id, waba_id, phone_number_id, display_phone_number, verified_name, status, is_default, token_expires_at, bot_enabled, bot_profile_id')
        .eq('tenant_id', tenantId)
        .order('created_at');
    return rows.map(WhatsAppConnection.fromRow).toList(growable: false);
  }

  /// Verifies the token with Meta, subscribes the WABA to webhooks and stores
  /// the token encrypted. Reconnecting the same number replaces its token.
  Future<void> connect({
    required String tenantId,
    required String wabaId,
    required String phoneNumberId,
    required String accessToken,
    required bool isDefault,
  }) =>
      _invoke({
        'action': 'connect',
        'tenant_id': tenantId,
        'waba_id': wabaId.trim(),
        'phone_number_id': phoneNumberId.trim(),
        'access_token': accessToken.trim(),
        'is_default': isDefault,
      });

  Future<void> disconnect({
    required String tenantId,
    required String connectionId,
  }) =>
      _invoke({
        'action': 'disconnect',
        'tenant_id': tenantId,
        'connection_id': connectionId,
      });

  Future<void> _invoke(Map<String, dynamic> body) async {
    try {
      final response = await _client.functions
          .invoke('manage-whatsapp-connection', body: body)
          .timeout(const Duration(seconds: 60));
      final data = response.data;
      if (data is! Map ||
          !{'connected', 'disconnected'}.contains(data['status'])) {
        throw const ConnectionFailure('unconfirmed');
      }
    } on FunctionException catch (error) {
      final details = error.details;
      throw ConnectionFailure(details is Map && details['code'] is String
          ? details['code'] as String
          : error.status == 401
              ? 'unauthorized'
              : 'unconfirmed');
    } on TimeoutException {
      throw const ConnectionFailure('unconfirmed');
    }
  }
}

/// Turkish guidance for each server error code; raw provider text is never shown.
String connectionErrorMessage(String code) => switch (code) {
      'unauthorized' => 'Oturum süresi doldu. Yeniden giriş yapın.',
      'admin_required' =>
        'WhatsApp numaralarını yalnızca işletme yöneticileri yönetebilir.',
      'invalid_meta_id' =>
        'WhatsApp Business Hesap Kimliği ve Telefon Numarası Kimliği yalnızca rakamlardan oluşmalı.',
      'invalid_token' => 'Geçerli bir erişim anahtarı (token) yapıştırın.',
      'invalid_whatsapp_token' =>
        'Bu erişim anahtarı Flow CRM uygulamasına ait değil veya WhatsApp yönetim ve mesajlaşma izinlerini içermiyor.',
      'token_expired' || 'token_expiry_unknown' =>
        'Erişim anahtarının süresi dolmuş veya dolmak üzere. Yeni bir anahtar oluşturun.',
      'phone_account_mismatch' =>
        'Bu telefon numarası, girilen WhatsApp Business hesabında bulunamadı.',
      'phone_lookup_incomplete' =>
        'Telefon numarası doğrulanamadı. Biraz sonra tekrar deneyin.',
      'connection_conflict' =>
        'Bu numara başka bir işletmeye veya hesaba bağlı.',
      'subscription_failed' ||
      'whatsapp_rejected' =>
        'WhatsApp isteği reddetti. Anahtarın izinlerini ve hesabı kontrol edin.',
      'whatsapp_transport' ||
      'connection_unavailable' =>
        'WhatsApp\'a şu anda ulaşılamıyor. Biraz sonra tekrar deneyin.',
      'credential_key_unavailable' ||
      'server_configuration' ||
      'graph_version_missing' =>
        'Sunucu yapılandırması eksik. Destek ekibiyle iletişime geçin.',
      'plan_limit' =>
        'Planınızın WhatsApp numarası sınırına ulaşıldı. Abonelik ekranından planınızı yükseltebilirsiniz.',
      'connection_save_failed' =>
        'Bağlantı kaydedilemedi. Listeyi yenileyip tekrar deneyin.',
      'disconnect_failed' =>
        'Bağlantı kesilemedi. Listeyi yenileyip tekrar deneyin.',
      _ =>
        'İşlemin sonucu doğrulanamadı. Listeyi yenileyip durumu kontrol edin; tekrar denemek güvenlidir.',
    };
