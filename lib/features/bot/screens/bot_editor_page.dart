import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/request_id.dart';
import '../../../ui/ui.dart';
import '../../tenancy/providers/tenant_providers.dart';
import '../data/supabase_bot_repository.dart';
import '../models/bot_config.dart';
import '../models/bot_profile.dart';
import '../providers/bot_providers.dart';
import '../widgets/bot_config_form.dart';

/// Starting values of a new extra assistant. It is on, but nothing changes until the
/// form is saved.
const newAssistantDraft = BotConfig(
  name: '',
  tone: 'Profesyonel ve net',
  language: 'Türkçe',
  systemPrompt: 'Kısa, profesyonel bir müşteri temsilcisi gibi yanıt ver.',
  model: 'gpt-4o-mini',
  temperature: 0.3,
  memoryHours: 6,
  maxHistoryMessages: 12,
  isActive: true,
);

/// The editor of one assistant as its own page (phones): the main assistant, an extra
/// assistant, or a new one.
class BotEditorPage extends StatelessWidget {
  const BotEditorPage.main({super.key, required BotConfig this.initial})
      : profile = null,
        isMain = true;
  const BotEditorPage.profile({super.key, required BotProfile this.profile})
      : initial = null,
        isMain = false;
  const BotEditorPage.create({super.key})
      : profile = null,
        initial = null,
        isMain = false;

  final BotConfig? initial;
  final BotProfile? profile;
  final bool isMain;

  @override
  Widget build(BuildContext context) {
    void close([bool? changed]) => Navigator.of(context).pop(changed);
    final initial = this.initial;
    final profile = this.profile;
    final panel = isMain && initial != null
        ? BotEditorPanel.main(initial: initial, onSaved: (_) => close(true), onCancel: close)
        : profile != null
            ? BotEditorPanel.profile(
                profile: profile,
                onSaved: (_) => close(true),
                onDeleted: () => close(true),
                onCancel: close,
              )
            : BotEditorPanel.create(onSaved: (_) => close(true), onCancel: close);
    return Scaffold(
      appBar: AppBar(title: Text(isMain || profile != null ? 'Asistanı düzenle' : 'Yeni asistan')),
      body: SafeArea(child: AppPage(maxWidth: 820, children: [panel])),
    );
  }
}

/// Loads, saves and deletes one assistant around [BotConfigForm]. Used as the body of
/// [BotEditorPage] and beside the list on wide screens.
class BotEditorPanel extends ConsumerStatefulWidget {
  const BotEditorPanel.main({
    super.key,
    required BotConfig this.initial,
    this.onSaved,
    this.onCancel,
    this.onDirtyChanged,
  })  : profile = null,
        onDeleted = null,
        isMain = true;
  const BotEditorPanel.profile({
    super.key,
    required BotProfile this.profile,
    this.onSaved,
    this.onDeleted,
    this.onCancel,
    this.onDirtyChanged,
  })  : initial = null,
        isMain = false;
  const BotEditorPanel.create({
    super.key,
    this.onSaved,
    this.onCancel,
    this.onDirtyChanged,
  })  : profile = null,
        initial = null,
        onDeleted = null,
        isMain = false;

  final BotConfig? initial;
  final BotProfile? profile;
  final bool isMain;

  /// After a confirmed save, with the extra assistant's ID (null for the main one).
  final ValueChanged<String?>? onSaved;
  final VoidCallback? onDeleted;
  final VoidCallback? onCancel;
  final ValueChanged<bool>? onDirtyChanged;

  bool get isNew => !isMain && profile == null;

  @override
  ConsumerState<BotEditorPanel> createState() => _BotEditorPanelState();
}

class _BotEditorPanelState extends ConsumerState<BotEditorPanel> {
  // A new assistant keeps one ID across save retries, so it is never created twice.
  late final String _profileId = widget.profile?.id ?? newRequestId();

  BotConfig get _initial => widget.initial ?? widget.profile?.config ?? newAssistantDraft;

  Future<void> _save(BotConfig config) async {
    final tenant = ref.read(selectedTenantProvider);
    if (tenant == null) return;
    final repository = ref.read(botRepositoryProvider);
    try {
      if (widget.isMain) {
        await repository.saveBotConfig(tenant.id, config);
        ref.invalidate(botConfigProvider);
      } else {
        await repository.saveProfile(tenant.id, _profileId, config);
        ref.invalidate(botProfilesProvider);
      }
    } catch (error) {
      if (mounted) showAppSnack(context, botErrorMessage(error), error: true);
      return;
    }
    if (!mounted) return;
    showAppSnack(context, widget.isNew ? 'Asistan oluşturuldu.' : 'Değişiklikler kaydedildi.');
    widget.onSaved?.call(widget.isMain ? null : _profileId);
  }

  Future<void> _delete() async {
    final tenant = ref.read(selectedTenantProvider);
    final profile = widget.profile;
    if (tenant == null || profile == null) return;
    final confirmed = await confirmAction(
      context,
      title: 'Asistan silinsin mi?',
      message: '"${profile.config.name}" silinecek. Bu asistanın yanıt verdiği numaralar ana asistana döner.',
      confirmLabel: 'Sil',
      destructive: true,
    );
    if (!confirmed || !mounted) return;
    try {
      await ref.read(botRepositoryProvider).deleteProfile(tenant.id, profile.id);
    } catch (error) {
      if (mounted) showAppSnack(context, botErrorMessage(error), error: true);
      return;
    }
    ref
      ..invalidate(botProfilesProvider)
      ..invalidate(botNumbersProvider);
    if (!mounted) return;
    showAppSnack(context, 'Asistan silindi.');
    widget.onDeleted?.call();
  }

  @override
  Widget build(BuildContext context) {
    final c = FlowColors.of(context);
    return BotConfigForm(
      initial: _initial,
      onSave: _save,
      kindLabel: widget.isMain ? 'Ana asistan' : (widget.isNew ? 'Yeni ek asistan' : 'Ek asistan'),
      saveLabel: widget.isNew ? 'Asistanı oluştur' : 'Değişiklikleri kaydet',
      onCancel: widget.onCancel,
      onDirtyChanged: widget.onDirtyChanged,
      headerAction: widget.profile == null
          ? null
          : IconButton(
              tooltip: 'Asistanı sil',
              onPressed: _delete,
              icon: Icon(Icons.delete_outline, color: c.danger),
            ),
    );
  }
}
