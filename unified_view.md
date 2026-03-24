## Plan: Unified Hybrid Diagram Editor

Replace the current split preview/canvas model with a single editable diagram canvas backed by a hybrid source+graph synchronization loop. The canvas becomes the only visual diagram surface, Mermaid source remains visible on demand, and graph edits serialize back into annotated Mermaid so source and selection-based inspection stay in sync.

**Steps**
1. Phase 1: Collapse the dual-view architecture into one visual diagram surface.
   Use the existing canvas window as the only diagram viewport and retire the separate preview window path from the active UI flow. This means refactoring mode/layout logic so the app no longer switches between a PNG preview surface and an editable graph surface.
   Depends on: none.
2. Phase 1: Redefine top-level UI state away from mermaid-vs-freeform rendering modes.
   Replace the current AppMode split with state that expresses presentation choices instead: diagram canvas always present, source pane visible/hidden, inspector mode, and interaction state. Preserve diagram selection and source diagnostics, but remove assumptions that inspector only exists in freeform mode.
   Depends on: 1.
3. Phase 1: Refactor layout and visibility management to support a unified editor shell.
   Rework layout so it always places the canvas plus the optional source pane and inspector pane. Recommended default: center canvas, optional source pane on the left or bottom, inspector on the right. Avoid a three-equal-pane layout because it will starve the canvas; prefer a dominant canvas with collapsible side panes.
   Depends on: 1, 2.
4. Phase 2: Unify the rebuild pipeline around editable graph generation.
   Source edits should rebuild a fresh StudioEditableGraph using the existing buildEditableGraph path, update selection if possible, refresh the canvas, and refresh diagnostics/highlighting. This replaces the current split where Mermaid mode renders PNG previews while freeform mode builds editable graphs.
   Depends on: 1, 2.
5. Phase 2: Make graph edits serialize back into Mermaid source with annotations.
   Extend the existing graph-change callbacks so any canvas mutation serializes the active editable graph via the Mermaid serializer/export path and replaces only the selected diagram block in the source document. This is the core hybrid behavior: graph edits annotate and update the source immediately or on a short debounce.
   Depends on: 4.
6. Phase 2: Prevent feedback loops between source-driven rebuilds and graph-driven source updates.
   Introduce explicit synchronization guards and document version tracking so a source-triggered graph rebuild does not immediately write the same source back, and a graph-triggered source rewrite does not recursively rebuild twice. This should include change-origin tagging such as source edit, graph mutation, selection-only change, and project-style change.
   Depends on: 4, 5.
7. Phase 3: Redesign inspector behavior for unified canvas+source editing.
   Recommended approach: keep the inspector in a right-hand pane, always available but adaptive. With no selection, show compact project-level controls. With a node/edge/subgraph selected, expand into selection inspector. Source visibility should not hide the inspector; instead the source pane is independently toggled. This avoids overloading selection to replace the code view.
   Depends on: 3.
8. Phase 3: Connect selection to source awareness without making source editing modal.
   When the user selects a graph element, keep the inspector live and optionally highlight or reveal the nearest corresponding annotated source lines in the RichEdit pane. The source pane remains editable. Do not force focus away from the source editor unless the user explicitly interacts with inspector fields.
   Depends on: 5, 7.
9. Phase 3: Decide persistence boundaries for temporary graph state versus canonical source state.
   Reassess FFM persistence so it becomes either a recovery cache or a performance cache rather than a separate competing source of truth. In the unified hybrid model, Mermaid source plus annotations should be canonical; FFM should not silently diverge.
   Depends on: 5, 6.
10. Phase 4: Remove obsolete preview-only code paths after parity is reached.
   Delete or retire PreviewRenderer-driven PNG rendering from the normal editor surface, mode-switch menu semantics, and layout branches that only exist to support the old split-view architecture. Keep export rendering paths that still need PNG output for Word or image export.
   Depends on: 4, 5, 6, 7.
11. Phase 4: Tighten validation and UX around hybrid synchronization.
   Add tests for source-to-graph rebuild, graph-to-source annotation writeback, idempotent round-tripping, multi-diagram documents, selection retention, and dirty-state behavior. Manual validation should cover typing in source, dragging nodes, editing styles in the inspector, toggling the source pane, resizing the window, and exporting to Mermaid/Word.
   Depends on: 5, 6, 7, 8, 9, 10.

