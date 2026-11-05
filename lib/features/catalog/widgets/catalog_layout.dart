import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../ui/ui.dart' hide formatPrice;
import '../models/catalog_models.dart';

/// A tab body with the same gutters and max width as `AppPage`, built from slivers so
/// long catalogs only build (and download photos for) what is on screen. Pull to
/// refresh works even when the content is short.
class CatalogScrollPage extends StatelessWidget {
  const CatalogScrollPage({super.key, required this.slivers, this.onRefresh, this.maxWidth = 1120});

  final List<Widget> slivers;
  final Future<void> Function()? onRefresh;
  final double maxWidth;

  @override
  Widget build(BuildContext context) {
    final gutter = FlowSpace.pageGutter(MediaQuery.sizeOf(context).width);
    return LayoutBuilder(builder: (context, constraints) {
      final side = math.max(gutter, (constraints.maxWidth - maxWidth) / 2);
      final view = CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          SliverPadding(
            padding: EdgeInsets.fromLTRB(side, FlowSpace.xl, side, 48),
            sliver: SliverMainAxisGroup(slivers: slivers),
          ),
        ],
      );
      final refresh = onRefresh;
      return refresh == null ? view : RefreshIndicator(onRefresh: refresh, child: view);
    });
  }
}

/// A box widget as a sliver.
Widget sliverBox(Widget child) => SliverToBoxAdapter(child: child);

/// Vertical space between slivers.
Widget sliverGap([double height = FlowSpace.lg]) => SliverToBoxAdapter(child: SizedBox(height: height));

/// Opens a catalog editor as a bottom sheet that can grow to the full height.
Future<T?> showCatalogSheet<T>(BuildContext context, Widget sheet, {double maxWidth = 640}) =>
    showModalBottomSheet<T>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      constraints: BoxConstraints(maxWidth: maxWidth),
      builder: (_) => sheet,
    );

/// The frame of a catalog sheet: eyebrow, title and close button on top, a scrolling
/// body, and a footer that stays visible above the keyboard.
class CatalogSheet extends StatelessWidget {
  const CatalogSheet({
    super.key,
    this.eyebrow,
    required this.title,
    this.badge,
    this.progress,
    required this.child,
    this.actions = const [],
    this.leadingAction,
  });

  final String? eyebrow;
  final String title;

  /// Shown under the title (a status badge).
  final Widget? badge;

  /// Shown under the header (a step bar).
  final Widget? progress;
  final Widget child;

  /// Right side of the footer; the last one is usually the sheet's one primary button.
  final List<Widget> actions;

  /// Left side of the footer (back, delete).
  final Widget? leadingAction;

  @override
  Widget build(BuildContext context) {
    final c = FlowColors.of(context);
    final theme = Theme.of(context);
    final pad = MediaQuery.sizeOf(context).width < 600 ? FlowSpace.lg : FlowSpace.xl;
    final hasFooter = actions.isNotEmpty || leadingAction != null;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Padding(
          padding: EdgeInsets.fromLTRB(pad, 20, FlowSpace.sm, FlowSpace.md),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                if (eyebrow != null) ...[Eyebrow(eyebrow!), const SizedBox(height: 6)],
                Semantics(
                  header: true,
                  child: Text(title, style: theme.textTheme.headlineSmall, maxLines: 2, overflow: TextOverflow.ellipsis),
                ),
                if (badge != null) ...[const SizedBox(height: FlowSpace.sm), badge!],
              ]),
            ),
            IconButton(
              tooltip: 'Kapat',
              onPressed: () => Navigator.of(context).maybePop(),
              icon: const Icon(Icons.close),
            ),
          ]),
        ),
        if (progress != null) Padding(padding: EdgeInsets.fromLTRB(pad, 0, pad, FlowSpace.md), child: progress),
        Divider(height: 1, color: c.border),
        Flexible(
          child: SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(pad, 20, pad, 20),
            child: child,
          ),
        ),
        if (hasFooter) ...[
          Divider(height: 1, color: c.border),
          Padding(
            padding: EdgeInsets.fromLTRB(pad, FlowSpace.md, pad, FlowSpace.md + MediaQuery.paddingOf(context).bottom),
            child: Row(children: [
              if (leadingAction != null) leadingAction!,
              const SizedBox(width: FlowSpace.sm),
              Expanded(
                child: Wrap(
                  alignment: WrapAlignment.end,
                  spacing: FlowSpace.sm,
                  runSpacing: FlowSpace.sm,
                  children: actions,
                ),
              ),
            ]),
          ),
        ],
      ]),
    );
  }
}

/// An inline notice inside a form or list: an error by default.
class CatalogNotice extends StatelessWidget {
  const CatalogNotice(this.message, {super.key, this.tone = FlowTone.danger, this.icon});

