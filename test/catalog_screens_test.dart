import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:wpapp/features/catalog/data/catalog_repository.dart';
import 'package:wpapp/features/catalog/models/catalog_models.dart';
import 'package:wpapp/features/catalog/providers/catalog_providers.dart';
import 'package:wpapp/features/catalog/screens/catalog_screen.dart';
import 'package:wpapp/features/catalog/widgets/industry_pack_sheet.dart';
import 'package:wpapp/features/catalog/widgets/resource_photos_editor.dart';
import 'package:wpapp/features/tenancy/models/tenant.dart';
import 'package:wpapp/features/tenancy/models/tenant_membership.dart';
import 'package:wpapp/features/tenancy/providers/tenant_providers.dart';
import 'package:wpapp/ui/ui.dart' show FlowTheme, StatusBadge;

const tenant = Tenant(
  id: 'tenant-a',
  name: 'Galeri',
  brandColor: Colors.blue,
  features: {TenantFeature.catalog},
  allowedDomains: [],
);

ResourceType typeFrom(ResourceTypePreset preset, String id) => ResourceType.fromRow({
      'id': id,
      'key': preset.key,
      'name': preset.name,
      'kind': preset.kind,
      'booking_unit': preset.bookingUnit,
      'fields': [for (final f in preset.fields) f.toJson()],
    });

final roomType = typeFrom(resourceTypePresets[0], 'type-room');
final vehicleType = typeFrom(resourceTypePresets[1], 'type-car');

final resources = [
  Resource.fromRow({
    'id': 'car-1',
    'type_id': 'type-car',
    'name': '2021 Renault Clio 1.0 TCe Touch, uzun bir ilan başlığı ile',
    'description': 'Servis bakımlı, garantili.',
    'attributes': {'brand': 'Renault', 'model': 'Clio', 'year': 2021, 'km': 40000, 'gear': 'Otomatik'},
    'price': 900000,
    'status': 'active',
    'photos': ['tenant-a/car-1/a.jpg', 'tenant-a/car-1/b.jpg'],
  }),
  Resource.fromRow({
    'id': 'car-2',
    'type_id': 'type-car',
    'name': '2019 Fiat Egea',
    'attributes': {'brand': 'Fiat', 'fuel': 'Dizel'},
    'price': null,
    'status': 'sold',
  }),
  Resource.fromRow({
    'id': 'room-1',
    'type_id': 'type-room',
    'name': 'Deniz manzaralı oda',
    'attributes': {'beds': 2, 'view': 'Deniz', 'breakfast': true},
    'price': 3500,
    'capacity': 3,
    'status': 'reserved',
  }),
];

final now = DateTime.now();

final bookings = [
  Booking(
    id: 'b1',
    resourceId: 'room-1',
    resourceName: 'Deniz manzaralı oda',
    start: DateTime(now.year, now.month, now.day, 14),
    end: DateTime(now.year, now.month, now.day, 14).add(const Duration(days: 2, hours: -3)),
    status: 'hold',
    holdExpiresAt: now.add(const Duration(minutes: 12)),
    customerName: 'Ayşe Yılmaz',
    customerPhone: '905551112233',
    source: 'bot',
    note: 'Erken giriş istiyor.',
  ),
  Booking(
    id: 'b2',
    resourceId: 'room-1',
    resourceName: 'Deniz manzaralı oda',
    start: now.add(const Duration(days: 3)),
    end: now.add(const Duration(days: 3, hours: 1)),
    status: 'confirmed',
    holdExpiresAt: null,
    customerName: null,
    customerPhone: null,
    source: 'agent',
    note: null,
  ),
  Booking(
    id: 'b3',
    resourceId: 'room-1',
    resourceName: 'Deniz manzaralı oda',
    start: now.add(const Duration(days: 1)),
    end: now.add(const Duration(days: 2)),
    status: 'hold',
    holdExpiresAt: now.subtract(const Duration(minutes: 1)),
    customerName: 'Mehmet Kaya',
    customerPhone: '905551110001',
    source: 'bot',
    note: null,
  ),
];

Lead lead(String id, String kind, String status, {String source = 'bot', String? resource, String? preferred}) =>
    Lead.fromRow({
      'id': id,
      'kind': kind,
      'status': status,
      'customer_name': 'Müşteri $id',
      'customer_phone': '90555111000$id',
      'details': {'note': 'Not $id'},
      'preferred_at': preferred,
      'source': source,
      'created_at': now.subtract(const Duration(minutes: 6)).toUtc().toIso8601String(),
      'resource': resource == null ? null : {'name': resource},
    });

final leads = [
  lead('1', 'test_drive', 'new', resource: '2021 Renault Clio', preferred: now.add(const Duration(days: 1)).toUtc().toIso8601String()),
  lead('2', 'financing', 'new'),
  lead('3', 'trade_in', 'contacted', source: 'agent', resource: '2015 VW Golf'),
  lead('4', 'inquiry', 'won', source: 'agent'),
  lead('5', 'booking_request', 'lost'),
];

