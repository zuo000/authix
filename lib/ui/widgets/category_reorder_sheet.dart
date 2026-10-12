import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/app_settings_provider.dart';

/// 呼出自定义分类顺序弹窗（自适应移动端底部抽屉与桌面端居中对话框）
Future<void> showCategoryReorderSheet(BuildContext context) async {
  final isDesktop = MediaQuery.of(context).size.width >= 800;
  if (isDesktop) {
    await showDialog(
      context: context,
      useRootNavigator: true,
      builder: (ctx) => Dialog(
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(24)),
        ),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 440, maxHeight: 620),
          child: const _CategoryReorderContent(isDesktop: true),
        ),
      ),
    );
  } else {
    await showModalBottomSheet(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        final screenHeight = MediaQuery.of(ctx).size.height;
        return ConstrainedBox(
          constraints: BoxConstraints(maxHeight: screenHeight * 0.85),
          child: const SafeArea(
            child: _CategoryReorderContent(isDesktop: false),
          ),
        );
      },
    );
  }
}

class _CategoryReorderContent extends ConsumerStatefulWidget {
  final bool isDesktop;
  const _CategoryReorderContent({required this.isDesktop});

  @override
  ConsumerState<_CategoryReorderContent> createState() => _CategoryReorderContentState();
}

class _CategoryReorderContentState extends ConsumerState<_CategoryReorderContent> {
  late List<CategoryItem> _items;

  @override
  void initState() {
    super.initState();
    _items = List<CategoryItem>.from(ref.read(orderedCategoriesProvider));
  }

  void _onReorder(int oldIndex, int newIndex) {
    setState(() {
      if (oldIndex < newIndex) {
        newIndex -= 1;
      }
      final item = _items.removeAt(oldIndex);
      _items.insert(newIndex, item);
    });
    HapticFeedback.selectionClick();
  }

  Future<void> _saveAndClose() async {
    final newOrderIds = _items.map((e) => e.id).toList();
    await ref.read(appSettingsProvider.notifier).setCategoryOrder(newOrderIds);
    HapticFeedback.mediumImpact();
    if (mounted) {
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('分类标签顺序已更新'),
          duration: Duration(seconds: 2),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _resetToDefault() async {
    setState(() {
      _items = List<CategoryItem>.from(defaultCategories);
    });
    HapticFeedback.lightImpact();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 移动端顶部滑动手柄线
          if (!widget.isDesktop) ...[
            Center(
              child: Container(
                width: 38,
                height: 4,
                margin: const EdgeInsets.only(bottom: 14),
                decoration: BoxDecoration(
                  color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.35),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
          ],

          // 头部标题与重置按钮
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '自定义分类顺序',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '长按右侧手柄拖拽排序，常用分类可置前',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.outline,
                      ),
                    ),
                  ],
                ),
              ),
              TextButton.icon(
                icon: const Icon(Icons.restore_rounded, size: 16),
                label: const Text('重置默认'),
                style: TextButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                ),
                onPressed: _resetToDefault,
              ),
            ],
          ),
          const SizedBox(height: 12),
          const Divider(height: 1),
          const SizedBox(height: 8),

          // 拖拽排序列表
          Flexible(
            child: ReorderableListView.builder(
              shrinkWrap: true,
              itemCount: _items.length,
              buildDefaultDragHandles: false,
              proxyDecorator: (Widget child, int index, Animation<double> animation) {
                return AnimatedBuilder(
                  animation: animation,
                  builder: (context, _) {
                    final double scale = 1.0 + (0.02 * animation.value);
                    return Transform.scale(
                      scale: scale,
                      child: Material(
                        elevation: 4,
                        shadowColor: Colors.black26,
                        borderRadius: BorderRadius.circular(14),
                        color: theme.colorScheme.surface,
                        child: child,
                      ),
                    );
                  },
                );
              },
              onReorder: _onReorder,
              itemBuilder: (context, index) {
                final item = _items[index];
                return Container(
                  key: ValueKey(item.id),
                  margin: const EdgeInsets.symmetric(vertical: 4),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surfaceVariant.withValues(alpha: 0.25),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: theme.colorScheme.outlineVariant.withValues(alpha: 0.35),
                    ),
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.primaryContainer.withValues(alpha: 0.5),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          item.icon,
                          size: 18,
                          color: theme.colorScheme.primary,
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Text(
                          item.label,
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      ReorderableDragStartListener(
                        index: index,
                        child: Padding(
                          padding: const EdgeInsets.all(6),
                          child: Icon(
                            Icons.drag_handle_rounded,
                            color: theme.colorScheme.outline,
                            size: 20,
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),

          const SizedBox(height: 16),

          // 底部保存并应用按钮
          FilledButton.icon(
            icon: const Icon(Icons.check_rounded, size: 18),
            label: const Text('保存并应用排序'),
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(44),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
            onPressed: _saveAndClose,
          ),
        ],
      ),
    );
  }
}
