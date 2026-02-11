//! State diagram PNG renderer.
//!
//! Converts a `StateDiagram` model into a Dagre graph for layout, then
//! renders state nodes (start/end circles, fork/join bars, choice diamonds,
//! rounded rectangles) and transition edges with proper arrowheads to PNG
//! via the Canvas rasteriser.
//!
//! This replaces the earlier simplistic rank-based layout with the full
//! Dagre pipeline (network-simplex ranking, barycenter crossing minimisation,
//! Brandes-Köpf coordinate assignment) so that edges no longer cross
//! unnecessarily.

const std = @import("std");
const Allocator = std.mem.Allocator;
const StateDiagram = @import("model.zig").StateDiagram;
const StateType = @import("model.zig").StateType;
const NotePosition = @import("model.zig").NotePosition;
const state_model = @import("model.zig");
const Canvas = @import("../render/canvas.zig").Canvas;
const Font = @import("../render/text.zig").Font;

const Digraph = @import("../graph/digraph.zig").Digraph;
const layout_model = @import("../model.zig");
const NodeData = layout_model.NodeData;
const EdgeData = layout_model.EdgeData;
const GraphData = layout_model.GraphData;
const Point = layout_model.Point;
const dagre = @import("../layout/dagre.zig");
const normalize = @import("../layout/dagre/normalize.zig");

const Graph = Digraph(NodeData, EdgeData, GraphData);

// -----------------------------------------------------------------------
// Layout / rendering constants
// -----------------------------------------------------------------------

const MARGIN: f64 = 40.0;
const TITLE_FONT_SIZE: f64 = 20.0;
const LABEL_FONT_SIZE: f64 = 14.0;
const NOTE_FONT_SIZE: f64 = 11.0;
const EDGE_LABEL_FONT_SIZE: f64 = 11.0;
const CHAR_WIDTH: f64 = 8.0;
const LINE_HEIGHT: f64 = 20.0;
const STATE_PADDING_H: f64 = 20.0;
const STATE_PADDING_V: f64 = 12.0;
const STATE_MIN_WIDTH: f64 = 80.0;
const STATE_MIN_HEIGHT: f64 = 40.0;
const START_END_RADIUS: f64 = 7.0;
const FORK_JOIN_WIDTH: f64 = 70.0;
const FORK_JOIN_HEIGHT: f64 = 6.0;
const CHOICE_SIZE: f64 = 28.0;
const NOTE_WIDTH: f64 = 120.0;
const NOTE_PADDING: f64 = 8.0;
const ARROW_SIZE: f64 = 8.0;
const EDGE_STROKE_WIDTH: f64 = 2;
const NODESEP: f64 = 50.0;
const RANKSEP: f64 = 60.0;
const SCALE_FACTOR: f64 = 2.0;

// -----------------------------------------------------------------------
// Position / size types
// -----------------------------------------------------------------------

const Position = struct { x: f64, y: f64 };
const NodeSize = struct { w: f64, h: f64 };

// -----------------------------------------------------------------------
// Public API
// -----------------------------------------------------------------------

