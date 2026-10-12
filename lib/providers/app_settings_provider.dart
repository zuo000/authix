import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/database/database_helper.dart';
import '../models/credential.dart';

/// 凭据分类元数据实体定义
class CategoryItem {
  final String label;
  final CredentialType? type;
  final IconData icon;

  const CategoryItem({
    required this.label,
    required this.type,
    required this.icon,
  });

  String get id => type?.name ?? 'all';
}

/// 系统默认分类顺序
const defaultCategories = <CategoryItem>[
  CategoryItem(label: '全部凭据', type: null, icon: Icons.all_inclusive),
  CategoryItem(label: 'TOTP 动态码', type: CredentialType.totp, icon: Icons.timer_outlined),
  CategoryItem(label: '账号密码', type: CredentialType.password, icon: Icons.lock_outline),
  CategoryItem(label: '服务器私钥', type: CredentialType.serverKey, icon: Icons.terminal_rounded),
  CategoryItem(label: '通行密钥', type: CredentialType.passkey, icon: Icons.fingerprint_rounded),
  CategoryItem(label: '开发者密钥', type: CredentialType.apiKey, icon: Icons.vpn_key_outlined),
  CategoryItem(label: '钱包助记词', type: CredentialType.cryptoWallet, icon: Icons.account_balance_wallet_outlined),
  CategoryItem(label: '银行卡', type: CredentialType.card, icon: Icons.credit_card_rounded),
  CategoryItem(label: '身份档案', type: CredentialType.identity, icon: Icons.badge_outlined),
  CategoryItem(label: '安全备忘', type: CredentialType.secureNote, icon: Icons.note_alt_outlined),
];

enum CardDensity {
  comfortable('comfortable', '标准舒适'),
  compact('compact', '紧凑轻便');

  final String value;
  final String label;
  const CardDensity(this.value, this.label);

  static CardDensity fromString(String? val) {
    if (val == 'compact') return CardDensity.compact;
    return CardDensity.comfortable;
  }
}

/// 卡片列数排列模式（单列 / 双列）
enum CardColumnsMode {
  single('single', '单列排列'),
  double_('double', '双列排列');

  final String value;
  final String label;
  const CardColumnsMode(this.value, this.label);

  static CardColumnsMode fromString(String? val) {
    if (val == 'single') return CardColumnsMode.single;
    return CardColumnsMode.double_;
  }
}

/// 凭据列表排序规则
enum CredentialSortOption {
  custom('custom', '自定义拖拽排序', Icons.drag_handle_rounded),
  titleAsc('title_asc', '按名称 A → Z', Icons.sort_by_alpha_rounded),
  titleDesc('title_desc', '按名称 Z → A', Icons.sort_by_alpha_rounded),
  createdDesc('created_desc', '按添加时间 (新 → 旧)', Icons.schedule_rounded),
  createdAsc('created_asc', '按添加时间 (旧 → 新)', Icons.history_rounded),
  updatedDesc('updated_desc', '按最近修改时间', Icons.update_rounded);

  final String value;
  final String label;
  final IconData icon;
  const CredentialSortOption(this.value, this.label, this.icon);

  static CredentialSortOption fromString(String? val) {
    for (final opt in CredentialSortOption.values) {
      if (opt.value == val) return opt;
    }
    return CredentialSortOption.custom;
  }
}

class AppSettingsState {
  final ThemeMode themeMode;
  final bool appLockEnabled;
  final bool isUnlocked;
  final bool maskPasswordsByDefault;
  final CardDensity cardDensity;
  final CardColumnsMode cardColumnsMode;
  final CredentialSortOption sortOption;
  final List<String> categoryOrder;

  const AppSettingsState({
    this.themeMode = ThemeMode.system,
    this.appLockEnabled = false,
    this.isUnlocked = true,
    this.maskPasswordsByDefault = true,
    this.cardDensity = CardDensity.comfortable,
    this.cardColumnsMode = CardColumnsMode.double_,
    this.sortOption = CredentialSortOption.custom,
    this.categoryOrder = const [],
  });

  AppSettingsState copyWith({
    ThemeMode? themeMode,
    bool? appLockEnabled,
    bool? isUnlocked,
    bool? maskPasswordsByDefault,
    CardDensity? cardDensity,
    CardColumnsMode? cardColumnsMode,
    CredentialSortOption? sortOption,
    List<String>? categoryOrder,
  }) {
    return AppSettingsState(
      themeMode: themeMode ?? this.themeMode,
      appLockEnabled: appLockEnabled ?? this.appLockEnabled,
      isUnlocked: isUnlocked ?? this.isUnlocked,
      maskPasswordsByDefault: maskPasswordsByDefault ?? this.maskPasswordsByDefault,
      cardDensity: cardDensity ?? this.cardDensity,
      cardColumnsMode: cardColumnsMode ?? this.cardColumnsMode,
      sortOption: sortOption ?? this.sortOption,
      categoryOrder: categoryOrder ?? this.categoryOrder,
    );
  }
}

