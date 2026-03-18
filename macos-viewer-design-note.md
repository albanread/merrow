# macOS Mermaid Viewer and Editor Design Note

## Goal

Build a native macOS desktop app for Mermaid diagrams with:

- a wide-screen two-pane layout
- left pane: fast Metal-backed diagram viewport with zoom and pan
- right pane: fast syntax-coloured Mermaid editor with live error detection
- native AppKit window chrome: menu bar, toolbar, status bar, document window behavior
- output support for SVG, PNG, and PDF

Phase one treats the diagram as a rendered image in the viewport.

Phase two upgrades the viewport into an editable canvas backed by the Mermaid scene graph.

## Product Shape

### Main Window

- Single document window
- Left pane takes roughly 60 to 70 percent of width
- Right pane takes roughly 30 to 40 percent of width
- Toolbar across the top
- Thin status bar along the bottom
- Optional navigator/minimap can wait until later

### Left Pane: Diagram View

- Metal-backed viewport
- Displays the currently rendered diagram image
- Smooth trackpad pan and pinch zoom
- Fit, 100%, and actual-size actions in toolbar
- Background checker or neutral paper texture to make transparent exports readable
- Fast redraw on resize with no layout stutter

### Right Pane: Mermaid Editor

- Metal-backed text editor surface
- Syntax colouring for Mermaid grammar
- Line numbers, current line highlight, selection, caret, and diagnostics gutter
- Incremental parse and error underline while typing
- Fast enough to keep latency below visible threshold on medium and large diagrams

### Status Bar

- Parse state: OK or first error summary
- Cursor line and column
- Current zoom percent
- Render time and last parse time

## Architectural Direction

Use AppKit for native shell and document behavior, and use Metal only for the high-frequency drawing surfaces.

That means:

- AppKit owns NSApplication, NSWindow, menu bar, toolbar, file dialogs, and document lifecycle
- a custom window content view hosts the split layout
- each pane is an MTKView or Metal-backed NSView
- Zig owns app state, parsing, layout, render scheduling, and export logic
- Objective-C bridge code handles AppKit and Metal device setup, then forwards events into Zig

This is the right split because Metal is ideal for the viewport and editor rendering paths, but AppKit is still the correct macOS layer for window management and native UI chrome.

## Reuse From Existing macgui

The existing macgui runtime already proves most of the hard platform plumbing:

- AppKit bootstrap and NSWindow creation
- MTKView setup and render loop
- toolbar and menu support
- text input handling through NSTextInputClient
- Metal shader pipeline and glyph rendering support
- event forwarding from Objective-C into Zig

The quickest path is not to invent a second platform layer. It is to extract a smaller reusable app shell from macgui and build the Mermaid app on top of that.

Recommended reused pieces:

- window and application bootstrap patterns from macgui bridge code
- toolbar and menu wiring patterns
- glyph atlas generation and text rendering pipeline
- input event dispatch model
- prebuilt runtime libraries only if they reduce iteration time without hiding too much behavior

## Proposed App Structure

## 1. Shell Layer

Language split:

- Zig: application state, commands, document model, Mermaid parse/render pipeline
- Objective-C: AppKit shell, MTKView hosting, file panels, menu and toolbar callbacks

Top-level modules:

- app/main.zig
- app/document.zig
- app/controller.zig
- app/editor_buffer.zig
- app/diagnostics.zig
- app/viewport.zig
- app/export.zig
- app/platform/macos_bridge.m

## 2. Data Flow

Edit loop:

1. user edits Mermaid text
2. buffer emits incremental dirty range
3. parser runs on background worker with debounce for full diagram regeneration
4. syntax tokenization updates immediately on the editor thread state
5. semantic parse result updates diagnostics
6. successful parse schedules render job
7. render job produces viewport image plus export-ready scene data
8. viewport uploads new texture and redraws

Important rule:

- typing must never block on a full render

The editor should keep responding even if layout on a complex graph takes longer.

## 3. Threading Model

Main thread:

- AppKit event loop
- MTKView draw callbacks
- menu and toolbar actions
- presentation of already-prepared frame data

Background worker pool:

- Mermaid lexing and parsing
- incremental diagnostics
- layout and image rendering jobs
- export jobs

Shared state strategy:

- immutable snapshots for document text and parse results
- atomic pointer swap for latest renderable frame
- bounded queues for render requests so stale intermediate jobs can be dropped

This matters more than almost anything else for perceived speed. Fast UI comes from aggressive cancellation and snapshot replacement, not from forcing every stage into a single synchronous pass.

## Left Pane Design

## Viewport Rendering

Phase one viewport model:

- viewport shows a GPU texture generated from a rendered RGBA image
- pan and zoom are pure camera transforms in Metal
- no per-node hit testing required yet

Render sources:

- preferred on-screen source: RGBA bitmap rendered by Merrow
- export sources: SVG, PNG, PDF generated from the same parse/layout snapshot

Why image-first is correct for phase one:

- simplest path to a stable, fast viewer
- avoids mixing interaction design with scene editing too early
- lets the team focus on parser, diagnostics, and export correctness first

### Zoom Strategy

