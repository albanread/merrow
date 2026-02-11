//! Class diagram SVG renderer.
//!
//! Converts a `ClassDiagram` model into a Dagre graph for layout, then
//! renders compartmented class boxes (name / attributes / methods) and
//! relationship edges with proper UML arrowheads to SVG.

const std = @import("std");
const Allocator = std.mem.Allocator;

const class_model = @import("model.zig");
const ClassDiagram = class_model.ClassDiagram;
const ClassNode = class_model.ClassNode;
const ClassRelation = class_model.ClassRelation;
const RelationEndType = class_model.RelationEndType;
const LineType = class_model.LineType;
const Visibility = class_model.Visibility;

const SvgWriter = @import("../render/svg.zig").SvgWriter;
const Font = @import("../render/text.zig").Font;

const Digraph = @import("../graph/digraph.zig").Digraph;
const model = @import("../model.zig");
const NodeData = model.NodeData;
const EdgeData = model.EdgeData;
const GraphData = model.GraphData;
const dagre = @import("../layout/dagre.zig");
const normalize = @import("../layout/dagre/normalize.zig");

const Graph = Digraph(NodeData, EdgeData, GraphData);

// -----------------------------------------------------------------------
// Layout / rendering constants
// -----------------------------------------------------------------------

const PADDING: f64 = 50.0;
const FONT_SIZE: f64 = 14.0;
const TITLE_FONT_SIZE: f64 = 20.0;
const HEADER_FONT_SIZE: f64 = 15.0;
const ANNOTATION_FONT_SIZE: f64 = 12.0;
const CHAR_WIDTH: f64 = 8.0; // approximate character width at 14px
const HEADER_CHAR_WIDTH: f64 = 9.0;
const LINE_HEIGHT: f64 = 22.0;
const SECTION_PAD: f64 = 8.0; // vertical padding inside each compartment
const HORIZ_PAD: f64 = 16.0; // horizontal padding in boxes
const MIN_BOX_WIDTH: f64 = 120.0;
const MIN_BOX_HEIGHT: f64 = 40.0;
const TITLE_EXTRA_Y: f64 = 40.0; // extra space at top when title is present

const FONT_FAMILY: []const u8 = "Lato, 'Helvetica Neue', Arial, sans-serif";

// -----------------------------------------------------------------------
// Public API
// -----------------------------------------------------------------------

/// Render a `ClassDiagram` to an SVG file.
pub fn renderClassToSVG(
    allocator: Allocator,
    diagram: *const ClassDiagram,
    output_path: []const u8,
    maybe_font: ?*const Font,
) !void {
    const svg_content = try renderClassToSVGString(allocator, diagram, maybe_font);
    defer allocator.free(svg_content);

    const file = try std.fs.cwd().createFile(output_path, .{});
    defer file.close();
    try file.writeAll(svg_content);
}

