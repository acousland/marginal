import AppKit
import Markdown

public extension NSAttributedString.Key {
    static let block = Self("Marginal.block")
    static let blockID = Self("Marginal.blockID")
    static let depth = Self("Marginal.depth")
    static let quoteDepth = Self("Marginal.quoteDepth")
    static let listNumber = Self("Marginal.listNumber")
    static let task = Self("Marginal.task")
    static let language = Self("Marginal.language")
    static let strong = Self("Marginal.strong")
    static let emphasis = Self("Marginal.emphasis")
    static let inlineCode = Self("Marginal.inlineCode")
    static let strike = Self("Marginal.strike")
    static let literal = Self("Marginal.literal")
    static let tableID = Self("Marginal.tableID")
    static let tableRow = Self("Marginal.tableRow")
    static let tableColumn = Self("Marginal.tableColumn")
    static let tableAlignment = Self("Marginal.tableAlignment")
    static let linkTitle = Self("Marginal.linkTitle")
    static let imageMarkdown = Self("Marginal.imageMarkdown")
}

public enum MarkdownStyle {
    public static func attributes(block: String = "p", depth: Int = 0, quoteDepth: Int = 0) -> [NSAttributedString.Key: Any] {
        var attrs: [NSAttributedString.Key: Any] = [.block: block, .depth: depth, .quoteDepth: quoteDepth]
        let style = NSMutableParagraphStyle()
        style.lineSpacing = 5
        style.paragraphSpacing = 14
        style.headIndent = CGFloat(depth * 24 + quoteDepth * 20)
        style.firstLineHeadIndent = style.headIndent
        if block == "ul" || block == "ol" {
            style.firstLineHeadIndent += 4
            style.headIndent += 26
            style.tabStops = [NSTextTab(textAlignment: .left, location: style.headIndent)]
            style.paragraphSpacing = 6
        }
        if block.hasPrefix("h"), let level = Int(block.dropFirst()) {
            let sizes: [CGFloat] = [32, 26, 21, 18, 17, 16]
            attrs[.font] = NSFont.systemFont(ofSize: sizes[min(max(level - 1, 0), 5)], weight: .semibold)
            style.paragraphSpacingBefore = 14
            style.paragraphSpacing = 12
        } else if block == "code" || block == "raw" {
            attrs[.font] = NSFont.monospacedSystemFont(ofSize: 14, weight: .regular)
            attrs[.backgroundColor] = NSColor.quaternaryLabelColor
            style.lineSpacing = 3
            style.paragraphSpacing = 0
        } else {
            attrs[.font] = NSFont.systemFont(ofSize: 16)
        }
        attrs[.foregroundColor] = quoteDepth > 0 ? NSColor.secondaryLabelColor : NSColor.labelColor
        attrs[.paragraphStyle] = style
        return attrs
    }

    public static func restyle(_ text: NSMutableAttributedString, range: NSRange) {
        guard range.length > 0 else { return }
        var changes: [(NSRange, [NSAttributedString.Key: Any])] = []
        text.enumerateAttributes(in: range) { attrs, part, _ in
            let base = attributes(block: attrs[.block] as? String ?? "p", depth: attrs[.depth] as? Int ?? 0, quoteDepth: attrs[.quoteDepth] as? Int ?? 0)
            if let oldStyle = attrs[.paragraphStyle] as? NSParagraphStyle, !oldStyle.textBlocks.isEmpty,
               let style = base[.paragraphStyle] as? NSMutableParagraphStyle {
                style.textBlocks = oldStyle.textBlocks
                style.alignment = oldStyle.alignment
                style.paragraphSpacing = 0
            }
            var visual = base.filter { [.font, .foregroundColor, .paragraphStyle].contains($0.key) }
            var font = base[.font] as! NSFont
            var traits = NSFontTraitMask()
            if attrs[.strong] as? Bool == true { traits.insert(.boldFontMask) }
            if attrs[.emphasis] as? Bool == true { traits.insert(.italicFontMask) }
            if attrs[.inlineCode] as? Bool == true { font = .monospacedSystemFont(ofSize: 14, weight: .regular) }
            visual[.font] = NSFontManager.shared.convert(font, toHaveTrait: traits)
            if attrs[.inlineCode] as? Bool == true || attrs[.block] as? String == "code" || attrs[.block] as? String == "raw" {
                visual[.backgroundColor] = NSColor.quaternaryLabelColor
            }
            if attrs[.strike] as? Bool == true { visual[.strikethroughStyle] = NSUnderlineStyle.single.rawValue }
            changes.append((part, visual))
        }
        for (part, attrs) in changes {
            text.removeAttribute(.backgroundColor, range: part)
            text.removeAttribute(.strikethroughStyle, range: part)
            text.addAttributes(attrs, range: part)
        }
    }
}

