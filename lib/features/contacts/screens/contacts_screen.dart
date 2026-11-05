import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../ui/ui.dart';
import '../../tenancy/providers/tenant_providers.dart';
import '../data/contact_csv.dart';
import '../models/contact.dart';
import '../providers/contacts_providers.dart';

/// Turkish guidance for contact RPC failures; raw server text is never shown.
String contactsErrorMessage(Object error) {
  if (error is PostgrestException) {
    switch (error.code) {
      case '42501':
        return 'Bu işlem için yetkiniz yok.';
      case '22023':
        return 'Bilgileri kontrol edin: telefon numarası geçerli olmalı ve izin için açıklama girilmeli.';
    }
  }
  if (error is TimeoutException) {
    return 'Sunucu yanıt vermedi. Bağlantınızı kontrol edip tekrar deneyin.';
  }
  return 'İşlem tamamlanamadı. Tekrar deneyin.';
}

/// How a marketing consent was recorded (`consented_contacts.consent_source`), or null
/// when there is nothing useful to show.
String? consentSourceLabel(String? source) => switch (source) {
      'manual' => 'Elle',
      'import' => 'CSV',
      'whatsapp' => 'WhatsApp',
      'form' => 'Form',
      _ => null,
    };

bool _canManageConsent(WidgetRef ref) =>
    ref
        .watch(currentMembershipProvider)
        .valueOrNull
        ?.hasPermission('campaigns') ??
    false;

/// Müşteriler → Kişiler: search, CSV import and the contact list with consent state.
class ContactsScreen extends ConsumerStatefulWidget {
  const ContactsScreen({super.key});

  @override
  ConsumerState<ContactsScreen> createState() => _ContactsScreenState();
}

class _ContactsScreenState extends ConsumerState<ContactsScreen> {
  final _searchController = TextEditingController();
  Timer? _debounce;

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  void _onSearch(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), () {
      ref.read(contactsControllerProvider.notifier).setSearch(value);
    });
  }

  @override
  Widget build(BuildContext context) {
    final page = ref.watch(contactsControllerProvider);
    final tenant = ref.watch(selectedTenantProvider);
    if (tenant == null) return const SizedBox.shrink();
    final searching = ref.read(contactsControllerProvider.notifier).search.isNotEmpty ||
        _searchController.text.trim().isNotEmpty;

    final Widget body;
    if (page.hasError && !page.isLoading) {
      body = ErrorState(
        title: 'Kişiler yüklenemedi',
        onRetry: () => ref.invalidate(contactsControllerProvider),
      );
    } else if (page.valueOrNull case final data?) {
      body = data.items.isEmpty
          ? _EmptyContacts(searching: searching)
          : Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              _ContactsSummary(page: data, searching: searching),
              const SizedBox(height: FlowSpace.md),
              _ContactList(
                contacts: data.items,
                onOpen: (contact) => _openEditor(tenant.id, contact),
              ),
              if (data.hasMore) ...[
                const SizedBox(height: FlowSpace.md),
                Center(
                  child: data.loadingMore
                      ? const Padding(
                          padding: EdgeInsets.all(FlowSpace.md),
                          child: SizedBox.square(dimension: 24, child: CircularProgressIndicator(strokeWidth: 2)),
                        )
                      : TextButton(onPressed: _loadMore, child: const Text('Daha fazla göster')),
                ),
              ],
            ]);
    } else {
      body = const _ListFrame(child: LoadingList(rows: 6));
    }

    return RefreshIndicator(
      onRefresh: () => ref.refresh(contactsControllerProvider.future),
      child: AppPage(
        toolbar: PageToolbar(
          leading: SearchField(
            hint: 'Ad, telefon veya etiket ara',
            controller: _searchController,
            onChanged: _onSearch,
          ),
          actions: [
            OutlinedButton.icon(
              onPressed: () => _import(tenant.id),
              icon: const Icon(Icons.file_upload_outlined, size: 18),
              label: const Text('CSV ile içe aktar'),
            ),
            FilledButton.icon(
              onPressed: () => _openEditor(tenant.id, null),
              icon: const Icon(Icons.add_rounded, size: 20),
              label: const Text('Kişi ekle'),
            ),
          ],
        ),
        children: [body],
      ),
    );
  }

  Future<void> _loadMore() async {
    try {
      await ref.read(contactsControllerProvider.notifier).loadMore();
    } catch (error) {
      if (mounted) showAppSnack(context, contactsErrorMessage(error), error: true);
    }
  }

  Future<void> _openEditor(String tenantId, Contact? contact) async {
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (_) => ContactEditorSheet(tenantId: tenantId, contact: contact),
    );
    if (saved == true) ref.invalidate(contactsControllerProvider);
  }

  Future<void> _import(String tenantId) async {
    final picked = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['csv', 'txt'],
      withData: true,
    );
    final bytes = picked?.files.single.bytes;
    if (bytes == null || !mounted) return;
    ContactImportPreview preview;
    try {
      preview = parseContactCsv(bytes);
    } on ContactCsvException catch (error) {
      showAppSnack(context, error.message, error: true);
      return;
    }
    final result = await showDialog<ContactImportResult>(
      context: context,
      barrierDismissible: false,
      builder: (_) => ImportPreviewDialog(tenantId: tenantId, preview: preview),
    );
    if (result == null || !mounted) return;
    ref.invalidate(contactsControllerProvider);
    await showDialog<void>(
      context: context,
      builder: (context) => ImportResultDialog(result: result),
    );
  }
}

