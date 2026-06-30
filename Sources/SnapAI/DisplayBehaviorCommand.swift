import Foundation

enum DisplayBehaviorCommandAction: Equatable {
    case setDockIcon(Bool)
    case setLoginItem(Bool)
    case setTypewriterSpeed(TypewriterSpeed)
}

struct DisplayBehaviorCommandDescriptor: Equatable {
    var id: String
    var title: String
    var subtitle: String
    var systemImage: String
    var keywords: String
    var action: DisplayBehaviorCommandAction
}

enum DisplayBehaviorCommandFactory {
    static func descriptors(showDockIcon: Bool,
                            loginItemEnabled: Bool,
                            typewriterSpeed: TypewriterSpeed) -> [DisplayBehaviorCommandDescriptor] {
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

        for speed in TypewriterSpeed.allCases {
            let isCurrent = typewriterSpeed == speed
            result.append(DisplayBehaviorCommandDescriptor(
                id: "typewriter-\(speed.id)",
                title: "打字机速度: \(speed.rawValue)",
                subtitle: isCurrent ? "当前速度" : subtitle(for: speed),
                systemImage: isCurrent ? "checkmark.circle.fill" : "text.cursor",
                keywords: "settings typewriter animation speed result typing 打字机 动效 速度 结果 \(speed.rawValue)",
                action: .setTypewriterSpeed(speed)
            ))
        }

        return result
    }

    static func subtitle(for speed: TypewriterSpeed) -> String {
        switch speed {
        case .off:
            return "直接显示完整结果"
        case .slow:
            return "更慢地显示流式结果"
        case .normal:
            return "标准流式显示速度"
        case .fast:
            return "更快地显示流式结果"
        }
    }
}
