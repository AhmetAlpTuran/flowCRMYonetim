import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/tenant_invite.dart';
import '../models/tenant_join_request.dart';
import '../models/tenant_member.dart';

class SupabaseTenantAdminRepository {
  SupabaseTenantAdminRepository(this._client);

  final SupabaseClient _client;

  Future<List<TenantMember>> fetchMembers(String tenantId) async {
    final response = await _client
        .from('tenant_memberships')
        .select('id, user_id, role, permissions, user:user_profiles(email, display_name)')
        .eq('tenant_id', tenantId)
        .order('created_at');

    return response.map<TenantMember>((row) {
      final profile = row['user'] as Map<String, dynamic>?;
      return TenantMember(
        id: row['id'] as String,
        userId: row['user_id'] as String,
        role: row['role'] as String? ?? 'user',
        permissions: _permissionsFrom(row['permissions']),
        email: profile?['email'] as String?,
        displayName: profile?['display_name'] as String?,
      );
    }).toList();
  }

  Future<void> updateMember({
    required String membershipId,
    required String role,
    required Set<String> permissions,
  }) async {
    await _client.from('tenant_memberships').update({
      'role': role,
      'permissions': permissions.toList(),
    }).eq('id', membershipId);
  }

  Future<void> removeMember(String membershipId) async {
    await _client.from('tenant_memberships').delete().eq('id', membershipId);
  }

  Future<List<TenantInvite>> fetchInvites(String tenantId) async {
    final response = await _client
        .from('tenant_invites')
        .select('id, email, role, permissions, status, created_at')
        .eq('tenant_id', tenantId)
        .order('created_at', ascending: false);

    return response.map<TenantInvite>((row) {
      return TenantInvite(
        id: row['id'] as String,
        email: row['email'] as String,
        role: row['role'] as String? ?? 'user',
        permissions: _permissionsFrom(row['permissions']),
        status: row['status'] as String? ?? 'pending',
        createdAt: DateTime.parse(row['created_at'] as String),
      );
    }).toList();
  }

  Future<void> createInvite({
    required String tenantId,
    required String email,
    required String role,
    required Set<String> permissions,
    required String invitedBy,
  }) async {
    await _client.from('tenant_invites').insert({
      'tenant_id': tenantId,
      'email': email,
      'role': role,
      'permissions': permissions.toList(),
      'invited_by': invitedBy,
    });
  }

  Future<void> updateInviteStatus({
    required String inviteId,
    required String status,
  }) async {
    await _client.from('tenant_invites').update({
      'status': status,
      'responded_at': DateTime.now().toIso8601String(),
    }).eq('id', inviteId);
  }

  Future<List<TenantJoinRequest>> fetchJoinRequests(String tenantId) async {
    final response = await _client
        .from('tenant_join_requests')
        .select('id, tenant_id, user_id, email, message, status, created_at')
        .eq('tenant_id', tenantId)
        .order('created_at', ascending: false);

    return response.map<TenantJoinRequest>((row) {
      return TenantJoinRequest(
        id: row['id'] as String,
        tenantId: row['tenant_id'] as String,
        userId: row['user_id'] as String?,
        email: row['email'] as String,
        message: row['message'] as String?,
        status: row['status'] as String? ?? 'pending',
        createdAt: DateTime.parse(row['created_at'] as String),
      );
    }).toList();
  }

  Future<List<TenantJoinRequest>> fetchMyRequests(String userId) async {
    final response = await _client
        .from('tenant_join_requests')
        .select(
          'id, tenant_id, email, message, status, created_at, tenant:tenants(name, brand_color)',
        )
        .eq('user_id', userId)
        .order('created_at', ascending: false);

    return response.map<TenantJoinRequest>((row) {
      final tenant = row['tenant'] as Map<String, dynamic>?;
      return TenantJoinRequest(
        id: row['id'] as String,
        tenantId: row['tenant_id'] as String,
        email: row['email'] as String,
        message: row['message'] as String?,
        status: row['status'] as String? ?? 'pending',
        createdAt: DateTime.parse(row['created_at'] as String),
        tenantName: tenant?['name'] as String?,
        tenantColor: _parseColor(tenant?['brand_color'] as String?),
      );
    }).toList();
  }

  Future<void> createJoinRequest({
    required String tenantId,
    required String userId,
    required String email,
    String? message,
  }) async {
    await _client.from('tenant_join_requests').insert({
      'tenant_id': tenantId,
      'user_id': userId,
      'email': email,
      'message': message,
    });
  }

  Future<void> approveJoinRequest({
    required String requestId,
    required String tenantId,
    required String userId,
    required String reviewerId,
    required String role,
    required Set<String> permissions,
  }) async {
    await _client.from('tenant_memberships').upsert({
      'tenant_id': tenantId,
      'user_id': userId,
      'role': role,
      'permissions': permissions.toList(),
    }, onConflict: 'tenant_id,user_id');

    await _client.from('tenant_join_requests').update({
      'status': 'approved',
      'reviewed_at': DateTime.now().toIso8601String(),
      'reviewed_by': reviewerId,
    }).eq('id', requestId);
  }

  Future<void> rejectJoinRequest({
    required String requestId,
    required String reviewerId,
  }) async {
    await _client.from('tenant_join_requests').update({
      'status': 'rejected',
      'reviewed_at': DateTime.now().toIso8601String(),
      'reviewed_by': reviewerId,
    }).eq('id', requestId);
  }

  Set<String> _permissionsFrom(dynamic raw) {
    if (raw is List) {
      return raw.map((item) => item.toString()).toSet();
    }
    return {};
  }

  Color? _parseColor(String? value) {
    if (value == null || value.isEmpty) {
      return null;
    }
    final normalized = value.replaceAll('#', '');
    final hex = normalized.length == 6 ? 'FF$normalized' : normalized;
    return Color(int.parse(hex, radix: 16));
  }
}
