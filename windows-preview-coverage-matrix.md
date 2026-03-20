# Windows Preview Coverage Matrix

## Purpose

This matrix turns the Windows preview requirement into an implementation backlog.

The key distinction is:

1. what the core renderers in `src/` can already export
2. what the current studio FFI in `app/preview.zig` already exposes to the app shell
3. what the Windows preview should do now

The Windows preview should target full diagram-family coverage.

That does not require every family to have an immediate Direct2D scene renderer.
It does require every supported family to have a working preview path.

## Current Evidence

From `src/` there are dedicated PNG renderers for:

1. flowchart or generic graph via `src/render/graph.zig`
2. sequence
3. class
4. ER
5. state
6. journey
7. gantt
8. pie

From `src/` there are dedicated SVG renderers for:

1. flowchart or generic graph via `src/render/svg_render.zig`
2. sequence
3. class
4. ER
5. state
6. journey
7. gantt
8. pie

From `app/preview.zig` today:

1. `merrow_studio_build_scene(...)` rejects sequence, class, and ER explicitly
2. `merrow_studio_render_preview_png(...)` supports sequence, class, ER, and state fallback preview rendering
3. `merrow_studio_export_diagram(...)` supports direct PNG or SVG export for:
   - sequence
   - state
   - class
   - ER
   - generic graph or flowchart path
4. `journey`, `gantt`, and `pie` have core renderers in `src/` but are not yet bridged through the current studio FFI path in `app/preview.zig`

## Coverage Matrix

| Diagram family | Core PNG renderer in `src/` | Core SVG renderer in `src/` | Current `merrow_studio_build_scene(...)` | Current studio fallback PNG preview | Current studio export bridge | Recommended Windows preview path now |
| --- | --- | --- | --- | --- | --- | --- |
| Flowchart / graph | Yes | Yes | Yes | Not needed | Yes | Direct scene preview |
| Sequence | Yes | Yes | No | Yes | Yes | PNG fallback first, then add direct scene renderer later |
| Class | Yes | Yes | No | Yes | Yes | PNG fallback first, then add direct scene renderer later |
| ER | Yes | Yes | No | Yes | Yes | PNG fallback first, then add direct scene renderer later |
| State | Yes | Yes | No practical direct path today | Yes | Yes | PNG fallback first, then add direct scene renderer later |
| Journey | Yes | Yes | No | No | No current studio bridge | Add studio export or preview bridge, use PNG or SVG fallback first |
| Gantt | Yes | Yes | No | No | No current studio bridge | Add studio export or preview bridge, use PNG or SVG fallback first |
| Pie | Yes | Yes | No | No | No current studio bridge | Add studio export or preview bridge, use PNG or SVG fallback first |

## What This Means For Windows Preview

### Tier 1: Already Reachable Through Studio FFI

These families can support Windows preview immediately without waiting for new scene builders:

1. flowchart or graph via `merrow_studio_build_scene(...)`
2. sequence via `merrow_studio_render_preview_png(...)`
3. class via `merrow_studio_render_preview_png(...)`
4. ER via `merrow_studio_render_preview_png(...)`
5. state via `merrow_studio_render_preview_png(...)`

### Tier 2: Core Renderers Exist But Studio FFI Does Not Expose Them Yet

These families are already renderable in the codebase, but the studio app path still needs bridging work:

1. journey
2. gantt
3. pie

The fastest path for Windows preview is not to invent scene rendering for these first.
It is to expose them through the studio FFI with the same PNG or SVG rendering model already used elsewhere.

## Recommended Implementation Order

### Step 1: Make Windows preview family-complete with existing FFI

Use the current mixed approach:

1. direct scene preview for flowchart or graph
2. PNG fallback preview for sequence
3. PNG fallback preview for class
4. PNG fallback preview for ER
5. PNG fallback preview for state

This gets the current Windows shell much closer to parity quickly.

### Step 2: Bridge the missing studio families

Extend `app/preview.zig` so the studio FFI can preview or export:

1. journey
2. gantt
3. pie

The first bridge can be PNG fallback only if that is the shortest path.

### Step 3: Replace family-specific PNG fallback paths selectively

Only after family coverage exists everywhere:

1. add direct scene builders for sequence if worthwhile
2. add direct scene builders for class if worthwhile
3. add direct scene builders for ER if worthwhile
4. add direct scene builders for state if worthwhile

Do not block Windows preview parity on completing Step 3.

## Immediate Backlog

1. Add a studio-family detection and dispatch path for journey diagrams in `app/preview.zig`.
2. Add a studio-family detection and dispatch path for gantt diagrams in `app/preview.zig`.
3. Add a studio-family detection and dispatch path for pie diagrams in `app/preview.zig`.
4. Add a Windows preview runtime path that chooses:
   - scene preview when `merrow_studio_build_scene(...)` succeeds
   - PNG fallback preview when the family is scene-unsupported but previewable
5. Add manual or automated preview validation for all eight families:
   - flowchart
   - sequence
   - class
   - ER
   - state
   - journey
   - gantt
   - pie

## Decision Rule

If a diagram family can already export correctly today, Windows preview should be considered blocked only until there is a working preview bridge for that family, not until there is a perfect native Direct2D scene renderer for it.