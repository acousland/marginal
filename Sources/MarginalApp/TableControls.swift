import AppKit
import MarginalCore

enum TableAxis { case row, column }

struct TableAxisSelection: Equatable {
    let id: String
    let axis: TableAxis
    let anchor: Int
    let extent: Int
    var indices: ClosedRange<Int> { min(anchor, extent)...max(anchor, extent) }
}

struct TableGeometry: Equatable {
    let id: String
    let location: Int
    let rows: [NSRect]
    let columns: [NSRect]
    var rect: NSRect { rows.reduce(.zero) { $0.isEmpty ? $1 : $0.union($1) } }
}

extension EditorTextView {
    func tableGeometry(at location: Int) -> TableGeometry? {
        guard !sourceMode, let storage = textStorage, location < storage.length,
              let layout = layoutManager else { return nil }
        var tableRange = NSRange()
        guard let id = storage.attribute(.tableID, at: location, longestEffectiveRange: &tableRange,
                                         in: NSRange(location: 0, length: storage.length)) as? String else { return nil }
        var rows: [Int: NSRect] = [:]
        var columns: [Int: NSRect] = [:]
        storage.enumerateAttributes(in: tableRange) { attrs, range, _ in
            guard let row = attrs[.tableRow] as? Int, let column = attrs[.tableColumn] as? Int,
                  let block = (attrs[.paragraphStyle] as? NSParagraphStyle)?.textBlocks.first as? NSTextTableBlock else { return }
            let glyph = layout.glyphIndexForCharacter(at: range.location)
            let bounds = layout.boundsRect(for: block, at: glyph, effectiveRange: nil)
                .offsetBy(dx: textContainerOrigin.x, dy: textContainerOrigin.y)
            guard !bounds.isEmpty, bounds.width.isFinite, bounds.height.isFinite else { return }
            rows[row] = rows[row].map { $0.union(bounds) } ?? bounds
            columns[column] = columns[column].map { $0.union(bounds) } ?? bounds
        }
        guard !rows.isEmpty, !columns.isEmpty else { return nil }
        return TableGeometry(id: id, location: tableRange.location,
                             rows: rows.keys.sorted().compactMap { rows[$0] },
                             columns: columns.keys.sorted().compactMap { columns[$0] })
    }

    func updateTableControls() {
        if tableControls.superview == nil { addSubview(tableControls) }
        if tableControls.frame != bounds { tableControls.frame = bounds }
        let location = hoveredTableLocation ?? selectedRange().location
        let geometry = tableGeometry(at: location)
        tableControls.update(geometry: geometry, selection: tableAxisSelection,
                             scale: enclosingScrollView?.magnification ?? 1)
    }

    func updateTableHover(at point: NSPoint) {
        let previous = hoveredTableLocation
        let location = characterIndexForInsertion(at: point)
        if let geometry = tableGeometry(at: location), geometry.rect.contains(point) {
            hoveredTableLocation = geometry.location
        } else if let geometry = tableControls.geometry,
                  geometry.rect.insetBy(dx: -26 / tableControls.scale, dy: -26 / tableControls.scale).contains(point) {
            hoveredTableLocation = geometry.location
        } else { hoveredTableLocation = nil }
        tableControls.updateHover(at: point)
        if previous != hoveredTableLocation { needsDisplay = true }
    }

    func selectTableAxis(id: String, axis: TableAxis, index: Int, extending: Bool = false) {
        guard let table = currentTable(), table.id == id,
              (axis == .row ? table.cells.indices : table.alignments.indices).contains(index) else { return }
        let old = tableAxisSelection
        let anchor = extending && old?.id == id && old?.axis == axis ? old!.anchor : index
        // Clicking an already selected handle opens the menu for the whole selection.
        let selection = !extending && old?.id == id && old?.axis == axis && old!.indices.contains(index)
            ? old! : TableAxisSelection(id: id, axis: axis, anchor: anchor, extent: index)
        selectCell(id: id, row: axis == .row ? selection.indices.lowerBound : 0,
                   column: axis == .column ? selection.indices.lowerBound : 0)
        tableAxisSelection = selection
        hoveredTableLocation = table.range.location
        window?.makeFirstResponder(self)
        needsDisplay = true
    }

    func selectedTableText() -> String? {
        guard let selection = tableAxisSelection, let table = currentTable(), selection.id == table.id else { return nil }
        let rows = selection.axis == .row ? Array(selection.indices) : Array(table.cells.indices)
        let columns = selection.axis == .column ? Array(selection.indices) : Array(table.alignments.indices)
        guard rows.allSatisfy({ table.cells.indices.contains($0) }), columns.allSatisfy({ table.alignments.indices.contains($0) }) else { return nil }
        return rows.map { row in columns.map { table.cells[row][$0].string.replacingOccurrences(of: "\u{2028}", with: "\n") }.joined(separator: "\t") }.joined(separator: "\n")
    }
}

final class TableEdgeButton: NSButton {
    let axis: TableAxis
    let index: Int
    let inserts: Bool
    var selected = false

