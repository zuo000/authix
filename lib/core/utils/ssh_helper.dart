import 'dart:convert';
import 'package:crypto/crypto.dart';

/// SSH 实用辅助类
class SshHelper {
  /// 生成标准的终端连接指令
  static String formatSshCommand({
    required String host,
    int port = 22,
    String user = '',
    String keyPath = '~/.ssh/id_rsa',
  }) {
    final sb = StringBuffer('ssh');
    if (keyPath.isNotEmpty) {
      sb.write(' -i $keyPath');
    }
    if (port != 22) {
      sb.write(' -p $port');
    }
    sb.write(' ');
    if (user.isNotEmpty) {
      sb.write('$user@');
    }
    sb.write(host.isEmpty ? 'your-server-ip' : host);
    return sb.toString();
  }

  /// 粗略计算并展示公钥指纹 (SHA-256)
  static String getFingerprint(String keyText) {
    if (keyText.trim().isEmpty) return '';
    try {
      final clean = keyText.replaceAll(RegExp(r'\r|\n'), '');
      final digest = sha256.convert(utf8.encode(clean));
      final base64String = base64Url.encode(digest.bytes).replaceAll('=', '');
      return 'SHA256:$base64String';
    } catch (_) {
      return '';
    }
  }
}
