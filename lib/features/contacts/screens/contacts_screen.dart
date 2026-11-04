import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

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

String _date(DateTime value) {
  final local = value.toLocal();
  String two(int n) => n.toString().padLeft(2, '0');
  return '${two(local.day)}.${two(local.month)}.${local.year}';
}

bool _canManageConsent(WidgetRef ref) =>
    ref
        .watch(currentMembershipProvider)
        .valueOrNull
        ?.hasPermission('campaigns') ??
    false;

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

    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
        child: Column(children: [
          Row(children: [
            Expanded(
              child: Text('Kişiler', style: Theme.of(context).textTheme.titleLarge),
            ),
            IconButton(
              tooltip: 'CSV içe aktar',
              onPressed: () => _import(tenant.id),
              icon: const Icon(Icons.upload_file),
            ),
            FilledButton.icon(
              onPressed: () => _openEditor(tenant.id, null),
              icon: const Icon(Icons.person_add_alt),
              label: const Text('Kişi ekle'),
            ),
          ]),
          const SizedBox(height: 8),
          TextField(
            controller: _searchController,
            onChanged: _onSearch,
            textInputAction: TextInputAction.search,
            decoration: const InputDecoration(
              prefixIcon: Icon(Icons.search),
              hintText: 'Ad, telefon veya etiket ara',
            ),
          ),
        ]),
      ),
      Expanded(
        child: page.when(
          data: (data) {
            if (data.items.isEmpty) {
              return _EmptyContacts(
                  searching: _searchController.text.trim().isNotEmpty);
            }
            return RefreshIndicator(
              onRefresh: () => ref.refresh(contactsControllerProvider.future),
              child: ListView.separated(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                itemCount: data.items.length + (data.hasMore ? 1 : 0),
                separatorBuilder: (_, __) => const SizedBox(height: 8),
                itemBuilder: (context, index) {
                  if (index == data.items.length) {
                    return Center(
                      child: data.loadingMore
                          ? const Padding(
                              padding: EdgeInsets.all(12),
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : TextButton(
                              onPressed: _loadMore,
                              child: const Text('Daha fazla göster'),
                            ),
                    );
                  }
                  final contact = data.items[index];
                  return _ContactTile(
                    contact: contact,
                    onTap: () => _openEditor(tenant.id, contact),
                  );
                },
              ),
            );
          },
          error: (_, __) => Center(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              const Text('Kişiler yüklenemedi.'),
              TextButton(
                onPressed: () => ref.invalidate(contactsControllerProvider),
                child: const Text('Tekrar dene'),
              ),
            ]),
          ),
          loading: () => const Center(child: CircularProgressIndicator()),
        ),
      ),
    ]);
  }

  Future<void> _loadMore() async {
    try {
      await ref.read(contactsControllerProvider.notifier).loadMore();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(contactsErrorMessage(error))));
      }
    }
  }

  Future<void> _openEditor(String tenantId, Contact? contact) async {
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
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
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(error.message)));
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
      builder: (context) => AlertDialog(
        title: const Text('İçe aktarma tamamlandı'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Yeni kişi: ${result.created}'),
            Text('Güncellenen kişi: ${result.updated}'),
            Text('Pazarlama izni eklenen: ${result.consented}'),
            if (result.skippedLines.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text('Atlanan satırlar (${result.skippedLines.length}):'),
              for (final (line, reason) in result.skippedLines.take(5))
                Text('Satır $line: ${importSkipReason(reason)}',
                    style: Theme.of(context).textTheme.bodySmall),
            ],
          ],
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Tamam'),
          ),
        ],
      ),
    );
  }
}

class _EmptyContacts extends StatelessWidget {
  const _EmptyContacts({required this.searching});
  final bool searching;

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            searching
                ? 'Aramanızla eşleşen kişi yok.'
                : 'Henüz kişi yok. WhatsApp\'tan yazan müşteriler otomatik eklenir; '
                    'kişi ekleyebilir veya CSV dosyasından içe aktarabilirsiniz.',
            textAlign: TextAlign.center,
          ),
        ),
      );
}

