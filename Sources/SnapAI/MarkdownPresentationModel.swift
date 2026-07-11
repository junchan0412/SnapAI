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
    private var generation = 0
    private var requestedText = ""

    func refresh(text: String) {
        if result.sourceText == text, result.presentation != nil { return }
        generation += 1
        let requestGeneration = generation
        requestedText = text

        refreshQueue.async { [weak self] in
            guard self != nil else { return }
            let presentation = MarkdownPresentationBuilder.build(text)
            Task { @MainActor [weak self] in
                guard let self,
                      MarkdownPresentationRefreshPolicy.shouldPublish(
                        requestGeneration: requestGeneration,
                        currentGeneration: self.generation,
                        requestedText: text,
                        currentText: self.requestedText
                      ) else { return }
                self.result = Result(sourceText: text, presentation: presentation)
            }
        }
    }

    func presentation(for text: String) -> MarkdownPresentation? {
        result.sourceText == text ? result.presentation : nil
    }
}