public enum MarkdownCodec {
    public static func render(_ source: String, baseURL: URL? = nil) -> NSAttributedString {
        let output = NSMutableAttributedString()
        var markdown = source
        // YAML front matter is metadata, not a heading. Keep it verbatim.
        if markdown.hasPrefix("---\n") || markdown.hasPrefix("---\r\n") {
            let lines = markdown.components(separatedBy: .newlines)
            if let end = lines.dropFirst().firstIndex(where: { $0 == "---" || $0 == "..." }) {
                let raw = lines[0...end].joined(separator: "\n")
                appendBlock(raw, attrs: MarkdownStyle.attributes(block: "raw"), to: output)
                markdown = lines.dropFirst(end + 1).joined(separator: "\n")
            }
        }
        let document = Document(parsing: markdown)
        for child in document.children { renderBlock(child, to: output, baseURL: baseURL) }
        return output
    }

    private static func appendBlock(_ string: String, attrs: [NSAttributedString.Key: Any], to output: NSMutableAttributedString) {
        var attrs = attrs
        attrs[.blockID] = UUID().uuidString
        output.append(NSAttributedString(string: string + "\n", attributes: attrs))
    }

    private static func renderBlock(_ node: any Markup, to output: NSMutableAttributedString, baseURL: URL?, depth: Int = 0, quote: Int = 0) {
        if let heading = node as? Heading {
            appendInlineBlock(heading, block: "h\(heading.level)", to: output, baseURL: baseURL, depth: depth, quote: quote)
        } else if node is Paragraph {
            appendInlineBlock(node, block: "p", to: output, baseURL: baseURL, depth: depth, quote: quote)
        } else if let code = node as? CodeBlock {
            var attrs = MarkdownStyle.attributes(block: "code", depth: depth, quoteDepth: quote)
            attrs[.language] = code.language ?? ""
            var text = code.code
            if text.hasSuffix("\n") { text.removeLast() }
            let start = output.length
            appendBlock(text, attrs: attrs, to: output)
            if output.length > start {
                let last = (output.string as NSString).paragraphRange(for: NSRange(location: output.length - 1, length: 0))
                let style = (attrs[.paragraphStyle] as! NSParagraphStyle).mutableCopy() as! NSMutableParagraphStyle
                style.paragraphSpacing = 14
                output.addAttribute(.paragraphStyle, value: style, range: last)
            }
        } else if let list = node as? ListItemContainer {
            let ordered = node as? OrderedList
            // Complex loose items retain their Markdown rather than losing structure.
            if list.listItems.contains(where: { $0.children.filter { !($0 is ListItemContainer) }.count != 1 }) {
                appendBlock(node.format().trimmingCharacters(in: .newlines), attrs: MarkdownStyle.attributes(block: "raw", depth: depth, quoteDepth: quote), to: output)
                return
            }
            for (index, item) in list.listItems.enumerated() {
                let number = Int(ordered?.startIndex ?? 1) + index
                for child in item.children {
                    if child is Paragraph {
                        var attrs = MarkdownStyle.attributes(block: ordered == nil ? "ul" : "ol", depth: depth, quoteDepth: quote)
                        attrs[.listNumber] = number
                        var marker = ordered == nil ? "•\t" : "\(number).\t"
                        if let checkbox = item.checkbox {
                            let checked = checkbox == .checked
                            attrs[.task] = checked
                            marker = checked ? "☑\t" : "☐\t"
                        }
                        appendInlineBlock(child, attributes: attrs, prefix: marker, to: output, baseURL: baseURL)
                    } else {
                        renderBlock(child, to: output, baseURL: baseURL, depth: depth + 1, quote: quote)
                    }
                }
            }
        } else if let table = node as? Markdown.Table {
            renderTable(table, to: output, baseURL: baseURL, quote: quote)
        } else if node is BlockQuote {
            for child in node.children { renderBlock(child, to: output, baseURL: baseURL, depth: depth, quote: quote + 1) }
        } else if node is ThematicBreak {
            appendBlock("────────────────────", attrs: MarkdownStyle.attributes(block: "rule", depth: depth, quoteDepth: quote), to: output)
        } else {
            appendBlock(node.format().trimmingCharacters(in: .newlines), attrs: MarkdownStyle.attributes(block: "raw", depth: depth, quoteDepth: quote), to: output)
        }
    }

