# Enhanced Features Plan: Mixed Markdown + Diagram Editor

## Overview

Transform Merrow Studio from a single-diagram mermaid editor into a mixed **markdown + enhanced diagram editor**. Users open standard `.md` files containing prose text and multiple ` ```mermaid ` code blocks. The editor always shows the full markdown source. A diagram selector lets the user choose which diagram to preview or freeform-edit. Hand-tuned freeform edits are persisted in a SQLite database (`Documents/Merrow/library/merrow.db`) keyed by content hash. Word/PDF export walks the full markdown document, translating text to Word content and each diagram to a high-quality PNG — preferring the hand-tuned freeform version (FFM) over raw mermaid auto-layout when one exists.

---

## Design Decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| **File format** | Standard `.md` files | Portable, editable in any text editor, version-control friendly |
| **FFM storage** | SQLite database at `Documents/Merrow/library/merrow.db` | Single file; atomic writes; queryable metadata; trivial garbage collection |
| **FFM keying** | Content hash of mermaid block (trimmed, `\r\n` → `\n`, then hash) as SQLite primary key | Portable across file moves; same diagram source = same key regardless of file location |
| **SQLite integration** | `sqlite3.c` amalgamation compiled via `addCSourceFile()` | Single C file, no external dependencies, Zig C interop is trivial |
| **On-screen rendering** | Direct2D (existing canvas) | Already implemented; real-time interactive editing |
| **Export rendering** | stb software renderer (new path) | High-quality, resolution-independent PNG; no GPU dependency for export |
| **Editor layout** | Split pane — editor always visible, preview/canvas on right | Existing layout; stop hiding editor when entering freeform mode |
| **Diagram naming** | Heading (`##`) immediately above a ` ```mermaid ` block | Natural markdown convention; unnamed blocks get "Diagram 1", "Diagram 2", etc. |
| **Markdown scope** | Minimal initially: headings, paragraphs, bold/italic, fenced code blocks | Enough for structured Word export; expand later (lists, tables, images) |
| **Multi-diagram** | Yes — N mermaid blocks per document, each independently editable | Core requirement for real-world documentation |
| **FFM preference** | If sidecar FFM exists for a block's content hash, use freeform graph; otherwise parse and auto-layout mermaid | Freeform edits always take priority; editing mermaid source changes the hash, orphaning old FFM |

---

## Architecture: How FFM Preference Works

```
User opens document.md
  │
  ├─ Parse markdown → MarkdownDocument { blocks: [Text, Diagram, Text, Diagram, ...] }
  │
  ├─ For each DiagramBlock:
  │     content_hash = hash(normalize(mermaid_source))
  │     Query: SELECT graph_blob FROM ffm WHERE content_hash = ?
  │       ├─ ROW FOUND → Deserialize StudioEditableGraph from BLOB (hand-tuned version)
  │       └─ NO ROW    → Parse mermaid → auto-layout → StudioEditableGraph
  │
  ├─ Preview pane: render selected diagram's graph
  │     On-screen: Direct2D canvas
  │     Export:    stb software renderer → PNG bytes
  │
  └─ User enters freeform edit mode for a diagram:
        Edits modify the StudioEditableGraph in memory
        Auto-saved to merrow.db via INSERT OR REPLACE on change
        Original mermaid source hash is preserved as the primary key
```

