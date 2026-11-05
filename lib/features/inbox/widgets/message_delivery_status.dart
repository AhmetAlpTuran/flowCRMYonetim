import 'package:flutter/material.dart';

import '../../../ui/ui.dart';
import '../models/message.dart';

/// One delivery state of an outgoing message. Queue, provider acceptance, delivery,
/// read and uncertainty stay distinct: acceptance or an unknown result never reads
/// as delivered.
typedef DeliveryStatusInfo = ({String label, String detail, FlowTone tone});

DeliveryStatusInfo deliveryStatusOf(Message message) {
  switch (message.status) {
    case MessageStatus.read:
      return (label: 'Okundu', detail: 'Müşteri mesajı okudu.', tone: FlowTone.accent);
    case MessageStatus.delivered:
      return (label: 'İletildi', detail: 'Mesaj müşterinin telefonuna ulaştı.', tone: FlowTone.neutral);
    case MessageStatus.sent:
      return (label: 'Gönderildi', detail: 'WhatsApp mesajı gönderdi; teslim bilgisi bekleniyor.', tone: FlowTone.neutral);
    case MessageStatus.failed:
      return (label: 'İletilemedi', detail: 'WhatsApp mesajı müşteriye iletemedi.', tone: FlowTone.danger);
    case MessageStatus.unknown:
      break;
  }
  return switch (message.outboundState) {
    'queued' || 'leased' => (label: 'Sırada', detail: 'Gönderim sırasında bekliyor.', tone: FlowTone.neutral),
    'sending' => (label: 'Gönderiliyor', detail: 'WhatsApp\'a gönderiliyor.', tone: FlowTone.neutral),
    'retry_wait' => (label: 'Yeniden denenecek', detail: 'Gönderim kısa süre sonra yeniden denenecek.', tone: FlowTone.warning),
    'blocked' => (label: 'Bağlantı bekleniyor', detail: 'WhatsApp bağlantısı düzelince gönderilecek.', tone: FlowTone.warning),
    'accepted' => (label: 'WhatsApp kabul etti', detail: 'WhatsApp mesajı aldı; teslim bilgisi bekleniyor.', tone: FlowTone.neutral),
    'failed' => message.outboundErrorCode == 'customer_service_window_closed'
        ? (label: '24 saat doldu', detail: '24 saatlik yanıt süresi dolduğu için gönderilemedi. Onaylı bir şablon kullanın.', tone: FlowTone.danger)
        : (label: 'Gönderilemedi', detail: 'Mesaj gönderilemedi.', tone: FlowTone.danger),
    'unknown' => (label: 'Belirsiz', detail: 'Gönderim sonucu doğrulanamadı; mesaj ulaşmış olabilir.', tone: FlowTone.warning),
    'cancelled' => (label: 'İptal edildi', detail: 'Gönderim iptal edildi.', tone: FlowTone.neutral),
    _ => (label: 'Durum bilinmiyor', detail: 'Gönderim durumu bilinmiyor.', tone: FlowTone.neutral),
  };
}

/// The delivery state under an outgoing bubble, in mono caps ("SIRADA", "OKUNDU").
class MessageDeliveryStatus extends StatelessWidget {
  const MessageDeliveryStatus({super.key, required this.message});
  final Message message;

  @override
  Widget build(BuildContext context) {
    final c = FlowColors.of(context);
    final info = deliveryStatusOf(message);
    final color = info.tone == FlowTone.neutral ? c.faint : c.toneText(info.tone);
    return Tooltip(
      message: info.detail,
      excludeFromSemantics: true,
      child: Semantics(
        label: '${info.label}. ${info.detail}',
        excludeSemantics: true,
        child: Text(upperTr(info.label), style: FlowText.caps(context, size: 10, color: color)),
      ),
    );
  }
}
