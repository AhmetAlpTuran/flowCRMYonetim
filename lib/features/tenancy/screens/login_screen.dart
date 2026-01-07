import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../app/user_role.dart';
import '../providers/tenant_providers.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  UserRole _role = UserRole.admin;
  String? _error;
  String? _selectedTenantId;
  bool _loading = false;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tenantsAsync = ref.watch(accessibleTenantsProvider);

    return Scaffold(
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 460),
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.lock_open_outlined,
                    size: 48,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Tenant Girisi',
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'E-posta ve sifre ile giris yapin, tenant secin.',
                    style: Theme.of(context).textTheme.bodyMedium,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 20),
                  TextField(
                    controller: _emailController,
                    keyboardType: TextInputType.emailAddress,
                    decoration: const InputDecoration(
                      labelText: 'E-posta',
                      prefixIcon: Icon(Icons.alternate_email),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _passwordController,
                    obscureText: true,
                    decoration: const InputDecoration(
                      labelText: 'Sifre',
                      prefixIcon: Icon(Icons.lock_outline),
                    ),
                  ),
                  const SizedBox(height: 12),
                  tenantsAsync.when(
                    data: (items) {
                      _selectedTenantId ??= items.isNotEmpty ? items.first.id : null;
                      return DropdownButtonFormField<String>(
                        value: _selectedTenantId,
                        decoration: const InputDecoration(
                          labelText: 'Tenant',
                        ),
                        items: [
                          for (final tenant in items)
                            DropdownMenuItem(
                              value: tenant.id,
                              child: Text(tenant.name),
                            ),
                        ],
                        onChanged: (value) {
                          setState(() {
                            _selectedTenantId = value;
                          });
                        },
                      );
                    },
                    error: (_, __) => const SizedBox.shrink(),
                    loading: () => const CircularProgressIndicator(),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<UserRole>(
                    value: _role,
                    decoration: const InputDecoration(
                      labelText: 'Rol',
                    ),
                    items: const [
                      DropdownMenuItem(
                        value: UserRole.admin,
                        child: Text('Yonetici'),
                      ),
                      DropdownMenuItem(
                        value: UserRole.user,
                        child: Text('Kullanici'),
                      ),
                    ],
                    onChanged: (value) {
                      if (value != null) {
                        setState(() {
                          _role = value;
                        });
                      }
                    },
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 12),
                    Text(
                      _error!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ],
                  const SizedBox(height: 20),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: _loading ? null : _handleSignUp,
                          child: const Text('Kayit ol'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: FilledButton(
                          onPressed: _loading ? null : _handleLogin,
                          child: _loading
                              ? const SizedBox(
                                  height: 18,
                                  width: 18,
                                  child: CircularProgressIndicator(strokeWidth: 2),
                                )
                              : const Text('Giris yap'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _handleLogin() async {
    await _runAuthAction(() async {
      await ref.read(authControllerProvider.notifier).login(
            _emailController.text.trim(),
            _passwordController.text.trim(),
          );
      await _ensureMembership();
    });
  }

  Future<void> _handleSignUp() async {
    await _runAuthAction(() async {
      await ref.read(authControllerProvider.notifier).signUp(
            _emailController.text.trim(),
            _passwordController.text.trim(),
          );
      await _ensureMembership();
    });
  }

  Future<void> _ensureMembership() async {
    final tenantId = _selectedTenantId;
    if (tenantId == null) {
      throw AuthException('Tenant secin.');
    }
    await ensureMembership(tenantId: tenantId, role: _role);
    await ref
        .read(selectedTenantIdProvider.notifier)
        .setSelectedTenantId(tenantId);
  }

  Future<void> _runAuthAction(Future<void> Function() action) async {
    setState(() {
      _error = null;
      _loading = true;
    });
    try {
      await action();
    } catch (error) {
      setState(() {
        _error = error.toString();
      });
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
    }
  }
}