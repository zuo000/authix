import 'package:local_auth/local_auth.dart';

/// 纯本地生物识别与应用安全锁服务
class LocalAuthService {
  static final LocalAuthentication _auth = LocalAuthentication();

  /// 检查当前设备是否支持生物识别
  static Future<bool> isBiometricsAvailable() async {
    try {
      final canAuthenticateWithBiometrics = await _auth.canCheckBiometrics;
      final canAuthenticate = canAuthenticateWithBiometrics || await _auth.isDeviceSupported();
      return canAuthenticate;
    } catch (_) {
      return false;
    }
  }

  /// 唤起系统生物识别或系统凭证认证
  static Future<bool> authenticate({String reason = '请验证身份以解锁 Authix 保险箱'}) async {
    try {
      return await _auth.authenticate(
        localizedReason: reason,
        options: const AuthenticationOptions(
          stickyAuth: true,
          biometricOnly: false,
          useErrorDialogs: true,
        ),
      );
    } catch (_) {
      return false;
    }
  }
}
