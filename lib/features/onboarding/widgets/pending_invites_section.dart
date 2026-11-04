import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/onboarding_errors.dart';
import '../models/pending_invite.dart';
import '../providers/onboarding_providers.dart';

/// Invites addressed to the signed-in user's verified email, with accept/decline.
class PendingInvitesSection extends ConsumerWidget {
  const PendingInvitesSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final invites = ref.watch(myInvitesProvider);
    return invites.when(
      data: (items) {
        if (items.isEmpty) return const SizedBox.shrink();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Davetleriniz', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            for (final invite in items) ...[
              _InviteTile(key: ValueKey(invite.id), invite: invite),
              const SizedBox(height: 8),
            ],
            const SizedBox(height: 8),
          ],
        );
      },
      error: (_, __) => Padding(
        padding: const EdgeInsets.only(bottom: 16),
        child: Row(children: [
          const Expanded(child: Text('Davetler yüklenemedi.')),
          TextButton(
            onPressed: () => ref.invalidate(myInvitesProvider),
            child: const Text('Tekrar dene'),
          ),
        ]),
      ),
      loading: () => const Padding(
        padding: EdgeInsets.only(bottom: 16),
        child: LinearProgressIndicator(minHeight: 2),
      ),
    );
  }
}

class _InviteTile extends ConsumerStatefulWidget {
  const _InviteTile({super.key, required this.invite});

  final PendingInvite invite;

  @override
  ConsumerState<_InviteTile> createState() => _InviteTileState();
}

class _InviteTileState extends ConsumerState<_InviteTile> {
  bool _busy = false;
  String? _error;

  @override
  Widget build(BuildContext context) {
    final invite = widget.invite;
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              CircleAvatar(
                backgroundColor: invite.brandColor ?? theme.colorScheme.primary,
                child: const Icon(Icons.apartment, color: Colors.white),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(invite.tenantName, style: theme.textTheme.titleSmall),
                    Text(
                      invite.isAdmin ? 'Yönetici olarak' : 'Ekip üyesi olarak',
                      style: theme.textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
            ]),
            if (_error != null) ...[
              const SizedBox(height: 8),
              Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
            ],
            const SizedBox(height: 8),
            Wrap(
              alignment: WrapAlignment.end,
              spacing: 8,
              children: [
                TextButton(
                  onPressed: _busy ? null : () => _respond(false),
                  child: const Text('Reddet'),
                ),
                FilledButton(
                  onPressed: _busy ? null : () => _respond(true),
                  child: _busy
                      ? const SizedBox(
                          height: 16,
                          width: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Katıl'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _respond(bool accept) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final tenantId = await ref
          .read(onboardingRepositoryProvider)
          .respondInvite(widget.invite.id, accept: accept);
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
