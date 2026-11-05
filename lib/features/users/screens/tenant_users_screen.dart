import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../ui/ui.dart';
import '../../billing/providers/billing_providers.dart';
import '../../onboarding/data/onboarding_errors.dart';
import '../../tenancy/providers/tenant_providers.dart';
import '../models/tenant_invite.dart';
import '../models/tenant_join_request.dart';
import '../models/tenant_member.dart';
import '../providers/tenant_admin_providers.dart';
import '../widgets/access_sheet.dart';

/// Ayarlar → Ekip: members and their screens, pending invites (shared by link or
/// WhatsApp) and join requests. Roles and permissions are enforced on the server.
class TenantUsersScreen extends ConsumerWidget {
  const TenantUsersScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final membership = ref.watch(currentMembershipProvider).valueOrNull;
    final canManage = membership?.hasPermission('users') ?? false;
    if (!canManage) {
      return const AppPage(maxWidth: 960, children: [
        EmptyState(
          icon: Icons.lock_outline,
          title: 'Bu bölüme erişiminiz yok',
          message: 'Ekibi yalnızca ekip yönetimi yetkisi olan kişiler görebilir. İşletme yöneticinize başvurun.',
        ),
      ]);
    }

    final members = ref.watch(tenantMembersProvider);
    final invites = ref.watch(tenantInvitesProvider);
    final requests = ref.watch(tenantJoinRequestsProvider);
    final me = ref.watch(authControllerProvider).valueOrNull?.userId;
    // The plan's seat limit is visible to administrators only.
    final overview = membership!.isAdmin ? ref.watch(billingOverviewProvider).valueOrNull : null;

    final count = members.valueOrNull?.length;
    final seats = overview?.limits.seats;
    final seatLine = [
      if (count != null)
        seats != null && seats > 0
            ? '${formatCount(count)} / ${formatCount(seats)} KULLANICI'
            : '${formatCount(count)} KULLANICI',
      if (overview != null && overview.planName.isNotEmpty) upperTr(overview.planName),
    ].join(' · ');

    final pending = invites.valueOrNull?.where((invite) => invite.isPending).toList() ?? const <TenantInvite>[];
    final history = invites.valueOrNull?.where((invite) => !invite.isPending).toList() ?? const <TenantInvite>[];
    final joinRequests = requests.valueOrNull ?? const <TenantJoinRequest>[];

