class TenantMember {
  const TenantMember({
    required this.id,
    required this.userId,
    required this.role,
    required this.permissions,
    this.displayName,
    this.email,
  });

  final String id;
  final String userId;
  final String role;
  final Set<String> permissions;
  final String? displayName;
  final String? email;

  bool get isAdmin => role == 'admin';
}