    private static func renderTable(_ table: Markdown.Table, to output: NSMutableAttributedString, baseURL: URL?, quote: Int) {
        let native = NSTextTable()
        native.numberOfColumns = max(1, table.maxColumnCount)
        native.collapsesBorders = true
        native.hidesEmptyCells = false
        native.setValue(100, type: .percentageValueType, for: .width)
        let id = UUID().uuidString
        let rows: [[any Markup]] = [Array(table.head.children)] + table.body.children.map { Array($0.children) }
        for (rowIndex, cells) in rows.enumerated() {
            for (column, cell) in cells.enumerated() {
                let block = NSTextTableBlock(table: native, startingRow: rowIndex, rowSpan: 1, startingColumn: column, columnSpan: 1)
                block.setWidth(8, type: .absoluteValueType, for: .padding)
                block.setWidth(0.5, type: .absoluteValueType, for: .border)
                block.setBorderColor(.separatorColor)
                if rowIndex == 0 { block.backgroundColor = .quaternaryLabelColor }
                var attrs = MarkdownStyle.attributes(block: "table", quoteDepth: quote)
                attrs[.tableID] = id
                attrs[.tableRow] = rowIndex
                attrs[.tableColumn] = column
                let alignment = column < table.columnAlignments.count ? table.columnAlignments[column] : nil
                attrs[.tableAlignment] = alignment.map { String(describing: $0) } ?? "none"
                let style = (attrs[.paragraphStyle] as! NSParagraphStyle).mutableCopy() as! NSMutableParagraphStyle
                style.textBlocks = [block]
                style.paragraphSpacing = 0
                style.alignment = alignment == .center ? .center : alignment == .right ? .right : .left
                attrs[.paragraphStyle] = style
                // Header emphasis is visual; do not inject ** into the original cell content.
                if rowIndex == 0 { attrs[.font] = NSFont.systemFont(ofSize: 16, weight: .semibold) }
                appendInlineBlock(cell, attributes: attrs, to: output, baseURL: baseURL)
            }
        }
    }

    private static func appendInlineBlock(_ node: any Markup, block: String, to output: NSMutableAttributedString, baseURL: URL?, depth: Int, quote: Int) {
        appendInlineBlock(node, attributes: MarkdownStyle.attributes(block: block, depth: depth, quoteDepth: quote), to: output, baseURL: baseURL)
    }

    private static func appendInlineBlock(_ node: any Markup, attributes: [NSAttributedString.Key: Any], prefix: String = "", to output: NSMutableAttributedString, baseURL: URL?) {
        var attrs = attributes
        attrs[.blockID] = UUID().uuidString
        output.append(NSAttributedString(string: prefix, attributes: attrs))
        for child in node.children { renderInline(child, attributes: attrs, to: output, baseURL: baseURL) }
        output.append(NSAttributedString(string: "\n", attributes: attrs))
    }