    return AppPage(maxWidth: 960, children: [
      Wrap(
        spacing: FlowSpace.md,
        runSpacing: FlowSpace.md,
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              if (seatLine.isNotEmpty) ...[
                Text(seatLine, style: FlowText.caps(context, size: 12)),
                const SizedBox(height: 6),
              ],
              Text('Ekip arkadaşlarınız yalnızca izin verdiğiniz ekranları görür.',
                  style: Theme.of(context).textTheme.bodySmall),
            ]),
          ),
          FilledButton.icon(
            onPressed: () => _invite(context, ref),
            icon: const Icon(Icons.add, size: 18),
            label: const Text('Ekip arkadaşı davet et'),
          ),
        ],
      ),
      members.when(
        data: (items) => items.isEmpty
            ? const EmptyState(title: 'Henüz ekip üyesi yok', message: 'İlk ekip arkadaşınızı davet edin.')
            : _RowsCard(rows: [
                for (final member in items)
                  _MemberRow(
                    member: member,
                    isMe: member.userId == me,
                    onEdit: () => _editMember(context, ref, member),
                    onRemove: () => _removeMember(context, ref, member),
                  ),
              ]),
        error: (_, __) => ErrorState(title: 'Ekip yüklenemedi', onRetry: () => ref.invalidate(tenantMembersProvider)),
        loading: () => const LoadingList(rows: 3),
      ),
      if (invites.hasError)
        ErrorState(title: 'Davetler yüklenemedi', onRetry: () => ref.invalidate(tenantInvitesProvider))
      else if (pending.isNotEmpty)
        _RowsCard(
          title: 'Bekleyen davetler',
          trailing: CountPill(formatCount(pending.length), strong: false),
          rows: [
            for (final invite in pending)
              _InviteRow(
                invite: invite,
                onCopy: () => _copyInvite(context, ref, invite.email),
                onWhatsApp: () => _shareOnWhatsApp(context, ref, invite.email),
                onRevoke: () => _revokeInvite(context, ref, invite),
              ),
          ],
        ),
      if (requests.hasError)
        ErrorState(title: 'Katılma istekleri yüklenemedi', onRetry: () => ref.invalidate(tenantJoinRequestsProvider))
      else if (joinRequests.isNotEmpty)
        _RowsCard(
          title: 'Katılma istekleri',
          subtitle: 'İşletmenize katılmak isteyen kişiler.',
          rows: [
            for (final request in joinRequests)
              _RequestRow(
                request: request,
                onApprove: () => _approve(context, ref, request),
                onReject: () => _reject(context, ref, request),
              ),
          ],
        ),
      if (history.isNotEmpty)
        _RowsCard(
          title: 'Geçmiş davetler',
          rows: [for (final invite in history) _InviteRow(invite: invite)],
        ),
    ]);
  }

  Future<void> _invite(BuildContext context, WidgetRef ref) async {
    final tenant = ref.read(selectedTenantProvider);
    if (tenant == null) return;
    final choice = await showModalBottomSheet<AccessChoice>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (_) => AccessSheet(
        title: 'Ekip arkadaşı davet et',
        askEmail: true,
        confirmLabel: 'Davet oluştur',
        footnote: 'Davet 14 gün geçerlidir. Kişi bu e-postayla giriş yaptığında daveti görür.',
        onSubmit: (choice) => ref.read(tenantAdminRepositoryProvider).createInvite(
              tenantId: tenant.id,
              email: choice.email!,
              role: choice.role,
              permissions: choice.permissions,
            ),
      ),
    );
    if (choice == null) return;
    ref.invalidate(tenantInvitesProvider);
    if (context.mounted) await _showShareDialog(context, ref, choice.email!.toLowerCase());
  }

  Future<void> _editMember(BuildContext context, WidgetRef ref, TenantMember member) async {
    final choice = await showModalBottomSheet<AccessChoice>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (_) => AccessSheet(
        title: 'Yetkileri düzenle',
        subtitle: member.email ?? member.displayName,
        confirmLabel: 'Kaydet',
        initialRole: member.role,
        initialPermissions: member.permissions,
        onSubmit: (choice) => ref.read(tenantAdminRepositoryProvider).updateMember(
              membershipId: member.id,
              role: choice.role,
              permissions: choice.permissions,
            ),
      ),
    );
    if (choice == null) return;
    ref.invalidate(tenantMembersProvider);
    if (context.mounted) showAppSnack(context, 'Yetkiler güncellendi');
  }

  Future<void> _removeMember(BuildContext context, WidgetRef ref, TenantMember member) async {
    final name = member.displayName ?? member.email ?? 'Bu kişi';
    final confirmed = await confirmAction(
      context,
      title: 'Ekipten çıkarılsın mı?',
      message: '$name bu işletmeye erişimini kaybeder. Yazdığı mesajlar silinmez.',
      confirmLabel: 'Ekipten çıkar',
      destructive: true,
    );
    if (!confirmed) return;
    try {
      await ref.read(tenantAdminRepositoryProvider).removeMember(member.id);
      if (context.mounted) showAppSnack(context, 'Ekipten çıkarıldı');
    } catch (error) {
      if (context.mounted) showAppSnack(context, onboardingErrorMessage(error), error: true);
    } finally {
      ref.invalidate(tenantMembersProvider);
    }
  }

  Future<void> _revokeInvite(BuildContext context, WidgetRef ref, TenantInvite invite) async {
    final confirmed = await confirmAction(
      context,
      title: 'Davet iptal edilsin mi?',
      message: '${invite.email} artık bu davetle katılamaz. İsterseniz yeniden davet edebilirsiniz.',
      confirmLabel: 'Daveti iptal et',
      destructive: true,
    );
    if (!confirmed) return;
    try {
      await ref.read(tenantAdminRepositoryProvider).revokeInvite(invite.id);
    } catch (error) {
      if (context.mounted) showAppSnack(context, onboardingErrorMessage(error), error: true);
    }
    ref.invalidate(tenantInvitesProvider);
  }

  Future<void> _approve(BuildContext context, WidgetRef ref, TenantJoinRequest request) async {
    final choice = await showModalBottomSheet<AccessChoice>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (_) => AccessSheet(
        title: 'Katılma isteğini onayla',
        subtitle: request.email,
        confirmLabel: 'Onayla',
        onSubmit: (choice) async {
          final tenant = ref.read(selectedTenantProvider);
          final reviewer = await ref.read(authControllerProvider.future);
          final userId = request.userId;
          if (tenant == null || reviewer == null || userId == null) {
            throw StateError('Approval context unavailable');
          }
          await ref.read(tenantAdminRepositoryProvider).approveJoinRequest(
                requestId: request.id,
                tenantId: tenant.id,
                userId: userId,
                reviewerId: reviewer.userId,
                role: choice.role,
                permissions: choice.permissions,
              );
        },
      ),
    );
    if (choice == null) return;
    ref
      ..invalidate(tenantJoinRequestsProvider)
      ..invalidate(tenantMembersProvider);
  }

  Future<void> _reject(BuildContext context, WidgetRef ref, TenantJoinRequest request) async {
    final confirmed = await confirmAction(
      context,
      title: 'İstek reddedilsin mi?',
      message: '${request.email} işletmenize katılamaz.',
      confirmLabel: 'Reddet',
      destructive: true,
    );
    if (!confirmed) return;
    try {
      final reviewer = await ref.read(authControllerProvider.future);
      if (reviewer == null) return;
      await ref.read(tenantAdminRepositoryProvider).rejectJoinRequest(
            requestId: request.id,
            reviewerId: reviewer.userId,
          );
    } catch (error) {
      if (context.mounted) showAppSnack(context, onboardingErrorMessage(error), error: true);
    }
    ref.invalidate(tenantJoinRequestsProvider);
  }
}

