<div align="center">

<img src="assets/icons/app_icon_rounded.png" alt="Authix Logo" width="120" />

# Authix

**🔒 A secure, 100% offline, cross-platform password manager and 2FA/TOTP authenticator vault.**

<p align="center">
  <a href="README.md">简体中文</a> •
  <a href="README_EN.md">English</a> •
  <a href="README_ZH-TW.md">繁體中文</a>
</p>

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![Flutter](https://img.shields.io/badge/Flutter-3.x+-02569B?logo=flutter&logoColor=white)](https://flutter.dev)
[![Platform](https://img.shields.io/badge/Platform-Android%20|%20iOS%20|%20macOS%20|%20Windows%20|%20Linux%20|%20Web-lightgrey.svg)]()
[![Offline First](https://img.shields.io/badge/Offline--First-100%25-success)]()

[Features](#-key-features) • [Downloads](#-downloads--releases) • [Build from Source](#-build-from-source) • [CI/CD Automation](#-github-actions-automation) • [Security & Privacy](#-security--privacy-commitments) • [License](#-license)

</div>

---

## 📖 Introduction

**Authix** is an **offline-first, zero-cloud, privacy-focused cross-platform digital credentials vault** built for users who prioritize total data sovereignty and geek-level security.

Most mainstream password managers today depend heavily on cloud services or recurring subscriptions, posing real risks of third-party server breaches, account lockouts, or unavailability during offline outages. Authix completely eliminates remote server infrastructure, embracing a pure standalone utility philosophy: zero network permissions, instant launch, and full data portability.

Whether on mobile or desktop, **your data remains strictly on your own physical devices**.

---

## ✨ Key Features

- **🛡️ 100% Offline-First (Zero Network Dependency)**:
  - The application requests **zero internet permissions**, completely eliminating data leakage or telemetry risks at the OS sandbox level.
  - No sign-ups, no logins, zero trackers. Ready to use immediately out of the box.
- **⏱️ Dynamic Two-Factor Authenticator (TOTP / 2FA)**:
  - Adheres strictly to RFC 6238, supporting 30s/60s time steps and SHA1, SHA256, and SHA512 algorithms.
  - High-precision countdown ring animations with one-tap code copying.
  - **Native 2FA Emergency Recovery Codes Management**: Keep track of remaining backup codes and mark used ones, eliminating the anxiety of 2FA lockouts.
- **🔑 Password & Login Credential Vault**:
  - Securely store accounts, usernames, and passwords for websites and applications.
  - Built-in customizable high-entropy password generator (uppercase, lowercase, digits, symbols, ambiguous filter).
  - Link TOTP tokens directly to credentials for unified one-stop logins.
- **💻 Server SSH Keys**:
  - Support for OpenSSH, PEM, Ed25519, and RSA private keys.
  - Automatic SHA256 public key fingerprint calculation.
  - Generate and copy standard terminal connection commands (`ssh user@host -i ...`) in one tap.
- **⚡ Developer API Keys & Tokens**:
  - Centralized archive for OpenAI, Claude, GitHub PATs, and cloud provider access keys.
  - Integrated expiration date tracking and renewal alerts.
- **🪙 Crypto Asset Wallets**:
  - Support for standard BIP-39 12/24-word recovery seeds.
  - Privacy-preserving grid view with individual tap-to-reveal word masking to protect against shoulder surfing.
- **💳 Payment Cards & Identity Documents**:
  - Store credit/debit cards with automated **Luhn algorithm** validation and masked CVV protection.
  - Quick-access personal IDs (Passports, Driver's Licenses, National IDs).
  - Encrypted secure notes with dynamic key-value pairs (Wi-Fi passwords, software license keys, config snippets).
- **🔒 Local Hardware-Backed Security Lock**:
  - Biometric authentication (Face ID, Touch ID, Fingerprint) and local 6-digit Master PIN.
  - Automatic lock upon app suspension with screenshot and preview masking.
- **📄 Human-Readable Data Portability (YAML Format)**:
  - First-class support for plaintext offline backup and restore in clean **YAML** format.
  - Clean indentation and elegant multi-line string handling. You can inspect, modify, and migrate your data in any text editor without proprietary lock-in.

---

## 📦 Downloads & Releases

Check out the [GitHub Releases](https://github.com/zuo000/authix/releases) page for precompiled releases across all major operating systems:

| Platform | Asset File | Description |
| :--- | :--- | :--- |
| **Android** | `authix-android-release.apk` | Offline standalone APK (no Google Play Services required) |
| **Windows** | `authix-windows-x64.zip` | Portable zero-install zip package |
| **macOS** | `authix-macos-universal.zip` | Universal binary (Apple Silicon & Intel) |
| **Linux** | `authix-linux-x64.tar.gz` | Linux x86_64 desktop binary tarball |
| **Web** | `authix-web.zip` | Offline static Web bundle |

---

## 🛠️ Build from Source

Authix maintains unified native build scripts for all host environments:

### 1. Prerequisites
- [Flutter SDK](https://flutter.dev/docs/get-started/install) (>= 3.13.5)
- Install project dependencies:
  ```bash
  flutter pub get
  ```

### 2. Run Local Build Scripts
- **macOS / Android (macOS Host)**:
  ```bash
  chmod +x build.sh
  ./build.sh --help          # View all build flags
  ./build.sh android         # Compile Android APK
  ./build.sh macos           # Compile macOS Application Bundle
  ```
- **Linux (Ubuntu/Debian Host)**:
  ```bash
  chmod +x build-linux.sh
  ./build-linux.sh all       # Package native Linux bundle
  ```
- **Windows (PowerShell)**:
  ```powershell
  .\build.ps1 -Target windows
  ```
Compiled binaries will be automatically collected under the `release/` directory.

---

## 🤖 GitHub Actions Automation

This repository includes a multi-platform CI/CD workflow ([`.github/workflows/release.yml`](.github/workflows/release.yml)):

1. **Tag-Triggered Releases**: Pushing any tag matching `v*` (e.g. `v1.0.0`) automatically compiles binaries across Android, Windows, macOS, Linux, and Web, creating a full GitHub Release.
2. **Manual Trigger**: You can also manually trigger builds via **Actions -> Build & Release -> Run workflow** on GitHub.

---

## 🔐 Security & Privacy Commitments

1. **Zero Network Permissions**: Network access permissions are omitted from Android manifests, iOS entitlements, and desktop configs.
2. **Hardware-Isolated Storage**: PIN and biometric authentications rely on local secure storage and platform-native keystores.
3. **Open & Transparent**: All cryptography routines, local database interactions, and UI source code are open for public audit.

---

## 📄 License

This project is licensed under the [MIT License](LICENSE).
