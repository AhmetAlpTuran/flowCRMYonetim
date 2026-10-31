import '../../templates/models/message_template.dart';
import '../models/campaign.dart';
import '../models/template_input.dart';

abstract class CampaignRepository {
  Future<List<CampaignConnection>> fetchConnections(String tenantId);
  Future<List<MessageTemplate>> fetchTemplates(String tenantId);
  Future<List<CampaignTemplateInput>> fetchTemplateInputs(
      {required String tenantId, required String templateId});
  Future<int> countAudience(
      {required String tenantId,
      String? segment,
      String? lastContacted,
      List<Map<String, dynamic>> custom = const []});
  Future<CampaignDraft> saveDraft(CampaignDraft draft);
  Future<CampaignDraft?> fetchCampaign(String tenantId, String campaignId);
  Future<List<CampaignDraft>> fetchCampaigns(String tenantId, {int page = 0});
  Future<CampaignProgress> fetchProgress(String campaignId);
  Future<CampaignProgress> enqueueCampaign(String campaignId,
      {required int expectedRevision});
  Future<List<Map<String, dynamic>>> fetchFailures(
      String tenantId, String campaignId,
      {int page = 0});
}
