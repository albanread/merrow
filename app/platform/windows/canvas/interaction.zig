/// Mouse and keyboard interaction handling for the freeform canvas window.
/// Translates Win32 messages into mutations on CanvasState.
const std = @import("std");
const win32 = @import("win32");
const state = @import("state.zig");
const hit_test = @import("hit_test.zig");

const foundation = win32.foundation;
const mouse = win32.ui.input.keyboard_and_mouse;
const ui = win32.ui.windows_and_messaging;
const gdi = win32.graphics.gdi;

const CanvasState = state.CanvasState;
const DragKind = state.DragKind;
const SelectionKind = state.SelectionKind;
const HandlePos = state.HandlePos;
const InsertionKind = state.InsertionKind;

/// Minimum screen-pixel distance the mouse must move before a click
/// on an object is promoted from "select" to "drag-move".
const drag_dead_zone: i32 = 4;

// ---------------------------------------------------------------------------
// Cursor helpers
// ---------------------------------------------------------------------------

pub fn setCursor(id: [*:0]align(1) const u16) void {
    const cursor = ui.LoadCursorW(null, id) orelse return;
    _ = ui.SetCursor(cursor);
}

pub fn updateCursor(canvas: *const CanvasState, screen_x: i32, screen_y: i32) void {
    const g = canvas.graph orelse {
        setCursor(ui.IDC_ARROW);
        return;
    };
    if (canvas.insertionModeActive()) {
        setCursor(ui.IDC_CROSS);
        return;
    }
    const cx: f64 = @floatFromInt(screen_x);
    const cy: f64 = @floatFromInt(screen_y);
    const hit = hit_test.hitTest(g, canvas.selection, canvas.viewport, cx, cy);
    switch (hit.kind) {
        .resize_handle => setCursor(resizeCursorForHandle(hit.handle)),
        .node, .subgraph => setCursor(ui.IDC_SIZEALL),
        .edge => setCursor(ui.IDC_HAND),
        else => setCursor(ui.IDC_ARROW),
    }
}

fn resizeCursorForHandle(handle: HandlePos) [*:0]align(1) const u16 {
    return switch (handle) {
        .top_left, .bot_right => ui.IDC_SIZENWSE,
        .top_right, .bot_left => ui.IDC_SIZENESW,
        .top_center, .bot_center => ui.IDC_SIZENS,
        .mid_left, .mid_right => ui.IDC_SIZEWE,
    };
}

// ---------------------------------------------------------------------------
// Insertion commit helpers
// ---------------------------------------------------------------------------

/// Default size for a newly-inserted node (canvas units).
const default_node_w: f64 = 120;
const default_node_h: f64 = 60;

/// Default size for a newly-inserted subgraph.
const default_sg_w: f64 = 200;
const default_sg_h: f64 = 160;

// ---------------------------------------------------------------------------
// Interaction result: tells the caller what changed so it knows what to
// invalidate / notify.
// ---------------------------------------------------------------------------

pub const InteractionResult = struct {
    /// Redraw the canvas.
    needs_redraw: bool = false,
    /// The selection changed — update the inspector panel.
    selection_changed: bool = false,
    /// A node / subgraph / edge was mutated — mark document dirty.
    document_mutated: bool = false,
    /// A new node was inserted at the given id index.
    node_inserted: bool = false,
    /// A new subgraph was inserted.
    subgraph_inserted: bool = false,
    /// When node_inserted: the canvas-space position and shape code for the new node.
    insert_x: f64 = 0,
    insert_y: f64 = 0,
    insert_shape: u32 = 0,
    /// A link was completed between connector_source and the newly-selected node/subgraph.
    link_completed: bool = false,
    /// The source ID for a completed link (pointer into the graph; valid until graph mutation).
    link_source_id: ?[*:0]const u8 = null,
};

fn clearHover(canvas: *CanvasState, result: *InteractionResult) void {
    if (canvas.hover.kind != .none) {
        canvas.clearHover();
        result.needs_redraw = true;
    }
}

fn hoverMatchesSelection(canvas: *const CanvasState) bool {
    return canvas.hover.kind == canvas.selection.kind and
        (canvas.hover.kind == .none or canvas.hover.index == canvas.selection.index);
}

