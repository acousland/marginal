import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    let updates = UpdateChecker()
    func menuNeedsUpdate(_ menu: NSMenu) {
        guard menu.identifier?.rawValue == "recent" else { return }
        menu.removeAllItems()
        for url in NSDocumentController.shared.recentDocumentURLs {
            let item = NSMenuItem(title: url.lastPathComponent, action: #selector(openRecent(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = url
            menu.addItem(item)
        }
        if menu.items.isEmpty {
            let empty = NSMenuItem(title: "No Recent Documents", action: nil, keyEquivalent: "")
            empty.isEnabled = false
            menu.addItem(empty)
        }
        menu.addItem(.separator())
        let clear = NSMenuItem(title: "Clear Menu", action: #selector(NSDocumentController.clearRecentDocuments(_:)), keyEquivalent: "")
        clear.target = NSDocumentController.shared
        menu.addItem(clear)
    }
    @objc private func openRecent(_ sender: NSMenuItem) {
        guard let url = sender.representedObject as? URL else { return }
        NSDocumentController.shared.openDocument(withContentsOf: url, display: true) { _, _, error in
            if let error { NSApp.presentError(error) }
        }
    }
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        updates.start()
    }
    func applicationShouldOpenUntitledFile(_ sender: NSApplication) -> Bool { true }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
}

func menuItem(_ title: String, _ action: Selector?, _ key: String = "", modifiers: NSEvent.ModifierFlags = .command) -> NSMenuItem {
    let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
    item.keyEquivalentModifierMask = modifiers
    return item
}
func submenu(_ title: String, items: [NSMenuItem]) -> NSMenuItem {
    let parent = NSMenuItem(title: title, action: nil, keyEquivalent: "")
    let menu = NSMenu(title: title)
    items.forEach { menu.addItem($0) }
    parent.submenu = menu
    return parent
}

private func smokeTest() throws {
    let controller = NSDocumentController.shared
    let type = "net.daringfireball.markdown"
    guard controller.documentClass(forType: type) == MarginalDocument.self else {
        throw NSError(domain: "Marginal", code: 1, userInfo: [NSLocalizedDescriptionKey: "Markdown document registration failed"])
    }
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: folder) }
    let input = folder.appendingPathComponent("input.md")
    let output = folder.appendingPathComponent("output.md")
    let source = "# Smoke test\n\nHello world.\n"
    try source.write(to: input, atomically: true, encoding: .utf8)
    let document = try controller.makeDocument(withContentsOf: input, ofType: type) as! MarginalDocument
    document.makeWindowControllers()
    let window = document.windowControllers[0] as! EditorWindowController
    let range = (window.editor.string as NSString).range(of: "world")
    window.editor.setSelectedRange(range)
    window.editor.bold(nil)
    try document.write(to: output, ofType: type)
    let reopened = try controller.makeDocument(withContentsOf: output, ofType: type) as! MarginalDocument
    guard reopened.originalMarkdown.contains("**world**") else {
        throw NSError(domain: "Marginal", code: 2, userInfo: [NSLocalizedDescriptionKey: "Edited Markdown did not survive saving and reopening"])
    }
    document.close()
    reopened.close()
    print("Document registration, open, edit, save, and reopen passed.")
}

