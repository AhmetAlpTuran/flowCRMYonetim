import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../ui/ui.dart';
import '../../billing/providers/billing_providers.dart';
import '../../catalog/widgets/industry_pack_sheet.dart';
import '../../knowledge/models/knowledge_document.dart';
import '../../knowledge/providers/knowledge_providers.dart';
import '../../knowledge/widgets/knowledge_documents_section.dart';
import '../../shell/shell_providers.dart';
import '../../tenancy/models/tenant.dart';
import '../../tenancy/providers/tenant_providers.dart';
import '../data/supabase_bot_repository.dart';
import '../models/bot_config.dart';
import '../models/bot_profile.dart';
import '../providers/bot_providers.dart';
import '../widgets/assistant_card.dart';
import '../widgets/dashed_action_button.dart';
import 'bot_editor_page.dart';

const _mainKey = 'main';
const _newKey = 'new';

/// From this content width the editor sits beside the list instead of on its own page.
const _splitWidth = 820.0;

/// How many assistants the plan allows; known only to administrators.
class _Allowance {
  const _Allowance(this.used, this.limit);

  final int used;
  final int limit;

  int get remaining => limit - used;
  bool get reached => remaining <= 0;
}

/// Asistan → Asistanlar: the main assistant, extra assistants, and which assistant
/// answers on each WhatsApp number. On wide screens the selected assistant is edited
/// beside the list; on phones the editor opens as a page.
class BotScreen extends ConsumerStatefulWidget {
  const BotScreen({super.key});

  @override
  ConsumerState<BotScreen> createState() => _BotScreenState();
}

class _BotScreenState extends ConsumerState<BotScreen> {
  String _selected = _mainKey;

  /// Bumped to rebuild the inline editor from saved values ("Vazgeç").
  int _revision = 0;
  bool _dirty = false;

  void _refresh() {
    ref
      ..invalidate(botConfigProvider)
      ..invalidate(botProfilesProvider)
      ..invalidate(botNumbersProvider);
  }

  Future<void> _push(Widget page) => Navigator.of(context).push(MaterialPageRoute<bool>(builder: (_) => page));

  void _show(String key) => setState(() {
        _selected = key;
        _dirty = false;
        _revision++;
      });

  Future<void> _select(String key) async {
    if (key == _selected) return;
    if (_dirty) {
      final leave = await confirmAction(
        context,
        title: 'Değişiklikler kaydedilmedi',
        message: 'Bu asistanda yaptığınız değişiklikler silinecek.',
        confirmLabel: 'Kaydetmeden geç',
        destructive: true,
      );
      if (!leave || !mounted) return;
    }
    _show(key);
  }

  Future<void> _add({required bool split, _Allowance? allowance}) async {
    if (allowance != null && allowance.reached) {
      final upgrade = await confirmAction(
        context,
        title: 'Asistan sınırına ulaştınız',
        message: 'Planınız en fazla ${allowance.limit} asistana izin veriyor. '
            'Yeni bir asistan için planınızı yükseltebilirsiniz.',
        confirmLabel: 'Aboneliğe git',
        cancelLabel: 'Kapat',
      );
      if (upgrade && mounted) openShellDestination(ref, ShellDestinationId.billing);
      return;
    }
    if (split) {
      await _select(_newKey);
    } else {
      await _push(const BotEditorPage.create());
    }
  }

