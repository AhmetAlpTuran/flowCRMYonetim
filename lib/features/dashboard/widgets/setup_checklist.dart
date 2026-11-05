import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../ui/ui.dart';
import '../../shell/shell_providers.dart';
import '../../tenancy/providers/tenant_providers.dart';

/// One first-run step and the screen that completes it.
class SetupStep {
  const SetupStep(this.key, this.title, this.destination, {this.optional = false, this.doneTitle});

  final String key;

  /// What to do, while the step is open.
  final String title;
  final ShellDestinationId destination;
  final bool optional;

  /// What is true once the step is done; falls back to [title].
  final String? doneTitle;
}

/// Required steps first (WhatsApp, knowledge, bot), then the optional ones. A solo
/// owner does not need a team, so inviting one is optional.
const setupSteps = [
  SetupStep('whatsapp', 'WhatsApp numaranızı bağlayın', ShellDestinationId.connections,
      doneTitle: 'WhatsApp numaranız bağlı'),
  SetupStep('knowledge', 'Bilgi bankasına not veya belge ekleyin', ShellDestinationId.knowledge,
      doneTitle: 'Bilgi bankasında içerik var'),
  SetupStep('bot', 'Botu yapılandırıp etkinleştirin', ShellDestinationId.bot, doneTitle: 'Bot etkin'),
  SetupStep('team', 'Ekip arkadaşınızı davet edin', ShellDestinationId.users,
      optional: true, doneTitle: 'Ekip arkadaşınız davet edildi'),
  SetupStep('catalog', 'Kataloğa ürün, oda veya araç ekleyin', ShellDestinationId.catalog,
      optional: true, doneTitle: 'Katalogda kayıt var'),
  SetupStep('contacts', 'Kişilerinizi içe aktarın', ShellDestinationId.contacts,
      optional: true, doneTitle: 'Kişileriniz eklendi'),
  SetupStep('billing', 'Fatura bilgilerinizi girin', ShellDestinationId.billing,
      optional: true, doneTitle: 'Fatura bilgileriniz kayıtlı'),
];

/// True while an administrator still has required steps open (the card is shown).
bool setupChecklistPending(Map<String, bool>? progress) =>
    progress != null && setupSteps.any((step) => !step.optional && progress[step.key] != true);

typedef SetupProgressLoader = Future<Map<String, bool>> Function(String tenantId);

/// Loads `tenant_setup_progress`; overridden in widget tests.
final setupProgressLoaderProvider = Provider<SetupProgressLoader>((ref) => (tenantId) async {
      final data = await Supabase.instance.client
          .rpc('tenant_setup_progress', params: {'p_tenant_id': tenantId}).timeout(const Duration(seconds: 20));
      return {for (final entry in (data as Map).entries) entry.key as String: entry.value == true};
    });

/// Null for members who are not administrators.
final setupProgressProvider = FutureProvider<Map<String, bool>?>((ref) async {
  final tenant = ref.watch(selectedTenantProvider);
  bool admin;
  try {
    admin = (await ref.watch(currentMembershipProvider.future))?.isAdmin == true;
  } catch (_) {
    admin = false;
  }
  if (tenant == null || !admin) return null;
  return ref.watch(setupProgressLoaderProvider)(tenant.id);
});

/// "Kurulum": the first steps of a new business, until the required ones are done.
class SetupChecklistCard extends ConsumerWidget {
  const SetupChecklistCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final progress = ref.watch(setupProgressProvider).valueOrNull;
    if (!setupChecklistPending(progress)) return const SizedBox.shrink();
    final c = FlowColors.of(context);
    final required = setupSteps.where((s) => !s.optional).toList();
    final optional = setupSteps.where((s) => s.optional).toList();
    final done = required.where((s) => progress![s.key] == true).length;

    Widget row(SetupStep step) => _StepRow(
          step: step,
          done: progress![step.key] == true,
          onTap: () => openShellDestination(ref, step.destination),
        );

