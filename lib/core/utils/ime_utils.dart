import 'package:flutter/services.dart';

/// 安全的输入法格式化器：
/// 针对 macOS、Windows 等桌面端中文/CJK 输入法，
/// 在退格删除组合拼音或中文字符时，若输入法产生的组合范围坍缩为 0 (collapsed) 或超出当前文本边界，
/// 及时校正为 [TextRange.empty]，防止输入流陷入无效组合等待锁进而导致输入框假死。
class ImeSafeTextInputFormatter extends TextInputFormatter {
  const ImeSafeTextInputFormatter();

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    if (newValue.composing.isValid) {
      // 1. 文本已空时，组合区域必须为空
      if (newValue.text.isEmpty) {
        return newValue.copyWith(composing: TextRange.empty);
      }
      // 2. 组合区域长度为 0 (例如退格删除掉所有未上屏拼音) 或越界时，安全重置为 TextRange.empty
      if (newValue.composing.isCollapsed ||
          newValue.composing.start < 0 ||
          newValue.composing.end > newValue.text.length ||
          newValue.composing.start > newValue.composing.end) {
        return newValue.copyWith(composing: TextRange.empty);
      }
    }
    return newValue;
  }
}
