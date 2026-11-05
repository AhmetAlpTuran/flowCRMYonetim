import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../ui/ui.dart';
import '../../inbox/providers/inbox_providers.dart';
import '../../tenancy/models/tenant.dart';
import '../../tenancy/models/tenant_membership.dart';
import '../../tenancy/providers/tenant_providers.dart';
import '../models/dashboard_metrics.dart';
import '../providers/dashboard_providers.dart';
import '../widgets/agent_performance.dart';
import '../widgets/live_queue.dart';
import '../widgets/setup_checklist.dart';

/// True when the member may open [feature] in the selected business (the shell's rule).
bool _allowed(TenantMembership? membership, Tenant? tenant, TenantFeature feature) =>
    membership != null &&
    tenant != null &&
    tenant.features.contains(feature) &&
    membership.hasPermission(feature.permissionKey);

/// "Günaydın", "İyi günler", "İyi akşamlar"; "İyi çalışmalar" on the night shift.
String dashboardGreeting(DateTime now) {
  final hour = now.toLocal().hour;
  if (hour >= 5 && hour < 11) return 'Günaydın';
  if (hour >= 11 && hour < 18) return 'İyi günler';
  if (hour >= 18) return 'İyi akşamlar';
  return 'İyi çalışmalar';
}

/// Ana sayfa: the live queue, the period's numbers, first-run steps and the team.
class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final metrics = ref.watch(dashboardMetricsProvider);
    final membership = ref.watch(currentMembershipProvider).valueOrNull;
    final tenant = ref.watch(selectedTenantProvider);
    final inbox = _allowed(membership, tenant, TenantFeature.inbox);
    final handoff = _allowed(membership, tenant, TenantFeature.handoff);
    final conversations = inbox ? ref.watch(conversationsProvider) : null;
    final showSetup = setupChecklistPending(ref.watch(setupProgressProvider).valueOrNull);
    final agents = ref.watch(agentMetricsProvider);
    final showAgents = agents.hasError || agents.valueOrNull != null;
    final queue = attentionQueue(conversations?.valueOrNull ?? const []);
    final metricsData = metrics.valueOrNull;

    return RefreshIndicator(
      onRefresh: () async {
        ref
          ..invalidate(agentMetricsProvider)
          ..invalidate(setupProgressProvider)
          ..invalidate(dashboardMetricsProvider);
        if (inbox) ref.invalidate(conversationsProvider);
        await ref.read(dashboardMetricsProvider.future);
      },
      child: _StaggeredPage(children: [
        const _Header(),
        if (conversations != null)
          LiveQueueHero(conversations: conversations, metrics: metricsData, handoffAllowed: handoff),
        if (metrics.hasError && !metrics.isLoading)
          ErrorState(
            title: 'Panel yüklenemedi',
            onRetry: () => ref.invalidate(dashboardMetricsProvider),
          )
        else if (metricsData != null)
          _MetricsView(metrics: metricsData, showLiveCounts: conversations == null)
        else if (metrics.isLoading)
          const _LoadingCard(),
        if (queue.isNotEmpty || showSetup)
          _SideBySide(children: [
            if (queue.isNotEmpty) AttentionList(conversations: queue),
            if (showSetup) const SetupChecklistCard(),
          ]),
        if (showAgents) const AgentPerformanceSection(),
      ]),
    );
  }
}

/// "PERŞEMBE · 5 KASIM", the greeting and the reporting period.
class _Header extends ConsumerWidget {
  const _Header();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = FlowColors.of(context);
    final theme = Theme.of(context);
    final days = ref.watch(dashboardPeriodProvider);
    final now = DateTime.now();
    final wide = MediaQuery.sizeOf(context).width >= FlowBreakpoints.compact;
    return Wrap(
      alignment: WrapAlignment.spaceBetween,
      crossAxisAlignment: WrapCrossAlignment.end,
      spacing: FlowSpace.lg,
      runSpacing: FlowSpace.lg,
      children: [
        Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(
            upperTr('${formatWeekday(now)} · ${formatDayMonth(now)}'),
            style: FlowText.caps(context, size: 12, color: c.muted),
          ),
          const SizedBox(height: FlowSpace.sm),
          Text(
            '${dashboardGreeting(now)}.',
            style: wide ? theme.textTheme.headlineMedium : theme.textTheme.headlineSmall,
          ),
        ]),
        SegmentedButton<int>(
          segments: const [
            ButtonSegment(value: 1, label: Text('Bugün')),
            ButtonSegment(value: 7, label: Text('7 gün')),
            ButtonSegment(value: 30, label: Text('30 gün')),
          ],
          selected: {days},
          showSelectedIcon: false,
          onSelectionChanged: (value) => ref.read(dashboardPeriodProvider.notifier).state = value.first,
        ),
      ],
    );
  }
}

class _MetricsView extends StatelessWidget {
  const _MetricsView({required this.metrics, required this.showLiveCounts});

  final DashboardMetrics metrics;

  /// The hero shows these counts when the member may open the inbox.
  final bool showLiveCounts;

