import 'package:flutter/material.dart';

import '../../../ui/ui.dart';
import '../../onboarding/data/onboarding_errors.dart';

/// A screen a member may open, keyed like `tenant_module_keys()`.
class PermissionOption {
  const PermissionOption(this.key, this.label);

  final String key;
  final String label;

  static const options = [
    PermissionOption('dashboard', 'Ana sayfa'),
    PermissionOption('inbox', 'Sohbetler ve müşteriler'),
    PermissionOption('handoff', 'Temsilci bekleyen'),
    PermissionOption('bot', 'Asistan'),
    PermissionOption('knowledge', 'Bilgi bankası'),
    PermissionOption('campaigns', 'Kampanyalar'),
    PermissionOption('templates', 'Şablonlar'),
    PermissionOption('catalog', 'Katalog ve rezervasyon'),
    PermissionOption('users', 'Ekip yönetimi'),
  ];

  static Iterable<String> get keys => options.map((option) => option.key);

  static List<String> labelsFor(Set<String> permissions) => [
        for (final option in options)
          if (permissions.contains(option.key)) option.label,
      ];
}

/// "Yönetici", "Temsilci".
String roleLabel(String role) => role == 'admin' ? 'Yönetici' : 'Temsilci';

/// One line for a badge: "Yönetici · Tüm ekranlar", "Temsilci · Sohbetler ve müşteriler".
String accessSummary(String role, Set<String> permissions) {
  if (role == 'admin') return 'Yönetici · Tüm ekranlar';
  final labels = PermissionOption.labelsFor(permissions);
  return 'Temsilci · ${labels.isEmpty ? 'Yetki yok' : labels.join(', ')}';
}

/// What a submitted [AccessSheet] holds. [email] is set only when the sheet asked for one.
typedef AccessChoice = ({String? email, String role, Set<String> permissions});

/// A bottom sheet for choosing a role and the screens a member may open; it also asks
/// for an email address when inviting. Errors from [onSubmit] stay in the sheet.
class AccessSheet extends StatefulWidget {
  const AccessSheet({
    super.key,
    required this.title,
    required this.confirmLabel,
    required this.onSubmit,
    this.subtitle,
    this.askEmail = false,
    this.initialRole = 'user',
    this.initialPermissions = const {'inbox'},
    this.footnote,
  });

  final String title;
  final String? subtitle;
  final String confirmLabel;
  final bool askEmail;
  final String initialRole;
  final Set<String> initialPermissions;
  final String? footnote;

  /// Runs the server call; the sheet closes with the choice when it succeeds.
  final Future<void> Function(AccessChoice choice) onSubmit;

  @override
  State<AccessSheet> createState() => _AccessSheetState();
}