- maintain a continuous zoom value and pan offset in viewport state
- use high-quality sampling in Metal for interactive zoom
- trigger background rerender at higher backing resolution when zoom exceeds threshold

This gives immediate fluid zoom while preserving crispness after the interaction settles.

### Pan and Fit

- space-drag or trackpad drag pans
- pinch zoom centered on cursor
- double-click fit to diagram
- toolbar actions: Fit, 100%, Actual Size

## Right Pane Design

## Editor Rendering

Do not use NSTextView as the main editor surface if the goal is maximum control and consistently low latency.

Instead:

- use a custom editor view that conforms to NSTextInputClient for IME and text services
- render glyphs through the existing Metal text path from macgui
- keep a rope or piece-table buffer in Zig
- maintain visible-line layout cache for the current viewport only

This yields predictable performance and makes syntax colouring, diagnostics, minimap, and future structural overlays much easier.

### Editor Internals

Core pieces:

- text buffer: piece table or rope
- tokenizer: incremental Mermaid lexer over dirty line spans
- parser: debounce full parse after edits
- diagnostics: line-column ranges plus severity
- layout cache: glyph runs for visible rows only

### Syntax and Diagnostics

Syntax colours should be cheap and lexical in the hot path:

- keywords and diagram headers
- identifiers
- arrows and operators
- strings and labels
- comments
- invalid tokens

Error detection should have two tiers:

- immediate lexical errors during typing
- debounced parser and semantic errors after short idle window

### Latency Targets

- caret movement and text insertion should feel instant
- syntax recolour should happen within one frame for local edits
- full parse should debounce in the 50 to 120 ms range
- render should be cancellable so stale frames never replace newer ones

## Export Model

Menu and toolbar should expose:

- Export SVG
- Export PNG
- Export PDF

Implementation direction:

- SVG: use existing vector output path
- PNG: use existing raster render path
- PDF: generate via CoreGraphics PDF context or emit vector drawing commands directly from the layout snapshot

PDF should not be produced by rasterizing the PNG unless absolutely necessary. It should preserve vector geometry where possible.

## Document and App Behavior

Recommended document features for the first usable version:

- New, Open, Save, Save As
- autosave in place
- dirty indicator in title bar
- recent files
- reopen last document
- export actions separate from save

Recommended toolbar actions:

- Open
- Save
- Export
- Fit
- Zoom In
- Zoom Out
- Re-render toggle or auto-render toggle if needed

Recommended menu groups:

- File
- Edit
- View
- Diagram
- Export
- Window
- Help

## Phase Plan

## Phase 1: Fast Viewer + Fast Editor

Deliver:

- native document window
- split layout
- Metal viewport displaying rendered image
- Metal text editor with syntax colouring
- live diagnostics panel or inline diagnostics
- SVG, PNG, PDF export
- background parse and render pipeline with cancellation

Explicitly out of scope:

- direct manipulation of nodes and edges on canvas
- selection handles in viewport
- drag-to-edit diagram geometry

## Phase 2: Editable Canvas

Upgrade from image viewer to scene viewer:

- Mermaid parse tree maps to editable scene graph
- node and edge hit testing
- selection model
- drag, add, delete, reconnect operations
- text and canvas stay synchronized from the same underlying document model

This phase needs a stable identity system in the parser and layout model, so nodes, edges, and subgraphs survive reparse with persistent IDs.

## Performance Rules

Non-negotiable rules for keeping the app fast:

- never block typing on layout or export
- never re-tokenize the whole file for a single-line edit
- never rebuild Metal resources that can be reused frame to frame
- keep viewport redraw independent from parser progress
- drop stale render jobs aggressively
- profile first before adding architectural complexity

## Recommended First Implementation Sequence

1. Create a new macOS app target in Zig that links the existing Mermaid core and the macgui platform pieces.
2. Extract a minimal AppKit plus MTKView shell from macgui instead of building a second shell from scratch.
3. Stand up a two-pane native window with dummy left and right Metal views.
4. Feed the left pane with an RGBA texture from the current renderer.
5. Build the editor buffer, text shaping cache, and lexical syntax highlighting.
6. Add debounced parse diagnostics.
7. Wire export actions for SVG, PNG, and PDF.
8. Add document lifecycle and autosave.

## Risks and Decisions

### Good Risk

Custom Metal editor rendering is more work than using NSTextView, but it is the right choice if low-latency rendering and a future canvas/editor hybrid are core goals.

### Main Technical Risk

Text editing correctness on macOS is not trivial. IME, selection, accessibility, clipboard, undo, and text services all need care. Reusing the NSTextInputClient approach already present in macgui reduces that risk substantially.

### Main Product Risk

Trying to make the viewport editable too early will slow everything down. The staged approach matters.

## Recommendation

Build the app as a native AppKit document app with two custom Metal surfaces inside it.

For phase one:

- left pane is a texture-backed diagram viewer
- right pane is the fast Mermaid source editor
- AppKit handles shell and export workflows

For phase two:

- promote the left pane from image viewport to editable scene canvas without replacing the shell or document model

That path is fast to first usable version, consistent with the current codebase, and leaves room for a serious editor rather than a demo wrapper.