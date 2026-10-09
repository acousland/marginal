import AppKit
import MarginalCore

extension EditorTextView {
    var canInsertTable: Bool {
        guard !sourceMode, let storage = textStorage else { return false }
        let selection = selectedRange()
        if selection.length == 0 {
            return selection.location == storage.length || storage.attribute(.tableID, at: selection.location, effectiveRange: nil) == nil
        }
        var includesTable = false
        storage.enumerateAttribute(.tableID, in: selection) { value, _, _ in if value != nil { includesTable = true } }
        return !includesTable
    }
    struct TableSelection {
        let range: NSRange
        let id: String
        let quoteDepth: Int
        var cells: [[NSAttributedString]]
        var alignments: [String]
        let row: Int
        let column: Int
    }

    func currentTable() -> TableSelection? {
        guard !sourceMode, let storage = textStorage else { return nil }
        let selection = selectedRange()
        guard selection.location < storage.length else { return nil }
        var range = NSRange()
        let attrs = storage.attributes(at: selection.location, effectiveRange: nil)
        guard let id = storage.attribute(.tableID, at: selection.location, longestEffectiveRange: &range,
                                         in: NSRange(location: 0, length: storage.length)) as? String,
              NSMaxRange(selection) <= NSMaxRange(range) else { return nil }
        var contents: [Int: [Int: NSMutableAttributedString]] = [:]
        var alignments: [Int: String] = [:]
        let string = storage.string as NSString
        var cursor = range.location
        while cursor < NSMaxRange(range) {
            let paragraph = NSIntersectionRange(string.paragraphRange(for: NSRange(location: cursor, length: 0)), range)
            guard paragraph.length > 0 else { return nil }
            let meta = storage.attributes(at: cursor, effectiveRange: nil)
            let row = meta[.tableRow] as? Int ?? 0
            let column = meta[.tableColumn] as? Int ?? 0
            var content = paragraph
            while content.length > 0 && [10, 13].contains(string.character(at: NSMaxRange(content) - 1)) { content.length -= 1 }
            let cell = storage.attributedSubstring(from: content)
            if let existing = contents[row]?[column] {
                existing.append(NSAttributedString(string: "\u{2028}"))
                existing.append(cell)
            } else { contents[row, default: [:]][column] = NSMutableAttributedString(attributedString: cell) }
            alignments[column] = meta[.tableAlignment] as? String ?? "none"
            cursor = NSMaxRange(paragraph)
        }
        let rows = (contents.keys.max() ?? 0) + 1
        let columns = (contents.values.flatMap { $0.keys }.max() ?? 0) + 1
        let cells = (0..<rows).map { row in
            (0..<columns).map { column -> NSAttributedString in contents[row]?[column] ?? NSAttributedString(string: "") }
        }
        return TableSelection(range: range, id: id, quoteDepth: attrs[.quoteDepth] as? Int ?? 0,
                              cells: cells, alignments: (0..<columns).map { alignments[$0] ?? "none" },
                              row: attrs[.tableRow] as? Int ?? 0, column: attrs[.tableColumn] as? Int ?? 0)
    }

    private func replaceTable(_ table: TableSelection, row: Int, column: Int, action: String) {
        let replacement = MarkdownTable.render(cells: table.cells, alignments: table.alignments, id: table.id, quoteDepth: table.quoteDepth)
        breakUndoCoalescing()
        replaceWithUndo(range: table.range, replacement: replacement, action: action)
        selectCell(id: table.id, row: row, column: column)
    }

    func selectCell(id: String, row: Int, column: Int, selectContents: Bool = false) {
        guard let storage = textStorage else { return }
        var cellRange: NSRange?
        storage.enumerateAttributes(in: NSRange(location: 0, length: storage.length)) { attrs, range, _ in
            if attrs[.tableID] as? String == id && attrs[.tableRow] as? Int == row && attrs[.tableColumn] as? Int == column {
                cellRange = cellRange.map { NSUnionRange($0, range) } ?? range
            }
        }
        guard var range = cellRange else { return }
        typingAttributes = storage.attributes(at: range.location, effectiveRange: nil)
        if selectContents {
            if range.length > 0, (storage.string as NSString).character(at: NSMaxRange(range) - 1) == 10 { range.length -= 1 }
        } else { range.length = 0 }
        setSelectedRange(range)
        scrollRangeToVisible(range)
    }

