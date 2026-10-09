import XCTest
import AppKit
import MarginalCore
@testable import MarginalApp

final class EditorTests: XCTestCase {
    private var documents: [MarginalDocument] = []

    override func tearDown() {
        for document in documents {
            if let manager = document.undoManager {
                while manager.groupingLevel > 0 { manager.endUndoGrouping() }
                manager.removeAllActions()
            }
            document.close()
        }
        documents.removeAll()
        super.tearDown()
    }

    private func editor(_ source: String, defaults: UserDefaults? = nil) throws -> (MarginalDocument, EditorWindowController) {
        _ = NSApplication.shared
        let document = MarginalDocument()
        // Tests explicitly close groups to exercise undo without a running app event loop.
        // Disable automatic event grouping so async tests cannot later close those groups again.
        document.undoManager = UndoManager()
        document.undoManager!.groupsByEvent = false
        document.undoManager!.beginUndoGrouping()
        documents.append(document)
        try document.read(from: Data(source.utf8), ofType: "net.daringfireball.markdown")
        if let defaults {
            document.storage.setAttributedString(MarkdownCodec.render(source))
            document.addWindowController(EditorWindowController(document: document, defaults: defaults))
        } else { document.makeWindowControllers() }
        let controller = try XCTUnwrap(document.windowControllers.first as? EditorWindowController)
        controller.window?.makeFirstResponder(controller.editor)
        return (document, controller)
    }

    private func undo(_ document: MarginalDocument) {
        if let manager = document.undoManager {
            while manager.groupingLevel > 0 { manager.endUndoGrouping() }
            manager.undo()
        }
    }

    private func visualLines(_ controller: EditorWindowController) throws -> Int {
        let layout = try XCTUnwrap(controller.editor.layoutManager)
        let container = try XCTUnwrap(controller.editor.textContainer)
        layout.ensureLayout(for: container)
        var lines = 0
        layout.enumerateLineFragments(forGlyphRange: layout.glyphRange(for: container)) { _, _, _, _, _ in lines += 1 }
        return lines
    }

