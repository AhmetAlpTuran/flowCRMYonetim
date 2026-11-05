import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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
      Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: TextFormField(
          controller: controller,
          keyboardType: keyboard,
          maxLength: maxLength,
          decoration: InputDecoration(labelText: label, helperText: helper, counterText: ''),
          validator: validator,
        ),
      );

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SafeArea(
        child: Form(
          key: _form,
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.all(16),
            children: [
              Row(children: [
                Expanded(child: Text('Fatura bilgileri', style: Theme.of(context).textTheme.titleMedium)),
                IconButton(
                  tooltip: 'Kapat',
                  onPressed: () => Navigator.of(context).pop(false),
                  icon: const Icon(Icons.close),
                ),
              ]),
              Text(
                'Ödeme sağlayıcısı iyzico abonelik için bu bilgileri ister; faturalarınızda da kullanılır.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 12),
              _field(_name, 'Ad', maxLength: 80, validator: (v) => _required(v, 'Ad zorunludur.')),
              _field(_surname, 'Soyad', maxLength: 80, validator: (v) => _required(v, 'Soyad zorunludur.')),
              _field(_email, 'E-posta', keyboard: TextInputType.emailAddress, maxLength: 254,
                  validator: (v) => RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(v?.trim() ?? '')
                      ? null
                      : 'Geçerli bir e-posta girin.'),
              _field(_phone, 'Cep telefonu', keyboard: TextInputType.phone, helper: 'Örn. 0555 111 22 33',
                  validator: (v) {
                final digits = (v ?? '').replaceAll(RegExp(r'[^0-9]'), '');
                return digits.length >= 10 && digits.length <= 15 ? null : 'Geçerli bir telefon numarası girin.';
              }),
              _field(_identity, 'T.C. kimlik veya vergi numarası', keyboard: TextInputType.number, maxLength: 11,
                  validator: (v) => RegExp(r'^[0-9]{10,11}$').hasMatch(v?.trim() ?? '')
                      ? null
                      : '10 haneli vergi veya 11 haneli T.C. kimlik numarası girin.'),
              _field(_company, 'Firma unvanı (isteğe bağlı)', maxLength: 200),
              _field(_taxOffice, 'Vergi dairesi (isteğe bağlı)', maxLength: 100),
              _field(_address, 'Fatura adresi', maxLength: 400,
                  validator: (v) => (v?.trim().length ?? 0) >= 5 ? null : 'Açık adres girin.'),
              _field(_city, 'Şehir', maxLength: 60,
                  validator: (v) => (v?.trim().length ?? 0) >= 2 ? null : 'Şehir zorunludur.'),
              _field(_zip, 'Posta kodu (isteğe bağlı)', keyboard: TextInputType.number, maxLength: 10),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
                ),
              FilledButton(
                onPressed: _saving ? null : _save,
                child: _saving
                    ? const SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Text('Kaydet'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
