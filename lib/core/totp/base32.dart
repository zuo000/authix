import 'dart:typed_data';

/// 纯 Dart 实现的标准 Base32 编解码器 (遵循 RFC 4648)
class Base32 {
  static const String _alphabet = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ234567';
  static final Map<String, int> _decodeMap = {
    for (int i = 0; i < _alphabet.length; i++) _alphabet[i]: i,
  };

  /// 解码 Base32 字符串为字节数组
  /// 自动容错：忽略空格、破折号，自动转为大写
  static Uint8List decode(String input) {
    final sanitized = input.replaceAll(RegExp(r'[\s\-]'), '').toUpperCase();
    if (sanitized.isEmpty) return Uint8List(0);

    // 移除末尾填充符 '='
    final clean = sanitized.replaceAll('=', '');

    final output = <int>[];
    int buffer = 0;
    int bitsLeft = 0;

    for (int i = 0; i < clean.length; i++) {
      final char = clean[i];
      final val = _decodeMap[char];
      if (val == null) {
        throw FormatException('无效的 Base32 字符: "$char"');
      }

      buffer = (buffer << 5) | val;
      bitsLeft += 5;

      if (bitsLeft >= 8) {
        bitsLeft -= 8;
        output.add((buffer >> bitsLeft) & 0xFF);
      }
    }

    return Uint8List.fromList(output);
  }

  /// 将字节数组编码为 Base32 字符串
  static String encode(List<int> bytes, {bool padding = true}) {
    if (bytes.isEmpty) return '';

    final sb = StringBuffer();
    int buffer = 0;
    int bitsLeft = 0;

    for (final byte in bytes) {
      buffer = (buffer << 8) | (byte & 0xFF);
      bitsLeft += 8;

      while (bitsLeft >= 5) {
        bitsLeft -= 5;
        final index = (buffer >> bitsLeft) & 0x1F;
        sb.write(_alphabet[index]);
      }
    }

    if (bitsLeft > 0) {
      final index = (buffer << (5 - bitsLeft)) & 0x1F;
      sb.write(_alphabet[index]);
    }

    if (padding) {
      while (sb.length % 8 != 0) {
        sb.write('=');
      }
    }

    return sb.toString();
  }

  /// 快捷将 UTF-8 文本编码为 Base32
  static String encodeString(String text, {bool padding = true}) {
    return encode(text.codeUnits, padding: padding);
  }

  /// 快捷将 Base32 解码为 UTF-8 文本
  static String decodeString(String base32) {
    return String.fromCharCodes(decode(base32));
  }

  /// 校验 Base32 字符串是否合法
  static bool isValid(String input) {
    try {
      decode(input);
      return true;
    } catch (_) {
      return false;
    }
  }
}