    private static func renderInline(_ node: any Markup, attributes: [NSAttributedString.Key: Any], to output: NSMutableAttributedString, baseURL: URL?) {
        var attrs = attributes
        if let text = node as? Text { output.append(NSAttributedString(string: text.string, attributes: attrs)); return }
        if node is SoftBreak { output.append(NSAttributedString(string: " ", attributes: attrs)); return }
        if node is LineBreak { output.append(NSAttributedString(string: "\u{2028}", attributes: attrs)); return }
        if let code = node as? InlineCode {
            attrs[.inlineCode] = true
            let run = NSMutableAttributedString(string: code.code, attributes: attrs)
            MarkdownStyle.restyle(run, range: NSRange(location: 0, length: run.length))
            output.append(run); return
        }
        if let html = node as? InlineHTML {
            attrs[.literal] = true
            output.append(NSAttributedString(string: html.rawHTML, attributes: attrs)); return
        }
        if let image = node as? Markdown.Image {
            let attachment = NSTextAttachment()
            var bitmap: NSImage?
            if let src = image.source, let url = URL(string: src, relativeTo: baseURL?.deletingLastPathComponent()), url.isFileURL {
                bitmap = NSImage(contentsOf: url)
            }
            attachment.image = bitmap ?? NSImage(systemSymbolName: "photo", accessibilityDescription: image.plainText)
            if let size = attachment.image?.size, size.width > 0 {
                let scale = min(1, 600 / size.width, 420 / max(1, size.height))
                attachment.bounds = NSRect(x: 0, y: 0, width: size.width * scale, height: size.height * scale)
            }
            let run = NSMutableAttributedString(attributedString: NSAttributedString(attachment: attachment))
            attrs[.imageMarkdown] = image.format().trimmingCharacters(in: .newlines)
            attrs[.toolTip] = image.source ?? image.plainText
            run.addAttributes(attrs, range: NSRange(location: 0, length: run.length))
            output.append(run); return
        }
        if node is Strong { attrs[.strong] = true }
        if node is Emphasis { attrs[.emphasis] = true }
        if node is Strikethrough { attrs[.strike] = true }
        if let link = node as? Markdown.Link, let destination = link.destination {
            attrs[.link] = destination
            if let title = link.title { attrs[.linkTitle] = title }
        }
        let start = output.length
        for child in node.children { renderInline(child, attributes: attrs, to: output, baseURL: baseURL) }
        MarkdownStyle.restyle(output, range: NSRange(location: start, length: output.length - start))
    }

