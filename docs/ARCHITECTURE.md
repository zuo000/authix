# Authix 系统架构与设计文档（纯离线版）

> 状态：架构基线（纯离线单机版）  
> 更新日期：2026-10-07  
> 目标：轻量级、纯离线、零服务端依赖、免登录注册、全平台统一支持的“数字保险箱”（TOTP、网站/App 密码、服务器私钥、API Key、加密钱包助记词、银行卡、证件与机密备忘录），核心采用 **YAML** 格式进行明文备份与恢复。

---

## 1. 系统定位与设计原则

Authix 是一款专为注重隐私、追求自主可控与极客体验的用户打造的**纯离线全能数字凭据与密钥管理工具**。项目彻底告别繁琐沉重的云端架构，回归纯单机、零网络权限、即开即用、数据完全自由流通的工具本质。

### 1.1 核心设计原则

1. **绝对离线（Zero Network）**：
   - 客户端应用完全不申请网络访问权限，断网环境下 100% 完整可用。
   - 无服务端、无账号体系（免注册、免登录）、无第三方跟踪与遥测。
2. **极简轻量与极致启动（Lightweight & Fast）**：
   - 即开即用，秒级冷启动。
   - 彻底摒弃网络同步、分布式冲突解决和云端公钥协商。
3. **全品类离线凭据支持（All-in-One Offline Vault）**：
   - **TOTP 二次验证码**：2FA/MFA 动态口令计算，**原生内置 2FA 应急备用恢复码（Recovery Codes）清单管理**。
   - **网站 / App 登录凭据**：网址、应用名、账号、密码，支持可选绑定 TOTP 形成一站式登录条目。
   - **服务器连接私钥（SSH Key）**：Linux/Unix SSH 私钥（OpenSSH/PEM/Ed25519/RSA）、端口、用户名及 Key Passphrase。
   - **开发者 API 密钥（API Keys / Tokens）**：OpenAI、GitHub PAT、云厂商 SecretKey 等，带过期时间提醒与一键复制。
   - **加密货币钱包（Crypto Wallets）**：冷钱包 12/24 位 BIP-39 助记词、钱包地址与资产私钥。
   - **银行卡 / 支付卡（Payment Cards）**：卡号（Luhn 算法自动校验）、持卡人、有效期、CVV 掩码。
   - **个人证件与档案（Identities）**：身份证、护照、驾照、税号备查。
   - **安全备忘录（Secure Notes）**：支持富文本/Markdown 与自定义动态键值对（Wi-Fi 密码、软件激活码、环境配置等）。
4. **自主可控与开放流通（YAML Plaintext Backup & Portability）**：
   - 核心支持**以 YAML 格式（`.yaml` / `.yml`）进行离线明文备份与恢复**。
   - 充分利用 YAML 原生支持多行文本块、缩进清晰无冗余引号的特点，兼顾人类极佳可读性与编辑便捷性。
   - 数据完全归用户所有，可自由在任意文本编辑器、跨平台设备或第三方工具之间迁移查看。

---

## 2. 整体架构设计

应用采用单机分层架构，基于 **Flutter 3.x+** 进行全平台统一构建（覆盖 Windows / macOS / Linux / Android / iOS）：

```text
┌────────────────────────────────────────────────────────┐
│                      UI 表现层                         │
│  - 凭据分类主视图 (全部 / TOTP / 密码 / 私钥 / 卡证 / 备忘) │
│  - 响应式布局 (移动端自适应 / 桌面端分栏 + 快捷键)      │
│  - 动态倒计时圆环 / 助记词防窥网格 / 密码强弱生成器    │
│  - 离线 YAML 导入与导出向导 / 纯本地应用锁设置         │
└──────────────────────────┬─────────────────────────────┘
                           │
┌──────────────────────────▼─────────────────────────────┐
│                     业务领域层                         │
│  - TOTP Engine (RFC 6238 动态码计算 + 应急恢复码状态流)  │
│  - Password & Generator (高强度本地密码生成与检测)      │
│  - SSH Key Manager (PEM/OpenSSH 解析、指纹计算与命令生成)│
│  - Extended Vault Services (API Key/助记词/银行卡/证件) │
│  - Vault Manager (全局凭据 CRUD、多维检索、排序引擎)   │
│  - Backup & Restore Service (YAML 离线导出格式化与导入校验) │
│  - App Lock Service (纯本地生物识别与 PIN 鉴权)        │
└──────────────────────────┬─────────────────────────────┘
                           │
┌──────────────────────────▼─────────────────────────────┐
│                    数据与平台支撑层                    │
│  - SQLite 统一本地持久化 (移动端 sqflite / 桌面端 FFI) │
│  - 纯 Dart YAML 解析与生成 (package:yaml 无原生依赖)    │
│  - 剪贴板安全生命周期管理 (30s 自动清空)               │
│  - 原生文件对话框与系统分享 (FilePicker / Share)       │
└────────────────────────────────────────────────────────┘
```

