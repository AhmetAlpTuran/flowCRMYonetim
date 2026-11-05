import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/request_id.dart';
import '../../../ui/ui.dart' hide formatPrice;
import '../../contacts/data/contact_csv.dart';
import '../../tenancy/providers/tenant_providers.dart';
import '../data/catalog_repository.dart';
import '../models/catalog_models.dart';
import '../providers/catalog_providers.dart';
import '../widgets/catalog_layout.dart';

enum _BookingFilter { all, pending, confirmed }

/// Katalog → Rezervasyonlar: upcoming stays and appointments, soonest first.
class BookingsTab extends ConsumerStatefulWidget {
  const BookingsTab({super.key});

  @override
  ConsumerState<BookingsTab> createState() => _BookingsTabState();
}

class _BookingsTabState extends ConsumerState<BookingsTab> {
  _BookingFilter _filter = _BookingFilter.all;

  @override
  Widget build(BuildContext context) {
    final bookings = ref.watch(bookingsProvider);
    final hasBookable = ref.watch(resourceTypesProvider).valueOrNull?.any((t) => t.bookable) ?? false;
    final now = DateTime.now();
    final items = bookings.valueOrNull ?? const <Booking>[];
    final pending = items.where((b) => b.isLiveHold(now)).length;
    final confirmed = items.where((b) => b.status == 'confirmed').length;
    final visible = [
      for (final booking in items)
        if (switch (_filter) {
          _BookingFilter.all => true,
          _BookingFilter.pending => booking.isLiveHold(now),
          _BookingFilter.confirmed => booking.status == 'confirmed',
        })
          booking,
    ];

    final slivers = <Widget>[
      sliverBox(PageToolbar(
        leading: items.isEmpty
            ? null
            : FilterChipsRow<_BookingFilter>(
                options: [
                  FilterOption(_BookingFilter.all, 'Tümü', count: items.length),
                  FilterOption(_BookingFilter.pending, 'Onay bekleyen', count: pending),
                  FilterOption(_BookingFilter.confirmed, 'Onaylı', count: confirmed),
                ],
                selected: _filter,
                onSelected: (value) => setState(() => _filter = value),
              ),
        actions: [
          FilledButton.icon(
            onPressed: hasBookable
                ? () => showCatalogSheet<void>(context, const BookingEditorSheet())
                : null,
            icon: const Icon(Icons.event_available, size: 18),
            label: const Text('Rezervasyon ekle'),
          ),
        ],
      )),
      if (!hasBookable) ...[
        sliverGap(FlowSpace.md),
        sliverBox(const CatalogNotice(
          'Rezervasyon almak için önce Oda veya Hizmet türünde bir kayıt ekleyin.',
          tone: FlowTone.info,
        )),
      ],
      sliverGap(FlowSpace.xl - 4),
      ...bookings.when(
        loading: () => [sliverBox(const LoadingList())],
        error: (_, __) => [
          sliverBox(ErrorState(
            title: 'Rezervasyonlar yüklenemedi',
            onRetry: () => ref.invalidate(bookingsProvider),
          )),
        ],
        data: (_) {
          if (items.isEmpty) {
            return [
              sliverBox(const EmptyState(
                icon: Icons.event_available_outlined,
                title: 'Yaklaşan rezervasyon yok',
                message: 'Asistanın aldığı ön rezervasyonlar ve sizin eklediğiniz rezervasyonlar burada görünür.',
              )),
            ];
          }
          if (visible.isEmpty) {
            return [
              sliverBox(EmptyState(
                compact: true,
                icon: Icons.filter_alt_off_outlined,
                title: 'Bu filtrede rezervasyon yok',
                action: TextButton(
                  onPressed: () => setState(() => _filter = _BookingFilter.all),
                  child: const Text('Tümünü göster'),
                ),
              )),
            ];
          }
          return [
            SliverList.separated(
              itemCount: visible.length,
              separatorBuilder: (_, __) => const SizedBox(height: FlowSpace.md),
              itemBuilder: (context, index) =>
                  _BookingCard(key: ValueKey(visible[index].id), booking: visible[index], now: now),
            ),
          ];
        },
      ),
    ];
    return CatalogScrollPage(onRefresh: () => ref.refresh(bookingsProvider.future), slivers: slivers);
  }
}