    func testZoomCompletesTextLayoutBeforeDrawing() throws {
        let suite = "Marginal.ZoomDrawingTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let source = String(repeating: "Text with **bold**, `code`, and a [link](https://example.com).\n\n", count: 400)
        let (document, controller) = try editor(source, defaults: defaults)
        let layout = try XCTUnwrap(controller.editor.layoutManager)
        controller.zoomIn(nil)
        // Reproduce pending layout after a zoom/clip change, without the test's
        // usual ensureLayout call hiding what happens in a real display pass.
        layout.invalidateLayout(forCharacterRange: NSRange(location: 0, length: document.storage.length), actualCharacterRange: nil)
        controller.editor.viewWillDraw()
        XCTAssertEqual(layout.firstUnlaidCharacterIndex(), document.storage.length)
        XCTAssertFalse(layout.hasNonContiguousLayout)
        XCTAssertFalse(document.hasEdits)
        XCTAssertEqual(document.markdown(), source)
    }

    func testZoomedClipResizeKeepsEditorAtViewportWidth() throws {
        let suite = "Marginal.ZoomClipTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let (_, controller) = try editor(String(repeating: "Some text to wrap. ", count: 80), defaults: defaults)
        controller.zoomIn(nil)
        let clip = controller.scroll.contentView
        for _ in 0..<10 {
            // A magnified clip has a different frame and bounds width. AppKit's
            // subview resizing must not repeatedly enlarge the document view.
            clip.resizeSubviews(withOldSize: clip.bounds.size)
            controller.editor.viewWillDraw()
            XCTAssertEqual(controller.editor.frame.width, clip.bounds.width, accuracy: 1)
        }
    }

    func testZoomReflowsWithoutChangingMarkdownOrSelection() throws {
        let suite = "Marginal.ZoomTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let source = "# Title\n\n" + String(repeating: "Words with **bold** and `code`. ", count: 80) + "\n"
        let (document, controller) = try editor(source, defaults: defaults)
        controller.window?.setContentSize(NSSize(width: 600, height: 500))
        controller.window?.contentView?.layoutSubtreeIfNeeded()
        let original = NSAttributedString(attributedString: document.storage)
        let selected = NSRange(location: 7, length: 5)
        controller.editor.setSelectedRange(selected)
        let lines = try visualLines(controller)
        let width = controller.editor.textContainer!.containerSize.width
        controller.zoomIn(nil)
        XCTAssertGreaterThan(controller.zoomLevel, 1)
        XCTAssertLessThan(controller.editor.textContainer!.containerSize.width, width)
        XCTAssertGreaterThan(try visualLines(controller), lines)
        XCTAssertEqual(controller.editor.selectedRange(), selected)
        XCTAssertEqual(document.storage, original)
        XCTAssertEqual(try document.data(ofType: "net.daringfireball.markdown"), Data(source.utf8))
        XCTAssertFalse(document.hasEdits)
        let (_, reloaded) = try editor("", defaults: defaults)
        XCTAssertEqual(reloaded.zoomLevel, controller.zoomLevel, accuracy: 0.001)
        controller.actualSize(nil)
        XCTAssertEqual(controller.zoomLevel, 1, accuracy: 0.001)
        controller.zoomOut(nil)
        XCTAssertLessThan(controller.zoomLevel, 1)
        XCTAssertEqual(document.storage, original)
    }

    func testWordWrapReflowsRenderedAndSourceWithoutInsertingLineBreaks() throws {
        let suite = "Marginal.WrapTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let source = String(repeating: "A long sentence to read. ", count: 80) + "\n"
        let (document, controller) = try editor(source, defaults: defaults)
        XCTAssertGreaterThan(try visualLines(controller), 1)
        controller.toggleWordWrap(nil)
        XCTAssertEqual(try visualLines(controller), 1)
        XCTAssertGreaterThan(controller.editor.frame.width, controller.scroll.contentView.bounds.width)
        XCTAssertTrue(controller.scroll.hasHorizontalScroller)
        let (_, reloaded) = try editor("", defaults: defaults)
        XCTAssertFalse(reloaded.wrapsLines)
        controller.toggleSource(nil)
        XCTAssertEqual(try visualLines(controller), 1)
        XCTAssertEqual(controller.editor.string, source)
        controller.toggleWordWrap(nil)
        XCTAssertGreaterThan(try visualLines(controller), 1)
        XCTAssertFalse(controller.scroll.hasHorizontalScroller)
        XCTAssertEqual(controller.editor.frame.width, controller.scroll.contentView.bounds.width, accuracy: 1)
        controller.zoomIn(nil)
        controller.toggleSource(nil)
        XCTAssertTrue(controller.wrapsLines)
        XCTAssertGreaterThan(try visualLines(controller), 1)
        XCTAssertEqual(try document.data(ofType: "net.daringfireball.markdown"), Data(source.utf8))
        XCTAssertFalse(document.hasEdits)
    }

    func testUnwrappedTableKeepsFiniteLayoutAndRemainsEditable() throws {
        let suite = "Marginal.TableWrapTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let source = "| Name | State |\n| --- | --- |\n| Marginal | Draft |\n"
        let (document, controller) = try editor(source, defaults: defaults)
        controller.toggleWordWrap(nil)
        _ = try visualLines(controller)
        let rect = controller.editor.layoutManager!.usedRect(for: controller.editor.textContainer!)
        XCTAssertTrue(rect.width.isFinite && rect.height.isFinite)
        XCTAssertLessThan(rect.width, 10_000)
        XCTAssertLessThan(controller.editor.frame.width, 10_000)
        XCTAssertEqual(try document.data(ofType: "net.daringfireball.markdown"), Data(source.utf8))
        controller.editor.insertText("Ready", replacementRange: (controller.editor.string as NSString).range(of: "Draft"))
        XCTAssertTrue(document.markdown().contains("| Marginal | Ready |"))
        undo(document)
        XCTAssertTrue(document.markdown().contains("| Marginal | Draft |"))
        controller.toggleWordWrap(nil)
        _ = try visualLines(controller)
        XCTAssertLessThan(controller.editor.layoutManager!.usedRect(for: controller.editor.textContainer!).width, 10_000)
    }

    func testOpeningAndSavingUntouchedFileIsByteIdentical() throws {
        let source = "# Title\r\n\r\nText with *emphasis* and [a link][ref].\r\n\r\n[ref]: https://example.com \"Title\"\r\n"
        let (document, _) = try editor(source)
        XCTAssertEqual(try document.data(ofType: "net.daringfireball.markdown"), Data(source.utf8))
        document.close()
    }

    func testRenderedEditSavesMarkdown() throws {
        let (document, controller) = try editor("# Title\n\nHello **world**.\n")
        let range = (controller.editor.string as NSString).range(of: "world")
        controller.editor.setSelectedRange(range)
        controller.editor.insertText("Mac", replacementRange: range)
        XCTAssertTrue(document.hasEdits)
        XCTAssertTrue(document.markdown().contains("**Mac**"))
        XCTAssertTrue(document.markdown().contains("# Title"))
        document.close()
    }

    func testFormattingAndUndo() throws {
        let (document, controller) = try editor("Hello world.\n")
        controller.editor.setSelectedRange(NSRange(location: 6, length: 5))
        controller.editor.bold(nil)
        XCTAssertTrue(document.markdown().contains("**world**"))
        undo(document)
        XCTAssertFalse(document.markdown().contains("**world**"))
        document.close()
    }

    func testHeadingThenReturnStartsBody() throws {
        let (document, controller) = try editor("# Hello\n")
        controller.editor.setSelectedRange(NSRange(location: 5, length: 0))
        controller.editor.insertNewline(nil)
        controller.editor.insertText("Body", replacementRange: controller.editor.selectedRange())
        XCTAssertEqual(document.markdown(), "# Hello\n\nBody\n")
        document.close()
    }

    func testListContinuationAndExit() throws {
        let (document, controller) = try editor("- One\n")
        controller.editor.setSelectedRange(NSRange(location: 5, length: 0))
        controller.editor.insertNewline(nil)
        controller.editor.insertText("Two", replacementRange: controller.editor.selectedRange())
        XCTAssertTrue(document.markdown().contains("- One\n- Two"))
        controller.editor.insertNewline(nil)
        controller.editor.insertNewline(nil)
        controller.editor.insertText("Body", replacementRange: controller.editor.selectedRange())
        XCTAssertTrue(document.markdown().contains("\n\nBody"))
        document.close()
    }

    func testSourceSwitchingAndUndo() throws {
        let (document, controller) = try editor("# Hello\n")
        controller.toggleSource(nil)
        while document.undoManager!.groupingLevel > 0 { document.undoManager!.endUndoGrouping() }
        XCTAssertTrue(document.sourceMode)
        XCTAssertEqual(controller.editor.string, "# Hello\n")
        let range = (controller.editor.string as NSString).range(of: "Hello")
        document.undoManager!.beginUndoGrouping()
        controller.editor.insertText("Edited", replacementRange: range)
        controller.editor.breakUndoCoalescing()
        while document.undoManager!.groupingLevel > 0 { document.undoManager!.endUndoGrouping() }
        document.undoManager!.beginUndoGrouping()
        controller.toggleSource(nil)
        XCTAssertFalse(document.sourceMode)
        XCTAssertEqual(controller.editor.string, "Edited\n")
        XCTAssertEqual(document.markdown(), "# Edited\n")
        undo(document)
        XCTAssertTrue(document.sourceMode)
        XCTAssertEqual(controller.editor.string, "# Edited\n")
        undo(document)
        XCTAssertEqual(controller.editor.string, "# Hello\n")
        document.close()
    }

    func testReloadReplacesVisibleDocument() throws {
        let (document, controller) = try editor("# Old\n")
        try document.read(from: Data("# Fresh\n".utf8), ofType: "net.daringfireball.markdown")
        XCTAssertEqual(controller.editor.string, "Fresh\n")
        XCTAssertEqual(document.markdown(), "# Fresh\n")
        document.close()
    }

    func testMultipleParagraphsBecomeOneCodeBlock() throws {
        let (document, controller) = try editor("First\n\nSecond\n")
        controller.editor.setSelectedRange(NSRange(location: 0, length: controller.editor.string.utf16.count))
        controller.editor.codeBlock(nil)
        XCTAssertEqual(document.markdown(), "```\nFirst\nSecond\n```\n")
        document.close()
    }

    func testTableCellEditing() throws {
        let (document, controller) = try editor("| Name | State |\n| --- | :---: |\n| Marginal | Draft |\n")
        let range = (controller.editor.string as NSString).range(of: "Draft")
        XCTAssertNotEqual(range.location, NSNotFound)
        controller.editor.insertText("Ready", replacementRange: range)
        let saved = document.markdown()
        XCTAssertTrue(saved.contains("| Marginal | Ready |"))
        XCTAssertTrue(saved.contains(":---:"))
        document.close()
    }

    func testHeadingReturnInMiddleConvertsFollowingTextToBody() throws {
        let (document, controller) = try editor("# Hello world\n")
        controller.editor.setSelectedRange(NSRange(location: 6, length: 0))
        controller.editor.insertNewline(nil)
        XCTAssertFalse(document.markdown().contains("# world"))
        document.close()
    }

    func testChangingEmptyListStyle() throws {
        let (document, controller) = try editor("")
        controller.editor.bullets(nil)
        controller.editor.numbers(nil)
        controller.editor.setSelectedRange(NSRange(location: controller.editor.string.utf16.count, length: 0))
        controller.editor.insertText("One", replacementRange: controller.editor.selectedRange())
        XCTAssertTrue(document.markdown().contains("1. One"))
        document.close()
    }

    func testInvalidUTF8FailsWithoutDataLoss() {
        let document = MarginalDocument()
        XCTAssertThrowsError(try document.read(from: Data([0xff, 0xfe, 0xfd]), ofType: "net.daringfireball.markdown"))
    }

    func testNativeViewRendersToImage() throws {
        let source = """
        # A little room to write

        Open a Markdown file. Read it beautifully. Edit it right here.

        ## Keep it simple

        Marginal is a small native Mac app for **words**, *ideas*, and the occasional `snippet`.

        - Open any Markdown file
        - Edit the rendered document
        - Save ordinary Markdown

        > Less chrome. More room for your thoughts.

        ```swift
        let thought = "Something worth keeping."
        print(thought)
        ```

        [Made for your Mac](https://github.com/acousland/marginal)
        """
        let (document, controller) = try editor(source)
        controller.window?.appearance = NSAppearance(named: .aqua)
        let view = try XCTUnwrap(controller.window?.contentView?.superview)
        view.layoutSubtreeIfNeeded()
        controller.editor.layoutManager?.ensureLayout(for: controller.editor.textContainer!)
        let bitmap = try XCTUnwrap(view.bitmapImageRepForCachingDisplay(in: view.bounds))
        view.cacheDisplay(in: view.bounds, to: bitmap)
        try bitmap.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: "/tmp/marginal-editor.png"))
        XCTAssertGreaterThan(bitmap.pixelsWide, 500)
        document.close()
    }
}

