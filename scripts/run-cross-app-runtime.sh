#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")/.."
if [ "${1:-}" = "--help" ] || [ "$#" -eq 0 ]; then
  cat <<'HELP'
Usage: scripts/run-cross-app-runtime.sh [--runner-dir ABSOLUTE_DIR] \
  --bundle-id BUNDLE_ID --pid PID --window-title EXACT_TITLE \
  --mode ax|copy|copy-replace|replace|two-phase [--state-dir ABSOLUTE_DIR] \
  [--expect pass|source-changed|selection-changed|target-changed|validation-unavailable|pasteboard-changed] \
  [--timeout SECONDS] [--fixture ascii|unicode] [--activate-fixture true|false] \
  [--alternate-fixture-title EXACT_ALTERNATE_TITLE]

在真实应用中先创建并聚焦临时 fixture，窗口标题必须包含 SnapAI-CrossApp-Fixture-。
--activate-fixture 默认为 false；显式 true 时先核验目标应用自身的 PID/bundleID、
精确 fixture 窗口和固定选区，再请求激活并等待最多 2s，随后仍须通过全部前台和全局 AX 门禁。
该选项仅是有界 fixture 初始化，不构成快捷键或真实用户触发链路的验收证据。
只选中固定原文：SnapAI fixture source 20261006.
固定替换内容为：SnapAI fixture replacement 20261006.
AX/copy 仅取词（captureOnly=true）；copy-replace 复制取词后写回，replace 优先 AX 后写回。
可选 unicode 原文：SnapAI 虚构原文 👩🏽‍💻 é 20261006.
可选 unicode 替换：SnapAI 虚构替换 🧪 é 20261006.（e + U+0301）
two-phase 捕获后写 ready.json，
等待外部创建 state-dir/go，再校验并写回。state-dir 必须存在且没有 ready.json/go。
同一 fixture 内源文/选区改变将进入真实 transaction 验证拒绝；只有业务拒绝才记 PASS。
仅 two-phase --expect target-changed 可提供 --alternate-fixture-title，两个不同标题
均须包含 fixture 标记；初始捕获/激活只允许 primary。go 后允许同 PID/bundle 的
primary 或明确 alternate，且当下选区必须仍为固定原文，再由真实 transaction 判断目标漂移。
第三个标题硬拒绝，不能记业务 PASS；transactionFixtureRole 标明实际进入事务的 fixture。
只有 alternateFixtureWasTransactionTarget=true 才能归入 alternate 文档漂移证据。
alternate 测试还要求拒绝前后的当前编辑区 AXValue 可比且未变化，否则 BLOCKED/FAIL。
拒绝证据包括实际回调和剪贴板状态；AXValue 可读时额外核验拒绝前后该编辑区未变化，
不可读时 rejectionFocusedValuePostcondition=unavailable，不代表全文未变化已验证。
离开绑定 fixture 的门禁拒绝记 REJECTED，businessRejectionVerified=false。
--expect pasteboard-changed 会在 transaction 开始后 50ms 注入另一份带 owner 标记的
固定剪贴板内容，验证业务拒绝且保留新 marker；仅仍持有最后自有 marker 时还原原剪贴板。
此竞争测试可直接用于 replace/copy-replace，无需 two-phase 或外部剪贴板操作。
只输出固定标识、枚举、匹配状态与指标，不保存选区或真实剪贴板内容。
缺少现有 TCC 权限时报告 BLOCKED；本脚本不会请求权限或自动编译。
退出码：0=PASS，1=FAIL，2=BLOCKED，3=REJECTED（与期望不符）。
HELP
  exit 0
fi
SNAPAI_CROSS_APP_BUILD_DIR="$PWD/.build/cross-app-runtime"
if [ "${1:-}" = "--runner-dir" ]; then
  [ "$#" -ge 2 ] || exit 2
  SNAPAI_CROSS_APP_BUILD_DIR="$2"
  shift 2
fi
if [[ "$SNAPAI_CROSS_APP_BUILD_DIR" != /* ]] || [ ! -x "$SNAPAI_CROSS_APP_BUILD_DIR/SnapAICrossAppRuntime" ]; then
  echo '{"status":"BLOCKED","reason":"runner-not-prepared"}'
  exit 2
fi
if ! shasum -a 256 -c "$SNAPAI_CROSS_APP_BUILD_DIR/sources.sha256" >/dev/null 2>&1; then
  echo '{"status":"BLOCKED","reason":"runner-sources-changed-rebuild-required"}'
  exit 2
fi
exec "$SNAPAI_CROSS_APP_BUILD_DIR/SnapAICrossAppRuntime" "$@"
