# ==============================================================================
# Authix Windows 端自动化构建打包脚本 (PowerShell)
# 全局版本号由根目录文件 [version] 控制
# 产物统一归档输出至根目录 [release\]
# ==============================================================================

[CmdletBinding()]
param (
    [ValidateSet('all', 'portable', 'installer', 'clean')]
    [string]$Target = 'all'
)

$ErrorActionPreference = "Stop"

$AppName = "authix"
$DisplayName = "Authix"
$RootDir = $PSScriptRoot
$ReleaseDir = Join-Path -Path $RootDir -ChildPath "release"
$VersionFile = Join-Path -Path $RootDir -ChildPath "version"

function Log-Info ($msg) {
    Write-Host "[INFO] $msg" -ForegroundColor Cyan
}

function Log-Success ($msg) {
    Write-Host "[SUCCESS] $msg" -ForegroundColor Green
}

function Log-Warn ($msg) {
    Write-Host "[WARN] $msg" -ForegroundColor Yellow
}

function Log-Error ($msg) {
    Write-Host "[ERROR] $msg" -ForegroundColor Red
}

# 1. 读取并校验全局版本
if (-not (Test-Path $VersionFile)) {
    Log-Warn "未找到 version 文件，初始化为 1.0.0..."
    Set-Content -Path $VersionFile -Value "1.0.0" -Encoding UTF8
}

$RawVersion = (Get-Content -Path $VersionFile -Raw).Trim()
if ([string]::IsNullOrWhiteSpace($RawVersion)) {
    $RawVersion = "1.0.0"
}

# 解析主版本号和构建号
$VersionName = $RawVersion
$BuildNumber = (Get-Date -UFormat %s).Substring(4, 6)
if ($RawVersion -match '^([0-9]+\.[0-9]+\.[0-9]+)\+?([0-9]*)$') {
    $VersionName = $matches[1]
    if (-not [string]::IsNullOrWhiteSpace($matches[2])) {
        $BuildNumber = $matches[2]
    }
}

# 确保 release 目录存在
if (-not (Test-Path $ReleaseDir)) {
    New-Item -ItemType Directory -Path $ReleaseDir | Out-Null
}

if ($Target -eq 'clean') {
    Log-Info "正在清理构建中间缓存 (保留 release 目录下已归档的历史版本)..."
    flutter clean
    Log-Success "清理完成！"
    exit 0
}

Write-Host "------------------------------------------------------------------" -ForegroundColor Cyan
Write-Host "  应用全局版本: v$VersionName (Build $BuildNumber)" -ForegroundColor Cyan
Write-Host "  统一归档输出: $ReleaseDir" -ForegroundColor Cyan
Write-Host "------------------------------------------------------------------" -ForegroundColor Cyan

