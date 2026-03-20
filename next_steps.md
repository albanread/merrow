# Next Steps

## Current Checkpoint

1. Current code checkpoint is still commit `02e7050` (`Refactor Windows scaffold and preview experiments`).
2. Local working tree is now ahead of that checkpoint with a first PNG-backed Windows preview slice implemented.
3. The viewport shell already exists and is reusable:
   - pan drag
   - mouse-wheel zoom
   - scrollbars
   - zoom status text
4. The preview update and paint path now go through PNG generation plus bitmap decode instead of scene rendering.
5. The remaining work is validation, cleanup, and hardening rather than first-path implementation.

## Verified Current State

1. `updateEditorDerivedState()` now calls `merrow_studio_render_preview_png(...)` on successful syntax checks.
2. Windows preview paint now draws a decoded bitmap through Direct2D.
3. Scroll extent math now uses decoded bitmap width and height.
4. `PreviewRenderer` now stores:
   - WIC factory state
   - decoded Direct2D bitmap state
   - preview temp file path
   - bitmap dimensions
   - viewport state
5. Build configuration now links `ole32` and `windowscodecs` for COM/WIC preview loading.
6. Shared preview export continues to come from `app/preview.zig` via `merrow_studio_render_preview_png(...)`.
7. The Windows-specific scene-preview declarations and helpers have been removed from the active path.
8. Remaining cleanup is now mostly naming, extraction, and validation rather than deleting dead scene code.

## Decision

1. Do not extend `StudioScene` preview support any further on Windows.
2. Use `merrow_studio_render_preview_png(...)` as the Windows preview generation path.
3. Keep the existing viewport interaction model and retarget it to bitmap dimensions instead of scene extents.
4. Treat scene cleanup as follow-up work after PNG preview is rendering end-to-end.

## Why This Is The Right Cut

1. The hard part that is already done on Windows is viewport behavior, not scene drawing.
2. The hard part that is already done in shared code is raster preview generation across diagram families.
3. The current gap is only the platform bridge:
   - render preview PNG
   - load PNG on Windows
   - draw bitmap with current zoom and scroll state
4. That path gets parity faster than continuing to teach `StudioScene` about every diagram family.

## Execution Plan

### Phase 1: Add PNG Preview State To Windows

1. Expand `PreviewRenderer` in `app/platform/windows/app_state.zig` to hold bitmap-backed preview state.
2. Add fields for:
   - current preview file path
   - decoded image width
   - decoded image height
   - decoded bitmap resource(s)
   - any COM/WIC factory state needed for PNG decode
3. Keep existing fields for:
   - `zoom`
   - `scroll_x`
   - `scroll_y`
   - drag state
4. Add cleanup helpers so preview bitmap resources are released whenever a new preview is loaded or the app exits.

### Phase 2: Swap Preview Generation In `windows_main.zig`

1. Status: complete for the first vertical slice.
2. `app/platform/windows_main.zig` now declares `merrow_studio_render_preview_png(...)`.
3. `updateEditorDerivedState()` now does this order:
   - run syntax check
   - if syntax fails, clear current preview bitmap and keep the error status
   - if syntax succeeds, call `merrow_studio_render_preview_png(...)`
   - if PNG generation succeeds, load the rendered file into preview state
   - if PNG generation fails, clear preview bitmap and surface the renderer message
4. `merrow_studio_build_scene(...)` is no longer used by the Windows preview refresh path.
5. Zoom status text is still preserved through the existing status-bar refresh path.

### Phase 3: Replace Scene-Based Extent Math With Bitmap Extent Math

1. Status: complete.
2. Bitmap extent helpers now use bitmap dimensions directly.
3. Active scrollbar calculations no longer depend on `sceneContentExtent(...)`.
4. `updatePreviewScrollbars()`, `applyPreviewScroll()`, `panPreviewBy()`, and `setPreviewZoom()` stayed structurally the same.
5. Their content-size calculations now use:
   - bitmap pixel width times zoom
   - bitmap pixel height times zoom
