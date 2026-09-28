#!/usr/bin/env bash
# 生成 Sparkle appcast.xml:把本次 release 的 zip 用 EdDSA 签名后写进 feed。
#
# 用法:scripts/generate-appcast.sh <version> [zip] [notes.md] [output.xml]
# 环境:
#   SPARKLE_SIGN_UPDATE    sign_update 路径(默认 ~/.snapai/sparkle-tools/bin/sign_update)
#   SPARKLE_ED_PRIVATE_KEY 私钥文件(base64 的 Ed25519 种子,默认 ~/.snapai/sparkle/ed25519-private.key)
#   SNAPAI_RELEASE_REPO    仓库(默认 junchan0412/SnapAI)
#
# 生成后立刻用官方工具回验签名,回验不过就退出 —— 坏的 appcast 不允许进 dist/。
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="${1:?usage: generate-appcast.sh <version> [zip] [notes.md] [output.xml]}"
VERSION="${VERSION#v}"
TAG="v${VERSION}"
ZIP="${2:-dist/SnapAI-${TAG}.zip}"
NOTES="${3:-docs/RELEASE_NOTES_${VERSION}.md}"
OUTPUT="${4:-dist/appcast.xml}"
REPO="${SNAPAI_RELEASE_REPO:-junchan0412/SnapAI}"
SIGN_UPDATE="${SPARKLE_SIGN_UPDATE:-$HOME/.snapai/sparkle-tools/bin/sign_update}"
KEY_FILE="${SPARKLE_ED_PRIVATE_KEY:-$HOME/.snapai/sparkle/ed25519-private.key}"

fail() { echo "error: $1" >&2; exit 1; }

[ -f "$ZIP" ] || fail "找不到更新包: $ZIP"
[ -x "$SIGN_UPDATE" ] || fail "找不到 sign_update: $SIGN_UPDATE(先跑 scripts/fetch-sparkle-tools.sh)"
[ -f "$KEY_FILE" ] || fail "找不到 EdDSA 私钥: $KEY_FILE"

SHORT_VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" Resources/Info.plist)
BUILD_VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleVersion" Resources/Info.plist)
[ "$SHORT_VERSION" = "$VERSION" ] || fail "Info.plist 短版本 $SHORT_VERSION 与传入版本 $VERSION 不一致"
[ "$BUILD_VERSION" = "$VERSION" ] || fail "CFBundleVersion($BUILD_VERSION) 必须与短版本一致"

# 公私钥一致性:Info.plist 里的 SUPublicEDKey 必须由这把私钥派生,
# 否则签名再正确,应用侧也会因为公钥对不上而拒绝更新。
KEY_PEM="${SPARKLE_ED_PRIVATE_PEM:-$HOME/.snapai/sparkle/ed25519-private.pem}"
if [ -f "$KEY_PEM" ]; then
  DERIVED_PUBLIC=$(openssl pkey -in "$KEY_PEM" -pubout -outform DER 2>/dev/null | tail -c 32 | base64 | tr -d '\n')
  PLIST_PUBLIC=$(/usr/libexec/PlistBuddy -c "Print :SUPublicEDKey" Resources/Info.plist)
  if [ "$DERIVED_PUBLIC" != "$PLIST_PUBLIC" ]; then
    fail "Info.plist 的 SUPublicEDKey 与私钥不匹配(期望 $DERIVED_PUBLIC,实际 $PLIST_PUBLIC)"
  fi
fi

SIGNATURE=$("$SIGN_UPDATE" "$ZIP" --ed-key-file "$KEY_FILE" -p | tr -d '[:space:]')
[ -n "$SIGNATURE" ] || fail "sign_update 没有产出签名"
if ! "$SIGN_UPDATE" "$ZIP" --verify "$SIGNATURE" --ed-key-file "$KEY_FILE" >/dev/null 2>&1; then
  fail "刚生成的签名回验失败,拒绝写入 appcast"
fi

LENGTH=$(wc -c < "$ZIP" | tr -d ' ')
URL="https://github.com/${REPO}/releases/download/${TAG}/$(basename "$ZIP")"
PUBDATE=$(date -R)
DESCRIPTION=$(python3 scripts/support/release-notes-html.py "$NOTES")

mkdir -p "$(dirname "$OUTPUT")"
cat > "$OUTPUT" <<XML
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
  <channel>
    <title>SnapAI 更新</title>
    <link>https://github.com/${REPO}</link>
    <description>SnapAI 的更新通道:每次发版生成 appcast 并随 Release 分发。</description>
    <language>zh-Hans</language>
    <item>
      <title>SnapAI ${VERSION}</title>
      <sparkle:version>${BUILD_VERSION}</sparkle:version>
      <sparkle:shortVersionString>${SHORT_VERSION}</sparkle:shortVersionString>
      <pubDate>${PUBDATE}</pubDate>
      <enclosure url="${URL}"
                 sparkle:edSignature="${SIGNATURE}"
                 length="${LENGTH}"
                 type="application/octet-stream"/>
      <description><![CDATA[${DESCRIPTION}]]></description>
    </item>
  </channel>
</rss>
XML

echo "$OUTPUT"
echo "version=${VERSION} length=${LENGTH}"
echo "url=${URL}"