/// "14:00–15:00", "17 Kas – 19 Kas" for whole days, else "17 Kas 14:00 → 19 Kas 11:00".
String bookingSpan(DateTime start, DateTime end) {
  final s = start.toLocal();
  final e = end.toLocal();
  bool sameDay(DateTime a, DateTime b) => a.year == b.year && a.month == b.month && a.day == b.day;
  if (sameDay(s, e)) return '${formatClock(s)}–${formatClock(e)}';
  final midnight = s.hour == 0 && s.minute == 0 && e.hour == 0 && e.minute == 0;
  if (midnight) {
    final last = e.subtract(const Duration(days: 1));
    return sameDay(s, last) ? 'Tüm gün' : '${shortDate(s)} – ${shortDate(last)}';
  }
  return '${shortDate(s)} ${formatClock(s)} → ${shortDate(e)} ${formatClock(e)}';
}

class _BookingCard extends ConsumerStatefulWidget {
  const _BookingCard({super.key, required this.booking, required this.now});

  final Booking booking;
  final DateTime now;

  @override
  ConsumerState<_BookingCard> createState() => _BookingCardState();
}

class _BookingCardState extends ConsumerState<_BookingCard> {
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    final booking = widget.booking;
    final c = FlowColors.of(context);
    final theme = Theme.of(context);
    final hold = booking.status == 'hold';
    final live = booking.isLiveHold(widget.now);
    final (label, tone) = hold
        ? (live ? ('Ön rezervasyon', FlowTone.warning) : ('Süresi doldu', FlowTone.danger))
        : ('Onaylı', FlowTone.accent);
    final source = sourceBadge(booking.source);
    final name = booking.customerName?.trim() ?? '';
    final phone = booking.customerPhone;
    final note = booking.note?.trim();

    return Container(
      padding: const EdgeInsets.all(FlowSpace.lg),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: FlowRadius.cardAll,
        border: Border.all(color: c.border),
      ),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _DateBlock(time: booking.start, now: widget.now),
        const SizedBox(width: 14),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Wrap(spacing: 6, runSpacing: 6, children: [
              StatusBadge(label, tone: tone),
              if (source != null) source,
            ]),
            const SizedBox(height: FlowSpace.sm),
            Text(
              booking.resourceName.isEmpty ? 'Kayıt' : booking.resourceName,
              style: theme.textTheme.titleMedium,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 2),
            Text(bookingSpan(booking.start, booking.end), style: FlowText.mono(context, size: 13, color: c.text)),
            if (name.isNotEmpty || phone != null) ...[
              const SizedBox(height: 6),
              Text.rich(
                TextSpan(children: [
                  if (name.isNotEmpty) TextSpan(text: name),
                  if (name.isNotEmpty && phone != null) const TextSpan(text: ' · '),
                  // Non-breaking spaces keep the number on one line.
                  if (phone != null)
                    TextSpan(text: formatPhone(phone).replaceAll(' ', '\u00A0'), style: FlowText.mono(context, size: 13)),
                ]),
                style: theme.textTheme.bodyMedium?.copyWith(color: c.muted),
              ),
            ],
            if (live) ...[
              const SizedBox(height: 4),
              Text.rich(
                TextSpan(children: [
                  const TextSpan(text: 'Son onay saati '),
                  TextSpan(
                    text: formatClock(booking.holdExpiresAt!),
                    style: FlowText.mono(context, size: 13, color: c.warning, weight: FontWeight.w600),
                  ),
                ]),
                style: theme.textTheme.bodySmall,
              ),
            ],
            if (note != null && note.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(note, style: theme.textTheme.bodySmall, maxLines: 3, overflow: TextOverflow.ellipsis),
            ],
            const SizedBox(height: FlowSpace.md),
            SizedBox(
              width: double.infinity,
              child: Wrap(alignment: WrapAlignment.end, spacing: FlowSpace.sm, runSpacing: FlowSpace.sm, children: [
                TextButton(
                  onPressed: _busy ? null : () => _set('cancelled'),
                  style: TextButton.styleFrom(foregroundColor: c.muted),
                  child: const Text('İptal et'),
                ),
                if (live)
                  OutlinedButton.icon(
                    onPressed: _busy ? null : () => _set('confirmed'),
                    icon: const Icon(Icons.check, size: 18),
                    label: const Text('Onayla'),
                  ),
              ]),
            ),
          ]),
        ),
      ]),
    );
  }

  Future<void> _set(String status) async {
    final tenant = ref.read(selectedTenantProvider);
    if (tenant == null) return;
    if (status == 'cancelled') {
      final confirmed = await confirmAction(
        context,
        title: 'Rezervasyon iptal edilsin mi?',
        message: 'Müşteriye otomatik mesaj gönderilmez; gerekirse sohbetten bilgilendirin.',
        confirmLabel: 'İptal et',
        destructive: true,
      );
      if (!confirmed || !mounted) return;
    }
    setState(() => _busy = true);
    String? failure;
    try {
      await ref.read(catalogRepositoryProvider).setBookingStatus(tenant.id, widget.booking.id, status);
    } catch (error) {
      failure = catalogErrorMessage(error);
    }
    if (!mounted) return;
    showAppSnack(
      context,
      failure ?? (status == 'confirmed' ? 'Rezervasyon onaylandı.' : 'Rezervasyon iptal edildi.'),
      error: failure != null,
    );
    setState(() => _busy = false);
    ref.invalidate(bookingsProvider);
  }
}

