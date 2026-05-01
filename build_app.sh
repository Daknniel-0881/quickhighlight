#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")"

EXEC_NAME="CursorMagnifier"           # Swift 二进制名（保持不变以复用 build cache）
APP_NAME="快捷高光"                    # 用户看到的 .app 名
BIN_SRC=".build/release/${EXEC_NAME}"
PLIST_SRC="Resources/Info.plist"
DIST_DIR="dist"
APP_DIR="${DIST_DIR}/${APP_NAME}.app"
INSTALL_PATH="/Applications/${APP_NAME}.app"
DESKTOP_DIR="${HOME}/Desktop"

# 稳定本地代码签名身份（一次创建，长期复用）。
# ad-hoc 签名（codesign --sign -）每次重 build 都会生成新的 cdhash，TCC 数据库以为是新 app
# 反复要求授权。用一个固定的 self-signed cert 让 cdhash 跨 build 稳定。
CERT_NAME="QuickHighlightDevCert"

ensure_signing_identity() {
    if security find-identity -v -p codesigning 2>/dev/null | grep -q "$CERT_NAME"; then
        return 0
    fi
    echo "→ 首次创建本地代码签名证书 ${CERT_NAME} ..."
    local TMPDIR_X
    TMPDIR_X="$(mktemp -d)"
    cat > "$TMPDIR_X/cert.cnf" <<EOF
[ req ]
default_bits       = 2048
default_md         = sha256
prompt             = no
distinguished_name = dn
x509_extensions    = v3_ca

[ dn ]
CN = ${CERT_NAME}

[ v3_ca ]
basicConstraints = critical, CA:TRUE
keyUsage = critical, keyCertSign, digitalSignature
extendedKeyUsage = critical, codeSigning
EOF
    openssl req -x509 -newkey rsa:2048 -keyout "$TMPDIR_X/key.pem" -out "$TMPDIR_X/cert.pem" \
        -days 3650 -nodes -config "$TMPDIR_X/cert.cnf" >/dev/null 2>&1
    openssl pkcs12 -export -inkey "$TMPDIR_X/key.pem" -in "$TMPDIR_X/cert.pem" \
        -out "$TMPDIR_X/cert.p12" -passout pass: -name "$CERT_NAME" >/dev/null 2>&1
    security import "$TMPDIR_X/cert.p12" -k "$HOME/Library/Keychains/login.keychain-db" \
        -P "" -T /usr/bin/codesign -A >/dev/null 2>&1 || true
    rm -rf "$TMPDIR_X"
    # 让 codesign 不再弹 keychain 密码框
    security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k "" \
        "$HOME/Library/Keychains/login.keychain-db" >/dev/null 2>&1 || true
}

echo "→ swift build (release) ..."
swift build -c release

echo "→ 生成 App 图标（圆环聚焦放大） ..."
swift generate_icon.swift
iconutil -c icns Resources/AppIcon.iconset -o Resources/AppIcon.icns

echo "→ 打包 ${APP_NAME}.app ..."
rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS"
mkdir -p "$APP_DIR/Contents/Resources"
cp "$BIN_SRC" "$APP_DIR/Contents/MacOS/$EXEC_NAME"
cp "$PLIST_SRC" "$APP_DIR/Contents/Info.plist"
cp Resources/AppIcon.icns "$APP_DIR/Contents/Resources/AppIcon.icns"

ensure_signing_identity
if security find-identity -v -p codesigning 2>/dev/null | grep -q "$CERT_NAME"; then
    echo "→ 用稳定本地证书签名（${CERT_NAME}）..."
    codesign --force --deep --sign "$CERT_NAME" "$APP_DIR" >/dev/null
else
    echo "→ 退化到 ad-hoc 签名（每次 build 后系统会要求重新授权权限）..."
    codesign --force --deep --sign - "$APP_DIR" >/dev/null
fi

echo "→ 关闭旧实例 ..."
pkill -f "$EXEC_NAME" 2>/dev/null || true
sleep 0.3

echo "→ 安装到 /Applications ..."
rm -rf "$INSTALL_PATH"
cp -R "$APP_DIR" "$INSTALL_PATH"

echo "→ 清除 Gatekeeper / quarantine 属性 ..."
xattr -cr "$INSTALL_PATH" 2>/dev/null || true
xattr -dr com.apple.provenance "$INSTALL_PATH" 2>/dev/null || true
xattr -dr com.apple.quarantine "$INSTALL_PATH" 2>/dev/null || true

echo "→ 重新注册到 Launch Services（刷图标缓存） ..."
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister \
    -f "$INSTALL_PATH" 2>/dev/null || true

echo "→ 桌面快捷方式：复制完整 .app（带完整 icon resource，Finder 直接显示 logo）..."
# symlink 在某些 macOS 版本里 Finder 不刷图标。直接 cp -R 整份 .app 最稳。
# 用稳定本地签名后两份 .app 共享同一个 cdhash，TCC 只记一条授权，不会反复弹权限。
rm -f "${DESKTOP_DIR}/${APP_NAME}" "${DESKTOP_DIR}/${APP_NAME}的替身" 2>/dev/null || true
rm -rf "${DESKTOP_DIR}/${APP_NAME}.app" 2>/dev/null || true
cp -R "$INSTALL_PATH" "${DESKTOP_DIR}/${APP_NAME}.app"
xattr -cr "${DESKTOP_DIR}/${APP_NAME}.app" 2>/dev/null || true
xattr -dr com.apple.provenance "${DESKTOP_DIR}/${APP_NAME}.app" 2>/dev/null || true
xattr -dr com.apple.quarantine "${DESKTOP_DIR}/${APP_NAME}.app" 2>/dev/null || true
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister \
    -f "${DESKTOP_DIR}/${APP_NAME}.app" 2>/dev/null || true
touch "${DESKTOP_DIR}/${APP_NAME}.app" 2>/dev/null || true

echo ""
echo "✓ 全部完成："
echo "  · 已安装：${INSTALL_PATH}"
echo "  · 桌面快捷方式：~/Desktop/${APP_NAME}"
echo ""
echo "双击桌面【${APP_NAME}】图标启动，菜单栏会出现 🔍 图标。"
echo "首次运行需授权：辅助功能 + 屏幕录制（系统设置 → 隐私与安全性）"
