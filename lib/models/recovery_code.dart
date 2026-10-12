/// 2FA 应急备用恢复码模型
class RecoveryCode {
  final String code;
  final bool used;

  const RecoveryCode({
    required this.code,
    this.used = false,
  });

  RecoveryCode copyWith({
    String? code,
    bool? used,
  }) {
    return RecoveryCode(
      code: code ?? this.code,
      used: used ?? this.used,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'code': code,
      'used': used,
    };
  }

  factory RecoveryCode.fromMap(Map<String, dynamic> map) {
    return RecoveryCode(
      code: map['code']?.toString() ?? '',
      used: map['used'] == true || map['used'] == 1 || map['used'] == 'true',
    );
  }
}
