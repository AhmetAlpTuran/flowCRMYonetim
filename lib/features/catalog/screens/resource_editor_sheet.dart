import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../ui/ui.dart' hide formatPrice;
import '../../tenancy/providers/tenant_providers.dart';
import '../data/catalog_repository.dart';
import '../models/catalog_models.dart';
import '../providers/catalog_providers.dart';
import '../widgets/catalog_layout.dart';
import '../widgets/resource_photos_editor.dart';

/// Opens the editor for a new ([resource] null) or existing item.
Future<void> openResourceEditor(BuildContext context, ResourceType type, [Resource? resource]) =>
    showCatalogSheet<void>(context, ResourceEditorSheet(type: type, resource: resource), maxWidth: 1000);

/// Edits one item: photos first, then price, the type's own fields, the description
/// the assistant uses, and the status. Attribute inputs follow the type's fields.
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
  late final _capacity = TextEditingController(text: widget.resource?.capacity?.toString() ?? '');
  late String _status = widget.resource?.status ?? 'active';
  late final Map<String, dynamic> _attributes = {...?widget.resource?.attributes};
  late final Map<String, TextEditingController> _text = {
    for (final f in widget.type.fields)
      if (f.type == 'text' || f.type == 'number') f.key: TextEditingController(text: _attributes[f.key]?.toString() ?? ''),
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
    final resource = widget.resource;
    final tenant = ref.watch(selectedTenantProvider);
    final c = FlowColors.of(context);
    final status = resourceStatusLabels[_status] ?? _status;

    final photos = _Panel(
      child: resource != null && tenant != null
          ? ResourcePhotosEditor(
              tenantId: tenant.id,
              resourceId: resource.id,
              photos: resource.photos,
              icon: resourceTypeIcon(type),
            )
          : Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Text('Fotoğraflar', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: FlowSpace.md),
              Row(children: [
                ClipRRect(
                  borderRadius: FlowRadius.controlAll,
                  child: SizedBox(
                    width: 88,
                    height: 66,
                    child: CatalogPhotoPlaceholder(icon: resourceTypeIcon(type), iconSize: 24),
                  ),
                ),
                const SizedBox(width: FlowSpace.md),
                Expanded(
                  child: Text(
                    'Fotoğrafları kaydı kaydettikten sonra ekleyebilirsiniz. İlk fotoğraf kapak olur.',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
              ]),
            ]),
    );

    final name = TextFormField(
      controller: _name,
      maxLength: 200,
      readOnly: _busy,
      textCapitalization: TextCapitalization.sentences,
      decoration: const InputDecoration(labelText: 'Ad'),
      validator: (v) => (v?.trim().isEmpty ?? true) ? 'Ad girin.' : null,
    );

    final price = ValueListenableBuilder<TextEditingValue>(
      valueListenable: _price,
      builder: (context, value, _) {
        final parsed = parseAmount(value.text);
        return TextFormField(
          controller: _price,
          readOnly: _busy,
          keyboardType: TextInputType.number,
          style: FlowText.number(context, size: 26),
          decoration: InputDecoration(
            labelText: type.bookingUnit == 'night' ? 'Gecelik fiyat' : 'Fiyat',
            hintText: '0',
            suffixText: '₺',
            suffixStyle: FlowText.mono(context, size: 18),
            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 18),
            helper: parsed == null
                ? null
                : Text('Müşteri ${formatPrice(parsed, 'TRY')} olarak görür.',
                    style: Theme.of(context).textTheme.bodySmall),
          ),
          validator: (v) =>
              (v?.trim().isEmpty ?? true) || parseAmount(v!) != null ? null : 'Sayı girin.',
        );
      },
    );

    final attributes = LayoutBuilder(builder: (context, constraints) {
      final twoColumns = constraints.maxWidth >= 320;
      final cell = twoColumns ? ((constraints.maxWidth - FlowSpace.md) / 2).floorToDouble() : constraints.maxWidth;
      return Wrap(spacing: FlowSpace.md, runSpacing: FlowSpace.lg, children: [
        if (type.bookable)
          SizedBox(
            width: cell,
            child: TextFormField(
              controller: _capacity,
              readOnly: _busy,
              keyboardType: TextInputType.number,
              style: FlowText.mono(context, size: 15, color: c.text),
              decoration: const InputDecoration(labelText: 'Kapasite (kişi)'),
              validator: (v) => (v?.trim().isEmpty ?? true) || int.tryParse(v!.trim()) != null ? null : 'Sayı girin.',
            ),
          ),
        for (final field in type.fields) SizedBox(width: cell, child: _fieldInput(field)),
      ]);
    });

    final description = TextFormField(
      controller: _description,
      readOnly: _busy,
      minLines: 3,
      maxLines: 6,
      maxLength: 4000,
      textCapitalization: TextCapitalization.sentences,
      decoration: const InputDecoration(
        labelText: 'Açıklama',
        alignLabelWithHint: true,
        helperText: 'Asistan bu metni müşterilere bu kayıttan bahsederken kullanır.',
        helperMaxLines: 2,
      ),
    );

    final statusField = DropdownButtonFormField<String>(
      initialValue: _status,
      decoration: const InputDecoration(
        labelText: 'Durum',
        helperText: 'Asistan yalnızca yayındaki kayıtları müşterilere önerir.',
        helperMaxLines: 2,
      ),
      items: [
        for (final entry in resourceStatusLabels.entries) DropdownMenuItem(value: entry.key, child: Text(entry.value)),
      ],
      onChanged: _busy ? null : (value) => setState(() => _status = value ?? _status),
    );

    final error = _error == null ? null : CatalogNotice(_error!);

    return CatalogSheet(
      eyebrow: resource == null ? '${type.name} · yeni kayıt' : '${type.name} · düzenle',
      title: resource == null ? '${type.name} ekle' : resource.name,
      badge: resource == null ? null : StatusBadge(status, tone: resourceStatusTone(_status)),
      leadingAction: resource == null
          ? null
          : TextButton.icon(
              onPressed: _busy ? null : _delete,
              style: TextButton.styleFrom(foregroundColor: c.danger),
              icon: const Icon(Icons.delete_outline, size: 18),
              label: const Text('Sil'),
            ),
      actions: [
        FilledButton(onPressed: _busy ? null : _save, child: const Text('Kaydet')),
      ],
      child: Form(
        key: _formKey,
        child: LayoutBuilder(builder: (context, constraints) {
          const gap = SizedBox(height: FlowSpace.lg);
          if (constraints.maxWidth >= 760) {
            return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(
                flex: 11,
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  photos,
                  gap,
                  _Panel(child: description),
                ]),
              ),
              const SizedBox(width: FlowSpace.lg),
              Expanded(
                flex: 10,
                child: _Panel(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    name,
                    const SizedBox(height: FlowSpace.sm),
                    price,
                    gap,
                    attributes,
                    gap,
                    statusField,
                    if (error != null) ...[gap, error],
                  ]),
                ),
              ),
            ]);
          }
          return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            photos,
            const SizedBox(height: FlowSpace.xl),
            name,
            const SizedBox(height: FlowSpace.sm),
            price,
            gap,
            attributes,
            gap,
            description,
            gap,
            statusField,
            if (error != null) ...[gap, error],
          ]);
        }),
      ),
    );
  }

  Widget _fieldInput(ResourceField field) {
    final c = FlowColors.of(context);
    switch (field.type) {
      case 'boolean':
        return Container(
          decoration: BoxDecoration(
            color: c.canvas,
            borderRadius: FlowRadius.controlAll,
            border: Border.all(color: c.borderStrong),
          ),
          child: SwitchListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: FlowSpace.md),
            shape: RoundedRectangleBorder(borderRadius: FlowRadius.controlAll),
            title: Text(field.label, style: Theme.of(context).textTheme.bodyMedium),
            value: _attributes[field.key] == true,
            onChanged: _busy ? null : (value) => setState(() => _attributes[field.key] = value),
          ),
        );
      case 'select':
        final current = _attributes[field.key];
        return DropdownButtonFormField<String>(
          initialValue: field.options.contains(current) ? current as String : null,
          isExpanded: true,
          decoration: InputDecoration(labelText: field.label),
          items: [
            for (final option in field.options)
              DropdownMenuItem(value: option, child: Text(option, overflow: TextOverflow.ellipsis)),
          ],
          onChanged: _busy ? null : (value) => setState(() => _attributes[field.key] = value),
        );
      default:
        final number = field.type == 'number';
        return TextFormField(
          controller: _text[field.key],
          readOnly: _busy,
          keyboardType: number ? TextInputType.number : TextInputType.text,
          style: number ? FlowText.mono(context, size: 15, color: c.text) : null,
          decoration: InputDecoration(labelText: field.label),
          validator: (v) => number && (v?.trim().isNotEmpty ?? false) && num.tryParse(v!.trim()) == null
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
            price: parseAmount(_price.text),
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
    final confirmed = await confirmAction(
      context,
      title: 'Kayıt silinsin mi?',
      message: 'Bu kayda ait rezervasyonlar da silinir. Satılan veya kullanılmayan kayıtlar için '
          'durumu değiştirmeniz yeterlidir.',
      confirmLabel: 'Sil',
      destructive: true,
    );
    if (!confirmed || !mounted) return;
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

/// A bordered group inside the editor.
class _Panel extends StatelessWidget {
  const _Panel({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final c = FlowColors.of(context);
    return Container(
      padding: const EdgeInsets.all(FlowSpace.lg),
      decoration: BoxDecoration(
        color: c.canvas,
        borderRadius: FlowRadius.cardAll,
        border: Border.all(color: c.border),
      ),
      child: child,
    );
  }
}
