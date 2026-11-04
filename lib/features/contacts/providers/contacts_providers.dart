import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../tenancy/providers/tenant_providers.dart';
import '../data/contacts_repository.dart';
import '../models/contact.dart';

final contactsRepositoryProvider = Provider<ContactsRepository>(
  (ref) => ContactsRepository(Supabase.instance.client),
);

class ContactsPage {
  const ContactsPage({
    required this.items,
    required this.hasMore,
    this.loadingMore = false,
  });

  final List<Contact> items;
  final bool hasMore;
  final bool loadingMore;
}

/// Search + paginated contact list for the selected tenant. A tenant change
/// rebuilds it, and late responses for an older query or tenant are dropped.
class ContactsController extends AsyncNotifier<ContactsPage> {
  String _search = '';
  int _generation = 0;

  String get search => _search;

  @override
  Future<ContactsPage> build() async {
    final tenant = ref.watch(selectedTenantProvider);
    // A newer build supersedes older ones; loadMore checks this counter too.
    _generation++;
    if (tenant == null) return const ContactsPage(items: [], hasMore: false);
    final items =
        await ref.watch(contactsRepositoryProvider).list(tenant.id, search: _search);
    return ContactsPage(
        items: items, hasMore: items.length == ContactsRepository.pageSize);
  }

  Future<void> setSearch(String value) async {
    if (value.trim() == _search) return;
    _search = value.trim();
    ref.invalidateSelf();
    await future.catchError((_) => const ContactsPage(items: [], hasMore: false));
  }

  Future<void> loadMore() async {
    final current = state.valueOrNull;
    final tenant = ref.read(selectedTenantProvider);
    if (current == null || !current.hasMore || current.loadingMore || tenant == null) {
      return;
    }
    final generation = _generation;
    state = AsyncData(ContactsPage(
        items: current.items, hasMore: current.hasMore, loadingMore: true));
    try {
      final more = await ref
          .read(contactsRepositoryProvider)
          .list(tenant.id, search: _search, offset: current.items.length);
      if (generation != _generation) return;
      final seen = current.items.map((item) => item.id).toSet();
      state = AsyncData(ContactsPage(
        items: [...current.items, ...more.where((item) => seen.add(item.id))],
        hasMore: more.length == ContactsRepository.pageSize,
      ));
    } catch (_) {
      if (generation != _generation) return;
      state = AsyncData(ContactsPage(items: current.items, hasMore: true));
      rethrow;
    }
  }
}

final contactsControllerProvider =
    AsyncNotifierProvider<ContactsController, ContactsPage>(ContactsController.new);