String _messageFor(WidgetRef ref, String email) =>
    inviteShareMessage(tenantName: ref.read(selectedTenantProvider)?.name ?? 'Ekibiniz', email: email);

Future<void> _copyInvite(BuildContext context, WidgetRef ref, String email) async {
  await Clipboard.setData(ClipboardData(text: _messageFor(ref, email)));
  if (context.mounted) showAppSnack(context, 'Davet mesajı ve bağlantı kopyalandı');
}

Future<void> _shareOnWhatsApp(BuildContext context, WidgetRef ref, String email) async {
  var opened = false;
  try {
    opened = await ref.read(openExternalLinkProvider)(whatsappShareUri(_messageFor(ref, email)));
  } catch (_) {
    opened = false;
  }
  if (!opened && context.mounted) {
    showAppSnack(context, 'WhatsApp açılamadı. Bağlantıyı kopyalayıp kendiniz gönderin.', error: true);
  }
}

Future<void> _showShareDialog(BuildContext context, WidgetRef ref, String email) {
  final message = _messageFor(ref, email);
  return showDialog<void>(
    context: context,
    builder: (dialogContext) {
      final c = FlowColors.of(dialogContext);
      return AlertDialog(
        title: const Text('Davet oluşturuldu'),
        content: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Bu mesajı davet ettiğiniz kişiye iletin:'),
            const SizedBox(height: FlowSpace.md),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(FlowSpace.md),
              decoration: BoxDecoration(
                color: c.raised,
                borderRadius: FlowRadius.controlAll,
                border: Border.all(color: c.border),
              ),
              child: SelectableText(message, style: Theme.of(dialogContext).textTheme.bodyMedium),
            ),
          ]),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            style: TextButton.styleFrom(foregroundColor: c.muted),
            child: const Text('Kapat'),
          ),
          OutlinedButton.icon(
            onPressed: () async {
              Navigator.of(dialogContext).pop();
              await _copyInvite(context, ref, email);
            },
            icon: const Icon(Icons.link, size: 18),
            label: const Text('Bağlantıyı kopyala'),
          ),
          FilledButton.icon(
            onPressed: () async {
              Navigator.of(dialogContext).pop();
              await _shareOnWhatsApp(context, ref, email);
            },
            icon: const Icon(Icons.chat_outlined, size: 18),
            label: const Text('WhatsApp ile gönder'),
          ),
        ],
      );
    },
  );
}