extension EditorTests {
    private func type(_ text: String, in view: EditorTextView) {
        for character in text { view.insertText(String(character), replacementRange: view.selectedRange()) }
    }

    func testTypedHeadingMarkersBecomeHeadingsAndReturnToBody() throws {
        for level in 1...6 {
            let (document, controller) = try editor("")
            type(String(repeating: "#", count: level) + " ", in: controller.editor)
            XCTAssertEqual(controller.editor.string, "")
            XCTAssertEqual(controller.editor.typingAttributes[.block] as? String, "h\(level)")
            XCTAssertEqual(controller.stylePicker.titleOfSelectedItem, "Heading \(level)")
            type("Title", in: controller.editor)
            controller.editor.insertNewline(nil)
            type("Body", in: controller.editor)
            XCTAssertEqual(document.markdown(), String(repeating: "#", count: level) + " Title\n\nBody\n")
        }
    }

    func testInlineTypingStylePersistsAsCursorAdvances() throws {
        let (document, controller) = try editor("Hello world\n")
        controller.editor.setSelectedRange(NSRange(location: 6, length: 0))
        controller.editor.bold(nil)
        type("New", in: controller.editor)
        XCTAssertEqual(document.markdown(), "Hello **New**world\n")
    }

    func testHeadingShortcutInFrontOfExistingUnicodeTextAndUndo() throws {
        let (document, controller) = try editor("Café 🐈\n")
        controller.editor.setSelectedRange(NSRange(location: 0, length: 0))
        type("##", in: controller.editor)
        controller.editor.breakUndoCoalescing()
        while document.undoManager!.groupingLevel > 0 { document.undoManager!.endUndoGrouping() }
        document.undoManager!.beginUndoGrouping()
        type(" ", in: controller.editor)
        XCTAssertEqual(document.markdown(), "## Café 🐈\n")
        XCTAssertEqual(controller.editor.selectedRange().location, 0)
        undo(document)
        XCTAssertEqual(controller.editor.string, "##Café 🐈\n")
        XCTAssertEqual(controller.editor.textStorage?.attribute(.block, at: 0, effectiveRange: nil) as? String, "p")
        document.undoManager!.redo()
        XCTAssertEqual(document.markdown(), "## Café 🐈\n")
    }