/// Render a `StateDiagram` to a PNG file at `output_path`.
pub fn renderStateToPNG(
    allocator: Allocator,
    diagram: *const StateDiagram,
    output_path: []const u8,
    maybe_font: ?*Font,
) !void {
    const mutable_diagram = @constCast(diagram);
    const state_count = mutable_diagram.states.count();

    // Handle empty diagram
    if (state_count == 0) {
        var canvas = try Canvas.initWithScale(allocator, 400, 200, SCALE_FACTOR);
        defer canvas.deinit();
        canvas.fill(255, 255, 255, 255);
        if (maybe_font) |font| {
            const msg = "(empty state diagram)";
            const tw = font.measureText(msg, @floatCast(LABEL_FONT_SIZE));
            font.drawText(&canvas, msg, @as(f32, @floatCast(200.0 - @as(f64, tw) / 2.0)), 90.0, @floatCast(LABEL_FONT_SIZE), 128, 128, 128, 255) catch {};
        }
        try canvas.saveToPNG(output_path);
        return;
    }

    // ── 1. Build Dagre graph ────────────────────────────────────
    var graph = Graph.init(allocator);
    defer {
        normalize.freeDummyIds(allocator, &graph);
        graph.deinitDeep();
    }

    // Collect all state IDs for stable iteration.
    var node_ids = std.ArrayListUnmanaged([]const u8){};
    defer {
        for (node_ids.items) |id| allocator.free(id);
        node_ids.deinit(allocator);
    }

    {
        var iter = mutable_diagram.states.iterator();
        while (iter.next()) |entry| {
            const id = try allocator.dupe(u8, entry.key_ptr.*);
            try node_ids.append(allocator, id);

            const state = entry.value_ptr;
            const size = computeStateSize(state);

            // If the state has a note, widen the node so Dagre reserves
            // enough horizontal space and the note doesn't overlap
            // neighbouring nodes.
            var effective_w = size.w;
            if (state.note) |note| {
                const ns = computeNoteSize(note.text);
                const note_gap: f64 = 15.0;
                effective_w += ns.w + note_gap;
            }

            try graph.setNode(entry.key_ptr.*, .{
                .label = state.displayLabel(),
                .width = effective_w,
                .height = size.h,
            });
        }
    }

    // Sort IDs for deterministic layout.
    std.mem.sort([]const u8, node_ids.items, {}, struct {
        fn cmp(_: void, a: []const u8, b: []const u8) bool {
            return std.mem.order(u8, a, b) == .lt;
        }
    }.cmp);

    // Set graph direction.
    var graph_label = graph.getGraphLabel();
    switch (diagram.direction) {
        .LR => graph_label.rankdir = "LR",
        .RL => graph_label.rankdir = "RL",
        .BT => graph_label.rankdir = "BT",
        .TB => graph_label.rankdir = "TB",
    }
    graph_label.nodesep = NODESEP;
    graph_label.ranksep = RANKSEP;

    // Add edges from relations.
    for (diagram.relations.items) |rel| {
        const edge_label = rel.label;
        try graph.setEdge(rel.from, rel.to, .{
            .label = if (edge_label != null and edge_label.?.len > 0) edge_label else null,
            .minlen = 1,
        }, null);
    }

    // ── 2. Run Dagre layout ─────────────────────────────────────
    const rankdir: dagre.RankDir = switch (diagram.direction) {
        .LR => .LR,
        .RL => .RL,
        .BT => .BT,
        .TB => .TB,
    };

    const config = dagre.DagreConfig{
        .rankdir = rankdir,
        .ranker = .network_simplex,
        .nodesep = NODESEP,
        .ranksep = RANKSEP,
    };

    try dagre.layout(allocator, &graph, config);

    // ── 3. Compute bounding box ─────────────────────────────────
    var min_x: f64 = std.math.floatMax(f64);
    var min_y: f64 = std.math.floatMax(f64);
    var max_x: f64 = -std.math.floatMax(f64);
    var max_y: f64 = -std.math.floatMax(f64);

    for (node_ids.items) |id| {
        if (graph.getNode(id)) |node| {
            const left = node.x - node.width / 2.0;
            const right = node.x + node.width / 2.0;
            const top = node.y - node.height / 2.0;
            const bottom = node.y + node.height / 2.0;
            if (left < min_x) min_x = left;
            if (right > max_x) max_x = right;
            if (top < min_y) min_y = top;
            if (bottom > max_y) max_y = bottom;

            // Include note in bounding box (use actual shape size, not
            // the inflated Dagre width, so the note box extent is correct).
            if (mutable_diagram.states.get(id)) |state| {
                if (state.note) |note| {
                    const shape_size = computeStateSize(&state);
                    const ns = computeNoteSize(note.text);
                    const note_gap: f64 = 15.0;
                    const half_shape_w = shape_size.w / 2.0;
                    if (note.position == .right_of) {
                        const nr = node.x + half_shape_w + note_gap + ns.w;
                        if (nr > max_x) max_x = nr;
                    } else {
                        const nl = node.x - half_shape_w - note_gap - ns.w;
                        if (nl < min_x) min_x = nl;
                    }
                    // Vertical extent of note
                    const note_top = node.y - ns.h / 2.0;
                    const note_bot = node.y + ns.h / 2.0;
                    if (note_top < min_y) min_y = note_top;
                    if (note_bot > max_y) max_y = note_bot;
                }
            }
        }
    }

    // Include edge points in bounding box.
    var edge_iter = graph.edgeIterator();
    while (edge_iter.next()) |entry| {
        for (entry.data.points.items) |pt| {
            if (pt.x < min_x) min_x = pt.x;
            if (pt.x > max_x) max_x = pt.x;
            if (pt.y < min_y) min_y = pt.y;
            if (pt.y > max_y) max_y = pt.y;
        }
    }

    if (min_x > max_x) {
        min_x = 0;
        max_x = 200;
        min_y = 0;
        max_y = 100;
    }

    const title_offset: f64 = if (diagram.title != null) 40.0 else 0.0;
    const canvas_width_f = (max_x - min_x) + MARGIN * 2;
    const canvas_height_f = (max_y - min_y) + MARGIN * 2 + title_offset;
    const canvas_w: u32 = @intFromFloat(@max(@ceil(canvas_width_f), 200.0));
    const canvas_h: u32 = @intFromFloat(@max(@ceil(canvas_height_f), 150.0));
    const offset_x = MARGIN - min_x;
    const offset_y = MARGIN - min_y + title_offset;

    // ── 4. Create canvas and draw ───────────────────────────────
    var canvas = try Canvas.initWithScale(allocator, canvas_w, canvas_h, SCALE_FACTOR);
    defer canvas.deinit();
    canvas.fill(255, 255, 255, 255);

    // Title
    if (diagram.title) |title| {
        if (maybe_font) |font| {
            const tw = font.measureText(title, @floatCast(TITLE_FONT_SIZE));
            const tx: f32 = @floatCast(@as(f64, @floatFromInt(canvas_w)) / 2.0 - @as(f64, tw) / 2.0);
            font.drawText(&canvas, title, tx, 10.0, @floatCast(TITLE_FONT_SIZE), 51, 51, 51, 255) catch {};
        }
    }

    // ── 4a. Draw edges (behind nodes) ───────────────────────────
    for (diagram.relations.items) |rel| {
        const ed = graph.edge(rel.from, rel.to, null);
        if (ed == null) continue;
        const edge_data = ed.?;

        const points = edge_data.points.items;

        // Get source and target node positions.
        const src_node = graph.getNode(rel.from);
        const tgt_node = graph.getNode(rel.to);

        const from_state_type = blk: {
            if (mutable_diagram.states.get(rel.from)) |s| break :blk s.state_type;
            break :blk StateType.default;
        };
        const to_state_type = blk: {
            if (mutable_diagram.states.get(rel.to)) |s| break :blk s.state_type;
            break :blk StateType.default;
        };

        // Build path: source border → intermediate Dagre points → target border.
        var path_points = std.ArrayListUnmanaged([2]f64){};
        defer path_points.deinit(allocator);

        if (src_node) |sn| {
            if (points.len > 0) {
                const clipped = computeExitPoint(
                    sn.x + offset_x,
                    sn.y + offset_y,
                    sn.width,
                    sn.height,
                    from_state_type,
                    points[0].x + offset_x,
                    points[0].y + offset_y,
                );
                try path_points.append(allocator, .{ clipped.x, clipped.y });
            } else if (tgt_node) |tn| {
                const clipped = computeExitPoint(
                    sn.x + offset_x,
                    sn.y + offset_y,
                    sn.width,
                    sn.height,
                    from_state_type,
                    tn.x + offset_x,
                    tn.y + offset_y,
                );
                try path_points.append(allocator, .{ clipped.x, clipped.y });
            }
        }

        for (points) |pt| {
            try path_points.append(allocator, .{ pt.x + offset_x, pt.y + offset_y });
        }

        if (tgt_node) |tn| {
            const last_x = if (points.len > 0) points[points.len - 1].x + offset_x else if (src_node) |sn| sn.x + offset_x else tn.x + offset_x;
            const last_y = if (points.len > 0) points[points.len - 1].y + offset_y else if (src_node) |sn| sn.y + offset_y else tn.y + offset_y;
            const clipped = computeEntryPoint(
                tn.x + offset_x,
                tn.y + offset_y,
                tn.width,
                tn.height,
                to_state_type,
                last_x,
                last_y,
            );
            try path_points.append(allocator, .{ clipped.x, clipped.y });
        }

        // Draw the polyline.
        const pp = path_points.items;
        if (pp.len >= 2) {
            for (0..pp.len - 1) |i| {
                canvas.drawLine(
                    pp[i][0],
                    pp[i][1],
                    pp[i + 1][0],
                    pp[i + 1][1],
                    @intFromFloat(EDGE_STROKE_WIDTH),
                    state_model.edge_color[0],
                    state_model.edge_color[1],
                    state_model.edge_color[2],
                    state_model.edge_color[3],
                );
            }

            // Arrowhead at the last segment.
            drawArrowhead(
                &canvas,
                pp[pp.len - 2][0],
                pp[pp.len - 2][1],
                pp[pp.len - 1][0],
                pp[pp.len - 1][1],
            );
        }

        // Edge label
        if (rel.label) |lbl| {
            if (maybe_font) |font| {
                // Place label at the midpoint of the edge.
                const mid_idx = pp.len / 2;
                var mid_x: f64 = 0;
                var mid_y: f64 = 0;
                if (pp.len >= 2 and mid_idx > 0) {
                    mid_x = (pp[mid_idx - 1][0] + pp[mid_idx][0]) / 2.0;
                    mid_y = (pp[mid_idx - 1][1] + pp[mid_idx][1]) / 2.0;
                } else if (pp.len >= 1) {
                    mid_x = pp[0][0];
                    mid_y = pp[0][1];
                }

                // Offset label perpendicular to the edge direction.
                var dx: f64 = 0;
                var dy: f64 = 1;
                if (pp.len >= 2 and mid_idx > 0) {
                    dx = pp[mid_idx][0] - pp[mid_idx - 1][0];
                    dy = pp[mid_idx][1] - pp[mid_idx - 1][1];
                }
                const len = @sqrt(dx * dx + dy * dy);
                const ox = if (len > 0) -dy / len * 10.0 else 0.0;
                const oy = if (len > 0) dx / len * 10.0 else 10.0;

                const lw = font.measureText(lbl, @floatCast(EDGE_LABEL_FONT_SIZE));
                const lx: f32 = @floatCast(mid_x + ox - @as(f64, lw) / 2.0);
                const ly: f32 = @floatCast(mid_y + oy - 6.0);
                font.drawText(&canvas, lbl, lx, ly, @floatCast(EDGE_LABEL_FONT_SIZE), state_model.text_color[0], state_model.text_color[1], state_model.text_color[2], state_model.text_color[3]) catch {};
            }
        }
    }

    // ── 4b. Draw nodes (on top of edges) ────────────────────────
    for (node_ids.items) |id| {
        const node = graph.getNode(id) orelse continue;
        const state = mutable_diagram.states.get(id) orelse continue;

        const cx = node.x + offset_x;
        const cy = node.y + offset_y;

        // Use original (non-inflated) size for drawing the actual shape.
        const size = computeStateSize(&state);

        renderStateNode(&canvas, &state, cx, cy, size.w, size.h, maybe_font);

        // Draw note
        if (state.note) |note| {
            renderNote(&canvas, note.position, note.text, cx, cy, size.w, maybe_font);
        }
    }

    try canvas.saveToPNG(output_path);
}