    public static func serialize(_ text: NSAttributedString) -> String {
        guard text.length > 0 else { return "" }
        let string = text.string as NSString
        var result = ""
        var location = 0
        var previousKind = ""
        var previousID = ""
        var previousQuote = 0
        while location < string.length {
            let paragraph = string.paragraphRange(for: NSRange(location: location, length: 0))
            var content = paragraph
            while content.length > 0 && [10, 13].contains(string.character(at: NSMaxRange(content) - 1)) { content.length -= 1 }
            let attrs = text.attributes(at: paragraph.location, effectiveRange: nil)
            let kind = attrs[.block] as? String ?? "p"
            let id = attrs[.blockID] as? String ?? ""
            let quote = attrs[.quoteDepth] as? Int ?? 0
            let sameGroup = !id.isEmpty && id == previousID && ["code", "raw"].contains(kind)
            if sameGroup {
                // The entire code/raw group is collected below on its first line.
                location = NSMaxRange(paragraph); continue
            }
            var body: String
            var lastParagraph = paragraph
            if kind == "table", let tableID = attrs[.tableID] as? String {
                var cells: [Int: [Int: String]] = [:]
                var alignments: [Int: String] = [:]
                var end = paragraph.location
                while end < string.length, text.attribute(.tableID, at: end, effectiveRange: nil) as? String == tableID {
                    lastParagraph = string.paragraphRange(for: NSRange(location: end, length: 0))
                    var cellRange = lastParagraph
                    while cellRange.length > 0 && [10, 13].contains(string.character(at: NSMaxRange(cellRange) - 1)) { cellRange.length -= 1 }
                    let meta = text.attributes(at: end, effectiveRange: nil)
                    let row = meta[.tableRow] as? Int ?? 0
                    let column = meta[.tableColumn] as? Int ?? 0
                    let cell = serializeInline(text.attributedSubstring(from: cellRange)).replacingOccurrences(of: "  \n", with: "<br>")
                    if let existing = cells[row]?[column] { cells[row]?[column] = existing + "<br>" + cell }
                    else { cells[row, default: [:]][column] = cell }
                    alignments[column] = meta[.tableAlignment] as? String ?? "none"
                    end = NSMaxRange(lastParagraph)
                }
                let columns = (cells.values.flatMap { $0.keys }.max() ?? 0) + 1
                func row(_ values: [Int: String]) -> String { "| " + (0..<columns).map { values[$0] ?? "" }.joined(separator: " | ") + " |" }
                let divider = (0..<columns).map { column in
                    switch alignments[column] { case "left": return ":---"; case "right": return "---:"; case "center": return ":---:"; default: return "---" }
                }
                body = row(cells[0] ?? [:]) + "\n| " + divider.joined(separator: " | ") + " |"
                for index in cells.keys.sorted() where index > 0 { body += "\n" + row(cells[index] ?? [:]) }
            } else if kind == "code" || kind == "raw" {
                var end = NSMaxRange(paragraph)
                while end < string.length, !id.isEmpty, text.attribute(.blockID, at: end, effectiveRange: nil) as? String == id,
                      text.attribute(.block, at: end, effectiveRange: nil) as? String == kind {
                    lastParagraph = string.paragraphRange(for: NSRange(location: end, length: 0))
                    end = NSMaxRange(lastParagraph)
                }
                var raw = string.substring(with: NSRange(location: paragraph.location, length: end - paragraph.location))
                if raw.hasSuffix("\n") { raw.removeLast() }
                if kind == "code" {
                    let fence = String(repeating: "`", count: max(3, longestBackticks(raw) + 1))
                    let language = (attrs[.language] as? String ?? "").replacingOccurrences(of: "`", with: "")
                    body = fence + language + "\n" + raw + "\n" + fence
                } else { body = raw }
            } else if kind == "rule", string.substring(with: content) == "────────────────────" {
                body = "---"
            } else {
                if kind == "ul" || kind == "ol", let tab = string.substring(with: content).firstIndex(of: "\t") {
                    let visible = string.substring(with: content)
                    let prefixLength = (String(visible[...tab]) as NSString).length
                    content.location += prefixLength; content.length -= prefixLength
                }
                body = serializeInline(text.attributedSubstring(from: content))
                if kind.hasPrefix("h"), let level = Int(kind.dropFirst()), (1...6).contains(level) {
                    body = String(repeating: "#", count: level) + " " + body
                } else if kind == "ul" || kind == "ol" {
                    let marker = kind == "ul" ? "- " : "\(attrs[.listNumber] as? Int ?? 1). "
                    let task = (attrs[.task] as? Bool).map { $0 ? "[x] " : "[ ] " } ?? ""
                    body = String(repeating: "    ", count: attrs[.depth] as? Int ?? 0) + marker + task + body
                }
            }
            if quote > 0 { body = body.components(separatedBy: "\n").map { String(repeating: "> ", count: quote) + $0 }.joined(separator: "\n") }
            if !result.isEmpty {
                let listAdjacent = ["ul", "ol"].contains(kind) && ["ul", "ol"].contains(previousKind) && quote == previousQuote
                let separator = listAdjacent ? "\n" : (quote > 0 && previousQuote == quote ? "\n" + String(repeating: "> ", count: quote).trimmingCharacters(in: .whitespaces) + "\n" : "\n\n")
                result += separator
            }
            result += body
            previousKind = kind; previousID = id; previousQuote = quote
            location = NSMaxRange(lastParagraph)
        }
        return result + (result.hasSuffix("\n") ? "" : "\n")
    }