/// A bordered list of rows split by hairlines, with an optional header.
class _RowsCard extends StatelessWidget {
  const _RowsCard({required this.rows, this.title, this.subtitle, this.trailing});

  final List<Widget> rows;
  final String? title;
  final String? subtitle;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final c = FlowColors.of(context);
    return SectionCard(
      title: title,
      subtitle: subtitle,
      trailing: trailing,
      flush: true,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        for (var i = 0; i < rows.length; i++) ...[
          if (i > 0) Divider(height: 1, color: c.border),
          rows[i],
        ],
      ]),
    );
  }
}

/// Leading mark, text and badges; actions sit on the right on wide screens and
/// wrap below the text on phones.
class _PersonRow extends StatelessWidget {
  const _PersonRow({
    required this.leading,
    required this.title,
    this.subtitle,
    this.badges = const [],
    this.actions = const [],
  });

  final Widget leading;
  final Widget title;
  final Widget? subtitle;
  final List<Widget> badges;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final info = Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      title,
      if (subtitle != null) ...[const SizedBox(height: 2), subtitle!],
      if (badges.isNotEmpty) ...[
        const SizedBox(height: FlowSpace.sm),
        Wrap(spacing: 6, runSpacing: 6, children: badges),
      ],
    ]);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: FlowSpace.lg, vertical: 14),
      child: LayoutBuilder(builder: (context, constraints) {
        if (constraints.maxWidth >= 720) {
          return Row(children: [
            leading,
            const SizedBox(width: FlowSpace.md),
            Expanded(child: info),
            if (actions.isNotEmpty) ...[
              const SizedBox(width: FlowSpace.md),
              // One line when it fits; wraps instead of overflowing with large text.
              ConstrainedBox(
                constraints: BoxConstraints(maxWidth: constraints.maxWidth * 0.6),
                child: Wrap(
                  spacing: FlowSpace.sm,
                  runSpacing: FlowSpace.sm,
                  alignment: WrapAlignment.end,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: actions,
                ),
              ),
            ],
          ]);
        }
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            leading,
            const SizedBox(width: FlowSpace.md),
            Expanded(child: info),
          ]),
          if (actions.isNotEmpty) ...[
            const SizedBox(height: FlowSpace.md),
            Wrap(
              spacing: FlowSpace.sm,
              runSpacing: FlowSpace.sm,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: actions,
            ),
          ],
        ]);
      }),
    );
  }
}

class _MemberRow extends StatelessWidget {
  const _MemberRow({required this.member, required this.isMe, required this.onEdit, required this.onRemove});

  final TenantMember member;
  final bool isMe;
  final VoidCallback onEdit;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final c = FlowColors.of(context);
    final name = member.displayName?.trim().isNotEmpty == true
        ? member.displayName!.trim()
        : (member.email ?? 'Adsız üye');
    final showEmail = member.email != null && member.email != name;
    return _PersonRow(
      leading: InitialsAvatar(name, size: 38, accent: isMe),
      title: Text.rich(
        TextSpan(text: name, children: [
          if (isMe) TextSpan(text: ' (siz)', style: TextStyle(color: c.muted, fontWeight: FontWeight.w400)),
        ]),
        style: theme.textTheme.titleMedium,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: showEmail
          ? Text(member.email!, style: FlowText.mono(context, size: 12), maxLines: 1, overflow: TextOverflow.ellipsis)
          : null,
      badges: [
        StatusBadge(accessSummary(member.role, member.permissions),
            tone: member.isAdmin ? FlowTone.accent : FlowTone.neutral),
      ],
      // Your own access is changed by another administrator, so you cannot lock yourself out.
      actions: isMe
          ? const []
          : [
              OutlinedButton(onPressed: onEdit, child: const Text('Yetkileri düzenle')),
              IconButton(
                tooltip: 'Ekipten çıkar',
                onPressed: onRemove,
                icon: const Icon(Icons.person_remove_outlined),
              ),
            ],
    );
  }
}