fn updateHover(canvas: *CanvasState, screen_x: i32, screen_y: i32) bool {
    const g = canvas.graph orelse {
        const changed = canvas.hover.kind != .none;
        canvas.clearHover();
        return changed;
    };

    const prev = canvas.hover;
    const cx: f64 = @floatFromInt(screen_x);
    const cy: f64 = @floatFromInt(screen_y);
    const hit = hit_test.hitTest(g, canvas.selection, canvas.viewport, cx, cy);

    switch (hit.kind) {
        .node => canvas.setHoverNode(hit.index),
        .subgraph => canvas.setHoverSubgraph(hit.index),
        .edge => canvas.setHoverEdge(hit.index),
        .resize_handle => canvas.hover = canvas.selection,
        else => canvas.clearHover(),
    }

    if (hoverMatchesSelection(canvas) and canvas.selection.kind != .none) {
        canvas.clearHover();
    }

    return prev.kind != canvas.hover.kind or prev.index != canvas.hover.index;
}

pub fn onMouseLeave(canvas: *CanvasState) InteractionResult {
    var result = InteractionResult{};
    clearHover(canvas, &result);
    return result;
}

// ---------------------------------------------------------------------------
// WM_LBUTTONDOWN
// ---------------------------------------------------------------------------

pub fn onLeftButtonDown(
    canvas: *CanvasState,
    hwnd: ?foundation.HWND,
    screen_x: i32,
    screen_y: i32,
) InteractionResult {
    _ = mouse.SetCapture(hwnd);

    var result = InteractionResult{};
    const g = canvas.graph orelse return result;
    clearHover(canvas, &result);

    const cx: f64 = @floatFromInt(screen_x);
    const cy: f64 = @floatFromInt(screen_y);
    const canvas_pt = canvas.viewport.screenToCanvas(cx, cy);

    // --- Insertion mode ---
    if (canvas.insertion.kind == .node) {
        const shape = canvas.insertion.node_shape;
        canvas.cancelInsertion();
        result.node_inserted = true;
        result.insert_x = canvas_pt.x;
        result.insert_y = canvas_pt.y;
        result.insert_shape = shape;
        result.document_mutated = true;
        result.needs_redraw = true;
        result.selection_changed = true;
        return result;
    }
    if (canvas.insertion.kind == .subgraph) {
        canvas.cancelInsertion();
        result.subgraph_inserted = true;
        result.insert_x = canvas_pt.x;
        result.insert_y = canvas_pt.y;
        result.document_mutated = true;
        result.needs_redraw = true;
        result.selection_changed = true;
        return result;
    }
    if (canvas.insertion.kind == .connector_source) {
        // Left-clicking a node or subgraph while in link mode completes the edge.
        const hit = hit_test.hitTest(g, canvas.selection, canvas.viewport, cx, cy);
        switch (hit.kind) {
            .node, .subgraph => {
                // Save source ID before cancelling insertion.
                const src_id = canvas.insertion.connector_source_id;
                canvas.cancelInsertion();
                if (hit.kind == .node) canvas.selectNode(hit.index) else canvas.selectSubgraph(hit.index);
                result.link_completed = true;
                result.link_source_id = src_id;
                result.document_mutated = true;
                result.selection_changed = true;
                result.needs_redraw = true;
            },
            else => {
                // Clicked empty space — cancel linking.
                canvas.cancelInsertion();
                canvas.clearSelection();
                result.selection_changed = true;
                result.needs_redraw = true;
            },
        }
        return result;
    }

    // --- Normal pick ---
    const prev_kind = canvas.selection.kind;
    const prev_idx = canvas.selection.index;

    const hit = hit_test.hitTest(g, canvas.selection, canvas.viewport, cx, cy);
    switch (hit.kind) {
        .resize_handle => {
            // Start resize drag, preserving existing selection.
            switch (canvas.selection.kind) {
                .node => {
                    const n = &g.nodes[canvas.selection.index];
                    canvas.drag = .{
                        .kind = .resize_object,
                        .start_screen_x = screen_x,
                        .start_screen_y = screen_y,
                        .object_origin_x = n.x,
                        .object_origin_y = n.y,
                        .object_origin_w = n.width,
                        .object_origin_h = n.height,
                        .handle = hit.handle,
                        .last_screen_x = screen_x,
                        .last_screen_y = screen_y,
                    };
                },
                .subgraph => {
                    const sg = &g.subgraphs[canvas.selection.index];
                    canvas.drag = .{
                        .kind = .resize_object,
                        .start_screen_x = screen_x,
                        .start_screen_y = screen_y,
                        .object_origin_x = sg.x,
                        .object_origin_y = sg.y,
                        .object_origin_w = sg.width,
                        .object_origin_h = sg.height,
                        .handle = hit.handle,
                        .last_screen_x = screen_x,
                        .last_screen_y = screen_y,
                    };
                },
                else => {},
            }
            result.needs_redraw = true;
        },
        .node => {
            canvas.selectNode(hit.index);
            const n = &g.nodes[hit.index];
            // Don't start a move immediately — wait for the dead-zone.
            canvas.drag = .{
                .kind = .pending_select,
                .start_screen_x = screen_x,
                .start_screen_y = screen_y,
                .object_origin_x = n.x,
                .object_origin_y = n.y,
                .object_origin_w = n.width,
                .object_origin_h = n.height,
                .last_screen_x = screen_x,
                .last_screen_y = screen_y,
            };
            result.needs_redraw = true;
            result.selection_changed = canvas.selection.kind != prev_kind or canvas.selection.index != prev_idx;
        },
        .subgraph => {
            canvas.selectSubgraph(hit.index);
            const sg = &g.subgraphs[hit.index];
            canvas.drag = .{
                .kind = .pending_select,
                .start_screen_x = screen_x,
                .start_screen_y = screen_y,
                .object_origin_x = sg.x,
                .object_origin_y = sg.y,
                .object_origin_w = sg.width,
                .object_origin_h = sg.height,
                .last_screen_x = screen_x,
                .last_screen_y = screen_y,
            };
            result.needs_redraw = true;
            result.selection_changed = canvas.selection.kind != prev_kind or canvas.selection.index != prev_idx;
        },
        .edge => {
            canvas.selectEdge(hit.index);
            canvas.drag = .{ .kind = .none };
            result.needs_redraw = true;
            result.selection_changed = canvas.selection.kind != prev_kind or canvas.selection.index != prev_idx;
        },
        else => {
            // Click on empty space — deselect.  Pan is done via middle-button.
            canvas.clearSelection();
            canvas.drag = .{ .kind = .none };
            result.selection_changed = prev_kind != .none;
            result.needs_redraw = result.selection_changed;
        },
    }

    return result;
}