**Content Hash Lifecycle:**
- When a user edits the mermaid *source text* in the editor, the content hash changes → the old FFM sidecar no longer matches → the diagram falls back to fresh auto-layout. This is intentional: source changes should produce new layouts unless re-tuned.
- When a user edits the diagram in *freeform canvas mode*, the content hash stays the same (it's keyed to the original mermaid source, not the visual edits) → the FFM row is updated in place.
- Orphaned FFM rows (from changed or deleted mermaid blocks) persist harmlessly. Garbage collection is a single SQL query: `DELETE FROM ffm WHERE content_hash NOT IN (...)` — trivial to implement in a future "Library Manager" or periodic cleanup.

---

## Phase 1: Document Model & Markdown Parser

**Goal**: Parse markdown into a block structure that identifies text blocks and mermaid diagram blocks.

### 1.1 Define `MarkdownDocument` struct

New file: `app/document_model.zig`

```
MarkdownDocument
  ├─ source_path: ?[]const u8          — original .md file path
  ├─ blocks: []Block                   — ordered sequence of content blocks
  └─ diagram_count: usize              — convenience: number of DiagramBlocks

Block = union(enum)
  ├─ text: TextBlock
  │    └─ content: []const u8          — raw markdown text (headings, paragraphs, etc.)
  └─ diagram: DiagramBlock
       ├─ name: ?[]const u8            — display name (from heading above block, or null)
       ├─ mermaid_source: []const u8   — raw mermaid text inside the fence
       ├─ content_hash: u64            — deterministic hash for FFM sidecar lookup
       └─ source_line: usize           — line number in the .md file (for editor sync)
```

### 1.2 Implement minimal markdown parser

New file: `app/markdown_parser.zig`

- Scan line-by-line for ` ```mermaid ` and ` ``` ` fences
- Everything outside fences → `TextBlock`
- Everything inside fences → `DiagramBlock`
- For each diagram block:
  - Compute content hash: trim, normalize `\r\n` → `\n`, `std.hash.Wyhash`
  - Walk backward through preceding `TextBlock` lines to find nearest heading (`# ...`) → extract as diagram name
- No full AST needed — line-oriented fence detection is sufficient

### 1.3 Content-hash function

Deterministic normalization:
1. Trim leading/trailing whitespace from the mermaid block
2. Normalize all line endings to `\n`
3. Collapse runs of blank lines to single `\n`
4. Hash with `std.hash.Wyhash` → `u64`
5. Hex-encode for filename: `{016x}.ffm`

### 1.4 Wire into app open flow

When user opens a file:
- If `.md` extension: parse into `MarkdownDocument`, populate diagram selector, show first diagram in preview, editor shows full markdown
- If `.mmd` extension (backward compat): wrap in a synthetic single-`DiagramBlock` `MarkdownDocument` so the rest of the pipeline is unified

**Files to modify:**
- `app/platform/windows/document.zig` — `loadSourceFromPath()`, `chooseDocumentPath()` (add `.md` filter)
- `app/platform/windows_main.zig` — `handleOpenFile()`, `setEditorText()`
- `app/platform/windows/app_state.zig` — add `MarkdownDocument` state, `selected_diagram_index`

---

## Phase 2: App Mode Unification & Diagram Selector

**Goal**: Keep the editor always visible. Add a diagram selector. Allow switching between preview and freeform edit per-diagram.

### 2.1 Revise `AppMode`

Current modes hide the editor in freeform. New behavior:
- `mermaid` mode → editor visible, preview pane shows selected diagram
- `freeform` mode → editor **still visible**, preview pane replaced by freeform canvas for selected diagram
- Bottom line: the only thing that changes between modes is the right pane (preview vs. canvas)

### 2.2 Add diagram selector UI

Add a `ComboBox` (Win32 `CBS_DROPDOWNLIST`) in the toolbar area:
- Populated from `MarkdownDocument` diagram blocks: `[name ?? "Diagram {i+1}" for each DiagramBlock]`
- `CBN_SELCHANGE` notification updates `selected_diagram_index` → triggers preview/canvas refresh
- For single-diagram docs (`.mmd` or `.md` with one block): selector shows one item or is hidden
- Store `selected_diagram_index: usize` in app state

### 2.3 Update preview rendering

The preview pane now renders the *selected* diagram:
1. Get `DiagramBlock` at `selected_diagram_index`
2. Query `db.loadFfm(content_hash)` from `merrow.db`
3. If row found → deserialize `graph_blob` into `StudioEditableGraph` → render via D2D (preview) or stb (export)
4. If no row → parse `mermaid_source` → auto-layout → render preview PNG as today

### 2.4 "Edit Diagram" toggle

- Menu item / toolbar button: "Edit Diagram" (or shortcut key)
- Switches preview pane to freeform canvas for the selected diagram
- Editor remains visible and editable below/beside the canvas
- Freeform modifications auto-save to `merrow.db` via `db.saveFfm()`

### 2.5 Editor ↔ diagram sync

- When user edits text inside a mermaid block in the editor:
  - Re-parse `MarkdownDocument` (fence detection is fast)
  - If the selected diagram's mermaid source changed → content hash changed → FFM no longer matches → preview falls back to auto-layout
- Cursor position tracking: determine which block the cursor is in
  - If inside a mermaid block → auto-select that diagram in the selector
  - If inside a mermaid block → enable "Edit Diagram" button

**Files to modify:**
- `app/platform/windows/toolbar.zig` — add ComboBox creation, population
- `app/platform/windows_main.zig` — `switchToMode()`, `rebuildFreeformCanvas()`, diagram selector handler
- `app/platform/windows/app_state.zig` — `selected_diagram_index`, `MarkdownDocument` reference
- `app/platform/windows/canvas/state.zig` — `CanvasState` (no structural change, just fed different graph)

---

## Phase 3: SQLite Library & FFM Persistence

**Goal**: Save/load freeform edits in a SQLite database keyed by content hash. SQLite provides atomic writes, queryable metadata, and trivial garbage collection — all in a single file.

### 3.1 Add SQLite to the build

Download the [SQLite amalgamation](https://sqlite.org/amalgamation.html) (`sqlite3.c` + `sqlite3.h`) into `deps/`.

In `build.zig`:
```zig
studio_exe.addCSourceFile(.{
    .file = .{ .cwd_relative = "deps/sqlite3.c" },
    .flags = &.{ "-DSQLITE_THREADSAFE=0", "-DSQLITE_OMIT_LOAD_EXTENSION" },
});
studio_exe.addIncludePath(.{ .cwd_relative = "deps" });
```

Flags: single-threaded (Studio is single-threaded), no extension loading (security hardening).

### 3.2 Extend user folders

Add `library` to `MerrowUserFolders` struct:
```
Documents/Merrow/
  ├─ generated/     — exported documents
  ├─ temp/          — temporary render files
  ├─ assets/        — header/trailer images
  └─ library/       — merrow.db lives here
```

Extend `runWindowsPreflight()` to ensure `library/` exists at startup.

### 3.3 Define database schema

```sql
-- FFM table: stores hand-tuned freeform graph edits
CREATE TABLE IF NOT EXISTS ffm (
    content_hash    TEXT PRIMARY KEY,   -- hex-encoded Wyhash of normalized mermaid source
    graph_type      INTEGER NOT NULL,   -- 0=flowchart, 1=sequence, 2=class, 3=ER
    diagram_name    TEXT,               -- display name from heading (nullable)
    source_file     TEXT,               -- last .md file path that contained this block
    mermaid_source  TEXT NOT NULL,       -- original mermaid source (for debugging/reference)
    graph_blob      BLOB NOT NULL,      -- serialized StudioEditableGraph binary
    created_at      TEXT NOT NULL DEFAULT (datetime('now')),
    modified_at     TEXT NOT NULL DEFAULT (datetime('now'))
);

-- Recent files table: tracks opened documents and last-used diagram index
CREATE TABLE IF NOT EXISTS recent_files (
    path            TEXT PRIMARY KEY,
    last_opened     TEXT NOT NULL DEFAULT (datetime('now')),
    diagram_index   INTEGER NOT NULL DEFAULT 0
);

-- App preferences (key-value store for future use)
CREATE TABLE IF NOT EXISTS preferences (
    key             TEXT PRIMARY KEY,
    value           TEXT
);
```

### 3.4 Implement SQLite wrapper

New file: `app/library_db.zig`

Thin Zig wrapper around the SQLite C API:
```
LibraryDb
  ├─ open(db_path: []const u8) → !LibraryDb
  ├─ close() → void
  ├─ ensureSchema() → !void              — CREATE TABLE IF NOT EXISTS
  │
  ├─ saveFfm(content_hash, graph_blob, mermaid_source, graph_type, diagram_name, source_file) → !void
  │    → INSERT OR REPLACE INTO ffm (...) VALUES (...)
  │
  ├─ loadFfm(content_hash) → !?FfmRecord
  │    → SELECT graph_blob, graph_type, diagram_name FROM ffm WHERE content_hash = ?
  │
  ├─ deleteFfm(content_hash) → !void
  │    → DELETE FROM ffm WHERE content_hash = ?
  │
  ├─ listFfm() → ![]FfmSummary
  │    → SELECT content_hash, diagram_name, graph_type, source_file, modified_at FROM ffm
  │
  ├─ gcFfm(active_hashes: []const []const u8) → !usize
  │    → DELETE FROM ffm WHERE content_hash NOT IN (...) — returns rows deleted
  │
  ├─ saveRecentFile(path, diagram_index) → !void
  │    → INSERT OR REPLACE INTO recent_files (...)
  │
  └─ getRecentFiles(limit: usize) → ![]RecentFile
       → SELECT * FROM recent_files ORDER BY last_opened DESC LIMIT ?
```

### 3.5 Implement graph BLOB serialization

New file: `app/ffm_serializer.zig`

Binary format for the `graph_blob` column (same struct layout as before, but stored as a BLOB rather than a standalone file):
```
Header:
  magic: [8]u8 = "MROW-FFM"
  version: u16 = 2
  graph_type: u32
  width: f64, height: f64
  background: StudioColor (4 × u8)

Subgraph array:
  count: u32
  for each: { id, title, parent_id (length-prefixed strings), x, y, w, h, corner_radius: f64,
              fill/stroke: Color, stroke_width: f32, title_x, title_y, title_font_size, title_color }

Node array:
  count: u32
  for each: { id, label, subtitle, attributes_text, methods_text, parent_subgraph_id
              (length-prefixed strings), shape: u32, x, y, w, h: f64,
              fill/body_fill/stroke: Color, stroke_width: f32, label_color, label_font_size }

Edge array:
  count: u32
  for each: { source_id, target_id, label (length-prefixed strings), label_font_size: f32,
              color: Color, thickness: f32, line_style: u32, has_arrow, has_source_arrow: u8,
              source_end_style, target_end_style: u32 }
```

Functions:
- `serializeGraph(graph: *StudioEditableGraph, allocator) → ![]u8` — graph → BLOB bytes
- `deserializeGraph(blob: []const u8, allocator) → !*StudioEditableGraph` — BLOB → allocated graph

### 3.6 Database lifecycle in the app

**Startup** (`runWindowsPreflight()`):
1. Ensure `Documents/Merrow/library/` directory exists
2. Open `merrow.db` (creates if missing)
3. Run `ensureSchema()` to create/migrate tables
4. Store `LibraryDb` handle in app state

**On freeform edit** (debounced, ~500ms after last change):
1. Serialize current `StudioEditableGraph` → BLOB
2. `db.saveFfm(content_hash, blob, mermaid_source, graph_type, name, source_file)`
3. SQLite transaction ensures atomic write — no risk of corrupt data on crash

**On diagram selection**:
1. `db.loadFfm(content_hash)` → returns `?FfmRecord`
2. If found: deserialize `graph_blob` → `StudioEditableGraph` → use for preview/canvas
3. If not found: parse mermaid → auto-layout → render normally

**On app close**:
1. `db.close()` — flushes WAL, releases file lock

### 3.7 FFM lifecycle

- **Created**: first time user edits a diagram in freeform mode → `INSERT`
- **Updated**: each subsequent modification → `INSERT OR REPLACE` (upsert)
- **Orphaned**: when mermaid source changes, content hash changes → old row stays but is never queried
- **Garbage collected**: `db.gcFfm(active_hashes)` — pass all content hashes from currently open documents; deletes rows not in the set. Can be triggered manually ("Clean Library") or periodically.

### 3.8 Why SQLite over flat files

| Concern | Flat files (`*.ffm`) | SQLite (`merrow.db`) |
|---------|---------------------|---------------------|
| Atomic writes | Risk of partial write on crash | Transactions guarantee atomicity |
| Garbage collection | Directory scan + hash comparison | `DELETE WHERE NOT IN (...)` |
| Metadata queries | Parse each file header | SQL query on indexed columns |
| File count | Hundreds of tiny files | Single file |
| Library Manager UI | Manual file listing + parsing | `SELECT` with sorting/filtering |
| Recent files | Separate config file | Same database |
| Backup | Copy entire directory | Copy one file |
| Corruption recovery | Per-file; lose individual edits | `PRAGMA integrity_check`; WAL journaling |

**Files to create/modify:**
- `deps/sqlite3.c` + `deps/sqlite3.h` — NEW: SQLite amalgamation
- `app/library_db.zig` — NEW: SQLite wrapper with typed Zig API
- `app/ffm_serializer.zig` — NEW: graph BLOB serialization (unchanged from flat-file plan)
- `build.zig` — add `sqlite3.c` to studio build
- `app/platform/windows/document.zig` — `MerrowUserFolders` struct (add `library` field), folder creation
- `app/platform/windows_main.zig` — `runWindowsPreflight()` (open db), app state (store `LibraryDb`), FFM load/save integration
- `app/platform/windows/app_state.zig` — add `LibraryDb` handle to app state

---

## Phase 4: Freeform Graph → PNG Software Renderer

**Goal**: Render a `StudioEditableGraph` to PNG via the stb software path for high-quality Word/PDF export.

### 4.1 Create software renderer

New file: `src/render/editable_graph.zig`

```zig
pub fn renderEditableGraphToPNGBytes(
    graph: *StudioEditableGraph,
    scale_factor: f32,        // e.g. 4.0 for high-quality export
    font_data: []const u8,    // TTF font bytes
) !?[]u8                      // PNG bytes, caller owns
```

Implementation:
- Allocate `Canvas` from `src/render/canvas.zig` at `graph.width × graph.height × scale_factor`
- Draw in Z-order (matching D2D canvas in `draw.zig`):
  1. Background fill
  2. Subgraphs (back to front, respecting nesting)
  3. Edges (lines + arrowheads + labels)
  4. Nodes (shape fill + border + label text)
- Reuse shape primitives from `src/render/graph.zig` where possible (roundedRect, diamond, circle, hexagon, etc.)
- Text rendering via `src/render/text.zig` (stb_truetype font rasterization)
- Output via `Canvas.saveToPNGBytes()` (stb_image_write)

### 4.2 Export FFI function

In `app/preview.zig`:

```zig
pub export fn merrow_studio_render_editable_graph_png_bytes(
    graph: *StudioEditableGraph,
    out_len: *u32,
) callconv(.c) ?[*]u8
```

Caller frees via existing `merrow_studio_free_png_bytes()`.

### 4.3 Update Word export to prefer freeform render

In `exportDiagramToWord()` (or new `exportMarkdownDocumentToWord()`):
- For each `DiagramBlock`:
  1. Query `db.loadFfm(content_hash)` from `merrow.db`
  2. If row found: deserialize `graph_blob` → `renderEditableGraphToPNGBytes()` → temp PNG → insert
  3. If no row: use existing `merrow_studio_render_preview_png_bytes()` from mermaid source
- This ensures hand-tuned diagrams export at full quality with exact user positioning

**Files to modify/create:**
- `src/render/editable_graph.zig` — NEW: software renderer
- `app/preview.zig` — new FFI export
- `app/platform/windows_main.zig` — export flow update

**Reference files:**
- `src/render/graph.zig` — `renderGraphToPNGBytesWithFont()` (template)
- `src/render/canvas.zig` — `Canvas` struct, pixel operations
- `app/platform/windows/canvas/draw.zig` — D2D shapes (parity reference)

---

## Phase 5: Markdown-Driven Word Export

**Goal**: Walk the full `MarkdownDocument` and translate each block to Word content, producing a structured document with text and diagrams.

### 5.1 Document-level export function

New or extended function: `exportMarkdownDocumentToWord()`

```
For each block in MarkdownDocument.blocks:
  ├─ TextBlock:
  │    Parse minimal markdown:
  │      # Heading 1    → wcg_insert_heading(doc, text, 1)  → Word "Heading 1" style
  │      ## Heading 2   → wcg_insert_heading(doc, text, 2)  → Word "Heading 2" style
  │      ...
  │      Paragraph text → wcg_insert_paragraph(doc, text)   → Word "Normal" style
  │      **bold**       → character formatting (defer to v2 if complex)
  │      *italic*       → character formatting (defer to v2 if complex)
  │
  └─ DiagramBlock:
       1. [FFM exists?] → render freeform graph to PNG (stb)
          [No FFM?]     → render mermaid source to PNG (existing path)
       2. wcg_insert_image(doc, png_path, content_width)
       3. Optionally insert diagram name as caption below image
```

### 5.2 Heading-level support in wordcomglue

Extend `wcg_insert_heading()` to accept a level parameter (1-6) and apply the corresponding Word heading style. The existing `insertWordHeading()` helper may already do this — verify and extend if needed.

### 5.3 PDF bookmarks

Already handled: `wcg_pdf_options.create_bookmarks = WdExportCreateBookmarks_Headings` causes Word to generate PDF bookmarks from all heading-styled paragraphs. No additional work needed — headings placed by the markdown translator automatically become navigable PDF bookmarks.

### 5.4 Bold/italic text runs

For v1: defer inline formatting. Paragraphs are inserted as plain text. This is sufficient for structured documentation. Rich inline formatting can be added in a follow-up phase via `wcg_insert_formatted_text(doc, text, bold, italic)`.

**Files to modify:**
- `app/platform/windows_main.zig` — `exportDiagramToWord()` → `exportMarkdownDocumentToWord()`
- `wordcomglue/wordcomglue.h` — verify/extend heading-level API
- `wordcomglue/src/document.cpp` — Word COM heading style application

---

## Phase 6: Editor Enhancements

**Goal**: Make the Rich Edit control markdown-aware for a better editing experience.

### 6.1 Extend syntax highlighting

In `app/platform/windows/editor.zig`, extend `MermaidScanner` / `applyEditorSyntaxHighlight()`:

| Markdown element | Visual treatment |
|------------------|-----------------|
| `# Heading 1` | Bold, 20pt |
| `## Heading 2` | Bold, 16pt |
| `### Heading 3` | Bold, 14pt |
| ` ```mermaid ` / ` ``` ` fences | Gray background or distinct color |
| Mermaid source inside fences | Existing keyword/symbol coloring (unchanged) |
| `**bold**` | Bold formatting |
| `*italic*` | Italic formatting |
| Plain text | Default font, default size |

Implementation uses `EM_SETCHARFORMAT` with `CHARFORMAT2` to set font size, bold, italic per token range. All within Rich Edit control capabilities — no custom rendering needed.

### 6.2 "Jump to Diagram" from editor

When the user clicks or moves the cursor inside a ` ```mermaid ` block in the editor:
- Determine which `DiagramBlock` the cursor is within (by line number / character offset)
- Auto-select that diagram in the ComboBox selector
- Preview pane updates to show that diagram
- Enable the "Edit Diagram" button

### 6.3 Cursor position tracking

Track `EM_GETSEL` / `EN_SELCHANGE` notifications to determine which block the cursor is in:
- Map cursor offset → line number → block index (using `MarkdownDocument.blocks[i].diagram.source_line`)
- Update UI state: disable "Edit Diagram" when cursor is in a text block

**Files to modify:**
- `app/platform/windows/editor.zig` — scanner, highlighting
- `app/platform/windows_main.zig` — cursor tracking, diagram selector sync

---

## Backward Compatibility

### `.mmd` files

Existing `.mmd` files continue to work unchanged:
- When a `.mmd` file is opened, wrap its content in a synthetic `MarkdownDocument` with a single `DiagramBlock` (no `TextBlock`s)
- Diagram selector shows "Diagram 1" (or hides if single-diagram)
- All other behavior (preview, freeform edit, export) works identically through the unified pipeline
- FFM sidecars work the same way — keyed by content hash of the mermaid source

### macOS FFM format

The macOS app uses `merrow-ffm-v1` (NSPropertyList binary). The new Windows format (`merrow-ffm-v2`) is a different binary format optimized for Zig's `c_allocator`. Cross-platform FFM sharing is out of scope for v1 — each platform manages its own library.

---

## File Inventory

### New files

| File | Purpose |
|------|---------|
| `app/document_model.zig` | `MarkdownDocument`, `Block`, `TextBlock`, `DiagramBlock` structs |
| `app/markdown_parser.zig` | Markdown fence parser, content hashing, diagram name extraction |
| `deps/sqlite3.c` + `deps/sqlite3.h` | SQLite amalgamation (single-file database engine) |
| `app/library_db.zig` | SQLite wrapper: typed Zig API for FFM, recent files, preferences |
| `app/ffm_serializer.zig` | `StudioEditableGraph` BLOB serialization (read/write) |
| `src/render/editable_graph.zig` | Freeform graph → PNG software renderer (stb path) |

### Modified files

| File | Changes |
|------|---------|
| `app/platform/windows/app_state.zig` | Add `selected_diagram_index`, `MarkdownDocument` reference to app state |
| `app/platform/windows_main.zig` | Diagram selector handling, mode switch (keep editor visible), FFM load/save, export flow (markdown-driven) |
| `app/platform/windows/toolbar.zig` | Add diagram selector ComboBox to toolbar |
| `app/platform/windows/document.zig` | Extend `MerrowUserFolders` with `library` dir, add `.md` to open dialog filter |
| `build.zig` | Add `sqlite3.c` source file to studio build |
| `app/platform/windows/editor.zig` | Extend syntax highlighting for markdown (headings, fences, bold/italic) |
| `app/preview.zig` | Add FFI for `merrow_studio_render_editable_graph_png_bytes()` |
| `wordcomglue/wordcomglue.h` | Verify/extend heading-level API |

### Reference files (read, not modified)

| File | Used for |
|------|----------|
| `src/render/graph.zig` | Template for editable graph software renderer |
| `src/render/canvas.zig` | `Canvas` struct, `initWithScale()`, `saveToPNGBytes()` |
| `src/render/text.zig` | Font loading, text measurement (stb_truetype) |
| `app/platform/windows/canvas/draw.zig` | D2D shape rendering (parity reference for stb renderer) |
| `app/platform/windows/canvas/state.zig` | `CanvasState`, `StudioEditableGraph` struct reference |

---

## Verification Plan

| # | Test | Validates |
|---|------|-----------|
| 1 | Parse a `.md` with 3 mermaid blocks → verify block count, names, content hashes | Phase 1 parser |
| 2 | Parse with headings above some blocks, not others → verify name extraction + "Diagram N" fallback | Phase 1 naming |
| 3 | Same mermaid source with `\r\n` vs `\n` and varied whitespace → same content hash | Phase 1 hash stability |
| 4 | Open `.mmd` file → synthetic single-diagram `MarkdownDocument` | Backward compat |
| 5 | Serialize `StudioEditableGraph` → BLOB → INSERT → SELECT → deserialize → field equality | Phase 3 round-trip |
| 6 | Corrupt/missing `merrow.db` → recreate schema, graceful fallback to auto-layout | Phase 3 error handling |
| 6b | `db.gcFfm(active_hashes)` deletes orphaned rows, keeps active ones | Phase 3 garbage collection |
| 7 | Compare stb-rendered freeform PNG against D2D screenshot → visual equivalence check | Phase 4 render parity |
| 8 | Open multi-diagram `.md` → hand-tune one diagram → export to Word → verify: text headings present as Word headings, tuned diagram uses FFM render, untouched diagram uses mermaid render | Phase 5 integration |
| 9 | Edit mermaid source in editor → content hash changes → old FFM no longer matches → preview falls back to auto-layout | FFM preference lifecycle |
| 10 | `zig build studio` compiles cleanly on Windows after each phase | Build validation |

---

## Scope Boundaries

### In scope
- `.md` and `.mmd` file open
- Markdown fence parsing (` ```mermaid ` blocks)
- Diagram selector (ComboBox) for multi-diagram documents
- Content-hash-keyed FFM persistence in SQLite (`merrow.db`)
- Recent files tracking in SQLite
- Freeform → PNG software renderer for export
- Markdown-driven Word/PDF export (headings, paragraphs, diagrams)
- Syntax highlighting for markdown in editor
- Editor ↔ diagram selector sync (cursor tracking)

### Out of scope (future work)
- `.md` round-trip save from editor (open/import only for now)
- Images embedded in markdown (`![alt](path)`)
- Tables, blockquotes, ordered/unordered lists in markdown
- Full CommonMark spec compliance
- macOS parity (Windows-first implementation)
- Library Manager UI (browse/delete FFM entries — the SQL queries exist, just no UI)
- Cross-platform FFM/database sharing (macOS ↔ Windows)
- Bold/italic inline formatting in Word export (v2)

---

## Phase Ordering & Dependencies

```
Phase 1 (Document Model) ──→ Phase 2 (UI / Selector) ──→ Phase 5 (Word Export)
                          │                                      ↑
                          ├──→ Phase 3 (SQLite + FFM) ───────────┤
                          │                                      │
                          └──→ Phase 4 (stb Renderer) ───────────┘
                          
Phase 6 (Editor Enhancements) — independent, can be done in parallel with 3-5
```

- **Phases 1–2** deliver immediate UX value: open `.md` files, see diagrams, select between them
- **Phases 3–4** are parallelizable: SQLite/FFM persistence and software renderer are independent
- **Phase 5** depends on 1 + 4: needs the document model and freeform PNG rendering
- **Phase 6** is independent polish: can be done any time after Phase 2
