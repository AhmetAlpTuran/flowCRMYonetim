import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../shell/app_shell.dart';
import '../../users/providers/tenant_admin_providers.dart';
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

class _NoTenantScreen extends ConsumerStatefulWidget {
  const _NoTenantScreen();

  @override
  ConsumerState<_NoTenantScreen> createState() => _NoTenantScreenState();
}

class _NoTenantScreenState extends ConsumerState<_NoTenantScreen> {
  final TextEditingController _messageController = TextEditingController();
  String? _selectedTenantId;
  bool _submitting = false;

  @override
  void dispose() {
    _messageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tenants = ref.watch(publicTenantsProvider);
    final requests = ref.watch(myJoinRequestsProvider);

    return Scaffold(
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: ListView(
            padding: const EdgeInsets.all(24),
            shrinkWrap: true,
            children: [
              Icon(
                Icons.lock_outline,
                size: 48,
                color: Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(height: 12),
              Text(
                'Bu kullanici icin tenant atamasi yok.',
                style: Theme.of(context).textTheme.titleMedium,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                'Yoneticiye ulasabilir veya asagidan tenant basvurusu yapabilirsiniz.',
                style: Theme.of(context).textTheme.bodyMedium,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 20),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Tenant basvurusu',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 12),
                      tenants.when(
                        data: (items) {
                          if (items.isEmpty) {
                            return const Text(
                              'Su anda acik tenant bulunamadi.',
                            );
                          }
                          _selectedTenantId ??= items.first.id;
                          return DropdownButtonFormField<String>(
                            value: _selectedTenantId,
                            decoration:
                                const InputDecoration(labelText: 'Tenant'),
                            items: [
                              for (final tenant in items)
                                DropdownMenuItem(
                                  value: tenant.id,
                                  child: Row(
                                    children: [
                                      CircleAvatar(
                                        radius: 8,
                                        backgroundColor: tenant.brandColor,
                                      ),
                                      const SizedBox(width: 8),
                                      Text(tenant.name),
                                    ],
                                  ),
                                ),
                            ],
                            onChanged: (value) {
                              setState(() {
                                _selectedTenantId = value;
                              });
                            },
                          );
                        },
                        error: (error, _) => Text(
                          'Tenant listesi yuklenemedi: $error',
                        ),
                        loading: () =>
                            const LinearProgressIndicator(minHeight: 2),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _messageController,
                        maxLines: 3,
                        decoration: const InputDecoration(
                          labelText: 'Not (opsiyonel)',
                          hintText: 'Kisa bir aciklama yazin',
                          alignLabelWithHint: true,
                        ),
                      ),
                      const SizedBox(height: 16),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton(
                          onPressed: _submitting ? null : _submitRequest,
                          child: _submitting
                              ? const SizedBox(
                                  height: 16,
                                  width: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Text('Basvuru gonder'),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'Basvurularim',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              requests.when(
                data: (items) {
                  if (items.isEmpty) {
                    return const Text('Henuz basvurunuz yok.');
                  }
                  return Column(
                    children: [
                      for (final request in items) ...[
                        Card(
                          child: ListTile(
                            leading: CircleAvatar(
                              backgroundColor: request.tenantColor ??
                                  Theme.of(context).colorScheme.primary,
                              child: const Icon(Icons.apartment),
                            ),
                            title: Text(request.tenantName ?? request.tenantId),
                            subtitle: Text(
                              'Durum: ${_statusLabel(request.status)}',
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                      ],
                    ],
                  );
                },
                error: (error, _) =>
                    Text('Basvurular yuklenemedi: $error'),
                loading: () => const LinearProgressIndicator(minHeight: 2),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _submitRequest() async {
    final auth = await ref.read(authControllerProvider.future);
    final tenantId = _selectedTenantId;
    if (auth == null || tenantId == null) {
      return;
    }
    setState(() {
      _submitting = true;
    });
    try {
      final repository = ref.read(tenantAdminRepositoryProvider);
      await repository.createJoinRequest(
        tenantId: tenantId,
        userId: auth.userId,
        email: auth.email,
        message: _messageController.text.trim().isEmpty
            ? null
            : _messageController.text.trim(),
      );
      _messageController.clear();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Basvuru gonderildi.')),
        );
      }
      ref.invalidate(myJoinRequestsProvider);
    } finally {
      if (mounted) {
        setState(() {
          _submitting = false;
        });
      }
    }
  }

  String _statusLabel(String value) {
    switch (value) {
      case 'pending':
        return 'Bekliyor';
      case 'approved':
        return 'Onaylandi';
      case 'rejected':
        return 'Reddedildi';
      default:
        return value;
    }
  }
}