  final String message;
  final FlowTone tone;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final c = FlowColors.of(context);
    final color = c.toneText(tone);
    return Semantics(
      liveRegion: tone == FlowTone.danger,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: FlowSpace.md, vertical: 10),
        decoration: BoxDecoration(
          color: tone == FlowTone.neutral ? c.raised : c.toneFill(tone),
          borderRadius: FlowRadius.controlAll,
          border: Border.all(color: color.withValues(alpha: 0.35)),
        ),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Icon(icon ?? (tone == FlowTone.danger ? Icons.error_outline : Icons.info_outline),
                size: 18, color: color),
          ),
          const SizedBox(width: 10),
          Expanded(child: Text(message, style: Theme.of(context).textTheme.bodyMedium)),
        ]),
      ),
    );
  }
}

/// A small spinner for buttons and headers while a request runs.
class CatalogSpinner extends StatelessWidget {
  const CatalogSpinner({super.key, this.size = 16});

  final double size;

  @override
  Widget build(BuildContext context) =>
      SizedBox.square(dimension: size, child: const CircularProgressIndicator(strokeWidth: 2));
}

/// The dot-grid stand-in for an item without a photo.
class CatalogPhotoPlaceholder extends StatelessWidget {
  const CatalogPhotoPlaceholder({super.key, required this.icon, this.iconSize = 32, this.message});

  final IconData icon;
  final double iconSize;
  final String? message;

  @override
  Widget build(BuildContext context) {
    final c = FlowColors.of(context);
    return ColoredBox(
      color: c.raised,
      child: DotGrid(
        child: LayoutBuilder(builder: (context, constraints) {
          // Scales down instead of overflowing in small boxes or with large text.
          return Center(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: (constraints.maxWidth - FlowSpace.lg).clamp(0, double.infinity)),
                child: Padding(
                  padding: const EdgeInsets.all(FlowSpace.sm),
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    ExcludeSemantics(child: Icon(icon, size: iconSize, color: c.faint)),
                    if (message != null) ...[
                      const SizedBox(height: FlowSpace.sm),
                      Text(message!,
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: c.muted)),
                    ],
                  ]),
                ),
              ),
            ),
          );
        }),
      ),
    );
  }
}

/// Icon for a kind of catalog item.
IconData resourceTypeIcon(ResourceType? type) => switch (type?.key) {
      'vehicle' => Icons.directions_car_outlined,
      'room' => Icons.bed_outlined,
      'service' => Icons.event_available_outlined,
      _ => type?.bookable ?? false ? Icons.event_outlined : Icons.inventory_2_outlined,
    };

/// Icon for a preset key (also the industry packs' catalog types).
IconData presetIcon(String key) => switch (key) {
      'vehicle' || 'auto_dealer' => Icons.directions_car_outlined,
      'room' || 'rental' => Icons.bed_outlined,
      'service' || 'appointments' => Icons.event_available_outlined,
      _ => Icons.inventory_2_outlined,
    };

/// Status badge tone of an item.
FlowTone resourceStatusTone(String status) => switch (status) {
      'active' => FlowTone.accent,
      'reserved' => FlowTone.warning,
      _ => FlowTone.neutral,
    };

/// Who created a booking or lead, as a badge; teal when the assistant did.
Widget? sourceBadge(String source) => switch (source) {
      'bot' => const StatusBadge('Asistandan', tone: FlowTone.assistant),
      'agent' => const StatusBadge('Ekipten', tone: FlowTone.accent),
      'import' => const StatusBadge('İçe aktarıldı'),
      _ => null,
    };

/// Lowercases with Turkish rules, for search.
String foldTr(String value) => value.replaceAll('İ', 'i').replaceAll('I', 'ı').toLowerCase();

const _monthsShort = ['Oca', 'Şub', 'Mar', 'Nis', 'May', 'Haz', 'Tem', 'Ağu', 'Eyl', 'Eki', 'Kas', 'Ara'];
const _weekdaysShort = ['Pzt', 'Sal', 'Çar', 'Per', 'Cum', 'Cmt', 'Paz'];

/// "17 Kas" in local time.
String shortDate(DateTime time) {
  final t = time.toLocal();
  return '${t.day} ${_monthsShort[t.month - 1]}';
}

/// "Kas" in local time.
String shortMonth(DateTime time) => _monthsShort[time.toLocal().month - 1];

/// "Pzt" in local time.
String shortWeekday(DateTime time) => _weekdaysShort[time.toLocal().weekday - 1];

/// Whole days from [now] to [time], in local calendar days (0 today, 1 tomorrow).
int dayOffset(DateTime time, {DateTime? now}) {
  final t = time.toLocal();
  final n = (now ?? DateTime.now()).toLocal();
  return (DateTime(t.year, t.month, t.day).difference(DateTime(n.year, n.month, n.day)).inHours / 24).round();
}

/// A planned time: "Bugün · 14:00", "Yarın · 09:30", "21 Kasım · 11:00".
String plannedAt(DateTime time, {DateTime? now}) {
  final offset = dayOffset(time, now: now);
  final day = switch (offset) {
    0 => 'Bugün',
    1 => 'Yarın',
    -1 => 'Dün',
    _ => (now ?? DateTime.now()).year == time.toLocal().year ? formatDayMonth(time) : formatDate(time),
  };
  return '$day · ${formatClock(time)}';
}