// -----------------------------------------------------------------------
// State size computation
// -----------------------------------------------------------------------

fn computeStateSize(state: *const state_model.State) NodeSize {
    return switch (state.state_type) {
        .start => .{ .w = START_END_RADIUS * 2, .h = START_END_RADIUS * 2 },
        .end => .{ .w = START_END_RADIUS * 2 + 4, .h = START_END_RADIUS * 2 + 4 },
        .fork, .join => .{ .w = FORK_JOIN_WIDTH, .h = FORK_JOIN_HEIGHT },
        .choice => .{ .w = CHOICE_SIZE, .h = CHOICE_SIZE },
        .divider => .{ .w = 40.0, .h = 4.0 },
        .default => {
            const label = state.displayLabel();
            const text_w = @as(f64, @floatFromInt(label.len)) * CHAR_WIDTH;
            const w = @max(text_w + STATE_PADDING_H * 2, STATE_MIN_WIDTH);
            var h = STATE_MIN_HEIGHT;
            if (state.descriptions.items.len > 0) {
                h += @as(f64, @floatFromInt(state.descriptions.items.len)) * LINE_HEIGHT;
            }
            return .{ .w = w, .h = h };
        },
    };
}

// -----------------------------------------------------------------------
// State node rendering
// -----------------------------------------------------------------------

