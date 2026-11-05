import 'package:flutter/material.dart';

import '../tokens.dart';

/// Asks before an irreversible action. Returns true only on an explicit confirm.
Future<bool> confirmAction(
  BuildContext context, {
  required String title,
  String? message,
  required String confirmLabel,
  String cancelLabel = 'Vazgeç',
  bool destructive = false,
}) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (context) {
      final c = FlowColors.of(context);
      return AlertDialog(
        title: Text(title),
        content: message == null ? null : Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            style: TextButton.styleFrom(foregroundColor: c.muted),
            child: Text(cancelLabel),
          ),
          destructive
              ? OutlinedButton(
                  onPressed: () => Navigator.of(context).pop(true),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: c.danger,
                    side: BorderSide(color: c.danger),
                  ),
                  child: Text(confirmLabel),
                )
              : FilledButton(onPressed: () => Navigator.of(context).pop(true), child: Text(confirmLabel)),
        ],
      );
    },
  );
  return result == true;
}

/// One short confirmation or error message at the bottom of the screen.
void showAppSnack(BuildContext context, String message, {bool error = false}) {
  final messenger = ScaffoldMessenger.maybeOf(context);
  if (messenger == null) return;
  final c = FlowColors.of(context);
  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(
      content: Row(children: [
        Icon(error ? Icons.error_outline : Icons.check_circle_outline,
            size: 18, color: error ? c.danger : c.lime),
        const SizedBox(width: 10),
        Expanded(child: Text(message)),
      ]),
    ));
}
