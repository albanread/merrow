//! State diagram PNG renderer.
//!
//! Converts a `StateDiagram` model into a Dagre graph for layout, then
//! renders state nodes (start/end circles, fork/join bars, choice diamonds,
//! rounded rectangles) and transition edges with proper arrowheads to PNG
//! via the Canvas rasteriser.
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
const STATE_FIXED_WIDTH: f64 = 180.0;
const START_END_RADIUS: f64 = 7.0;
const FORK_JOIN_WIDTH: f64 = 70.0;
const FORK_JOIN_HEIGHT: f64 = 6.0;
const CHOICE_SIZE: f64 = 28.0;
const NOTE_PADDING: f64 = 8.0;
const ARROW_SIZE: f64 = 8.0;
const EDGE_STROKE_WIDTH: f64 = 2;
const NODESEP: f64 = 50.0;
const RANKSEP: f64 = 60.0;
const SCALE_FACTOR: f64 = 2.0;

// Composite state rendering constants
const COMPOSITE_PADDING: f64 = 16.0;
const COMPOSITE_HEADER_HEIGHT: f64 = 30.0;
const COMPOSITE_CORNER_RADIUS: f64 = 8.0;

// Note callout constants
const NOTE_CALLOUT_GAP: f64 = 15.0;

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
                    effective_w += ns.w + NOTE_CALLOUT_GAP;
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

    // ── 4a. Draw composite state containers (behind everything) ─
    var composite_ids = std.ArrayListUnmanaged([]const u8){};
    defer composite_ids.deinit(allocator);

    {
        var cit = composite_set.iterator();
        while (cit.next()) |entry| {
            try composite_ids.append(allocator, entry.key_ptr.*);
        }
    }

    // Sort by nesting depth (outermost first).
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

        renderCompositeBox(&canvas, &state, cx, cy, w, h, maybe_font);
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

        renderStateNode(&canvas, &state, cx, cy, size.w, size.h, maybe_font);

        // Draw note with callout line if present
        if (state.note) |note| {
            renderNoteWithCallout(&canvas, note.position, note.text, cx, cy, size.w, size.h, maybe_font);
        }
    }

    // ── 4d. Draw notes attached to composite states ─────────────
    for (composite_ids.items) |comp_id| {
        const state = mutable_diagram.states.get(comp_id) orelse continue;
        if (state.note) |note| {
            const node = graph.getNode(comp_id) orelse continue;
            const cx = node.x + offset_x;
            const cy = node.y + offset_y;
            renderNoteWithCallout(&canvas, note.position, note.text, cx, cy, node.width, node.height, maybe_font);
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
            const w = @max(STATE_FIXED_WIDTH, STATE_MIN_WIDTH);
            const max_chars = stateMaxCharsPerLine(w);

            const label_lines = countWrappedTextLines(state.displayLabel(), max_chars);

            var description_lines: usize = 0;
            if (state.description) |desc| {
                description_lines += countWrappedTextLines(desc, max_chars);
            }
            for (state.descriptions.items) |desc| {
                description_lines += countWrappedTextLines(desc.data, max_chars);
            }

            var h = STATE_PADDING_V * 2.0 + @as(f64, @floatFromInt(label_lines)) * LINE_HEIGHT;
            if (description_lines > 0) {
                h += 8.0 + @as(f64, @floatFromInt(description_lines)) * LINE_HEIGHT;
            }

            h = @max(h, STATE_MIN_HEIGHT);
            return .{ .w = w, .h = h };
        },
    };
}

fn stateMaxCharsPerLine(width: f64) usize {
    const content_w = @max(width - STATE_PADDING_H * 2.0, CHAR_WIDTH);
    const chars_f = @floor(content_w / CHAR_WIDTH);
    const chars: usize = @intFromFloat(chars_f);
    return @max(chars, 1);
}

fn countWrappedTextLines(text: []const u8, max_chars_per_line: usize) usize {
    var total: usize = 0;
    var line_iter = std.mem.splitScalar(u8, text, '\n');

    while (line_iter.next()) |line| {
        const trimmed = std.mem.trim(u8, line, " ");
        if (trimmed.len == 0) {
            total += 1;
            continue;
        }

        total += (trimmed.len + max_chars_per_line - 1) / max_chars_per_line;
    }

    return @max(total, 1);
}