    /// Rows includes the required Markdown header; the UI asks for body rows.
    func insertTable(rows: Int, columns: Int) {
        guard canInsertTable, let storage = textStorage,
              (2...101).contains(rows), (1...20).contains(columns) else { return }
        let selection = selectedRange()
        let id = UUID().uuidString
        let cells = (0..<rows).map { row in
            (0..<columns).map { column in NSAttributedString(string: row == 0 ? "Column \(column + 1)" : "") }
        }
        let replacement = NSMutableAttributedString()
        let string = storage.string as NSString
        if selection.location > 0, string.character(at: selection.location - 1) != 10 {
            // End the existing paragraph before inserting the table.
            replacement.append(NSAttributedString(string: "\n", attributes: storage.attributes(at: selection.location - 1, effectiveRange: nil)))
        }
        replacement.append(MarkdownTable.render(cells: cells, alignments: [], id: id))
        if NSMaxRange(selection) == storage.length {
            replacement.append(NSAttributedString(string: "\n", attributes: MarkdownStyle.attributes()))
        }
        breakUndoCoalescing()
        replaceWithUndo(range: selection, replacement: replacement, action: "Insert Table")
        selectCell(id: id, row: 0, column: 0, selectContents: true)
    }

    @objc func insertTable(_ sender: Any?) {
        guard canInsertTable, let window else { return }
        let alert = NSAlert()
        alert.messageText = "Insert Table"
        alert.informativeText = "A header row is included above the body rows."
        alert.addButton(withTitle: "Insert Table")
        alert.addButton(withTitle: "Cancel")
        let rows = NSTextField(string: "2")
        let columns = NSTextField(string: "2")
        rows.setAccessibilityLabel("Body rows")
        columns.setAccessibilityLabel("Columns")
        let stack = NSStackView(views: [NSTextField(labelWithString: "Body rows (1–100)"), rows,
                                      NSTextField(labelWithString: "Columns (1–20)"), columns])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 8
        stack.frame = NSRect(x: 0, y: 0, width: 250, height: 120)
        rows.widthAnchor.constraint(equalToConstant: 250).isActive = true
        columns.widthAnchor.constraint(equalToConstant: 250).isActive = true
        alert.accessoryView = stack
        alert.window.initialFirstResponder = rows
        alert.beginSheetModal(for: window) { [weak self] response in
            guard response == .alertFirstButtonReturn else { return }
            self?.insertTable(rows: min(100, max(1, rows.integerValue)) + 1, columns: min(20, max(1, columns.integerValue)))
            window.makeFirstResponder(self)
        }
    }

    private func addRow(after: Bool) {
        guard var table = currentTable(), after || table.row > 0 else { return }
        let index = after ? table.row + 1 : table.row
        table.cells.insert(table.alignments.map { _ in NSAttributedString(string: "") }, at: index)
        replaceTable(table, row: index, column: table.column, action: "Add Table Row")
    }
    @objc func addRowAbove(_ sender: Any?) { addRow(after: false) }
    @objc func addRowBelow(_ sender: Any?) { addRow(after: true) }
    @objc func deleteRow(_ sender: Any?) {
        guard var table = currentTable(), table.row > 0 else { return }
        table.cells.remove(at: table.row)
        replaceTable(table, row: min(table.row, table.cells.count - 1), column: table.column, action: "Delete Table Row")
    }

