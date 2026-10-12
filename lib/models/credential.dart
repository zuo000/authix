import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';
import '../core/totp/totp_engine.dart';
import 'recovery_code.dart';

/// 支持的凭据类型枚举
enum CredentialType {
  totp('totp', 'TOTP 动态码'),
  password('password', '账号密码'),
  serverKey('server_key', '服务器私钥'),
  passkey('passkey', '通行密钥'),
  apiKey('api_key', '开发者密钥'),
  cryptoWallet('crypto_wallet', '钱包助记词'),
  card('card', '银行卡'),
  identity('identity', '身份档案'),
  secureNote('secure_note', '安全备忘');

  final String value;
  final String label;

  const CredentialType(this.value, this.label);

  /// 全局统一权威类型图标定义
  IconData get icon => switch (this) {
    CredentialType.totp => Icons.timer_outlined,
    CredentialType.password => Icons.lock_outline,
    CredentialType.serverKey => Icons.terminal_rounded,
    CredentialType.passkey => Icons.fingerprint_rounded,
    CredentialType.apiKey => Icons.vpn_key_outlined,
    CredentialType.cryptoWallet => Icons.account_balance_wallet_outlined,
    CredentialType.card => Icons.credit_card_rounded,
    CredentialType.identity => Icons.badge_outlined,
    CredentialType.secureNote => Icons.note_alt_outlined,
  };

  static CredentialType fromString(String? val) {
    for (final t in CredentialType.values) {
      if (t.value == val) return t;
    }
    return CredentialType.totp;
  }
}

/// 网址 / URI 匹配检测规则 (对标 Bitwarden / 1Password 密码管理器行业标准)
enum UrlMatchType {
  baseDomain('base_domain', '基础域名匹配', '匹配主域名及所有子域名（推荐）'),
  host('host', '主机匹配', '主机名与端口需完全一致，忽略页面路径'),
  startsWith('starts_with', '起始路径匹配', '当前网址以指定前缀开头即可匹配'),
  exact('exact', '完全一致匹配', '网址协议、主机及具体路径必须完全一致'),
  regex('regex', '正则表达式匹配', '使用自定义正则表达式模式精准匹配'),
  never('never', '从不匹配', '此条目不参与任何网址自动识别与填充');

  final String value;
  final String label;
  final String description;

  const UrlMatchType(this.value, this.label, this.description);

  static UrlMatchType fromString(String? val) {
    for (final t in UrlMatchType.values) {
      if (t.value == val) return t;
    }
    return UrlMatchType.baseDomain;
  }
}

/// 网址规则匹配判定工具类
class UrlMatcher {
  /// 判断 targetUrl 是否与 ruleUrl 按照 matchType 规则匹配
  static bool matches({
    required String ruleUrl,
    required String targetUrl,
    UrlMatchType matchType = UrlMatchType.baseDomain,
  }) {
    if (matchType == UrlMatchType.never) return false;
    final cleanRule = ruleUrl.trim();
    final cleanTarget = targetUrl.trim();
    if (cleanRule.isEmpty || cleanTarget.isEmpty) return false;

    switch (matchType) {
      case UrlMatchType.exact:
        return cleanRule == cleanTarget;

      case UrlMatchType.startsWith:
        return cleanTarget.startsWith(cleanRule);

      case UrlMatchType.regex:
        try {
          return RegExp(cleanRule, caseSensitive: false).hasMatch(cleanTarget);
        } catch (_) {
          return false;
        }

      case UrlMatchType.host:
        final ruleUri = _tryParseUri(cleanRule);
        final targetUri = _tryParseUri(cleanTarget);
        if (ruleUri == null || targetUri == null) return cleanRule == cleanTarget;
        final ruleHost = (ruleUri.host.isEmpty ? cleanRule : ruleUri.host).toLowerCase();
        final targetHost = (targetUri.host.isEmpty ? cleanTarget : targetUri.host).toLowerCase();
        final rulePort = ruleUri.hasPort ? ruleUri.port : null;
        final targetPort = targetUri.hasPort ? targetUri.port : null;
        return ruleHost == targetHost && rulePort == targetPort;

      case UrlMatchType.baseDomain:
        final ruleUri = _tryParseUri(cleanRule);
        final targetUri = _tryParseUri(cleanTarget);
        final ruleHost = (ruleUri?.host.isNotEmpty == true ? ruleUri!.host : cleanRule).toLowerCase();
        final targetHost = (targetUri?.host.isNotEmpty == true ? targetUri!.host : cleanTarget).toLowerCase();
        final ruleBase = _getBaseDomain(ruleHost);
        final targetBase = _getBaseDomain(targetHost);
        return ruleBase.isNotEmpty && ruleBase == targetBase;

      case UrlMatchType.never:
        return false;
    }
  }