// ---------------------------------------------------------------------------
// WM_MOUSEMOVE
// ---------------------------------------------------------------------------

pub fn onMouseMove(
    canvas: *CanvasState,
    screen_x: i32,
    screen_y: i32,
    snap_to_grid: bool,
) InteractionResult {
    var result = InteractionResult{};

    switch (canvas.drag.kind) {
        .none => {
            updateCursor(canvas, screen_x, screen_y);
            if (updateHover(canvas, screen_x, screen_y)) {
                result.needs_redraw = true;
            }
        },
        .pending_select => {
            clearHover(canvas, &result);
            // Check if the mouse has moved past the dead-zone.
            const adx = @abs(screen_x - canvas.drag.start_screen_x);
            const ady = @abs(screen_y - canvas.drag.start_screen_y);
            if (adx > drag_dead_zone or ady > drag_dead_zone) {
                // Promote to move_object — the actual position update will
                // happen on the next WM_MOUSEMOVE when kind == .move_object.
                canvas.drag.kind = .move_object;
            }
        },
        .pan => {
            clearHover(canvas, &result);
            const dx: f64 = @floatFromInt(screen_x - canvas.drag.last_screen_x);
            const dy: f64 = @floatFromInt(screen_y - canvas.drag.last_screen_y);
            canvas.viewport.pan_x -= dx / canvas.viewport.zoom;
            canvas.viewport.pan_y -= dy / canvas.viewport.zoom;
            canvas.drag.last_screen_x = screen_x;
            canvas.drag.last_screen_y = screen_y;
            result.needs_redraw = true;
        },
        .move_object => {
            clearHover(canvas, &result);
            _ = canvas.graph orelse return result;
            const total_dx: f64 = @as(f64, @floatFromInt(screen_x - canvas.drag.start_screen_x)) / canvas.viewport.zoom;
            const total_dy: f64 = @as(f64, @floatFromInt(screen_y - canvas.drag.start_screen_y)) / canvas.viewport.zoom;

            canvas.drag.last_screen_x = screen_x;
            canvas.drag.last_screen_y = screen_y;

            const moved = canvas.moveSelectionToward(
                canvas.drag.object_origin_x,
                canvas.drag.object_origin_y,
                total_dx,
                total_dy,
                snap_to_grid,
                10.0,
            );
            result.needs_redraw = true;
            result.document_mutated = moved;
            result.selection_changed = moved;
        },
        .resize_object => {
            clearHover(canvas, &result);
            const g = canvas.graph orelse return result;
            const dx: f64 = @as(f64, @floatFromInt(screen_x - canvas.drag.start_screen_x)) / canvas.viewport.zoom;
            const dy: f64 = @as(f64, @floatFromInt(screen_y - canvas.drag.start_screen_y)) / canvas.viewport.zoom;

            applyResize(g, canvas, dx, dy);
            result.needs_redraw = true;
            result.document_mutated = true;
            result.selection_changed = true;
        },
    }

    return result;
}

