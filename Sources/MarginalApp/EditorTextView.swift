import AppKit
import MarginalCore

final class EditorTextView: NSTextView {
    var sourceMode = false
    private var isPasting = false
    private var structuralChange = false

    override func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        if let enabled = tableMenuValidation(menuItem) { return enabled }
        return super.validateMenuItem(menuItem)
    }

    override func insertText(_ insertString: Any, replacementRange: NSRange) {
        let selection = replacementRange.location == NSNotFound ? selectedRange() : replacementRange
        if !isPasting, !hasMarkedText(), insertString as? String == " ",
           applyTypingShortcut(at: selection, fencedCode: false) { return }
        if !sourceMode, let text = insertString as? String, let storage = textStorage,
           selection.location < storage.length, storage.attribute(.tableID, at: selection.location, effectiveRange: nil) != nil {
            var tableRange = NSRange()
            _ = storage.attribute(.tableID, at: selection.location, longestEffectiveRange: &tableRange,
                                  in: NSRange(location: 0, length: storage.length))
            if selection.location <= tableRange.location, NSMaxRange(selection) >= NSMaxRange(tableRange) {
                super.insertText(NSAttributedString(string: text, attributes: MarkdownStyle.attributes()), replacementRange: replacementRange)
                return
            }
            let cellText = text.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
                .replacingOccurrences(of: "\n", with: "\u{2028}").replacingOccurrences(of: "\u{2029}", with: "\u{2028}")
            super.insertText(cellText, replacementRange: replacementRange)
        } else { super.insertText(insertString, replacementRange: replacementRange) }
    }

    override func shouldChangeText(in affectedCharRange: NSRange, replacementString: String?) -> Bool {
        if !sourceMode, !structuralChange, replacementString != nil,
           !preservesTableBoundaries(in: affectedCharRange) { return false }
        return super.shouldChangeText(in: affectedCharRange, replacementString: replacementString)
    }

    private func preservesTableBoundaries(in range: NSRange) -> Bool {
        guard let storage = textStorage, NSMaxRange(range) <= storage.length else { return false }
        let text = storage.string as NSString
        for index in range.location..<NSMaxRange(range) {
            if text.character(at: index) == 10, storage.attribute(.tableID, at: index, effectiveRange: nil) != nil {
                var tableRange = NSRange()
                _ = storage.attribute(.tableID, at: index, longestEffectiveRange: &tableRange,
                                      in: NSRange(location: 0, length: storage.length))
                // Whole tables can be replaced. Partial edits must retain cell separators.
                if range.location > tableRange.location || NSMaxRange(range) < NSMaxRange(tableRange) { return false }
            }
        }
        return true
    }

    override func didChangeText() {
        if !sourceMode, string.isEmpty, typingAttributes[.tableID] != nil { typingAttributes = MarkdownStyle.attributes() }
        super.didChangeText()
    }

    /// Only transform a marker typed at the start of an ordinary paragraph.
    private func applyTypingShortcut(at selection: NSRange, fencedCode: Bool) -> Bool {
        guard !sourceMode, selection.length == 0, let storage = textStorage else { return false }
        let text = string as NSString
        let paragraph = text.paragraphRange(for: selection)
        let attrs = paragraph.location < storage.length ? storage.attributes(at: paragraph.location, effectiveRange: nil) : typingAttributes
        guard (attrs[.block] as? String ?? "p") == "p", attrs[.tableID] == nil else { return false }
        guard selection.location - paragraph.location <= 80 else { return false }
        let prefix = text.substring(with: NSRange(location: paragraph.location, length: selection.location - paragraph.location))
        var kind: String
        var number = 1
        var language = ""
        if prefix.hasPrefix("```"), !prefix.dropFirst(3).contains(where: { $0.isWhitespace || $0 == "`" }) {
            kind = "code"
            language = String(prefix.dropFirst(3))
        } else if fencedCode { return false }
        else if (1...6).contains(prefix.count), prefix.allSatisfy({ $0 == "#" }) { kind = "h\(prefix.count)" }
        else if ["-", "*", "+"].contains(prefix) { kind = "ul" }
        else if prefix == ">" { kind = "quote" }
        else if prefix.last == "." || prefix.last == ")" {
            let digits = prefix.dropLast()
            guard (1...9).contains(digits.count), digits.utf8.allSatisfy({ (48...57).contains($0) }), let value = Int(digits) else { return false }
            kind = "ol"; number = value
        } else { return false }
        var next = MarkdownStyle.attributes(block: kind == "quote" ? "p" : kind,
                                            quoteDepth: kind == "quote" ? (attrs[.quoteDepth] as? Int ?? 0) + 1 : attrs[.quoteDepth] as? Int ?? 0)
        next[.blockID] = UUID().uuidString
        if kind == "code" { next[.language] = language }
        if kind == "ol" { next[.listNumber] = number }
        let tail = NSRange(location: selection.location, length: NSMaxRange(paragraph) - selection.location)
        let replacement = NSMutableAttributedString(attributedString: storage.attributedSubstring(from: tail))
        let full = NSRange(location: 0, length: replacement.length)
        for key: NSAttributedString.Key in [.block, .blockID, .depth, .quoteDepth, .listNumber, .task, .language] { replacement.removeAttribute(key, range: full) }
        replacement.addAttributes(next, range: full)
        MarkdownStyle.restyle(replacement, range: full)
        let marker = kind == "ul" ? "•\t" : kind == "ol" ? "\(number).\t" : ""
        replacement.insert(NSAttributedString(string: marker, attributes: next), at: 0)
        breakUndoCoalescing()
        replaceWithUndo(range: paragraph, replacement: replacement, action: "Markdown Shortcut")
        setSelectedRange(NSRange(location: paragraph.location + (marker as NSString).length, length: 0))
        typingAttributes = next
        // Empty headings have no character attributes for the style picker to inspect.
        delegate?.textViewDidChangeSelection?(Notification(name: NSTextView.didChangeSelectionNotification, object: self))
        return true
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        if string.isEmpty {
            let attrs: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 16), .foregroundColor: NSColor.tertiaryLabelColor]
            (sourceMode ? "Write Markdown…" : "Start writing…" as NSString).draw(at: NSPoint(x: textContainerInset.width + 5, y: textContainerInset.height), withAttributes: attrs)
        }
    }

    override func paste(_ sender: Any?) {
        // Avoid importing arbitrary web/Word rich text that cannot survive Markdown save.
        guard let text = NSPasteboard.general.string(forType: .string) else { super.pasteAsPlainText(sender); return }
        isPasting = true
        defer { isPasting = false }
        insertText(text, replacementRange: selectedRange())
    }

    override func insertTab(_ sender: Any?) {
        if !moveBetweenCells(backwards: false) { super.insertTab(sender) }
    }

    override func insertBacktab(_ sender: Any?) {
        if !moveBetweenCells(backwards: true) { super.insertBacktab(sender) }
    }

    override func insertNewline(_ sender: Any?) {
        guard !sourceMode, let storage = textStorage else { super.insertNewline(sender); return }
        let selection = selectedRange()
        guard preservesTableBoundaries(in: selection) else { return }
        let nsString = string as NSString
        let line = nsString.paragraphRange(for: selection)
        let attrs = line.location < storage.length ? storage.attributes(at: line.location, effectiveRange: nil) : typingAttributes
        let kind = attrs[.block] as? String ?? "p"
        if kind == "p", applyTypingShortcut(at: selection, fencedCode: true) { return }
        if kind == "table" {
            // Keep Return inside a cell without creating a new native table paragraph.
            insertText("\u{2028}", replacementRange: selection)
            return
        }
        if kind == "code", selection.length == 0,
           nsString.substring(with: line).trimmingCharacters(in: .newlines) == "```" {
            let next = MarkdownStyle.attributes()
            breakUndoCoalescing()
            replaceWithUndo(range: line, replacement: NSAttributedString(string: "\n", attributes: next), action: "End Code Block")
            setSelectedRange(NSRange(location: line.location, length: 0))
            typingAttributes = next
            return
        }
        if kind == "ul" || kind == "ol" {
            let visible = nsString.substring(with: line).trimmingCharacters(in: .newlines)
            let contents = visible.components(separatedBy: "\t").dropFirst().joined(separator: "\t")
            if contents.trimmingCharacters(in: .whitespaces).isEmpty {
                replaceWithUndo(range: line, replacement: NSAttributedString(string: "", attributes: MarkdownStyle.attributes()), action: "End List")
                typingAttributes = MarkdownStyle.attributes()
                return
            }
            let number = (attrs[.listNumber] as? Int ?? 0) + 1
            var next = MarkdownStyle.attributes(block: kind, depth: attrs[.depth] as? Int ?? 0, quoteDepth: attrs[.quoteDepth] as? Int ?? 0)
            next[.listNumber] = number
            next[.blockID] = UUID().uuidString
            var prefix = kind == "ul" ? "•\t" : "\(number).\t"
            if attrs[.task] != nil { next[.task] = false; prefix = "☐\t" }
            let replacement = NSMutableAttributedString(string: "\n", attributes: attrs)
            replacement.append(NSAttributedString(string: prefix, attributes: next))
            insertText(replacement, replacementRange: selection)
            typingAttributes = next
        } else if ["code", "raw", "table"].contains(kind) {
            super.insertNewline(sender)
        } else {
            var next = MarkdownStyle.attributes(quoteDepth: attrs[.quoteDepth] as? Int ?? 0)
            next[.blockID] = UUID().uuidString
            if kind == "p" {
                for key: NSAttributedString.Key in [.strong, .emphasis, .inlineCode, .strike] { next[key] = typingAttributes[key] }
            }
            let end = NSMaxRange(line)
            let suffixStart = min(NSMaxRange(selection), end)
            let suffix = NSMutableAttributedString(attributedString: storage.attributedSubstring(from: NSRange(location: suffixStart, length: end - suffixStart)))
            let full = NSRange(location: 0, length: suffix.length)
            for key: NSAttributedString.Key in [.block, .blockID, .depth, .quoteDepth, .listNumber, .task, .language] { suffix.removeAttribute(key, range: full) }
            suffix.addAttributes(next, range: full)
            MarkdownStyle.restyle(suffix, range: full)
            let replacement = NSMutableAttributedString(string: "\n", attributes: attrs)
            replacement.append(suffix)
            replaceWithUndo(range: NSRange(location: selection.location, length: end - selection.location), replacement: replacement, action: "Typing")
            setSelectedRange(NSRange(location: selection.location + 1, length: 0))
            typingAttributes = next
        }
    }

    func replaceWithUndo(range: NSRange, replacement: NSAttributedString, action: String) {
        guard let storage = textStorage else { return }
        // NSTextView registers its own string undo in shouldChangeText. This operation
        // supplies an attributed undo, so registering both would apply the edit twice.
        let manager = undoManager
        manager?.disableUndoRegistration()
        structuralChange = true
        let approved = shouldChangeText(in: range, replacementString: replacement.string)
        structuralChange = false
        manager?.enableUndoRegistration()
        guard approved else { return }
        let old = storage.attributedSubstring(from: range)
        let oldSelection = selectedRange()
        let oldTypingAttributes = typingAttributes
        let newRange = NSRange(location: range.location, length: replacement.length)
        undoManager?.registerUndo(withTarget: self) { target in
            target.replaceWithUndo(range: newRange, replacement: old, action: action)
            target.setSelectedRange(oldSelection)
            target.typingAttributes = oldTypingAttributes
        }
        storage.replaceCharacters(in: range, with: replacement)
        setSelectedRange(NSRange(location: min(NSMaxRange(newRange), storage.length), length: 0))
        didChangeText()
        undoManager?.setActionName(action)
    }

    func toggleInline(_ key: NSAttributedString.Key, action: String) {
        guard !sourceMode, let storage = textStorage else { return }
        let range = selectedRange()
        if range.length == 0 {
            var attrs = typingAttributes
            if attrs[key] as? Bool == true { attrs.removeValue(forKey: key) } else { attrs[key] = true }
            let sample = NSMutableAttributedString(string: "x", attributes: attrs)
            MarkdownStyle.restyle(sample, range: NSRange(location: 0, length: 1))
            typingAttributes = sample.attributes(at: 0, effectiveRange: nil)
            return
        }
        let replacement = NSMutableAttributedString(attributedString: storage.attributedSubstring(from: range))
        var allEnabled = true
        replacement.enumerateAttribute(key, in: NSRange(location: 0, length: replacement.length)) { value, _, _ in
            if value as? Bool != true { allEnabled = false }
        }
        let full = NSRange(location: 0, length: replacement.length)
        if allEnabled { replacement.removeAttribute(key, range: full) } else { replacement.addAttribute(key, value: true, range: full) }
        MarkdownStyle.restyle(replacement, range: full)
        replaceWithUndo(range: range, replacement: replacement, action: action)
        setSelectedRange(range)
    }

    func formatBlock(_ kind: String) {
        guard !sourceMode, let storage = textStorage else { return }
        let selected = selectedRange()
        if selected.location < storage.length, storage.attribute(.block, at: selected.location, effectiveRange: nil) as? String == "table" { return }
        let nsString = string as NSString
        if storage.length == 0 || selected.location == storage.length && nsString.hasSuffix("\n") {
            typingAttributes = MarkdownStyle.attributes(block: kind == "quote" ? "p" : kind, quoteDepth: kind == "quote" ? 1 : 0)
            if kind == "ul" || kind == "ol" {
                insertText(kind == "ul" ? "•\t" : "1.\t", replacementRange: selected)
            }
            return
        }
        var selectedForParagraphs = selected
        if selected.length > 0 { selectedForParagraphs.length -= 1 }
        let range = nsString.paragraphRange(for: selectedForParagraphs)
        let replacement = NSMutableAttributedString(attributedString: storage.attributedSubstring(from: range))
        var includesTable = false
        replacement.enumerateAttribute(.tableID, in: NSRange(location: 0, length: replacement.length)) { value, _, _ in
            if value != nil { includesTable = true }
        }
        guard !includesTable else { return }
        let codeGroup = UUID().uuidString
        let replacementString = replacement.string as NSString
        var paragraphs: [NSRange] = []
        var cursor = 0
        while cursor < replacement.length {
            let part = replacementString.paragraphRange(for: NSRange(location: cursor, length: 0))
            paragraphs.append(part); cursor = NSMaxRange(part)
        }
        // Reverse order keeps offsets stable while adding/removing visible list markers.
        for (index, part) in paragraphs.enumerated().reversed() {
            let old = replacement.attributes(at: part.location, effectiveRange: nil)
            let oldKind = old[.block] as? String ?? "p"
            let contents = NSMutableAttributedString(attributedString: replacement.attributedSubstring(from: part))
            if oldKind == "ul" || oldKind == "ol", let tab = contents.string.firstIndex(of: "\t") {
                let length = (String(contents.string[...tab]) as NSString).length
                contents.deleteCharacters(in: NSRange(location: 0, length: length))
            }
            let block = kind == "quote" ? "p" : kind
            let attrs = MarkdownStyle.attributes(block: block, quoteDepth: kind == "quote" ? 1 : 0)
            let full = NSRange(location: 0, length: contents.length)
            for key: NSAttributedString.Key in [.block, .depth, .quoteDepth, .listNumber, .task, .language, .blockID] {
                contents.removeAttribute(key, range: full)
            }
            contents.addAttributes(attrs, range: full)
            let paragraphID = kind == "code" ? codeGroup : UUID().uuidString
            contents.addAttribute(.blockID, value: paragraphID, range: full)
            if kind == "ul" || kind == "ol" {
                var markerAttrs = attrs
                markerAttrs[.listNumber] = index + 1
                markerAttrs[.blockID] = paragraphID
                contents.addAttribute(.listNumber, value: index + 1, range: full)
                contents.insert(NSAttributedString(string: kind == "ul" ? "•\t" : "\(index + 1).\t", attributes: markerAttrs), at: 0)
            }
            MarkdownStyle.restyle(contents, range: NSRange(location: 0, length: contents.length))
            replacement.replaceCharacters(in: part, with: contents)
        }
        replaceWithUndo(range: range, replacement: replacement, action: "Paragraph Style")
        setSelectedRange(NSRange(location: range.location, length: selected.length > 0 ? replacement.length : 0))
        if range.location < storage.length { typingAttributes = storage.attributes(at: range.location, effectiveRange: nil) }
    }

    @objc func bold(_ sender: Any?) { toggleInline(.strong, action: "Bold") }
    @objc func italic(_ sender: Any?) { toggleInline(.emphasis, action: "Italic") }
    @objc func code(_ sender: Any?) { toggleInline(.inlineCode, action: "Code") }
    @objc func strike(_ sender: Any?) { toggleInline(.strike, action: "Strikethrough") }
    @objc func body(_ sender: Any?) { formatBlock("p") }
    @objc func heading1(_ sender: Any?) { formatBlock("h1") }
    @objc func heading2(_ sender: Any?) { formatBlock("h2") }
    @objc func heading3(_ sender: Any?) { formatBlock("h3") }
    @objc func bullets(_ sender: Any?) { formatBlock("ul") }
    @objc func numbers(_ sender: Any?) { formatBlock("ol") }
    @objc func quote(_ sender: Any?) { formatBlock("quote") }
    @objc func codeBlock(_ sender: Any?) { formatBlock("code") }

    @objc func insertLink(_ sender: Any?) {
        guard !sourceMode, let storage = textStorage, let window else { return }
        let selection = selectedRange()
        let alert = NSAlert()
        alert.messageText = "Add Link"
        alert.addButton(withTitle: "Add Link")
        alert.addButton(withTitle: "Cancel")
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 340, height: 24))
        field.placeholderString = "https://example.com"
        if selection.location < storage.length, let link = storage.attribute(.link, at: selection.location, effectiveRange: nil) {
            field.stringValue = String(describing: link)
        }
        alert.accessoryView = field
        alert.beginSheetModal(for: window) { [weak self] response in
            guard response == .alertFirstButtonReturn, let self else { return }
            let destination = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !destination.isEmpty else { return }
            var attrs = self.typingAttributes
            attrs[.link] = destination
            let replacement = selection.length > 0 ? NSMutableAttributedString(attributedString: storage.attributedSubstring(from: selection)) : NSMutableAttributedString(string: destination, attributes: attrs)
            replacement.addAttribute(.link, value: destination, range: NSRange(location: 0, length: replacement.length))
            self.replaceWithUndo(range: selection, replacement: replacement, action: "Add Link")
        }
        alert.window.initialFirstResponder = field
    }

    @objc func removeLink(_ sender: Any?) {
        guard !sourceMode, let storage = textStorage, selectedRange().length > 0 else { return }
        let range = selectedRange()
        let replacement = NSMutableAttributedString(attributedString: storage.attributedSubstring(from: range))
        replacement.removeAttribute(.link, range: NSRange(location: 0, length: replacement.length))
        replaceWithUndo(range: range, replacement: replacement, action: "Remove Link")
        setSelectedRange(range)
    }
}
