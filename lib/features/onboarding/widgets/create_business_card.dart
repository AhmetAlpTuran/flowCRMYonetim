import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../ui/ui.dart';
import '../data/onboarding_errors.dart';
import '../providers/onboarding_providers.dart';
import 'onboarding_parts.dart';

/// Lets a signed-in user create their own business and become its administrator.
/// Drawn as a card on the no-business screen; inside a [Dialog] (the account menu)
/// it drops its own frame and uses the dialog's.
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
    final c = FlowColors.of(context);
    final inDialog = context.findAncestorWidgetOfExactType<Dialog>() != null;
    final form = Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: c.accentSoft,
                borderRadius: BorderRadius.circular(11),
              ),
              child: Icon(Icons.add_business_outlined, color: c.accentText, size: 20),
            ),
            const SizedBox(width: FlowSpace.md),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Semantics(
                  header: true,
                  child: Text('İşletmenizi oluşturun', style: theme.textTheme.titleLarge),
                ),
                const SizedBox(height: 6),
                const StatusBadge('14 gün ücretsiz', tone: FlowTone.accent),
              ]),
            ),
          ]),
          const SizedBox(height: FlowSpace.md),
          Text(
            'İşletmenin yöneticisi siz olursunuz; ekibinizi daha sonra davet edebilirsiniz.',
            style: theme.textTheme.bodyMedium?.copyWith(color: c.muted),
          ),
          const SizedBox(height: FlowSpace.lg),
          TextFormField(
            controller: _nameController,
            enabled: !_submitting,
            textInputAction: TextInputAction.done,
            textCapitalization: TextCapitalization.words,
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
            const SizedBox(height: FlowSpace.sm),
            InlineNotice(_error!),
          ],
          const SizedBox(height: FlowSpace.md),
          FilledButton(
            onPressed: _submitting ? null : _submit,
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
            child: _submitting
                ? const SizedBox(
                    height: 18,
                    width: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('İşletmeyi oluştur'),
          ),
        ],
      ),
    );
    if (inDialog) {
      return Padding(padding: const EdgeInsets.all(FlowSpace.xl), child: form);
    }
    return Container(
      padding: const EdgeInsets.all(FlowSpace.xl - 4),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: FlowRadius.cardAll,
        border: Border.all(color: c.border),
      ),
      child: form,
    );
  }

  Future<void> _submit() async {
    if (_submitting || !(_formKey.currentState?.validate() ?? false)) return;
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      final tenantId = await ref.read(onboardingRepositoryProvider).createBusiness(_nameController.text);
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
