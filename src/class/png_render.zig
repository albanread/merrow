//! Class diagram PNG renderer.
//!
//! Converts a `ClassDiagram` model into a Dagre graph for layout, then
//! renders compartmented class boxes (name / attributes / methods) and
//! relationship edges with proper UML arrowheads to PNG via the Canvas
//! rasteriser.

const std = @import("std");
const Allocator = std.mem.Allocator;

const class_model = @import("model.zig");
const ClassDiagram = class_model.ClassDiagram;
const ClassNode = class_model.ClassNode;
const ClassRelation = class_model.ClassRelation;
const RelationEndType = class_model.RelationEndType;
const LineType = class_model.LineType;
const Visibility = class_model.Visibility;

const Canvas = @import("../render/canvas.zig").Canvas;
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
const CHAR_WIDTH: f64 = 8.0;
const HEADER_CHAR_WIDTH: f64 = 9.0;
const LINE_HEIGHT: f64 = 22.0;
const SECTION_PAD: f64 = 8.0;
const HORIZ_PAD: f64 = 16.0;
const MIN_BOX_WIDTH: f64 = 120.0;
const MIN_BOX_HEIGHT: f64 = 40.0;
const TITLE_EXTRA_Y: f64 = 40.0;
const SCALE_FACTOR: f64 = 2.0;

// -----------------------------------------------------------------------
// Public API
// -----------------------------------------------------------------------