**Relevant files**
- c:\projects\zig\merrow\app\platform\windows_main.zig — main integration point for mode switching, layout orchestration, editor refresh, freeform rebuilds, inspector visibility, graph-change callbacks, and the future unified sync controller.
- c:\projects\zig\merrow\app\platform\windows\layout.zig — current preview/editor/canvas layout split; should be redesigned around a single canvas plus optional panes.
- c:\projects\zig\merrow\app\platform\windows\app_state.zig — AppMode, PreviewRenderer, CanvasRenderer, and child window state; likely needs a new unified UI-state model.
- c:\projects\zig\merrow\app\platform\windows\editor.zig — RichEdit ownership, syntax highlighting, diagnostics, and any future source reveal/highlight integration from canvas selection.
- c:\projects\zig\merrow\app\platform\windows\canvas\inspector.zig — selection inspector UI, project/font inspector state, callbacks, and the right-pane behavior that must coexist with the source pane.
- c:\projects\zig\merrow\app\platform\windows\canvas\state.zig — selection model, viewport, graph ownership, and graph mutation state that must participate in synchronization.
- c:\projects\zig\merrow\app\platform\windows\canvas\interaction.zig — mutation and selection event sources that should emit graph-changed versus selection-only change origins.
- c:\projects\zig\merrow\app\mermaid_serializer.zig — canonical annotated Mermaid serialization for graph-to-source writeback.
- c:\projects\zig\merrow\app\mermaid_export.zig — export-oriented canonicalization patterns that can inform graph-to-source writeback.
- c:\projects\zig\merrow\app\preview.zig — editable graph build entrypoints and annotation-aware rebuild behavior reused by the unified canvas pipeline.
- c:\projects\zig\merrow\app\ffm_serializer.zig — current persisted graph blob handling; should be narrowed so it no longer competes with annotated source as the canonical representation.
- c:\projects\zig\merrow\app\document_model.zig — diagram block boundaries needed to replace only the selected Mermaid block during graph-driven source updates.
- c:\projects\zig\merrow\app\markdown_parser.zig — source parsing flow used during source-to-graph rebuild.

**Verification**
1. Automated: add tests proving annotated Mermaid generated from a graph can rebuild the same editable graph, including node, edge, subgraph, direction, and style preservation.
2. Automated: add tests for graph mutation writeback replacing only the selected diagram block in a multi-diagram markdown document.
3. Automated: add tests for sync guard behavior so graph-to-source updates do not recursively retrigger redundant rebuilds.
4. Manual: type Mermaid in the source pane and confirm the unified canvas updates after debounce, preserves diagnostics, and does not flicker or reset selection unnecessarily.
5. Manual: drag or style-edit a node in the unified canvas, confirm the source pane updates with annotation comments, and verify undo/dirty-state expectations.
6. Manual: select a node/edge/subgraph with the source pane open and confirm the inspector remains visible and the source pane stays editable.
7. Manual: resize, maximize, toggle the source pane, and confirm the unified canvas layout remains stable and the inspector does not overlap or disappear incorrectly.
8. Manual: verify Word export, Mermaid export, and recent-file/open/save flows still operate on the synchronized diagram state.

**Decisions**
- Hybrid model is in scope: source edits rebuild the graph, and graph edits write annotated Mermaid back into the source.
- Recommended UI model: one canvas viewport, independently toggleable source pane, persistent right-hand inspector.
- Recommended inspector behavior: compact project inspector when nothing is selected; expand into selection inspector on node/edge/subgraph selection.
- Mermaid source with annotations should become canonical for editor state. FFM persistence should be treated as cache/recovery, not a competing source of truth.
- Out of scope for the first consolidation pass: full collaborative conflict resolution between simultaneous source and graph edits from separate windows/processes.

**Further Considerations**
1. Source pane placement recommendation: bottom drawer is usually stronger than left-right split for preserving canvas width. If source literacy is central to the product, a toggleable side pane is acceptable, but a permanent three-column layout is the weakest option.
2. Undo model recommendation: keep source-editor undo as canonical first, and initially treat graph edits as source rewrites that enter the source undo stack. A custom unified undo stack can come later if needed.
3. Selection-to-source mapping should target annotated element comments rather than raw Mermaid syntax heuristics whenever possible, because the annotations give you stable anchors for reveal/highlight behavior.