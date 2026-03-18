## Plan: macOS Mermaid Viewer and Editor

The recommended implementation is a native AppKit document app with two custom Metal-backed surfaces: a left viewport that presents the current diagram as a GPU texture, and a right editor that renders Mermaid source with low-latency syntax colouring and diagnostics. The existing `macgui` runtime should be reused for window creation, MTKView hosting, text input bridging, toolbar/menu wiring, and glyph rendering, while new app-specific Zig modules own document state, parse/render scheduling, export, and phase-two scene editing.

**Steps**
1. Freeze the phase-one target and keep it narrow: native document window, split layout, image-based viewport, Mermaid source editor, live diagnostics, and SVG/PNG/PDF export. Explicitly defer direct canvas editing, node handles, and structural drag operations to phase two so the first version is stable and fast.
2. Create a dedicated macOS app target in [build.zig](/Volumes/SSK%20SSD/merrow/build.zig) that links the existing Mermaid core plus a trimmed `macgui` platform layer. Avoid baking this into the CLI executable. The app should have its own entrypoint and platform bridge so build, test, and packaging concerns stay separate.
3. Extract or adapt a reusable shell from [macgui/ed_metal_bridge.m](/Volumes/SSK%20SSD/merrow/macgui/ed_metal_bridge.m) and related runtime code so the app gets: `NSApplication`, `NSWindow`, menu bar, toolbar, file panels, and `MTKView` lifecycle without copying unrelated editor features from the other project. Keep the reuse surgical rather than wholesale.
4. Introduce a document model in Zig that holds source text, document path, dirty state, parse snapshot, render snapshot, and export metadata. Add app modules for document management, controller logic, diagnostics, viewport state, editor buffer state, and export orchestration. These modules should be app-specific and not mixed into the core Mermaid library.
5. Stand up the main two-pane window. The left side should host a Metal viewport view with zoom and pan state. The right side should host a Metal-backed text editor view. Add a thin status bar at the bottom that reports cursor location, zoom, parse state, and render timing.
6. Implement the phase-one viewport as a texture presenter, not a scene editor. Use the current renderer to produce an RGBA image from the latest good parse/layout snapshot, upload it into a Metal texture, and let the viewport handle zoom/pan as a camera transform. Add fit, 100%, and actual-size commands in the toolbar and View menu.
7. Build the Mermaid editor buffer and presentation path. Use a piece table or rope in Zig, visible-line layout caching, incremental lexical tokenization over dirty spans, and a custom `NSTextInputClient`-compatible view so text input, selection, IME, and clipboard stay native while rendering stays Metal-driven.
8. Add fast diagnostics in two layers: immediate lexical feedback and debounced full parse diagnostics. Reuse the existing Mermaid parser and lexer in `src/` for real syntax validation, but do not block typing or caret motion on parse/layout work. A failed parse should update the status bar and inline markers while leaving the last valid render visible.
9. Build a cancellable background pipeline. Text edits should produce immutable snapshots; parser, layout, and raster render jobs should run on background workers; and the app should atomically swap in only the latest completed frame. Stale jobs must be dropped aggressively so typing speed is never held hostage by previous renders.
10. Add native file and document actions: New, Open, Save, Save As, autosave in place, recent files, and reopen-last-document behavior. Export should remain distinct from save and should appear in both menu and toolbar workflows where appropriate.
11. Implement export paths from a shared document snapshot. SVG should reuse the existing vector path. PNG should reuse the current raster path. PDF should be vector-first, ideally emitted through CoreGraphics from layout geometry rather than by rasterizing the PNG output.
12. Define performance guardrails and test them early. The app needs cheap incremental tokenization, bounded render queues, reuse of Metal resources, and instrumentation for parse time, render time, and frame latency. Measure before optimizing blindly, but build the architecture so expensive work is already off the UI path.
13. Prepare for phase two by ensuring the parse and layout model can eventually expose stable node, edge, and subgraph identities. The phase-one viewport remains image-based, but the internal snapshot format should not make a later editable-canvas transition impossible.
14. Phase two begins only after phase one is solid: promote the left pane from texture viewer to editable scene canvas, add hit testing and selection, map Mermaid entities to persistent scene IDs, and keep text and canvas edits synchronized through one document model.

**Relevant files and areas**
- [build.zig](/Volumes/SSK%20SSD/merrow/build.zig) - add a macOS app target, separate entrypoint, and platform-specific linkage.
- [macgui/ed_metal_bridge.m](/Volumes/SSK%20SSD/merrow/macgui/ed_metal_bridge.m) - strongest source for AppKit bootstrap, MTKView hosting, toolbar/menu plumbing, and `NSTextInputClient` handling.
- [macgui/ed_graphics.zig](/Volumes/SSK%20SSD/merrow/macgui/ed_graphics.zig) - useful patterns for command routing, glyph rendering support, and runtime state boundaries.
- [src/root.zig](/Volumes/SSK%20SSD/merrow/src/root.zig) and existing `src/` parser/render code - core Mermaid parse, layout, and render functionality to reuse rather than duplicate.
- [macos-viewer-design-note.md](/Volumes/SSK%20SSD/merrow/macos-viewer-design-note.md) - architectural baseline for the app and source of the phase split.

**Verification**
1. App target builds and launches a native macOS window with menu bar, toolbar, and status bar.
2. Opening a Mermaid file shows source text on the right and a rendered diagram on the left.
3. Typing updates syntax colours immediately and diagnostics within the debounce window.
4. A syntax error does not freeze typing and does not destroy the last valid viewport image.
5. Zoom, pan, fit, and actual-size behavior stay smooth on large diagrams.
6. Exported SVG, PNG, and PDF match the current document snapshot.
7. Rendering and parse timings are visible enough to catch regressions during development.

**Decisions**
- Use AppKit for native shell and document behavior, not a custom all-Metal shell.
- Use Metal for both the viewport and editor rendering surfaces.
- Keep phase one image-based in the viewport to reduce complexity and get to a usable product sooner.
- Reuse `macgui` plumbing selectively; do not drag over unrelated features from the other project.

**Further Considerations**
1. If the custom Metal editor threatens schedule, keep the internal interfaces clean enough that a temporary text component can be swapped in without rewriting the document model.
2. If PDF vector export is more involved than expected, stage it behind SVG and PNG, but do not lock in a raster-only PDF path as the permanent design.
3. Plan for snapshot-based undo/redo at the document layer early, because phase two canvas editing will need it anyway.