/// Render a `ClassDiagram` to a PNG file.
pub fn renderClassToPNG(
    allocator: Allocator,
    diagram: *const ClassDiagram,
    output_path: []const u8,
    maybe_font: ?*Font,
) !void {
    // ── 1. Build Dagre graph ────────────────────────────────────
    var graph = Graph.init(allocator);
    defer {
        normalize.freeDummyIds(allocator, &graph);
        graph.deinitDeep();
    }

    var class_ids = std.ArrayListUnmanaged([]const u8){};
    defer {
        for (class_ids.items) |id| allocator.free(id);
        class_ids.deinit(allocator);
    }

    var class_iter = diagram.classes.iterator();
    while (class_iter.next()) |entry| {
        const cls = entry.value_ptr;
        const id = entry.key_ptr.*;

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

    // Add edges.
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

    const has_title = diagram.title != null;
    const title_offset: f64 = if (has_title) TITLE_EXTRA_Y else 0.0;

    const canvas_width_f = (max_x - min_x) + PADDING * 2;
    const canvas_height_f = (max_y - min_y) + PADDING * 2 + title_offset;
    const offset_x = PADDING - min_x;
    const offset_y = PADDING - min_y + title_offset;

    const canvas_w: u32 = @intFromFloat(@ceil(canvas_width_f));
    const canvas_h: u32 = @intFromFloat(@ceil(canvas_height_f));

    // ── 4. Create canvas and draw ───────────────────────────────
    var canvas = try Canvas.initWithScale(allocator, canvas_w, canvas_h, SCALE_FACTOR);
    defer canvas.deinit();

    // White background.
    canvas.fill(255, 255, 255, 255);

    // Title.
    if (diagram.title) |title| {
        if (maybe_font) |font| {
            const tw = font.measureText(title, @floatCast(TITLE_FONT_SIZE));
            const tx: f32 = @floatCast(canvas_width_f / 2.0 - @as(f64, tw) / 2.0);
            font.drawText(&canvas, title, tx, 10.0, @floatCast(TITLE_FONT_SIZE), 51, 51, 51, 255) catch {};
        }
    }

    // ── 4a. Draw edges (behind nodes) ───────────────────────────
    drawEdges(allocator, diagram, &graph, &canvas, offset_x, offset_y, maybe_font);

    // ── 4b. Draw class boxes (on top) ───────────────────────────
    for (class_ids.items) |id| {
        if (graph.getNode(id)) |node| {
            if (diagram.classes.getPtr(id)) |cls| {
                drawClassBox(&canvas, cls, node.x + offset_x, node.y + offset_y, node.width, node.height, maybe_font);
            }
        }
    }

    try canvas.saveToPNG(output_path);
}

// -----------------------------------------------------------------------
// Class box sizing
// -----------------------------------------------------------------------

const BoxSize = struct {
    width: f64,
    height: f64,
};

fn computeClassBoxSize(cls: *const ClassNode, maybe_font: ?*Font) BoxSize {
    _ = maybe_font;

    var header_lines: usize = 1;
    header_lines += cls.annotations.items.len;

    var max_text_width: f64 = 0;

    const name = cls.displayName();
    var name_width = @as(f64, @floatFromInt(name.len)) * HEADER_CHAR_WIDTH;
    if (cls.generic) |g| {
        name_width += @as(f64, @floatFromInt(g.len + 2)) * HEADER_CHAR_WIDTH;
    }
    if (name_width > max_text_width) max_text_width = name_width;

    for (cls.annotations.items) |ann| {
        const ann_width = (@as(f64, @floatFromInt(ann.len)) + 4) * CHAR_WIDTH;
        if (ann_width > max_text_width) max_text_width = ann_width;
    }

    for (cls.members.items) |m| {
        const w = @as(f64, @floatFromInt(m.text.len)) * CHAR_WIDTH;
        if (w > max_text_width) max_text_width = w;
    }

    for (cls.methods.items) |m| {
        const w = @as(f64, @floatFromInt(m.text.len)) * CHAR_WIDTH;
        if (w > max_text_width) max_text_width = w;
    }

    const box_width = @max(MIN_BOX_WIDTH, max_text_width + HORIZ_PAD * 2);

    var total_height: f64 = 0;
    total_height += @as(f64, @floatFromInt(header_lines)) * LINE_HEIGHT + SECTION_PAD * 2;

    const num_attrs = cls.members.items.len;
    if (num_attrs > 0) {
        total_height += @as(f64, @floatFromInt(num_attrs)) * LINE_HEIGHT + SECTION_PAD * 2;
    } else {
        total_height += SECTION_PAD * 2;
    }

    const num_methods = cls.methods.items.len;
    if (num_methods > 0) {
        total_height += @as(f64, @floatFromInt(num_methods)) * LINE_HEIGHT + SECTION_PAD * 2;
    } else {
        total_height += SECTION_PAD * 2;
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
    canvas: *Canvas,
    cls: *const ClassNode,
    cx: f64,
    cy: f64,
    width: f64,
    height: f64,
    maybe_font: ?*Font,
) void {
    const x = cx - width / 2.0;
    const y = cy - height / 2.0;

    var header_lines: usize = 1;
    header_lines += cls.annotations.items.len;
    const header_height = @as(f64, @floatFromInt(header_lines)) * LINE_HEIGHT + SECTION_PAD * 2;

    const num_attrs = cls.members.items.len;
    const attrs_height = if (num_attrs > 0)
        @as(f64, @floatFromInt(num_attrs)) * LINE_HEIGHT + SECTION_PAD * 2
    else
        SECTION_PAD * 2;

    const methods_height = height - header_height - attrs_height;

    // Header background (dark blue).
    canvas.fillRect(x, y, width, header_height, class_model.class_header_color[0], class_model.class_header_color[1], class_model.class_header_color[2], class_model.class_header_color[3]);

    // Attributes background (light).
    canvas.fillRect(x, y + header_height, width, attrs_height, class_model.class_body_color[0], class_model.class_body_color[1], class_model.class_body_color[2], class_model.class_body_color[3]);

    // Methods background (light).
    canvas.fillRect(x, y + header_height + attrs_height, width, methods_height, class_model.class_body_color[0], class_model.class_body_color[1], class_model.class_body_color[2], class_model.class_body_color[3]);

    // Border: outer rectangle.
    canvas.strokeRect(x, y, width, height, 2, class_model.class_border_color[0], class_model.class_border_color[1], class_model.class_border_color[2], class_model.class_border_color[3]);

    // Separator lines.
    canvas.drawLine(x, y + header_height, x + width, y + header_height, 2, class_model.class_border_color[0], class_model.class_border_color[1], class_model.class_border_color[2], class_model.class_border_color[3]);

    if (attrs_height > 0 and methods_height > 0) {
        canvas.drawLine(x, y + header_height + attrs_height, x + width, y + header_height + attrs_height, 2, class_model.class_border_color[0], class_model.class_border_color[1], class_model.class_border_color[2], class_model.class_border_color[3]);
    }

    // ── Text rendering ──────────────────────────────────────────
    if (maybe_font) |font| {
        var text_y: f64 = y + SECTION_PAD + LINE_HEIGHT * 0.3;

        // Annotations.
        for (cls.annotations.items) |ann| {
            var ann_buf: [128]u8 = undefined;
            const ann_display = std.fmt.bufPrint(&ann_buf, "<<{s}>>", .{ann}) catch ann;
            const aw = font.measureText(ann_display, @floatCast(ANNOTATION_FONT_SIZE));
            const ax: f32 = @floatCast(cx - @as(f64, aw) / 2.0);
            font.drawText(canvas, ann_display, ax, @floatCast(text_y), @floatCast(ANNOTATION_FONT_SIZE), 255, 255, 255, 255) catch {};
            text_y += LINE_HEIGHT;
        }

        // Class name (centred).
        const display_name = cls.displayName();
        var name_buf: [256]u8 = undefined;
        const rendered_name = if (cls.generic) |g|
            std.fmt.bufPrint(&name_buf, "{s}<{s}>", .{ display_name, g }) catch display_name
        else
            display_name;

        const nw = font.measureText(rendered_name, @floatCast(HEADER_FONT_SIZE));
        const nx: f32 = @floatCast(cx - @as(f64, nw) / 2.0);
        font.drawText(canvas, rendered_name, nx, @floatCast(text_y), @floatCast(HEADER_FONT_SIZE), 255, 255, 255, 255) catch {};

        // Attributes.
        text_y = y + header_height + SECTION_PAD + LINE_HEIGHT * 0.3;
        for (cls.members.items) |m| {
            const tx: f32 = @floatCast(x + HORIZ_PAD);
            font.drawText(canvas, m.text, tx, @floatCast(text_y), @floatCast(FONT_SIZE), class_model.class_text_color[0], class_model.class_text_color[1], class_model.class_text_color[2], class_model.class_text_color[3]) catch {};
            text_y += LINE_HEIGHT;
        }

        // Methods.
        text_y = y + header_height + attrs_height + SECTION_PAD + LINE_HEIGHT * 0.3;
        for (cls.methods.items) |m| {
            const tx: f32 = @floatCast(x + HORIZ_PAD);
            font.drawText(canvas, m.text, tx, @floatCast(text_y), @floatCast(FONT_SIZE), class_model.class_text_color[0], class_model.class_text_color[1], class_model.class_text_color[2], class_model.class_text_color[3]) catch {};
            text_y += LINE_HEIGHT;
        }
    }
}

// -----------------------------------------------------------------------
// Edge drawing
// -----------------------------------------------------------------------

fn drawEdges(
    allocator: Allocator,
    diagram: *const ClassDiagram,
    graph: *Graph,
    canvas: *Canvas,
    offset_x: f64,
    offset_y: f64,
    maybe_font: ?*Font,
) void {
    for (diagram.relations.items) |rel| {
        const edge_data = graph.edge(rel.id1, rel.id2, null);
        if (edge_data == null) continue;
        const ed = edge_data.?;

        const points = ed.points.items;
        if (points.len == 0) continue;

        const is_dotted = rel.relation.line_type == .dotted;
        const cr = class_model.relation_color[0];
        const cg = class_model.relation_color[1];
        const cb = class_model.relation_color[2];
        const ca = class_model.relation_color[3];

        // Get source and target nodes.
        const src_node = graph.getNode(rel.id1);
        const tgt_node = graph.getNode(rel.id2);

        // Build path: source border → intermediate → target border.
        var path_points = std.ArrayListUnmanaged([2]f64){};
        defer path_points.deinit(allocator);

        if (src_node) |sn| {
            const clipped = clipToBoxBorder(sn.x + offset_x, sn.y + offset_y, sn.width, sn.height, points[0].x + offset_x, points[0].y + offset_y);
            path_points.append(allocator, .{ clipped[0], clipped[1] }) catch {};
        } else {
            path_points.append(allocator, .{ points[0].x + offset_x, points[0].y + offset_y }) catch {};
        }

        for (points) |pt| {
            path_points.append(allocator, .{ pt.x + offset_x, pt.y + offset_y }) catch {};
        }

        const last_pt = points[points.len - 1];
        if (tgt_node) |tn| {
            const clipped = clipToBoxBorder(tn.x + offset_x, tn.y + offset_y, tn.width, tn.height, last_pt.x + offset_x, last_pt.y + offset_y);
            path_points.append(allocator, .{ clipped[0], clipped[1] }) catch {};
        } else {
            path_points.append(allocator, .{ last_pt.x + offset_x, last_pt.y + offset_y }) catch {};
        }

        // Draw segments.
        const pts = path_points.items;
        if (pts.len >= 2) {
            var i: usize = 0;
            while (i + 1 < pts.len) : (i += 1) {
                if (is_dotted) {
                    drawDashedLine(canvas, pts[i][0], pts[i][1], pts[i + 1][0], pts[i + 1][1], 2, cr, cg, cb, ca, 8.0, 5.0);
                } else {
                    canvas.drawLine(pts[i][0], pts[i][1], pts[i + 1][0], pts[i + 1][1], 2, cr, cg, cb, ca);
                }
            }

            // Arrowheads.
            drawArrowhead(canvas, rel.relation.type2, pts[pts.len - 2], pts[pts.len - 1], cr, cg, cb, ca);
            drawArrowhead(canvas, rel.relation.type1, pts[1], pts[0], cr, cg, cb, ca);
        }

        // Edge label.
        if (rel.label) |lbl| {
            if (lbl.len > 0) {
                if (maybe_font) |font| {
                    const label_x: f64 = if (ed.x != 0) ed.x + offset_x else blk: {
                        const mid_idx = pts.len / 2;
                        break :blk pts[mid_idx][0];
                    };
                    const label_y: f64 = if (ed.y != 0) ed.y + offset_y else blk: {
                        const mid_idx = pts.len / 2;
                        break :blk pts[mid_idx][1];
                    };

                    const lw = font.measureText(lbl, @floatCast(FONT_SIZE - 1));
                    const lbl_bg_w = @as(f64, lw) + 8;
                    canvas.fillRect(label_x - lbl_bg_w / 2.0, label_y - LINE_HEIGHT / 2.0, lbl_bg_w, LINE_HEIGHT, 255, 255, 255, 230);

                    const lx: f32 = @floatCast(label_x - @as(f64, lw) / 2.0);
                    const ly: f32 = @floatCast(label_y - 6.0);
                    font.drawText(canvas, lbl, lx, ly, @floatCast(FONT_SIZE - 1), class_model.label_color[0], class_model.label_color[1], class_model.label_color[2], class_model.label_color[3]) catch {};
                }
            }
        }

        // Cardinality labels.
        if (maybe_font) |font| {
            if (rel.cardinality1) |c1| {
                if (c1.len > 0 and pts.len >= 2) {
                    const p = pts[0];
                    const p2 = pts[1];
                    const angle = std.math.atan2(p2[1] - p[1], p2[0] - p[0]);
                    const perp_x = -@sin(angle) * 15.0;
                    const perp_y = @cos(angle) * 15.0;
                    const along_x = @cos(angle) * 20.0;
                    const along_y = @sin(angle) * 20.0;
                    const cw = font.measureText(c1, @floatCast(FONT_SIZE - 2));
                    const card_x: f32 = @floatCast(p[0] + perp_x + along_x - @as(f64, cw) / 2.0);
                    const card_y: f32 = @floatCast(p[1] + perp_y + along_y - 6.0);
                    font.drawText(canvas, c1, card_x, card_y, @floatCast(FONT_SIZE - 2), class_model.label_color[0], class_model.label_color[1], class_model.label_color[2], class_model.label_color[3]) catch {};
                }
            }
            if (rel.cardinality2) |c2| {
                if (c2.len > 0 and pts.len >= 2) {
                    const p = pts[pts.len - 1];
                    const p2 = pts[pts.len - 2];
                    const angle = std.math.atan2(p2[1] - p[1], p2[0] - p[0]);
                    const perp_x = -@sin(angle) * 15.0;
                    const perp_y = @cos(angle) * 15.0;
                    const along_x = @cos(angle) * 20.0;
                    const along_y = @sin(angle) * 20.0;
                    const cw = font.measureText(c2, @floatCast(FONT_SIZE - 2));
                    const card_x: f32 = @floatCast(p[0] + perp_x + along_x - @as(f64, cw) / 2.0);
                    const card_y: f32 = @floatCast(p[1] + perp_y + along_y - 6.0);
                    font.drawText(canvas, c2, card_x, card_y, @floatCast(FONT_SIZE - 2), class_model.label_color[0], class_model.label_color[1], class_model.label_color[2], class_model.label_color[3]) catch {};
                }
            }
        }
    }
}

// -----------------------------------------------------------------------
// Arrowhead drawing
// -----------------------------------------------------------------------

fn drawArrowhead(
    canvas: *Canvas,
    end_type: RelationEndType,
    from_pt: [2]f64,
    tip: [2]f64,
    r: u8,
    g: u8,
    b: u8,
    a: u8,
) void {
    if (end_type == .none) return;

    const dx = tip[0] - from_pt[0];
    const dy = tip[1] - from_pt[1];
    const len = @sqrt(dx * dx + dy * dy);
    if (len < 0.001) return;

    const ux = dx / len;
    const uy = dy / len;
    const px = -uy;
    const py = ux;

    switch (end_type) {
        .extension => {
            // Hollow triangle (inheritance).
            const arrow_len: f64 = 18.0;
            const arrow_w: f64 = 10.0;
            const base_x = tip[0] - ux * arrow_len;
            const base_y = tip[1] - uy * arrow_len;
            const l_x = base_x + px * arrow_w;
            const l_y = base_y + py * arrow_w;
            const r_x = base_x - px * arrow_w;
            const r_y = base_y - py * arrow_w;
            // Fill white then outline.
            fillTriangle(canvas, tip[0], tip[1], l_x, l_y, r_x, r_y, 255, 255, 255, 255);
            canvas.drawLine(tip[0], tip[1], l_x, l_y, 2, r, g, b, a);
            canvas.drawLine(l_x, l_y, r_x, r_y, 2, r, g, b, a);
            canvas.drawLine(r_x, r_y, tip[0], tip[1], 2, r, g, b, a);
        },
        .composition => {
            // Filled diamond.
            const d_len: f64 = 20.0;
            const d_w: f64 = 10.0;
            const mid_x = tip[0] - ux * d_len / 2.0;
            const mid_y = tip[1] - uy * d_len / 2.0;
            const base_x = tip[0] - ux * d_len;
            const base_y = tip[1] - uy * d_len;
            const l_x = mid_x + px * d_w;
            const l_y = mid_y + py * d_w;
            const r_x = mid_x - px * d_w;
            const r_y = mid_y - py * d_w;
            fillTriangle(canvas, tip[0], tip[1], l_x, l_y, base_x, base_y, r, g, b, a);
            fillTriangle(canvas, tip[0], tip[1], r_x, r_y, base_x, base_y, r, g, b, a);
            canvas.drawLine(tip[0], tip[1], l_x, l_y, 2, r, g, b, a);
            canvas.drawLine(l_x, l_y, base_x, base_y, 2, r, g, b, a);
            canvas.drawLine(base_x, base_y, r_x, r_y, 2, r, g, b, a);
            canvas.drawLine(r_x, r_y, tip[0], tip[1], 2, r, g, b, a);
        },
        .aggregation => {
            // Open diamond.
            const d_len: f64 = 20.0;
            const d_w: f64 = 10.0;
            const mid_x = tip[0] - ux * d_len / 2.0;
            const mid_y = tip[1] - uy * d_len / 2.0;
            const base_x = tip[0] - ux * d_len;
            const base_y = tip[1] - uy * d_len;
            const l_x = mid_x + px * d_w;
            const l_y = mid_y + py * d_w;
            const r_x = mid_x - px * d_w;
            const r_y = mid_y - py * d_w;
            fillTriangle(canvas, tip[0], tip[1], l_x, l_y, base_x, base_y, 255, 255, 255, 255);
            fillTriangle(canvas, tip[0], tip[1], r_x, r_y, base_x, base_y, 255, 255, 255, 255);
            canvas.drawLine(tip[0], tip[1], l_x, l_y, 2, r, g, b, a);
            canvas.drawLine(l_x, l_y, base_x, base_y, 2, r, g, b, a);
            canvas.drawLine(base_x, base_y, r_x, r_y, 2, r, g, b, a);
            canvas.drawLine(r_x, r_y, tip[0], tip[1], 2, r, g, b, a);
        },
        .dependency => {
            // Open arrow (V shape).
            const arrow_len: f64 = 14.0;
            const arrow_w: f64 = 8.0;
            const l_x = tip[0] - ux * arrow_len + px * arrow_w;
            const l_y = tip[1] - uy * arrow_len + py * arrow_w;
            const r_x = tip[0] - ux * arrow_len - px * arrow_w;
            const r_y = tip[1] - uy * arrow_len - py * arrow_w;
            canvas.drawLine(l_x, l_y, tip[0], tip[1], 2, r, g, b, a);
            canvas.drawLine(r_x, r_y, tip[0], tip[1], 2, r, g, b, a);
        },
        .lollipop => {
            // Circle.
            const radius: f64 = 6.0;
            const circle_cx = tip[0] - ux * radius;
            const circle_cy = tip[1] - uy * radius;
            canvas.strokeEllipse(circle_cx, circle_cy, radius, radius, 2, r, g, b, a);
        },
        .none => {},
    }
}

// -----------------------------------------------------------------------
// Triangle fill helper (scanline)
// -----------------------------------------------------------------------

fn fillTriangle(
    canvas: *Canvas,
    x0: f64,
    y0: f64,
    x1: f64,
    y1: f64,
    x2: f64,
    y2: f64,
    r: u8,
    g: u8,
    b: u8,
    a: u8,
) void {
    // Bounding box.
    const min_y_f = @min(@min(y0, y1), y2);
    const max_y_f = @max(@max(y0, y1), y2);
    const min_x_f = @min(@min(x0, x1), x2);
    const max_x_f = @max(@max(x0, x1), x2);

    // Scale for canvas.
    const scale = SCALE_FACTOR;
    const iy_start: i32 = @intFromFloat(@floor(min_y_f * scale));
    const iy_end: i32 = @intFromFloat(@ceil(max_y_f * scale));
    const ix_start: i32 = @intFromFloat(@floor(min_x_f * scale));
    const ix_end: i32 = @intFromFloat(@ceil(max_x_f * scale));

    // Scaled triangle vertices.
    const sx0 = x0 * scale;
    const sy0 = y0 * scale;
    const sx1 = x1 * scale;
    const sy1 = y1 * scale;
    const sx2 = x2 * scale;
    const sy2 = y2 * scale;

    var iy: i32 = iy_start;
    while (iy <= iy_end) : (iy += 1) {
        var ix: i32 = ix_start;
        while (ix <= ix_end) : (ix += 1) {
            const px_f = @as(f64, @floatFromInt(ix)) + 0.5;
            const py_f = @as(f64, @floatFromInt(iy)) + 0.5;

            // Barycentric test.
            if (pointInTriangle(px_f, py_f, sx0, sy0, sx1, sy1, sx2, sy2)) {
                canvas.setPixel(ix, iy, r, g, b, a);
            }
        }
    }
}

fn pointInTriangle(
    px: f64,
    py: f64,
    x0: f64,
    y0: f64,
    x1: f64,
    y1: f64,
    x2: f64,
    y2: f64,
) bool {
    const d1 = sign(px, py, x0, y0, x1, y1);
    const d2 = sign(px, py, x1, y1, x2, y2);
    const d3 = sign(px, py, x2, y2, x0, y0);

    const has_neg = (d1 < 0) or (d2 < 0) or (d3 < 0);
    const has_pos = (d1 > 0) or (d2 > 0) or (d3 > 0);

    return !(has_neg and has_pos);
}

fn sign(px: f64, py: f64, x1: f64, y1: f64, x2: f64, y2: f64) f64 {
    return (px - x2) * (y1 - y2) - (x1 - x2) * (py - y2);
}

// -----------------------------------------------------------------------
// Dashed line helper
// -----------------------------------------------------------------------

fn drawDashedLine(
    canvas: *Canvas,
    x0: f64,
    y0: f64,
    x1: f64,
    y1: f64,
    thickness: i32,
    r: u8,
    g: u8,
    b: u8,
    a: u8,
    dash_len: f64,
    gap_len: f64,
) void {
    const dx = x1 - x0;
    const dy = y1 - y0;
    const total_len = @sqrt(dx * dx + dy * dy);
    if (total_len < 0.001) return;

    const ux = dx / total_len;
    const uy = dy / total_len;
    const segment = dash_len + gap_len;

    var pos: f64 = 0;
    while (pos < total_len) {
        const dash_start = pos;
        const dash_end = @min(pos + dash_len, total_len);

        canvas.drawLine(
            x0 + ux * dash_start,
            y0 + uy * dash_start,
            x0 + ux * dash_end,
            y0 + uy * dash_end,
            thickness,
            r,
            g,
            b,
            a,
        );

        pos += segment;
    }
}

// -----------------------------------------------------------------------
// Geometry helpers
// -----------------------------------------------------------------------

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
        return .{ cx, cy - hh };
    }

    var t: f64 = std.math.floatMax(f64);

    if (dx > 0) {
        const t_right = hw / dx;
        const y_at = dy * t_right;
        if (@abs(y_at) <= hh and t_right < t) t = t_right;
    }
    if (dx < 0) {
        const t_left = -hw / dx;
        const y_at = dy * t_left;
        if (@abs(y_at) <= hh and t_left < t) t = t_left;
    }
    if (dy > 0) {
        const t_bottom = hh / dy;
        const x_at = dx * t_bottom;
        if (@abs(x_at) <= hw and t_bottom < t) t = t_bottom;
    }
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

test "class png: renders without crash (no font)" {
    const allocator = std.testing.allocator;
    var diagram = ClassDiagram.init(allocator);
    defer diagram.deinit();

    try diagram.addMember("Animal", "+name: string");
    try diagram.addMember("Animal", "+speak()");
    try diagram.addMember("Dog", "+breed: string");

    const rel = ClassRelation{
        .id1 = "Dog",
        .id2 = "Animal",
        .relation = .{ .type1 = .none, .type2 = .extension, .line_type = .solid },
    };
    try diagram.addRelation(rel);

    try renderClassToPNG(allocator, &diagram, "/tmp/merrow_class_test.png", null);

    const stat = try std.fs.cwd().statFile("/tmp/merrow_class_test.png");
    try std.testing.expect(stat.size > 0);
}

test "class png: empty diagram renders" {
    const allocator = std.testing.allocator;
    var diagram = ClassDiagram.init(allocator);
    defer diagram.deinit();

    try renderClassToPNG(allocator, &diagram, "/tmp/merrow_class_empty_test.png", null);

    const stat = try std.fs.cwd().statFile("/tmp/merrow_class_empty_test.png");
    try std.testing.expect(stat.size > 0);
}

test "class png: single class renders" {
    const allocator = std.testing.allocator;
    var diagram = ClassDiagram.init(allocator);
    defer diagram.deinit();

    try diagram.addMember("Foo", "+bar: int");

    try renderClassToPNG(allocator, &diagram, "/tmp/merrow_class_single_test.png", null);

    const stat = try std.fs.cwd().statFile("/tmp/merrow_class_single_test.png");
    try std.testing.expect(stat.size > 0);
}

test "class png: diagram with title renders" {
    const allocator = std.testing.allocator;
    var diagram = ClassDiagram.init(allocator);
    defer diagram.deinit();

    try diagram.setTitle("My Classes");
    try diagram.addMember("Widget", "+draw()");

    try renderClassToPNG(allocator, &diagram, "/tmp/merrow_class_title_test.png", null);

    const stat = try std.fs.cwd().statFile("/tmp/merrow_class_title_test.png");
    try std.testing.expect(stat.size > 0);
}

test "class png: multiple relationships render" {
    const allocator = std.testing.allocator;
    var diagram = ClassDiagram.init(allocator);
    defer diagram.deinit();

    try diagram.addMember("A", "+x: int");
    try diagram.addMember("B", "+y: int");
    try diagram.addMember("C", "+z: int");

    try diagram.addRelation(.{
        .id1 = "A",
        .id2 = "B",
        .relation = .{ .type1 = .none, .type2 = .extension, .line_type = .solid },
    });
    try diagram.addRelation(.{
        .id1 = "A",
        .id2 = "C",
        .relation = .{ .type1 = .composition, .type2 = .none, .line_type = .dotted },
    });

    try renderClassToPNG(allocator, &diagram, "/tmp/merrow_class_multi_test.png", null);

    const stat = try std.fs.cwd().statFile("/tmp/merrow_class_multi_test.png");
    try std.testing.expect(stat.size > 0);
}
