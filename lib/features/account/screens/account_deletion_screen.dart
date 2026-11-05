import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart' hide AuthState;

import '../../../ui/ui.dart';
import '../../onboarding/widgets/onboarding_parts.dart';
import '../../tenancy/providers/tenant_providers.dart';
import '../data/account_repository.dart';

final accountRepositoryProvider = Provider<AccountRepository>(
  (ref) => AccountRepository(Supabase.instance.client),
);

final accountDeletionPlanProvider = FutureProvider.autoDispose<AccountDeletionPlan>(
  (ref) => ref.watch(accountRepositoryProvider).deletionPlan(),
);

/// Explains exactly what will be deleted, requires the account email, then asks once
/// more before the server deletes the account.
class AccountDeletionScreen extends ConsumerStatefulWidget {
  const AccountDeletionScreen({super.key});

  @override
  ConsumerState<AccountDeletionScreen> createState() => _AccountDeletionScreenState();
}

class _AccountDeletionScreenState extends ConsumerState<AccountDeletionScreen> {
  final _email = TextEditingController();
  bool _busy = false;
  String? _error;
  List<String> _blocked = const [];

  @override
  void dispose() {
    _email.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final c = FlowColors.of(context);
    final plan = ref.watch(accountDeletionPlanProvider);
    final tenants = ref.watch(accessibleTenantsProvider).valueOrNull ?? const [];
    final accountEmail = ref.watch(authControllerProvider).valueOrNull?.email ?? '';
    String names(List<String> ids) => [
          for (final id in ids) tenants.where((t) => t.id == id).map((t) => t.name).firstOrNull ?? 'İşletme',
        ].join(', ');

    return Scaffold(
      appBar: AppBar(title: const Text('Hesabı sil')),
      body: plan.when(
        loading: () => const AppPage(maxWidth: 640, children: [LoadingList(rows: 3)]),
        error: (_, __) => AppPage(maxWidth: 640, children: [
          ErrorState(
            title: 'Bilgiler yüklenemedi',
            message: 'Neyin silineceğini gösteremedik. Bağlantınızı kontrol edip tekrar deneyin.',
            onRetry: () => ref.invalidate(accountDeletionPlanProvider),
          ),
        ]),
        data: (data) {
          final blocked = _blocked.isNotEmpty ? _blocked : data.blocked;
          final canConfirm = !_busy &&
              blocked.isEmpty &&
              accountEmail.isNotEmpty &&
              _email.text.trim().toLowerCase() == accountEmail.toLowerCase();
          return AppPage(
            maxWidth: 640,
            children: [
              Container(
                padding: const EdgeInsets.all(FlowSpace.xl - 4),
                decoration: BoxDecoration(
                  color: c.dangerSoft,
                  borderRadius: FlowRadius.cardAll,
                  border: Border.all(color: c.danger.withValues(alpha: 0.55)),
                ),
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  Row(children: [
                    Icon(Icons.warning_amber_rounded, color: c.danger),
                    const SizedBox(width: 10),
                    Flexible(child: Eyebrow('Geri alınamaz', color: c.danger)),
                  ]),
                  const SizedBox(height: FlowSpace.md),
                  Text(
                    'Hesabınız ve giriş bilgileriniz kalıcı olarak silinir. Bu işlem geri alınamaz.',
                    style: theme.textTheme.titleMedium,
                  ),
                  if (data.deleteTenantIds.isNotEmpty || data.leaveTenantIds.isNotEmpty || blocked.isNotEmpty)
                    const SizedBox(height: FlowSpace.lg),
                  if (data.deleteTenantIds.isNotEmpty)
                    _Point(
                      icon: Icons.delete_forever_outlined,
                      color: c.danger,
                      text: 'Tek üyesi olduğunuz işletmeler tüm konuşmaları, kişileri, '
                          'kampanyaları ve dosyalarıyla birlikte silinir: '
                          '${names(data.deleteTenantIds)}.',
                    ),
                  if (data.leaveTenantIds.isNotEmpty)
                    _Point(
                      icon: Icons.logout,
                      color: c.muted,
                      text: 'Diğer üyeleri olan işletmelerden ayrılırsınız; verileri korunur: '
                          '${names(data.leaveTenantIds)}.',
                    ),
                  if (blocked.isNotEmpty)
                    _Point(
                      icon: Icons.block,
                      color: c.danger,
                      text: 'Şu işletmelerin tek yöneticisisiniz ve başka üyeleri var: '
                          '${blocked.join(', ')}. Hesabınızı silmeden önce Kullanıcılar '
                          'ekranından bir üyeyi yönetici yapın.',
                    ),
                ]),
              ),
              SectionCard(
                title: 'Silmeyi onaylayın',
                subtitle: 'Devam etmek için hesabınızın e-posta adresini yazın.',
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  if (accountEmail.isNotEmpty) ...[
                    Wrap(
                      spacing: 6,
                      runSpacing: FlowSpace.xs,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text('Hesap:', style: theme.textTheme.bodySmall?.copyWith(color: c.muted)),
                        Text(accountEmail, style: FlowText.mono(context, size: 13, color: c.text)),
                      ],
                    ),
                    const SizedBox(height: FlowSpace.md),
                  ],
                  TextField(
                    controller: _email,
                    enabled: !_busy && blocked.isEmpty,
                    keyboardType: TextInputType.emailAddress,
                    autocorrect: false,
                    onChanged: (_) => setState(() {}),
                    decoration: const InputDecoration(
                      labelText: 'E-posta adresiniz',
                      hintText: 'ornek@isletmeniz.com',
                    ),
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: FlowSpace.md),
                    InlineNotice(_error!),
                  ],
                  const SizedBox(height: FlowSpace.lg),
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: c.danger,
                      iconColor: c.danger,
                      side: BorderSide(color: canConfirm ? c.danger : c.border),
                      minimumSize: const Size.fromHeight(48),
                    ),
                    onPressed: canConfirm ? _confirmAndDelete : null,
                    icon: _busy
                        ? SizedBox(
                            height: 16,
                            width: 16,
                            child: CircularProgressIndicator(strokeWidth: 2, color: c.danger),
                          )
                        : const Icon(Icons.delete_forever_outlined, size: 18),
                    label: const Text('Hesabımı kalıcı olarak sil'),
                  ),
                ]),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _confirmAndDelete() async {
    final confirmed = await confirmAction(
      context,
      title: 'Hesabınız silinsin mi?',
      message: 'Hesabınız ve tek üyesi olduğunuz işletmelerin bütün verileri kalıcı olarak silinir. '
          'Bu işlem geri alınamaz.',
      confirmLabel: 'Evet, kalıcı olarak sil',
      destructive: true,
    );
    if (confirmed && mounted) await _delete();
  }

  Future<void> _delete() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(accountRepositoryProvider).deleteAccount(_email.text);
      // The server already revoked the account; clear the local session only.
      try {
        await ref.read(authClientProvider).signOut(scope: SignOutScope.local);
      } catch (_) {}
      if (mounted) Navigator.of(context).popUntil((route) => route.isFirst);
    } on AccountDeletionFailure catch (error) {
      if (mounted) {
        setState(() {
          _error = error.message;
          if (error.blocked.isNotEmpty) _blocked = error.blocked;
        });
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }
}

class _Point extends StatelessWidget {
  const _Point({required this.icon, required this.text, required this.color});

  final IconData icon;
  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: FlowSpace.md),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(width: FlowSpace.md),
          Expanded(child: Text(text, style: Theme.of(context).textTheme.bodyMedium)),
        ]),
      );
}