    return SectionCard(
      title: 'Kurulum',
      trailing: Semantics(
        label: '${required.length} zorunlu adımdan $done tamamlandı',
        excludeSemantics: true,
        child: Text(
          upperTr('$done / ${required.length} tamam'),
          style: FlowText.caps(context, size: 12, color: c.accentText),
        ),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        LinearProgressIndicator(
          value: done / required.length,
          semanticsLabel: 'Kurulum ilerlemesi',
        ),
        const SizedBox(height: FlowSpace.md + 2),
        for (final step in required) row(step),
        if (optional.isNotEmpty) ...[
          Padding(
            padding: const EdgeInsets.symmetric(vertical: FlowSpace.sm),
            child: CustomPaint(
              size: const Size(double.infinity, 1),
              painter: _DashedLinePainter(c.borderStrong),
            ),
          ),
          for (final step in optional) row(step),
        ],
        const SizedBox(height: FlowSpace.md),
        Text(
          'Tek başınıza çalışıyorsanız ekip adımını atlayabilirsiniz; kurulum onsuz da tamamlanır.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ]),
    );
  }
}

class _StepRow extends StatelessWidget {
  const _StepRow({required this.step, required this.done, required this.onTap});

  final SetupStep step;
  final bool done;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = FlowColors.of(context);
    final theme = Theme.of(context);
    final title = done ? (step.doneTitle ?? step.title) : step.title;
    return MergeSemantics(
      child: Semantics(
        checked: done,
        child: InkWell(
          onTap: onTap,
          borderRadius: FlowRadius.controlAll,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 44),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: FlowSpace.xs, vertical: 6),
              child: Row(children: [
                _StepMark(done: done),
                const SizedBox(width: FlowSpace.md),
                Expanded(
                  child: Wrap(
                    spacing: FlowSpace.sm,
                    runSpacing: FlowSpace.xs,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text(
                        title,
                        style: theme.textTheme.bodyMedium?.copyWith(color: done ? c.muted : c.text),
                      ),
                      if (step.optional) const StatusBadge('İsteğe bağlı'),
                    ],
                  ),
                ),
                if (!done) ...[
                  const SizedBox(width: FlowSpace.sm),
                  Icon(Icons.chevron_right_rounded, size: 20, color: c.faint),
                ],
              ]),
            ),
          ),
        ),
      ),
    );
  }
}

/// A lime check circle once done; a dashed ring while open.
class _StepMark extends StatelessWidget {
  const _StepMark({required this.done});

  final bool done;

  @override
  Widget build(BuildContext context) {
    final c = FlowColors.of(context);
    if (!done) {
      return ExcludeSemantics(
        child: CustomPaint(size: const Size.square(22), painter: _DashedRingPainter(c.faint)),
      );
    }
    return ExcludeSemantics(
      child: Container(
        width: 22,
        height: 22,
        decoration: BoxDecoration(
          color: c.lime,
          shape: BoxShape.circle,
          border: c.isDark ? null : Border.all(color: c.limeEdge),
        ),
        child: Icon(Icons.check_rounded, size: 14, color: c.onLime),
      ),
    );
  }
}

class _DashedRingPainter extends CustomPainter {
  _DashedRingPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    const dashes = 12;
    const sweep = 2 * 3.141592653589793 / dashes;
    final rect = Offset.zero & size;
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..color = color;
    for (var i = 0; i < dashes; i++) {
      canvas.drawArc(rect.deflate(0.75), i * sweep, sweep * 0.55, false, paint);
    }
  }

  @override
  bool shouldRepaint(_DashedRingPainter old) => old.color != color;
}

class _DashedLinePainter extends CustomPainter {
  _DashedLinePainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1;
    for (var x = 0.0; x < size.width; x += 7) {
      canvas.drawLine(Offset(x, 0.5), Offset((x + 4).clamp(0, size.width), 0.5), paint);
    }
  }

  @override
  bool shouldRepaint(_DashedLinePainter old) => old.color != color;
}
