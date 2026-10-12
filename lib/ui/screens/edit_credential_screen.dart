import 'dart:convert';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/totp/totp_engine.dart';
import '../../core/utils/password_generator.dart';
import '../../models/credential.dart';
import '../../models/recovery_code.dart';
import '../../providers/vault_provider.dart';
import '../../core/utils/ime_utils.dart';
import '../widgets/totp_timer_ring.dart';
import 'qr_scanner_screen.dart';

/// 新建与编辑凭据页面
class EditCredentialScreen extends ConsumerStatefulWidget {
  final Credential? initialItem;
  final CredentialType defaultType;

  const EditCredentialScreen({
    super.key,
    this.initialItem,
    this.defaultType = CredentialType.totp,
  });

  /// 智能提取恢复码，避免将空格分组的单个长恢复码误拆
  static List<String> extractRecoveryCodes(String text) {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return [];

    // 1. 如果包含明确换行，优先按换行切分
    final lines = trimmed
        .split(RegExp(r'\r?\n'))
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty)
        .toList();

    final List<String> results = [];

    for (final line in lines) {
      // 移除行首列表序号或符号，例如 "1. ", "(1) ", "1) ", "[1] ", "- ", "* ", "• "
      var cleaned = line
          .replaceFirst(RegExp(r'^(?:(?:\(?\d+[\.\)\]\-:]+)|[-*•])\s*'), '')
          .trim();
      if (cleaned.isEmpty) continue;

      // 检查行内是否含有逗号或分号分割
      if (cleaned.contains(RegExp(r'[,;，；]'))) {
        final items = cleaned
            .split(RegExp(r'[,;，；]+'))
            .map((s) => s.trim())
            .where((s) => s.isNotEmpty);
        for (final item in items) {
          final norm = item.replaceAll(RegExp(r'\s+'), ' ').trim();
          if (norm.isNotEmpty) results.add(norm);
        }
        continue;
      }

      // 检查行内是否有制表符 \t 或 3 个及以上连续空格（通常为多列并排排版）
      if (cleaned.contains(RegExp(r'[\t]|\s{3,}'))) {
        final items = cleaned
            .split(RegExp(r'[\t]|\s{3,}'))
            .map((s) => s.trim())
            .where((s) => s.isNotEmpty);
        for (final item in items) {
          final norm = item.replaceAll(RegExp(r'\s+'), ' ').trim();
          if (norm.isNotEmpty) results.add(norm);
        }
        continue;
      }

      // 单行单码情况：如空格分组的长恢复码（如 XXXX XXXX...）或备用码
      // 这些由空格分段的字符属于同一个恢复码的分组，完整作为一个恢复码保留
      final normalized = cleaned.replaceAll(RegExp(r'\s+'), ' ').trim();
      if (normalized.isNotEmpty) {
        results.add(normalized);
      }
    }

    return results;
  }

  @override
  ConsumerState<EditCredentialScreen> createState() =>
      _EditCredentialScreenState();
}

class _EditCredentialScreenState extends ConsumerState<EditCredentialScreen> {
  final _formKey = GlobalKey<FormState>();

  late CredentialType _type;
  late TextEditingController _titleController;
  late TextEditingController _notesController;
  late TextEditingController _tagsController;
  bool _pinned = false;

  // 账号密码
  late TextEditingController _accountController;
  late TextEditingController _passwordController;
  late TextEditingController _urlController;
  UrlMatchType _urlMatchType = UrlMatchType.baseDomain;
  bool _obscurePassword = true;
  String? _linkedExistingTotpTitle;

  // TOTP
  late TextEditingController _issuerController;
  late TextEditingController _secretController;
  OtpAlgorithm _algorithm = OtpAlgorithm.sha1;
  int _digits = 6;
  int _period = 30;
  late TextEditingController _customPeriodController;
  final List<RecoveryCode> _recoveryCodes = [];
  final TextEditingController _batchRecoveryCodesController =
      TextEditingController();

  // SSH
  late TextEditingController _serverHostController;
  late TextEditingController _serverPortController;
  late TextEditingController _serverUserController;
  late TextEditingController _privateKeyController;
  late TextEditingController _keyPassphraseController;
  String _keyAlgorithm = '';

  // 扩展字段 (API Key / 助记词 / 银行卡 / 身份 / 备忘自定义项)
  final Map<String, dynamic> _extraData = {};

  // 专有控制器
  final TextEditingController _apiKeyController = TextEditingController();
  final TextEditingController _apiProviderController = TextEditingController();
  final TextEditingController _cryptoSeedController = TextEditingController();
  final TextEditingController _cryptoAddressController =
      TextEditingController();
  final TextEditingController _cardNumberController = TextEditingController();
  final TextEditingController _cardHolderController = TextEditingController();
  final TextEditingController _cardCvvController = TextEditingController();
  final TextEditingController _cardExpiryController = TextEditingController();
  final TextEditingController _idNumberController = TextEditingController();
  final TextEditingController _fullNameController = TextEditingController();
  // 通行密钥 (Passkey) 专有控制器
  final TextEditingController _passkeyRpIdController = TextEditingController();
  final TextEditingController _passkeyUserNameController =
      TextEditingController();
  final TextEditingController _passkeyCredentialIdController =
      TextEditingController();
  final TextEditingController _passkeyUserHandleController =
      TextEditingController();
  final TextEditingController _passkeyPublicKeyController =
      TextEditingController();
  final TextEditingController _passkeyPrivateKeyController =
      TextEditingController();
  String _passkeyAlgorithm = 'ES256';

  @override
  void initState() {
    super.initState();
    final item = widget.initialItem;
    _type = item?.type ?? widget.defaultType;
    _titleController = TextEditingController(text: item?.title ?? '');
    _notesController = TextEditingController(text: item?.notes ?? '');
    _tagsController = TextEditingController(text: item?.tags.join(', ') ?? '');
    _pinned = item?.pinned ?? false;

    _accountController = TextEditingController(text: item?.account ?? '');
    _passwordController = TextEditingController(text: item?.password ?? '');
    _urlController = TextEditingController(text: item?.url ?? '');
    _urlMatchType = item?.urlMatchType ?? UrlMatchType.baseDomain;

    _issuerController = TextEditingController(text: item?.issuer ?? '');
    _secretController = TextEditingController(text: item?.secret ?? '');
    _algorithm = item?.algorithm ?? OtpAlgorithm.sha1;
    _digits = item?.digits ?? 6;
    _period = item?.period ?? 30;
    _customPeriodController = TextEditingController(text: _period.toString());
    if (item != null) {
      _recoveryCodes.addAll(item.recoveryCodes);
    }

    _serverHostController = TextEditingController(text: item?.serverHost ?? '');
    _serverPortController = TextEditingController(
      text: item?.serverPort.toString() ?? '22',
    );
    _serverUserController = TextEditingController(text: item?.serverUser ?? '');
    _privateKeyController = TextEditingController(text: item?.privateKey ?? '');
    _keyPassphraseController = TextEditingController(
      text: item?.keyPassphrase ?? '',
    );
    _keyAlgorithm = item?.keyAlgorithm ?? '';

    if (item != null) {
      _extraData.addAll(item.extraData);
      _apiKeyController.text = _extraData['api_key']?.toString() ?? '';
      _apiProviderController.text =
          _extraData['service_provider']?.toString() ?? '';
      final seeds = _extraData['seed_phrase'];
      if (seeds is List) {
        _cryptoSeedController.text = seeds.join(' ');
      }
      _cryptoAddressController.text =
          _extraData['wallet_address']?.toString() ?? '';
      _cardNumberController.text = _extraData['card_number']?.toString() ?? '';
      _cardHolderController.text =
          _extraData['cardholder_name']?.toString() ?? '';
      _cardCvvController.text = _extraData['cvv']?.toString() ?? '';
      _cardExpiryController.text = _extraData['expiry_date']?.toString() ?? '';
      _idNumberController.text = _extraData['id_number']?.toString() ?? '';
      _fullNameController.text = _extraData['full_name']?.toString() ?? '';

      // 初始化 Passkey 控制器
      _passkeyRpIdController.text = item.url.isNotEmpty
          ? item.url
          : (_extraData['rp_id']?.toString() ?? '');
      _passkeyUserNameController.text = item.account;
      _passkeyCredentialIdController.text =
          _extraData['credential_id']?.toString() ?? '';
      _passkeyUserHandleController.text =
          _extraData['user_handle']?.toString() ?? '';
      _passkeyPublicKeyController.text = item.publicKey.isNotEmpty
          ? item.publicKey
          : (_extraData['public_key']?.toString() ?? '');
      _passkeyPrivateKeyController.text = item.privateKey;
      _passkeyAlgorithm =
          _extraData['passkey_algorithm']?.toString() ?? 'ES256';
    }
  }

