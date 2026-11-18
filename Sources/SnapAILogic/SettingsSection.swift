import Foundation
import CoreGraphics

public enum SettingsSection: String, CaseIterable, Identifiable, Hashable {
    case model
    case provider
    case actions
    case history
    case general
    case permission

    public var id: String { rawValue }

    /// 主侧栏合并展示的导航项（供应商配置已整合进「模型与服务」页）。
    public static let sidebarSections: [SettingsSection] = [
        .model, .actions, .history, .general, .permission
    ]

    /// 对应到主侧栏的规范分区。
    public var sidebarSection: SettingsSection {
        self == .provider ? .model : self
    }

    /// 旧 `ai` 分区的持久化/自动化别名。重命名后仍能解析回来。
    public init?(resolvingLegacy rawValue: String) {
        if rawValue == "ai" {
            self = .model
            return
        }
        self.init(rawValue: rawValue)
    }

    public var titleKey: String {
        switch self {
        case .model: return "AI Model"
        case .provider: return "AI Providers"
        case .actions: return "Actions"
        case .history: return "History"
        case .general: return "General"
        case .permission: return "Permissions"
        }
    }

    public var title: String {
        switch self {
        case .model: return "模型与服务"
        case .provider: return "AI 供应商"
        case .actions: return "动作与快捷键"
        case .history: return "历史与会话"
        case .general: return "通用与隐私"
        case .permission: return "权限与诊断"
        }
    }

    public var icon: String {
        switch self {
        case .model: return "cpu"
        case .provider: return "network"
        case .actions: return "sparkles.rectangle.stack"
        case .history: return "clock.arrow.circlepath"
        case .general: return "slider.horizontal.3"
        case .permission: return "checkmark.shield"
        }
    }

    public var subtitle: String {
        switch self {
        case .model, .provider:
            return "工作模型、智能路由、供应商配置与用量概览"
        case .actions:
            return "全局唤起热键、动作指令模板与写回策略"
        case .history:
            return "搜索历史记录、恢复本地会话与保留策略"
        case .general:
            return "启动与面板行为、跨应用取词、隐私脱敏与同步"
        case .permission:
            return "系统权限状态、热键检测与本地运行诊断"
        }
    }

    public var tabWidth: CGFloat {
        switch self {
        case .model: return 96
        case .provider: return 96
        case .actions: return 96
        case .history: return 88
        case .general: return 88
        case .permission: return 88
        }
    }
}