/// What an import changed: mono counts and the first skipped lines.
class ImportResultDialog extends StatelessWidget {
  const ImportResultDialog({super.key, required this.result});

  final ContactImportResult result;

  @override
  Widget build(BuildContext context) {
    final c = FlowColors.of(context);
    return AlertDialog(
      title: const Text('İçe aktarma tamamlandı'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            KeyValueRow(label: 'Yeni kişi', value: formatCount(result.created), mono: true),
            KeyValueRow(label: 'Güncellenen kişi', value: formatCount(result.updated), mono: true),
            KeyValueRow(
              label: 'Pazarlama izni eklenen',
              value: formatCount(result.consented),
              mono: true,
              valueColor: result.consented > 0 ? c.accentText : null,
            ),
            if (result.skippedLines.isNotEmpty) ...[
              KeyValueRow(
                label: 'Atlanan satır',
                value: formatCount(result.skippedLines.length),
                mono: true,
                valueColor: c.warning,
              ),
              const SizedBox(height: FlowSpace.sm),
              for (final (line, reason) in result.skippedLines.take(5))
                Padding(
                  padding: const EdgeInsets.only(top: FlowSpace.xs),
                  child: Text.rich(
                    TextSpan(children: [
                      TextSpan(text: 'Satır $line', style: FlowText.mono(context, size: 12, color: c.text)),
                      TextSpan(text: ': ${importSkipReason(reason)}'),
                    ]),
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
            ],
          ],
        ),
      ),
      actions: [
        FilledButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Tamam')),
      ],
    );
  }
}

/// "214 KİŞİ · 168 PAZARLAMA İZNİ · 3 LİSTEDEN ÇIKTI" for the loaded rows.
class _ContactsSummary extends StatelessWidget {
  const _ContactsSummary({required this.page, required this.searching});

  final ContactsPage page;
  final bool searching;

  @override
  Widget build(BuildContext context) {
    final c = FlowColors.of(context);
    final items = page.items;
    final count = formatCount(items.length);
    final total = searching
        ? (page.hasMore ? 'İlk $count sonuç' : '$count sonuç')
        : (page.hasMore ? 'İlk $count kişi' : '$count kişi');
    final consentVisible = items.any((item) => item.consent != ConsentState.hidden);
    final granted = items.where((item) => item.consent == ConsentState.granted).length;
    final optedOut = items.where((item) => item.consent == ConsentState.optedOut).length;
    // Lines break only between the parts, never inside "1 LİSTEDEN ÇIKTI".
    String part(String text) => upperTr(text).replaceAll(' ', ' ');
    return Text.rich(
      TextSpan(children: [
        TextSpan(text: part(total)),
        if (consentVisible) ...[
          const TextSpan(text: ' · '),
          TextSpan(text: part('${formatCount(granted)} pazarlama izni'), style: TextStyle(color: c.accentText)),
          const TextSpan(text: ' · '),
          TextSpan(text: part('${formatCount(optedOut)} listeden çıktı')),
        ],
      ]),
      style: FlowText.caps(context, color: c.muted),
    );
  }
}

