import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../tenancy/providers/tenant_providers.dart';
import '../providers/tenant_admin_providers.dart';
import '../models/tenant_invite.dart';
import '../models/tenant_join_request.dart';
import '../models/tenant_member.dart';

class TenantUsersScreen extends ConsumerWidget {
  const TenantUsersScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final membership = ref.watch(currentMembershipProvider).maybeWhen(
          data: (value) => value,
          orElse: () => null,
        );
    final canManage = membership?.hasPermission('users') ?? false;

    if (!canManage) {
      return Center(
        child: Text(
          'Bu ekran icin yetkiniz yok.',
          style: Theme.of(context).textTheme.bodyLarge,
        ),
      );
    }

    return DefaultTabController(
      length: 2,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
            child: Row(
              children: [
                Icon(
                  Icons.manage_accounts_outlined,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(width: 8),
                Text(
                  'Kullanicilar ve Yetkiler',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ],
            ),
          ),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 20),
            child: TabBar(
              tabs: [
                Tab(text: 'Kullanicilar'),
                Tab(text: 'Basvurular & Davetler'),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: TabBarView(
              children: [
                _MembersTab(),
                _RequestsTab(),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _MembersTab extends ConsumerWidget {
  const _MembersTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final members = ref.watch(tenantMembersProvider);

    return members.when(
      data: (items) {
        if (items.isEmpty) {
          return const Center(child: Text('Henuz uye yok.'));
        }
        return ListView.separated(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
          itemBuilder: (context, index) {
            final member = items[index];
            return _MemberCard(member: member);
          },
          separatorBuilder: (_, __) => const SizedBox(height: 12),
          itemCount: items.length,
        );
      },
      error: (error, _) => Center(
        child: Text('Kullanicilar yuklenemedi: $error'),
      ),
      loading: () => const Center(child: CircularProgressIndicator()),
    );
  }
}

class _MemberCard extends ConsumerWidget {
  const _MemberCard({required this.member});

  final TenantMember member;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final subtitle = member.email ?? member.displayName ?? member.userId;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  backgroundColor: Theme.of(context).colorScheme.primaryContainer,
                  child: Text(
                    _initials(subtitle),
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onPrimaryContainer,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        member.displayName ?? subtitle,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        subtitle,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: 'Duzenle',
                  icon: const Icon(Icons.edit_outlined),
                  onPressed: () => _openMemberEditor(context, ref),
                ),
                IconButton(
                  tooltip: 'Kaldir',
                  icon: const Icon(Icons.delete_outline),
                  onPressed: () => _confirmRemove(context, ref),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _RoleChip(role: member.role),
                for (final permission in _PermissionOption.labelsFor(member.permissions))
                  Chip(label: Text(permission)),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _openMemberEditor(BuildContext context, WidgetRef ref) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) => _MemberEditorSheet(member: member),
    ).then((updated) {
      if (updated == true) {
        ref.invalidate(tenantMembersProvider);
      }
    });
  }

  void _confirmRemove(BuildContext context, WidgetRef ref) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Kullaniciyi kaldir'),
        content: const Text('Bu kullanici tenant erisimini kaybedecek.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Vazgec'),
          ),
          FilledButton(
            onPressed: () async {
              Navigator.of(context).pop();
              final repository = ref.read(tenantAdminRepositoryProvider);
              await repository.removeMember(member.id);
              ref.invalidate(tenantMembersProvider);
            },
            child: const Text('Kaldir'),
          ),
        ],
      ),
    );
  }

  String _initials(String value) {
    final parts = value.trim().split(' ');
    if (parts.isEmpty) {
      return '';
    }
    final first = parts.first.isNotEmpty ? parts.first[0] : '';
    final last = parts.length > 1 && parts.last.isNotEmpty ? parts.last[0] : '';
    return (first + last).toUpperCase();
  }
}

class _RequestsTab extends ConsumerWidget {
  const _RequestsTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final requests = ref.watch(tenantJoinRequestsProvider);
    final invites = ref.watch(tenantInvitesProvider);

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
      children: [
        Text(
          'Basvurular',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 12),
        requests.when(
          data: (items) {
            if (items.isEmpty) {
              return const Text('Bekleyen basvuru yok.');
            }
            return Column(
              children: [
                for (final request in items) ...[
                  _RequestCard(request: request),
                  const SizedBox(height: 12),
                ],
              ],
            );
          },
          error: (error, _) => Text('Basvurular yuklenemedi: $error'),
          loading: () => const Center(child: CircularProgressIndicator()),
        ),
        const SizedBox(height: 16),
        Text(
          'Davet gonder',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 12),
        const _InviteFormCard(),
        const SizedBox(height: 16),
        invites.when(
          data: (items) {
            if (items.isEmpty) {
              return const Text('Henuz davet yok.');
            }
            return Column(
              children: [
                for (final invite in items) ...[
                  _InviteCard(invite: invite),
                  const SizedBox(height: 12),
                ],
              ],
            );
          },
          error: (error, _) => Text('Davetler yuklenemedi: $error'),
          loading: () => const Center(child: CircularProgressIndicator()),
        ),
      ],
    );
  }
}

