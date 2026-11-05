import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart' hide AuthState;
import 'package:wpapp/features/billing/data/billing_repository.dart';
import 'package:wpapp/features/billing/models/billing_overview.dart';
import 'package:wpapp/features/billing/providers/billing_providers.dart';
import 'package:wpapp/features/billing/screens/billing_screen.dart';
import 'package:wpapp/features/connections/models/whatsapp_connection.dart';
import 'package:wpapp/features/connections/providers/connections_providers.dart';
import 'package:wpapp/features/connections/screens/connections_screen.dart';
import 'package:wpapp/features/tenancy/data/business_profile_repository.dart';
import 'package:wpapp/features/tenancy/models/tenant.dart';
import 'package:wpapp/features/tenancy/models/tenant_membership.dart';
import 'package:wpapp/features/tenancy/providers/tenant_providers.dart';
import 'package:wpapp/features/tenancy/screens/business_settings_screen.dart';
import 'package:wpapp/features/tenancy/screens/custom_feature_screen.dart';
import 'package:wpapp/features/users/data/supabase_tenant_admin_repository.dart';
import 'package:wpapp/features/users/models/tenant_invite.dart';
import 'package:wpapp/features/users/models/tenant_join_request.dart';
import 'package:wpapp/features/users/models/tenant_member.dart';
import 'package:wpapp/features/users/providers/tenant_admin_providers.dart';
import 'package:wpapp/features/users/screens/tenant_users_screen.dart';
import 'package:wpapp/features/users/widgets/access_sheet.dart';
import 'package:wpapp/ui/ui.dart';

Tenant tenantNamed(String name, String hex) => Tenant(
      id: 'tenant-a',
      name: name,
      brandColor: brandColorFromHex(hex)!,
      features: const {TenantFeature.inbox, TenantFeature.users},
      allowedDomains: const [],
    );

const admin = TenantMembership(role: 'admin', permissions: {'inbox', 'users'});

class SignedIn extends AuthController {
  @override
  FutureOr<AuthState?> build() => const AuthState(userId: 'user-me', email: 'demo@example.invalid');
}

class FakeBusinessProfile implements BusinessProfileRepository {
  FakeBusinessProfile({this.failure});
  final Object? failure;
  final calls = <(String, String, String)>[];
  void Function(String name, String hex)? onSaved;

  @override
  Future<void> update({required String tenantId, required String name, required String brandColor}) async {
    calls.add((tenantId, name, brandColor));
    if (failure != null) throw failure!;
    onSaved?.call(name, brandColor);
  }
}

class FakeAdminRepository extends SupabaseTenantAdminRepository {
  FakeAdminRepository()
      : super(SupabaseClient('https://example.invalid', 'fixture',
            authOptions: const AuthClientOptions(autoRefreshToken: false)));
  final invites = <(String, String, Set<String>)>[];
  final updates = <(String, String, Set<String>)>[];

  @override
  Future<String> createInvite({
    required String tenantId,
    required String email,
    required String role,
    required Set<String> permissions,
  }) async {
    invites.add((email, role, permissions));
    return 'invite-new';
  }

  @override
  Future<void> updateMember({required String membershipId, required String role, required Set<String> permissions}) async =>
      updates.add((membershipId, role, permissions));
}

class FakeBilling implements BillingRepository {
  FakeBilling(this.json);
  final Map<String, dynamic> json;

  @override
  Future<BillingOverview> fetchOverview(String tenantId) async => BillingOverview.fromJson(json);
  @override
  Future<BillingProfile?> fetchProfile(String tenantId) async => null;
  @override
  Future<void> saveProfile(String tenantId, BillingProfile profile) async {}
  @override
  Future<String> startCheckout(String tenantId, String planKey, String period) async => 'https://pages.example/odeme/';
  @override
  Future<void> changePlan(String tenantId, String planKey) async {}
  @override
  Future<void> cancel(String tenantId) async {}
  @override
  Future<String> refresh(String tenantId) async => 'none';
}

