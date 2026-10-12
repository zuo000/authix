import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';
import 'package:yaml/yaml.dart';
import '../../models/credential.dart';
import '../database/database_helper.dart';

/// 恢复冲突解决策略
enum RestoreConflictStrategy {
  skipExisting('跳过已存在的凭据'),
  overwriteExisting('覆盖已存在的凭据'),
  appendAsNew('全部作为新条目追加');

  final String description;
  const RestoreConflictStrategy(this.description);
}

/// 导入解析结果
class YamlImportPreview {
  final int totalCount;
  final List<Credential> validItems;
  final List<String> warnings;

  const YamlImportPreview({
    required this.totalCount,
    required this.validItems,
    this.warnings = const [],
  });
}

/// 纯离线 YAML 明文备份与恢复服务
class YamlBackupService {
  /// 生成标准的 YAML 格式文本
  static String exportToYamlString(List<Credential> items) {
    final nowIso = DateTime.now().toUtc().toIso8601String();
    final sb = StringBuffer();

    sb.writeln('# Authix 离线明文备份文件');
    sb.writeln('version: 1');
    sb.writeln('app: Authix');
    sb.writeln('exported_at: "$nowIso"');
    sb.writeln('count: ${items.length}');
    sb.writeln();
    sb.writeln('items:');

    if (items.isEmpty) {
      sb.writeln('  []');
      return sb.toString();
    }

    for (final item in items) {
      final map = item.toPlainMap();
      sb.writeln('  - id: "${map['id']}"');
      sb.writeln('    type: ${map['type']}');
      sb.writeln('    title: ${_escapeYamlString(map['title']?.toString() ?? '')}');

      map.forEach((key, value) {
        if (key == 'id' || key == 'type' || key == 'title') return;
        _writeYamlField(sb, key, value, indent: '    ');
      });

      sb.writeln();
    }

    return sb.toString();
  }

  /// 递归写入 YAML 字段，支持多行文本 `|` 保留换行
  static void _writeYamlField(StringBuffer sb, String key, dynamic value, {required String indent}) {
    if (value == null) return;

    if (value is bool) {
      sb.writeln('$indent$key: $value');
    } else if (value is num) {
      sb.writeln('$indent$key: $value');
    } else if (value is String) {
      if (value.isEmpty) return;
      if (value.contains('\n')) {
        // 多行字符串使用 Literal Block Scalar '|'
        sb.writeln('$indent$key: |');
        final lines = value.split('\n');
        for (final line in lines) {
          sb.writeln('$indent  $line');
        }
      } else {
        sb.writeln('$indent$key: ${_escapeYamlString(value)}');
      }
    } else if (value is List) {
      if (value.isEmpty) return;
      sb.writeln('$indent$key:');
      for (final elem in value) {
        if (elem is Map) {
          sb.writeln('$indent  -');
          elem.forEach((k, v) {
            _writeYamlField(sb, k.toString(), v, indent: '$indent    ');
          });
        } else {
          sb.writeln('$indent  - ${_escapeYamlString(elem.toString())}');
        }
      }
    } else if (value is Map) {
      if (value.isEmpty) return;
      sb.writeln('$indent$key:');
      value.forEach((k, v) {
        _writeYamlField(sb, k.toString(), v, indent: '$indent  ');
      });
    }
  }

