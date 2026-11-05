import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../ui/ui.dart';
import '../data/onboarding_errors.dart';
import '../models/pending_invite.dart';
import '../providers/onboarding_providers.dart';
import 'onboarding_parts.dart';

/// Invites addressed to the signed-in user's verified email, with accept/decline.
/// Renders nothing when there are none.
class PendingInvitesSection extends ConsumerWidget {
  const PendingInvitesSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final invites = ref.watch(myInvitesProvider);
    final c = FlowColors.of(context);
    return invites.when(
      data: (items) {
        if (items.isEmpty) return const SizedBox.shrink();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(children: [
              Flexible(
                child: Semantics(
                  header: true,
                  child: Text('Davetleriniz', style: Theme.of(context).textTheme.titleLarge),
                ),
              ),
              const SizedBox(width: FlowSpace.sm),
              CountPill('${items.length}'),
            ]),
            const SizedBox(height: FlowSpace.md),
            for (final invite in items) ...[
              _InviteCard(key: ValueKey(invite.id), invite: invite),
              const SizedBox(height: FlowSpace.md),
            ],
            const SizedBox(height: FlowSpace.sm),
          ],
        );
      },
      error: (_, __) => Padding(
        padding: const EdgeInsets.only(bottom: FlowSpace.lg),
        child: Container(
          padding: const EdgeInsets.fromLTRB(FlowSpace.lg, FlowSpace.sm, FlowSpace.sm, FlowSpace.sm),
          decoration: BoxDecoration(
            color: c.surface,
            borderRadius: FlowRadius.cardAll,
            border: Border.all(color: c.border),
          ),
          child: Row(children: [
            Icon(Icons.error_outline, size: 18, color: c.danger),
            const SizedBox(width: 10),
            const Expanded(child: Text('Davetler yüklenemedi.')),
            TextButton(
              onPressed: () => ref.invalidate(myInvitesProvider),
              child: const Text('Tekrar dene'),
            ),
          ]),
        ),
      ),
      loading: () => const Padding(
        padding: EdgeInsets.only(bottom: FlowSpace.lg),
        child: LinearProgressIndicator(minHeight: 2, semanticsLabel: 'Davetler yükleniyor'),
      ),
    );
  }
}

class _InviteCard extends ConsumerStatefulWidget {
  const _InviteCard({super.key, required this.invite});

  final PendingInvite invite;

  @override
  ConsumerState<_InviteCard> createState() => _InviteCardState();
}

class _InviteCardState extends ConsumerState<_InviteCard> {
  bool _busy = false;
  String? _error;

  @override
  Widget build(BuildContext context) {
    final invite = widget.invite;
    final theme = Theme.of(context);
    final c = FlowColors.of(context);
    return Container(
      padding: const EdgeInsets.all(FlowSpace.lg),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: FlowRadius.cardAll,
        border: Border.all(color: c.borderStrong),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(children: [
            InitialsAvatar(invite.tenantName, size: 44, color: invite.brandColor),
            const SizedBox(width: FlowSpace.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(invite.tenantName, style: theme.textTheme.titleMedium),
                  const SizedBox(height: FlowSpace.xs),
                  Wrap(
                    spacing: FlowSpace.sm,
                    runSpacing: FlowSpace.xs,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      StatusBadge(
                        invite.isAdmin ? 'Yönetici olarak' : 'Ekip üyesi olarak',
                        tone: invite.isAdmin ? FlowTone.accent : FlowTone.neutral,
                      ),
                      Text(
                        'Son gün ${formatDayMonth(invite.expiresAt)}',
                        style: FlowText.mono(context, size: 12),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ]),
          if (_error != null) ...[
            const SizedBox(height: FlowSpace.md),
            InlineNotice(_error!),
          ],
          const SizedBox(height: FlowSpace.md),
          Wrap(
            alignment: WrapAlignment.end,
            spacing: FlowSpace.sm,
            runSpacing: FlowSpace.xs,
            children: [
              TextButton(
                onPressed: _busy ? null : _decline,
                style: TextButton.styleFrom(foregroundColor: c.muted),
                child: const Text('Reddet'),
              ),
              OutlinedButton.icon(
                onPressed: _busy ? null : () => _respond(true),
                icon: _busy
                    ? const SizedBox(
                        height: 16,
                        width: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.check, size: 18),
                label: const Text('Katıl'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _decline() async {
    final confirmed = await confirmAction(
      context,
      title: 'Davet reddedilsin mi?',
      message: '${widget.invite.tenantName} sizi yeniden davet edene kadar bu işletmeye katılamazsınız.',
      confirmLabel: 'Daveti reddet',
      destructive: true,
    );
    if (confirmed && mounted) await _respond(false);
  }

  Future<void> _respond(bool accept) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final tenantId = await ref.read(onboardingRepositoryProvider).respondInvite(widget.invite.id, accept: accept);
      if (!mounted) return;
      if (accept && tenantId != null) {
        await enterTenant(ref, tenantId);
      } else {
        if (accept) setState(() => _error = 'Bu davetin süresi dolmuş.');
        ref.invalidate(myInvitesProvider);
      }
    } catch (error) {
      if (mounted) setState(() => _error = onboardingErrorMessage(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }
}