/// Render a `ClassDiagram` to an SVG string.  Caller owns the returned slice.
pub fn renderClassToSVGString(
    allocator: Allocator,
    diagram: *const ClassDiagram,
    maybe_font: ?*const Font,
) ![]u8 {
    // ── 1. Build Dagre graph ────────────────────────────────────
    var graph = Graph.init(allocator);
    defer {
        normalize.freeDummyIds(allocator, &graph);
        graph.deinitDeep();
    }

    // Collect class ids for stable iteration order.
    var class_ids = std.ArrayListUnmanaged([]const u8){};
    defer {
        for (class_ids.items) |id| allocator.free(id);
        class_ids.deinit(allocator);
    }

    var class_iter = diagram.classes.iterator();
    while (class_iter.next()) |entry| {
        const cls = entry.value_ptr;
        const id = entry.key_ptr.*;

        // Compute node dimensions based on content.
        const size = computeClassBoxSize(cls, maybe_font);

        try graph.setNode(id, .{
            .label = cls.displayName(),
            .width = size.width,
            .height = size.height,
        });

        try class_ids.append(allocator, try allocator.dupe(u8, id));
    }

    // Set graph direction.
    var graph_label = graph.getGraphLabel();
    if (std.mem.eql(u8, diagram.direction, "LR")) {
        graph_label.rankdir = "LR";
    } else if (std.mem.eql(u8, diagram.direction, "RL")) {
        graph_label.rankdir = "RL";
    } else if (std.mem.eql(u8, diagram.direction, "BT")) {
        graph_label.rankdir = "BT";
    } else {
        graph_label.rankdir = "TB";
    }
    graph_label.nodesep = 60.0;
    graph_label.ranksep = 60.0;

    // Add edges for relationships.
    for (diagram.relations.items) |rel| {
        const edge_label = rel.label orelse "";
        try graph.setEdge(rel.id1, rel.id2, .{
            .label = if (edge_label.len > 0) edge_label else null,
            .minlen = 1,
        }, null);
    }

    // ── 2. Run Dagre layout ─────────────────────────────────────
    const rankdir: dagre.RankDir = blk: {
        if (std.mem.eql(u8, diagram.direction, "LR")) break :blk .LR;
        if (std.mem.eql(u8, diagram.direction, "RL")) break :blk .RL;
        if (std.mem.eql(u8, diagram.direction, "BT")) break :blk .BT;
        break :blk .TB;
    };

    const config = dagre.DagreConfig{
        .rankdir = rankdir,
        .ranker = .network_simplex,
        .nodesep = 60,
        .ranksep = 60,
    };

    try dagre.layout(allocator, &graph, config);

    // ── 3. Compute bounding box ─────────────────────────────────
    var min_x: f64 = std.math.floatMax(f64);
    var min_y: f64 = std.math.floatMax(f64);
    var max_x: f64 = -std.math.floatMax(f64);
    var max_y: f64 = -std.math.floatMax(f64);

    for (class_ids.items) |id| {
        if (graph.getNode(id)) |node| {
            const left = node.x - node.width / 2.0;
            const right = node.x + node.width / 2.0;
            const top = node.y - node.height / 2.0;
            const bottom = node.y + node.height / 2.0;
            if (left < min_x) min_x = left;
            if (right > max_x) max_x = right;
            if (top < min_y) min_y = top;
            if (bottom > max_y) max_y = bottom;
        }
    }

    // Also consider edge points.
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
        // Empty diagram.
        min_x = 0;
        max_x = 200;
        min_y = 0;
        max_y = 100;
    }

    const has_title = diagram.title != null;
    const title_offset: f64 = if (has_title) TITLE_EXTRA_Y else 0.0;

    const canvas_width = (max_x - min_x) + PADDING * 2;
    const canvas_height = (max_y - min_y) + PADDING * 2 + title_offset;
    const offset_x = PADDING - min_x;
    const offset_y = PADDING - min_y + title_offset;

    // ── 4. Build SVG ────────────────────────────────────────────
    var svg = try SvgWriter.init(allocator, canvas_width, canvas_height);
    defer svg.deinit();

    // White background.
    try svg.rect(0, 0, canvas_width, canvas_height, 0, 0, [4]u8{ 255, 255, 255, 255 }, null, 0);

    // Title.
    if (diagram.title) |title| {
        try svg.textCentered(
            canvas_width / 2.0,
            25.0,
            title,
            TITLE_FONT_SIZE,
            class_model.class_text_color,
            FONT_FAMILY,
        );
    }

    // ── 4a. Draw edges (behind nodes) ───────────────────────────
    try drawEdges(allocator, diagram, &graph, &svg, offset_x, offset_y);

    // ── 4b. Draw class boxes (on top) ───────────────────────────
    for (class_ids.items) |id| {
        if (graph.getNode(id)) |node| {
            if (diagram.classes.getPtr(id)) |cls| {
                try drawClassBox(&svg, cls, node.x + offset_x, node.y + offset_y, node.width, node.height);
            }
        }
    }

    return svg.finalize();
}

// -----------------------------------------------------------------------
// Class box sizing
// -----------------------------------------------------------------------

const BoxSize = struct {
    width: f64,
    height: f64,
};