Map<String, dynamic> billingJson({String status = 'trialing', bool profile = false}) => {
      'status': status,
      'plan': {'key': 'pro', 'name': 'Profesyonel', 'monthly_price_try': 3490, 'yearly_price_try': 34900},
      'billing_period': null,
      'provider': null,
      'has_billing_profile': profile,
      'trial_ends_at': DateTime.now().toUtc().add(const Duration(days: 9)).toIso8601String(),
      'current_period_end': '2026-12-01T00:00:00Z',
      'limits': {
        'seats': 5,
        'whatsapp_numbers': 2,
        'bots': 3,
        'ai_monthly_tokens': 15000000,
        'campaign_messages_monthly': 10000,
      },
      'usage': {'seats': 2, 'whatsapp_numbers': 1, 'bots': 2, 'ai_tokens': 4020000, 'campaign_messages': 1240},
      'plans': [
        for (final (key, name, price, seats) in [
          ('starter', 'Başlangıç', 1490, 2),
          ('pro', 'Profesyonel', 3490, 5),
          ('business', 'İşletme', 7990, 15),
        ])
          {
            'key': key,
            'name': name,
            'description': '',
            'monthly_price_try': price,
            'yearly_price_try': price * 10,
            'seats': seats,
            'whatsapp_numbers': 2,
            'bots': 3,
            'ai_monthly_tokens': 15000000,
            'campaign_messages_monthly': 10000,
            'online_monthly': true,
            'online_yearly': true,
          },
      ],
    };

final members = [
  const TenantMember(
    id: 'm-1',
    userId: 'user-me',
    role: 'admin',
    permissions: {'inbox', 'users'},
    displayName: 'Demo Yönetici',
    email: 'demo@example.invalid',
  ),
  const TenantMember(
    id: 'm-2',
    userId: 'user-2',
    role: 'user',
    permissions: {'inbox', 'handoff', 'campaigns', 'templates', 'catalog', 'knowledge'},
    displayName: 'Elif Kara',
    email: 'elif.kara.uzun-adres@ornekgaleri.example.invalid',
  ),
];

final invites = [
  TenantInvite(
    id: 'i-1',
    email: 'can@ornekgaleri.example.invalid',
    role: 'user',
    permissions: const {'inbox'},
    status: 'pending',
    createdAt: DateTime.now().subtract(const Duration(days: 2)),
    expiresAt: DateTime.now().add(const Duration(days: 12)),
  ),
  TenantInvite(
    id: 'i-2',
    email: 'eski@ornekgaleri.example.invalid',
    role: 'user',
    permissions: const {'inbox'},
    status: 'pending',
    createdAt: DateTime(2026, 9, 1),
    expiresAt: DateTime(2026, 9, 15),
  ),
];

final requests = [
  TenantJoinRequest(
    id: 'r-1',
    tenantId: 'tenant-a',
    userId: 'user-9',
    email: 'basvuru@example.invalid',
    status: 'pending',
    createdAt: DateTime(2026, 11, 1),
    message: 'Satış ekibinden Mert, katılmak istiyorum.',
  ),
];

final connections = [
  WhatsAppConnection.fromRow({
    'id': 'conn-1',
    'waba_id': '900000000001',
    'phone_number_id': '900000000002',
    'display_phone_number': '905550000000',
    'verified_name': 'Demo Oto Galeri',
    'status': 'active',
    'is_default': true,
    'token_expires_at': null,
  }),
  WhatsAppConnection.fromRow({
    'id': 'conn-2',
    'waba_id': '900000000001',
    'phone_number_id': '900000000003',
    'display_phone_number': '905551112233',
    'verified_name': '',
    'status': 'active',
    'is_default': false,
    'token_expires_at': DateTime.now().add(const Duration(days: 3)).toUtc().toIso8601String(),
  }),
  WhatsAppConnection.fromRow({
    'id': 'conn-3',
    'waba_id': '900000000001',
    'phone_number_id': '900000000004',
    'display_phone_number': '',
    'verified_name': 'Şube',
    'status': 'needs_attention',
    'is_default': false,
    'token_expires_at': null,
  }),
];