class _AccessSheetState extends State<AccessSheet> {
  final _form = GlobalKey<FormState>();
  final _email = TextEditingController();
  late String _role = widget.initialRole;
  late Set<String> _permissions =
      widget.initialRole == 'admin' ? PermissionOption.keys.toSet() : {...widget.initialPermissions};
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    super.dispose();
  }

  String? _validateEmail(String? value) {
    final address = value?.trim() ?? '';
    if (address.isEmpty) return 'E-posta adresini girin.';
    if (address.length > 320 || !RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(address)) {
      return 'Geçerli bir e-posta adresi girin.';
    }
    return null;
  }

  void _setRole(String role) => setState(() {
        _role = role;
        if (role == 'admin') _permissions = PermissionOption.keys.toSet();
      });

  Future<void> _submit() async {
    if (_saving || !(_form.currentState?.validate() ?? false)) return;
    final choice = (
      email: widget.askEmail ? _email.text.trim() : null,
      role: _role,
      permissions: _role == 'admin' ? PermissionOption.keys.toSet() : {..._permissions},
    );
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.onSubmit(choice);
      if (mounted) Navigator.of(context).pop(choice);
    } catch (error) {
      if (mounted) setState(() => _error = onboardingErrorMessage(error));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final c = FlowColors.of(context);
    final admin = _role == 'admin';
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(FlowSpace.xl - 4, FlowSpace.xs, FlowSpace.xl - 4, FlowSpace.xl - 4),
          child: Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 560),
              child: Form(
                key: _form,
                child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  Text(widget.title, style: theme.textTheme.headlineSmall),
                  if (widget.subtitle != null) ...[
                    const SizedBox(height: 6),
                    Text(widget.subtitle!, style: FlowText.mono(context, size: 13)),
                  ],
                  const SizedBox(height: FlowSpace.xl - 4),
                  if (widget.askEmail) ...[
                    TextFormField(
                      controller: _email,
                      enabled: !_saving,
                      autofocus: true,
                      keyboardType: TextInputType.emailAddress,
                      autocorrect: false,
                      textInputAction: TextInputAction.done,
                      validator: _validateEmail,
                      decoration: const InputDecoration(labelText: 'E-posta', hintText: 'ornek@firma.com'),
                    ),
                    const SizedBox(height: FlowSpace.xl - 4),
                  ],
                  Text('Rol', style: theme.textTheme.titleSmall),
                  const SizedBox(height: FlowSpace.sm),
                  SegmentedButton<String>(
                    showSelectedIcon: false,
                    segments: const [
                      ButtonSegment(value: 'user', label: Text('Temsilci'), icon: Icon(Icons.person_outline, size: 18)),
                      ButtonSegment(value: 'admin', label: Text('Yönetici'), icon: Icon(Icons.shield_outlined, size: 18)),
                    ],
                    selected: {_role},
                    onSelectionChanged: _saving ? null : (value) => _setRole(value.first),
                  ),
                  const SizedBox(height: FlowSpace.xl - 4),
                  Text('Açabileceği ekranlar', style: theme.textTheme.titleSmall),
                  const SizedBox(height: FlowSpace.sm),
                  Wrap(spacing: 6, runSpacing: 6, children: [
                    for (final option in PermissionOption.options)
                      FilterChip(
                        label: Text(option.label),
                        selected: _permissions.contains(option.key),
                        onSelected: admin || _saving
                            ? null
                            : (selected) => setState(() {
                                  selected ? _permissions.add(option.key) : _permissions.remove(option.key);
                                }),
                      ),
                  ]),
                  if (admin) ...[
                    const SizedBox(height: FlowSpace.sm),
                    Text('Yönetici tüm ekranları açar; abonelik ve WhatsApp numaralarını da yönetir.',
                        style: theme.textTheme.bodySmall),
                  ],
                  if (widget.footnote != null) ...[
                    const SizedBox(height: FlowSpace.lg),
                    Text(widget.footnote!, style: theme.textTheme.bodySmall),
                  ],
                  if (_error != null)
                    Semantics(
                      liveRegion: true,
                      child: Container(
                        margin: const EdgeInsets.only(top: FlowSpace.lg),
                        padding: const EdgeInsets.all(FlowSpace.md),
                        decoration: BoxDecoration(
                          color: c.dangerSoft,
                          borderRadius: FlowRadius.controlAll,
                          border: Border.all(color: c.danger),
                        ),
                        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Icon(Icons.error_outline, size: 18, color: c.danger),
                          const SizedBox(width: 10),
                          Expanded(child: Text(_error!, style: theme.textTheme.bodyMedium)),
                        ]),
                      ),
                    ),
                  const SizedBox(height: FlowSpace.xl - 4),
                  Wrap(alignment: WrapAlignment.end, spacing: FlowSpace.sm, runSpacing: FlowSpace.sm, children: [
                    TextButton(
                      onPressed: _saving ? null : () => Navigator.of(context).pop(),
                      style: TextButton.styleFrom(foregroundColor: c.muted),
                      child: const Text('Vazgeç'),
                    ),
                    FilledButton(
                      onPressed: _saving ? null : _submit,
                      child: _saving
                          ? const SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2))
                          : Text(widget.confirmLabel),
                    ),
                  ]),
                ]),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