fn computeClassBoxSize(cls: *const ClassNode, maybe_font: ?*const Font) BoxSize {
    _ = maybe_font; // TODO: use font for precise measurement

    // Header section: class name (+ annotation + generic)
    var header_lines: usize = 1; // class name
    header_lines += cls.annotations.items.len;

    // Compute max text width.
    var max_text_width: f64 = 0;

    // Class name width.
    const name = cls.displayName();
    var name_width = @as(f64, @floatFromInt(name.len)) * HEADER_CHAR_WIDTH;
    if (cls.generic) |g| {
        name_width += @as(f64, @floatFromInt(g.len + 2)) * HEADER_CHAR_WIDTH; // ~T~
    }
    if (name_width > max_text_width) max_text_width = name_width;

    // Annotation widths.
    for (cls.annotations.items) |ann| {
        const ann_width = (@as(f64, @floatFromInt(ann.len)) + 4) * CHAR_WIDTH; // <<ann>>
        if (ann_width > max_text_width) max_text_width = ann_width;
    }

    // Member widths.
    for (cls.members.items) |m| {
        const w = @as(f64, @floatFromInt(m.text.len)) * CHAR_WIDTH;
        if (w > max_text_width) max_text_width = w;
    }

    // Method widths.
    for (cls.methods.items) |m| {
        const w = @as(f64, @floatFromInt(m.text.len)) * CHAR_WIDTH;
        if (w > max_text_width) max_text_width = w;
    }

    const box_width = @max(MIN_BOX_WIDTH, max_text_width + HORIZ_PAD * 2);

    // Height: header + separator + attributes + separator + methods
    var total_height: f64 = 0;

    // Header section.
    total_height += @as(f64, @floatFromInt(header_lines)) * LINE_HEIGHT + SECTION_PAD * 2;

    // Attributes section (always present, may be empty).
    const num_attrs = cls.members.items.len;
    if (num_attrs > 0) {
        total_height += @as(f64, @floatFromInt(num_attrs)) * LINE_HEIGHT + SECTION_PAD * 2;
    } else {
        total_height += SECTION_PAD * 2; // empty compartment
    }

    // Methods section (always present, may be empty).
    const num_methods = cls.methods.items.len;
    if (num_methods > 0) {
        total_height += @as(f64, @floatFromInt(num_methods)) * LINE_HEIGHT + SECTION_PAD * 2;
    } else {
        total_height += SECTION_PAD * 2; // empty compartment
    }

    return .{
        .width = box_width,
        .height = @max(MIN_BOX_HEIGHT, total_height),
    };
}

// -----------------------------------------------------------------------
// Class box drawing
// -----------------------------------------------------------------------

fn drawClassBox(
    svg: *SvgWriter,
    cls: *const ClassNode,
    cx: f64,
    cy: f64,
    width: f64,
    height: f64,
) !void {
    const x = cx - width / 2.0;
    const y = cy - height / 2.0;

    // Calculate section heights.
    var header_lines: usize = 1;
    header_lines += cls.annotations.items.len;
    const header_height = @as(f64, @floatFromInt(header_lines)) * LINE_HEIGHT + SECTION_PAD * 2;

    const num_attrs = cls.members.items.len;
    const attrs_height = if (num_attrs > 0)
        @as(f64, @floatFromInt(num_attrs)) * LINE_HEIGHT + SECTION_PAD * 2
    else
        SECTION_PAD * 2;

    // Methods take the remaining space.
    const methods_height = height - header_height - attrs_height;

    // ── Header background (darker) ──────────────────────────────
    try svg.rect(
        x,
        y,
        width,
        header_height,
        4,
        4,
        class_model.class_header_color,
        class_model.class_border_color,
        2,
    );

    // ── Attributes background ───────────────────────────────────
    try svg.rect(
        x,
        y + header_height,
        width,
        attrs_height,
        0,
        0,
        class_model.class_body_color,
        class_model.class_border_color,
        2,
    );

    // ── Methods background ──────────────────────────────────────
    try svg.rect(
        x,
        y + header_height + attrs_height,
        width,
        methods_height,
        4,
        4,
        class_model.class_body_color,
        class_model.class_border_color,
        2,
    );

    // Cover the inner rounded corners with small rects for a clean join.
    // Top section bottom-left and bottom-right corners overlap with middle section.
    if (header_height > 4 and attrs_height > 0) {
        try svg.rect(x, y + header_height - 4, width, 6, 0, 0, class_model.class_header_color, null, 0);
        try svg.line(x, y + header_height, x + width, y + header_height, class_model.class_border_color, 2, null);
    }
    if (attrs_height > 0 and methods_height > 4) {
        // Clean join between attrs and methods.
        try svg.rect(x, y + header_height + attrs_height - 2, width, 4, 0, 0, class_model.class_body_color, null, 0);
        try svg.line(x, y + header_height + attrs_height, x + width, y + header_height + attrs_height, class_model.class_border_color, 2, null);
    }

    // ── Header text ─────────────────────────────────────────────
    var text_y = y + SECTION_PAD + LINE_HEIGHT * 0.7;

    // Annotations (above the class name, e.g. <<interface>>).
    for (cls.annotations.items) |ann| {
        var ann_buf: [128]u8 = undefined;
        const ann_display = std.fmt.bufPrint(&ann_buf, "\xC2\xAB{s}\xC2\xBB", .{ann}) catch ann;
        try svg.textCentered(
            cx,
            text_y,
            ann_display,
            ANNOTATION_FONT_SIZE,
            class_model.class_header_text_color,
            FONT_FAMILY,
        );
        text_y += LINE_HEIGHT;
    }

    // Class name (bold — we use a slightly larger font to simulate bold).
    var name_buf: [256]u8 = undefined;
    const display_name = if (cls.generic) |g|
        std.fmt.bufPrint(&name_buf, "{s}~{s}~", .{ cls.displayName(), g }) catch cls.displayName()
    else
        cls.displayName();

    try svg.textCentered(
        cx,
        text_y,
        display_name,
        HEADER_FONT_SIZE,
        class_model.class_header_text_color,
        FONT_FAMILY,
    );

    // ── Attribute text ──────────────────────────────────────────
    text_y = y + header_height + SECTION_PAD + LINE_HEIGHT * 0.7;

    for (cls.members.items) |m| {
        try svg.textAt(
            x + HORIZ_PAD,
            text_y,
            m.text,
            FONT_SIZE,
            class_model.class_text_color,
            FONT_FAMILY,
            .start,
        );
        text_y += LINE_HEIGHT;
    }

    // ── Method text ─────────────────────────────────────────────
    text_y = y + header_height + attrs_height + SECTION_PAD + LINE_HEIGHT * 0.7;

    for (cls.methods.items) |m| {
        try svg.textAt(
            x + HORIZ_PAD,
            text_y,
            m.text,
            FONT_SIZE,
            class_model.class_text_color,
            FONT_FAMILY,
            .start,
        );
        text_y += LINE_HEIGHT;
    }
}