List<Override> settingsOverrides({
  Tenant? tenant,
  bool overrideTenant = true,
  TenantMembership membership = admin,
  BusinessProfileRepository? profile,
  SupabaseTenantAdminRepository? adminRepository,
  List<Uri>? opened,
}) =>
    [
      if (overrideTenant)
        selectedTenantProvider.overrideWithValue(tenant ?? tenantNamed('Demo Oto Galeri', '#1F4B99')),
      currentMembershipProvider.overrideWith((ref) async => membership),
      authControllerProvider.overrideWith(SignedIn.new),
      businessProfileRepositoryProvider.overrideWithValue(profile ?? FakeBusinessProfile()),
      billingRepositoryProvider.overrideWithValue(FakeBilling(billingJson())),
      onlinePurchaseAllowedProvider.overrideWithValue(true),
      openPaymentPageProvider.overrideWithValue((url) async => true),
      tenantAdminRepositoryProvider.overrideWithValue(adminRepository ?? FakeAdminRepository()),
      tenantMembersProvider.overrideWith((ref) async => members),
      tenantInvitesProvider.overrideWith((ref) async => invites),
      tenantJoinRequestsProvider.overrideWith((ref) async => requests),
      openExternalLinkProvider.overrideWithValue((uri) async {
        opened?.add(uri);
        return true;
      }),
      whatsappConnectionsProvider.overrideWith((ref) async => connections),
      connectionAssistantsProvider.overrideWith((ref) async => {'conn-1': 'Ava'}),
    ];

Widget host(Widget screen, List<Override> overrides, {ThemeData? theme}) => ProviderScope(
      overrides: overrides,
      child: MaterialApp(theme: theme ?? FlowTheme.dark(), home: Scaffold(body: screen)),
    );

/// FilledButton.icon builds a private subclass, which find.byType does not match.
final filled = find.byWidgetPredicate((widget) => widget is FilledButton);

