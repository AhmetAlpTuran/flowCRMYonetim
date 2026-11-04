import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/request_id.dart';
import '../../contacts/data/contact_csv.dart';
import '../../tenancy/providers/tenant_providers.dart';
import '../data/catalog_repository.dart';
import '../models/catalog_models.dart';
import '../providers/catalog_providers.dart';
import '../widgets/industry_pack_sheet.dart';

String _day(DateTime value) {
  final d = value.toLocal();
  String two(int n) => n.toString().padLeft(2, '0');
  return '${two(d.day)}.${two(d.month)}.${d.year}';
}

String _time(DateTime value) {
  final d = value.toLocal();
  String two(int n) => n.toString().padLeft(2, '0');
  return '${two(d.hour)}:${two(d.minute)}';
}

void _snack(BuildContext context, String text) =>
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));

/// Catalog module: items (rooms, vehicles, services), bookings and leads.
class CatalogScreen extends StatelessWidget {
  const CatalogScreen({super.key});

  @override
  Widget build(BuildContext context) => const DefaultTabController(
        length: 3,
        child: Column(children: [
          TabBar(tabs: [
            Tab(text: 'Kayıtlar'),
            Tab(text: 'Rezervasyonlar'),
            Tab(text: 'Talepler'),
          ]),
          Expanded(
            child: TabBarView(children: [
              ResourcesTab(),
              BookingsTab(),
              LeadsTab(),
            ]),
          ),
        ]),
      );
}

// --- Items -------------------------------------------------------------------

class ResourcesTab extends ConsumerWidget {
  const ResourcesTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final types = ref.watch(resourceTypesProvider);
    final resources = ref.watch(resourcesProvider);
    return types.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (_, __) => _Retry(onRetry: () => ref.invalidate(resourceTypesProvider)),
      data: (typeList) {
        if (typeList.isEmpty) return const _NoTypes();
        final items = resources.valueOrNull ?? const <Resource>[];
        return ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
          children: [
            Wrap(spacing: 8, runSpacing: 8, children: [
              for (final type in typeList)
                FilledButton.tonalIcon(
                  onPressed: () => _openResource(context, type, null),
                  icon: const Icon(Icons.add),
                  label: Text('${type.name} ekle'),
                ),
              TextButton.icon(
                onPressed: () => _addType(context, ref, typeList),
                icon: const Icon(Icons.category_outlined),
                label: const Text('Tür ekle'),
              ),
            ]),
            const SizedBox(height: 12),
            if (resources.isLoading) const LinearProgressIndicator(minHeight: 2),
            if (resources.hasError)
              _Retry(onRetry: () => ref.invalidate(resourcesProvider)),
            for (final type in typeList) ...[
              const SizedBox(height: 8),
              Text(type.name, style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 4),
              if (!items.any((r) => r.typeId == type.id))
                Text('Henüz kayıt yok.', style: Theme.of(context).textTheme.bodySmall),
              for (final item in items.where((r) => r.typeId == type.id))
                Card(
                  child: ListTile(
                    onTap: () => _openResource(context, type, item),
                    title: Text(item.name),
                    subtitle: Text(_summary(type, item)),
                    trailing: Text(resourceStatusLabels[item.status] ?? item.status,
                        style: Theme.of(context).textTheme.labelSmall),
                  ),
                ),
            ],
          ],
        );
      },
    );
  }

  String _summary(ResourceType type, Resource item) {
    final parts = <String>[formatPrice(item.price, item.currency)];
    if (type.bookable && type.bookingUnit == 'night') parts[0] = '${parts[0]} / gece';
    for (final field in type.fields.take(3)) {
      final value = item.attributes[field.key];
      if (value == null) continue;
      parts.add(value is bool ? (value ? field.label : '') : '$value');
    }
    return parts.where((p) => p.isNotEmpty).join(' · ');
  }

  Future<void> _openResource(BuildContext context, ResourceType type, Resource? item) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => ResourceEditorSheet(type: type, resource: item),
    );
  }

  Future<void> _addType(BuildContext context, WidgetRef ref, List<ResourceType> existing) async {
    final tenant = ref.read(selectedTenantProvider);
    final available = [
      for (final p in resourceTypePresets)
        if (!existing.any((t) => t.key == p.key)) p,
    ];
    if (tenant == null) return;
    if (available.isEmpty) {
      _snack(context, 'Tüm hazır türler zaten ekli.');
      return;
    }
    final preset = await showDialog<ResourceTypePreset>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('Ne tür kayıtlar tutacaksınız?'),
        children: [
          for (final p in available)
            SimpleDialogOption(
              onPressed: () => Navigator.of(context).pop(p),
              child: ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(p.name),
                subtitle: Text(p.description),
              ),
            ),
        ],
      ),
    );
    if (preset == null) return;
    try {
      await ref.read(catalogRepositoryProvider).createTypeFromPreset(tenant.id, preset);
      ref.invalidate(resourceTypesProvider);
    } catch (error) {
      if (context.mounted) _snack(context, catalogErrorMessage(error));
    }
  }
}