    private static func serializeInline(_ text: NSAttributedString, level: Int = 0) -> String {
        let keys: [NSAttributedString.Key] = [.link, .strike, .strong, .emphasis]
        guard level < keys.count else { return serializeLeaves(text) }
        let key = keys[level]
        var result = ""
        text.enumerateAttribute(key, in: NSRange(location: 0, length: text.length)) { value, range, _ in
            let substring = text.attributedSubstring(from: range)
            var body = serializeInline(substring, level: level + 1)
            if key == .link, let value {
                let url = String(describing: value).replacingOccurrences(of: ">", with: "%3E").replacingOccurrences(of: "<", with: "%3C").replacingOccurrences(of: "\n", with: "%0A")
                let title = (substring.attribute(.linkTitle, at: 0, effectiveRange: nil) as? String).map { " " + String(UnicodeScalar(34)) + escapeTitle($0) + String(UnicodeScalar(34)) } ?? ""
                body = "[" + body + "](<" + url + ">" + title + ")"
            } else if value as? Bool == true {
                let delimiter = key == .strong ? "**" : key == .strike ? "~~" : "*"
                let leading = String(body.prefix(while: { $0.isWhitespace }))
                let trailing = String(body.reversed().prefix(while: { $0.isWhitespace }).reversed())
                let core = body.dropFirst(leading.count).dropLast(min(trailing.count, max(0, body.count - leading.count)))
                body = leading + (core.isEmpty ? "" : delimiter + core + delimiter + trailing)
            }
            result += body
        }
        return result
    }

    private static func serializeLeaves(_ text: NSAttributedString) -> String {
        var result = ""
        var pending = ""
        var current: [NSAttributedString.Key: Any] = [:]
        func signature(_ attrs: [NSAttributedString.Key: Any]) -> String {
            [.inlineCode, .literal, .imageMarkdown].map { String(describing: attrs[$0] ?? "") }.joined(separator: "\u{0}")
        }
        func flush() {
            guard !pending.isEmpty else { return }
            if let image = current[.imageMarkdown] as? String {
                result += String(repeating: image, count: pending.filter { $0 == "\u{fffc}" }.count)
            } else if current[.literal] as? Bool == true {
                result += pending
            } else if current[.inlineCode] as? Bool == true {
                let fence = String(repeating: "`", count: longestBackticks(pending) + 1)
                let pad = pending.hasPrefix("`") || pending.hasSuffix("`") || (pending.hasPrefix(" ") && pending.hasSuffix(" ") && !pending.allSatisfy { $0 == " " })
                result += fence + (pad ? " " : "") + pending + (pad ? " " : "") + fence
            } else {
                result += escape(pending)
            }
            pending = ""
        }
        text.enumerateAttributes(in: NSRange(location: 0, length: text.length)) { attrs, range, _ in
            if signature(attrs) != signature(current) { flush(); current = attrs }
            pending += (text.string as NSString).substring(with: range)
        }
        flush()
        return result
    }

    private static func escapeTitle(_ title: String) -> String {
        var result = ""
        for char in title {
            if char == "\\" || char == "\"" { result.append("\\") }
            result.append(char)
        }
        return result
    }

    private static func escape(_ string: String) -> String {
        var output = ""
        for char in string {
            if char == "\u{2028}" { output += "  \n" }
            else if "\\`*_{}[]<>#+-.!|~".contains(char) { output += "\\" + String(char) }
            else { output.append(char) }
        }
        return output
    }

    private static func longestBackticks(_ string: String) -> Int {
        var longest = 0, current = 0
        for char in string {
            current = char == "`" ? current + 1 : 0
            longest = max(longest, current)
        }
        return longest
    }
}
