import Foundation

public enum WriteBackCoordinator {
    public static func replace(original: String,
                               replacement: String,
                               handler: ((String, String) -> Void)?) {
        guard !replacement.isEmpty else { return }
        handler?(original, replacement)
    }

    public static func append(text: String,
                              handler: ((String) -> Void)?) {
        guard !text.isEmpty else { return }
        handler?(text)
    }

    public static func shouldAutoReplace(recordUsage: Bool,
                                         autoReplaceEnabled: Bool,
                                         replaceByDefault: Bool,
                                         outputText: String,
                                         errorMessage: String?) -> Bool {
        recordUsage &&
        autoReplaceEnabled &&
        replaceByDefault &&
        !outputText.isEmpty &&
        errorMessage == nil
    }
}

public typealias ResultWriteBackCoordinator = WriteBackCoordinator