class _NoTypes extends ConsumerWidget {
  const _NoTypes();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ListView(padding: const EdgeInsets.all(24), children: [
      Text('Botunuzun müşterilere sunacağı kayıtları burada tutarsınız.',
          style: Theme.of(context).textTheme.titleMedium),
      const SizedBox(height: 12),
      const Align(alignment: Alignment.centerLeft, child: IndustryPackButton()),
      const SizedBox(height: 12),
      const Text('veya yalnızca bir kayıt türü ekleyin:'),
      const SizedBox(height: 12),
      for (final preset in resourceTypePresets)
        Card(
          child: ListTile(
            title: Text(preset.name),
            subtitle: Text(preset.description),
            trailing: const Icon(Icons.add),
            onTap: () async {
              final tenant = ref.read(selectedTenantProvider);
              if (tenant == null) return;
              try {
                await ref.read(catalogRepositoryProvider).createTypeFromPreset(tenant.id, preset);
                ref.invalidate(resourceTypesProvider);
              } catch (error) {
                if (context.mounted) _snack(context, catalogErrorMessage(error));
              }
            },
          ),
        ),
    ]);
  }
}

/// Edits one item; attribute inputs follow the type's field definitions.
class ResourceEditorSheet extends ConsumerStatefulWidget {
  const ResourceEditorSheet({super.key, required this.type, this.resource});

  final ResourceType type;
  final Resource? resource;

  @override
  ConsumerState<ResourceEditorSheet> createState() => _ResourceEditorSheetState();
}

