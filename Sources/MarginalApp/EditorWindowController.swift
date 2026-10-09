import AppKit
import MarginalCore

final class EditorWindowController: NSWindowController, NSTextViewDelegate, NSToolbarDelegate, NSMenuItemValidation {
    let editor: EditorTextView
    let scroll = NSScrollView()
    let status = NSTextField(labelWithString: "")
    let stylePicker = NSPopUpButton()
    weak var markdownDocument: MarginalDocument?
    private var statusWork: DispatchWorkItem?
    private var sourceItem: NSToolbarItem?
    private var lastWidth: CGFloat = 0
    private var scrollToStatus: NSLayoutConstraint?
    private var scrollToBottom: NSLayoutConstraint?
    private let defaults: UserDefaults
    static let toolbarKey = "showsFormattingToolbar"
    static let wordCountKey = "showsWordCount"

    init(document: MarginalDocument, defaults: UserDefaults = .standard) {
        self.defaults = defaults
        markdownDocument = document
        let layout = NSLayoutManager()
        layout.allowsNonContiguousLayout = true
        let container = NSTextContainer(containerSize: NSSize(width: 720, height: CGFloat.greatestFiniteMagnitude))
        container.widthTracksTextView = true
        document.storage.addLayoutManager(layout)
        layout.addTextContainer(container)
        editor = EditorTextView(frame: NSRect(x: 0, y: 0, width: 860, height: 600), textContainer: container)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 860, height: 700), styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        window.minSize = NSSize(width: 530, height: 360)
        window.title = "Untitled"
        window.titlebarAppearsTransparent = true
        window.tabbingMode = .preferred
        super.init(window: window)
        window.center()
        window.setFrameAutosaveName("MarginalEditor")
        configureEditor()
        configureStylePicker()
        configureLayout()
        let toolbar = NSToolbar(identifier: "MarginalToolbar")
        toolbar.delegate = self
        toolbar.displayMode = .iconOnly
        toolbar.allowsUserCustomization = false
        window.toolbar = toolbar
        window.toolbarStyle = .unifiedCompact
        toolbar.isVisible = defaults.bool(forKey: Self.toolbarKey)
        window.makeFirstResponder(editor)
        updateStatus()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private func configureStylePicker() {
        stylePicker.addItems(withTitles: ["Body", "Heading 1", "Heading 2", "Heading 3", "Heading 4", "Heading 5", "Heading 6", "Bullet List", "Numbered List", "Quote", "Code Block"])
        stylePicker.target = self
        stylePicker.action = #selector(selectStyle)
        stylePicker.setAccessibilityLabel("Paragraph style")
        stylePicker.frame = NSRect(x: 0, y: 0, width: 125, height: 26)
    }

    private func configureEditor() {
        editor.delegate = self
        editor.isRichText = true
        editor.importsGraphics = false
        editor.allowsUndo = true
        editor.isAutomaticQuoteSubstitutionEnabled = false
        editor.isAutomaticDashSubstitutionEnabled = false
        editor.isAutomaticLinkDetectionEnabled = false
        editor.isAutomaticTextReplacementEnabled = false
        editor.isAutomaticSpellingCorrectionEnabled = false
        editor.isContinuousSpellCheckingEnabled = true
        editor.usesFindBar = true
        editor.isIncrementalSearchingEnabled = true
        editor.isVerticallyResizable = true
        editor.isHorizontallyResizable = false
        editor.autoresizingMask = [.width]
        editor.minSize = NSSize(width: 0, height: 600)
        editor.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        editor.backgroundColor = .textBackgroundColor
        editor.insertionPointColor = .labelColor
        editor.typingAttributes = editor.textStorage!.length > 0 ? editor.textStorage!.attributes(at: 0, effectiveRange: nil) : MarkdownStyle.attributes()
        editor.textContainerInset = NSSize(width: 65, height: 35)
        editor.linkTextAttributes = [.foregroundColor: NSColor.linkColor, .underlineStyle: NSUnderlineStyle.single.rawValue]
    }

