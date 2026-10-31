import 'dart:convert';
import '../../templates/models/message_template.dart';

class CampaignOptions {
  const CampaignOptions({required this.connections, required this.templates});
  final List<CampaignConnection> connections;
  final List<MessageTemplate> templates;
}

class CampaignDraft {
  CampaignDraft(
      {required this.id,
      required this.tenantId,
      required this.name,
      required this.templateId,
      required this.connectionId,
      required Map<String, dynamic> audienceFilter,
      required Map<String, dynamic> templateBindings,
      this.revision = 0,
      this.status = 'draft',
      this.queuedAt})
      : _audienceJson = jsonEncode(audienceFilter),
        _bindingsJson = jsonEncode(templateBindings);

  factory CampaignDraft.fromJson(Map<String, dynamic> row) => CampaignDraft(
        id: row['id'] as String,
        tenantId: row['tenant_id'] as String,
        name: row['name'] as String,
        templateId: row['template_id'] as String?,
        connectionId: row['connection_id'] as String?,
        audienceFilter:
            Map<String, dynamic>.from(row['audience_filter'] as Map),
        templateBindings:
            Map<String, dynamic>.from(row['template_bindings'] as Map? ?? {}),
        revision: (row['revision'] as num).toInt(),
        status: row['status'] as String,
        queuedAt: row['queued_at'] == null
            ? null
            : DateTime.parse(row['queued_at'] as String),
      );

  final String id, tenantId, name, status;
  final String? templateId, connectionId;
  final int revision;
  final DateTime? queuedAt;
  final String _audienceJson, _bindingsJson;
  // Defensive snapshots prevent later form mutations from changing a pending retry.
  Map<String, dynamic> get audienceFilter =>
      jsonDecode(_audienceJson) as Map<String, dynamic>;
  Map<String, dynamic> get templateBindings =>
      jsonDecode(_bindingsJson) as Map<String, dynamic>;
  bool get editable => status == 'draft' && queuedAt == null;
  Map<String, dynamic> get payload => {
        'name': name.trim(),
        'template_id': templateId,
        'connection_id': connectionId,
        'audience_filter': audienceFilter,
        'template_bindings': templateBindings,
      };
}

class CampaignConnection {
  const CampaignConnection(
      {required this.id,
      required this.wabaId,
      required this.label,
      required this.isDefault});
  factory CampaignConnection.fromJson(Map<String, dynamic> row) =>
      CampaignConnection(
        id: row['id'] as String,
        wabaId: row['waba_id'] as String,
        label: '${row['verified_name']} · ${row['display_phone_number']}',
        isDefault: row['is_default'] == true,
      );
  final String id, wabaId, label;
  final bool isDefault;
}

class CampaignProgress {
  CampaignProgress(Map<String, dynamic> data) : _data = Map.unmodifiable(data);
  final Map<String, dynamic> _data;
  String get status => _data['status'] as String;
  bool get legacy => _data['legacy'] == true;
  int count(String key) => (_data[key] as num?)?.toInt() ?? 0;
  bool get pending => ['queued', 'leased', 'sending', 'retry_wait']
      .any((key) => count(key) > 0);
}
