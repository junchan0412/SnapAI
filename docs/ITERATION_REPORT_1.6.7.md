# SnapAI 1.6.7 迭代报告

1.6.7 来自一轮稳定性审查:同步、数据库、更新校验和图片请求都属于“平时不显眼,失败时很伤用户信任”的链路。本轮目标是让这些路径更安全、更可诊断,并用逻辑测试固定关键边界。

## 已完成

- iCloud 配置同步从单纯写入配置升级为带 schema、时间、设备和 revision 的 payload。
- 多设备拉取策略新增本机回环、旧 revision、本机未上传修改和同 revision 其他设备冲突保护,避免静默覆盖。
- 设置页和权限健康中心会展示 iCloud 最近同步状态,诊断文本中也包含 revision、脏状态、远端设备和同步时间。
- HistoryStore 的 SQLite 写入路径改为 throwing API,事务失败时执行 rollback,并记录最近一次数据库错误。
- 历史数据库状态进入权限健康中心,用户可以复制诊断给维护者排查。
- 更新包 SHA256 从一次性 `Data(contentsOf:)` 改成分块读取,降低 release zip 变大后的内存峰值。
- 图片输入在原始数据限制之外,新增 base64 data URL 后大小估算和校验。
- 快捷提问图片压缩成功后显示压缩格式与大小;压缩失败或编码后仍超限时给出可见说明。
- 补齐 iCloud、SQLite、更新校验和图片 payload 的逻辑测试。

## 风险收敛

- iCloud 当前仍采用“保守跳过冲突”的策略,不会自动合并动作、模型或上下文。下一阶段可以在设置页提供冲突处理 UI,让用户选择采用远端、保留本机或导出对比。
- HistoryStore 现在会记录错误并返回失败,但部分调用方仍以“内存先更新”的方式保持 UI 响应。后续可把持久化失败提示做成更明显的非阻塞横幅。
- 更新器仍会调用系统 `codesign`、`ditto` 和 `openssl`。长期可以用更独立的 helper updater 与 Security.framework 原生验签降低外部命令依赖。

## 验证计划

- 空白 diff 检查。
- 逻辑测试。
- SwiftPM 构建。
- Release preflight,包含 release app bundle 构建、稳定签名、zip 打包、manifest 签名和 release zip 可安装性验证。

## 发布资产

完整 release 包应包含:

- `SnapAI-v1.6.7.zip`
- `snapai-manifest-v1.6.7.json`
- `snapai-manifest-v1.6.7.json.sig`
