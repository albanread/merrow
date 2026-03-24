# Markdown as Document Container — Implementation Plan

## Vision

A `.md` file is the primary document unit. It contains prose sections and
one or more embedded Mermaid diagrams.  The app treats it as a rich document:
you can edit prose, author and enhance diagrams visually, then export to Word
or PDF with prose and diagrams rendered together in the correct positions.

The architecture already has most of the scaffolding. This plan fills the
gaps in three ordered phases.

---

## What Already Exists

| Area | Status |
|---|---|
| `markdown_parser.zig` — `TextBlock` / `DiagramBlock` with byte offsets | Done |
| `document_model.zig` — `MarkdownDocument` owner | Done |
| `replaceSelectedDiagramSource()` — surgical splice-back | Done |
| Multi-diagram selector + caret-sync | Done |
| RichEdit editor with markdown-aware syntax highlighting | Done |
| FFM sidecar for persisted layout | Done |
| Word export (text blocks → headings/paragraphs, diagrams → SVG/PNG) | Done |
| Canvas editable graph D2D rendering + interaction | Done |

---

## Phase 1 — Robust Diagram Editing Inside Markdown

**Goal:** Canvas edits round-trip cleanly back into the `.md` source without
losing surrounding prose or causing rebuild loops.

### 1.1 — Write-back on Canvas Mutation

Currently `onEditableGraphMutated()` saves the FFM sidecar but does **not**
write the updated diagram annotation source back into the markdown file.

**Required:**
- Add `serializeAnnotationSource(graph) []u8` (already partially in
  `mermaid_serializer.zig`) that emits the canonical `%% @`-annotated
  Mermaid source reflecting current node positions, sizes, and styles.
- After every canvas mutation call `replaceSelectedDiagramSource(new_source)`.
- Guard against infinite rebuild loops: introduce an `edit_origin` tag
  (`canvas` | `editor`) on `updateEditorDerivedState`.  When origin is
  `canvas`, skip re-building the editable graph (the graph is already
  current); only re-parse for syntax errors and caret sync.

### 1.2 — Debounce Write-Back

Canvas mutations fire many times per drag. Write-back must be debounced.

**Design:**
- Add a `canvas_writeback_pending: bool` flag and a 400 ms `SetTimer` on the
  canvas HWND.
- `WM_TIMER` flushes pending write-back: serialize → splice → save file to
  disk atomically (write temp, rename).
- Cancel and restart the timer on every new mutation.

### 1.3 — Annotation Round-Trip Validation

The `%% @pos x=... y=...` annotation system already exists in the parser.
Ensure node IDs survive a full round-trip edit:

1. Canvas drag → annotation written to source.
2. Source reparsed → FFM sidecar updated.
3. Reopen file → positions restored from annotations (today it uses FFM;
   annotations should be the primary, FFM the cache).

Priority: annotations win if both exist and differ.

### 1.4 — Multi-Diagram Coexistence

When a multi-diagram document is open:
- Each diagram has its own FFM sidecar key (`filename.md#0`, `#1`, …).
- Switching diagrams via the selector persists the outgoing diagram's
  annotation source before loading the incoming one.
- The editor highlights the selected diagram's fence block with a stronger
  background tint.

---

## Phase 2 — Prose Editing Inside the Application

**Goal:** The user edits prose directly in the app instead of an external
text editor, with a readable formatted preview.

### 2.1 — Split Editor Modes

Add a mode toggle (`View > Source` / `View > Document`) to the toolbar.

**Source mode (current):** RichEdit shows raw markdown source with syntax
highlighting.  This is unchanged.

**Document mode:** A read/edit surface that renders prose as formatted text
(headings styled, paragraphs readable) with diagram thumbnails in-line.

### 2.2 — Document Mode Rendering

Options (in order of pragmatism):

**Option A — Enhanced RichEdit (recommended for Phase 2)**

RichEdit already supports styled paragraphs, font sizes, bold, italic, and
embedded OLE objects.  Extend `editor.zig`:

