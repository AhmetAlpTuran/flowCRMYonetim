class TenantInvite {
  const TenantInvite({
    required this.id,
    required this.email,
    required this.role,
    required this.permissions,
    required this.status,
    required this.createdAt,
  });

  final String id;
  final String email;
  final String role;
  final Set<String> permissions;
  final String status;
  final DateTime createdAt;

  bool get isPending => status == 'pending';
}
