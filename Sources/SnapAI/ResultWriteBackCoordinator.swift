import Foundation

enum WriteBackCoordinator {
    static func replace(original: String,
                        replacement: String,
                        handler: ((String, String) -> Void)?) {
        guard !replacement.isEmpty else { return }
        handler?(original, replacement)
    }

    static func append(text: String,
                       handler: ((String) -> Void)?) {
        guard !text.isEmpty else { return }
        handler?(text)
    }

    static func shouldAutoReplace(recordUsage: Bool,
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

typealias ResultWriteBackCoordinator = WriteBackCoordinator