# 2. 检查与自适应配置 Flutter 编译环境
function Check-And-Setup-Flutter-Environment {
    Log-Info "正在检测并适配 Flutter 编译环境..."

    # 2.1 检测 flutter 是否在 PATH 中，若不在则在常见安装路径搜索
    $FlutterCmd = Get-Command flutter -ErrorAction SilentlyContinue
    if (-not $FlutterCmd) {
        $CommonFlutterDirs = @(
            "C:\flutter\bin",
            "C:\src\flutter\bin",
            "$env:USERPROFILE\flutter\bin",
            "$env:LOCALAPPDATA\flutter\bin",
            "$env:ProgramFiles\flutter\bin"
        )
        foreach ($dir in $CommonFlutterDirs) {
            if (Test-Path (Join-Path $dir "flutter.bat")) {
                Log-Info "在系统路径中自动探测到 Flutter SDK: $dir，已加入当前会话 PATH"
                $env:PATH = "$dir;" + $env:PATH
                $FlutterCmd = Get-Command flutter -ErrorAction SilentlyContinue
                break
            }
        }
    }

    if (-not $FlutterCmd) {
        Log-Error "未在系统环境中检测到 Flutter SDK！"
        Write-Host ""
        Write-Host "==================================================================" -ForegroundColor Yellow
        Write-Host "【Flutter SDK 安装与配置指引】" -ForegroundColor Yellow
        Write-Host "1. 若已安装但未加入环境变量，请将 Flutter 的 bin 目录 (如 C:\src\flutter\bin) 添加至系统 PATH。" -ForegroundColor Yellow
        Write-Host "2. 若尚未安装，推荐通过以下方式快速安装：" -ForegroundColor Yellow
        Write-Host "   - 方式一 (推荐): 在 Windows 终端运行: winget install Google.Flutter" -ForegroundColor Yellow
        Write-Host "   - 方式二: 前往 Flutter 官网下载解压包: https://docs.flutter.dev/get-started/install/windows" -ForegroundColor Yellow
        Write-Host "==================================================================" -ForegroundColor Yellow
        exit 1
    }

    # 2.2 检测 Flutter 与 Dart 版本基线
    $FlutterVersionOutput = & flutter --version 2>&1 | Out-String
    $FirstLine = ($FlutterVersionOutput -split "`r?`n")[0]
    Log-Info "检测到 $FirstLine"

    $RequiredDartMajor = 3
    $RequiredDartMinor = 13
    $NeedUpgrade = $false

    if ($FlutterVersionOutput -match 'Dart\s+([0-9]+)\.([0-9]+)\.([0-9]+)') {
        $CurrentMajor = [int]$matches[1]
        $CurrentMinor = [int]$matches[2]
        if ($CurrentMajor -lt $RequiredDartMajor -or ($CurrentMajor -eq $RequiredDartMajor -and $CurrentMinor -lt $RequiredDartMinor)) {
            $NeedUpgrade = $true
            Log-Warn "当前 Dart SDK 版本为 $($matches[1]).$($matches[2]).$($matches[3])，低于工程要求的基线 Dart 3.13.5 (对应 Flutter 3.27+)！"
        }
    }

    if ($NeedUpgrade) {
        Log-Warn "当前 Flutter / Dart 版本偏旧，可能导致 Riverpod 3.x、现代模式匹配等语法编译失败。"
        Write-Host "建议执行: flutter upgrade 升级至最新的稳定版 (stable)。" -ForegroundColor Yellow
        $choice = Read-Host "是否现在尝试自动运行 'flutter upgrade' 进行升级？(y/N)"
        if ($choice -eq 'y' -or $choice -eq 'Y') {
            Log-Info "正在执行 flutter upgrade..."
            & flutter upgrade
        }
    }

    # 2.3 确保已启用 Windows 桌面端构建支持
    Log-Info "确保开启 Windows 桌面构建配置 (flutter config --enable-windows-desktop)..."
    & flutter config --enable-windows-desktop | Out-Null

    # 2.4 检查 Visual Studio C++ 工具链
    $VsWhere = "${env:ProgramFiles(x86)}\Microsoft Visual Studio\Installer\vswhere.exe"
    if (Test-Path $VsWhere) {
        $VsPath = & $VsWhere -latest -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath
        if (-not $VsPath) {
            Log-Warn "未检测到安装了「使用 C++ 的桌面开发」的 Visual Studio 工具链！"
            Log-Warn "如果构建 Windows 产物失败，请在 Visual Studio Installer 中勾选「Desktop development with C++」工作负载。"
        }
    }
}

Check-And-Setup-Flutter-Environment

# 3. 同步版本至 pubspec.yaml
$PubspecPath = Join-Path -Path $RootDir -ChildPath "pubspec.yaml"
if (Test-Path $PubspecPath) {
    Log-Info "正在同步版本号至 pubspec.yaml -> $VersionName+$BuildNumber..."
    (Get-Content -Path $PubspecPath) -replace '^version:.*', "version: $VersionName+$BuildNumber" | Set-Content -Path $PubspecPath -Encoding UTF8
}

# 4. 编译 Flutter Windows Release
Log-Info "正在拉取依赖并编译 Flutter Windows Release..."
flutter pub get
flutter build windows --release --build-name=$VersionName --build-number=$BuildNumber

$BuildRunnerDir = Join-Path -Path $RootDir -ChildPath "build\windows\x64\runner\Release"
if (-not (Test-Path $BuildRunnerDir)) {
    $BuildRunnerDir = Join-Path -Path $RootDir -ChildPath "build\windows\runner\Release"
}

