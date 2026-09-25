import Foundation

/// 双模型对照(A/B):同一输入发两个模型,并排展示,差异行高亮。
///
/// 设计约束:
/// 1. 纯值类型 + 纯函数,可测试;不持有 ViewModel、不碰网络。
/// 2. 输入是两段已完成文本(调用方各自用 ResultViewModel 跑完后传入),
///    本类型只负责"配对展示":行对齐、差异统计、胜负无关的中立摘要。
/// 3. 复用 TextDiff 的行级 diff,不另起 diff 算法。
package struct ModelCompare {
    package struct Side: Equatable {
        package var title: String
        package var text: String
        package var characterCount: Int { text.count }

        package init(title: String, text: String) {
            self.title = title
            self.text = text
        }
    }

    package struct ComparedSide: Equatable {
        package var side: Side
        package var rows: [TextDiffRow]
        /// 变更行数(relative to 另一侧),用于标题徽标。
        package var changedLineCount: Int
    }

    package struct Comparison: Equatable {
        package var left: ComparedSide
        package var right: ComparedSide
        package var summary: TextDiffSummary
        /// 两侧是否逐字相同。
        package var isIdentical: Bool
    }

    package static func compare(left: Side, right: Side, maxRows: Int? = 1_000) -> Comparison {
        let rows = TextDiff.rows(original: left.text, revised: right.text, maxRows: maxRows)
        let summary = TextDiff.summary(for: rows)
        let changed = rows.filter { $0.kind != .unchanged }.count
        return Comparison(
            left: ComparedSide(side: left, rows: rows, changedLineCount: changed),
            right: ComparedSide(side: right, rows: rows, changedLineCount: changed),
            summary: summary,
            isIdentical: left.text == right.text
        )
    }

    package static func summaryText(for comparison: Comparison) -> String {
        if comparison.isIdentical {
            return "两侧输出完全一致"
        }
        let summary = comparison.summary
        var parts: [String] = []
        if summary.changed > 0 { parts.append("改动 \(summary.changed) 行") }
        if summary.inserted > 0 { parts.append("新增 \(summary.inserted) 行") }
        if summary.deleted > 0 { parts.append("删除 \(summary.deleted) 行") }
        guard !parts.isEmpty else { return "两侧输出一致" }
        return parts.joined(separator: "、")
    }
}