    func testTypedListAndQuoteShortcuts() throws {
        for (marker, expected) in [("-", "- Item\n"), ("*", "- Item\n"), ("+", "- Item\n"),
                                   ("3.", "3. Item\n"), ("1)", "1. Item\n"), (">", "> Item\n")] {
            let (document, controller) = try editor("")
            type(marker + " Item", in: controller.editor)
            XCTAssertEqual(document.markdown(), expected)
        }
        let (document, controller) = try editor("")
        type("3. First", in: controller.editor)
        controller.editor.insertNewline(nil)
        type("Second", in: controller.editor)
        XCTAssertEqual(document.markdown(), "3. First\n4. Second\n")
    }

    func testTypingShortcutsStayLiteralInSourceCodeTablesAndMidParagraph() throws {
        for source in ["Words text", "```\n\n```\n", "| A |\n| --- |\n| B |\n"] {
            let (_, controller) = try editor(source)
            controller.editor.setSelectedRange(NSRange(location: source.hasPrefix("Words") ? 6 : 0, length: 0))
            type("## ", in: controller.editor)
            XCTAssertTrue(controller.editor.string.contains("## "))
        }
        let (_, controller) = try editor("")
        controller.toggleSource(nil)
        type("## ", in: controller.editor)
        XCTAssertEqual(controller.editor.string, "## ")
        controller.toggleSource(nil)
        let (_, body) = try editor("")
        type("####### ", in: body.editor)
        XCTAssertEqual(body.editor.string, "####### ")
    }

