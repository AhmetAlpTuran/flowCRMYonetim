import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart' hide AuthState;
import 'package:wpapp/features/account/data/account_repository.dart';
import 'package:wpapp/features/account/screens/account_deletion_screen.dart';
import 'package:wpapp/features/tenancy/models/tenant.dart';
import 'package:wpapp/features/tenancy/providers/tenant_providers.dart';

class SignedIn extends AuthController {
  @override
  FutureOr<AuthState?> build() =>
      const AuthState(userId: 'user-1', email: 'Owner@Example.invalid');
}

class FakeAccountRepository extends AccountRepository {
  FakeAccountRepository(this.plan, {this.failure})
      : super(SupabaseClient('https://example.invalid', 'fixture',
            authOptions: const AuthClientOptions(autoRefreshToken: false)));
  final AccountDeletionPlan plan;
  final AccountDeletionFailure? failure;
  final confirmations = <String>[];

  @override
  Future<AccountDeletionPlan> deletionPlan() async => plan;

  @override
  Future<void> deleteAccount(String confirmEmail) async {
    confirmations.add(confirmEmail);
    if (failure != null) throw failure!;
  }
}

const tenants = [
  Tenant(id: 't-solo', name: 'Yıldız Oto', brandColor: Colors.blue, features: {}, allowedDomains: []),
  Tenant(id: 't-shared', name: 'Ortak Galeri', brandColor: Colors.blue, features: {}, allowedDomains: []),
];

Future<void> pump(WidgetTester tester, FakeAccountRepository repository) async {
  tester.view.physicalSize = const Size(360, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(ProviderScope(
    overrides: [
      authControllerProvider.overrideWith(SignedIn.new),
      accessibleTenantsProvider.overrideWith((ref) async => tenants),
      accountRepositoryProvider.overrideWithValue(repository),
    ],
    child: const MaterialApp(home: AccountDeletionScreen()),
  ));
  await tester.pumpAndSettle();
}

OutlinedButton deleteButton(WidgetTester tester) => tester.widget<OutlinedButton>(
    find.widgetWithText(OutlinedButton, 'Hesabımı kalıcı olarak sil'));

void main() {
  test('deletion plan parses blocked names and tenant ids', () {
    final plan = AccountDeletionPlan.fromJson({
      'blocked': [
        {'tenant_id': 't1', 'name': 'Tek Yönetici'}
      ],
      'delete_tenants': ['t2'],
      'leave_tenants': [],
    });
    expect(plan.blocked, ['Tek Yönetici']);
    expect(plan.deleteTenantIds, ['t2']);
    expect(plan.canDelete, isFalse);
  });

  testWidgets('explains consequences and requires the exact account email',
      (tester) async {
    final repository = FakeAccountRepository(const AccountDeletionPlan(
        blocked: [], deleteTenantIds: ['t-solo'], leaveTenantIds: ['t-shared']));
    await pump(tester, repository);
    expect(find.textContaining('Yıldız Oto'), findsOneWidget);
    expect(find.textContaining('Ortak Galeri'), findsOneWidget);
    expect(deleteButton(tester).onPressed, isNull);

    await tester.enterText(find.byType(TextField), 'someone@else.invalid');
    await tester.pump();
    expect(deleteButton(tester).onPressed, isNull);

    await tester.enterText(find.byType(TextField), ' owner@example.INVALID ');
    await tester.pump();
    expect(deleteButton(tester).onPressed, isNotNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets('sole admin of a team is told to hand over the role',
      (tester) async {
    final repository = FakeAccountRepository(const AccountDeletionPlan(
        blocked: ['Tek Yönetici A.Ş.'], deleteTenantIds: [], leaveTenantIds: []));
    await pump(tester, repository);
    expect(find.textContaining('Tek Yönetici A.Ş.'), findsOneWidget);
    expect(find.textContaining('yönetici yapın'), findsOneWidget);
    expect(tester.widget<TextField>(find.byType(TextField)).enabled, isFalse);
    expect(deleteButton(tester).onPressed, isNull);
  });

  testWidgets('a server refusal is shown and keeps the account', (tester) async {
    final repository = FakeAccountRepository(
      const AccountDeletionPlan(blocked: [], deleteTenantIds: [], leaveTenantIds: []),
      failure: const AccountDeletionFailure('Önce yönetici rolünü başka bir üyeye devredin.',
          blocked: ['Yeni Ekip']),
    );
    await pump(tester, repository);
    await tester.enterText(find.byType(TextField), 'owner@example.invalid');
    await tester.pump();
    // The irreversible step asks once more; cancelling keeps everything.
    await tester.tap(find.text('Hesabımı kalıcı olarak sil'));
    await tester.pumpAndSettle();
    expect(find.text('Hesabınız silinsin mi?'), findsOneWidget);
    await tester.tap(find.text('Vazgeç'));
    await tester.pumpAndSettle();
    expect(repository.confirmations, isEmpty);
    await tester.tap(find.text('Hesabımı kalıcı olarak sil'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Evet, kalıcı olarak sil'));
    await tester.pumpAndSettle();
    expect(repository.confirmations, ['owner@example.invalid']);
    expect(find.textContaining('devredin'), findsOneWidget);
    expect(find.textContaining('Yeni Ekip'), findsOneWidget);
    expect(find.byType(AccountDeletionScreen), findsOneWidget);
  });
}