class AppSettingsNotifier extends StateNotifier<AppSettingsState> {
  AppSettingsNotifier() : super(const AppSettingsState()) {
    _loadSettings();
  }

  final _db = DatabaseHelper.instance;

  Future<void> _loadSettings() async {
    final themeStr = await _db.getSetting('theme_mode');
    final appLockStr = await _db.getSetting('app_lock_enabled');
    final maskStr = await _db.getSetting('mask_passwords');
    final densityStr = await _db.getSetting('card_density');
    final columnsStr = await _db.getSetting('card_columns_mode');
    final sortStr = await _db.getSetting('sort_option');
    final orderStr = await _db.getSetting('custom_category_order');

    ThemeMode mode = ThemeMode.system;
    if (themeStr == 'dark') mode = ThemeMode.dark;
    if (themeStr == 'light') mode = ThemeMode.light;

    final appLock = appLockStr == 'true';
    final mask = maskStr != 'false';
    final density = CardDensity.fromString(densityStr);
    final columns = CardColumnsMode.fromString(columnsStr);
    final sort = CredentialSortOption.fromString(sortStr);

    List<String> order = [];
    if (orderStr != null && orderStr.isNotEmpty) {
      try {
        final decoded = jsonDecode(orderStr);
        if (decoded is List) {
          order = decoded.map((e) => e.toString()).toList();
        }
      } catch (_) {}
    }

    state = state.copyWith(
      themeMode: mode,
      appLockEnabled: appLock,
      isUnlocked: !appLock, // 若开启应用锁，初始为未解锁状态
      maskPasswordsByDefault: mask,
      cardDensity: density,
      cardColumnsMode: columns,
      sortOption: sort,
      categoryOrder: order,
    );
  }

  Future<void> setCardDensity(CardDensity density) async {
    state = state.copyWith(cardDensity: density);
    await _db.setSetting('card_density', density.value);
  }

  Future<void> toggleCardDensity() async {
    final next = state.cardDensity == CardDensity.comfortable
        ? CardDensity.compact
        : CardDensity.comfortable;
    await setCardDensity(next);
  }

  Future<void> setCardColumnsMode(CardColumnsMode mode) async {
    state = state.copyWith(cardColumnsMode: mode);
    await _db.setSetting('card_columns_mode', mode.value);
  }

  Future<void> toggleCardColumnsMode() async {
    final next = state.cardColumnsMode == CardColumnsMode.double_
        ? CardColumnsMode.single
        : CardColumnsMode.double_;
    await setCardColumnsMode(next);
  }

  Future<void> setSortOption(CredentialSortOption option) async {
    state = state.copyWith(sortOption: option);
    await _db.setSetting('sort_option', option.value);
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    state = state.copyWith(themeMode: mode);
    String val = 'system';
    if (mode == ThemeMode.dark) val = 'dark';
    if (mode == ThemeMode.light) val = 'light';
    await _db.setSetting('theme_mode', val);
  }

  Future<void> toggleTheme() async {
    final next = switch (state.themeMode) {
      ThemeMode.system => ThemeMode.light,
      ThemeMode.light => ThemeMode.dark,
      ThemeMode.dark => ThemeMode.system,
    };
    await setThemeMode(next);
  }

  Future<void> setAppLockEnabled(bool enabled) async {
    state = state.copyWith(appLockEnabled: enabled, isUnlocked: true);
    await _db.setSetting('app_lock_enabled', enabled ? 'true' : 'false');
  }

  void setUnlocked(bool unlocked) {
    state = state.copyWith(isUnlocked: unlocked);
  }

  Future<void> toggleMaskPasswords() async {
    final newVal = !state.maskPasswordsByDefault;
    state = state.copyWith(maskPasswordsByDefault: newVal);
    await _db.setSetting('mask_passwords', newVal ? 'true' : 'false');
  }

  Future<void> setCategoryOrder(List<String> newOrder) async {
    state = state.copyWith(categoryOrder: newOrder);
    await _db.setSetting('custom_category_order', jsonEncode(newOrder));
  }

  Future<void> resetCategoryOrder() async {
    state = state.copyWith(categoryOrder: []);
    await _db.setSetting('custom_category_order', '');
  }
}

final appSettingsProvider = StateNotifierProvider<AppSettingsNotifier, AppSettingsState>((ref) {
  return AppSettingsNotifier();
});

/// 响应式的有效排序分类列表 Provider（桌面端与移动端统一使用）
final orderedCategoriesProvider = Provider<List<CategoryItem>>((ref) {
  final orderIds = ref.watch(appSettingsProvider).categoryOrder;
  if (orderIds.isEmpty) {
    return defaultCategories;
  }

  final Map<String, CategoryItem> map = {
    for (final item in defaultCategories) item.id: item,
  };

  final result = <CategoryItem>[];
  for (final id in orderIds) {
    final item = map.remove(id);
    if (item != null) {
      result.add(item);
    }
  }
  // 未在用户自定义列表中的新分类项，自动追加在末尾
  result.addAll(map.values);
  return result;
});
