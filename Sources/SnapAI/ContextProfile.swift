import Foundation

struct ContextProfile: Codable, Identifiable, Equatable {
    var id: String = UUID().uuidString
    var name: String
    var content: String
    var isEnabled: Bool = true

    static func defaults() -> [ContextProfile] {
        [
            ContextProfile(name: "通用上下文", content: "", isEnabled: false)
        ]
    }
}
