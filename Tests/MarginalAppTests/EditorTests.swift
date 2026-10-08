import XCTest
import AppKit
import MarginalCore
@testable import MarginalApp

final class EditorTests: XCTestCase {
    private func editor(_ source: String) throws -> (MarginalDocument, EditorWindowController) {
        _ = NSApplication.shared
        let document = MarginalDocument()
        try document.read(from: Data(source.utf8), ofType: "net.daringfireball.markdown")
        document.makeWindowControllers()
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