  @override
  Widget build(BuildContext context) {
    final m = metrics;
    final sections = <Widget>[
      if (showLiveCounts)
        _TileGroup(title: 'Şu an', tiles: [
          StatTile(
            label: 'Açık konuşma',
            value: formatCount(m.openConversations + m.pendingConversations),
            footnote: 'açık ve beklemede',
          ),
          StatTile(
            label: 'Temsilci bekleyen',
            value: formatCount(m.handoffConversations),
            footnote: 'bir temsilci istedi',
            tone: FlowTone.warning,
          ),
          StatTile(
            label: 'Atanmamış',
            value: formatCount(m.unassignedWaiting),
            footnote: 'kimseye atanmadan bekliyor',
            tone: FlowTone.info,
          ),
        ]),
      _TileGroup(title: dashboardPeriodLabel(m.periodDays), tiles: [
        StatTile(
          label: 'Gelen mesaj',
          value: formatCount(m.inboundMessages),
          footnote: '${formatCount(m.startedConversations)} yeni konuşma',
        ),
        StatTile(
          label: 'Bot yanıt oranı',
          value: formatPercent(m.botShare),
          footnote: '${formatCount(m.botReplies)} bot · ${formatCount(m.humanReplies)} temsilci',
          tone: FlowTone.assistant,
        ),
        StatTile(
          label: 'Medyan ilk yanıt',
          value: formatDuration(m.medianFirstResponse),
          footnote: 'Temsilci: ${formatDuration(m.medianFirstHumanResponse)}',
        ),
        StatTile(
          label: 'Çözülen talep',
          value: '${formatCount(m.supportResolved)} / ${formatCount(m.supportOpened)}',
          footnote: 'Çözüm süresi: ${formatDuration(m.medianResolution)}',
        ),
        StatTile(
          label: 'Aktarılan sohbet',
          value: formatCount(m.handoffs),
          footnote: 'temsilciye yönlendirildi',
        ),
        if (m.failedReplies > 0)
          StatTile(
            label: 'Başarısız yanıt',
            value: formatCount(m.failedReplies),
            footnote: 'WhatsApp\'a iletilemedi',
            tone: FlowTone.danger,
          ),
      ]),
      if (m.campaignAccepted > 0)
        _TileGroup(title: 'Kampanyalar', tiles: [
          StatTile(
            label: 'Gönderilen',
            value: formatCount(m.campaignAccepted),
            footnote: m.campaignFailed > 0 ? '${formatCount(m.campaignFailed)} başarısız' : 'WhatsApp kabul etti',
          ),
          StatTile(
            label: 'Teslim edilen',
            value: formatPercent(m.deliveryRate),
            footnote: '${formatCount(m.campaignDelivered)} kişiye ulaştı',
          ),
          StatTile(
            label: 'Okunan',
            value: formatPercent(m.readRate),
            footnote: '${formatCount(m.campaignRead)} kişi okudu',
          ),
        ]),
      if (m.daily.length > 1)
        SectionCard(title: 'Günlük mesaj trafiği', child: ActivityChart(days: m.daily)),
    ];
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      for (var i = 0; i < sections.length; i++) ...[
        if (i > 0) const SizedBox(height: FlowSpace.xl),
        sections[i],
      ],
    ]);
  }
}

/// A heading over a balanced grid of KPI tiles: rows of equal length where possible,
/// and a short last row stretched to the full width.
class _TileGroup extends StatelessWidget {
  const _TileGroup({required this.title, required this.tiles});

  final String title;
  final List<StatTile> tiles;

  static const _minTile = 160.0;
  static const _gap = FlowSpace.md;

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Semantics(header: true, child: Text(title, style: Theme.of(context).textTheme.titleLarge)),
      const SizedBox(height: FlowSpace.md),
      LayoutBuilder(builder: (context, constraints) {
        final fit = ((constraints.maxWidth + _gap) / (_minTile + _gap)).floor().clamp(1, 4);
        final rows = (tiles.length / fit).ceil();
        final columns = (tiles.length / rows).ceil();
        // Single-column phones get smaller numerals so the page stays short.
        final size = columns == 1 ? 40.0 : 48.0;
        final grid = <Widget>[];
        for (var start = 0; start < tiles.length; start += columns) {
          final row = tiles.sublist(start, (start + columns).clamp(0, tiles.length));
          if (start > 0) grid.add(const SizedBox(height: _gap));
          grid.add(Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            for (var i = 0; i < row.length; i++) ...[
              if (i > 0) const SizedBox(width: _gap),
              Expanded(
                child: StatTile(
                  label: row[i].label,
                  value: row[i].value,
                  footnote: row[i].footnote,
                  tone: row[i].tone,
                  size: size,
                ),
              ),
            ],
          ]));
        }
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: grid);
      }),
    ]);
  }
}

