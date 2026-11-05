import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../ui/ui.dart';
import 'onboarding_parts.dart';

/// The frame of the sign-in, sign-up and password screens. Wide screens show a dot-grid
/// panel with the signal rings and a headline beside the form; phones show the logo
/// above the form. The form column owns its scroll area, so every field stays
/// reachable with the keyboard open and at short heights.
class AuthFrame extends StatelessWidget {
  const AuthFrame({
    super.key,
    required this.heroTitle,
    required this.heroLine,
    this.heroEyebrow,
    required this.child,
  });

  /// From this width the hero panel sits beside the form.
  static const double splitBreakpoint = 900;

  final String heroTitle;
  final String heroLine;
  final String? heroEyebrow;

  /// The form, at most 400 px wide.
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final canPop = ModalRoute.of(context)?.canPop ?? false;
    return Scaffold(
      body: LayoutBuilder(builder: (context, constraints) {
        final wide = constraints.maxWidth >= splitBreakpoint;
        final form = _FormColumn(showLogo: !wide, canPop: canPop, child: child);
        if (!wide) return SafeArea(child: form);
        return Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Expanded(
            flex: 11,
            child: _HeroPanel(eyebrow: heroEyebrow, title: heroTitle, line: heroLine),
          ),
          Expanded(flex: 9, child: SafeArea(left: false, child: form)),
        ]);
      }),
    );
  }
}

class _FormColumn extends StatelessWidget {
  const _FormColumn({required this.showLogo, required this.canPop, required this.child});

  final bool showLogo;
  final bool canPop;
  final Widget child;

  static const _top = FlowSpace.md;
  static const _bottom = FlowSpace.xl;
  static const _barHeight = 48.0;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) {
      final gutter = constraints.maxWidth < 600 ? FlowSpace.lg : FlowSpace.xl;
      return SingleChildScrollView(
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        padding: EdgeInsets.fromLTRB(gutter, _top, gutter, _bottom),
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: math.max(0, constraints.maxHeight - _top - _bottom)),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                height: _barHeight,
                child: Row(children: [
                  if (canPop) const BackButton(),
                  if (showLogo) ...[
                    if (canPop) const SizedBox(width: FlowSpace.xs),
                    const FlowLogo(size: 26),
                  ],
                ]),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(vertical: FlowSpace.xl),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 400),
                    child: child,
                  ),
                ),
              ),
              // Balances the top bar so the form sits in the middle of tall screens.
              const SizedBox(height: _barHeight),
            ],
          ),
        ),
      );
    });
  }
}

class _HeroPanel extends StatelessWidget {
  const _HeroPanel({required this.eyebrow, required this.title, required this.line});

  final String? eyebrow;
  final String title;
  final String line;

  @override
  Widget build(BuildContext context) {
    final c = FlowColors.of(context);
    final theme = Theme.of(context);
    const padding = EdgeInsets.fromLTRB(56, 40, 56, 40);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: c.canvas,
        border: Border(right: BorderSide(color: c.border)),
      ),
      child: ClipRect(
        child: DotGrid(
          child: Stack(children: [
            const Positioned(left: -260, bottom: -380, child: SignalRings(size: 900)),
            Positioned.fill(
              child: SafeArea(
                right: false,
                child: LayoutBuilder(
                  builder: (context, constraints) => SingleChildScrollView(
                    padding: padding,
                    child: ConstrainedBox(
                      constraints: BoxConstraints(
                        minHeight: math.max(0, constraints.maxHeight - padding.vertical),
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const FlowLogo(size: 30),
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 48),
                            child: EntranceRise(
                              child: ConstrainedBox(
                                constraints: const BoxConstraints(maxWidth: 520),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Semantics(
                                      header: true,
                                      child: Text(title, style: theme.textTheme.displayLarge),
                                    ),
                                    const SizedBox(height: FlowSpace.xxl),
                                    Container(
                                      width: double.infinity,
                                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
                                      decoration: BoxDecoration(
                                        color: c.surface,
                                        borderRadius: FlowRadius.cardAll,
                                        border: Border.all(color: c.border),
                                      ),
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          if (eyebrow != null) ...[
                                            Eyebrow(eyebrow!),
                                            const SizedBox(height: 10),
                                          ],
                                          Text(
                                            line,
                                            style: theme.textTheme.bodyLarge?.copyWith(fontSize: 18, height: 1.45),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                          Text(
                            '© ${DateTime.now().year} FLOW CRM',
                            style: FlowText.caps(context, color: c.faint),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ]),
        ),
      ),
    );
  }
}

/// "—— YA DA ——" between the primary action and the alternative path.
class OrDivider extends StatelessWidget {
  const OrDivider({super.key, this.label = 'ya da'});

  final String label;

  @override
  Widget build(BuildContext context) {
    final c = FlowColors.of(context);
    return Row(children: [
      Expanded(child: Divider(color: c.border)),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: FlowSpace.md),
        child: Text(upperTr(label), style: FlowText.caps(context, color: c.faint)),
      ),
      Expanded(child: Divider(color: c.border)),
    ]);
  }
}