### 2.1 模块职责划分

- **TOTP Engine**：
  - 实现 RFC 6238（TOTP）与 RFC 4226（HOTP），支持 SHA-1/256/512 与 6/8 位动态码。
  - **原生内聚 2FA 应急恢复码管理**：维护对应服务的多组一次性备用恢复码，支持“已使用”标记划线与批量导入。
- **Password Manager**：
  - 维护网址、用户名、密码；集成纯本地强随机密码生成器；支持与 TOTP 二合一无缝融合。
- **SSH Key Manager**：
  - 管理 Linux/Unix SSH 私钥文本，解析并派生公钥指纹（SHA-256/MD5），生成标准化终端一键连接命令。
- **Specialized Credential Managers**：
  - `CryptoWalletManager`：助记词规范化校验与序号分词展示。
  - `PaymentCardManager`：卡号分段与本地 Luhn 算法合法性校验。
  - `ApiKeyManager`：密钥明密文转换与过期状态判定。
  - `SecureNoteManager`：动态键值对（Key-Value）属性扩展。
- **Vault Manager**：
  - 统一存储仓库，负责所有凭据对象的增删改查、标签过滤与全局检索。
- **Backup & Restore Service**：
  - 负责版本化 YAML 备份文件的离线格式化导出与原子性恢复，支持去重与冲突合并。
- **App Lock Service**：
  - 纯本地系统生物识别（Face ID/Touch ID/Windows Hello）或简易 PIN 码防护。

---

## 3. 本地数据模型

为保持轻量高效与零配置启动，本地数据库采用 SQLite，包含统一凭据主表 `credentials` 及本地配置表 `app_settings`。

### 3.1 核心凭据表 `credentials`

采用“标准通用列 + 高频业务列 + 泛型扩展列（`extra_data`）”的设计模式。既能享有 SQLite 强类型字段的高速索引与排序，又赋予每种凭据灵活的数据表达能力：

| 字段名 | 类型 | 说明 | 适用类型 | 示例 |
|---|---|---|---|---|
| `id` | TEXT PRIMARY KEY | 本地唯一标识 UUID | 全部 | `c9b2e13a-7a1b-4f9e-...` |
| `type` | TEXT NOT NULL | 凭据类型枚举（见下文 8 大类型） | 全部 | `totp` / `password` / `server_key` 等 |
| `title` | TEXT NOT NULL | 条目标题 / 显示名称 | 全部 | `GitHub 个人` / `AWS 生产控制台` |
| `tags` | TEXT | 分组或标签 (逗号分隔或 JSON 数组) | 全部 | `DevOps,Cloud,Personal` |
| `pinned` | INTEGER DEFAULT 0 | 是否置顶 (0: 否, 1: 是) | 全部 | `1` |
| `sort_order` | INTEGER DEFAULT 0 | 自定义拖拽排序序号 | 全部 | `10` |
| `notes` | TEXT | 通用备注说明 / 备忘文本 | 全部 | `跳板机之后访问，每月轮换密码` |
| **--- 账号 / 密码 / 网站专属 ---** | | | | |
| `account` | TEXT | 登录账号 / 用户名 / 邮箱 | password / totp | `developer@example.com` |
| `password` | TEXT | 登录密码明文 | password | `k$9P#mQ2!vL8@` |
| `url` | TEXT | 网站登录地址或应用标识 | password | `https://github.com/login` |
| **--- TOTP 动态码专属 (天然内聚应急备用码) ---** | | | | |
| `issuer` | TEXT | 发行方 / 机构名称 | totp / password | `Google` / `GitHub` |
| `secret` | TEXT | TOTP Base32 密钥字符串 | totp / password | `JBSWY3DPEHPK3PXP` |
| `algorithm` | TEXT DEFAULT 'SHA1'| 算法：`SHA1` / `SHA256` / `SHA512` | totp / password | `SHA1` |
| `digits` | INTEGER DEFAULT 6 | 动态码位数 (6 或 8) | totp / password | `6` |
| `period` | INTEGER DEFAULT 30 | 刷新周期 (秒) | totp / password | `30` |
| `recovery_codes` | TEXT | **2FA 应急恢复码清单 (JSON 数组)** | totp / password | `[{"code":"1a2b-3c4d","used":false}]` |
| **--- 服务器连接私钥专属 ---** | | | | |
| `server_host` | TEXT | 服务器 IP 或域名 | server_key | `10.0.1.5` / `bastion.internal` |
| `server_port` | INTEGER DEFAULT 22 | SSH 端口 | server_key | `22` / `2222` |
| `server_user` | TEXT | SSH 登录用户名 | server_key | `ubuntu` / `root` |
| `private_key` | TEXT | 私钥明文文本 (OpenSSH/PEM 格式) | server_key | `-----BEGIN OPENSSH PRIVATE KEY-----...` |
| `key_passphrase` | TEXT | 私钥加密口令 (若有) | server_key | `MyPassphrase2026` |
| `key_algorithm` | TEXT | 密钥算法：`ed25519` / `rsa` 等 | server_key | `ed25519` |
| `public_key` | TEXT | 对应公钥文本 (可选) | server_key | `ssh-ed25519 AAAAC3Nz...` |
| **--- 扩展专有数据 (JSON 结构体) ---** | | | | |
| `extra_data` | TEXT | 存放 API Key、钱包助记词、银行卡、证件、自定义键值对等专有结构 | api_key / crypto / card / note / identity | `{"card_number":"...","cvv":"..."}` |
| **--- 基础元数据 ---** | | | | |
| `created_at` | INTEGER NOT NULL | 创建时间戳 (毫秒或秒) | 全部 | `1791384000` |
| `updated_at` | INTEGER NOT NULL | 更新时间戳 (毫秒或秒) | 全部 | `1791384000` |

