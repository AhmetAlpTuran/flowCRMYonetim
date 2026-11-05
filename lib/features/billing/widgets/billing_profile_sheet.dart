import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../ui/ui.dart';
import '../../tenancy/providers/tenant_providers.dart';
import '../data/billing_repository.dart';
import '../models/billing_overview.dart';
import '../providers/billing_providers.dart';

/// "Fatura bilgileri": the details iyzico requires for a subscription (and invoices).
class BillingProfileSheet extends ConsumerStatefulWidget {
  const BillingProfileSheet({super.key, this.initial});

  final BillingProfile? initial;

  @override
  ConsumerState<BillingProfileSheet> createState() => _BillingProfileSheetState();
}

class _BillingProfileSheetState extends ConsumerState<BillingProfileSheet> {
  final _form = GlobalKey<FormState>();
  late final _name = TextEditingController(text: widget.initial?.contactName ?? '');
  late final _surname = TextEditingController(text: widget.initial?.contactSurname ?? '');
  late final _email = TextEditingController(text: widget.initial?.email ?? '');
  late final _phone = TextEditingController(text: widget.initial?.phone ?? '');
  late final _identity = TextEditingController(text: widget.initial?.identityNumber ?? '');
  late final _company = TextEditingController(text: widget.initial?.companyName ?? '');
  late final _taxOffice = TextEditingController(text: widget.initial?.taxOffice ?? '');
  late final _address = TextEditingController(text: widget.initial?.address ?? '');
  late final _city = TextEditingController(text: widget.initial?.city ?? '');
  late final _zip = TextEditingController(text: widget.initial?.zipCode ?? '');
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    for (final c in [_name, _surname, _email, _phone, _identity, _company, _taxOffice, _address, _city, _zip]) {
      c.dispose();
    }
    super.dispose();
  }

  String? _required(String? v, String message) => v == null || v.trim().isEmpty ? message : null;

  Future<void> _save() async {
    if (_saving || !(_form.currentState?.validate() ?? false)) return;
    final tenant = ref.read(selectedTenantProvider);
    if (tenant == null) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    String? optional(TextEditingController c) => c.text.trim().isEmpty ? null : c.text.trim();
    try {
      await ref.read(billingRepositoryProvider).saveProfile(
            tenant.id,
            BillingProfile(
              contactName: _name.text.trim(),
              contactSurname: _surname.text.trim(),
              email: _email.text.trim(),
              phone: _phone.text.trim(),
              identityNumber: _identity.text.trim(),
              address: _address.text.trim(),
              city: _city.text.trim(),
              companyName: optional(_company),
              taxOffice: optional(_taxOffice),
              zipCode: optional(_zip),
            ),
          );
      ref
        ..invalidate(billingProfileProvider)
        ..invalidate(billingOverviewProvider);
      if (mounted) Navigator.of(context).pop(true);
    } catch (error) {
      if (mounted) setState(() => _error = billingErrorMessage(error));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Widget _field(TextEditingController controller, String label,
          {String? Function(String?)? validator, TextInputType? keyboard, int? maxLength, String? helper}) =>
      TextFormField(
        controller: controller,
        keyboardType: keyboard,
        maxLength: maxLength,
        enabled: !_saving,
        decoration: InputDecoration(labelText: label, helperText: helper, helperMaxLines: 2, errorMaxLines: 3, counterText: ''),
        validator: validator,
      );

  /// Two fields side by side when there is room, stacked on phones.
  Widget _pair(bool wide, Widget first, Widget second) => wide
      ? Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(child: first),
          const SizedBox(width: FlowSpace.md),
          Expanded(child: second),
        ])
      : Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          first,
          const SizedBox(height: FlowSpace.md),
          second,
        ]);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final c = FlowColors.of(context);
    Widget group(String label) => Padding(
          padding: const EdgeInsets.only(top: FlowSpace.xl - 4, bottom: FlowSpace.md),
          child: Eyebrow(label, color: c.muted),
        );
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SafeArea(
        child: Form(
          key: _form,
          child: LayoutBuilder(builder: (context, constraints) {
            final wide = constraints.maxWidth >= 520;
            return ListView(
              shrinkWrap: true,
              padding: EdgeInsets.fromLTRB(
                FlowSpace.pageGutter(constraints.maxWidth),
                FlowSpace.xs,
                FlowSpace.pageGutter(constraints.maxWidth),
                FlowSpace.xl,
              ),
              children: [
                Row(children: [
                  Expanded(child: Text('Fatura bilgileri', style: theme.textTheme.headlineSmall)),
                  IconButton(
                    tooltip: 'Kapat',
                    onPressed: () => Navigator.of(context).pop(false),
                    icon: const Icon(Icons.close),
                  ),
                ]),
                const SizedBox(height: FlowSpace.xs),
                Text(
                  'Ödeme sağlayıcısı iyzico abonelik için bu bilgileri ister; faturalarınızda da kullanılır.',
                  style: theme.textTheme.bodySmall,
                ),
                group('Yetkili kişi'),
                _pair(
                  wide,
                  _field(_name, 'Ad', maxLength: 80, validator: (v) => _required(v, 'Ad zorunludur.')),
                  _field(_surname, 'Soyad', maxLength: 80, validator: (v) => _required(v, 'Soyad zorunludur.')),
                ),
                const SizedBox(height: FlowSpace.md),
                _pair(
                  wide,
                  _field(_email, 'E-posta', keyboard: TextInputType.emailAddress, maxLength: 254,
                      validator: (v) => RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(v?.trim() ?? '')
                          ? null
                          : 'Geçerli bir e-posta girin.'),
                  _field(_phone, 'Cep telefonu', keyboard: TextInputType.phone, helper: 'Örn. 0555 111 22 33',
                      validator: (v) {
                    final digits = (v ?? '').replaceAll(RegExp(r'[^0-9]'), '');
                    return digits.length >= 10 && digits.length <= 15 ? null : 'Geçerli bir telefon numarası girin.';
                  }),
                ),
                group('Vergi'),
                _field(_identity, 'T.C. kimlik veya vergi numarası', keyboard: TextInputType.number, maxLength: 11,
                    helper: 'Şahıs için 11 haneli T.C. kimlik, şirket için 10 haneli vergi numarası.',
                    validator: (v) => RegExp(r'^[0-9]{10,11}$').hasMatch(v?.trim() ?? '')
                        ? null
                        : '10 haneli vergi veya 11 haneli T.C. kimlik numarası girin.'),
                const SizedBox(height: FlowSpace.md),
                _pair(
                  wide,
                  _field(_company, 'Firma unvanı (isteğe bağlı)', maxLength: 200),
                  _field(_taxOffice, 'Vergi dairesi (isteğe bağlı)', maxLength: 100),
                ),
                group('Fatura adresi'),
                _field(_address, 'Fatura adresi', maxLength: 400,
                    validator: (v) => (v?.trim().length ?? 0) >= 5 ? null : 'Açık adres girin.'),
                const SizedBox(height: FlowSpace.md),
                _pair(
                  wide,
                  _field(_city, 'Şehir', maxLength: 60,
                      validator: (v) => (v?.trim().length ?? 0) >= 2 ? null : 'Şehir zorunludur.'),
                  _field(_zip, 'Posta kodu (isteğe bağlı)', keyboard: TextInputType.number, maxLength: 10),
                ),
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
                const SizedBox(height: FlowSpace.xl),
                Text(
                  'Kart bilgileriniz burada istenmez; ödemeyi iyzico güvenli ödeme sayfasında yaparsınız.',
                  style: theme.textTheme.bodySmall?.copyWith(color: c.faint),
                ),
                const SizedBox(height: FlowSpace.md),
                FilledButton(
                  onPressed: _saving ? null : _save,
                  child: _saving
                      ? const SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Text('Kaydet'),
                ),
              ],
            );
          }),
        ),
      ),
    );
  }
}
