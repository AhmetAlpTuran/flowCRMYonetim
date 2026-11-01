import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:wpapp/features/bot/data/supabase_bot_repository.dart';

// Authored only. Verification execution remains deferred.
void main() {
  for (final configured in [false, true]) {
    test('reading bot settings preserves configured activation ($configured)',
        () async {
      final requests = <http.Request>[];
      final client = SupabaseClient(
        'https://example.invalid',
        'fixture',
        httpClient: MockClient((request) async {
          requests.add(request);
          return http.Response(
              jsonEncode(configured
                  ? [
                      {'tenant_id': 'tenant', 'is_active': true}
                    ]
                  : []),
              200,
              headers: {'content-type': 'application/json'});
        }),
      );
      addTearDown(client.dispose);
      final config =
          await SupabaseBotRepository(client).fetchBotConfig('tenant');
      expect(config.isActive, configured);
      expect(requests, hasLength(1));
      expect(requests.single.method, 'GET');
      expect(requests.single.url.queryParameters['tenant_id'], 'eq.tenant');
    });
  }
}
