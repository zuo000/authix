import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/backup/yaml_backup_service.dart';
import '../../models/credential.dart';
import '../../providers/vault_provider.dart';

class BackupRestoreScreen extends ConsumerStatefulWidget {
  const BackupRestoreScreen({super.key});

  @override
  ConsumerState<BackupRestoreScreen> createState() => _BackupRestoreScreenState();
}

class _BackupRestoreScreenState extends ConsumerState<BackupRestoreScreen> {
  bool _isLoading = false;
  String? _statusMessage;
  YamlImportPreview? _previewResult;
  RestoreConflictStrategy _selectedStrategy = RestoreConflictStrategy.skipExisting;

  Future<void> _handleExport() async {
    setState(() {
      _isLoading = true;
      _statusMessage = '正在导出本地凭据并生成备份...';
    });

    try {
      final savedPath = await YamlBackupService.exportAndSave();

      if (!mounted) return;
      if (savedPath != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('已成功导出备份文件：\n$savedPath'),
            backgroundColor: Colors.green.shade700,
            duration: const Duration(seconds: 4),
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('导出失败: $e'),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _statusMessage = null;
        });
      }
    }
  }

  Future<void> _handleSelectFileToImport() async {
    setState(() {
      _isLoading = true;
      _statusMessage = '正在选择并解析备份文件...';
    });

    try {
      final fileContent = await YamlBackupService.pickAndReadBackupFile();
      if (!mounted) return;

      if (fileContent == null) {
        setState(() {
          _isLoading = false;
          _statusMessage = null;
        });
        return;
      }

      final preview = YamlBackupService.parseYamlString(fileContent);

      setState(() {
        _previewResult = preview;
        _isLoading = false;
        _statusMessage = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _statusMessage = null;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('导入解析失败: $e'),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
    }
  }

  Future<void> _confirmRestore() async {
    final preview = _previewResult;
    if (preview == null || preview.validItems.isEmpty) return;

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('确认恢复凭据'),
        content: Text(
          '将以「${_selectedStrategy.description}」策略导入 ${preview.validItems.length} 条凭据到本地数据库。\n该操作不可撤销，确定继续吗？',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('确认写入'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    setState(() {
      _isLoading = true;
      _statusMessage = '正在将数据批量存入本地 SQLite 数据库...';
    });

    try {
      final importedCount = await ref
          .read(vaultProvider.notifier)
          .restoreCredentials(preview.validItems, _selectedStrategy);

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('成功恢复 $importedCount 条凭据！'),
          backgroundColor: Colors.green.shade700,
        ),
      );

      setState(() {
        _previewResult = null;
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('恢复写入失败: $e'),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _statusMessage = null;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final vaultAsync = ref.watch(vaultProvider);
    final vaultCount = vaultAsync.asData?.value.length ?? 0;

    return Scaffold(
      appBar: AppBar(
        title: const Text('备份与恢复'),
      ),
      body: Stack(
        children: [
          ListView(
            padding: const EdgeInsets.all(20),
            children: [
              // 导出区域
              Text('本地数据导出', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
              const SizedBox(height: 10),
              Card(
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                  side: BorderSide(color: theme.colorScheme.outlineVariant),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(18),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Colors.blue.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: const Icon(Icons.upload_file_outlined, color: Colors.blue),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text('导出完整数据备份', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                                const SizedBox(height: 4),
                                Text(
                                  '当前本地金库共包含 $vaultCount 项凭据',
                                  style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton.icon(
                          onPressed: _isLoading || vaultCount == 0 ? null : _handleExport,
                          icon: const Icon(Icons.file_download_outlined),
                          label: const Text('立即导出备份文件'),
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 32),

              // 恢复导入区域
              Text('从备份文件恢复', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
              const SizedBox(height: 10),
              Card(
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                  side: BorderSide(color: theme.colorScheme.outlineVariant),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(18),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Colors.green.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: const Icon(Icons.file_open_outlined, color: Colors.green),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text('选择备份文件导入', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                                const SizedBox(height: 4),
                                Text(
                                  '支持由 Authix 导出的备份文件',
                                  style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          onPressed: _isLoading ? null : _handleSelectFileToImport,
                          icon: const Icon(Icons.folder_open_outlined),
                          label: const Text('选择本地备份文件'),
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              if (_previewResult != null) ...[
                const SizedBox(height: 24),
                _buildPreviewSection(theme, _previewResult!),
              ],

              const SizedBox(height: 40),
            ],
          ),

          if (_isLoading)
            Container(
              color: Colors.black45,
              child: Center(
                child: Card(
                  elevation: 6,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const CircularProgressIndicator(),
                        const SizedBox(height: 16),
                        Text(_statusMessage ?? '处理中...'),
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildPreviewSection(ThemeData theme, YamlImportPreview preview) {
    final typeStats = <CredentialType, int>{};
    for (final c in preview.validItems) {
      typeStats[c.type] = (typeStats[c.type] ?? 0) + 1;
    }

    return Material(
      color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: theme.colorScheme.primary.withValues(alpha: 0.4)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.check_circle_outline, color: theme.colorScheme.primary),
                const SizedBox(width: 8),
                Text(
                  '备份文件解析成功 (共 ${preview.totalCount} 项)',
                  style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                ),
              ],
            ),
            if (preview.warnings.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                '提示: ${preview.warnings.join(", ")}',
                style: TextStyle(color: Colors.amber.shade800, fontSize: 12),
              ),
            ],
            const Divider(height: 24),
            Text(
              '有效待导入凭据统计 (共 ${preview.validItems.length} 项)：',
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: typeStats.entries.map((entry) {
                return Chip(
                  avatar: Icon(entry.key.icon, size: 16),
                  label: Text('${entry.key.label} × ${entry.value}'),
                  visualDensity: VisualDensity.compact,
                );
              }).toList(),
            ),
          const SizedBox(height: 20),
          Text('冲突解决策略：', style: const TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          ...RestoreConflictStrategy.values.map((strat) {
            return RadioListTile<RestoreConflictStrategy>(
              value: strat,
              groupValue: _selectedStrategy,
              title: Text(strat.description, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
              contentPadding: EdgeInsets.zero,
              dense: true,
              onChanged: (val) {
                if (val != null) setState(() => _selectedStrategy = val);
              },
            );
          }),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => setState(() => _previewResult = null),
                  child: const Text('放弃导入'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton(
                  onPressed: _confirmRestore,
                  child: const Text('确认恢复写入'),
                ),
              ),
            ],
          ),
        ],
      ),
    ),
  );
}
}
