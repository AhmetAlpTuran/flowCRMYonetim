import 'dart:async';

import 'package:flutter/material.dart';

import '../../../ui/ui.dart';

/// WhatsApp allows free-form replies for 24 hours after the customer's last message;
/// after that only approved templates can be sent (enforced by the send endpoint).
typedef ServiceWindowState = ({bool open, Duration remaining, String label, String spoken});

ServiceWindowState serviceWindowOf(DateTime lastCustomerMessageAt, {DateTime? now}) {
  final remaining =
      lastCustomerMessageAt.add(const Duration(hours: 24)).difference(now ?? DateTime.now());
  if (remaining <= Duration.zero) {
    return (
      open: false,
      remaining: Duration.zero,
      label: '24 SAAT PENCERESİ KAPALI · YANIT İÇİN ONAYLI ŞABLON GEREKİR',
      spoken: '24 saatlik yanıt penceresi kapandı. Yanıt için onaylı bir şablon gerekir.',
    );
  }
  final hours = remaining.inHours;
  final minutes = remaining.inMinutes % 60;
  final (String short, String spoken) = hours > 0
      ? ('$hours SA $minutes DK', '$hours saat $minutes dakika')
      : remaining.inMinutes > 0
          ? ('${remaining.inMinutes} DK', '${remaining.inMinutes} dakika')
          : ('1 DK\'DAN AZ', '1 dakikadan az');
  return (
    open: true,
    remaining: remaining,
    label: '24 SAAT PENCERESİ AÇIK · $short',
    spoken: '24 saatlik yanıt penceresi açık, $spoken kaldı.',
  );
}

/// The mono caps window line above the composer; refreshes every half minute.
class ServiceWindowNote extends StatefulWidget {
  const ServiceWindowNote({super.key, required this.lastCustomerMessageAt});

  final DateTime lastCustomerMessageAt;

  @override
  State<ServiceWindowNote> createState() => _ServiceWindowNoteState();
}

class _ServiceWindowNoteState extends State<ServiceWindowNote> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = FlowColors.of(context);
    final window = serviceWindowOf(widget.lastCustomerMessageAt);
    final color = !window.open
        ? c.danger
        : window.remaining <= const Duration(hours: 2)
            ? c.warning
            : c.accentText;
    return Semantics(
      label: window.spoken,
      excludeSemantics: true,
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(
          width: 7,
          height: 7,
          margin: const EdgeInsets.only(top: 3, right: 8),
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        Expanded(child: Text(window.label, style: FlowText.caps(context, size: 10, color: color))),
      ]),
    );
  }
}
