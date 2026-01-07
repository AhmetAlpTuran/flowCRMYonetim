import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../app/user_role.dart';
import '../models/tenant.dart';

class AuthState {
  const AuthState({
    required this.userId,
    required this.email,
  });

  final String userId;
  final String email;
}

class AuthController extends AsyncNotifier<AuthState?> {
  @override
  Future<AuthState?> build() async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) {
      return null;
    }
    return AuthState(userId: user.id, email: user.email ?? '');
  }

  Future<void> login(String email, String password) async {
    final response = await Supabase.instance.client.auth.signInWithPassword(
      email: email,
      password: password,
    );
    final user = response.user;
    if (user == null) {
      throw const AuthException('Giris basarisiz.');
    }
    state = AsyncValue.data(AuthState(userId: user.id, email: email));
  }

  Future<void> signUp(String email, String password) async {
    final response = await Supabase.instance.client.auth.signUp(
      email: email,
      password: password,
    );
    final user = response.user;
    if (user == null) {
      throw const AuthException('Kayit basarisiz.');
    }
    state = AsyncValue.data(AuthState(userId: user.id, email: email));
  }

  Future<void> logout() async {
    await Supabase.instance.client.auth.signOut();
    state = const AsyncValue.data(null);
  }
}

final authControllerProvider =
    AsyncNotifierProvider<AuthController, AuthState?>(AuthController.new);

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

final accessibleTenantsProvider = FutureProvider<List<Tenant>>((ref) async {
  final auth = await ref.watch(authControllerProvider.future);
  if (auth == null) {
    return [];
  }
  final client = Supabase.instance.client;
  final response = await client
      .from('tenant_memberships')
      .select('tenant:tenants(id, name, brand_color, features)')
      .eq('user_id', auth.userId);

  return response.map<Tenant>((row) {
    final tenant = row['tenant'] as Map<String, dynamic>;
    return Tenant(
      id: tenant['id'] as String,
      name: tenant['name'] as String,
      brandColor: _parseColor(tenant['brand_color'] as String),
      features: _parseFeatures(tenant['features'] as List<dynamic>),
      allowedDomains: const [],
    );
  }).toList();
});

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

final currentRoleProvider = FutureProvider<UserRole>((ref) async {
  final auth = await ref.watch(authControllerProvider.future);
  final tenant = ref.watch(selectedTenantProvider);
  if (auth == null || tenant == null) {
    return UserRole.user;
  }
  final client = Supabase.instance.client;
  final response = await client
      .from('tenant_memberships')
      .select('role')
      .eq('tenant_id', tenant.id)
      .eq('user_id', auth.userId)
      .maybeSingle();
  final role = response?['role'] as String?;
  if (role == 'admin') {
    return UserRole.admin;
  }
  return UserRole.user;
});

Color _parseColor(String value) {
  final normalized = value.replaceAll('#', '');
  final hex = normalized.length == 6 ? 'FF$normalized' : normalized;
  return Color(int.parse(hex, radix: 16));
}

Set<TenantFeature> _parseFeatures(List<dynamic> raw) {
  return raw.map((item) => _featureFromString(item as String)).toSet();
}

TenantFeature _featureFromString(String value) {
  switch (value) {
    case 'dashboard':
      return TenantFeature.dashboard;
    case 'bot':
      return TenantFeature.bot;
    case 'knowledge':
      return TenantFeature.knowledge;
    case 'inbox':
      return TenantFeature.inbox;
    case 'handoff':
      return TenantFeature.handoff;
    case 'custom':
      return TenantFeature.custom;
    case 'campaigns':
      return TenantFeature.campaigns;
    case 'templates':
      return TenantFeature.templates;
    default:
      return TenantFeature.inbox;
  }
}