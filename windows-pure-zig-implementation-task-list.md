# Windows Pure Zig Studio Implementation Task List

## Goal

Build a Windows-native `merrow-studio` app in pure Zig that is equivalent to the current macOS studio app where it matters: split-pane document UI, live Mermaid editing, diagram preview, command application, freeform canvas mode, and PNG or SVG export.

## Current Baseline

1. The shared Zig core already exists.
   - `app/preview.zig` exports the scene-building, editable-graph, syntax-check, export, command, and shuffle entry points.
   - `app/commands.zig` already owns Mermaid command application logic.
   - `src/` already owns parsing, layout, and render backends.
2. The macOS app is a thin native shell over that Zig core.
   - `app/main.zig` is already platform-agnostic and calls an extern `merrow_studio_main(...)`.
   - `app/platform/macos_app.m` owns the native window, editor, menus, status UI, mode switching, and command wiring.
   - `app/platform/merrow_freeform_canvas.m` owns the editable canvas, selection model, inspector-facing mutations, serialization, and canvas export.
3. The current macOS app is more advanced than the older design notes imply.
   - It uses a native `NSTextView` editor, not a custom Metal editor.
   - It supports Mermaid source mode and freeform canvas mode.
   - It already has command application, diagram shuffle, editable graph loading, and canvas serialization hooks.
4. The current docs disagree on Windows direction.
   - `windows-port-plan.md` and `ultimate-recommendation.md` prefer a C++ shim.
   - `zig-pure-windows-plan.md` and `windows-next-steps.md` prefer a pure Zig Win32 plus Direct2D path.
   - The implementation plan below follows the pure Zig path.

## Scope Decision

1. Use pure Zig plus `zigwin32` for Win32, Direct2D, DirectWrite, and common controls.
2. Preserve the existing architecture split.
   - Zig core stays in `app/preview.zig`, `app/commands.zig`, and `src/`.
   - Windows UI lives in Zig platform files under `app/platform/`.
3. Match the current mac app, not the earlier Metal-first design notes.
4. Defer PDF export unless a clean Windows-native vector path is chosen.

## Refactor Note

1. The current Windows shell has grown beyond what should stay in one file.
2. Use `windows-studio-refactor-plan.md` as the file-splitting plan for breaking `app/platform/windows_main.zig` into component modules under `app/platform/windows/`.

## Task List

## Phase 0: Freeze the Real Windows Target

1. Write down the parity target against the current mac app.
   - Include: split-pane window, source editor, live syntax feedback, status line, command box, shuffle action, Mermaid preview, freeform canvas mode, PNG export, SVG export, file open and save.
   - Explicitly mark PDF export and background job cancellation as follow-up work if they are not ready on Windows V1.
2. Reconcile the stale docs.
   - Update the Windows plan docs so they stop mixing the C++ shim path with the pure Zig path.
   - Update the mac app notes so they reflect the current AppKit plus `NSTextView` implementation instead of the earlier Metal-heavy direction.
3. Decide the Windows V1 editor approach.
   - Use a native Windows text control first, not a custom editor renderer.
   - Candidate default: RichEdit control for multiline editing, selection, clipboard, undo, and IME.

## Phase 1: Make the Shared Zig Core Windows-Safe

4. Fix temporary-file path handling in `app/preview.zig`.
   - Replace the hardcoded `/tmp/merrow-studio-preview-*` path generation with an OS-aware temp directory strategy.
   - Verify preview PNG generation works on Windows.
5. Audit path resolution and font loading in `app/preview.zig`.
   - Confirm `resolveRepoPath(...)` works for Windows path shapes.
   - Verify packaged `fonts/` resolution next to the Windows executable.
6. Confirm exported FFI contracts are OS-neutral.
   - Reuse the scene structs already exposed by `app/preview.zig`.
   - Reuse the editable graph structs already mirrored in `app/platform/merrow_freeform_canvas.h`.
7. Extract any remaining reusable non-UI behavior from Objective-C into Zig where it reduces port risk.
   - Prioritize document serialization format helpers and freeform graph snapshot conversion helpers.
   - Do not move drawing code unless it simplifies both platforms.

## Phase 2: Build and Packaging Foundation

8. Add a Windows studio target in `build.zig`.
   - Keep `merrow` CLI unchanged.
   - Add `merrow-studio` for Windows only.
   - Continue using `app/main.zig` as the shared Zig entrypoint.
9. Add `zigwin32` to `build.zig.zon`.
   - Import Win32, Direct2D, DirectWrite, common controls, file dialogs, and shell APIs through generated Zig bindings.
10. Link the required Windows libraries.
   - `user32`
   - `gdi32`
   - `comctl32`
   - `d2d1`
   - `dwrite`
   - any additional libraries required for dialogs, DPI, or RichEdit once chosen
11. Create Windows packaging and run scripts.
   - `scripts/build_windows_studio.ps1`
   - optional run task and package task in `.vscode/tasks.json`
   - stage `merrow-studio.exe` plus `fonts/` in a versioned release folder

## Phase 3: Native Window Shell in Pure Zig

12. Create `app/platform/windows_main.zig`.
   - Export `merrow_studio_main(...)` to satisfy `app/main.zig`.
   - Register the window class.
   - Create the main window.
   - Run the Win32 message loop.
13. Build the top-level window layout.
   - Left pane: preview or freeform canvas host.
   - Right pane: source editor or freeform inspector host.
   - Bottom strip: status label and command context label.