fn drawWrappedCenteredText(
    canvas: *Canvas,
    font: *Font,
    text: []const u8,
    cx: f64,
    start_y: f64,
    font_size: f64,
    color: [4]u8,
    max_chars_per_line: usize,
) usize {
    var y = start_y;
    var lines_drawn: usize = 0;
    var line_iter = std.mem.splitScalar(u8, text, '\n');

    while (line_iter.next()) |line| {
        const trimmed = std.mem.trim(u8, line, " ");
        if (trimmed.len == 0) {
            y += LINE_HEIGHT;
            lines_drawn += 1;
            continue;
        }

        var start: usize = 0;
        while (start < trimmed.len) {
            const end = @min(start + max_chars_per_line, trimmed.len);
            const chunk = trimmed[start..end];

            const tw = font.measureText(chunk, @floatCast(font_size));
            const tx: f32 = @floatCast(cx - @as(f64, tw) / 2.0);
            const ty: f32 = @floatCast(y - font_size / 2.0);
            font.drawText(canvas, chunk, tx, ty, @floatCast(font_size), color[0], color[1], color[2], color[3]) catch {};

            y += LINE_HEIGHT;
            lines_drawn += 1;
            start = end;
        }
    }

    return @max(lines_drawn, 1);
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
    canvas: *Canvas,
    state: *const state_model.State,
    cx: f64,
    cy: f64,
    w: f64,
    h: f64,
    maybe_font: ?*Font,
) void {
    const rx = cx - w / 2.0;
    const ry = cy - h / 2.0;

    // Outer rectangle (white body)
    canvas.fillRect(rx, ry, w, h, 255, 255, 255, 255);
    canvas.strokeRect(rx, ry, w, h, 2, state_model.state_stroke_color[0], state_model.state_stroke_color[1], state_model.state_stroke_color[2], state_model.state_stroke_color[3]);

    // Header background bar (colored strip at the top)
    const header_h = COMPOSITE_HEADER_HEIGHT;
    canvas.fillRect(rx, ry, w, header_h, state_model.composite_header_fill[0], state_model.composite_header_fill[1], state_model.composite_header_fill[2], state_model.composite_header_fill[3]);

    // Separator line between header and body
    canvas.drawLine(rx, ry + header_h, rx + w, ry + header_h, 1, state_model.state_stroke_color[0], state_model.state_stroke_color[1], state_model.state_stroke_color[2], state_model.state_stroke_color[3]);

    // Re-draw the top border and sides of header area to cover any fill overlap
    canvas.drawLine(rx, ry, rx + w, ry, 2, state_model.state_stroke_color[0], state_model.state_stroke_color[1], state_model.state_stroke_color[2], state_model.state_stroke_color[3]);
    canvas.drawLine(rx, ry, rx, ry + header_h, 2, state_model.state_stroke_color[0], state_model.state_stroke_color[1], state_model.state_stroke_color[2], state_model.state_stroke_color[3]);
    canvas.drawLine(rx + w, ry, rx + w, ry + header_h, 2, state_model.state_stroke_color[0], state_model.state_stroke_color[1], state_model.state_stroke_color[2], state_model.state_stroke_color[3]);

    // Header label
    if (maybe_font) |font| {
        const label = state.displayLabel();
        const tw = font.measureText(label, @floatCast(LABEL_FONT_SIZE));
        const tx: f32 = @floatCast(cx - @as(f64, tw) / 2.0);
        const ty: f32 = @floatCast(ry + header_h / 2.0 - 7.0);
        font.drawText(canvas, label, tx, ty, @floatCast(LABEL_FONT_SIZE), state_model.text_color[0], state_model.text_color[1], state_model.text_color[2], state_model.text_color[3]) catch {};

        // Description below header if present
        if (state.description) |desc| {
            const dw = font.measureText(desc, @floatCast(NOTE_FONT_SIZE));
            const dx: f32 = @floatCast(cx - @as(f64, dw) / 2.0);
            const dy: f32 = @floatCast(ry + header_h + 10.0);
            font.drawText(canvas, desc, dx, dy, @floatCast(NOTE_FONT_SIZE), 100, 100, 100, 255) catch {};
        }
    }
}

