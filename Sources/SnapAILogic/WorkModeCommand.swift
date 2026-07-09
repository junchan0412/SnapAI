import Foundation

public struct WorkModeCommandInput: Equatable {
    public var id: String
    public var title: String
    public var shortTitle: String
    public var summary: String
    public var systemImage: String
    public var keywords: String
    public var isCurrent: Bool

    public init(id: String,
                title: String,
                shortTitle: String,
                summary: String,
                systemImage: String,
                keywords: String,
                isCurrent: Bool) {
        self.id = id
        self.title = title
        self.shortTitle = shortTitle
        self.summary = summary
        self.systemImage = systemImage
        self.keywords = keywords
        self.isCurrent = isCurrent
    }
}

public enum WorkModeCommandAction: Equatable {
    case apply(String)
}

public struct WorkModeCommandDescriptor: Equatable {
    public var id: String
    public var title: String
    public var subtitle: String
    public var systemImage: String
    public var keywords: String
    public var action: WorkModeCommandAction
}

public enum WorkModeCommandFactory {
    public static func descriptors(modes: [WorkModeCommandInput]) -> [WorkModeCommandDescriptor] {
        modes.map { mode in
            WorkModeCommandDescriptor(
                id: "work-mode-\(mode.id)",
                title: "切换到\(mode.title)",
                subtitle: (mode.isCurrent ? "当前 - " : "") + mode.summary,
                systemImage: mode.isCurrent ? "checkmark.circle.fill" : mode.systemImage,
                keywords: MarkdownExportSafety.keywords([
                    "settings workflow work mode preset privacy route history 模式 工作模式 预设 隐私 路由 历史",
                    mode.shortTitle,
                    mode.title,
                    mode.summary,
                    mode.keywords
                ]),
                action: .apply(mode.id)
            )
        }
    }
}
