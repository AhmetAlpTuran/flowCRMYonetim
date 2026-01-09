class TenantMembership {
  const TenantMembership({
    required this.role,
    required this.permissions,
  });

  final String role;
  final Set<String> permissions;

  bool get isAdmin => role == 'admin';

  bool hasPermission(String key) {
    return isAdmin || permissions.contains(key);
  }
}