  @override
  Widget build(BuildContext context) {
    final main = ref.watch(botConfigProvider);
    final profiles = ref.watch(botProfilesProvider);
    final numbers = ref.watch(botNumbersProvider);
    final firstError = [main, profiles, numbers].where((v) => v.hasError).firstOrNull;
    if (firstError != null) {
      return AppPage(maxWidth: 820, children: [
        ErrorState(
          title: 'Asistanlar yüklenemedi',
          message: botErrorMessage(firstError.error!),
          onRetry: _refresh,
        ),
      ]);
    }
    if (!main.hasValue || !profiles.hasValue || !numbers.hasValue) {
      return const AppPage(children: [LoadingList(rows: 3)]);
    }

    final mainBot = main.value!;
    final extra = profiles.value!;
    final allNumbers = numbers.value!;
    final tenant = ref.watch(selectedTenantProvider);
    final membership = ref.watch(currentMembershipProvider).valueOrNull;
    final isAdmin = membership?.isAdmin ?? false;
    final knowledgeAllowed = tenant != null &&
        tenant.features.contains(TenantFeature.knowledge) &&
        (membership?.hasPermission(TenantFeature.knowledge.permissionKey) ?? false);
    final limit = isAdmin ? ref.watch(billingOverviewProvider).valueOrNull?.limits.bots : null;
    final allowance = limit == null || limit <= 0 ? null : _Allowance(1 + extra.length, limit);

    final known = {for (final profile in extra) profile.id};
    List<String> phonesOf(String? profileId) => [
          for (final number in allNumbers)
            if (number.botEnabled &&
                (profileId == null
                    ? number.botProfileId == null || !known.contains(number.botProfileId)
                    : number.botProfileId == profileId))
              number.displayPhone,
        ];

    final theme = Theme.of(context);
    final c = FlowColors.of(context);

    return RefreshIndicator(
      onRefresh: () async {
        _refresh();
        await ref.read(botNumbersProvider.future);
      },
      child: AppPage(children: [
        Text(
          'Asistanınız müşterilere sizin bilgilerinizle, sizin üslubunuzla yanıt verir. Satış ve servis '
          'gibi işler için ayrı asistanlar kurup her numaraya birini atayabilirsiniz.',
          style: theme.textTheme.bodyMedium?.copyWith(color: c.muted),
        ),
        LayoutBuilder(builder: (context, constraints) {
          final split = constraints.maxWidth >= _splitWidth;
          final selectedProfile = extra.where((p) => p.id == _selected).firstOrNull;
          final current = _selected == _newKey ? _newKey : (selectedProfile?.id ?? _mainKey);
          void pick(String key) {
            if (key != current) _select(key);
          }

          final list = Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(children: [
              Expanded(child: Text(upperTr('Asistanlarınız'), style: FlowText.caps(context))),
              Text(
                allowance == null
                    ? formatCount(1 + extra.length)
                    : '${formatCount(allowance.used)} / ${formatCount(allowance.limit)}',
                style: FlowText.mono(context, size: 12),
              ),
            ]),
            const SizedBox(height: FlowSpace.md - 2),
            AssistantCard(
              name: mainBot.name,
              isMain: true,
              isActive: mainBot.isActive,
              phones: phonesOf(null),
              selected: split && current == _mainKey,
              onTap: () => split ? pick(_mainKey) : _push(BotEditorPage.main(initial: mainBot)),
            ),
            for (final profile in extra) ...[
              const SizedBox(height: FlowSpace.md - 2),
              AssistantCard(
                name: profile.config.name,
                isMain: false,
                isActive: profile.config.isActive,
                phones: phonesOf(profile.id),
                selected: split && current == profile.id,
                onTap: () => split ? pick(profile.id) : _push(BotEditorPage.profile(profile: profile)),
              ),
            ],
            const SizedBox(height: FlowSpace.md - 2),
            DashedActionButton(
              label: 'Asistan ekle',
              note: allowance == null
                  ? null
                  : (allowance.reached ? 'Plan sınırında' : '${formatCount(allowance.remaining)} hak kaldı'),
              onPressed: () => _add(split: split, allowance: allowance),
            ),
          ]);

          final numbersCard = SectionCard(
            title: 'WhatsApp numaraları',
            subtitle: 'Her numarada hangi asistanın yanıt vereceğini seçin; seçiminiz hemen geçerli olur. '
                'Seçim yapılmayan numaralarda ana asistan yanıt verir.',
            child: allNumbers.isEmpty
                ? EmptyState(
                    compact: true,
                    icon: Icons.phone_iphone_outlined,
                    title: 'Numara bağlı değil',
                    message: 'Henüz WhatsApp numarası bağlanmadı. Bağladığınızda her numarada hangi '
                        'asistanın yanıt vereceğini buradan seçersiniz.',
                    action: isAdmin
                        ? OutlinedButton(
                            onPressed: () => openShellDestination(ref, ShellDestinationId.connections),
                            child: const Text('Numara bağla'),
                          )
                        : null,
                  )
                : Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    for (var i = 0; i < allNumbers.length; i++) ...[
                      if (i > 0) Divider(height: FlowSpace.xxl, color: c.border),
                      NumberBotCard(number: allNumbers[i], mainBot: mainBot, profiles: extra),
                    ],
                  ]),
          );

          final side = [
            if (knowledgeAllowed) const _KnowledgeSummary(),
            if (isAdmin) const _IndustryPackCard(),
          ];

          if (!split) {
            return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              list,
              const SizedBox(height: FlowSpace.xl),
              numbersCard,
              for (final item in side) ...[const SizedBox(height: FlowSpace.lg), item],
            ]);
          }