    init(axis: TableAxis, index: Int, inserts: Bool, frame: NSRect) {
        self.axis = axis; self.index = index; self.inserts = inserts
        super.init(frame: frame)
        isBordered = false
        imagePosition = .imageOnly
        image = NSImage(systemSymbolName: inserts ? "plus" : "ellipsis", accessibilityDescription: nil)
        let name = axis == .row ? "row" : "column"
        let label = inserts ? "Insert \(name) \(index + 1)" : "Select \(name) \(index + 1)"
        setAccessibilityLabel(label)
        toolTip = inserts ? "Add a \(name) here" : "Select \(name) \(index + 1) and show actions. Shift-click to select several."
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func draw(_ dirtyRect: NSRect) {
        (selected ? NSColor.controlAccentColor.withAlphaComponent(0.2) : NSColor.controlBackgroundColor).setFill()
        NSBezierPath(roundedRect: bounds.insetBy(dx: 1, dy: 1), xRadius: 4, yRadius: 4).fill()
        super.draw(dirtyRect)
    }
}

final class TableControlsView: NSView {
    weak var editor: EditorTextView?
    private(set) var geometry: TableGeometry?
    private var selection: TableAxisSelection?
    private var hoverPoint: NSPoint?
    private(set) var scale: CGFloat = 1
    override var isFlipped: Bool { true }

    init(editor: EditorTextView) { self.editor = editor; super.init(frame: .zero) }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func update(geometry: TableGeometry?, selection: TableAxisSelection?, scale: CGFloat) {
        let changed = self.geometry != geometry || abs(self.scale - scale) > 0.001
        let selectionChanged = self.selection != selection
        self.geometry = geometry; self.selection = selection; self.scale = scale
        if isHidden != (geometry == nil) { isHidden = geometry == nil }
        guard let geometry else { return }
        if changed {
            subviews.forEach { $0.removeFromSuperview() }
            let size = 18 / scale
            for (index, rect) in geometry.rows.enumerated() {
                addButton(axis: .row, index: index, inserts: false,
                          rect: NSRect(x: geometry.rect.minX - size - 3 / scale, y: rect.midY - size / 2, width: size, height: size))
            }
            for (index, rect) in geometry.columns.enumerated() {
                addButton(axis: .column, index: index, inserts: false,
                          rect: NSRect(x: rect.midX - size / 2, y: geometry.rect.minY - size - 3 / scale, width: size, height: size))
            }
            // Insertion buttons sit on the boundaries, separate from selection handles.
            let plusSize = 14 / scale
            for index in 0...geometry.rows.count {
                let y = index == geometry.rows.count ? geometry.rect.maxY : geometry.rows[index].minY
                addButton(axis: .row, index: index, inserts: true,
                          rect: NSRect(x: geometry.rect.minX - size / 2 - 3 / scale - plusSize / 2, y: y - plusSize / 2, width: plusSize, height: plusSize))
            }
            for index in 0...geometry.columns.count {
                let x = index == geometry.columns.count ? geometry.rect.maxX : geometry.columns[index].minX
                addButton(axis: .column, index: index, inserts: true,
                          rect: NSRect(x: x - plusSize / 2, y: geometry.rect.minY - size / 2 - 3 / scale - plusSize / 2, width: plusSize, height: plusSize))
            }
        }
        if changed || selectionChanged {
            for button in subviews.compactMap({ $0 as? TableEdgeButton }) {
                button.selected = !button.inserts && selection?.id == geometry.id && selection?.axis == button.axis && selection!.indices.contains(button.index)
                button.contentTintColor = button.selected ? .controlAccentColor : .secondaryLabelColor
                button.needsDisplay = true
            }
            needsDisplay = true
        }
        updateHover(at: hoverPoint)
    }

    func updateHover(at point: NSPoint?) {
        hoverPoint = point
        for button in subviews.compactMap({ $0 as? TableEdgeButton }) where button.inserts {
            let hidden = point.map { hypot($0.x - button.frame.midX, $0.y - button.frame.midY) > 8 / scale } ?? true
            if button.isHidden != hidden { button.isHidden = hidden }
        }
    }

    private func addButton(axis: TableAxis, index: Int, inserts: Bool, rect: NSRect) {
        let button = TableEdgeButton(axis: axis, index: index, inserts: inserts, frame: rect)
        button.target = self
        button.action = #selector(activate(_:))
        addSubview(button)
    }

    // Let all clicks inside table cells continue to the native text editor.
    override func hitTest(_ point: NSPoint) -> NSView? {
        let hit = super.hitTest(point)
        return hit === self ? nil : hit
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let geometry, let selection, selection.id == geometry.id else { return }
        let rects = selection.axis == .row ? geometry.rows : geometry.columns
        NSColor.controlAccentColor.withAlphaComponent(0.16).setFill()
        for index in selection.indices where rects.indices.contains(index) { NSBezierPath(rect: rects[index]).fill() }
    }

    @objc private func activate(_ button: TableEdgeButton) {
        guard let editor, let geometry else { return }
        // Hover controls can belong to a different table from the insertion point.
        if editor.currentTable()?.id != geometry.id { editor.setSelectedRange(NSRange(location: geometry.location, length: 0)) }
        if button.inserts {
            editor.insertTableAxis(button.axis, at: button.index)
        } else {
            let extending = NSApp.currentEvent?.modifierFlags.contains(.shift) == true
            editor.selectTableAxis(id: geometry.id, axis: button.axis, index: button.index, extending: extending)
            editor.updateTableControls()
            if !extending {
                let menu = editor.tableAxisMenu(button.axis)
                menu.popUp(positioning: nil, at: NSPoint(x: button.bounds.minX, y: button.bounds.maxY + 2 / scale), in: button)
            }
        }
    }
}