- On entering Document mode, parse the `MarkdownDocument` blocks.
- Render `TextBlock` content using RichEdit paragraph styles:
  - `# Heading` → CHARFORMAT2 with larger bold font.
  - `## Heading` → medium bold.
  - Plain paragraphs → normal body font.
  - `**bold**`, `*italic*` → inline CHARFORMAT.
- Render `DiagramBlock` as an embedded bitmap (OLE picture object) showing
  the current diagram PNG at the correct size.
- The RichEdit control becomes read/write for prose; diagram areas are
  click-through locked (tab stop skipped) — double-click activates the
  canvas editor for that diagram.
- A `WM_SETTEXT` round-trip converts edited prose back to Markdown when
  leaving Document mode.

**Option B — Separate WebView2 pane (deferred)**

Embed a Chromium WebView2 panel rendering markdown to HTML for read-only
preview.  Heavier dependency; defer until Option A limitations are hit.

### 2.3 — Inline Diagram Thumbnail Click

In Document mode, clicking a diagram thumbnail:
1. Sets `selected_diagram_index` to that diagram.
2. Switches layout to show the canvas for that diagram (existing layout code).
3. Restores Source mode automatically so the user sees the diagram editor.

Double-clicking a thumbnail enters a full-screen canvas edit mode.

### 2.4 — Prose Markdown Write-Back

When Document mode is exited or the document saved, the styled RichEdit
content is serialised back to Markdown source:

- Headings → `#`, `##`, `###` prefix.
- Bold → `**...**`, italic → `*...*`.
- Diagram thumbnails → preserved as the original fenced Mermaid blocks
  (diagrams are never re-encoded from the thumbnail).
- Paragraph breaks → blank lines.

---

## Phase 3 — Word / PDF Export with Prose + Diagrams

**Goal:** `File > Export > Word Document` produces a `.docx` (and optionally
`.pdf`) that exactly mirrors the document structure: prose in correct
heading/body styles, diagrams placed at the correct positions, matching the
sizes configured in the canvas.

### 3.1 — Improve Existing Word Export

The export pipeline in `windows_main.zig → exportMarkdownDocumentToWord()` is
already block-aware.  Tighten it:

- **Heading levels:** Pass the `#` count (1-3) to WordComGlue so the correct
  built-in Word style (`Heading 1`, `Heading 2`, `Heading 3`) is applied.
  Currently headings are treated as bold paragraphs.
- **Paragraph styles:** Normal body paragraphs → `Normal` style.  Preserve
  blank-line paragraph spacing (currently may collapse).
- **Inline formatting:** Parse `**bold**` and `*italic*` in text blocks and
  emit the correct WordComGlue character formatting calls.
- **Bullet lists:** Detect leading `- ` or `* ` on prose lines → `List
  Bullet` Word style.
- **Code spans:** `\`inline code\`` → Courier New / monospace character style.

### 3.2 — Diagram Sizing in Export

Each canvas diagram has a physical size (`canvas_width_cm × canvas_height_cm`
from `ProjectFontSettings`).  Export must honour it:

- Compute the image width/height to insert in cm using the project settings.
- Pass the dimensions to `api.insert_image(path, width_cm, height_cm)` in
  WordComGlue so Word does not auto-resize.
- The SVG export path (`renderEditableGraphToExportSvg`) already produces a
  vector output; prefer it over PNG for Word so the diagram is crisp at any
  zoom.

### 3.3 — Diagram Captions

If a `DiagramBlock.name` is present (derived from the `# Heading` immediately
before the fence), insert it as a Word `Caption` style paragraph after the
diagram image.

### 3.4 — Table of Contents Hook

After all content is inserted, if the document has any Heading 1/2 blocks,
call `api.update_toc()` (a new WordComGlue method) so Word refreshes the TOC
field if one was already present in the template.

### 3.5 — PDF Export