public func runMarginal() {
if CommandLine.arguments.contains("--check-updates") {
    _ = NSApplication.shared
    UpdateProbe().run()
}
if CommandLine.arguments.contains("--smoke-test") {
    _ = NSApplication.shared
    do { try smokeTest(); exit(0) }
    catch { fputs("Smoke test failed: \(error)\n", stderr); exit(1) }
}
let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
let mainMenu = NSMenu()
let checkUpdates = menuItem("Check for Updates…", #selector(UpdateChecker.checkForUpdates(_:)))
checkUpdates.target = delegate.updates
let automaticUpdates = menuItem("Automatically Check for Updates", #selector(UpdateChecker.toggleAutomaticChecks(_:)))
automaticUpdates.target = delegate.updates
automaticUpdates.state = delegate.updates.automaticallyChecks ? .on : .off
let automaticDownloads = menuItem("Download and Install Updates Automatically", #selector(UpdateChecker.toggleAutomaticDownloads(_:)))
automaticDownloads.target = delegate.updates
automaticDownloads.state = delegate.updates.automaticallyDownloads ? .on : .off
mainMenu.addItem(submenu("Marginal", items: [
    menuItem("About Marginal", #selector(NSApplication.orderFrontStandardAboutPanel(_:))),
    checkUpdates, automaticUpdates, automaticDownloads, .separator(),
    submenu("Services", items: []), .separator(),
    menuItem("Hide Marginal", #selector(NSApplication.hide(_:)), "h"),
    menuItem("Hide Others", #selector(NSApplication.hideOtherApplications(_:)), "h", modifiers: [.command, .option]),
    menuItem("Show All", #selector(NSApplication.unhideAllApplications(_:))), .separator(),
    menuItem("Quit Marginal", #selector(NSApplication.terminate(_:)), "q")
]))
let recent = submenu("Open Recent", items: [menuItem("Clear Menu", #selector(NSDocumentController.clearRecentDocuments(_:)))])
recent.submenu?.identifier = NSUserInterfaceItemIdentifier("recent")
recent.submenu?.delegate = delegate
mainMenu.addItem(submenu("File", items: [
    menuItem("New", #selector(NSDocumentController.newDocument(_:)), "n"),
    menuItem("Open…", #selector(NSDocumentController.openDocument(_:)), "o"), recent, .separator(),
    menuItem("Close", #selector(NSWindow.performClose(_:)), "w"),
    menuItem("Save", #selector(NSDocument.save(_:)), "s"),
    menuItem("Save As…", #selector(NSDocument.saveAs(_:)), "s", modifiers: [.command, .shift]),
    menuItem("Revert to Saved…", #selector(NSDocument.revertToSaved(_:)))
]))
mainMenu.addItem(submenu("Edit", items: [
    menuItem("Undo", Selector(("undo:")), "z"),
    menuItem("Redo", Selector(("redo:")), "z", modifiers: [.command, .shift]), .separator(),
    menuItem("Cut", #selector(NSText.cut(_:)), "x"),
    menuItem("Copy", #selector(NSText.copy(_:)), "c"),
    menuItem("Paste", #selector(NSText.paste(_:)), "v"),
    menuItem("Select All", #selector(NSText.selectAll(_:)), "a"), .separator(),
    menuItem("Find…", #selector(NSTextView.performFindPanelAction(_:)), "f")
]))
mainMenu.items.last?.submenu?.items.last?.tag = NSTextFinder.Action.showFindInterface.rawValue
mainMenu.addItem(submenu("Format", items: [
    menuItem("Bold", #selector(EditorTextView.bold(_:)), "b"),
    menuItem("Italic", #selector(EditorTextView.italic(_:)), "i"),
    menuItem("Inline Code", #selector(EditorTextView.code(_:)), "c", modifiers: [.command, .shift]),
    menuItem("Strikethrough", #selector(EditorTextView.strike(_:))), .separator(),
    menuItem("Body", #selector(EditorTextView.body(_:)), "0", modifiers: [.command, .option]),
    menuItem("Heading 1", #selector(EditorTextView.heading1(_:)), "1", modifiers: [.command, .option]),
    menuItem("Heading 2", #selector(EditorTextView.heading2(_:)), "2", modifiers: [.command, .option]),
    menuItem("Heading 3", #selector(EditorTextView.heading3(_:)), "3", modifiers: [.command, .option]),
    menuItem("Bullet List", #selector(EditorTextView.bullets(_:)), "7", modifiers: [.command, .option]),
    menuItem("Numbered List", #selector(EditorTextView.numbers(_:)), "8", modifiers: [.command, .option]),
    menuItem("Quote", #selector(EditorTextView.quote(_:)), "9", modifiers: [.command, .option]),
    menuItem("Code Block", #selector(EditorTextView.codeBlock(_:))), .separator(),
    menuItem("Add Link…", #selector(EditorTextView.insertLink(_:)), "k"),
    menuItem("Remove Link", #selector(EditorTextView.removeLink(_:)))
]))
let tableMenuItem = NSMenuItem(title: "Table", action: nil, keyEquivalent: "")
tableMenuItem.submenu = EditorTextView.tableMenu()
mainMenu.addItem(tableMenuItem)
let zoomInWithoutShift = menuItem("Zoom In", #selector(EditorWindowController.zoomIn(_:)), "=")
zoomInWithoutShift.isHidden = true
zoomInWithoutShift.allowsKeyEquivalentWhenHidden = true
mainMenu.addItem(submenu("View", items: [
    menuItem("Zoom In", #selector(EditorWindowController.zoomIn(_:)), "+"), zoomInWithoutShift,
    menuItem("Zoom Out", #selector(EditorWindowController.zoomOut(_:)), "-"),
    menuItem("Actual Size", #selector(EditorWindowController.actualSize(_:)), "0"),
    menuItem("Word Wrap", #selector(EditorWindowController.toggleWordWrap(_:))), .separator(),
    menuItem("Show Formatting Toolbar", #selector(EditorWindowController.toggleFormattingToolbar(_:)), "t", modifiers: [.command, .option]),
    menuItem("Show Word Count", #selector(EditorWindowController.toggleWordCount(_:))), .separator(),
    menuItem("Show Markdown Source", #selector(EditorWindowController.toggleSource(_:)), "m", modifiers: [.command, .shift]),
    menuItem("Enter Full Screen", #selector(NSWindow.toggleFullScreen(_:)), "f", modifiers: [.command, .control])
]))
let windowMenu = submenu("Window", items: [
    menuItem("Minimize", #selector(NSWindow.performMiniaturize(_:)), "m"),
    menuItem("Zoom", #selector(NSWindow.performZoom(_:))), .separator(),
    menuItem("Bring All to Front", #selector(NSApplication.arrangeInFront(_:)))
])
mainMenu.addItem(windowMenu)
app.mainMenu = mainMenu
app.windowsMenu = windowMenu.submenu
app.servicesMenu = mainMenu.items.first?.submenu?.items.first(where: { $0.title == "Services" })?.submenu
_ = NSDocumentController.shared
withExtendedLifetime(delegate) { app.run() }

}
