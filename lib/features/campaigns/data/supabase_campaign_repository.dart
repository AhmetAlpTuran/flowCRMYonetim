import 'package:supabase_flutter/supabase_flutter.dart';

import '../../templates/models/message_template.dart';

class SupabaseCampaignRepository {
  SupabaseCampaignRepository(this._client);

  final SupabaseClient _client;

  Future<List<MessageTemplate>> fetchTemplates(String tenantId) async {
    final response = await _client
        .from('templates')
        .select('id, name, category, language, status, components, wa_template_id')
        .eq('tenant_id', tenantId)
        .order('created_at', ascending: false);

    return response.map<MessageTemplate>((row) {
      final components = row['components'];
      return MessageTemplate(
        id: row['id'] as String,
        name: row['name'] as String,
        category: row['category'] as String,
        language: row['language'] as String,
        status: row['status'] as String? ?? 'PENDING',
        body: _extractBodyText(components),
        components: components is Map<String, dynamic>
            ? components
            : components is List
                ? {'components': components}
                : null,
        waTemplateId: row['wa_template_id'] as String?,
      );
    }).toList();
  }

  Future<int> countAudience({
    required String tenantId,
    String? segment,
    String? lastContacted,
  }) async {
    var query = _client.from('consented_contacts').select('id').eq(
          'tenant_id',
          tenantId,
        );

    if (segment != null && segment.isNotEmpty) {
      query = query.contains('tags', [segment]);
    }

    if (lastContacted != null) {
      final match = RegExp(r'^(\\d+)(d)$').firstMatch(lastContacted);
      if (match != null) {
        final days = int.parse(match.group(1)!);
        final cutoff =
            DateTime.now().subtract(Duration(days: days)).toIso8601String();
        query = query.gte('last_contacted_at', cutoff);
      }
    }

    final response = await query.count(CountOption.exact);
    return response.count ?? 0;
  }

  Future<String> createCampaign({
    required String tenantId,
    required String name,
    required Map<String, dynamic> audienceFilter,
    required String templateId,
  }) async {
    final response = await _client
        .from('campaigns')
        .insert({
          'tenant_id': tenantId,
          'name': name,
          'audience_filter': audienceFilter,
          'template_id': templateId,
          'status': 'running',
        })
        .select('id')
        .single();

    return response['id'] as String;
  }

  Future<Map<String, dynamic>> sendCampaign(String campaignId) async {
    final response = await _client.functions.invoke(
      'send-campaign',
      body: {'campaign_id': campaignId},
    );
    return response.data as Map<String, dynamic>? ?? {};
  }

  String _extractBodyText(dynamic components) {
    if (components is List) {
      for (final item in components) {
        if (item is Map<String, dynamic> &&
            (item['type'] == 'BODY' || item['type'] == 'body')) {
          final text = item['text'];
          if (text is String) {
            return text;
          }
        }
      }
    }
    if (components is Map<String, dynamic>) {
      final nested = components['components'];
      if (nested is List) {
        return _extractBodyText(nested);
      }
    }
    return '';
  }
}
