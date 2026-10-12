import 'dart:math';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'base32.dart';

/// TOTP 哈希算法类型
enum OtpAlgorithm {
  sha1,
  sha256,
  sha512;

  static OtpAlgorithm fromString(String? val) {
    switch (val?.toUpperCase()) {
      case 'SHA256':
        return OtpAlgorithm.sha256;
      case 'SHA512':
        return OtpAlgorithm.sha512;
      case 'SHA1':
      default:
        return OtpAlgorithm.sha1;
    }
  }

  String get nameString {
    switch (this) {
      case OtpAlgorithm.sha1:
        return 'SHA1';
      case OtpAlgorithm.sha256:
        return 'SHA256';
      case OtpAlgorithm.sha512:
        return 'SHA512';
    }
  }
}

/// 解析后的 OTPAuth 凭据参数
class OtpAuthUriData {
  final String secret;
  final String? issuer;
  final String? account;
  final OtpAlgorithm algorithm;
  final int digits;
  final int period;

  const OtpAuthUriData({
    required this.secret,
    this.issuer,
    this.account,
    this.algorithm = OtpAlgorithm.sha1,
    this.digits = 6,
    this.period = 30,
  });
}

/// 纯 Dart RFC 6238 TOTP 算法引擎
class TotpEngine {
  /// 计算当前时间步下的 TOTP 验证码
  static String generateCode({
    required String secret,
    DateTime? time,
    OtpAlgorithm algorithm = OtpAlgorithm.sha1,
    int digits = 6,
    int period = 30,
  }) {
    final now = time ?? DateTime.now();
    final epochSeconds = now.millisecondsSinceEpoch ~/ 1000;
    final counter = epochSeconds ~/ period;
    return generateHotp(
      secret: secret,
      counter: counter,
      algorithm: algorithm,
      digits: digits,
    );
  }

  /// 获取当前剩余有效秒数及进度百分比 (0.0 ~ 1.0)
  static ({int remainingSeconds, double progress}) getRemainingProgress({
    DateTime? time,
    int period = 30,
  }) {
    final now = time ?? DateTime.now();
    final currentSecondInPeriod = (now.millisecondsSinceEpoch ~/ 1000) % period;
    final remaining = period - currentSecondInPeriod;
    final progress = remaining / period;
    return (remainingSeconds: remaining, progress: progress);
  }

  /// RFC 4226 HOTP 核心算法
  static String generateHotp({
    required String secret,
    required int counter,
    OtpAlgorithm algorithm = OtpAlgorithm.sha1,
    int digits = 6,
  }) {
    final keyBytes = Base32.decode(secret);

    // 将 64 位整数 counter 转换为 8 字节大端序
    final counterBytes = Uint8List(8);
    var temp = counter;
    for (int i = 7; i >= 0; i--) {
      counterBytes[i] = temp & 0xFF;
      temp >>= 8;
    }

    // HMAC 计算
    Hash hash;
    switch (algorithm) {
      case OtpAlgorithm.sha1:
        hash = sha1;
        break;
      case OtpAlgorithm.sha256:
        hash = sha256;
        break;
      case OtpAlgorithm.sha512:
        hash = sha512;
        break;
    }

    final hmac = Hmac(hash, keyBytes);
    final digest = hmac.convert(counterBytes).bytes;

    // 动态截断 (Dynamic Truncation)
    final offset = digest.last & 0x0F;
    final binary = ((digest[offset] & 0x7F) << 24) |
        ((digest[offset + 1] & 0xFF) << 16) |
        ((digest[offset + 2] & 0xFF) << 8) |
        (digest[offset + 3] & 0xFF);

    final otp = binary % pow(10, digits).toInt();
    return otp.toString().padLeft(digits, '0');
  }

  /// 解析标准 otpauth://totp/ 协议 URI
  static OtpAuthUriData? parseUri(String uriString) {
    try {
      final uri = Uri.parse(uriString.trim());
      if (uri.scheme.toLowerCase() != 'otpauth') return null;
      if (uri.host.toLowerCase() != 'totp') return null;

      final secret = uri.queryParameters['secret'];
      if (secret == null || secret.isEmpty) return null;

      // 解析 path: 例如 /GitHub:user@example.com 或 /user@example.com
      var label = Uri.decodeComponent(uri.path.replaceFirst('/', ''));
      String? issuer = uri.queryParameters['issuer'];
      String? account;

      if (label.contains(':')) {
        final parts = label.split(':');
        issuer ??= parts[0].trim();
        account = parts.sublist(1).join(':').trim();
      } else {
        account = label.trim();
      }

      final algorithm = OtpAlgorithm.fromString(uri.queryParameters['algorithm']);
      final digits = int.tryParse(uri.queryParameters['digits'] ?? '') ?? 6;
      final period = int.tryParse(uri.queryParameters['period'] ?? '') ?? 30;

      return OtpAuthUriData(
        secret: secret,
        issuer: issuer,
        account: account,
        algorithm: algorithm,
        digits: digits,
        period: period,
      );
    } catch (_) {
      return null;
    }
  }

  /// 生成标准 otpauth://totp/ URI 字符串
  static String formatUri({
    required String secret,
    String? issuer,
    String? account,
    OtpAlgorithm algorithm = OtpAlgorithm.sha1,
    int digits = 6,
    int period = 30,
  }) {
    final labelParts = <String>[];
    if (issuer != null && issuer.isNotEmpty) labelParts.add(issuer);
    if (account != null && account.isNotEmpty) labelParts.add(account);
    final label = Uri.encodeComponent(labelParts.join(':'));

    final query = <String, String>{
      'secret': secret.replaceAll(RegExp(r'\s+'), '').toUpperCase(),
    };
    if (issuer != null && issuer.isNotEmpty) {
      query['issuer'] = issuer;
    }
    if (algorithm != OtpAlgorithm.sha1) {
      query['algorithm'] = algorithm.nameString;
    }
    if (digits != 6) {
      query['digits'] = digits.toString();
    }
    if (period != 30) {
      query['period'] = period.toString();
    }

    final queryString = query.entries.map((e) => '${e.key}=${Uri.encodeComponent(e.value)}').join('&');
    return 'otpauth://totp/$label?$queryString';
  }

  /// 别名：生成标准 otpauth://totp/ URI 字符串
  static String generateUri({
    required String secret,
    String? issuer,
    String? account,
    OtpAlgorithm algorithm = OtpAlgorithm.sha1,
    int digits = 6,
    int period = 30,
  }) => formatUri(
    secret: secret,
    issuer: issuer,
    account: account,
    algorithm: algorithm,
    digits: digits,
    period: period,
  );
}
