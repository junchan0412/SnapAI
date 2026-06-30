import Foundation

enum WorkModeCommandAction: Equatable {
    case apply(WorkModePreset)
}

struct WorkModeCommandDescriptor: Equatable {
    var id: String
    var title: String
    var subtitle: String
    var systemImage: String
    var keywords: String
    var action: WorkModeCommandAction
}

enum WorkModeCommandFactory {
    static func descriptors(current: WorkModePreset?) -> [WorkModeCommandDescriptor] {
        WorkModePreset.allCases.map { mode in
            let isCurrent = current == mode
            return WorkModeCommandDescriptor(
                id: "work-mode-\(mode.id)",
                title: "切换到\(mode.title)",
                subtitle: (isCurrent ? "当前 - " : "") + mode.summary,
                systemImage: isCurrent ? "checkmark.circle.fill" : mode.systemImage,
                keywords: MarkdownExportSafety.keywords([
                    "settings workflow work mode preset privacy route history 模式 工作模式 预设 隐私 路由 历史",
                    mode.shortTitle,
                    mode.title,
                    mode.summary,
                    mode.keywords
                ]),
                action: .apply(mode)
            )
        }
    }
}
