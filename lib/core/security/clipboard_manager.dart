import 'dart:async';
import 'package:flutter/services.dart';

/// 安全剪贴板管理：支持复制与 30 秒后自动清空
class ClipboardManager {
  static Timer? _clearTimer;
  static String? _lastCopiedText;

  /// 复制文本到系统剪贴板，并在指定秒数后自动清空
  static Future<void> copyWithAutoClear(String text, {int clearAfterSeconds = 30}) async {
    await Clipboard.setData(ClipboardData(text: text));
    _lastCopiedText = text;

    _clearTimer?.cancel();
    if (clearAfterSeconds > 0) {
      _clearTimer = Timer(Duration(seconds: clearAfterSeconds), () async {
        final currentData = await Clipboard.getData(Clipboard.kTextPlain);
        // 仅当剪贴板内容仍为我们复制的内容时才清空，避免误清用户后续复制的内容
        if (currentData?.text == _lastCopiedText) {
          await Clipboard.setData(const ClipboardData(text: ''));
        }
        _lastCopiedText = null;
      });
    }
  }

  /// 立即清空
  static Future<void> clearImmediately() async {
    _clearTimer?.cancel();
    await Clipboard.setData(const ClipboardData(text: ''));
    _lastCopiedText = null;
  }
}