/// Places two panels side by side on wide screens, stacked on narrow ones.
class _SideBySide extends StatelessWidget {
  const _SideBySide({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) {
      if (children.length < 2 || constraints.maxWidth < 940) {
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          for (var i = 0; i < children.length; i++) ...[
            if (i > 0) const SizedBox(height: FlowSpace.lg),
            children[i],
          ],
        ]);
      }
      return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        for (var i = 0; i < children.length; i++) ...[
          if (i > 0) const SizedBox(width: FlowSpace.lg),
          Expanded(child: children[i]),
        ],
      ]);
    });
  }
}

class _LoadingCard extends StatelessWidget {
  const _LoadingCard();

  @override
  Widget build(BuildContext context) {
    final c = FlowColors.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: FlowSpace.sm),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: FlowRadius.cardAll,
        border: Border.all(color: c.border),
      ),
      child: const LoadingList(rows: 3),
    );
  }
}

/// The page's one staggered entrance: each section rises in 60 ms after the previous.
class _StaggeredPage extends StatefulWidget {
  const _StaggeredPage({required this.children});

  final List<Widget> children;

  @override
  State<_StaggeredPage> createState() => _StaggeredPageState();
}

class _StaggeredPageState extends State<_StaggeredPage> with SingleTickerProviderStateMixin {
  static const _slots = 6;
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: FlowMotion.entrance + FlowMotion.stagger * (_slots - 1),
  );
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    if (FlowMotion.reduced(context)) {
      _controller.value = 1;
    } else {
      _controller.forward();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final total = _controller.duration!.inMilliseconds;
    final step = FlowMotion.stagger.inMilliseconds;
    final length = FlowMotion.entrance.inMilliseconds;
    return AppPage(children: [
      for (final (index, child) in widget.children.indexed)
        _Rise(
          animation: _controller.drive(CurveTween(
            curve: Interval(
              step * index.clamp(0, _slots - 1) / total,
              (step * index.clamp(0, _slots - 1) + length) / total,
              curve: FlowMotion.curve,
            ),
          )),
          child: child,
        ),
    ]);
  }
}

class _Rise extends AnimatedWidget {
  const _Rise({required Animation<double> animation, required this.child}) : super(listenable: animation);

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final t = (listenable as Animation<double>).value;
    return Opacity(
      opacity: t,
      child: Transform.translate(offset: Offset(0, 10 * (1 - t)), child: child),
    );
  }
}

/// Paired daily bars: customer messages and replies.
class ActivityChart extends StatelessWidget {
  const ActivityChart({super.key, required this.days});
  final List<DailyActivity> days;

  @override
  Widget build(BuildContext context) {
    final c = FlowColors.of(context);
    final peak = days.fold<int>(1, (max, d) {
      final value = d.inbound > d.replies ? d.inbound : d.replies;
      return value > max ? value : max;
    });
    String label(DailyActivity d) => '${d.day.day}.${d.day.month}';
    return LayoutBuilder(builder: (context, constraints) {
      // At most one date label per 52 px, and never more than seven.
      final slots = (constraints.maxWidth / 52).floor().clamp(1, 7);
      final labelEvery = (days.length / slots).ceil();
      return _chart(context, c, peak, labelEvery, label);
    });
  }

  Widget _chart(
    BuildContext context,
    FlowColors c,
    int peak,
    int labelEvery,
    String Function(DailyActivity) label,
  ) {
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      SizedBox(
        height: 140,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            for (final day in days)
              Expanded(
                child: Tooltip(
                  message: '${label(day)}: ${day.inbound} gelen, ${day.replies} yanıt',
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      _Bar(fraction: day.inbound / peak, color: c.meter),
                      _Bar(fraction: day.replies / peak, color: c.muted),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
      Divider(height: 1, color: c.border),
      const SizedBox(height: 6),
      ExcludeSemantics(
        child: Row(children: [
          for (var i = 0; i < days.length; i += labelEvery)
            Expanded(
              flex: (days.length - i).clamp(1, labelEvery),
              child: Text(
                label(days[i]),
                style: FlowText.mono(context, size: 11, color: c.faint),
                maxLines: 1,
                overflow: TextOverflow.clip,
                softWrap: false,
              ),
            ),
        ]),
      ),
      const SizedBox(height: FlowSpace.md),
      Wrap(spacing: FlowSpace.lg, runSpacing: FlowSpace.xs, children: [
        _Legend(color: c.meter, label: 'Gelen mesaj'),
        _Legend(color: c.muted, label: 'Yanıt'),
      ]),
    ]);
  }
}

class _Bar extends StatelessWidget {
  const _Bar({required this.fraction, required this.color});
  final double fraction;
  final Color color;

  @override
  Widget build(BuildContext context) => Expanded(
        child: FractionallySizedBox(
          heightFactor: fraction <= 0 ? 0.01 : fraction,
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 1),
            decoration: BoxDecoration(
              color: color,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(2)),
            ),
          ),
        ),
      );
}

class _Legend extends StatelessWidget {
  const _Legend({required this.color, required this.label});
  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) => Row(mainAxisSize: MainAxisSize.min, children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(3)),
        ),
        const SizedBox(width: 6),
        Text(label, style: Theme.of(context).textTheme.bodySmall),
      ]);
}
