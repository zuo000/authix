import 'package:flutter_test/flutter_test.dart';
import 'package:authix/models/credential.dart';

void main() {
  test('Credential 基础模型实例化与默认值测试', () {
    final item = Credential.create(
      type: CredentialType.password,
      title: '测试账号',
      account: 'user@test.com',
      password: 'SafePassword123!',
    );

    expect(item.id.isNotEmpty, true);
    expect(item.type, CredentialType.password);
    expect(item.title, '测试账号');
    expect(item.account, 'user@test.com');
    expect(item.password, 'SafePassword123!');
    expect(item.pinned, false);
    expect(item.tags, isEmpty);
  });
}
