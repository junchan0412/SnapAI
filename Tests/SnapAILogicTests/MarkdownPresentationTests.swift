import Foundation

#if !SNAPAI_MANUAL_TEST_MAIN
@testable import SnapAILogic
#endif

func testMarkdownTablesPreserveCellsAndAlignment() {
    let presentation = MarkdownPresentationBuilder.build(#"""
    | 功能 | 状态 | 数量 |
    | :--- | :---: | ---: |
    | **表格** | a\|b | 3 |
    | 少一格 | 可读 |
    | 多一格 | 保留 | 4 | 忽略 |

    正文
    """#)
    expect(presentation.blocks.count == 2, "table stops before the next paragraph")
    guard case .table(let table) = presentation.blocks[0] else {
        expect(false, "markdown builds a native table")
        return
    }
    expect(table.alignments == [.leading, .center, .trailing], "table column alignment follows delimiters")
    expect(table.headers.map { String($0.characters) } == ["功能", "状态", "数量"], "table retains headers")
    expect(table.rows[0].map { String($0.characters) } == ["表格", "a|b", "3"],
           "table inline markdown and escaped pipes stay inside cells")
    expect(table.rows[1].map { String($0.characters) } == ["少一格", "可读", ""],
           "short rows pad missing columns")
    expect(table.rows[2].count == 3, "extra table cells do not misalign the grid")
    let noEdges = MarkdownPresentationBuilder.build("a | b\n--- | ---\nx | y")
    expect(noEdges.blocks.count == 1, "tables support omitted outer pipes")
    if case .table(let table) = noEdges.blocks[0] {
        expect(table.rows.count == 1, "table without outer pipes includes its row")
    } else { expect(false, "table without outer pipes is recognized") }
    for invalid in ["a | b\n-- | ---", "a | b\n::--- | ---", "a | b\n---"] {
        if case .paragraph = MarkdownPresentationBuilder.build(invalid).blocks.first {
            expect(true, "invalid delimiters remain plain text")
        } else { expect(false, "invalid delimiters must not become tables") }
    }
}

func testMarkdownListsPreserveNumberingNestingAndTasks() {
    let presentation = MarkdownPresentationBuilder.build("""
    7. 第一步
       2) 子步骤
       - [x] 完成
       - [ ] 待处理
         继续说明
    8. 第二步

    - 普通列表
    """)
    guard case .list(let items) = presentation.blocks[0] else {
        expect(false, "markdown builds semantic list items")
        return
    }
    expect(items.map(\.marker) == [.ordered(7), .ordered(2), .task(completed: true),
                                  .task(completed: false), .ordered(8)],
           "list markers retain starting numbers, mixed child types and task status")
    expect(items.map(\.depth) == [0, 1, 1, 1, 0], "nested lists return to the parent indentation")
    expect(String(items[3].content.characters) == "待处理\n继续说明", "indented continuation belongs to its list item")
    expect(presentation.blocks.count == 2, "blank line separates independent lists")
    let literal = MarkdownPresentationBuilder.build("1234567890. not a list\n1.no space")
    if case .paragraph = literal.blocks.first {
        expect(true, "malformed numbered markers remain text")
    } else { expect(false, "malformed numbered markers must not create a list") }
}

func testMarkdownCodeHighlightingPreservesSource() {
    let code = "let 文本 = \"https://example.com/中文\" // return 12\nreturn 42"
    let tokens = MarkdownCodeHighlighter.tokens(code, language: "Swift linenums")
    expect(tokens.map(\.text).joined() == code, "highlighting preserves original code including Unicode and whitespace")
    expect(tokens.contains { $0.kind == .keyword && $0.text == "let" }, "known language keywords are highlighted")
    expect(tokens.contains { $0.kind == .string && $0.text.contains("https://") }, "comment markers in strings stay strings")
    expect(tokens.contains { $0.kind == .comment && $0.text == "// return 12" }, "comments are not tokenized as keywords")
    expect(tokens.contains { $0.kind == .number && $0.text == "42" }, "numeric literals are highlighted")
    let unknown = MarkdownCodeHighlighter.tokens(code, language: "custom-dsl")
    expect(unknown.count == 1 && unknown[0].kind == .plain && unknown[0].text == code,
           "unknown languages fall back to exact plain source")
    let json = MarkdownCodeHighlighter.tokens(#"{"url":"a//b","enabled":true,"count":2}"#, language: "json")
    expect(!json.contains { $0.kind == .comment }, "JSON does not invent line comments")
    let python = MarkdownCodeHighlighter.tokens("def run():\n    return True # ok", language: "python")
    expect(python.contains { $0.kind == .keyword && $0.text == "True" }, "Python keyword casing is preserved")
    let sql = MarkdownCodeHighlighter.tokens("SELECT name FROM items", language: "sql")
    expect(sql.filter { $0.kind == .keyword }.map(\.text) == ["SELECT", "FROM"], "SQL keywords ignore case")
    let presentation = MarkdownPresentationBuilder.build("```swift\n\(code)\n```")
    expect(presentation.codeHighlights[0] == tokens, "code tokens are prepared with the background presentation")
}

func testMarkdownReadingPositionSurvivesReflow() {
    let position = MarkdownReadingPosition(viewportTop: 500, contentTop: 100, contentHeight: 1000)
    expect(position?.fraction == 0.4, "reading anchor tracks progress inside output instead of whole document")
    expect(position?.restoredTop(contentTop: 120, contentHeight: 1500, maximumScrollTop: 1800) == 720,
           "reading anchor follows content height and source-section movement")
    expect(position?.restoredTop(contentTop: 120, contentHeight: 1500, maximumScrollTop: 600) == 600,
           "reading anchor stays within scrollable bounds")
    expect(MarkdownReadingPosition(viewportTop: 50, contentTop: 100, contentHeight: 1000) == nil,
           "reading source above output does not trigger a jump")
    expect(MarkdownReadingPosition(viewportTop: 1200, contentTop: 100, contentHeight: 1000) == nil,
           "reading below output does not trigger a jump")
    expect(MarkdownReadingPosition(viewportTop: 100, contentTop: 100, contentHeight: 0) == nil,
           "unlaid-out content cannot create an invalid anchor")
}
