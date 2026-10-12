#!/usr/bin/env bash
# ==============================================================================
# Authix 多端自动化构建打包脚本 (macOS 宿主专用)
# 全局版本号由根目录文件 [version] 控制
# 产物统一归档输出至根目录 [release/]
# ==============================================================================

set -e

# 默认优先启用官方国内高速镜像加速依赖拉取
export PUB_HOSTED_URL="${PUB_HOSTED_URL:-https://pub.flutter-io.cn}"
export FLUTTER_STORAGE_BASE_URL="${FLUTTER_STORAGE_BASE_URL:-https://storage.flutter-io.cn}"

# 彩色输出定义
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

APP_NAME="authix"
DISPLAY_NAME="Authix"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RELEASE_DIR="${ROOT_DIR}/release"
VERSION_FILE="${ROOT_DIR}/version"

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

# 1. 读取并校验全局版本文件
if [ ! -f "$VERSION_FILE" ]; then
    log_warn "未找到根目录 version 文件，正在自动初始化为 1.0.0..."
    echo "1.0.0" > "$VERSION_FILE"
fi

# 过滤空白与换行
APP_VERSION=$(tr -d '[:space:]' < "$VERSION_FILE")
if [ -z "$APP_VERSION" ]; then
    APP_VERSION="1.0.0"
fi

# 解析版本号与构建号（兼容 1.0.0 或 1.0.0+10 格式）
if [[ "$APP_VERSION" =~ ^([0-9]+\.[0-9]+\.[0-9]+)\+?([0-9]*)$ ]]; then
    VERSION_NAME="${BASH_REMATCH[1]}"
    BUILD_NUMBER="${BASH_REMATCH[2]}"
else
    VERSION_NAME="$APP_VERSION"
    BUILD_NUMBER=""
fi

if [ -z "$BUILD_NUMBER" ]; then
    BUILD_NUMBER=$(date +"%s" | cut -c5-10) # 自动基于时间戳生成构建编号
fi

FULL_VERSION="${VERSION_NAME}+${BUILD_NUMBER}"

# 确保 release 目录存在
mkdir -p "$RELEASE_DIR"

show_help() {
    echo "=================================================================="
    echo "  Authix 构建脚本 (当前全局版本: v${VERSION_NAME} [Build ${BUILD_NUMBER}])"
    echo "=================================================================="
    echo "用法: ./build.sh [选项]"
    echo ""
    echo "选项:"
    echo "  all      构建所有目标 (macOS, Android, iOS, Web) [默认]"
    echo "  macos    仅构建 macOS 版 (生成安装镜像 .dmg)"
    echo "  android  仅构建 Android 版 (生成 release .apk)"
    echo "  ios      仅构建 iOS 版 (生成未签名安装包 .ipa)"
    echo "  web      仅构建 Web 版 (生成静态发布包 .zip)"
    echo "  clean    清理 Flutter 编译中间缓存 (保留 release 归档)"
    echo "  help     显示此帮助信息"
    echo ""
}

clean_build() {
    log_info "正在清理构建中间缓存 (保留 release 目录下已归档的历史版本)..."
    flutter clean
    log_success "清理完成！"
}

