import 'package:cached_network_image/cached_network_image.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../shared/widgets/image_lightbox.dart';
import '../../../../shared/widgets/post_image_gallery.dart';
import '../../../auth/data/models/user_model.dart';
import '../../../auth/providers/auth_providers.dart';
import '../../../social/providers/social_providers.dart';
import '../../data/models/post_model.dart';
import '../../providers/posts_providers.dart';

/// 将数字格式化为 K/M 简写（如 1800 → 1.8K）。
String _formatCount(int count) {
  if (count >= 1000000) return '${(count / 1000000).toStringAsFixed(1)}M';
  if (count >= 1000) return '${(count / 1000).toStringAsFixed(1)}K';
  return '$count';
}

/// 将 ISO 8601 时间字符串转为相对时间（如 "20h"、"2d"）。
String _formatRelativeTime(String? isoTime) {
  if (isoTime == null) return '';
  try {
    final DateTime created = DateTime.parse(isoTime).toLocal();
    final Duration diff = DateTime.now().difference(created);
    if (diff.inMinutes < 1) return '刚刚';
    if (diff.inHours < 1) return '${diff.inMinutes}m';
    if (diff.inDays < 1) return '${diff.inHours}h';
    if (diff.inDays < 365) return '${diff.inDays}d';
    return '${(diff.inDays / 365).floor()}y';
  } catch (_) {
    return isoTime;
  }
}

/// X.com 风格帖子卡片。
///
/// [isDetailView] 为 true 时禁用整卡点击跳转（用于帖子详情页自身）。
/// [onPostDeleted] 删除成功后回调（如详情页需 context.pop）。
class PostCard extends ConsumerWidget {
  const PostCard({
    super.key,
    required this.post,
    this.isDetailView = false,
    this.onPostDeleted,
  });

  final PostModel post;
  final bool isDetailView;
  final VoidCallback? onPostDeleted;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final UserModel? authUser = ref.watch(authStateProvider).valueOrNull;
    final bool isOwnPost = authUser != null && authUser.id == post.userId;
    final PostUser? user = post.user;
    final String name = user?.displayName ?? user?.username ?? '未知用户';
    final String handle = user?.username ?? '';
    final String timeAgo = _formatRelativeTime(post.createdAt);
    final Widget cardContent = Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          _PostAvatar(
            user: user,
            name: name,
            onTap: () {},
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                _PostHeader(
                  name: name,
                  handle: handle,
                  timeAgo: timeAgo,
                  post: post,
                  authUser: authUser,
                  isOwnPost: isOwnPost,
                  ref: ref,
                  onPostDeleted: onPostDeleted,
                ),
                if (post.title.isNotEmpty) ...<Widget>[
                  const SizedBox(height: 4),
                  Text(
                    post.title,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: Theme.of(context).colorScheme.onSurface,
                    ),
                  ),
                ],
                const SizedBox(height: 4),
                _PostContent(content: post.content),
                if (post.imageUrls != null && post.imageUrls!.isNotEmpty) ...<Widget>[
                  const SizedBox(height: 12),
                  _PostImages(
                    imageUrls: post.imageUrls!,
                    postId: post.id,
                  ),
                ],
                const SizedBox(height: 12),
                _PostActionBar(post: post, authUser: authUser, ref: ref),
                const SizedBox(height: 8),
              ],
            ),
          ),
        ],
      ),
    );
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        if (isDetailView)
          cardContent
        else
          InkWell(
            onTap: () => context.push('/posts/${post.id}', extra: post),
            onLongPress: () => _showPostActionsSheet(context, ref, post, isOwnPost, onPostDeleted: onPostDeleted),
            child: cardContent,
          ),
        const Divider(height: 1, thickness: 0.5),
      ],
    );
  }
}

/// 展示帖子操作底部菜单（回复、转发、复制链接、举报、编辑、删除）。
void _showPostActionsSheet(
  BuildContext context,
  WidgetRef ref,
  PostModel post,
  bool isOwnPost, {
  VoidCallback? onPostDeleted,
}) {
  final BuildContext sheetContext = context;
  showModalBottomSheet<void>(
    context: context,
    useRootNavigator: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (_) => _PostActionsSheet(
      post: post,
      isOwnPost: isOwnPost,
      ref: ref,
      sheetContext: sheetContext,
      onPostDeleted: onPostDeleted,
    ),
  );
}

