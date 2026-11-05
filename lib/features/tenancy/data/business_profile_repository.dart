import 'dart:async';

import 'package:flutter/painting.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Saves the business name and identity color through `update_business_profile`,
/// which checks the administrator, validates and audits on the server.
abstract class BusinessProfileRepository {
  Future<void> update({required String tenantId, required String name, required String brandColor});
}

class SupabaseBusinessProfileRepository implements BusinessProfileRepository {
  SupabaseBusinessProfileRepository(this._client);

  final SupabaseClient _client;

  @override
  Future<void> update({required String tenantId, required String name, required String brandColor}) async {
    await _client.rpc('update_business_profile', params: {
      'p_tenant_id': tenantId,
      'p_name': name.trim(),
      'p_brand_color': brandColor.toUpperCase(),
    }).timeout(const Duration(seconds: 20));
  }
}

final businessProfileRepositoryProvider = Provider<BusinessProfileRepository>(
  (ref) => SupabaseBusinessProfileRepository(Supabase.instance.client),
);

/// Turkish guidance for a failed profile save; raw backend text is never shown.
String businessProfileErrorMessage(Object error) {
  if (error is PostgrestException) {
    return switch ((error.code, error.hint)) {
      ('42501', _) => 'İşletme bilgilerini yalnızca işletme yöneticileri değiştirebilir.',
      ('22023', 'brand_color') => 'Listeden bir işletme rengi seçin.',
      ('22023', _) => 'İşletme adı 2 ile 80 karakter arasında olmalı.',
      ('P0002', _) => 'İşletme bulunamadı. Sayfayı yenileyip tekrar deneyin.',
      _ => 'İşletme bilgileri kaydedilemedi. Tekrar deneyin.',
    };
  }
  if (error is TimeoutException) {
    return 'Sunucu yanıt vermedi. Sayfayı yenileyip kaydın durumunu kontrol edin.';
  }
  return 'İşletme bilgileri kaydedilemedi. Tekrar deneyin.';
}

/// "#1F4B99" for a color (alpha dropped), the format the server stores.
String brandHex(Color color) {
  final rgb = color.toARGB32() & 0xFFFFFF;
  return '#${rgb.toRadixString(16).padLeft(6, '0').toUpperCase()}';
}

/// The color of a "#RRGGBB" string, or null when it is not one.
Color? brandColorFromHex(String hex) {
  final match = RegExp(r'^#?([0-9A-Fa-f]{6})$').firstMatch(hex.trim());
  if (match == null) return null;
  return Color(int.parse('FF${match.group(1)}', radix: 16));
}
