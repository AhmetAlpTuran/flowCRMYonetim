import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../ui/ui.dart' hide formatPrice;
import '../../tenancy/providers/tenant_providers.dart';
import '../data/catalog_repository.dart';
import '../models/catalog_models.dart';
import '../providers/catalog_providers.dart';
import '../widgets/catalog_layout.dart';
import '../widgets/industry_pack_sheet.dart';
import '../widgets/resource_photos_editor.dart';
import 'resource_editor_sheet.dart';

/// Katalog → Kayıtlar: the rooms, vehicles or services the assistant can offer.
class ResourcesTab extends ConsumerStatefulWidget {
  const ResourcesTab({super.key});

  @override
  ConsumerState<ResourcesTab> createState() => _ResourcesTabState();
}

class _ResourcesTabState extends ConsumerState<ResourcesTab> {
  final _search = TextEditingController();
  String _query = '';
  String? _typeId;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final types = ref.watch(resourceTypesProvider);
    return types.when(
      loading: () => CatalogScrollPage(slivers: [sliverBox(const LoadingList())]),
      error: (_, __) => CatalogScrollPage(slivers: [
        sliverBox(ErrorState(
          title: 'Katalog yüklenemedi',
          onRetry: () => ref.invalidate(resourceTypesProvider),
        )),
      ]),
      data: (typeList) => typeList.isEmpty ? const _NoTypes() : _catalog(typeList),
    );
  }

  Widget _catalog(List<ResourceType> typeList) {
    final resources = ref.watch(resourcesProvider);
    final all = resources.valueOrNull ?? const <Resource>[];
    final filterType = typeList.where((t) => t.id == _typeId).firstOrNull;
    final query = foldTr(_query.trim());
    final visible = [
      for (final item in all)
        if ((filterType == null || item.typeId == filterType.id) && (query.isEmpty || _matches(item, query))) item,
    ];
    final narrow = MediaQuery.sizeOf(context).width < 600;

    final toolbar = PageToolbar(
      leading: all.isEmpty
          ? null
          : SearchField(
              hint: 'Kayıtlarda ara',
              controller: _search,
              onChanged: (value) => setState(() => _query = value),
            ),
      actions: [
        OutlinedButton.icon(
          onPressed: () => _addType(typeList),
          icon: const Icon(Icons.category_outlined, size: 18),
          label: const Text('Tür ekle'),
        ),
        _AddItemButton(types: filterType == null ? typeList : [filterType]),
      ],
    );

    final slivers = <Widget>[
      sliverBox(toolbar),
      if (typeList.length > 1 && all.isNotEmpty) ...[
        sliverGap(FlowSpace.md),
        sliverBox(FilterChipsRow<String?>(
          scrollable: narrow,
          options: [
            FilterOption(null, 'Tümü', count: all.length),
            for (final type in typeList)
              FilterOption(type.id, type.name, count: all.where((r) => r.typeId == type.id).length),
          ],
          selected: filterType?.id,
          onSelected: (id) => setState(() => _typeId = id),
        )),
      ],
      sliverGap(FlowSpace.xl - 4),
    ];

    if (resources.isLoading && !resources.hasValue) {
      slivers.add(sliverBox(const LoadingList()));
    } else if (resources.hasError && !resources.hasValue) {
      slivers.add(sliverBox(ErrorState(
        title: 'Kayıtlar yüklenemedi',
        onRetry: () => ref.invalidate(resourcesProvider),
      )));
    } else if (all.isEmpty) {
      slivers.add(sliverBox(EmptyState(
        icon: resourceTypeIcon(typeList.first),
        title: 'İlk kaydınızı ekleyin',
        message: 'Asistan, müşterilere yalnızca burada yayında olan kayıtları önerir. '
            'Fotoğraf, fiyat ve kısa bir açıklama yeterli.',
      )));
    } else if (visible.isEmpty) {
      slivers.add(sliverBox(EmptyState(
        compact: true,
        icon: Icons.search_off,
        title: 'Eşleşen kayıt yok',
        message: 'Aramayı değiştirin ya da filtreyi kaldırın.',
        action: TextButton(
          onPressed: () => setState(() {
            _search.clear();
            _query = '';
            _typeId = null;
          }),
          child: const Text('Filtreyi temizle'),
        ),
      )));
    } else {
      final byId = {for (final t in typeList) t.id: t};
      final groups = filterType == null && typeList.length > 1
          ? [
              for (final type in typeList)
                if (visible.any((r) => r.typeId == type.id))
                  (type: type, items: visible.where((r) => r.typeId == type.id).toList()),
            ]
          : [(type: filterType ?? typeList.first, items: visible)];
      for (final (index, group) in groups.indexed) {
        if (groups.length > 1) {
          if (index > 0) slivers.add(sliverGap(FlowSpace.xl));
          slivers.add(sliverBox(Padding(
            padding: const EdgeInsets.only(bottom: FlowSpace.md),
            child: Text(
              upperTr('${group.type.name} · ${formatCount(group.items.length)}'),
              style: FlowText.caps(context, size: 12),
            ),
          )));
        }
        slivers.add(_ResourceGrid(
          items: group.items,
          typeOf: (item) => byId[item.typeId],
          onOpen: (item) {
            final type = byId[item.typeId];
            if (type != null) openResourceEditor(context, type, item);
          },
        ));
      }
    }
    return CatalogScrollPage(
      onRefresh: () {
        ref.invalidate(resourceTypesProvider);
        return ref.refresh(resourcesProvider.future);
      },
      slivers: slivers,
    );
  }

  bool _matches(Resource item, String query) {
    if (foldTr(item.name).contains(query)) return true;
    if (item.description != null && foldTr(item.description!).contains(query)) return true;
    return item.attributes.values.any((value) => value is! bool && foldTr('$value').contains(query));
  }

  Future<void> _addType(List<ResourceType> existing) async {
    final tenant = ref.read(selectedTenantProvider);
    if (tenant == null) return;
    final available = [
      for (final p in resourceTypePresets)
        if (!existing.any((t) => t.key == p.key)) p,
    ];
    if (available.isEmpty) {
      showAppSnack(context, 'Tüm hazır türler zaten ekli.');
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
                leading: Icon(presetIcon(p.key)),
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
      if (mounted) showAppSnack(context, '${preset.name} türü eklendi.');
    } catch (error) {
      if (mounted) showAppSnack(context, catalogErrorMessage(error), error: true);
    }
  }
}

