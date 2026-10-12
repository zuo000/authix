import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/credential.dart';
import '../../providers/vault_provider.dart';
import '../widgets/marquee_text.dart';

/// 垃圾箱 (回收站) 界面
class TrashScreen extends ConsumerWidget {
  const TrashScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final trashAsync = ref.watch(trashCredentialsProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('垃圾箱'),
        actions: [
          trashAsync.maybeWhen(
            data: (items) {
              if (items.isEmpty) return const SizedBox.shrink();
              return TextButton.icon(
                onPressed: () => _confirmEmptyTrash(context, ref),
                icon: Icon(Icons.delete_sweep_outlined, color: theme.colorScheme.error),
                label: Text('清空', style: TextStyle(color: theme.colorScheme.error)),
              );
            },
            orElse: () => const SizedBox.shrink(),
          ),
        ],
      ),
      body: trashAsync.when(
        data: (items) {
          if (items.isEmpty) {
            return _buildEmptyState(theme);
          }
          return ListView.separated(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
            itemCount: items.length,
            separatorBuilder: (_, _) => const SizedBox(height: 12),
            itemBuilder: (ctx, index) {
              final item = items[index];
              return _buildTrashItem(context, ref, theme, item);
            },
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, _) => Center(child: Text('加载垃圾箱失败: $err')),
      ),
    );
  }

  Widget _buildEmptyState(ThemeData theme) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.delete_outline_rounded,
              size: 64,
              color: theme.colorScheme.outline,
            ),
          ),
          const SizedBox(height: 20),
          Text(
            '垃圾箱为空',
            style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Text(
            '从密码库中删除的凭据将暂存在这里，可随时恢复',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTrashItem(BuildContext context, WidgetRef ref, ThemeData theme, Credential item) {
    final deletedDateStr = item.deletedAt != null
        ? _formatDateTime(DateTime.fromMillisecondsSinceEpoch(item.deletedAt!))
        : '未知时间';

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: theme.colorScheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            // 类型图标
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(_getIconForType(item.type), color: theme.colorScheme.primary, size: 24),
            ),
            const SizedBox(width: 14),

            // 信息
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.title,
                    style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  MarqueeText(
                    text: '${item.type.label} · 删除于 $deletedDateStr',
                    style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.outline),
                  ),
                  if (item.account.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    MarqueeText(
                      text: item.account,
                      style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                    ),
                  ],
                ],
              ),
            ),

            const SizedBox(width: 8),

            // 操作：恢复
            FilledButton.tonalIcon(
              onPressed: () async {
                await ref.read(vaultProvider.notifier).restoreFromTrash(item.id);
                if (context.mounted) {
                  final messenger = ScaffoldMessenger.of(context);
                  messenger.clearSnackBars();
                  messenger.showSnackBar(
                    const SnackBar(
                      content: Text('已成功恢复至密码库'),
                      behavior: SnackBarBehavior.floating,
                      duration: Duration(seconds: 2),
                    ),
                  );
                }
              },
              icon: const Icon(Icons.restore, size: 16),
              label: const Text('恢复'),
              style: FilledButton.styleFrom(
                visualDensity: VisualDensity.compact,
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                textStyle: const TextStyle(fontSize: 13),
              ),
            ),

            const SizedBox(width: 4),

            // 操作：彻底删除
            IconButton(
              visualDensity: VisualDensity.compact,
              icon: Icon(Icons.delete_forever, color: theme.colorScheme.error, size: 20),
              tooltip: '彻底删除',
              onPressed: () => _confirmPermanentDelete(context, ref, item),
            ),
          ],
        ),
      ),
    );
  }

  String _formatDateTime(DateTime dt) {
    final y = dt.year.toString().padLeft(4, '0');
    final m = dt.month.toString().padLeft(2, '0');
    final d = dt.day.toString().padLeft(2, '0');
    final h = dt.hour.toString().padLeft(2, '0');
    final min = dt.minute.toString().padLeft(2, '0');
    return '$y-$m-$d $h:$min';
  }

  IconData _getIconForType(CredentialType type) {
    switch (type) {
      case CredentialType.passkey:
        return Icons.fingerprint_rounded;
      case CredentialType.totp:
        return Icons.timer_outlined;
      case CredentialType.password:
        return Icons.password_rounded;
      case CredentialType.serverKey:
        return Icons.terminal_rounded;
      case CredentialType.apiKey:
        return Icons.key_rounded;
      case CredentialType.cryptoWallet:
        return Icons.account_balance_wallet_outlined;
      case CredentialType.card:
        return Icons.credit_card_outlined;
      case CredentialType.identity:
        return Icons.badge_outlined;
      case CredentialType.secureNote:
        return Icons.note_alt_outlined;
    }
  }

  Future<void> _confirmPermanentDelete(BuildContext context, WidgetRef ref, Credential item) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('彻底删除'),
        content: Text('确定要彻底从本地数据库删除「${item.title}」吗？此操作无法撤销。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Theme.of(ctx).colorScheme.error),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('彻底删除'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await ref.read(vaultProvider.notifier).deleteCredential(item.id);
      if (context.mounted) {
        final messenger = ScaffoldMessenger.of(context);
        messenger.clearSnackBars();
        messenger.showSnackBar(
          SnackBar(
            content: Text('已彻底删除「${item.title}」'),
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 2),
          ),
        );
      }
    }
  }

  Future<void> _confirmEmptyTrash(BuildContext context, WidgetRef ref) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('清空垃圾箱'),
        content: const Text('确定要永久清空垃圾箱中的所有内容吗？清空后将无法找回。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Theme.of(ctx).colorScheme.error),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('确认清空'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await ref.read(vaultProvider.notifier).emptyTrash();
      if (context.mounted) {
        final messenger = ScaffoldMessenger.of(context);
        messenger.clearSnackBars();
        messenger.showSnackBar(
          const SnackBar(
            content: Text('垃圾箱已彻底清空'),
            behavior: SnackBarBehavior.floating,
            duration: Duration(seconds: 2),
          ),
        );
      }
    }
  }
}
