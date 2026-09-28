#!/usr/bin/env bash
# 取 Sparkle 官方签名工具(sign_update / generate_keys / generate_appcast)并校验哈希。
# 只在发版机需要;工具与私钥都不进仓库。
set -euo pipefail

SPARKLE_VERSION="${SPARKLE_VERSION:-2.9.6}"
# Sparkle-<version>.tar.xz 的 SHA-256(升级版本时必须同步更新这一行)
SPARKLE_SHA256="${SPARKLE_SHA256:-52bf9e88cdd972fc0c81501377a880e90d47031bd8ca5462488f843e2609e192}"
DEST="${SPARKLE_TOOLS_DIR:-$HOME/.snapai/sparkle-tools}"
URL="https://github.com/sparkle-project/Sparkle/releases/download/${SPARKLE_VERSION}/Sparkle-${SPARKLE_VERSION}.tar.xz"

fail() { echo "error: $1" >&2; exit 1; }

if [ -x "$DEST/bin/sign_update" ]; then
  echo "已存在: $DEST/bin/sign_update"
  exit 0
fi

mkdir -p "$DEST"
TMP=$(mktemp "${TMPDIR:-/tmp}/sparkle-tools.XXXXXX.tar.xz")
trap 'rm -f "$TMP"' EXIT
echo "==> 下载 $URL"
curl -fsSL -o "$TMP" "$URL"
ACTUAL=$(shasum -a 256 "$TMP" | awk '{print $1}')
if [ "$ACTUAL" != "$SPARKLE_SHA256" ]; then
  fail "Sparkle 工具包哈希不匹配(期望 $SPARKLE_SHA256,实际 $ACTUAL)"
fi
tar -xJf "$TMP" -C "$DEST" bin/sign_update bin/generate_keys bin/generate_appcast
chmod +x "$DEST"/bin/*
echo "==> 已安装到 $DEST/bin"
"$DEST/bin/sign_update" --help >/dev/null && echo "sign_update 可用"
