import AppKit
import MarginalCore

// Exercise real, layer-backed window drawing between zoom and layout changes.
// Offscreen layout tests alone do not run AppKit's display cycle.
func runDisplayProbe(tables: Bool = false) -> Never {
    // A swallowed AppKit exception must fail this check rather than leave a
    // timer running until it prints a misleading success message.
    UserDefaults.standard.register(defaults: ["NSApplicationCrashOnExceptions": true])
    let app = NSApplication.shared
    app.setActivationPolicy(.accessory)
    let suite = "Marginal.DisplayProbe.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    let source = tables ? "# Table controls\n\nSelect rows and columns.\n\n| Name | State | Notes |\n| --- | :---: | --- |\n| **Marginal** | Draft | First |\n| Other | Ready | Second |\n\nAfter the table.\n" : "# Display test\n\n" + (0..<120).map { index in
        "Paragraph \(index). " + String(repeating: "Words with **bold**, `code`, and a [link](https://example.com). ", count: 12)
        + "\n\n| Name | State |\n| --- | --- |\n| Marginal | Draft |\n\n```swift\nlet value = \(index)\n```\n\n"
    }.joined()
    let document = MarginalDocument()
    document.originalMarkdown = source
    document.storage.setAttributedString(MarkdownCodec.render(source))
    let controller = EditorWindowController(document: document, defaults: defaults)
    document.addWindowController(controller)
    let window = controller.window!
    window.setFrameAutosaveName("")
    window.title = "Marginal display regression test"
    window.contentView?.wantsLayer = true
    window.orderFront(nil)
    var step = 0
    let timer = Timer(timeInterval: 0.12, repeats: true) { timer in
        guard controller.editor.frame.width.isFinite, controller.editor.frame.height.isFinite,
              !controller.wrapsLines || abs(controller.editor.frame.width - controller.scroll.contentView.bounds.width) < 1 else {
            fputs("Display probe produced unstable editor geometry at step \(step).\n", stderr)
            exit(1)
        }
        if step == 96 {
            timer.invalidate()
            let expected = tables ? MarkdownCodec.serialize(MarkdownCodec.render(source)) : source
            guard document.markdown() == expected, tables || !document.hasEdits else {
                fputs("Display probe changed Markdown.\n", stderr)
                exit(1)
            }
            document.close()
            defaults.removePersistentDomain(forName: suite)
            print(tables ? "Live table handles, selections, insert/delete, undo, zoom, wrap, and source mode passed (96 changes)." : "Live display, zoom, magnification, scrolling, wrap, source mode, and resizing passed (96 changes).")
            exit(0)
        }
        if tables {
            let view = controller.editor
            let location = (view.string as NSString).range(of: "Marginal").location
            let id = document.storage.attribute(.tableID, at: min(location, document.storage.length - 1), effectiveRange: nil) as? String
            switch step % 16 {
            case 0:
                if let id { view.selectCell(id: id, row: 1, column: 1); view.selectTableAxis(id: id, axis: .column, index: 1) }
            case 1: if let id { view.selectTableAxis(id: id, axis: .column, index: 2, extending: true) }
            case 2: view.addColumnAfter(nil)
            case 3, 7, 11: document.undoManager?.undo()
            case 4: if let id { view.selectTableAxis(id: id, axis: .row, index: 1) }
            case 5: if let id { view.selectTableAxis(id: id, axis: .row, index: 2, extending: true) }
            case 6: view.deleteRow(nil)
            case 8: controller.zoomIn(nil)
            case 9: if let id { view.selectCell(id: id, row: 0, column: 0); view.selectTableAxis(id: id, axis: .row, index: 0) }
            case 10:
                view.viewWillDraw()
                if let button = view.tableControls.subviews.compactMap({ $0 as? TableEdgeButton }).first(where: { $0.inserts && $0.axis == .row && $0.index == 0 }) {
                    view.tableControls.updateHover(at: NSPoint(x: button.frame.midX, y: button.frame.midY))
                    button.performClick(nil)
                }
            case 12: controller.toggleWordWrap(nil)
            case 13: controller.scroll.setMagnification(2, centeredAt: controller.scroll.contentView.bounds.origin)
            case 14: controller.toggleSource(nil)
            default: controller.toggleSource(nil)
            }
        } else { switch step % 16 {
        case 0...3: controller.zoomIn(nil)
        case 4:
            controller.editor.scrollRangeToVisible(NSRange(location: controller.editor.string.utf16.count / 2, length: 0))
        case 5...8: controller.zoomOut(nil)
        case 9: controller.toggleWordWrap(nil)
        case 10: controller.toggleSource(nil)
        case 11:
            // Trackpad magnification also changes the clip bounds without a menu action.
            controller.scroll.setMagnification(step % 32 == 11 ? 2.5 : 0.67,
                                              centeredAt: controller.scroll.contentView.bounds.origin)
        case 12: window.setContentSize(NSSize(width: step % 32 == 12 ? 580 : 920, height: 500))
        case 13: controller.actualSize(nil)
        case 14: controller.toggleSource(nil)
        default: controller.toggleWordWrap(nil)
        } }
        step += 1
    }
    RunLoop.main.add(timer, forMode: .common)
    app.run()
    exit(1)
}
