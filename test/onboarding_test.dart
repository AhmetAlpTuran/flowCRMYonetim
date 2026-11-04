import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart' hide AuthState;
import 'package:wpapp/features/onboarding/data/onboarding_errors.dart';
import 'package:wpapp/features/onboarding/data/onboarding_repository.dart';
import 'package:wpapp/features/onboarding/providers/onboarding_providers.dart';
import 'package:wpapp/features/onboarding/widgets/create_business_card.dart';
import 'package:wpapp/features/tenancy/providers/tenant_providers.dart';
import 'package:wpapp/features/tenancy/screens/password_reset_screen.dart';
import 'package:wpapp/features/users/models/tenant_invite.dart';

SupabaseClient fixtureClient(
        Future<http.Response> Function(http.Request request) handler) =>
    SupabaseClient(
      'https://example.invalid',
      'fixture',
      authOptions: const AuthClientOptions(autoRefreshToken: false),
      httpClient: MockClient(handler),
    );

http.Response json(http.Request request, Object? body, [int status = 200]) =>
    http.Response(jsonEncode(body), status,
        headers: {'content-type': 'application/json'}, request: request);

class ResetFixture extends AuthController {
  final calls = <String>[];
  Object? failure;

  @override
  FutureOr<AuthState?> build() => null;

  @override
  Future<void> requestPasswordReset(String email) async {
    calls.add('request:$email');
  }

  @override
  Future<void> completePasswordReset({
    required String email,
    required String code,
    required String newPassword,
  }) async {
    calls.add('complete:$email:$code:$newPassword');
    if (failure != null) throw failure!;
  }
}

void main() {
  test('repository calls the onboarding RPCs with server-owned identity',
      () async {
    final requests = <http.Request>[];
    final client = fixtureClient((request) async {
      requests.add(request);
      final path = request.url.path;
      if (path.endsWith('create_business')) return json(request, 'tenant-new');
      if (path.endsWith('my_tenant_invites')) {
        return json(request, [
          {
            'id': 'invite-1',
            'tenant_id': 'tenant-a',
            'tenant_name': 'Yıldız Oto',
            'brand_color': '#12AB34',
            'role': 'admin',
            'created_at': '2026-11-01T00:00:00Z',
            'expires_at': '2026-11-15T00:00:00Z',
          }
        ]);
      }
      return json(request, 'tenant-a');
    });
    addTearDown(client.dispose);
    final repository = OnboardingRepository(client);

    expect(await repository.createBusiness('  Yıldız Oto  '), 'tenant-new');
    expect(jsonDecode(requests.last.body), {'p_name': 'Yıldız Oto'});

    final invites = await repository.myInvites();
    expect(invites.single.tenantName, 'Yıldız Oto');
    expect(invites.single.isAdmin, isTrue);
    expect(invites.single.brandColor, const Color(0xFF12AB34));

    expect(await repository.respondInvite('invite-1', accept: true), 'tenant-a');
    expect(jsonDecode(requests.last.body),
        {'p_invite_id': 'invite-1', 'p_accept': true});
    for (final request in requests) {
      expect(request.body, isNot(contains('user_id')));
      expect(request.body, isNot(contains('invited_by')));
    }
  });

  test('onboarding errors become Turkish guidance, never raw server text', () {
    PostgrestException code(String value) =>
        PostgrestException(message: 'raw server text', code: value);
    expect(onboardingErrorMessage(code('P0013')), contains('doğrulayın'));
    expect(onboardingErrorMessage(code('P0010')), contains('Sınıra'));
    expect(onboardingErrorMessage(code('P0011')), contains('zaten'));
    expect(onboardingErrorMessage(code('42501')), contains('yetkiniz'));
    expect(onboardingErrorMessage(code('XX000')), isNot(contains('raw')));
    expect(onboardingErrorMessage(TimeoutException('x')), contains('yanıt'));
  });

  test('invite status reflects expiry and share text names the address', () {
    final expired = TenantInvite(
      id: 'i',
      email: 'a@example.invalid',
      role: 'user',
      permissions: const {'inbox'},
      status: 'pending',
      createdAt: DateTime(2026),
      expiresAt: DateTime.now().subtract(const Duration(minutes: 1)),
    );
    expect(expired.isPending, isFalse);
    expect(expired.displayStatus, 'expired');
    expect(
        inviteShareMessage(tenantName: 'Yıldız Oto', email: 'a@example.invalid'),
        allOf(contains('Yıldız Oto'), contains('a@example.invalid')));
  });

  testWidgets('create business validates locally and maps server limits',
      (tester) async {
    tester.view.physicalSize = const Size(360, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    var calls = 0;
    final client = fixtureClient((request) async {
      calls++;
      return json(request, {
        'code': 'P0010',
        'message': 'Business limit reached',
        'details': null,
        'hint': null,
      }, 400);
    });
    addTearDown(() => unawaited(client.dispose()));
    await tester.pumpWidget(ProviderScope(
      overrides: [
        onboardingRepositoryProvider
            .overrideWithValue(OnboardingRepository(client)),
      ],
      child: const MaterialApp(
          home: Scaffold(body: SingleChildScrollView(child: CreateBusinessCard()))),
    ));

    await tester.enterText(find.byType(TextFormField), ' x ');
    await tester.tap(find.text('İşletmeyi oluştur'));
    await tester.pump();
    expect(find.text('En az 2 karakter girin.'), findsOneWidget);
    expect(calls, 0);

    await tester.enterText(find.byType(TextFormField), 'Yıldız Oto');
    await tester.tap(find.text('İşletmeyi oluştur'));
    await tester.pumpAndSettle();
    expect(calls, 1);
    expect(find.textContaining('Sınıra ulaşıldı'), findsOneWidget);
    expect(find.textContaining('Business limit'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('password reset sends a code, then verifies it with a new password',
      (tester) async {
    tester.view.physicalSize = const Size(360, 760);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final auth = ResetFixture();
    await tester.pumpWidget(ProviderScope(
      overrides: [authControllerProvider.overrideWith(() => auth)],
      child: const MaterialApp(
          home: PasswordResetScreen(initialEmail: 'agent@example.invalid')),
    ));

    await tester.tap(find.text('Kod gönder'));
    await tester.pumpAndSettle();
    expect(auth.calls, ['request:agent@example.invalid']);
    expect(find.textContaining('hesap varsa'), findsOneWidget);
    expect(find.text('Doğrulama kodu'), findsOneWidget);

    await tester.enterText(find.widgetWithText(TextFormField, 'Doğrulama kodu'), '12');
    await tester.enterText(find.widgetWithText(TextFormField, 'Yeni şifre'), 'short');
    await tester.tap(find.text('Şifreyi değiştir'));
    await tester.pump();
    expect(find.text('E-postadaki kodu girin.'), findsOneWidget);
    expect(find.text('En az 8 karakterlik bir şifre seçin.'), findsOneWidget);
    expect(auth.calls, hasLength(1));

    auth.failure = const AuthException('expired', code: 'otp_expired');
    await tester.enterText(
        find.widgetWithText(TextFormField, 'Doğrulama kodu'), '123456');
    await tester.enterText(
        find.widgetWithText(TextFormField, 'Yeni şifre'), 'yeni-sifre-123');
    await tester.tap(find.text('Şifreyi değiştir'));
    await tester.pumpAndSettle();
    expect(auth.calls.last,
        'complete:agent@example.invalid:123456:yeni-sifre-123');
    expect(find.textContaining('süresi dolmuş'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
