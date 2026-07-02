import Foundation
import CoreGraphics

enum SettingsSection: String, CaseIterable, Identifiable, Hashable {
    case ai
    case actions
    case history
    case general
    case permission

    var id: String { rawValue }

    var title: String {
        switch self {
        case .ai: return "AI 模型"
        case .actions: return "动作"
        case .history: return "历史"
        case .general: return "通用"
        case .permission: return "权限"
        }
    }

    var icon: String {
        switch self {
        case .ai: return "cpu"
        case .actions: return "wand.and.stars"
        case .history: return "clock.arrow.circlepath"
        case .general: return "slider.horizontal.3"
        case .permission: return "checkmark.shield"
        }
    }

    var subtitle: String {
        switch self {
        case .ai:
            return "供应商、模型、路由策略"
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

    var tabWidth: CGFloat {
        switch self {
        case .ai: return 96
        case .actions: return 82
        case .history: return 82
        case .general: return 82
        case .permission: return 82
        }
    }
}
