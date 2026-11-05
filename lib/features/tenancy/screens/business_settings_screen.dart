import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../ui/ui.dart';
import '../data/business_profile_repository.dart';
import '../models/tenant.dart';
import '../providers/tenant_providers.dart';

/// Identity colors offered for a business (data, not theme colors).
const businessColorPresets = <(String, String)>[
  ('Lacivert', '#1F4B99'),
  ('Zümrüt', '#0F7B5F'),
  ('Bordo', '#9B2335'),
  ('Turuncu', '#C2410C'),
  ('Mor', '#6D28D9'),
  ('Antrasit', '#334155'),
];

/// Ayarlar → İşletme (administrators): the business name and identity color shown in
/// the sidebar, the business switcher and invites. Saved through an audited RPC.
class BusinessSettingsScreen extends ConsumerStatefulWidget {
  const BusinessSettingsScreen({super.key});

  @override
  ConsumerState<BusinessSettingsScreen> createState() => _BusinessSettingsScreenState();
}

class _BusinessSettingsScreenState extends ConsumerState<BusinessSettingsScreen> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController();
  String? _tenantId;
  String _hex = businessColorPresets.first.$2;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _name.addListener(_changed);
    final tenant = ref.read(selectedTenantProvider);
    if (tenant != null) _load(tenant);
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  void _changed() => setState(() {});

  void _load(Tenant tenant) {
    _tenantId = tenant.id;
    _hex = brandHex(tenant.brandColor);
    _name.text = tenant.name;
  }

  bool _dirty(Tenant tenant) => _name.text.trim() != tenant.name || _hex != brandHex(tenant.brandColor);

  String? _validateName(String? value) {
    final length = value?.trim().length ?? 0;
    if (length < 2) return 'İşletme adı en az 2 karakter olmalı.';
    if (length > 80) return 'İşletme adı en fazla 80 karakter olabilir.';
    return null;
  }

  Future<void> _save(Tenant tenant) async {
    if (_saving || !(_form.currentState?.validate() ?? false)) return;
    setState(() => _saving = true);
    try {
      await ref.read(businessProfileRepositoryProvider).update(
            tenantId: tenant.id,
            name: _name.text.trim(),
            brandColor: _hex,
          );
      // The sidebar, the switcher and every tenant-scoped screen read this list.
      ref.invalidate(accessibleTenantsProvider);
      if (mounted) showAppSnack(context, 'İşletme bilgileri kaydedildi');
    } catch (error) {
      if (mounted) showAppSnack(context, businessProfileErrorMessage(error), error: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<Tenant?>(selectedTenantProvider, (previous, next) {
      if (next != null && next.id != _tenantId) setState(() => _load(next));
    });
    final tenant = ref.watch(selectedTenantProvider);
    if (tenant == null) {
      return const AppPage(maxWidth: 820, children: [LoadingList(rows: 2)]);
    }
    final membership = ref.watch(currentMembershipProvider).valueOrNull;
    if (membership != null && !membership.isAdmin) {
      return const AppPage(maxWidth: 820, children: [
        EmptyState(
          icon: Icons.lock_outline,
          title: 'Yalnızca yöneticiler',
          message: 'İşletme adını ve rengini işletme yöneticileri değiştirebilir.',
        ),
      ]);
    }

    final theme = Theme.of(context);
    final c = FlowColors.of(context);
    final swatches = [
      if (!businessColorPresets.any((preset) => preset.$2 == brandHex(tenant.brandColor)))
        ('Mevcut renk', brandHex(tenant.brandColor)),
      ...businessColorPresets,
    ];
    final previewName = _name.text.trim().isEmpty ? tenant.name : _name.text.trim();

    return AppPage(maxWidth: 820, children: [
      SectionCard(
        title: 'İşletme',
        subtitle: 'Ekibinizin ve faturalarınızın gördüğü işletme bilgileri.',
        child: Form(
          key: _form,
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            TextFormField(
              controller: _name,
              enabled: !_saving,
              maxLength: 80,
              textCapitalization: TextCapitalization.words,
              textInputAction: TextInputAction.done,
              validator: _validateName,
              onFieldSubmitted: (_) {
                if (_dirty(tenant)) _save(tenant);
              },
              decoration: const InputDecoration(
                labelText: 'İşletme adı',
                helperText: 'Kenar çubuğunda, işletme seçicide ve davetlerde görünür.',
                helperMaxLines: 2,
                errorMaxLines: 2,
                counterText: '',
              ),
            ),
            const SizedBox(height: FlowSpace.xl),
            Text('İşletme rengi', style: theme.textTheme.titleSmall),
            const SizedBox(height: FlowSpace.xs),
            Text('İşletme simgenizde ve ekip davetlerinde görünür.', style: theme.textTheme.bodySmall),
            const SizedBox(height: FlowSpace.md),
            Wrap(spacing: 10, runSpacing: 10, children: [
              for (final (name, hex) in swatches)
                _Swatch(
                  name: name,
                  hex: hex,
                  selected: hex == _hex,
                  onTap: _saving ? null : () => setState(() => _hex = hex),
                ),
            ]),
            const SizedBox(height: FlowSpace.lg),
            Align(
              alignment: Alignment.centerLeft,
              child: Semantics(
                label: 'Önizleme: $previewName, $_hex',
                excludeSemantics: true,
                child: Container(
                  padding: const EdgeInsets.fromLTRB(6, 6, 12, 6),
                  decoration: BoxDecoration(
                    borderRadius: FlowRadius.controlAll,
                    border: Border.all(color: c.border),
                  ),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    InitialsAvatar(previewName, size: 30, color: brandColorFromHex(_hex)),
                    const SizedBox(width: 10),
                    Flexible(
                      child: Text(previewName,
                          style: theme.textTheme.titleSmall, maxLines: 1, overflow: TextOverflow.ellipsis),
                    ),
                    const SizedBox(width: 10),
                    Text(_hex, style: FlowText.mono(context, size: 11)),
                  ]),
                ),
              ),
            ),
            const SizedBox(height: FlowSpace.xl),
            Divider(height: 1, color: c.border),
            const SizedBox(height: FlowSpace.lg),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton(
                onPressed: _saving || !_dirty(tenant) ? null : () => _save(tenant),
                child: _saving
                    ? const SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Text('Kaydet'),
              ),
            ),
          ]),
        ),
      ),
    ]);
  }
}

/// One identity color choice: a 44 px square, ringed in ink when selected.
class _Swatch extends StatelessWidget {
  const _Swatch({required this.name, required this.hex, required this.selected, this.onTap});

  final String name;
  final String hex;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = FlowColors.of(context);
    final color = brandColorFromHex(hex) ?? c.raised;
    return Semantics(
      button: true,
      inMutuallyExclusiveGroup: true,
      selected: selected,
      label: '$name, $hex',
      excludeSemantics: true,
      child: Tooltip(
        message: name,
        child: InkWell(
          onTap: onTap,
          borderRadius: FlowRadius.controlAll,
          child: Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: color,
              borderRadius: FlowRadius.controlAll,
              border: Border.all(color: selected ? c.text : c.border, width: selected ? 3 : 1),
            ),
          ),
        ),
      ),
    );
  }
}
