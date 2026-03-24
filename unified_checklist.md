# Unified Hybrid Diagram Editor — Implementation Checklist

Refers to [unified_view.md](unified_view.md) for full plan details.

## Phase 1: Collapse dual-view, redefine state, refactor layout

### Step 1 — Collapse dual-view into one canvas surface
- [x] Remove `AppMode` enum (`mermaid` vs `freeform`) from `app_state.zig`
- [x] Replace `AppMode` with a unified `UIState` that tracks: canvas always-on, source pane visible/hidden, inspector mode
- [x] Remove `switchToMode()` in `windows_main.zig`; replace callers with source/inspector toggle helpers
- [x] Remove `applyModeVisibility()` toggling between preview and canvas windows
- [x] Retire `PreviewRenderer` (PNG preview surface) from the active editor flow; keep only for export
- [x] Ensure canvas (`CanvasRenderer` / D2D) is always created and visible
- [x] Update menu items that reference "Mermaid mode" / "Freeform mode" to reflect the unified model

### Step 2 — Redefine top-level UI state
- [x] Define new state fields: `source_pane_visible`, `inspector_visible`, `interaction_state`
- [x] Preserve diagram selection and source diagnostics across pane toggles
- [x] Remove assumptions that inspector only exists in freeform mode
- [x] Wire keyboard shortcut / menu toggle for source pane visibility
- [x] Wire keyboard shortcut / menu toggle for inspector visibility

### Step 3 — Refactor layout and visibility
- [x] Rework `layoutChildWindows()` in `layout.zig` to always place the canvas
- [x] Add collapsible source pane (left or bottom) to layout
- [x] Keep inspector pane on the right, collapsible
- [x] Ensure canvas gets dominant space (not three-equal-pane)
- [x] Verify resize, maximize, and restore behavior with new layout
- [x] Verify source pane toggle does not break canvas or inspector

## Phase 2: Unify rebuild pipeline and hybrid sync

### Step 4 — Unify rebuild pipeline
- [x] Source edits always rebuild `StudioEditableGraph` via `buildEditableGraph`
- [x] Remove PNG preview render path from source-edit response
- [x] Update `updateEditorDerivedState()` to always feed canvas, not preview
- [x] Refresh diagnostics and syntax highlighting after rebuild
- [ ] Preserve selection across source-driven rebuilds when possible

### Step 5 — Graph-to-source writeback
- [ ] On canvas mutation, serialize graph via `mermaid_serializer.zig`
- [ ] Replace only the selected diagram block in source using `document_model.zig` block boundaries
- [ ] Update RichEdit content without losing cursor/scroll position
- [ ] Add short debounce for rapid graph edits (drag sequences)

### Step 6 — Sync guards to prevent feedback loops
- [ ] Add change-origin tag enum: `source_edit`, `graph_mutation`, `selection_only`, `project_change`
- [ ] Track document version / generation counter
- [ ] Source-triggered rebuild must not immediately write source back
- [ ] Graph-triggered source rewrite must not recursively rebuild
- [ ] Test: rapid alternating source and graph edits do not cause infinite loops

## Phase 3: Inspector and selection integration

### Step 7 — Redesign inspector for unified canvas+source
- [ ] Inspector always available in right pane (not gated by mode)
- [ ] No selection → show compact project-level controls
- [ ] Node/edge/subgraph selected → expand into selection inspector
- [ ] Source pane visibility does not hide the inspector

### Step 8 — Selection-to-source awareness
- [ ] Canvas selection highlights corresponding annotated source lines in RichEdit
- [ ] Source pane remains editable during selection highlight
- [ ] Do not force focus away from source editor on selection
- [ ] Use annotation comments (`%% @shape=`, `%% @edge`) as stable anchors

### Step 9 — Persistence boundaries
- [ ] Mermaid source with annotations becomes canonical editor state
- [ ] FFM persistence becomes recovery/performance cache only
- [ ] FFM must not silently diverge from annotated source
- [ ] Save/load flows operate on source, not FFM

## Phase 4: Cleanup and validation

### Step 10 — Remove obsolete preview-only code
- [ ] Delete or retire `PreviewRenderer` PNG rendering from editor surface
- [ ] Remove mode-switch menu semantics
- [ ] Remove layout branches that only support old split-view
- [ ] Keep PNG export paths for Word/image export

### Step 11 — Validation and testing
- [ ] Automated: annotated Mermaid round-trip (graph → source → graph)
- [ ] Automated: graph mutation writeback replaces correct diagram block
- [ ] Automated: sync guard prevents recursive rebuilds
- [ ] Manual: source typing updates canvas after debounce
- [ ] Manual: drag/style-edit updates source with annotations
- [ ] Manual: selection keeps inspector visible with source pane open
- [ ] Manual: resize/maximize/toggle source pane — stable layout
- [ ] Manual: Word export, Mermaid export, open/save flows work correctly
