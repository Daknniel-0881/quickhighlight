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
    # 证书已经导入过（哪怕没 trust）就别再 import 一遍堆积同名条目，直接 return 1 走 fallback
    if security find-certificate -c "$CERT_NAME" -a 2>/dev/null | grep -q "labl"; then
        echo "  (证书已存在但缺 keychain trust setting，本次走 ad-hoc fallback)"
        return 1
    fi
    echo "→ 首次创建本地代码签名证书 ${CERT_NAME} ..."

    # 此前这段 silent fail（>/dev/null 2>&1 || true）—— openssl 3 默认 PKCS12 用
    # PBES2/AES-256-CBC，macOS Security framework 默认不识别，security import 静默失败 →
    # keychain 0 valid identity → 每次 build fallback ad-hoc → cdhash 跨 build 变 →
    # TCC 每次当新 app → 屏幕录制权限失效 → 抓帧 nil → 用户以为 zoom 没生效。
    # 反复栽跟头三次。这次让所有错误都 loud + 创建后立刻 verify，找不到就 abort。
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
basicConstraints = critical, CA:FALSE
keyUsage = critical, digitalSignature
extendedKeyUsage = critical, codeSigning
EOF
    if ! openssl req -x509 -newkey rsa:2048 \
            -keyout "$TMPDIR_X/key.pem" -out "$TMPDIR_X/cert.pem" \
            -days 3650 -nodes -config "$TMPDIR_X/cert.cnf" 2>"$TMPDIR_X/err"; then
        echo "✗ openssl req 创建证书失败:"
        cat "$TMPDIR_X/err"
        rm -rf "$TMPDIR_X"
        return 1
    fi
    # openssl 3 用 -legacy 强制旧版 PKCS12（RC2 + 3DES）；如果没有 -legacy（LibreSSL 旧版），
    # 显式指定 PBE-SHA1-3DES，保证 macOS 能解析
    local PKCS12_OK=0
    if openssl pkcs12 -export -legacy \
            -inkey "$TMPDIR_X/key.pem" -in "$TMPDIR_X/cert.pem" \
            -out "$TMPDIR_X/cert.p12" -passout pass:qhdev -name "$CERT_NAME" \
            2>"$TMPDIR_X/err"; then
        PKCS12_OK=1
    elif openssl pkcs12 -export \
            -keypbe PBE-SHA1-3DES -certpbe PBE-SHA1-3DES -macalg sha1 \
            -inkey "$TMPDIR_X/key.pem" -in "$TMPDIR_X/cert.pem" \
            -out "$TMPDIR_X/cert.p12" -passout pass:qhdev -name "$CERT_NAME" \
            2>"$TMPDIR_X/err"; then
        PKCS12_OK=1
    fi
    if [ "$PKCS12_OK" != "1" ]; then
        echo "✗ openssl pkcs12 -export 失败（既无 -legacy 又无 PBE-SHA1-3DES 兼容）:"
        cat "$TMPDIR_X/err"
        rm -rf "$TMPDIR_X"
        return 1
    fi
    # 关键：macOS Security framework 对空密码 PKCS12 的 MAC 验证有 bug，
    # 必须给 .p12 一个非空密码（与 -passout pass:qhdev 对齐）
    if ! security import "$TMPDIR_X/cert.p12" \
            -k "$HOME/Library/Keychains/login.keychain-db" \
            -P "qhdev" -T /usr/bin/codesign -A 2>"$TMPDIR_X/err"; then
        echo "✗ security import 失败（keychain 锁定？或权限问题）:"
        cat "$TMPDIR_X/err"
        rm -rf "$TMPDIR_X"
        return 1
    fi
    rm -rf "$TMPDIR_X"

    # 让 codesign 不再弹 keychain 密码框
    security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k "" \
        "$HOME/Library/Keychains/login.keychain-db" >/dev/null 2>&1 || true

    # 关键 verify：必须能在 codesigning policy 下找到这张证书，否则 abort
    if ! security find-identity -v -p codesigning 2>/dev/null | grep -q "$CERT_NAME"; then
        echo "✗ 证书已 import 但 security find-identity -p codesigning 找不到 —— "
        echo "  通常是证书 extendedKeyUsage 不含 codeSigning 或 keychain trust 设置错误"
        echo "  当前 codesigning identity 列表："
        security find-identity -v -p codesigning 2>&1 | head -10
        echo "  当前所有 identity："
        security find-identity -v 2>&1 | head -10
        return 1
    fi
    echo "✓ 证书 ${CERT_NAME} 创建并导入成功"
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

