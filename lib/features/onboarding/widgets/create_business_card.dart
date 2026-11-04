import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/onboarding_errors.dart';
import '../providers/onboarding_providers.dart';

/// Lets a signed-in user create their own business and become its administrator.
class CreateBusinessCard extends ConsumerStatefulWidget {
  const CreateBusinessCard({super.key, this.onCreated});

  /// Called after the new business is selected, e.g. to close a dialog.
  final VoidCallback? onCreated;

  @override
  ConsumerState<CreateBusinessCard> createState() => _CreateBusinessCardState();
}

class _CreateBusinessCardState extends ConsumerState<CreateBusinessCard> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  bool _submitting = false;
  String? _error;

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('İşletmenizi oluşturun', style: theme.textTheme.titleMedium),
              const SizedBox(height: 4),
              Text(
                'İşletmenin yöneticisi siz olursunuz; ekibinizi daha sonra davet edebilirsiniz.',
                style: theme.textTheme.bodySmall,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _nameController,
                enabled: !_submitting,
                textInputAction: TextInputAction.done,
                maxLength: 80,
                decoration: const InputDecoration(
                  labelText: 'İşletme adı',
                  hintText: 'Örn. Yıldız Oto Galeri',
                ),
                validator: (value) {
                  final name = value?.trim() ?? '';
                  if (name.length < 2) return 'En az 2 karakter girin.';
                  return null;
                },
                onFieldSubmitted: (_) => _submit(),
              ),
              if (_error != null) ...[
                const SizedBox(height: 8),
                Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
              ],
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _submitting ? null : _submit,
                  icon: _submitting
                      ? const SizedBox(
                          height: 16,
                          width: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.add_business_outlined),
                  label: const Text('İşletmeyi oluştur'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _submit() async {
    if (_submitting || !(_formKey.currentState?.validate() ?? false)) return;
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      final tenantId = await ref
          .read(onboardingRepositoryProvider)
          .createBusiness(_nameController.text);
      if (!mounted) return;
      await enterTenant(ref, tenantId);
      widget.onCreated?.call();
    } catch (error) {
      if (mounted) setState(() => _error = onboardingErrorMessage(error));
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }
}
