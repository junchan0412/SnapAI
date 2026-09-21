# SnapAI 1.6.47 迭代报告

## 背景

`TextCaptureDiagnostic.swift` 没有其它 symlink 消费者,但原实现直接引用 `TextCaptureMethod` 和 `TextCaptureFailureReason`。这些枚举仍属于取词实现簇,直接迁移会让 logic target 的公开 API 暴露 app target 的取词实现类型。

## 本轮完成

- 新增 `TextCaptureDiagnosticMethod` 与 `TextCaptureDiagnosticFailureReason`,保留原始 raw value 语义。
- `TextCaptureDiagnostic` 改为只依赖轻量诊断枚举,继续生成状态摘要和恢复建议。
- 新增 `TextCaptureDiagnosticAppBridge`,由 app target 将 `TextCaptureOutcome` 中的 method/failure reason 映射为诊断枚举。
- `AppDelegate+WriteBack` 的取词结果记录逻辑改用桥接后的诊断状态。
- `TextCaptureDiagnostic.swift` 迁入 `Sources/SnapAILogic`,并从 app target 删除重复源码。
- 下调 `SnapAILogic` symlink 上限并提升真实源码下限。

## 当前边界状态

- `SnapAILogic` 实体 Swift 源码:30 个。
- `SnapAILogic` 剩余 symlink:46 个。
- 取词/写回大簇仍未完成,后续需继续处理 `TextCapture`, `TextEditTransaction`, `WriteBackCommand` 等强耦合文件。