### 3.2 支持的 8 大凭据类型及其 `extra_data` 结构

1. **`totp`（独立二次验证码）**：
   - 使用核心 TOTP 字段，`recovery_codes` 原生存放该服务的一组应急备用码（包含 code 与 used 状态）。
2. **`password`（网站 / App 登录凭据）**：
   - 核心字段：`url`, `account`, `password`；可选附带 `secret` 与 `recovery_codes`，形成二合一全套登录凭据。
3. **`server_key`（服务器 SSH 连接私钥）**：
   - 核心字段：`server_host`, `server_port`, `server_user`, `private_key`, `key_passphrase`, `key_algorithm`。
4. **`api_key`（开发者 API 密钥与 Access Token）**：
   - `extra_data`：
     ```json
     {
       "service_provider": "OpenAI",
       "api_key": "sk-proj-abc123xyz...",
       "key_id": "org-default-key",
       "expires_at": 1825000000
     }
     ```
5. **`crypto_wallet`（加密货币钱包助记词与私钥）**：
   - `extra_data`：
     ```json
     {
       "blockchain": "Ethereum / EVM",
       "wallet_address": "0x71C...3a9",
       "seed_phrase": ["apple", "banana", "cat", "dog", "elephant", "...(12/24词)"],
       "private_key": "0x4f355b4a..."
     }
     ```
6. **`card`（银行卡 / 支付卡）**：
   - `extra_data`：
     ```json
     {
       "cardholder_name": "SAN ZHANG",
       "card_number": "4111 2222 3333 4444",
       "expiry_date": "10/28",
       "cvv": "888",
       "card_type": "Visa",
       "bank_name": "招商银行"
     }
     ```
7. **`identity`（个人证件与档案）**：
   - `extra_data`：
     ```json
     {
       "full_name": "张三",
       "doc_type": "居民身份证",
       "id_number": "110101199003072345",
       "expiry_date": "2035-08-01",
       "issuing_authority": "北京市公安局"
     }
     ```
8. **`secure_note`（安全备忘录与自定义键值对）**：
   - `notes` 存放正文 Markdown/纯文本，`extra_data` 存放动态键值对：
     ```json
     {
       "custom_fields": [
         {"label": "Wi-Fi 密码", "value": "Home5G@SecretPass", "masked": true},
         {"label": "路由器后台", "value": "192.168.1.1", "masked": false},
         {"label": "软件激活码", "value": "XXXXX-YYYYY-ZZZZZ", "masked": false}
       ]
     }
     ```

### 3.3 应用本地配置表 `app_settings`

| 字段名 | 类型 | 说明 |
|---|---|---|
| `key` | TEXT PRIMARY KEY | 配置键名 |
| `value` | TEXT | 配置值 |

常见配置项：
- `app_lock_enabled`：是否开启应用锁（true/false）
- `biometric_enabled`：是否允许生物识别（true/false）
- `local_pin_hash`：本地 PIN 码的单向哈希
- `auto_lock_seconds`：切入后台后的自动锁定时间（如 0 秒即刻锁定，或 30 秒）
- `clipboard_clear_seconds`：复制验证码/密码/私钥后自动清空剪贴板的时间（默认 30 秒）
- `theme_mode`：浅色 / 深色 / 跟随系统
- `mask_passwords_by_default`：列表是否默认以圆点掩码遮挡密码、CVV、私钥与助记词

