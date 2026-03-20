# Windows Freeform Canvas — Object Editing Improvements

Comprehensive review of the current canvas interaction, hit-testing, drawing,
and inspector behaviour compared to standard graphics editors (Figma, Sketch,
draw.io, OmniGraffle, Keynote).

---

## 1. Selection & Hit-testing

### 1.1 Edge/link selection is nearly impossible
**Current:** Edges are hit-tested as a thin line between source and target
*centres*. The tolerance is 5 screen-pixels. Because the line runs from the
exact centre of the source node through the body of both nodes, the clickable
segment is very short and hidden behind the nodes — it is almost impossible to
click an edge.

**Expected (every normal editor):** Edges should be selectable by clicking
anywhere on the *visible* portion of the line. The hit segment should run from
the border of the source to the border of the target (clip to node boundary),
not centre-to-centre. Increase the tolerance to 8-10 px. Highlighted/thicker
stroke on hover also helps discoverability.

**Files:** `hit_test.zig` — `hitTest()` edge loop, `findNodeCentre()`,
`pointNearSegment()`.

### 1.2 Edge selection highlight is barely visible
**Current:** A selected edge is drawn with the standard selection blue brush
at the same thickness — it looks almost the same as an unselected edge.

**Expected:** Draw the selected edge 2-3 px thicker than its stored thickness
and overlay with a translucent blue halo or outline (double-stroke). Show
small square handles at source and target endpoints.

**Files:** `draw.zig` — edge drawing block, `drawEdge()`.

### 1.3 Node hit-test uses raw bounding box regardless of shape
**Current:** All shapes (diamond, circle, hexagon…) are tested against their
axis-aligned bounding rectangle. Clicking the empty corner area of a diamond
still "hits" the node, stealing the click from whatever is behind it.

**Expected:** The hit rect for circles and diamonds should test against the
actual geometry (ellipse, rotated square). At minimum, diamonds and circles
should use inscribed-shape hit-testing.

**Files:** `hit_test.zig` — `nodeRect()`, `hitTest()` node loop.

### 1.4 Subgraph body should not steal clicks from child nodes
**Current:** Subgraphs are tested *after* nodes, so this is partly correct.
But the order depends on the arrays returned from the C FFI — there is no
guarantee that child nodes come before or after the parent subgraph in the
arrays.

**Expected:** Always test nodes first (regardless of array order), then edges,
then subgraphs — matching the visual z-order (nodes on top, subgraphs behind).

**Files:** `hit_test.zig` — test ordering.

### 1.5 No hover feedback
**Current:** The cursor changes shape over objects, but the objects themselves
do not highlight on hover.

**Expected:** On mouse-move, lightly highlight the object under the cursor
(translucent overlay or thicker outline). This gives users confidence about
what will be selected *before* they click.

**Files:** `interaction.zig` — `onMouseMove()`, `draw.zig` — add hover index
to draw state.

---

## 2. Drag / Move Behaviour

### 2.1 Move only drags the selected object — CORRECT
The current implementation moves only the selected node or subgraph, not the
entire graph. **This is correct.** Verified in `interaction.zig` →
`onMouseMove` → `.move_object`.

### 2.2 No drag threshold / click-vs-drag discrimination
**Current:** Any `WM_LBUTTONDOWN` on a node immediately starts `.move_object`
drag. Moving the mouse even 1 pixel during a click commits a position change
and sets `document_mutated = true`.

**Expected:** Do not start a move until the mouse has moved at least 3-4
screen pixels from the mouse-down point ("drag dead-zone"). Until that
threshold is crossed, treat the gesture as a potential click-only (select).
This prevents accidental micro-moves and avoids dirtying the document on every
click.

**Files:** `interaction.zig` — `onLeftButtonDown()`, `onMouseMove()`.

### 2.3 Object resize must be supported and discoverable
**Current:** The canvas has resize-handle plumbing, but resize is not called
out as a first-class editing requirement here and the interaction is not yet at
the standard expected of normal graphics editors. Users need to be able to
select an object, grab visible handles, and resize it reliably without the
gesture being confused with move or background hit-testing.

