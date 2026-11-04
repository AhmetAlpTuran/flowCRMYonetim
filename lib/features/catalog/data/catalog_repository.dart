import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/catalog_models.dart';

/// Catalog data. Types, resources and leads are written directly under RLS;
/// bookings only through `create_booking` / `set_booking_status`
/// (supabase/migrations/20261107090000_catalog_bookings_leads.sql).
class CatalogRepository {
  CatalogRepository(this._client);

  final SupabaseClient _client;
  static const _timeout = Duration(seconds: 20);

  Future<List<ResourceType>> types(String tenantId) async {
    final rows = await _client
        .from('resource_types')
        .select()
        .eq('tenant_id', tenantId)
        .order('created_at')
        .timeout(_timeout);
    return rows.map(ResourceType.fromRow).toList(growable: false);
  }

  Future<void> createTypeFromPreset(String tenantId, ResourceTypePreset preset,
      {String? name}) async {
    await _client.from('resource_types').insert({
      'tenant_id': tenantId,
      'key': preset.key,
      'name': (name ?? preset.name).trim(),
      'kind': preset.kind,
      'booking_unit': preset.bookingUnit,
      'fields': [for (final f in preset.fields) f.toJson()],
    }).timeout(_timeout);
  }

  Future<List<Resource>> resources(String tenantId) async {
    final rows = await _client
        .from('resources')
        .select('id, type_id, name, description, attributes, price, currency, capacity, status')
        .eq('tenant_id', tenantId)
        .order('name')
        .limit(500)
        .timeout(_timeout);
    return rows.map(Resource.fromRow).toList(growable: false);
  }

  Future<void> saveResource({
    required String tenantId,
    String? id,
    required String typeId,
    required String name,
    String? description,
    required Map<String, dynamic> attributes,
    double? price,
    int? capacity,
    required String status,
  }) async {
    final values = {
      'tenant_id': tenantId,
      'type_id': typeId,
      'name': name.trim(),
      'description': (description?.trim().isEmpty ?? true) ? null : description!.trim(),
      'attributes': attributes,
      'price': price,
      'capacity': capacity,
      'status': status,
    };
    if (id == null) {
      await _client.from('resources').insert(values).timeout(_timeout);
    } else {
      await _client
          .from('resources')
          .update(values)
          .eq('tenant_id', tenantId)
          .eq('id', id)
          .timeout(_timeout);
    }
  }

  Future<void> deleteResource(String tenantId, String id) => _client
      .from('resources')
      .delete()
      .eq('tenant_id', tenantId)
      .eq('id', id)
      .timeout(_timeout);

  /// Bookings ending after [from], soonest first.
  Future<List<Booking>> bookings(String tenantId, {required DateTime from}) async {
    final rows = await _client
        .from('bookings')
        .select('id, resource_id, period, status, hold_expires_at, customer_name, '
            'customer_phone, source, note, resource:resources(name)')
        .eq('tenant_id', tenantId)
        .neq('status', 'cancelled')
        .filter('period', 'ov', '[${from.toUtc().toIso8601String()},infinity)')
        .order('period')
        .limit(300)
        .timeout(_timeout);
    return rows.map(Booking.fromRow).toList(growable: false);
  }

  Future<String> createBooking({
    required String tenantId,
    required String resourceId,
    required DateTime start,
    required DateTime end,
    String? customerName,
    String? customerPhone,
    String? note,
    required String requestKey,
  }) async {
    final id = await _client.rpc('create_booking', params: {
      'p_tenant_id': tenantId,
      'p_resource_id': resourceId,
      'p_start': start.toUtc().toIso8601String(),
      'p_end': end.toUtc().toIso8601String(),
      'p_customer_name': customerName,
      'p_customer_phone': customerPhone,
      'p_note': note,
      'p_request_key': requestKey,
    }).timeout(_timeout);
    return id as String;
  }

  Future<void> setBookingStatus(String tenantId, String bookingId, String status) =>
      _client.rpc('set_booking_status', params: {
        'p_tenant_id': tenantId,
        'p_booking_id': bookingId,
        'p_status': status,
      }).timeout(_timeout);

  Future<List<Lead>> leads(String tenantId) async {
    final rows = await _client
        .from('leads')
        .select('id, kind, status, customer_name, customer_phone, details, preferred_at, '
            'source, created_at, resource:resources(name)')
        .eq('tenant_id', tenantId)
        .order('created_at', ascending: false)
        .limit(200)
        .timeout(_timeout);
    return rows.map(Lead.fromRow).toList(growable: false);
  }

  Future<void> setLeadStatus(String tenantId, String leadId, String status) => _client
      .from('leads')
      .update({'status': status, 'updated_at': DateTime.now().toUtc().toIso8601String()})
      .eq('tenant_id', tenantId)
      .eq('id', leadId)
      .timeout(_timeout);
}

/// Turkish guidance for catalog errors; raw server text is never shown.
String catalogErrorMessage(Object error) {
  if (error is PostgrestException) {
    return switch (error.code) {
      'P0015' => 'Bu tarihler başka bir rezervasyonla çakışıyor.',
      'P0016' => 'Bu ön rezervasyonun süresi dolmuş veya iptal edilmiş.',
      'P0002' => 'Kayıt bulunamadı veya şu anda kullanılamıyor.',
      '42501' => 'Bu işlem için katalog yetkiniz yok.',
      '23505' => 'Bu anahtarla bir tür zaten var.',
      '22023' || '23514' => 'Girilen bilgileri kontrol edin.',
      _ => 'İşlem tamamlanamadı. Tekrar deneyin.',
    };
  }
  if (error is TimeoutException) {
    return 'Sunucu yanıt vermedi. Bağlantınızı kontrol edip tekrar deneyin.';
  }
  return 'İşlem tamamlanamadı. Tekrar deneyin.';
}