class _RequestCard extends ConsumerWidget {
  const _RequestCard({required this.request});

  final TenantJoinRequest request;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              request.email,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            if (request.message != null && request.message!.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(request.message!),
            ],
            const SizedBox(height: 8),
            Row(
              children: [
                _StatusChip(status: request.status),
                const Spacer(),
                if (request.isPending) ...[
                  TextButton(
                    onPressed: () async {
                      final repository = ref.read(tenantAdminRepositoryProvider);
                      final reviewer = await ref.read(authControllerProvider.future);
                      if (reviewer == null) {
                        return;
                      }
                      await repository.rejectJoinRequest(
                        requestId: request.id,
                        reviewerId: reviewer.userId,
                      );
                      ref.invalidate(tenantJoinRequestsProvider);
                    },
                    child: const Text('Reddet'),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: () => _openApproval(context, ref),
                    child: const Text('Onayla'),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _openApproval(BuildContext context, WidgetRef ref) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) => _RequestApprovalSheet(request: request),
    ).then((updated) {
      if (updated == true) {
        ref.invalidate(tenantJoinRequestsProvider);
        ref.invalidate(tenantMembersProvider);
      }
    });
  }
}

class _InviteFormCard extends ConsumerStatefulWidget {
  const _InviteFormCard();

  @override
  ConsumerState<_InviteFormCard> createState() => _InviteFormCardState();
}

class _InviteFormCardState extends ConsumerState<_InviteFormCard> {
  final TextEditingController _emailController = TextEditingController();
  String _role = 'user';
  Set<String> _permissions = {'inbox'};
  bool _submitting = false;