class _EmptyContacts extends StatelessWidget {
  const _EmptyContacts({required this.searching});
  final bool searching;

  @override
  Widget build(BuildContext context) => searching
      ? const EmptyState(
          title: 'Eşleşen kişi yok',
          message: 'Aramanızla eşleşen kişi yok. Farklı bir ad, numara veya etiket deneyin.',
          icon: Icons.search_off_rounded,
        )
      : const EmptyState(
          title: 'Henüz kişi yok',
          message: 'WhatsApp\'tan yazan müşteriler otomatik eklenir; '
              'kişi ekleyebilir veya CSV dosyasından içe aktarabilirsiniz.',
          icon: Icons.people_outline_rounded,
        );
}

/// The bordered surface around the contact rows.
class _ListFrame extends StatelessWidget {
  const _ListFrame({required this.child, this.padded = true});

  final Widget child;
  final bool padded;

  @override
  Widget build(BuildContext context) {
    final c = FlowColors.of(context);
    return Container(
      padding: padded ? const EdgeInsets.symmetric(horizontal: 20, vertical: FlowSpace.sm) : null,
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: FlowRadius.cardAll,
        border: Border.all(color: c.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: child,
    );
  }
}

/// A table on wide screens (person, phone, consent, last conversation), a compact
/// list on phones. Tapping a row opens the editor.
class _ContactList extends StatelessWidget {
  const _ContactList({required this.contacts, required this.onOpen});

  final List<Contact> contacts;
  final ValueChanged<Contact> onOpen;

  static const _tableBreakpoint = 720.0;

  @override
  Widget build(BuildContext context) {
    final c = FlowColors.of(context);
    final consentVisible = contacts.any((item) => item.consent != ConsentState.hidden);
    return _ListFrame(
      padded: false,
      child: LayoutBuilder(builder: (context, constraints) {
        final table = constraints.maxWidth >= _tableBreakpoint;
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          if (table) ...[
            _TableHeader(consentVisible: consentVisible),
            Divider(height: 1, color: c.border),
          ],
          for (final (index, contact) in contacts.indexed) ...[
            if (index > 0) Divider(height: 1, color: c.border),
            table
                ? _TableRow(contact: contact, consentVisible: consentVisible, onTap: () => onOpen(contact))
                : _CompactRow(contact: contact, onTap: () => onOpen(contact)),
          ],
        ]);
      }),
    );
  }
}

/// Column flex factors: person, phone, consent, last conversation.
const _columns = [5, 3, 3, 2];

/// Turkish numbers grouped ("+90 555 111 22 33"); others as stored E.164 ("+4915123456789"),
/// so a foreign country code is never split.
String contactPhoneLabel(Contact contact) =>
    contact.phone.startsWith('90') && contact.phone.length == 12 ? formatPhone(contact.phone) : contact.displayPhone;

String _nameOf(Contact contact) => contact.fullName.isEmpty ? contactPhoneLabel(contact) : contact.fullName;

String _lastContact(Contact contact) =>
    contact.lastContactedAt == null ? '—' : upperTr(formatListStamp(contact.lastContactedAt!));

class _TableHeader extends StatelessWidget {
  const _TableHeader({required this.consentVisible});

  final bool consentVisible;

  @override
  Widget build(BuildContext context) {
    Widget cell(String label, int flex, {TextAlign align = TextAlign.left}) => Expanded(
          flex: flex,
          child: Text(
            upperTr(label),
            style: FlowText.caps(context),
            textAlign: align,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        );
    return ExcludeSemantics(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: FlowSpace.md),
        child: Row(children: [
          cell('Kişi', _columns[0]),
          const SizedBox(width: FlowSpace.lg),
          cell('Telefon', _columns[1]),
          if (consentVisible) ...[
            const SizedBox(width: FlowSpace.lg),
            cell('Pazarlama izni', _columns[2]),
          ],
          const SizedBox(width: FlowSpace.lg),
          cell('Son sohbet', _columns[3], align: TextAlign.right),
        ]),
      ),
    );
  }
}

