import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wpapp/features/account/data/account_repository.dart';
import 'package:wpapp/features/account/screens/account_deletion_screen.dart';
import 'package:wpapp/features/onboarding/models/pending_invite.dart';
import 'package:wpapp/features/onboarding/providers/onboarding_providers.dart';
import 'package:wpapp/features/tenancy/models/tenant_directory.dart';
import 'package:wpapp/features/tenancy/providers/tenant_providers.dart';
import 'package:wpapp/features/tenancy/screens/app_entry.dart';
import 'package:wpapp/features/tenancy/screens/landing_screen.dart';
import 'package:wpapp/features/tenancy/screens/login_screen.dart';
import 'package:wpapp/features/tenancy/screens/password_reset_screen.dart';
import 'package:wpapp/features/users/models/tenant_join_request.dart';
import 'package:wpapp/features/users/providers/tenant_admin_providers.dart';
import 'package:supabase_flutter/supabase_flutter.dart' hide AuthState;
import 'package:wpapp/ui/ui.dart';

class SignedOut extends AuthController {
  @override
  FutureOr<AuthState?> build() => null;
}

class SignedIn extends AuthController {
  @override
  FutureOr<AuthState?> build() => const AuthState(userId: 'user-1', email: 'yeni@example.invalid');
}

class FakeAccountRepository extends AccountRepository {
  FakeAccountRepository()
      : super(SupabaseClient('https://example.invalid', 'fixture',
            authOptions: const AuthClientOptions(autoRefreshToken: false)));

  @override
  Future<AccountDeletionPlan> deletionPlan() async =>
      const AccountDeletionPlan(blocked: [], deleteTenantIds: ['t-1'], leaveTenantIds: []);
}

final invite = PendingInvite(
  id: 'invite-1',
  tenantId: 'tenant-a',
  tenantName: 'Yıldız Oto Galeri',
  brandColor: null,
  role: 'admin',
  expiresAt: DateTime(2026, 11, 19, 12),
);

final joinRequest = TenantJoinRequest(
  id: 'request-1',
  tenantId: 'tenant-b',
  email: 'yeni@example.invalid',
  status: 'pending',
  createdAt: DateTime(2026, 11, 1),
  tenantName: 'Ortak Galeri',
);

/// Signed in with no memberships: the onboarding screen inside [AppEntry].
List<Override> noBusinessOverrides({bool failTenants = false}) => [
      authControllerProvider.overrideWith(SignedIn.new),
      accessibleTenantsProvider.overrideWith((ref) async {
        if (failTenants) throw StateError('offline');
        return const [];
      }),
      publicTenantsProvider.overrideWith((ref) async => const [
            TenantDirectoryEntry(id: 'tenant-b', name: 'Ortak Galeri', brandColor: Color(0xFF1F4B99)),
          ]),
      myJoinRequestsProvider.overrideWith((ref) async => [joinRequest]),
      myInvitesProvider.overrideWith((ref) async => [invite]),
    ];