/// 帖子操作底部菜单内容。
class _PostActionsSheet extends StatelessWidget {
  const _PostActionsSheet({
    required this.post,
    required this.isOwnPost,
    required this.ref,
    required this.sheetContext,
    this.onPostDeleted,
  });

  final PostModel post;
  final bool isOwnPost;
  final WidgetRef ref;
  final BuildContext sheetContext;
  final VoidCallback? onPostDeleted;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          _buildHandle(context),
          _buildTile(
            context,
            icon: Icons.chat_bubble_outline,
            label: '回复',
            onTap: () {
              final router = GoRouter.of(context);
              Navigator.pop(context);
              router.push('/posts/${post.id}', extra: post);
            },
          ),
          _buildTile(
            context,
            icon: Icons.repeat,
            label: '转发',
            onTap: () => Navigator.pop(context),
          ),
          _buildTile(
            context,
            icon: Icons.link,
            label: '复制链接',
            onTap: () async {
              Navigator.pop(context);
              await Clipboard.setData(
                ClipboardData(text: 'https://capslian.app/posts/${post.id}'),
              );
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('链接已复制')),
                );
              }
            },
          ),
          _buildTile(
            context,
            icon: Icons.flag_outlined,
            label: '举报',
            onTap: () => Navigator.pop(context),
          ),
          if (isOwnPost) ...<Widget>[
            const Divider(height: 1),
            _buildTile(
              context,
              icon: Icons.edit_outlined,
              label: '编辑',
              onTap: () {
                final router = GoRouter.of(context);
                Navigator.pop(context);
                router.push('/posts/${post.id}/edit', extra: post);
              },
            ),
            _buildTile(
              context,
              icon: Icons.delete_outline,
              label: '删除',
              color: Theme.of(context).colorScheme.error,
              onTap: () async {
                Navigator.pop(context);
                await _confirmAndDelete(sheetContext);
              },
            ),
          ],
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  Widget _buildHandle(BuildContext context) {
    return Container(
      width: 40,
      height: 4,
      margin: const EdgeInsets.symmetric(vertical: 10),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.onSurfaceVariant.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(2),
      ),
    );
  }

  Widget _buildTile(
    BuildContext context, {
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    Color? color,
  }) {
    final Color effectiveColor = color ?? Theme.of(context).colorScheme.onSurface;
    return ListTile(
      leading: Icon(icon, color: effectiveColor),
      title: Text(label, style: TextStyle(color: effectiveColor)),
      onTap: onTap,
    );
  }

  Future<void> _confirmAndDelete(BuildContext context) async {
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        title: const Text('删除帖子'),
        content: const Text('确定要删除这条帖子吗？删除后无法恢复。'),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    try {
      await ref.read(postsRepositoryProvider).deletePost(post.id);
      if (context.mounted) {
        ref.invalidate(postsListProvider(const PostsListKey()));
        ref.invalidate(feedsListProvider(const PostsListKey()));
        ref.invalidate(postDetailProvider(post.id));
        onPostDeleted?.call();
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(
          const SnackBar(content: Text('已删除帖子及相关评论与图片')),
        );
      }
    } catch (err) {
      String msg = '删除失败，请重试';
      if (err is DioException) {
        final DioException e = err;
        final dynamic data = e.response?.data;
        if (data is Map && data['error'] is String && (data['error'] as String).trim().isNotEmpty) {
          msg = (data['error'] as String).trim();
        } else if ((e.message ?? '').trim().isNotEmpty) {
          msg = (e.message ?? '').trim();
        }
        if (e.response?.statusCode != null) {
          msg = '[$msg] (${e.response!.statusCode})';
        }
      } else {
        final raw = err.toString().replaceFirst('Exception: ', '').trim();
        if (raw.isNotEmpty) msg = raw;
      }
      if (context.mounted) {
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(
          SnackBar(content: Text(msg.isNotEmpty ? msg : '删除失败，请重试')),
        );
      }
    }
  }
}

/// 用户头像（圆形，支持网络图或首字母占位）。
class _PostAvatar extends StatelessWidget {
  const _PostAvatar({required this.user, required this.name, required this.onTap});

  final dynamic user;
  final String name;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return GestureDetector(
      onTap: onTap,
      child: CircleAvatar(
        radius: 20,
        backgroundColor: theme.colorScheme.primaryContainer,
        child: user?.avatarUrl != null
            ? ClipOval(
                child: CachedNetworkImage(
                  imageUrl: user!.avatarUrl as String,
                  width: 40,
                  height: 40,
                  fit: BoxFit.cover,
                  errorWidget: (_, __, ___) => _buildInitial(theme),
                ),
              )
            : _buildInitial(theme),
      ),
    );
  }

  Widget _buildInitial(ThemeData theme) {
    return Text(
      name.isNotEmpty ? name[0].toUpperCase() : '?',
      style: theme.textTheme.titleMedium?.copyWith(
        color: theme.colorScheme.onPrimaryContainer,
        fontWeight: FontWeight.bold,
      ),
    );
  }
}