---

## 4. 离线明文备份与恢复设计（以 YAML 为核心格式）

用户核心要求**离线明文备份与恢复**。系统以 **YAML（`.yaml` / `.yml`）** 作为全量备份与还原的第一主选格式。

### 4.1 为什么选定 YAML 作为核心明文格式？

1. **天然支持多行文本块（Literal Block Scalar `|`）**：
   - 存储 Linux 服务器 SSH 私钥（`-----BEGIN OPENSSH PRIVATE KEY-----`）或 Markdown 备忘录时，YAML 能**原生保留换行与原始缩进**，无需像 JSON 那样把几百行私钥压缩成充满 `\n` 转义符的难读单行。
2. **人类阅读与手工编辑体验极佳**：
   - 彻底摒弃大括号 `{}`、中括号 `[]` 和繁琐双引号的视觉干扰。
   - 助记词列表（12/24词）与 2FA 应急恢复码清单采用清晰的破折号缩进，用户甚至可以直接用系统自带的“记事本 / 文本编辑 / VS Code”直接阅览、修改或手动补全。
3. **生态成熟与零外部依赖**：
   - 纯 Dart 官方生态提供 `package:yaml` 解析库，无任何 C 语言动态库依赖，全平台解析稳健高效。

---

### 4.2 核心 YAML 备份规范与范例（文件名：`authix_backup_YYYYMMDD_HHMMSS.yaml`）

```yaml
version: 1
app: Authix
exported_at: "2026-10-07T21:30:00Z"
count: 6

items:
  # 1. 独立 TOTP 动态码（原生收纳 2FA 应急恢复码）
  - id: "c9b2e13a-7a1b-4f9e-9d2e-0123456789ab"
    type: totp
    title: "GitHub 个人"
    issuer: "GitHub"
    account: "developer@example.com"
    secret: "JBSWY3DPEHPK3PXP"
    algorithm: SHA1
    digits: 6
    period: 30
    recovery_codes:
      - code: "1a2b-3c4d"
        used: true
      - code: "5e6f-7g8h"
        used: false
      - code: "9i0j-1k2l"
        used: false
    tags: ["Work", "2FA"]
    pinned: true
    notes: "主账号，开启强制 2FA"
    created_at: 1791384000
    updated_at: 1791384000

  # 2. 网站 / App 登录凭据（账号密码 + 内嵌 TOTP 与恢复码）
  - id: "e4a7c29d-11f2-4bc9-a831-abcdef012345"
    type: password
    title: "AWS 控制台"
    url: "https://signin.aws.amazon.com/console"
    account: "devops-admin"
    password: "SuperSecretPassword123!"
    issuer: "Amazon Web Services"
    secret: "HXDMVJECJJWSRB3HWIZR4IFUGFTMXBOZ"
    algorithm: SHA1
    digits: 6
    period: 30
    recovery_codes:
      - code: "aws-rec-001"
        used: false
    tags: ["Cloud", "AWS"]
    pinned: true
    notes: "生产控制台主登录账号（含内嵌 TOTP 与恢复码）"
    created_at: 1791384500
    updated_at: 1791384500

  # 3. 服务器连接私钥（多行私钥天然排版）
  - id: "f5b8d30e-22e3-4ca0-b942-bcdef0123456"
    type: server_key
    title: "生产跳板机 Bastion-01"
    server_host: "10.0.1.5"
    server_port: 22
    server_user: "ubuntu"
    key_algorithm: ed25519
    key_passphrase: "bastion-key-passphrase-2026"
    private_key: |
      -----BEGIN OPENSSH PRIVATE KEY-----
      b3BlbnNzaC1rZXktdjEAAAAABG5vbmUAAAAEbm9uZQAAAAAAAAABAAAAMwAAAAtzc2gtZW
      QyNTUxOQAAACD...（私钥多行内容，原生保留换行）...
      -----END OPENSSH PRIVATE KEY-----
    public_key: "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIB... ubuntu@bastion"
    tags: ["Server", "Bastion"]
    pinned: false
    created_at: 1791385000
    updated_at: 1791385000

  # 4. 开发者 API 密钥与 Access Token
  - id: "a1b2c3d4-e5f6-7a8b-9c0d-112233445566"
    type: api_key
    title: "OpenAI 生产 API Key"
    service_provider: "OpenAI"
    api_key: "sk-proj-Abc123XyZ789..."
    key_id: "prod-org-key"
    expires_at: 1825000000
    tags: ["AI", "Dev"]
    notes: "每月限额 $500"
    pinned: false
    created_at: 1791385500
    updated_at: 1791385500

  # 5. 加密货币冷钱包（12/24 位助记词）
  - id: "b2c3d4e5-f6a7-8b9c-0d1e-223344556677"
    type: crypto_wallet
    title: "MetaMask 冷钱包主账户"
    blockchain: "Ethereum / Arbitrum"
    wallet_address: "0x71C...3a9"
    seed_phrase:
      - apple
      - banana
      - cat
      - dog
      - elephant
      - fish
      - grape
      - hat
      - ice
      - jungle
      - kite
      - lemon
    private_key: "0x4f355b4a..."
    tags: ["Crypto", "Web3"]
    pinned: false
    notes: "离线冷钱包助记词，绝不上云"
    created_at: 1791386000
    updated_at: 1791386000

  # 6. 安全备忘录（Markdown + 动态自定义键值对）
  - id: "c3d4e5f6-a7b8-9c0d-1e2f-334455667788"
    type: secure_note
    title: "家庭办公与网络机密"
    notes: |
      # 家庭路由器与网络配置
      - 主路由 IP: 192.168.1.1
      - 备用 DNS: 1.1.1.1
    custom_fields:
      - label: "Wi-Fi 密码"
        value: "Home5G@SecretPass"
        masked: true
      - label: "NAS 管理员密码"
        value: "NasAdminPassword2026"
        masked: true
      - label: "正版激活码"
        value: "XXXXX-YYYYY-ZZZZZ"
        masked: false
    tags: ["Home", "Notes"]
    pinned: false
    created_at: 1791386500
    updated_at: 1791386500
```

