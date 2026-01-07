import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../shell/app_shell.dart';
import '../providers/tenant_providers.dart';
import 'login_screen.dart';

class AppEntry extends ConsumerWidget {
  const AppEntry({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authControllerProvider);

    return auth.when(
      data: (value) {
        if (value == null) {
          return const LoginScreen();
        }
        final tenants = ref.watch(accessibleTenantsProvider);
        final selectedId = ref.watch(selectedTenantIdProvider);
        return tenants.when(
          data: (items) {
            if (items.isEmpty) {
              return const _NoTenantScreen();
            }
            final hasSelected = selectedId.maybeWhen(
              data: (id) => id != null,
              orElse: () => false,
            );
            if (!hasSelected) {
              Future.microtask(() {
                ref
                    .read(selectedTenantIdProvider.notifier)
                    .setSelectedTenantId(items.first.id);
              });
              return const Center(child: CircularProgressIndicator());
            }
            return const AppShell();
          },
          error: (_, __) => const _NoTenantScreen(),
          loading: () => const Center(child: CircularProgressIndicator()),
        );
      },
      error: (_, __) => const _NoTenantScreen(),
      loading: () => const Center(child: CircularProgressIndicator()),
    );
  }
}

class _NoTenantScreen extends StatelessWidget {
  const _NoTenantScreen();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.lock_outline,
              size: 48,
              color: Theme.of(context).colorScheme.primary,
            ),
            const SizedBox(height: 12),
            const Text('Bu kullanici icin tenant atamasi yok.'),
            const SizedBox(height: 8),
            Text(
              'Yoneticiye ulasarak tenant ve rol atamasi isteyin.',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ],
        ),
      ),
    );
  }
}