/// 帖子头部：用户名、handle、时间、操作菜单按钮。
class _PostHeader extends StatelessWidget {
  const _PostHeader({
    required this.name,
    required this.handle,
    required this.timeAgo,
    required this.post,
    required this.authUser,
    required this.isOwnPost,
    required this.ref,
    this.onPostDeleted,
  });

  final String name;
  final String handle;
  final String timeAgo;
  final PostModel post;
  final UserModel? authUser;
  final bool isOwnPost;
  final WidgetRef ref;
  final VoidCallback? onPostDeleted;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final Color secondaryColor = theme.colorScheme.onSurfaceVariant;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: <Widget>[
        Expanded(
          child: Text.rich(
            TextSpan(
              children: <InlineSpan>[
                TextSpan(
                  text: name,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: theme.colorScheme.onSurface,
                  ),
                ),
                if (handle.isNotEmpty)
                  TextSpan(
                    text: '  @$handle',
                    style: theme.textTheme.bodySmall?.copyWith(color: secondaryColor),
                  ),
                if (timeAgo.isNotEmpty)
                  TextSpan(
                    text: ' · $timeAgo',
                    style: theme.textTheme.bodySmall?.copyWith(color: secondaryColor),
                  ),
              ],
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        SizedBox(
          width: 32,
          height: 32,
          child: IconButton(
            padding: EdgeInsets.zero,
            iconSize: 18,
            icon: Icon(Icons.more_horiz, color: secondaryColor),
            onPressed: () => _showPostActionsSheet(
              context,
              ref,
              post,
              isOwnPost,
              onPostDeleted: onPostDeleted,
            ),
          ),
        ),
      ],
    );
  }
}

/// 帖子正文内容。
class _PostContent extends StatelessWidget {
  const _PostContent({required this.content});

  final String content;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Text(
      content,
      style: theme.textTheme.bodyMedium?.copyWith(
        color: theme.colorScheme.onSurface,
        height: 1.4,
      ),
    );
  }
}

/// 帖子图片区域：支持单图、双图并排、多图网格，点击任意图片打开全屏灯箱。
class _PostImages extends StatelessWidget {
  const _PostImages({required this.imageUrls, required this.postId});

  final List<String> imageUrls;
  final String postId;

  String _heroTag(int index) => '${postId}_img_$index';

  void _openLightbox(BuildContext context, int index) {
    showImageLightbox(
      context,
      imageUrls: imageUrls,
      initialIndex: index,
      heroTagPrefix: '${postId}_img',
    );
  }

  @override
  Widget build(BuildContext context) {
    if (imageUrls.length == 1) return _buildSingleImage(context);
    return PostImageGallery(
      imageUrls: imageUrls,
      onImageTap: (int index) => _openLightbox(context, index),
    );
  }

  Widget _buildSingleImage(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => _openLightbox(context, 0),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: AspectRatio(
          aspectRatio: 16 / 9,
          child: Hero(
            tag: _heroTag(0),
            child: _NetworkImage(url: imageUrls[0]),
          ),
        ),
      ),
    );
  }

}

/// 带缓存的网络图片，加载失败时显示占位图。
class _NetworkImage extends StatelessWidget {
  const _NetworkImage({required this.url});

  final String url;

  @override
  Widget build(BuildContext context) {
    return CachedNetworkImage(
      imageUrl: url,
      fit: BoxFit.cover,
      errorWidget: (_, __, ___) => const _ImagePlaceholder(),
    );
  }
}

/// 图片加载失败占位。
class _ImagePlaceholder extends StatelessWidget {
  const _ImagePlaceholder();

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Theme.of(context).colorScheme.surfaceContainerHigh,
      child: Icon(
        Icons.broken_image_outlined,
        color: Theme.of(context).colorScheme.onSurfaceVariant,
      ),
    );
  }
}

/// 底部操作栏：评论、转帖、喜欢、浏览量 / 收藏、转发。
class _PostActionBar extends ConsumerStatefulWidget {
  const _PostActionBar({required this.post, required this.authUser, required this.ref});