  static Uri? _tryParseUri(String raw) {
    try {
      if (!raw.contains('://')) {
        return Uri.tryParse('https://$raw');
      }
      return Uri.tryParse(raw);
    } catch (_) {
      return null;
    }
  }

  static String _getBaseDomain(String host) {
    final clean = host.split(':')[0].toLowerCase();
    final parts = clean.split('.');
    if (parts.length <= 2) return clean;
    return '${parts[parts.length - 2]}.${parts.last}';
  }
}

/// 统一核心凭据模型
class Credential {
  final String id;
  final CredentialType type;
  final String title;
  final List<String> tags;
  final bool pinned;
  final int sortOrder;
  final String notes;

  // --- 账号 / 密码 / 网站专属 ---
  final String account;
  final String password;
  final String url;

  // --- TOTP 动态码专属 (天然内聚应急恢复码) ---
  final String issuer;
  final String secret;
  final OtpAlgorithm algorithm;
  final int digits;
  final int period;
  final List<RecoveryCode> recoveryCodes;

  // --- 服务器连接私钥专属 ---
  final String serverHost;
  final int serverPort;
  final String serverUser;
  final String privateKey;
  final String keyPassphrase;
  final String keyAlgorithm;
  final String publicKey;

  // --- 扩展专有数据 (JSON 结构体: API Key、助记词、银行卡、证件、自定义键值对) ---
  final Map<String, dynamic> extraData;

  /// 获取当前凭据关联的网址匹配规则类型
  UrlMatchType get urlMatchType =>
      UrlMatchType.fromString(extraData['url_match_type'] as String?);

  // --- 垃圾箱机制 (软删除与废弃回收) ---
  final bool isDeleted;
  final int? deletedAt;

  // --- 元数据 ---
  final int createdAt;
  final int updatedAt;

  const Credential({
    required this.id,
    required this.type,
    required this.title,
    this.tags = const [],
    this.pinned = false,
    this.sortOrder = 0,
    this.notes = '',
    this.account = '',
    this.password = '',
    this.url = '',
    this.issuer = '',
    this.secret = '',
    this.algorithm = OtpAlgorithm.sha1,
    this.digits = 6,
    this.period = 30,
    this.recoveryCodes = const [],
    this.serverHost = '',
    this.serverPort = 22,
    this.serverUser = '',
    this.privateKey = '',
    this.keyPassphrase = '',
    this.keyAlgorithm = '',
    this.publicKey = '',
    this.extraData = const {},
    this.isDeleted = false,
    this.deletedAt,
    required this.createdAt,
    required this.updatedAt,
  });