#### 兼容支持
- **标准 otpauth 文本列表**（`.txt`）：单独将 TOTP 条目导出为标准 URI 列表，便于快速与其他纯 2FA 软件联动。

---

### 4.3 离线 YAML 备份导出流程

```text
用户点击“导出明文备份 (YAML)”
       │
       ▼
系统从本地数据库读取全部有效凭据记录
       │
       ▼
格式化为标准规范的 YAML 文本内容（私钥使用 | 语法，数组清晰缩进）
       │
       ▼
唤起系统“另存为 / 文件选择器”或“本地分享”
       │
       ▼
写入用户指定的本地磁盘路径或外部存储介质（如 USB、本地文件夹）
```

> **UI 安全提示**：在导出明文时，App 弹出防呆安全提示：  
> *“导出的备份文件为未加密的明文 YAML 文件，包含您的所有秘钥、私钥与密码。请将其妥善保存在安全的本地介质中，切勿随意外发或发送给陌生人。”*

---

### 4.4 离线 YAML 恢复导入流程

```text
用户点击“导入备份文件”
       │
       ▼
通过系统原生文件选择器选取本地备份文件 (.yaml / .yml)
       │
       ▼
使用纯 Dart YAML 解析器解析并校验格式规范性（合法性、字段类型、Base32 有效性）
       │
       ▼
展示导入预览界面（解析成功条数、重复条数、详细条目列表）
       │
       ▼
用户选择冲突处理策略：
  ├─ 策略 A：跳过已存在的凭据（基于 title + account / host 判断）
  ├─ 策略 B：覆盖已存在的凭据
  └─ 策略 C：全部作为新条目追加（保留历史副本）
       │
       ▼
本地 SQLite 开启单事务，批量写入，提交生效
```

- **事务原子性保证**：导入过程如果在中途遇到数据损坏或语法错误，本地 SQLite 事务将自动回滚，杜绝脏数据注入。

---

## 5. 核心业务流程与交互

### 5.1 凭据录入流程

应用提供统一的“新建凭据”入口，按业务类型自适应切换输入表单：

#### 1. TOTP 二次验证码录入（含 2FA 应急恢复码）
- **扫码录入**：
  - 移动端使用摄像头扫描包含 `otpauth://totp/...` 的二维码；桌面端支持从本地图片导入或剪贴板截图解析。
  - 正则解析 URL 参数：提取 `secret`、`issuer`、`account`、`algorithm`、`digits`、`period`。
- **手动录入**：
  - 手动输入 Base32 密钥，自动过滤空格与破折号并校验 Base32 编码合法性。
- **2FA 应急恢复码一并收纳**：
  - 许多服务开启 2FA 时会提供一批一次性备用恢复码（如 8~10 个 `xxxx-xxxx`）。
  - 在当前 TOTP 条目表单下方，提供“批量粘贴恢复码”输入区，自动分词拆分为列表，用户无需另存单独文本文件。
- **即时核对**：
  - 在录入页面实时计算并渲染出当前的动态验证码，方便用户即时与服务商核对。

