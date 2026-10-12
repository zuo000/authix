import 'dart:io' show Platform;
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:sqflite_common_ffi_web/sqflite_ffi_web.dart';
import '../../models/credential.dart';

/// 全平台统一的离线本地 SQLite 数据库助手
class DatabaseHelper {
  static final DatabaseHelper instance = DatabaseHelper._init();
  static Database? _database;

  DatabaseHelper._init();

  /// 获取数据库实例，支持全平台 (Win/Mac/Linux/Android/iOS/Web)
  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDB('authix_vault.db');
    return _database!;
  }

  Future<Database> _initDB(String filePath) async {
    // Web 平台：使用 WebAssembly + IndexedDB 的 SQLite 引擎
    if (kIsWeb) {
      databaseFactory = databaseFactoryFfiWeb;
      return await openDatabase(
        filePath,
        version: 2,
        onCreate: _createDB,
        onUpgrade: (db, oldVersion, newVersion) async {
          if (oldVersion < 2) {
            try {
              await db.execute('ALTER TABLE credentials ADD COLUMN is_deleted INTEGER DEFAULT 0;');
              await db.execute('ALTER TABLE credentials ADD COLUMN deleted_at INTEGER;');
              await db.execute('CREATE INDEX IF NOT EXISTS idx_cred_trash ON credentials(is_deleted);');
            } catch (_) {}
          }
        },
      );
    }

    // 桌面端初始化 FFI
    if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
    }

    final dbDirectory = await getApplicationDocumentsDirectory();
    final path = p.join(dbDirectory.path, filePath);

    return await openDatabase(
      path,
      version: 2,
      onCreate: _createDB,
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          try {
            await db.execute('ALTER TABLE credentials ADD COLUMN is_deleted INTEGER DEFAULT 0;');
            await db.execute('ALTER TABLE credentials ADD COLUMN deleted_at INTEGER;');
            await db.execute('CREATE INDEX IF NOT EXISTS idx_cred_trash ON credentials(is_deleted);');
          } catch (_) {}
        }
      },
    );
  }

  Future<void> _createDB(Database db, int version) async {
    // 1. 凭据主表
    await db.execute('''
      CREATE TABLE credentials (
        id TEXT PRIMARY KEY,
        type TEXT NOT NULL,
        title TEXT NOT NULL,
        tags TEXT,
        pinned INTEGER DEFAULT 0,
        sort_order INTEGER DEFAULT 0,
        notes TEXT,
        account TEXT,
        password TEXT,
        url TEXT,
        issuer TEXT,
        secret TEXT,
        algorithm TEXT DEFAULT 'SHA1',
        digits INTEGER DEFAULT 6,
        period INTEGER DEFAULT 30,
        recovery_codes TEXT,
        server_host TEXT,
        server_port INTEGER DEFAULT 22,
        server_user TEXT,
        private_key TEXT,
        key_passphrase TEXT,
        key_algorithm TEXT DEFAULT 'ed25519',
        public_key TEXT,
        extra_data TEXT,
        is_deleted INTEGER DEFAULT 0,
        deleted_at INTEGER,
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL
      )
    ''');

    // 索引以极大提升查询和排序性能
    await db.execute('CREATE INDEX idx_cred_type ON credentials(type);');
    await db.execute('CREATE INDEX idx_cred_pinned_sort ON credentials(pinned DESC, sort_order ASC, updated_at DESC);');
    await db.execute('CREATE INDEX idx_cred_trash ON credentials(is_deleted);');

    // 2. 本地配置表
    await db.execute('''
      CREATE TABLE app_settings (
        key TEXT PRIMARY KEY,
        value TEXT
      )
    ''');
  }

  // ==================== 凭据 CRUD 操作 ====================

  /// 插入新凭据
  Future<int> insertCredential(Credential credential) async {
    final db = await database;
    return await db.insert(
      'credentials',
      credential.toDbMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// 批量插入/替换凭据 (单事务原子提交)
  Future<void> batchInsertCredentials(List<Credential> list, {ConflictAlgorithm conflict = ConflictAlgorithm.replace}) async {
    final db = await database;
    await db.transaction((txn) async {
      final batch = txn.batch();
      for (final item in list) {
        batch.insert('credentials', item.toDbMap(), conflictAlgorithm: conflict);
      }
      await batch.commit(noResult: true);
    });
  }

  /// 更新凭据
  Future<int> updateCredential(Credential credential) async {
    final db = await database;
    return await db.update(
      'credentials',
      credential.toDbMap(),
      where: 'id = ?',
      whereArgs: [credential.id],
    );
  }

  /// 永久彻底删除凭据
  Future<int> deleteCredential(String id) async {
    final db = await database;
    return await db.delete(
      'credentials',
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  /// 移入垃圾箱 (软删除)
  Future<int> moveToTrash(String id) async {
    final db = await database;
    return await db.update(
      'credentials',
      {
        'is_deleted': 1,
        'deleted_at': DateTime.now().millisecondsSinceEpoch,
      },
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  /// 批量更新凭据顺序 sort_order (单事务执行)
  Future<void> updateSortOrders(List<String> orderedIds) async {
    final db = await database;
    await db.transaction((txn) async {
      final batch = txn.batch();
      for (int i = 0; i < orderedIds.length; i++) {
        batch.update(
          'credentials',
          {'sort_order': i},
          where: 'id = ?',
          whereArgs: [orderedIds[i]],
        );
      }
      await batch.commit(noResult: true);
    });
  }

  /// 从垃圾箱恢复凭据
  Future<int> restoreFromTrash(String id) async {
    final db = await database;
    return await db.update(
      'credentials',
      {
        'is_deleted': 0,
        'deleted_at': null,
      },
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  /// 清空垃圾箱 (永久清除所有已软删除的数据)
  Future<int> emptyTrash() async {
    final db = await database;
    return await db.delete(
      'credentials',
      where: 'is_deleted = 1',
    );
  }

  /// 获取垃圾箱中的所有废弃凭据
  Future<List<Credential>> getTrashCredentials() async {
    final db = await database;
    final maps = await db.query(
      'credentials',
      where: 'is_deleted = 1',
      orderBy: 'deleted_at DESC',
    );
    return maps.map((map) => Credential.fromDbMap(map)).toList();
  }

  /// 获取所有正常有效凭据 (按置顶、自定义排序与更新时间排列，默认排除垃圾箱)
  Future<List<Credential>> getAllCredentials({bool includeDeleted = false}) async {
    final db = await database;
    final maps = await db.query(
      'credentials',
      where: includeDeleted ? null : 'is_deleted = 0',
      orderBy: 'pinned DESC, sort_order ASC, updated_at DESC',
    );
    return maps.map((map) => Credential.fromDbMap(map)).toList();
  }

  /// 切换置顶状态
  Future<int> togglePin(String id, bool currentPinned) async {
    final db = await database;
    return await db.update(
      'credentials',
      {'pinned': currentPinned ? 0 : 1, 'updated_at': DateTime.now().millisecondsSinceEpoch},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  /// 本地搜索与类型过滤
  Future<List<Credential>> queryCredentials({
    String? keyword,
    CredentialType? filterType,
  }) async {
    final db = await database;
    final whereClauses = <String>['is_deleted = 0'];
    final whereArgs = <dynamic>[];

    if (filterType != null) {
      whereClauses.add('type = ?');
      whereArgs.add(filterType.value);
    }

    if (keyword != null && keyword.trim().isNotEmpty) {
      final term = '%${keyword.trim()}%';
      whereClauses.add('''
        (title LIKE ? OR account LIKE ? OR issuer LIKE ? OR url LIKE ? 
         OR server_host LIKE ? OR notes LIKE ? OR tags LIKE ?)
      ''');
      whereArgs.addAll([term, term, term, term, term, term, term]);
    }

    final whereString = whereClauses.isEmpty ? null : whereClauses.join(' AND ');

    final maps = await db.query(
      'credentials',
      where: whereString,
      whereArgs: whereArgs.isEmpty ? null : whereArgs,
      orderBy: 'pinned DESC, sort_order ASC, updated_at DESC',
    );

    return maps.map((map) => Credential.fromDbMap(map)).toList();
  }

  // ==================== 应用配置操作 ====================

  Future<void> setSetting(String key, String value) async {
    final db = await database;
    await db.insert(
      'app_settings',
      {'key': key, 'value': value},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<String?> getSetting(String key) async {
    final db = await database;
    final maps = await db.query(
      'app_settings',
      where: 'key = ?',
      whereArgs: [key],
      limit: 1,
    );
    if (maps.isNotEmpty) {
      return maps.first['value']?.toString();
    }
    return null;
  }
}