    func testFencedCodeShortcutAndExit() throws {
        let (document, controller) = try editor("")
        type("```swift", in: controller.editor)
        controller.editor.insertNewline(nil)
        type("let value = 1", in: controller.editor)
        controller.editor.insertNewline(nil)
        type("```", in: controller.editor)
        controller.editor.insertNewline(nil)
        type("Body", in: controller.editor)
        XCTAssertEqual(document.markdown(), "```swift\nlet value = 1\n```\n\nBody\n")
    }

    func testInsertTableAndUndoKeepsSurroundingParagraphs() throws {
        let (document, controller) = try editor("Before after\n")
        controller.editor.setSelectedRange(NSRange(location: 7, length: 0))
        controller.editor.insertTable(rows: 3, columns: 2)
        let saved = document.markdown()
        XCTAssertTrue(saved.hasPrefix("Before \n\n| Column 1 | Column 2 |\n| --- | --- |\n|  |  |\n|  |  |\n\nafter\n"), saved)
        XCTAssertEqual(controller.editor.selectedRange().length, 8)
        XCTAssertEqual(controller.editor.currentTable()?.cells.count, 3)
        undo(document)
        XCTAssertEqual(controller.editor.string, "Before after\n")
        document.undoManager!.redo()
        XCTAssertTrue(document.markdown().contains("| Column 1 | Column 2 |"))
    }

