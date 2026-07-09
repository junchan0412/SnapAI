import Foundation

public struct TypewriterSpeedCommandInput: Equatable {
    public var id: String
    public var title: String
    public var isCurrent: Bool

    public init(id: String,
                title: String,
                isCurrent: Bool) {
        self.id = id
        self.title = title
        self.isCurrent = isCurrent
    }
}

public enum DisplayBehaviorCommandAction: Equatable {
    case setDockIcon(Bool)
    case setLoginItem(Bool)
    case setTypewriterSpeed(String)
}

public struct DisplayBehaviorCommandDescriptor: Equatable {
    public var id: String
    public var title: String
    public var subtitle: String
    public var systemImage: String
    public var keywords: String
    public var action: DisplayBehaviorCommandAction
}

public enum DisplayBehaviorCommandFactory {
    public static func descriptors(showDockIcon: Bool,
                                   loginItemEnabled: Bool,
                                   typewriterSpeeds: [TypewriterSpeedCommandInput]) -> [DisplayBehaviorCommandDescriptor] {
        var result = [
            DisplayBehaviorCommandDescriptor(
                id: "dock-icon-toggle",
                title: showDockIcon ? "隐藏 Dock 图标" : "显示 Dock 图标",
                subtitle: showDockIcon ? "当前已显示" : "当前仅菜单栏常驻",
                systemImage: "dock.rectangle",
                keywords: "settings dock icon menu bar display 显示 Dock 图标 菜单栏",
                action: .setDockIcon(!showDockIcon)
            ),
            DisplayBehaviorCommandDescriptor(
                id: "login-item-toggle",
                title: loginItemEnabled ? "关闭开机启动" : "开启开机启动",
                subtitle: loginItemEnabled ? "当前已开启" : "登录系统时自动启动 SnapAI",
                systemImage: loginItemEnabled ? "power.circle.fill" : "power.circle",
                keywords: "settings login item launch startup boot 开机 启动 登录 自启",
                action: .setLoginItem(!loginItemEnabled)
            )
        ]

        for speed in typewriterSpeeds {
            result.append(DisplayBehaviorCommandDescriptor(
                id: "typewriter-\(speed.id)",
                title: "打字机速度: \(speed.title)",
                subtitle: speed.isCurrent ? "当前速度" : subtitle(for: speed.id),
                systemImage: speed.isCurrent ? "checkmark.circle.fill" : "text.cursor",
                keywords: "settings typewriter animation speed result typing 打字机 动效 速度 结果 \(speed.title)",
                action: .setTypewriterSpeed(speed.id)
            ))
        }

        return result
    }

    public static func subtitle(for speedID: String) -> String {
        switch speedID {
        case "关闭", "off":
            return "直接显示完整结果"
        case "慢", "slow":
            return "更慢地显示流式结果"
        case "标准", "normal", "standard":
            return "标准流式显示速度"
        case "快", "fast":
            return "更快地显示流式结果"
        default:
            return "调整结果面板打字机动画速度"
        }
    }
}
