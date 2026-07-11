import Foundation

public enum TextWriteBackOperation: Equatable {
  case replace
  case append

  public var diagnosticName: String {
    switch self {
    case .replace: return "replace"
    case .append: return "append"
    }
  }
}

public enum TextWriteBackTargetState: Equatable {
  case missing
  case running
  case terminated
  case currentApp

  public var diagnosticName: String {
    switch self {
    case .missing: return "missing"
    case .running: return "running"
    case .terminated: return "terminated"
    case .currentApp: return "current-app"
    }
  }
}

public enum TextWriteBackPayload {
  public static func appendPayload(for text: String) -> String {
    "\n" + text
  }
}

public enum TextWriteBackUndoState: Equatable {
  case available
  case expired
  case missingOriginal
  case missingReplacement
  case targetTerminated
  case targetIsCurrentApp

  public var diagnosticName: String {
    switch self {
    case .available: return "available"
    case .expired: return "expired"
    case .missingOriginal: return "missing-original"
    case .missingReplacement: return "missing-replacement"
    case .targetTerminated: return "target-terminated"
    case .targetIsCurrentApp: return "target-current-app"
    }
  }
}

public enum TextWriteBackStateResolver {
  public static func targetState(
    processIdentifier: Int32?,
    isTerminated: Bool,
    currentProcessIdentifier: Int32
  ) -> TextWriteBackTargetState {
    guard let processIdentifier else { return .missing }
    if isTerminated { return .terminated }
    if processIdentifier == currentProcessIdentifier { return .currentApp }
    return .running
  }
}

public struct TextWriteBackRecordState: Equatable {
  public static let expirationInterval: TimeInterval = 10 * 60

  public var targetName: String?
  public var targetState: TextWriteBackTargetState
  public var operation: TextWriteBackOperation
  public var originalText: String
  public var replacementText: String
  public var createdAt: Date

  public init(
    targetName: String?,
    targetState: TextWriteBackTargetState,
    operation: TextWriteBackOperation = .replace,
    originalText: String,
    replacementText: String,
    createdAt: Date = Date()
  ) {
    self.targetName = targetName
    self.targetState = targetState
    self.operation = operation
    self.originalText = originalText
    self.replacementText = replacementText
    self.createdAt = createdAt
  }

  public var isUndoAvailable: Bool {
    undoState() == .available
  }

  public func undoState(at date: Date = Date()) -> TextWriteBackUndoState {
    guard !replacementText.isEmpty,
      date.timeIntervalSince(createdAt) <= Self.expirationInterval
    else {
      return replacementText.isEmpty ? .missingReplacement : .expired
    }
    switch targetState {
    case .terminated:
      return .targetTerminated
    case .currentApp:
      return .targetIsCurrentApp
    case .missing, .running:
      break
    }
    switch operation {
    case .replace:
      return originalText.isEmpty ? .missingOriginal : .available
    case .append:
      return .available
    }
  }

  public var undoTitle: String {
    let appName = targetName ?? "原应用"
    switch operation {
    case .replace:
      return "撤销上次替换到 \(appName)"
    case .append:
      return "撤销上次追加到 \(appName)"
    }
  }

  public var diagnosticSummary: String {
    let undo = undoState()
    let state = undo == .available ? "available" : "unavailable"
    let appName = MarkdownExportSafety.metadata(
      targetName,
      fallback: "unknown",
      maxLength: 80)
    let age = max(0, Int(Date().timeIntervalSince(createdAt)))
    return
      "state=\(state), undo=\(undo.diagnosticName), operation=\(operation.diagnosticName), target=\(appName), targetState=\(targetState.diagnosticName), ageSeconds=\(age), originalChars=\(originalText.count), replacementChars=\(replacementText.count), recovery=\(recoverySuggestion)"
  }

  public var recoverySuggestion: String {
    switch undoState() {
    case .available:
      return "可通过命令面板或菜单撤销上次写回"
    case .expired:
      return "撤销窗口已过期; 请在目标应用中手动恢复"
    case .missingOriginal:
      return "缺少原文快照; 请在目标应用中手动恢复"
    case .missingReplacement:
      return "缺少写回内容; 请重新复制结果或手动恢复"
    case .targetTerminated:
      return "目标应用已退出; 请重新打开后手动恢复"
    case .targetIsCurrentApp:
      return "目标是 SnapAI; 请切回原应用后手动恢复"
    }
  }
}

public struct TextWriteBackUndoFallbackDiagnostic: Equatable {
  public var operation: TextWriteBackOperation
  public var undoState: TextWriteBackUndoState
  public var targetState: TextWriteBackTargetState
  public var targetName: String?
  public var reason: String
  public var copiedOriginalToPasteboard: Bool
  public var originalCharacterCount: Int
  public var replacementCharacterCount: Int
  public var recoveryOverride: String?

  public init(
    record: TextWriteBackRecordState,
    reason: String,
    copiedOriginalToPasteboard: Bool,
    recoveryOverride: String? = nil
  ) {
    operation = record.operation
    undoState = record.undoState()
    targetState = record.targetState
    targetName = record.targetName
    self.reason = reason
    self.copiedOriginalToPasteboard = copiedOriginalToPasteboard
    originalCharacterCount = max(0, record.originalText.count)
    replacementCharacterCount = max(0, record.replacementText.count)
    self.recoveryOverride = recoveryOverride
  }