void size(WidgetTester tester, double width, {double height = 1400}) {
  tester.view.physicalSize = Size(width, height);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

void main() {
  group('business profile', () {
    test('colors round-trip as uppercase #RRGGBB', () {
      expect(brandHex(brandColorFromHex('#1f4b99')!), '#1F4B99');
      expect(brandColorFromHex('red'), isNull);
      expect(brandColorFromHex('#12345'), isNull);
      expect(businessColorPresets, hasLength(6));
      expect(businessColorPresets.every((preset) => brandColorFromHex(preset.$2) != null), isTrue);
    });

    test('server errors become Turkish guidance without raw text', () {
      expect(businessProfileErrorMessage(const PostgrestException(message: 'raw', code: '42501')),
          contains('yalnızca işletme yöneticileri'));
      expect(businessProfileErrorMessage(const PostgrestException(message: 'raw', code: '22023', hint: 'brand_color')),
          contains('rengi'));
      expect(businessProfileErrorMessage(const PostgrestException(message: 'raw', code: '22023', hint: 'business_name')),
          contains('2 ile 80'));
      expect(businessProfileErrorMessage(TimeoutException('x')), contains('yanıt vermedi'));
      expect(businessProfileErrorMessage(const PostgrestException(message: 'raw', code: 'XX000')), isNot(contains('raw')));
    });

    test('the repository calls update_business_profile with trimmed, uppercase input', () async {
      final sent = <(String, Map<String, dynamic>)>[];
      var fail = false;
      final client = SupabaseClient('https://example.invalid', 'fixture',
          authOptions: const AuthClientOptions(autoRefreshToken: false),
          httpClient: MockClient((request) async {
            sent.add((request.url.path, jsonDecode(request.body) as Map<String, dynamic>));
            return fail
                ? http.Response(
                    jsonEncode({'code': '22023', 'message': 'raw', 'details': null, 'hint': 'brand_color'}), 400,
                    headers: {'content-type': 'application/json'}, request: request)
                : http.Response('null', 200, headers: {'content-type': 'application/json'}, request: request);
          }));
      final repository = SupabaseBusinessProfileRepository(client);
      await repository.update(tenantId: 'tenant-a', name: '  Yeni Galeri ', brandColor: '#9b2335');
      expect(sent.single.$1, '/rest/v1/rpc/update_business_profile');
      expect(sent.single.$2, {'p_tenant_id': 'tenant-a', 'p_name': 'Yeni Galeri', 'p_brand_color': '#9B2335'});
      fail = true;
      final error = await repository
          .update(tenantId: 'tenant-a', name: 'Galeri', brandColor: '#000000')
          .then<Object?>((_) => null, onError: (Object error) => error);
      expect(businessProfileErrorMessage(error!), contains('rengi'));
      unawaited(client.dispose());
    });

    testWidgets('saving renames, recolors and refreshes the business list', (tester) async {
      size(tester, 320);
      var current = tenantNamed('Demo Oto Galeri', '#1F4B99');
      var loads = 0;
      final fake = FakeBusinessProfile()..onSaved = (name, hex) => current = tenantNamed(name, hex);
      await tester.pumpWidget(host(const BusinessSettingsScreen(), [
        ...settingsOverrides(profile: fake, overrideTenant: false),
        accessibleTenantsProvider.overrideWith((ref) async {
          loads++;
          return [current];
        }),
        selectedTenantProvider.overrideWith((ref) => ref.watch(accessibleTenantsProvider).valueOrNull?.first),
      ]));
      await tester.pumpAndSettle();
      expect(loads, 1);
      final save = find.widgetWithText(FilledButton, 'Kaydet');
      expect(tester.widget<FilledButton>(save).onPressed, isNull, reason: 'nothing changed yet');
      expect(find.text('#1F4B99'), findsOneWidget);

      await tester.enterText(find.widgetWithText(TextFormField, 'İşletme adı'), ' Yeni Galeri ');
      await tester.tap(find.byTooltip('Bordo'));
      await tester.pump();
      expect(find.text('#9B2335'), findsOneWidget, reason: 'the preview follows the swatch');
      expect(find.text('Yeni Galeri'), findsOneWidget, reason: 'the preview follows the name');

      await tester.ensureVisible(save);
      await tester.tap(save);
      await tester.pumpAndSettle();
      expect(fake.calls.single, ('tenant-a', 'Yeni Galeri', '#9B2335'));
      expect(loads, 2, reason: 'the sidebar and switcher reload the business');
      expect(find.text('İşletme bilgileri kaydedildi'), findsOneWidget);
      expect(tester.widget<FilledButton>(save).onPressed, isNull, reason: 'saved values are clean');
      expect(tester.takeException(), isNull);
    });

    testWidgets('a short name is caught locally and server errors are shown in Turkish', (tester) async {
      size(tester, 320);
      final fake = FakeBusinessProfile(failure: const PostgrestException(message: 'raw', code: '42501'));
      await tester.pumpWidget(host(const BusinessSettingsScreen(), settingsOverrides(profile: fake)));
      await tester.pumpAndSettle();
      final save = find.widgetWithText(FilledButton, 'Kaydet');

      await tester.enterText(find.widgetWithText(TextFormField, 'İşletme adı'), 'x');
      await tester.pump();
      await tester.ensureVisible(save);
      await tester.tap(save);
      await tester.pump();
      expect(find.textContaining('en az 2 karakter'), findsOneWidget);
      expect(fake.calls, isEmpty);

      await tester.enterText(find.widgetWithText(TextFormField, 'İşletme adı'), 'Başka Galeri');
      await tester.pump();
      await tester.tap(save);
      await tester.pumpAndSettle();
      expect(fake.calls, hasLength(1));
      expect(find.textContaining('yalnızca işletme yöneticileri'), findsOneWidget);
      expect(find.textContaining('raw'), findsNothing);
    });

    testWidgets('members who are not administrators see no form', (tester) async {
      size(tester, 320);
      await tester.pumpWidget(host(const BusinessSettingsScreen(),
          settingsOverrides(membership: const TenantMembership(role: 'user', permissions: {'users'}))));
      await tester.pumpAndSettle();
      expect(find.text('Yalnızca yöneticiler'), findsOneWidget);
      expect(find.text('Kaydet'), findsNothing);
    });
  });

  group('Ekip', () {
    test('invite text carries the business, the address and the link', () {
      final message = inviteShareMessage(tenantName: 'Yıldız Oto', email: 'a@example.invalid', link: 'https://flow.example/');
      expect(message, allOf(contains('Yıldız Oto'), contains('a@example.invalid'), contains('https://flow.example/')));
      final uri = whatsappShareUri(message);
      expect(uri.host, 'wa.me');
      expect(uri.queryParameters['text'], message);
      expect(uri.toString(), isNot(contains(' ')));
      expect(accessSummary('admin', const {}), 'Yönetici · Tüm ekranlar');
      expect(accessSummary('user', const {'inbox', 'handoff'}), 'Temsilci · Sohbetler ve müşteriler, Temsilci bekleyen');
      expect(accessSummary('user', const {}), 'Temsilci · Yetki yok');
    });

    testWidgets('members, seats, pending invites and join requests are listed', (tester) async {
      size(tester, 320, height: 2400);
      final opened = <Uri>[];
      String? copied;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
        if (call.method == 'Clipboard.setData') copied = (call.arguments as Map)['text'] as String?;
        return null;
      });
      addTearDown(() => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, null));
      await tester.pumpWidget(host(const TenantUsersScreen(), settingsOverrides(opened: opened)));
      await tester.pumpAndSettle();

      expect(find.text('2 / 5 KULLANICI · PROFESYONEL'), findsOneWidget);
      expect(find.text('Demo Yönetici (siz)', findRichText: true), findsOneWidget);
      expect(find.text('YÖNETİCİ · TÜM EKRANLAR'), findsOneWidget);
      expect(find.text('Yetkileri düzenle'), findsOneWidget, reason: 'only for other members');
      expect(find.text('Bekleyen davetler'), findsOneWidget);
      expect(find.text('DAVET BEKLİYOR · 2 GÜN ÖNCE'), findsOneWidget);
      expect(find.text('Katılma istekleri'), findsOneWidget);
      expect(find.text('SÜRESİ DOLDU'), findsOneWidget, reason: 'expired invites move to history');
      expect(find.ancestor(of: find.text('Ekip arkadaşı davet et'), matching: filled), findsOneWidget);
      expect(filled, findsOneWidget, reason: 'one primary button per view');

      await tester.ensureVisible(find.text('WhatsApp ile gönder'));
      await tester.tap(find.text('WhatsApp ile gönder'));
      await tester.pumpAndSettle();
      final text = opened.single.queryParameters['text']!;
      expect(opened.single.host, 'wa.me');
      expect(text, allOf(contains('Demo Oto Galeri'), contains('can@ornekgaleri.example.invalid'), contains(inviteLink)));

      await tester.tap(find.text('Bağlantıyı kopyala'));
      await tester.pumpAndSettle();
      expect(copied, text);
      expect(find.text('Davet mesajı ve bağlantı kopyalandı'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a new invite is created and shared on WhatsApp', (tester) async {
      size(tester, 320);
      final repository = FakeAdminRepository();
      final opened = <Uri>[];
      await tester.pumpWidget(
          host(const TenantUsersScreen(), settingsOverrides(adminRepository: repository, opened: opened)));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Ekip arkadaşı davet et'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Davet oluştur'));
      await tester.pump();
      expect(find.text('E-posta adresini girin.'), findsOneWidget);
      expect(repository.invites, isEmpty);

      await tester.enterText(find.widgetWithText(TextFormField, 'E-posta'), ' Yeni@Example.invalid ');
      await tester.ensureVisible(find.text('Kampanyalar'));
      await tester.tap(find.text('Kampanyalar'));
      await tester.ensureVisible(find.text('Davet oluştur'));
      await tester.tap(find.text('Davet oluştur'));
      await tester.pumpAndSettle();
      expect(repository.invites.single.$1, 'Yeni@Example.invalid');
      expect(repository.invites.single.$2, 'user');
      expect(repository.invites.single.$3, {'inbox', 'campaigns'});
      expect(find.text('Davet oluşturuldu'), findsOneWidget);

      await tester.tap(find.descendant(of: find.byType(AlertDialog), matching: find.text('WhatsApp ile gönder')));
      await tester.pumpAndSettle();
      expect(opened.single.queryParameters['text'], contains('yeni@example.invalid'));
      expect(tester.takeException(), isNull);
    });

    testWidgets('making a member an administrator grants every screen', (tester) async {
      size(tester, 320);
      final repository = FakeAdminRepository();
      await tester.pumpWidget(host(const TenantUsersScreen(), settingsOverrides(adminRepository: repository)));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Yetkileri düzenle'));
      await tester.tap(find.text('Yetkileri düzenle'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Yönetici'));
      await tester.pump();
      await tester.tap(find.widgetWithText(FilledButton, 'Kaydet'));
      await tester.pumpAndSettle();
      expect(repository.updates.single.$1, 'm-2');
      expect(repository.updates.single.$2, 'admin');
      expect(repository.updates.single.$3, PermissionOption.keys.toSet());
      expect(find.text('Yetkiler güncellendi'), findsOneWidget);
    });

    testWidgets('people without user management see a plain message', (tester) async {
      size(tester, 320);
      await tester.pumpWidget(host(const TenantUsersScreen(),
          settingsOverrides(membership: const TenantMembership(role: 'user', permissions: {'inbox'}))));
      await tester.pumpAndSettle();
      expect(find.text('Bu bölüme erişiminiz yok'), findsOneWidget);
    });
  });

  testWidgets('WhatsApp numbers show the live state, the assistant and expiry', (tester) async {
    size(tester, 320, height: 2000);
    await tester.pumpWidget(host(const ConnectionsScreen(), settingsOverrides()));
    await tester.pumpAndSettle();
    expect(find.text('3 / 2 NUMARA'), findsOneWidget, reason: 'count against the plan limit');
    expect(find.text('+90 555 000 00 00'), findsOneWidget);
    expect(find.text('ASİSTAN · AVA'), findsOneWidget);
    expect(find.text('ANAHTAR SÜRESİ DOLUYOR'), findsOneWidget);
    expect(find.text('HATA'), findsOneWidget);
    expect(find.text('900000000004'), findsOneWidget, reason: 'the Meta ID when no number is known');
    expect(find.byType(LiveDot), findsNWidgets(2));
  });

  group('settings screens render in both themes at phone and desktop widths', () {
    final screens = <String, Widget>{
      'İşletme': const BusinessSettingsScreen(),
      'Ekip': const TenantUsersScreen(),
      'WhatsApp numaraları': const ConnectionsScreen(),
      'Abonelik': const BillingScreen(),
      'Özel modüller': const CustomFeatureScreen(),
    };
    for (final entry in screens.entries) {
      for (final dark in [true, false]) {
        for (final width in [320.0, 1280.0]) {
          testWidgets('${entry.key} · ${dark ? 'koyu' : 'açık'} · ${width.toInt()} px', (tester) async {
            size(tester, width, height: 1000);
            await tester.pumpWidget(host(entry.value, settingsOverrides(),
                theme: dark ? FlowTheme.dark() : FlowTheme.light()));
            await tester.pumpAndSettle();
            expect(tester.takeException(), isNull);
            final scrollable = find.byType(Scrollable);
            if (scrollable.evaluate().isNotEmpty) {
              await tester.drag(scrollable.first, const Offset(0, -3000));
              await tester.pumpAndSettle();
              expect(tester.takeException(), isNull);
            }
          });
        }
      }
    }
  });
}