fn renderStateNode(
    canvas: *Canvas,
    state: *const state_model.State,
    cx: f64,
    cy: f64,
    w: f64,
    h: f64,
    maybe_font: ?*Font,
) void {
    switch (state.state_type) {
        .start => {
            // Filled black circle
            canvas.fillEllipse(cx, cy, START_END_RADIUS, START_END_RADIUS, 0, 0, 0, 255);
        },
        .end => {
            // Outer ring
            canvas.strokeEllipse(cx, cy, START_END_RADIUS + 2, START_END_RADIUS + 2, 2, 0, 0, 0, 255);
            // Inner filled circle
            canvas.fillEllipse(cx, cy, START_END_RADIUS - 1, START_END_RADIUS - 1, 0, 0, 0, 255);
        },
        .fork, .join => {
            // Horizontal black bar
            canvas.fillRect(cx - w / 2.0, cy - h / 2.0, w, h, 0, 0, 0, 255);
        },
        .choice => {
            // Diamond
            canvas.fillDiamond(cx, cy, CHOICE_SIZE / 2.0, CHOICE_SIZE / 2.0, state_model.choice_fill[0], state_model.choice_fill[1], state_model.choice_fill[2], state_model.choice_fill[3]);
            canvas.strokeDiamond(cx, cy, CHOICE_SIZE / 2.0, CHOICE_SIZE / 2.0, 2, state_model.state_stroke_color[0], state_model.state_stroke_color[1], state_model.state_stroke_color[2], state_model.state_stroke_color[3]);
        },
        .divider => {
            // Dashed horizontal line
            canvas.drawDashedLine(cx - w / 2.0, cy, cx + w / 2.0, cy, 2, state_model.state_stroke_color[0], state_model.state_stroke_color[1], state_model.state_stroke_color[2], state_model.state_stroke_color[3], 4.0, 2.0);
        },
        .default => {
            // Rounded rectangle (fill then stroke)
            const rx = cx - w / 2.0;
            const ry = cy - h / 2.0;
            canvas.fillRect(rx, ry, w, h, state_model.state_fill_color[0], state_model.state_fill_color[1], state_model.state_fill_color[2], state_model.state_fill_color[3]);
            canvas.strokeRect(rx, ry, w, h, 2, state_model.state_stroke_color[0], state_model.state_stroke_color[1], state_model.state_stroke_color[2], state_model.state_stroke_color[3]);

            // Label text
            if (maybe_font) |font| {
                const label = state.displayLabel();
                const tw = font.measureText(label, @floatCast(LABEL_FONT_SIZE));
                const tx: f32 = @floatCast(cx - @as(f64, tw) / 2.0);
                const ty: f32 = @floatCast(cy - 7.0);
                font.drawText(canvas, label, tx, ty, @floatCast(LABEL_FONT_SIZE), state_model.text_color[0], state_model.text_color[1], state_model.text_color[2], state_model.text_color[3]) catch {};

                // Additional descriptions
                for (state.descriptions.items, 0..) |desc, i| {
                    const desc_y: f32 = @floatCast(cy + 8.0 + @as(f64, @floatFromInt(i)) * LINE_HEIGHT);
                    const dw = font.measureText(desc.data, @floatCast(NOTE_FONT_SIZE));
                    const dx: f32 = @floatCast(cx - @as(f64, dw) / 2.0);
                    font.drawText(canvas, desc.data, dx, desc_y, @floatCast(NOTE_FONT_SIZE), state_model.text_color[0], state_model.text_color[1], state_model.text_color[2], state_model.text_color[3]) catch {};
                }
            }
        },
    }
}

