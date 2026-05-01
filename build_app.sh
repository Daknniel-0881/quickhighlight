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

# 签名模式：
#   adhoc (默认)  : 不需要证书，适合开源用户直接 build/install。
#   local         : 使用当前 Mac 自己生成并复用的本地证书，适合频繁 rebuild 的开发者。
#   none          : 跳过 app bundle 签名（仅本机实验，不推荐发布）。
#
# 说明：Zoom 数学不依赖签名；屏幕抓帧权限由 macOS TCC 管理。
# ad-hoc / none 在 rebuild 后可能让 TCC 认为这是新 app。代码层已经用
# CGPreflightScreenCaptureAccess() 做只读预检，未授权时不启动 SCStream，
# 避免系统权限弹窗死循环。
SIGNING_MODE="${QH_SIGNING_MODE:-adhoc}"
CERT_NAME="QuickHighlightLocalSigner"

run_with_timeout() {
    local seconds="$1"
    shift
    "$@" &
    local pid=$!
    local elapsed=0
    while kill -0 "$pid" 2>/dev/null; do
        if [ "$elapsed" -ge "$seconds" ]; then
            kill "$pid" 2>/dev/null || true
            wait "$pid" 2>/dev/null || true
            return 124
        fi
        sleep 1
        elapsed=$((elapsed + 1))
    done
    wait "$pid"
}

ensure_signing_identity() {
    if security find-identity -v -p codesigning 2>/dev/null | grep -q "$CERT_NAME"; then
        return 0
    fi

    # 如果同名证书存在但不是 valid codesigning identity，就删掉证书记录后重建。
    # 旧版脚本会留下“只有证书/不可用于 codesign”的 QuickHighlightDevCert，
    # 导致后续每次都 fallback 到 ad-hoc。这里不要容忍半坏状态。
    while security find-certificate -c "$CERT_NAME" -a 2>/dev/null | grep -q "labl"; do
        echo "  (发现不可用的 ${CERT_NAME} 证书记录，删除后重建)"
        security delete-certificate -c "$CERT_NAME" "$HOME/Library/Keychains/login.keychain-db" >/dev/null 2>&1 || break
        if security find-identity -v -p codesigning 2>/dev/null | grep -q "$CERT_NAME"; then
            return 0
        fi
    done

    if ! command -v openssl >/dev/null 2>&1; then
        echo "✗ 找不到 openssl，无法自动创建稳定代码签名证书"
        return 1
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
basicConstraints = critical, CA:FALSE
keyUsage = critical, digitalSignature
extendedKeyUsage = critical, codeSigning
subjectKeyIdentifier = hash
authorityKeyIdentifier = keyid:always,issuer
EOF
    # 直接使用 self-signed leaf cert 时，macOS 往往不会把它列为 valid codesigning
    # identity。这里改成当前用户 trustRoot 的本地 code signing root；这是钥匙串
    # “创建证书… → 自签名根身份 → 代码签名”的命令行等价物。
    perl -0pi -e 's/basicConstraints = critical, CA:FALSE/basicConstraints = critical, CA:TRUE/; s/keyUsage = critical, digitalSignature/keyUsage = critical, digitalSignature, keyCertSign/' "$TMPDIR_X/cert.cnf"
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
    if ! security add-trusted-cert -d -r trustRoot -p codeSign \
            -k "$HOME/Library/Keychains/login.keychain-db" \
            "$TMPDIR_X/cert.pem" 2>"$TMPDIR_X/err"; then
        echo "✗ 将 ${CERT_NAME} 设为当前用户可信代码签名证书失败:"
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
    echo "✓ 证书 ${CERT_NAME} 创建、导入并信任成功"
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

case "$SIGNING_MODE" in
    adhoc)
        echo "→ 使用无需证书的 ad-hoc 签名（默认开源安装模式）..."
        codesign --force --deep --sign - "$APP_DIR" >/dev/null
        ;;
    local)
        echo "→ 使用当前 Mac 的稳定本地证书签名（${CERT_NAME}）..."
        ensure_signing_identity
        if ! run_with_timeout 20 codesign --force --deep --sign "$CERT_NAME" "$APP_DIR" >/dev/null; then
            echo "✗ 稳定签名未能完成（通常是钥匙串正在等待私钥访问授权）。"
            echo "  可先用默认模式安装：bash build_app.sh"
            echo "  或解决钥匙串私钥访问后重试：QH_SIGNING_MODE=local bash build_app.sh"
            exit 1
        fi
        ;;
    none)
        echo "→ 跳过 app bundle 签名（QH_SIGNING_MODE=none，本机实验模式）..."
        ;;
    *)
        echo "✗ 未知 QH_SIGNING_MODE=${SIGNING_MODE}（可选：adhoc / local / none）"
        exit 1
        ;;
esac

SIGN_AUTH="$(codesign -dv --verbose=4 "$APP_DIR" 2>&1 | grep -E '^Authority|^TeamIdentifier|^Signature=' | head -5 || true)"
if [ -n "$SIGN_AUTH" ]; then
    echo "$SIGN_AUTH" | sed 's/^/  ✓ /'
else
    echo "  ✓ app bundle 未签名或仅主二进制保留工具链签名"
fi

echo "→ 关闭旧实例 ..."
pkill -f "$EXEC_NAME" 2>/dev/null || true
sleep 0.3

# 关键卫生：清理所有可能的老版本残留 + 反注册 Launch Services
# 踩过的坑（曲率 2026-05-01 反馈）—— Spotlight 搜「快捷高光」会列出多个不同路径的 .app
# （/Applications + 桌面 + 旧 dist/ + 旧位置移动后的残留），用户根本不知道双击哪个才是最新版，
# 导致反复测「这个 bug 修没修」时验错了 binary，认知严重错位。
# 修复：每次 build 前用 mdfind 主动扫一遍，干掉除当前构建临时路径和 /Applications 之外的全部副本。
echo "→ 清理机器上其他位置的「快捷高光 / CursorMagnifier」老残留 ..."
PROJECT_ROOT="$(cd "$(dirname "$0")" && pwd)"
KEEP_PATHS=(
    "${PROJECT_ROOT}/dist/${APP_NAME}.app"
    "${INSTALL_PATH}"
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

if [ "${QH_KEEP_DIST_APP:-}" != "1" ]; then
    echo "→ 删除 dist 中的临时 .app，避免 Spotlight/用户误启动第二份副本 ..."
    /System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister \
        -u "$APP_DIR" 2>/dev/null || true
    rm -rf "$APP_DIR" 2>/dev/null || true
fi

echo "→ 清理桌面旧副本，避免误启动另一个代码身份 ..."
rm -f "${DESKTOP_DIR}/${APP_NAME}" "${DESKTOP_DIR}/${APP_NAME}的替身" 2>/dev/null || true
if [ -d "${DESKTOP_DIR}/${APP_NAME}.app" ]; then
    /System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister \
        -u "${DESKTOP_DIR}/${APP_NAME}.app" 2>/dev/null || true
    rm -rf "${DESKTOP_DIR}/${APP_NAME}.app" 2>/dev/null || true
fi

echo ""
echo "✓ 全部完成："
echo "  · 已安装：${INSTALL_PATH}"
echo ""
echo "请从【应用程序】里的【${APP_NAME}】启动，菜单栏会出现 🔍 图标。"
echo "首次运行需授权：辅助功能 + 屏幕录制（系统设置 → 隐私与安全性）"
