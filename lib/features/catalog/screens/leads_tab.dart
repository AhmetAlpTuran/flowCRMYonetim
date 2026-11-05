import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../ui/ui.dart' hide formatPrice;
import '../../tenancy/providers/tenant_providers.dart';
import '../data/catalog_repository.dart';
import '../models/catalog_models.dart';
import '../providers/catalog_providers.dart';
import '../widgets/catalog_layout.dart';

/// Short kind names for badges and filters.
const leadKindShortLabels = {
  'inquiry': 'Bilgi',
  'test_drive': 'Test sürüşü',
  'trade_in': 'Takas',
  'financing': 'Kredi',
  'booking_request': 'Rezervasyon',
  'other': 'Diğer',
};

String _kindLabel(String kind) => leadKindShortLabels[kind] ?? leadKindLabels[kind] ?? kind;

/// Müşteriler → Talepler: what customers asked for, as a board by stage.
class LeadsTab extends ConsumerStatefulWidget {
  const LeadsTab({super.key});

  @override
  ConsumerState<LeadsTab> createState() => _LeadsTabState();
}

class _LeadsTabState extends ConsumerState<LeadsTab> {
  String? _kind;

  @override
  Widget build(BuildContext context) {
    final leads = ref.watch(leadsProvider);
    final narrow = MediaQuery.sizeOf(context).width < 600;
    final slivers = leads.when(
      loading: () => [sliverBox(const LoadingList())],
      error: (_, __) => [
        sliverBox(ErrorState(
          title: 'Talepler yüklenemedi',
          onRetry: () => ref.invalidate(leadsProvider),
        )),
      ],
      data: (items) {
        if (items.isEmpty) {
          return [
            sliverBox(const EmptyState(
              icon: Icons.assignment_outlined,
              title: 'Henüz talep yok',
              message: 'Asistan sohbetlerde aldığı test sürüşü, rezervasyon ve bilgi taleplerini buraya kaydeder.',
            )),
          ];
        }
        final kinds = <String, int>{};
        for (final lead in items) {
          kinds[lead.kind] = (kinds[lead.kind] ?? 0) + 1;
        }
        final kind = kinds.containsKey(_kind) ? _kind : null;
        final visible = [for (final lead in items) if (kind == null || lead.kind == kind) lead];
        final fresh = items.where((lead) => lead.status == 'new').length;
        return [
          sliverBox(Text(
            upperTr('${formatCount(items.length)} talep · ${formatCount(fresh)} yeni'),
            style: FlowText.caps(context, size: 12),
          )),
          if (kinds.length > 1) ...[
            sliverGap(FlowSpace.md),
            sliverBox(FilterChipsRow<String?>(
              scrollable: narrow,
              options: [
                FilterOption(null, 'Tümü', count: items.length),
                for (final entry in kinds.entries) FilterOption(entry.key, _kindLabel(entry.key), count: entry.value),
              ],
              selected: kind,
              onSelected: (value) => setState(() => _kind = value),
            )),
          ],
          sliverGap(FlowSpace.lg + 2),
          sliverBox(_LeadBoard(leads: visible)),
        ];
      },
    );
    return CatalogScrollPage(onRefresh: () => ref.refresh(leadsProvider.future), slivers: slivers);
  }
}

/// One column per stage: side by side on wide screens, stacked on phones.
class _LeadBoard extends StatelessWidget {
  const _LeadBoard({required this.leads});

  final List<Lead> leads;

  @override
  Widget build(BuildContext context) {
    final columns = [
      for (final entry in leadStatusLabels.entries)
        _LeadColumn(
          status: entry.key,
          title: entry.value,
          leads: [for (final lead in leads) if (lead.status == entry.key) lead],
        ),
    ];
    final other = [for (final lead in leads) if (!leadStatusLabels.containsKey(lead.status)) lead];
    if (other.isNotEmpty) columns.add(_LeadColumn(status: 'other', title: 'Diğer', leads: other));
    return LayoutBuilder(builder: (context, constraints) {
      if (constraints.maxWidth >= 880) {
        return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          for (var i = 0; i < columns.length; i++) ...[
            if (i > 0) const SizedBox(width: FlowSpace.md),
            Expanded(child: columns[i]),
          ],
        ]);
      }
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        for (var i = 0; i < columns.length; i++) ...[
          if (i > 0) const SizedBox(height: FlowSpace.md),
          columns[i],
        ],
      ]);
    });
  }
}

class _LeadColumn extends StatelessWidget {
  const _LeadColumn({required this.status, required this.title, required this.leads});

  final String status;
  final String title;
  final List<Lead> leads;