**Expected:** Selected nodes and subgraphs should expose clear resize handles
at corners and edges. Dragging a handle should resize the selected object in
place, with live redraw and live inspector updates for X/Y/W/H. Handle hit
areas should stay usable at all zoom levels, and resize should be visually and
behaviourally distinct from move.

**Files:** `hit_test.zig` — handle hit-testing, `draw.zig` — handle drawing,
`interaction.zig` — `.resize_object` drag behaviour.

### 2.4 Pan on empty-space left-click is surprising
**Current:** Left-click on empty canvas starts panning. Most editors require
either middle-mouse-button, spacebar+drag, or right-click-drag for panning.
Left-click on empty canvas should *deselect* without panning.

**Expected:** Left-click on background: deselect only. Add panning on
middle-mouse-button-drag or Ctrl+left-drag (or space+drag). Keep right-click
for context menu.

**Files:** `interaction.zig` — `onLeftButtonDown()` → `.none` branch.
`canvasWindowProc` — add `WM_MBUTTONDOWN`/`WM_MBUTTONUP`.

### 2.5 Drag does not update the inspector live
**Current:** While dragging a node, only `needs_redraw` and
`document_mutated` are set. The inspector X/Y fields are not refreshed during
the drag.

**Expected:** During a move or resize drag, refresh the inspector position and
size fields continuously so the user sees live numeric feedback.

**Files:** `interaction.zig` — `onMouseMove()` `.move_object` /
`.resize_object` should set `selection_changed = true`.
`windows_main.zig` — `WM_MOUSEMOVE` handler already checks
`result.selection_changed`.

---

## 3. Drawing & Visual Feedback

### 3.1 Diamond shape has no fill
**Current:** The diamond case in `drawNodeShape` uses four `DrawLine` calls
but never calls `FillPolygon` or equivalent. Diamonds are always hollow.

**Expected:** Fill the diamond with the node's fill colour, then stroke the
outline. Requires building a path geometry (ID2D1PathGeometry) or using four
triangles.

**Files:** `draw.zig` — `drawNodeShape()` → `.diamond`.

### 3.2 Dashed / dotted line styles are not rendered
**Current:** `StudioEditableEdge.line_style` (0=solid, 1=dashed, 2=dotted) is
stored but `drawEdge()` always uses `null` for the stroke style parameter —
every edge draws as solid.

**Expected:** Create `ID2D1StrokeStyle` objects for dashed and dotted, pass
them as the last parameter to `DrawLine`. Cache the stroke styles (they are
device-independent and reusable).

**Files:** `draw.zig` — `drawEdge()`, `drawCanvas()` — create stroke styles
via factory, `windows_main.zig` — `ensureCanvasD2DFactory()`.

### 3.3 Source-arrow is not rendered
**Current:** Only the target arrow tip is drawn (`has_arrow`). The source
arrow (`has_source_arrow`) is ignored.

**Expected:** If `has_source_arrow != 0`, draw an identical arrow tip at the
source end pointing away from the target.

**Files:** `draw.zig` — `drawEdge()`, `drawArrowTip()`.

### 3.4 Edge labels are not drawn
**Current:** `StudioEditableEdge.label` is stored and shown in the inspector,
but the edge drawing code never renders the label text on the canvas.

**Expected:** Draw the edge label at the midpoint of the visible edge segment,
with a small white background rectangle behind it (standard for graph editors).

**Files:** `draw.zig` — `drawEdge()`.

### 3.5 Selection outline is behind the object
**Current:** The selection outline is drawn as part of the same pass as the
object. Because the outline is slightly expanded, it can be covered by
adjacent overlapping objects.

**Expected:** Draw all objects first, then draw all selection outlines and
handles in a final pass so they are always fully visible on top.

**Files:** `draw.zig` — `drawCanvas()`.