class FakeCatalogRepository extends CatalogRepository {
  FakeCatalogRepository()
      : super(SupabaseClient('https://example.invalid', 'fixture',
            authOptions: const AuthClientOptions(autoRefreshToken: false)));

  final leadStatuses = <(String, String)>[];
  final bookingStatuses = <(String, String)>[];

  @override
  Future<void> setLeadStatus(String tenantId, String leadId, String status) async =>
      leadStatuses.add((leadId, status));

  @override
  Future<void> setBookingStatus(String tenantId, String bookingId, String status) async =>
      bookingStatuses.add((bookingId, status));
}

class FakeStore implements CatalogPhotoStore {
  @override
  Future<String> upload(String tenantId, String resourceId, Uint8List bytes, String extension) async => 'x';

  @override
  Future<void> setPhotos(String tenantId, String resourceId, List<String> paths) async {}

  @override
  Future<void> remove(String path) async {}

  @override
  Future<String> signedUrl(String path) async => '';
}

Finder badge(String label) => find.byWidgetPredicate((w) => w is StatusBadge && w.label == label);

Widget app(
  Widget child, {
  ThemeData? theme,
  FakeCatalogRepository? repository,
  List<ResourceType> types = const [],
  List<Resource> items = const [],
  bool admin = true,
}) =>
    ProviderScope(
      overrides: [
        selectedTenantProvider.overrideWithValue(tenant),
        currentMembershipProvider.overrideWith(
            (ref) async => TenantMembership(role: admin ? 'admin' : 'user', permissions: const {'catalog'})),
        catalogRepositoryProvider.overrideWithValue(repository ?? FakeCatalogRepository()),
        catalogPhotoStoreProvider.overrideWithValue(FakeStore()),
        resourceTypesProvider.overrideWith((ref) async => types),
        resourcesProvider.overrideWith((ref) async => items),
        bookingsProvider.overrideWith((ref) async => bookings),
        leadsProvider.overrideWith((ref) async => leads),
        industryPacksProvider.overrideWith((ref) async => [
              IndustryPack.fromJson({
                'key': 'auto_dealer',
                'name': 'Oto galeri',
                'questions': [
                  {'key': 'address', 'title': 'Adres ve çalışma saatleri'},
                ],
              }),
              IndustryPack.fromJson({'key': 'rental', 'name': 'Konaklama ve kiralama', 'questions': []}),
              IndustryPack.fromJson({'key': 'appointments', 'name': 'Randevu', 'questions': []}),
            ]),
      ],
      child: MaterialApp(theme: theme ?? FlowTheme.dark(), home: Scaffold(body: child)),
    );