#### 2. 网站 / App 登录凭据录入
- **基础信息**：填写标题、登录网址（URL）、用户名/邮箱及密码。
- **内置密码生成器**：
  - 纯本地 CSPRNG 生成高强度密码，可配置长度（8~64 位）、大写字母、小写字母、数字及特殊符号组合。
- **二合一 TOTP 关联（可选）**：
  - 若该网站开启了 2FA，可在同一表单下直接填入或扫码录入 TOTP 密钥及应急恢复码。
  - 用户只需维护一个条目，即可同时获得登录密码与动态验证码。

#### 3. 服务器连接私钥（SSH Key）录入
- **私钥录入方式**：
  - **手动粘贴**：直接将 OpenSSH / PEM / PKCS#8 格式的私钥文本粘贴至输入框。
  - **本地文件读取**：支持点击文件选择器直接选取本地私钥文件（如 `id_ed25519`、`id_rsa`、`server.pem`）。
- **元数据补充**：
  - 输入服务器 IP/域名（Host）、SSH 端口（默认 22）、登录用户名（User）。
  - 若私钥有 Passphrase 口令保护，可一并记录保存。
- **私钥解析与校验**：
  - 本地识别私钥算法类型（Ed25519 / RSA / ECDSA 等），自动派生并计算公钥指纹（SHA-256 / MD5），防止录入损坏或不合规的密钥文本。

#### 4. 开发者 API 密钥与 Access Token 录入
- 填写服务商名称（如 OpenAI、GitHub、AWS 等）、Key ID、API Key / Secret Token 明文及可选的到期日。

#### 5. 加密货币钱包助记词与私钥录入
- 选择区块链网络/标准（BIP-39），选择 12 词或 24 词模式。
- 逐个输入或一键粘贴整串单词，本地基于 BIP-39 官方词表（Wordlist）执行实时拼写校验与自动补全。

#### 6. 银行卡 / 支付卡录入
- 输入卡号时自动每 4 位添加空格分段，本地执行 **Luhn 算法** 自动校验卡号校验位的正确性。
- 录入持卡人姓名、有效期（MM/YY）、CVV 安全码及发卡行名称。

#### 7. 个人证件与档案录入
- 选择证件类型（身份证、护照、驾照、港澳通行证等），录入证件号码、全名及有效期。

#### 8. 安全备忘录录入（自定义键值对）
- 提供多行富文本/Markdown 编辑区。
- 支持动态“添加自定义字段（Key-Value）”，例如 `标签: Wi-Fi 密码`、`值: Secret123`，并可勾选是否默认掩码遮挡。

---

### 5.2 凭据查看与日常使用交互

#### 1. 列表主页与多维筛选
- **分类标签栏**：顶部快捷切换 `全部` / `TOTP 动态码` / `账号密码` / `服务器私钥` / `开发者密钥` / `钱包助记词` / `卡证备忘`。
- **即时全文搜索**：支持对标题、账号、域名、Host、标签及备注的毫秒级本地过滤。

#### 2. 日常快捷使用动作
- **TOTP 动态码**：
  - 显示动态圆环倒计时（默认 30 秒刷新）。
  - 点击大号验证码即刻复制，并在 30 秒后自动清空系统剪贴板。
  - **恢复码清单交互**：展开“应急恢复码”抽屉，点击某条备用码可一键复制，并支持点击复选框**划线标记为“已使用”**，避免紧急时刻混淆。
- **网站 / App 密码**：
  - 密码默认以圆点掩码隐藏，支持眼睛图标明文显隐。
  - 提供“复制用户名”、“复制密码”两个快捷动作。
  - 点击 URL 链接一键唤起系统默认浏览器访问登录页。
- **服务器连接私钥**：
  - 私钥内容默认折叠保密，可展开查看或一键复制完整私钥文本。
  - 提供**“一键复制 SSH 登录命令”**便捷按钮，直接生成标准的终端连接指令：
    ```bash
    ssh -i ~/.ssh/id_rsa -p 22 ubuntu@192.168.1.100
    ```
  - 桌面端支持一键**“导出私钥文件”**到指定本地目录。
- **开发者 API Key**：
  - 提供一键复制 Secret Token，显示过期倒计时或状态标识。
- **加密钱包助记词**：
  - 默认全屏磨砂掩码遮挡；长按或按住“显隐”按钮解锁显示 12/24 宫格编号单词卡片，松开立即重新打码，防止旁人偷窥。
- **银行卡**：
  - 显示卡面卡片视图，卡号一键格式化复制，CVV 点击显隐。
- **安全备忘录**：
  - 支持直接渲染 Markdown，自定义字段单独提供一键复制按钮。

