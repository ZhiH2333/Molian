import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/dio_provider.dart';
import '../data/realms_repository.dart';
import '../data/models/realm_model.dart';

final realmsRepositoryProvider = Provider<RealmsRepository>((ref) {
  final dio = ref.watch(dioProvider);
  return RealmsRepository(dio: dio);
});

/// 圈子列表请求 key：scope + 可选搜索关键词。
class RealmsListKey {
  const RealmsListKey({
    this.scope = RealmsScope.all,
    this.query,
  });
  final RealmsScope scope;
  final String? query;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is RealmsListKey && scope == other.scope && query == other.query;

  @override
  int get hashCode => Object.hash(scope, query);
}

final realmsListProvider =
    FutureProvider.family<List<RealmModel>, RealmsListKey>((ref, key) async {
  final repo = ref.watch(realmsRepositoryProvider);
  return repo.fetchRealms(scope: key.scope, query: key.query);
});

final realmDetailProvider = FutureProvider.family<RealmModel?, String>((ref, id) async {
  final repo = ref.watch(realmsRepositoryProvider);
  return repo.getRealm(id);
});