// -----------------------------------------------------------------------
// Edge drawing
// -----------------------------------------------------------------------

fn drawEdges(
    allocator: Allocator,
    diagram: *const ClassDiagram,
    graph: *Graph,
    svg: *SvgWriter,
    offset_x: f64,
    offset_y: f64,
) !void {
    // We iterate over the diagram's relations in order and match them
    // to graph edges to get layout points.
    for (diagram.relations.items) |rel| {
        const edge_data = graph.edge(rel.id1, rel.id2, null);
        if (edge_data == null) continue;
        const ed = edge_data.?;

        const points = ed.points.items;
        if (points.len == 0) continue;

        // Determine stroke style.
        const stroke_color = class_model.relation_color;
        const stroke_width: f64 = 1.5;
        const dash_array: ?[]const u8 = if (rel.relation.line_type == .dotted) "8,5" else null;

        // Get source and target node centres for endpoint clipping.
        const src_node = graph.getNode(rel.id1);
        const tgt_node = graph.getNode(rel.id2);

        // Build the edge path.
        // Start from the source node border, through layout points, to
        // target node border.
        var path_points = std.ArrayListUnmanaged([2]f64){};
        defer path_points.deinit(allocator);

        // Source attachment point: clip to node border.
        if (src_node) |sn| {
            const clipped = clipToBoxBorder(
                sn.x + offset_x,
                sn.y + offset_y,
                sn.width,
                sn.height,
                points[0].x + offset_x,
                points[0].y + offset_y,
            );
            try path_points.append(allocator, .{ clipped[0], clipped[1] });
        } else {
            try path_points.append(allocator, .{ points[0].x + offset_x, points[0].y + offset_y });
        }

        // Intermediate points.
        for (points) |pt| {
            try path_points.append(allocator, .{ pt.x + offset_x, pt.y + offset_y });
        }

        // Target attachment: clip to node border.
        const last_pt = points[points.len - 1];
        if (tgt_node) |tn| {
            const clipped = clipToBoxBorder(
                tn.x + offset_x,
                tn.y + offset_y,
                tn.width,
                tn.height,
                last_pt.x + offset_x,
                last_pt.y + offset_y,
            );
            try path_points.append(allocator, .{ clipped[0], clipped[1] });
        } else {
            try path_points.append(allocator, .{ last_pt.x + offset_x, last_pt.y + offset_y });
        }

        // Draw the polyline.
        const pts_slice = path_points.items;
        try svg.polyline(pts_slice, stroke_color, stroke_width, dash_array);

        // Draw arrowheads at the endpoints.
        if (pts_slice.len >= 2) {
            // Target end arrowhead (type2).
            const tip2 = pts_slice[pts_slice.len - 1];
            const before_tip2 = pts_slice[pts_slice.len - 2];
            try drawArrowhead(svg, rel.relation.type2, before_tip2, tip2, stroke_color);

            // Source end arrowhead (type1).
            const tip1 = pts_slice[0];
            const before_tip1 = pts_slice[1];
            try drawArrowhead(svg, rel.relation.type1, before_tip1, tip1, stroke_color);
        }

        // Draw relationship label at the midpoint.
        if (rel.label) |lbl| {
            if (lbl.len > 0) {
                // Use the edge's label position if available, else midpoint.
                const label_x = if (ed.x != 0) ed.x + offset_x else blk: {
                    const mid_idx = pts_slice.len / 2;
                    break :blk pts_slice[mid_idx][0];
                };
                const label_y = if (ed.y != 0) ed.y + offset_y else blk: {
                    const mid_idx = pts_slice.len / 2;
                    break :blk pts_slice[mid_idx][1];
                };

                // Draw label background.
                const lbl_width = @as(f64, @floatFromInt(lbl.len)) * CHAR_WIDTH + 8;
                try svg.rect(
                    label_x - lbl_width / 2.0,
                    label_y - LINE_HEIGHT / 2.0,
                    lbl_width,
                    LINE_HEIGHT,
                    3,
                    3,
                    [4]u8{ 255, 255, 255, 230 },
                    null,
                    0,
                );

                try svg.textCentered(
                    label_x,
                    label_y,
                    lbl,
                    FONT_SIZE - 1,
                    class_model.label_color,
                    FONT_FAMILY,
                );
            }
        }

        // Draw cardinality labels near the endpoints.
        if (rel.cardinality1) |c1| {
            if (c1.len > 0 and pts_slice.len >= 2) {
                const p = pts_slice[0];
                const p2 = pts_slice[1];
                const angle = std.math.atan2(p2[1] - p[1], p2[0] - p[0]);
                // Offset perpendicular to the edge direction.
                const perp_x = -@sin(angle) * 15.0;
                const perp_y = @cos(angle) * 15.0;
                const along_x = @cos(angle) * 20.0;
                const along_y = @sin(angle) * 20.0;
                try svg.textCentered(
                    p[0] + perp_x + along_x,
                    p[1] + perp_y + along_y,
                    c1,
                    FONT_SIZE - 2,
                    class_model.label_color,
                    FONT_FAMILY,
                );
            }
        }
        if (rel.cardinality2) |c2| {
            if (c2.len > 0 and pts_slice.len >= 2) {
                const p = pts_slice[pts_slice.len - 1];
                const p2 = pts_slice[pts_slice.len - 2];
                const angle = std.math.atan2(p2[1] - p[1], p2[0] - p[0]);
                const perp_x = -@sin(angle) * 15.0;
                const perp_y = @cos(angle) * 15.0;
                const along_x = @cos(angle) * 20.0;
                const along_y = @sin(angle) * 20.0;
                try svg.textCentered(
                    p[0] + perp_x + along_x,
                    p[1] + perp_y + along_y,
                    c2,
                    FONT_SIZE - 2,
                    class_model.label_color,
                    FONT_FAMILY,
                );
            }
        }
    }
}

