#!/usr/bin/env bash
# ==============================================================================
# Authix Linux 端自动化构建打包脚本 (Linux 宿主专用)
# 全局版本号由根目录文件 [version] 控制
# 产物统一归档输出至根目录 [release/]
# ==============================================================================

set -e

# 彩色输出定义
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

APP_NAME="authix"
DISPLAY_NAME="Authix"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RELEASE_DIR="${ROOT_DIR}/release"
VERSION_FILE="${ROOT_DIR}/version"

# 检测系统架构 (amd64 / arm64)
ARCH=$(uname -m)
case "$ARCH" in
    x86_64)  DEB_ARCH="amd64" ;;
    aarch64) DEB_ARCH="arm64" ;;
    armv7l)  DEB_ARCH="armhf" ;;
    *)       DEB_ARCH="$ARCH" ;;
esac

log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# 1. 读取并校验全局版本
if [ ! -f "$VERSION_FILE" ]; then
    log_warn "未找到根目录 version 文件，正在自动初始化为 1.0.0..."
    echo "1.0.0" > "$VERSION_FILE"
fi

APP_VERSION=$(tr -d '[:space:]' < "$VERSION_FILE")
if [ -z "$APP_VERSION" ]; then
    APP_VERSION="1.0.0"
fi

if [[ "$APP_VERSION" =~ ^([0-9]+\.[0-9]+\.[0-9]+)\+?([0-9]*)$ ]]; then
    VERSION_NAME="${BASH_REMATCH[1]}"
    BUILD_NUMBER="${BASH_REMATCH[2]}"
else
    VERSION_NAME="$APP_VERSION"
    BUILD_NUMBER=""
fi

if [ -z "$BUILD_NUMBER" ]; then
    BUILD_NUMBER=$(date +"%s" | cut -c5-10)
fi

FULL_VERSION="${VERSION_NAME}+${BUILD_NUMBER}"

# 确保 release 目录存在
mkdir -p "$RELEASE_DIR"

show_help() {
    echo "=================================================================="
    echo "  Authix Linux 构建脚本 (当前全局版本: v${VERSION_NAME} [Build ${BUILD_NUMBER}])"
    echo "=================================================================="
    echo "用法: ./build-linux.sh [选项]"
    echo ""
    echo "选项:"
    echo "  all       构建全部版本 (绿色版 .tar.gz + 安装包 .deb) [默认]"
    echo "  portable  仅构建 Linux 绿色免安装版 (.tar.gz)"
    echo "  deb       仅构建 Debian/Ubuntu 安装包 (.deb)"
    echo "  clean     清理 Flutter 编译中间缓存 (保留 release 归档)"
    echo "  help      显示此帮助信息"
    echo ""
}

clean_build() {
    log_info "正在清理构建中间缓存 (保留 release 目录下已归档的历史版本)..."
    flutter clean
    log_success "清理完成！"
}

