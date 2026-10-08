import XCTest
import AppKit
import Markdown
@testable import MarginalCore

final class MarkdownCodecTests: XCTestCase {
    func roundTrip(_ source: String, file: StaticString = #filePath, line: UInt = #line) {
        let result = MarkdownCodec.serialize(MarkdownCodec.render(source))
        XCTAssertEqual(Document(parsing: result).debugDescription(), Document(parsing: source).debugDescription(), "Saved Markdown:\n\(result)", file: file, line: line)
    }

    func testHeadingsAndInlineFormatting() {
        roundTrip("# A heading\n\nHello **bold**, *italic*, ~~gone~~ and `let x = 1`.\n\n## Another\n\n[Link](https://example.com) and ![Photo](photo.png).\n")
    }
    func testNestedListsAndTasks() {
        roundTrip("- First\n    - Nested\n- Last\n\n3. Three\n4. Four\n\n- [ ] Later\n- [x] Done\n")
    }
    func testCodeFencesAndEmptyLines() {
        roundTrip("```swift\nlet x = 1\n\nprint(x)\n```\n\nAfter.\n")
        roundTrip("````text\n```\ncode\n```\n````\n")
    }
    func testQuotesAndHardBreaks() {
        roundTrip("> First paragraph.\n>\n> Second **paragraph**.\n\nLine one  \nLine two.\n")
        roundTrip("> ## Heading\n>\n> - One\n> - Two\n")
    }
    func testLiteralPunctuationStaysLiteral() {
        let input = "# Not a heading\n- Not a list\n*a literal star*"
        let rich = NSAttributedString(string: input, attributes: MarkdownStyle.attributes())
        let result = MarkdownCodec.serialize(rich)
        let parsed = Document(parsing: result)
        XCTAssertTrue(parsed.children.allSatisfy { $0 is Paragraph })
        XCTAssertTrue(result.contains("\\*a literal star\\*"))
    }
    func testTablesAndHTMLSurviveEditing() {
        roundTrip("| A | B |\n| --- | --- |\n| One | Two |\n\n<div>Hello</div>\n")
        roundTrip("Before <span>inline</span> after.\n")
    }
    func testCodeWhitespaceAndBackticks() {
        roundTrip("A `` `tick` `` and ` spaces ` and ``a`b``.\n")
    }
    func testFrontMatterPreserved() {
        let source = "---\ntitle: My document\ntags: [one, two]\n---\n\n# Hello\n"
        let result = MarkdownCodec.serialize(MarkdownCodec.render(source))
        XCTAssertTrue(result.hasPrefix("---\ntitle: My document\ntags: [one, two]\n---\n\n# Hello"))
    }
    func testBoldWhitespaceAndEditedLiteralCharacters() {
        let text = NSMutableAttributedString(string: "  some *text*  ", attributes: MarkdownStyle.attributes())
        text.addAttribute(.strong, value: true, range: NSRange(location: 0, length: text.length))
        let result = MarkdownCodec.serialize(text)
        XCTAssertTrue(result.contains("**some \\*text\\***"))
        XCTAssertTrue(Document(parsing: result).debugDescription().contains("Strong"))
    }
    func testTableAlignmentAndEscapedPipes() {
        roundTrip("| Left | Center | Right |\n| :--- | :---: | ---: |\n| **Bold** | A \\| B | `value` |\n")
    }
    func testLinkTitles() {
        roundTrip("[Hello](https://example.com \"A title\").\n")
    }

    func testNestedInlineStyles() {
        roundTrip("**Bold with *italic* inside and more bold**.\n")
        roundTrip("~~Gone with **bold** inside~~.\n")
        roundTrip("[A **bold** link](https://example.com).\n")
    }
    func testInlineFormattingInsideWords() {
        let text = NSMutableAttributedString(string: "abc", attributes: MarkdownStyle.attributes())
        text.addAttribute(.emphasis, value: true, range: NSRange(location: 1, length: 1))
        let saved = MarkdownCodec.serialize(text)
        XCTAssertTrue(Document(parsing: saved).debugDescription().contains("Emphasis"), saved)
    }

    func testUnicode() {
        roundTrip("# Café 🌱\n\nこんにちは **世界**.\n")
    }
    func testEmptyDocument() {
        XCTAssertEqual(MarkdownCodec.serialize(MarkdownCodec.render("")), "")
    }
}
