import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as sb;
import 'package:wpapp/features/tenancy/providers/tenant_providers.dart';
import 'package:wpapp/features/tenancy/screens/login_screen.dart';

const user = sb.User(
    id: 'fixture-user',
    appMetadata: {},
    userMetadata: {},
    aud: 'authenticated',
    email: 'agent@example.invalid',
    createdAt: '2026-01-01T00:00:00Z');

class SessionEventsClient extends sb.GoTrueClient {
  SessionEventsClient()
      : super(url: 'https://example.invalid/auth/v1', autoRefreshToken: false);
  final events = StreamController<sb.AuthState>.broadcast();
  sb.Session? session;
  @override
  sb.Session? get currentSession => session;
  @override
  Stream<sb.AuthState> get onAuthStateChange => events.stream;

  void emit(sb.AuthChangeEvent event, sb.Session? value) {
    session = value;
    events.add(sb.AuthState(event, value));
  }
}

class LoginFixture extends AuthController {
  String? password;
  final completion = Completer<void>();
  int calls = 0;
  @override
  FutureOr<AuthState?> build() => null;
  @override
  Future<void> login(String email, String password) async {
    this.password = password;
    calls++;
    await completion.future;
    state = const AsyncData(
        AuthState(userId: 'fixture-user', email: 'agent@example.invalid'));
  }

  @override
  Future<bool> signUp(String email, String password) async {
    calls++;
    return true;
  }
}

// Authored only. All transports are mocked. Execute in the deferred test phase.
void main() {
  test(
      'session events update routing, retain identity on refresh and handle stream errors',
      () async {
    final client = SessionEventsClient();
    final container = ProviderContainer(
        overrides: [authClientProvider.overrideWithValue(client)]);
    addTearDown(() async {
      container.dispose();
      await client.events.close();
      client.dispose();
    });
    expect(await container.read(authControllerProvider.future), isNull);
    final session =
        sb.Session(accessToken: 'fixture', tokenType: 'bearer', user: user);
    session.expiresAt =
        DateTime.now().add(const Duration(hours: 1)).millisecondsSinceEpoch ~/
            1000;
    client.emit(sb.AuthChangeEvent.signedIn, session);
    await Future<void>.delayed(Duration.zero);
    final signedIn = container.read(authControllerProvider).valueOrNull;
    expect(signedIn?.userId, user.id);
    client.emit(sb.AuthChangeEvent.tokenRefreshed, session);
    await Future<void>.delayed(Duration.zero);
    expect(container.read(authControllerProvider).valueOrNull, same(signedIn));
    client.events.addError(StateError('Offline refresh'));
    await Future<void>.delayed(Duration.zero);
    expect(container.read(authControllerProvider).valueOrNull, same(signedIn));
    client.emit(sb.AuthChangeEvent.signedOut, null);
    await Future<void>.delayed(Duration.zero);
    expect(container.read(authControllerProvider).valueOrNull, isNull);
    session.expiresAt = DateTime.now()
            .subtract(const Duration(minutes: 1))
            .millisecondsSinceEpoch ~/
        1000;
    client.emit(sb.AuthChangeEvent.initialSession, session);
    await Future<void>.delayed(Duration.zero);
    expect(container.read(authControllerProvider).valueOrNull, isNull);
  });

  test(
      'signup without a session does not manufacture an authenticated identity or write a profile',
      () async {
    final requests = <http.Request>[];
    final client = sb.GoTrueClient(
        url: 'https://example.invalid/auth/v1',
        autoRefreshToken: false,
        flowType: sb.AuthFlowType.implicit,
        httpClient: MockClient((request) async {
          requests.add(request);
          return http.Response(jsonEncode(user.toJson()), 200,
              headers: {'content-type': 'application/json'});
        }));
    final container = ProviderContainer(
        overrides: [authClientProvider.overrideWithValue(client)]);
    addTearDown(() {
      container.dispose();
      client.dispose();
    });
    await container.read(authControllerProvider.future);
    expect(
        await container
            .read(authControllerProvider.notifier)
            .signUp('agent@example.invalid', ' password '),
        isTrue);
    expect(container.read(authControllerProvider).valueOrNull, isNull);
    expect(requests, hasLength(1));
    expect(requests.single.url.path, '/auth/v1/signup');
    expect(jsonDecode(requests.single.body)['password'], ' password ');
  });

  test(
      'login publishes the real session immediately and makes no profile request',
      () async {
    final requests = <http.Request>[];
    final payload = base64Url
        .encode(utf8.encode(jsonEncode({
          'exp': DateTime.now()
                  .add(const Duration(hours: 1))
                  .millisecondsSinceEpoch ~/
              1000
        })))
        .replaceAll('=', '');
    final client = sb.GoTrueClient(
        url: 'https://example.invalid/auth/v1',
        autoRefreshToken: false,
        httpClient: MockClient((request) async {
          requests.add(request);
          return http.Response(
              jsonEncode({
                'access_token': 'e30.$payload.fixture',
                'refresh_token': 'fixture',
                'token_type': 'bearer',
                'expires_in': 3600,
                'user': user.toJson()
              }),
              200,
              headers: {'content-type': 'application/json'});
        }));
    final container = ProviderContainer(
        overrides: [authClientProvider.overrideWithValue(client)]);
    addTearDown(() {
      container.dispose();
      client.dispose();
    });
    await container.read(authControllerProvider.future);
    await container
        .read(authControllerProvider.notifier)
        .login('agent@example.invalid', ' password ');
    expect(container.read(authControllerProvider).valueOrNull?.userId, user.id);
    expect(requests, hasLength(1));
    expect(requests.single.url.path, '/auth/v1/token');
  });

  testWidgets('confirmation-required signup stays on the scrollable form',
      (tester) async {
    tester.view.physicalSize = const Size(360, 500);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final controller = LoginFixture();
    await tester.pumpWidget(ProviderScope(
        overrides: [authControllerProvider.overrideWith(() => controller)],
        child: const MaterialApp(home: LoginScreen())));
    await tester.pumpAndSettle();
    await tester.enterText(
        find.byType(TextFormField).first, 'agent@example.invalid');
    await tester.enterText(find.byType(TextFormField).last, ' password ');
    await tester.ensureVisible(find.text('Kayıt ol'));
    await tester.tap(find.text('Kayıt ol'));
    await tester.pumpAndSettle();
    expect(find.byType(LoginScreen), findsOneWidget);
    expect(find.textContaining('E-posta doğrulaması'), findsOneWidget);
    expect(controller.calls, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'login preserves password whitespace, blocks duplicates and returns to root',
      (tester) async {
    final controller = LoginFixture();
    await tester.pumpWidget(ProviderScope(
        overrides: [authControllerProvider.overrideWith(() => controller)],
        child: MaterialApp(
            home: Scaffold(
                body: Builder(
                    builder: (context) => TextButton(
                        onPressed: () => Navigator.of(context).push(
                            MaterialPageRoute<void>(
                                builder: (_) => const LoginScreen())),
                        child: const Text('Open login')))))));
    await tester.tap(find.text('Open login'));
    await tester.pumpAndSettle();
    await tester.enterText(
        find.byType(TextFormField).first, 'agent@example.invalid');
    await tester.enterText(find.byType(TextFormField).last, ' password ');
    await tester.tap(find.text('Giriş yap'));
    await tester.pump();
    expect(controller.password, ' password ');
    expect(tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNull);
    controller.completion.complete();
    await tester.pumpAndSettle();
    expect(find.byType(LoginScreen), findsNothing);
    expect(controller.calls, 1);
    expect(tester.takeException(), isNull);
  });
}
