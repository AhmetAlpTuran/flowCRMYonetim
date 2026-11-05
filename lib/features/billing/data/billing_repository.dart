import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/billing_overview.dart';

/// A failed billing action, by the server's error code.
class BillingFailure implements Exception {
  const BillingFailure(this.code);
  final String code;
}

/// Turkish guidance for billing failures; raw provider text is never shown.
String billingErrorMessage(Object error) {
  final code = switch (error) {
    BillingFailure(:final code) => code,
    PostgrestException(code: '22023') => 'invalid_billing_profile',
    PostgrestException(code: '42501') => 'admin_required',
    TimeoutException() => 'timeout',
    _ => '',
  };
  return switch (code) {
    'billing_not_configured' => 'Online ödeme henüz etkin değil. Plan değişikliği için bizimle iletişime geçin.',
    'billing_profile_required' => 'Önce fatura bilgilerinizi kaydedin.',
    'invalid_billing_profile' =>
      'Fatura bilgilerini kontrol edin: telefon (+90 5xx…), 10-11 haneli T.C. kimlik veya vergi numarası ve açık adres gerekli.',
    'plan_unavailable' => 'Bu plan için online ödeme şu anda kullanılamıyor.',
    'already_subscribed' => 'Zaten online bir aboneliğiniz var; planı değiştirmek için ilgili planı seçin.',
    'same_plan' => 'Zaten bu plandasınız.',
    'no_online_subscription' => 'Online bir aboneliğiniz bulunmuyor.',
    'checkout_rate_limited' => 'Çok fazla ödeme denemesi yapıldı. Bir saat sonra tekrar deneyin.',
    'provider_rejected' =>
      'Ödeme sağlayıcısı isteği reddetti. Fatura bilgilerinizi kontrol edip tekrar deneyin.',
    'provider_unavailable' || 'billing_unavailable' || 'billing_unconfirmed' || 'timeout' =>
      'Ödeme sağlayıcısına şu anda ulaşılamıyor. Biraz sonra tekrar deneyin; işlem tekrarlanmaz.',
    'admin_required' => 'Bu işlem için işletme yöneticisi olmalısınız.',
    'unauthorized' => 'Oturum süresi doldu. Yeniden giriş yapın.',
    _ => 'İşlem tamamlanamadı. Abonelik ekranını yenileyip durumu kontrol edin.',
  };
}

abstract class BillingRepository {
  Future<BillingOverview> fetchOverview(String tenantId);
  Future<BillingProfile?> fetchProfile(String tenantId);
  Future<void> saveProfile(String tenantId, BillingProfile profile);

  /// Starts an online checkout and returns the payment page URL.
  Future<String> startCheckout(String tenantId, String planKey, String period);
  Future<void> changePlan(String tenantId, String planKey);
  Future<void> cancel(String tenantId);

  /// Re-checks an unfinished payment with iyzico; returns its outcome.
  Future<String> refresh(String tenantId);
}

class SupabaseBillingRepository implements BillingRepository {
  SupabaseBillingRepository(this._client);

  final SupabaseClient _client;
  static const _timeout = Duration(seconds: 20);

  @override
  Future<BillingOverview> fetchOverview(String tenantId) async {
    final result = await _client.rpc('tenant_billing_overview', params: {'p_tenant_id': tenantId}).timeout(_timeout);
    return BillingOverview.fromJson(Map<String, dynamic>.from(result as Map));
  }

  @override
  Future<BillingProfile?> fetchProfile(String tenantId) async {
    final row = await _client
        .from('tenant_billing_profiles')
        .select()
        .eq('tenant_id', tenantId)
        .maybeSingle()
        .timeout(_timeout);
    return row == null ? null : BillingProfile.fromJson(row);
  }

  @override
  Future<void> saveProfile(String tenantId, BillingProfile profile) async {
    await _client.rpc('save_billing_profile', params: {
      'p_tenant_id': tenantId,
      'p_contact_name': profile.contactName,
      'p_contact_surname': profile.contactSurname,
      'p_email': profile.email,
      'p_phone': profile.phone,
      'p_identity_number': profile.identityNumber,
      'p_company_name': profile.companyName,
      'p_tax_office': profile.taxOffice,
      'p_address': profile.address,
      'p_city': profile.city,
      'p_zip_code': profile.zipCode,
    }).timeout(_timeout);
  }

  Future<Map<String, dynamic>> _invoke(Map<String, dynamic> body) async {
    try {
      final response = await _client.functions.invoke('billing', body: body).timeout(const Duration(seconds: 45));
      final data = response.data;
      if (data is! Map) throw const BillingFailure('billing_unconfirmed');
      return Map<String, dynamic>.from(data);
    } on FunctionException catch (error) {
      final details = error.details;
      throw BillingFailure(details is Map && details['code'] is String
          ? details['code'] as String
          : error.status == 401
              ? 'unauthorized'
              : 'billing_unconfirmed');
    } on TimeoutException {
      throw const BillingFailure('timeout');
    }
  }

  @override
  Future<String> startCheckout(String tenantId, String planKey, String period) async {
    final data = await _invoke({'action': 'checkout', 'tenant_id': tenantId, 'plan_key': planKey, 'period': period});
    final url = data['payment_url'];
    if (url is! String || !url.startsWith('http')) throw const BillingFailure('billing_unconfirmed');
    return url;
  }

  @override
  Future<void> changePlan(String tenantId, String planKey) async {
    await _invoke({'action': 'change_plan', 'tenant_id': tenantId, 'plan_key': planKey});
  }

  @override
  Future<void> cancel(String tenantId) async {
    await _invoke({'action': 'cancel', 'tenant_id': tenantId});
  }

  @override
  Future<String> refresh(String tenantId) async {
    final data = await _invoke({'action': 'refresh', 'tenant_id': tenantId});
    return data['status'] as String? ?? 'none';
  }
}