  /// 创建一个全新默认凭据实体
  factory Credential.create({
    required CredentialType type,
    required String title,
    List<String> tags = const [],
    bool pinned = false,
    int sortOrder = 0,
    String notes = '',
    String account = '',
    String password = '',
    String url = '',
    UrlMatchType? urlMatchType,
    String issuer = '',
    String secret = '',
    OtpAlgorithm algorithm = OtpAlgorithm.sha1,
    int digits = 6,
    int period = 30,
    List<RecoveryCode> recoveryCodes = const [],
    String serverHost = '',
    int serverPort = 22,
    String serverUser = '',
    String privateKey = '',
    String keyPassphrase = '',
    String keyAlgorithm = '',
    String publicKey = '',
    Map<String, dynamic> extraData = const {},
  }) {
    final now = DateTime.now().millisecondsSinceEpoch;
    final finalExtra = Map<String, dynamic>.from(extraData);
    if (urlMatchType != null) {
      finalExtra['url_match_type'] = urlMatchType.value;
    }
    return Credential(
      id: const Uuid().v4(),
      type: type,
      title: title,
      tags: tags,
      pinned: pinned,
      sortOrder: sortOrder,
      notes: notes,
      account: account,
      password: password,
      url: url,
      issuer: issuer,
      secret: secret,
      algorithm: algorithm,
      digits: digits,
      period: period,
      recoveryCodes: recoveryCodes,
      serverHost: serverHost,
      serverPort: serverPort,
      serverUser: serverUser,
      privateKey: privateKey,
      keyPassphrase: keyPassphrase,
      keyAlgorithm: keyAlgorithm,
      publicKey: publicKey,
      extraData: finalExtra,
      createdAt: now,
      updatedAt: now,
    );
  }