  @override
  Widget build(BuildContext context) {
    final c = FlowColors.of(context);
    final theme = Theme.of(context);
    return Semantics(
      container: true,
      label: '$title, ${leads.length} talep',
      child: Container(
        padding: const EdgeInsets.all(FlowSpace.md),
        decoration: BoxDecoration(
          color: c.surface,
          borderRadius: FlowRadius.cardAll,
          border: Border.all(color: c.border),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 4, 4, 10),
            child: Row(children: [
              _StageMark(status: status),
              const SizedBox(width: FlowSpace.sm),
              Flexible(
                child: Semantics(
                  header: true,
                  child: Text(title, style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                ),
              ),
              const SizedBox(width: FlowSpace.sm),
              Text(formatCount(leads.length), style: FlowText.mono(context, size: 12)),
            ]),
          ),
          if (leads.isEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 0, 4, 6),
              child: Text('Bu aşamada talep yok.', style: theme.textTheme.bodySmall?.copyWith(color: c.faint)),
            )
          else
            for (var i = 0; i < leads.length; i++) ...[
              if (i > 0) const SizedBox(height: FlowSpace.sm),
              _LeadCard(key: ValueKey(leads[i].id), lead: leads[i]),
            ],
        ]),
      ),
    );
  }
}

/// The stage marker: lime dot for new, amber for in progress, a check when won.
class _StageMark extends StatelessWidget {
  const _StageMark({required this.status});

  final String status;

  @override
  Widget build(BuildContext context) {
    final c = FlowColors.of(context);
    Widget dot(Color color, {Color? edge}) => Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
            border: edge == null ? null : Border.all(color: edge),
          ),
        );
    return ExcludeSemantics(
      child: SizedBox.square(
        dimension: 14,
        child: Center(
          child: switch (status) {
            'new' => dot(c.lime, edge: c.isDark ? null : c.limeEdge),
            'contacted' => dot(c.warning),
            'won' => Icon(Icons.check_rounded, size: 14, color: c.accentText),
            'lost' => Icon(Icons.close_rounded, size: 14, color: c.faint),
            _ => dot(c.faint),
          },
        ),
      ),
    );
  }
}

class _LeadCard extends ConsumerStatefulWidget {
  const _LeadCard({super.key, required this.lead});

  final Lead lead;

  @override
  ConsumerState<_LeadCard> createState() => _LeadCardState();
}

class _LeadCardState extends ConsumerState<_LeadCard> {
  bool _busy = false;

  Future<void> _move(String status) async {
    final tenant = ref.read(selectedTenantProvider);
    if (tenant == null || status == widget.lead.status) return;
    setState(() => _busy = true);
    String? failure;
    try {
      await ref.read(catalogRepositoryProvider).setLeadStatus(tenant.id, widget.lead.id, status);
    } catch (error) {
      failure = catalogErrorMessage(error);
    }
    if (!mounted) return;
    if (failure != null) showAppSnack(context, failure, error: true);
    setState(() => _busy = false);
    ref.invalidate(leadsProvider);
  }

  @override
  Widget build(BuildContext context) {
    final lead = widget.lead;
    final c = FlowColors.of(context);
    final theme = Theme.of(context);
    final source = sourceBadge(lead.source);
    final note = lead.details['note'];
    final name = lead.customerName?.trim() ?? '';
    return Container(
      padding: const EdgeInsets.fromLTRB(FlowSpace.md, 4, 4, FlowSpace.md),
      decoration: BoxDecoration(
        color: c.canvas,
        borderRadius: FlowRadius.controlAll,
        border: Border.all(color: c.border),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Expanded(
            child: Wrap(spacing: 6, runSpacing: 6, children: [
              StatusBadge(_kindLabel(lead.kind)),
              if (source != null) source,
            ]),
          ),
          _busy
              ? const SizedBox.square(dimension: 44, child: Center(child: CatalogSpinner()))
              : PopupMenuButton<String>(
                  tooltip: 'Durumu değiştir',
                  icon: const Icon(Icons.more_horiz, size: 20),
                  onSelected: _move,
                  itemBuilder: (_) => [
                    for (final entry in leadStatusLabels.entries)
                      if (entry.key != lead.status)
                        PopupMenuItem(value: entry.key, child: Text('${entry.value} olarak işaretle')),
                  ],
                ),
        ]),
        Padding(
          padding: const EdgeInsets.only(right: FlowSpace.sm),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(crossAxisAlignment: CrossAxisAlignment.baseline, textBaseline: TextBaseline.alphabetic, children: [
              Expanded(
                child: Text(
                  name.isEmpty ? 'İsimsiz müşteri' : name,
                  style: theme.textTheme.titleSmall?.copyWith(fontSize: 15),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: FlowSpace.sm),
              Text(upperTr(formatAgo(lead.createdAt)), style: FlowText.mono(context, size: 11, color: c.faint)),
            ]),
            if (lead.customerPhone != null)
              Text(formatPhone(lead.customerPhone!), style: FlowText.mono(context, size: 12)),
            if (lead.resourceName != null) ...[
              const SizedBox(height: 4),
              Text(lead.resourceName!, style: theme.textTheme.bodyMedium?.copyWith(color: c.muted)),
            ],
            if (lead.preferredAt != null) ...[
              const SizedBox(height: 6),
              Row(children: [
                Icon(Icons.schedule, size: 14, color: c.muted),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    upperTr(plannedAt(lead.preferredAt!)),
                    style: FlowText.mono(context, size: 12, color: c.text),
                  ),
                ),
              ]),
            ],
            if (note is String && note.trim().isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(note, style: theme.textTheme.bodySmall, maxLines: 3, overflow: TextOverflow.ellipsis),
            ],
          ]),
        ),
      ]),
    );
  }
}
