import 'package:flutter/material.dart';

import '../tokens.dart';
import 'motifs.dart';

/// An empty list that invites the next action: rings on a dot grid, one line, one button.
class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.title,
    this.message,
    this.action,
    this.icon,
    this.compact = false,
  });

  final String title;
  final String? message;

  /// Usually one [FilledButton].
  final Widget? action;

  /// Shown inside the rings; defaults to the lime center dot.
  final IconData? icon;

  /// Smaller padding, for empty sections inside a card.
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final c = FlowColors.of(context);
    final theme = Theme.of(context);
    final ringSize = compact ? 56.0 : 72.0;
    return Container(
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: FlowRadius.cardAll,
        border: Border.all(color: c.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: DotGrid(
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: FlowSpace.xl, vertical: compact ? FlowSpace.xl : 40),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            SizedBox.square(
              dimension: ringSize,
              child: Stack(alignment: Alignment.center, children: [
                SignalRings(size: ringSize, rings: 3, dot: icon == null),
                if (icon != null) Icon(icon, color: c.accentText, size: ringSize * 0.34),
              ]),
            ),
            const SizedBox(height: FlowSpace.lg),
            Text(title, style: theme.textTheme.titleLarge, textAlign: TextAlign.center),
            if (message != null) ...[
              const SizedBox(height: 6),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 360),
                child: Text(message!, style: theme.textTheme.bodyMedium?.copyWith(color: c.muted),
                    textAlign: TextAlign.center),
              ),
            ],
            if (action != null) ...[const SizedBox(height: FlowSpace.lg), action!],
          ]),
        ),
      ),
    );
  }
}

/// A failed load with a plain Turkish explanation and a retry button. Never show raw
/// backend errors here; map them with the feature's `*ErrorMessage` helper first.
class ErrorState extends StatelessWidget {
  const ErrorState({
    super.key,
    this.title = 'Yüklenemedi',
    this.message = 'Bağlantınızı kontrol edip tekrar deneyin.',
    this.onRetry,
  });

  final String title;
  final String message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final c = FlowColors.of(context);
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: FlowSpace.xl, vertical: 36),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: FlowRadius.cardAll,
        border: Border.all(color: c.border),
      ),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Container(
          width: 52,
          height: 52,
          decoration: BoxDecoration(color: c.dangerSoft, borderRadius: BorderRadius.circular(15)),
          child: Icon(Icons.error_outline, color: c.danger, size: 26),
        ),
        const SizedBox(height: FlowSpace.lg),
        Text(title, style: theme.textTheme.titleLarge, textAlign: TextAlign.center),
        const SizedBox(height: 6),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 360),
          child: Text(message, style: theme.textTheme.bodyMedium?.copyWith(color: c.muted),
              textAlign: TextAlign.center),
        ),
        if (onRetry != null) ...[
          const SizedBox(height: FlowSpace.lg),
          OutlinedButton.icon(onPressed: onRetry, icon: const Icon(Icons.refresh, size: 18), label: const Text('Tekrar dene')),
        ],
      ]),
    );
  }
}

/// Placeholder rows while a list loads.
class LoadingList extends StatelessWidget {
  const LoadingList({super.key, this.rows = 4});

  final int rows;

  @override
  Widget build(BuildContext context) {
    final c = FlowColors.of(context);
    Widget bar(double widthFactor, double height) => FractionallySizedBox(
          alignment: Alignment.centerLeft,
          widthFactor: widthFactor,
          child: Container(
            height: height,
            decoration: BoxDecoration(color: c.raised, borderRadius: BorderRadius.circular(6)),
          ),
        );
    return Semantics(
      label: 'Yükleniyor',
      child: ExcludeSemantics(
        child: Column(children: [
          for (var i = 0; i < rows; i++)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: Row(children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(color: c.raised, borderRadius: BorderRadius.circular(11)),
                ),
                const SizedBox(width: FlowSpace.md),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    bar(i.isEven ? 0.55 : 0.4, 12),
                    const SizedBox(height: 8),
                    bar(i.isEven ? 0.85 : 0.7, 10),
                  ]),
                ),
              ]),
            ),
        ]),
      ),
    );
  }
}