// -----------------------------------------------------------------------
// Arrowhead rendering
// -----------------------------------------------------------------------

fn drawArrowhead(canvas: *Canvas, from_x: f64, from_y: f64, to_x: f64, to_y: f64) void {
    const dx = to_x - from_x;
    const dy = to_y - from_y;
    const len = @sqrt(dx * dx + dy * dy);
    if (len < 0.001) return;

    const ux = dx / len;
    const uy = dy / len;
    const px = -uy;
    const py = ux;

    const arrow_len: f64 = ARROW_SIZE;
    const arrow_half_w: f64 = ARROW_SIZE / 2.5;

    // Draw the arrowhead as filled triangle
    const tip_x = to_x;
    const tip_y = to_y;
    const base1_x = to_x - ux * arrow_len + px * arrow_half_w;
    const base1_y = to_y - uy * arrow_len + py * arrow_half_w;
    const base2_x = to_x - ux * arrow_len - px * arrow_half_w;
    const base2_y = to_y - uy * arrow_len - py * arrow_half_w;

    // Fill by drawing many lines from base to tip
    const steps: usize = 12;
    var s: usize = 0;
    while (s <= steps) : (s += 1) {
        const t = @as(f64, @floatFromInt(s)) / @as(f64, @floatFromInt(steps));
        const bx = base1_x + (base2_x - base1_x) * t;
        const by = base1_y + (base2_y - base1_y) * t;
        canvas.drawLine(bx, by, tip_x, tip_y, 1, state_model.edge_color[0], state_model.edge_color[1], state_model.edge_color[2], state_model.edge_color[3]);
    }
}