// -----------------------------------------------------------------------
// Arrowhead drawing
// -----------------------------------------------------------------------

fn drawArrowhead(
    svg: *SvgWriter,
    end_type: RelationEndType,
    from_pt: [2]f64,
    tip: [2]f64,
    color: [4]u8,
) !void {
    if (end_type == .none) return;

    const dx = tip[0] - from_pt[0];
    const dy = tip[1] - from_pt[1];
    const len = @sqrt(dx * dx + dy * dy);
    if (len < 0.001) return;

    // Unit vector along the edge direction (towards tip).
    const ux = dx / len;
    const uy = dy / len;

    // Perpendicular unit vector.
    const px = -uy;
    const py = ux;

    switch (end_type) {
        .extension => {
            // Filled triangle (inheritance).
            const arrow_len: f64 = 18.0;
            const arrow_w: f64 = 10.0;
            const base_x = tip[0] - ux * arrow_len;
            const base_y = tip[1] - uy * arrow_len;
            const pts = [_][2]f64{
                .{ tip[0], tip[1] },
                .{ base_x + px * arrow_w, base_y + py * arrow_w },
                .{ base_x - px * arrow_w, base_y - py * arrow_w },
            };
            try svg.polygon(&pts, [4]u8{ 255, 255, 255, 255 }, color, 2);
        },
        .composition => {
            // Filled diamond.
            const d_len: f64 = 20.0;
            const d_w: f64 = 10.0;
            const mid_x = tip[0] - ux * d_len / 2.0;
            const mid_y = tip[1] - uy * d_len / 2.0;
            const base_x = tip[0] - ux * d_len;
            const base_y = tip[1] - uy * d_len;
            const pts = [_][2]f64{
                .{ tip[0], tip[1] },
                .{ mid_x + px * d_w, mid_y + py * d_w },
                .{ base_x, base_y },
                .{ mid_x - px * d_w, mid_y - py * d_w },
            };
            try svg.polygon(&pts, color, color, 2);
        },
        .aggregation => {
            // Open diamond.
            const d_len: f64 = 20.0;
            const d_w: f64 = 10.0;
            const mid_x = tip[0] - ux * d_len / 2.0;
            const mid_y = tip[1] - uy * d_len / 2.0;
            const base_x = tip[0] - ux * d_len;
            const base_y = tip[1] - uy * d_len;
            const pts = [_][2]f64{
                .{ tip[0], tip[1] },
                .{ mid_x + px * d_w, mid_y + py * d_w },
                .{ base_x, base_y },
                .{ mid_x - px * d_w, mid_y - py * d_w },
            };
            try svg.polygon(&pts, [4]u8{ 255, 255, 255, 255 }, color, 2);
        },
        .dependency => {
            // Open arrow (two lines forming a V).
            const arrow_len: f64 = 14.0;
            const arrow_w: f64 = 8.0;
            const left_x = tip[0] - ux * arrow_len + px * arrow_w;
            const left_y = tip[1] - uy * arrow_len + py * arrow_w;
            const right_x = tip[0] - ux * arrow_len - px * arrow_w;
            const right_y = tip[1] - uy * arrow_len - py * arrow_w;
            try svg.line(left_x, left_y, tip[0], tip[1], color, 2, null);
            try svg.line(right_x, right_y, tip[0], tip[1], color, 2, null);
        },
        .lollipop => {
            // Circle at the tip.
            const radius: f64 = 6.0;
            const circle_cx = tip[0] - ux * radius;
            const circle_cy = tip[1] - uy * radius;
            try svg.ellipse(circle_cx, circle_cy, radius, radius, [4]u8{ 255, 255, 255, 255 }, color, 2);
        },
        .none => {},
    }
}

