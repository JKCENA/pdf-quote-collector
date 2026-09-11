# Manual end-to-end tests

These cases exercise the packaged `dist/PDF Quote Collector.app`. Automated service tests and `swift run` are not substitutes for the menu-bar, Adobe Acrobat, filesystem, Automation-permission, and Microsoft Word checks below.

## Test setup

1. Build and package the app using the README instructions.
2. Create empty temporary files named `Reading Notes.md` and `Reading Notes.docx`; create and save the `.docx` from Microsoft Word.
3. Launch the packaged app and confirm the quote-bubble menu appears without a Dock icon.
4. In Settings, select both destinations. Set **Save to Markdown** on, **Save to Microsoft Word** on, and **Automatically open Word when needed** off.
5. Leave Capture on and Adobe Acrobat enabled.
6. Record the original contents and sizes of both output files and `captures.json` before each destructive/failure test.

## Required dual-output acceptance matrix

| # | Case | Procedure and expected result | Status |
|---|---|---|---|
| 1 | Acrobat, both outputs | Keep Word open. In Acrobat select new text and press Command-C once. `captures.json` is created/updated first and contains the cleaned text. `Reading Notes.md` contains it once in UTF-8. Word appends it once to `Reading Notes.docx` and saves. Capture history reports Markdown `exported` and Word `exported`. | Verified 2026-09-10 with the final packaged app: a 133-character Acrobat generation was accepted; canonical JSON, Markdown, and Word all contained capture `41973F4F-555B-4336-8E7A-BF5BE684BBD2`; both states were `exported`; the Markdown marker count was exactly one and Word's UUID document variable was `exported`. |
| 2 | Word closed | Quit Word, leave automatic opening off, then capture new Acrobat text. Canonical JSON and Markdown succeed. Word remains `pending`, Word does not launch, and the capture remains safe. | Verified 2026-09-10: 40 canonical captures were Markdown `exported`, Word `pending` with the exact closed/automatic-off reason, and Word was not launched. |
| 3 | Retry Word only | Launch Word after case 2 and choose **Retry Word Output**. Only the pending Word quotation is appended. Markdown bytes and its capture-ID marker count do not change. A second Word retry creates no duplicate. | Verified 2026-09-10 with the final packaged app: all pending Word states became `exported`; Markdown was unchanged; a second Word-only retry left both output SHA-256 values unchanged. |
| 4 | Markdown target missing | Move `Reading Notes.md` after it was selected, keep Word open, then capture. Canonical JSON succeeds, Markdown is `failed`, and Word still appends exactly once. | Not run |
| 5 | Retry Markdown only | Restore/reselect the Markdown file and choose **Retry Markdown Output**. Markdown receives only its non-exported quotation; Word content and marker variables do not change. A second retry creates no duplicate. | Not run |
| 6 | Word permission denied | Reset or deny Automation permission for Microsoft Word, keep Word running, then capture. Canonical JSON and Markdown succeed; Word is `failed` with a specific Apple Events error. | Not run |
| 7 | Recover Word permission | Permit Word control in System Settings and choose **Retry Word Output**. Only Word is retried and the quotation appears once. | Not run |
| 8 | Retry Failed Outputs | Create one Markdown failure and one Word pending/failure on separate captures. Restore both conditions and choose **Retry Failed Outputs**. Each non-exported side is retried; already-exported sides are unchanged. | Not run |
| 9 | Repeated clipboard generation | Copy the same Acrobat selection repeatedly within the duplicate window. Exactly one canonical capture, one Markdown block, and one Word insertion exist. | Verified 2026-09-10: immediate repeated Command-C was rejected as a recent duplicate at changeCount 200; canonical count and both output hashes were unchanged. |
| 10 | Unicode and spacing | Capture Korean, accented Latin text, punctuation, and smart quotes. Verify exact Unicode preservation in JSON, Markdown, and Word. Repeat with zero and three blank lines and each quotation style. | Partially verified: the Word service appended `Unicode 테스트 — café`, saved it, and returned `already-exported` on retry with one occurrence; automated Markdown Unicode/spacing tests passed. Full packaged style matrix not run. |
| 11 | Pending output before quit | Produce a pending Word output and retry it before quitting. Confirm only Word is appended and Markdown is unchanged. Pending/failed session state is intentionally discarded at quit. | Not run |
| 12 | Automatic Word opening | Turn automatic opening on, quit Word, and capture. Word launches, appends, saves, and reports exported while Markdown remains independent. | Not run |
| 12a | Fresh destination | Select a new empty Markdown file and a new empty Word document while historical captures exist. Both files remain empty. Copy one new Acrobat quotation; only that quotation is appended to each new destination. | Not run |

