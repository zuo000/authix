import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import '../../core/totp/totp_engine.dart';
import '../../models/credential.dart';
import 'edit_credential_screen.dart';

/// 专用于 TOTP 动态口令的二维码扫描器界面
class QRScannerScreen extends StatefulWidget {
  final bool returnRawContent;
  final String? title;
  final String? prompt;

  const QRScannerScreen({
    super.key,
    this.returnRawContent = false,
    this.title,
    this.prompt,
  });

  @override
  State<QRScannerScreen> createState() => _QRScannerScreenState();
}

class _QRScannerScreenState extends State<QRScannerScreen> {
  final MobileScannerController _controller = MobileScannerController(
    detectionSpeed: DetectionSpeed.noDuplicates,
    facing: CameraFacing.back,
    torchEnabled: false,
  );

  bool _isProcessing = false;
  bool _hasCameraError = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) {
    if (_isProcessing) return;
    for (final barcode in capture.barcodes) {
      final code = barcode.rawValue;
      if (code != null && code.trim().isNotEmpty) {
        _handleQrContent(code.trim());
        break;
      }
    }
  }

  void _handleQrContent(String rawContent) {
    if (_isProcessing) return;
    setState(() => _isProcessing = true);

    if (widget.returnRawContent) {
      if (mounted) {
        Navigator.pop(context, rawContent);
      }
      return;
    }

    // 1. 尝试解析标准 otpauth:// 协议
    final uriData = TotpEngine.parseUri(rawContent);

    if (uriData != null) {
      final issuerStr = uriData.issuer ?? '';
      final accountStr = uriData.account ?? '';
      final titleStr = issuerStr.isNotEmpty ? issuerStr : (accountStr.isNotEmpty ? accountStr : 'TOTP 动态码');

      final newCred = Credential.create(
        type: CredentialType.totp,
        title: titleStr,
        account: accountStr,
        issuer: issuerStr,
        secret: uriData.secret,
        algorithm: uriData.algorithm,
        digits: uriData.digits,
        period: uriData.period,
      );

      if (mounted) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (_) => EditCredentialScreen(initialItem: newCred),
          ),
        );
      }
    } else {
      // 2. 纯密钥或其它文本格式智能容错
      final cleanedKey = rawContent.replaceAll(RegExp(r'\s+'), '').toUpperCase();
      final newCred = Credential.create(
        type: CredentialType.totp,
        title: '新 TOTP 凭据',
        secret: cleanedKey,
      );

      if (mounted) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (_) => EditCredentialScreen(initialItem: newCred),
          ),
        );
      }
    }
  }

  Future<void> _pickImageAndScan() async {
    try {
      final pickerTitle = widget.title != null
          ? '选取包含${widget.title}的图片'
          : (widget.returnRawContent ? '选取包含二维码的图片' : '选取包含 TOTP 二维码的图片');
      final files = await FilePickerPlatform.instance.pickFiles(
        dialogTitle: pickerTitle,
        type: FileType.image,
      );

      if (files.isEmpty) return;

      final path = files.first.path;
      if (path == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('未能读取图片路径，请使用摄像头实时扫描或手动录入')),
          );
        }
        return;
      }

      setState(() => _isProcessing = true);
      final barcodeCapture = await _controller.analyzeImage(path);

      if (barcodeCapture != null && barcodeCapture.barcodes.isNotEmpty) {
        final code = barcodeCapture.barcodes.first.rawValue;
        if (code != null && code.isNotEmpty) {
          _handleQrContent(code);
          return;
        }
      }

      if (mounted) {
        setState(() => _isProcessing = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('所选图片中未识别到有效二维码，请确认清晰度或手动录入')),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isProcessing = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('图片解析失败: $e')),
        );
      }
    }
  }

  void _goToManualInput() {
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => EditCredentialScreen(
          initialItem: Credential.create(type: CredentialType.totp, title: ''),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final appBarTitle = widget.title ??
        (widget.returnRawContent ? '扫描二维码' : '扫描 TOTP 动态码');

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        foregroundColor: Colors.white,
        title: Text(appBarTitle),
        actions: [
          if (!widget.returnRawContent) ...[
            TextButton.icon(
              onPressed: _goToManualInput,
              icon: const Icon(Icons.edit_note_rounded, color: Colors.white),
              label: const Text('手动录入', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            ),
            const SizedBox(width: 8),
          ],
        ],
      ),
      body: Stack(
        children: [
          // 摄像头视图或无摄像头错误提示
          if (!_hasCameraError)
            MobileScanner(
              controller: _controller,
              onDetect: _onDetect,
              errorBuilder: (ctx, err) {
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (mounted && !_hasCameraError) {
                    setState(() => _hasCameraError = true);
                  }
                });
                return _buildNoCameraView(theme);
              },
            )
          else
            _buildNoCameraView(theme),

          // 扫码指示框遮罩
          if (!_hasCameraError) _buildScanOverlay(theme),

          // 正在解析中 Loading
          if (_isProcessing)
            Container(
              color: Colors.black54,
              child: const Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircularProgressIndicator(color: Colors.cyanAccent),
                    SizedBox(height: 16),
                    Text('正在解析二维码...', style: TextStyle(color: Colors.white, fontSize: 16)),
                  ],
                ),
              ),
            ),

          // 底部控制工具栏 (闪光灯 / 相册图片识别 / 切换镜头)
          Positioned(
            left: 0,
            right: 0,
            bottom: 40,
            child: _buildBottomActions(theme),
          ),
        ],
      ),
    );
  }

  Widget _buildScanOverlay(ThemeData theme) {
    final size = MediaQuery.of(context).size;
    final scanSize = size.width * 0.72 > 300 ? 300.0 : size.width * 0.72;

    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: scanSize,
            height: scanSize,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: Colors.cyanAccent.withValues(alpha: 0.8), width: 2.5),
              boxShadow: [
                BoxShadow(
                  color: Colors.cyanAccent.withValues(alpha: 0.2),
                  blurRadius: 20,
                  spreadRadius: 2,
                ),
              ],
            ),
            child: Stack(
              children: [
                // 四角加粗点缀
                _buildCorner(Alignment.topLeft),
                _buildCorner(Alignment.topRight),
                _buildCorner(Alignment.bottomLeft),
                _buildCorner(Alignment.bottomRight),
              ],
            ),
          ),
          const SizedBox(height: 24),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.6),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              widget.prompt ??
                  (widget.returnRawContent
                      ? '将二维码置于框内即可自动识别'
                      : '将双因子认证二维码置于框内即可自动识别'),
              style: const TextStyle(color: Colors.white70, fontSize: 14),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCorner(Alignment alignment) {
    return Align(
      alignment: alignment,
      child: Container(
        width: 24,
        height: 24,
        margin: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: Colors.cyanAccent,
          borderRadius: BorderRadius.circular(4),
        ),
      ),
    );
  }

  Widget _buildNoCameraView(ThemeData theme) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.white10,
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.videocam_off_outlined, color: Colors.white70, size: 56),
            ),
            const SizedBox(height: 20),
            const Text(
              '未能启动摄像头预览',
              style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 10),
            const Text(
              '请检查设备是否连接摄像头或已授权相机权限。\n您也可以直接选择截图图片识别或手动录入。',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white60, height: 1.4),
            ),
            const SizedBox(height: 28),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              alignment: WrapAlignment.center,
              children: [
                FilledButton.icon(
                  onPressed: _pickImageAndScan,
                  icon: const Icon(Icons.image_outlined),
                  label: const Text('从图片/截图识别'),
                ),
                if (!widget.returnRawContent)
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.white,
                      side: const BorderSide(color: Colors.white54),
                    ),
                    onPressed: _goToManualInput,
                    icon: const Icon(Icons.keyboard_outlined),
                    label: const Text('手动键盘录入'),
                  )
                else
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.white,
                      side: const BorderSide(color: Colors.white54),
                    ),
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.arrow_back_rounded),
                    label: const Text('返回手动输入'),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBottomActions(ThemeData theme) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        // 闪光灯切换
        ValueListenableBuilder(
          valueListenable: _controller,
          builder: (context, state, child) {
            final isTorchOn = state.torchState == TorchState.on;
            return _buildCircleButton(
              icon: isTorchOn ? Icons.flash_on_rounded : Icons.flash_off_rounded,
              label: '手电筒',
              color: isTorchOn ? Colors.amberAccent : Colors.white70,
              onTap: () => _controller.toggleTorch(),
            );
          },
        ),
        const SizedBox(width: 32),

        // 从相册选择图片识别
        _buildCircleButton(
          icon: Icons.photo_library_outlined,
          label: '相册识别',
          color: Colors.cyanAccent,
          onTap: _pickImageAndScan,
        ),
        const SizedBox(width: 32),

        // 切换镜头
        _buildCircleButton(
          icon: Icons.flip_camera_ios_outlined,
          label: '切换镜头',
          color: Colors.white70,
          onTap: () => _controller.switchCamera(),
        ),
      ],
    );
  }

  Widget _buildCircleButton({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(30),
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.15),
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white24),
            ),
            child: Icon(icon, color: color, size: 24),
          ),
        ),
        const SizedBox(height: 6),
        Text(label, style: const TextStyle(color: Colors.white70, fontSize: 12)),
      ],
    );
  }
}
