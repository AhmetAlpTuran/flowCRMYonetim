import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/contact.dart';
import 'contact_csv.dart';

/// Contacts and marketing consent. Rules live in the database
/// (`supabase/migrations/20261105100000_contacts_consent.sql`).
class ContactsRepository {
  ContactsRepository(this._client);

  final SupabaseClient _client;
  static const pageSize = 50;
  static const _timeout = Duration(seconds: 30);

  Future<List<Contact>> list(String tenantId,
      {String search = '', int offset = 0}) async {
    final rows = await _client.rpc('list_contacts', params: {
      'p_tenant_id': tenantId,
      'p_search': search.trim().isEmpty ? null : search.trim(),
      'p_limit': pageSize,
      'p_offset': offset,
    }).timeout(_timeout);
    if (rows is! List) return const [];
    return rows
        .whereType<Map<String, dynamic>>()
        .map(Contact.fromRow)
        .toList(growable: false);
  }

  Future<String> save({
    required String tenantId,
    required String phone,
    required String fullName,
    String? email,
    required List<String> tags,
  }) async {
    final id = await _client.rpc('upsert_contact', params: {
      'p_tenant_id': tenantId,
      'p_full_name': fullName.trim(),
      'p_phone': phone,
      'p_email': (email?.trim().isEmpty ?? true) ? null : email!.trim(),
      'p_tags': tags,
    }).timeout(_timeout);
    if (id is! String) throw const FormatException('Kişi kaydedilemedi.');
    return id;
  }

  Future<void> setConsent({
    required String tenantId,
    required String phone,
    required bool consent,
    String? note,
    String source = 'manual',
  }) async {
    await _client.rpc('set_marketing_consent', params: {
      'p_tenant_id': tenantId,
      'p_phone': phone,
      'p_consent': consent,
      'p_note': note,
      'p_source': source,
    }).timeout(_timeout);
  }

  /// Sends rows in chunks of 1000 (the server limit) and merges the results.
  /// Chunks already sent stay imported if a later chunk fails.
  Future<ContactImportResult> import(String tenantId, List<ContactImportRow> rows,
      {String? consentNote}) async {
    var total = const ContactImportResult();
    for (var start = 0; start < rows.length; start += 1000) {
      final chunk = rows.sublist(start, (start + 1000).clamp(0, rows.length));
      final data = await _client.rpc('import_contacts', params: {
        'p_tenant_id': tenantId,
        'p_rows': chunk.map((row) => row.toJson()).toList(),
        'p_consent_note': consentNote,
      }).timeout(_timeout);
      if (data is! Map) throw const FormatException('İçe aktarma yanıtı alınamadı.');
      final skipped = <(int, String)>[];
      for (final item in (data['skipped'] as List? ?? const [])) {
        if (item is Map && item['row'] is int) {
          final index = (item['row'] as int) - 1;
          if (index >= 0 && index < chunk.length) {
            skipped.add((chunk[index].line, item['reason']?.toString() ?? ''));
          }
        }
      }
      total = total +
          ContactImportResult(
            created: (data['created'] as num?)?.toInt() ?? 0,
            updated: (data['updated'] as num?)?.toInt() ?? 0,
            consented: (data['consented'] as num?)?.toInt() ?? 0,
            skippedLines: skipped,
          );
    }
    return total;
  }
}
