//! State diagram SVG renderer.
//!
//! Converts a `StateDiagram` model into a Dagre graph for layout, then
//! renders state nodes (start/end circles, fork/join bars, choice diamonds,
//! rounded rectangles) and transition edges with proper arrowheads to SVG.
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
const Direction = @import("model.zig").Direction;
const state_model = @import("model.zig");
const SvgWriter = @import("../render/svg.zig").SvgWriter;

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
const NOTE_FONT_SIZE: f64 = 12.0;
const EDGE_LABEL_FONT_SIZE: f64 = 12.0;
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
const EDGE_STROKE_WIDTH: f64 = 1.5;
const NODESEP: f64 = 50.0;
const RANKSEP: f64 = 60.0;

// -----------------------------------------------------------------------
// Position / size types
// -----------------------------------------------------------------------

const Position = struct { x: f64, y: f64 };
const NodeSize = struct { w: f64, h: f64 };

// -----------------------------------------------------------------------
// Public API
// -----------------------------------------------------------------------

/// Render a `StateDiagram` to SVG and write the result to a file at `output_path`.
pub fn renderStateToSVG(
    allocator: Allocator,
    diagram: *const StateDiagram,
    output_path: []const u8,
) !void {
    const svg_content = try renderStateToSVGString(allocator, diagram);
    defer allocator.free(svg_content);

    const file = try std.fs.cwd().createFile(output_path, .{});
    defer file.close();
    try file.writeAll(svg_content);
}

/// Render a `StateDiagram` to an SVG string. Caller owns the returned slice.
pub fn renderStateToSVGString(
    allocator: Allocator,
    diagram: *const StateDiagram,
) ![]u8 {
    const mutable_diagram = @constCast(diagram);
    const state_count = mutable_diagram.states.count();

    if (state_count == 0) {
        var svg = try SvgWriter.init(allocator, 400, 200);
        defer svg.deinit();
        if (diagram.title) |title| {
            try svg.textCentered(200, 30, title, TITLE_FONT_SIZE, state_model.text_color, "sans-serif");
        }
        try svg.textCentered(200, 100, "(empty state diagram)", LABEL_FONT_SIZE, .{ 128, 128, 128, 255 }, "sans-serif");
        return try svg.finalize();
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
    const svg_width = (max_x - min_x) + MARGIN * 2;
    const svg_height = (max_y - min_y) + MARGIN * 2 + title_offset;
    const offset_x = MARGIN - min_x;
    const offset_y = MARGIN - min_y + title_offset;

    // ── 4. Create SVG and draw ──────────────────────────────────
    var svg = try SvgWriter.init(allocator, @max(@ceil(svg_width), 200), @max(@ceil(svg_height), 150));
    defer svg.deinit();

    // Add arrow marker definition
    const marker_id = try svg.addArrowMarker(state_model.edge_color, ARROW_SIZE);
    allocator.free(marker_id);

    // Background
    try svg.rect(0, 0, @max(svg_width, 200), @max(svg_height, 150), 0, 0, .{ 255, 255, 255, 255 }, null, 0);

    // Title
    if (diagram.title) |title| {
        try svg.textCentered(
            svg_width / 2.0,
            30.0,
            title,
            TITLE_FONT_SIZE,
            state_model.text_color,
            "sans-serif",
        );
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
            try svg.polyline(pp, state_model.edge_color, EDGE_STROKE_WIDTH, null);

            // Arrowhead at the last segment.
            try renderArrowhead(
                &svg,
                pp[pp.len - 2][0],
                pp[pp.len - 2][1],
                pp[pp.len - 1][0],
                pp[pp.len - 1][1],
            );
        }

        // Edge label
        if (rel.label) |lbl| {
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

            // Draw background rect behind label for readability
            const label_w = @as(f64, @floatFromInt(lbl.len)) * 7.0 + 8.0;
            const label_h: f64 = 18.0;
            const bg_x = mid_x + ox - label_w / 2.0;
            const bg_y = mid_y + oy - label_h / 2.0;
            try svg.rect(bg_x, bg_y, label_w, label_h, 3, 3, .{ 255, 255, 255, 230 }, null, 0);

            try svg.textCentered(
                mid_x + ox,
                mid_y + oy,
                lbl,
                EDGE_LABEL_FONT_SIZE,
                state_model.text_color,
                "sans-serif",
            );
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

        try renderStateNode(&svg, &state, cx, cy, size.w, size.h);

        // Draw note if present
        if (state.note) |note| {
            try renderNote(&svg, note.position, note.text, cx, cy, size.w);
        }
    }

    return try svg.finalize();
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
            // Account for primary description too
            if (state.description != null) {
                if (state.descriptions.items.len == 0) {
                    h += LINE_HEIGHT;
                }
            }
            return .{ .w = w, .h = h };
        },
    };
}

