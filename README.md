<div align="center">

<img src="assets/icons/app_icon_rounded.png" alt="Authix Logo" width="120" />

# Authix

**🔒 优雅、安全的纯本地离线密码管理器与 2FA/TOTP 双重验证器**

<p align="center">
  <a href="README.md">简体中文</a> •
  <a href="README_EN.md">English</a> •
  <a href="README_ZH-TW.md">繁體中文</a>
</p>

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![Flutter](https://img.shields.io/badge/Flutter-3.x+-02569B?logo=flutter&logoColor=white)](https://flutter.dev)
[![Platform](https://img.shields.io/badge/Platform-Android%20|%20iOS%20|%20macOS%20|%20Windows%20|%20Linux%20|%20Web-lightgrey.svg)]()
[![Offline First](https://img.shields.io/badge/Offline--First-100%25-success)]()

[功能特性](#-功能特性) • [安装下载](#-下载与安装) • [本地编译构建](#-本地编译构建) • [安全与隐私](#-安全与隐私承诺) • [开源协议](#-开源许可)

</div>

---

## 📖 项目简介

**Authix** 是一款专为注重个人隐私、追求极致掌控感与极客体验的用户打造的**纯本地、零云端依赖的跨平台数字凭证保险箱**。

现今主流的密码管理工具普遍强依赖云端服务器或订阅制收费，存在服务端被脱库泄露、账号被封禁或断网时无法使用的隐患。Authix 彻底告别繁琐沉重的服务端架构，回归纯单机、零网络权限、即开即用、数据完全自由流通的工具本质。

无论是在移动端还是桌面端，**数据永远完全留在你自己的设备上**。

---

## ✨ 核心特性

- **🛡️ 100% 纯本地离线（Zero Network）**：
  - 应用不申请任何联网权限，物理层面杜绝任何数据泄露与隐私遥测。
  - 零注册、零登录，即开即用。
- **⏱️ 动态双重身份验证器（TOTP / 2FA）**：
  - 遵循 RFC 6238 标准，支持 30s/60s 动态步长与 SHA1 / SHA256 / SHA512 算法。
  - 炫彩动态倒计时圆环，毫秒级精准更新，一键快速复制。
  - **独创原生支持「2FA 应急备用恢复码（Recovery Codes）」清单**，标记划扣已使用状态，彻底告别二次验证丢失风险。
- **🔑 账号与密码管理**：
  - 网站与 App 账户密码集中安全存储。
  - 内置高强度自定义密码生成器（支持大写、小写、数字、特殊符号、易读模式）。
  - 支持直接绑定关联 TOTP，实现一站式登录体验。
- **💻 服务器连接私钥（SSH Keys）**：
  - 支持 OpenSSH、PEM、Ed25519、RSA 等各类格式私钥。
  - 自动解析并计算 SHA256 公钥指纹。
  - 快速生成并一键复制标准终端连接指令：`ssh user@host -i ...`。
- **⚡ 开发者 API 密钥与令牌（API Keys / Tokens）**：
  - 统一归档 OpenAI、Claude、GitHub PAT、各云厂商 AccessKey。
  - 支持有效期监控与到期提醒。
- **🪙 加密资产冷钱包（Crypto Wallets）**：
  - 支持 BIP-39 标准 12/24 位助记词。
  - 专属「防窥网格布局」，点击单独显示对应序号单词，防止身后窥屏。
- **💳 卡证档案与安全备忘录**：
  - 银行卡/信用卡信息存储，内置 **Luhn 算法** 自动校验卡号有效性，CVV 安全掩码保护。
  - 证件信息（身份证、护照、驾照）快速检索与归档。
  - 结构化机密备忘录（Wi-Fi 密码、软件激活码、环境配置等）。
- **🔒 纯本地安全锁**：
  - 支持生物识别（指纹 / Face ID / Touch ID）以及本地 6 位安全 PIN 码。
  - 离开应用自动锁定，防截屏防窥探。
- **📄 人类高可读性的数据备份（YAML 格式）**：
  - 独创支持以标准 **YAML 格式** 进行明文离线导出与恢复。
  - 缩进清晰、多行文本排版优雅，数据完全归用户所有，可在任意文本编辑器中自由查看与迁移，拒绝格式绑定。

---

## 📦 下载与安装

前往仓库的 [Releases 页面](https://github.com/zuo000/authix/releases) 下载适用于你操作系统的预编译安装包：

| 操作系统 | 安装包文件 | 说明 |
| :--- | :--- | :--- |
| **Android** | `authix-android-release.apk` | 纯离线安装包（无需 Google Play 服务） |
| **Windows** | `authix-windows-x64.zip` | 绿色解压即用版 / 可配合快捷方式运行 |
| **macOS** | `authix-macos-universal.zip` | 原生通用二进制（支持 Apple Silicon & Intel） |
| **Linux** | `authix-linux-x64.tar.gz` | Linux x86_64 二进制归档包 |
| **Web** | `authix-web.zip` | 离线纯静态 Web 部署包 |

---

## 🛠️ 本地编译构建

本项目保留了完整的全平台本地编译脚本，用户也可自行从源码构建任意平台的发布包：

### 1. 环境准备
- 安装 [Flutter SDK](https://flutter.dev/docs/get-started/install) (>= 3.13.5)
- 获取依赖：
  ```bash
  flutter pub get
  ```

### 2. 使用内置自动化构建脚本
- **macOS / Android 构建（macOS 宿主）**：
  ```bash
  chmod +x build.sh
  ./build.sh --help          # 查看所有构建选项
  ./build.sh android         # 构建 Android APK
  ./build.sh macos           # 构建 macOS 应用包
  ```
- **Linux 构建（Ubuntu/Debian 宿主）**：
  ```bash
  chmod +x build-linux.sh
  ./build-linux.sh all       # 一键打包 Linux 二进制
  ```
- **Windows 构建（Windows 宿主）**：
  ```powershell
  .\build.ps1 -Target windows
  ```
所有编译产物将自动输出并归档在根目录的 `release/` 文件夹中。


---

## 🔐 安全与隐私承诺

1. **零网络权限**：Android 清单、iOS 及各平台配置均未申请任何联网权限，在操作系统级限制网络出入。
2. **本地硬件安全**：生物识别与 PIN 鉴权完全依托设备本地的安全隔离区（Secure Enclave / Keystore / Keyring）。
3. **开源透明**：所有核心逻辑、加密算法、数据库读写代码完全开源，接受社区审查。

---

## 📄 开源许可

本项目基于 [MIT License](LICENSE) 开源。