class _ResourceEditorSheetState extends ConsumerState<ResourceEditorSheet> {
  final _formKey = GlobalKey<FormState>();
  late final _name = TextEditingController(text: widget.resource?.name ?? '');
  late final _description = TextEditingController(text: widget.resource?.description ?? '');
  late final _price = TextEditingController(
      text: widget.resource?.price == null ? '' : widget.resource!.price!.round().toString());
  late final _capacity =
      TextEditingController(text: widget.resource?.capacity?.toString() ?? '');
  late String _status = widget.resource?.status ?? 'active';
  late final Map<String, dynamic> _attributes = {...?widget.resource?.attributes};
  late final Map<String, TextEditingController> _text = {
    for (final f in widget.type.fields)
      if (f.type == 'text' || f.type == 'number')
        f.key: TextEditingController(text: _attributes[f.key]?.toString() ?? ''),
  };
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    for (final c in [_name, _description, _price, _capacity, ..._text.values]) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final type = widget.type;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Form(
          key: _formKey,
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text(widget.resource == null ? '${type.name} ekle' : '${type.name} düzenle',
                style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 12),
            TextFormField(
              controller: _name,
              maxLength: 200,
              decoration: const InputDecoration(labelText: 'Ad'),
              validator: (v) => (v?.trim().isEmpty ?? true) ? 'Ad girin.' : null,
            ),
            Row(children: [
              Expanded(
                child: TextFormField(
                  controller: _price,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    labelText: type.bookingUnit == 'night' ? 'Gecelik fiyat (₺)' : 'Fiyat (₺)',
                  ),
                  validator: (v) => (v?.trim().isEmpty ?? true) || double.tryParse(v!.trim()) != null
                      ? null
                      : 'Sayı girin.',
                ),
              ),
              if (type.bookable) ...[
                const SizedBox(width: 12),
                Expanded(
                  child: TextFormField(
                    controller: _capacity,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'Kapasite (kişi)'),
                    validator: (v) =>
                        (v?.trim().isEmpty ?? true) || int.tryParse(v!.trim()) != null ? null : 'Sayı girin.',
                  ),
                ),
              ],
            ]),
            const SizedBox(height: 8),
            for (final field in type.fields) _fieldInput(field),
            TextFormField(
              controller: _description,
              maxLines: 3,
              maxLength: 4000,
              decoration: const InputDecoration(
                labelText: 'Açıklama',
                helperText: 'Bot müşterilere bu bilgiyi kullanarak yanıt verir.',
              ),
            ),
            DropdownButtonFormField<String>(
              initialValue: _status,
              decoration: const InputDecoration(labelText: 'Durum'),
              items: [
                for (final entry in resourceStatusLabels.entries)
                  DropdownMenuItem(value: entry.key, child: Text(entry.value)),
              ],
              onChanged: (value) => setState(() => _status = value ?? _status),
            ),
            if (_error != null) ...[
              const SizedBox(height: 8),
              Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
            ],
            const SizedBox(height: 16),
            Wrap(alignment: WrapAlignment.end, spacing: 8, children: [
              if (widget.resource != null)
                TextButton(
                  onPressed: _busy ? null : _delete,
                  child: const Text('Sil'),
                ),
              TextButton(
                onPressed: _busy ? null : () => Navigator.of(context).pop(),
                child: const Text('Kapat'),
              ),
              FilledButton(
                onPressed: _busy ? null : _save,
                child: const Text('Kaydet'),
              ),
            ]),
          ]),
        ),
      ),
    );
  }

  Widget _fieldInput(ResourceField field) {
    switch (field.type) {
      case 'boolean':
        return SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(field.label),
          value: _attributes[field.key] == true,
          onChanged: (value) => setState(() => _attributes[field.key] = value),
        );
      case 'select':
        final current = _attributes[field.key];
        return DropdownButtonFormField<String>(
          initialValue: field.options.contains(current) ? current as String : null,
          decoration: InputDecoration(labelText: field.label),
          items: [
            for (final option in field.options)
              DropdownMenuItem(value: option, child: Text(option)),
          ],
          onChanged: (value) => setState(() => _attributes[field.key] = value),
        );
      default:
        return TextFormField(
          controller: _text[field.key],
          keyboardType: field.type == 'number' ? TextInputType.number : TextInputType.text,
          decoration: InputDecoration(labelText: field.label),
          validator: (v) => field.type == 'number' &&
                  (v?.trim().isNotEmpty ?? false) &&
                  num.tryParse(v!.trim()) == null
              ? 'Sayı girin.'
              : null,
        );
    }
  }

  Map<String, dynamic> _collectAttributes() {
    final values = <String, dynamic>{};
    for (final field in widget.type.fields) {
      if (field.type == 'text' || field.type == 'number') {
        final text = _text[field.key]!.text.trim();
        if (text.isEmpty) continue;
        values[field.key] = field.type == 'number' ? num.parse(text) : text;
      } else if (_attributes[field.key] != null) {
        values[field.key] = _attributes[field.key];
      }
    }
    return values;
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final tenant = ref.read(selectedTenantProvider);
    if (tenant == null) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(catalogRepositoryProvider).saveResource(
            tenantId: tenant.id,
            id: widget.resource?.id,
            typeId: widget.type.id,
            name: _name.text,
            description: _description.text,
            attributes: _collectAttributes(),
            price: double.tryParse(_price.text.trim()),
            capacity: int.tryParse(_capacity.text.trim()),
            status: _status,
          );
      ref.invalidate(resourcesProvider);
      if (mounted) Navigator.of(context).pop();
    } catch (error) {
      if (mounted) setState(() => _error = catalogErrorMessage(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _delete() async {
    final tenant = ref.read(selectedTenantProvider);
    if (tenant == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Kayıt silinsin mi?'),
        content: const Text('Bu kayda ait rezervasyonlar da silinir. Satılan veya kullanılmayan kayıtlar için durumu değiştirmeniz yeterlidir.'),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Vazgeç')),
          FilledButton(onPressed: () => Navigator.of(context).pop(true), child: const Text('Sil')),
        ],
      ),
    );
    if (confirmed != true) return;
    setState(() => _busy = true);
    try {
      await ref.read(catalogRepositoryProvider).deleteResource(tenant.id, widget.resource!.id);
      ref.invalidate(resourcesProvider);
      ref.invalidate(bookingsProvider);
      if (mounted) Navigator.of(context).pop();
    } catch (error) {
      if (mounted) setState(() => _error = catalogErrorMessage(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }
}

// --- Bookings ----------------------------------------------------------------

class BookingsTab extends ConsumerWidget {
  const BookingsTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bookings = ref.watch(bookingsProvider);
    final hasBookable =
        ref.watch(resourceTypesProvider).valueOrNull?.any((t) => t.bookable) ?? false;
    final now = DateTime.now();
    return RefreshIndicator(
      onRefresh: () => ref.refresh(bookingsProvider.future),
      child: ListView(padding: const EdgeInsets.fromLTRB(16, 16, 16, 32), children: [
        Align(
          alignment: Alignment.centerLeft,
          child: FilledButton.tonalIcon(
            onPressed: hasBookable
                ? () => showModalBottomSheet<void>(
                      context: context,
                      isScrollControlled: true,
                      useSafeArea: true,
                      builder: (_) => const BookingEditorSheet(),
                    )
                : null,
            icon: const Icon(Icons.event_available),
            label: const Text('Rezervasyon ekle'),
          ),
        ),
        if (!hasBookable)
          const Padding(
            padding: EdgeInsets.only(top: 8),
            child: Text('Rezervasyon için önce Oda veya Hizmet türünde kayıt ekleyin.'),
          ),
        const SizedBox(height: 8),
        ...bookings.when(
          loading: () => [const LinearProgressIndicator(minHeight: 2)],
          error: (_, __) => [_Retry(onRetry: () => ref.invalidate(bookingsProvider))],
          data: (items) => items.isEmpty
              ? [const Padding(padding: EdgeInsets.all(16), child: Text('Yaklaşan rezervasyon yok.'))]
              : [for (final booking in items) _BookingCard(booking: booking, now: now)],
        ),
      ]),
    );
  }
}

class _BookingCard extends ConsumerWidget {
  const _BookingCard({required this.booking, required this.now});
  final Booking booking;
  final DateTime now;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final hold = booking.status == 'hold';
    final live = booking.isLiveHold(now);
    final sameDay = _day(booking.start) == _day(booking.end);
    final when = sameDay
        ? '${_day(booking.start)} ${_time(booking.start)}–${_time(booking.end)}'
        : '${_day(booking.start)} → ${_day(booking.end)}';
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(child: Text(booking.resourceName, style: theme.textTheme.titleSmall)),
            Text(
              hold ? (live ? 'Ön rezervasyon' : 'Süresi doldu') : 'Onaylı',
              style: TextStyle(
                color: hold ? (live ? theme.colorScheme.tertiary : theme.colorScheme.error) : Colors.green.shade700,
                fontSize: 12,
              ),
            ),
          ]),
          Text(when),
          if (booking.customerName != null || booking.customerPhone != null)
            Text([
              booking.customerName,
              if (booking.customerPhone != null) '+${booking.customerPhone}',
            ].whereType<String>().join(' · '), style: theme.textTheme.bodySmall),
          if (booking.source == 'bot')
            Text('Bot tarafından oluşturuldu', style: theme.textTheme.bodySmall),
          if (hold && live)
            Text('Onay bekleniyor: ${_time(booking.holdExpiresAt!)} saatine kadar',
                style: theme.textTheme.bodySmall),
          Align(
            alignment: Alignment.centerRight,
            child: Wrap(spacing: 8, children: [
              TextButton(
                onPressed: () => _set(context, ref, 'cancelled'),
                child: const Text('İptal et'),
              ),
              if (hold && live)
                FilledButton(
                  onPressed: () => _set(context, ref, 'confirmed'),
                  child: const Text('Onayla'),
                ),
            ]),
          ),
        ]),
      ),
    );
  }

  Future<void> _set(BuildContext context, WidgetRef ref, String status) async {
    final tenant = ref.read(selectedTenantProvider);
    if (tenant == null) return;
    if (status == 'cancelled') {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Rezervasyon iptal edilsin mi?'),
          content: const Text('Müşteriye otomatik mesaj gönderilmez; gerekiyorsa konuşmadan bilgilendirin.'),
          actions: [
            TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Vazgeç')),
            FilledButton(onPressed: () => Navigator.of(context).pop(true), child: const Text('İptal et')),
          ],
        ),
      );
      if (confirmed != true) return;
    }
    try {
      await ref.read(catalogRepositoryProvider).setBookingStatus(tenant.id, booking.id, status);
    } catch (error) {
      if (context.mounted) _snack(context, catalogErrorMessage(error));
    }
    ref.invalidate(bookingsProvider);
  }
}

