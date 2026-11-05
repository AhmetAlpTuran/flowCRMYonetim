import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../../billing/plan_limit.dart';

/// Turkish guidance for onboarding RPC failures. Raw provider text is never shown.
String onboardingErrorMessage(Object error) {
  if (planLimitKind(error) == 'seats') {
    return 'İşletmenin kullanıcı sınırı dolu. Yönetici, Abonelik ekranından planı yükseltebilir.';
  }
  if (error is PostgrestException) {
    switch (error.code) {
      case 'P0013':
        return 'Devam etmeden önce e-posta adresinizi doğrulayın.';
      case 'P0010':
        return 'Sınıra ulaşıldı. Mevcut kayıtları kontrol edin veya destekle iletişime geçin.';
      case 'P0011':
        return 'Bu kişi zaten işletmenin üyesi.';
      case 'P0012':
        return 'Bu davet artık geçerli değil.';
      case 'P0002':
        return 'Davet bulunamadı. Listeyi yenileyin.';
      case '42501':
        return 'Bu işlem için yetkiniz yok.';
      case '22023':
        return 'Girilen bilgileri kontrol edin.';
    }
  }
  if (error is TimeoutException) {
    return 'Sunucu yanıt vermedi. Bağlantınızı kontrol edip tekrar deneyin.';
  }
  return 'İşlem tamamlanamadı. Tekrar deneyin.';
}
