<div align="center">

<img src="assets/icons/app_icon_rounded.png" alt="Authix Logo" width="120" />

# Authix

**🔒 優雅、安全的全離線密碼管理器與 2FA/TOTP 雙重驗證器**

<p align="center">
  <a href="README.md">简体中文</a> •
  <a href="README_EN.md">English</a> •
  <a href="README_ZH-TW.md">繁體中文</a>
</p>

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![Flutter](https://img.shields.io/badge/Flutter-3.x+-02569B?logo=flutter&logoColor=white)](https://flutter.dev)
[![Platform](https://img.shields.io/badge/Platform-Android%20|%20iOS%20|%20macOS%20|%20Windows%20|%20Linux%20|%20Web-lightgrey.svg)]()
[![Offline First](https://img.shields.io/badge/Offline--First-100%25-success)]()

[功能特點](#-功能特點) • [安裝下載](#-下載與安裝) • [本地編譯構建](#-本地編譯構建) • [安全與隱私](#-安全與隱私承諾) • [開源授權](#-開源授權)

</div>

---

## 📖 專案簡介

**Authix** 是一款專為注重個人隱私、追求極致掌控感與極客體驗的用戶打造的**純本機、零雲端依賴的跨平台數位憑證保險箱**。

現今主流的密碼管理工具普遍高度依賴雲端伺服器或訂閱制收費，存在伺服器資料外洩、帳號被封鎖或離線時無法使用的隱患。Authix 徹底告別繁瑣沉重的伺服器架構，回歸純單機、零網路權限、即開即用、資料完全自由流通的工具本質。

無論是在行動裝置還是桌面端，**資料永遠只保留在您自己的裝置上**。

---

## ✨ 功能特點

- **🛡️ 100% 純本機離線（Zero Network）**：
  - 應用程式不申請任何連網權限，物理層面杜絕任何資料外洩與隱私遙測。
  - 免註冊、免登入，即開即用。
- **⏱️ 動態雙重身分驗證器（TOTP / 2FA）**：
  - 遵循 RFC 6238 標準，支援 30s/60s 動態步長與 SHA1 / SHA256 / SHA512 演算法。
  - 炫彩動態倒數圓環，毫秒級精準更新，一鍵快速複製。
  - **原生支援「2FA 緊急備用復原碼（Recovery Codes）」清單**，標記已使用狀態，徹底擺脫雙重驗證遺失風險。
- **🔑 帳號與密碼管理**：
  - 網站與 App 帳號密碼集中安全儲存。
  - 內建高強度自訂密碼產生器（支援大寫、小寫、數字、特殊符號、易讀模式）。
  - 支援直接綁定關聯 TOTP，實現一站式登入體驗。
- **💻 伺服器連線私密金鑰（SSH Keys）**：
  - 支援 OpenSSH、PEM、Ed25519、RSA 等各類格式私密金鑰。
  - 自動解析並計算 SHA256 公開金鑰指紋。
  - 快速產生並一鍵複製標準終端機連線指令：`ssh user@host -i ...`。
- **⚡ 開發者 API 金鑰與權杖（API Keys / Tokens）**：
  - 統一歸檔 OpenAI、Claude、GitHub PAT、各雲端廠商 AccessKey。
  - 支援有效期監控與到期提醒。
- **🪙 加密資產冷錢包（Crypto Wallets）**：
  - 支援 BIP-39 標準 12/24 位助記詞。
  - 專屬「防窺格狀布局」，點擊單獨顯示對應序號單字，防止身後偷窺。
- **💳 卡證檔案與安全備忘錄**：
  - 銀行卡/信用卡資訊儲存，內建 **Luhn 演算法** 自動校驗卡號有效性，CVV 安全遮罩防護。
  - 證件資訊（身分證、護照、駕照）快速檢索與歸檔。
  - 結構化機密備忘錄（Wi-Fi 密碼、軟體授權序號、環境設定等）。
- **🔒 純本機安全鎖**：
  - 支援生物辨識（指紋 / Face ID / Touch ID）以及本機 6 位元安全 PIN 碼。
  - 離開應用程式自動鎖定，防截圖防偷窺。
- **📄 高度可讀的資料備份（YAML 格式）**：
  - 首創支援以標準 **YAML 格式** 進行純文字離線匯出與還原。
  - 縮排清晰、多行文字排版優雅，資料完全歸使用者所有，可在任意文字編輯器中自由檢視與遷移，拒絕專有格式綁定。

---

## 📦 下載與安裝

前往專案的 [Releases 頁面](https://github.com/zuo000/authix/releases) 下載適用於您作業系統的預編譯安裝套件：

| 作業系統 | 安裝套件檔案 | 說明 |
| :--- | :--- | :--- |
| **Android** | `authix-android-release.apk` | 全離線安裝包（無需 Google Play 服務） |
| **Windows** | `authix-windows-x64.zip` | 綠色解壓即用版 |
| **macOS** | `authix-macos-universal.zip` | 原生通用二進位檔（支援 Apple Silicon & Intel） |
| **Linux** | `authix-linux-x64.tar.gz` | Linux x86_64 二進位歸檔套件 |
| **Web** | `authix-web.zip` | 離線純靜態 Web 部署套件 |

---

## 🛠️ 本地編譯構建

本專案保留了完整的全平台本地編譯指令碼，亦可自行從原始碼建置任意平台的發布套件：

### 1. 環境準備
- 安裝 [Flutter SDK](https://flutter.dev/docs/get-started/install) (>= 3.13.5)
- 取得依賴套件：
  ```bash
  flutter pub get
  ```

### 2. 使用內建自動化建置指令碼
- **macOS / Android 建置（macOS 主機）**：
  ```bash
  chmod +x build.sh
  ./build.sh --help          # 檢視所有構建選項
  ./build.sh android         # 構建 Android APK
  ./build.sh macos           # 構建 macOS 應用套件
  ```
- **Linux 建置（Ubuntu/Debian 主機）**：
  ```bash
  chmod +x build-linux.sh
  ./build-linux.sh all       # 一鍵打包 Linux 二進位檔
  ```
- **Windows 建置（Windows 主機）**：
  ```powershell
  .\build.ps1 -Target windows
  ```
所有編譯產物將自動輸出並歸檔在根目錄的 `release/` 資料夾中。


---

## 🔐 安全與隱私承諾

1. **零網路權限**：Android 清單、iOS 及各平台設定均未申請任何連網權限，在作業系統層級限制網路出入。
2. **本機硬體安全**：生物辨識與 PIN 驗證完全依託裝置本機的安全隔離區（Secure Enclave / Keystore / Keyring）。
3. **開源透明**：所有核心邏輯、加密演算法、資料庫讀寫程式碼完全開源，接受社群審查。

---

## 📄 開源授權

本專案基於 [MIT License](LICENSE) 授權開源。