fn applyResize(g: *state.StudioEditableGraph, canvas: *CanvasState, dx: f64, dy: f64) void {
    const min_size: f64 = 20;
    const content_padding: f64 = 12;
    const ox = canvas.drag.object_origin_x;
    const oy = canvas.drag.object_origin_y;
    const ow = canvas.drag.object_origin_w;
    const oh = canvas.drag.object_origin_h;
    const handle = canvas.drag.handle;

    // Compute new bounds based on which handle is being dragged.
    var new_x = ox;
    var new_y = oy;
    var new_w = ow;
    var new_h = oh;

    const drags_left = handle == .top_left or handle == .mid_left or handle == .bot_left;
    const drags_right = handle == .top_right or handle == .mid_right or handle == .bot_right;
    const drags_top = handle == .top_left or handle == .top_center or handle == .top_right;
    const drags_bot = handle == .bot_left or handle == .bot_center or handle == .bot_right;

    if (drags_right) new_w = @max(min_size, ow + dx);
    if (drags_bot) new_h = @max(min_size, oh + dy);
    if (drags_left) {
        new_w = @max(min_size, ow - dx);
        new_x = ox + ow - new_w;
    }
    if (drags_top) {
        new_h = @max(min_size, oh - dy);
        new_y = oy + oh - new_h;
    }

    if (canvas.selection.kind == .subgraph) {
        if (state.subgraphContentBounds(g, canvas.selection.index)) |content| {
            const min_left = content.min_x - content_padding;
            const min_top = content.min_y - content_padding;
            const min_right = content.max_x + content_padding;
            const min_bottom = content.max_y + content_padding;

            var right = new_x + new_w;
            var bottom = new_y + new_h;

            if (new_x > min_left) new_x = min_left;
            if (new_y > min_top) new_y = min_top;
            if (right < min_right) right = min_right;
            if (bottom < min_bottom) bottom = min_bottom;

            new_w = @max(min_size, right - new_x);
            new_h = @max(min_size, bottom - new_y);
        }
    }

    switch (canvas.selection.kind) {
        .node => {
            if (canvas.selection.index < g.node_count) {
                g.nodes[canvas.selection.index].x = new_x;
                g.nodes[canvas.selection.index].y = new_y;
                g.nodes[canvas.selection.index].width = new_w;
                g.nodes[canvas.selection.index].height = new_h;
            }
        },
        .subgraph => {
            if (canvas.selection.index < g.subgraph_count) {
                g.subgraphs[canvas.selection.index].x = new_x;
                g.subgraphs[canvas.selection.index].y = new_y;
                g.subgraphs[canvas.selection.index].width = new_w;
                g.subgraphs[canvas.selection.index].height = new_h;
            }
        },
        else => {},
    }
}

// ---------------------------------------------------------------------------
// WM_LBUTTONUP
// ---------------------------------------------------------------------------

pub fn onLeftButtonUp(
    canvas: *CanvasState,
    screen_x: i32,
    screen_y: i32,
) InteractionResult {
    var result = InteractionResult{};
    const was_drag = canvas.drag.kind == .move_object or canvas.drag.kind == .resize_object;
    canvas.drag = .{};
    _ = mouse.ReleaseCapture();
    if (updateHover(canvas, screen_x, screen_y)) {
        result.needs_redraw = true;
    }
    if (was_drag) {
        result.needs_redraw = true;
    }
    return result;
}

// ---------------------------------------------------------------------------
// WM_MOUSEWHEEL — zoom centred on cursor
// ---------------------------------------------------------------------------

pub fn onMouseWheel(
    canvas: *CanvasState,
    screen_x: i32,
    screen_y: i32,
    delta: i16,
) InteractionResult {
    var result = InteractionResult{};
    const factor: f64 = if (delta > 0) 1.1 else (1.0 / 1.1);
    const old_zoom = canvas.viewport.zoom;
    canvas.viewport.zoom = std.math.clamp(old_zoom * factor, 0.1, 8.0);

    // Keep the canvas point under the cursor stationary.
    const cx: f64 = @floatFromInt(screen_x);
    const cy: f64 = @floatFromInt(screen_y);
    canvas.viewport.pan_x = cx / canvas.viewport.zoom - cx / old_zoom + canvas.viewport.pan_x;
    canvas.viewport.pan_y = cy / canvas.viewport.zoom - cy / old_zoom + canvas.viewport.pan_y;

    result.needs_redraw = true;
    return result;
}

// ---------------------------------------------------------------------------
// WM_RBUTTONDOWN — context menu hook (selection only for now)
// ---------------------------------------------------------------------------