  @override
  void dispose() {
    _titleController.dispose();
    _notesController.dispose();
    _tagsController.dispose();
    _accountController.dispose();
    _passwordController.dispose();
    _urlController.dispose();
    _issuerController.dispose();
    _secretController.dispose();
    _customPeriodController.dispose();
    _batchRecoveryCodesController.dispose();
    _serverHostController.dispose();
    _serverPortController.dispose();
    _serverUserController.dispose();
    _privateKeyController.dispose();
    _keyPassphraseController.dispose();
    _apiKeyController.dispose();
    _apiProviderController.dispose();
    _cryptoSeedController.dispose();
    _cryptoAddressController.dispose();
    _cardNumberController.dispose();
    _cardHolderController.dispose();
    _cardCvvController.dispose();
    _cardExpiryController.dispose();
    _idNumberController.dispose();
    _fullNameController.dispose();
    _passkeyRpIdController.dispose();
    _passkeyUserNameController.dispose();
    _passkeyCredentialIdController.dispose();
    _passkeyUserHandleController.dispose();
    _passkeyPublicKeyController.dispose();
    _passkeyPrivateKeyController.dispose();
    super.dispose();
  }

  void _generatePassword() {
    final pwd = PasswordGenerator.generate(length: 18);
    setState(() {
      _passwordController.text = pwd;
    });
  }

  void _parseBatchRecoveryCodes() {
    final text = _batchRecoveryCodesController.text.trim();
    if (text.isEmpty) return;

    final parsed = EditCredentialScreen.extractRecoveryCodes(text);
    if (parsed.isEmpty) return;

    setState(() {
      for (final p in parsed) {
        if (!_recoveryCodes.any(
          (rc) => rc.code.toLowerCase() == p.toLowerCase(),
        )) {
          _recoveryCodes.add(RecoveryCode(code: p));
        }
      }
      _batchRecoveryCodesController.clear();
    });
  }