// -----------------------------------------------------------------------
// State node rendering
// -----------------------------------------------------------------------

fn renderStateNode(
    svg: *SvgWriter,
    state: *const state_model.State,
    cx: f64,
    cy: f64,
    w: f64,
    h: f64,
) !void {
    switch (state.state_type) {
        .start => {
            // Filled black circle
            try svg.ellipse(cx, cy, START_END_RADIUS, START_END_RADIUS, state_model.start_end_fill, state_model.start_end_fill, 0);
        },
        .end => {
            // Bullseye: outer circle (stroke only) + inner filled circle
            try svg.ellipse(cx, cy, START_END_RADIUS + 2, START_END_RADIUS + 2, null, state_model.start_end_fill, 2);
            try svg.ellipse(cx, cy, START_END_RADIUS - 1, START_END_RADIUS - 1, state_model.start_end_fill, state_model.start_end_fill, 0);
        },
        .fork, .join => {
            // Horizontal black bar
            const bar_x = cx - w / 2.0;
            const bar_y = cy - h / 2.0;
            try svg.rect(bar_x, bar_y, w, h, 2, 2, state_model.fork_join_fill, state_model.fork_join_fill, 0);
        },
        .choice => {
            // Diamond shape
            const half = CHOICE_SIZE / 2.0;
            var points: [4][2]f64 = undefined;
            points[0] = .{ cx, cy - half }; // top
            points[1] = .{ cx + half, cy }; // right
            points[2] = .{ cx, cy + half }; // bottom
            points[3] = .{ cx - half, cy }; // left
            try svg.polygon(&points, state_model.choice_fill, state_model.state_stroke_color, 2);
        },
        .divider => {
            // Dashed horizontal line
            try svg.line(cx - w / 2.0, cy, cx + w / 2.0, cy, state_model.state_stroke_color, 2, "4 2");
        },
        .default => {
            // Rounded rectangle
            const rx = cx - w / 2.0;
            const ry = cy - h / 2.0;
            try svg.rect(rx, ry, w, h, 8, 8, state_model.state_fill_color, state_model.state_stroke_color, 2);

            // Label text (always the id or alias)
            const label = state.displayLabel();
            const descs = state.allDescriptions();
            const has_descs = state.hasDescriptions();
            if (has_descs) {
                // Label at top, then separator, then descriptions
                const label_y = ry + STATE_PADDING_V + 7;
                try svg.textCentered(cx, label_y, label, LABEL_FONT_SIZE, state_model.text_color, "sans-serif");

                // Separator line
                const sep_y = label_y + 10;
                try svg.line(rx, sep_y, rx + w, sep_y, state_model.state_stroke_color, 1, null);

                // Draw descriptions: primary first, then additional
                var desc_idx: usize = 0;
                if (descs.primary) |primary| {
                    const desc_y = sep_y + 4 + (@as(f64, @floatFromInt(desc_idx)) + 1) * LINE_HEIGHT - LINE_HEIGHT / 2;
                    try svg.textCentered(cx, desc_y, primary, NOTE_FONT_SIZE, state_model.text_color, "sans-serif");
                    desc_idx += 1;
                }
                for (descs.extra) |extra| {
                    const desc_y = sep_y + 4 + (@as(f64, @floatFromInt(desc_idx)) + 1) * LINE_HEIGHT - LINE_HEIGHT / 2;
                    try svg.textCentered(cx, desc_y, extra.data, NOTE_FONT_SIZE, state_model.text_color, "sans-serif");
                    desc_idx += 1;
                }
            } else {
                try svg.textCentered(cx, cy, label, LABEL_FONT_SIZE, state_model.text_color, "sans-serif");
            }
        },
    }
}

