import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';

class AccountDeletionPlan {
  const AccountDeletionPlan({
    required this.blocked,
    required this.deleteTenantIds,
    required this.leaveTenantIds,
  });

  factory AccountDeletionPlan.fromJson(Map<String, dynamic> json) =>
      AccountDeletionPlan(
        blocked: [
          for (final item in (json['blocked'] as List? ?? const []))
            if (item is Map) item['name']?.toString() ?? '',
        ],
        deleteTenantIds: [
          for (final id in (json['delete_tenants'] as List? ?? const [])) id.toString(),
        ],
        leaveTenantIds: [
          for (final id in (json['leave_tenants'] as List? ?? const [])) id.toString(),
        ],
      );

  /// Businesses where the user is the only admin but others are members.
  final List<String> blocked;

  /// Businesses where the user is the only member: deleted with all their data.
  final List<String> deleteTenantIds;

  /// Businesses that keep their data; only the membership is removed.
  final List<String> leaveTenantIds;

  bool get canDelete => blocked.isEmpty;
}

class AccountDeletionFailure implements Exception {
  const AccountDeletionFailure(this.message, {this.blocked = const []});
  final String message;
  final List<String> blocked;
  @override
  String toString() => message;
}

class AccountRepository {
  AccountRepository(this._client);

  final SupabaseClient _client;

  Future<AccountDeletionPlan> deletionPlan() async {
    final data = await _client
        .rpc('my_account_deletion_plan')
        .timeout(const Duration(seconds: 20));
    if (data is! Map) throw const FormatException('Hesap bilgisi alınamadı.');
    return AccountDeletionPlan.fromJson(Map<String, dynamic>.from(data));
  }

  /// Permanently deletes the account; safe to call again after a failure.
  Future<void> deleteAccount(String confirmEmail) async {
    try {
      final response = await _client.functions
          .invoke('delete-account', body: {'confirm_email': confirmEmail.trim()})
          .timeout(const Duration(seconds: 60));
      final data = response.data;
      if (data is! Map || data['status'] != 'deleted') {
        throw const AccountDeletionFailure(
            'Silme işleminin sonucu doğrulanamadı. Tekrar denemek güvenlidir.');
      }
    } on FunctionException catch (error) {
      final details = error.details;
      final code = details is Map ? details['code'] : null;
      throw switch (code) {
        'confirmation_mismatch' =>
          const AccountDeletionFailure('E-posta adresi hesabınızla eşleşmiyor.'),
        'admin_transfer_required' => AccountDeletionFailure(
            'Önce yönetici rolünü başka bir üyeye devredin.',
            blocked: [
              for (final name in (details is Map ? details['blocked'] as List? ?? const [] : const []))
                name.toString(),
            ],
          ),
        _ => const AccountDeletionFailure(
            'Hesap şu anda silinemedi. Bir süre sonra tekrar deneyin; tekrar denemek güvenlidir.'),
      };
    } on TimeoutException {
      throw const AccountDeletionFailure(
          'Sunucu yanıt vermedi. Tekrar denemek güvenlidir.');
    }
  }
}
