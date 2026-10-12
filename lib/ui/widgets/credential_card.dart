import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/security/clipboard_manager.dart';
import '../../core/totp/totp_engine.dart';
import '../../core/utils/ssh_helper.dart';
import '../../models/credential.dart';
import '../../providers/vault_provider.dart';
import '../../providers/app_settings_provider.dart';

import 'package:qr_flutter/qr_flutter.dart';

import 'totp_timer_ring.dart';

/// 现代化多功能凭据卡片
class CredentialCard extends ConsumerStatefulWidget {
  final Credential item;
  final VoidCallback onEdit;
  final VoidCallback? onDelete;
  final EdgeInsetsGeometry? margin;

  const CredentialCard({
    super.key,
    required this.item,
    required this.onEdit,
    this.onDelete,
    this.margin,
  });

  @override
  ConsumerState<CredentialCard> createState() => _CredentialCardState();
}

class _CredentialCardState extends ConsumerState<CredentialCard> {
  bool _revealed = false; // 是否明文显隐（针对密码、私钥、助记词）

  void _copy(String text, String tip) {
    ClipboardManager.copyWithAutoClear(text);
    HapticFeedback.lightImpact();
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('$tip 已复制（30 秒后自动清空剪贴板）'),
        duration: const Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  void _showTotpQrDialog(BuildContext context, Credential item) {
    final uri = TotpEngine.generateUri(
      issuer: item.issuer.isNotEmpty ? item.issuer : item.title,
      account: item.account.isNotEmpty ? item.account : '用户',
      secret: item.secret,
      algorithm: item.algorithm,
      digits: item.digits,
      period: item.period,
    );

    final theme = Theme.of(context);

    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
        ),
        insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
        child: Container(
          width: 340,
          padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // 顶部标题区：纯粹简约的凭据名称与说明
              Text(
                item.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  letterSpacing: -0.3,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                item.account.isNotEmpty
                    ? '${item.account} · 扫码快速导入'
                    : '其他验证器对准即可扫码录入',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 13,
                  color: theme.colorScheme.outline,
                ),
              ),

              const SizedBox(height: 20),

              // 中间二维码卡片（圆角双层细腻阴影容器）
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: Colors.black.withValues(alpha: 0.08),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.04),
                      blurRadius: 16,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
                child: QrImageView(
                  data: uri,
                  version: QrVersions.auto,
                  size: 200.0,
                  backgroundColor: Colors.white,
                  eyeStyle: const QrEyeStyle(
                    eyeShape: QrEyeShape.square,
                    color: Color(0xFF1E293B),
                  ),
                  dataModuleStyle: const QrDataModuleStyle(
                    dataModuleShape: QrDataModuleShape.square,
                    color: Color(0xFF1E293B),
                  ),
                ),
              ),

              const SizedBox(height: 18),

              // 底部快捷操作条（精致的全宽胶囊按钮）
              OutlinedButton.icon(
                icon: const Icon(Icons.link_rounded, size: 16),
                label: const Text('复制 otpauth 导入链接'),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size.fromHeight(40),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                onPressed: () => _copy(uri, 'otpauth 链接'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final item = widget.item;

    // 若包含 TOTP 动态码，监听全局秒级时钟，周期到期时自动重新计算并即时刷新验证码
    if (item.type == CredentialType.totp || item.secret.isNotEmpty) {
      ref.watch(totpTickerProvider);
    }

    final density = ref.watch(appSettingsProvider).cardDensity;
    final isCompact = density == CardDensity.compact;

    return Theme(
      data: theme.copyWith(
        visualDensity: isCompact ? VisualDensity.compact : VisualDensity.comfortable,
        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
        iconButtonTheme: IconButtonThemeData(
          style: IconButton.styleFrom(
            visualDensity: VisualDensity.compact,
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
        ),
      ),
      child: Card(
        elevation: 0,
        margin:
            widget.margin ??
            EdgeInsets.symmetric(horizontal: 0, vertical: isCompact ? 2 : 4),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(
            color: item.pinned
                ? theme.colorScheme.primary.withOpacity(0.5)
                : theme.colorScheme.outlineVariant.withOpacity(0.4),
            width: item.pinned ? 1.5 : 1.0,
          ),
        ),
        color: item.pinned
            ? theme.colorScheme.primaryContainer.withOpacity(0.15)
            : theme.colorScheme.surface,
        child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: isCompact ? 12 : 16,
          vertical: isCompact ? 10 : 14,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 卡片头部：类型图标、标题、标签与置顶菜单
            _buildHeader(context, theme, item),
            SizedBox(height: isCompact ? 8 : 12),

            // 卡片核心内容区（根据凭据类型分流）
            _buildBody(context, theme, item),

            // 备注区域（若有，且非系统自动关联提示，自动提示仅在详情弹窗内展示）
            if (item.notes.isNotEmpty &&
                !_isAutoGeneratedTotpNote(item.notes)) ...[
              const SizedBox(height: 10),
              Padding(
                padding: const EdgeInsets.only(right: 6),
                child: Tooltip(
                  message: item.notes,
                  waitDuration: const Duration(milliseconds: 250),
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surfaceVariant.withOpacity(0.35),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      item.notes,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    ),
  );
}

  Widget _buildHeader(BuildContext context, ThemeData theme, Credential item) {
    final typeIcon = item.type.icon;
    final isCompact =
        ref.watch(appSettingsProvider).cardDensity == CardDensity.compact;

    return Row(
      children: [
        Expanded(
          child: Material(
            color: Colors.transparent,
            child: Tooltip(
              message: '点击查看完整详情大卡片',
              child: InkWell(
                borderRadius: BorderRadius.circular(10),
                onTap: () => _showDetailDialog(context, theme, item),
                child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 2.0),
                child: Row(
                  children: [
                    Container(
                      padding: EdgeInsets.all(isCompact ? 6 : 8),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.primaryContainer.withValues(
                          alpha: 0.6,
                        ),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(
                        typeIcon,
                        size: isCompact ? 18 : 20,
                        color: theme.colorScheme.primary,
                      ),
                    ),
                    SizedBox(width: isCompact ? 8 : 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: AutoScrollText(
                                  text: item.title,
                                  style: theme.textTheme.titleMedium?.copyWith(
                                    fontWeight: FontWeight.bold,
                                    fontSize: isCompact ? 14 : 15,
                                  ),
                                ),
                              ),
                              if (item.pinned) ...[
                                const SizedBox(width: 4),
                                Icon(
                                  Icons.push_pin,
                                  size: 13,
                                  color: theme.colorScheme.primary,
                                ),
                              ],
                            ],
                          ),
                          if (item.account.isNotEmpty ||
                              item.issuer.isNotEmpty ||
                              item.serverHost.isNotEmpty) ...[
                            const SizedBox(height: 2),
                            AutoScrollText(
                              text: [
                                if (item.account.isNotEmpty) item.account,
                                if (item.issuer.isNotEmpty) item.issuer,
                                if (item.serverHost.isNotEmpty)
                                  '${item.serverUser.isEmpty ? "" : "${item.serverUser}@"}${item.serverHost}',
                              ].join(' · '),
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                                fontSize: isCompact ? 11 : 12,
                              ),
                              velocity: 11.5,
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
      SizedBox(width: isCompact ? 6 : 8),
        PopupMenuButton<String>(
          tooltip: '更多操作',
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(),
          child: Container(
            width: 32,
            height: 32,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(
              Icons.more_vert,
              size: 18,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          onSelected: (val) {
            if (val == 'qr') _showTotpQrDialog(context, item);
            if (val == 'recovery_codes')
              _showRecoveryCodesDialog(context, item);
            if (val == 'edit') widget.onEdit();
            if (val == 'pin')
              ref.read(vaultProvider.notifier).togglePin(item.id, item.pinned);
            if (val == 'delete') {
              if (widget.onDelete != null) {
                widget.onDelete!();
              } else {
                ref.read(vaultProvider.notifier).moveToTrash(item.id);
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
                        if (context.mounted) {
                          messenger.hideCurrentSnackBar();
                        }
                      });
                    },
                    action: SnackBarAction(
                      label: '撤销',
                      onPressed: () {
                        messenger.hideCurrentSnackBar();
                        ref
                            .read(vaultProvider.notifier)
                            .restoreFromTrash(item.id);
                      },
                    ),
                  ),
                );
              }
            }
          },
          itemBuilder: (context) => [
            if (item.type == CredentialType.totp || item.secret.isNotEmpty)
              const PopupMenuItem(
                value: 'qr',
                child: Row(
                  children: [
                    Icon(Icons.qr_code_2_rounded, size: 18),
                    SizedBox(width: 8),
                    Text('展示 2FA 二维码'),
                  ],
                ),
              ),
            if (item.recoveryCodes.isNotEmpty)
              PopupMenuItem(
                value: 'recovery_codes',
                child: Row(
                  children: [
                    const Icon(Icons.key_rounded, size: 18),
                    const SizedBox(width: 8),
                    Text(
                      '应急恢复码 (${item.recoveryCodes.where((c) => !c.used).length}/${item.recoveryCodes.length})',
                    ),
                  ],
                ),
              ),
            PopupMenuItem(
              value: 'pin',
              child: Row(
                children: [
                  Icon(
                    item.pinned ? Icons.push_pin_outlined : Icons.push_pin,
                    size: 18,
                  ),
                  SizedBox(width: 8),
                  Text(item.pinned ? '取消置顶' : '置顶凭据'),
                ],
              ),
            ),
            const PopupMenuItem(
              value: 'edit',
              child: Row(
                children: [
                  Icon(Icons.edit_outlined, size: 18),
                  SizedBox(width: 8),
                  Text('编辑'),
                ],
              ),
            ),
            const PopupMenuItem(
              value: 'delete',
              child: Row(
                children: [
                  Icon(Icons.delete_outline, size: 18, color: Colors.red),
                  SizedBox(width: 8),
                  Text('移入垃圾箱', style: TextStyle(color: Colors.red)),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }

  void _showDetailDialog(
    BuildContext context,
    ThemeData theme,
    Credential item,
  ) {
    showDialog(
      context: context,
      builder: (dialogCtx) => _CredentialDetailDialog(
        item: item,
        onEdit: () {
          Navigator.pop(dialogCtx);
          widget.onEdit();
        },
        onCopy: (text, desc) => _copy(text, desc),
      ),
    );
  }

  bool _isAutoGeneratedTotpNote(String note) {
    return note.startsWith('由账号密码「') && note.contains('自动生成的双重验证码');
  }

  Widget _buildBody(BuildContext context, ThemeData theme, Credential item) {
    switch (item.type) {
      case CredentialType.passkey:
        return _buildPasskeyBody(context, theme, item);
      case CredentialType.totp:
        return _buildTotpBody(context, theme, item);
      case CredentialType.password:
        return _buildPasswordBody(context, theme, item);
      case CredentialType.serverKey:
        return _buildServerKeyBody(context, theme, item);
      case CredentialType.apiKey:
        return _buildApiKeyBody(context, theme, item);
      case CredentialType.cryptoWallet:
        return _buildCryptoWalletBody(context, theme, item);
      case CredentialType.card:
        return _buildCardBody(context, theme, item);
      case CredentialType.identity:
        return _buildIdentityBody(context, theme, item);
      case CredentialType.secureNote:
        return _buildSecureNoteBody(context, theme, item);
    }
  }

  // --- 通行密钥 (Passkey / FIDO2) 渲染 ---
  Widget _buildPasskeyBody(
    BuildContext context,
    ThemeData theme,
    Credential item,
  ) {
    final rpId = item.url.isNotEmpty
        ? item.url.replaceAll(RegExp(r'^https?:\/\/'), '').split('/').first
        : (item.serverHost.isNotEmpty ? item.serverHost : '未知依赖方');
    final account = item.account.isNotEmpty ? item.account : '默认用户';
    final credentialId = item.extraData['credential_id']?.toString() ?? '';
    final algorithm =
        item.extraData['passkey_algorithm']?.toString() ?? 'ES256';
    final userHandle = item.extraData['user_handle']?.toString() ?? '';
    final hasPrivateKey = item.privateKey.isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // FIDO2 状态栏与依赖方卡片
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: theme.colorScheme.primaryContainer.withValues(alpha: 0.25),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: theme.colorScheme.primary.withValues(alpha: 0.2),
            ),
          ),
          child: Row(
            children: [
              Icon(
                Icons.fingerprint_rounded,
                size: 20,
                color: theme.colorScheme.primary,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'FIDO2 / WebAuthn 标准无密码通行密钥',
                  style: theme.textTheme.labelMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: theme.colorScheme.primary,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.green.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.shield_outlined,
                      size: 12,
                      color: Colors.green,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      algorithm,
                      style: const TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        color: Colors.green,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        () {
          final labelWidth = _measureMaxLabelWidth(context, [
            '绑定网站',
            '用户账号',
            if (credentialId.isNotEmpty) '凭据 ID',
          ]);
          return Column(
            children: [
              _buildInfoRow(
                label: '绑定网站',
                value: rpId,
                labelWidth: labelWidth,
                onCopy: () => _copy(rpId, '通行密钥绑定域名'),
              ),
              _buildInfoRow(
                label: '用户账号',
                value: account,
                labelWidth: labelWidth,
                onCopy: () => _copy(account, '通行密钥用户名'),
              ),
              if (credentialId.isNotEmpty)
                _buildInfoRow(
                  label: '凭据 ID',
                  value: credentialId.length > 24
                      ? '${credentialId.substring(0, 12)}...${credentialId.substring(credentialId.length - 8)}'
                      : credentialId,
                  tooltipMessage: credentialId,
                  labelWidth: labelWidth,
                  onCopy: () => _copy(credentialId, '通行密钥凭据 ID'),
                ),
            ],
          );
        }(),
        const SizedBox(height: 8),
        Row(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: hasPrivateKey
                    ? Colors.green.withValues(alpha: 0.1)
                    : Colors.orange.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    hasPrivateKey
                        ? Icons.check_circle
                        : Icons.warning_amber_rounded,
                    size: 14,
                    color: hasPrivateKey ? Colors.green : Colors.orange,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    hasPrivateKey ? '私钥已在本地加密受保护' : '仅公钥凭据信息',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                      color: hasPrivateKey
                          ? Colors.green.shade800
                          : Colors.orange.shade800,
                    ),
                  ),
                ],
              ),
            ),
            const Spacer(),
            TextButton.icon(
              style: TextButton.styleFrom(
                visualDensity: VisualDensity.compact,
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              ),
              icon: const Icon(Icons.copy_all_outlined, size: 14),
              label: const Text('复制密钥摘要', style: TextStyle(fontSize: 12)),
              onPressed: () {
                final summary = {
                  'rpId': rpId,
                  'userName': account,
                  'credentialId': credentialId,
                  'algorithm': algorithm,
                  'userHandle': userHandle,
                  'hasPrivateKey': hasPrivateKey,
                };
                _copy(jsonEncode(summary), '通行密钥参数摘要');
              },
            ),
          ],
        ),
      ],
    );
  }

  // --- 1. TOTP 动态码渲染 ---
  Widget _buildTotpBody(
    BuildContext context,
    ThemeData theme,
    Credential item,
  ) {
    final currentCode = TotpEngine.generateCode(
      secret: item.secret,
      algorithm: item.algorithm,
      digits: item.digits,
      period: item.period,
    );

    // 格式化验证码，如 6 位为 123 456
    final formattedCode = item.digits == 6
        ? '${currentCode.substring(0, 3)} ${currentCode.substring(3)}'
        : currentCode;

    final density = ref.watch(appSettingsProvider).cardDensity;
    final isCompact = density == CardDensity.compact;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Material(
          color: Colors.transparent,
          child: Tooltip(
            message: '点击复制动态码: $formattedCode',
            waitDuration: const Duration(milliseconds: 250),
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: () => _copy(currentCode, 'TOTP 验证码'),
            child: Ink(
              padding: EdgeInsets.fromLTRB(
                isCompact ? 8 : 10,
                isCompact ? 6 : 10,
                8.5,
                isCompact ? 6 : 10,
              ),
              decoration: BoxDecoration(
                color: theme.colorScheme.primary.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: theme.colorScheme.primary.withValues(alpha: 0.16),
                  width: 1.0,
                ),
              ),
              child: Row(
                children: [
                  // 1. 辅助指示：小巧精致的倒计时圆环
                  TotpTimerRing(period: item.period, size: isCompact ? 18 : 20),
                  SizedBox(width: isCompact ? 8 : 10),

                  // 2. 绝对视觉核心：突出超大号粗体动态验证码
                  Expanded(
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Text(
                        formattedCode,
                        style: TextStyle(
                          fontSize: isCompact ? 20.0 : 23.0,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 1.5,
                          fontFeatures: const [FontFeature.tabularFigures()],
                          color: theme.colorScheme.primary,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 4),

                  // 3. 微型复制提示图标（点击整个容器均可复制）
                  Icon(
                    Icons.copy_rounded,
                    size: 15,
                    color: theme.colorScheme.primary.withValues(alpha: 0.65),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    ],
    );
  }

  // --- 2. 账号密码渲染（含可选内嵌 TOTP） ---
  Widget _buildPasswordBody(
    BuildContext context,
    ThemeData theme,
    Credential item,
  ) {
    final labelWidth = _measureMaxLabelWidth(context, [
      if (item.url.isNotEmpty) '登录网址',
      if (item.account.isNotEmpty) '用户名',
      if (item.password.isNotEmpty) '密码',
    ]);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (item.url.isNotEmpty)
          _buildInfoRow(
            label: '登录网址',
            value: item.url,
            labelWidth: labelWidth,
            onCopy: () => _copy(item.url, '登录网址'),
          ),
        if (item.account.isNotEmpty)
          _buildInfoRow(
            label: '用户名',
            value: item.account,
            labelWidth: labelWidth,
            onCopy: () => _copy(item.account, '用户名'),
          ),
        if (item.password.isNotEmpty)
          _buildInfoRow(
            label: '密码',
            value: _revealed ? item.password : '••••••••••••',
            labelWidth: labelWidth,
            isSensitive: true,
            onCopy: () => _copy(item.password, '密码'),
            trailingAction: IconButton(
              icon: Icon(
                _revealed
                    ? Icons.visibility_off_outlined
                    : Icons.visibility_outlined,
                size: 18,
              ),
              visualDensity: VisualDensity.compact,
              padding: const EdgeInsets.all(6),
              constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
              splashRadius: 16,
              tooltip: _revealed ? '隐藏密码' : '显示密码',
              onPressed: () => setState(() => _revealed = !_revealed),
            ),
          ),
        if (item.secret.isNotEmpty) ...[
          const Divider(height: 16),
          _buildTotpBody(context, theme, item),
        ],
      ],
    );
  }

  // --- 3. 服务器私钥渲染 ---
  Widget _buildServerKeyBody(
    BuildContext context,
    ThemeData theme,
    Credential item,
  ) {
    final sshCommand = SshHelper.formatSshCommand(
      host: item.serverHost,
      port: item.serverPort,
      user: item.serverUser,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (item.serverHost.isNotEmpty)
          _buildInfoRow(
            label: 'SSH 命令',
            value: sshCommand,
            onCopy: () => _copy(sshCommand, 'SSH 登录命令'),
          ),
        if (item.privateKey.isNotEmpty) ...[
          const SizedBox(height: 8),
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
              visualDensity: VisualDensity.compact,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            icon: const Icon(Icons.copy_rounded, size: 16),
            label: const Text('复制私钥明文'),
            onPressed: () => _copy(item.privateKey, 'SSH 私钥'),
          ),
        ],
      ],
    );
  }

  // --- 4. 开发者 API 密钥渲染 ---
  Widget _buildApiKeyBody(
    BuildContext context,
    ThemeData theme,
    Credential item,
  ) {
    final apiKey = item.extraData['api_key']?.toString() ?? '';
    final provider = item.extraData['service_provider']?.toString() ?? '';
    final labelWidth = _measureMaxLabelWidth(context, [
      if (provider.isNotEmpty) '服务商',
      if (apiKey.isNotEmpty) 'API Key',
    ]);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (provider.isNotEmpty)
          _buildInfoRow(
            label: '服务商',
            value: provider,
            labelWidth: labelWidth,
            onCopy: () => _copy(provider, '服务商'),
          ),
        if (apiKey.isNotEmpty)
          _buildInfoRow(
            label: 'API Key',
            value: _revealed ? apiKey : '••••••••••••••••••••••••',
            labelWidth: labelWidth,
            isSensitive: true,
            onCopy: () => _copy(apiKey, 'API Key'),
            trailingAction: IconButton(
              icon: Icon(
                _revealed
                    ? Icons.visibility_off_outlined
                    : Icons.visibility_outlined,
                size: 18,
              ),
              visualDensity: VisualDensity.compact,
              padding: const EdgeInsets.all(6),
              constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
              splashRadius: 16,
              tooltip: _revealed ? '隐藏密钥' : '显示密钥',
              onPressed: () => setState(() => _revealed = !_revealed),
            ),
          ),
      ],
    );
  }

  // --- 5. 加密钱包助记词渲染 ---
  Widget _buildCryptoWalletBody(
    BuildContext context,
    ThemeData theme,
    Credential item,
  ) {
    final seedWords =
        (item.extraData['seed_phrase'] as List?)
            ?.map((e) => e.toString())
            .toList() ??
        [];
    final address = item.extraData['wallet_address']?.toString() ?? '';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (address.isNotEmpty)
          _buildInfoRow(
            label: '钱包地址',
            value: address,
            onCopy: () => _copy(address, '钱包地址'),
          ),
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              '助记词 (${seedWords.length} 词)',
              style: theme.textTheme.labelMedium,
            ),
            TextButton.icon(
              style: TextButton.styleFrom(
                visualDensity: VisualDensity.compact,
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              ),
              icon: Icon(
                _revealed
                    ? Icons.visibility_off_outlined
                    : Icons.visibility_outlined,
                size: 16,
              ),
              label: Text(_revealed ? '遮挡助记词' : '显示助记词 (防窥)'),
              onPressed: () => setState(() => _revealed = !_revealed),
            ),
          ],
        ),
        if (_revealed && seedWords.isNotEmpty)
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: List.generate(seedWords.length, (idx) {
              return Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceVariant.withOpacity(0.6),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  '${idx + 1}. ${seedWords[idx]}',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              );
            }),
          )
        else
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceVariant.withOpacity(0.3),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Center(
              child: Text('助记词已遮蔽保护，点击右上角显隐查看', style: TextStyle(fontSize: 12)),
            ),
          ),
      ],
    );
  }

  // --- 6. 银行卡渲染 ---
  Widget _buildCardBody(
    BuildContext context,
    ThemeData theme,
    Credential item,
  ) {
    final cardNumber = item.extraData['card_number']?.toString() ?? '';
    final holder = item.extraData['cardholder_name']?.toString() ?? '';
    final cvv = item.extraData['cvv']?.toString() ?? '';
    final expiry = item.extraData['expiry_date']?.toString() ?? '';

    final labelWidth = _measureMaxLabelWidth(context, [
      if (cardNumber.isNotEmpty) '卡号',
      if (holder.isNotEmpty) '持卡人',
      if (expiry.isNotEmpty) '有效期',
      if (cvv.isNotEmpty) '安全码',
    ]);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (cardNumber.isNotEmpty)
          _buildInfoRow(
            label: '卡号',
            value: cardNumber,
            labelWidth: labelWidth,
            onCopy: () => _copy(cardNumber.replaceAll(' ', ''), '银行卡号'),
          ),
        if (holder.isNotEmpty)
          _buildInfoRow(
            label: '持卡人',
            value: holder,
            labelWidth: labelWidth,
            onCopy: () => _copy(holder, '持卡人姓名'),
          ),
        if (expiry.isNotEmpty)
          _buildInfoRow(
            label: '有效期',
            value: expiry,
            labelWidth: labelWidth,
            onCopy: () => _copy(expiry, '有效期'),
          ),
        if (cvv.isNotEmpty)
          _buildInfoRow(
            label: '安全码',
            value: _revealed ? cvv : '•••',
            labelWidth: labelWidth,
            isSensitive: true,
            onCopy: () => _copy(cvv, '安全码 (CVV)'),
            trailingAction: IconButton(
              icon: Icon(
                _revealed
                    ? Icons.visibility_off_outlined
                    : Icons.visibility_outlined,
                size: 18,
              ),
              visualDensity: VisualDensity.compact,
              padding: const EdgeInsets.all(6),
              constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
              splashRadius: 16,
              tooltip: _revealed ? '隐藏安全码' : '显示安全码',
              onPressed: () => setState(() => _revealed = !_revealed),
            ),
          ),
      ],
    );
  }

  // --- 7. 身份档案渲染 ---
  Widget _buildIdentityBody(
    BuildContext context,
    ThemeData theme,
    Credential item,
  ) {
    final idNum = item.extraData['id_number']?.toString() ?? '';
    final name = item.extraData['full_name']?.toString() ?? '';
    final docType = item.extraData['doc_type']?.toString() ?? '证件号码';
    final labelWidth = _measureMaxLabelWidth(context, [
      if (name.isNotEmpty) '姓名',
      if (idNum.isNotEmpty) docType,
    ]);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (name.isNotEmpty)
          _buildInfoRow(
            label: '姓名',
            value: name,
            labelWidth: labelWidth,
          ),
        if (idNum.isNotEmpty)
          _buildInfoRow(
            label: docType,
            value: _revealed ? idNum : '••••••••••••••••',
            labelWidth: labelWidth,
            isSensitive: true,
            onCopy: () => _copy(idNum, docType),
            trailingAction: IconButton(
              icon: Icon(
                _revealed
                    ? Icons.visibility_off_outlined
                    : Icons.visibility_outlined,
                size: 18,
              ),
              visualDensity: VisualDensity.compact,
              padding: const EdgeInsets.all(6),
              constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
              splashRadius: 16,
              tooltip: _revealed ? '隐藏证件号' : '显示证件号',
              onPressed: () => setState(() => _revealed = !_revealed),
            ),
          ),
      ],
    );
  }

  // --- 8. 安全备忘录自定义字段渲染 ---
  Widget _buildSecureNoteBody(
    BuildContext context,
    ThemeData theme,
    Credential item,
  ) {
    final customFields = (item.extraData['custom_fields'] as List?) ?? [];
    if (customFields.isEmpty) {
      return const SizedBox.shrink();
    }

    final labelWidth = _measureMaxLabelWidth(
      context,
      customFields.map((f) => f['label']?.toString() ?? '属性'),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: customFields.map((field) {
        final label = field['label']?.toString() ?? '属性';
        final val = field['value']?.toString() ?? '';
        final isMasked = field['masked'] == true;

        return _buildInfoRow(
          label: label,
          value: (isMasked && !_revealed) ? '••••••••' : val,
          labelWidth: labelWidth,
          isSensitive: isMasked,
          onCopy: () => _copy(val, label),
          trailingAction: isMasked
              ? IconButton(
                  icon: Icon(
                    _revealed
                        ? Icons.visibility_off_outlined
                        : Icons.visibility_outlined,
                    size: 18,
                  ),
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.all(6),
                  constraints:
                      const BoxConstraints(minWidth: 32, minHeight: 32),
                  splashRadius: 16,
                  tooltip: _revealed ? '隐藏' : '显示',
                  onPressed: () => setState(() => _revealed = !_revealed),
                )
              : null,
        );
      }).toList(),
    );
  }

  // --- 2FA 应急恢复码独立管理弹窗 ---
  void _showRecoveryCodesDialog(BuildContext context, Credential item) {
    showDialog(
      context: context,
      builder: (ctx) {
        return Consumer(
          builder: (context, ref, _) {
            final vault = ref.watch(vaultProvider);
            final currentItem = (vault.value ?? []).firstWhere(
              (c) => c.id == item.id,
              orElse: () => item,
            );
            final codes = currentItem.recoveryCodes;
            final availableCount = codes.where((c) => !c.used).length;
            final theme = Theme.of(context);

            return AlertDialog(
              title: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.primaryContainer.withValues(
                        alpha: 0.6,
                      ),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(
                      Icons.key_rounded,
                      size: 20,
                      color: theme.colorScheme.primary,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '2FA 应急备用恢复码',
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          '$availableCount/${codes.length} 个可用 · 点击复制，勾选标记已用',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              content: SizedBox(
                width: 420,
                child: codes.isEmpty
                    ? const Padding(
                        padding: EdgeInsets.symmetric(vertical: 24),
                        child: Center(child: Text('暂无备用恢复码')),
                      )
                    : Container(
                        constraints: const BoxConstraints(maxHeight: 360),
                        child: ListView.separated(
                          shrinkWrap: true,
                          itemCount: codes.length,
                          separatorBuilder: (_, __) => const Divider(height: 8),
                          itemBuilder: (context, idx) {
                            final rc = codes[idx];
                            return InkWell(
                              borderRadius: BorderRadius.circular(8),
                              onTap: () => _copy(rc.code, '应急恢复码'),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 4,
                                  horizontal: 4,
                                ),
                                child: Row(
                                  children: [
                                    Checkbox(
                                      value: rc.used,
                                      onChanged: (_) {
                                        ref
                                            .read(vaultProvider.notifier)
                                            .toggleRecoveryCodeUsed(
                                              currentItem.id,
                                              idx,
                                            );
                                      },
                                    ),
                                    Expanded(
                                      child: Text(
                                        rc.code,
                                        style: TextStyle(
                                          fontSize: 13,
                                          fontFamily: 'monospace',
                                          fontWeight: FontWeight.w500,
                                          decoration: rc.used
                                              ? TextDecoration.lineThrough
                                              : null,
                                          color: rc.used
                                              ? theme.colorScheme.outline
                                              : theme.colorScheme.onSurface,
                                        ),
                                      ),
                                    ),
                                    IconButton(
                                      icon: const Icon(
                                        Icons.copy_rounded,
                                        size: 16,
                                      ),
                                      tooltip: '复制',
                                      onPressed: () => _copy(rc.code, '应急恢复码'),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                      ),
              ),
              actions: [
                if (availableCount > 1)
                  TextButton.icon(
                    icon: const Icon(Icons.copy_all_rounded, size: 16),
                    label: const Text('复制所有未用码'),
                    onPressed: () {
                      final unused = codes
                          .where((c) => !c.used)
                          .map((c) => c.code)
                          .join('\n');
                      _copy(unused, '所有未用恢复码');
                    },
                  ),
                FilledButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('完成'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  /// 动态测量标签的实际文字宽度并附带舒适呼吸间距（默认 10px）
  double _measureLabelWidth(
    BuildContext context,
    String text, [
    double spacing = 10.0,
  ]) {
    final theme = Theme.of(context);
    final style = theme.textTheme.bodySmall?.copyWith(
      fontWeight: FontWeight.w500,
      fontSize: 11.5,
    ) ?? const TextStyle(fontWeight: FontWeight.w500, fontSize: 11.5);

    final painter = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: Directionality.of(context),
    )..layout();

    return painter.width + spacing;
  }

  /// 动态测量当前卡片内所有标签的最大宽度并统一加呼吸间距，保证卡片内对齐且间距恒定舒适
  double _measureMaxLabelWidth(
    BuildContext context,
    Iterable<String> labels, [
    double spacing = 10.0,
  ]) {
    double max = 0;
    for (final l in labels) {
      if (l.trim().isNotEmpty) {
        final w = _measureLabelWidth(context, l, 0);
        if (w > max) max = w;
      }
    }
    return max > 0 ? (max + spacing) : (36.0 + spacing);
  }

  Widget _buildInfoRow({
    required String label,
    required String value,
    String? tooltipMessage,
    VoidCallback? onCopy,
    Widget? trailingAction,
    double? labelWidth,
    bool isSensitive = false,
  }) {
    final theme = Theme.of(context);

    return LayoutBuilder(
      builder: (context, constraints) {
        final availableWidth = constraints.maxWidth;
        final rawWidth = labelWidth ?? _measureLabelWidth(context, label);

        // 如果处于超窄卡片（如小屏双列模式），动态限制标签宽度，确保内容和按钮不发生横向溢出
        double effectiveLabelWidth = rawWidth;
        if (availableWidth.isFinite && availableWidth > 0) {
          final reservedActions =
              (trailingAction != null ? 36.0 : 0.0) +
              (onCopy != null ? 32.0 : 0.0);
          final safeMaxLabelWidth = availableWidth - reservedActions - 24.0;
          if (safeMaxLabelWidth > 0 && rawWidth > safeMaxLabelWidth) {
            effectiveLabelWidth = safeMaxLabelWidth.clamp(20.0, rawWidth);
          }
        }

        final isCompact =
            ref.watch(appSettingsProvider).cardDensity == CardDensity.compact;
        final verticalPadding = isCompact ? 4.0 : 6.0;

        // 非密码/非敏感控件且值非遮罩时，在桌面端支持悬停气泡显示完整内容
        final shouldShowTooltip = !isSensitive &&
            !value.startsWith('••••') &&
            value.trim().isNotEmpty;
        final displayTooltip = tooltipMessage ?? value;

        Widget contentWidget = InkWell(
          onTap: onCopy,
          borderRadius: BorderRadius.circular(4),
          child: Text(
            value,
            style: theme.textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w500,
              fontFamily: value.startsWith('••••') ? null : 'monospace',
            ),
            maxLines: 1,
            softWrap: false,
            overflow: TextOverflow.clip,
          ),
        );

        if (shouldShowTooltip) {
          contentWidget = Tooltip(
            message: displayTooltip,
            waitDuration: const Duration(milliseconds: 250),
            child: contentWidget,
          );
        }

        return Padding(
          padding: EdgeInsets.symmetric(
            horizontal: 4,
            vertical: verticalPadding,
          ),
          child: Row(
            children: [
              SizedBox(
                width: effectiveLabelWidth,
                child: Text(
                  label,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.w500,
                    fontSize: 11.5,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Expanded(
                child: contentWidget,
              ),
              if (trailingAction != null) trailingAction,
              if (onCopy != null)
                IconButton(
                  icon: const Icon(Icons.copy_rounded, size: 16),
                  tooltip: '点击复制',
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.all(6),
                  constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                  splashRadius: 16,
                  onPressed: onCopy,
                ),
            ],
          ),
        );
      },
    );
  }
}

/// 支持文本超长时自动平滑慢速往返跑马灯滚动与手势触摸滚动的文本组件
class AutoScrollText extends StatefulWidget {
  final String text;
  final TextStyle? style;
  final double velocity;
  final Duration pauseDuration;

  const AutoScrollText({
    super.key,
    required this.text,
    this.style,
    this.velocity = 13.0,
    this.pauseDuration = const Duration(milliseconds: 2200),
  });

  @override
  State<AutoScrollText> createState() => _AutoScrollTextState();
}

class _AutoScrollTextState extends State<AutoScrollText> {
  final ScrollController _scrollController = ScrollController();
  bool _isRunning = false;
  bool _isPausedByUser = false;
  bool _disposed = false;
  double _lastAvailableWidth = -1.0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _ensureLoopRunning();
    });
  }

  @override
  void didUpdateWidget(AutoScrollText oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.text != widget.text) {
      if (_scrollController.hasClients) {
        _scrollController.jumpTo(0.0);
      }
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _ensureLoopRunning();
      });
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _isRunning = false;
    _scrollController.dispose();
    super.dispose();
  }

  void _onLayoutChanged(double width) {
    if ((width - _lastAvailableWidth).abs() > 0.5) {
      _lastAvailableWidth = width;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && !_disposed) {
          _ensureLoopRunning();
        }
      });
    }
  }

  void _ensureLoopRunning() {
    if (!_isRunning && !_disposed && mounted) {
      _startLoop();
    }
  }

  void _pauseAndResumeLater() {
    _isPausedByUser = true;
    Future.delayed(const Duration(seconds: 3), () {
      if (!_disposed && mounted) {
        _isPausedByUser = false;
        _ensureLoopRunning();
      }
    });
  }

  Future<void> _startLoop() async {
    if (_isRunning || _disposed) return;
    _isRunning = true;

    while (!_disposed && mounted && _isRunning) {
      if (_isPausedByUser) {
        await Future.delayed(const Duration(milliseconds: 500));
        continue;
      }

      if (!_scrollController.hasClients) {
        await Future.delayed(const Duration(milliseconds: 200));
        continue;
      }

      final maxScroll = _scrollController.position.maxScrollExtent;
      // 文本没有超长时，重置至起点并定期检测（应对窗口变窄场景）
      if (maxScroll <= 1.0) {
        if (_scrollController.position.pixels > 0) {
          _scrollController.jumpTo(0.0);
        }
        await Future.delayed(const Duration(milliseconds: 600));
        continue;
      }

      // 起始位置停留，让用户清晰阅读文本开端
      await Future.delayed(widget.pauseDuration);
      if (_disposed || !mounted || !_isRunning || _isPausedByUser) continue;
      if (!_scrollController.hasClients) continue;

      final currentMax = _scrollController.position.maxScrollExtent;
      if (currentMax <= 1.0) continue;

      // 1. 向末尾从容优雅慢速滚动
      final distanceToEnd = (currentMax - _scrollController.position.pixels)
          .abs();
      final durationToEnd = (distanceToEnd / widget.velocity * 1000)
          .toInt()
          .clamp(800, 16000);
      try {
        await _scrollController.animateTo(
          currentMax,
          duration: Duration(milliseconds: durationToEnd),
          curve: Curves.easeInOutSine,
        );
      } catch (_) {
        // 捕获拉伸窗口或打断异常，自愈重试
        await Future.delayed(const Duration(milliseconds: 250));
        continue;
      }

      // 末端位置停留，让用户清晰阅读末尾字符
      await Future.delayed(widget.pauseDuration);
      if (_disposed || !mounted || !_isRunning || _isPausedByUser) continue;
      if (!_scrollController.hasClients) continue;

      // 2. 向起点平滑返回
      final distanceToStart = _scrollController.position.pixels;
      final durationToStart = (distanceToStart / widget.velocity * 1000)
          .toInt()
          .clamp(800, 16000);
      try {
        await _scrollController.animateTo(
          0.0,
          duration: Duration(milliseconds: durationToStart),
          curve: Curves.easeInOutSine,
        );
      } catch (_) {
        await Future.delayed(const Duration(milliseconds: 250));
        continue;
      }
    }

    _isRunning = false;
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        _onLayoutChanged(constraints.maxWidth);
        return NotificationListener<ScrollNotification>(
          onNotification: (notification) {
            if (notification is UserScrollNotification) {
              _pauseAndResumeLater();
            }
            return false;
          },
          child: SingleChildScrollView(
            controller: _scrollController,
            scrollDirection: Axis.horizontal,
            physics: const BouncingScrollPhysics(),
            child: Text(
              widget.text,
              style: widget.style,
              maxLines: 1,
              softWrap: false,
            ),
          ),
        );
      },
    );
  }
}

/// 凭据完整详情大卡片弹窗，支持全量字段展示、复制与交互
class _CredentialDetailDialog extends ConsumerStatefulWidget {
  final Credential item;
  final VoidCallback onEdit;
  final void Function(String text, String desc) onCopy;

  const _CredentialDetailDialog({
    required this.item,
    required this.onEdit,
    required this.onCopy,
  });

  @override
  ConsumerState<_CredentialDetailDialog> createState() =>
      _CredentialDetailDialogState();
}

class _CredentialDetailDialogState
    extends ConsumerState<_CredentialDetailDialog> {
  bool _revealedPassword = false;
  bool _revealedCvv = false;
  bool _revealedKey = false;

  String _formatTime(int ms) {
    if (ms <= 0) return '未知';
    final dt = DateTime.fromMillisecondsSinceEpoch(ms);
    return DateFormat('yyyy-MM-dd HH:mm:ss').format(dt);
  }

  Widget _buildFieldCard({
    required BuildContext context,
    required ThemeData theme,
    required String label,
    required String value,
    String? copyValue,
    String? subtitle,
    Widget? trailing,
    bool isMonospace = false,
  }) {
    if (value.isEmpty) return const SizedBox.shrink();

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.3),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                label,
                style: theme.textTheme.labelMedium?.copyWith(
                  color: theme.colorScheme.primary,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const Spacer(),
              if (trailing != null) trailing,
              IconButton(
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                icon: const Icon(Icons.copy_rounded, size: 16),
                tooltip: '复制$label',
                onPressed: () => widget.onCopy(copyValue ?? value, label),
              ),
            ],
          ),
          const SizedBox(height: 4),
          SelectableText(
            value,
            style: theme.textTheme.bodyMedium?.copyWith(
              fontFamily: isMonospace ? 'monospace' : null,
              fontWeight: FontWeight.w500,
            ),
          ),
          if (subtitle != null && subtitle.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              subtitle,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.outline,
                fontSize: 11,
              ),
            ),
          ],
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    final theme = Theme.of(context);
    final size = MediaQuery.of(context).size;

    // 若含 TOTP 则监听刷新
    if (item.type == CredentialType.totp || item.secret.isNotEmpty) {
      ref.watch(totpTickerProvider);
    }

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      clipBehavior: Clip.antiAlias,
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 540,
          maxHeight: size.height * 0.85,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 头部大卡片标题区
            Container(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 16),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest.withValues(
                  alpha: 0.5,
                ),
                border: Border(
                  bottom: BorderSide(
                    color: theme.colorScheme.outlineVariant.withValues(
                      alpha: 0.3,
                    ),
                  ),
                ),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.primaryContainer,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      item.type.icon,
                      size: 24,
                      color: theme.colorScheme.onPrimaryContainer,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: SelectableText(
                                item.title,
                                style: theme.textTheme.titleLarge?.copyWith(
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                            if (item.pinned)
                              Padding(
                                padding: const EdgeInsets.only(left: 6),
                                child: Icon(
                                  Icons.push_pin,
                                  size: 16,
                                  color: theme.colorScheme.primary,
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Wrap(
                          spacing: 6,
                          runSpacing: 4,
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: theme.colorScheme.primary.withValues(
                                  alpha: 0.12,
                                ),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                item.type.label,
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  color: theme.colorScheme.primary,
                                ),
                              ),
                            ),
                            for (final tag in item.tags)
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: theme.colorScheme.surfaceContainerHighest
                                      .withValues(alpha: 0.6),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  '#$tag',
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: theme.colorScheme.onSurfaceVariant,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            // 主体可滚动信息列表
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // 1. 登录网址
                    if (item.url.isNotEmpty)
                      _buildFieldCard(
                        context: context,
                        theme: theme,
                        label: '登录网址',
                        value: item.url,
                        subtitle:
                            '匹配规则：${item.urlMatchType.label} (${item.urlMatchType.description})',
                      ),

                    // 2. 用户名 / 账号
                    if (item.account.isNotEmpty)
                      _buildFieldCard(
                        context: context,
                        theme: theme,
                        label: item.type == CredentialType.passkey
                            ? '用户账号'
                            : '用户名 / 账号',
                        value: item.account,
                      ),

                    // 3. 密码
                    if (item.password.isNotEmpty)
                      _buildFieldCard(
                        context: context,
                        theme: theme,
                        label: '登录密码',
                        value: _revealedPassword
                            ? item.password
                            : '••••••••••••••••',
                        copyValue: item.password,
                        trailing: IconButton(
                          visualDensity: VisualDensity.compact,
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(
                            minWidth: 28,
                            minHeight: 28,
                          ),
                          icon: Icon(
                            _revealedPassword
                                ? Icons.visibility_off_outlined
                                : Icons.visibility_outlined,
                            size: 17,
                          ),
                          tooltip: _revealedPassword ? '隐藏密码' : '显示明文',
                          onPressed: () => setState(
                            () => _revealedPassword = !_revealedPassword,
                          ),
                        ),
                      ),

                    // 4. TOTP 动态码
                    if (item.secret.isNotEmpty) ...[
                      () {
                        final currentCode = TotpEngine.generateCode(
                          secret: item.secret,
                          algorithm: item.algorithm,
                          digits: item.digits,
                          period: item.period,
                        );
                        final formattedCode = item.digits == 6
                            ? '${currentCode.substring(0, 3)} ${currentCode.substring(3)}'
                            : currentCode;

                        return Container(
                          margin: const EdgeInsets.only(bottom: 12),
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: theme.colorScheme.primary.withValues(
                              alpha: 0.08,
                            ),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: theme.colorScheme.primary.withValues(
                                alpha: 0.2,
                              ),
                            ),
                          ),
                          child: Row(
                            children: [
                              TotpTimerRing(period: item.period, size: 28),
                              const SizedBox(width: 14),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'TOTP 双重验证动态码',
                                      style: TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.bold,
                                        color: theme.colorScheme.primary,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      formattedCode,
                                      style: theme.textTheme.headlineSmall
                                          ?.copyWith(
                                            fontWeight: FontWeight.bold,
                                            letterSpacing: 2.0,
                                            fontFamily: 'monospace',
                                            color: theme.colorScheme.primary,
                                          ),
                                    ),
                                  ],
                                ),
                              ),
                              FilledButton.tonalIcon(
                                icon: const Icon(Icons.copy_rounded, size: 16),
                                label: const Text('复制'),
                                onPressed: () =>
                                    widget.onCopy(currentCode, 'TOTP 验证码'),
                              ),
                            ],
                          ),
                        );
                      }(),
                    ],

                    // 5. 银行卡信息
                    if (item.type == CredentialType.card) ...[
                      if (item.extraData['card_number'] != null)
                        _buildFieldCard(
                          context: context,
                          theme: theme,
                          label: '银行卡号',
                          value: item.extraData['card_number'].toString(),
                          copyValue: item.extraData['card_number']
                              .toString()
                              .replaceAll(' ', ''),
                          isMonospace: true,
                        ),
                      if (item.extraData['cardholder_name'] != null)
                        _buildFieldCard(
                          context: context,
                          theme: theme,
                          label: '持卡人姓名',
                          value: item.extraData['cardholder_name'].toString(),
                        ),
                      if (item.extraData['expiry_date'] != null)
                        _buildFieldCard(
                          context: context,
                          theme: theme,
                          label: '卡片有效期',
                          value: item.extraData['expiry_date'].toString(),
                          isMonospace: true,
                        ),
                      if (item.extraData['cvv'] != null)
                        _buildFieldCard(
                          context: context,
                          theme: theme,
                          label: '安全码 (CVV)',
                          value: _revealedCvv
                              ? item.extraData['cvv'].toString()
                              : '•••',
                          copyValue: item.extraData['cvv'].toString(),
                          trailing: IconButton(
                            visualDensity: VisualDensity.compact,
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(
                              minWidth: 28,
                              minHeight: 28,
                            ),
                            icon: Icon(
                              _revealedCvv
                                  ? Icons.visibility_off_outlined
                                  : Icons.visibility_outlined,
                              size: 17,
                            ),
                            tooltip: _revealedCvv ? '隐藏' : '显示',
                            onPressed: () => setState(
                              () => _revealedCvv = !_revealedCvv,
                            ),
                          ),
                          isMonospace: true,
                        ),
                    ],

                    // 6. 身份档案
                    if (item.type == CredentialType.identity) ...[
                      if (item.extraData['full_name'] != null)
                        _buildFieldCard(
                          context: context,
                          theme: theme,
                          label: '姓名',
                          value: item.extraData['full_name'].toString(),
                        ),
                      if (item.extraData['id_number'] != null)
                        _buildFieldCard(
                          context: context,
                          theme: theme,
                          label: item.extraData['doc_type']?.toString() ??
                              '证件号码',
                          value: item.extraData['id_number'].toString(),
                          isMonospace: true,
                        ),
                    ],

                    // 7. 服务器私钥
                    if (item.type == CredentialType.serverKey) ...[
                      if (item.serverHost.isNotEmpty)
                        _buildFieldCard(
                          context: context,
                          theme: theme,
                          label: 'SSH 快速登录命令',
                          value: SshHelper.formatSshCommand(
                            host: item.serverHost,
                            port: item.serverPort,
                            user: item.serverUser,
                          ),
                          isMonospace: true,
                        ),
                      if (item.privateKey.isNotEmpty)
                        _buildFieldCard(
                          context: context,
                          theme: theme,
                          label: 'SSH 私钥内容',
                          value: _revealedKey
                              ? item.privateKey
                              : '-----BEGIN OPENSSH PRIVATE KEY-----\n••••••••••••••••\n-----END OPENSSH PRIVATE KEY-----',
                          copyValue: item.privateKey,
                          trailing: IconButton(
                            visualDensity: VisualDensity.compact,
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(
                              minWidth: 28,
                              minHeight: 28,
                            ),
                            icon: Icon(
                              _revealedKey
                                  ? Icons.visibility_off_outlined
                                  : Icons.visibility_outlined,
                              size: 17,
                            ),
                            tooltip: _revealedKey ? '隐藏' : '显示',
                            onPressed: () => setState(
                              () => _revealedKey = !_revealedKey,
                            ),
                          ),
                          isMonospace: true,
                        ),
                    ],

                    // 8. API Key
                    if (item.type == CredentialType.apiKey) ...[
                      if (item.extraData['api_key'] != null)
                        _buildFieldCard(
                          context: context,
                          theme: theme,
                          label: 'API Key',
                          value: item.extraData['api_key'].toString(),
                          isMonospace: true,
                        ),
                      if (item.extraData['service_provider'] != null)
                        _buildFieldCard(
                          context: context,
                          theme: theme,
                          label: '服务提供商',
                          value: item.extraData['service_provider'].toString(),
                        ),
                    ],

                    // 9. 通行密钥 Passkey
                    if (item.type == CredentialType.passkey) ...[
                      if (item.extraData['rp_id'] != null)
                        _buildFieldCard(
                          context: context,
                          theme: theme,
                          label: '依赖方标识 (RP ID)',
                          value: item.extraData['rp_id'].toString(),
                        ),
                      if (item.extraData['credential_id'] != null)
                        _buildFieldCard(
                          context: context,
                          theme: theme,
                          label: '凭据标识 (Credential ID)',
                          value: item.extraData['credential_id'].toString(),
                          isMonospace: true,
                        ),
                    ],

                    // 10. 备注
                    if (item.notes.isNotEmpty)
                      _buildFieldCard(
                        context: context,
                        theme: theme,
                        label: '备注信息',
                        value: item.notes,
                      ),

                    // 11. 元数据时间信息
                    Padding(
                      padding: const EdgeInsets.only(top: 8, bottom: 4),
                      child: LayoutBuilder(
                        builder: (context, constraints) {
                          final isNarrow = constraints.maxWidth < 380;
                          final style = theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.outline,
                            fontSize: 11,
                          );
                          final createdWidget = Text(
                            '创建于: ${_formatTime(item.createdAt)}',
                            style: style,
                          );
                          final updatedWidget = Text(
                            '更新于: ${_formatTime(item.updatedAt)}',
                            style: style,
                          );

                          if (isNarrow) {
                            return Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                createdWidget,
                                const SizedBox(height: 3),
                                updatedWidget,
                              ],
                            );
                          }

                          return Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              createdWidget,
                              updatedWidget,
                            ],
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // 底部操作按钮
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 12,
              ),
              decoration: BoxDecoration(
                border: Border(
                  top: BorderSide(
                    color: theme.colorScheme.outlineVariant.withValues(
                      alpha: 0.3,
                    ),
                  ),
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('关闭'),
                  ),
                  const SizedBox(width: 8),
                  FilledButton.icon(
                    onPressed: widget.onEdit,
                    icon: const Icon(Icons.edit_rounded, size: 16),
                    label: const Text('编辑此凭据'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

