import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/user_role.dart';
import '../providers/tenant_providers.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _emailController = TextEditingController();
  UserRole _role = UserRole.admin;
  String? _error;

  @override
  void dispose() {
    _emailController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
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
                    'E-posta ile giris yapin ve tenant secin.',
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
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: _handleLogin,
                      child: const Text('Giris yap'),
                    ),
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
    final email = _emailController.text.trim();
    if (!email.contains('@')) {
      setState(() {
        _error = 'Lutfen gecerli bir e-posta girin.';
      });
      return;
    }

    final repository = ref.read(tenantRepositoryProvider);
    final tenants = await repository.fetchTenantsForEmail(email);
    if (tenants.isEmpty) {
      setState(() {
        _error = 'Bu e-posta icin tenant bulunamadi.';
      });
      return;
    }

    setState(() {
      _error = null;
    });

    await ref.read(authControllerProvider.notifier).login(email, _role);
    await ref
        .read(selectedTenantIdProvider.notifier)
        .setSelectedTenantId(tenants.first.id);
  }
}
