// Authored for deferred verification. No Supabase initialization or network calls.
import 'dart:async';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:wpapp/features/campaigns/data/campaign_repository.dart';
import 'package:wpapp/features/campaigns/models/campaign.dart';
import 'package:wpapp/features/campaigns/models/template_input.dart';
import 'package:wpapp/features/campaigns/providers/campaign_providers.dart';
import 'package:wpapp/features/templates/models/message_template.dart';

void main() {
  test('lost create reply retries one immutable draft identity', () async {
    final repository = _FakeCampaignRepository()..loseSaveReply = true;
    final actions = CampaignActions(repository, 'tenant-a');
    addTearDown(actions.dispose);
    final bindings = <String, dynamic>{
      'body.1': {'source': 'literal', 'value': 'Original'}
    };
    final draft = _draft(actions, bindings: bindings);
    expect(await actions.save(draft, send: true), isFalse);
    expect(actions.state.canRetry, isTrue);
    final originalId = actions.state.id;
    actions.open(null);
    expect(actions.state.id, originalId);
    bindings['body.1']['value'] = 'Changed after request';
    expect(await actions.retry(), isTrue);
    expect(repository.records.length, 1);
    expect(repository.savedInputs.map((item) => item.id).toSet(), {originalId});
    expect(repository.savedInputs.last.templateBindings['body.1']['value'],
        'Original');
    expect(repository.enqueued, {originalId});
    expect(actions.state.locked, isTrue);
  });

  test(
      'lost enqueue reply retries enqueue only, without re-saving changed templates',
      () async {
    final repository = _FakeCampaignRepository()..loseEnqueueReply = true;
    final actions = CampaignActions(repository, 'tenant-a');
    addTearDown(actions.dispose);
    final draft = _draft(actions);
    expect(await actions.save(draft, send: true), isFalse);
    expect(await actions.retry(), isTrue);
    expect(repository.savedInputs.length, 1);
    expect(repository.enqueueCalls, [draft.id, draft.id]);
    expect(repository.enqueued.length, 1);
  });

  test('busy submission is ignored and disposal prevents the enqueue stage',
      () async {
    final gate = Completer<void>();
    final repository = _FakeCampaignRepository()..saveGate = gate.future;
    final actions = CampaignActions(repository, 'tenant-a');
    final draft = _draft(actions);
    final pending = actions.save(draft, send: true);
    expect(await actions.save(draft, send: true), isFalse);
    actions.dispose();
    gate.complete();
    expect(await pending, isFalse);
    expect(repository.enqueueCalls, isEmpty);
  });

  test('stale edits require review and cannot enqueue', () async {
    final repository = _FakeCampaignRepository()
      ..saveFailure =
          const PostgrestException(message: 'Conflict', code: '40001');
    final actions = CampaignActions(repository, 'tenant-a');
    addTearDown(actions.dispose);
    expect(await actions.save(_draft(actions), send: true), isFalse);
    expect(actions.state.locked, isTrue);
    expect(actions.state.canRetry, isFalse);
    expect(repository.enqueueCalls, isEmpty);
  });

  test('controller rejects another tenant draft before persistence', () async {
    final repository = _FakeCampaignRepository();
    final actions = CampaignActions(repository, 'tenant-a');
    addTearDown(actions.dispose);
    final foreign = CampaignDraft(
        id: actions.state.id,
        tenantId: 'tenant-b',
        name: 'Foreign',
        templateId: 'template',
        connectionId: 'connection',
        audienceFilter: {},
        templateBindings: {});
    expect(await actions.save(foreign, send: true), isFalse);
    expect(repository.savedInputs, isEmpty);
  });
}

CampaignDraft _draft(CampaignActions actions,
        {Map<String, dynamic> bindings = const {}}) =>
    CampaignDraft(
        id: actions.state.id,
        tenantId: 'tenant-a',
        name: 'Fixture',
        templateId: 'template',
        connectionId: 'connection',
        audienceFilter: {},
        templateBindings: bindings);

class _FakeCampaignRepository implements CampaignRepository {
  bool loseSaveReply = false, loseEnqueueReply = false;
  Object? saveFailure;
  Future<void>? saveGate;
  final records = <String, CampaignDraft>{};
  final savedInputs = <CampaignDraft>[];
  final enqueueCalls = <String>[];
  final enqueued = <String>{};
  @override
  Future<CampaignDraft> saveDraft(CampaignDraft draft) async {
    savedInputs.add(draft);
    await saveGate;
    if (saveFailure != null) throw saveFailure!;
    final previous = records[draft.id];
    if (previous != null &&
        jsonEncode(previous.payload) == jsonEncode(draft.payload)) {
      return previous;
    }
    final saved = CampaignDraft(
        id: draft.id,
        tenantId: draft.tenantId,
        name: draft.name,
        templateId: draft.templateId,
        connectionId: draft.connectionId,
        audienceFilter: draft.audienceFilter,
        templateBindings: draft.templateBindings,
        revision: (previous?.revision ?? 0) + 1);
    records[draft.id] = saved;
    if (loseSaveReply) {
      loseSaveReply = false;
      throw TimeoutException('Saved but reply lost');
    }
    return saved;
  }

  @override
  Future<CampaignProgress> enqueueCampaign(String id,
      {required int expectedRevision}) async {
    enqueueCalls.add(id);
    enqueued.add(id);
    if (loseEnqueueReply) {
      loseEnqueueReply = false;
      throw TimeoutException('Enqueued but reply lost');
    }
    return CampaignProgress({'status': 'running', 'total': 1, 'queued': 1});
  }

  @override
  Future<CampaignDraft?> fetchCampaign(
          String tenantId, String campaignId) async =>
      records[campaignId];
  @override
  Future<List<CampaignDraft>> fetchCampaigns(String tenantId,
          {int page = 0}) async =>
      records.values.toList();
  @override
  Future<List<CampaignConnection>> fetchConnections(String tenantId) async =>
      [];
  @override
  Future<List<MessageTemplate>> fetchTemplates(String tenantId) async => [];
  @override
  Future<List<CampaignTemplateInput>> fetchTemplateInputs(
          {required String tenantId, required String templateId}) async =>
      [];
  @override
  Future<int> countAudience(
          {required String tenantId,
          String? segment,
          String? lastContacted,
          List<Map<String, dynamic>> custom = const []}) async =>
      1;
  @override
  Future<CampaignProgress> fetchProgress(String campaignId) async =>
      CampaignProgress({'status': 'running', 'total': 1});
  @override
  Future<List<Map<String, dynamic>>> fetchFailures(
          String tenantId, String campaignId,
          {int page = 0}) async =>
      [];
}
