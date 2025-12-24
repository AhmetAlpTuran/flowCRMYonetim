import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'user_role.dart';

final userRoleProvider = StateProvider<UserRole>((ref) => UserRole.admin);