  Credential copyWith({
    String? id,
    CredentialType? type,
    String? title,
    List<String>? tags,
    bool? pinned,
    int? sortOrder,
    String? notes,
    String? account,
    String? password,
    String? url,
    UrlMatchType? urlMatchType,
    String? issuer,
    String? secret,
    OtpAlgorithm? algorithm,
    int? digits,
    int? period,
    List<RecoveryCode>? recoveryCodes,
    String? serverHost,
    int? serverPort,
    String? serverUser,
    String? privateKey,
    String? keyPassphrase,
    String? keyAlgorithm,
    String? publicKey,
    Map<String, dynamic>? extraData,
    bool? isDeleted,
    int? deletedAt,
    int? createdAt,
    int? updatedAt,
  }) {
    final newExtra = Map<String, dynamic>.from(extraData ?? this.extraData);
    if (urlMatchType != null) {
      newExtra['url_match_type'] = urlMatchType.value;
    }
    return Credential(
      id: id ?? this.id,
      type: type ?? this.type,
      title: title ?? this.title,
      tags: tags ?? this.tags,
      pinned: pinned ?? this.pinned,
      sortOrder: sortOrder ?? this.sortOrder,
      notes: notes ?? this.notes,
      account: account ?? this.account,
      password: password ?? this.password,
      url: url ?? this.url,
      issuer: issuer ?? this.issuer,
      secret: secret ?? this.secret,
      algorithm: algorithm ?? this.algorithm,
      digits: digits ?? this.digits,
      period: period ?? this.period,
      recoveryCodes: recoveryCodes ?? this.recoveryCodes,
      serverHost: serverHost ?? this.serverHost,
      serverPort: serverPort ?? this.serverPort,
      serverUser: serverUser ?? this.serverUser,
      privateKey: privateKey ?? this.privateKey,
      keyPassphrase: keyPassphrase ?? this.keyPassphrase,
      keyAlgorithm: keyAlgorithm ?? this.keyAlgorithm,
      publicKey: publicKey ?? this.publicKey,
      extraData: newExtra,
      isDeleted: isDeleted ?? this.isDeleted,
      deletedAt: deletedAt ?? this.deletedAt,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  /// 转换为 SQLite 数据库记录 Map
  Map<String, dynamic> toDbMap() {
    return {
      'id': id,
      'type': type.value,
      'title': title,
      'tags': jsonEncode(tags),
      'pinned': pinned ? 1 : 0,
      'sort_order': sortOrder,
      'notes': notes,
      'account': account,
      'password': password,
      'url': url,
      'issuer': issuer,
      'secret': secret,
      'algorithm': algorithm.nameString,
      'digits': digits,
      'period': period,
      'recovery_codes': jsonEncode(recoveryCodes.map((e) => e.toMap()).toList()),
      'server_host': serverHost,
      'server_port': serverPort,
      'server_user': serverUser,
      'private_key': privateKey,
      'key_passphrase': keyPassphrase,
      'key_algorithm': keyAlgorithm,
      'public_key': publicKey,
      'extra_data': jsonEncode(extraData),
      'is_deleted': isDeleted ? 1 : 0,
      'deleted_at': deletedAt,
      'created_at': createdAt,
      'updated_at': updatedAt,
    };
  }

  /// 从 SQLite 记录解析
  factory Credential.fromDbMap(Map<String, dynamic> map) {
    List<String> parsedTags = [];
    if (map['tags'] != null && map['tags'].toString().isNotEmpty) {
      try {
        final decoded = jsonDecode(map['tags']);
        if (decoded is List) {
          parsedTags = decoded.map((e) => e.toString()).toList();
        }
      } catch (_) {}
    }

    List<RecoveryCode> parsedRecoveryCodes = [];
    if (map['recovery_codes'] != null && map['recovery_codes'].toString().isNotEmpty) {
      try {
        final decoded = jsonDecode(map['recovery_codes']);
        if (decoded is List) {
          parsedRecoveryCodes = decoded
              .map((e) => RecoveryCode.fromMap(Map<String, dynamic>.from(e as Map)))
              .toList();
        }
      } catch (_) {}
    }

    Map<String, dynamic> parsedExtraData = {};
    if (map['extra_data'] != null && map['extra_data'].toString().isNotEmpty) {
      try {
        final decoded = jsonDecode(map['extra_data']);
        if (decoded is Map) {
          parsedExtraData = Map<String, dynamic>.from(decoded);
        }
      } catch (_) {}
    }

    return Credential(
      id: map['id']?.toString() ?? const Uuid().v4(),
      type: CredentialType.fromString(map['type']?.toString()),
      title: map['title']?.toString() ?? '',
      tags: parsedTags,
      pinned: map['pinned'] == 1 || map['pinned'] == true,
      sortOrder: (map['sort_order'] as num?)?.toInt() ?? 0,
      notes: map['notes']?.toString() ?? '',
      account: map['account']?.toString() ?? '',
      password: map['password']?.toString() ?? '',
      url: map['url']?.toString() ?? '',
      issuer: map['issuer']?.toString() ?? '',
      secret: map['secret']?.toString() ?? '',
      algorithm: OtpAlgorithm.fromString(map['algorithm']?.toString()),
      digits: (map['digits'] as num?)?.toInt() ?? 6,
      period: (map['period'] as num?)?.toInt() ?? 30,
      recoveryCodes: parsedRecoveryCodes,
      serverHost: map['server_host']?.toString() ?? '',
      serverPort: (map['server_port'] as num?)?.toInt() ?? 22,
      serverUser: map['server_user']?.toString() ?? '',
      privateKey: map['private_key']?.toString() ?? '',
      keyPassphrase: map['key_passphrase']?.toString() ?? '',
      keyAlgorithm: map['key_algorithm']?.toString() ?? '',
      publicKey: map['public_key']?.toString() ?? '',
      extraData: parsedExtraData,
      isDeleted: map['is_deleted'] == 1 || map['is_deleted'] == true,
      deletedAt: (map['deleted_at'] as num?)?.toInt(),
      createdAt: (map['created_at'] as num?)?.toInt() ?? DateTime.now().millisecondsSinceEpoch,
      updatedAt: (map['updated_at'] as num?)?.toInt() ?? DateTime.now().millisecondsSinceEpoch,
    );
  }

  /// 转换为规范的明文 YAML / JSON 序列化结构
  Map<String, dynamic> toPlainMap() {
    final map = <String, dynamic>{
      'id': id,
      'type': type.value,
      'title': title,
    };

    if (tags.isNotEmpty) map['tags'] = tags;
    if (pinned) map['pinned'] = true;
    if (sortOrder != 0) map['sort_order'] = sortOrder;
    if (notes.isNotEmpty) map['notes'] = notes;

    // 账号密码
    if (account.isNotEmpty) map['account'] = account;
    if (password.isNotEmpty) map['password'] = password;
    if (url.isNotEmpty) map['url'] = url;

    // TOTP
    if (issuer.isNotEmpty) map['issuer'] = issuer;
    if (secret.isNotEmpty) {
      map['secret'] = secret;
      map['algorithm'] = algorithm.nameString;
      map['digits'] = digits;
      map['period'] = period;
    }
    if (recoveryCodes.isNotEmpty) {
      map['recovery_codes'] = recoveryCodes.map((e) => e.toMap()).toList();
    }

    // 通行密钥 / SSH 私钥
    if (type == CredentialType.serverKey || type == CredentialType.passkey || privateKey.isNotEmpty) {
      if (serverHost.isNotEmpty) map['server_host'] = serverHost;
      map['server_port'] = serverPort;
      if (serverUser.isNotEmpty) map['server_user'] = serverUser;
      if (keyPassphrase.isNotEmpty) map['key_passphrase'] = keyPassphrase;
      if (privateKey.isNotEmpty) map['private_key'] = privateKey;
      if (publicKey.isNotEmpty) map['public_key'] = publicKey;
    }

    // 扩展字段展开
    extraData.forEach((key, value) {
      map[key] = value;
    });

    map['created_at'] = createdAt;
    map['updated_at'] = updatedAt;

    return map;
  }

  /// 从明文 YAML / JSON 结构解析恢复
  factory Credential.fromPlainMap(Map<dynamic, dynamic> rawMap) {
    final map = rawMap.map((key, value) => MapEntry(key.toString(), value));

    List<String> parsedTags = [];
    if (map['tags'] is List) {
      parsedTags = (map['tags'] as List).map((e) => e.toString()).toList();
    }

    List<RecoveryCode> parsedRecoveryCodes = [];
    if (map['recovery_codes'] is List) {
      parsedRecoveryCodes = (map['recovery_codes'] as List).map((item) {
        if (item is Map) {
          return RecoveryCode.fromMap(Map<String, dynamic>.from(item));
        } else {
          return RecoveryCode(code: item.toString());
        }
      }).toList();
    }

    // 提取剩余未被专用列占用的字段作为 extraData
    final knownKeys = {
      'id', 'type', 'title', 'tags', 'pinned', 'sort_order', 'notes',
      'account', 'password', 'url', 'issuer', 'secret', 'algorithm',
      'digits', 'period', 'recovery_codes', 'server_host', 'server_port',
      'server_user', 'private_key', 'key_passphrase', 'key_algorithm',
      'public_key', 'created_at', 'updated_at'
    };

    final extra = <String, dynamic>{};
    map.forEach((k, v) {
      if (!knownKeys.contains(k)) {
        extra[k] = v;
      }
    });

    return Credential(
      id: map['id']?.toString() ?? const Uuid().v4(),
      type: CredentialType.fromString(map['type']?.toString()),
      title: map['title']?.toString() ?? '未命名凭据',
      tags: parsedTags,
      pinned: map['pinned'] == true,
      sortOrder: (map['sort_order'] as num?)?.toInt() ?? 0,
      notes: map['notes']?.toString() ?? '',
      account: map['account']?.toString() ?? '',
      password: map['password']?.toString() ?? '',
      url: map['url']?.toString() ?? '',
      issuer: map['issuer']?.toString() ?? '',
      secret: map['secret']?.toString() ?? '',
      algorithm: OtpAlgorithm.fromString(map['algorithm']?.toString()),
      digits: (map['digits'] as num?)?.toInt() ?? 6,
      period: (map['period'] as num?)?.toInt() ?? 30,
      recoveryCodes: parsedRecoveryCodes,
      serverHost: map['server_host']?.toString() ?? '',
      serverPort: (map['server_port'] as num?)?.toInt() ?? 22,
      serverUser: map['server_user']?.toString() ?? '',
      privateKey: map['private_key']?.toString() ?? '',
      keyPassphrase: map['key_passphrase']?.toString() ?? '',
      keyAlgorithm: map['key_algorithm']?.toString() ?? '',
      publicKey: map['public_key']?.toString() ?? '',
      extraData: extra,
      createdAt: (map['created_at'] as num?)?.toInt() ?? DateTime.now().millisecondsSinceEpoch,
      updatedAt: (map['updated_at'] as num?)?.toInt() ?? DateTime.now().millisecondsSinceEpoch,
    );
  }
}
