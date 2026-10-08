import AppKit
import MarginalCore
import UniformTypeIdentifiers

@objc(MarginalDocument)
final class MarginalDocument: NSDocument {
    var originalMarkdown = ""
    var hasEdits = false
    var sourceMode = false
    let storage = NSTextStorage()

    override class var autosavesInPlace: Bool { true }
    override var autosavingFileType: String? { "net.daringfireball.markdown" }

    override func read(from data: Data, ofType typeName: String) throws {
        guard let string = String(data: data, encoding: .utf8) else {
            throw NSError(domain: NSCocoaErrorDomain, code: NSFileReadInapplicableStringEncodingError,
                          userInfo: [NSLocalizedDescriptionKey: "Marginal opens UTF-8 Markdown files. This file uses a different encoding."])
        }
        originalMarkdown = string
        hasEdits = false
        if !windowControllers.isEmpty {
            storage.setAttributedString(sourceMode ? NSAttributedString(string: string, attributes: [.font: NSFont.monospacedSystemFont(ofSize: 14, weight: .regular), .foregroundColor: NSColor.labelColor]) : MarkdownCodec.render(string, baseURL: fileURL))
            for controller in windowControllers { (controller as? EditorWindowController)?.refreshAfterRead() }
        }
    }

    override func makeWindowControllers() {
        storage.setAttributedString(MarkdownCodec.render(originalMarkdown, baseURL: fileURL))
        let controller = EditorWindowController(document: self)
        addWindowController(controller)
    }

    func markdown() -> String {
        if !hasEdits { return originalMarkdown }
        return sourceMode ? storage.string : MarkdownCodec.serialize(storage)
    }

    override func data(ofType typeName: String) throws -> Data { Data(markdown().utf8) }

    override func prepareSavePanel(_ savePanel: NSSavePanel) -> Bool {
        savePanel.allowedContentTypes = [UTType(filenameExtension: "md") ?? .plainText]
        savePanel.allowsOtherFileTypes = true
        return true
    }
}