prepare_environment() {
    echo -e "${CYAN}------------------------------------------------------------------${NC}"
    echo -e "${CYAN}  应用全局版本: v${VERSION_NAME} (Build ${BUILD_NUMBER})${NC}"
    echo -e "${CYAN}  统一归档输出: ${RELEASE_DIR}${NC}"
    echo -e "${CYAN}------------------------------------------------------------------${NC}"

    # 1. 检测 flutter 是否在 PATH 中，若不在则在常见目录搜索
    log_info "正在检测并适配 Flutter 编译环境..."
    if ! command -v flutter &> /dev/null; then
        COMMON_FLUTTER_DIRS=(
            "$HOME/development/flutter/bin"
            "$HOME/flutter/bin"
            "/opt/homebrew/bin"
            "/usr/local/bin"
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
        echo -e "${YELLOW}【macOS 下 Flutter SDK 安装与配置指引】${NC}"
        echo -e "${YELLOW}1. 若已安装但未加入 PATH，请执行:${NC}"
        echo -e "${YELLOW}   export PATH=\"\$HOME/development/flutter/bin:\$PATH\"${NC}"
        echo -e "${YELLOW}2. 若尚未安装，推荐通过 Homebrew 快速安装: brew install --cask flutter${NC}"
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
            log_warn "当前 Dart SDK 版本为 $DART_VER，低于工程要求的基线 Dart 3.13.5！"
            echo -e "${YELLOW}【升级建议】建议执行: flutter upgrade 升级至最新的 stable 版本。${NC}"
        fi
    fi

    # 仅当 pubspec.yaml 的主版本号与 version 文件不一致时同步基线版本，避免每次构建动态写入时间戳导致 Git 记录污染
    CURRENT_PUBSPEC_VER=$(grep "^version:" "${ROOT_DIR}/pubspec.yaml" | awk '{print $2}' | cut -d'+' -f1)
    if [ "$CURRENT_PUBSPEC_VER" != "$VERSION_NAME" ]; then
        log_info "正在同步主版本号至 pubspec.yaml -> ${VERSION_NAME}+1..."
        sed -i '' "s/^version:.*/version: ${VERSION_NAME}+1/" "${ROOT_DIR}/pubspec.yaml"
    fi

    log_info "正在同步并拉取 Flutter 依赖..."
    flutter pub get
}

build_macos() {
    echo ""
    echo -e "${CYAN}==================================================================${NC}"
    echo -e "${CYAN}  1/4 正在构建 macOS 桌面端 (v${VERSION_NAME})${NC}"
    echo -e "${CYAN}==================================================================${NC}"

    if [ -f "${ROOT_DIR}/scripts/sync_all_icons.py" ]; then
        log_info "正在校验并同步多端全尺寸应用图标..."
        python3 "${ROOT_DIR}/scripts/sync_all_icons.py" > /dev/null 2>&1 || true
    fi

    flutter build macos --release \
        --build-name="$VERSION_NAME" \
        --build-number="$BUILD_NUMBER"

    MACOS_APP_PATH="build/macos/Build/Products/Release/${APP_NAME}.app"
    if [ ! -d "$MACOS_APP_PATH" ]; then
        log_error "macOS .app 产物未找到: $MACOS_APP_PATH"
        return 1
    fi

    # 生成商业级 DMG 安装镜像 (带应用大图标、Applications 快捷方式与引导背景图)
    log_info "正在打包 macOS 商业级安装镜像 (.dmg)..."
    DMG_OUTPUT="${RELEASE_DIR}/${DISPLAY_NAME}-v${VERSION_NAME}-macOS.dmg"
    rm -f "$DMG_OUTPUT" "${RELEASE_DIR}"/rw.*.dmg 2>/dev/null || true

    BG_IMAGE="${ROOT_DIR}/assets/dmg/background.tiff"
    if [ ! -f "$BG_IMAGE" ] && [ -f "${ROOT_DIR}/scripts/create_dmg_background.py" ]; then
        log_info "正在生成 DMG Retina 引导背景图..."
        python3 "${ROOT_DIR}/scripts/create_dmg_background.py" > /dev/null 2>&1 || true
    fi
    if [ ! -f "$BG_IMAGE" ]; then
        BG_IMAGE="${ROOT_DIR}/assets/dmg/background.png"
    fi

    VOL_ICON="$MACOS_APP_PATH/Contents/Resources/AppIcon.icns"

    if command -v create-dmg &> /dev/null; then
        CREATE_DMG_ARGS=(
            --volname "${DISPLAY_NAME}"
            --window-pos 200 120
            --window-size 660 450
            --icon-size 128
            --text-size 13
            --icon "${APP_NAME}.app" 175 175
            --app-drop-link 485 175
            --hide-extension "${APP_NAME}.app"
            --no-internet-enable
        )

        if [ -f "$VOL_ICON" ]; then
            CREATE_DMG_ARGS+=(--volicon "$VOL_ICON")
        fi

        if [ -f "$BG_IMAGE" ]; then
            CREATE_DMG_ARGS+=(--background "$BG_IMAGE")
        fi

        # 运行 create-dmg (返回码 0 或 2 视为正常完成)
        set +e
        create-dmg "${CREATE_DMG_ARGS[@]}" "$DMG_OUTPUT" "$MACOS_APP_PATH"
        CREATE_EXIT_CODE=$?
        
        # 若因 Finder 索引偶发 -1728 延迟，自动清理并重试一次
        if [ $CREATE_EXIT_CODE -ne 0 ] && [ $CREATE_EXIT_CODE -ne 2 ] && [ ! -f "$DMG_OUTPUT" ]; then
            log_warn "初次执行受 Finder 索引影响，正在自动清理并重试..."
            rm -f "$DMG_OUTPUT" "${RELEASE_DIR}"/rw.*.dmg 2>/dev/null || true
            sleep 2
            create-dmg "${CREATE_DMG_ARGS[@]}" "$DMG_OUTPUT" "$MACOS_APP_PATH"
            CREATE_EXIT_CODE=$?
        fi
        set -e

        # 清理可能残留的临时可读写 dmg
        rm -f "${RELEASE_DIR}"/rw.*.dmg 2>/dev/null || true

        if [ $CREATE_EXIT_CODE -ne 0 ] && [ $CREATE_EXIT_CODE -ne 2 ] && [ ! -f "$DMG_OUTPUT" ]; then
            log_warn "create-dmg 执行异常，回退至标准镜像打包..."
            DMG_TMP_DIR=$(mktemp -d /tmp/authix_dmg.XXXXXX)
            cp -R "$MACOS_APP_PATH" "$DMG_TMP_DIR/"
            ln -s /Applications "$DMG_TMP_DIR/Applications"
            hdiutil create -volname "${DISPLAY_NAME}" -srcfolder "$DMG_TMP_DIR" -ov -format UDZO "$DMG_OUTPUT" -quiet
            rm -rf "$DMG_TMP_DIR"
        fi
    else
        log_warn "未检测到 create-dmg 工具，正在使用基础方式打包 (建议执行: brew install create-dmg 以获得最佳视觉体验)..."
        DMG_TMP_DIR=$(mktemp -d /tmp/authix_dmg.XXXXXX)
        cp -R "$MACOS_APP_PATH" "$DMG_TMP_DIR/"
        ln -s /Applications "$DMG_TMP_DIR/Applications"
        hdiutil create -volname "${DISPLAY_NAME}" -srcfolder "$DMG_TMP_DIR" -ov -format UDZO "$DMG_OUTPUT" -quiet
        rm -rf "$DMG_TMP_DIR"
    fi

    log_success "macOS 商业级安装镜像 (.dmg) 已生成: $DMG_OUTPUT"
}

build_android() {
    echo ""
    echo -e "${CYAN}==================================================================${NC}"
    echo -e "${CYAN}  2/4 正在构建 Android 客户端 (v${VERSION_NAME})${NC}"
    echo -e "${CYAN}==================================================================${NC}"

    flutter build apk --release \
        --build-name="$VERSION_NAME" \
        --build-number="$BUILD_NUMBER"

    APK_SOURCE="build/app/outputs/flutter-apk/app-release.apk"
    if [ -f "$APK_SOURCE" ]; then
        APK_TARGET="${RELEASE_DIR}/${DISPLAY_NAME}-v${VERSION_NAME}-Android.apk"
        cp "$APK_SOURCE" "$APK_TARGET"
        log_success "Android 安装包 (.apk) 已生成: $APK_TARGET"
    else
        log_error "Android APK 产物未找到！"
        return 1
    fi
}

build_ios() {
    echo ""
    echo -e "${CYAN}==================================================================${NC}"
    echo -e "${CYAN}  3/4 正在构建 iOS 客户端 (v${VERSION_NAME})${NC}"
    echo -e "${CYAN}==================================================================${NC}"

    flutter build ios --release --no-codesign \
        --build-name="$VERSION_NAME" \
        --build-number="$BUILD_NUMBER"

    IOS_BUILD_DIR="build/ios/iphoneos"
    if [ -d "$IOS_BUILD_DIR/Runner.app" ]; then
        log_info "正在打包 iOS 归档..."
        PAYLOAD_TMP=$(mktemp -d /tmp/authix_payload.XXXXXX)
        mkdir -p "$PAYLOAD_TMP/Payload"
        cp -R "$IOS_BUILD_DIR/Runner.app" "$PAYLOAD_TMP/Payload/"
        
        IOS_IPA="${RELEASE_DIR}/${DISPLAY_NAME}-v${VERSION_NAME}-iOS-Unsigned.ipa"
        (cd "$PAYLOAD_TMP" && zip -q -r "$IOS_IPA" Payload)
        rm -rf "$PAYLOAD_TMP"
        log_success "iOS 未签名安装包 (.ipa) 已生成: $IOS_IPA"
    else
        log_warn "未找到 Runner.app，跳过 iOS .ipa 打包。"
    fi
}

build_web() {
    echo ""
    echo -e "${CYAN}==================================================================${NC}"
    echo -e "${CYAN}  4/4 正在构建 Web 静态版本 (v${VERSION_NAME})${NC}"
    echo -e "${CYAN}==================================================================${NC}"

    if [ ! -f "${ROOT_DIR}/web/sqflite_sw.js" ] || [ ! -f "${ROOT_DIR}/web/sqlite3.wasm" ]; then
        log_info "正在预热并配置 Web SQLite 引擎 (sqflite_sw.js & sqlite3.wasm)..."
        dart run sqflite_common_ffi_web:setup > /dev/null 2>&1 || true
    fi

    flutter build web --release \
        --base-href="/"

    WEB_SOURCE="build/web"
    if [ -d "$WEB_SOURCE" ]; then
        # 兼容离线与任意二级子目录静态托管，将根路径 base href 转换为相对路径
        if [ -f "$WEB_SOURCE/index.html" ]; then
            sed -i '' 's|<base href="/"\s*>|<base href="./">|g' "$WEB_SOURCE/index.html" 2>/dev/null || \
            sed -i 's|<base href="/"\s*>|<base href="./">|g' "$WEB_SOURCE/index.html" 2>/dev/null || true
        fi

        # 生成免配置的本地快速预览脚本 preview.sh
        cat << 'EOF' > "$WEB_SOURCE/preview.sh"
#!/usr/bin/env bash
PORT=${1:-8080}
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
echo "---------------------------------------------------------"
echo "  Authix 密码库 Web 本地 HTTP 服务已就绪"
echo "  访问地址: http://localhost:$PORT"
echo "  (按 Ctrl+C 退出服务)"
echo "---------------------------------------------------------"
(sleep 1 && open "http://localhost:$PORT") &
cd "$DIR" && python3 -m http.server "$PORT"
EOF
        chmod +x "$WEB_SOURCE/preview.sh"

        WEB_ZIP="${RELEASE_DIR}/${DISPLAY_NAME}-v${VERSION_NAME}-Web.zip"
        (cd "$WEB_SOURCE" && zip -q -r "$WEB_ZIP" ./*)
        log_success "Web 离线纯静态包已生成: $WEB_ZIP"
        echo -e "${YELLOW}  [提示] 现代浏览器出于安全限制禁止通过 file:// 直接打开单页 Web 应用。${NC}"
        echo -e "${YELLOW}         本地预览请解压后执行: ./preview.sh (或运行: python3 -m http.server 8080)${NC}"
    else
        log_error "Web 构建产物未找到！"
        return 1
    fi
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
    macos)
        prepare_environment
        build_macos
        ;;
    android)
        prepare_environment
        build_android
        ;;
    ios)
        prepare_environment
        build_ios
        ;;
    web)
        prepare_environment
        build_web
        ;;
    all)
        prepare_environment
        build_macos
        build_android
        build_ios
        build_web
        ;;
    *)
        log_error "未知选项: $TARGET"
        show_help
        exit 1
        ;;
esac

echo ""
echo -e "${GREEN}==================================================================${NC}"
echo -e "${GREEN}  打包完成！产物已归档至 [release/] 目录：${NC}"
echo -e "${GREEN}  $RELEASE_DIR${NC}"
echo -e "${GREEN}==================================================================${NC}"
ls -lh "$RELEASE_DIR"
