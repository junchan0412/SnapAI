# SnapAI 2.0.3

SnapAI 2.0.3 是审查驱动的维护版本：补 MIT 许可证、修复并发与外部进程隐患、加固历史库文件权限、补无障碍标签，并让“取消生成”不再丢弃部分结果。功能、配置、快捷键与历史记录完全兼容 2.0.x。

## 许可证

- 新增 `LICENSE`（MIT），README 许可证章节改为指向该文件。
- 发布 preflight 增加许可证门禁：缺少 `LICENSE` 或 README 未引用即失败；manifest 打包时也一并校验。
- SBOM 记录许可证：CycloneDX `metadata.licenses` 与根组件 `licenses` 均声明 `MIT`。

## 取消不再丢弃部分结果

- 点“停止生成”后，已产生的部分结果会写入历史，并自动打上“部分结果”标签，可搜索、可筛选、可重新打开。
- 取消仍不计成功（不计动作使用次数、不触发自动替换原文），与正常完成区分。
- 只有真正的部分内容才会入库：空输出的取消不写历史。

## 并发与外部进程

- `AIClient` 的流式任务句柄改由独立锁保护，`deinit` 不再触碰 `@MainActor` 隔离状态；任务收尾只清空属于自己的句柄，不会误删接管的新请求。
- `UpdateChecker.runTool/runToolOutput` 与 updater helper 的 `run` 改为“后台排空管道 + 整体超时”：默认 30 秒（updater 侧 60 秒），超时终止子进程并抛错/记日志，避免管道塞满互等或 `openssl/codesign/ditto` 挂起卡死调用方。
- `TextCapture` 的 CF 桥接转换保留 `as!`（CF 类型经 `isAXUIElementRef/isAXValueRef` 守卫后桥接，`as?` 会被编译器判为恒成功），并在首处补充注释说明原因。

## 存储与隐私

- `history.sqlite` 及其 WAL/SHM 建库后收紧到 `0600`，父目录收紧到 `0700`，与本地密钥存储的 `Secrets` 目录对齐。已有文件同样收紧。
- 供应商设置的“超时（秒）”输入框旁增加说明：流式空闲超过此时长会断开，长思考/慢回复请设大。该结论来自新增的慢流探测（见下）。

## 无障碍

- 动作上移/下移按钮补带动作名的 `accessibilityLabel`（如“将动作翻译上移”）。
- 供应商排序菜单与模型移除按钮补带供应商/模型名的 label（如“调整供应商 OpenAI 的排序”“从供应商 OpenAI 移除模型 gpt-4o”）。

## 测试与 CI

- 新增慢流探测：chunk 间隔 7 秒、超时 5 秒的 fixture 会触发系统空闲超时（已验证 `The request timed out`），锁定“超时即断开”的语义；探测只记录 NOTE，不判失败。
- 取消语义的回归测试更新：`run-app-runtime-tests.sh` 断言取消会保存一条带“部分结果”标签的历史，且错误/纯思考输出不再新增。
- CI 新增 `Offline App Runtime Tests` 与 `Benchmark Smoke`（只验证基准可编译、不崩溃，不做数值门禁；数值对比仍见 `docs/benchmarks/` 与重构报告）。
- 审计门禁新增：MIT LICENSE 存在性、README 引用、取消保存部分结果的模式三项检查。

## 文档治理

- `docs/` 下 1.x 的 83 份迭代报告与 83 份发布说明移入 `docs/archive/1.x/`（共 166 个文件，仅移动未改内容）。`docs/` 根保留 2.x release notes、重构报告与迁移/模块文档。
- 此后每次修改都需同步更新开发文档：在对应版本 release notes（或 `docs/REFACTOR_REPORT_*.md`）中记录变更内容，本次即按此执行。

## 兼容性

- 不改变更新包的下载、校验与安装安全链路；manifest 公钥、bundle id、签名连续性校验保持不变。
- 需要 macOS 14 或更高版本，发布包为 Apple Silicon 构建。
- 提供 ZIP、签名 manifest、签名文件与 SBOM。应用仍采用自签名分发，尚无 Apple notarization；首次安装步骤见 README。
