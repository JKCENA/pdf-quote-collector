# PDF Quote Collector

PDF Quote Collector is a native, local-only macOS menu-bar app for collecting quotations from selectable and scanned academic PDFs without leaving the reader.

## Highlights

- Captures copied text from Preview, Adobe Acrobat/Reader, PDF Expert, Safari, and Chrome through an explicit allowlist
- Appends every accepted quotation independently to UTF-8 Markdown and a Microsoft Word document
- Captures scanned text with an on-demand screen-region selector and local Apple Vision OCR
- Keeps clipboard monitoring alive as a menu-bar-only `LSUIElement` app with no Dock icon
- Suppresses immediate duplicate copies and uses per-output idempotency markers for safe retries
- Provides native Settings, capture history, and live clipboard-pipeline diagnostics
- Performs no network requests, telemetry, cloud OCR, or background screen recording

## Requirements

- macOS 13 Ventura or later
- Xcode with a matching macOS SDK, or matching Apple Command Line Tools
- Screen Recording permission only for OCR region capture
- Microsoft Word is required only for the optional Word output; canonical storage and Markdown continue without it

The app uses SwiftUI, AppKit, `NSPasteboard`, CoreGraphics, Carbon hotkeys, and Apple Vision. It has no third-party package or network dependency.

## Build, test, and package

With a correctly paired Xcode/Command Line Tools installation:

```sh
swift build
swift run PDFQuoteCollectorTests
scripts/package_app.sh
open "dist/PDF Quote Collector.app"
```

The test target is a standalone deterministic runner because the build host's Command Line Tools installation does not include XCTest. A failure exits nonzero.

This repository's host has Swift 6.3.3 paired with a default SDK built by Swift 6.3.2. The installed macOS 15.4 SDK works when selected explicitly:

```sh
mkdir -p .build/ModuleCache
CLANG_MODULE_CACHE_PATH="$PWD/.build/ModuleCache" \
SWIFTPM_MODULECACHE_OVERRIDE="$PWD/.build/ModuleCache" \
SDKROOT=/Library/Developer/CommandLineTools/SDKs/MacOSX15.4.sdk \
swift build --disable-sandbox --sdk /Library/Developer/CommandLineTools/SDKs/MacOSX15.4.sdk

SWIFT_SDK_PATH=/Library/Developer/CommandLineTools/SDKs/MacOSX15.4.sdk \
scripts/package_app.sh
```

The package script creates an ad-hoc signed local app at `dist/PDF Quote Collector.app`. Production distribution should use a Developer ID signature and notarization.

To install the local build, quit any running copy first and copy the packaged app to Applications:

```sh
ditto "dist/PDF Quote Collector.app" "/Applications/PDF Quote Collector.app"
open "/Applications/PDF Quote Collector.app"
```

Run only the `/Applications` copy. Running both it and the `dist` copy can cause the global OCR shortcut to conflict.

## First run

1. Launch the app. It appears as a quote-bubble in the menu bar and has no Dock icon.
2. Open Settings and choose a Markdown destination such as `Reading Notes.md`.
3. Create a Word document such as `Reading Notes.docx` in Microsoft Word, save it, then select it as the Word destination.
4. Leave **Capture: ON**. The recommended defaults enable both outputs and leave automatic Word opening off.
5. Enable only PDF readers/browsers you want to capture from.

History is durable for the current app session, even before a notes target is selected. The canonical store is at `~/Library/Application Support/PDF Quote Collector/captures.json`; it is versioned JSON written atomically. During a normal app quit, `captures.json` is removed. App startup also removes any stale file left by an older build, force quit, crash, or power loss, so **Show Captures** always starts empty. Markdown and Word documents are not cleared. Pending or failed output entries must therefore be retried before quitting if they are still needed.

## Selectable PDF workflow

Open a PDF in Preview, Adobe Acrobat/Reader, PDF Expert, Safari, or Chrome. Select text and press Command-C. The app observes the new text pasteboard event without modifying or delaying normal copying, verifies the foreground app's bundle identifier, performs conservative artifact cleanup, suppresses immediate duplicates, saves the structured capture, then independently attempts Markdown and Word output.