### 3.6 No grid or snap-to-grid
**Expected (low priority):** Option to show a dot/line grid and snap objects
to grid increments during drag.

---

## 4. Inspector Panel

### 4.1 Colour buttons show hex text instead of a colour swatch
**Current:** Fill/Stroke/Color buttons display "#RRGGBB" as button text. The
user has no visual preview of the actual colour.

**Expected:** Owner-draw or subclass the buttons to paint a solid colour
swatch rectangle inside the button. Display the hex text next to (or below)
the swatch.  An immediate approach: use `WM_CTLCOLORBTN` or owner-draw
(`BS_OWNERDRAW` + `WM_DRAWITEM`) to fill the button face, or simply create a
small `STATIC` control with a coloured background brush next to each button.

**Files:** `inspector.zig` — `mkButton()`, `setColorButtonText()`,
`inspectorWndProc`.

### 4.2 Border / thickness fields should use a trackbar (slider)
**Current:** Border width and edge thickness are plain text EDIT controls. The
user must type a number and tab out.

**Expected:** Replace each with a Win32 `TRACKBAR_CLASS` (slider) control that
runs from 0.5 to 10.0 (or similar). Show the current value as a small label
next to the slider. The slider should commit changes in real time on
`WM_HSCROLL`, not just on focus-loss.

**Files:** `inspector.zig` — replace `mkEdit` calls for border/thickness with
trackbar creation. Add `WM_HSCROLL` handling in `inspectorWndProc`.

### 4.3 Inspector does not scroll
**Current:** If the panel is shorter than the sum of its controls there is no
scrollbar — controls are clipped.

**Expected:** Add `WS_VSCROLL` and handle `WM_VSCROLL` / mouse-wheel on the
panel to scroll the inspector contents when the window is too small.

**Files:** `inspector.zig` — panel creation style, `inspectorWndProc`.

### 4.4 Inspector should show the selected object's label prominently
**Current:** The header says "Node" or "Edge". In every real editor the header
shows the *name* of the selected object, e.g. "Node: Start" or
"Edge: Start → Step".

**Expected:** Format the header as `"Node: <label>"` (truncated if needed).

**Files:** `inspector.zig` — `refresh()`.

### 4.5 Label fields are read-only but should be editable
**Current:** `edt_ns_label` and `edt_e_label` are created with `ES_READONLY`.
The user cannot change the label from the inspector.

**Expected:** Make them editable. On `EN_KILLFOCUS` (or `EN_CHANGE` with
debounce), write the new text back to the graph struct's label field. This
requires allocating a new C string and updating the `[*c]const u8` pointer.

**Files:** `inspector.zig` — `mkEdit(..., true)` → `false`, add commit
handler. `state.zig` — may need a label-update helper that allocates.

---

## 5. Keyboard & Shortcuts

### 5.1 Escape only cancels insertion or clears selection
**Current behaviour is fine** as a baseline but additional common shortcuts are
missing.

### 5.2 Missing standard shortcuts
| Shortcut | Expected action |
|---|---|
| Ctrl+A | Select all objects |
| Ctrl+Z / Ctrl+Y | Undo / Redo (requires snapshot stack) |
| Arrow keys | Nudge selected object by 1 px (10 px with Shift) |
| Delete / Backspace | Delete selected object (currently sets flags but does not actually remove) |
| Ctrl+D | Duplicate selected object |
| Ctrl+0 | Zoom to fit |
| Ctrl+= / Ctrl+- | Zoom in / out |

**Files:** `interaction.zig` — `onKeyDown()`, `windows_main.zig` —
`canvasWindowProc` → `WM_KEYDOWN`.

### 5.3 Delete doesn't actually delete
**Current:** `onKeyDown(VK_DELETE)` sets `document_mutated` and
`selection_changed` but does NOT remove the object from the graph arrays. The
caller in `canvasWindowProc` does nothing with the flag either.

**Expected:** Call an FFI deletion function (or implement array removal) to
actually remove the selected node/edge/subgraph, then clear selection and
redraw.

