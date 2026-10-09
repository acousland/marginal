# Marginal

A tiny, native Markdown viewer and WYSIWYG editor for macOS. Open a file, edit the rendered document, and save it as ordinary Markdown.

**[Download Marginal](https://github.com/acousland/marginal/releases/latest)** · macOS 13 or later · Apple silicon

![Marginal’s native rendered editor](docs/editor.png)

## Install

Download the ZIP from Releases, unzip it, and drag **Marginal.app** to Applications.

The latest release is signed with Aaron Cousland's Apple Developer ID, notarized by Apple, and includes a stapled notarization ticket. It uses the hardened runtime and passes macOS Gatekeeper assessment.

## Use

Open a `.md`, `.markdown`, `.mdown`, `.mkd`, or `.txt` file with **File → Open** (⌘O), or drop it onto the app in Finder. Click anywhere in the rendered text and type. Use the small toolbar or Format menu to change formatting. **⌘S** saves; standard macOS autosave also saves existing documents in place.

| Action | Shortcut |
| --- | --- |
| New / Open / Save | ⌘N / ⌘O / ⌘S |
| Save As | ⇧⌘S |
| Bold / Italic / Link | ⌘B / ⌘I / ⌘K |
| Inline code | ⇧⌘C |
| Body / Heading 1–3 | ⌥⌘0 / ⌥⌘1–3 |
| Bullet list / Numbered list / Quote | ⌥⌘7 / ⌥⌘8 / ⌥⌘9 |
| Find | ⌘F |
| Markdown source / Rendered editor | ⇧⌘M |

## Typing shortcuts

At the start of a body paragraph, type a marker followed by **Space**. The marker disappears and the paragraph changes style:

| Type, then Space | Style |
| --- | --- |
| `#` through `######` | Heading 1–6 |
| `-`, `*`, or `+` | Bullet list |
| `1.` or `1)` | Numbered list (other starting numbers work too) |
| `>` | Quote |

Type three backticks (optionally followed by a language such as `swift`) and press **Return** to start a code block. Type three backticks on their own line and press Return to leave it. Return after a heading starts body text; Return continues a list, and Return on an empty list item exits it. Undo restores the typed marker. Shortcuts apply while typing in the rendered editor; source and code content remain literal.

## Tables

Use the **table button in the toolbar** or **Table → Insert Table…** to create a table with a header and the number of body rows and columns you choose. Click a cell, then use the same menu to add or delete rows and columns, align a column, or delete the table. These changes preserve cell formatting and support undo/redo. The required header row and final column cannot be deleted individually.

**Tab** and **Shift-Tab** move between cells; Tab from the last cell adds a row. **Return** inserts a line break inside a cell. **Table → Paragraph After Table** moves you out of the table to keep writing. Use the Table controls to change structure; Backspace and Delete protect cell boundaries.

![Native table editing](docs/tables.png)

## Updates

Choose **Marginal → Check for Updates…** to check the latest stable GitHub release immediately. Automatic checks are enabled by default and run at most once every 24 hours, after launch or while the app stays open. Toggle **Automatically Check for Updates** in the same menu to turn them off.

A newer release produces a download prompt once per version, when Marginal is active. **Download Update** opens its GitHub release page; download the ZIP and replace the app in Applications. Background connection failures stay quiet. Manual checks report errors and when you're up to date. Drafts and prereleases are ignored.

Update checks send an HTTPS request to GitHub with the app version in its User-Agent. Document contents and file paths remain local. Existing 1.0.x installations need this version installed once to gain update checking.

## What it handles

- Headings, bold, italic, strikethrough, links, inline code, and fenced code blocks.
- Bullet and numbered lists, nested lists, task-list display, quotes, and horizontal rules.
- Native tables with editable cell text and preserved column alignment.
- Local images, resolved relative to the Markdown file.
- Native undo/redo, find, document windows, recent files, and light/dark appearance.

Untouched files save byte for byte. Editing produces equivalent Markdown with normalized spacing, escaping, and inline links. Files must be UTF-8.

Keep advanced syntax edits in the source view: task checkboxes, complex list items with multiple paragraphs, and metadata/HTML. YAML front matter, HTML, and unsupported blocks are displayed as preserved source. Remote images use a placeholder; the document's image URL is retained. Moving a document with relative image paths keeps those paths unchanged.

## Build

Install Xcode and its command-line tools, then:

```sh
swift test
scripts/build.sh
open dist/Marginal.app
```

The build script creates an Apple silicon (`arm64`) app with an ad-hoc development signature. Open `Package.swift` in Xcode to work on the app.

The bundle has a self-test for file-type registration and opening, editing, saving, and reopening a Markdown file. You can also check the live update endpoint without displaying UI:

```sh
dist/Marginal.app/Contents/MacOS/Marginal --smoke-test
dist/Marginal.app/Contents/MacOS/Marginal --check-updates
```

## Signed releases

```sh
SIGNING_IDENTITY='Developer ID Application: Your Name (TEAMID)' \
NOTARY_PROFILE='your-keychain-profile' \
VERSION=1.2.0 scripts/release.sh
```

First save notarization credentials interactively to your Keychain using Apple's `xcrun notarytool store-credentials marginal-notary`. Then set `NOTARY_PROFILE=marginal-notary` when running the release script. It submits the app, staples the ticket, verifies Gatekeeper acceptance, and creates the final ZIP and SHA-256 checksum. Keep credentials out of this repository.

For future updates, increment `VERSION`, publish the corresponding `v<version>` tag, and upload `Marginal-<version>-macOS.zip` and its checksum to a stable GitHub release marked latest. The checker uses GitHub's latest-release endpoint and only offers releases with an uploaded app archive. No separate update feed is needed. The build script keeps both bundle version fields in sync with `VERSION`.

## Implementation

Swift and AppKit, with native `NSTextView` editing and [Swift Markdown](https://github.com/swiftlang/swift-markdown) for CommonMark/GFM parsing. Markdown is parsed when opening a document or switching from source to rendered mode. Typing uses the native text system; Markdown serialization happens on save or when switching to source. Editing stays local and remote images are not fetched. Update checking uses a small asynchronous native URLSession request to GitHub.

[MIT license](LICENSE). Dependency licenses are included in the app bundle.