    func testTableRowAndColumnControlsPreserveInlineFormattingAndAlignment() throws {
        let source = "Before\n\n| Name | State |\n| --- | :---: |\n| **Marginal** | [Ready](https://example.com) |\n\nAfter\n"
        let (document, controller) = try editor(source)
        let view = controller.editor
        let range = (view.string as NSString).range(of: "Ready")
        view.setSelectedRange(NSRange(location: range.location, length: 0))
        view.addRowAbove(nil)
        XCTAssertEqual(view.currentTable()?.cells.count, 3)
        XCTAssertEqual(view.currentTable()?.row, 1)
        view.addColumnBefore(nil)
        XCTAssertEqual(view.currentTable()?.alignments, ["none", "none", "center"])
        view.alignColumnRight(nil)
        view.insertText("Added", replacementRange: view.selectedRange())
        let saved = document.markdown()
        XCTAssertTrue(saved.contains("| --- | ---: | :---: |"), saved)
        XCTAssertTrue(saved.contains("| **Marginal** |  | [Ready](<https://example.com>) |"), saved)
        XCTAssertTrue(saved.contains("Before\n\n"))
        XCTAssertTrue(saved.hasSuffix("\n\nAfter\n"))
        view.deleteColumn(nil)
        view.deleteRow(nil)
        XCTAssertEqual(document.markdown(), MarkdownCodec.serialize(MarkdownCodec.render(source)))
        let reopened = MarkdownCodec.render(document.markdown())
        XCTAssertTrue(reopened.string.contains("Marginal"))
    }

    func testDeleteTableIsUndoableAndKeepsAdjacentTablesSeparate() throws {
        let source = "| A |\n| --- |\n| B |\n\n| C |\n| --- |\n| D |\n"
        let (document, controller) = try editor(source)
        controller.editor.setSelectedRange(NSRange(location: 0, length: 0))
        controller.editor.deleteTable(nil)
        XCTAssertEqual(document.markdown(), "| C |\n| --- |\n| D |\n")
        undo(document)
        XCTAssertEqual(document.markdown(), source)
        document.undoManager!.beginUndoGrouping()
        controller.editor.setSelectedRange(NSRange(location: 0, length: 0))
        controller.editor.addRowBelow(nil)
        XCTAssertEqual(controller.editor.currentTable()?.cells.count, 3)
        XCTAssertTrue(document.markdown().hasSuffix("\n\n| C |\n| --- |\n| D |\n"))
    }

    func testTabMovesAcrossCellsAndAddsRowAtEnd() throws {
        let (document, controller) = try editor("| A | B |\n| --- | --- |\n| C | D |\n")
        let view = controller.editor
        view.setSelectedRange(NSRange(location: 0, length: 0))
        view.insertTab(nil)
        XCTAssertEqual(view.currentTable()?.column, 1)
        XCTAssertEqual(view.selectedRange().length, 1)
        view.insertBacktab(nil)
        XCTAssertEqual(view.currentTable()?.column, 0)
        let last = (view.string as NSString).range(of: "D")
        view.setSelectedRange(NSRange(location: last.location, length: 0))
        view.insertTab(nil)
        XCTAssertEqual(view.currentTable()?.row, 2)
        XCTAssertEqual(view.currentTable()?.column, 0)
        type("E", in: view)
        XCTAssertTrue(document.markdown().hasSuffix("| E |  |\n"))
    }

    func testTableReturnStaysInCellAndParagraphAfterTableExits() throws {
        let (document, controller) = try editor("| A |\n| --- |\n| B |\n")
        let view = controller.editor
        let cell = (view.string as NSString).range(of: "B")
        view.setSelectedRange(NSRange(location: NSMaxRange(cell), length: 0))
        view.insertNewline(nil)
        type("Next", in: view)
        XCTAssertEqual(view.currentTable()?.cells.count, 2)
        XCTAssertTrue(document.markdown().contains("| B<br>Next |"), document.markdown())
        view.addColumnAfter(nil)
        XCTAssertTrue(document.markdown().contains("| B<br>Next |  |"), document.markdown())
        let reopened = MarkdownCodec.render(document.markdown())
        XCTAssertTrue(reopened.string.contains("B\u{2028}Next"))
        XCTAssertEqual(MarkdownCodec.serialize(reopened), document.markdown())
        view.paragraphAfterTable(nil)
        type("Body", in: view)
        XCTAssertTrue(document.markdown().hasSuffix("\n\nBody\n"), document.markdown())
        XCTAssertNil(view.currentTable())
    }

