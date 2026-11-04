import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/request_id.dart';
import '../../tenancy/providers/tenant_providers.dart';
import '../data/supabase_bot_repository.dart';
import '../models/bot_config.dart';
import '../models/bot_profile.dart';
import '../providers/bot_providers.dart';
import '../widgets/bot_config_form.dart';

/// Edits the main bot (`profile` null and `isMain`), an extra bot, or creates one.
class BotEditorPage extends ConsumerStatefulWidget {
  const BotEditorPage.main({super.key, required this.initial})
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
  ConsumerState<BotEditorPage> createState() => _BotEditorPageState();
}

class _BotEditorPageState extends ConsumerState<BotEditorPage> {
  // A new bot keeps one ID across save retries, so it is never created twice.
  late final String _profileId = widget.profile?.id ?? newRequestId();

  BotConfig get _initial =>
      widget.initial ??
      widget.profile?.config ??
      const BotConfig(
        name: 'Yeni bot',
        tone: 'Profesyonel ve net',
        language: 'Türkçe',
        systemPrompt: 'Kısa, profesyonel bir müşteri temsilcisi gibi yanıt ver.',
        model: 'gpt-4o-mini',
        temperature: 0.3,
        memoryHours: 6,
        maxHistoryMessages: 12,
        isActive: true,
      );

  void _say(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

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
      if (mounted) _say(botErrorMessage(error));
      return;
    }
    if (!mounted) return;
    _say('Bot ayarları kaydedildi.');
    Navigator.of(context).pop(true);
  }

  Future<void> _delete() async {
    final tenant = ref.read(selectedTenantProvider);
    final profile = widget.profile;
    if (tenant == null || profile == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Bot silinsin mi?'),
        content: Text('"${profile.config.name}" silinecek. Bu botu kullanan numaralar ana bota döner.'),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Vazgeç')),
          FilledButton(onPressed: () => Navigator.of(context).pop(true), child: const Text('Sil')),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      await ref.read(botRepositoryProvider).deleteProfile(tenant.id, profile.id);
    } catch (error) {
      if (mounted) _say(botErrorMessage(error));
      return;
    }
    ref
      ..invalidate(botProfilesProvider)
      ..invalidate(botNumbersProvider);
    if (!mounted) return;
    _say('Bot silindi.');
    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final title = widget.isMain ? 'Ana bot' : (widget.profile == null ? 'Yeni bot' : 'Botu düzenle');
    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        actions: [
          if (widget.profile != null)
            IconButton(tooltip: 'Botu sil', onPressed: _delete, icon: const Icon(Icons.delete_outline)),
        ],
      ),
      body: SafeArea(child: BotConfigForm(initial: _initial, onSave: _save)),
    );
  }
}
