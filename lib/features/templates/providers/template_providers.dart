import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../data/supabase_template_repository.dart';
import '../data/template_repository.dart';

final templateRepositoryProvider = Provider<TemplateRepository>(
    (ref) => SupabaseTemplateRepository(Supabase.instance.client));
