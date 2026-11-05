import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../ui/ui.dart';
import '../../tenancy/providers/tenant_providers.dart';
import '../models/dashboard_metrics.dart';
import '../providers/dashboard_providers.dart';

/// One member's numbers from `dashboard_agent_metrics`.
class AgentMetric {
  const AgentMetric({
    required this.name,
    required this.role,
    required this.replies,
    required this.firstResponses,
    required this.resolved,
    required this.openAssigned,
    this.medianFirstResponse,
  });

  factory AgentMetric.fromJson(Map<String, dynamic> json) => AgentMetric(
        name: json['name'] as String? ?? 'Kullanıcı',
        role: json['role'] as String? ?? 'user',
        replies: (json['replies'] as num?)?.toInt() ?? 0,
        firstResponses: (json['first_responses'] as num?)?.toInt() ?? 0,
        resolved: (json['resolved'] as num?)?.toInt() ?? 0,
        openAssigned: (json['open_assigned'] as num?)?.toInt() ?? 0,
        medianFirstResponse: json['median_first_response_seconds'] is num
            ? Duration(milliseconds: ((json['median_first_response_seconds'] as num) * 1000).round())
            : null,
      );

  final String name;
  final String role;
  final int replies;
  final int firstResponses;
  final int resolved;
  final int openAssigned;
  final Duration? medianFirstResponse;

  /// One sentence for screen readers, e.g. "12 yanıt · ilk yanıt 3 dk · …".
  String get summary => '$replies yanıt · ilk yanıt ${formatDuration(medianFirstResponse)}'
      ' · $resolved çözüldü · $openAssigned açık konuşma';
}

typedef AgentMetricsLoader = Future<List<AgentMetric>> Function(String tenantId, int days);

/// Loads per-agent metrics; overridden in widget tests.
final agentMetricsLoaderProvider = Provider<AgentMetricsLoader>((ref) => (tenantId, days) async {
      final data = await Supabase.instance.client.rpc('dashboard_agent_metrics', params: {
        'p_tenant_id': tenantId,
        'p_days': days,
        'p_timezone': 'Europe/Istanbul',
      }).timeout(const Duration(seconds: 20));
      final agents = (data as Map)['agents'] as List? ?? const [];
      return [for (final a in agents) AgentMetric.fromJson(Map<String, dynamic>.from(a as Map))];
    });

/// Null for members who are not administrators (the section is hidden).
final agentMetricsProvider = FutureProvider<List<AgentMetric>?>((ref) async {
  final tenant = ref.watch(selectedTenantProvider);
  bool admin;
  try {
    admin = (await ref.watch(currentMembershipProvider.future))?.isAdmin == true;
  } catch (_) {
    admin = false;
  }
  if (tenant == null || !admin) return null;
  return ref.watch(agentMetricsLoaderProvider)(tenant.id, ref.watch(dashboardPeriodProvider));
});

/// "Bugün" or "Son 7 gün" for a reporting period.
String dashboardPeriodLabel(int days) => days == 1 ? 'Bugün' : 'Son $days gün';

/// "Ekip performansı" on the dashboard (administrators): a table with mono numbers
/// and a reply meter that scrolls sideways on phones.
class AgentPerformanceSection extends ConsumerWidget {
  const AgentPerformanceSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final agents = ref.watch(agentMetricsProvider);
    return agents.when(
      loading: () => const SizedBox.shrink(),
      error: (_, __) => ErrorState(
        title: 'Ekip performansı yüklenemedi',
        onRetry: () => ref.invalidate(agentMetricsProvider),
      ),
      data: (list) {
        if (list == null) return const SizedBox.shrink();
        final days = ref.watch(dashboardPeriodProvider);
        return SectionCard(
          title: 'Ekip performansı',
          flush: true,
          trailing: Text(upperTr(dashboardPeriodLabel(days)), style: FlowText.caps(context)),
          child: list.isEmpty
              ? Padding(
                  padding: const EdgeInsets.fromLTRB(20, FlowSpace.lg, 20, 20),
                  child: Text('Henüz ekip üyesi yok.', style: Theme.of(context).textTheme.bodyMedium),
                )
              : _AgentTable(agents: list),
        );
      },
    );
  }
}

