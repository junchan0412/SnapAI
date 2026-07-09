import Foundation

public enum DiffRowKind: String {
    case unchanged
    case inserted
    case deleted
    case changed
}

public struct TextDiffRow: Identifiable, Equatable {
    public let id = UUID()
    public var original: String?
    public var revised: String?
    public var kind: DiffRowKind
}

public struct TextDiffSummary: Equatable {
    public var inserted: Int = 0
    public var deleted: Int = 0
    public var changed: Int = 0

    public var hasChanges: Bool {
        inserted > 0 || deleted > 0 || changed > 0
    }
}

public enum TextDiff {
    private static let lcsCellLimit = 120_000

    public static func rows(original: String, revised: String, maxRows: Int? = nil) -> [TextDiffRow] {
        let left = splitLines(original)
        let right = splitLines(revised)
        guard left != right else {
            let visible = maxRows.map { Array(left.prefix($0)) } ?? left
            return visible.map { TextDiffRow(original: $0, revised: $0, kind: .unchanged) }
        }
        guard left.count * right.count <= lcsCellLimit else {
            var rows: [TextDiffRow] = []
            appendChangedBlock(left: left, right: right, rows: &rows, maxRows: maxRows)
            return rows
        }

        var rows: [TextDiffRow] = []
        let pairs = lcsPairs(left, right)
        var leftIndex = 0
        var rightIndex = 0

        for pair in pairs {
            appendChangedBlock(left: Array(left[leftIndex..<pair.left]),
                               right: Array(right[rightIndex..<pair.right]),
                               rows: &rows,
                               maxRows: maxRows)
            guard canAppend(rows, maxRows: maxRows) else { return rows }
            rows.append(TextDiffRow(original: left[pair.left], revised: right[pair.right], kind: .unchanged))
            leftIndex = pair.left + 1
            rightIndex = pair.right + 1
        }

        appendChangedBlock(left: Array(left[leftIndex..<left.count]),
                           right: Array(right[rightIndex..<right.count]),
                           rows: &rows,
                           maxRows: maxRows)
        return rows
    }

    public static func summary(for rows: [TextDiffRow]) -> TextDiffSummary {
        rows.reduce(TextDiffSummary()) { partial, row in
            var next = partial
            switch row.kind {
            case .inserted:
                next.inserted += 1
            case .deleted:
                next.deleted += 1
            case .changed:
                next.changed += 1
            case .unchanged:
                break
            }
            return next
        }
    }

    private static func splitLines(_ text: String) -> [String] {
        let normalized = text.replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        let lines = normalized.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        return lines.isEmpty ? [""] : lines
    }

    private static func appendChangedBlock(left: [String],
                                           right: [String],
                                           rows: inout [TextDiffRow],
                                           maxRows: Int?) {
        let paired = min(left.count, right.count)
        if paired > 0 {
            for index in 0..<paired {
                guard canAppend(rows, maxRows: maxRows) else { return }
                rows.append(TextDiffRow(original: left[index], revised: right[index], kind: .changed))
            }
        }
        if left.count > paired {
            for item in left[paired...] {
                guard canAppend(rows, maxRows: maxRows) else { return }
                rows.append(TextDiffRow(original: item, revised: nil, kind: .deleted))
            }
        }
        if right.count > paired {
            for item in right[paired...] {
                guard canAppend(rows, maxRows: maxRows) else { return }
                rows.append(TextDiffRow(original: nil, revised: item, kind: .inserted))
            }
        }
    }

    private static func canAppend(_ rows: [TextDiffRow], maxRows: Int?) -> Bool {
        guard let maxRows else { return true }
        return rows.count < maxRows
    }

    private static func lcsPairs(_ left: [String], _ right: [String]) -> [(left: Int, right: Int)] {
        guard !left.isEmpty, !right.isEmpty else { return [] }
        var table = Array(
            repeating: Array(repeating: 0, count: right.count + 1),
            count: left.count + 1
        )

        for i in stride(from: left.count - 1, through: 0, by: -1) {
            for j in stride(from: right.count - 1, through: 0, by: -1) {
                if left[i] == right[j] {
                    table[i][j] = table[i + 1][j + 1] + 1
                } else {
                    table[i][j] = max(table[i + 1][j], table[i][j + 1])
                }
            }
        }

        var pairs: [(left: Int, right: Int)] = []
        var i = 0
        var j = 0
        while i < left.count, j < right.count {
            if left[i] == right[j] {
                pairs.append((i, j))
                i += 1
                j += 1
            } else if table[i + 1][j] >= table[i][j + 1] {
                i += 1
            } else {
                j += 1
            }
        }
        return pairs
    }
}