pub fn onRightButtonDown(
    canvas: *CanvasState,
    screen_x: i32,
    screen_y: i32,
) InteractionResult {
    var result = InteractionResult{};
    const g = canvas.graph orelse return result;

    const cx: f64 = @floatFromInt(screen_x);
    const cy: f64 = @floatFromInt(screen_y);
    const prev_kind = canvas.selection.kind;
    const prev_idx = canvas.selection.index;

    const hit = hit_test.hitTest(g, canvas.selection, canvas.viewport, cx, cy);
    switch (hit.kind) {
        .node => canvas.selectNode(hit.index),
        .subgraph => canvas.selectSubgraph(hit.index),
        .edge => canvas.selectEdge(hit.index),
        else => {},
    }
    result.selection_changed = canvas.selection.kind != prev_kind or canvas.selection.index != prev_idx;
    result.needs_redraw = result.selection_changed;
    return result;
}

// ---------------------------------------------------------------------------
// WM_KEYDOWN
// ---------------------------------------------------------------------------

pub fn onKeyDown(
    canvas: *CanvasState,
    vkey: u16,
) InteractionResult {
    var result = InteractionResult{};
    switch (vkey) {
        @as(u16, @intCast(@intFromEnum(mouse.VK_ESCAPE))) => {
            if (canvas.insertionModeActive()) {
                canvas.cancelInsertion();
                result.needs_redraw = true;
            } else if (canvas.hasSelection()) {
                canvas.clearSelection();
                result.selection_changed = true;
                result.needs_redraw = true;
            }
        },
        @as(u16, @intCast(@intFromEnum(mouse.VK_DELETE))), @as(u16, @intCast(@intFromEnum(mouse.VK_BACK))) => {
            // Deletion: caller must handle full graph mutation via FFI.
            // Here we just clear the selection so the caller can act.
            if (canvas.hasSelection()) {
                result.selection_changed = true;
                result.document_mutated = true;
                result.needs_redraw = true;
            }
        },
        else => {},
    }
    return result;
}

pub fn nudgeSelectionOnGrid(canvas: *CanvasState, step_x: i32, step_y: i32) ?InteractionResult {
    if (!canvas.hasSelection()) return null;

    const moved = canvas.snapNudgeSelection(step_x, step_y, 10.0);
    return .{
        .needs_redraw = true,
        .selection_changed = moved,
        .document_mutated = moved,
    };
}

pub fn nudgeSelectionBy(canvas: *CanvasState, dx: f64, dy: f64) ?InteractionResult {
    if (!canvas.hasSelection()) return null;

    const moved = canvas.nudgeSelectionBy(dx, dy);
    return .{
        .needs_redraw = true,
        .selection_changed = moved,
        .document_mutated = moved,
    };
}

/// Move the entire graph (all nodes and subgraphs) by (dx, dy). Used for Ctrl+Arrow.
pub fn nudgeAllBy(canvas: *CanvasState, dx: f64, dy: f64) InteractionResult {
    const moved = canvas.nudgeAllBy(dx, dy);
    return .{
        .needs_redraw = moved,
        .selection_changed = false,
        .document_mutated = moved,
    };
}

/// Resize every node and subgraph by (dw, dh). Used for Alt+Arrow.
pub fn resizeAllBy(canvas: *CanvasState, dw: f64, dh: f64) InteractionResult {
    const resized = canvas.resizeAllBy(dw, dh);
    return .{
        .needs_redraw = resized,
        .selection_changed = false,
        .document_mutated = resized,
    };
}

// ---------------------------------------------------------------------------
// WM_MBUTTONDOWN — begin canvas pan
// ---------------------------------------------------------------------------

pub fn onMiddleButtonDown(
    canvas: *CanvasState,
    hwnd: ?foundation.HWND,
    screen_x: i32,
    screen_y: i32,
) InteractionResult {
    _ = mouse.SetCapture(hwnd);
    canvas.drag = .{
        .kind = .pan,
        .start_screen_x = screen_x,
        .start_screen_y = screen_y,
        .last_screen_x = screen_x,
        .last_screen_y = screen_y,
    };
    return InteractionResult{};
}

// ---------------------------------------------------------------------------
// WM_MBUTTONUP — end canvas pan
// ---------------------------------------------------------------------------

pub fn onMiddleButtonUp(canvas: *CanvasState) InteractionResult {
    var result = InteractionResult{};
    if (canvas.drag.kind == .pan) {
        canvas.drag = .{};
        _ = mouse.ReleaseCapture();
        result.needs_redraw = true;
    }
    return result;
}
