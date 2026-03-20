/// Hit-testing: given a canvas-space point, determine what was clicked.
/// All functions are pure and work only on the StudioEditableGraph data.
const std = @import("std");
const state = @import("state.zig");

const StudioEditableGraph = state.StudioEditableGraph;
const Selection = state.Selection;
const HandlePos = state.HandlePos;
const Viewport = state.Viewport;

// ---------------------------------------------------------------------------
// Constants
// ---------------------------------------------------------------------------

/// Pixel radius used to detect a click on a resize handle (in screen pixels).
pub const handle_hit_radius: f64 = 6.0;

/// Pixel tolerance for clicking on an edge polyline (in screen pixels).
pub const edge_hit_tolerance: f64 = 10.0;

const Shape = enum(u32) {
    rectangle = 0,
    rounded_rectangle = 1,
    parallelogram = 2,
    diamond = 3,
    stadium = 4,
    cylinder = 5,
    circle = 6,
    other = 0xffff_ffff,
    _,
};

// ---------------------------------------------------------------------------
// Hit-test result
// ---------------------------------------------------------------------------

pub const HitKind = enum(u8) {
    none,
    node,
    subgraph,
    edge,
    /// A resize handle on the currently selected node or subgraph.
    resize_handle,
};

pub const HitResult = struct {
    kind: HitKind = .none,
    index: usize = 0,
    handle: HandlePos = .bot_right,
};

// ---------------------------------------------------------------------------
// Bounding-box helpers
// ---------------------------------------------------------------------------

pub const Rect = struct {
    x: f64,
    y: f64,
    w: f64,
    h: f64,

    pub fn containsPoint(self: Rect, px: f64, py: f64) bool {
        return px >= self.x and px <= self.x + self.w and
            py >= self.y and py <= self.y + self.h;
    }
};

pub fn nodeRect(node: *const state.StudioEditableNode) Rect {
    return .{ .x = node.x, .y = node.y, .w = node.width, .h = node.height };
}

pub fn subgraphRect(sg: *const state.StudioEditableSubgraph) Rect {
    return .{ .x = sg.x, .y = sg.y, .w = sg.width, .h = sg.height };
}

/// Return the 8 handle positions (canvas coords) for a bounding rect.
const HandlePoint = struct { pos: HandlePos, cx: f64, cy: f64 };
pub fn handlesForRect(r: Rect) [8]HandlePoint {
    const mx = r.x + r.w / 2.0;
    const my = r.y + r.h / 2.0;
    const rx = r.x + r.w;
    const ry = r.y + r.h;
    return .{
        .{ .pos = .top_left, .cx = r.x, .cy = r.y },
        .{ .pos = .top_center, .cx = mx, .cy = r.y },
        .{ .pos = .top_right, .cx = rx, .cy = r.y },
        .{ .pos = .mid_left, .cx = r.x, .cy = my },
        .{ .pos = .mid_right, .cx = rx, .cy = my },
        .{ .pos = .bot_left, .cx = r.x, .cy = ry },
        .{ .pos = .bot_center, .cx = mx, .cy = ry },
        .{ .pos = .bot_right, .cx = rx, .cy = ry },
    };
}

// ---------------------------------------------------------------------------
// Main hit-test entry point
// ---------------------------------------------------------------------------