Cleanup joins column-width line wraps, repairs letter-hyphen-newline-letter splits, and normalizes odd whitespace. It preserves punctuation, Unicode, smart quotes, and blank-line paragraph breaks. It does not rewrite prose or guess away headers, footers, citations, footnotes, or page numbers.

## Scanned PDF workflow

Press the configured global shortcut (default **Command-Shift-X**), drag a rectangle on one display, and release. The overlay disappears before the selected pixels are captured. Apple Vision performs accurate local OCR using English and Korean when the installed Vision revision reports support. Edit the recognized text in the confirmation panel, then press **Command-Return** or click **Add**. Escape or **Cancel** stores nothing.

The screenshot stays in memory and is never written by the app. Screen Recording is requested only after an explicit OCR action. If denied, Settings shows the status and links to the correct privacy pane. Permission changes require relaunching the app. Because local packages are ad-hoc signed, replacing the executable changes its macOS privacy identity; remove and re-add `/Applications/PDF Quote Collector.app` in Screen Recording settings after rebuilding if an enabled entry is reported as not granted.

## Markdown and Word output

Every accepted quotation is written to the canonical local store before any output is attempted. The capture then carries independent `markdownExportStatus` and `wordExportStatus` values, each of which can be `pending`, `exported`, or `failed`.

Markdown is appended directly as UTF-8 to the selected `.md` file. Unicode is preserved, zero-to-three blank lines are configurable, and plain, bullet, and quotation-mark styles are available. A capture-ID comment makes retry idempotent without regenerating the whole file.

Word output uses AppleScript/Apple Events to ask Microsoft Word to append at the end of the selected `.docx`. The app never modifies `.docx` internals. A capture-ID document variable prevents a retry from adding a second copy. With automatic opening off, a closed Word process leaves Word output pending while Markdown and canonical storage still succeed.

Use **Retry Failed Outputs** to retry both non-exported states, or use **Retry Markdown Output** and **Retry Word Output** separately. A successful output is not rerun just because the other output failed.

Choosing a new destination starts a fresh output file: existing captures are not copied into it automatically. Only captures accepted after the selection are appended. Use an explicit Retry command if you intentionally want older pending or failed captures written to the newly selected destination.

## Permissions

- **Screen Recording:** required only to capture an explicitly dragged OCR region. Authorization is checked on every explicit OCR action, and a System Settings link is available in Settings.
- **Accessibility:** not requested or required.
- **Automation / Apple Events:** required only for Microsoft Word output. macOS prompts when the app first controls Word; denial leaves the Word status failed and does not affect local or Markdown storage.
- **Network:** not used.

Clipboard monitoring, foreground bundle lookup, local storage, and Markdown output need no privacy prompt. Source window names may be unavailable under some macOS privacy conditions; capture continues with only the foreground application.

## Privacy

PDF Quote Collector is designed for unpublished and sensitive academic material:

- No telemetry, analytics, tracking, crash upload, remote logging, cloud OCR, LLM, external API, or automatic network transmission exists.
- Clipboard polling uses only `NSPasteboard.general`; the app never alters clipboard contents.
- There is no continuous screen recording. Region capture occurs only after the shortcut and completed drag.
- OCR runs locally with Apple Vision; region images remain in memory.
- Raw and cleaned quotations exist only in the local canonical store and user-selected output.
- Repository ignore rules exclude captures, PDFs, notes, screenshots, and build products.

## Known limitations

- Word must be installed for Word output. With automatic opening disabled, Word must already be running; otherwise captures remain pending for a later Word-only retry.
- The selected Word document must already exist. Create and save it in Word before choosing it in Settings.
- Region selection is intentionally confined to the display where the drag begins; cross-display rectangles are not supported.
- Source filenames are stored only when the observed title is unambiguously a `.pdf`; page numbers are never inferred.
- Browser allowlisting permits browser clipboard text generally because macOS does not expose a reliable, permission-free “this tab is a PDF” signal. Disable browser entries when not reading PDFs.
- Korean OCR depends on the installed macOS/Vision language support.
- The global shortcut accepts one A–Z key plus modifier choices. Registration fails visibly if another app owns it.
- Clipboard text above 250,000 characters is rejected to keep the menu-bar process responsive.

See `MANUAL_TESTS.md` for the full end-to-end acceptance matrix and honest execution status. See `ARCHITECTURE.md` for the output tradeoff analysis and component design.