// -----------------------------------------------------------------------
// Geometry helpers
// -----------------------------------------------------------------------

/// Clip a point coming from `from_x, from_y` towards the centre of a box
/// at `(cx, cy)` with given `width` and `height`, returning the border
/// intersection point.
fn clipToBoxBorder(
    cx: f64,
    cy: f64,
    width: f64,
    height: f64,
    from_x: f64,
    from_y: f64,
) [2]f64 {
    const hw = width / 2.0;
    const hh = height / 2.0;

    const dx = from_x - cx;
    const dy = from_y - cy;

    if (@abs(dx) < 0.001 and @abs(dy) < 0.001) {
        return .{ cx, cy - hh }; // default to top
    }

    // Calculate intersection with each side of the box.
    var t: f64 = std.math.floatMax(f64);

    // Right side.
    if (dx > 0) {
        const t_right = hw / dx;
        const y_at = dy * t_right;
        if (@abs(y_at) <= hh and t_right < t) t = t_right;
    }
    // Left side.
    if (dx < 0) {
        const t_left = -hw / dx;
        const y_at = dy * t_left;
        if (@abs(y_at) <= hh and t_left < t) t = t_left;
    }
    // Bottom side.
    if (dy > 0) {
        const t_bottom = hh / dy;
        const x_at = dx * t_bottom;
        if (@abs(x_at) <= hw and t_bottom < t) t = t_bottom;
    }
    // Top side.
    if (dy < 0) {
        const t_top = -hh / dy;
        const x_at = dx * t_top;
        if (@abs(x_at) <= hw and t_top < t) t = t_top;
    }

    if (t == std.math.floatMax(f64)) {
        return .{ cx, cy - hh };
    }

    return .{ cx + dx * t, cy + dy * t };
}

