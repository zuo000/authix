import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/credential.dart';
import '../../providers/vault_provider.dart';
import '../../providers/app_settings_provider.dart';
import 'category_reorder_sheet.dart';

/// 兼容旧引用的基础定义别名
const filterCategories = defaultCategories;

/// 凭据分类快速切换水平滑动条
class TypeFilterBar extends ConsumerStatefulWidget {
  const TypeFilterBar({super.key});

  @override
  ConsumerState<TypeFilterBar> createState() => _TypeFilterBarState();
}

class _TypeFilterBarState extends ConsumerState<TypeFilterBar> {
  final ScrollController _scrollController = ScrollController();
  final Map<String, GlobalKey> _itemKeys = {};

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollToSelected(CredentialType? selectedType, List<CategoryItem> categories) {
    final targetId = selectedType?.name ?? 'all';
    final targetKey = _itemKeys[targetId];
    if (targetKey == null || !mounted) return;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scrollController.hasClients) return;
      final currentContext = targetKey.currentContext;
      if (currentContext != null) {
        Scrollable.ensureVisible(
          currentContext,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeInOutCubic,
          alignment: 0.5, // 居中
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final selectedFilter = ref.watch(selectedTypeFilterProvider);
    final categories = ref.watch(orderedCategoriesProvider);
    final theme = Theme.of(context);

    ref.listen<CredentialType?>(selectedTypeFilterProvider, (_, next) {
      _scrollToSelected(next, categories);
    });

    return SizedBox(
      height: 48,
      child: SingleChildScrollView(
        controller: _scrollController,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
        child: Row(
          children: [
            for (int i = 0; i < categories.length; i++) ...[
              if (i > 0) const SizedBox(width: 8),
              () {
                final item = categories[i];
                final isSelected = selectedFilter == item.type;
                final key = _itemKeys.putIfAbsent(item.id, () => GlobalKey());

                return KeyedSubtree(
                  key: key,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onLongPress: () {
                      HapticFeedback.mediumImpact();
                      showCategoryReorderSheet(context);
                    },
                    child: FilterChip(
                      selected: isSelected,
                      avatar: Icon(
                        item.icon,
                        size: 16,
                        color: isSelected ? theme.colorScheme.onPrimary : theme.colorScheme.onSurfaceVariant,
                      ),
                      label: Text(item.label),
                      labelStyle: TextStyle(
                        fontSize: 13,
                        fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                        color: isSelected ? theme.colorScheme.onPrimary : theme.colorScheme.onSurface,
                      ),
                      selectedColor: theme.colorScheme.primary,
                      backgroundColor: theme.colorScheme.surfaceVariant.withOpacity(0.5),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                      side: BorderSide(
                        color: isSelected ? theme.colorScheme.primary : theme.colorScheme.outlineVariant.withOpacity(0.5),
                      ),
                      showCheckmark: false,
                      onSelected: (_) {
                        ref.read(selectedTypeFilterProvider.notifier).state = item.type;
                      },
                    ),
                  ),
                );
              }(),
            ],
          ],
        ),
      ),
    );
  }
}