// -----------------------------------------------------------------------
// Edge point computation
// -----------------------------------------------------------------------

fn computeExitPoint(cx: f64, cy: f64, w: f64, h: f64, state_type: StateType, target_x: f64, target_y: f64) Position {
    return switch (state_type) {
        .start => computeCircleIntersection(cx, cy, START_END_RADIUS, target_x, target_y),
        .end => computeCircleIntersection(cx, cy, START_END_RADIUS + 2, target_x, target_y),
        .choice => computeDiamondIntersection(cx, cy, CHOICE_SIZE / 2.0, target_x, target_y),
        .fork, .join => computeRectIntersection(cx, cy, w, h, target_x, target_y),
        .divider => .{ .x = cx, .y = cy },
        .default => computeRectIntersection(cx, cy, w, h, target_x, target_y),
    };
}

fn computeEntryPoint(cx: f64, cy: f64, w: f64, h: f64, state_type: StateType, source_x: f64, source_y: f64) Position {
    return switch (state_type) {
        .start => computeCircleIntersection(cx, cy, START_END_RADIUS, source_x, source_y),
        .end => computeCircleIntersection(cx, cy, START_END_RADIUS + 2, source_x, source_y),
        .choice => computeDiamondIntersection(cx, cy, CHOICE_SIZE / 2.0, source_x, source_y),
        .fork, .join => computeRectIntersection(cx, cy, w, h, source_x, source_y),
        .divider => .{ .x = cx, .y = cy },
        .default => computeRectIntersection(cx, cy, w, h, source_x, source_y),
    };
}

