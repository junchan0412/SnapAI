# SnapAI 1.6.7

SnapAI 1.6.7 聚焦同步、历史、更新和图片请求的稳定性。它让多设备配置同步更可解释,让历史数据库写入失败不再静默,也降低了更新包校验和图片请求在大 payload 场景下的内存与失败风险。

## 主要更新

- iCloud 配置同步 payload 新增 `schemaVersion`、`updatedAt`、`deviceID` 和 `revision`。
- 设置变更会标记本机待上传状态;拉取远端配置时会跳过本机未上传修改、旧 revision、同 revision 多设备冲突和本机回环 payload。
- 设置页的 iCloud 配置同步说明会显示最近同步状态和 revision。
- 权限健康中心与可复制诊断新增 iCloud 同步状态和历史数据库状态。
- 历史 SQLite 写入改为显式 throwing 事务;写入、删除、清空和全量替换失败时会 rollback 并记录最近错误。
- 更新包 SHA256 改为 `FileHandle` 分块读取并增量计算,避免整包读入内存。
- AI 图片请求会同时校验原始图片字节数和 base64 data URL 后的编码 payload 大小。
- 快捷提问截图和粘贴图片会在压缩成功后显示可见提示;压缩后仍超出编码限制时给出明确失败原因。
- 新增逻辑测试覆盖 iCloud payload 与冲突策略、HistoryStore 写入失败、流式 SHA256 和图片编码体积估算。

## 验证

- `git diff --check`
- `scripts/run-logic-tests.sh`
- `swift build`
- `SNAPAI_MANIFEST_PRIVATE_KEY="$HOME/.snapai/snapai-manifest-private.pem" scripts/preflight-release.sh`

## 发布资产

完整 release 包应包含:

- `SnapAI-v1.6.7.zip`
- `snapai-manifest-v1.6.7.json`
- `snapai-manifest-v1.6.7.json.sig`
