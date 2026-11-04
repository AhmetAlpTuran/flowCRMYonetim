import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:wpapp/features/catalog/data/catalog_repository.dart';
import 'package:wpapp/features/catalog/models/catalog_models.dart';
import 'package:wpapp/features/catalog/providers/catalog_providers.dart';
import 'package:wpapp/features/catalog/screens/catalog_screen.dart';
import 'package:wpapp/features/shell/app_shell.dart';
import 'package:wpapp/features/shell/shell_providers.dart';
import 'package:wpapp/features/tenancy/models/tenant.dart';
import 'package:wpapp/features/tenancy/providers/tenant_providers.dart';

const tenant = Tenant(
  id: 'tenant-a',
  name: 'Galeri',
  brandColor: Colors.blue,
  features: {TenantFeature.catalog},
  allowedDomains: [],
);

final vehicleType = ResourceType.fromRow({
  'id': 'type-car',
  'key': 'vehicle',
  'name': 'Araç',
  'kind': 'listing',
  'booking_unit': null,
  'fields': [for (final f in resourceTypePresets[1].fields) f.toJson()],
});

class FakeCatalogRepository extends CatalogRepository {
  FakeCatalogRepository()
      : super(SupabaseClient('https://example.invalid', 'fixture',
            authOptions: const AuthClientOptions(autoRefreshToken: false)));
  final saved = <Map<String, dynamic>>[];

  @override
  Future<void> saveResource({
    required String tenantId,
    String? id,
    required String typeId,
    required String name,
    String? description,
    required Map<String, dynamic> attributes,
    double? price,
    int? capacity,
    required String status,
  }) async {
    saved.add({
      'tenant': tenantId,
      'type': typeId,
      'name': name,
      'attributes': attributes,
      'price': price,
      'status': status,
    });
  }
}

Widget scope(Widget child, {List<Override> overrides = const []}) => ProviderScope(
      overrides: [selectedTenantProvider.overrideWithValue(tenant), ...overrides],
      child: MaterialApp(home: Scaffold(body: child)),
    );