// -----------------------------------------------------------------------
// Arrowhead rendering
// -----------------------------------------------------------------------

fn renderArrowhead(
    svg: *SvgWriter,
    from_x: f64,
    from_y: f64,
    to_x: f64,
    to_y: f64,
) !void {
    const dx = to_x - from_x;
    const dy = to_y - from_y;
    const len = @sqrt(dx * dx + dy * dy);
    if (len < 0.001) return;

    // Unit vector along edge direction
    const ux = dx / len;
    const uy = dy / len;

    // Perpendicular unit vector
    const px = -uy;
    const py = ux;

    const arrow_len: f64 = ARROW_SIZE;
    const arrow_half_w: f64 = ARROW_SIZE / 2.5;

    // Arrow tip is at (to_x, to_y)
    // Base points are behind the tip
    var points: [3][2]f64 = undefined;
    points[0] = .{ to_x, to_y }; // tip
    points[1] = .{ to_x - ux * arrow_len + px * arrow_half_w, to_y - uy * arrow_len + py * arrow_half_w };
    points[2] = .{ to_x - ux * arrow_len - px * arrow_half_w, to_y - uy * arrow_len - py * arrow_half_w };

    try svg.polygon(&points, state_model.edge_color, state_model.edge_color, 0);
}

// -----------------------------------------------------------------------
// Edge point computation
// -----------------------------------------------------------------------

/// Compute the exit point from a node towards a target
fn computeExitPoint(
    cx: f64,
    cy: f64,
    w: f64,
    h: f64,
    state_type: StateType,
    target_x: f64,
    target_y: f64,
) Position {
    return switch (state_type) {
        .start => computeCircleIntersection(cx, cy, START_END_RADIUS, target_x, target_y),
        .end => computeCircleIntersection(cx, cy, START_END_RADIUS + 2, target_x, target_y),
        .choice => computeDiamondIntersection(cx, cy, CHOICE_SIZE / 2.0, target_x, target_y),
        .fork, .join => computeRectIntersection(cx, cy, w, h, target_x, target_y),
        .divider => .{ .x = cx, .y = cy },
        .default => computeRectIntersection(cx, cy, w, h, target_x, target_y),
    };
}

/// Compute the entry point into a node from a source
fn computeEntryPoint(
    cx: f64,
    cy: f64,
    w: f64,
    h: f64,
    state_type: StateType,
    source_x: f64,
    source_y: f64,
) Position {
    return switch (state_type) {
        .start => computeCircleIntersection(cx, cy, START_END_RADIUS, source_x, source_y),
        .end => computeCircleIntersection(cx, cy, START_END_RADIUS + 2, source_x, source_y),
        .choice => computeDiamondIntersection(cx, cy, CHOICE_SIZE / 2.0, source_x, source_y),
        .fork, .join => computeRectIntersection(cx, cy, w, h, source_x, source_y),
        .divider => .{ .x = cx, .y = cy },
        .default => computeRectIntersection(cx, cy, w, h, source_x, source_y),
    };
}

/// Compute intersection of a line from (cx,cy) to (tx,ty) with a circle of radius r centered at (cx,cy)
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

