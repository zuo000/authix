import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/credential.dart';
import '../../providers/vault_provider.dart';
import '../../providers/app_settings_provider.dart';
import '../../core/utils/ime_utils.dart';
import '../widgets/type_filter_bar.dart';
import '../widgets/credential_card.dart';
import '../widgets/category_reorder_sheet.dart';
import 'edit_credential_screen.dart';
import 'backup_restore_screen.dart';
import 'trash_screen.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  final TextEditingController _searchController = TextEditingController();
  bool _isSearching = false;
  late final PageController _pageController;
  bool _isPageAnimating = false;

  static const int _loopMultiplier = 10000;

  @override
  void initState() {
    super.initState();
    final categories = ref.read(orderedCategoriesProvider);
    final initialFilter = ref.read(selectedTypeFilterProvider);
    final initialIndex = categories.indexWhere((c) => c.type == initialFilter);
    final realIndex = initialIndex >= 0 ? initialIndex : 0;
    final base = _loopMultiplier * categories.length;
    _pageController = PageController(initialPage: base + realIndex);
  }

  @override
  void dispose() {
    _pageController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  void _openAddCredential([CredentialType? defaultType]) {
    final currentFilter = ref.read(selectedTypeFilterProvider);
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => EditCredentialScreen(
          defaultType: defaultType ?? currentFilter ?? CredentialType.totp,
        ),
      ),
    );
  }

  void _showAddTypePicker() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        final screenHeight = MediaQuery.of(ctx).size.height;
        return ConstrainedBox(
          constraints: BoxConstraints(maxHeight: screenHeight * 0.85),
          child: SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      margin: const EdgeInsets.only(bottom: 16),
                      decoration: BoxDecoration(
                        color: Colors.grey.shade400,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  Text(
                    '添加新凭据',
                    style: Theme.of(ctx).textTheme.titleLarge
                        ?.copyWith(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '选择要创建的凭据类型：',
                    style: Theme.of(ctx).textTheme.bodySmall
                        ?.copyWith(color: Theme.of(ctx).colorScheme.outline),
                  ),
                  const SizedBox(height: 16),
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final count = constraints.maxWidth > 540 ? 5 : 4;
                      return GridView.count(
                        crossAxisCount: count,
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        mainAxisSpacing: 10,
                        crossAxisSpacing: 10,
                        childAspectRatio: 1.0,
                        children: CredentialType.values.map((type) {
                          return InkWell(
                            borderRadius: BorderRadius.circular(16),
                            onTap: () {
                              Navigator.pop(ctx);
                              _openAddCredential(type);
                            },
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    color: Theme.of(ctx)
                                        .colorScheme
                                        .primaryContainer
                                        .withValues(alpha: 0.5),
                                    shape: BoxShape.circle,
                                  ),
                                  child: Icon(
                                    type.icon,
                                    color: Theme.of(ctx).colorScheme.primary,
                                  ),
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  type.label,
                                  style: const TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w500,
                                  ),
                                  textAlign: TextAlign.center,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ),
                          );
                        }).toList(),
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDesktop = MediaQuery.of(context).size.width >= 800;

    final vaultAsync = ref.watch(vaultProvider);
    final selectedFilter = ref.watch(selectedTypeFilterProvider);
    final categories = ref.watch(orderedCategoriesProvider);
    final isVaultEmpty = vaultAsync.asData?.value.isEmpty ?? false;

    // 监听分类顺序外部重排变化，保证移动端PageView瞬时对齐到当前所选分类的新页码
    ref.listen<List<CategoryItem>>(orderedCategoriesProvider, (prev, next) {
      if (isDesktop || !_pageController.hasClients) return;
      final currentFilter = ref.read(selectedTypeFilterProvider);
      final newIndex = next.indexWhere((c) => c.type == currentFilter);
      if (newIndex >= 0) {
        final base = _loopMultiplier * next.length;
        _pageController.jumpToPage(base + newIndex);
      }
    });

    // 监听移动端分类选中变化，平滑过渡滑动切页（桌面端采用符合侧边栏逻辑的原地平滑淡入切换）
    ref.listen<CredentialType?>(selectedTypeFilterProvider, (prev, next) {
      if (isDesktop) return;
      if (_isPageAnimating) return;
      final targetIndex = categories.indexWhere((c) => c.type == next);
      if (targetIndex >= 0 && _pageController.hasClients) {
        final currentPage = _pageController.page?.round() ?? _pageController.initialPage;
        final count = categories.length;
        final currentRealIndex = (currentPage % count + count) % count;
        if (currentRealIndex != targetIndex) {
          int delta = targetIndex - currentRealIndex;
          if (delta > count / 2) {
            delta -= count;
          } else if (delta < -count / 2) {
            delta += count;
          }
          final targetPage = currentPage + delta;
          _isPageAnimating = true;
          _pageController.animateToPage(
            targetPage,
            duration: const Duration(milliseconds: 320),
            curve: Curves.easeOutCubic,
          ).then((_) {
            _isPageAnimating = false;
          });
        }
      }
    });

    return Scaffold(
      appBar: AppBar(
        titleSpacing: isDesktop ? 16 : 10,
        title: _isSearching
            ? TextField(
                controller: _searchController,
                inputFormatters: const [ImeSafeTextInputFormatter()],
                autofocus: true,
                decoration: const InputDecoration(
                  hintText: '搜索标题、账号、域名、备注或标签...',
                  border: InputBorder.none,
                ),
                onChanged: (val) {
                  ref.read(searchKeywordProvider.notifier).state = val;
                },
              )
            : Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  PopupMenuButton<String>(
                    tooltip: '功能菜单',
                    offset: const Offset(0, 46),
                    clipBehavior: Clip.antiAlias,
                    borderRadius: BorderRadius.circular(8),
                    surfaceTintColor: Colors.transparent,
                    shadowColor: Colors.black.withValues(alpha: 0.35),
                    elevation: 6,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    onSelected: (val) {
                      if (val == 'backup_restore') {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => const BackupRestoreScreen(),
                          ),
                        );
                      } else if (val == 'trash') {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => const TrashScreen(),
                          ),
                        );
                      } else if (val == 'custom_categories') {
                        showCategoryReorderSheet(context);
                      } else if (val == 'theme_settings') {
                        _showThemeDialog();
                      } else if (val == 'about') {
                        _showAboutDialog();
                      }
                    },
                    itemBuilder: (ctx) {
                      final trashCount =
                          ref
                              .watch(trashCredentialsProvider)
                              .valueOrNull
                              ?.length ??
                          0;
                      final ThemeMode currentThemeMode = ref
                          .watch(appSettingsProvider)
                          .themeMode;
                      final (
                        themeModeTitle,
                        themeModeIcon,
                      ) = switch (currentThemeMode) {
                        ThemeMode.light => ('浅色模式', Icons.light_mode_outlined),
                        ThemeMode.dark => ('深色模式', Icons.dark_mode_outlined),
                        _ => ('跟随系统', Icons.brightness_auto_outlined),
                      };

                      return [
                        const PopupMenuItem(
                          value: 'backup_restore',
                          child: Row(
                            children: [
                              Icon(Icons.import_export_outlined, size: 20),
                              SizedBox(width: 10),
                              Text('备份与恢复'),
                            ],
                          ),
                        ),
                        PopupMenuItem(
                          value: 'trash',
                          child: Row(
                            children: [
                              const Icon(Icons.delete_outline, size: 20),
                              const SizedBox(width: 10),
                              Text(
                                trashCount > 0 ? '垃圾箱 ($trashCount)' : '垃圾箱',
                              ),
                            ],
                          ),
                        ),
                        const PopupMenuItem(
                          value: 'custom_categories',
                          child: Row(
                            children: [
                              Icon(Icons.tune_rounded, size: 20),
                              SizedBox(width: 10),
                              Text('自定义分类顺序'),
                            ],
                          ),
                        ),
                        const PopupMenuDivider(),
                        PopupMenuItem(
                          value: 'theme_settings',
                          child: Row(
                            children: [
                              Icon(themeModeIcon, size: 20),
                              const SizedBox(width: 10),
                              const Expanded(child: Text('外观主题')),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: theme.colorScheme.primary.withValues(
                                    alpha: 0.12,
                                  ),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Text(
                                  themeModeTitle,
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    color: theme.colorScheme.primary,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const PopupMenuItem(
                          value: 'about',
                          child: Row(
                            children: [
                              Icon(Icons.info_outline, size: 20),
                              SizedBox(width: 10),
                              Text('关于 Authix'),
                            ],
                          ),
                        ),
                      ];
                    },
                    child: MouseRegion(
                      cursor: SystemMouseCursors.click,
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: Image.asset(
                          'assets/icons/app_icon.png',
                          width: 28,
                          height: 28,
                          fit: BoxFit.cover,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      'Authix 密码库',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: isDesktop ? 18 : 16,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
        actions: [
          IconButton(
            visualDensity: isDesktop ? null : VisualDensity.compact,
            icon: Icon(_isSearching ? Icons.close : Icons.search),
            tooltip: _isSearching ? '关闭搜索' : '查找',
            onPressed: () {
              setState(() {
                if (_isSearching) {
                  _searchController.clear();
                  ref.read(searchKeywordProvider.notifier).state = '';
                  _isSearching = false;
                } else {
                  _isSearching = true;
                }
              });
            },
          ),
          // 排序与视图选项选择菜单
          Consumer(
            builder: (context, ref, _) {
              final currentSort = ref.watch(appSettingsProvider).sortOption;
              final currentDensity = ref.watch(appSettingsProvider).cardDensity;
              final isCompact = currentDensity == CardDensity.compact;

              return PopupMenuButton<dynamic>(
                icon: const Icon(Icons.sort_rounded),
                tooltip: isDesktop ? '排序规则' : '排序与视图选项',
                offset: const Offset(0, 46),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                onSelected: (val) {
                  if (val is CredentialSortOption) {
                    ref.read(appSettingsProvider.notifier).setSortOption(val);
                  } else if (val == 'toggle_density') {
                    ref.read(appSettingsProvider.notifier).toggleCardDensity();
                  }
                },
                itemBuilder: (ctx) => [
                  // 移动端在菜单内同时提供卡片紧凑/舒适切换，节省顶部按钮空间
                  if (!isDesktop) ...[
                    PopupMenuItem<String>(
                      value: 'toggle_density',
                      child: Row(
                        children: [
                          Icon(
                            isCompact ? Icons.density_small_rounded : Icons.density_medium_rounded,
                            size: 18,
                            color: theme.colorScheme.primary,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              isCompact ? '卡片视图：紧凑轻便' : '卡片视图：标准舒适',
                              style: TextStyle(
                                fontWeight: FontWeight.w600,
                                color: theme.colorScheme.primary,
                              ),
                            ),
                          ),
                          Text(
                            isCompact ? '点击切舒适' : '点击切紧凑',
                            style: TextStyle(
                              fontSize: 11,
                              color: theme.colorScheme.outline,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const PopupMenuDivider(),
                  ],
                  ...CredentialSortOption.values.map((opt) {
                    final isSelected = opt == currentSort;
                    return PopupMenuItem<CredentialSortOption>(
                      value: opt,
                      child: Row(
                        children: [
                          Icon(
                            opt.icon,
                            size: 18,
                            color: isSelected ? theme.colorScheme.primary : null,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              opt.label,
                              style: TextStyle(
                                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                                color: isSelected ? theme.colorScheme.primary : null,
                              ),
                            ),
                          ),
                          if (isSelected)
                            Icon(Icons.check_rounded, size: 18, color: theme.colorScheme.primary),
                        ],
                      ),
                    );
                  }),
                ],
              );
            },
          ),
          // 卡片单列 / 双列排列一键切换（移动端保留一键切换）
          Consumer(
            builder: (context, ref, _) {
              final columnsMode = ref.watch(appSettingsProvider).cardColumnsMode;
              final isSingle = columnsMode == CardColumnsMode.single;
              return IconButton(
                visualDensity: isDesktop ? null : VisualDensity.compact,
                icon: Icon(
                  isSingle ? Icons.view_agenda_rounded : Icons.grid_view_rounded,
                ),
                tooltip: isSingle ? '当前：单列排列 (点击切换为双列)' : '当前：双列排列 (点击切换为单列)',
                onPressed: () {
                  ref.read(appSettingsProvider.notifier).toggleCardColumnsMode();
                },
              );
            },
          ),
          // 仅在宽屏/桌面端展开卡片密度切换与分类排序按钮
          if (isDesktop) ...[
            Consumer(
              builder: (context, ref, _) {
                final density = ref.watch(appSettingsProvider).cardDensity;
                final isCompact = density == CardDensity.compact;
                return IconButton(
                  icon: Icon(
                    isCompact
                        ? Icons.density_small_rounded
                        : Icons.density_medium_rounded,
                  ),
                  tooltip: isCompact ? '当前：紧凑视图 (点击切换为舒适)' : '当前：舒适视图 (点击切换为紧凑)',
                  onPressed: () {
                    ref.read(appSettingsProvider.notifier).toggleCardDensity();
                  },
                );
              },
            ),
            IconButton(
              icon: const Icon(Icons.tune_rounded),
              tooltip: '自定义分类顺序',
              onPressed: () => showCategoryReorderSheet(context),
            ),
          ],
          IconButton(
            visualDensity: isDesktop ? null : VisualDensity.compact,
            icon: const Icon(Icons.add_rounded, size: 28),
            tooltip: '添加凭据',
            onPressed: _showAddTypePicker,
          ),
        ],
      ),
      body: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 宽屏/桌面端侧边分类导航
          if (isDesktop)
            LayoutBuilder(
              builder: (context, constraints) {
                final selectedRailIndex = categories.indexWhere((c) => c.type == selectedFilter);
                return SingleChildScrollView(
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      minHeight: constraints.maxHeight,
                    ),
                    child: IntrinsicHeight(
                      child: NavigationRail(
                        selectedIndex: selectedRailIndex >= 0 ? selectedRailIndex : 0,
                        onDestinationSelected: (idx) {
                          ref
                              .read(selectedTypeFilterProvider.notifier)
                              .state = categories[idx].type;
                        },
                        labelType: NavigationRailLabelType.all,
                        destinations: categories.map(
                          (c) => NavigationRailDestination(
                            icon: Icon(c.icon),
                            selectedIcon: Icon(c.icon),
                            label: Text(c.label),
                          ),
                        ).toList(),
                      ),
                    ),
                  ),
                );
              },
            ),

          // 主内容视图：通过 PageView 赋予原生高刷手感与物理弹性切页动效
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // 仅移动端展示顶部水平滚动分类过滤栏，桌面端已在左侧提供侧边导航栏
                if (!isDesktop) const TypeFilterBar(),

                // 凭据列表内容区：PageView 左右丝滑滑动切换分类，带1:1跟手阻尼与物理动效
                Expanded(
                  child: vaultAsync.when(
                    loading: () =>
                        const Center(child: CircularProgressIndicator()),
                    error: (err, _) => Center(child: Text('加载数据失败: $err')),
                    data: (allItems) {
                      // 桌面端：左侧垂直导航搭配符合桌面交互的平滑交叉淡入动效，消除横向大滑动的割裂感
                      if (isDesktop) {
                        final itemsForCategory =
                            _filterAndSortItems(allItems, selectedFilter);

                        return AnimatedSwitcher(
                          duration: const Duration(milliseconds: 220),
                          switchInCurve: Curves.easeOutCubic,
                          switchOutCurve: Curves.easeInCubic,
                          layoutBuilder: (Widget? currentChild, List<Widget> previousChildren) {
                            return Stack(
                              alignment: Alignment.topCenter,
                              fit: StackFit.expand,
                              children: <Widget>[
                                ...previousChildren,
                                if (currentChild != null) currentChild,
                              ],
                            );
                          },
                          transitionBuilder: (child, animation) {
                            return FadeTransition(
                              opacity: animation,
                              child: child,
                            );
                          },
                          child: KeyedSubtree(
                            key: ValueKey(selectedFilter),
                            child: RefreshIndicator(
                              onRefresh: () async {
                                await ref
                                    .read(vaultProvider.notifier)
                                    .loadCredentials();
                              },
                              child: itemsForCategory.isEmpty
                                  ? _buildEmptyState(theme, isVaultEmpty)
                                  : _buildCredentialView(
                                      itemsForCategory, isDesktop),
                            ),
                          ),
                        );
                      }

                      // 移动端：顶部横向分类栏搭配首尾相接无限循环的环形左右划屏 PageView
                      return PageView.builder(
                        controller: _pageController,
                        physics: const PageScrollPhysics(),
                        onPageChanged: (index) {
                          final count = categories.length;
                          final realIndex = (index % count + count) % count;
                          final targetType = categories[realIndex].type;
                          if (ref.read(selectedTypeFilterProvider) !=
                              targetType) {
                            HapticFeedback.selectionClick();
                            _isPageAnimating = true;
                            ref
                                .read(selectedTypeFilterProvider.notifier)
                                .state = targetType;
                            _isPageAnimating = false;
                          }
                        },
                        itemBuilder: (context, pageIndex) {
                          final count = categories.length;
                          final realIndex = (pageIndex % count + count) % count;
                          final categoryType = categories[realIndex].type;
                          final itemsForCategory =
                              _filterAndSortItems(allItems, categoryType);

                          return RefreshIndicator(
                            onRefresh: () async {
                              await ref
                                  .read(vaultProvider.notifier)
                                  .loadCredentials();
                            },
                            child: itemsForCategory.isEmpty
                                ? _buildEmptyState(theme, isVaultEmpty)
                                : _buildCredentialView(
                                    itemsForCategory, isDesktop),
                          );
                        },
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// 根据分类、搜索关键字和排序规则计算当前页面展示的凭据数据
  List<Credential> _filterAndSortItems(
    List<Credential> allItems,
    CredentialType? filterType,
  ) {
    final keyword = ref.watch(searchKeywordProvider).trim().toLowerCase();
    final sortOption = ref.watch(appSettingsProvider).sortOption;

    final list = allItems.where((item) {
      if (filterType != null && item.type != filterType) {
        return false;
      }

      if (keyword.isEmpty) return true;

      final inTitle = item.title.toLowerCase().contains(keyword);
      final inAccount = item.account.toLowerCase().contains(keyword);
      final inIssuer = item.issuer.toLowerCase().contains(keyword);
      final inHost = item.serverHost.toLowerCase().contains(keyword);
      final inNotes = item.notes.toLowerCase().contains(keyword);
      final inTags = item.tags.any((t) => t.toLowerCase().contains(keyword));

      return inTitle || inAccount || inIssuer || inHost || inNotes || inTags;
    }).toList();

    final categories = ref.watch(orderedCategoriesProvider);
    final categoryOrderMap = <CredentialType, int>{};
    for (int i = 0; i < categories.length; i++) {
      final t = categories[i].type;
      if (t != null) {
        categoryOrderMap[t] = i;
      }
    }

    list.sort((a, b) {
      if (a.pinned != b.pinned) {
        return a.pinned ? -1 : 1;
      }

      // 当在“全部凭据”视图下且为自定义排序时，优先依照用户自定义的分类顺序排列不同类别的凭据
      if (filterType == null && sortOption == CredentialSortOption.custom) {
        final orderA = categoryOrderMap[a.type] ?? 999;
        final orderB = categoryOrderMap[b.type] ?? 999;
        if (orderA != orderB) {
          return orderA.compareTo(orderB);
        }
      }

      return switch (sortOption) {
        CredentialSortOption.custom => a.sortOrder.compareTo(b.sortOrder),
        CredentialSortOption.titleAsc =>
          a.title.toLowerCase().compareTo(b.title.toLowerCase()),
        CredentialSortOption.titleDesc =>
          b.title.toLowerCase().compareTo(a.title.toLowerCase()),
        CredentialSortOption.createdDesc => b.createdAt.compareTo(a.createdAt),
        CredentialSortOption.createdAsc => a.createdAt.compareTo(b.createdAt),
        CredentialSortOption.updatedDesc => b.updatedAt.compareTo(a.updatedAt),
      };
    });

    return list;
  }

  /// 根据单列/双列模式排布卡片
  Widget _buildCredentialView(List<Credential> items, bool isDesktop) {
    final columnsMode = ref.watch(appSettingsProvider).cardColumnsMode;

    if (columnsMode == CardColumnsMode.single) {
      return _buildSingleColumnList(items, isDesktop);
    } else {
      return _buildDoubleColumnGrid(items, isDesktop);
    }
  }

  /// 单列列表视图（支持自定义拖拽排序）
  Widget _buildSingleColumnList(List<Credential> items, bool isDesktop) {
    final isSearching = ref.watch(searchKeywordProvider).trim().isNotEmpty;
    final sortOption = ref.watch(appSettingsProvider).sortOption;

    Widget listView;

    // 仅在未搜索且处于自定义排序规则时支持长按拖拽重排
    if (!isSearching && sortOption == CredentialSortOption.custom) {
      listView = ReorderableListView.builder(
        padding: EdgeInsets.symmetric(
          horizontal: isDesktop ? 20 : 16,
          vertical: 12,
        ),
        itemCount: items.length,
        buildDefaultDragHandles: false,
        proxyDecorator: (Widget child, int index, Animation<double> animation) {
          return AnimatedBuilder(
            animation: animation,
            builder: (BuildContext context, Widget? _) {
              final double animValue = Curves.easeInOut.transform(animation.value);
              final double scale = 1.0 + (0.02 * animValue);
              return Transform.scale(
                scale: scale,
                child: Material(
                  color: Colors.transparent,
                  shadowColor: Colors.transparent,
                  elevation: 0,
                  type: MaterialType.transparency,
                  child: child,
                ),
              );
            },
            child: child,
          );
        },
        onReorder: (oldIndex, newIndex) {
          ref.read(vaultProvider.notifier).reorder(oldIndex, newIndex);
        },
        itemBuilder: (ctx, index) {
          final item = items[index];
          Widget card = Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: CredentialCard(
              item: item,
              onEdit: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) =>
                        EditCredentialScreen(initialItem: item),
                  ),
                );
              },
              onDelete: () => _confirmDelete(item),
            ),
          );

          if (isDesktop) {
            card = Align(
              alignment: Alignment.topCenter,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 880),
                child: card,
              ),
            );
          }

          return ReorderableDelayedDragStartListener(
            key: ValueKey(item.id),
            index: index,
            child: card,
          );
        },
      );
    } else {
      listView = ListView.builder(
        padding: EdgeInsets.symmetric(
          horizontal: isDesktop ? 20 : 16,
          vertical: 12,
        ),
        itemCount: items.length,
        itemBuilder: (ctx, index) {
          final item = items[index];
          Widget card = Padding(
            key: ValueKey(item.id),
            padding: const EdgeInsets.only(bottom: 12),
            child: CredentialCard(
              item: item,
              onEdit: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) =>
                        EditCredentialScreen(initialItem: item),
                  ),
                );
              },
              onDelete: () => _confirmDelete(item),
            ),
          );

          if (isDesktop) {
            card = Align(
              key: ValueKey(item.id),
              alignment: Alignment.topCenter,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 880),
                child: card,
              ),
            );
          }

          return card;
        },
      );
    }

    return listView;
  }

  /// 双列瀑布流排列视图（移动端与桌面端均忠实响应双列设置，支持长按拖拽自定义排序）
  Widget _buildDoubleColumnGrid(List<Credential> items, bool isDesktop) {
    final theme = Theme.of(context);
    final isSearching = ref.watch(searchKeywordProvider).trim().isNotEmpty;
    final sortOption = ref.watch(appSettingsProvider).sortOption;
    final canReorder = !isSearching && sortOption == CredentialSortOption.custom;

    final columns = List.generate(2, (_) => <Credential>[]);
    for (var i = 0; i < items.length; i++) {
      columns[i % 2].add(items[i]);
    }

    final double horizontalPadding = isDesktop ? 20.0 : 10.0;
    final double columnSpacing = isDesktop ? 14.0 : 8.0;
    final double cardBottomSpacing = isDesktop ? 12.0 : 8.0;

    Widget buildCardWidget(Credential item, double colWidth) {
      final card = CredentialCard(
        key: ValueKey(item.id),
        item: item,
        onEdit: () {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => EditCredentialScreen(initialItem: item),
            ),
          );
        },
        onDelete: () => _confirmDelete(item),
      );

      if (!canReorder) {
        return Padding(
          padding: EdgeInsets.only(bottom: cardBottomSpacing),
          child: card,
        );
      }

      return DragTarget<String>(
        onWillAcceptWithDetails: (details) => details.data != item.id,
        onAcceptWithDetails: (details) {
          final movedId = details.data;
          HapticFeedback.mediumImpact();
          ref.read(vaultProvider.notifier).moveItem(movedId, item.id);
        },
        builder: (context, candidateData, rejectedData) {
          final isHovered = candidateData.isNotEmpty;

          return Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // 拖拽悬停时展开的平滑插槽：卡片及后续条目瞬间获得如同单列一样的移动让位物理动效
              AnimatedContainer(
                duration: const Duration(milliseconds: 220),
                curve: Curves.easeOutCubic,
                height: isHovered ? 68.0 : 0.0,
                margin: EdgeInsets.only(
                  bottom: isHovered ? cardBottomSpacing : 0.0,
                ),
                decoration: BoxDecoration(
                  color: isHovered
                      ? theme.colorScheme.primaryContainer.withValues(alpha: 0.35)
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(16),
                  border: isHovered
                      ? Border.all(
                          color: theme.colorScheme.primary,
                          width: 2,
                        )
                      : null,
                ),
                child: isHovered
                    ? Center(
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.south_rounded,
                              size: 16,
                              color: theme.colorScheme.primary,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              '移动至此处',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.bold,
                                color: theme.colorScheme.primary,
                              ),
                            ),
                          ],
                        ),
                      )
                    : const SizedBox.shrink(),
              ),

              // 卡片本体：长按浮起，原位置半透明占位
              Padding(
                padding: EdgeInsets.only(bottom: cardBottomSpacing),
                child: LongPressDraggable<String>(
                  data: item.id,
                  delay: const Duration(milliseconds: 300),
                  feedback: SizedBox(
                    width: colWidth > 0 ? colWidth : 360,
                    child: Material(
                      color: Colors.transparent,
                      elevation: 0,
                      type: MaterialType.transparency,
                      child: Transform.scale(
                        scale: 1.02,
                        child: CredentialCard(
                          item: item,
                          onEdit: () {},
                          onDelete: () {},
                        ),
                      ),
                    ),
                  ),
                  childWhenDragging: Opacity(
                    opacity: 0.25,
                    child: card,
                  ),
                  child: card,
                ),
              ),
            ],
          );
        },
      );
    }

    Widget buildColumnDropEndZone(int colIdx) {
      if (!canReorder || columns[colIdx].isEmpty) {
        return const SizedBox.shrink();
      }
      final lastItem = columns[colIdx].last;

      return DragTarget<String>(
        onWillAcceptWithDetails: (details) => details.data != lastItem.id,
        onAcceptWithDetails: (details) {
          final movedId = details.data;
          HapticFeedback.mediumImpact();
          ref.read(vaultProvider.notifier).moveItem(movedId, lastItem.id, after: true);
        },
        builder: (context, candidateData, rejectedData) {
          final isHovered = candidateData.isNotEmpty;
          return AnimatedContainer(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOutCubic,
            height: isHovered ? 56.0 : 16.0,
            margin: EdgeInsets.only(bottom: isHovered ? 12.0 : 0.0),
            decoration: BoxDecoration(
              color: isHovered
                  ? theme.colorScheme.primaryContainer.withValues(alpha: 0.35)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(14),
              border: isHovered
                  ? Border.all(
                      color: theme.colorScheme.primary,
                      width: 2,
                    )
                  : null,
            ),
            child: isHovered
                ? Center(
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.arrow_downward_rounded,
                          size: 16,
                          color: theme.colorScheme.primary,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          '放置在此列末尾',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: theme.colorScheme.primary,
                          ),
                        ),
                      ],
                    ),
                  )
                : const SizedBox.shrink(),
          );
        },
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final double maxContentWidth = isDesktop ? 1080.0 : constraints.maxWidth;
        final double effectiveWidth =
            constraints.maxWidth > maxContentWidth ? maxContentWidth : constraints.maxWidth;
        final double colWidth =
            (effectiveWidth - (horizontalPadding * 2) - columnSpacing) / 2;

        final Widget gridContent = Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                children: [
                  for (final item in columns[0])
                    buildCardWidget(item, colWidth),
                  buildColumnDropEndZone(0),
                ],
              ),
            ),
            SizedBox(width: columnSpacing),
            Expanded(
              child: Column(
                children: [
                  for (final item in columns[1])
                    buildCardWidget(item, colWidth),
                  buildColumnDropEndZone(1),
                ],
              ),
            ),
          ],
        );

        return SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: EdgeInsets.symmetric(
            horizontal: horizontalPadding,
            vertical: 12,
          ),
          child: isDesktop
              ? Align(
                  alignment: Alignment.topCenter,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 1080),
                    child: gridContent,
                  ),
                )
              : gridContent,
        );
      },
    );
  }

  Widget _buildEmptyState(ThemeData theme, bool isVaultCompletelyEmpty) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: theme.colorScheme.primaryContainer.withValues(
                  alpha: 0.3,
                ),
                shape: BoxShape.circle,
              ),
              child: Icon(
                isVaultCompletelyEmpty
                    ? Icons.lock_open_rounded
                    : Icons.search_off_rounded,
                size: 64,
                color: theme.colorScheme.primary,
              ),
            ),
            const SizedBox(height: 20),
            Text(
              isVaultCompletelyEmpty ? '本地密码库为空' : '未找到匹配凭据',
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              isVaultCompletelyEmpty
                  ? '点击右上角「+」即可添加第一条凭据'
                  : '试试清除搜索关键字或切换分类筛选条件',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 24),
            if (isVaultCompletelyEmpty)
              Wrap(
                spacing: 12,
                runSpacing: 12,
                alignment: WrapAlignment.center,
                children: [
                  FilledButton.icon(
                    onPressed: _showAddTypePicker,
                    icon: const Icon(Icons.add),
                    label: const Text('录入第一条凭据'),
                  ),
                  OutlinedButton.icon(
                    onPressed: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => const BackupRestoreScreen(),
                        ),
                      );
                    },
                    icon: const Icon(Icons.file_open_outlined),
                    label: const Text('从备份恢复数据'),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmDelete(Credential item) async {
    // 移入垃圾箱机制
    await ref.read(vaultProvider.notifier).moveToTrash(item.id);
    if (mounted) {
      final messenger = ScaffoldMessenger.of(context);
      messenger.clearSnackBars();
      messenger.showSnackBar(
        SnackBar(
          content: Text('已将「${item.title}」移入垃圾箱'),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 3),
          showCloseIcon: true,
          dismissDirection: DismissDirection.horizontal,
          onVisible: () {
            Future.delayed(const Duration(seconds: 3), () {
              if (mounted) {
                messenger.hideCurrentSnackBar();
              }
            });
          },
          action: SnackBarAction(
            label: '撤销',
            onPressed: () {
              messenger.hideCurrentSnackBar();
              ref.read(vaultProvider.notifier).restoreFromTrash(item.id);
            },
          ),
        ),
      );
    }
  }

  void _showThemeDialog() {
    showDialog(
      context: context,
      builder: (ctx) {
        return Consumer(
          builder: (context, ref, _) {
            final currentMode = ref.watch(appSettingsProvider).themeMode;
            final theme = Theme.of(context);

            Widget buildThemeOption({
              required ThemeMode mode,
              required String title,
              required String description,
              required IconData icon,
            }) {
              final isSelected = currentMode == mode;
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(14),
                    onTap: () {
                      HapticFeedback.selectionClick();
                      ref.read(appSettingsProvider.notifier).setThemeMode(mode);
                      Navigator.of(ctx).pop();
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 14,
                      ),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: isSelected
                              ? theme.colorScheme.primary
                              : theme.colorScheme.outlineVariant.withValues(
                                  alpha: 0.5,
                                ),
                          width: isSelected ? 2 : 1,
                        ),
                        color: isSelected
                            ? theme.colorScheme.primaryContainer.withValues(
                                alpha: 0.25,
                              )
                            : theme.colorScheme.surface,
                      ),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: isSelected
                                  ? theme.colorScheme.primary.withValues(
                                      alpha: 0.15,
                                    )
                                  : theme.colorScheme.surfaceContainerHighest
                                        .withValues(alpha: 0.5),
                            ),
                            child: Icon(
                              icon,
                              color: isSelected
                                  ? theme.colorScheme.primary
                                  : theme.colorScheme.onSurfaceVariant,
                              size: 20,
                            ),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  title,
                                  style: TextStyle(
                                    fontWeight: isSelected
                                        ? FontWeight.bold
                                        : FontWeight.w600,
                                    fontSize: 15,
                                    color: isSelected
                                        ? theme.colorScheme.primary
                                        : theme.colorScheme.onSurface,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  description,
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: theme.colorScheme.onSurfaceVariant,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          if (isSelected)
                            Icon(
                              Icons.check_circle,
                              color: theme.colorScheme.primary,
                              size: 22,
                            )
                          else
                            Icon(
                              Icons.radio_button_unchecked,
                              color: theme.colorScheme.outlineVariant,
                              size: 22,
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            }

            return AlertDialog(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
              title: const Row(
                children: [
                  Icon(Icons.palette_outlined),
                  SizedBox(width: 10),
                  Text('外观主题'),
                ],
              ),
              content: SizedBox(
                width: 380,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      buildThemeOption(
                        mode: ThemeMode.system,
                        title: '跟随系统',
                        description: '自动与操作系统的深浅外观设置保持同步',
                        icon: Icons.brightness_auto_outlined,
                      ),
                      buildThemeOption(
                        mode: ThemeMode.light,
                        title: '浅色模式',
                        description: '保持明亮清爽的经典浅色视觉风格',
                        icon: Icons.light_mode_outlined,
                      ),
                      buildThemeOption(
                        mode: ThemeMode.dark,
                        title: '深色模式',
                        description: '深色暗黑低对比，暗光环境下更护眼',
                        icon: Icons.dark_mode_outlined,
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  void _showAboutDialog() {
    showAboutDialog(
      context: context,
      applicationName: 'Authix',
      applicationVersion: '1.0.0',
      applicationIcon: ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: Image.asset(
          'assets/icons/app_icon.png',
          width: 48,
          height: 48,
          fit: BoxFit.cover,
        ),
      ),
      children: const [
        Text('纯离线多端密码管理器与 TOTP 二次验证器。'),
        SizedBox(height: 8),
        Text('• 零网络连接，全本地存储'),
        Text('• 跨平台支持：Windows / macOS / Linux / Android / iOS'),
        Text('• 支持完整数据离线备份与迁移恢复'),
        Text('• 包含 2FA 应急恢复码、SSH Key、API Key 与冷钱包存储'),
      ],
    );
  }
}
