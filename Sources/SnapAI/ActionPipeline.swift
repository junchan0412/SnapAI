import Foundation

struct ActionPipelineDiagnostic: Equatable {
    var inputPolicy: String
    var privacyPolicy: String
    var outputPolicy: String
    var modelPolicy: String

    var summaryLines: [String] {
        [
            "Pipeline Input: \(inputPolicy)",
            "Pipeline Privacy: \(privacyPolicy)",
            "Pipeline Output: \(outputPolicy)",
            "Pipeline Model: \(modelPolicy)"
        ]
    }

    static let empty = ActionPipelineDiagnostic(inputPolicy: "not-recorded",
                                                privacyPolicy: "not-recorded",
                                                outputPolicy: "not-recorded",
                                                modelPolicy: "not-recorded")

    static func make(action: AIAction,
                     settings: AppSettings,
                     hasImage: Bool,
                     captureMethod: TextCaptureMethod? = nil,
                     sourceKind: SelectionSourceKind? = nil) -> ActionPipelineDiagnostic {
        var inputParts = ["text"]
        if hasImage {
            inputParts.append("image")
        }
        if let captureMethod {
            inputParts.append("capture-\(captureMethod.rawValue)")
        }
        if let sourceKind {
            inputParts.append("source-\(sourceKind.rawValue)")
        }
        let input = inputParts.joined(separator: "+")

        var privacyParts: [String] = []
        if settings.privacyPreviewEnabled {
            privacyParts.append("preview")
        }
        if settings.redactionEnabled {
            privacyParts.append("local-redaction")
        }
        if !action.saveHistory {
            privacyParts.append("no-history")
        } else if settings.historyContentStorage == .metadataOnly {
            privacyParts.append("history-metadata-only")
        } else {
            privacyParts.append("history-full")
        }
        let privacy = privacyParts.joined(separator: "+")

        let output = action.replaceByDefault ? "replace-confirmation" : "result-panel"

        let model: String
        if action.providerID != nil || action.modelOverride != nil {
            model = "action-override"
        } else if settings.autoRouteEnabled {
            model = settings.prefersLocalModelRoutes ? "auto-route-local-first" : "auto-route"
        } else {
            model = "current-model"
        }

        return ActionPipelineDiagnostic(inputPolicy: input,
                                        privacyPolicy: privacy,
                                        outputPolicy: output,
                                        modelPolicy: model)
    }
}