/// Day number, short month and weekday ("BUGÜN" for today) in mono.
class _DateBlock extends StatelessWidget {
  const _DateBlock({required this.time, required this.now});

  final DateTime time;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final c = FlowColors.of(context);
    final offset = dayOffset(time, now: now);
    final today = offset == 0;
    final local = time.toLocal();
    final caption = switch (offset) { 0 => 'Bugün', 1 => 'Yarın', _ => shortWeekday(time) };
    final ink = today ? c.accentText : c.text;
    return Semantics(
      label: '${formatDate(time)}, ${formatWeekday(time)}',
      excludeSemantics: true,
      child: Container(
        width: 56,
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: today ? c.accentSoft : c.raised,
          borderRadius: FlowRadius.controlAll,
          border: Border.all(color: today ? c.limeEdge : c.border),
        ),
        child: Column(children: [
          Text('${local.day}', style: FlowText.number(context, size: 24, color: ink)),
          const SizedBox(height: 4),
          Text(upperTr(shortMonth(time)), style: FlowText.caps(context, size: 10, color: ink)),
          const SizedBox(height: 2),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(upperTr(caption), style: FlowText.caps(context, size: 9, color: today ? c.accentText : c.faint)),
          ),
        ]),
      ),
    );
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

  String _clock(TimeOfDay t) => '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    final c = FlowColors.of(context);
    final types = ref.watch(resourceTypesProvider).valueOrNull ?? const [];
    final bookableTypes = {for (final t in types) if (t.bookable) t.id: t};
    final resources = [
      for (final r in ref.watch(resourcesProvider).valueOrNull ?? const <Resource>[])
        if (bookableTypes.containsKey(r.typeId) && r.status == 'active') r,
    ];
    final selected = resources.where((r) => r.id == _resourceId).firstOrNull;
    final unit = selected == null ? null : bookableTypes[selected.typeId]!.bookingUnit;
    final now = DateTime.now();
    const gap = SizedBox(height: FlowSpace.lg);
    final ready = selected != null && (unit == 'hour' ? _hourDay != null : _range != null);

    return CatalogSheet(
      eyebrow: 'Rezervasyonlar',
      title: 'Rezervasyon ekle',
      actions: [
        FilledButton(
          onPressed: _busy || !ready ? null : () => _save(selected, unit!),
          child: const Text('Kaydet'),
        ),
      ],
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        DropdownButtonFormField<String>(
          initialValue: _resourceId,
          isExpanded: true,
          decoration: InputDecoration(
            labelText: 'Kayıt',
            helperText: resources.isEmpty ? 'Yayında rezervasyon alınabilen bir kayıt yok.' : null,
          ),
          items: [
            for (final r in resources)
              DropdownMenuItem(value: r.id, child: Text(r.name, overflow: TextOverflow.ellipsis)),
          ],
          onChanged: _busy
              ? null
              : (value) => setState(() {
                    _resourceId = value;
                    _range = null;
                    _hourDay = null;
                  }),
        ),
        gap,
        if (unit == 'hour') ...[
          _PickerField(
            label: 'Tarih',
            icon: Icons.calendar_today_outlined,
            value: _hourDay == null ? null : '${formatDate(_hourDay!)}, ${formatWeekday(_hourDay!)}',
            onTap: _busy
                ? null
                : () async {
                    final picked = await showDatePicker(
                      context: context,
                      firstDate: DateTime(now.year, now.month, now.day),
                      lastDate: now.add(const Duration(days: 365)),
                    );
                    if (picked != null) setState(() => _hourDay = picked);
                  },
          ),
          gap,
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(
              child: _PickerField(
                label: 'Başlangıç',
                icon: Icons.schedule,
                value: _clock(_start),
                onTap: _busy
                    ? null
                    : () async {
                        final picked = await showTimePicker(context: context, initialTime: _start);
                        if (picked != null) setState(() => _start = picked);
                      },
              ),
            ),
            const SizedBox(width: FlowSpace.md),
            Expanded(
              child: DropdownButtonFormField<int>(
                initialValue: _hours,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Süre'),
                items: [
                  for (var h = 1; h <= 8; h++)
                    DropdownMenuItem(value: h, child: Text('$h saat', style: FlowText.mono(context, size: 15, color: c.text))),
                ],
                onChanged: _busy ? null : (value) => setState(() => _hours = value ?? 1),
              ),
            ),
          ]),
          gap,
        ] else if (unit != null) ...[
          _PickerField(
            label: unit == 'night' ? 'Giriş ve çıkış' : 'Tarihler',
            icon: Icons.date_range_outlined,
            value: _range == null ? null : '${shortDate(_range!.start)} → ${shortDate(_range!.end)}',
            onTap: _busy
                ? null
                : () async {
                    final picked = await showDateRangePicker(
                      context: context,
                      firstDate: DateTime(now.year, now.month, now.day),
                      lastDate: now.add(const Duration(days: 365)),
                      helpText: unit == 'night' ? 'Giriş ve çıkış tarihi' : 'Tarih aralığı',
                    );
                    if (picked != null) setState(() => _range = picked);
                  },
          ),
          if (unit == 'night') ...[
            const SizedBox(height: 6),
            Text('Giriş 14:00, çıkış 11:00 olarak kaydedilir.', style: Theme.of(context).textTheme.bodySmall),
          ],
          gap,
        ],
        TextField(
          controller: _name,
          readOnly: _busy,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(labelText: 'Müşteri adı'),
        ),
        gap,
        TextField(
          controller: _phone,
          readOnly: _busy,
          keyboardType: TextInputType.phone,
          style: FlowText.mono(context, size: 15, color: c.text),
          decoration: const InputDecoration(labelText: 'Telefon (isteğe bağlı)', hintText: '0555 111 22 33'),
        ),
        gap,
        TextField(
          controller: _note,
          readOnly: _busy,
          minLines: 1,
          maxLines: 3,
          decoration: const InputDecoration(labelText: 'Not'),
        ),
        if (_error != null) ...[gap, CatalogNotice(_error!)],
      ]),
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

/// A read-only field that opens a date or time picker; the value shows in mono.
class _PickerField extends StatelessWidget {
  const _PickerField({required this.label, required this.icon, required this.value, required this.onTap});

  final String label;
  final IconData icon;
  final String? value;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = FlowColors.of(context);
    return Semantics(
      button: true,
      label: label,
      value: value ?? 'Seçilmedi',
      excludeSemantics: true,
      child: InkWell(
        onTap: onTap,
        borderRadius: FlowRadius.controlAll,
        child: InputDecorator(
          isEmpty: value == null,
          decoration: InputDecoration(
            labelText: label,
            hintText: 'Seçin',
            enabled: onTap != null,
            suffixIcon: Icon(icon, size: 18),
          ),
          child: Text(
            value ?? '',
            style: FlowText.mono(context, size: 15, color: c.text),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ),
    );
  }
}
