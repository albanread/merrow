# Windows Studio Refactor Plan

## Why This Refactor Is Necessary

`app/platform/windows_main.zig` is currently carrying too many responsibilities in one place.

At the time of writing it is about 1800 lines and mixes:

1. Win32 process startup and manifest assumptions
2. top-level window creation and message dispatch
3. layout math and resize behavior
4. toolbar, status bar, editor, and command-row control setup
5. Direct2D and DirectWrite preview rendering
6. preview pan, zoom, and scroll state
7. document load, save, dirty tracking, and window-title updates
8. Mermaid scene rebuild and command application wiring
9. DPI awareness and shell font handling

This will become unmaintainable once more Windows-specific features arrive.

The goal is not to create many tiny files for their own sake. The goal is to separate stable component boundaries so we can keep adding Windows code without turning one file into an unreviewable platform blob.

## Refactor Goals

1. Keep `app/main.zig` unchanged as the platform-agnostic studio entrypoint.
2. Preserve the current Windows behavior while moving code.
3. Make preview rendering, shell controls, and document state independently testable and readable.
4. Establish clear ownership boundaries before freeform canvas and richer Windows UI work expand the codebase further.

## Target Layout

Create a dedicated Windows platform folder:

1. `app/platform/windows/main.zig`
2. `app/platform/windows/app_state.zig`
3. `app/platform/windows/constants.zig`
4. `app/platform/windows/layout.zig`
5. `app/platform/windows/shell.zig`
6. `app/platform/windows/toolbar.zig`
7. `app/platform/windows/status_bar.zig`
8. `app/platform/windows/editor.zig`
9. `app/platform/windows/document.zig`
10. `app/platform/windows/dpi.zig`
11. `app/platform/windows/preview_view.zig`
12. `app/platform/windows/preview_render.zig`
13. `app/platform/windows/preview_input.zig`
14. `app/platform/windows/common.zig`

Keep a thin compatibility shim at:

1. `app/platform/windows_main.zig`

That file should eventually do little more than:

1. import `app/platform/windows/main.zig`
2. export `merrow_studio_main(...)`

## Responsibilities By File

### `app/platform/windows/main.zig`

Own only platform bootstrap:

1. process DPI awareness startup
2. common-controls initialization
3. window-class registration
4. main-window creation
5. top-level message loop
6. call-through to the shell window proc

This file should not contain layout math, preview drawing, or document command handling.

### `app/platform/windows/app_state.zig`

Own shared runtime state structs and lifecycle helpers:

1. child window handles
2. preview renderer state
3. document path and dirty state
4. status message storage
5. current scene pointer ownership
6. shell font and editor font handles

This is the central state module. It should define structs and focused helper methods, not become a second `windows_main.zig`.

### `app/platform/windows/constants.zig`

Own stable Win32-facing constants:

1. class names
2. menu IDs
3. toolbar button IDs
4. default strings
5. layout defaults that are truly constants

Move pure constants here so the rest of the Windows files stay focused on behavior.

### `app/platform/windows/layout.zig`

Own all shell geometry and size policy:

1. `Layout` struct
2. minimum pane constraints
3. minimum window-size calculation
4. deferred child-window positioning
5. status-bar part sizing

This module should expose a small API such as:

1. `applyMainWindowLayout(...)`
2. `minimumWindowTrackSize(...)`
3. `updateStatusBarParts(...)`

No document logic and no rendering logic should live here.

### `app/platform/windows/shell.zig`

Own top-level shell orchestration:

1. create child windows
2. install menu bar
3. dispatch top-level commands
4. route `WM_CREATE`, `WM_SIZE`, `WM_GETMINMAXINFO`, `WM_DPICHANGED`, `WM_DESTROY`
5. coordinate calls into layout, editor, document, toolbar, and preview modules

This file should be the main window proc home after the split.

### `app/platform/windows/toolbar.zig`

Own the toolbar band only:

1. toolbar creation
2. reserved toolbar buttons
3. button sizing and toolbar font assignment
4. placeholder or future toolbar command routing helpers

This is the right place for later icon work and richer toolbar actions.

### `app/platform/windows/status_bar.zig`

Own the status bar only:

1. status bar creation
2. part management
3. status text updates
4. zoom display updates
5. font assignment for the status bar

This module should not know about preview drawing or document parsing directly.

### `app/platform/windows/editor.zig`

Own source-editor control behavior:

1. editor control creation
2. editor font creation and cleanup
3. set and get text helpers
4. any future syntax-highlighting path
5. editor-specific message handling if needed later

This keeps future RichEdit or custom editor experiments isolated from the shell.

### `app/platform/windows/document.zig`

Own document workflows and shared app-level actions:

