import Foundation

enum SettingsToggleCommand: CaseIterable {
    case privacyPreview
    case redaction
    case historyMetadataOnly
    case autoRoute
    case fallback

    var id: String {
        switch self {
        case .privacyPreview: return "toggle-privacy-preview"
        case .redaction: return "toggle-redaction"
        case .historyMetadataOnly: return "toggle-history-metadata"
        case .autoRoute: return "toggle-auto-route"
        case .fallback: return "toggle-fallback"
        }
    }

    static func resolve(_ query: String?) -> SettingsToggleCommand? {
        guard let rawQuery = query?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased(), !rawQuery.isEmpty else {
            return nil
        }
        let queryVariants = normalizedQueryVariants(rawQuery)
        if matches(queryVariants, aliases: ["privacy", "preview", "privacy-preview", "privacypreview", "发送前预览", "预览"]) {
            return .privacyPreview
        }
        if matches(queryVariants, aliases: ["redaction", "redact", "mask", "local-redaction", "localredaction", "脱敏", "本地脱敏"]) {
            return .redaction
        }
        if matches(queryVariants, aliases: [
            "history-metadata",
            "historymetadata",
            "history-metadata-only",
            "historymetadataonly",
            "metadata-history",
            "metadatahistory",
            "metadata-only",
            "metadataonly",
            "history-privacy",
            "historyprivacy",
            "历史元信息",
            "仅元信息",
            "历史隐私"
        ]) {
            return .historyMetadataOnly
        }
        if matches(queryVariants, aliases: ["auto-route", "autoroute", "route", "routing", "自动路由", "路由"]) {
            return .autoRoute
        }
        if matches(queryVariants, aliases: ["fallback", "failover", "fail-over", "backup", "backup-model", "backupmodel", "失败切换", "备用模型"]) {
            return .fallback
        }
        return allCases.first { command in
            !queryVariants.isDisjoint(with: normalizedQueryVariants(command.id.lowercased()))
        }
    }

    private static func matches(_ queryVariants: Set<String>, aliases: [String]) -> Bool {
        aliases.contains { alias in
            !queryVariants.isDisjoint(with: normalizedQueryVariants(alias.lowercased()))
        }
    }

    private static func normalizedQueryVariants(_ query: String) -> Set<String> {
        let dashed = query
            .replacingOccurrences(of: "_", with: "-")
            .replacingOccurrences(of: " ", with: "-")
        return [
            query,
            dashed,
            dashed.replacingOccurrences(of: "-", with: "")
        ]
    }

    var systemImage: String {
        switch self {
        case .privacyPreview: return "eye"
        case .redaction: return "text.badge.checkmark"
        case .historyMetadataOnly: return "clock.badge.checkmark"
        case .autoRoute: return "point.3.connected.trianglepath.dotted"
        case .fallback: return "arrow.triangle.2.circlepath"
        }
    }

    var keywords: String {
        switch self {
        case .privacyPreview:
            return "settings privacy preview prompt confirm 隐私 预览 发送前 确认"
        case .redaction:
            return "settings privacy redaction mask redact pii 脱敏 隐私"
        case .historyMetadataOnly:
            return "settings history privacy metadata only audit record 历史 隐私 元信息 审计 不保存原文"
        case .autoRoute:
            return "settings route model auto routing ai 自动路由 模型"
        case .fallback:
            return "settings fallback failover backup model route 备用模型 失败切换"
        }
    }

    func isEnabled(in settings: AppSettings) -> Bool {
        switch self {
        case .privacyPreview: return settings.privacyPreviewEnabled
        case .redaction: return settings.redactionEnabled
        case .historyMetadataOnly: return settings.historyContentStorage == .metadataOnly
        case .autoRoute: return settings.autoRouteEnabled
        case .fallback: return settings.fallbackEnabled
        }
    }

    func setEnabled(_ enabled: Bool, in settings: AppSettings) {
        switch self {
        case .privacyPreview:
            settings.privacyPreviewEnabled = enabled
        case .redaction:
            settings.redactionEnabled = enabled
        case .historyMetadataOnly:
            settings.historyContentStorage = enabled ? .metadataOnly : .full
        case .autoRoute:
            settings.autoRouteEnabled = enabled
        case .fallback:
            settings.fallbackEnabled = enabled
        }
    }

    func title(isEnabled: Bool) -> String {
        let action = isEnabled ? "关闭" : "开启"
        switch self {
        case .privacyPreview:
            return "\(action)发送前预览"
        case .redaction:
            return "\(action)本地脱敏"
        case .historyMetadataOnly:
            return "\(action)历史仅元信息"
        case .autoRoute:
            return "\(action)自动路由"
        case .fallback:
            return "\(action)失败自动切换"
        }
    }

    func subtitle(isEnabled: Bool) -> String {
        let state = isEnabled ? "当前已开启" : "当前已关闭"
        switch self {
        case .privacyPreview:
            return "\(state) - 发送前确认最终 Prompt"
        case .redaction:
            return "\(state) - 请求前应用本地脱敏规则"
        case .historyMetadataOnly:
            return "\(state) - 历史只保留动作、模型、时间和标签"
        case .autoRoute:
            return "\(state) - 按动作、文本和图片选择模型"
        case .fallback:
            return "\(state) - 请求失败时尝试备用模型"
        }
    }
}