  public var diagnosticSummary: String {
    let appName = MarkdownExportSafety.metadata(
      targetName,
      fallback: "unknown",
      maxLength: 80)
    let safeReason = SensitiveTextSanitizer.sanitizedMessage(reason, limit: 180)
    return [
      "state=undo-fallback",
      "undo=\(undoState.diagnosticName)",
      "operation=\(operation.diagnosticName)",
      "target=\(appName)",
      "targetState=\(targetState.diagnosticName)",
      "copiedOriginalToPasteboard=\(copiedOriginalToPasteboard ? "yes" : "no")",
      "originalChars=\(originalCharacterCount)",
      "replacementChars=\(replacementCharacterCount)",
      "recovery=\(recoverySuggestion)",
      "reason=\(safeReason.isEmpty ? "unknown" : safeReason)",
    ].joined(separator: ", ")
  }

  public var noticeMessage: String {
    let safeReason = SensitiveTextSanitizer.sanitizedMessage(reason, limit: 220)
    let normalizedReason = safeReason.isEmpty ? "无法自动撤销上次写回。" : safeReason
    return [normalizedReason, "建议: \(recoverySuggestion)"].joined(separator: "\n\n")
  }

  public var recoverySuggestion: String {
    if let recoveryOverride {
      let safeOverride = SensitiveTextSanitizer.sanitizedMessage(recoveryOverride, limit: 220)
      if !safeOverride.isEmpty { return safeOverride }
    }
    if copiedOriginalToPasteboard {
      return "替换前的原文已复制到剪贴板; 请回到目标应用手动粘贴恢复"
    }
    if let hint = WriteBackCompatibility.recoveryHint(for: targetName) {
      return hint
    }
    switch operation {
    case .replace:
      return "请在目标应用中使用系统撤销,或从历史记录中找回替换前内容"
    case .append:
      return "请在目标应用中使用系统撤销,或手动移除上次追加内容"
    }
  }
}

public struct TextWriteBackFallbackDiagnostic: Equatable {
  public var operation: TextWriteBackOperation
  public var targetState: TextWriteBackTargetState
  public var targetName: String?
  public var reason: String
  public var copiedToPasteboard: Bool
  public var originalCharacterCount: Int
  public var payloadCharacterCount: Int
  public var recoveryOverride: String?

  public init(
    operation: TextWriteBackOperation,
    targetState: TextWriteBackTargetState,
    targetName: String?,
    reason: String,
    copiedToPasteboard: Bool,
    originalCharacterCount: Int,
    payloadCharacterCount: Int,
    recoveryOverride: String? = nil
  ) {
    self.operation = operation
    self.targetState = targetState
    self.targetName = targetName
    self.reason = reason
    self.copiedToPasteboard = copiedToPasteboard
    self.originalCharacterCount = max(0, originalCharacterCount)
    self.payloadCharacterCount = max(0, payloadCharacterCount)
    self.recoveryOverride = recoveryOverride
  }

  public var diagnosticSummary: String {
    let appName = MarkdownExportSafety.metadata(
      targetName,
      fallback: "unknown",
      maxLength: 80)
    let safeReason = SensitiveTextSanitizer.sanitizedMessage(reason, limit: 180)
    return [
      "state=fallback-copied",
      "operation=\(operation.diagnosticName)",
      "target=\(appName)",
      "targetState=\(targetState.diagnosticName)",
      "copiedToPasteboard=\(copiedToPasteboard ? "yes" : "no")",
      "originalChars=\(originalCharacterCount)",
      "payloadChars=\(payloadCharacterCount)",
      "recovery=\(recoverySuggestion)",
      "reason=\(safeReason.isEmpty ? "unknown" : safeReason)",
    ].joined(separator: ", ")
  }

  public var noticeMessage: String {
    let safeReason = SensitiveTextSanitizer.sanitizedMessage(reason, limit: 220)
    let normalizedReason = safeReason.isEmpty ? "无法自动写回到目标应用。" : safeReason
    let pasteboardStatus = copiedToPasteboard ? "结果已复制到剪贴板。" : "结果未能自动复制到剪贴板。"
    return [normalizedReason, pasteboardStatus, "建议: \(recoverySuggestion)"].joined(
      separator: "\n\n")
  }

  public var recoverySuggestion: String {
    if let recoveryOverride {
      let safeOverride = SensitiveTextSanitizer.sanitizedMessage(recoveryOverride, limit: 220)
      if !safeOverride.isEmpty { return safeOverride }
    }
    var parts: [String] = []
    switch targetState {
    case .missing:
      parts.append("回到原应用后手动粘贴剪贴板内容")
    case .terminated:
      parts.append("重新打开目标应用后手动粘贴剪贴板内容")
    case .currentApp:
      parts.append("切回需要写入的应用后手动粘贴剪贴板内容")
    case .running:
      parts.append("确认目标输入框仍聚焦后手动粘贴剪贴板内容")
    }
    switch operation {
    case .replace:
      parts.append("如需替换请重新选中原文")
    case .append:
      parts.append("如需追加请定位到目标位置")
    }
    if let hint = WriteBackCompatibility.recoveryHint(for: targetName) {
      parts.append(hint)
    }
    if !copiedToPasteboard {
      parts.append("若剪贴板未更新请手动复制结果")
    }
    return parts.joined(separator: "; ")
  }
}

public enum TextEditTiming {
  public static func replacementPreparationDelay(
    hasAccessibleSelection: Bool,
    restoredSnapshot: Bool,
    assumeSelectionIsPreserved: Bool
  ) -> TimeInterval {
    if hasAccessibleSelection { return 0.03 }
    if restoredSnapshot { return 0.08 }
    if assumeSelectionIsPreserved { return 0.05 }
    return 0.03
  }
}
