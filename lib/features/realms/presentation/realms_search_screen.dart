import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/layout_constants.dart';
import '../../../core/router/app_router.dart';
import '../../../core/utils/image_url_utils.dart';
import '../../../shared/widgets/app_scaffold.dart';
import '../../../shared/widgets/auto_leading_button.dart';
import '../data/models/realm_model.dart';
import '../data/realms_repository.dart';
import '../providers/realms_providers.dart';

/// 圈子搜索页：搜索框 + 结果列表（scope=all + q）。
class RealmsSearchScreen extends ConsumerStatefulWidget {
  const RealmsSearchScreen({super.key});

  @override
  ConsumerState<RealmsSearchScreen> createState() => _RealmsSearchScreenState();
}

class _RealmsSearchScreenState extends ConsumerState<RealmsSearchScreen> {
  final _queryController = TextEditingController();
  String _query = '';
  bool _hasSearched = false;

  @override
  void dispose() {
    _queryController.dispose();
    super.dispose();
  }

  void _onSearch(String value) {
    setState(() {
      _query = value.trim();
      _hasSearched = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    final key = RealmsListKey(scope: RealmsScope.all, query: _query.isEmpty ? null : _query);
    final async = ref.watch(realmsListProvider(key));

    return AppScaffold(
      appBar: AppBar(
        leading: const AutoLeadingButton(),
        title: TextField(
          controller: _queryController,
          decoration: InputDecoration(
            hintText: '搜索圈子名称、短链接',
            border: InputBorder.none,
            filled: false,
          ),
          autofocus: true,
          textInputAction: TextInputAction.search,
          onSubmitted: _onSearch,
          onChanged: (String value) {
            if (value.trim().isEmpty) setState(() => _hasSearched = true);
          },
        ),
        actions: <Widget>[
          IconButton(
            icon: const Icon(Icons.search),
            onPressed: () => _onSearch(_queryController.text),
          ),
        ],
      ),
      body: _query.isEmpty && !_hasSearched
          ? Center(
              child: Text(
                '输入关键词搜索圈子',
                style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
              ),
            )
          : _query.isEmpty
              ? Center(
                  child: Text(
                    '请输入搜索关键词',
                    style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                  ),
                )
              : async.when(
                  data: (List<RealmModel> realms) {
                    if (realms.isEmpty) {
                      return Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: <Widget>[
                            Icon(
                              Icons.search_off,
                              size: 48,
                              color: Theme.of(context).colorScheme.onSurfaceVariant,
                            ),
                            const SizedBox(height: LayoutConstants.kSpacingMedium),
                            Text(
                              '未找到相关圈子',
                              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                                  ),
                            ),
                          ],
                        ),
                      );
                    }
                    return ListView.builder(
                      padding: const EdgeInsets.only(
                        bottom: LayoutConstants.kSpacingXLarge,
                      ),
                      itemCount: realms.length,
                      itemBuilder: (BuildContext context, int index) {
                        final realm = realms[index];
                        return ListTile(
                          minLeadingWidth: LayoutConstants.kListTileMinLeadingWidth,
                          contentPadding: LayoutConstants.kListTileContentPadding,
                          leading: CircleAvatar(
                            backgroundImage: realm.avatarUrl != null &&
                                    realm.avatarUrl!.isNotEmpty
                                ? CachedNetworkImageProvider(fullImageUrl(realm.avatarUrl))
                                : null,
                            child: realm.avatarUrl == null || realm.avatarUrl!.isEmpty
                                ? Text(realm.name.isNotEmpty ? realm.name[0] : '?')
                                : null,
                          ),
                          title: Text(realm.name),
                          subtitle: realm.description != null &&
                                  realm.description!.isNotEmpty
                              ? Text(
                                  realm.description!,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                )
                              : null,
                          onTap: () => context.push(
                            AppRoutes.realmDetail(realm.id),
                            extra: realm,
                          ),
                        );
                      },
                    );
                  },
                  loading: () => const Center(child: CircularProgressIndicator()),
                  error: (Object err, StackTrace? st) => Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        Text(err.toString(), textAlign: TextAlign.center),
                        const SizedBox(height: LayoutConstants.kSpacingMedium),
                        TextButton(
                          onPressed: () => ref.invalidate(realmsListProvider(key)),
                          child: const Text('重试'),
                        ),
                      ],
                    ),
                  ),
                ),
    );
  }
}