/// The one primary action: add an item, choosing the type when there are several.
class _AddItemButton extends StatelessWidget {
  const _AddItemButton({required this.types});

  final List<ResourceType> types;

  @override
  Widget build(BuildContext context) {
    if (types.length == 1) {
      return FilledButton.icon(
        onPressed: () => openResourceEditor(context, types.single),
        icon: const Icon(Icons.add, size: 18),
        label: Text('${types.single.name} ekle'),
      );
    }
    return MenuAnchor(
      menuChildren: [
        for (final type in types)
          MenuItemButton(
            leadingIcon: Icon(resourceTypeIcon(type), size: 18),
            onPressed: () => openResourceEditor(context, type),
            child: Text('${type.name} ekle'),
          ),
      ],
      builder: (context, controller, _) => FilledButton.icon(
        onPressed: () => controller.isOpen ? controller.close() : controller.open(),
        icon: const Icon(Icons.add, size: 18),
        label: const Text('Kayıt ekle'),
      ),
    );
  }
}

/// Item cards: a photo grid on wide screens, compact rows on phones. Lazy, so photos
/// are only fetched for cards on screen.
class _ResourceGrid extends StatelessWidget {
  const _ResourceGrid({required this.items, required this.typeOf, required this.onOpen});

  final List<Resource> items;
  final ResourceType? Function(Resource) typeOf;
  final ValueChanged<Resource> onOpen;

  @override
  Widget build(BuildContext context) {
    return SliverLayoutBuilder(builder: (context, constraints) {
      final width = constraints.crossAxisExtent;
      final columns = width >= 1000 ? 4 : (width >= 700 ? 3 : (width >= 480 ? 2 : 1));
      final rows = (items.length / columns).ceil();
      return SliverList.builder(
        itemCount: rows,
        itemBuilder: (context, row) {
          final start = row * columns;
          return Padding(
            padding: EdgeInsets.only(bottom: row == rows - 1 ? 0 : (columns == 1 ? FlowSpace.sm + 2 : FlowSpace.lg)),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              for (var i = 0; i < columns; i++) ...[
                if (i > 0) const SizedBox(width: FlowSpace.lg),
                Expanded(
                  child: start + i < items.length
                      ? _ResourceCard(
                          item: items[start + i],
                          type: typeOf(items[start + i]),
                          compact: columns == 1,
                          onTap: () => onOpen(items[start + i]),
                        )
                      : const SizedBox.shrink(),
                ),
              ],
            ]),
          );
        },
      );
    });
  }
}