After Word DOCX is saved, call `api.save_as_pdf(pdf_path)` (already plumbed
in the existing export code) to produce a PDF of the same layout.  Surface
this as a separate `File > Export > PDF` menu item.

### 3.6 — Template Support

Allow the user to choose a `.dotx` Word template via a file dialog.  The
template controls fonts, margins, header/footer, and style definitions.
WordComGlue opens the new document from the template before inserting content.

---

## Supporting Infrastructure

### Markdown Parser Enhancements

- **Inline formatting tokens:** Extend `parseSourceDocument()` to extract
  `InlineSpan` list per `TextBlock`: bold, italic, code, plain text with
  start/end byte offsets.  Used by both Document mode rendering and Word
  export.
- **Fenced code blocks (non-mermaid):** Treat `\`\`\`zig`, `\`\`\`python`, etc. as
  `CodeBlock` rather than `TextBlock`, so they export with monospace style.
- **Link support:** Detect `[text](url)` spans for export as Word hyperlinks.

### WordComGlue C++ DLL Additions

Additions needed in `wordcomglue/` (C++ COM automation):

| New API | Purpose |
|---|---|
| `insert_heading(text, level)` | Apply `Heading 1`/`2`/`3` built-in style |
| `insert_image_sized(path, w_cm, h_cm)` | Insert image at exact physical size |
| `insert_caption(text)` | `Caption` style paragraph after image |
| `insert_hyperlink(text, url)` | Inline hyperlink |
| `insert_bullet(text)` | `List Bullet` paragraph |
| `insert_code(text)` | Monospace inline or block |
| `save_as_pdf(path)` | Word's `ExportAsFixedFormat` |
| `open_from_template(dotx_path)` | Open new doc from .dotx |
| `update_toc()` | `ActiveDocument.Fields.Update` |
| `apply_character_bold(range)` | CHARFORMAT bold over a range |
| `apply_character_italic(range)` | CHARFORMAT italic |

### Zig-Side Dispatcher

In `windows_main.zig`, replace the current monolithic
`exportMarkdownTextBlockToWord()` with a block renderer that:

1. Walks `TextBlock.inline_spans[]` in order.
2. Dispatches each span to the appropriate WordComGlue call.
3. Handles mixed bold/italic/plain within a single paragraph without
   starting a new Word paragraph for each span.

---

## Sequencing

```
Phase 1.1 — Canvas write-back to MD source         (highest value, unblocks everything)
Phase 1.2 — Debounce + atomic save
Phase 1.3 — Annotation primacy over FFM
Phase 1.4 — Multi-diagram sidecar keys

Phase 3.1 — Heading / paragraph styles in Word     (export is closest to done)
Phase 3.2 — Diagram sizing
Phase 3.3 — Captions
Phase 3.5 — PDF menu item

Parser — Inline formatting spans                   (enables both Phase 2 and Phase 3)

Phase 2.1 — Source/Document mode toggle
Phase 2.2 — Enhanced RichEdit document view
Phase 2.3 — Diagram thumbnail click
Phase 2.4 — Prose write-back

Phase 3.4 — TOC update
Phase 3.6 — Template support
```

---

## Key Design Constraints

- **Source of truth is always the `.md` file on disk.**  The FFM sidecar and
  in-memory `CanvasState` are caches derived from it.  Any write-back
  operation writes the `.md` file first, then updates UI.
- **No new rendering engine dependency** until Option A (RichEdit) is
  exhausted.  WebView2 is a fallback for Document mode only.
- **WordComGlue stays in C++** (COM automation from Zig is impractical).  The
  Zig side prepares data and calls the DLL; WordComGlue performs all Word
  interactions.
- **Diagram identity is stable.**  A diagram is identified by its ordinal
  position within the file (`#0`, `#1`, …).  Renaming a heading does not
  change the identity.
- **No destructive merge.** When writing annotation updates back to source,
  only the lines within the fenced block change.  Prose above and below is
  never touched.