fn computeCircleIntersection(cx: f64, cy: f64, r: f64, tx: f64, ty: f64) Position {
    const dx = tx - cx;
    const dy = ty - cy;
    const len = @sqrt(dx * dx + dy * dy);
    if (len < 0.001) return .{ .x = cx, .y = cy + r };
    return .{
        .x = cx + dx / len * r,
        .y = cy + dy / len * r,
    };
}

fn computeRectIntersection(cx: f64, cy: f64, w: f64, h: f64, tx: f64, ty: f64) Position {
    const dx = tx - cx;
    const dy = ty - cy;
    const half_w = w / 2.0;
    const half_h = h / 2.0;

    if (@abs(dx) < 0.001 and @abs(dy) < 0.001) {
        return .{ .x = cx, .y = cy + half_h };
    }

    const abs_dx = @abs(dx);
    const abs_dy = @abs(dy);

    if (abs_dx * half_h > abs_dy * half_w) {
        const sign: f64 = if (dx > 0) 1.0 else -1.0;
        return .{
            .x = cx + sign * half_w,
            .y = cy + dy * half_w / abs_dx,
        };
    } else {
        const sign: f64 = if (dy > 0) 1.0 else -1.0;
        return .{
            .x = cx + dx * half_h / abs_dy,
            .y = cy + sign * half_h,
        };
    }
}

fn computeDiamondIntersection(cx: f64, cy: f64, half_size: f64, tx: f64, ty: f64) Position {
    const dx = tx - cx;
    const dy = ty - cy;

    if (@abs(dx) < 0.001 and @abs(dy) < 0.001) {
        return .{ .x = cx, .y = cy + half_size };
    }

    const abs_dx = @abs(dx);
    const abs_dy = @abs(dy);
    const sum = abs_dx + abs_dy;

    if (sum < 0.001) {
        return .{ .x = cx, .y = cy + half_size };
    }

    const t = half_size / sum;
    return .{
        .x = cx + dx * t,
        .y = cy + dy * t,
    };
}

// -----------------------------------------------------------------------
// Note size computation
// -----------------------------------------------------------------------

/// Compute the pixel size of a note box based on its text content.
/// Measures each line individually so multi-line notes get a width that
/// fits the longest line rather than using the total character count.
fn computeNoteSize(text: []const u8) NodeSize {
    var max_line_len: usize = 0;
    var cur_line_len: usize = 0;
    var line_count: usize = 1;

    for (text) |c| {
        if (c == '\n') {
            if (cur_line_len > max_line_len) max_line_len = cur_line_len;
            cur_line_len = 0;
            line_count += 1;
        } else {
            cur_line_len += 1;
        }
    }
    if (cur_line_len > max_line_len) max_line_len = cur_line_len;

    const note_text_w = @as(f64, @floatFromInt(max_line_len)) * 7.0;
    const note_w = note_text_w + NOTE_PADDING * 2;
    const note_h = @as(f64, @floatFromInt(line_count)) * 16.0 + NOTE_PADDING * 2;

    return .{ .w = note_w, .h = note_h };
}

// -----------------------------------------------------------------------
// Note rendering
// -----------------------------------------------------------------------