/// Compute intersection of a line from (cx,cy) to (tx,ty) with a rectangle centered at (cx,cy)
fn computeRectIntersection(cx: f64, cy: f64, w: f64, h: f64, tx: f64, ty: f64) Position {
    const dx = tx - cx;
    const dy = ty - cy;
    const half_w = w / 2.0;
    const half_h = h / 2.0;

    if (@abs(dx) < 0.001 and @abs(dy) < 0.001) {
        return .{ .x = cx, .y = cy + half_h };
    }

    // Determine which edge the line exits through
    const abs_dx = @abs(dx);
    const abs_dy = @abs(dy);

    if (abs_dx * half_h > abs_dy * half_w) {
        // Exits through left or right edge
        const sign: f64 = if (dx > 0) 1.0 else -1.0;
        return .{
            .x = cx + sign * half_w,
            .y = cy + dy * half_w / abs_dx,
        };
    } else {
        // Exits through top or bottom edge
        const sign: f64 = if (dy > 0) 1.0 else -1.0;
        return .{
            .x = cx + dx * half_h / abs_dy,
            .y = cy + sign * half_h,
        };
    }
}

/// Compute intersection of a line from (cx,cy) to (tx,ty) with a diamond centered at (cx,cy)
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

    // Diamond edge: |x - cx| / half_size + |y - cy| / half_size = 1
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
    svg: *SvgWriter,
    position: NotePosition,
    text: []const u8,
    cx: f64,
    cy: f64,
    node_w: f64,
) !void {
    const ns = computeNoteSize(text);
    const note_w = ns.w;
    const note_h = ns.h;

    // Position the note
    const note_gap: f64 = 15.0;
    const note_x = switch (position) {
        .right_of => cx + node_w / 2.0 + note_gap,
        .left_of => cx - node_w / 2.0 - note_gap - note_w,
    };
    const note_y = cy - note_h / 2.0;

    // Draw note rectangle (yellow sticky note style)
    try svg.rect(
        note_x,
        note_y,
        note_w,
        note_h,
        2,
        2,
        state_model.note_fill,
        state_model.note_stroke,
        1,
    );

    // Draw folded corner effect
    const fold_size: f64 = 8.0;
    const fold_x = note_x + note_w - fold_size;
    const fold_y = note_y;
    var fold_points: [3][2]f64 = undefined;
    fold_points[0] = .{ fold_x, fold_y };
    fold_points[1] = .{ fold_x, fold_y + fold_size };
    fold_points[2] = .{ fold_x + fold_size, fold_y + fold_size };
    try svg.polygon(&fold_points, .{ 240, 240, 200, 255 }, state_model.note_stroke, 1);

    // Count lines for rendering
    var line_count: usize = 1;
    for (text) |c| {
        if (c == '\n') line_count += 1;
    }

    // Draw note text (handle newlines)
    if (line_count == 1) {
        try svg.textAt(
            note_x + NOTE_PADDING,
            note_y + note_h / 2.0,
            text,
            NOTE_FONT_SIZE,
            state_model.text_color,
            "sans-serif",
            .start,
        );
    } else {
        // Multi-line: split on newlines and draw each line
        var line_y = note_y + NOTE_PADDING + 8.0;
        var start: usize = 0;
        for (text, 0..) |c, i| {
            if (c == '\n') {
                const line_text = text[start..i];
                try svg.textAt(
                    note_x + NOTE_PADDING,
                    line_y,
                    line_text,
                    NOTE_FONT_SIZE,
                    state_model.text_color,
                    "sans-serif",
                    .start,
                );
                line_y += 16.0;
                start = i + 1;
            }
        }
        // Last line
        if (start < text.len) {
            try svg.textAt(
                note_x + NOTE_PADDING,
                line_y,
                text[start..],
                NOTE_FONT_SIZE,
                state_model.text_color,
                "sans-serif",
                .start,
            );
        }
    }
}

// -----------------------------------------------------------------------
// Tests
// -----------------------------------------------------------------------

test "state svg: renders empty diagram" {
    const allocator = std.testing.allocator;
    var diagram = StateDiagram.init(allocator);
    defer diagram.deinit();

    const result = try renderStateToSVGString(allocator, &diagram);
    defer allocator.free(result);

    try std.testing.expect(result.len > 0);
    try std.testing.expect(std.mem.indexOf(u8, result, "<svg") != null);
    try std.testing.expect(std.mem.indexOf(u8, result, "empty state diagram") != null);
}

