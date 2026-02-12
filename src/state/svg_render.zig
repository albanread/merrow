//! State diagram SVG renderer.
//!
//! Converts a `StateDiagram` model into a Dagre graph for layout, then
//! renders state nodes (start/end circles, fork/join bars, choice diamonds,
//! rounded rectangles) and transition edges with proper arrowheads to SVG.
//!
//! Supports:
//!   - Composite (nested) states rendered as container boxes with headers
//!   - Note callout lines connecting notes to their parent state
//!   - Full Dagre pipeline for crossing minimisation

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

// Composite state rendering constants
const COMPOSITE_PADDING: f64 = 16.0;
const COMPOSITE_HEADER_HEIGHT: f64 = 30.0;
const COMPOSITE_CORNER_RADIUS: f64 = 8.0;

// Note callout constants
const NOTE_CALLOUT_GAP: f64 = 15.0;
const NOTE_CALLOUT_DASH: f64 = 4.0;
const NOTE_CALLOUT_COLOR = state_model.note_stroke;

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

    // ── 0. Identify composite states ────────────────────────────
    // A composite state is any state that is the parent of other states.
    var composite_set = std.StringHashMap(void).init(allocator);
    defer composite_set.deinit();

    {
        var iter = mutable_diagram.states.iterator();
        while (iter.next()) |entry| {
            const state = entry.value_ptr;
            if (state.parent) |p| {
                try composite_set.put(p, {});
            }
        }
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
            const is_composite = composite_set.contains(entry.key_ptr.*);

            if (is_composite) {
                // Composite states become subgraph container nodes.
                // Give them a minimal size — bounds will be computed from children.
                try graph.setNode(entry.key_ptr.*, .{
                    .label = state.displayLabel(),
                    .width = 0,
                    .height = 0,
                    .is_subgraph = true,
                    .subgraph_title = state.displayLabel(),
                    .subgraph_padding = COMPOSITE_PADDING,
                });
            } else {
                const size = computeStateSize(state);

                // If the state has a note, widen the node so Dagre reserves
                // enough horizontal space and the note doesn't overlap
                // neighbouring nodes.
                var effective_w = size.w;
                if (state.note) |note| {
                    const ns = computeNoteSize(note.text);
                    const note_gap: f64 = NOTE_CALLOUT_GAP;
                    effective_w += ns.w + note_gap;
                }

                try graph.setNode(entry.key_ptr.*, .{
                    .label = state.displayLabel(),
                    .width = effective_w,
                    .height = size.h,
                });
            }
        }
    }

    // Set parent relationships for composite states.
    {
        var iter = mutable_diagram.states.iterator();
        while (iter.next()) |entry| {
            const state = entry.value_ptr;
            if (state.parent) |p| {
                // Only set parent if parent node exists in graph
                if (graph.getNode(p) != null) {
                    try graph.setParent(entry.key_ptr.*, p);
                }
            }
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
            const is_composite = composite_set.contains(id);
            if (!is_composite) {
                if (mutable_diagram.states.get(id)) |state| {
                    if (state.note) |note| {
                        const shape_size = computeStateSize(&state);
                        const ns = computeNoteSize(note.text);
                        const half_shape_w = shape_size.w / 2.0;
                        if (note.position == .right_of) {
                            const nr = node.x + half_shape_w + NOTE_CALLOUT_GAP + ns.w;
                            if (nr > max_x) max_x = nr;
                        } else {
                            const nl = node.x - half_shape_w - NOTE_CALLOUT_GAP - ns.w;
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

    // ── 4a. Draw composite state containers (behind everything) ─
    // Sort composites so outermost are drawn first (parents before children).
    var composite_ids = std.ArrayListUnmanaged([]const u8){};
    defer composite_ids.deinit(allocator);

    {
        var cit = composite_set.iterator();
        while (cit.next()) |entry| {
            try composite_ids.append(allocator, entry.key_ptr.*);
        }
    }

    // Sort by nesting depth (outermost first): states with no parent first,
    // then states whose parent is not composite, etc.
    // Simple approach: sort by counting ancestor depth.
    if (composite_ids.items.len > 1) {
        const SortCtx = struct {
            diagram_ptr: *const StateDiagram,

            fn depth(self: @This(), id: []const u8) usize {
                var d: usize = 0;
                var current = id;
                const md = @constCast(self.diagram_ptr);
                while (true) {
                    if (md.states.get(current)) |s| {
                        if (s.parent) |p| {
                            d += 1;
                            current = p;
                        } else break;
                    } else break;
                }
                return d;
            }

            fn lessThan(self: @This(), a: []const u8, b: []const u8) bool {
                const da = self.depth(a);
                const db = self.depth(b);
                if (da != db) return da < db;
                return std.mem.order(u8, a, b) == .lt;
            }
        };
        const ctx = SortCtx{ .diagram_ptr = diagram };
        std.mem.sort([]const u8, composite_ids.items, ctx, SortCtx.lessThan);
    }

    for (composite_ids.items) |comp_id| {
        const node = graph.getNode(comp_id) orelse continue;
        const state = mutable_diagram.states.get(comp_id) orelse continue;

        const cx = node.x + offset_x;
        const cy = node.y + offset_y;
        const w = node.width;
        const h = node.height;

        try renderCompositeBox(&svg, &state, cx, cy, w, h);
    }

    // ── 4b. Draw edges (behind regular nodes) ───────────────────
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

        // Check if source or target is composite — use the container box for clipping
        const from_is_composite = composite_set.contains(rel.from);
        const to_is_composite = composite_set.contains(rel.to);

        // Build path: source border → intermediate Dagre points → target border.
        var path_points = std.ArrayListUnmanaged([2]f64){};
        defer path_points.deinit(allocator);

        if (src_node) |sn| {
            const src_w = if (from_is_composite) sn.width else computeStateSizeById(mutable_diagram, rel.from).w;
            const src_h = if (from_is_composite) sn.height else computeStateSizeById(mutable_diagram, rel.from).h;
            if (points.len > 0) {
                const clipped = computeExitPoint(
                    sn.x + offset_x,
                    sn.y + offset_y,
                    src_w,
                    src_h,
                    if (from_is_composite) StateType.default else from_state_type,
                    points[0].x + offset_x,
                    points[0].y + offset_y,
                );
                try path_points.append(allocator, .{ clipped.x, clipped.y });
            } else if (tgt_node) |tn| {
                const clipped = computeExitPoint(
                    sn.x + offset_x,
                    sn.y + offset_y,
                    src_w,
                    src_h,
                    if (from_is_composite) StateType.default else from_state_type,
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
            const tgt_w = if (to_is_composite) tn.width else computeStateSizeById(mutable_diagram, rel.to).w;
            const tgt_h = if (to_is_composite) tn.height else computeStateSizeById(mutable_diagram, rel.to).h;
            const last_x = if (points.len > 0) points[points.len - 1].x + offset_x else if (src_node) |sn| sn.x + offset_x else tn.x + offset_x;
            const last_y = if (points.len > 0) points[points.len - 1].y + offset_y else if (src_node) |sn| sn.y + offset_y else tn.y + offset_y;
            const clipped = computeEntryPoint(
                tn.x + offset_x,
                tn.y + offset_y,
                tgt_w,
                tgt_h,
                if (to_is_composite) StateType.default else to_state_type,
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

    // ── 4c. Draw regular (non-composite) nodes ──────────────────
    for (node_ids.items) |id| {
        // Skip composite states — they were drawn as containers above
        if (composite_set.contains(id)) continue;

        const node = graph.getNode(id) orelse continue;
        const state = mutable_diagram.states.get(id) orelse continue;

        const cx = node.x + offset_x;
        const cy = node.y + offset_y;

        // Use original (non-inflated) size for drawing the actual shape.
        const size = computeStateSize(&state);

        try renderStateNode(&svg, &state, cx, cy, size.w, size.h);

        // Draw note with callout line if present
        if (state.note) |note| {
            try renderNoteWithCallout(&svg, note.position, note.text, cx, cy, size.w, size.h);
        }
    }

    // ── 4d. Draw notes attached to composite states ─────────────
    for (composite_ids.items) |comp_id| {
        const state = mutable_diagram.states.get(comp_id) orelse continue;
        if (state.note) |note| {
            const node = graph.getNode(comp_id) orelse continue;
            const cx = node.x + offset_x;
            const cy = node.y + offset_y;
            try renderNoteWithCallout(&svg, note.position, note.text, cx, cy, node.width, node.height);
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

/// Compute the size of a state by looking it up in the diagram by ID.
/// Falls back to a reasonable default if the state is not found.
fn computeStateSizeById(diagram: *StateDiagram, id: []const u8) NodeSize {
    if (diagram.states.get(id)) |state| {
        return computeStateSize(&state);
    }
    return .{ .w = STATE_MIN_WIDTH, .h = STATE_MIN_HEIGHT };
}

// -----------------------------------------------------------------------
// Composite state box rendering
// -----------------------------------------------------------------------

fn renderCompositeBox(
    svg: *SvgWriter,
    state: *const state_model.State,
    cx: f64,
    cy: f64,
    w: f64,
    h: f64,
) !void {
    const rx = cx - w / 2.0;
    const ry = cy - h / 2.0;

    // Outer rounded rectangle (the container)
    try svg.rect(
        rx,
        ry,
        w,
        h,
        COMPOSITE_CORNER_RADIUS,
        COMPOSITE_CORNER_RADIUS,
        .{ 255, 255, 255, 255 }, // white fill
        state_model.state_stroke_color,
        2,
    );

    // Header background bar (colored strip at the top)
    // Clip to the rounded corners by drawing a smaller rect
    const header_h = COMPOSITE_HEADER_HEIGHT;
    try svg.rect(
        rx,
        ry,
        w,
        header_h,
        COMPOSITE_CORNER_RADIUS,
        COMPOSITE_CORNER_RADIUS,
        state_model.composite_header_fill,
        state_model.state_stroke_color,
        1,
    );

    // Draw a thin rectangle to fill the gap below rounded header corners
    if (header_h < h) {
        try svg.rect(
            rx,
            ry + header_h - COMPOSITE_CORNER_RADIUS,
            w,
            COMPOSITE_CORNER_RADIUS,
            0,
            0,
            state_model.composite_header_fill,
            null,
            0,
        );
    }

    // Separator line between header and body
    try svg.line(
        rx,
        ry + header_h,
        rx + w,
        ry + header_h,
        state_model.state_stroke_color,
        1.0,
        null,
    );

    // Header label
    const label = state.displayLabel();
    try svg.textCentered(
        cx,
        ry + header_h / 2.0 + 1.0,
        label,
        LABEL_FONT_SIZE,
        state_model.text_color,
        "sans-serif",
    );

    // Description below header if present
    if (state.description) |desc| {
        try svg.textCentered(
            cx,
            ry + header_h + 14.0,
            desc,
            NOTE_FONT_SIZE,
            .{ 100, 100, 100, 255 },
            "sans-serif",
        );
    }
}

// -----------------------------------------------------------------------
// State node rendering (non-composite)
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
            try svg.ellipse(cx, cy, START_END_RADIUS, START_END_RADIUS, state_model.start_end_fill, null, 0);
        },
        .end => {
            // Outer ring
            try svg.ellipse(cx, cy, START_END_RADIUS + 2, START_END_RADIUS + 2, null, state_model.start_end_fill, 2);
            // Inner filled circle
            try svg.ellipse(cx, cy, START_END_RADIUS - 1, START_END_RADIUS - 1, state_model.start_end_fill, null, 0);
        },
        .fork, .join => {
            // Horizontal black bar
            try svg.rect(cx - w / 2.0, cy - h / 2.0, w, h, 0, 0, state_model.fork_join_fill, null, 0);
        },
        .choice => {
            // Diamond shape (rotated square)
            const half = CHOICE_SIZE / 2.0;
            var diamond_pts: [4][2]f64 = undefined;
            diamond_pts[0] = .{ cx, cy - half }; // top
            diamond_pts[1] = .{ cx + half, cy }; // right
            diamond_pts[2] = .{ cx, cy + half }; // bottom
            diamond_pts[3] = .{ cx - half, cy }; // left
            try svg.polygon(&diamond_pts, state_model.choice_fill, state_model.state_stroke_color, 2);
        },
        .divider => {
            // Dashed horizontal line
            try svg.line(
                cx - w / 2.0,
                cy,
                cx + w / 2.0,
                cy,
                state_model.state_stroke_color,
                2.0,
                "4,2",
            );
        },
        .default => {
            // Rounded rectangle
            const rx = cx - w / 2.0;
            const ry = cy - h / 2.0;
            try svg.rect(rx, ry, w, h, 5, 5, state_model.state_fill_color, state_model.state_stroke_color, 2);

            // Label text
            const label = state.displayLabel();
            // If there are descriptions, shift label up slightly
            const has_extra = state.descriptions.items.len > 0 or state.description != null;
            const label_y = if (has_extra) cy - 5.0 else cy;
            try svg.textCentered(cx, label_y, label, LABEL_FONT_SIZE, state_model.text_color, "sans-serif");

            // Primary description
            if (state.description) |desc| {
                // Draw separator line
                const sep_y = cy + 4.0;
                try svg.line(rx + 4, sep_y, rx + w - 4, sep_y, state_model.state_stroke_color, 0.5, null);
                try svg.textCentered(cx, cy + 18.0, desc, NOTE_FONT_SIZE, state_model.text_color, "sans-serif");
            }

            // Additional descriptions
            const desc_start_y: f64 = if (state.description != null) cy + 32.0 else cy + 14.0;
            for (state.descriptions.items, 0..) |desc, i| {
                const dy = desc_start_y + @as(f64, @floatFromInt(i)) * LINE_HEIGHT;
                try svg.textCentered(cx, dy, desc.data, NOTE_FONT_SIZE, state_model.text_color, "sans-serif");
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

    const ux = dx / len;
    const uy = dy / len;
    const px = -uy;
    const py = ux;

    const arrow_len: f64 = ARROW_SIZE;
    const arrow_half_w: f64 = ARROW_SIZE / 2.5;

    var arrow_pts: [3][2]f64 = undefined;
    arrow_pts[0] = .{ to_x, to_y }; // tip
    arrow_pts[1] = .{ to_x - ux * arrow_len + px * arrow_half_w, to_y - uy * arrow_len + py * arrow_half_w };
    arrow_pts[2] = .{ to_x - ux * arrow_len - px * arrow_half_w, to_y - uy * arrow_len - py * arrow_half_w };
    try svg.polygon(&arrow_pts, state_model.edge_color, state_model.edge_color, 1);
}

// -----------------------------------------------------------------------
// Edge clipping helpers
// -----------------------------------------------------------------------

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
        .start, .end => computeCircleIntersection(cx, cy, START_END_RADIUS + 2, target_x, target_y),
        .choice => computeDiamondIntersection(cx, cy, CHOICE_SIZE / 2.0, target_x, target_y),
        else => computeRectIntersection(cx, cy, w, h, target_x, target_y),
    };
}

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
        .start, .end => computeCircleIntersection(cx, cy, START_END_RADIUS + 2, source_x, source_y),
        .choice => computeDiamondIntersection(cx, cy, CHOICE_SIZE / 2.0, source_x, source_y),
        else => computeRectIntersection(cx, cy, w, h, source_x, source_y),
    };
}

fn computeCircleIntersection(
    cx: f64,
    cy: f64,
    radius: f64,
    target_x: f64,
    target_y: f64,
) Position {
    const dx = target_x - cx;
    const dy = target_y - cy;
    const dist = @sqrt(dx * dx + dy * dy);
    if (dist < 0.001) return .{ .x = cx + radius, .y = cy };
    return .{
        .x = cx + dx / dist * radius,
        .y = cy + dy / dist * radius,
    };
}

fn computeRectIntersection(
    cx: f64,
    cy: f64,
    w: f64,
    h: f64,
    target_x: f64,
    target_y: f64,
) Position {
    const dx = target_x - cx;
    const dy = target_y - cy;
    const half_w = w / 2.0;
    const half_h = h / 2.0;

    if (@abs(dx) < 0.001 and @abs(dy) < 0.001) {
        return .{ .x = cx, .y = cy - half_h };
    }

    // Try horizontal edges
    if (@abs(dx) > 0.001) {
        const t_right = half_w / @abs(dx);
        const y_at_right = dy * t_right;
        if (@abs(y_at_right) <= half_h) {
            return .{
                .x = if (dx > 0) cx + half_w else cx - half_w,
                .y = cy + y_at_right,
            };
        }
    }

    // Try vertical edges
    if (@abs(dy) > 0.001) {
        const t_top = half_h / @abs(dy);
        const x_at_top = dx * t_top;
        if (@abs(x_at_top) <= half_w) {
            return .{
                .x = cx + x_at_top,
                .y = if (dy > 0) cy + half_h else cy - half_h,
            };
        }
    }

    return .{ .x = cx, .y = if (dy >= 0) cy + half_h else cy - half_h };
}

fn computeDiamondIntersection(
    cx: f64,
    cy: f64,
    half_size: f64,
    target_x: f64,
    target_y: f64,
) Position {
    const dx = target_x - cx;
    const dy = target_y - cy;
    const dist = @sqrt(dx * dx + dy * dy);
    if (dist < 0.001) return .{ .x = cx, .y = cy - half_size };

    // Diamond edge: |dx/half_size| + |dy/half_size| = 1
    const abs_dx = @abs(dx);
    const abs_dy = @abs(dy);
    const sum = abs_dx + abs_dy;
    if (sum < 0.001) return .{ .x = cx, .y = cy - half_size };

    const scale = half_size / sum;
    return .{
        .x = cx + dx * scale,
        .y = cy + dy * scale,
    };
}

// -----------------------------------------------------------------------
// Note size computation
// -----------------------------------------------------------------------

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
// Note rendering with callout line
// -----------------------------------------------------------------------

fn renderNoteWithCallout(
    svg: *SvgWriter,
    position: NotePosition,
    text: []const u8,
    cx: f64,
    cy: f64,
    node_w: f64,
    node_h: f64,
) !void {
    _ = node_h; // may be used for vertical positioning in future
    const ns = computeNoteSize(text);
    const note_w = ns.w;
    const note_h = ns.h;

    // Position the note
    const note_x = switch (position) {
        .right_of => cx + node_w / 2.0 + NOTE_CALLOUT_GAP,
        .left_of => cx - node_w / 2.0 - NOTE_CALLOUT_GAP - note_w,
    };
    const note_y = cy - note_h / 2.0;

    // ── Draw callout line (dashed) from state border to note ────
    const line_start_x = switch (position) {
        .right_of => cx + node_w / 2.0,
        .left_of => cx - node_w / 2.0,
    };
    const line_end_x = switch (position) {
        .right_of => note_x,
        .left_of => note_x + note_w,
    };
    const line_y = cy; // horizontal line at the vertical center

    try svg.line(
        line_start_x,
        line_y,
        line_end_x,
        line_y,
        NOTE_CALLOUT_COLOR,
        1.0,
        "4,3",
    );

    // ── Draw note rectangle (yellow sticky note style) ──────────
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

    // ── Draw note text (handle newlines) ────────────────────────
    var line_count: usize = 1;
    for (text) |c| {
        if (c == '\n') line_count += 1;
    }

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
        var text_y = note_y + NOTE_PADDING + 8.0;
        var start: usize = 0;
        for (text, 0..) |c, i| {
            if (c == '\n') {
                const line_text = text[start..i];
                try svg.textAt(
                    note_x + NOTE_PADDING,
                    text_y,
                    line_text,
                    NOTE_FONT_SIZE,
                    state_model.text_color,
                    "sans-serif",
                    .start,
                );
                text_y += 16.0;
                start = i + 1;
            }
        }
        // Last line
        if (start < text.len) {
            try svg.textAt(
                note_x + NOTE_PADDING,
                text_y,
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
    var diagram = state_model.StateDiagram.init(allocator);
    defer diagram.deinit();

    const svg = try renderStateToSVGString(allocator, &diagram);
    defer allocator.free(svg);
    try std.testing.expect(svg.len > 0);
    try std.testing.expect(std.mem.indexOf(u8, svg, "<svg") != null);
}

test "state svg: renders simple transitions" {
    const allocator = std.testing.allocator;
    var diagram = state_model.StateDiagram.init(allocator);
    defer diagram.deinit();

    try diagram.addRelation("Idle", "Active", "start", null);
    try diagram.addRelation("Active", "Done", null, null);

    const svg = try renderStateToSVGString(allocator, &diagram);
    defer allocator.free(svg);
    try std.testing.expect(svg.len > 0);
    try std.testing.expect(std.mem.indexOf(u8, svg, "Idle") != null);
}

test "state svg: renders with title" {
    const allocator = std.testing.allocator;
    var diagram = state_model.StateDiagram.init(allocator);
    defer diagram.deinit();

    try diagram.setTitle("My State Diagram");
    try diagram.addRelation("A", "B", null, null);

    const svg = try renderStateToSVGString(allocator, &diagram);
    defer allocator.free(svg);
    try std.testing.expect(std.mem.indexOf(u8, svg, "My State Diagram") != null);
}

test "state svg: renders special state types" {
    const allocator = std.testing.allocator;
    var diagram = state_model.StateDiagram.init(allocator);
    defer diagram.deinit();

    _ = try diagram.addStateWithType("fk", .fork);
    _ = try diagram.addStateWithType("jn", .join);
    _ = try diagram.addStateWithType("ch", .choice);
    try diagram.addRelation("A", "fk", null, null);
    try diagram.addRelation("fk", "B", null, null);

    const svg = try renderStateToSVGString(allocator, &diagram);
    defer allocator.free(svg);
    try std.testing.expect(svg.len > 0);
}

test "state svg: renders note with callout" {
    const allocator = std.testing.allocator;
    var diagram = state_model.StateDiagram.init(allocator);
    defer diagram.deinit();

    try diagram.addRelation("Idle", "Active", null, null);
    try diagram.addNote("Idle", .right_of, "A note here");

    const svg = try renderStateToSVGString(allocator, &diagram);
    defer allocator.free(svg);
    try std.testing.expect(std.mem.indexOf(u8, svg, "A note here") != null);
    // Should contain a dashed line (callout)
    try std.testing.expect(std.mem.indexOf(u8, svg, "stroke-dasharray") != null);
}

test "state svg: renders descriptions" {
    const allocator = std.testing.allocator;
    var diagram = state_model.StateDiagram.init(allocator);
    defer diagram.deinit();

    try diagram.addDescription("Idle", "Waiting for input");
    try diagram.addRelation("Idle", "Active", null, null);

    const svg = try renderStateToSVGString(allocator, &diagram);
    defer allocator.free(svg);
    try std.testing.expect(std.mem.indexOf(u8, svg, "Waiting for input") != null);
}

test "state svg: renders composite states" {
    const allocator = std.testing.allocator;
    var diagram = state_model.StateDiagram.init(allocator);
    defer diagram.deinit();

    // Create parent composite state
    _ = try diagram.ensureState("Processing");

    // Create children
    _ = try diagram.ensureState("Validating");
    try diagram.setParent("Validating", "Processing");
    _ = try diagram.ensureState("Executing");
    try diagram.setParent("Executing", "Processing");

    // Transitions within composite
    try diagram.addRelation("Validating", "Executing", "valid", "Processing");

    // Transitions into/out of composite
    try diagram.addRelation("Idle", "Processing", "start", null);
    try diagram.addRelation("Processing", "Done", "complete", null);

    const svg = try renderStateToSVGString(allocator, &diagram);
    defer allocator.free(svg);
    try std.testing.expect(svg.len > 0);
    // Should contain the composite label
    try std.testing.expect(std.mem.indexOf(u8, svg, "Processing") != null);
    // Should contain child state labels
    try std.testing.expect(std.mem.indexOf(u8, svg, "Validating") != null);
    try std.testing.expect(std.mem.indexOf(u8, svg, "Executing") != null);
}

test "state svg: computeCircleIntersection" {
    const p = computeCircleIntersection(100, 100, 10, 200, 100);
    try std.testing.expectApproxEqAbs(@as(f64, 110.0), p.x, 0.1);
    try std.testing.expectApproxEqAbs(@as(f64, 100.0), p.y, 0.1);
}

test "state svg: computeRectIntersection" {
    // Target directly to the right
    const p1 = computeRectIntersection(100, 100, 60, 40, 200, 100);
    try std.testing.expectApproxEqAbs(@as(f64, 130.0), p1.x, 0.1);
    try std.testing.expectApproxEqAbs(@as(f64, 100.0), p1.y, 0.1);

    // Target directly below
    const p2 = computeRectIntersection(100, 100, 60, 40, 100, 200);
    try std.testing.expectApproxEqAbs(@as(f64, 100.0), p2.x, 0.1);
    try std.testing.expectApproxEqAbs(@as(f64, 120.0), p2.y, 0.1);
}

test "state svg: computeDiamondIntersection" {
    const p = computeDiamondIntersection(100, 100, 14, 200, 100);
    try std.testing.expectApproxEqAbs(@as(f64, 114.0), p.x, 0.1);
    try std.testing.expectApproxEqAbs(@as(f64, 100.0), p.y, 0.1);
}

test "state svg: direction LR layout" {
    const allocator = std.testing.allocator;
    var diagram = state_model.StateDiagram.init(allocator);
    defer diagram.deinit();

    diagram.direction = .LR;
    try diagram.addRelation("A", "B", null, null);
    try diagram.addRelation("B", "C", null, null);

    const svg = try renderStateToSVGString(allocator, &diagram);
    defer allocator.free(svg);
    try std.testing.expect(svg.len > 0);
}

test "state svg: write to file" {
    const allocator = std.testing.allocator;
    var diagram = state_model.StateDiagram.init(allocator);
    defer diagram.deinit();

    try diagram.addRelation("S1", "S2", "go", null);

    const tmp_path = "/tmp/test_state_svg.svg";
    try renderStateToSVG(allocator, &diagram, tmp_path);
}