/// Column widths as flex factors: person, replies (meter), first reply, resolved, open.
const _flex = [5, 5, 3, 3, 2];
const _tableMinWidth = 640.0;

class _AgentTable extends StatelessWidget {
  const _AgentTable({required this.agents});

  final List<AgentMetric> agents;

  @override
  Widget build(BuildContext context) {
    final c = FlowColors.of(context);
    final peak = agents.fold<int>(1, (max, agent) => math.max(max, agent.replies));
    return LayoutBuilder(builder: (context, constraints) {
      final width = math.max(constraints.maxWidth, _tableMinWidth);
      final table = SizedBox(
        width: width,
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const _HeaderRow(),
          for (final (index, agent) in agents.indexed) ...[
            Divider(height: 1, color: c.border),
            _AgentRow(agent: agent, share: agent.replies / peak, last: index == agents.length - 1),
          ],
        ]),
      );
      if (width <= constraints.maxWidth) return table;
      return SingleChildScrollView(scrollDirection: Axis.horizontal, child: table);
    });
  }
}

class _HeaderRow extends StatelessWidget {
  const _HeaderRow();

  @override
  Widget build(BuildContext context) {
    const labels = ['Kişi', 'Yanıt', 'İlk yanıt', 'Çözülen', 'Açık'];
    return ExcludeSemantics(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: FlowSpace.md),
        child: Row(children: [
          for (var i = 0; i < labels.length; i++) ...[
            if (i > 0) const SizedBox(width: FlowSpace.lg),
            Expanded(
              flex: _flex[i],
              child: Text(
                upperTr(labels[i]),
                style: FlowText.caps(context),
                textAlign: i < 2 ? TextAlign.left : TextAlign.right,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ]),
      ),
    );
  }
}

class _AgentRow extends StatelessWidget {
  const _AgentRow({required this.agent, required this.share, required this.last});

  final AgentMetric agent;
  final double share;
  final bool last;

  @override
  Widget build(BuildContext context) {
    final c = FlowColors.of(context);
    final theme = Theme.of(context);
    Widget number(String value, int flex) => Expanded(
          flex: flex,
          child: Text(
            value,
            textAlign: TextAlign.right,
            maxLines: 1,
            style: FlowText.mono(context, size: 14, color: c.text),
          ),
        );
    return Semantics(
      label: '${agent.name}: ${agent.summary}',
      excludeSemantics: true,
      child: Padding(
        padding: EdgeInsets.fromLTRB(20, 14, 20, last ? 16 : 14),
        child: Row(children: [
          Expanded(
            flex: _flex[0],
            child: Row(children: [
              InitialsAvatar(agent.name.isEmpty ? '?' : agent.name, size: 30, accent: agent.role == 'admin'),
              const SizedBox(width: 10),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(agent.name, style: theme.textTheme.titleSmall, maxLines: 1, overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 2),
                  Text(
                    agent.role == 'admin' ? 'YÖNETİCİ' : 'EKİP ÜYESİ',
                    style: FlowText.caps(context, size: 10, color: c.faint),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ]),
              ),
            ]),
          ),
          const SizedBox(width: FlowSpace.lg),
          Expanded(
            flex: _flex[1],
            child: Row(children: [
              Expanded(child: LinearProgressIndicator(value: share.clamp(0.0, 1.0))),
              const SizedBox(width: 10),
              SizedBox(
                width: 40,
                child: Text(
                  '${agent.replies}',
                  textAlign: TextAlign.right,
                  maxLines: 1,
                  style: FlowText.mono(context, size: 14, color: c.text),
                ),
              ),
            ]),
          ),
          const SizedBox(width: FlowSpace.lg),
          number(formatDuration(agent.medianFirstResponse), _flex[2]),
          const SizedBox(width: FlowSpace.lg),
          number('${agent.resolved}', _flex[3]),
          const SizedBox(width: FlowSpace.lg),
          number('${agent.openAssigned}', _flex[4]),
        ]),
      ),
    );
  }
}
