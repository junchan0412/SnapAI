import Combine
import Dispatch
import SnapAILogic

@MainActor
final class MarkdownPresentationModel: ObservableObject {
    struct Result: Equatable {
        var sourceText: String = ""
        var presentation: MarkdownPresentation?
    }

    @Published private(set) var result = Result()

    private let refreshQueue = DispatchQueue(label: "com.snapai.markdown-presentation",
                                             qos: .userInitiated)
    private let build: @Sendable (String) -> MarkdownPresentation
    private var requestedText = ""
    private var pendingText: String?
    private var buildingText: String?

    init(build: @escaping @Sendable (String) -> MarkdownPresentation = { MarkdownPresentationBuilder.build($0) }) {
        self.build = build
    }

    func refresh(text: String) {
        requestedText = text
        if (result.sourceText == text && result.presentation != nil) || buildingText == text {
            pendingText = nil
            return
        }
        pendingText = text
        startNextBuild()
    }

    private func startNextBuild() {
        guard buildingText == nil, let text = pendingText else { return }
        buildingText = text
        pendingText = nil
        let build = build
        refreshQueue.async { [weak self] in
            guard self != nil else { return }
            let presentation = build(text)
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.buildingText = nil
                if self.requestedText == text {
                    self.result = Result(sourceText: text, presentation: presentation)
                    self.pendingText = nil
                }
                self.startNextBuild()
            }
        }
    }

    func presentation(for text: String) -> MarkdownPresentation? {
        result.sourceText == text ? result.presentation : nil
    }
}