class _TableRow extends StatelessWidget {
  const _TableRow({required this.contact, required this.consentVisible, required this.onTap});

  final Contact contact;
  final bool consentVisible;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = FlowColors.of(context);
    final theme = Theme.of(context);
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 13),
        child: Row(children: [
          Expanded(
            flex: _columns[0],
            child: Row(children: [
              InitialsAvatar(contact.fullName.isEmpty ? '?' : contact.fullName, size: 32),
              const SizedBox(width: FlowSpace.md),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  // The phone has its own column, so an unnamed contact says so here.
                  Text(
                    contact.fullName.isEmpty ? 'Adı yok' : contact.fullName,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontSize: 15,
                      color: contact.fullName.isEmpty ? c.muted : null,
                      fontWeight: contact.fullName.isEmpty ? FontWeight.w500 : null,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (contact.tags.isNotEmpty)
                    Text(
                      contact.tags.take(4).join(' · '),
                      style: theme.textTheme.bodySmall?.copyWith(color: c.faint),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                ]),
              ),
            ]),
          ),
          const SizedBox(width: FlowSpace.lg),
          Expanded(
            flex: _columns[1],
            child: Text(
              contactPhoneLabel(contact),
              style: FlowText.mono(context, size: 13),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (consentVisible) ...[
            const SizedBox(width: FlowSpace.lg),
            Expanded(
              flex: _columns[2],
              child: Align(
                alignment: Alignment.centerLeft,
                child: ConsentBadge(state: contact.consent, source: contact.consentSource),
              ),
            ),
          ],
          const SizedBox(width: FlowSpace.lg),
          Expanded(
            flex: _columns[3],
            child: Text(
              _lastContact(contact),
              textAlign: TextAlign.right,
              style: FlowText.mono(context, size: 13),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ]),
      ),
    );
  }
}

class _CompactRow extends StatelessWidget {
  const _CompactRow({required this.contact, required this.onTap});

  final Contact contact;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = FlowColors.of(context);
    final theme = Theme.of(context);
    final showBadge = contact.consent != ConsentState.hidden;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: FlowSpace.lg, vertical: FlowSpace.md),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          InitialsAvatar(contact.fullName.isEmpty ? '?' : contact.fullName, size: 40),
          const SizedBox(width: FlowSpace.md),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(
                _nameOf(contact),
                style: theme.textTheme.titleSmall?.copyWith(fontSize: 15),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              if (contact.fullName.isNotEmpty) ...[
                const SizedBox(height: 2),
                Text(
                  contactPhoneLabel(contact),
                  style: FlowText.mono(context, size: 13),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
              if (showBadge || contact.tags.isNotEmpty) ...[
                const SizedBox(height: 6),
                Wrap(
                  spacing: FlowSpace.sm,
                  runSpacing: FlowSpace.xs,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    if (showBadge) ConsentBadge(state: contact.consent, source: contact.consentSource),
                    if (contact.tags.isNotEmpty)
                      Text(
                        contact.tags.take(4).join(' · '),
                        style: theme.textTheme.bodySmall?.copyWith(color: c.faint),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                  ],
                ),
              ],
            ]),
          ),
          const SizedBox(width: FlowSpace.sm),
          Text(_lastContact(contact), style: FlowText.mono(context, size: 12)),
        ]),
      ),
    );
  }
}

/// Marketing consent as a status badge: "VAR · CSV", "YOK" or "LİSTEDEN ÇIKTI".
/// Nothing for members who may not see consent.
class ConsentBadge extends StatelessWidget {
  const ConsentBadge({super.key, required this.state, this.source});

  final ConsentState state;

  /// `consent_source` of a granted consent; adds where it came from.
  final String? source;

