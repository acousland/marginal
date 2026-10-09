import AppKit

/// Builds native table cells while retaining inline Markdown attributes.
public enum MarkdownTable {
    public static func render(cells: [[NSAttributedString]], alignments: [String],
                              id: String = UUID().uuidString, quoteDepth: Int = 0) -> NSAttributedString {
        let output = NSMutableAttributedString()
        let columns = max(1, cells.map(\.count).max() ?? 1)
        let table = NSTextTable()
        table.numberOfColumns = columns
        table.collapsesBorders = true
        table.hidesEmptyCells = false
        table.setValue(100, type: .percentageValueType, for: .width)
        for (row, contents) in cells.enumerated() {
            for column in 0..<columns {
                let block = NSTextTableBlock(table: table, startingRow: row, rowSpan: 1, startingColumn: column, columnSpan: 1)
                block.setWidth(8, type: .absoluteValueType, for: .padding)
                block.setWidth(0.5, type: .absoluteValueType, for: .border)
                block.setBorderColor(.separatorColor)
                if row == 0 { block.backgroundColor = .quaternaryLabelColor }
                let alignment = column < alignments.count ? alignments[column] : "none"
                var attrs = MarkdownStyle.attributes(block: "table", quoteDepth: quoteDepth)
                attrs[.tableID] = id
                attrs[.tableRow] = row
                attrs[.tableColumn] = column
                attrs[.tableAlignment] = alignment
                attrs[.blockID] = UUID().uuidString
                let style = (attrs[.paragraphStyle] as! NSParagraphStyle).mutableCopy() as! NSMutableParagraphStyle
                style.textBlocks = [block]
                style.paragraphSpacing = 0
                style.alignment = alignment == "center" ? .center : alignment == "right" ? .right : .left
                attrs[.paragraphStyle] = style
                let cell = NSMutableAttributedString(attributedString: column < contents.count ? contents[column] : NSAttributedString(string: ""))
                // A cell has one terminal paragraph separator; internal breaks stay in the cell.
                cell.append(NSAttributedString(string: "\n"))
                cell.addAttributes(attrs, range: NSRange(location: 0, length: cell.length))
                MarkdownStyle.restyle(cell, range: NSRange(location: 0, length: cell.length))
                if row == 0 {
                    cell.enumerateAttributes(in: NSRange(location: 0, length: cell.length)) { attributes, range, _ in
                        let font = attributes[.font] as? NSFont ?? NSFont.systemFont(ofSize: 16)
                        cell.addAttribute(.font, value: NSFontManager.shared.convert(font, toHaveTrait: .boldFontMask), range: range)
                    }
                }
                output.append(cell)
            }
        }
        return output
    }
}