void main() {
  test('Postgres ranges parse with short and long offsets', () {
    final (start, end) = parseRange('["2026-11-17 11:00:00+00","2026-11-19 08:00:00.5+00")');
    expect(start, DateTime.utc(2026, 11, 17, 11));
    expect(end.isUtc, isTrue);
    expect(end.difference(start).inHours, 45);
    final (s2, _) = parseRange('["2026-11-17 14:00:00+03:00","2026-11-17 15:00:00+03:00")');
    expect(s2, DateTime.utc(2026, 11, 17, 11));
  });

  test('booking periods follow check-in/out and hourly conventions', () {
    final (inAt, outAt) = bookingPeriod(
        unit: 'night', firstDay: DateTime(2026, 11, 17), lastDay: DateTime(2026, 11, 19));
    expect(inAt, DateTime(2026, 11, 17, 14));
    expect(outAt, DateTime(2026, 11, 19, 11));
    final (single, singleOut) = bookingPeriod(
        unit: 'night', firstDay: DateTime(2026, 11, 17), lastDay: DateTime(2026, 11, 17));
    expect(singleOut.difference(single).inHours, 21, reason: 'same day means one night');
    final (h1, h2) = bookingPeriod(
        unit: 'hour',
        firstDay: DateTime(2026, 11, 17),
        lastDay: DateTime(2026, 11, 17),
        startTime: const TimeOfDay(hour: 9, minute: 30),
        hours: 2);
    expect(h1, DateTime(2026, 11, 17, 9, 30));
    expect(h2, DateTime(2026, 11, 17, 11, 30));
    final (d1, d2) = bookingPeriod(
        unit: 'day', firstDay: DateTime(2026, 11, 17), lastDay: DateTime(2026, 11, 18));
    expect(d2.difference(d1).inDays, 2);
  });

  test('prices and presets are ready for the database', () {
    expect(formatPrice(1150000, 'TRY'), '1.150.000 ₺');
    expect(formatPrice(null, 'TRY'), 'Fiyat yok');
    for (final preset in resourceTypePresets) {
      expect(RegExp(r'^[a-z][a-z0-9_]{0,39}$').hasMatch(preset.key), isTrue);
      for (final field in preset.fields) {
        expect(RegExp(r'^[a-z][a-z0-9_]{0,39}$').hasMatch(field.key), isTrue);
        if (field.type == 'select') expect(field.toJson()['options'], isNotEmpty);
      }
      expect(preset.kind == 'listing' || preset.bookingUnit != null, isTrue);
    }
  });

  test('catalog members see the Katalog entry', () {
    expect(shellDestinationIdsFor(false, const {'catalog'}, const {TenantFeature.catalog}),
        [ShellDestinationId.catalog]);
    expect(shellDestinationIdsFor(false, const {'inbox'}, const {TenantFeature.catalog}), isEmpty);
  });

  testWidgets('empty catalog offers business presets', (tester) async {
    await tester.pumpWidget(scope(const ResourcesTab(), overrides: [
      resourceTypesProvider.overrideWith((ref) async => const []),
      resourcesProvider.overrideWith((ref) async => const []),
    ]));
    await tester.pumpAndSettle();
    expect(find.text('Oda'), findsOneWidget);
    expect(find.text('Araç'), findsOneWidget);
    expect(find.text('Hizmet'), findsOneWidget);
  });

  testWidgets('item editor builds inputs from fields and saves typed attributes',
      (tester) async {
    tester.view.physicalSize = const Size(360, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final repository = FakeCatalogRepository();
    await tester.pumpWidget(scope(ResourceEditorSheet(type: vehicleType), overrides: [
      catalogRepositoryProvider.overrideWithValue(repository),
      resourcesProvider.overrideWith((ref) async => const []),
    ]));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextFormField, 'Ad'), '2021 Toyota Corolla');
    await tester.enterText(find.widgetWithText(TextFormField, 'Fiyat (₺)'), '1150000');
    await tester.enterText(find.widgetWithText(TextFormField, 'Marka'), 'Toyota');
    await tester.enterText(find.widgetWithText(TextFormField, 'Yıl'), '2021');
    await tester.enterText(find.widgetWithText(TextFormField, 'Kilometre'), 'kırk bin');
    await tester.tap(find.text('Kaydet'));
    await tester.pump();
    expect(find.text('Sayı girin.'), findsOneWidget);
    expect(repository.saved, isEmpty);

    await tester.enterText(find.widgetWithText(TextFormField, 'Kilometre'), '40000');
    await tester.tap(find.byType(DropdownButtonFormField<String>).at(1)); // Vites
    await tester.pumpAndSettle();
    await tester.tap(find.text('Otomatik').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Kaydet'));
    await tester.pumpAndSettle();
    expect(repository.saved.single['attributes'],
        {'brand': 'Toyota', 'year': 2021, 'km': 40000, 'gear': 'Otomatik'});
    expect(repository.saved.single['price'], 1150000);
    expect(repository.saved.single['status'], 'active');
  });

  testWidgets('bookings show live holds with confirm, expired holds without',
      (tester) async {
    tester.view.physicalSize = const Size(360, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final now = DateTime.now().toUtc();
    Booking booking(String id, String status, Duration holdLeft) => Booking(
          id: id,
          resourceId: 'r1',
          resourceName: 'Deniz Odası $id',
          start: now.add(const Duration(days: 3)),
          end: now.add(const Duration(days: 5)),
          status: status,
          holdExpiresAt: status == 'hold' ? now.add(holdLeft) : null,
          customerName: 'Ayşe',
          customerPhone: '905551112233',
          source: 'bot',
          note: null,
        );
    await tester.pumpWidget(scope(const BookingsTab(), overrides: [
      resourceTypesProvider.overrideWith((ref) async => const []),
      bookingsProvider.overrideWith((ref) async => [
            booking('1', 'hold', const Duration(minutes: 10)),
            booking('2', 'hold', const Duration(minutes: -1)),
            booking('3', 'confirmed', Duration.zero),
          ]),
    ]));
    await tester.pumpAndSettle();
    expect(find.text('Ön rezervasyon'), findsOneWidget);
    expect(find.text('Süresi doldu'), findsOneWidget);
    expect(find.text('Onaylı'), findsOneWidget);
    expect(find.text('Onayla'), findsOneWidget);
    expect(find.textContaining('+905551112233'), findsNWidgets(3));
    expect(find.text('Bot tarafından oluşturuldu'), findsNWidgets(3));
    expect(find.textContaining('önce Oda veya Hizmet'), findsOneWidget);
  });

  testWidgets('leads list labels kinds and statuses', (tester) async {
    await tester.pumpWidget(scope(const LeadsTab(), overrides: [
      leadsProvider.overrideWith((ref) async => [
            Lead.fromRow({
              'id': 'l1',
              'kind': 'test_drive',
              'status': 'new',
              'customer_name': 'Mehmet',
              'customer_phone': '905551110001',
              'details': {'note': 'Cumartesi öğleden sonra'},
              'preferred_at': '2026-11-21T11:00:00Z',
              'source': 'bot',
              'created_at': '2026-11-07T10:00:00Z',
              'resource': {'name': '2021 Toyota Corolla'},
            }),
          ]),
    ]));
    await tester.pumpAndSettle();
    expect(find.text('Test sürüşü'), findsOneWidget);
    expect(find.text('Yeni'), findsOneWidget);
    expect(find.text('2021 Toyota Corolla'), findsOneWidget);
    expect(find.text('Cumartesi öğleden sonra'), findsOneWidget);
  });
}