1. open and save dialogs
2. current path and dirty-state updates
3. window title updates
4. source-to-scene rebuild flow
5. apply command flow
6. shuffle flow if it stays in source mode

This is the right place for future export actions too.

### `app/platform/windows/dpi.zig`

Own DPI and shell-font handling:

1. process DPI awareness opt-in
2. non-client DPI scaling
3. `WM_DPICHANGED` adjustments
4. system font retrieval from `NONCLIENTMETRICSA`
5. shell font assignment and cleanup

The shell should call into this module rather than carrying font and DPI code inline.

### `app/platform/windows/preview_view.zig`

Own preview window behavior and window proc:

1. preview class registration support
2. preview window proc
3. scrollbar updates
4. scene content extent calculations
5. pan and zoom state changes
6. invalidate and refresh requests

This should be the home of viewport policy.

### `app/platform/windows/preview_render.zig`

Own Direct2D and DirectWrite rendering:

1. factory creation
2. render-target lifecycle
3. brush and text-format helpers
4. actual scene drawing for nodes, edges, labels, and subgraphs
5. text rendering helpers

This is the biggest rendering-specific split and will reduce the main platform file size substantially.

### `app/platform/windows/preview_input.zig`

Own preview interaction helpers:

1. mouse-coordinate extraction
2. wheel delta helpers
3. drag-pan updates
4. keyboard zoom shortcuts
5. scroll-message translation

This keeps input policy separate from drawing and shell orchestration.

### `app/platform/windows/common.zig`

Own low-level shared helpers that are too small for a dedicated module but reused across several others:

1. Win32 bitcast helpers for styles and flags
2. HRESULT helpers
3. small string conversion helpers
4. any narrow utility that would otherwise be duplicated

Do not let this become a dumping ground.

## Dependency Rules

To avoid rebuilding the giant-file problem under a new folder structure:

1. `shell.zig` may depend on every Windows component module.
2. `layout.zig` may depend on `constants.zig`, `app_state.zig`, and `common.zig` only.
3. `preview_render.zig` must not import `document.zig`.
4. `document.zig` must not import `preview_render.zig`.
5. `toolbar.zig`, `status_bar.zig`, and `editor.zig` should not own global application state beyond their specific handles and resources.
6. `app_state.zig` should define state, not orchestrate application flow.

## Recommended Extraction Order

This order minimizes regression risk.

### Stage 1: Pure Mechanical Splits

Move code that has very low behavioral risk first:

1. `constants.zig`
2. `common.zig`
3. `app_state.zig`
4. `dpi.zig`

These are mostly constants, structs, and helper functions.

### Stage 2: Isolate Layout and Status UI

Then extract the shell pieces that are already fairly self-contained:

1. `layout.zig`
2. `status_bar.zig`
3. `toolbar.zig`

This should leave the main file noticeably smaller without changing preview behavior.

### Stage 3: Extract Editor and Document Flow

Next split the source-mode control logic:

1. `editor.zig`
2. `document.zig`

This isolates the control that is most likely to keep changing.

### Stage 4: Extract Preview Viewport

Split viewport behavior before render internals:

1. `preview_input.zig`
2. `preview_view.zig`

This removes scroll, clamp, pan, and zoom logic from the shell.

### Stage 5: Extract Direct2D Rendering

Finally move the large drawing code:

1. `preview_render.zig`

This is the highest-risk move because it touches many helper functions and COM-related setup, so it should come after the simpler structural splits.

### Stage 6: Collapse `windows_main.zig`

After the above steps:

1. convert `app/platform/windows_main.zig` into a thin compatibility shim
2. move the real entrypoint to `app/platform/windows/main.zig`

## First Practical Cut

The best first refactor is:

1. create `app/platform/windows/`
2. move constants and state structs out first
3. move layout and status-bar code next

That should reduce `windows_main.zig` materially without touching the most fragile rendering path yet.

## What Should Stay Shared Across Platforms

Do not move these into Windows-only code unless forced:

1. Mermaid syntax and scene-building logic in `app/preview.zig`
2. command-application logic in `app/commands.zig`
3. parser, layout, and render core in `src/`

The Windows refactor should be about the shell and platform UI, not about replatforming the shared Zig core.

## Review Standard For The Refactor

Each extraction step should satisfy all of these:

1. `zig build studio` still works after the step
2. no feature movement without explicit intent
3. no new cross-module cycles
4. each new file has one clear ownership area
5. top-level shell code becomes shorter and easier to scan after every extraction

## Immediate Next Refactor Tasks

1. Create `app/platform/windows/`.
2. Extract `constants.zig`, `common.zig`, and `app_state.zig`.
3. Extract `layout.zig` and `status_bar.zig`.
4. Rebuild and verify resize, toolbar, and status-bar behavior.
5. Only then move preview rendering and input code.