class _InviteRow extends StatelessWidget {
  const _InviteRow({required this.invite, this.onCopy, this.onWhatsApp, this.onRevoke});

  final TenantInvite invite;
  final VoidCallback? onCopy;
  final VoidCallback? onWhatsApp;
  final VoidCallback? onRevoke;

  @override
  Widget build(BuildContext context) {
    final c = FlowColors.of(context);
    final pending = invite.isPending;
    final ago = formatAgo(invite.createdAt);
    final when = RegExp(r'^\d+ (dk|sa|gün)$').hasMatch(ago) ? '$ago önce' : ago;
    return _PersonRow(
      leading: Container(
        width: 38,
        height: 38,
        decoration: BoxDecoration(
          borderRadius: FlowRadius.controlAll,
          border: Border.all(color: c.borderStrong, width: 1.5),
        ),
        child: Icon(Icons.mail_outline, size: 18, color: c.muted),
      ),
      title: Text(invite.email,
          style: FlowText.mono(context, size: 14, color: c.text), maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(
        upperTr(pending ? 'Davet bekliyor · $when' : 'Davet · $when'),
        style: FlowText.caps(context, color: pending ? c.warning : c.faint),
      ),
      badges: [
        if (!pending) _StatusLabel(status: invite.displayStatus),
        StatusBadge(accessSummary(invite.role, invite.permissions)),
      ],
      actions: pending
          ? [
              OutlinedButton.icon(
                onPressed: onCopy,
                icon: const Icon(Icons.link, size: 18),
                label: const Text('Bağlantıyı kopyala'),
              ),
              OutlinedButton.icon(
                onPressed: onWhatsApp,
                style: OutlinedButton.styleFrom(
                  backgroundColor: c.accentSoft,
                  side: BorderSide(color: c.isDark ? c.lime : c.limeEdge),
                ),
                icon: const Icon(Icons.chat_outlined, size: 18),
                label: const Text('WhatsApp ile gönder'),
              ),
              TextButton(
                onPressed: onRevoke,
                style: TextButton.styleFrom(foregroundColor: c.muted),
                child: const Text('Daveti iptal et'),
              ),
            ]
          : const [],
    );
  }
}

class _RequestRow extends StatelessWidget {
  const _RequestRow({required this.request, required this.onApprove, required this.onReject});

  final TenantJoinRequest request;
  final VoidCallback onApprove;
  final VoidCallback onReject;

  @override
  Widget build(BuildContext context) {
    final c = FlowColors.of(context);
    final message = request.message?.trim() ?? '';
    return _PersonRow(
      leading: InitialsAvatar(request.email, size: 38),
      title: Text(request.email,
          style: FlowText.mono(context, size: 14, color: c.text), maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: message.isEmpty
          ? Text(upperTr(formatDate(request.createdAt)), style: FlowText.caps(context, color: c.faint))
          : Text('“$message”', style: Theme.of(context).textTheme.bodySmall),
      badges: [_StatusLabel(status: request.status)],
      actions: request.isPending
          ? [
              TextButton(
                onPressed: onReject,
                style: TextButton.styleFrom(foregroundColor: c.muted),
                child: const Text('Reddet'),
              ),
              OutlinedButton(onPressed: onApprove, child: const Text('Onayla')),
            ]
          : const [],
    );
  }
}

/// Invite and join request status as a badge.
class _StatusLabel extends StatelessWidget {
  const _StatusLabel({required this.status});

  final String status;

  @override
  Widget build(BuildContext context) {
    final (label, tone) = switch (status) {
      'pending' => ('Bekliyor', FlowTone.warning),
      'approved' => ('Onaylandı', FlowTone.accent),
      'accepted' => ('Kabul edildi', FlowTone.accent),
      'rejected' || 'declined' => ('Reddedildi', FlowTone.danger),
      'revoked' => ('İptal edildi', FlowTone.neutral),
      'expired' => ('Süresi doldu', FlowTone.neutral),
      _ => ('Bilinmiyor', FlowTone.neutral),
    };
    return StatusBadge(label, tone: tone);
  }
}
