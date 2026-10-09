import AppKit
import MarginalCore

// Exercise real, layer-backed window drawing between zoom and layout changes.
// Offscreen layout tests alone do not run AppKit's display cycle.
func runDisplayProbe() -> Never {
    // A swallowed AppKit exception must fail this check rather than leave a
    // timer running until it prints a misleading success message.
    UserDefaults.standard.register(defaults: ["NSApplicationCrashOnExceptions": true])
    let app = NSApplication.shared
    app.setActivationPolicy(.accessory)
    let suite = "Marginal.DisplayProbe.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    let source = "# Display test\n\n" + (0..<120).map { index in
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
            guard document.markdown() == source, !document.hasEdits else {
                fputs("Display probe changed Markdown.\n", stderr)
                exit(1)
            }
            document.close()
            defaults.removePersistentDomain(forName: suite)
            print("Live display, zoom, magnification, scrolling, wrap, source mode, and resizing passed (96 changes).")
            exit(0)
        }
        switch step % 16 {
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
        }
        step += 1
    }
    RunLoop.main.add(timer, forMode: .common)
    app.run()
    exit(1)
}
