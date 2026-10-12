import 'dart:math';

/// 纯本地高强度随机密码生成器 (CSPRNG)
class PasswordGenerator {
  static const _upper = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ';
  static const _lower = 'abcdefghijklmnopqrstuvwxyz';
  static const _numbers = '0123456789';
  static const _symbols = '!@#\$%^&*()_+-=[]{}|;:,.<>?';

  static String generate({
    int length = 16,
    bool includeUpper = true,
    bool includeLower = true,
    bool includeNumbers = true,
    bool includeSymbols = true,
  }) {
    final chars = StringBuffer();
    final guaranteed = <String>[];
    final random = Random.secure();

    if (includeUpper) {
      chars.write(_upper);
      guaranteed.add(_upper[random.nextInt(_upper.length)]);
    }
    if (includeLower) {
      chars.write(_lower);
      guaranteed.add(_lower[random.nextInt(_lower.length)]);
    }
    if (includeNumbers) {
      chars.write(_numbers);
      guaranteed.add(_numbers[random.nextInt(_numbers.length)]);
    }
    if (includeSymbols) {
      chars.write(_symbols);
      guaranteed.add(_symbols[random.nextInt(_symbols.length)]);
    }

    final charPool = chars.toString();
    if (charPool.isEmpty) return '';

    final result = List<String>.from(guaranteed);
    while (result.length < length) {
      result.add(charPool[random.nextInt(charPool.length)]);
    }

    // 洗牌打乱顺序
    result.shuffle(random);
    return result.join();
  }
}