/// Agent booking (phone or walk-in). The database refuses overlaps.
class BookingEditorSheet extends ConsumerStatefulWidget {
  const BookingEditorSheet({super.key});

  @override
  ConsumerState<BookingEditorSheet> createState() => _BookingEditorSheetState();
}

class _BookingEditorSheetState extends ConsumerState<BookingEditorSheet> {
  final _name = TextEditingController();
  final _phone = TextEditingController();
  final _note = TextEditingController();
  final _requestKey = newRequestId();
  String? _resourceId;
  DateTimeRange? _range;
  DateTime? _hourDay;
  TimeOfDay _start = const TimeOfDay(hour: 10, minute: 0);
  int _hours = 1;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    _note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final types = ref.watch(resourceTypesProvider).valueOrNull ?? const [];
    final bookableTypes = {for (final t in types) if (t.bookable) t.id: t};
    final resources = [
      for (final r in ref.watch(resourcesProvider).valueOrNull ?? const <Resource>[])
        if (bookableTypes.containsKey(r.typeId) && r.status == 'active') r,
    ];
    final selected = resources.where((r) => r.id == _resourceId).firstOrNull;
    final unit = selected == null ? null : bookableTypes[selected.typeId]!.bookingUnit;
    final now = DateTime.now();
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text('Rezervasyon ekle', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            initialValue: _resourceId,
            decoration: const InputDecoration(labelText: 'Kayıt'),
            items: [
              for (final r in resources) DropdownMenuItem(value: r.id, child: Text(r.name)),
            ],
            onChanged: (value) => setState(() {
              _resourceId = value;
              _range = null;
              _hourDay = null;
            }),
          ),
          const SizedBox(height: 12),
          if (unit == 'hour') ...[
            OutlinedButton(
              onPressed: () async {
                final picked = await showDatePicker(
                  context: context,
                  firstDate: DateTime(now.year, now.month, now.day),
                  lastDate: now.add(const Duration(days: 365)),
                );
                if (picked != null) setState(() => _hourDay = picked);
              },
              child: Text(_hourDay == null ? 'Tarih seç' : _day(_hourDay!)),
            ),
            Row(children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () async {
                    final picked = await showTimePicker(context: context, initialTime: _start);
                    if (picked != null) setState(() => _start = picked);
                  },
                  child: Text('Başlangıç ${_start.format(context)}'),
                ),
              ),
              const SizedBox(width: 8),
              DropdownButton<int>(
                value: _hours,
                items: [for (var h = 1; h <= 8; h++) DropdownMenuItem(value: h, child: Text('$h saat'))],
                onChanged: (value) => setState(() => _hours = value ?? 1),
              ),
            ]),
          ] else if (unit != null)
            OutlinedButton(
              onPressed: () async {
                final picked = await showDateRangePicker(
                  context: context,
                  firstDate: DateTime(now.year, now.month, now.day),
                  lastDate: now.add(const Duration(days: 365)),
                  helpText: unit == 'night' ? 'Giriş ve çıkış tarihi' : 'Tarih aralığı',
                );
                if (picked != null) setState(() => _range = picked);
              },
              child: Text(_range == null
                  ? (unit == 'night' ? 'Giriş / çıkış tarihi seç' : 'Tarih seç')
                  : '${_day(_range!.start)} → ${_day(_range!.end)}'),
            ),
          const SizedBox(height: 12),
          TextField(controller: _name, decoration: const InputDecoration(labelText: 'Müşteri adı')),
          TextField(
            controller: _phone,
            keyboardType: TextInputType.phone,
            decoration: const InputDecoration(labelText: 'Telefon (isteğe bağlı)'),
          ),
          TextField(controller: _note, decoration: const InputDecoration(labelText: 'Not')),
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
          ],
          const SizedBox(height: 16),
          Wrap(alignment: WrapAlignment.end, spacing: 8, children: [
            TextButton(onPressed: _busy ? null : () => Navigator.of(context).pop(), child: const Text('Vazgeç')),
            FilledButton(
              onPressed: _busy || selected == null || (unit == 'hour' ? _hourDay == null : _range == null)
                  ? null
                  : () => _save(selected, unit!),
              child: const Text('Kaydet'),
            ),
          ]),
        ]),
      ),
    );
  }

  Future<void> _save(Resource resource, String unit) async {
    final tenant = ref.read(selectedTenantProvider);
    if (tenant == null) return;
    final phoneText = _phone.text.trim();
    final phone = phoneText.isEmpty ? null : normalizeContactPhone(phoneText);
    if (phoneText.isNotEmpty && phone == null) {
      setState(() => _error = 'Geçerli bir telefon numarası girin.');
      return;
    }
    final (start, end) = unit == 'hour'
        ? bookingPeriod(unit: unit, firstDay: _hourDay!, lastDay: _hourDay!, startTime: _start, hours: _hours)
        : bookingPeriod(unit: unit, firstDay: _range!.start, lastDay: _range!.end);
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(catalogRepositoryProvider).createBooking(
            tenantId: tenant.id,
            resourceId: resource.id,
            start: start,
            end: end,
            customerName: _name.text.trim().isEmpty ? null : _name.text.trim(),
            customerPhone: phone,
            note: _note.text.trim().isEmpty ? null : _note.text.trim(),
            requestKey: _requestKey,
          );
      ref.invalidate(bookingsProvider);
      if (mounted) Navigator.of(context).pop();
    } catch (error) {
      if (mounted) setState(() => _error = catalogErrorMessage(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }
}

// --- Leads -------------------------------------------------------------------

class LeadsTab extends ConsumerWidget {
  const LeadsTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final leads = ref.watch(leadsProvider);
    return RefreshIndicator(
      onRefresh: () => ref.refresh(leadsProvider.future),
      child: leads.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, __) => _Retry(onRetry: () => ref.invalidate(leadsProvider)),
        data: (items) => items.isEmpty
            ? ListView(children: const [
                Padding(
                  padding: EdgeInsets.all(24),
                  child: Text('Henüz talep yok. Bot test sürüşü, takas veya bilgi taleplerini buraya kaydeder.'),
                ),
              ])
            : ListView(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
                children: [for (final lead in items) _LeadCard(lead: lead)],
              ),
      ),
    );
  }
}

