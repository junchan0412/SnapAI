import Foundation

#if !SNAPAI_MANUAL_TEST_MAIN
  @testable import SnapAILogic
#endif

func testWriteBackSourceValidationRejectsStaleConfirmation() {
  let original = "预算 12,500 元"
  expect(TextWriteBackSourceValidation.sourceFailure(
    original: original, capturedText: original, originalRangeText: original) == nil,
    "unchanged original range allows replacement")
  expect(TextWriteBackSourceValidation.sourceFailure(
    original: original, capturedText: original, originalRangeText: "预算 12,800 元") == .sourceChanged,
    "a changed amount blocks the previously confirmed response")
  expect(TextWriteBackSourceValidation.sourceFailure(
    original: original, capturedText: original, originalRangeText: "[人工更新]预算") == .sourceChanged,
    "inserted source text cannot be overwritten using the old range")
  expect(TextWriteBackSourceValidation.sourceFailure(
    original: "其他原文", capturedText: original, originalRangeText: original) == .sourceChanged,
    "a response from another source cannot reuse a captured range")
  expect(TextWriteBackSourceValidation.sourceFailure(
    original: original, capturedText: original, originalRangeText: nil) == .unavailable,
    "unreadable source remains unverified")

  let updatedDocument = "预算 12,500 元\n未选中的备注已修改"
  expect(TextWriteBackSourceValidation.sourceFailure(
    original: original, capturedText: original,
    originalRangeText: TextCapture.selectedSubstring(
      in: updatedDocument, range: CFRange(location: 0, length: original.utf16.count))) == nil,
    "edits outside the original range do not invalidate unchanged selected source text")

  expect(TextWriteBackSourceValidation.selectionFailure(
    original: original, selectedText: "其他段落", rangeMatchesSnapshot: false,
    requiresSelection: true) == .selectionChanged,
    "a different nonempty selection cannot authorize replacement")
  expect(TextWriteBackSourceValidation.selectionFailure(
    original: original, selectedText: original, rangeMatchesSnapshot: false,
    requiresSelection: true) == .selectionChanged,
    "identical text selected at another range is a different target")
  expect(TextWriteBackSourceValidation.selectionFailure(
    original: original, selectedText: "", rangeMatchesSnapshot: false,
    requiresSelection: false) == nil,
    "a cleared selection may be restored after source and target validation")
  expect(TextWriteBackSourceValidation.selectionFailure(
    original: original, selectedText: "", rangeMatchesSnapshot: false,
    requiresSelection: true) == .selectionChanged,
    "selection lost again during the paste delay blocks insertion at the caret")
  expect(TextWriteBackSourceValidation.selectionFailure(
    original: original, selectedText: nil, rangeMatchesSnapshot: false,
    requiresSelection: true) == .unavailable,
    "missing AX selection data is not reported as validation success")

  for failure in [TextWriteBackValidationFailure.sourceChanged, .selectionChanged, .targetChanged, .pasteboardChanged] {
    expect(TextWriteBackSourceValidation.requiresBlocking(failure, allowsUnverifiedReplacement: true),
           "manual compatibility confirmation cannot bypass a known source or target mismatch")
    expect(!failure.recoveryMessage.isEmpty,
           "blocked writes provide an actionable recovery message")
  }
  expect(TextWriteBackSourceValidation.requiresBlocking(.unavailable,
                                                        allowsUnverifiedReplacement: false),
         "clipboard compatibility requires a new explicit confirmation when AX cannot validate")
  expect(!TextWriteBackSourceValidation.requiresBlocking(.unavailable,
                                                         allowsUnverifiedReplacement: true),
         "explicit confirmation preserves compatibility without claiming AX validation")
  expect(!TextWriteBackSourceValidation.requiresBlocking(nil, allowsUnverifiedReplacement: false),
         "verified writes do not need an additional compatibility confirmation")
  let unanchoredMatch = TextWriteBackSourceValidation.unanchoredSelectionFailure(
    original: original, selectedText: original)
  expect(unanchoredMatch == .unavailable,
         "matching text without the captured target and range is never reported as verified")
  expect(TextWriteBackSourceValidation.requiresBlocking(unanchoredMatch,
                                                        allowsUnverifiedReplacement: false),
         "identical text in another document or duplicate range still requires explicit confirmation")
  expect(!TextWriteBackSourceValidation.requiresBlocking(unanchoredMatch,
                                                         allowsUnverifiedReplacement: true),
         "an unanchored match can proceed only through the explicit compatibility confirmation")
  expect(TextWriteBackSourceValidation.unanchoredSelectionFailure(
    original: original, selectedText: "已修改内容") == .selectionChanged,
         "newly readable mismatched selection cannot bypass source validation")
  expect(TextWriteBackSourceValidation.pasteboardFailure(expectedChangeCount: 12,
                                                         currentChangeCount: 12) == nil,
         "unchanged injected clipboard may be pasted after focus and selection delays")
  expect(TextWriteBackSourceValidation.pasteboardFailure(expectedChangeCount: 12,
                                                         currentChangeCount: 13) == .pasteboardChanged,
         "user clipboard changes during preparation must abort before posting Cmd-V")
  expect(!TextCapture.shouldRestorePasteboard(expectedChangeCount: 12, currentChangeCount: 13),
         "aborting a clipboard race does not restore an older snapshot over user data")
}