## Capture, lifecycle, and UI regression matrix

| # | Case | Procedure and expected result | Status |
|---|---|---|---|
| 13 | Clipboard monitor with no windows | Close Settings, history, diagnostics, and the status menu. Wait, copy new Acrobat text, and reopen diagnostics. Timer count kept increasing and the generation was accepted. | Verified on the final package: the app-level monitor remained running and the timer reached 783 while windows were independently closed/reopened. |
| 14 | Live diagnostics | For an accepted Acrobat copy, verify monitor running, increasing timer count, current/previous/pending change counts, extraction attempts, both extraction lengths, foreground name and `com.adobe.Acrobat.Pro`, capture enabled, allowed, duplicate decision, coordinator/store invocation, persistence, and final result. | Verified on the final package at changeCount 197: timer 685, both lengths 133, Acrobat bundle ID, capture/allowed true, duplicate false, coordinator/store true, persistence success, accepted. |
| 15 | Capture off/on | With Capture off, a new allowed copy changes the clipboard but adds no capture. Turn it on and copy different text; one capture is accepted. | Not run |
| 16 | Non-allowed application | Copy text from TextEdit while it is not allowed. Clipboard remains unchanged by the collector and no capture/output occurs. | Not run |
| 17 | Settings window | Click Settings from the menu-bar menu. One real Settings window becomes frontmost/key. Click again after focusing, minimizing, and closing it; focus/reopen the controlled existing window without accumulating duplicates. Verify macOS 14+ and the macOS 13 AppKit fallback. | Partially verified on the current host with the packaged app: the same native Settings command made the Settings scene key, reused one window, and reopened after close. The automation surface does not expose the `MenuBarExtra` status item itself, so the literal status-icon click and physical Ventura fallback remain manual. The fallback builds with target 13.0. |
| 18 | Quit clears capture history | Capture once and confirm it appears in **Show Captures** and `captures.json`. Choose **Quit**, then verify `captures.json` was removed. Relaunch and confirm **Show Captures** is empty and the session count is zero. Also place a stale test store before launch and confirm startup removes it. Verify the previously exported Markdown and Word content is unchanged. | Not run |
| 19 | Preview/Safari/Chrome | For each enabled source, copy distinct PDF text. Each is captured once. Disable each source and confirm it is rejected. | Not run |
| 20 | OCR accepted | With the packaged menu-bar app running and Screen Recording granted, invoke OCR from both the menu and the global shortcut while Acrobat is frontmost. Confirm the app activates, crosshair overlays accept a drag immediately, Escape cancels, and a completed selection opens the editable confirmation panel. Add English or Korean text and verify it enters canonical storage and both enabled outputs exactly like clipboard text. | Not run |
| 21 | OCR cancel/blank | Cancel OCR or select a blank area. No canonical capture or output is created. | Not run |
| 22 | Screen Recording denied or stale | Deny Screen Recording, or replace an ad-hoc build while its old TCC entry remains enabled. Every explicit OCR attempt must recheck/request through CoreGraphics and show an actionable explanation instead of trusting stale `UserDefaults` or silently returning. Remove/re-add the installed app when its code identity changed, relaunch, and confirm OCR becomes available. Clipboard and both outputs continue throughout. | Not run |
| 23 | Output toggles | Disable Markdown only and capture: canonical plus Word succeed and Markdown stays pending. Reverse the toggles and verify canonical plus Markdown succeed. Re-enabling an output does not replay history; an explicit Markdown retry exports only its non-exported captures without duplicating Word. | Not run |
| 24 | Huge clipboard | Copy more than 250,000 characters from an allowed app. The size policy rejects it without creating canonical or output records, and the menu-bar app remains responsive. | Not run |
| 25 | Destination rename/bookmark | Rename or move each selected destination in Finder. If its bookmark follows the move, output continues. Otherwise that output alone fails visibly and reselecting it enables a safe retry. | Not run |

## Automated and build evidence

On 2026-09-10, the automated runner covers canonical persistence and session-history removal, persistence-failure integrity, Markdown UTF-8 append, capture-ID idempotency, Markdown missing-target failure, output formatting, settings migration/persistence, and independent per-capture output-state persistence.

The release app was rebuilt at `dist/PDF Quote Collector.app`, ad-hoc signing passed strict verification, `LSUIElement` is true, minimum macOS is 13.0, and the Apple Events usage description is present. The final packaged process passed cases 1–3, 9, 13, and 14; the automation-accessible portion of 17 also passed. Cases still marked Not run require their specific destructive destination, privacy denial, OCR, status-item, or cross-version setup.