  final PostModel post;
  final UserModel? authUser;
  final WidgetRef ref;

  @override
  ConsumerState<_PostActionBar> createState() => _PostActionBarState();
}

class _PostActionBarState extends ConsumerState<_PostActionBar> {
  late bool _liked;
  late int _likeCount;
  late bool _isReposted;
  late int _repostCount;
  late bool _isBookmarked;

  @override
  void initState() {
    super.initState();
    _liked = widget.post.liked;
    _likeCount = widget.post.likeCount;
    _isReposted = widget.post.isReposted;
    _repostCount = widget.post.repostCount;
    _isBookmarked = widget.post.isBookmarked;
  }

  Future<void> _toggleLike() async {
    if (widget.authUser == null) return;
    final bool prevLiked = _liked;
    setState(() {
      _liked = !_liked;
      _likeCount = (_likeCount + (_liked ? 1 : -1)).clamp(0, 999999999);
    });
    try {
      final repo = ref.read(socialRepositoryProvider);
      if (!prevLiked) {
        await repo.likePost(widget.post.id);
      } else {
        await repo.unlikePost(widget.post.id);
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _liked = prevLiked;
          _likeCount = (_likeCount + (prevLiked ? 1 : -1)).clamp(0, 999999999);
        });
      }
    }
  }

  void _toggleRepost() {
    if (widget.authUser == null) return;
    setState(() {
      _isReposted = !_isReposted;
      _repostCount = (_repostCount + (_isReposted ? 1 : -1)).clamp(0, 999999999);
    });
  }

  void _toggleBookmark() {
    if (widget.authUser == null) return;
    setState(() => _isBookmarked = !_isBookmarked);
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final Color defaultColor = theme.colorScheme.onSurfaceVariant;
    return Row(
      children: <Widget>[
        _ActionButton(
          icon: Icons.chat_bubble_outline,
          count: widget.post.commentCount,
          color: defaultColor,
          activeColor: const Color(0xFF1D9BF0),
          onTap: () => context.push('/posts/${widget.post.id}', extra: widget.post),
        ),
        const SizedBox(width: 4),
        _ActionButton(
          icon: Icons.repeat,
          count: _repostCount,
          color: _isReposted ? const Color(0xFF00BA7C) : defaultColor,
          activeColor: const Color(0xFF00BA7C),
          isActive: _isReposted,
          onTap: _toggleRepost,
        ),
        const SizedBox(width: 4),
        _ActionButton(
          icon: _liked ? Icons.favorite : Icons.favorite_border,
          count: _likeCount,
          color: _liked ? const Color(0xFFF91880) : defaultColor,
          activeColor: const Color(0xFFF91880),
          isActive: _liked,
          onTap: _toggleLike,
        ),
        const SizedBox(width: 4),
        _ActionButton(
          icon: Icons.bar_chart,
          count: widget.post.viewCount,
          color: defaultColor,
          activeColor: const Color(0xFF1D9BF0),
          onTap: null,
        ),
        const Spacer(),
        _IconActionButton(
          icon: _isBookmarked ? Icons.bookmark : Icons.bookmark_border,
          color: _isBookmarked ? const Color(0xFF1D9BF0) : defaultColor,
          onTap: _toggleBookmark,
        ),
        const SizedBox(width: 4),
        _IconActionButton(
          icon: Icons.ios_share_outlined,
          color: defaultColor,
          onTap: () async {
            await Clipboard.setData(
              ClipboardData(text: 'https://capslian.app/posts/${widget.post.id}'),
            );
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('链接已复制')),
              );
            }
          },
        ),
      ],
    );
  }
}

/// 带数字的操作按钮（评论、转帖、喜欢、浏览量）。
class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.icon,
    required this.count,
    required this.color,
    required this.activeColor,
    this.isActive = false,
    required this.onTap,
  });

  final IconData icon;
  final int count;
  final Color color;
  final Color activeColor;
  final bool isActive;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final String displayCount = count > 0 ? _formatCount(count) : '';
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 2),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(icon, size: 18, color: color),
            if (displayCount.isNotEmpty) ...<Widget>[
              const SizedBox(width: 4),
              Text(
                displayCount,
                style: TextStyle(fontSize: 13, color: color),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// 仅图标操作按钮（收藏、分享）。
class _IconActionButton extends StatelessWidget {
  const _IconActionButton({required this.icon, required this.color, required this.onTap});

  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 2),
        child: Icon(icon, size: 18, color: color),
      ),
    );
  }
}