  @override
  Widget build(BuildContext context) {
    final from = consentSourceLabel(source);
    final (label, tone, spoken) = switch (state) {
      ConsentState.granted => (
          from == null ? 'Var' : 'Var · $from',
          FlowTone.accent,
          from == null ? 'Pazarlama izni var' : 'Pazarlama izni var, kaynak: $from',
        ),
      ConsentState.optedOut => ('Listeden çıktı', FlowTone.danger, 'Pazarlama listesinden çıktı'),
      ConsentState.none => ('Yok', FlowTone.neutral, 'Pazarlama izni yok'),
      ConsentState.hidden => ('', FlowTone.neutral, ''),
    };
    if (label.isEmpty) return const SizedBox.shrink();
    return Semantics(label: spoken, excludeSemantics: true, child: StatusBadge(label, tone: tone));
  }
}

/// Create or edit a contact. The phone number identifies a contact and is fixed
/// after creation; consent is recorded with a basis note.
class ContactEditorSheet extends ConsumerStatefulWidget {
  const ContactEditorSheet({super.key, required this.tenantId, this.contact});

  final String tenantId;
  final Contact? contact;

  @override
  ConsumerState<ContactEditorSheet> createState() => _ContactEditorSheetState();
}

class _ContactEditorSheetState extends ConsumerState<ContactEditorSheet> {
  final _formKey = GlobalKey<FormState>();
  late final _phone = TextEditingController(text: widget.contact?.displayPhone ?? '');
  late final _name = TextEditingController(text: widget.contact?.fullName ?? '');
  late final _email = TextEditingController(text: widget.contact?.email ?? '');
  late final _tags = TextEditingController(text: widget.contact?.tags.join(', ') ?? '');
  final _consentNote = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    for (final controller in [_phone, _name, _email, _tags, _consentNote]) {
      controller.dispose();
    }
    super.dispose();
  }

  String get _normalizedPhone =>
      widget.contact?.phone ?? normalizeContactPhone(_phone.text) ?? '';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final c = FlowColors.of(context);
    final contact = widget.contact;
    final canConsent = _canManageConsent(ref);
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(contact == null ? 'Yeni kişi' : 'Kişiyi düzenle', style: theme.textTheme.headlineSmall),
              const SizedBox(height: FlowSpace.lg),
              TextFormField(
                controller: _phone,
                readOnly: contact != null || _busy,
                keyboardType: TextInputType.phone,
                style: FlowText.mono(context, size: 15, color: c.text),
                decoration: const InputDecoration(
                  labelText: 'Telefon',
                  hintText: '0555 111 22 33 veya +49 ...',
                ),
                validator: (value) => contact == null &&
                        normalizeContactPhone(value ?? '') == null
                    ? 'Geçerli bir telefon numarası girin.'
                    : null,
              ),
              const SizedBox(height: FlowSpace.md),
              TextFormField(
                controller: _name,
                readOnly: _busy,
                maxLength: 120,
                decoration: const InputDecoration(labelText: 'Ad soyad'),
              ),
              TextFormField(
                controller: _email,
                readOnly: _busy,
                keyboardType: TextInputType.emailAddress,
                decoration: const InputDecoration(labelText: 'E-posta (isteğe bağlı)'),
                validator: (value) {
                  final text = value?.trim() ?? '';
                  return text.isEmpty || text.contains('@')
                      ? null
                      : 'Geçerli bir e-posta girin.';
                },
              ),
              const SizedBox(height: FlowSpace.md),
              TextFormField(
                controller: _tags,
                readOnly: _busy,
                decoration: const InputDecoration(
                  labelText: 'Etiketler',
                  helperText: 'Virgülle ayırın. Kampanya segmentleri etiketleri kullanır.',
                ),
              ),
              if (contact != null && canConsent) ...[
                const Divider(height: 32),
                _ConsentSection(
                  contact: contact,
                  noteController: _consentNote,
                  busy: _busy,
                  onGrant: () => _setConsent(true),
                  onRevoke: () => _setConsent(false),
                ),
              ],
              if (_error != null) ...[
                const SizedBox(height: FlowSpace.md),
                Semantics(
                  liveRegion: true,
                  child: Text(_error!, style: theme.textTheme.bodyMedium?.copyWith(color: c.danger)),
                ),
              ],
              const SizedBox(height: FlowSpace.lg),
              Wrap(alignment: WrapAlignment.end, spacing: FlowSpace.sm, runSpacing: FlowSpace.sm, children: [
                TextButton(
                  onPressed: _busy ? null : () => Navigator.of(context).pop(false),
                  style: TextButton.styleFrom(foregroundColor: c.muted),
                  child: const Text('Kapat'),
                ),
                FilledButton(
                  onPressed: _busy ? null : _save,
                  child: _busy
                      ? const SizedBox(
                          height: 16,
                          width: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Kaydet'),
                ),
              ]),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _save() async {
    if (_busy || !(_formKey.currentState?.validate() ?? false)) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(contactsRepositoryProvider).save(
            tenantId: widget.tenantId,
            phone: _normalizedPhone,
            fullName: _name.text,
            email: _email.text,
            tags: _tags.text
                .split(',')
                .map((tag) => tag.trim())
                .where((tag) => tag.isNotEmpty)
                .toSet()
                .toList(),
          );
      if (mounted) Navigator.of(context).pop(true);
    } catch (error) {
      if (mounted) setState(() => _error = contactsErrorMessage(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _setConsent(bool grant) async {
    final note = _consentNote.text.trim();
    if (grant && note.length < 3) {
      setState(() => _error = 'İznin nasıl alındığını yazın (örn. "Mağazada imzalı form").');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(contactsRepositoryProvider).setConsent(
            tenantId: widget.tenantId,
            phone: _normalizedPhone,
            consent: grant,
            note: grant ? note : null,
          );
      if (mounted) Navigator.of(context).pop(true);
    } catch (error) {
      if (mounted) setState(() => _error = contactsErrorMessage(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }
}

class _ConsentSection extends StatelessWidget {
  const _ConsentSection({
    required this.contact,
    required this.noteController,
    required this.busy,
    required this.onGrant,
    required this.onRevoke,
  });

  final Contact contact;
  final TextEditingController noteController;
  final bool busy;
  final VoidCallback onGrant;
  final VoidCallback onRevoke;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final c = FlowColors.of(context);
    final status = switch (contact.consent) {
      ConsentState.granted =>
        'Pazarlama izni var (${formatDate(contact.consentedAt!)}). Kampanyalara dahil edilir.',
      ConsentState.optedOut =>
        'Kişi ${formatDate(contact.optedOutAt!)} tarihinde izni geri aldı. Kampanya gönderilmez.',
      _ => 'Pazarlama izni yok. Kampanya gönderilmez; destek mesajları etkilenmez.',
    };
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Wrap(
        spacing: FlowSpace.sm,
        runSpacing: FlowSpace.xs,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Text('Pazarlama izni', style: theme.textTheme.titleMedium),
          ConsentBadge(state: contact.consent, source: contact.consentSource),
        ],
      ),
      const SizedBox(height: 6),
      Text(status, style: theme.textTheme.bodyMedium?.copyWith(color: c.muted)),
      const SizedBox(height: FlowSpace.sm),
      if (contact.consent != ConsentState.granted) ...[
        TextField(
          controller: noteController,
          readOnly: busy,
          maxLength: 500,
          decoration: InputDecoration(
            labelText: contact.consent == ConsentState.optedOut
                ? 'Yeniden onayın kanıtı'
                : 'İzin nasıl alındı?',
            hintText: 'Örn. Mağazada imzalı form, 01.11.2026',
          ),
        ),
        Align(
          alignment: Alignment.centerRight,
          child: OutlinedButton(
            onPressed: busy ? null : onGrant,
            child: const Text('İzni kaydet'),
          ),
        ),
      ] else
        Align(
          alignment: Alignment.centerRight,
          child: TextButton(
            onPressed: busy ? null : onRevoke,
            style: TextButton.styleFrom(foregroundColor: c.danger),
            child: const Text('İzni geri al'),
          ),
        ),
    ]);
  }
}

/// Shows what the file contains and, when it marks consent, requires the basis
/// of that consent before importing.
class ImportPreviewDialog extends ConsumerStatefulWidget {
  const ImportPreviewDialog({
    super.key,
    required this.tenantId,
    required this.preview,
  });

  final String tenantId;
  final ContactImportPreview preview;

  @override
  ConsumerState<ImportPreviewDialog> createState() => _ImportPreviewDialogState();
}

class _ImportPreviewDialogState extends ConsumerState<ImportPreviewDialog> {
  final _note = TextEditingController();
  bool _confirmed = false;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final c = FlowColors.of(context);
    final preview = widget.preview;
    final canConsent = _canManageConsent(ref);
    final consentRows = canConsent ? preview.consentCount : 0;
    final needsBasis = consentRows > 0;
    final ready = preview.rows.isNotEmpty &&
        (!needsBasis || (_confirmed && _note.text.trim().length >= 3));
    return AlertDialog(
      title: const Text('Kişileri içe aktar'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Aktarılacak kişi: ${preview.rows.length}', style: theme.textTheme.bodyLarge),
            if (preview.issues.isNotEmpty) ...[
              const SizedBox(height: FlowSpace.xs),
              Text('Okunamayan satır: ${preview.issues.length}',
                  style: theme.textTheme.bodyMedium?.copyWith(color: c.warning)),
              for (final issue in preview.issues.take(5))
                Text(
                  issue.line > 0 ? 'Satır ${issue.line}: ${issue.message}' : issue.message,
                  style: theme.textTheme.bodySmall,
                ),
            ],
            if (preview.consentCount > 0 && !canConsent)
              const Padding(
                padding: EdgeInsets.only(top: FlowSpace.sm),
                child: Text(
                    'Dosyadaki pazarlama izinleri aktarılmayacak: izin kaydetmek için kampanya yetkisi gerekir.'),
              ),
            if (needsBasis) ...[
              const SizedBox(height: FlowSpace.md),
              Text('Pazarlama izni olan kişi: $consentRows', style: theme.textTheme.bodyLarge),
              const SizedBox(height: FlowSpace.sm),
              TextField(
                controller: _note,
                readOnly: _busy,
                maxLength: 500,
                onChanged: (_) => setState(() {}),
                decoration: const InputDecoration(
                  labelText: 'İzinler nasıl alındı?',
                  hintText: 'Örn. Web sitesi bülten formu',
                ),
              ),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                value: _confirmed,
                onChanged: _busy ? null : (value) => setState(() => _confirmed = value ?? false),
                title: const Text(
                    'Bu kişilerden ticari ileti için açık onay aldığımı ve kanıtını sakladığımı onaylıyorum.'),
              ),
            ],
            if (_error != null)
              Semantics(
                liveRegion: true,
                child: Text(_error!, style: theme.textTheme.bodyMedium?.copyWith(color: c.danger)),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.of(context).pop(),
          style: TextButton.styleFrom(foregroundColor: c.muted),
          child: const Text('Vazgeç'),
        ),
        FilledButton(
          onPressed: _busy || !ready ? null : () => _import(canConsent),
          child: _busy
              ? const SizedBox(
                  height: 16, width: 16, child: CircularProgressIndicator(strokeWidth: 2))
              : const Text('İçe aktar'),
        ),
      ],
    );
  }

  Future<void> _import(bool canConsent) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    final rows = canConsent
        ? widget.preview.rows
        : [
            for (final row in widget.preview.rows)
              ContactImportRow(
                line: row.line,
                phone: row.phone,
                fullName: row.fullName,
                email: row.email,
                tags: row.tags,
              ),
          ];
    try {
      final result = await ref.read(contactsRepositoryProvider).import(
            widget.tenantId,
            rows,
            consentNote: canConsent && widget.preview.consentCount > 0
                ? _note.text.trim()
                : null,
          );
      if (mounted) Navigator.of(context).pop(result);
    } catch (error) {
      if (mounted) {
        setState(() => _error =
            '${contactsErrorMessage(error)} Önceki bölümler aktarılmış olabilir; tekrar denemek güvenlidir.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }
}
