import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart' hide AuthState;

import '../../tenancy/providers/tenant_providers.dart';
import '../data/account_repository.dart';

final accountRepositoryProvider = Provider<AccountRepository>(
  (ref) => AccountRepository(Supabase.instance.client),
);

final accountDeletionPlanProvider =
    FutureProvider.autoDispose<AccountDeletionPlan>(
  (ref) => ref.watch(accountRepositoryProvider).deletionPlan(),
);

/// Explains exactly what will be deleted, then requires the account email.
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
    final plan = ref.watch(accountDeletionPlanProvider);
    final tenants = ref.watch(accessibleTenantsProvider).valueOrNull ?? const [];
    final accountEmail = ref.watch(authControllerProvider).valueOrNull?.email ?? '';
    String names(List<String> ids) => [
          for (final id in ids)
            tenants.where((t) => t.id == id).map((t) => t.name).firstOrNull ?? 'İşletme',
        ].join(', ');

    return Scaffold(
      appBar: AppBar(title: const Text('Hesabı sil')),
      body: plan.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, __) => Center(
          child: TextButton(
            onPressed: () => ref.invalidate(accountDeletionPlanProvider),
            child: const Text('Bilgiler yüklenemedi. Tekrar dene'),
          ),
        ),
        data: (data) {
          final blocked = _blocked.isNotEmpty ? _blocked : data.blocked;
          return ListView(
            padding: const EdgeInsets.all(20),
            children: [
              Text(
                'Hesabınız ve giriş bilgileriniz kalıcı olarak silinir. Bu işlem geri alınamaz.',
                style: theme.textTheme.bodyLarge,
              ),
              const SizedBox(height: 16),
              if (data.deleteTenantIds.isNotEmpty)
                _Point(
                  icon: Icons.delete_forever_outlined,
                  color: theme.colorScheme.error,
                  text: 'Tek üyesi olduğunuz işletmeler tüm konuşmaları, kişileri, '
                      'kampanyaları ve dosyalarıyla birlikte silinir: '
                      '${names(data.deleteTenantIds)}.',
                ),
              if (data.leaveTenantIds.isNotEmpty)
                _Point(
                  icon: Icons.logout,
                  text: 'Diğer üyeleri olan işletmelerden ayrılırsınız; verileri korunur: '
                      '${names(data.leaveTenantIds)}.',
                ),
              if (blocked.isNotEmpty)
                _Point(
                  icon: Icons.block,
                  color: theme.colorScheme.error,
                  text: 'Şu işletmelerin tek yöneticisisiniz ve başka üyeleri var: '
                      '${blocked.join(', ')}. Hesabınızı silmeden önce Kullanıcılar '
                      'ekranından bir üyeyi yönetici yapın.',
                ),
              const SizedBox(height: 16),
              TextField(
                controller: _email,
                enabled: !_busy && blocked.isEmpty,
                keyboardType: TextInputType.emailAddress,
                autocorrect: false,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  labelText: 'Onaylamak için e-posta adresinizi yazın',
                  hintText: accountEmail,
                ),
              ),
              if (_error != null) ...[
                const SizedBox(height: 8),
                Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
              ],
              const SizedBox(height: 16),
              FilledButton(
                style: FilledButton.styleFrom(backgroundColor: theme.colorScheme.error),
                onPressed: _busy ||
                        blocked.isNotEmpty ||
                        _email.text.trim().toLowerCase() != accountEmail.toLowerCase() ||
                        accountEmail.isEmpty
                    ? null
                    : _delete,
                child: _busy
                    ? const SizedBox(
                        height: 16,
                        width: 16,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                    : const Text('Hesabımı kalıcı olarak sil'),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _delete() async {
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
  const _Point({required this.icon, required this.text, this.color});
  final IconData icon;
  final String text;
  final Color? color;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(icon, color: color),
          const SizedBox(width: 12),
          Expanded(child: Text(text)),
        ]),
      );
}