---

## 6. 安全边界与设计建议

虽然定位为纯离线明文可导出的轻量工具，但仍在本地设备使用层面提供合理的安全防护：

| 关注维度 | 防护措施 |
|---|---|
| **网络泄露** | **物理隔绝**：应用完全不申请网络访问权限（Android/iOS/Desktop 无网络权限声明）。 |
| **他人暂借手机窥探** | **本地应用锁**：支持系统指纹/面容解锁，或本地 PIN 码保护；后台任务预览图打码/遮罩。 |
| **恶意截屏** | **防截屏保护（可选）**：移动端可开启 `FLAG_SECURE`（Android）或遮罩层，防止被恶意软件后台录屏。 |
| **剪贴板残留** | **延时清理**：复制凭据或验证码后，后台倒计时自动清理剪贴板。 |
| **数据遗失** | **简单明了的明文备份**：用户可随时导出 `.yaml` 文件并存放到个人 U 盘或冷存储盘中。 |

---

## 7. 跨平台技术方案选型（覆盖 5 大平台）

系统需要同时原生支持 **Windows、macOS、Linux、Android、iOS** 共 5 种客户端。经过对生态成熟度、跨平台一致性、纯离线能力与维护成本的综合评估，选定 **Flutter** 作为全平台统一技术方案。

### 7.1 跨平台技术选型对比

| 技术方案 | Windows / macOS / Linux | Android / iOS | 优势 | 劣势 / 排除原因 |
|---|---|---|---|---|
| **Flutter (选定方案)** | **官方 Tier 1 级支持** | **官方 Tier 1 级支持** | **一套代码覆盖 5 端**；自绘引擎（Impeller/Skia）UI 像素级一致；无浏览器内核开销；纯 Dart 离线密码学与 YAML 库无系统编译依赖；社区插件成熟度极高。 | 桌面端初次打包体积略大于原生（但远小于 Electron）。 |
| **Electron** | 优秀 | **不支持移动端** | 桌面端生态极为丰富。 | 无法支持 Android / iOS，内存开销大，直接排除。 |
| **Tauri v2** | 优秀 | 实验性/演进中 | 桌面端轻量极致。 | 移动端插件生态尚不成熟，相机扫码及生物识别跨 5 端一致性较差。 |
| **React Native** | 社区第三方维护 (微软/社区) | 官方支持 | Web 开发者上手快。 | 桌面端（尤其 Linux）体验与维护割裂，非官方一级支持。 |
| **Compose Multiplatform** | 支持 | Android 原生，iOS 演进中 | 现代声明式 Kotlin。 | 跨 5 端的二维码相机、文件选择器及本地加密插件生态不如 Flutter 完善。 |

### 7.2 5 端平台核心技术矩阵

针对 Flutter 方案，底层技术选型全部采用经过广泛验证且支持 5 端的稳定库，不引入任何联网依赖：

```text
┌────────────────────────────────────────────────────────────────────────┐
│               UI 表现层 (Flutter Material 3 / 自适应布局)               │
├────────────────────────────────────────────────────────────────────────┤
│ 业务层: 纯 Dart 核心 (RFC 6238 TOTP Engine / Base32 / 导入导出 YAML 编解码) │
├────────────────────────────────────────────────────────────────────────┤
│                          5 端平台功能适配矩阵                           │
│                                                                        │
│   功能模块        │   移动端 (Android / iOS)    │ 桌面端 (Win / Mac / Linux)  │
│  ─────────────┼─────────────────────────┼───────────────────────────  │
│   本地数据库      │   sqflite               │ sqflite_common_ffi (SQLite) │
│   动态验证码计算  │   crypto (纯 Dart 实现) │ crypto (纯 Dart 实现)      │
│   YAML 明文编解码 │   package:yaml (纯 Dart)│ package:yaml (纯 Dart)     │
│   二维码录入      │   mobile_scanner (相机) │ 图片文件导入 / 剪贴板识别    │
│   离线导入与导出  │   file_picker / 系统分享│ file_picker 原生文件对话框  │
│   本地安全锁      │   local_auth (指纹/Face)│ local_auth / 本地 PIN 码    │
│   窗口生命周期    │   AppLifecycleListener  │ window_manager (窗口尺寸等) │
└────────────────────────────────────────────────────────────────────────┘
```

#### 详细适配规范：

1. **本地数据库适配（SQLite 全端统一）**：
   - 移动端（Android / iOS）：使用原生编译的 `sqflite`。
   - 桌面端（Windows / macOS / Linux）：使用 `sqflite_common_ffi`，通过 `dart:ffi` 加载轻量 SQLite 动态库。
   - 业务层使用统一的 `Database` 接口，5 端共享相同的 SQL DDL、迁移脚本与事务逻辑。