// -----------------------------------------------------------------------
// State node rendering (non-composite)
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
                const max_chars = stateMaxCharsPerLine(w);
                var line_y = ry + STATE_PADDING_V + LINE_HEIGHT / 2.0;

                _ = drawWrappedCenteredText(
                    canvas,
                    font,
                    state.displayLabel(),
                    cx,
                    line_y,
                    LABEL_FONT_SIZE,
                    state_model.text_color,
                    max_chars,
                );

                const label_lines = countWrappedTextLines(state.displayLabel(), max_chars);
                line_y += @as(f64, @floatFromInt(label_lines)) * LINE_HEIGHT;

                var description_lines: usize = 0;
                if (state.description) |desc| {
                    description_lines += countWrappedTextLines(desc, max_chars);
                }
                for (state.descriptions.items) |desc| {
                    description_lines += countWrappedTextLines(desc.data, max_chars);
                }

                if (description_lines > 0) {
                    const sep_y = line_y + 2.0;
                    canvas.drawLine(rx + 4, sep_y, rx + w - 4, sep_y, 1, state_model.state_stroke_color[0], state_model.state_stroke_color[1], state_model.state_stroke_color[2], state_model.state_stroke_color[3]);
                    line_y = sep_y + 10.0;

                    if (state.description) |desc| {
                        const used = drawWrappedCenteredText(
                            canvas,
                            font,
                            desc,
                            cx,
                            line_y,
                            NOTE_FONT_SIZE,
                            state_model.text_color,
                            max_chars,
                        );
                        line_y += @as(f64, @floatFromInt(used)) * LINE_HEIGHT;
                    }

                    for (state.descriptions.items) |desc| {
                        const used = drawWrappedCenteredText(
                            canvas,
                            font,
                            desc.data,
                            cx,
                            line_y,
                            NOTE_FONT_SIZE,
                            state_model.text_color,
                            max_chars,
                        );
                        line_y += @as(f64, @floatFromInt(used)) * LINE_HEIGHT;
                    }
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
    canvas: *Canvas,
    position: NotePosition,
    text: []const u8,
    cx: f64,
    cy: f64,
    node_w: f64,
    node_h: f64,
    maybe_font: ?*Font,
) void {
    _ = node_h; // may be used for vertical positioning in future
    const ns = computeNoteSize(text);
    const note_w = ns.w;
    const note_h = ns.h;

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

    canvas.drawDashedLine(
        line_start_x,
        line_y,
        line_end_x,
        line_y,
        1,
        state_model.note_stroke[0],
        state_model.note_stroke[1],
        state_model.note_stroke[2],
        state_model.note_stroke[3],
        4.0,
        3.0,
    );

    // ── Draw note background (yellow) ───────────────────────────
    canvas.fillRect(note_x, note_y, note_w, note_h, state_model.note_fill[0], state_model.note_fill[1], state_model.note_fill[2], state_model.note_fill[3]);
    canvas.strokeRect(note_x, note_y, note_w, note_h, 1, state_model.note_stroke[0], state_model.note_stroke[1], state_model.note_stroke[2], state_model.note_stroke[3]);

    // ── Draw note text ──────────────────────────────────────────
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
            var text_y: f64 = note_y + NOTE_PADDING;
            var start: usize = 0;
            for (text, 0..) |c, i| {
                if (c == '\n') {
                    const line_text = text[start..i];
                    font.drawText(canvas, line_text, @floatCast(note_x + NOTE_PADDING), @floatCast(text_y), @floatCast(NOTE_FONT_SIZE), state_model.text_color[0], state_model.text_color[1], state_model.text_color[2], state_model.text_color[3]) catch {};
                    text_y += 16.0;
                    start = i + 1;
                }
            }
            if (start < text.len) {
                font.drawText(canvas, text[start..], @floatCast(note_x + NOTE_PADDING), @floatCast(text_y), @floatCast(NOTE_FONT_SIZE), state_model.text_color[0], state_model.text_color[1], state_model.text_color[2], state_model.text_color[3]) catch {};
            }
        }
    }
}

// -----------------------------------------------------------------------
// Tests
// -----------------------------------------------------------------------

test "state png: renders without crash (no font)" {
    const allocator = std.testing.allocator;
    var diagram = state_model.StateDiagram.init(allocator);
    defer diagram.deinit();

    try diagram.addRelation("Idle", "Active", "start", null);
    try diagram.addRelation("Active", "Done", null, null);

    const tmp = "/tmp/test_state_png.png";
    try renderStateToPNG(allocator, &diagram, tmp, null);
}

test "state png: empty diagram renders without crash" {
    const allocator = std.testing.allocator;
    var diagram = state_model.StateDiagram.init(allocator);
    defer diagram.deinit();

    const tmp = "/tmp/test_state_png_empty.png";
    try renderStateToPNG(allocator, &diagram, tmp, null);
}

test "state png: special states render without crash" {
    const allocator = std.testing.allocator;
    var diagram = state_model.StateDiagram.init(allocator);
    defer diagram.deinit();

    _ = try diagram.addStateWithType("fk", .fork);
    _ = try diagram.addStateWithType("jn", .join);
    _ = try diagram.addStateWithType("ch", .choice);
    try diagram.addRelation("A", "fk", null, null);
    try diagram.addRelation("fk", "B", null, null);

    const tmp = "/tmp/test_state_png_special.png";
    try renderStateToPNG(allocator, &diagram, tmp, null);
}

test "state png: with note renders without crash" {
    const allocator = std.testing.allocator;
    var diagram = state_model.StateDiagram.init(allocator);
    defer diagram.deinit();

    try diagram.addRelation("Idle", "Active", null, null);
    try diagram.addNote("Idle", .right_of, "A note here");

    const tmp = "/tmp/test_state_png_note.png";
    try renderStateToPNG(allocator, &diagram, tmp, null);
}

test "state png: composite state renders without crash" {
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

    const tmp = "/tmp/test_state_png_composite.png";
    try renderStateToPNG(allocator, &diagram, tmp, null);
}