  static String _escapeYamlString(String str) {
    if (str.isEmpty) return '""';
    // 若包含冒号、井号、中括号等特殊符号，加引号包裹
    if (str.contains(RegExp(r'[:#\[\]{},&*?|<>=!%@\\]')) || str.startsWith(' ') || str.endsWith(' ')) {
      final escaped = str.replaceAll(r'\', r'\\').replaceAll('"', r'\"');
      return '"$escaped"';
    }
    return str;
  }

  /// 解析 YAML 文本并生成预览
  static YamlImportPreview parseYamlString(String yamlContent) {
    final doc = loadYaml(yamlContent);
    if (doc is! Map) {
      throw const FormatException('无效的备份文件：根节点必须为数据对象结构');
    }

    final rawItems = doc['items'];
    if (rawItems == null || rawItems is! List) {
      throw const FormatException('备份文件中未找到 items 凭据列表');
    }

    final validItems = <Credential>[];
    final warnings = <String>[];

    for (int i = 0; i < rawItems.length; i++) {
      final rawItem = rawItems[i];
      if (rawItem is! Map) {
        warnings.add('第 ${i + 1} 条凭据数据结构异常，已跳过');
        continue;
      }

      try {
        final cred = Credential.fromPlainMap(rawItem);
        validItems.add(cred);
      } catch (e) {
        warnings.add('解析第 ${i + 1} 条条目失败: $e');
      }
    }

    return YamlImportPreview(
      totalCount: rawItems.length,
      validItems: validItems,
      warnings: warnings,
    );
  }

  /// 执行导入入库
  static Future<int> executeImport({
    required List<Credential> newItems,
    required RestoreConflictStrategy strategy,
  }) async {
    final db = DatabaseHelper.instance;
    final existingItems = await db.getAllCredentials();
    final existingIdMap = {for (final e in existingItems) e.id: e};

    final itemsToSave = <Credential>[];

    for (final item in newItems) {
      final existing = existingIdMap[item.id];
      if (existing == null) {
        itemsToSave.add(item);
      } else {
        switch (strategy) {
          case RestoreConflictStrategy.skipExisting:
            // 跳过
            break;
          case RestoreConflictStrategy.overwriteExisting:
            // 覆盖原凭据
            itemsToSave.add(item);
            break;
          case RestoreConflictStrategy.appendAsNew:
            // 生成新 ID 作为副本追加
            itemsToSave.add(item.copyWith(
              id: const Uuid().v4(),
              title: '${item.title} (导入副本)',
            ));
            break;
        }
      }
    }

    if (itemsToSave.isNotEmpty) {
      await db.batchInsertCredentials(itemsToSave);
    }

    return itemsToSave.length;
  }

  /// 导出并保存到本地文件系统 (全平台通用)
  static Future<String?> exportAndSave() async {
    final items = await DatabaseHelper.instance.getAllCredentials();
    final yamlString = exportToYamlString(items);

    final timestamp = DateFormat('yyyyMMdd_HHmmss').format(DateTime.now());
    final defaultFileName = 'authix_backup_$timestamp.yaml';
    final bytes = Uint8List.fromList(utf8.encode(yamlString));

    final uri = await FilePickerPlatform.instance.saveFile(
      dialogTitle: '保存 Authix 离线备份文件',
      fileName: defaultFileName,
      bytes: bytes,
      mimeType: 'text/yaml',
    );

    if (uri != null) {
      try {
        final filePath = uri.toFilePath();
        if (filePath.isNotEmpty) {
          final file = File(filePath);
          if (!await file.exists() || (await file.length()) == 0) {
            await file.writeAsBytes(bytes);
          }
          return filePath;
        }
      } catch (_) {
        // 部分沙盒或虚拟 URI 忽略
      }
      return uri.path.isNotEmpty ? uri.path : defaultFileName;
    }

    return null;
  }

  /// 从系统文件选择器选取并读取备份文件
  static Future<String?> pickAndReadBackupFile() async {
    final isAndroid = Platform.isAndroid;
    final files = await FilePickerPlatform.instance.pickFiles(
      dialogTitle: '选取 Authix 备份文件',
      type: isAndroid ? FileType.any : FileType.custom,
      allowedExtensions: isAndroid ? null : const ['yaml', 'yml'],
    );

    if (files.isNotEmpty) {
      final path = files.first.path;
      if (path != null) {
        final file = File(path);
        if (await file.exists()) {
          return await file.readAsString();
        }
      }
    }
    return null;
  }
}