2. **纯 Dart 密码学与 YAML 编解码**：
   - 采用官方团队维护的纯 Dart `crypto` 库（HMAC、SHA-1、SHA-256、SHA-512），**无任何 C/C++ 原生链接依赖**。
   - YAML 序列化与反序列化使用纯 Dart 官方维护的 `yaml` 包，零外部二进制库。
   - 在所有 5 种操作系统上均可无缝即时编译运行，杜绝跨架构跨平台编译原生二进制包的兼容性问题。
3. **二维码录入体验差异化适配**：
   - **移动端（Android / iOS）**：调用设备后置摄像头，通过 `mobile_scanner` 毫秒级扫码捕获 `otpauth://` 链接。
   - **桌面端（Windows / macOS / Linux）**：提供**“导入二维码图片”**、**“剪贴板粘贴截图识别”**以及**“直接粘贴 otpauth:// 文本”**三种录入方式。
4. **离线文件备份与恢复（File System）**：
   - 使用 `file_picker` 插件直接调起各平台原生的“保存文件（Save As）”和“打开文件（Open File）”对话框，筛选 `.yaml` / `.yml` 文件。
   - 移动端支持唤起原生系统分享面板（Share Sheet），便于将导出的 YAML 明文备份快捷保存到本地文件夹、外部 U 盘或 AirDrop 发送。
5. **本地安全锁与防窥**：
   - **iOS / macOS**：支持 Face ID / Touch ID。
   - **Android**：支持 Android BiometricPrompt（指纹/面部识别）。
   - **Windows**：支持 Windows Hello 生物识别。
   - **Linux / 兜底**：若系统未配置生物识别硬件，统一切换为纯本地 4~8 位数字 PIN 码防护。

### 7.3 响应式 UI 与人机交互规范

为了让一套代码在 5 种客户端上都具备符合平台习惯的原生体验，UI 设计遵循以下响应式准则：

- **屏幕宽度自适应**：
  - **移动端 / 紧凑窗口（宽度 < 600dp）**：采用经典单列列表布局、底部导航栏（BottomNavigationBar）、长按快捷复制、下拉刷新/搜索栏浮动。
  - **桌面端 / 宽屏（宽度 >= 600dp）**：自动切换为**左侧固定导航栏（NavigationRail）+ 主凭据网格/多列列表 + 右侧详情预览抽屉**，充分利用大屏幕显示面积。
- **桌面快捷操作支持**：
  - 支持键盘快捷键：`Ctrl / Cmd + F`（快速聚焦搜索框）、`Ctrl / Cmd + N`（新建凭据）、`Ctrl / Cmd + C`（快捷复制选中的动态码）、`Esc`（取消搜索/关闭详情）。
  - 支持调整窗口最小尺寸（如 380x600 保持小窗置顶模式），方便桌面用户边办公边查看验证码。

### 7.4 项目代码工程结构

基于 Flutter 的跨平台统一代码目录结构规划：

```text
authix/
├── docs/                        # 架构设计与开发文档
├── android/                     # Android 原生配置 (minSdkVersion 21+)
├── ios/                         # iOS 原生配置 (iOS 12.0+)
├── windows/                     # Windows 桌面原生 Runner (Win10/11)
├── macos/                       # macOS 桌面原生 Runner (10.14+)
├── linux/                       # Linux 桌面原生 Runner (Ubuntu 20.04+, GTK3)
├── lib/                         # 5 端完全共享的 Dart 源码
│   ├── main.dart                # 应用入口与全平台数据库初始化
│   ├── app.dart                 # 全局主题、路由与应用锁监听
│   ├── core/                    # 基础核心工具与平台适配抽象
│   │   ├── totp/                # RFC 6238 TOTP 算法引擎 (纯 Dart)
│   │   ├── database/            # SQLite 初始化 (移动端 vs 桌面端 FFI 抹平)
│   │   ├── backup/              # 明文 YAML 格式化生成与解析校验
│   │   └── security/            # 剪贴板清空与平台生物识别封装
│   ├── models/                  # 凭据模型 (Credential) 与配置模型
│   ├── providers/               # 状态管理 (Riverpod / BLoC)
│   └── ui/                      # 响应式 UI 组件
│       ├── screens/             # 列表主页、添加页、YAML导入导出向导、设置页
│       ├── widgets/             # 动态倒计时圆环、凭据卡片、自适应导航栏
│       └── responsive/          # 移动端 / 桌面端分流适配器
└── pubspec.yaml                 # 纯离线依赖配置清单 (crypto, sqflite, yaml, etc.)
```
