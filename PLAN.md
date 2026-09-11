# PDF Quote Collector implementation plan

## Environment findings

- Host: macOS 26.6.2 on Apple silicon.
- Toolchain: Apple Swift 6.3.3 and Clang are available through Command Line Tools.
- Full Xcode is not selected (`xcodebuild` is unavailable with the active developer directory). The project therefore uses Swift Package Manager and includes an app-bundle packaging script. Full Xcode remains the recommended development environment for signing, entitlements, and interactive debugging.
- Native frameworks available on the host include AppKit, SwiftUI, Vision, and ScreenCaptureKit.
- Minimum deployment target: macOS 13. `MenuBarExtra` is the determining API. Screen capture uses CoreGraphics APIs available on that target; OCR uses Vision.
- The repository was already initialized but had no commits or files.

## Sequential phases

1. Build a native SwiftUI/AppKit menu-bar executable, a non-invasive `NSPasteboard` monitor, an in-memory session history, and a capture-history window. Verify build and unit-testable clipboard event handling.
2. Record the frontmost app for each clipboard event and filter with a persistent bundle-ID allowlist.
3. Add a conservative `TextCleaner` with tests for line wrapping, soft hyphenation, Unicode whitespace, and paragraph preservation.
4. Add time-bounded, configurable duplicate suppression with tests.
5. Introduce a structured capture model and an atomic, durable JSON canonical store with recovery behavior and tests.
6. Keep the canonical store authoritative, then attempt independent idempotent Markdown append and Microsoft Word Apple Events output for every accepted capture.
7. Add independently testable plain/bullet/quoted formatting and spacing settings.
8. Add conservative source context using the foreground application and window title only when available without Accessibility permission.
9. Add a configurable global shortcut and native drag-region selection with on-demand screen capture and graceful Screen Recording permission handling.
10. Add local Vision OCR for English and Korean where supported.
11. Add an editable OCR confirmation panel with Add, Cancel, Escape, and Command-Return.
12. Complete persistent native settings and menu status.
13. Centralize permission status and explanations; request Screen Recording only for OCR and Apple Events only when exporting to Word.
14. Document and enforce a local-only privacy model.
15. Add bounded-input checks and explicit output/storage error reporting and recovery state.
16. Complete automated tests and `MANUAL_TESTS.md`; record only tests actually run.
17. Maintain modular services with protocols at persistence/output boundaries.
18. Complete user and architecture documentation.
19. Commit only stable phases; never commit captures, PDFs, screenshots, notes, or build products.
20. Run the full automated suite and package the app. Record manual UI steps that still require a person and installed third-party readers.

## Critical gates

- Clipboard capture must build and its event de-duplication logic must pass tests before source filtering or cleanup is added.
- Text cleanup and duplicate suppression tests must pass before persistence is introduced.
- Persistence must survive reloads within the active session and recover from output failure before export/OCR work proceeds; a normal app quit intentionally clears session history.
- OCR UI is added only after region capture and permission failure paths compile and can be exercised independently.

## Progress

