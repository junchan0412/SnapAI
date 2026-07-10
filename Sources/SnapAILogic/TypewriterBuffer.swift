import Foundation

/// 按流式 chunk 保存尚未展示的文本，避免每个 UI tick 从完整结果开头重新索引和复制。
public struct TypewriterBuffer {
    private var chunks: [String] = []
    private var chunkIndex = 0
    private var characterIndex: String.Index?

    public init() {}

    public var isEmpty: Bool {
        chunkIndex >= chunks.count
    }

    public mutating func enqueue(_ text: String) {
        guard !text.isEmpty else { return }
        chunks.append(text)
    }

    public mutating func dequeue(maxCharacters: Int) -> String {
        guard maxCharacters > 0, !isEmpty else { return "" }
        var remaining = maxCharacters
        var result = ""

        while remaining > 0, chunkIndex < chunks.count {
            let chunk = chunks[chunkIndex]
            let start = characterIndex ?? chunk.startIndex
            let end = chunk.index(start,
                                  offsetBy: remaining,
                                  limitedBy: chunk.endIndex) ?? chunk.endIndex
            result.append(contentsOf: chunk[start..<end])
            remaining -= chunk.distance(from: start, to: end)

            if end == chunk.endIndex {
                chunkIndex += 1
                characterIndex = nil
            } else {
                characterIndex = end
            }
        }

        compactIfNeeded()
        return result
    }

    public mutating func removeAll() {
        chunks.removeAll(keepingCapacity: false)
        chunkIndex = 0
        characterIndex = nil
    }

    private mutating func compactIfNeeded() {
        if chunkIndex >= chunks.count {
            removeAll()
        } else if chunkIndex >= 64, chunkIndex * 2 >= chunks.count {
            chunks.removeFirst(chunkIndex)
            chunkIndex = 0
        }
    }
}