class _ContactTile extends StatelessWidget {
  const _ContactTile({required this.contact, required this.onTap});
  final Contact contact;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: ListTile(
        onTap: onTap,
        title: Text(contact.fullName.isEmpty ? contact.displayPhone : contact.fullName),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (contact.fullName.isNotEmpty) Text(contact.displayPhone),
            if (contact.tags.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(contact.tags.take(4).join(' · '),
                    style: theme.textTheme.bodySmall),
              ),
          ],
        ),
        trailing: ConsentBadge(state: contact.consent),
      ),
    );
  }
}

class ConsentBadge extends StatelessWidget {
  const ConsentBadge({super.key, required this.state});
  final ConsentState state;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final (label, color) = switch (state) {
      ConsentState.granted => ('İzinli', Colors.green.shade700),
      ConsentState.optedOut => ('İzin geri alındı', scheme.error),
      ConsentState.none => ('İzin yok', scheme.outline),
      ConsentState.hidden => ('', scheme.outline),
    };
    if (label.isEmpty) return const SizedBox.shrink();
    return Text(label, style: TextStyle(color: color, fontSize: 12));
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
    final contact = widget.contact;
    final canConsent = _canManageConsent(ref);
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(contact == null ? 'Yeni kişi' : 'Kişiyi düzenle',
                  style: theme.textTheme.titleLarge),
              const SizedBox(height: 12),
              TextFormField(
                controller: _phone,
                readOnly: contact != null || _busy,
                keyboardType: TextInputType.phone,
                decoration: const InputDecoration(
                  labelText: 'Telefon',
                  hintText: '0555 111 22 33 veya +49 ...',
                ),
                validator: (value) => contact == null &&
                        normalizeContactPhone(value ?? '') == null
                    ? 'Geçerli bir telefon numarası girin.'
                    : null,
              ),
              const SizedBox(height: 12),
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
              const SizedBox(height: 12),
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
                const SizedBox(height: 12),
                Semantics(
                  liveRegion: true,
                  child: Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
                ),
              ],
              const SizedBox(height: 16),
              Wrap(alignment: WrapAlignment.end, spacing: 8, children: [
                TextButton(
                  onPressed: _busy ? null : () => Navigator.of(context).pop(false),
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
    final status = switch (contact.consent) {
      ConsentState.granted =>
        'Pazarlama izni var (${_date(contact.consentedAt!)}). Kampanyalara dahil edilir.',
      ConsentState.optedOut =>
        'Kişi ${_date(contact.optedOutAt!)} tarihinde izni geri aldı. Kampanya gönderilmez.',
      _ => 'Pazarlama izni yok. Kampanya gönderilmez; destek mesajları etkilenmez.',
    };
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Text('Pazarlama izni', style: theme.textTheme.titleMedium),
      const SizedBox(height: 4),
      Text(status),
      const SizedBox(height: 8),
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
            Text('Aktarılacak kişi: ${preview.rows.length}'),
            if (preview.issues.isNotEmpty) ...[
              Text('Okunamayan satır: ${preview.issues.length}'),
              for (final issue in preview.issues.take(5))
                Text(
                  issue.line > 0 ? 'Satır ${issue.line}: ${issue.message}' : issue.message,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
            ],
            if (preview.consentCount > 0 && !canConsent)
              const Padding(
                padding: EdgeInsets.only(top: 8),
                child: Text(
                    'Dosyadaki pazarlama izinleri aktarılmayacak: izin kaydetmek için kampanya yetkisi gerekir.'),
              ),
            if (needsBasis) ...[
              const SizedBox(height: 12),
              Text('Pazarlama izni olan kişi: $consentRows'),
              const SizedBox(height: 8),
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
                value: _confirmed,
                onChanged: _busy ? null : (value) => setState(() => _confirmed = value ?? false),
                title: const Text(
                    'Bu kişilerden ticari ileti için açık onay aldığımı ve kanıtını sakladığımı onaylıyorum.'),
              ),
            ],
            if (_error != null)
              Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.of(context).pop(),
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
