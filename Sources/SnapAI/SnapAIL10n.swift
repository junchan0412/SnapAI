import Foundation

/// 统一简体中文界面文案中心:避免 SwiftPM / Preview 环境下因默认 locale 回退成中英混排。
package enum SnapAIL10n {
    private static let zhTable: [String: String] = [
        "Quick Input": "快捷提问",
        "Send": "发送",
        "Sent": "已发送",
        "Ask a question, or paste text…": "输入问题、粘贴文本，或添加截图…",
        "What would you like to know about this image?": "想了解这张图片的什么？",
        "Screenshot": "截图",
        "Capturing": "截图中…",
        "Paste Image": "粘贴图片",
        "Close Quick Input (Esc)": "关闭快捷提问 (Esc)",
        "Send Prompt (Return)": "发送提问 (↩)",
        "Request Details": "请求与路由详情",
        "Hide request details": "收起请求详情",
        "View model, route, timing and diagnostics": "查看模型、路由、耗时与诊断",
        "Settings": "设置",
        "AI Model": "模型与服务",
        "AI Providers": "AI 供应商",
        "Actions": "动作与快捷键",
        "History": "历史与会话",
        "General": "通用与隐私",
        "Permissions": "权限与诊断",
        "Compare Models": "双模型对照",
        "Model Comparison": "双模型对照",
        "Usage": "用量统计",
        "Copy": "复制",
        "Cancel": "取消",
        "Delete": "删除",
        "Retry": "重试",
        "Done": "完成",
        "Search": "搜索",
        "Send Follow-up": "发送追问"
    ]

    package static func string(_ key: String, comment: String = "") -> String {
        if let zh = zhTable[key] {
            return zh
        }
        return NSLocalizedString(key, tableName: nil, bundle: .main, value: key, comment: comment)
    }

    package static func format(_ key: String, _ arguments: CVarArg...) -> String {
        String(format: string(key), arguments: arguments)
    }
}
