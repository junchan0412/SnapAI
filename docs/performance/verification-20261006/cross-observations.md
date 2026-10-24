# Cross-app 复验观察

时间：2026-10-06 11:11 +08:00。

本轮状态：BLOCKED，未执行任何 cross-app runtime case。

首个 CUA `cua.getState()` 返回原始错误：

> Native apps: Error: The Mac is locked and automatic unlock could not unlock it. Ask the user to unlock the Mac manually before continuing.

因此本轮没有取得 TextEdit、Chrome、Word 的当前 PID、版本或 owned fixture 实际完整窗口 title；没有操作任何 fixture，也没有运行 ax、copy-replace 或 target-changed。未生成冒充 runtime stdout 的 JSONL。旧 /tmp raw logs 已不可用，不能以本记录补证历史结果。

构建与源文件一致性：`shasum -a 256 -c .build/cross-app-runtime-v2/sources.sha256` 的 8 个文件全部 OK。未重新编译，也未修改业务、runner 或脚本。

本轮开始时 SHA-256：

| 文件 | SHA-256 |
| --- | --- |
| `.build/cross-app-runtime-v2/SnapAICrossAppRuntime` | `708ab8c9d5c96352854a3942ce1472e61b74fd91ef224471f994e06d46086d2f` |
| `.build/cross-app-runtime-v2/sources.sha256` | `cf8767b413f5c66ab4af1ce3709208d915f1a0fd31a47f29f9916f19420bc5fe` |
| `scripts/run-cross-app-runtime.sh` | `4b8442b0105fb107033d586ecdcc4f3aa92aedfbecb63148964e320fbae0fa8b` |
| Browser primary fixture | `ccfa302fa9234e1508e3f74c5b4125116041c1cb7dc7c43cd8a904c04fe5ebc1` |
| Browser Other fixture | `e976fb0ebf40ee021bc1db3ec8beb66b430fab357c19ae3a8a56afc4ea2248f9` |
| TextEdit、Electron primary / Other fixtures（4 个） | `983737ff179a5dcc67292695c0e8c8ce0165b24dd64e43918ad1787e3bb783ca` |
| Word primary / Other fixtures（2 个） | `07fd5eb6ef71bab181e983e12078a54f5427c6aab3258293c72d8122582798d0` |

所有编辑用 fixture 位于 `.build/roadmap-fixtures/`。本轮无 GUI 修改需要恢复。GUI 已释放；后续真实验证须先由用户手动解锁 Mac。