    private func addColumn(after: Bool) {
        guard var table = currentTable() else { return }
        let index = table.column + (after ? 1 : 0)
        for row in table.cells.indices { table.cells[row].insert(NSAttributedString(string: ""), at: index) }
        table.alignments.insert("none", at: index)
        replaceTable(table, row: table.row, column: index, action: "Add Table Column")
    }
    @objc func addColumnBefore(_ sender: Any?) { addColumn(after: false) }
    @objc func addColumnAfter(_ sender: Any?) { addColumn(after: true) }
    @objc func deleteColumn(_ sender: Any?) {
        guard var table = currentTable(), table.alignments.count > 1 else { return }
        for row in table.cells.indices { table.cells[row].remove(at: table.column) }
        table.alignments.remove(at: table.column)
        replaceTable(table, row: table.row, column: min(table.column, table.alignments.count - 1), action: "Delete Table Column")
    }
    private func alignColumn(_ alignment: String) {
        guard var table = currentTable() else { return }
        table.alignments[table.column] = alignment
        replaceTable(table, row: table.row, column: table.column, action: "Align Table Column")
    }
    @objc func alignColumnLeft(_ sender: Any?) { alignColumn("left") }
    @objc func alignColumnCenter(_ sender: Any?) { alignColumn("center") }
    @objc func alignColumnRight(_ sender: Any?) { alignColumn("right") }
    @objc func deleteTable(_ sender: Any?) {
        guard let table = currentTable() else { return }
        breakUndoCoalescing()
        replaceWithUndo(range: table.range, replacement: NSAttributedString(string: ""), action: "Delete Table")
        typingAttributes = MarkdownStyle.attributes()
    }
    @objc func paragraphAfterTable(_ sender: Any?) {
        guard let table = currentTable(), let storage = textStorage else { return }
        let location = NSMaxRange(table.range)
        if location < storage.length, storage.attribute(.block, at: location, effectiveRange: nil) as? String == "p" {
            setSelectedRange(NSRange(location: location, length: 0))
        } else {
            breakUndoCoalescing()
            replaceWithUndo(range: NSRange(location: location, length: 0), replacement: NSAttributedString(string: "\n", attributes: MarkdownStyle.attributes()), action: "Paragraph After Table")
            setSelectedRange(NSRange(location: location, length: 0))
        }
        typingAttributes = MarkdownStyle.attributes()
        scrollRangeToVisible(selectedRange())
    }

    func moveBetweenCells(backwards: Bool) -> Bool {
        guard let table = currentTable() else { return false }
        let columns = table.alignments.count
        var index = table.row * columns + table.column + (backwards ? -1 : 1)
        if index < 0 { index = 0 }
        if index == table.cells.count * columns {
            addRowBelow(nil)
            if let added = currentTable() { selectCell(id: added.id, row: added.row, column: 0, selectContents: true) }
        } else { selectCell(id: table.id, row: index / columns, column: index % columns, selectContents: true) }
        return true
    }

    private static let tableMenuDefinitions: [(String, Selector?)] = [
            ("Insert Table…", #selector(insertTable(_:))), ("", nil),
            ("Add Row Above", #selector(addRowAbove(_:))), ("Add Row Below", #selector(addRowBelow(_:))),
            ("Delete Row", #selector(deleteRow(_:))), ("", nil),
            ("Add Column Before", #selector(addColumnBefore(_:))), ("Add Column After", #selector(addColumnAfter(_:))),
            ("Delete Column", #selector(deleteColumn(_:))), ("", nil),
            ("Align Column Left", #selector(alignColumnLeft(_:))), ("Align Column Center", #selector(alignColumnCenter(_:))),
            ("Align Column Right", #selector(alignColumnRight(_:))), ("", nil),
            ("Paragraph After Table", #selector(paragraphAfterTable(_:))), ("Delete Table", #selector(deleteTable(_:)))
        ]

    static func tableMenu(target: AnyObject? = nil) -> NSMenu {
        let menu = NSMenu(title: "Table")
        for (title, action) in tableMenuDefinitions {
            if title.isEmpty { menu.addItem(.separator()); continue }
            let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
            item.target = target
            menu.addItem(item)
        }
        return menu
    }

    func tableMenuValidation(_ menuItem: NSMenuItem) -> Bool? {
        guard let action = menuItem.action, Self.tableMenuDefinitions.contains(where: { $0.1 == action }) else { return nil }
        guard !sourceMode else { return false }
        let table = currentTable()
        if action == #selector(insertTable(_:)) { return canInsertTable }
        guard let table else { return false }
        if action == #selector(deleteRow(_:)) || action == #selector(addRowAbove(_:)) { return table.row > 0 }
        if action == #selector(deleteColumn(_:)) { return table.alignments.count > 1 }
        return true
    }
}