test "state svg: renders simple transitions" {
    const allocator = std.testing.allocator;
    var diagram = StateDiagram.init(allocator);
    defer diagram.deinit();

    try diagram.addRelation("[*]", "Idle", null, null);
    try diagram.addRelation("Idle", "Active", "activate", null);
    try diagram.addRelation("Active", "[*]", null, null);

    const result = try renderStateToSVGString(allocator, &diagram);
    defer allocator.free(result);

    try std.testing.expect(result.len > 0);
    try std.testing.expect(std.mem.indexOf(u8, result, "<svg") != null);
}

test "state svg: renders with title" {
    const allocator = std.testing.allocator;
    var diagram = StateDiagram.init(allocator);
    defer diagram.deinit();

    try diagram.setTitle("My State Machine");
    try diagram.addRelation("[*]", "Start", null, null);

    const result = try renderStateToSVGString(allocator, &diagram);
    defer allocator.free(result);

    try std.testing.expect(std.mem.indexOf(u8, result, "My State Machine") != null);
}

test "state svg: renders special state types" {
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

    const result = try renderStateToSVGString(allocator, &diagram);
    defer allocator.free(result);

    try std.testing.expect(result.len > 0);
}

test "state svg: renders note" {
    const allocator = std.testing.allocator;
    var diagram = StateDiagram.init(allocator);
    defer diagram.deinit();

    _ = try diagram.ensureState("Idle");
    try diagram.addNote("Idle", .right_of, "A note");

    const result = try renderStateToSVGString(allocator, &diagram);
    defer allocator.free(result);

    try std.testing.expect(std.mem.indexOf(u8, result, "A note") != null);
}

test "state svg: renders descriptions" {
    const allocator = std.testing.allocator;
    var diagram = StateDiagram.init(allocator);
    defer diagram.deinit();

    _ = try diagram.ensureState("Active");
    try diagram.addDescription("Active", "Doing stuff");

    const result = try renderStateToSVGString(allocator, &diagram);
    defer allocator.free(result);

    try std.testing.expect(std.mem.indexOf(u8, result, "Active") != null);
}

test "state svg: computeCircleIntersection" {
    const p = computeCircleIntersection(100, 100, 10, 200, 100);
    try std.testing.expectApproxEqAbs(p.x, 110.0, 0.1);
    try std.testing.expectApproxEqAbs(p.y, 100.0, 0.1);
}

test "state svg: computeRectIntersection" {
    // Target is directly to the right
    const p = computeRectIntersection(100, 100, 60, 40, 200, 100);
    try std.testing.expectApproxEqAbs(p.x, 130.0, 0.1);
    try std.testing.expectApproxEqAbs(p.y, 100.0, 0.1);

    // Target is directly below
    const p2 = computeRectIntersection(100, 100, 60, 40, 100, 200);
    try std.testing.expectApproxEqAbs(p2.x, 100.0, 0.1);
    try std.testing.expectApproxEqAbs(p2.y, 120.0, 0.1);
}

test "state svg: computeDiamondIntersection" {
    const p = computeDiamondIntersection(100, 100, 20, 120, 100);
    try std.testing.expectApproxEqAbs(p.x, 120.0, 0.1);
}

test "state svg: direction LR layout" {
    const allocator = std.testing.allocator;
    var diagram = StateDiagram.init(allocator);
    defer diagram.deinit();

    diagram.direction = .LR;
    try diagram.addRelation("[*]", "A", null, null);
    try diagram.addRelation("A", "[*]", null, null);

    const result = try renderStateToSVGString(allocator, &diagram);
    defer allocator.free(result);

    try std.testing.expect(result.len > 0);
}

test "state svg: write to file" {
    const allocator = std.testing.allocator;
    var diagram = StateDiagram.init(allocator);
    defer diagram.deinit();

    try diagram.addRelation("[*]", "Ready", null, null);

    try renderStateToSVG(allocator, &diagram, "/tmp/merrow_state_svg_test.svg");

    const stat = try std.fs.cwd().statFile("/tmp/merrow_state_svg_test.svg");
    try std.testing.expect(stat.size > 0);
}