class _LeadCard extends ConsumerWidget {
  const _LeadCard({required this.lead});
  final Lead lead;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final note = lead.details['note'];
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(
              child: Text(leadKindLabels[lead.kind] ?? lead.kind, style: theme.textTheme.titleSmall),
            ),
            DropdownButton<String>(
              value: lead.status,
              underline: const SizedBox.shrink(),
              items: [
                for (final entry in leadStatusLabels.entries)
                  DropdownMenuItem(value: entry.key, child: Text(entry.value)),
              ],
              onChanged: (value) async {
                final tenant = ref.read(selectedTenantProvider);
                if (value == null || tenant == null) return;
                try {
                  await ref.read(catalogRepositoryProvider).setLeadStatus(tenant.id, lead.id, value);
                } catch (error) {
                  if (context.mounted) _snack(context, catalogErrorMessage(error));
                }
                ref.invalidate(leadsProvider);
              },
            ),
          ]),
          Text([
            lead.customerName,
            if (lead.customerPhone != null) '+${lead.customerPhone}',
          ].whereType<String>().join(' · ')),
          if (lead.resourceName != null) Text(lead.resourceName!, style: theme.textTheme.bodySmall),
          if (lead.preferredAt != null)
            Text('Tercih edilen zaman: ${_day(lead.preferredAt!)} ${_time(lead.preferredAt!)}',
                style: theme.textTheme.bodySmall),
          if (note is String && note.isNotEmpty) Text(note, style: theme.textTheme.bodySmall),
          Text('${_day(lead.createdAt)} · ${lead.source == 'bot' ? 'Bot' : 'Temsilci'}',
              style: theme.textTheme.labelSmall),
        ]),
      ),
    );
  }
}

class _Retry extends StatelessWidget {
  const _Retry({required this.onRetry});
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Center(
        child: TextButton(onPressed: onRetry, child: const Text('Yüklenemedi. Tekrar dene')),
      );
}
