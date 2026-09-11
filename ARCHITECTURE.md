# Architecture

## Durable capture pipeline

The ordering is intentional and non-negotiable:

```text
Clipboard or confirmed OCR
        ↓
CaptureCoordinator
        ↓
canonical captures.json
        ↓
   ┌────┴────┐
Markdown    Microsoft Word
output      output
```

`ClipboardMonitor` is owned by the app-level `AppModel`, not a transient SwiftUI view. It polls `NSPasteboard.changeCount` on the common run-loop mode and keeps observed, pending, and handled generations separate. A temporarily empty read remains pending for a bounded retry rather than being discarded. Live packaged-app diagnostics expose timer activity, both AppKit text reads, foreground application detection, allowlist and duplicate decisions, coordinator/store entry, persistence, and the final result.

`CaptureCoordinator` applies bounded-input validation, conservative `TextCleaner`, and recent-duplicate suppression. It advances duplicate state only after `CaptureStore` has atomically persisted the capture. The Application Support directory is created lazily by the first successful `CaptureStore.save` at:

```text
~/Library/Application Support/PDF Quote Collector/captures.json
```

The canonical JSON document is authoritative during the running app session. Each accepted `Capture` contains raw and cleaned text, observed metadata, timestamps, and independent Markdown and Word export states. Output failures never roll back or remove the canonical capture while the app is running.

On a normal application termination, `AppDelegate.applicationWillTerminate` stops the clipboard monitor and asks `AppModel`/`CaptureCoordinator` to remove `captures.json`. App initialization also removes any stale session file left when a force quit, crash, power loss, or older build prevented termination cleanup. This makes **Show Captures** session-scoped and prevents quote history from accumulating across launches. User-selected Markdown and Word files are never removed or rewritten by this cleanup. Because pending/failed output state is part of the session history, it must be retried before quitting.

## Independent output state machines

Every new capture begins with:

```text
markdownExportStatus = pending
wordExportStatus = pending
```

Only after canonical persistence does `AppModel` invoke the enabled exporters independently. Each exporter records `pending`, `exported`, or `failed`, plus its own optional error message, back into the canonical store. Markdown failure does not prevent Word automation; Word failure or a closed Word process does not prevent Markdown append.

Retry commands select only non-exported captures for the requested output. `Retry Markdown Output` never calls Word, and `Retry Word Output` never calls Markdown. `Retry Failed Outputs` tries both independently. This prevents a successful destination from receiving another copy merely because the other destination failed.

Selecting a different destination or changing an output toggle never replays historical captures automatically. The new destination starts receiving only captures accepted after selection. Older pending/failed captures move to the current destination only when the user explicitly invokes the corresponding Retry command.

## Markdown output

`MarkdownOutputService` appends UTF-8 data directly to a user-selected `.md` file. It preserves Unicode and formats each cleaned quotation as plain text, a Markdown bullet, or smart-quoted text, with zero to three configurable blank lines. Formatting is isolated in `NotesFormatter`, leaving room for an optional source-heading formatter without changing canonical capture or persistence behavior.

The exporter does not regenerate or replace the whole notes file. It reads the existing UTF-8 content to detect the capture marker, then performs a single end-of-file append and synchronizes the handle. Each appended block includes an invisible HTML comment containing the capture UUID. A retry after an uncertain status write therefore detects the marker and reports success without appending the quotation again.

A missing or invalid UTF-8 destination marks only Markdown as failed. The Word attempt still proceeds.

## Microsoft Word output

`WordOutputService` never reads or modifies OOXML or `.docx` package internals. It addresses Microsoft Word through AppleScript/Apple Events and asks Word itself to:

1. open or focus the selected document (only after the process-level automatic-opening policy allows the attempt);
2. inspect a document variable derived from the capture UUID;
3. append the formatted quotation at the end of Word's document text;
4. add the UUID document variable and save the document.

The document variable is the Word-side idempotency key. If a retry finds it, Word saves the document and returns `already-exported` without inserting the text again.

When Word is not installed, or Word is closed while **Automatically open Word when needed** is off, Word remains `pending`. An Apple Events denial or automation error becomes `failed`. In every case the canonical capture and any successful Markdown append remain intact.

## Settings and lifecycle

`SettingsStore` persists one schema-versioned `AppSettings` value. Version 2 stores separate security-scoped bookmarks and toggles for Markdown and Word, plus the automatic-Word-launch preference. Defaults are:

- Save to Markdown: on
- Save to Microsoft Word: on
- Automatically open Word when needed: off

The SwiftUI app declares a real `Settings` scene. macOS 14 and later use SwiftUI's `openSettings` environment action; macOS 13 uses a retained AppKit-hosted Settings window fallback that activates the accessory application and focuses the existing window. The packaged app remains `LSUIElement`/accessory-only and never gains a permanent Dock icon.

The app-level delegate also owns normal-termination cleanup. Closing the menu, Settings, capture history, or diagnostics window does not clear history and does not stop monitoring; choosing **Quit** clears the session history immediately before process termination.

## Permissions and privacy

Clipboard monitoring, foreground bundle lookup, local JSON storage, and Markdown append require no special privacy permission. Word output uses Apple Events and macOS may request Automation permission for Microsoft Word. Screen Recording is requested only for an explicit OCR region capture. Accessibility is not requested, and the app performs no network activity.

Screen Recording authorization is checked with `CGPreflightScreenCaptureAccess` on every explicit OCR action and, when absent, re-requested through `CGRequestScreenCaptureAccess`. The app does not cache a one-time request decision in `UserDefaults`, because a permission change or locally rebuilt executable can otherwise leave a visibly enabled but stale TCC entry. Ad-hoc development builds have CDHash-based identities; after replacing such a build, the old Screen Recording entry may need to be removed and the installed `/Applications/PDF Quote Collector.app` added again.

## Region capture and OCR

`GlobalShortcutRegistrar` uses the native Carbon hotkey API. `RegionCaptureService` creates temporary borderless overlays, confines a drag to its starting display, closes overlays before capture, and retains the image only in memory. `OCRService` uses local Apple Vision recognition. Only text confirmed by the user enters the same canonical coordinator and dual-output pipeline.

## Source metadata

The foreground application's bundle identifier and display name come from `NSWorkspace`. Window titles and filenames are stored only when a conservative lookup associates them with the foreground process; page numbers are never guessed. Missing metadata never blocks capture.