    func testTableMenuProtectsHeaderAndFinalColumnAndDisablesSourceControls() throws {
        let (_, controller) = try editor("| A |\n| --- |\n| B |\n")
        let view = controller.editor
        view.setSelectedRange(NSRange(location: 0, length: 0))
        let menu = EditorTextView.tableMenu(target: view)
        func enabled(_ title: String) throws -> Bool { view.validateMenuItem(try XCTUnwrap(menu.items.first { $0.title == title })) }
        XCTAssertFalse(try enabled("Delete Row"))
        XCTAssertFalse(try enabled("Add Row Above"))
        XCTAssertFalse(try enabled("Delete Column"))
        XCTAssertTrue(try enabled("Add Row Below"))
        XCTAssertFalse(try enabled("Insert Table…"))
        controller.toggleSource(nil)
        XCTAssertFalse(try enabled("Add Row Below"))
        XCTAssertFalse(try enabled("Insert Table…"))
    }

    func testTableCellBoundariesAndMultilinePasting() throws {
        let (document, controller) = try editor("| A | B |\n| --- | --- |\n| C | D |\n")
        let view = controller.editor
        let first = view.string as NSString
        let start = first.range(of: "D").location
        view.setSelectedRange(NSRange(location: start, length: 0))
        view.deleteBackward(nil)
        XCTAssertEqual(view.string, first as String)
        view.insertText("Line 1\nLine 2\r\n", replacementRange: view.selectedRange())
        XCTAssertTrue(document.markdown().contains("Line 1<br>Line 2<br>D"), document.markdown())
        view.setSelectedRange(NSRange(location: 0, length: view.string.utf16.count))
        XCTAssertFalse(view.canInsertTable)
        view.insertTable(rows: 2, columns: 2)
        XCTAssertTrue(document.markdown().contains("Line 1<br>Line 2<br>D"))
        let (_, other) = try editor("Before\n\n| A |\n| --- |\n| B |\n")
        let before = other.editor.string
        other.editor.setSelectedRange(NSRange(location: 0, length: (before as NSString).range(of: "B", options: .backwards).location))
        other.editor.insertNewline(nil)
        XCTAssertEqual(other.editor.string, before)
    }

    func testSelectingWholeTableCanReplaceItWithBodyTextAndUndo() throws {
        let (document, controller) = try editor("| A |\n| --- |\n| B |\n")
        let view = controller.editor
        view.setSelectedRange(NSRange(location: 0, length: view.string.utf16.count))
        view.insertText("Body", replacementRange: view.selectedRange())
        XCTAssertEqual(document.markdown(), "Body\n")
        XCTAssertNil(view.currentTable())
        undo(document)
        XCTAssertEqual(document.markdown(), "| A |\n| --- |\n| B |\n")
        document.undoManager!.beginUndoGrouping()
        view.setSelectedRange(NSRange(location: 0, length: view.string.utf16.count))
        view.deleteBackward(nil)
        type("Body", in: view)
        XCTAssertEqual(document.markdown(), "Body\n")
    }

    func testEditedNativeTableRendersToImage() throws {
        let (_, controller) = try editor("# Tables, without the pipes\n\nClick a cell and use the Table menu to change its structure.\n\n| Feature | Status |\n| :--- | :---: |\n| **Headings** | Ready |\n| Tables | Editable |\n\nKeep writing below your table.\n")
        controller.editor.setSelectedRange((controller.editor.string as NSString).range(of: "Editable"))
        controller.editor.addColumnAfter(nil)
        controller.editor.insertText("Notes", replacementRange: controller.editor.selectedRange())
        controller.window?.appearance = NSAppearance(named: .aqua)
        let view = try XCTUnwrap(controller.window?.contentView?.superview)
        view.layoutSubtreeIfNeeded()
        controller.editor.layoutManager?.ensureLayout(for: controller.editor.textContainer!)
        let bitmap = try XCTUnwrap(view.bitmapImageRepForCachingDisplay(in: view.bounds))
        view.cacheDisplay(in: view.bounds, to: bitmap)
        try bitmap.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: "/tmp/marginal-tables.png"))
        XCTAssertGreaterThan(bitmap.pixelsWide, 500)
    }
}
