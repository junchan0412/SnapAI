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

    /// 旧 `ai` 分区的持久化/自动化别名。重命名后仍能解析回来。
    public init?(resolvingLegacy rawValue: String) {
        if rawValue == "ai" {
            self = .model
            return
        }
        self.init(rawValue: rawValue)
    }

    public var title: String {
        switch self {
        case .model: return "AI 模型"
        case .provider: return "AI 供应商"
        case .actions: return "动作"
        case .history: return "历史"
        case .general: return "通用"
        case .permission: return "权限"
        }
    }

    public var icon: String {
        switch self {
        case .model: return "cpu"
        case .provider: return "network"
        case .actions: return "wand.and.stars"
        case .history: return "clock.arrow.circlepath"
        case .general: return "slider.horizontal.3"
        case .permission: return "checkmark.shield"
        }
    }

    public var subtitle: String {
        switch self {
        case .model:
            return "当前模型、路由策略"
        case .provider:
            return "供应商、Key、模型列表"
        case .actions:
            return "动作模板、快捷键、写回行为"
        case .history:
            return "记录、筛选、上下文包"
        case .general:
            return "启动、显示、隐私、同步"
        case .permission:
            return "辅助功能与系统权限"
        }
    }

    public var tabWidth: CGFloat {
        switch self {
        case .model: return 96
        case .provider: return 96
        case .actions: return 82
        case .history: return 82
        case .general: return 82
        case .permission: return 82
        }
    }
}