          // The form reports when saved values arrive, so a save needs no reset here.
          final editorKey = ValueKey('$current#$_revision');
          final Widget editor;
          if (current == _newKey) {
            editor = BotEditorPanel.create(
              key: editorKey,
              onSaved: (id) => _show(id ?? _mainKey),
              onCancel: () => _show(_mainKey),
              onDirtyChanged: (dirty) => _dirty = dirty,
            );
          } else if (selectedProfile != null) {
            editor = BotEditorPanel.profile(
              key: editorKey,
              profile: selectedProfile,
              onDeleted: () => _show(_mainKey),
              onCancel: () => _show(current),
              onDirtyChanged: (dirty) => _dirty = dirty,
            );
          } else {
            editor = BotEditorPanel.main(
              key: editorKey,
              initial: mainBot,
              onCancel: () => _show(_mainKey),
              onDirtyChanged: (dirty) => _dirty = dirty,
            );
          }

          return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            SizedBox(
              width: 320,
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                list,
                for (final item in side) ...[const SizedBox(height: FlowSpace.lg), item],
              ]),
            ),
            const SizedBox(width: FlowSpace.xl),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                editor,
                const SizedBox(height: FlowSpace.lg),
                numbersCard,
              ]),
            ),
          ]);
        }),
      ]),
    );
  }
}

/// What every assistant knows: counts from Bilgi bankası and its latest documents.
class _KnowledgeSummary extends ConsumerWidget {
  const _KnowledgeSummary();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final notes = ref.watch(knowledgeEntriesProvider);
    final documents = ref.watch(knowledgeDocumentsProvider);
    String count(AsyncValue<List<Object>> value, String unit) => value.when(
          data: (items) => upperTr('${formatCount(items.length)} $unit'),
          loading: () => '…',
          error: (error, stack) => '—',
        );
    final latest = (documents.valueOrNull ?? const <KnowledgeDocument>[]).take(3).toList();
    return SectionCard(
      title: 'Asistanların bildikleri',
      subtitle: 'Bilgi bankası tüm asistanlarınızda ortaktır.',
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        _CountRow(label: 'Notlar', value: count(notes, 'not')),
        _CountRow(label: 'Belgeler', value: count(documents, 'belge')),
        if (latest.isNotEmpty) ...[
          const SizedBox(height: FlowSpace.sm),
          const Divider(height: FlowSpace.lg),
          for (final document in latest)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: FlowSpace.xs),
              child: Row(children: [
                Icon(knowledgeFormatIcon(document.format), size: 18),
                const SizedBox(width: FlowSpace.sm + 2),
                Expanded(
                  child: Text(document.title,
                      maxLines: 1, overflow: TextOverflow.ellipsis, style: theme.textTheme.bodyMedium),
                ),
                const SizedBox(width: FlowSpace.sm),
                KnowledgeDocumentBadge(document),
              ]),
            ),
        ],
        const SizedBox(height: FlowSpace.md),
        OutlinedButton.icon(
          onPressed: () => openShellDestination(ref, ShellDestinationId.knowledge),
          icon: const Icon(Icons.menu_book_outlined, size: 18),
          label: const Text('Bilgi bankasını aç'),
        ),
      ]),
    );
  }
}