14. Add a native menu and toolbar equivalent.
   - File: New, Open, Save, Save As, Export PNG, Export SVG, Exit.
   - View: Mermaid mode, Freeform mode, Fit, 100%, Actual Size.
   - Diagram: Apply command, Shuffle, Set direction.
15. Add DPI awareness at process startup.
   - Use per-monitor DPI if available.
   - Ensure layout math and text scale correctly on high-DPI displays.

## Phase 4: Mermaid Source Mode

16. Host a native multiline editor control.
   - Default to RichEdit if it provides the needed behavior with low implementation risk.
   - Support selection, undo, clipboard, IME, and keyboard shortcuts.
17. Recreate the current edit loop from `app/platform/macos_app.m`.
   - On edit, debounce syntax highlighting or syntax feedback.
   - Dispatch syntax check and scene build work off the UI thread.
   - Update the status line with syntax and file state.
18. Implement the command box workflow.
   - Wire an input field plus action button to `merrow_studio_apply_command(...)`.
   - Preserve command context ID and command context display state.
19. Implement diagram shuffle and direction actions.
   - Wire to `merrow_studio_shuffle_diagram(...)`.
   - Add menu actions for direction changes via command application.

## Phase 5: Preview Viewport

20. Implement a custom preview window class backed by Direct2D.
   - Use `merrow_studio_build_scene(...)` as the first render path.
   - Draw subgraphs, nodes, edges, and edge labels from the exported scene structs.
21. Add DirectWrite text rendering.
   - Match label alignment, wrapping width, and font sizing closely enough to preserve diagram readability.
   - Use packaged fonts if needed for parity.
22. Add pan and zoom behavior.
   - Mouse wheel zoom.
   - drag pan.
   - Fit and reset actions.
23. Keep the PNG preview fallback path available.
   - If direct scene rendering fails for a diagram type, preserve the ability to load a rendered preview image from `merrow_studio_render_preview_png(...)`.

## Phase 6: Freeform Canvas Mode

24. Create a Windows equivalent of the freeform canvas component.
   - Load `merrow_studio_build_editable_graph(...)` snapshots.
   - Maintain selection state for nodes, edges, and groups.
   - Mirror the current freeform mode switch behavior from the mac app.
25. Reimplement canvas drawing in Zig.
   - Draw node shapes, group bounds, connectors, labels, resize handles, and selection affordances.
   - Preserve the current graph-type-specific rendering distinctions where practical.
26. Reimplement canvas interactions.
   - Click selection.
   - drag move.
   - resize selected objects.
   - insert node.
   - insert group.
   - create connector.
27. Recreate the freeform inspector panel.
   - Default canvas, node, group, and edge style controls.
   - Selected object property controls.
   - connector source and target pickers.
28. Recreate freeform mutation wiring.
   - Update selected node, edge, and group properties.
   - Mark the document dirty after each mutation.
   - Refresh selection summary and status text after changes.

## Phase 7: File Formats and Export

29. Implement Mermaid document open and save.
   - `.mmd` source files.
   - dirty-state tracking.
   - recent path handling if needed later.
30. Decide and document the freeform document format.
   - The mac app already serializes and reloads freeform documents in `merrow_freeform_canvas.m`.
   - Extract or replicate that format in Zig so Windows and macOS can share it.
31. Implement file open and save flows for both modes.
   - Mermaid source mode.
   - freeform document mode.
32. Implement export dialogs and export actions.
   - PNG export from Mermaid source mode.
   - SVG export from Mermaid source mode.
   - PNG export from freeform canvas mode.
   - SVG export from freeform canvas mode.

## Phase 8: Quality Gates

33. Add Windows smoke tests for the shared Zig layer.
   - syntax check
   - build scene
   - build editable graph
   - export PNG
   - export SVG
34. Create a manual parity checklist against the mac app.
   - source editing
   - live preview updates
   - command application
   - shuffle
   - mode switching
   - freeform insertion and selection
   - save and reload
   - export
35. Build a Windows visual-check workflow.
   - Render the `test-diagrams/` set from the studio-backed path where possible.
   - Capture screenshots for key interactive flows.
36. Add packaging verification.
   - fresh unzip on Windows
   - launch `merrow-studio.exe`
   - verify `fonts/` resolution

## Suggested Milestones

1. Milestone A: Window shell plus source editor opens and syntax-checks Mermaid text.
2. Milestone B: Preview viewport renders diagrams from `merrow_studio_build_scene(...)` with pan and zoom.
3. Milestone C: Command box, shuffle, and source-mode export work.
4. Milestone D: Freeform canvas loads and supports selection plus mutation.
5. Milestone E: File formats, packaging, and parity verification are complete.

## Risks to Track

1. The docs still describe a more Metal-centric mac app than the current implementation actually uses.
2. The editable canvas logic is large and currently concentrated in Objective-C, so a straight Windows rewrite will be expensive unless some shared logic is first moved into Zig.
3. Text rendering parity will be the hardest visual correctness problem on Windows.
4. Pure Zig Direct2D and DirectWrite work is viable, but the COM surface area is large enough that bindings and wrappers should be kept disciplined from the start.

## Immediate Next Actions

1. Fix the temp-path issue in `app/preview.zig`.
2. Add the Windows `merrow-studio` target and `zigwin32` dependency.
3. Create the empty pure-Zig window shell in `app/platform/windows_main.zig`.
4. Stand up the source editor plus status bar before touching the freeform canvas.
5. Implement Direct2D preview rendering before re-creating the inspector-heavy freeform toolchain.