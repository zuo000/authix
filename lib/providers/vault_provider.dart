import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/backup/yaml_backup_service.dart';
import '../core/database/database_helper.dart';
import '../models/credential.dart';
import '../models/recovery_code.dart';
import 'app_settings_provider.dart';

/// 分类筛选状态
final selectedTypeFilterProvider = StateProvider<CredentialType?>((ref) => null);

/// 搜索关键词状态
final searchKeywordProvider = StateProvider<String>((ref) => '');

/// 全局每秒滴答时钟 Provider，用于驱动所有 TOTP 动态码和倒计时圆环同步刷新
final totpTickerProvider = StreamProvider<int>((ref) {
  return Stream.periodic(
    const Duration(seconds: 1),
    (_) => DateTime.now().millisecondsSinceEpoch ~/ 1000,
  );
});

/// 全局垃圾箱状态管理器
class TrashNotifier extends StateNotifier<AsyncValue<List<Credential>>> {
  TrashNotifier() : super(const AsyncValue.loading()) {
    loadTrash();
  }

  final _db = DatabaseHelper.instance;

  Future<void> loadTrash() async {
    try {
      final items = await _db.getTrashCredentials();
      state = AsyncValue.data(items);
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }
}

/// 垃圾箱凭据列表 Provider
final trashCredentialsProvider = StateNotifierProvider<TrashNotifier, AsyncValue<List<Credential>>>((ref) {
  return TrashNotifier();
});

/// 全局凭据仓库状态管理器
class VaultNotifier extends StateNotifier<AsyncValue<List<Credential>>> {
  final Ref _ref;

  VaultNotifier(this._ref) : super(const AsyncValue.loading()) {
    loadCredentials();
    _ref.read(trashCredentialsProvider.notifier).loadTrash();
  }

  final _db = DatabaseHelper.instance;

