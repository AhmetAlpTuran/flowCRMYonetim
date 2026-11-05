import 'package:flutter/material.dart';

import '../app_typography.dart';
import '../tokens.dart';

/// A screen's scrolling body: shared gutters, a centered max width and even gaps.
/// The shell owns the page title; [toolbar] holds the screen's search and actions.
class AppPage extends StatelessWidget {
  const AppPage({
    super.key,
    required this.children,
    this.toolbar,
    this.maxWidth = 1120,
    this.gap = FlowSpace.lg,
    this.controller,
  });

  final List<Widget> children;
  final Widget? toolbar;
  final double maxWidth;
  final double gap;
  final ScrollController? controller;

  @override
  Widget build(BuildContext context) {
    final gutter = FlowSpace.pageGutter(MediaQuery.sizeOf(context).width);
    final items = [if (toolbar != null) toolbar!, ...children];
    return SingleChildScrollView(
      controller: controller,
      padding: EdgeInsets.fromLTRB(gutter, FlowSpace.xl, gutter, 48),
      child: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: maxWidth),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var i = 0; i < items.length; i++) ...[
                if (i > 0) SizedBox(height: gap),
                items[i],
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Search on the left, actions on the right; wraps onto two lines on phones.
class PageToolbar extends StatelessWidget {
  const PageToolbar({super.key, this.leading, this.actions = const []});

  final Widget? leading;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) {
      final narrow = constraints.maxWidth < 560;
      final actionRow = Wrap(
        spacing: FlowSpace.sm,
        runSpacing: FlowSpace.sm,
        alignment: WrapAlignment.end,
        children: actions,
      );
      if (leading == null) return Align(alignment: Alignment.centerRight, child: actionRow);
      if (narrow) {
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          leading!,
          if (actions.isNotEmpty) ...[const SizedBox(height: FlowSpace.sm), actionRow],
        ]);
      }
      return Row(children: [
        Expanded(child: Align(alignment: Alignment.centerLeft, child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: leading,
        ))),
        if (actions.isNotEmpty) ...[const SizedBox(width: FlowSpace.md), actionRow],
      ]);
    });
  }
}

/// A bordered panel with an optional header row.
class SectionCard extends StatelessWidget {
  const SectionCard({
    super.key,
    this.title,
    this.subtitle,
    this.trailing,
    required this.child,
    this.padding = const EdgeInsets.all(FlowSpace.xl - 4),
    this.flush = false,
  });

  final String? title;
  final String? subtitle;
  final Widget? trailing;
  final Widget child;
  final EdgeInsets padding;

  /// Puts [child] edge to edge under the header (lists, tables).
  final bool flush;

  @override
  Widget build(BuildContext context) {
    final c = FlowColors.of(context);
    final theme = Theme.of(context);
    final header = title == null
        ? null
        : Padding(
            padding: flush ? EdgeInsets.fromLTRB(padding.left, padding.top, padding.right, FlowSpace.md) : EdgeInsets.zero,
            child: Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(title!, style: theme.textTheme.titleLarge),
                  if (subtitle != null) ...[
                    const SizedBox(height: 4),
                    Text(subtitle!, style: theme.textTheme.bodySmall),
                  ],
                ]),
              ),
              if (trailing != null) ...[const SizedBox(width: FlowSpace.md), trailing!],
            ]),
          );
    return Container(
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: FlowRadius.cardAll,
        border: Border.all(color: c.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: flush
          ? Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              if (header != null) ...[header, Divider(height: 1, color: c.border)],
              child,
            ])
          : Padding(
              padding: padding,
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                if (header != null) ...[header, const SizedBox(height: FlowSpace.lg)],
                child,
              ]),
            ),
    );
  }
}

/// "01 — ÖZELLİKLER" style eyebrow label above a heading.
class Eyebrow extends StatelessWidget {
  const Eyebrow(this.label, {super.key, this.color});

  final String label;
  final Color? color;

  @override
  Widget build(BuildContext context) => Text(
        upperTr(label),
        style: FlowText.caps(context, size: 11, color: color ?? FlowColors.of(context).accentText),
      );
}

/// A list beside its detail on wide screens; the list alone on phones, where the
/// caller pushes the detail as a route.
class ListDetailLayout extends StatelessWidget {
  const ListDetailLayout({
    super.key,
    required this.list,
    this.detail,
    this.listWidth = 360,
    this.breakpoint = 900,
  });

  final Widget list;
  final Widget? detail;
  final double listWidth;
  final double breakpoint;

  static bool isSplit(BuildContext context, {double breakpoint = 900}) =>
      MediaQuery.sizeOf(context).width >= breakpoint;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) {
      if (constraints.maxWidth < breakpoint || detail == null) return list;
      final c = FlowColors.of(context);
      return Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        SizedBox(width: listWidth, child: list),
        VerticalDivider(width: 1, color: c.border),
        Expanded(child: detail!),
      ]);
    });
  }
}