- Phase 0 complete: environment inspected, package plan selected, privacy-oriented ignore rules installed.
- Phase 1 complete (automated gate): debug build succeeds and pasteboard event de-duplication test passes. Manual Preview and ordinary-app copy checks remain listed for a signed/running GUI session.
- Phase 2 complete (automated gate): bundle-ID foreground filtering and a persistent per-application allowlist build successfully; allowed, disabled, disallowed, and unknown sources are covered by tests. Manual browser/reader checks remain.
- Phase 3 complete (automated gate): conservative PDF extraction cleanup passes required hyphenation, line-wrap, Unicode whitespace, punctuation, and paragraph-preservation fixtures.
- Phase 4 complete (automated gate): configurable, time-bounded recent duplicate suppression passes exact, whitespace-normalized, expiry, different-text, and disabled-mode tests.
- Phase 5 complete (automated gate): structured capture records round-trip through an atomic, versioned JSON canonical store; unknown metadata remains nil, and normal termination clears the session-scoped history.
- Phase 6 updated (automated gate): canonical persistence precedes two independent exporters. Markdown uses synchronized UTF-8 append plus capture-ID markers; Word uses Apple Events plus capture-ID document variables. Per-output pending/exported/failed states persist independently, and selecting a new destination never replays history automatically.
- Phase 7 complete (automated gate): plain paragraphs remain the default; bullet, quotation-mark, and zero-to-three blank-line formats are isolated from capture logic and pass exact-output tests.
- Phase 8 complete (automated gate): foreground window titles are captured when CoreGraphics exposes them, known browser suffixes are stripped, and filenames are recorded only for unambiguous `.pdf` titles. Ambiguous browser titles never invent filenames.
- Phase 9 complete (automated/build gate): native global Command-Shift-X registration, one-shot permission flow, drag-region overlays, coordinate conversion, and in-memory capture build successfully. Coordinate conversion passes; the menu-bar process survived a launch smoke test. Permission prompt and physical drag remain manual checks.
- Phase 10 complete (automated/build gate): local Vision accurate OCR compiles, selects English/Korean only when reported supported, preserves recognized punctuation strings, and passes deterministic reading-order tests. Actual English/Korean image recognition remains a manual system-framework check.
- Phase 11 complete (build gate): editable multiline OCR confirmation compiles with Add, Cancel, Escape, and Command-Return. Clipboard and accepted OCR text share cleanup, duplicate, canonical persistence, metadata, and output ordering. A persistence failure keeps the confirmation open. Interactive key behavior remains manual.
- Phase 12 complete (automated gate): Capture state, bookmark, shortcut, allowlist, duplicate control, style, and spacing use one versioned settings store. The native Settings window exposes all controls; round-trip and corrupt-settings fallback tests pass.
- Phase 13 updated (build gate): Screen Recording remains confined to explicit OCR. Word output has its own Apple Events usage description and does not run while Word is closed unless automatic opening is enabled.
- Phase 14 complete: the README documents the local-only data path, in-memory screenshots, local Vision OCR, absence of network dependencies/telemetry/LLMs, and least-privilege permissions.
- Phase 15 updated (automated gate): oversized input is rejected explicitly; atomic-store failure cannot create a partial record; exporter failures remain attached to the durable capture and can be retried separately without duplicating an already-exported destination.
- Phase 16 complete (automated gate/documentation): 13 deterministic tests pass. `MANUAL_TESTS.md` covers every required reader, restart, permission, OCR, Word, and failure-recovery workflow and clearly marks all unperformed GUI cases as not run.
- Phase 17 complete (automated gate): capture monitoring, source detection, transaction processing, persistence, formatting/output, OCR, region selection, settings, and permissions are separate components. The extracted `CaptureCoordinator` is directly tested and all 14 checks pass without warnings.
- Phase 18 complete: README, plan, architecture, and manual-test documentation cover build/run workflows, output behavior, permissions, privacy, components, recovery, and known limitations. A native app-bundle packaging script and Info.plist are included.
- Phase 19 complete: stable work was committed at each phase boundary; build products, app bundles, captures, notes, PDFs, and screenshots are ignored. The final tracked tree contains no user content or secrets.
- Phase 20 complete for automated/build gates: the production configuration builds, the app bundle is assembled and ad-hoc signed, its Info.plist validates with `LSUIElement` and macOS 13 minimum, all 14 release tests pass, and the packaged process survives a startup smoke test. The real-reader, permission, OCR-language, and Word workflows remain explicitly unverified in `MANUAL_TESTS.md` and must be performed before claiming end-to-end acceptance.

## Intended architecture

`ClipboardMonitor` and `RegionCaptureService` produce candidates. `CaptureCoordinator` validates input, cleans text, suppresses duplicates, and commits accepted captures to `CaptureStore`. Only then do `MarkdownOutputService` and `WordOutputService` run independently and persist their own state. OCR passes through an editable confirmation step before entering the same coordinator. Settings and permissions are isolated services.