    private func configureLayout() {
        guard let content = window?.contentView else { return }
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.drawsBackground = true
        scroll.backgroundColor = .textBackgroundColor
        scroll.documentView = editor
        scroll.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(scroll)
        status.font = .systemFont(ofSize: 11)
        status.textColor = .secondaryLabelColor
        status.isHidden = !defaults.bool(forKey: Self.wordCountKey)
        status.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(status)
        NSLayoutConstraint.activate([
            scroll.topAnchor.constraint(equalTo: content.topAnchor),
            scroll.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            status.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 18),
            status.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -18),
            status.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -8)
        ])
        scrollToStatus = scroll.bottomAnchor.constraint(equalTo: status.topAnchor, constant: -8)
        scrollToBottom = scroll.bottomAnchor.constraint(equalTo: content.bottomAnchor)
        updateStatusLayout()
        scroll.contentView.postsBoundsChangedNotifications = true
        scroll.postsFrameChangedNotifications = true
        NotificationCenter.default.addObserver(self, selector: #selector(resizeEditor), name: NSView.frameDidChangeNotification, object: scroll)
    }

    @objc private func resizeEditor() {
        let width = scroll.contentSize.width
        guard abs(width - lastWidth) > 1 else { return }
        lastWidth = width
        editor.textContainerInset = NSSize(width: max(24, (width - 730) / 2), height: 35)
    }

    func textDidChange(_ notification: Notification) {
        markdownDocument?.hasEdits = true
        markdownDocument?.updateChangeCount(.changeDone)
        editor.needsDisplay = true
        statusWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.updateStatus() }
        statusWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: work)
    }

    func textViewDidChangeSelection(_ notification: Notification) {
        guard !editor.sourceMode else { return }
        let location = editor.selectedRange().location
        let kind = location < editor.textStorage!.length ? editor.textStorage!.attribute(.block, at: location, effectiveRange: nil) as? String ?? "p" : editor.typingAttributes[.block] as? String ?? "p"
        let kinds = ["p", "h1", "h2", "h3", "h4", "h5", "h6", "ul", "ol", "quote", "code"]
        let quote = location < editor.textStorage!.length ? editor.textStorage!.attribute(.quoteDepth, at: location, effectiveRange: nil) as? Int ?? 0 : editor.typingAttributes[.quoteDepth] as? Int ?? 0
        stylePicker.selectItem(at: kinds.firstIndex(of: kind == "p" && quote > 0 ? "quote" : kind) ?? 0)
        stylePicker.isEnabled = kind != "table"
    }

    func refreshAfterRead() {
        editor.typingAttributes = editor.sourceMode ? [.font: NSFont.monospacedSystemFont(ofSize: 14, weight: .regular), .foregroundColor: NSColor.labelColor] : editor.textStorage!.length > 0 ? editor.textStorage!.attributes(at: 0, effectiveRange: nil) : MarkdownStyle.attributes()
        editor.setSelectedRange(NSRange(location: 0, length: 0))
        editor.needsDisplay = true
        updateStatus()
    }

    private func updateStatus() {
        guard !status.isHidden else { return }
        let words = editor.string.split(whereSeparator: { $0.isWhitespace || $0 == "\u{fffc}" }).filter { !["•", "☐", "☑"].contains(String($0)) }.count
        status.stringValue = "\(words.formatted()) \(words == 1 ? "word" : "words")" + (editor.sourceMode ? "  ·  Markdown source" : "")
        status.setAccessibilityLabel(status.stringValue)
    }

    private func updateStatusLayout() {
        scrollToStatus?.isActive = false
        scrollToBottom?.isActive = false
        (status.isHidden ? scrollToBottom : scrollToStatus)?.isActive = true
    }

    @objc func toggleFormattingToolbar(_ sender: Any?) {
        guard let toolbar = window?.toolbar else { return }
        toolbar.isVisible.toggle()
        defaults.set(toolbar.isVisible, forKey: Self.toolbarKey)
        window?.makeFirstResponder(editor)
    }

    @objc func toggleWordCount(_ sender: Any?) {
        status.isHidden.toggle()
        defaults.set(!status.isHidden, forKey: Self.wordCountKey)
        updateStatusLayout()
        updateStatus()
    }

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        if menuItem.action == #selector(toggleFormattingToolbar(_:)) {
            menuItem.state = window?.toolbar?.isVisible == true ? .on : .off
        } else if menuItem.action == #selector(toggleWordCount(_:)) {
            menuItem.state = status.isHidden ? .off : .on
        } else if menuItem.action == #selector(toggleSource(_:)) {
            menuItem.title = editor.sourceMode ? "Show Rendered Editor" : "Show Markdown Source"
        }
        return true
    }

    @objc func selectStyle(_ sender: NSPopUpButton) {
        let kinds = ["p", "h1", "h2", "h3", "h4", "h5", "h6", "ul", "ol", "quote", "code"]
        editor.formatBlock(kinds[sender.indexOfSelectedItem])
        window?.makeFirstResponder(editor)
    }

    @objc func toggleSource(_ sender: Any?) {
        guard let document = markdownDocument else { return }
        let markdown = document.markdown()
        // Register mode transitions in the same undo history as text edits.
        restoreMode(source: !editor.sourceMode, markdown: markdown, content: nil, selection: NSRange(location: 0, length: 0))
    }

    private func restoreMode(source: Bool, markdown: String, content: NSAttributedString?, selection: NSRange) {
        guard let document = markdownDocument else { return }
        let oldSource = editor.sourceMode
        let oldContent = NSAttributedString(attributedString: document.storage)
        let oldSelection = editor.selectedRange()
        document.undoManager?.registerUndo(withTarget: self) { target in
            target.restoreMode(source: oldSource, markdown: markdown, content: oldContent, selection: oldSelection)
        }
        document.undoManager?.setActionName("Switch Editor")
        document.sourceMode = source
        editor.sourceMode = source
        let rendered = content ?? (source ? NSAttributedString(string: markdown, attributes: [.font: NSFont.monospacedSystemFont(ofSize: 14, weight: .regular), .foregroundColor: NSColor.labelColor]) : MarkdownCodec.render(markdown, baseURL: document.fileURL))
        document.storage.setAttributedString(rendered)
        editor.typingAttributes = source ? [.font: NSFont.monospacedSystemFont(ofSize: 14, weight: .regular), .foregroundColor: NSColor.labelColor] : MarkdownStyle.attributes()
        editor.setSelectedRange(NSRange(location: min(selection.location, rendered.length), length: min(selection.length, max(0, rendered.length - selection.location))))
        stylePicker.isEnabled = !source
        updateSourceItem()
        window?.subtitle = source ? "Markdown source" : ""
        editor.needsDisplay = true
        updateStatus()
    }

    private func updateSourceItem() {
        sourceItem?.label = editor.sourceMode ? "Rendered Editor" : "Markdown Source"
        sourceItem?.toolTip = editor.sourceMode ? "Show rendered editor (⇧⌘M)" : "Show Markdown source (⇧⌘M)"
        sourceItem?.image = NSImage(systemSymbolName: editor.sourceMode ? "doc.richtext" : "chevron.left.forwardslash.chevron.right", accessibilityDescription: sourceItem?.label)
    }

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] { toolbarDefaultItemIdentifiers(toolbar) }
    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [.init("style"), .init("bold"), .init("italic"), .init("code"), .init("link"), .init("table"), .flexibleSpace, .init("source")]
    }
    func toolbar(_ toolbar: NSToolbar, itemForItemIdentifier identifier: NSToolbarItem.Identifier, willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? {
        if identifier.rawValue == "table" {
            let item = NSMenuToolbarItem(itemIdentifier: identifier)
            item.label = "Table"
            item.toolTip = "Insert a table or edit the selected table"
            item.image = NSImage(systemSymbolName: "tablecells", accessibilityDescription: "Table")
            item.menu = EditorTextView.tableMenu(target: editor)
            item.showsIndicator = true
            return item
        }
        let item = NSToolbarItem(itemIdentifier: identifier)
        if identifier.rawValue == "style" {
            item.view = stylePicker
            item.label = "Paragraph Style"
            return item
        }
        let definitions: [String: (String, String, Selector)] = [
            "bold": ("Bold (⌘B)", "bold", #selector(EditorTextView.bold)),
            "italic": ("Italic (⌘I)", "italic", #selector(EditorTextView.italic)),
            "code": ("Inline Code (⇧⌘C)", "curlybraces", #selector(EditorTextView.code)),
            "link": ("Add Link (⌘K)", "link", #selector(EditorTextView.insertLink)),
            "source": ("Markdown Source (⇧⌘M)", "chevron.left.forwardslash.chevron.right", #selector(toggleSource))
        ]
        guard let (label, symbol, action) = definitions[identifier.rawValue] else { return nil }
        item.label = label
        item.toolTip = label
        item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: label)
        item.action = action
        item.target = identifier.rawValue == "source" ? self : editor
        if identifier.rawValue == "source" {
            sourceItem = item
            updateSourceItem()
        }
        return item
    }

}