  /// 加载全部凭据
  Future<void> loadCredentials() async {
    try {
      final items = await _db.getAllCredentials();
      state = AsyncValue.data(items);
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }

  /// 添加凭据
  Future<void> addCredential(Credential credential) async {
    await _db.insertCredential(credential);
    await loadCredentials();
  }

  /// 更新凭据
  Future<void> updateCredential(Credential credential) async {
    await _db.updateCredential(credential);
    await loadCredentials();
  }

  /// 移入垃圾箱 (软删除) - 同步原子刷新主仓库与垃圾箱
  Future<void> moveToTrash(String id) async {
    await _db.moveToTrash(id);
    await Future.wait([
      loadCredentials(),
      _ref.read(trashCredentialsProvider.notifier).loadTrash(),
    ]);
  }

  /// 从垃圾箱恢复凭据 - 同步原子刷新主仓库与垃圾箱
  Future<void> restoreFromTrash(String id) async {
    await _db.restoreFromTrash(id);
    await Future.wait([
      loadCredentials(),
      _ref.read(trashCredentialsProvider.notifier).loadTrash(),
    ]);
  }

  /// 清空垃圾箱 - 同步原子刷新主仓库与垃圾箱
  Future<void> emptyTrash() async {
    await _db.emptyTrash();
    await Future.wait([
      loadCredentials(),
      _ref.read(trashCredentialsProvider.notifier).loadTrash(),
    ]);
  }

  /// 永久彻底删除凭据 - 同步原子刷新主仓库与垃圾箱
  Future<void> deleteCredential(String id) async {
    await _db.deleteCredential(id);
    await Future.wait([
      loadCredentials(),
      _ref.read(trashCredentialsProvider.notifier).loadTrash(),
    ]);
  }

  /// 切换置顶
  Future<void> togglePin(String id, bool currentPinned) async {
    await _db.togglePin(id, currentPinned);
    await loadCredentials();
  }

  /// 标记 2FA 恢复码为已使用/未使用
  Future<void> toggleRecoveryCodeUsed(String credentialId, int codeIndex) async {
    final currentList = state.value;
    if (currentList == null) return;

    final target = currentList.firstWhere((e) => e.id == credentialId);
    if (codeIndex < 0 || codeIndex >= target.recoveryCodes.length) return;

    final updatedCodes = List<RecoveryCode>.from(target.recoveryCodes);
    final currentCode = updatedCodes[codeIndex];
    updatedCodes[codeIndex] = currentCode.copyWith(used: !currentCode.used);

    final updatedCred = target.copyWith(recoveryCodes: updatedCodes);
    await updateCredential(updatedCred);
  }

  /// 批量从备份恢复凭据并重新加载
  Future<int> restoreCredentials(List<Credential> items, RestoreConflictStrategy strategy) async {
    final count = await YamlBackupService.executeImport(newItems: items, strategy: strategy);
    await Future.wait([
      loadCredentials(),
      _ref.read(trashCredentialsProvider.notifier).loadTrash(),
    ]);
    return count;
  }

  /// 手动调整凭据排序顺序并即时持久化到数据库
  Future<void> reorder(int oldIndex, int newIndex) async {
    final currentList = state.value;
    if (currentList == null) return;
    final items = List<Credential>.from(currentList);
    if (oldIndex < newIndex) {
      newIndex -= 1;
    }
    final movedItem = items.removeAt(oldIndex);
    items.insert(newIndex, movedItem);

    // 关键：为内存中所有条目重新赋值更新后的 sortOrder，防止被排序比较器重新弹回原位
    final updatedItems = [
      for (int i = 0; i < items.length; i++)
        items[i].copyWith(sortOrder: i),
    ];

    // 乐观立即刷新 UI
    state = AsyncValue.data(updatedItems);

    // 异步更新数据库中全部条目的 sort_order
    final orderedIds = updatedItems.map((e) => e.id).toList();
    await _db.updateSortOrders(orderedIds);
  }

  /// 根据凭据 ID 将 movedId 移动至 targetId 位置并持久化（支持跨列/网格拖拽，after 为 true 表示插在目标后）
  Future<void> moveItem(String movedId, String targetId, {bool after = false}) async {
    final currentList = state.value;
    if (currentList == null) return;
    final items = List<Credential>.from(currentList);
    final oldIndex = items.indexWhere((e) => e.id == movedId);
    final targetIndex = items.indexWhere((e) => e.id == targetId);

    if (oldIndex == -1 || targetIndex == -1 || oldIndex == targetIndex) return;

    final movedItem = items.removeAt(oldIndex);
    var insertIndex = items.indexWhere((e) => e.id == targetId);
    if (after) {
      insertIndex += 1;
    }
    items.insert(insertIndex, movedItem);

    // 关键：为内存中所有条目重新赋值更新后的 sortOrder，防止被排序比较器重新弹回原位
    final updatedItems = [
      for (int i = 0; i < items.length; i++)
        items[i].copyWith(sortOrder: i),
    ];

    // 乐观立即刷新 UI
    state = AsyncValue.data(updatedItems);

    // 异步更新数据库中全部条目的 sort_order
    final orderedIds = updatedItems.map((e) => e.id).toList();
    await _db.updateSortOrders(orderedIds);
  }
}

final vaultProvider = StateNotifierProvider<VaultNotifier, AsyncValue<List<Credential>>>((ref) {
  return VaultNotifier(ref);
});

/// 根据搜索词、类型过滤及选定排序规则计算的凭据列表
final filteredCredentialsProvider = Provider<List<Credential>>((ref) {
  final vaultAsync = ref.watch(vaultProvider);
  final keyword = ref.watch(searchKeywordProvider).trim().toLowerCase();
  final filterType = ref.watch(selectedTypeFilterProvider);
  final sortOption = ref.watch(appSettingsProvider).sortOption;

  return vaultAsync.when(
    data: (items) {
      final list = items.where((item) {
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

      list.sort((a, b) {
        if (a.pinned != b.pinned) {
          return a.pinned ? -1 : 1;
        }

        return switch (sortOption) {
          CredentialSortOption.custom => a.sortOrder.compareTo(b.sortOrder),
          CredentialSortOption.titleAsc => a.title.toLowerCase().compareTo(b.title.toLowerCase()),
          CredentialSortOption.titleDesc => b.title.toLowerCase().compareTo(a.title.toLowerCase()),
          CredentialSortOption.createdDesc => b.createdAt.compareTo(a.createdAt),
          CredentialSortOption.createdAsc => a.createdAt.compareTo(b.createdAt),
          CredentialSortOption.updatedDesc => b.updatedAt.compareTo(a.updatedAt),
        };
      });

      return list;
    },
    loading: () => [],
    error: (_, __) => [],
  );
});
