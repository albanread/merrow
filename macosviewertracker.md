# macOS Viewer and Editor Tracker

Tracks implementation progress for the macOS Mermaid app plan in [macosviewerplan.md](./macosviewerplan.md).

## Overall Status

- Status: In progress
- Focus area: Phase-one native macOS document app with Metal viewport and a real Mermaid editor
- Target outcome: A fast two-pane macOS app with live Mermaid editing, image-based preview, and SVG/PNG/PDF export

## Work Items

| ID | Work Item | Status | Notes |
| --- | --- | --- | --- |
| 1 | Freeze phase-one scope and success criteria | Complete | Phase one remains image-based in the viewport with editor and diagnostics still planned separately |
| 2 | Add dedicated macOS app target in `build.zig` | Complete | `zig build studio` now builds the separate macOS scaffold target |
| 3 | Extract or adapt reusable AppKit plus Metal shell from `macgui` | Partial | AppKit window shell, Metal view hosting, status bar, and menu scaffolding are live without pulling across the full runtime |
| 4 | Define app module structure for document, controller, editor, viewport, diagnostics, and export | Not started | Keep app code separate from core Mermaid library code |
| 5 | Create native document window with split layout and status bar | Complete | Large native window, split panes, status bar, toolbar, and menu bar are live |
| 6 | Implement phase-one Metal viewport with zoom and pan | Complete | Viewport is texture-backed, Metal-rendered, and supports pan and zoom interactions |
| 7 | Hook viewport to existing Mermaid raster render output | Complete | App loads a rendered Mermaid preview at launch and now refreshes the preview from the live editor buffer |
| 8 | Implement editor buffer and visible-line layout cache | Partial | Native `NSTextView` editor is live; custom buffer and line-layout cache remain future work |
| 9 | Build Metal-backed text editor rendering path | Deferred | Replaced the fake texture editor with a real native editor; revisit custom Metal text rendering only if needed later |
| 10 | Wire native text input, clipboard, IME, and selection behavior | Complete | Native editing now comes from AppKit text controls instead of a placeholder surface |
| 11 | Add incremental lexical tokenization for Mermaid syntax colouring | Partial | Live syntax colouring now runs on each edit, but it is still whole-buffer rather than dirty-range incremental |
| 12 | Add debounced parser diagnostics and status updates | Partial | Status bar now updates from live syntax checks and preview refresh is debounced on valid edits |
| 13 | Build cancellable background parse, layout, and render pipeline | Not started | Immutable snapshots plus stale-job dropping |
| 14 | Add file lifecycle actions: New, Open, Save, Save As, autosave | Not started | Native macOS document behavior |
| 15 | Add export actions for SVG, PNG, and PDF | Not started | PDF should remain vector-first where possible |
| 16 | Add performance instrumentation and developer diagnostics | Not started | Parse time, render time, frame timing, queue depth |
| 17 | Add app-level tests or harnesses for editor, render pipeline, and export smoke checks | Not started | Start with non-UI logic and targeted integration coverage |
| 18 | Define stable scene identity requirements for phase two | Not started | Needed before editable canvas work starts |
| 19 | Prototype phase-two canvas hit testing and selection model | Not started | Do only after phase one is solid |

## Milestones

### Milestone 1: App Shell

- [x] Items 1-5 complete
- [x] App launches as a native macOS window
- [x] Split layout, toolbar, menu bar, and status bar are in place

### Milestone 2: Live Editing Loop

- [ ] Items 6-13 complete
- [ ] Editor remains responsive while parse and render work happens in background
- [ ] Viewport updates from the latest valid document snapshot

### Milestone 3: Document and Export

- [ ] Items 14-17 complete
- [ ] Files can be opened, saved, and exported reliably
- [ ] SVG, PNG, and PDF outputs match the live document state

### Milestone 4: Canvas Foundation

- [ ] Items 18-19 complete
- [ ] Phase-two canvas work has stable entity identity and selection groundwork

## Risks

- Custom text editing on macOS is a correctness risk if IME, undo, and selection behavior are under-specified.
- Pulling too much from `macgui` could import unrelated complexity and slow down the app.
- Trying to make the viewport editable before phase one is stable will likely derail schedule and performance.
- PDF export could drift into a raster shortcut unless vector-first requirements are held explicitly.

## Decision Log

- Preferred shell: AppKit for native windowing and document behavior.
- Preferred rendering path: Metal viewport plus a real native editor for phase one.
- Phase-one preview model: rendered image texture, not editable scene canvas.
- Reuse strategy: selective extraction from `macgui`, not wholesale porting.

## Update Log

- 2026-03-16: Tracker created from [macosviewerplan.md](./macosviewerplan.md) and [macos-viewer-design-note.md](./macos-viewer-design-note.md).
- 2026-03-16: Added the first `merrow-studio` macOS app target plus a native AppKit window scaffold with split panes, toolbar, status bar, and a standard `Quit Merrow Studio` menu item.
- 2026-03-16: Connected the left Metal viewport to a real Merrow render path by generating a default preview from `test-diagrams/flowchart_subgraphs.mmd` and loading the PNG as a Metal texture at launch.
- 2026-03-16: Replaced the fake right-pane texture editor with a real `NSTextView` editor, added live Mermaid syntax highlighting and parser-backed status updates, and refreshed the left Metal preview from the current editor buffer.