if (-not (Test-Path "$BuildRunnerDir\$AppName.exe")) {
    Log-Error "未找到构建产物: $BuildRunnerDir\$AppName.exe"
    exit 1
}

# 4. 打包绿色版 (Portable .zip)
if ($Target -eq 'all' -or $Target -eq 'portable') {
    Log-Info "正在打包 Windows 绿色免安装版 (.zip)..."
    $ZipOutput = Join-Path -Path $ReleaseDir -ChildPath "$DisplayName-v$VersionName-Windows-Portable.zip"

    Compress-Archive -Path "$BuildRunnerDir\*" -DestinationPath $ZipOutput -Force
    Log-Success "Windows 绿色版生成成功: $ZipOutput"
}

# 5. 打包安装包 (Installer .exe)
if ($Target -eq 'all' -or $Target -eq 'installer') {
    Log-Info "正在准备生成 Windows 安装包..."

    $IssPath = Join-Path -Path $RootDir -ChildPath "build\installer.iss"
    $InstallerOutput = "$DisplayName-v$VersionName-Windows-Installer"

    $IssContent = @"
#define MyAppName "$DisplayName"
#define MyAppVersion "$VersionName"
#define MyAppPublisher "Authix OpenSource"
#define MyAppURL "https://github.com/zuo000/authix"
#define MyAppExeName "$AppName.exe"
#define MySourceDir "$BuildRunnerDir"

[Setup]
AppId={{5B2A0F8C-1681-4C5D-808E-04FA9B300F29}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppPublisher={#MyAppPublisher}
AppPublisherURL={#MyAppURL}
AppSupportURL={#MyAppURL}
AppUpdatesURL={#MyAppURL}
DefaultDirName={autopf}\{#MyAppName}
DisableProgramGroupPage=yes
OutputDir=$ReleaseDir
OutputBaseFilename=$InstallerOutput
Compression=lzma
SolidCompression=yes
WizardStyle=modern

[Languages]
Name: "chinesesimplified"; MessagesFile: "compiler:Languages\ChineseSimplified.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: unchecked

[Files]
Source: "{#MySourceDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{autoprograms}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"
Name: "{autodesktop}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"; Tasks: desktopicon

[Run]
Filename: "{app}\{#MyAppExeName}"; Description: "{cm:LaunchProgram,{#StringChange(MyAppName, '&', '&&')}}"; Flags: nowait postinstall skipifsilent
"@

    Set-Content -Path $IssPath -Value $IssContent -Encoding UTF8

    $IsccPaths = @(
        "ISCC.exe",
        "${env:ProgramFiles(x86)}\Inno Setup 6\ISCC.exe",
        "${env:ProgramFiles}\Inno Setup 6\ISCC.exe",
        "${env:LOCALAPPDATA}\Programs\Inno Setup 6\ISCC.exe"
    )

    $IsccFound = $null
    foreach ($p in $IsccPaths) {
        if (Get-Command $p -ErrorAction SilentlyContinue) {
            $IsccFound = $p
            break
        } elseif (Test-Path $p) {
            $IsccFound = $p
            break
        }
    }

    if ($IsccFound) {
        Log-Info "调用 Inno Setup 编译安装向导程序: $IsccFound"
        & $IsccFound $IssPath
        Log-Success "Windows 安装包生成成功: $ReleaseDir\$InstallerOutput.exe"
    } else {
        Log-Warn "未在系统检测到 Inno Setup (ISCC.exe)。"
        Log-Warn "已为您生成标准安装脚本: $IssPath"
        Log-Warn "安装 Inno Setup 6 (https://jrsoftware.org/isdl.php) 后重新运行本脚本即可自动生成 .exe 安装包。"
    }
}

Write-Host ""
Write-Host "==================================================================" -ForegroundColor Green
Write-Host "  打包完成！产物输出目录:" -ForegroundColor Green
Write-Host "  $ReleaseDir" -ForegroundColor Green
Write-Host "==================================================================" -ForegroundColor Green
Get-ChildItem -Path $ReleaseDir | Select-Object Name, Length, LastWriteTime | Format-Table -AutoSize