prepare_dependencies() {
    echo -e "${CYAN}------------------------------------------------------------------${NC}"
    echo -e "${CYAN}  应用全局版本: v${VERSION_NAME} (Build ${BUILD_NUMBER})${NC}"
    echo -e "${CYAN}  统一归档输出: ${RELEASE_DIR}${NC}"
    echo -e "${CYAN}------------------------------------------------------------------${NC}"

    # 1. 检测 flutter 是否在 PATH 中，若不在则在常见目录搜索
    log_info "正在检测并适配 Flutter 编译环境..."
    if ! command -v flutter &> /dev/null; then
        COMMON_FLUTTER_DIRS=(
            "$HOME/flutter/bin"
            "$HOME/development/flutter/bin"
            "/opt/flutter/bin"
            "/snap/bin"
            "$HOME/.local/share/flutter/bin"
        )
        for dir in "${COMMON_FLUTTER_DIRS[@]}"; do
            if [ -x "$dir/flutter" ]; then
                log_info "在系统路径中自动探测到 Flutter SDK: $dir，已加入当前 PATH"
                export PATH="$dir:$PATH"
                break
            fi
        done
    fi

    if ! command -v flutter &> /dev/null; then
        log_error "未在系统环境中检测到 Flutter SDK！"
        echo ""
        echo -e "${YELLOW}==================================================================${NC}"
        echo -e "${YELLOW}【Linux 下 Flutter SDK 安装与配置指引】${NC}"
        echo -e "${YELLOW}1. 若已安装但未加入 PATH，请执行:${NC}"
        echo -e "${YELLOW}   export PATH=\"\$HOME/flutter/bin:\$PATH\"${NC}"
        echo -e "${YELLOW}2. 若尚未安装，推荐通过以下方式快速安装：${NC}"
        echo -e "${YELLOW}   - 方式一 (Snap 快速安装):${NC}"
        echo -e "${YELLOW}     sudo snap install flutter --classic${NC}"
        echo -e "${YELLOW}   - 方式二 (Git 官方推荐):${NC}"
        echo -e "${YELLOW}     git clone https://github.com/flutter/flutter.git -b stable ~/flutter${NC}"
        echo -e "${YELLOW}     echo 'export PATH=\"\$HOME/flutter/bin:\$PATH\"' >> ~/.bashrc && source ~/.bashrc${NC}"
        echo -e "${YELLOW}==================================================================${NC}"
        exit 1
    fi

    # 2. 检查 Flutter 与 Dart 版本基线
    FLUTTER_VER_OUTPUT=$(flutter --version 2>&1)
    FIRST_LINE=$(echo "$FLUTTER_VER_OUTPUT" | head -n 1)
    log_info "检测到 $FIRST_LINE"

    DART_VER=$(echo "$FLUTTER_VER_OUTPUT" | grep -oE "Dart [0-9]+\.[0-9]+\.[0-9]+" | head -n 1 | awk '{print $2}')
    if [ -n "$DART_VER" ]; then
        DART_MAJOR=$(echo "$DART_VER" | cut -d. -f1)
        DART_MINOR=$(echo "$DART_VER" | cut -d. -f2)
        if [ "$DART_MAJOR" -lt 3 ] || { [ "$DART_MAJOR" -eq 3 ] && [ "$DART_MINOR" -lt 13 ]; }; then
            log_warn "当前 Dart SDK 版本为 $DART_VER，低于工程要求的基线 Dart 3.13.5 (对应 Flutter 3.27+)！"
            log_warn "较老版本可能导致 Riverpod 3.x 或现代 Dart 语言特性编译失败。"
            echo -e "${YELLOW}【升级建议】建议执行: flutter upgrade 升级至最新的 stable 版本。${NC}"
            
            read -p "是否现在尝试自动运行 'flutter upgrade' 进行升级？(y/N): " -r choice
            if [[ "$choice" =~ ^[Yy]$ ]]; then
                log_info "正在执行 flutter upgrade..."
                flutter upgrade
            fi
        fi
    fi

    # 3. 自动确保开启 Linux 桌面构建支持
    log_info "确保开启 Linux 桌面端构建配置 (flutter config --enable-linux-desktop)..."
    flutter config --enable-linux-desktop > /dev/null 2>&1 || true

    # 4. 同步版本号至 pubspec.yaml
    if grep -q "^version:" "${ROOT_DIR}/pubspec.yaml"; then
        log_info "正在同步版本号至 pubspec.yaml -> ${FULL_VERSION}..."
        sed -i "s/^version:.*/version: ${FULL_VERSION}/" "${ROOT_DIR}/pubspec.yaml" 2>/dev/null || sed -i '' "s/^version:.*/version: ${FULL_VERSION}/" "${ROOT_DIR}/pubspec.yaml"
    fi

    # 5. 检查 Linux 原生构建基础工具链
    log_info "检查 Linux 原生构建基础工具链与依赖库..."
    MISSING_PKGS=()
    for pkg in clang cmake ninja pkg-config; do
        if ! command -v "$pkg" &> /dev/null; then
            MISSING_PKGS+=("$pkg")
        fi
    done

    # 检查 GTK3 依赖
    if command -v pkg-config &> /dev/null; then
        if ! pkg-config --exists gtk+-3.0 2>/dev/null; then
            MISSING_PKGS+=("libgtk-3-dev")
        fi
    fi

    if [ ${#MISSING_PKGS[@]} -gt 0 ]; then
        log_warn "检测到缺少以下 Linux 构建工具/开发库: ${MISSING_PKGS[*]}"
        echo -e "${YELLOW}==================================================================${NC}"
        echo -e "${YELLOW}【Linux 依赖安装指引】若构建报错，请按您的发行版执行安装：${NC}"
        echo -e "${YELLOW} - Ubuntu / Debian: sudo apt-get update && sudo apt-get install -y clang cmake ninja-build pkg-config libgtk-3-dev liblzma-dev${NC}"
        echo -e "${YELLOW} - Fedora / RHEL:   sudo dnf install -y clang cmake ninja-build pkgconf-pkg-config gtk3-devel xz-devel${NC}"
        echo -e "${YELLOW} - Arch Linux:      sudo pacman -S --needed clang cmake ninja pkgconf gtk3 xz${NC}"
        echo -e "${YELLOW}==================================================================${NC}"
    fi

    log_info "正在获取 Flutter 项目依赖..."
    flutter pub get
}

build_flutter_linux() {
    log_info "正在执行 Flutter Linux Release 构建 (v${VERSION_NAME})..."
    flutter build linux --release \
        --build-name="$VERSION_NAME" \
        --build-number="$BUILD_NUMBER"

    BUNDLE_DIR="build/linux/x64/release/bundle"
    if [ ! -d "$BUNDLE_DIR" ]; then
        BUNDLE_DIR=$(find build/linux -type d -name "bundle" | head -n 1)
    fi

    if [ -z "$BUNDLE_DIR" ] || [ ! -d "$BUNDLE_DIR" ]; then
        log_error "未找到 Linux 构建产物目录！"
        return 1
    fi
}

build_portable() {
    echo ""
    echo -e "${CYAN}==================================================================${NC}"
    echo -e "${CYAN}  正在打包 Linux 绿色免安装版 (.tar.gz)${NC}"
    echo -e "${CYAN}==================================================================${NC}"

    PORTABLE_TAR="${RELEASE_DIR}/${DISPLAY_NAME}-v${VERSION_NAME}-Linux-${DEB_ARCH}-Portable.tar.gz"
    
    TMP_PACK_DIR=$(mktemp -d /tmp/authix_pack.XXXXXX)
    cp -R "$BUNDLE_DIR" "$TMP_PACK_DIR/${APP_NAME}"
    
    tar -czf "$PORTABLE_TAR" -C "$TMP_PACK_DIR" "${APP_NAME}"
    rm -rf "$TMP_PACK_DIR"

    log_success "Linux 绿色版已生成: $PORTABLE_TAR"
}

build_deb() {
    echo ""
    echo -e "${CYAN}==================================================================${NC}"
    echo -e "${CYAN}  正在打包 Debian/Ubuntu 安装包 (.deb)${NC}"
    echo -e "${CYAN}==================================================================${NC}"

    if ! command -v dpkg-deb &> /dev/null; then
        log_warn "未检测到 dpkg-deb 工具，跳过 .deb 安装包制作。"
        return 0
    fi

    DEB_ROOT=$(mktemp -d /tmp/authix_deb.XXXXXX)
    OPT_DIR="$DEB_ROOT/opt/${APP_NAME}"
    BIN_DIR="$DEB_ROOT/usr/bin"
    APP_DESKTOP_DIR="$DEB_ROOT/usr/share/applications"
    ICON_DIR="$DEB_ROOT/usr/share/icons/hicolor/128x128/apps"
    CONTROL_DIR="$DEB_ROOT/DEBIAN"

    mkdir -p "$OPT_DIR" "$BIN_DIR" "$APP_DESKTOP_DIR" "$ICON_DIR" "$CONTROL_DIR"

    # 1. 复制运行时程序
    cp -R "$BUNDLE_DIR"/* "$OPT_DIR/"

    # 2. 创建软链接启动器
    cat << 'EOF' > "$BIN_DIR/authix"
#!/usr/bin/env bash
exec /opt/authix/authix "$@"
EOF
    chmod +x "$BIN_DIR/authix"

    # 3. 生成桌面启动图标 entry
    cat << EOF > "$APP_DESKTOP_DIR/authix.desktop"
[Desktop Entry]
Name=Authix
Comment=纯离线多端密码管理器与 TOTP 二次验证器
Exec=/usr/bin/authix
Icon=authix
Terminal=false
Type=Application
Categories=Utility;Security;
StartupWMClass=authix
EOF

    # 4. 图标复制
    if [ -f "linux/flutter/assets/icon.png" ]; then
        cp "linux/flutter/assets/icon.png" "$ICON_DIR/authix.png"
    elif [ -f "macos/Runner/Assets.xcassets/AppIcon.appiconset/app_icon_128.png" ]; then
        cp "macos/Runner/Assets.xcassets/AppIcon.appiconset/app_icon_128.png" "$ICON_DIR/authix.png"
    fi

    # 5. 生成 DEBIAN/control 元数据
    cat << EOF > "$CONTROL_DIR/control"
Package: ${APP_NAME}
Version: ${VERSION_NAME}
Architecture: ${DEB_ARCH}
Maintainer: Authix Developer <contact@authix.local>
Section: utils
Priority: optional
Depends: libc6, libgtk-3-0
Description: Authix - 纯离线现代密码与凭据管理器 (v${VERSION_NAME})
 零网络依赖、纯本地 SQLite 存储、支持 TOTP、密码、SSH 私钥及 YAML 规范离线备份。
EOF

    # 6. 生成并打包 .deb
    DEB_OUTPUT="${RELEASE_DIR}/${DISPLAY_NAME}-v${VERSION_NAME}-Linux-${DEB_ARCH}.deb"
    dpkg-deb --build --root-owner-group "$DEB_ROOT" "$DEB_OUTPUT" > /dev/null
    rm -rf "$DEB_ROOT"

    log_success "Linux 安装包 (.deb) 已生成: $DEB_OUTPUT"
}

# ------------------------------------------------------------------------------
# 主逻辑入口
# ------------------------------------------------------------------------------
TARGET="${1:-all}"

case "$TARGET" in
    clean)
        clean_build
        exit 0
        ;;
    help|--help|-h)
        show_help
        exit 0
        ;;
    portable)
        prepare_dependencies
        build_flutter_linux
        build_portable
        ;;
    deb)
        prepare_dependencies
        build_flutter_linux
        build_deb
        ;;
    all)
        prepare_dependencies
        build_flutter_linux
        build_portable
        build_deb
        ;;
    *)
        log_error "未知选项: $TARGET"
        show_help
        exit 1
        ;;
esac

echo ""
echo -e "${GREEN}==================================================================${NC}"
echo -e "${GREEN}  Linux 打包完成！产物输出至 [release/] 目录:${NC}"
echo -e "${GREEN}  $RELEASE_DIR${NC}"
echo -e "${GREEN}==================================================================${NC}"
ls -lh "$RELEASE_DIR"