6. Empty-preview state now resets bitmap size and scroll position back to zero.

### Phase 4: Replace Scene Paint With Bitmap Paint

1. Status: complete.
2. The Windows preview paint path now renders the decoded bitmap directly.
3. The current paint path:
   - clears the background
   - draws the loaded preview bitmap
   - applies current zoom
   - offsets by `scroll_x` and `scroll_y`
4. Scaled bitmap drawing uses Direct2D linear interpolation.
5. `requestPreviewRefresh()` and the preview window procedure remain structurally intact.

### Phase 5: Delete Windows-Only Scene Preview Plumbing

1. Status: complete for the Windows layer.
2. `current_scene`, `replaceCurrentScene(...)`, scene-only helpers, and Windows scene FFI declarations have been removed.
3. Follow-up cleanup here is optional extraction and naming polish, not more dead-code deletion.

### Phase 6: Re-evaluate Shared Scene Exports

1. Leave `merrow_studio_build_scene(...)` alone until Windows PNG preview is stable.
2. After that, confirm whether only macOS still needs it.
3. If scene export is no longer strategically important, move it out of the Windows plan and treat it as optional cleanup.

## Concrete First Implementation Slice

1. Status: implemented and compiling.
2. Preview PNG FFI and bitmap state are in place.
3. `updateEditorDerivedState()` generates a preview PNG.
4. Windows decodes the generated PNG through WIC and uploads it to a Direct2D bitmap.
5. The preview pane now renders that bitmap with the existing zoom and scroll behavior.
6. Remaining work is runtime validation across diagram families plus any extraction or hardening that shows up during manual testing.

## Suggested File-Level Order

1. `app/platform/windows/app_state.zig`
   - extend `PreviewRenderer`
2. `app/platform/windows_main.zig`
   - add preview PNG extern
   - add bitmap load/release helpers
   - switch `updateEditorDerivedState()` to PNG preview generation
   - replace scene extent math
   - replace scene paint path
3. Optional follow-up extraction after it works:
   - move bitmap preview helpers into `app/platform/windows/preview.zig` or similar

## Risks To Watch

1. Temporary preview files can accumulate if old preview paths are never deleted.
2. Re-rendering on every editor change may be expensive; correctness first, caching later.
3. Direct2D resource lifetime still needs explicit scrutiny when render target recreation and bitmap reload interact.
4. COM/WIC is now initialized and cleaned up in the preview path; verify no edge case leaks or apartment conflicts remain.
5. The first slice compiles, but it still needs visual validation in the actual Windows app.

## Validation Order

1. Launch the Windows app and verify flowchart preview renders and pans correctly.
2. Verify class preview renders through the same PNG path.
3. Verify sequence preview renders through the same PNG path.
4. Verify state preview renders through the same PNG path.
5. Verify ER preview renders through the same PNG path.
6. Verify syntax error case clears preview and shows the error message.
7. Verify zoom reset and scrollbar clamping still behave correctly.
8. Verify resize and DPI changes reload or preserve preview content correctly.

## Not The Work Right Now

1. Do not add more scene-specific rendering for sequence, state, ER, or anything else on Windows.
2. Do not redesign the preview interaction model.
3. Do not optimize preview caching before the PNG-backed path is working.
4. Do not remove shared scene exports until the Windows path is stable.

## Best Next Task

1. Run the Windows app and visually validate the new PNG-backed preview path with at least flowchart and class diagrams.
2. After visual validation, decide whether the bitmap preview helpers should move into a dedicated Windows preview module.
3. If visual validation exposes redraw or reload issues, harden bitmap reload around resize and rapid edit cycles.

## Future Notes

1. Cache preview PNGs or decoded bitmaps only after correctness is established.
2. Consider redraw-at-higher-scale buckets later if zoom quality is not good enough.
3. Consider SVG preview only if PNG quality becomes an actual product limitation.

## Tone Check For Future Me

1. The viewport shell is already good enough.
2. The missing bridge is bitmap loading, not another scene architecture.
3. Ship parity first.