  @override
  void dispose() {
    _emailController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _emailController,
              decoration: const InputDecoration(
                labelText: 'E-posta',
                hintText: 'ornek@firma.com',
              ),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              value: _role,
              decoration: const InputDecoration(labelText: 'Rol'),
              items: const [
                DropdownMenuItem(value: 'user', child: Text('Temsilci')),
                DropdownMenuItem(value: 'admin', child: Text('Yonetici')),
              ],
              onChanged: (value) {
                if (value == null) {
                  return;
                }
                setState(() {
                  _role = value;
                  if (_role == 'admin') {
                    _permissions = _PermissionOption.keys.toSet();
                  }
                });
              },
            ),
            const SizedBox(height: 12),
            Text(
              'Yetkiler',
              style: Theme.of(context).textTheme.labelLarge,
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final option in _PermissionOption.options)
                  FilterChip(
                    label: Text(option.label),
                    selected: _permissions.contains(option.key),
                    onSelected: _role == 'admin'
                        ? null
                        : (selected) {
                            setState(() {
                              if (selected) {
                                _permissions.add(option.key);
                              } else {
                                _permissions.remove(option.key);
                              }
                            });
                          },
                  ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Davet e-postasi gonderimi mock olarak kaydedilir.',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
                const SizedBox(width: 12),
                FilledButton(
                  onPressed: _submitting ? null : _submitInvite,
                  child: _submitting
                      ? const SizedBox(
                          height: 16,
                          width: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Davet gonder'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _submitInvite() async {
    final email = _emailController.text.trim();
    if (email.isEmpty) {
      return;
    }
    final tenant = ref.read(selectedTenantProvider);
    final auth = await ref.read(authControllerProvider.future);
    if (tenant == null || auth == null) {
      return;
    }
    setState(() {
      _submitting = true;
    });
    try {
      final repository = ref.read(tenantAdminRepositoryProvider);
      await repository.createInvite(
        tenantId: tenant.id,
        email: email,
        role: _role,
        permissions: _role == 'admin' ? _PermissionOption.keys.toSet() : _permissions,
        invitedBy: auth.userId,
      );
      _emailController.clear();
      setState(() {
        _role = 'user';
        _permissions = {'inbox'};
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Davet olusturuldu.')),
        );
      }
      ref.invalidate(tenantInvitesProvider);
    } finally {
      if (mounted) {
        setState(() {
          _submitting = false;
        });
      }
    }
  }
}

class _InviteCard extends ConsumerWidget {
  const _InviteCard({required this.invite});

  final TenantInvite invite;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    invite.email,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _RoleChip(role: invite.role),
                      for (final permission
                          in _PermissionOption.labelsFor(invite.permissions))
                        Chip(label: Text(permission)),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            _StatusChip(status: invite.status),
            if (invite.isPending) ...[
              const SizedBox(width: 8),
              TextButton(
                onPressed: () async {
                  final repository = ref.read(tenantAdminRepositoryProvider);
                  await repository.updateInviteStatus(
                    inviteId: invite.id,
                    status: 'revoked',
                  );
                  ref.invalidate(tenantInvitesProvider);
                },
                child: const Text('Iptal'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _MemberEditorSheet extends ConsumerStatefulWidget {
  const _MemberEditorSheet({required this.member});

  final TenantMember member;

  @override
  ConsumerState<_MemberEditorSheet> createState() => _MemberEditorSheetState();
}

class _MemberEditorSheetState extends ConsumerState<_MemberEditorSheet> {
  late String _role;
  late Set<String> _permissions;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _role = widget.member.role;
    _permissions = Set<String>.from(widget.member.permissions);
  }

  @override
  Widget build(BuildContext context) {
    final isAdmin = _role == 'admin';
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          20,
          20,
          20,
          20 + MediaQuery.of(context).viewInsets.bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Kullanici yetkileri',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              value: _role,
              decoration: const InputDecoration(labelText: 'Rol'),
              items: const [
                DropdownMenuItem(value: 'user', child: Text('Temsilci')),
                DropdownMenuItem(value: 'admin', child: Text('Yonetici')),
              ],
              onChanged: (value) {
                if (value == null) {
                  return;
                }
                setState(() {
                  _role = value;
                  if (_role == 'admin') {
                    _permissions = _PermissionOption.keys.toSet();
                  }
                });
              },
            ),
            const SizedBox(height: 12),
            Text(
              'Yetkiler',
              style: Theme.of(context).textTheme.labelLarge,
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final option in _PermissionOption.options)
                  FilterChip(
                    label: Text(option.label),
                    selected: _permissions.contains(option.key),
                    onSelected: isAdmin
                        ? null
                        : (selected) {
                            setState(() {
                              if (selected) {
                                _permissions.add(option.key);
                              } else {
                                _permissions.remove(option.key);
                              }
                            });
                          },
                  ),
              ],
            ),
            if (isAdmin) ...[
              const SizedBox(height: 8),
              Text(
                'Yonetici tum yetkilere sahiptir.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
            const SizedBox(height: 16),
            Row(
              children: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Vazgec'),
                ),
                const Spacer(),
                FilledButton(
                  onPressed: _saving ? null : _save,
                  child: _saving
                      ? const SizedBox(
                          height: 16,
                          width: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Kaydet'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _save() async {
    setState(() {
      _saving = true;
    });
    try {
      final repository = ref.read(tenantAdminRepositoryProvider);
      await repository.updateMember(
        membershipId: widget.member.id,
        role: _role,
        permissions: _role == 'admin' ? _PermissionOption.keys.toSet() : _permissions,
      );
      if (mounted) {
        Navigator.of(context).pop(true);
      }
    } finally {
      if (mounted) {
        setState(() {
          _saving = false;
        });
      }
    }
  }
}

class _RequestApprovalSheet extends ConsumerStatefulWidget {
  const _RequestApprovalSheet({required this.request});

  final TenantJoinRequest request;

  @override
  ConsumerState<_RequestApprovalSheet> createState() =>
      _RequestApprovalSheetState();
}

class _RequestApprovalSheetState extends ConsumerState<_RequestApprovalSheet> {
  String _role = 'user';
  Set<String> _permissions = {'inbox'};
  bool _saving = false;

  @override
  Widget build(BuildContext context) {
    final isAdmin = _role == 'admin';
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          20,
          20,
          20,
          20 + MediaQuery.of(context).viewInsets.bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Basvuruyu onayla',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              value: _role,
              decoration: const InputDecoration(labelText: 'Rol'),
              items: const [
                DropdownMenuItem(value: 'user', child: Text('Temsilci')),
                DropdownMenuItem(value: 'admin', child: Text('Yonetici')),
              ],
              onChanged: (value) {
                if (value == null) {
                  return;
                }
                setState(() {
                  _role = value;
                  if (_role == 'admin') {
                    _permissions = _PermissionOption.keys.toSet();
                  }
                });
              },
            ),
            const SizedBox(height: 12),
            Text(
              'Yetkiler',
              style: Theme.of(context).textTheme.labelLarge,
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final option in _PermissionOption.options)
                  FilterChip(
                    label: Text(option.label),
                    selected: _permissions.contains(option.key),
                    onSelected: isAdmin
                        ? null
                        : (selected) {
                            setState(() {
                              if (selected) {
                                _permissions.add(option.key);
                              } else {
                                _permissions.remove(option.key);
                              }
                            });
                          },
                  ),
              ],
            ),
            if (isAdmin) ...[
              const SizedBox(height: 8),
              Text(
                'Yonetici tum yetkilere sahiptir.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
            const SizedBox(height: 16),
            Row(
              children: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Vazgec'),
                ),
                const Spacer(),
                FilledButton(
                  onPressed: _saving ? null : _approve,
                  child: _saving
                      ? const SizedBox(
                          height: 16,
                          width: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Onayla'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _approve() async {
    final tenant = ref.read(selectedTenantProvider);
    final reviewer = await ref.read(authControllerProvider.future);
    final userId = widget.request.userId;
    if (tenant == null || reviewer == null || userId == null) {
      return;
    }
    setState(() {
      _saving = true;
    });
    try {
      final repository = ref.read(tenantAdminRepositoryProvider);
      await repository.approveJoinRequest(
        requestId: widget.request.id,
        tenantId: tenant.id,
        userId: userId,
        reviewerId: reviewer.userId,
        role: _role,
        permissions: _role == 'admin' ? _PermissionOption.keys.toSet() : _permissions,
      );
      if (mounted) {
        Navigator.of(context).pop(true);
      }
    } finally {
      if (mounted) {
        setState(() {
          _saving = false;
        });
      }
    }
  }
}

class _RoleChip extends StatelessWidget {
  const _RoleChip({required this.role});

  final String role;

  @override
  Widget build(BuildContext context) {
    final isAdmin = role == 'admin';
    return Chip(
      avatar: Icon(
        isAdmin ? Icons.shield_outlined : Icons.person_outline,
        size: 18,
      ),
      label: Text(isAdmin ? 'Yonetici' : 'Temsilci'),
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.status});

  final String status;

  @override
  Widget build(BuildContext context) {
    final color = _statusColor(context, status);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withOpacity(0.15),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color),
      ),
      child: Text(
        _statusLabel(status),
        style: Theme.of(context).textTheme.labelSmall?.copyWith(color: color),
      ),
    );
  }

  String _statusLabel(String value) {
    switch (value) {
      case 'pending':
        return 'Bekliyor';
      case 'approved':
        return 'Onaylandi';
      case 'rejected':
        return 'Reddedildi';
      case 'accepted':
        return 'Kabul edildi';
      case 'revoked':
        return 'Iptal';
      case 'expired':
        return 'Suresi doldu';
      default:
        return value;
    }
  }

  Color _statusColor(BuildContext context, String value) {
    switch (value) {
      case 'pending':
        return Theme.of(context).colorScheme.secondary;
      case 'approved':
      case 'accepted':
        return Theme.of(context).colorScheme.primary;
      case 'rejected':
      case 'revoked':
        return Theme.of(context).colorScheme.error;
      case 'expired':
        return Theme.of(context).colorScheme.outline;
      default:
        return Theme.of(context).colorScheme.secondary;
    }
  }
}

class _PermissionOption {
  const _PermissionOption(this.key, this.label);

  final String key;
  final String label;

  static const options = [
    _PermissionOption('dashboard', 'Panel'),
    _PermissionOption('inbox', 'Gelen Kutusu'),
    _PermissionOption('bot', 'Bot'),
    _PermissionOption('knowledge', 'Bilgi Bankasi'),
    _PermissionOption('handoff', 'Yonlendirme'),
    _PermissionOption('campaigns', 'Kampanyalar'),
    _PermissionOption('templates', 'Sablonlar'),
    _PermissionOption('custom', 'Ozel Moduller'),
    _PermissionOption('users', 'Kullanicilar'),
  ];

  static Iterable<String> get keys => options.map((option) => option.key);

  static List<String> labelsFor(Set<String> permissions) {
    if (permissions.isEmpty) {
      return ['Yetki yok'];
    }
    final labels = <String>[];
    for (final option in options) {
      if (permissions.contains(option.key)) {
        labels.add(option.label);
      }
    }
    return labels.isEmpty ? ['Yetki yok'] : labels;
  }
}