  void _mergeAllRecoveryCodes() {
    if (_recoveryCodes.length <= 1) return;
    final mergedCode = _recoveryCodes.map((rc) => rc.code.trim()).join(' ');
    setState(() {
      _recoveryCodes.clear();
      _recoveryCodes.add(RecoveryCode(code: mergedCode));
    });
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('已将所有片段合并为 1 个完整恢复码')));
  }

  Future<void> _editRecoveryCodeDialog(int index) async {
    final current = _recoveryCodes[index].code;
    final controller = TextEditingController(text: current);
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('修改恢复码'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: '恢复码',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: const Text('保存'),
          ),
        ],
      ),
    );

    if (result != null && result.isNotEmpty && mounted) {
      setState(() {
        _recoveryCodes[index] = _recoveryCodes[index].copyWith(code: result);
      });
    }
  }

  void _generatePasskeyMockKeyPair() {
    final random = Random.secure();
    final credIdBytes = List<int>.generate(32, (_) => random.nextInt(256));
    final handleBytes = List<int>.generate(16, (_) => random.nextInt(256));
    final privKeyBytes = List<int>.generate(32, (_) => random.nextInt(256));
    final pubKeyBytes = List<int>.generate(65, (_) => random.nextInt(256));
    pubKeyBytes[0] = 0x04; // 非压缩公钥前缀

    final credId = base64Url.encode(credIdBytes).replaceAll('=', '');
    final handle = base64Url.encode(handleBytes).replaceAll('=', '');
    final privKey = base64Url.encode(privKeyBytes).replaceAll('=', '');
    final pubKey = base64Url.encode(pubKeyBytes).replaceAll('=', '');

    setState(() {
      if (_passkeyCredentialIdController.text.trim().isEmpty) {
        _passkeyCredentialIdController.text = credId;
      }
      if (_passkeyUserHandleController.text.trim().isEmpty) {
        _passkeyUserHandleController.text = handle;
      }
      _passkeyPrivateKeyController.text = privKey;
      _passkeyPublicKeyController.text = pubKey;
      if (_passkeyRpIdController.text.trim().isEmpty) {
        _passkeyRpIdController.text = 'github.com';
      }
      if (_titleController.text.trim().isEmpty) {
        _titleController.text = 'GitHub 通行密钥';
      }
    });

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('已为您在本地成功生成 ES256 合规通行密钥对与凭据 ID'),
        backgroundColor: Colors.green,
        duration: Duration(seconds: 3),
      ),
    );
  }

  void _parseWebAuthnJson() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final rawText = data?.text?.trim();
    if (rawText == null || rawText.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('剪贴板中未检测到文本内容')));
      }
      return;
    }

    try {
      final decoded = jsonDecode(rawText);
      if (decoded is Map<String, dynamic>) {
        setState(() {
          final rp = decoded['rp']?['id'] ?? decoded['rpId'] ?? decoded['rp'];
          if (rp != null) _passkeyRpIdController.text = rp.toString();

          final user =
              decoded['user']?['name'] ??
              decoded['userName'] ??
              decoded['name'];
          if (user != null) _passkeyUserNameController.text = user.toString();

          final id =
              decoded['id'] ?? decoded['rawId'] ?? decoded['credentialId'];
          if (id != null) _passkeyCredentialIdController.text = id.toString();

          final handle = decoded['user']?['id'] ?? decoded['userHandle'];
          if (handle != null)
            _passkeyUserHandleController.text = handle.toString();

          if (_titleController.text.trim().isEmpty &&
              _passkeyRpIdController.text.isNotEmpty) {
            _titleController.text = '${_passkeyRpIdController.text} 通行密钥';
          }
        });
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('已成功解析剪贴板中的 WebAuthn 凭据参数并自动填入'),
              backgroundColor: Colors.green,
            ),
          );
        }
        return;
      }
    } catch (_) {}

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('未能识别出有效的 WebAuthn JSON 格式')),
      );
    }
  }

  Future<String?> _scanQRCode({String? title, String? prompt}) async {
    return await Navigator.of(context).push<String>(
      MaterialPageRoute(
        builder: (_) => QRScannerScreen(
          returnRawContent: true,
          title: title,
          prompt: prompt,
        ),
      ),
    );
  }

  Future<void> _scanToField(
    TextEditingController controller,
    String fieldName,
  ) async {
    final raw = await _scanQRCode(
      title: '扫描$fieldName',
      prompt: '将包含 $fieldName 的二维码置于框内即可自动识别',
    );
    if (raw == null || raw.trim().isEmpty) return;
    setState(() {
      controller.text = raw.trim();
    });
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('已成功扫码录入 $fieldName'),
          backgroundColor: Colors.green,
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  /// 通用解析 otpauth:// 协议字符串并自动填充字段
  bool _parseOtpauthString(String raw, {bool notify = true}) {
    final text = raw.trim();
    final otpIndex = text.indexOf('otpauth://');
    if (otpIndex == -1) return false;

    final uriText = text.substring(otpIndex).trim();
    final uriData = TotpEngine.parseUri(uriText);
    if (uriData != null) {
      final issuerStr = uriData.issuer ?? '';
      final accountStr = uriData.account ?? '';
      setState(() {
        if (_type != CredentialType.password && _type != CredentialType.totp) {
          _type = CredentialType.totp;
        }
        if (_titleController.text.trim().isEmpty) {
          _titleController.text = issuerStr.isNotEmpty
              ? issuerStr
              : (accountStr.isNotEmpty ? accountStr : 'TOTP 动态码');
        }
        if (issuerStr.isNotEmpty &&
            (_issuerController.text.trim().isEmpty ||
                _issuerController.text == '未知服务商')) {
          _issuerController.text = issuerStr;
        }
        if (accountStr.isNotEmpty && _accountController.text.trim().isEmpty) {
          _accountController.text = accountStr;
        }
        _secretController.text = uriData.secret;
        _algorithm = uriData.algorithm;
        _digits = uriData.digits;
        _period = uriData.period;
        _customPeriodController.text = _period.toString();
      });

      if (notify && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('已自动识别并解析 otpauth 链接！'),
            backgroundColor: Colors.green,
            duration: Duration(seconds: 2),
          ),
        );
      }
      return true;
    }
    return false;
  }

  /// 弹出对话框手动输入或粘贴 otpauth 完整链接
  void _showImportOtpauthDialog() {
    final textController = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.link_rounded, color: Colors.blue),
            SizedBox(width: 8),
            Text('导入 otpauth 链接'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '请粘贴以 otpauth:// 开头的完整链接，系统将自动解析密钥、发行商、账号及周期参数：',
              style: TextStyle(fontSize: 13, color: Colors.grey),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: textController,
              maxLines: 3,
              autofocus: true,
              decoration: InputDecoration(
                hintText: 'otpauth://totp/Example:alice@google.com?secret=JBSWY3DPEHPK3PXP...',
                border: const OutlineInputBorder(),
                suffixIcon: IconButton(
                  icon: const Icon(Icons.paste_rounded),
                  tooltip: '从剪贴板粘贴',
                  onPressed: () async {
                    final data = await Clipboard.getData(Clipboard.kTextPlain);
                    if (data?.text != null) {
                      textController.text = data!.text!.trim();
                    }
                  },
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () {
              final ok = _parseOtpauthString(textController.text);
              Navigator.pop(ctx);
              if (!ok && mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('未能在输入内容中解析到合法的 otpauth 动态码链接'),
                    backgroundColor: Colors.red,
                  ),
                );
              }
            },
            child: const Text('解析并填入'),
          ),
        ],
      ),
    );
  }

  /// 从密码库中选择已有的 TOTP 凭据进行关联
  void _showPickExistingTotpDialog() {
    final credentials = ref.read(vaultProvider).valueOrNull ?? [];
    final totpItems = credentials
        .where((c) =>
            c.type == CredentialType.totp &&
            c.secret.isNotEmpty &&
            !c.isDeleted)
        .toList();

    if (totpItems.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('当前密码库中暂无单独的 TOTP 项目可供关联')),
      );
      return;
    }

    showDialog(
      context: context,
      builder: (ctx) {
        String filter = '';
        return StatefulBuilder(
          builder: (dialogCtx, setDialogState) {
            final filtered = totpItems.where((item) {
              if (filter.isEmpty) return true;
              final q = filter.toLowerCase();
              return item.title.toLowerCase().contains(q) ||
                  item.account.toLowerCase().contains(q) ||
                  item.issuer.toLowerCase().contains(q);
            }).toList();

            return AlertDialog(
              title: const Row(
                children: [
                  Icon(Icons.timer_outlined, color: Colors.blue),
                  SizedBox(width: 8),
                  Text('关联已有的 TOTP 码'),
                ],
              ),
              content: SizedBox(
                width: 400,
                height: 360,
                child: Column(
                  children: [
                    TextField(
                      decoration: const InputDecoration(
                        hintText: '搜索 TOTP 标题、账号或发行商...',
                        prefixIcon: Icon(Icons.search, size: 18),
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                      onChanged: (val) {
                        setDialogState(() => filter = val);
                      },
                    ),
                    const SizedBox(height: 10),
                    Expanded(
                      child: filtered.isEmpty
                          ? const Center(child: Text('无匹配的 TOTP 项目'))
                          : ListView.separated(
                              itemCount: filtered.length,
                              separatorBuilder: (_, __) =>
                                  const Divider(height: 1),
                              itemBuilder: (context, idx) {
                                final item = filtered[idx];
                                return ListTile(
                                  dense: true,
                                  leading: const Icon(Icons.timer_rounded),
                                  title: Text(
                                    item.title,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  subtitle: Text(
                                    item.account.isNotEmpty
                                        ? item.account
                                        : (item.issuer.isNotEmpty
                                            ? item.issuer
                                            : '无附加信息'),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  trailing: const Icon(
                                    Icons.arrow_forward_ios,
                                    size: 14,
                                  ),
                                  onTap: () {
                                    Navigator.pop(dialogCtx);
                                    setState(() {
                                      _secretController.text = item.secret;
                                      _issuerController.text = item.issuer;
                                      _algorithm = item.algorithm;
                                      _digits = item.digits;
                                      _period = item.period;
                                      if (item.recoveryCodes.isNotEmpty &&
                                          _recoveryCodes.isEmpty) {
                                        _recoveryCodes.addAll(
                                          item.recoveryCodes,
                                        );
                                      }
                                      _linkedExistingTotpTitle = item.title;
                                    });
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        content: Text(
                                          '已成功关联 TOTP「${item.title}」',
                                        ),
                                      ),
                                    );
                                  },
                                );
                              },
                            ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogCtx),
                  child: const Text('取消'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _smartScanAndFill() async {
    final raw = await _scanQRCode();
    if (raw == null || raw.trim().isEmpty) return;
    final text = raw.trim();

    // 1. 若包含 TOTP URI (otpauth://)
    if (_parseOtpauthString(text)) {
      return;
    }

    // 2. 若为 WebAuthn JSON
    try {
      final decoded = jsonDecode(text);
      if (decoded is Map<String, dynamic>) {
        setState(() {
          _type = CredentialType.passkey;
          final rp = decoded['rp']?['id'] ?? decoded['rpId'] ?? decoded['rp'];
          if (rp != null) _passkeyRpIdController.text = rp.toString();
          final user =
              decoded['user']?['name'] ??
              decoded['userName'] ??
              decoded['name'];
          if (user != null) _passkeyUserNameController.text = user.toString();
          final id =
              decoded['id'] ?? decoded['rawId'] ?? decoded['credentialId'];
          if (id != null) _passkeyCredentialIdController.text = id.toString();
          final handle = decoded['user']?['id'] ?? decoded['userHandle'];
          if (handle != null)
            _passkeyUserHandleController.text = handle.toString();
          if (_titleController.text.trim().isEmpty &&
              _passkeyRpIdController.text.isNotEmpty) {
            _titleController.text = '${_passkeyRpIdController.text} 通行密钥';
          }
        });
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('已智能识别并填入通行密钥凭据'),
              backgroundColor: Colors.green,
            ),
          );
        }
        return;
      }
    } catch (_) {}

    // 3. 根据当前类型定向填入核心字段
    setState(() {
      switch (_type) {
        case CredentialType.password:
          if (text.startsWith('http://') || text.startsWith('https://')) {
            _urlController.text = text;
          } else {
            _passwordController.text = text;
          }
          break;
        case CredentialType.apiKey:
          _apiKeyController.text = text;
          break;
        case CredentialType.cryptoWallet:
          _cryptoAddressController.text = text;
          break;
        case CredentialType.card:
          _cardNumberController.text = text;
          break;
        case CredentialType.identity:
          _idNumberController.text = text;
          break;
        case CredentialType.serverKey:
          if (text.contains('BEGIN') && text.contains('PRIVATE KEY')) {
            _privateKeyController.text = text;
          } else {
            _serverHostController.text = text;
          }
          break;
        case CredentialType.secureNote:
          if (_notesController.text.isEmpty) {
            _notesController.text = text;
          } else {
            _notesController.text = '${_notesController.text}\n$text';
          }
          break;
        case CredentialType.passkey:
          _passkeyCredentialIdController.text = text;
          break;
        case CredentialType.totp:
          _secretController.text = text;
          break;
      }
    });

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('已扫码填入「${_type.label}」凭据'),
          backgroundColor: Colors.green,
        ),
      );
    }
  }

  void _save() {
    if (!_formKey.currentState!.validate()) return;

    final tags = _tagsController.text
        .split(RegExp(r'[,，\s]+'))
        .where((s) => s.trim().isNotEmpty)
        .toList();

    // 收集 extraData
    final extra = Map<String, dynamic>.from(_extraData);
    if (_type == CredentialType.apiKey) {
      if (_apiKeyController.text.isNotEmpty)
        extra['api_key'] = _apiKeyController.text.trim();
      if (_apiProviderController.text.isNotEmpty)
        extra['service_provider'] = _apiProviderController.text.trim();
    } else if (_type == CredentialType.cryptoWallet) {
      if (_cryptoSeedController.text.isNotEmpty) {
        extra['seed_phrase'] = _cryptoSeedController.text
            .trim()
            .split(RegExp(r'\s+'))
            .where((s) => s.isNotEmpty)
            .toList();
      }
      if (_cryptoAddressController.text.isNotEmpty)
        extra['wallet_address'] = _cryptoAddressController.text.trim();
    } else if (_type == CredentialType.card) {
      if (_cardNumberController.text.isNotEmpty)
        extra['card_number'] = _cardNumberController.text.trim();
      if (_cardHolderController.text.isNotEmpty)
        extra['cardholder_name'] = _cardHolderController.text.trim();
      if (_cardCvvController.text.isNotEmpty)
        extra['cvv'] = _cardCvvController.text.trim();
      if (_cardExpiryController.text.isNotEmpty)
        extra['expiry_date'] = _cardExpiryController.text.trim();
    } else if (_type == CredentialType.identity) {
      if (_idNumberController.text.isNotEmpty)
        extra['id_number'] = _idNumberController.text.trim();
      if (_fullNameController.text.isNotEmpty)
        extra['full_name'] = _fullNameController.text.trim();
    } else if (_type == CredentialType.passkey) {
      if (_passkeyRpIdController.text.isNotEmpty)
        extra['rp_id'] = _passkeyRpIdController.text.trim();
      if (_passkeyCredentialIdController.text.isNotEmpty)
        extra['credential_id'] = _passkeyCredentialIdController.text.trim();
      if (_passkeyUserHandleController.text.isNotEmpty)
        extra['user_handle'] = _passkeyUserHandleController.text.trim();
      if (_passkeyPublicKeyController.text.isNotEmpty)
        extra['public_key'] = _passkeyPublicKeyController.text.trim();
      extra['passkey_algorithm'] = _passkeyAlgorithm;
      if (_type == CredentialType.password) {
        extra['url_match_type'] = _urlMatchType.value;
      }
    }

    final isNew = widget.initialItem == null;
    final cred =
        (widget.initialItem ??
                Credential.create(
                  type: _type,
                  title: _titleController.text.trim(),
                ))
            .copyWith(
              type: _type,
              title: _titleController.text.trim(),
              tags: tags,
              pinned: _pinned,
              notes: _notesController.text.trim(),
              account: _type == CredentialType.passkey
                  ? _passkeyUserNameController.text.trim()
                  : _accountController.text.trim(),
              password: _passwordController.text,
              url: _type == CredentialType.passkey
                  ? _passkeyRpIdController.text.trim()
                  : _urlController.text.trim(),
              urlMatchType: _urlMatchType,
              issuer: _issuerController.text.trim(),
              secret: _secretController.text
                  .trim()
                  .replaceAll(' ', '')
                  .toUpperCase(),
              algorithm: _algorithm,
              digits: _digits,
              period: _period,
              recoveryCodes: _recoveryCodes,
              serverHost: _serverHostController.text.trim(),
              serverPort: int.tryParse(_serverPortController.text.trim()) ?? 22,
              serverUser: _serverUserController.text.trim(),
              privateKey: _type == CredentialType.passkey
                  ? _passkeyPrivateKeyController.text.trim()
                  : _privateKeyController.text.trim(),
              publicKey: _type == CredentialType.passkey
                  ? _passkeyPublicKeyController.text.trim()
                  : '',
              keyPassphrase: _keyPassphraseController.text,
              keyAlgorithm: _keyAlgorithm,
              extraData: extra,
              updatedAt: DateTime.now().millisecondsSinceEpoch,
            );

    final notifier = ref.read(vaultProvider.notifier);
    if (isNew) {
      notifier.addCredential(cred);
    } else {
      notifier.updateCredential(cred);
    }

    // 需求 1：如果是账号密码类型且填写了 TOTP，新录入时在 TOTP 分类自动创建对应项目
    if (cred.type == CredentialType.password && cred.secret.isNotEmpty) {
      final credentials = ref.read(vaultProvider).valueOrNull ?? [];
      final existsInTotp = credentials.any(
        (c) =>
            c.type == CredentialType.totp &&
            c.secret == cred.secret &&
            !c.isDeleted,
      );

      if (!existsInTotp && _linkedExistingTotpTitle == null) {
        final totpItem = Credential.create(
          type: CredentialType.totp,
          title: cred.title.isNotEmpty
              ? cred.title
              : (cred.issuer.isNotEmpty ? cred.issuer : 'TOTP 动态码'),
          tags: cred.tags,
        ).copyWith(
          account: cred.account,
          issuer: cred.issuer.isNotEmpty ? cred.issuer : cred.title,
          secret: cred.secret,
          algorithm: cred.algorithm,
          digits: cred.digits,
          period: cred.period,
          recoveryCodes: cred.recoveryCodes,
          notes: cred.notes.isNotEmpty
              ? cred.notes
              : '由账号密码「${cred.title}」自动生成的双重验证码',
        );
        notifier.addCredential(totpItem);
      }
    }

    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isNew = widget.initialItem == null;

    return Scaffold(
      appBar: AppBar(
        title: Text(isNew ? '新建凭据' : '编辑凭据'),
        actions: [
          IconButton(
            icon: Icon(_pinned ? Icons.push_pin : Icons.push_pin_outlined),
            tooltip: _pinned ? '取消置顶' : '置顶',
            onPressed: () => setState(() => _pinned = !_pinned),
          ),
          FilledButton.icon(
            icon: const Icon(Icons.check_rounded, size: 18),
            label: const Text('保存'),
            onPressed: _save,
          ),
          const SizedBox(width: 12),
        ],
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            // 类型选择下拉框 (新建时可自由切换)
            DropdownButtonFormField<CredentialType>(
              value: _type,
              decoration: const InputDecoration(
                labelText: '凭据类型',
                prefixIcon: Icon(Icons.category_outlined),
                border: OutlineInputBorder(),
              ),
              items: CredentialType.values.map((t) {
                return DropdownMenuItem(value: t, child: Text(t.label));
              }).toList(),
              onChanged: (val) {
                if (val != null) setState(() => _type = val);
              },
            ),
            const SizedBox(height: 16),

            // 标题
            TextFormField(
              controller: _titleController,
              inputFormatters: const [ImeSafeTextInputFormatter()],
              decoration: const InputDecoration(
                labelText: '标题 / 服务名称 *',
                hintText: '例如：GitHub 个人、生产跳板机、AWS 根账号',
                prefixIcon: Icon(Icons.title_rounded),
                border: OutlineInputBorder(),
              ),
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? '请输入标题' : null,
            ),
            const SizedBox(height: 16),

            // 根据类型动态渲染专有字段
            ..._buildTypeSpecificFields(theme),

            const SizedBox(height: 16),
            // 通用标签输入
            TextFormField(
              controller: _tagsController,
              inputFormatters: const [ImeSafeTextInputFormatter()],
              decoration: const InputDecoration(
                labelText: '标签 (以逗号分隔)',
                hintText: 'Work, DevOps, 2FA, 常用',
                prefixIcon: Icon(Icons.label_outline),
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),

            // 通用备注
            TextFormField(
              controller: _notesController,
              maxLines: 3,
              inputFormatters: const [ImeSafeTextInputFormatter()],
              decoration: const InputDecoration(
                labelText: '安全备注说明',
                hintText: '仅保存在本地设备，支持多行备忘信息',
                prefixIcon: Icon(Icons.notes_rounded),
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }

  List<Widget> _buildTypeSpecificFields(ThemeData theme) {
    switch (_type) {
      case CredentialType.passkey:
        return _buildPasskeyFields(theme);
      case CredentialType.totp:
        return _buildTotpFields(theme);
      case CredentialType.password:
        return _buildPasswordFields(theme, allowTotp: true);
      case CredentialType.serverKey:
        return _buildServerKeyFields(theme);
      case CredentialType.apiKey:
        return _buildApiKeyFields(theme);
      case CredentialType.cryptoWallet:
        return _buildCryptoWalletFields(theme);
      case CredentialType.card:
        return _buildCardFields(theme);
      case CredentialType.identity:
        return _buildIdentityFields(theme);
      case CredentialType.secureNote:
        return []; // 仅使用 notes 和 custom fields
    }
  }

  // --- 通行密钥 (Passkey / WebAuthn) 表单字段 ---
  List<Widget> _buildPasskeyFields(ThemeData theme) {
    return [
      // 快捷生成与导入向导卡片
      Container(
        margin: const EdgeInsets.only(bottom: 16),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: theme.colorScheme.primaryContainer.withValues(alpha: 0.35),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: theme.colorScheme.primary.withValues(alpha: 0.25),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.fingerprint_rounded,
                  color: theme.colorScheme.primary,
                  size: 22,
                ),
                const SizedBox(width: 8),
                Text(
                  'FIDO2 / WebAuthn 标准无密码通行密钥',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: theme.colorScheme.primary,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              '支持安全生成并保存各网站注册的通行密钥参数。私钥在本地强加密保护，支持离线备份与迁移。',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton.tonalIcon(
                  onPressed: _generatePasskeyMockKeyPair,
                  icon: const Icon(Icons.auto_awesome_rounded, size: 16),
                  label: const Text('本地生成合规密钥对 (ES256)'),
                ),
                OutlinedButton.icon(
                  onPressed: _smartScanAndFill,
                  icon: const Icon(Icons.qr_code_scanner_rounded, size: 16),
                  label: const Text('扫码导入二维码'),
                ),
                OutlinedButton.icon(
                  onPressed: _parseWebAuthnJson,
                  icon: const Icon(Icons.paste_rounded, size: 16),
                  label: const Text('粘贴注册 JSON'),
                ),
              ],
            ),
          ],
        ),
      ),
      TextFormField(
        controller: _passkeyRpIdController,
        decoration: InputDecoration(
          labelText: '绑定网站域名 (RP ID) *',
          hintText: '例如：github.com, google.com, apple.com',
          prefixIcon: const Icon(Icons.language_rounded),
          suffixIcon: IconButton(
            icon: const Icon(Icons.qr_code_scanner_rounded),
            tooltip: '扫码录入域名',
            onPressed: () => _scanToField(_passkeyRpIdController, '绑定网站域名'),
          ),
          border: const OutlineInputBorder(),
        ),
        validator: (v) =>
            (v == null || v.trim().isEmpty) ? '请输入绑定网站域名 (RP ID)' : null,
      ),
      const SizedBox(height: 16),
      TextFormField(
        controller: _passkeyUserNameController,
        decoration: const InputDecoration(
          labelText: '绑定用户名 / 账号 *',
          hintText: 'user@example.com 或 octocat',
          prefixIcon: Icon(Icons.person_outline),
          border: OutlineInputBorder(),
        ),
        validator: (v) =>
            (v == null || v.trim().isEmpty) ? '请输入关联用户名或账号' : null,
      ),
      const SizedBox(height: 16),
      TextFormField(
        controller: _passkeyCredentialIdController,
        decoration: InputDecoration(
          labelText: '凭据 ID (Credential ID) *',
          hintText: 'Base64URL 格式的 WebAuthn 凭据 ID',
          prefixIcon: const Icon(Icons.vpn_key_outlined),
          suffixIcon: IconButton(
            icon: const Icon(Icons.qr_code_scanner_rounded),
            tooltip: '扫码录入凭据 ID',
            onPressed: () =>
                _scanToField(_passkeyCredentialIdController, '凭据 ID'),
          ),
          border: const OutlineInputBorder(),
        ),
        validator: (v) =>
            (v == null || v.trim().isEmpty) ? '请输入或生成凭据 ID' : null,
      ),
      const SizedBox(height: 16),
      DropdownButtonFormField<String>(
        value: _passkeyAlgorithm,
        isExpanded: true,
        decoration: const InputDecoration(
          labelText: '加密签名算法',
          prefixIcon: Icon(Icons.security_outlined),
          border: OutlineInputBorder(),
        ),
        items: const [
          DropdownMenuItem(
            value: 'ES256',
            child: Text('ES256 (ECDSA P-256，推荐标准)'),
          ),
          DropdownMenuItem(value: 'RS256', child: Text('RS256 (RSA 2048)')),
          DropdownMenuItem(value: 'EdDSA', child: Text('EdDSA (Ed25519)')),
        ],
        onChanged: (val) {
          if (val != null) setState(() => _passkeyAlgorithm = val);
        },
      ),
      const SizedBox(height: 16),
      TextFormField(
        controller: _passkeyUserHandleController,
        decoration: InputDecoration(
          labelText: '用户标识 (User Handle，可选)',
          hintText: '依赖方生成的内部用户标识 (Base64 或字符串)',
          prefixIcon: const Icon(Icons.badge_outlined),
          suffixIcon: IconButton(
            icon: const Icon(Icons.qr_code_scanner_rounded),
            tooltip: '扫码录入用户标识',
            onPressed: () => _scanToField(
              _passkeyUserHandleController,
              '用户标识 (User Handle)',
            ),
          ),
          border: const OutlineInputBorder(),
        ),
      ),
      const SizedBox(height: 16),
      ExpansionTile(
        title: const Text('高级：本地私钥与公钥材料 (可选安全保存)'),
        subtitle: const Text('查看或手动录入该通行密钥的非对称密钥对'),
        leading: const Icon(Icons.lock_clock_outlined),
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            child: Column(
              children: [
                TextFormField(
                  controller: _passkeyPrivateKeyController,
                  maxLines: 3,
                  decoration: const InputDecoration(
                    labelText: '私钥材料 (Private Key，Base64 / PEM)',
                    hintText: '仅在设备本地安全保存',
                    prefixIcon: Icon(Icons.key_rounded),
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _passkeyPublicKeyController,
                  maxLines: 2,
                  decoration: const InputDecoration(
                    labelText: '公钥材料 (Public Key，Base64)',
                    hintText: '注册到服务器的公钥',
                    prefixIcon: Icon(Icons.key_off_outlined),
                    border: OutlineInputBorder(),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    ];
  }

  Future<void> _scanAndFillTotp() async {
    final raw = await Navigator.of(context).push<String>(
      MaterialPageRoute(
        builder: (_) => const QRScannerScreen(
          returnRawContent: true,
          title: '扫描 TOTP 动态码',
          prompt: '将双因子认证二维码置于框内即可自动识别',
        ),
      ),
    );

    if (raw == null || raw.trim().isEmpty) return;

    final uriData = TotpEngine.parseUri(raw.trim());
    if (uriData != null) {
      final issuerStr = uriData.issuer ?? '';
      final accountStr = uriData.account ?? '';
      setState(() {
        if (_titleController.text.trim().isEmpty) {
          _titleController.text = issuerStr.isNotEmpty
              ? issuerStr
              : (accountStr.isNotEmpty ? accountStr : 'TOTP 动态码');
        }
        if (issuerStr.isNotEmpty) _issuerController.text = issuerStr;
        if (accountStr.isNotEmpty) _accountController.text = accountStr;
        _secretController.text = uriData.secret;
        _algorithm = uriData.algorithm;
        _digits = uriData.digits;
        _period = uriData.period;
        _customPeriodController.text = _period.toString();
      });
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('已从二维码自动识别并填充 TOTP 参数')));
      }
    } else {
      final cleaned = raw.replaceAll(RegExp(r'\s+'), '').toUpperCase();
      setState(() {
        _secretController.text = cleaned;
      });
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('已自动提取并填充 TOTP 密钥')));
      }
    }
  }

  // --- TOTP 输入字段 ---
  List<Widget> _buildTotpFields(ThemeData theme) {
    final hasSecret = _secretController.text.trim().isNotEmpty;
    final isNewEntry = widget.initialItem == null;

    return [
      // 1. 核心专业扫码识别控件卡片
      Container(
        margin: const EdgeInsets.only(bottom: 16),
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: theme.colorScheme.primaryContainer.withValues(alpha: 0.25),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: theme.colorScheme.primary.withValues(alpha: 0.3),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primary,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.qr_code_scanner_rounded,
                    color: Colors.white,
                    size: 24,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '扫码添加动态验证码',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '两步验证 (2FA 动态口令)',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              '扫描网站或应用提供的两步验证二维码，自动识别并生成动态验证码：',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed: _scanAndFillTotp,
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                    icon: const Icon(Icons.qr_code_scanner_rounded, size: 18),
                    label: const Text('扫码'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () async {
                      final data = await Clipboard.getData(
                        Clipboard.kTextPlain,
                      );
                      if (data?.text != null && data!.text!.trim().isNotEmpty) {
                        final raw = data.text!.trim();
                        if (_parseOtpauthString(raw)) {
                          return;
                        }
                        final cleaned = raw
                            .replaceAll(RegExp(r'\s+'), '')
                            .toUpperCase();
                        setState(() {
                          _secretController.text = cleaned;
                        });
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('已自动提取并填充密钥')),
                          );
                        }
                      } else {
                        _showImportOtpauthDialog();
                      }
                    },
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                    icon: const Icon(Icons.paste_rounded, size: 18),
                    label: const Text('从剪贴板粘贴'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),

      // 实时动态验证码预览（若已有密钥）
      if (hasSecret) ...[
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: theme.colorScheme.primaryContainer.withValues(alpha: 0.3),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: theme.colorScheme.primary.withValues(alpha: 0.2),
            ),
          ),
          child: Row(
            children: [
              TotpTimerRing(period: _period, size: 24),
              const SizedBox(width: 12),
              Text(
                '动态码: ',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              Consumer(
                builder: (context, ref, _) {
                  ref.watch(totpTickerProvider);
                  return Text(
                    _previewTotp(),
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                      letterSpacing: 2.0,
                      color: theme.colorScheme.primary,
                    ),
                  );
                },
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: theme.colorScheme.primary.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  '${_period}s',
                  style: theme.textTheme.labelSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: theme.colorScheme.primary,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
      ],

      // 2. 手动输入密钥与更多设置折叠面板
      ExpansionTile(
        initiallyExpanded: hasSecret || !isNewEntry,
        tilePadding: EdgeInsets.zero,
        leading: const Icon(Icons.tune_rounded),
        title: const Text(
          '手动输入密钥及更多设置',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        subtitle: Text(
          hasSecret
              ? '已设置密钥 · ${_issuerController.text.isNotEmpty ? _issuerController.text : "未填写服务商"}'
              : '没有二维码？可展开手动输入密钥和账号',
          style: const TextStyle(fontSize: 12),
        ),
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextFormField(
                  controller: _issuerController,
                  decoration: const InputDecoration(
                    labelText: '发行机构 / 服务商',
                    hintText: '例如：Google, GitHub, 微软',
                    prefixIcon: Icon(Icons.business_outlined),
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _accountController,
                  decoration: const InputDecoration(
                    labelText: '账号 / 用户名 / 邮箱',
                    hintText: 'user@example.com',
                    prefixIcon: Icon(Icons.person_outline),
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _secretController,
                  decoration: InputDecoration(
                    labelText: '双重验证密钥 *',
                    hintText: '服务商提供的安全密钥，支持直接粘贴 otpauth:// 链接',
                    prefixIcon: const Icon(Icons.key_rounded),
                    border: const OutlineInputBorder(),
                    suffixIcon: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.link_rounded),
                          tooltip: '粘贴或输入 otpauth 链接',
                          onPressed: _showImportOtpauthDialog,
                        ),
                        IconButton(
                          icon: const Icon(Icons.paste_rounded),
                          tooltip: '快捷粘贴并自动清洗空格',
                          onPressed: () async {
                            final data = await Clipboard.getData(
                              Clipboard.kTextPlain,
                            );
                            if (data?.text != null &&
                                data!.text!.trim().isNotEmpty) {
                              final raw = data.text!.trim();
                              if (_parseOtpauthString(raw)) {
                                return;
                              }
                              final cleaned = raw
                                  .replaceAll(RegExp(r'\s+'), '')
                                  .toUpperCase();
                              setState(() {
                                _secretController.text = cleaned;
                              });
                            }
                          },
                        ),
                      ],
                    ),
                  ),
                  validator: (v) {
                    if (v == null || v.trim().isEmpty) return '双重验证密钥不能为空';
                    return null;
                  },
                  onChanged: (v) {
                    if (v.contains('otpauth://')) {
                      _parseOtpauthString(v);
                    }
                    setState(() {});
                  },
                ),
                const SizedBox(height: 16),
                // 高级算法与自定义刷新周期设置
                _buildTotpAdvancedSettings(theme),
                const SizedBox(height: 16),
                // 2FA 应急恢复码输入清单
                _buildRecoveryCodeInputs(theme),
              ],
            ),
          ),
        ],
      ),
    ];
  }

  /// 构建 TOTP 高级参数设置组件（支持自定义超时周期、位数与哈希算法）
  Widget _buildTotpAdvancedSettings(ThemeData theme) {
    final isCustomPeriod = _period != 30 && _period != 60 && _period != 15;

    return ExpansionTile(
      initiallyExpanded:
          isCustomPeriod || _digits != 6 || _algorithm != OtpAlgorithm.sha1,
      tilePadding: EdgeInsets.zero,
      leading: const Icon(Icons.tune_rounded),
      title: const Text('高级参数：刷新周期与算法配置'),
      subtitle: Text(
        '当前：$_period 秒超时 · $_digits 位动态码 · ${_algorithm.nameString}',
      ),
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 1. 刷新周期 (超时时间)
              const Text(
                '动态口令刷新周期 (超时时间)',
                style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  ChoiceChip(
                    label: const Text('30 秒 (标准默认)'),
                    selected: _period == 30,
                    onSelected: (sel) {
                      if (sel) {
                        setState(() {
                          _period = 30;
                          _customPeriodController.text = '30';
                        });
                      }
                    },
                  ),
                  ChoiceChip(
                    label: const Text('60 秒 (双倍周期)'),
                    selected: _period == 60,
                    onSelected: (sel) {
                      if (sel) {
                        setState(() {
                          _period = 60;
                          _customPeriodController.text = '60';
                        });
                      }
                    },
                  ),
                  ChoiceChip(
                    label: const Text('15 秒 (高频)'),
                    selected: _period == 15,
                    onSelected: (sel) {
                      if (sel) {
                        setState(() {
                          _period = 15;
                          _customPeriodController.text = '15';
                        });
                      }
                    },
                  ),
                  ChoiceChip(
                    label: const Text('自定义秒数'),
                    selected: isCustomPeriod,
                    onSelected: (sel) {
                      if (sel) {
                        setState(() {
                          if (!isCustomPeriod) {
                            _period = 45;
                            _customPeriodController.text = '45';
                          }
                        });
                      }
                    },
                  ),
                ],
              ),
              if (isCustomPeriod) ...[
                const SizedBox(height: 10),
                TextFormField(
                  controller: _customPeriodController,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: const InputDecoration(
                    labelText: '自定义超时周期 (秒) *',
                    hintText: '输入有效秒数 (如 45, 90, 120)',
                    suffixText: '秒',
                    prefixIcon: Icon(Icons.timer_outlined),
                    border: OutlineInputBorder(),
                  ),
                  onChanged: (val) {
                    final p = int.tryParse(val.trim());
                    if (p != null && p > 0) {
                      setState(() => _period = p);
                    }
                  },
                ),
              ],
              const SizedBox(height: 16),
              // 2. 验证码位数
              DropdownButtonFormField<int>(
                value: _digits,
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: '验证码位数 (Digits)',
                  prefixIcon: Icon(Icons.pin_outlined),
                  border: OutlineInputBorder(),
                ),
                items: const [
                  DropdownMenuItem(
                    value: 6,
                    child: Text('6 位数 (RFC 6238 标准通用)'),
                  ),
                  DropdownMenuItem(
                    value: 8,
                    child: Text('8 位数 (部分特殊企业/银行 2FA)'),
                  ),
                  DropdownMenuItem(value: 7, child: Text('7 位数')),
                ],
                onChanged: (val) {
                  if (val != null) setState(() => _digits = val);
                },
              ),
              const SizedBox(height: 16),
              // 3. 哈希摘要算法
              DropdownButtonFormField<OtpAlgorithm>(
                value: _algorithm,
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: '哈希摘要算法 (HMAC Algorithm)',
                  prefixIcon: Icon(Icons.fingerprint_rounded),
                  border: OutlineInputBorder(),
                ),
                items: const [
                  DropdownMenuItem(
                    value: OtpAlgorithm.sha1,
                    child: Text('SHA1 (绝大多数服务标准兼容)'),
                  ),
                  DropdownMenuItem(
                    value: OtpAlgorithm.sha256,
                    child: Text('SHA256'),
                  ),
                  DropdownMenuItem(
                    value: OtpAlgorithm.sha512,
                    child: Text('SHA512'),
                  ),
                ],
                onChanged: (val) {
                  if (val != null) setState(() => _algorithm = val);
                },
              ),
            ],
          ),
        ),
      ],
    );
  }

  String _previewTotp() {
    try {
      return TotpEngine.generateCode(
        secret: _secretController.text,
        algorithm: _algorithm,
        digits: _digits,
        period: _period,
      );
    } catch (_) {
      return '格式无效';
    }
  }

  // --- 账号密码字段 ---
  List<Widget> _buildPasswordFields(ThemeData theme, {bool allowTotp = false}) {
    return [
      TextFormField(
        controller: _urlController,
        inputFormatters: const [ImeSafeTextInputFormatter()],
        decoration: InputDecoration(
          labelText: '登录网址 / URL',
          hintText: 'https://github.com/login',
          prefixIcon: const Icon(Icons.link_rounded),
          suffixIcon: IconButton(
            icon: const Icon(Icons.qr_code_scanner_rounded),
            tooltip: '扫码识别网址',
            onPressed: () => _scanToField(_urlController, '登录网址'),
          ),
          border: const OutlineInputBorder(),
        ),
      ),
      const SizedBox(height: 12),
      DropdownButtonFormField<UrlMatchType>(
        value: _urlMatchType,
        decoration: InputDecoration(
          labelText: '网址匹配规则',
          prefixIcon: const Icon(Icons.tune_rounded),
          helperText: _urlMatchType.description,
          helperMaxLines: 2,
          border: const OutlineInputBorder(),
        ),
        isExpanded: true,
        items: UrlMatchType.values.map((type) {
          return DropdownMenuItem<UrlMatchType>(
            value: type,
            child: Text(type.label),
          );
        }).toList(),
        onChanged: (val) {
          if (val != null) {
            setState(() {
              _urlMatchType = val;
            });
          }
        },
      ),
      const SizedBox(height: 16),
      TextFormField(
        controller: _accountController,
        inputFormatters: const [ImeSafeTextInputFormatter()],
        decoration: const InputDecoration(
          labelText: '用户名 / 邮箱 / 登录账号',
          prefixIcon: Icon(Icons.person_outline),
          border: OutlineInputBorder(),
        ),
      ),
      const SizedBox(height: 16),
      TextFormField(
        controller: _passwordController,
        obscureText: _obscurePassword,
        decoration: InputDecoration(
          labelText: '登录密码',
          prefixIcon: const Icon(Icons.lock_outline),
          border: const OutlineInputBorder(),
          suffixIcon: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                icon: Icon(
                  _obscurePassword
                      ? Icons.visibility_outlined
                      : Icons.visibility_off_outlined,
                ),
                tooltip: _obscurePassword ? '显示明文密码' : '隐藏密码',
                onPressed: () =>
                    setState(() => _obscurePassword = !_obscurePassword),
              ),
              IconButton(
                icon: const Icon(Icons.qr_code_scanner_rounded),
                tooltip: '扫码录入密码/文本',
                onPressed: () => _scanToField(_passwordController, '登录密码'),
              ),
              IconButton(
                icon: const Icon(Icons.auto_awesome_rounded),
                tooltip: '纯本地生成强随机密码',
                onPressed: _generatePassword,
              ),
            ],
          ),
        ),
      ),
      if (allowTotp) ...[
        const SizedBox(height: 16),
        ExpansionTile(
          title: const Text('关联 TOTP 动态码'),
          subtitle: _linkedExistingTotpTitle != null
              ? Text(
                  '已关联: $_linkedExistingTotpTitle',
                  style: const TextStyle(color: Colors.green, fontSize: 12),
                )
              : null,
          leading: const Icon(Icons.timer_outlined),
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (_linkedExistingTotpTitle != null) ...[
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Chip(
                        avatar: const Icon(
                          Icons.check_circle_rounded,
                          size: 16,
                          color: Colors.green,
                        ),
                        label: Text(
                          '已关联: $_linkedExistingTotpTitle',
                          overflow: TextOverflow.ellipsis,
                        ),
                        onDeleted: () {
                          setState(() {
                            _linkedExistingTotpTitle = null;
                            _secretController.clear();
                          });
                        },
                      ),
                    ),
                  ],
                  TextFormField(
                    controller: _secretController,
                    decoration: InputDecoration(
                      labelText: '双重验证密钥 (可选)',
                      hintText:
                          '例如：JBSWY3DPEHPK3PXP，支持直接粘贴 otpauth:// 链接',
                      suffixIcon: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            icon: const Icon(Icons.hub_outlined),
                            tooltip: '从已有 TOTP 选择关联',
                            onPressed: _showPickExistingTotpDialog,
                          ),
                          IconButton(
                            icon: const Icon(Icons.paste_rounded),
                            tooltip: '粘贴或输入 otpauth 链接',
                            onPressed: _showImportOtpauthDialog,
                          ),
                          IconButton(
                            icon: const Icon(Icons.qr_code_scanner_rounded),
                            tooltip: '扫码识别双重验证密钥',
                            onPressed: () =>
                                _scanToField(_secretController, '双重验证密钥'),
                          ),
                        ],
                      ),
                      border: const OutlineInputBorder(),
                    ),
                    onChanged: (val) {
                      if (val.contains('otpauth://')) {
                        _parseOtpauthString(val);
                      }
                      setState(() {});
                    },
                  ),
                  if (_secretController.text.trim().isNotEmpty) ...[
                    const SizedBox(height: 12),
                    _buildTotpAdvancedSettings(theme),
                  ],
                ],
              ),
            ),
          ],
        ),
      ],
    ];
  }

  // --- 服务器私钥字段 ---
  List<Widget> _buildServerKeyFields(ThemeData theme) {
    return [
      Row(
        children: [
          Expanded(
            flex: 3,
            child: TextFormField(
              controller: _serverHostController,
              decoration: InputDecoration(
                labelText: '主机地址 (IP / 域名) *',
                hintText: '192.168.1.100',
                prefixIcon: const Icon(Icons.dns_outlined),
                suffixIcon: IconButton(
                  icon: const Icon(Icons.qr_code_scanner_rounded),
                  tooltip: '扫码录入主机地址',
                  onPressed: () => _scanToField(_serverHostController, '服务器主机'),
                ),
                border: const OutlineInputBorder(),
              ),
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? '请输入服务器主机' : null,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            flex: 1,
            child: TextFormField(
              controller: _serverPortController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: '端口',
                hintText: '22',
                border: OutlineInputBorder(),
              ),
            ),
          ),
        ],
      ),
      const SizedBox(height: 16),
      TextFormField(
        controller: _serverUserController,
        decoration: const InputDecoration(
          labelText: '登录用户名',
          hintText: 'ubuntu / root',
          prefixIcon: Icon(Icons.account_circle_outlined),
          border: OutlineInputBorder(),
        ),
      ),
      const SizedBox(height: 16),
      TextFormField(
        controller: _keyPassphraseController,
        decoration: const InputDecoration(
          labelText: '私钥口令 (Passphrase，可选)',
          prefixIcon: Icon(Icons.key_outlined),
          border: OutlineInputBorder(),
        ),
      ),
      const SizedBox(height: 16),
      TextFormField(
        controller: _privateKeyController,
        maxLines: 6,
        decoration: const InputDecoration(
          labelText: 'SSH 私钥文本内容 (OpenSSH / PEM 格式) *',
          hintText: '-----BEGIN OPENSSH PRIVATE KEY-----\n...\n-----END OPENSSH PRIVATE KEY-----',
          prefixIcon: Icon(Icons.terminal_rounded),
          border: OutlineInputBorder(),
          alignLabelWithHint: true,
        ),
        validator: (v) => (v == null || v.trim().isEmpty) ? '请输入或粘贴私钥文本' : null,
      ),
    ];
  }

  // --- 开发者 API Key ---
  List<Widget> _buildApiKeyFields(ThemeData theme) {
    return [
      TextFormField(
        controller: _apiProviderController,
        decoration: const InputDecoration(
          labelText: '服务提供商',
          hintText: 'OpenAI, GitHub, AWS, Stripe 等',
          prefixIcon: Icon(Icons.cloud_outlined),
          border: OutlineInputBorder(),
        ),
      ),
      const SizedBox(height: 16),
      TextFormField(
        controller: _apiKeyController,
        decoration: InputDecoration(
          labelText: 'API Key / Secret Token *',
          hintText: 'sk-proj-...',
          prefixIcon: const Icon(Icons.vpn_key_outlined),
          suffixIcon: IconButton(
            icon: const Icon(Icons.qr_code_scanner_rounded),
            tooltip: '扫码录入 API Key',
            onPressed: () => _scanToField(_apiKeyController, 'API Key'),
          ),
          border: const OutlineInputBorder(),
        ),
        validator: (v) =>
            (v == null || v.trim().isEmpty) ? '请输入 API Key' : null,
      ),
    ];
  }

  // --- 加密钱包助记词 ---
  List<Widget> _buildCryptoWalletFields(ThemeData theme) {
    return [
      TextFormField(
        controller: _cryptoAddressController,
        decoration: InputDecoration(
          labelText: '钱包公钥地址 (可选)',
          hintText: '0x...',
          prefixIcon: const Icon(Icons.wallet_outlined),
          suffixIcon: IconButton(
            icon: const Icon(Icons.qr_code_scanner_rounded),
            tooltip: '扫码识别钱包地址',
            onPressed: () => _scanToField(_cryptoAddressController, '钱包地址'),
          ),
          border: const OutlineInputBorder(),
        ),
      ),
      const SizedBox(height: 16),
      TextFormField(
        controller: _cryptoSeedController,
        maxLines: 4,
        decoration: const InputDecoration(
          labelText: '12 / 24 位助记词 (以空格分隔) *',
          hintText: 'apple banana cat dog elephant fish grape hat ice jungle kite lemon',
          prefixIcon: Icon(Icons.grid_view_rounded),
          border: OutlineInputBorder(),
          alignLabelWithHint: true,
        ),
        validator: (v) => (v == null || v.trim().isEmpty) ? '助记词不能为空' : null,
      ),
    ];
  }

  // --- 银行卡 ---
  List<Widget> _buildCardFields(ThemeData theme) {
    return [
      TextFormField(
        controller: _cardNumberController,
        keyboardType: TextInputType.number,
        decoration: InputDecoration(
          labelText: '卡号 *',
          hintText: '4111 2222 3333 4444',
          prefixIcon: const Icon(Icons.credit_card_rounded),
          suffixIcon: IconButton(
            icon: const Icon(Icons.qr_code_scanner_rounded),
            tooltip: '扫码录入卡号',
            onPressed: () => _scanToField(_cardNumberController, '银行卡号'),
          ),
          border: const OutlineInputBorder(),
        ),
        validator: (v) => (v == null || v.trim().isEmpty) ? '卡号不能为空' : null,
      ),
      const SizedBox(height: 16),
      Row(
        children: [
          Expanded(
            child: TextFormField(
              controller: _cardHolderController,
              decoration: const InputDecoration(
                labelText: '持卡人姓名',
                border: OutlineInputBorder(),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: TextFormField(
              controller: _cardExpiryController,
              decoration: const InputDecoration(
                labelText: '有效期 (MM/YY)',
                hintText: '10/28',
                border: OutlineInputBorder(),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: TextFormField(
              controller: _cardCvvController,
              decoration: const InputDecoration(
                labelText: 'CVV / CVC',
                hintText: '888',
                border: OutlineInputBorder(),
              ),
            ),
          ),
        ],
      ),
    ];
  }

  // --- 身份档案 ---
  List<Widget> _buildIdentityFields(ThemeData theme) {
    return [
      TextFormField(
        controller: _fullNameController,
        decoration: const InputDecoration(
          labelText: '姓名',
          prefixIcon: Icon(Icons.person_outline),
          border: OutlineInputBorder(),
        ),
      ),
      const SizedBox(height: 16),
      TextFormField(
        controller: _idNumberController,
        decoration: InputDecoration(
          labelText: '证件号码 *',
          prefixIcon: const Icon(Icons.badge_outlined),
          suffixIcon: IconButton(
            icon: const Icon(Icons.qr_code_scanner_rounded),
            tooltip: '扫码录入证件号',
            onPressed: () => _scanToField(_idNumberController, '证件号码'),
          ),
          border: const OutlineInputBorder(),
        ),
        validator: (v) => (v == null || v.trim().isEmpty) ? '证件号码不能为空' : null,
      ),
    ];
  }

  // --- 2FA 应急恢复码录入区 ---
  Widget _buildRecoveryCodeInputs(ThemeData theme) {
    return Card(
      elevation: 0,
      color: theme.colorScheme.surfaceVariant.withOpacity(0.3),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  '2FA 应急备用恢复码 (${_recoveryCodes.length} 个)',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                if (_recoveryCodes.isNotEmpty)
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (_recoveryCodes.length > 1)
                        TextButton.icon(
                          onPressed: _mergeAllRecoveryCodes,
                          icon: const Icon(Icons.call_merge_rounded, size: 15),
                          label: const Text('合并为1个完整码'),
                          style: TextButton.styleFrom(
                            visualDensity: VisualDensity.compact,
                            foregroundColor: theme.colorScheme.primary,
                          ),
                        ),
                      TextButton(
                        onPressed: () => setState(() => _recoveryCodes.clear()),
                        child: const Text(
                          '清空',
                          style: TextStyle(color: Colors.red),
                        ),
                      ),
                    ],
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: TextField(
                    controller: _batchRecoveryCodesController,
                    minLines: 1,
                    maxLines: 3,
                    decoration: const InputDecoration(
                      labelText: '录入恢复码',
                      hintText: '换行/逗号批量粘贴',
                      isDense: true,
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: FilledButton.tonal(
                    onPressed: _parseBatchRecoveryCodes,
                    child: const Text('添加'),
                  ),
                ),
              ],
            ),
            if (_recoveryCodes.isNotEmpty) ...[
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: List.generate(_recoveryCodes.length, (idx) {
                  final code = _recoveryCodes[idx];
                  return InputChip(
                    label: Text(
                      code.code,
                      style: const TextStyle(
                        fontSize: 12,
                        fontFamily: 'monospace',
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    tooltip: '点击可修改内容',
                    onPressed: () => _editRecoveryCodeDialog(idx),
                    deleteIcon: const Icon(Icons.close, size: 14),
                    onDeleted: () {
                      setState(() => _recoveryCodes.removeAt(idx));
                    },
                  );
                }),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