# 尝试创建/查找稳定证书。openssl 自动路径在新版 macOS Security 上会因为
# trust setting 缺失被拒（即使 import 成功，find-identity -p codesigning 仍 0）。
# 没有稳定证书时 fallback ad-hoc，并 loud 提示曲率手动建一次。
set +e
ensure_signing_identity
ENSURE_RC=$?
set -e
if [ "$ENSURE_RC" = "0" ] && security find-identity -v -p codesigning 2>/dev/null | grep -q "$CERT_NAME"; then
    echo "→ 用稳定本地证书签名（${CERT_NAME}）..."
    codesign --force --deep --sign "$CERT_NAME" "$APP_DIR" >/dev/null
    SIGN_AUTH="$(codesign -dv --verbose=4 "$APP_DIR" 2>&1 | grep -E '^Authority' | head -1)"
    echo "  ✓ Authority: $SIGN_AUTH"
else
    echo ""
    echo "⚠️  稳定本地证书不可用，本次退化到 ad-hoc 签名 ⚠️"
    echo "    后果：本次 build 的 cdhash 会跟之前授权过的不一样，"
    echo "    曲率需要去【系统设置 → 隐私与安全性 → 屏幕录制】重新勾选「快捷高光」一次。"
    echo ""
    echo "    一次性根治办法（手动 5 分钟，之后所有 build 都稳定）:"
    echo "    1) 打开「钥匙串访问」.app"
    echo "    2) 菜单栏：钥匙串访问 → 证书助理 → 创建证书…"
    echo "       名称：${CERT_NAME}"
    echo "       身份类型：自签名根身份"
    echo "       证书类型：代码签名"
    echo "       勾「让我覆盖默认」→ 一直点继续，全部默认即可"
    echo "    3) 创建完后再跑 bash build_app.sh，会自动找到并用它"
    echo ""
    codesign --force --deep --sign - "$APP_DIR" >/dev/null
fi

echo "→ 关闭旧实例 ..."
pkill -f "$EXEC_NAME" 2>/dev/null || true
sleep 0.3

# 关键卫生：清理所有可能的老版本残留 + 反注册 Launch Services
# 踩过的坑（曲率 2026-05-01 反馈）—— Spotlight 搜「快捷高光」会列出多个不同路径的 .app
# （/Applications + 桌面 + 旧 dist/ + 旧位置移动后的残留），用户根本不知道双击哪个才是最新版，
# 导致反复测「这个 bug 修没修」时验错了 binary，认知严重错位。
# 修复：每次 build 前用 mdfind 主动扫一遍，干掉除「dist/ + /Applications + 桌面」之外的全部副本。
echo "→ 清理机器上其他位置的「快捷高光 / CursorMagnifier」老残留 ..."
PROJECT_ROOT="$(cd "$(dirname "$0")" && pwd)"
KEEP_PATHS=(
    "${PROJECT_ROOT}/dist/${APP_NAME}.app"
    "${INSTALL_PATH}"
    "${DESKTOP_DIR}/${APP_NAME}.app"
)
STALE_LIST="$(mdfind 'kMDItemFSName == "*快捷高光*"cd || kMDItemFSName == "CursorMagnifier*"cd || kMDItemFSName == "QuickHighlight*"cd' 2>/dev/null \
    | grep -E '\.app$' \
    | grep -vE "(/Sources/|/.build/|/Resources/|/.git/)" || true)"
while IFS= read -r STALE; do
    [ -z "$STALE" ] && continue
    SKIP=0
    for KEEP in "${KEEP_PATHS[@]}"; do
        if [ "$STALE" = "$KEEP" ]; then SKIP=1; break; fi
    done
    [ "$SKIP" = "1" ] && continue
    echo "    ✗ 删除老版本: $STALE"
    /System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -u "$STALE" 2>/dev/null || true
    rm -rf "$STALE" 2>/dev/null || true
done <<< "$STALE_LIST"

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