/// Test a canvas-space point against the graph.
/// Tests resize handles first (if something is selected), then nodes, then
/// subgraphs, then edges.
pub fn hitTest(
    graph: *const StudioEditableGraph,
    selection: Selection,
    viewport: Viewport,
    screen_x: f64,
    screen_y: f64,
) HitResult {
    const canvas_pt = viewport.screenToCanvas(screen_x, screen_y);
    const canvas_x = canvas_pt.x;
    const canvas_y = canvas_pt.y;

    // --- Resize handles (only when something that has a bounding box is selected) ---
    switch (selection.kind) {
        .node => {
            if (selection.index < graph.node_count) {
                const r = nodeRect(@ptrCast(&graph.nodes[selection.index]));
                for (handlesForRect(r)) |h| {
                    const screen_pt = viewport.canvasToScreen(h.cx, h.cy);
                    const dx = screen_x - screen_pt.x;
                    const dy = screen_y - screen_pt.y;
                    if (dx * dx + dy * dy <= handle_hit_radius * handle_hit_radius) {
                        return .{ .kind = .resize_handle, .index = selection.index, .handle = h.pos };
                    }
                }
            }
        },
        .subgraph => {
            if (selection.index < graph.subgraph_count) {
                const r = subgraphRect(@ptrCast(&graph.subgraphs[selection.index]));
                for (handlesForRect(r)) |h| {
                    const screen_pt = viewport.canvasToScreen(h.cx, h.cy);
                    const dx = screen_x - screen_pt.x;
                    const dy = screen_y - screen_pt.y;
                    if (dx * dx + dy * dy <= handle_hit_radius * handle_hit_radius) {
                        return .{ .kind = .resize_handle, .index = selection.index, .handle = h.pos };
                    }
                }
            }
        },
        else => {},
    }

    // --- Nodes (test in reverse order so later-drawn nodes are on top) ---
    if (graph.node_count > 0 and graph.nodes != null) {
        var ni: usize = graph.node_count;
        while (ni > 0) {
            ni -= 1;
            const node = &graph.nodes[ni];
            if (pointInNodeShape(@ptrCast(node), canvas_x, canvas_y)) {
                return .{ .kind = .node, .index = ni };
            }
        }
    }

    // --- Edges (polyline proximity) ---
    // Hit-test edges using segments clipped to node boundaries so the
    // clickable region matches the visible portion of the line.
    if (graph.edge_count > 0 and graph.edges != null) {
        for (graph.edges[0..graph.edge_count], 0..) |*edge, ei| {
            const src_centre = findNodeCentre(graph, edge.source_id);
            const dst_centre = findNodeCentre(graph, edge.target_id);
            if (src_centre == null or dst_centre == null) continue;
            const sc = src_centre.?;
            const dc = dst_centre.?;
            // Clip endpoints to node/subgraph boundaries.
            const src_rect = findNodeOrSubgraphRect(graph, edge.source_id);
            const dst_rect = findNodeOrSubgraphRect(graph, edge.target_id);
            const clipped_src = if (src_rect) |sr| clipPointToRectBorder(sc[0], sc[1], dc[0], dc[1], sr) else sc;
            const clipped_dst = if (dst_rect) |dr| clipPointToRectBorder(dc[0], dc[1], sc[0], sc[1], dr) else dc;
            const src_screen = viewport.canvasToScreen(clipped_src[0], clipped_src[1]);
            const dst_screen = viewport.canvasToScreen(clipped_dst[0], clipped_dst[1]);
            if (pointNearSegment(screen_x, screen_y, src_screen.x, src_screen.y, dst_screen.x, dst_screen.y, edge_hit_tolerance)) {
                return .{ .kind = .edge, .index = ei };
            }
        }
    }

    // --- Subgraphs (test in reverse order) ---
    if (graph.subgraph_count > 0 and graph.subgraphs != null) {
        var si: usize = graph.subgraph_count;
        while (si > 0) {
            si -= 1;
            const sg = &graph.subgraphs[si];
            const r = subgraphRect(@ptrCast(sg));
            if (pointInRoundedRect(r, sg.corner_radius, canvas_x, canvas_y)) {
                return .{ .kind = .subgraph, .index = si };
            }
        }
    }

    return .{};
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

fn findNodeCentre(graph: *const StudioEditableGraph, id: [*c]const u8) ?[2]f64 {
    if (id == null) return null;
    const id_slice = std.mem.span(id);
    if (graph.node_count > 0 and graph.nodes != null) {
        for (graph.nodes[0..graph.node_count]) |*n| {
            if (n.id == null) continue;
            if (std.mem.eql(u8, std.mem.span(n.id), id_slice)) {
                return .{ n.x + n.width / 2.0, n.y + n.height / 2.0 };
            }
        }
    }
    // Also check subgraphs (edges can connect to them).
    if (graph.subgraph_count > 0 and graph.subgraphs != null) {
        for (graph.subgraphs[0..graph.subgraph_count]) |*sg| {
            if (sg.id == null) continue;
            if (std.mem.eql(u8, std.mem.span(sg.id), id_slice)) {
                return .{ sg.x + sg.width / 2.0, sg.y + sg.height / 2.0 };
            }
        }
    }
    return null;
}

fn pointInNodeShape(node: *const state.StudioEditableNode, px: f64, py: f64) bool {
    const r = nodeRect(node);
    const shape: Shape = @enumFromInt(node.shape);
    return switch (shape) {
        .circle => pointInEllipse(r, px, py),
        .diamond => pointInDiamond(r, px, py),
        .rounded_rectangle => pointInRoundedRect(r, 8.0, px, py),
        .stadium => pointInStadium(r, px, py),
        else => r.containsPoint(px, py),
    };
}

fn pointInEllipse(r: Rect, px: f64, py: f64) bool {
    if (r.w <= 0 or r.h <= 0) return false;
    const rx = r.w / 2.0;
    const ry = r.h / 2.0;
    const cx = r.x + rx;
    const cy = r.y + ry;
    const nx = (px - cx) / rx;
    const ny = (py - cy) / ry;
    return nx * nx + ny * ny <= 1.0;
}

fn pointInDiamond(r: Rect, px: f64, py: f64) bool {
    if (r.w <= 0 or r.h <= 0) return false;
    const hw = r.w / 2.0;
    const hh = r.h / 2.0;
    const cx = r.x + hw;
    const cy = r.y + hh;
    return @abs((px - cx) / hw) + @abs((py - cy) / hh) <= 1.0;
}

fn pointInRoundedRect(r: Rect, radius: f64, px: f64, py: f64) bool {
    if (!r.containsPoint(px, py)) return false;
    const rr = @min(radius, @min(r.w, r.h) / 2.0);
    if (rr <= 0) return true;

    const inner_left = r.x + rr;
    const inner_right = r.x + r.w - rr;
    const inner_top = r.y + rr;
    const inner_bottom = r.y + r.h - rr;

    if (px >= inner_left and px <= inner_right) return true;
    if (py >= inner_top and py <= inner_bottom) return true;

    const corner_cx = if (px < inner_left) inner_left else inner_right;
    const corner_cy = if (py < inner_top) inner_top else inner_bottom;
    const dx = px - corner_cx;
    const dy = py - corner_cy;
    return dx * dx + dy * dy <= rr * rr;
}

fn pointInStadium(r: Rect, px: f64, py: f64) bool {
    return pointInRoundedRect(r, @min(r.w, r.h) / 2.0, px, py);
}

/// Find the bounding rect of a node or subgraph by its id.
pub fn findNodeOrSubgraphRect(graph: *const StudioEditableGraph, id: [*c]const u8) ?Rect {
    if (id == null) return null;
    const id_slice = std.mem.span(id);
    if (graph.node_count > 0 and graph.nodes != null) {
        for (graph.nodes[0..graph.node_count]) |*n| {
            if (n.id == null) continue;
            if (std.mem.eql(u8, std.mem.span(n.id), id_slice)) {
                return nodeRect(n);
            }
        }
    }
    if (graph.subgraph_count > 0 and graph.subgraphs != null) {
        for (graph.subgraphs[0..graph.subgraph_count]) |*sg| {
            if (sg.id == null) continue;
            if (std.mem.eql(u8, std.mem.span(sg.id), id_slice)) {
                return subgraphRect(sg);
            }
        }
    }
    return null;
}

/// Clip a line from (cx,cy) toward (tx,ty) to the border of rect r.
/// Returns the intersection point on the rect border.
pub fn clipPointToRectBorder(cx: f64, cy: f64, tx: f64, ty: f64, r: Rect) [2]f64 {
    const dx = tx - cx;
    const dy = ty - cy;
    if (@abs(dx) < 1e-9 and @abs(dy) < 1e-9) return .{ cx, cy };

    // Find the parametric t where the ray from centre hits the rect border.
    var t_min: f64 = std.math.floatMax(f64);
    // Right edge
    if (dx > 1e-9) {
        const t = (r.x + r.w - cx) / dx;
        if (t > 0 and t < t_min) t_min = t;
    }
    // Left edge
    if (dx < -1e-9) {
        const t = (r.x - cx) / dx;
        if (t > 0 and t < t_min) t_min = t;
    }
    // Bottom edge
    if (dy > 1e-9) {
        const t = (r.y + r.h - cy) / dy;
        if (t > 0 and t < t_min) t_min = t;
    }
    // Top edge
    if (dy < -1e-9) {
        const t = (r.y - cy) / dy;
        if (t > 0 and t < t_min) t_min = t;
    }
    if (t_min == std.math.floatMax(f64)) return .{ cx, cy };
    return .{ cx + dx * t_min, cy + dy * t_min };
}

/// Distance from point P to segment AB; returns true if within tolerance.
fn pointNearSegment(px: f64, py: f64, ax: f64, ay: f64, bx: f64, by: f64, tol: f64) bool {
    const dx = bx - ax;
    const dy = by - ay;
    const len2 = dx * dx + dy * dy;
    if (len2 < 1e-9) {
        // Degenerate segment — treat as a point.
        const dpx = px - ax;
        const dpy = py - ay;
        return dpx * dpx + dpy * dpy <= tol * tol;
    }
    const t = std.math.clamp(((px - ax) * dx + (py - ay) * dy) / len2, 0.0, 1.0);
    const nearest_x = ax + t * dx;
    const nearest_y = ay + t * dy;
    const ex = px - nearest_x;
    const ey = py - nearest_y;
    return ex * ex + ey * ey <= tol * tol;
}
