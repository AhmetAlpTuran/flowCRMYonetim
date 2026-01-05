import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../app/user_role.dart';
import '../data/mock_tenant_repository.dart';
import '../models/tenant.dart';

class AuthState {
  const AuthState({
    required this.email,
    required this.role,
  });

  final String email;
  final UserRole role;
}

class AuthController extends AsyncNotifier<AuthState?> {
  static const _emailKey = 'auth_email';
  static const _roleKey = 'auth_role';

  @override
  Future<AuthState?> build() async {
    final prefs = await SharedPreferences.getInstance();
    final email = prefs.getString(_emailKey);
    final roleName = prefs.getString(_roleKey);
    if (email == null || roleName == null) {
      return null;
    }
    final role = UserRole.values.firstWhere(
      (value) => value.name == roleName,
      orElse: () => UserRole.user,
    );
    return AuthState(email: email, role: role);
  }

  Future<void> login(String email, UserRole role) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_emailKey, email);
    await prefs.setString(_roleKey, role.name);
    state = AsyncValue.data(AuthState(email: email, role: role));
  }

  Future<void> logout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_emailKey);
    await prefs.remove(_roleKey);
    state = const AsyncValue.data(null);
  }
}

final authControllerProvider =
    AsyncNotifierProvider<AuthController, AuthState?>(AuthController.new);

final tenantRepositoryProvider = Provider<MockTenantRepository>((ref) {
  return MockTenantRepository();
});

final accessibleTenantsProvider = FutureProvider<List<Tenant>>((ref) async {
  final auth = await ref.watch(authControllerProvider.future);
  if (auth == null) {
    return [];
  }
  final repository = ref.watch(tenantRepositoryProvider);
  return repository.fetchTenantsForEmail(auth.email);
});

class SelectedTenantIdController extends AsyncNotifier<String?> {
  static const _tenantIdKey = 'selected_tenant_id';

  @override
  Future<String?> build() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_tenantIdKey);
  }

  Future<void> setSelectedTenantId(String id) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_tenantIdKey, id);
    state = AsyncValue.data(id);
  }
}

final selectedTenantIdProvider =
    AsyncNotifierProvider<SelectedTenantIdController, String?>(
  SelectedTenantIdController.new,
);

final selectedTenantProvider = Provider<Tenant?>((ref) {
  final tenants = ref.watch(accessibleTenantsProvider);
  final selectedId = ref
      .watch(selectedTenantIdProvider)
      .maybeWhen(data: (value) => value, orElse: () => null);

  return tenants.maybeWhen(
    data: (items) {
      if (items.isEmpty) {
        return null;
      }
      if (selectedId == null) {
        return items.first;
      }
      return items.firstWhere(
        (item) => item.id == selectedId,
        orElse: () => items.first,
      );
    },
    orElse: () => null,
  );
});