/// A label with its mono count at the far right.
class _CountRow extends StatelessWidget {
  const _CountRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final c = FlowColors.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: FlowSpace.xs),
      child: Row(children: [
        Expanded(child: Text(label, style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: c.muted))),
        const SizedBox(width: FlowSpace.md),
        Text(value, style: FlowText.mono(context, color: c.text)),
      ]),
    );
  }
}

/// Administrators can set up instructions, notes and the catalog for their sector.
class _IndustryPackCard extends StatelessWidget {
  const _IndustryPackCard();

  @override
  Widget build(BuildContext context) {
    return SectionCard(
      title: 'Sektör paketi',
      subtitle: 'İşinize uygun talimatları, bilgi notlarını ve katalog türünü tek adımda hazırlar.',
      child: Align(
        alignment: Alignment.centerLeft,
        child: OutlinedButton.icon(
          onPressed: () => showModalBottomSheet<void>(
            context: context,
            isScrollControlled: true,
            useSafeArea: true,
            builder: (_) => const IndustryPackSheet(),
          ),
          icon: const Icon(Icons.auto_awesome_outlined, size: 18),
          label: const Text('Sektör paketi kur'),
        ),
      ),
    );
  }
}

/// One number with a picker: the main assistant, an extra assistant, or none.
class NumberBotCard extends ConsumerStatefulWidget {
  const NumberBotCard({super.key, required this.number, required this.mainBot, required this.profiles});

  final BotNumber number;
  final BotConfig mainBot;
  final List<BotProfile> profiles;

  @override
  ConsumerState<NumberBotCard> createState() => _NumberBotCardState();
}

class _NumberBotCardState extends ConsumerState<NumberBotCard> {
  bool _saving = false;

  Future<void> _assign(String value) async {
    final tenant = ref.read(selectedTenantProvider);
    if (tenant == null || value == widget.number.assignment) return;
    setState(() => _saving = true);
    try {
      await ref.read(botRepositoryProvider).setNumberBot(
            tenant.id,
            widget.number.id,
            enabled: value != 'off',
            profileId: value == 'off' || value == 'main' ? null : value,
          );
      if (mounted) showAppSnack(context, 'Numaranın asistanı güncellendi.');
    } catch (error) {
      if (mounted) showAppSnack(context, botErrorMessage(error), error: true);
    } finally {
      ref.invalidate(botNumbersProvider);
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = FlowColors.of(context);
    final theme = Theme.of(context);
    final number = widget.number;
    final known = {'main', 'off', ...widget.profiles.map((p) => p.id)};
    final value = known.contains(number.assignment) ? number.assignment : 'main';
    final named = number.title != number.displayPhone;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Row(children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: c.raised,
            borderRadius: FlowRadius.controlAll,
            border: Border.all(color: c.border),
          ),
          child: Icon(Icons.phone_iphone_outlined, size: 19, color: c.muted),
        ),
        const SizedBox(width: FlowSpace.md),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            if (named)
              Text(number.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: theme.textTheme.titleSmall),
            Text(
              formatPhone(number.displayPhone),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: named ? FlowText.mono(context, size: 12) : FlowText.mono(context, size: 14, color: c.text),
            ),
          ]),
        ),
        if (_saving) const SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2)),
      ]),
      const SizedBox(height: FlowSpace.md),
      DropdownButtonFormField<String>(
        key: ValueKey('${number.id}:$value'),
        initialValue: value,
        isExpanded: true,
        decoration: const InputDecoration(labelText: 'Yanıt veren asistan'),
        items: [
          DropdownMenuItem(
            value: 'main',
            child: Text('Ana asistan: ${widget.mainBot.name}', maxLines: 1, overflow: TextOverflow.ellipsis),
          ),
          for (final profile in widget.profiles)
            DropdownMenuItem(
              value: profile.id,
              child: Text(profile.config.name, maxLines: 1, overflow: TextOverflow.ellipsis),
            ),
          const DropdownMenuItem(
            value: 'off',
            child: Text('Asistan kapalı, ekip yanıtlar', maxLines: 1, overflow: TextOverflow.ellipsis),
          ),
        ],
        onChanged: _saving ? null : (selected) => selected == null ? null : _assign(selected),
      ),
    ]);
  }
}