Future<void> pumpAt(
  WidgetTester tester,
  Size size,
  ThemeData theme,
  Widget home, {
  List<Override> overrides = const [],
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(ProviderScope(
    overrides: [authControllerProvider.overrideWith(SignedOut.new), ...overrides],
    child: MaterialApp(theme: theme, home: home),
  ));
  await tester.pumpAndSettle();
}

const phone = Size(320, 568);
const desktop = Size(1280, 800);

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  final themes = {'dark': FlowTheme.dark, 'light': FlowTheme.light};

  for (final theme in themes.entries) {
    for (final size in [phone, desktop]) {
      final label = '${theme.key}, ${size.width.toInt()} px';

      testWidgets('sign-in renders without overflow ($label)', (tester) async {
        await pumpAt(tester, size, theme.value(), const LoginScreen());
        expect(find.widgetWithText(FilledButton, 'Giriş yap'), findsOneWidget);
        expect(find.text('Tekrar hoş geldiniz.'), size == desktop ? findsOneWidget : findsNothing);
        expect(tester.takeException(), isNull);
        await tester.ensureVisible(find.text('İşletmenizi oluşturun · 14 gün ücretsiz'));
        await tester.tap(find.text('İşletmenizi oluşturun · 14 gün ücretsiz'));
        await tester.pumpAndSettle();
        expect(find.widgetWithText(FilledButton, 'Kayıt ol'), findsOneWidget);
        expect(tester.takeException(), isNull);
      });

      testWidgets('password reset renders without overflow ($label)', (tester) async {
        await pumpAt(tester, size, theme.value(), const PasswordResetScreen(initialEmail: 'a@example.invalid'));
        expect(find.text('Şifrenizi sıfırlayın'), findsOneWidget);
        expect(tester.takeException(), isNull);
      });

      testWidgets('app welcome renders every step without overflow ($label)', (tester) async {
        await pumpAt(tester, size, theme.value(), const LandingScreen(web: false));
        expect(find.textContaining('uyumuyor'), findsOneWidget);
        for (var step = 0; step < 2; step++) {
          await tester.ensureVisible(find.text('İleri'));
          await tester.tap(find.text('İleri'));
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
        }
        expect(find.text('Talepler kendiliğinden kayda girer.'), findsOneWidget);
        expect(find.text('İşletmeni oluştur'), findsOneWidget);
        expect(find.text('Atla'), findsNothing);
      });

      testWidgets('no-business screen renders without overflow ($label)', (tester) async {
        await pumpAt(tester, size, theme.value(), const AppEntry(), overrides: noBusinessOverrides());
        expect(find.text('Bir işletmeyle başlayın.'), findsOneWidget);
        expect(find.text('Yıldız Oto Galeri'), findsOneWidget);
        expect(find.text('Katıl'), findsOneWidget);
        expect(find.text('İşletmeyi oluştur'), findsOneWidget);
        expect(find.text('Katılma isteklerim'), findsOneWidget);
        expect(find.byType(FilledButton), findsOneWidget);
        expect(tester.takeException(), isNull);
      });

      testWidgets('account deletion renders without overflow ($label)', (tester) async {
        await pumpAt(tester, size, theme.value(), const AccountDeletionScreen(), overrides: [
          authControllerProvider.overrideWith(SignedIn.new),
          accessibleTenantsProvider.overrideWith((ref) async => const []),
          accountRepositoryProvider.overrideWithValue(FakeAccountRepository()),
        ]);
        expect(find.text('Hesabımı kalıcı olarak sil'), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }

    for (final size in [const Size(320, 640), const Size(1024, 700), const Size(1440, 900)]) {
      final roomy = size.width >= 1024;
      testWidgets('web landing renders (${theme.key}, ${size.width.toInt()}×${size.height.toInt()})',
          (tester) async {
        await pumpAt(tester, size, theme.value(), const LandingScreen(web: true));
        expect(find.text('Tüm WhatsApp’ınız tek bir komuta merkezinde.'), findsOneWidget);
        expect(find.text('14 gün ücretsiz dene'), findsOneWidget);
        expect(tester.takeException(), isNull);
        if (roomy) {
          // One screen of cards: nothing needs to scroll.
          expect(find.byType(Scrollable), findsNothing);
          expect(find.text('Planları gör'), findsOneWidget);
          expect(find.text('Paketleri gör'), findsOneWidget);
          expect(find.text('Ortak gelen kutusu'), findsOneWidget);
        } else {
          expect(find.text('Fiyatlar'), findsOneWidget);
          expect(find.text('Güvenlik ve KVKK'), findsOneWidget);
        }
      });
    }
  }

  testWidgets('sign-in stays usable with the keyboard open on a small phone', (tester) async {
    tester.view.viewInsets = const FakeViewPadding(bottom: 300);
    addTearDown(tester.view.resetViewInsets);
    await pumpAt(tester, phone, FlowTheme.dark(), const LoginScreen());
    await tester.ensureVisible(find.byType(TextFormField).first);
    await tester.tap(find.byType(TextFormField).first);
    await tester.pump();
    await tester.ensureVisible(find.widgetWithText(FilledButton, 'Giriş yap'));
    await tester.tap(find.widgetWithText(FilledButton, 'Giriş yap'));
    await tester.pumpAndSettle();
    expect(find.text('E-posta adresinizi girin.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the welcome leads to sign-up on the last step and sign-in from any step', (tester) async {
    await pumpAt(tester, phone, FlowTheme.dark(), const LandingScreen(web: false));
    await tester.ensureVisible(find.text('Zaten hesabım var · Giriş yap'));
    await tester.tap(find.text('Zaten hesabım var · Giriş yap'));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(FilledButton, 'Giriş yap'), findsOneWidget);
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();

    for (var step = 0; step < 2; step++) {
      await tester.ensureVisible(find.text('İleri'));
      await tester.tap(find.text('İleri'));
      await tester.pumpAndSettle();
    }
    await tester.ensureVisible(find.text('İşletmeni oluştur'));
    await tester.tap(find.text('İşletmeni oluştur'));
    await tester.pumpAndSettle();
    expect(find.text('Hesap oluşturun'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Kayıt ol'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the Fiyatlar card opens the pricing panel with monthly and yearly prices', (tester) async {
    await pumpAt(tester, const Size(1440, 900), FlowTheme.dark(), const LandingScreen(web: true));
    await tester.tap(find.text('Planları gör'));
    await tester.pumpAndSettle();
    expect(find.text('Sade fiyat, sürpriz yok.'), findsOneWidget);
    expect(find.text('Profesyonel'), findsOneWidget);
    expect(find.text('3.490'), findsOneWidget);
    expect(find.text('Kapat'), findsOneWidget);

    await tester.tap(find.text('Yıllık · 2 ay bizden'));
    await tester.pumpAndSettle();
    expect(find.text('34.900'), findsOneWidget);
    expect(find.text('3.490'), findsNothing);

    await tester.tap(find.text('Kapat'));
    await tester.pumpAndSettle();
    expect(find.text('Sade fiyat, sürpriz yok.'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('on a phone the pricing tile opens a bottom sheet whose CTA leads to sign-up', (tester) async {
    await pumpAt(tester, const Size(320, 640), FlowTheme.light(), const LandingScreen(web: true));
    await tester.ensureVisible(find.text('Fiyatlar'));
    await tester.tap(find.text('Fiyatlar'));
    await tester.pumpAndSettle();
    expect(find.byType(BottomSheet), findsOneWidget);
    expect(find.text('Sade fiyat, sürpriz yok.'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.tap(find.descendant(of: find.byType(BottomSheet), matching: find.text('14 gün ücretsiz dene')));
    await tester.pumpAndSettle();
    expect(find.byType(BottomSheet), findsNothing);
    expect(find.text('Hesap oluşturun'), findsOneWidget);
  });

  testWidgets('a failed business list offers a retry, not onboarding', (tester) async {
    await pumpAt(tester, phone, FlowTheme.dark(), const AppEntry(),
        overrides: noBusinessOverrides(failTenants: true));
    expect(find.text('İşletmeler yüklenemedi'), findsOneWidget);
    expect(find.text('Tekrar dene'), findsOneWidget);
    expect(find.text('İşletmeyi oluştur'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('declining an invite asks first', (tester) async {
    await pumpAt(tester, phone, FlowTheme.dark(), const AppEntry(), overrides: noBusinessOverrides());
    await tester.ensureVisible(find.text('Reddet'));
    await tester.tap(find.text('Reddet'));
    await tester.pumpAndSettle();
    expect(find.text('Davet reddedilsin mi?'), findsOneWidget);
    await tester.tap(find.text('Vazgeç'));
    await tester.pumpAndSettle();
    expect(find.text('Yıldız Oto Galeri'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
