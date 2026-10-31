import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../tenancy/providers/tenant_providers.dart';
import '../data/campaign_repository.dart';
import '../data/supabase_campaign_repository.dart';
import '../models/campaign.dart';
import '../models/template_input.dart';

final campaignRepositoryProvider = Provider<CampaignRepository>(
    (ref) => SupabaseCampaignRepository(Supabase.instance.client));

final campaignOptionsProvider = FutureProvider.autoDispose
    .family<CampaignOptions, String>((ref, tenantId) async {
  ref.watch(authControllerProvider);
  final repository = ref.watch(campaignRepositoryProvider);
  final connections = await repository.fetchConnections(tenantId);
  final templates = await repository.fetchTemplates(tenantId);
  return CampaignOptions(connections: connections, templates: templates);
});

typedef CampaignKey = ({String tenantId, String id});
typedef CampaignPage = ({String tenantId, int page});
final campaignInputsProvider = FutureProvider.autoDispose
    .family<List<CampaignTemplateInput>, CampaignKey>((ref, key) {
  ref.watch(authControllerProvider);
  return ref
      .watch(campaignRepositoryProvider)
      .fetchTemplateInputs(tenantId: key.tenantId, templateId: key.id);
});
final campaignAudienceProvider = FutureProvider.autoDispose
    .family<int, ({String tenantId, String filter})>((ref, key) async {
  ref.watch(authControllerProvider);
  final repository = ref.watch(campaignRepositoryProvider);
  var disposed = false;
  ref.onDispose(() => disposed = true);
  await Future<void>.delayed(const Duration(milliseconds: 300));
  if (disposed) return 0;
  final filter = jsonDecode(key.filter) as Map<String, dynamic>;
  return repository.countAudience(
      tenantId: key.tenantId,
      segment: filter['segment'] as String?,
      lastContacted: filter['last_contacted'] as String?,
      custom: (filter['custom'] as List? ?? [])
          .map((item) => Map<String, dynamic>.from(item as Map))
          .toList());
});
final campaignHistoryProvider = FutureProvider.autoDispose
    .family<List<CampaignDraft>, CampaignPage>((ref, key) {
  ref.watch(authControllerProvider);
  return ref
      .watch(campaignRepositoryProvider)
      .fetchCampaigns(key.tenantId, page: key.page);
});
final campaignProgressProvider = FutureProvider.autoDispose
    .family<CampaignProgress, CampaignKey>((ref, key) {
  ref.watch(authControllerProvider);
  return ref.watch(campaignRepositoryProvider).fetchProgress(key.id);
});
final campaignFailuresProvider = FutureProvider.autoDispose.family<
    List<Map<String, dynamic>>,
    ({String tenantId, String id, int page})>((ref, key) {
  ref.watch(authControllerProvider);
  return ref
      .watch(campaignRepositoryProvider)
      .fetchFailures(key.tenantId, key.id, page: key.page);
});

final campaignActionsProvider = StateNotifierProvider.autoDispose
    .family<CampaignActions, CampaignActionState, String>((ref, tenantId) {
  ref.watch(authControllerProvider);
  return CampaignActions(ref.watch(campaignRepositoryProvider), tenantId);
});

class CampaignActionState {
  const CampaignActionState(
      {required this.id,
      this.revision = 0,
      this.busy = false,
      this.locked = false,
      this.canRetry = false,
      this.error,
      this.notice,
      this.saved,
      this.progress});
  final String id;
  final int revision;
  final bool busy, locked, canRetry;
  final String? error, notice;
  final CampaignDraft? saved;
  final CampaignProgress? progress;
}

class CampaignActions extends StateNotifier<CampaignActionState> {
  CampaignActions(this.repository, this.tenantId)
      : super(CampaignActionState(id: newCampaignId()));
  final CampaignRepository repository;
  final String tenantId;
  CampaignDraft? _pendingDraft;
  CampaignDraft? _pendingPersisted;
  bool _pendingSend = false;