**Files:** `interaction.zig` — `onKeyDown()`, `windows_main.zig` —
`WM_KEYDOWN` handler.

---

## 6. Zoom & Scroll

### 6.1 Zoom is too slow
**Current:** 10% per wheel notch (factor 1.1).

**Expected:** Use 15-20% per notch and smooth it with an eased animation (or
at least 1.15 for snappier feel).

**Files:** `interaction.zig` — `onMouseWheel()`.

### 6.2 No zoom indicator or zoom-level display
**Expected:** Show the current zoom percentage in the status bar or a small
overlay label on the canvas (e.g. "125%").

**Files:** `windows_main.zig` — status bar update after zoom.

---

## 7. Right-click Context Menu

### 7.1 No context menu
**Current:** Right-click performs selection-only (same as left-click but
without drag initiation).

**Expected:** Show a `TrackPopupMenu` with contextual items:
- On node/subgraph: Edit Label, Change Shape, Duplicate, Delete, Bring to
  Front / Send to Back.
- On edge: Edit Label, Reverse Direction, Delete.
- On background: Paste, Add Node, Add Subgraph, Fit Canvas.

**Files:** `interaction.zig` — `onRightButtonDown()`,
`windows_main.zig` — `WM_RBUTTONDOWN`.

---

## 8. Edge Routing

### 8.1 Edges are straight centre-to-centre lines that go through nodes
**Current:** Edges are drawn as a single `DrawLine` from source centre to
target centre. They pass through the bodies of both nodes.

**Expected:** Clip the endpoints to the node boundaries. For a rectangle, find
the intersection of the centre-to-centre line with the node's bounding rect
and start/end the visible line there. This keeps arrows pointing at edges of
nodes rather than hidden inside them.

**Files:** `draw.zig` — `drawEdge()`, new helper
`clipLineToRect(cx, cy, rect, target_x, target_y) → (clipped_x, clipped_y)`.

---

## 9. Summary — Priority Order

| # | Item | Impact | Effort |
|---|------|--------|--------|
| 1 | Drag dead-zone (2.2) | High — prevents accidental moves | Small |
| 2 | Edge hit-test from border not centre (1.1) | High — edges unselectable | Medium |
| 3 | Edge endpoint clipping to node boundary (8.1) | High — visual | Medium |
| 4 | Diamond fill (3.1) | Medium — visual bug | Small |
| 5 | Dashed/dotted stroke styles (3.2) | Medium — feature | Medium |
| 6 | Source arrow (3.3) | Medium — feature | Small |
| 7 | Edge labels on canvas (3.4) | Medium — feature | Small |
| 8 | Selection outline drawn last (3.5) | Medium — visual | Small |
| 9 | Left-click-pan → middle-button-pan (2.3) | Medium — UX | Small |
| 10 | Colour swatch buttons (4.1) | Medium — UX | Medium |
| 11 | Slider for border/thickness (4.2) | Medium — UX | Medium |
| 12 | Header shows object name (4.4) | Low — UX | Tiny |
| 13 | Editable labels in inspector (4.5) | Medium — feature gap | Medium |
| 14 | Selected edge thicker highlight + handles (1.2) | Medium — UX | Small |
| 15 | Live inspector update during drag (2.4) | Low — UX | Tiny |
| 16 | Hover highlight (1.5) | Low — UX | Medium |
| 17 | Shape-aware hit-test (1.3) | Low — correctness | Medium |
| 18 | Arrow-key nudge (5.2) | Low — convenience | Small |
| 19 | Context menu (7.1) | Low — expected feature | Medium |
| 20 | Actual delete (5.3) | Medium — feature gap | Medium |
| 21 | Zoom speed (6.1) | Low — UX | Tiny |
| 22 | Zoom indicator (6.2) | Low — UX | Tiny |
| 23 | Inspector scroll (4.3) | Low — robustness | Small |
| 24 | Snap to grid (3.6) | Low — optional | Large |
| 25 | Undo/Redo (5.2) | High — expected | Large |