// -----------------------------------------------------------------------
// Tests
// -----------------------------------------------------------------------

const testing = std.testing;

test "class svg: empty diagram renders" {
    const allocator = testing.allocator;
    var diagram = ClassDiagram.init(allocator);
    defer diagram.deinit();

    const svg = try renderClassToSVGString(allocator, &diagram, null);
    defer allocator.free(svg);

    try testing.expect(std.mem.indexOf(u8, svg, "<svg") != null);
    try testing.expect(std.mem.indexOf(u8, svg, "</svg>") != null);
}

test "class svg: single class renders" {
    const allocator = testing.allocator;
    var diagram = ClassDiagram.init(allocator);
    defer diagram.deinit();

    try diagram.addMember("Animal", "+name: string");
    try diagram.addMember("Animal", "+speak()");

    const svg = try renderClassToSVGString(allocator, &diagram, null);
    defer allocator.free(svg);

    try testing.expect(std.mem.indexOf(u8, svg, "Animal") != null);
    try testing.expect(std.mem.indexOf(u8, svg, "+name: string") != null);
    try testing.expect(std.mem.indexOf(u8, svg, "+speak()") != null);
}

test "class svg: two classes with relationship" {
    const allocator = testing.allocator;
    var diagram = ClassDiagram.init(allocator);
    defer diagram.deinit();

    try diagram.addMember("Animal", "+name: string");
    try diagram.addMember("Dog", "+breed: string");

    const rel = ClassRelation{
        .id1 = "Dog",
        .id2 = "Animal",
        .relation = .{ .type1 = .none, .type2 = .extension, .line_type = .solid },
    };
    try diagram.addRelation(rel);

    const svg = try renderClassToSVGString(allocator, &diagram, null);
    defer allocator.free(svg);

    try testing.expect(std.mem.indexOf(u8, svg, "Animal") != null);
    try testing.expect(std.mem.indexOf(u8, svg, "Dog") != null);
    // Should have polyline or path for the edge.
    try testing.expect(std.mem.indexOf(u8, svg, "<polyline") != null or std.mem.indexOf(u8, svg, "<line") != null or std.mem.indexOf(u8, svg, "<polygon") != null);
}

test "class svg: diagram with title" {
    const allocator = testing.allocator;
    var diagram = ClassDiagram.init(allocator);
    defer diagram.deinit();

    try diagram.setTitle("My Class Diagram");
    _ = try diagram.ensureClass("Foo");

    const svg = try renderClassToSVGString(allocator, &diagram, null);
    defer allocator.free(svg);

    try testing.expect(std.mem.indexOf(u8, svg, "My Class Diagram") != null);
}

test "class svg: annotation renders" {
    const allocator = testing.allocator;
    var diagram = ClassDiagram.init(allocator);
    defer diagram.deinit();

    try diagram.addAnnotation("Shape", "interface");
    try diagram.addMember("Shape", "+draw()");

    const svg = try renderClassToSVGString(allocator, &diagram, null);
    defer allocator.free(svg);

    try testing.expect(std.mem.indexOf(u8, svg, "interface") != null);
    try testing.expect(std.mem.indexOf(u8, svg, "Shape") != null);
}

test "class svg: clipToBoxBorder" {
    // Point directly below the box centre should clip to bottom edge.
    const result = clipToBoxBorder(100, 100, 80, 60, 100, 200);
    try testing.expectApproxEqAbs(@as(f64, 100.0), result[0], 0.1);
    try testing.expectApproxEqAbs(@as(f64, 130.0), result[1], 0.1); // 100 + 60/2

    // Point to the right.
    const result2 = clipToBoxBorder(100, 100, 80, 60, 300, 100);
    try testing.expectApproxEqAbs(@as(f64, 140.0), result2[0], 0.1); // 100 + 80/2
    try testing.expectApproxEqAbs(@as(f64, 100.0), result2[1], 0.1);
}