  void open(CampaignDraft? draft) {
    if (state.busy ||
        state.canRetry ||
        (draft != null && draft.tenantId != tenantId)) {
      return;
    }
    _pendingDraft = null;
    _pendingPersisted = null;
    _pendingSend = false;
    state = CampaignActionState(
        id: draft?.id ?? newCampaignId(),
        revision: draft?.revision ?? 0,
        saved: draft,
        locked: draft != null && !draft.editable);
  }

  Future<bool> save(CampaignDraft draft, {bool send = false}) async {
    if (state.busy ||
        state.locked ||
        draft.id != state.id ||
        draft.tenantId != tenantId) {
      return false;
    }
    _pendingDraft = draft;
    _pendingPersisted = null;
    _pendingSend = send;
    return _persist();
  }

  Future<bool> retry() async {
    if (state.busy || !state.canRetry || _pendingDraft == null) return false;
    return _persist();
  }

  Future<bool> _persist() async {
    final draft = _pendingDraft!;
    final send = _pendingSend;
    state = CampaignActionState(
        id: state.id, revision: state.revision, saved: state.saved, busy: true);
    CampaignDraft? saved = state.saved;
    try {
      saved = _pendingPersisted ??
          await repository
              .saveDraft(draft)
              .timeout(const Duration(seconds: 20));
      if (!mounted) return false;
      _pendingPersisted = saved;
      final progress = send
          ? await repository
              .enqueueCampaign(saved.id, expectedRevision: saved.revision)
              .timeout(const Duration(seconds: 20))
          : null;
      if (!mounted) return false;
      _pendingDraft = null;
      _pendingPersisted = null;
      state = CampaignActionState(
          id: saved.id,
          revision: saved.revision,
          saved: saved,
          locked: send || !saved.editable,
          progress: progress,
          notice: send
              ? 'Kampanya kuyruğa alındı. Gönderim durumunu aşağıdan izleyebilirsiniz.'
              : 'Taslak kaydedildi.');
      return true;
    } catch (error) {
      if (!mounted) return false;
      final conflict = error is PostgrestException &&
              ['40001', '55000'].contains(error.code) ||
          error is FunctionException &&
              error.details is Map &&
              (error.details as Map)['code'] == 'campaign_changed';
      final definite = error is PostgrestException &&
              ['22023', '22P02', '23514', '42501'].contains(error.code) ||
          error is FunctionException &&
              error.status >= 400 &&
              error.status < 500;
      final retryable = !conflict && !definite;
      if (!retryable) _pendingDraft = null;
      state = CampaignActionState(
          id: draft.id,
          revision: saved?.revision ?? draft.revision,
          saved: saved,
          locked: retryable || conflict,
          canRetry: retryable,
          error: conflict
              ? 'Bu kampanya başka bir işlemde değişti. Geçmişten güncel kaydı açın; girdileriniz henüz değiştirilmedi.'
              : definite
                  ? _knownError(error)
                  : 'İşlem sonucu doğrulanamadı. Aynı kampanya için tekrar deneyin; yeni bir kampanya oluşturmayın.');
      return false;
    }
  }

  String _knownError(Object error) {
    if (error is FunctionException) {
      final details = error.details;
      final code = details is Map ? details['code'] : null;
      if (code == 'connection_required' || code == 'connection_expired') {
        return 'WhatsApp bağlantısını kontrol edip yeniden bağlayın.';
      }
      if (code == 'template_account_mismatch') {
        return 'Seçilen WhatsApp hesabının şablonlarını eşitleyip doğru şablonu seçin.';
      }
      if (code == 'invalid_template_values') {
        return 'Şablonun zorunlu gönderim değerlerini kontrol edin.';
      }
      if (error.status == 401) {
        return 'Oturum süresi doldu. Yeniden giriş yapın.';
      }
      if (error.status == 403) {
        return 'Bu işletmede kampanya gönderme yetkiniz yok.';
      }
    }
    return 'Kampanya kaydedilemedi veya kuyruğa alınamadı. Filtreleri, bağlantıyı ve onaylı şablonu kontrol edin.';
  }
}