void setSize(WidgetTester tester, double width, [double height = 900]) {
  tester.view.physicalSize = Size(width, height);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

void main() {
  test('booking spans read as times, whole days or check-in to check-out', () {
    final day = DateTime(2026, 11, 17);
    expect(bookingSpan(day.add(const Duration(hours: 10)), day.add(const Duration(hours: 11, minutes: 30))),
        '10:00–11:30');
    expect(bookingSpan(day, day.add(const Duration(days: 1))), 'Tüm gün');
    expect(bookingSpan(day, day.add(const Duration(days: 3))), '17 Kas – 19 Kas');
    expect(bookingSpan(day.add(const Duration(hours: 14)), DateTime(2026, 11, 19, 11)), '17 Kas 14:00 → 19 Kas 11:00');
  });

  final screens = <String, Widget Function()>{
    'Kayıtlar': () => const ResourcesTab(),
    'Kayıtlar (boş)': () => const ResourcesTab(),
    'Rezervasyonlar': () => const BookingsTab(),
    'Talepler': () => const LeadsTab(),
    'Kayıt düzenleyici': () => ResourceEditorSheet(type: vehicleType, resource: resources.first),
    'Yeni oda': () => ResourceEditorSheet(type: roomType),
    'Rezervasyon ekle': () => const BookingEditorSheet(),
    'Sektör paketi': () => const IndustryPackSheet(),
  };

  for (final brightness in Brightness.values) {
    for (final width in [320.0, 1280.0]) {
      for (final entry in screens.entries) {
        testWidgets('${entry.key} renders without overflow ($brightness, ${width.toInt()} px)', (tester) async {
          setSize(tester, width);
          final empty = entry.key == 'Kayıtlar (boş)';
          await tester.pumpWidget(app(
            entry.value(),
            theme: FlowTheme.of(brightness),
            types: empty ? const [] : [vehicleType, roomType],
            items: empty ? const [] : resources,
          ));
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
        });
      }
    }
  }

  testWidgets('items show as cards with mono prices, status badges and a type filter', (tester) async {
    setSize(tester, 1280);
    await tester.pumpWidget(app(const ResourcesTab(), types: [vehicleType, roomType], items: resources));
    await tester.pumpAndSettle();
    expect(find.text('900.000 ₺'), findsOneWidget);
    expect(find.text('Fiyat yok'), findsOneWidget);
    expect(badge('Yayında'), findsOneWidget);
    expect(badge('Satıldı'), findsOneWidget);
    expect(badge('Rezerve'), findsOneWidget);
    expect(find.text('Kayıt ekle'), findsOneWidget, reason: 'one primary action for several types');
    expect(find.byType(FilledButton), findsOneWidget);

    await tester.tap(find.text('Oda'));
    await tester.pumpAndSettle();
    expect(find.text('Deniz manzaralı oda'), findsOneWidget);
    expect(find.text('2019 Fiat Egea'), findsNothing);
    expect(find.text('Oda ekle'), findsOneWidget, reason: 'the filter picks the type to add');

    await tester.tap(find.text('Tümü'));
    await tester.enterText(find.byType(TextField), 'dizel');
    await tester.pumpAndSettle();
    expect(find.text('2019 Fiat Egea'), findsOneWidget);
    expect(find.text('Deniz manzaralı oda'), findsNothing);

    await tester.enterText(find.byType(TextField), 'yok böyle');
    await tester.pumpAndSettle();
    expect(find.text('Eşleşen kayıt yok'), findsOneWidget);
    await tester.tap(find.text('Filtreyi temizle'));
    await tester.pumpAndSettle();
    expect(find.text('2019 Fiat Egea'), findsOneWidget);
  });

  testWidgets('the empty catalog offers the sector pack to admins', (tester) async {
    setSize(tester, 360);
    await tester.pumpWidget(app(const ResourcesTab()));
    await tester.pumpAndSettle();
    expect(find.text('Kataloğunuzu kurun'), findsOneWidget);
    expect(find.text('Sektör paketi kur'), findsOneWidget);
    await tester.tap(find.text('Sektör paketi kur'));
    await tester.pumpAndSettle();
    expect(find.text('Oto galeri'), findsOneWidget);
    expect(find.text('Randevu'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('leads sit in stage columns and move through the card menu', (tester) async {
    setSize(tester, 1280);
    final repository = FakeCatalogRepository();
    await tester.pumpWidget(app(const LeadsTab(), repository: repository));
    await tester.pumpAndSettle();
    for (final title in ['Yeni', 'İletişimde', 'Kazanıldı', 'Kaybedildi']) {
      expect(find.text(title), findsOneWidget);
    }
    expect(find.text('5 TALEP · 2 YENİ'), findsOneWidget);
    expect(badge('Asistandan'), findsNWidgets(3));
    expect(badge('Ekipten'), findsNWidgets(2));
    expect(find.textContaining('YARIN · '), findsOneWidget);
    expect(find.text('+90 555 111 00 01'), findsOneWidget);

    await tester.tap(find.byTooltip('Durumu değiştir').first);
    await tester.pumpAndSettle();
    expect(find.text('Yeni olarak işaretle'), findsNothing, reason: 'the current stage is not offered');
    await tester.tap(find.text('İletişimde olarak işaretle'));
    await tester.pumpAndSettle();
    expect(repository.leadStatuses, [('1', 'contacted')]);

    await tester.tap(find.text('Kredi').first);
    await tester.pumpAndSettle();
    expect(find.text('Müşteri 2'), findsOneWidget);
    expect(find.text('Müşteri 1'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a live hold is confirmed from its card; cancelling asks first', (tester) async {
    setSize(tester, 360, 1400);
    final repository = FakeCatalogRepository();
    await tester.pumpWidget(app(const BookingsTab(), repository: repository, types: [roomType]));
    await tester.pumpAndSettle();
    expect(find.text('BUGÜN'), findsOneWidget);
    expect(find.textContaining('Son onay saati'), findsOneWidget);
    expect(find.byType(FilledButton), findsOneWidget, reason: 'only "Rezervasyon ekle" is primary');

    await tester.tap(find.text('Onayla'));
    await tester.pumpAndSettle();
    expect(repository.bookingStatuses, [('b1', 'confirmed')]);

    await tester.tap(find.text('Onay bekleyen'));
    await tester.pumpAndSettle();
    expect(find.text('Mehmet Kaya'), findsNothing, reason: 'expired holds are not waiting');

    await tester.tap(find.text('İptal et').first);
    await tester.pumpAndSettle();
    expect(find.text('Rezervasyon iptal edilsin mi?'), findsOneWidget);
    await tester.tap(find.text('Vazgeç'));
    await tester.pumpAndSettle();
    expect(repository.bookingStatuses, hasLength(1));
  });
}