class _ResourceCard extends StatelessWidget {
  const _ResourceCard({required this.item, required this.type, required this.compact, required this.onTap});

  final Resource item;
  final ResourceType? type;
  final bool compact;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = FlowColors.of(context);
    final theme = Theme.of(context);
    final status = StatusBadge(resourceStatusLabels[item.status] ?? item.status, tone: resourceStatusTone(item.status));
    final summary = _summary();
    final price = Text.rich(
      TextSpan(children: [
        TextSpan(text: formatPrice(item.price, item.currency)),
        if (item.price != null && type?.bookingUnit == 'night')
          TextSpan(text: ' / gece', style: FlowText.mono(context, size: 12)),
      ]),
      style: item.price == null
          ? FlowText.mono(context, size: 13, color: c.faint)
          : FlowText.mono(context, size: compact ? 15 : 17, color: c.text, weight: FontWeight.w600),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );
    final photo = CatalogPhotoImage(
      path: item.photos.firstOrNull,
      cacheWidth: compact ? 300 : 720,
      placeholder: CatalogPhotoPlaceholder(icon: resourceTypeIcon(type), iconSize: compact ? 24 : 36),
    );

    final Widget body;
    if (compact) {
      body = Padding(
        padding: const EdgeInsets.all(FlowSpace.md),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          ClipRRect(
            borderRadius: FlowRadius.controlAll,
            child: SizedBox(width: 88, height: 66, child: photo),
          ),
          const SizedBox(width: FlowSpace.md),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(item.name, style: theme.textTheme.titleSmall, maxLines: 2, overflow: TextOverflow.ellipsis),
              if (summary.isNotEmpty) ...[
                const SizedBox(height: 2),
                Text(summary, style: theme.textTheme.bodySmall, maxLines: 2, overflow: TextOverflow.ellipsis),
              ],
              const SizedBox(height: FlowSpace.sm),
              Wrap(
                spacing: FlowSpace.sm,
                runSpacing: 6,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [price, status],
              ),
            ]),
          ),
        ]),
      );
    } else {
      body = Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        AspectRatio(
          aspectRatio: 16 / 10,
          child: Stack(fit: StackFit.expand, children: [
            photo,
            if (item.photos.length > 1)
              Positioned(
                right: 10,
                bottom: 10,
                child: _PhotoCount(count: item.photos.length),
              ),
          ]),
        ),
        Divider(height: 1, color: c.border),
        Padding(
          padding: const EdgeInsets.fromLTRB(FlowSpace.lg, 14, FlowSpace.lg, FlowSpace.lg),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(item.name, style: theme.textTheme.titleMedium, maxLines: 2, overflow: TextOverflow.ellipsis),
            const SizedBox(height: 4),
            Text(
              summary.isEmpty ? (type?.name ?? '') : summary,
              style: theme.textTheme.bodySmall,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: FlowSpace.md),
            Row(children: [
              Expanded(child: price),
              const SizedBox(width: FlowSpace.sm),
              status,
            ]),
          ]),
        ),
      ]);
    }

    return Material(
      color: c.surface,
      shape: RoundedRectangleBorder(borderRadius: FlowRadius.cardAll, side: BorderSide(color: c.border)),
      clipBehavior: Clip.antiAlias,
      child: InkWell(onTap: onTap, child: body),
    );
  }

  /// Up to four filled attributes: "2021 · 40.000 km · Otomatik".
  String _summary() {
    final fields = type?.fields ?? const <ResourceField>[];
    final parts = <String>[];
    if (item.capacity != null) parts.add('${item.capacity} kişi');
    for (final field in fields) {
      if (parts.length >= 4) break;
      final value = item.attributes[field.key];
      if (value == null || value == false || '$value'.trim().isEmpty) continue;
      if (value == true) {
        parts.add(field.label);
      } else if (value is num) {
        // Years stay as typed; larger figures (kilometres) get thousands separators.
        final text = value.abs() >= 10000 ? formatCount(value) : '$value';
        parts.add(switch (field.key) {
          'year' => text,
          'km' => '$text km',
          _ => '${field.label}: $text',
        });
      } else {
        parts.add('$value');
      }
    }
    return parts.join(' · ');
  }
}

