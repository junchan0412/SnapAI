import Foundation

/// 本地化字符串集中管理:主路径 UI 先行,英文完整,中文回退。
///
/// 设计约束:
/// 1. 不引入 String Catalog(.xcstrings 需要 Xcode 工程,本仓库是纯 SwiftPM);
///    用 NSLocalizedString + Sources/SnapAI/Resources/{en,zh-Hans}.lproj。
/// 2. key 即英文原文:英文环境零翻译成本,中文按 key 查表;缺 key 回退英文。
/// 3. 动态插值一律用 String(format:) + 本地化格式串,不拼接句子。
/// 4. 逻辑层错误文案暂不进表(诊断文本需原文稳定可 grep);先覆盖 UI 主路径。
package enum SnapAIL10n {
    package static func string(_ key: String, comment: String = "") -> String {
        NSLocalizedString(key, tableName: nil, bundle: .main, value: key, comment: comment)
    }

    package static func format(_ key: String, _ arguments: CVarArg...) -> String {
        String(format: string(key), arguments: arguments)
    }
}