fn renderNote(
    canvas: *Canvas,
    position: NotePosition,
    text: []const u8,
    cx: f64,
    cy: f64,
    node_w: f64,
    maybe_font: ?*Font,
) void {
    const ns = computeNoteSize(text);
    const note_w = ns.w;
    const note_h = ns.h;

    const note_gap: f64 = 15.0;
    const note_x = switch (position) {
        .right_of => cx + node_w / 2.0 + note_gap,
        .left_of => cx - node_w / 2.0 - note_gap - note_w,
    };
    const note_y = cy - note_h / 2.0;

    // Note background (yellow)
    canvas.fillRect(note_x, note_y, note_w, note_h, state_model.note_fill[0], state_model.note_fill[1], state_model.note_fill[2], state_model.note_fill[3]);
    canvas.strokeRect(note_x, note_y, note_w, note_h, 1, state_model.note_stroke[0], state_model.note_stroke[1], state_model.note_stroke[2], state_model.note_stroke[3]);

    // Note text
    if (maybe_font) |font| {
        // Count lines for rendering
        var line_count: usize = 1;
        for (text) |c| {
            if (c == '\n') line_count += 1;
        }

        if (line_count == 1) {
            const tx: f32 = @floatCast(note_x + NOTE_PADDING);
            const ty: f32 = @floatCast(note_y + note_h / 2.0 - 6.0);
            font.drawText(canvas, text, tx, ty, @floatCast(NOTE_FONT_SIZE), state_model.text_color[0], state_model.text_color[1], state_model.text_color[2], state_model.text_color[3]) catch {};
        } else {
            var line_y: f64 = note_y + NOTE_PADDING;
            var start: usize = 0;
            for (text, 0..) |c, i| {
                if (c == '\n') {
                    const line_text = text[start..i];
                    font.drawText(canvas, line_text, @floatCast(note_x + NOTE_PADDING), @floatCast(line_y), @floatCast(NOTE_FONT_SIZE), state_model.text_color[0], state_model.text_color[1], state_model.text_color[2], state_model.text_color[3]) catch {};
                    line_y += 16.0;
                    start = i + 1;
                }
            }
            if (start < text.len) {
                font.drawText(canvas, text[start..], @floatCast(note_x + NOTE_PADDING), @floatCast(line_y), @floatCast(NOTE_FONT_SIZE), state_model.text_color[0], state_model.text_color[1], state_model.text_color[2], state_model.text_color[3]) catch {};
            }
        }
    }
}

// -----------------------------------------------------------------------
// Tests
// -----------------------------------------------------------------------

test "state png: renders without crash (no font)" {
    const allocator = std.testing.allocator;
    var diagram = StateDiagram.init(allocator);
    defer diagram.deinit();

    try diagram.addRelation("[*]", "Idle", null, null);
    try diagram.addRelation("Idle", "Active", "activate", null);
    try diagram.addRelation("Active", "[*]", null, null);

    try renderStateToPNG(allocator, &diagram, "/tmp/merrow_state_test.png", null);

    const stat = try std.fs.cwd().statFile("/tmp/merrow_state_test.png");
    try std.testing.expect(stat.size > 0);
}

test "state png: empty diagram renders without crash" {
    const allocator = std.testing.allocator;
    var diagram = StateDiagram.init(allocator);
    defer diagram.deinit();

    try renderStateToPNG(allocator, &diagram, "/tmp/merrow_state_empty_test.png", null);

    const stat = try std.fs.cwd().statFile("/tmp/merrow_state_empty_test.png");
    try std.testing.expect(stat.size > 0);
}

test "state png: special states render without crash" {
    const allocator = std.testing.allocator;
    var diagram = StateDiagram.init(allocator);
    defer diagram.deinit();

    _ = try diagram.addStateWithType("f1", .fork);
    _ = try diagram.addStateWithType("j1", .join);
    _ = try diagram.addStateWithType("c1", .choice);
    try diagram.addRelation("[*]", "f1", null, null);
    try diagram.addRelation("f1", "c1", null, null);
    try diagram.addRelation("c1", "j1", null, null);
    try diagram.addRelation("j1", "[*]", null, null);

    try renderStateToPNG(allocator, &diagram, "/tmp/merrow_state_special_test.png", null);

    const stat = try std.fs.cwd().statFile("/tmp/merrow_state_special_test.png");
    try std.testing.expect(stat.size > 0);
}

test "state png: with note renders without crash" {
    const allocator = std.testing.allocator;
    var diagram = StateDiagram.init(allocator);
    defer diagram.deinit();

    _ = try diagram.ensureState("Idle");
    try diagram.addNote("Idle", .right_of, "A note");

    try renderStateToPNG(allocator, &diagram, "/tmp/merrow_state_note_test.png", null);

    const stat = try std.fs.cwd().statFile("/tmp/merrow_state_note_test.png");
    try std.testing.expect(stat.size > 0);
}