class _PhotoCount extends StatelessWidget {
  const _PhotoCount({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    final c = FlowColors.of(context);
    return Semantics(
      label: '$count fotoğraf',
      excludeSemantics: true,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
        decoration: BoxDecoration(
          color: c.surface,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: c.border),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.photo_library_outlined, size: 13, color: c.muted),
          const SizedBox(width: 4),
          Text('$count', style: FlowText.mono(context, size: 11, color: c.text)),
        ]),
      ),
    );
  }
}

/// No catalog types yet: the sector pack for administrators, or a single type.
class _NoTypes extends ConsumerStatefulWidget {
  const _NoTypes();

  @override
  ConsumerState<_NoTypes> createState() => _NoTypesState();
}

class _NoTypesState extends ConsumerState<_NoTypes> {
  String? _adding;

  Future<void> _create(ResourceTypePreset preset) async {
    final tenant = ref.read(selectedTenantProvider);
    if (tenant == null || _adding != null) return;
    setState(() => _adding = preset.key);
    try {
      await ref.read(catalogRepositoryProvider).createTypeFromPreset(tenant.id, preset);
      ref.invalidate(resourceTypesProvider);
    } catch (error) {
      if (mounted) showAppSnack(context, catalogErrorMessage(error), error: true);
    } finally {
      if (mounted) setState(() => _adding = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isAdmin = ref.watch(currentMembershipProvider).valueOrNull?.isAdmin ?? false;
    return CatalogScrollPage(slivers: [
      sliverBox(EmptyState(
        icon: Icons.inventory_2_outlined,
        title: 'Kataloğunuzu kurun',
        message: isAdmin
            ? 'Sektör paketi; kayıt türünü, asistan talimatını ve bilgi bankasını birkaç soruyla hazırlar.'
            : 'Asistan; odalarınızı, araçlarınızı veya hizmetlerinizi buradan öğrenir ve müşterilere önerir.',
        action: isAdmin ? const IndustryPackButton() : null,
      )),
      sliverGap(FlowSpace.xl + 4),
      sliverBox(Text(isAdmin ? 'Ya da yalnızca bir kayıt türü ekleyin' : 'Bir kayıt türü ekleyin',
          style: theme.textTheme.titleLarge)),
      sliverGap(FlowSpace.md),
      sliverBox(LayoutBuilder(builder: (context, constraints) {
        final columns = constraints.maxWidth >= 720 ? 3 : 1;
        final width = columns == 1
            ? constraints.maxWidth
            : ((constraints.maxWidth - FlowSpace.md * (columns - 1)) / columns).floorToDouble();
        return Wrap(spacing: FlowSpace.md, runSpacing: FlowSpace.md, children: [
          for (final preset in resourceTypePresets)
            SizedBox(
              width: width,
              child: _PresetCard(
                preset: preset,
                busy: _adding == preset.key,
                onTap: _adding == null ? () => _create(preset) : null,
              ),
            ),
        ]);
      })),
    ]);
  }
}

class _PresetCard extends StatelessWidget {
  const _PresetCard({required this.preset, required this.busy, required this.onTap});

  final ResourceTypePreset preset;
  final bool busy;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = FlowColors.of(context);
    final theme = Theme.of(context);
    return Material(
      color: c.surface,
      shape: RoundedRectangleBorder(borderRadius: FlowRadius.cardAll, side: BorderSide(color: c.border)),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(FlowSpace.lg),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(color: c.raised, borderRadius: FlowRadius.controlAll),
              child: Icon(presetIcon(preset.key), color: c.accentText),
            ),
            const SizedBox(width: FlowSpace.md),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(preset.name, style: theme.textTheme.titleMedium),
                const SizedBox(height: 2),
                Text(preset.description, style: theme.textTheme.bodySmall),
              ]),
            ),
            const SizedBox(width: FlowSpace.sm),
            busy ? const CatalogSpinner(size: 20) : Icon(Icons.add, color: c.muted),
          ]),
        ),
      ),
    );
  }
}
