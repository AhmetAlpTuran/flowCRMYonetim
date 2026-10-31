import 'package:supabase_flutter/supabase_flutter.dart';

import '../../templates/models/message_template.dart';
import '../models/template_input.dart';
import '../models/campaign.dart';
import 'campaign_repository.dart';

class SupabaseCampaignRepository implements CampaignRepository {
  SupabaseCampaignRepository(this._client);

  final SupabaseClient _client;

  @override
  Future<List<CampaignTemplateInput>> fetchTemplateInputs({
    required String tenantId,
    required String templateId,
  }) async {
    final response = await _client.functions.invoke(
      'campaign-template-inputs',
      body: {'tenant_id': tenantId, 'template_id': templateId},
    );
    final inputs = (response.data as Map<String, dynamic>)['inputs'] as List;
    return inputs
        .map((value) => CampaignTemplateInput.fromJson(
              Map<String, dynamic>.from(value as Map),
            ))
        .toList();
  }

  @override
  Future<List<MessageTemplate>> fetchTemplates(String tenantId) async {
    final response = await _client
        .from('templates')
        .select(
            'id, name, category, language, status, components, wa_template_id, waba_id')
        .eq('tenant_id', tenantId)
        .eq('status', 'APPROVED')
        .not('waba_id', 'is', null)
        .order('created_at', ascending: false);

    return response.map<MessageTemplate>(MessageTemplate.fromRow).toList();
  }

  @override
  Future<int> countAudience({
    required String tenantId,
    String? segment,
    String? lastContacted,
    List<Map<String, dynamic>> custom = const [],
  }) async {
    final response = await _client.rpc('count_campaign_audience', params: {
      'p_tenant_id': tenantId,
      'p_filter': {
        if (segment != null && segment.isNotEmpty) 'segment': segment,
        if (lastContacted != null) 'last_contacted': lastContacted,
        'custom': custom,
      },
    });
    return (response as num).toInt();
  }

  @override
  Future<List<CampaignConnection>> fetchConnections(String tenantId) async {
    final rows = await _client
        .from('whatsapp_connections')
        .select('id,waba_id,verified_name,display_phone_number,is_default')
        .eq('tenant_id', tenantId)
        .eq('status', 'active')
        .order('is_default', ascending: false)
        .order('id');
    return rows.map(CampaignConnection.fromJson).toList();
  }

  @override
  Future<CampaignDraft> saveDraft(CampaignDraft draft) async {
    final row = await _client.rpc('save_campaign_draft', params: {
      'p_tenant_id': draft.tenantId,
      'p_campaign_id': draft.id,
      'p_expected_revision': draft.revision,
      'p_draft': draft.payload,
    });
    return CampaignDraft.fromJson(Map<String, dynamic>.from(row as Map));
  }

  static const _columns =
      'id,tenant_id,name,template_id,connection_id,audience_filter,template_bindings,revision,status,queued_at';

  @override
  Future<CampaignDraft?> fetchCampaign(
      String tenantId, String campaignId) async {
    final row = await _client
        .from('campaigns')
        .select(_columns)
        .eq('tenant_id', tenantId)
        .eq('id', campaignId)
        .maybeSingle();
    return row == null ? null : CampaignDraft.fromJson(row);
  }

  @override
  Future<List<CampaignDraft>> fetchCampaigns(String tenantId,
      {int page = 0}) async {
    final rows = await _client
        .from('campaigns')
        .select(_columns)
        .eq('tenant_id', tenantId)
        .order('created_at', ascending: false)
        .order('id')
        .range(page * 20, page * 20 + 19);
    return rows.map(CampaignDraft.fromJson).toList();
  }

  @override
  Future<CampaignProgress> fetchProgress(String campaignId) async {
    final result = await _client
        .rpc('campaign_progress', params: {'p_campaign_id': campaignId});
    return CampaignProgress(Map<String, dynamic>.from(result as Map));
  }

  @override
  Future<CampaignProgress> enqueueCampaign(String campaignId,
      {required int expectedRevision}) async {
    final response = await _client.functions.invoke('send-campaign', body: {
      'campaign_id': campaignId,
      'expected_revision': expectedRevision
    });
    final data = response.data as Map;
    return CampaignProgress(Map<String, dynamic>.from(data['progress'] as Map));
  }

  @override
  Future<List<Map<String, dynamic>>> fetchFailures(
      String tenantId, String campaignId,
      {int page = 0}) async {
    return await _client
        .from('campaign_dispatches')
        .select('id,recipient_phone,state,error_code,error_detail,attempts')
        .eq('tenant_id', tenantId)
        .eq('campaign_id', campaignId)
        .inFilter('state', ['failed', 'unknown', 'blocked', 'cancelled'])
        .order('id')
        .range(page * 20, page * 20 + 19);
  }
}
