import 'package:flutter/material.dart';
import '../models/message.dart';

class MessageDeliveryStatus extends StatelessWidget {
  const MessageDeliveryStatus({super.key, required this.message});
  final Message message;

  @override
  Widget build(BuildContext context) => Text(
        _label,
        style: Theme.of(context).textTheme.labelSmall,
      );

  String get _label {
    switch (message.status) {
      case MessageStatus.read:
        return 'Okundu';
      case MessageStatus.delivered:
        return 'Teslim edildi';
      case MessageStatus.sent:
        return 'Gönderildi';
      case MessageStatus.failed:
        return 'Teslim edilemedi';
      case MessageStatus.unknown:
        break;
    }
    return switch (message.outboundState) {
      'queued' || 'leased' => 'Kuyrukta',
      'sending' => 'Gönderiliyor',
      'retry_wait' => 'Yeniden deneme bekliyor',
      'blocked' => 'Bağlantı bekleniyor',
      'accepted' => 'WhatsApp kabul etti',
      'failed' => message.outboundErrorCode == 'customer_service_window_closed'
          ? '24 saatlik yanıt süresi doldu'
          : 'Gönderilemedi',
      'unknown' => 'Gönderim doğrulanamadı',
      'cancelled' => 'İptal edildi',
      _ => 'Durum bilinmiyor',
    };
  }
}
