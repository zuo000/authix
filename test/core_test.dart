import 'package:flutter_test/flutter_test.dart';
import 'package:authix/core/totp/base32.dart';
import 'package:authix/core/totp/totp_engine.dart';
import 'package:authix/core/backup/yaml_backup_service.dart';
import 'package:authix/models/credential.dart';
import 'package:authix/models/recovery_code.dart';
import 'package:authix/ui/screens/edit_credential_screen.dart';

void main() {
  group('Base32 RFC 4648 编解码测试', () {
    test('标准字符串 Base32 编码与解码一致性', () {
      const sample = 'Hello, Authix!';
      final encoded = Base32.encodeString(sample);
      final decoded = Base32.decodeString(encoded);
      expect(decoded, equals(sample));
    });

    test('常见 Base32 Secret 规范化与有效性校验', () {
      expect(Base32.isValid('JBSWY3DPEHPK3PXP'), isTrue);
      expect(Base32.isValid('jbswy 3dpehp k3pxp'), isTrue); // 支持小写和空格
      expect(Base32.isValid('invalid189!'), isFalse);
    });
  });

  group('TOTP RFC 6238 动态口令计算测试', () {
    test('标准密钥计算 6 位动态验证码', () {
      const secret = 'JBSWY3DPEHPK3PXP';
      final code = TotpEngine.generateCode(secret: secret);
      expect(code.length, equals(6));
      expect(int.tryParse(code), isNotNull);
    });

    test('从 otpauth URI 解析参数并内嵌恢复码', () {
      const uri = 'otpauth://totp/GitHub:alice@example.com?secret=JBSWY3DPEHPK3PXP&issuer=GitHub&digits=6&period=30';
      final parsed = TotpEngine.parseUri(uri);
      expect(parsed, isNotNull);
      expect(parsed!.issuer, equals('GitHub'));
      expect(parsed.account, equals('alice@example.com'));
      expect(parsed.secret, equals('JBSWY3DPEHPK3PXP'));
      expect(parsed.digits, equals(6));
      expect(parsed.period, equals(30));
    });

    test('时间步推进与跨周期验证码更新测试', () {
      const secret = 'JBSWY3DPEHPK3PXP';
      final t1 = DateTime.fromMillisecondsSinceEpoch(1000000 * 1000); // 周期 counter = 1000000 ~/ 30 = 33333
      final t2 = DateTime.fromMillisecondsSinceEpoch((1000000 + 35) * 1000); // 下一周期 counter = 33334

      final code1 = TotpEngine.generateCode(secret: secret, time: t1);
      final code2 = TotpEngine.generateCode(secret: secret, time: t2);

      // 跨越 30 秒周期，新验证码必须自动变化
      expect(code1, isNot(equals(code2)));

      final state = TotpEngine.getRemainingProgress(time: t1, period: 30);
      expect(state.remainingSeconds >= 1 && state.remainingSeconds <= 30, isTrue);
    });
  });

  group('YAML 明文备份与恢复规范测试', () {
    test('全量导出 YAML 并无损反序列化还原', () {
      final originalList = [
        Credential.create(
          type: CredentialType.totp,
          title: 'GitHub 2FA',
          account: 'octocat',
          issuer: 'GitHub',
          secret: 'JBSWY3DPEHPK3PXP',
          tags: ['开发', '核心'],
          pinned: true,
          recoveryCodes: [
            RecoveryCode(code: '1111-2222', used: false),
            RecoveryCode(code: '3333-4444', used: true),
          ],
        ),
        Credential.create(
          type: CredentialType.serverKey,
          title: '生产跳板机私钥',
          serverHost: 'jump.example.com',
          serverPort: 22,
          serverUser: 'root',
          privateKey: '-----BEGIN OPENSSH PRIVATE KEY-----\nb3BlbnNzaC1rZXktdjEAAAA\n-----END OPENSSH PRIVATE KEY-----',
          publicKey: 'ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIG...',
          notes: '重要生产服务器，切勿泄露',
        ),
      ];

      // 导出为 YAML 字符串
      final yamlContent = YamlBackupService.exportToYamlString(originalList);
      expect(yamlContent.contains('version: 1'), isTrue);
      expect(yamlContent.contains('items:'), isTrue);
      expect(yamlContent.contains('GitHub 2FA'), isTrue);
      expect(yamlContent.contains('1111-2222'), isTrue);
      expect(yamlContent.contains('jump.example.com'), isTrue);

      // 从 YAML 还原解析
      final preview = YamlBackupService.parseYamlString(yamlContent);
      expect(preview.validItems.length, equals(2));

      final totpItem = preview.validItems.firstWhere((c) => c.type == CredentialType.totp);
      expect(totpItem.title, equals('GitHub 2FA'));
      expect(totpItem.recoveryCodes.length, equals(2));
      expect(totpItem.recoveryCodes[0].code, equals('1111-2222'));
      expect(totpItem.recoveryCodes[1].used, isTrue);

      final sshItem = preview.validItems.firstWhere((c) => c.type == CredentialType.serverKey);
      expect(sshItem.serverHost, equals('jump.example.com'));
      expect(sshItem.privateKey.contains('BEGIN OPENSSH PRIVATE KEY'), isTrue);
    });

    test('通行密钥 (Passkey) 模型序列化与无损备份还原测试', () {
      final passkey = Credential.create(
        type: CredentialType.passkey,
        title: 'GitHub Passkey 登录',
        url: 'github.com',
        account: 'octocat@github.com',
        publicKey: 'MFkwEwYHKoZIzj0CAQYIKoZIzj0DAQcDQgAE123456',
        privateKey: 'MIGHAgEAMBMGByqGSM49AgEGCCqGSM49AwEHBG0wawIBAQQg987654',
        extraData: {
          'rp_id': 'github.com',
          'credential_id': 'Ac7u9xK23L0qweRTY==',
          'user_handle': 'dXNlcg==',
          'passkey_algorithm': 'ES256',
        },
      );

      // 验证基本属性
      expect(passkey.type, equals(CredentialType.passkey));
      expect(passkey.url, equals('github.com'));
      expect(passkey.account, equals('octocat@github.com'));
      expect(passkey.extraData['passkey_algorithm'], equals('ES256'));

      // 测试 SQLite Map 转换
      final dbMap = passkey.toDbMap();
      final fromDb = Credential.fromDbMap(dbMap);
      expect(fromDb.type, equals(CredentialType.passkey));
      expect(fromDb.extraData['credential_id'], equals('Ac7u9xK23L0qweRTY=='));

      // 测试离线备份导出与解析还原
      final backupText = YamlBackupService.exportToYamlString([passkey]);
      expect(backupText.contains('passkey'), isTrue);
      expect(backupText.contains('github.com'), isTrue);
      expect(backupText.contains('Ac7u9xK23L0qweRTY=='), isTrue);

      final preview = YamlBackupService.parseYamlString(backupText);
      expect(preview.validItems.length, equals(1));
      final restored = preview.validItems.first;
      expect(restored.type, equals(CredentialType.passkey));
      expect(restored.title, equals('GitHub Passkey 登录'));
      expect(restored.account, equals('octocat@github.com'));
      expect(restored.publicKey, equals('MFkwEwYHKoZIzj0CAQYIKoZIzj0DAQcDQgAE123456'));
      expect(restored.extraData['credential_id'], equals('Ac7u9xK23L0qweRTY=='));
    });

    test('凭据软删除 (移入垃圾箱) 与恢复属性序列化测试', () {
      final item = Credential.create(
        type: CredentialType.password,
        title: '测试待删除凭据',
        account: 'user@test.com',
        password: 'password123',
      );

      // 默认未删除
      expect(item.isDeleted, isFalse);
      expect(item.deletedAt, isNull);

      // 模拟移入垃圾箱
      final now = DateTime.now().millisecondsSinceEpoch;
      final trashedItem = item.copyWith(isDeleted: true, deletedAt: now);
      expect(trashedItem.isDeleted, isTrue);
      expect(trashedItem.deletedAt, equals(now));

      // 验证数据库序列化
      final dbMap = trashedItem.toDbMap();
      expect(dbMap['is_deleted'], equals(1));
      expect(dbMap['deleted_at'], equals(now));

      final restoredFromDb = Credential.fromDbMap(dbMap);
      expect(restoredFromDb.isDeleted, isTrue);
      expect(restoredFromDb.deletedAt, equals(now));

      // 模拟从垃圾箱恢复
      final unTrashedItem = restoredFromDb.copyWith(isDeleted: false, deletedAt: null);
      expect(unTrashedItem.isDeleted, isFalse);
      expect(unTrashedItem.toDbMap()['is_deleted'], equals(0));
    });

    test('网址匹配检测规则 UrlMatcher 逻辑验证测试', () {
      // 1. 基础域名匹配 (baseDomain)
      expect(
        UrlMatcher.matches(
          ruleUrl: 'https://github.com/login',
          targetUrl: 'https://gist.github.com/settings',
          matchType: UrlMatchType.baseDomain,
        ),
        isTrue,
      );
      expect(
        UrlMatcher.matches(
          ruleUrl: 'github.com',
          targetUrl: 'https://gitlab.com/login',
          matchType: UrlMatchType.baseDomain,
        ),
        isFalse,
      );

      // 2. 主机匹配 (host)
      expect(
        UrlMatcher.matches(
          ruleUrl: 'https://my.router.local:8080/admin',
          targetUrl: 'http://my.router.local:8080/dashboard',
          matchType: UrlMatchType.host,
        ),
        isTrue,
      );
      expect(
        UrlMatcher.matches(
          ruleUrl: 'https://my.router.local:8080/admin',
          targetUrl: 'https://my.router.local:9090/admin',
          matchType: UrlMatchType.host,
        ),
        isFalse,
      );

      // 3. 起始路径匹配 (startsWith)
      expect(
        UrlMatcher.matches(
          ruleUrl: 'https://company.com/portal',
          targetUrl: 'https://company.com/portal/subapp/home',
          matchType: UrlMatchType.startsWith,
        ),
        isTrue,
      );
      expect(
        UrlMatcher.matches(
          ruleUrl: 'https://company.com/portal',
          targetUrl: 'https://company.com/other',
          matchType: UrlMatchType.startsWith,
        ),
        isFalse,
      );

      // 4. 完全一致匹配 (exact)
      expect(
        UrlMatcher.matches(
          ruleUrl: 'https://auth.org/login?step=1',
          targetUrl: 'https://auth.org/login?step=1',
          matchType: UrlMatchType.exact,
        ),
        isTrue,
      );
      expect(
        UrlMatcher.matches(
          ruleUrl: 'https://auth.org/login?step=1',
          targetUrl: 'https://auth.org/login?step=2',
          matchType: UrlMatchType.exact,
        ),
        isFalse,
      );

      // 5. 正则表达式匹配 (regex)
      expect(
        UrlMatcher.matches(
          ruleUrl: r'^https:\/\/(.*\.)?google\.(com|cn|co\.jp)$',
          targetUrl: 'https://accounts.google.com',
          matchType: UrlMatchType.regex,
        ),
        isTrue,
      );

      // 6. 从不匹配 (never)
      expect(
        UrlMatcher.matches(
          ruleUrl: 'https://example.com',
          targetUrl: 'https://example.com',
          matchType: UrlMatchType.never,
        ),
        isFalse,
      );
    });
  });

  group('2FA 应急恢复码智能解析测试', () {
    test('单码内部带空格分组不应被错误拆分成碎片码', () {
      // 常见 32 位恢复码带空格分组测试
      const input = 'ABCD EFGH IJKL MNOP QRST UVWX YZ01 2345';
      final results = EditCredentialScreen.extractRecoveryCodes(input);

      expect(results.length, equals(1));
      expect(results.first, equals('ABCD EFGH IJKL MNOP QRST UVWX YZ01 2345'));
    });

    test('Google 格式多行带空格恢复码正确保留每一行作为一个码', () {
      const input = '''
1234 5678
9012 3456
7890 1234
''';
      final results = EditCredentialScreen.extractRecoveryCodes(input);

      expect(results.length, equals(3));
      expect(results[0], equals('1234 5678'));
      expect(results[1], equals('9012 3456'));
      expect(results[2], equals('7890 1234'));
    });

    test('带列表序号与前缀的恢复码文本自动清洗序号', () {
      const input = '''
1. abcd-1234-efgh
2) ijkl-5678-mnop
- qrst-9012-uvwx
* yz12-3456-7890
''';
      final results = EditCredentialScreen.extractRecoveryCodes(input);

      expect(results.length, equals(4));
      expect(results[0], equals('abcd-1234-efgh'));
      expect(results[1], equals('ijkl-5678-mnop'));
      expect(results[2], equals('qrst-9012-uvwx'));
      expect(results[3], equals('yz12-3456-7890'));
    });

    test('逗号和分号分隔的多恢复码文本能够正确切分', () {
      const input = 'codeA123, codeB456; codeC789，codeD000；codeE111';
      final results = EditCredentialScreen.extractRecoveryCodes(input);

      expect(results.length, equals(5));
      expect(results, equals(['codeA123', 'codeB456', 'codeC789', 'codeD000', 'codeE111']));
    });

    test('制表符与多空格表格排版的两列恢复码正确切分', () {
      const input = '''
code-1111\tcode-2222
code-3333   code-4444
''';
      final results = EditCredentialScreen.extractRecoveryCodes(input);

      expect(results.length, equals(4));
      expect(results, equals(['code-1111', 'code-2222', 'code-3333', 'code-4444']));
    });
  });
}
