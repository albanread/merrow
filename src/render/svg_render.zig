//! SVG rendering pipeline for graph diagrams.
//!
//! This module parallels the PNG rendering path in `graph.zig` but emits
//! SVG XML via `SvgWriter` instead of rasterising to a pixel canvas.
//!
//! The rendering order matches the PNG path:
//!   1. Subgraph boxes (deepest-first for correct z-layering)
//!   2. Edges (with spline tessellation, clipping, arrowheads, labels)
//!   3. Nodes (shape-specific SVG elements + text labels)

const std = @import("std");
const Allocator = std.mem.Allocator;

const svg_mod = @import("svg.zig");
const SvgWriter = svg_mod.SvgWriter;

const graph_mod = @import("graph.zig");
const RenderConfig = graph_mod.RenderConfig;
const Bounds = graph_mod.Bounds;
const Vec2 = graph_mod.Vec2;
const LabelPlacement = graph_mod.LabelPlacement;

const text_mod = @import("text.zig");
pub const Font = text_mod.Font;

const Digraph = @import("../graph/digraph.zig").Digraph;
const model = @import("../model.zig");
const NodeData = model.NodeData;
const EdgeData = model.EdgeData;
const GraphData = model.GraphData;
const NodeShape = model.NodeShape;
const LineStyle = model.LineStyle;

const Graph = Digraph(NodeData, EdgeData, GraphData);

/// Default font family used in SVG text elements.
const default_font_family = "Lato, 'Helvetica Neue', Arial, sans-serif";

// -----------------------------------------------------------------------
// Public API
// -----------------------------------------------------------------------

/// Render a laid-out graph to an SVG file.
pub fn renderGraphToSVG(
    allocator: Allocator,
    graph: *Graph,
    filename: []const u8,
    config: RenderConfig,
) !void {
    return renderGraphToSVGWithFont(allocator, graph, filename, config, null);
}

/// Render a laid-out graph to an SVG file, optionally using a font for
/// accurate text measurement (needed for text wrapping decisions).
pub fn renderGraphToSVGWithFont(
    allocator: Allocator,
    graph: *Graph,
    filename: []const u8,
    config: RenderConfig,
    font: ?*Font,
) !void {
    const svg_data = try renderGraphToSVGString(allocator, graph, config, font);
    defer allocator.free(svg_data);

    const file = try std.fs.cwd().createFile(filename, .{});
    defer file.close();
    try file.writeAll(svg_data);
}

/// Render a laid-out graph to an SVG string.  Caller owns the returned
/// slice and must free it with `allocator`.
pub fn renderGraphToSVGString(
    allocator: Allocator,
    graph: *Graph,
    config: RenderConfig,
    font: ?*Font,
) ![]u8 {
    // Calculate bounding box
    const bounds = try graph_mod.calculateBounds(allocator, graph, config);

    const canvas_width = bounds.width + config.padding * 2;
    const canvas_height = bounds.height + config.padding * 2;

    var svg = try SvgWriter.init(allocator, canvas_width, canvas_height);
    defer svg.deinit();

    // Offsets to centre the graph within the SVG canvas
    const offset_x = config.padding - bounds.min_x;
    const offset_y = config.padding - bounds.min_y;

    // 1. Subgraph boxes (behind everything)
    try drawSubgraphs(allocator, graph, &svg, offset_x, offset_y, config);

    // 2. Edges (behind nodes)
    try drawEdges(allocator, graph, &svg, offset_x, offset_y, config, font);

    // 3. Nodes on top
    try drawNodes(allocator, graph, &svg, offset_x, offset_y, config, font);

    return svg.finalize();
}

// -----------------------------------------------------------------------
// Subgraph drawing
// -----------------------------------------------------------------------

fn drawSubgraphs(
    allocator: Allocator,
    graph: *Graph,
    svg: *SvgWriter,
    offset_x: f64,
    offset_y: f64,
    config: RenderConfig,
) !void {
    const nodes = try graph.allNodes(allocator);
    defer {
        for (nodes) |id| allocator.free(id);
        allocator.free(nodes);
    }

    const SubgraphEntry = struct {
        id: []const u8,
        depth: usize,
    };

    var subgraphs = std.ArrayListUnmanaged(SubgraphEntry){};
    defer subgraphs.deinit(allocator);

    for (nodes) |id| {
        const node = graph.getNode(id) orelse continue;
        if (!node.is_subgraph) continue;
        if (node.width < 0.1) continue;

        var depth: usize = 0;
        var cursor: ?[]const u8 = graph.getParent(id);
        while (cursor) |parent_id| {
            depth += 1;
            cursor = graph.getParent(parent_id);
        }

        try subgraphs.append(allocator, .{ .id = id, .depth = depth });
    }

    // Sort shallowest first (outermost drawn first).
    std.mem.sort(SubgraphEntry, subgraphs.items, {}, struct {
        fn lessThan(_: void, a: SubgraphEntry, b: SubgraphEntry) bool {
            return a.depth < b.depth;
        }
    }.lessThan);

    if (subgraphs.items.len == 0) return;

    // Depth-based tint palette (matches PNG renderer)
    const depth_tints = [_][4]u8{
        .{ 245, 245, 250, 255 },
        .{ 235, 240, 250, 255 },
        .{ 225, 235, 248, 255 },
        .{ 218, 228, 245, 255 },
    };

    try svg.openGroup("subgraphs");

    for (subgraphs.items) |entry| {
        const node = graph.getNode(entry.id) orelse continue;

        const x = node.x + offset_x - node.width / 2.0;
        const y = node.y + offset_y - node.height / 2.0;
        const w = node.width;
        const h = node.height;

        const tint_idx = @min(entry.depth, depth_tints.len - 1);
        const fill = depth_tints[tint_idx];
        const r = config.subgraph_corner_radius;

        // Rounded rectangle for the subgraph box
        try svg.rect(x, y, w, h, r, r, fill, config.subgraph_stroke_color, @floatFromInt(config.subgraph_stroke_width));

        // Title label
        const title_text = node.subgraph_title orelse (node.label orelse entry.id);
        if (title_text.len > 0) {
            const title_size: f64 = @as(f64, @floatCast(config.text_size)) * 0.9;
            const title_x = x + r + 6.0;
            const title_y = y + 16.0;

            try svg.textAt(
                title_x,
                title_y,
                title_text,
                title_size,
                config.subgraph_title_color,
                default_font_family,
                .start,
            );
        }
    }

    try svg.closeGroup();
}

// -----------------------------------------------------------------------
// Node drawing
// -----------------------------------------------------------------------

fn drawNodes(
    allocator: Allocator,
    graph: *Graph,
    svg: *SvgWriter,
    offset_x: f64,
    offset_y: f64,
    config: RenderConfig,
    font: ?*Font,
) !void {
    const nodes = try graph.allNodes(allocator);
    defer {
        for (nodes) |id| allocator.free(id);
        allocator.free(nodes);
    }

    try svg.openGroup("nodes");

    for (nodes) |id| {
        if (graph.getNode(id)) |node| {
            if (node.dummy) continue;
            if (node.is_subgraph) continue;

            // Wrap clickable nodes in an <a> hyperlink element
            const has_link = node.link_url != null;
            if (has_link) {
                try svg.openLink(node.link_url.?, node.link_tooltip, node.link_target);
            }

            const cx = node.x + offset_x;
            const cy = node.y + offset_y;
            const x = cx - node.width / 2.0;
            const y = cy - node.height / 2.0;
            const hw = node.width / 2.0;
            const hh = node.height / 2.0;

            const fill_color = node.fill_color orelse config.node_fill_color;
            const stroke_color = node.stroke_color orelse config.node_stroke_color;
            const stroke_width: f64 = @floatFromInt(node.stroke_width orelse config.node_stroke_width);

            switch (node.shape) {
                .box => {
                    try svg.rect(x, y, node.width, node.height, 0, 0, fill_color, stroke_color, stroke_width);
                },
                .round => {
                    const corner_r = @min(@min(hw, hh), 12.0);
                    try svg.rect(x, y, node.width, node.height, corner_r, corner_r, fill_color, stroke_color, stroke_width);
                },
                .circle => {
                    try svg.ellipse(cx, cy, hw, hh, fill_color, stroke_color, stroke_width);
                },
                .diamond => {
                    const pts = [_][2]f64{
                        .{ cx, cy - hh },
                        .{ cx + hw, cy },
                        .{ cx, cy + hh },
                        .{ cx - hw, cy },
                    };
                    try svg.polygon(&pts, fill_color, stroke_color, stroke_width);
                },
                .hexagon => {
                    const inset = hw * 0.35;
                    const pts = [_][2]f64{
                        .{ cx - hw + inset, cy - hh },
                        .{ cx + hw - inset, cy - hh },
                        .{ cx + hw, cy },
                        .{ cx + hw - inset, cy + hh },
                        .{ cx - hw + inset, cy + hh },
                        .{ cx - hw, cy },
                    };
                    try svg.polygon(&pts, fill_color, stroke_color, stroke_width);
                },
                .cylinder => {
                    // Cylinder: rect body + top/bottom ellipses
                    const cap_h = @min(hh * 0.3, 10.0);
                    const body_top = cy - hh + cap_h;
                    const body_bot = cy + hh - cap_h;
                    const body_h = body_bot - body_top;

                    // Body fill
                    try svg.rect(cx - hw, body_top, node.width, body_h, 0, 0, fill_color, null, 0);
                    // Bottom ellipse (full, behind body)
                    try svg.ellipse(cx, cy + hh - cap_h, hw, cap_h, fill_color, stroke_color, stroke_width);
                    // Body side strokes
                    try svg.line(cx - hw, body_top, cx - hw, body_bot, stroke_color, stroke_width, null);
                    try svg.line(cx + hw, body_top, cx + hw, body_bot, stroke_color, stroke_width, null);
                    // Top ellipse (drawn on top)
                    try svg.ellipse(cx, cy - hh + cap_h, hw, cap_h, fill_color, stroke_color, stroke_width);
                },
                .stadium => {
                    const corner_r = hh;
                    try svg.rect(x, y, node.width, node.height, corner_r, corner_r, fill_color, stroke_color, stroke_width);
                },
                .trapezoid => {
                    const inset = hw * 0.25;
                    const pts = [_][2]f64{
                        .{ cx - hw + inset, cy - hh },
                        .{ cx + hw - inset, cy - hh },
                        .{ cx + hw, cy + hh },
                        .{ cx - hw, cy + hh },
                    };
                    try svg.polygon(&pts, fill_color, stroke_color, stroke_width);
                },
                .trapezoid_alt => {
                    const inset = hw * 0.25;
                    const pts = [_][2]f64{
                        .{ cx - hw, cy - hh },
                        .{ cx + hw, cy - hh },
                        .{ cx + hw - inset, cy + hh },
                        .{ cx - hw + inset, cy + hh },
                    };
                    try svg.polygon(&pts, fill_color, stroke_color, stroke_width);
                },
                .parallelogram => {
                    const slant = hw * 0.25;
                    const pts = [_][2]f64{
                        .{ cx - hw + slant, cy - hh },
                        .{ cx + hw + slant, cy - hh },
                        .{ cx + hw - slant, cy + hh },
                        .{ cx - hw - slant, cy + hh },
                    };
                    try svg.polygon(&pts, fill_color, stroke_color, stroke_width);
                },
                .parallelogram_alt => {
                    const slant = hw * 0.25;
                    const pts = [_][2]f64{
                        .{ cx - hw - slant, cy - hh },
                        .{ cx + hw - slant, cy - hh },
                        .{ cx + hw + slant, cy + hh },
                        .{ cx - hw + slant, cy + hh },
                    };
                    try svg.polygon(&pts, fill_color, stroke_color, stroke_width);
                },
                .subroutine => {
                    try svg.rect(x, y, node.width, node.height, 0, 0, fill_color, stroke_color, stroke_width);
                    const inset = @max(hw * 0.15, 6.0);
                    try svg.line(cx - hw + inset, cy - hh, cx - hw + inset, cy + hh, stroke_color, stroke_width, null);
                    try svg.line(cx + hw - inset, cy - hh, cx + hw - inset, cy + hh, stroke_color, stroke_width, null);
                },
            }

            // Add cursor:pointer hint for clickable nodes (via a wrapping <g>)
            // The <a> wrapper already makes the node clickable; the style
            // attribute on the shape elements isn't needed since browsers
            // apply pointer cursor to <a> children automatically.

            // Text label
            const display_text = node.label orelse id;
            const label_color = node.text_color orelse config.text_color;
            const font_size: f64 = @floatCast(config.text_size);

            // Check if wrapping is needed
            const inner_pad: f64 = 28.0;
            const shape_shrink: f64 = switch (node.shape) {
                .diamond => 0.55,
                .hexagon => 0.65,
                .circle => 0.65,
                .trapezoid, .trapezoid_alt => 0.70,
                .parallelogram, .parallelogram_alt => 0.70,
                .subroutine => 0.75,
                .cylinder => 0.80,
                .stadium => 0.80,
                .round, .box => 1.0,
            };
            const max_text_w: f32 = @floatCast(@max(40.0, (node.width - inner_pad) * shape_shrink));

            // Try to determine if text needs wrapping
            var needs_wrap = false;
            if (font) |f| {
                const single_w = f.measureText(display_text, config.text_size);
                if (single_w > max_text_w) {
                    needs_wrap = true;
                }
            } else {
                // Estimate: ~8px per char
                const est_w = @as(f32, @floatFromInt(display_text.len)) * 8.0;
                if (est_w > max_text_w) {
                    needs_wrap = true;
                }
            }

            if (needs_wrap) {
                // Word-wrap the text into lines
                var lines_list = std.ArrayListUnmanaged([]const u8){};
                defer lines_list.deinit(allocator);

                if (font) |f| {
                    var wrapped = try f.wrapText(display_text, config.text_size, max_text_w);
                    defer wrapped.deinit();

                    for (0..wrapped.line_count) |li| {
                        const lt = wrapped.lineText(li, display_text);
                        try lines_list.append(allocator, lt);
                    }

                    const line_height: f64 = @floatCast(config.text_size * 1.4);
                    try svg.textWrapped(
                        cx,
                        cy,
                        lines_list.items,
                        font_size,
                        line_height,
                        label_color,
                        default_font_family,
                    );
                } else {
                    // Simple word-wrap without font metrics
                    try simpleWordWrap(display_text, max_text_w, &lines_list, allocator);
                    const line_height: f64 = @floatCast(config.text_size * 1.4);
                    try svg.textWrapped(
                        cx,
                        cy,
                        lines_list.items,
                        font_size,
                        line_height,
                        label_color,
                        default_font_family,
                    );
                }
            } else {
                try svg.textCentered(cx, cy, display_text, font_size, label_color, default_font_family);
            }

            // Close the <a> hyperlink wrapper if this node is clickable
            if (has_link) {
                try svg.closeLink();
            }
        }
    }

    try svg.closeGroup();
}

// -----------------------------------------------------------------------
// Edge drawing
// -----------------------------------------------------------------------

fn drawEdges(
    allocator: Allocator,
    graph: *Graph,
    svg: *SvgWriter,
    offset_x: f64,
    offset_y: f64,
    config: RenderConfig,
    font: ?*Font,
) !void {
    // Collect label placements for collision resolution (same as PNG path).
    var label_placements = std.ArrayListUnmanaged(LabelPlacement){};
    defer label_placements.deinit(allocator);

    try svg.openGroup("edges");

    var iter = graph.edgeIterator();
    while (iter.next()) |entry| {
        const v_node = graph.getNode(entry.v) orelse continue;
        if (v_node.dummy) continue;

        const edge_data = graph.edge(entry.v, entry.w, entry.name);

        const edge_color = if (edge_data) |ed| ed.color orelse config.edge_color else config.edge_color;
        const line_style: LineStyle = if (edge_data) |ed| ed.line_style else .solid;
        const base_thickness: i32 = if (edge_data) |ed| ed.thickness orelse config.edge_width else config.edge_width;
        const edge_thickness: f64 = @floatFromInt(if (line_style == .thick) @max(base_thickness * 2, 3) else base_thickness);

        const has_arrow = if (edge_data) |ed| blk: {
            if (ed.arrowhead) |ah| {
                break :blk !std.mem.eql(u8, ah, "none");
            }
            break :blk true;
        } else true;

        const has_source_arrow = if (edge_data) |ed| blk: {
            if (ed.arrowtail) |at| {
                break :blk !std.mem.eql(u8, at, "none");
            }
            break :blk false;
        } else false;

        // Dash array for SVG
        const dash_array: ?[]const u8 = switch (line_style) {
            .dashed => "10,6",
            .dotted => "4,4",
            .solid, .thick => null,
        };

        // ---------------------------------------------------------------
        // Self-edge
        // ---------------------------------------------------------------
        if (std.mem.eql(u8, entry.v, entry.w)) {
            try drawSelfEdgeLoop(
                allocator,
                svg,
                v_node,
                offset_x,
                offset_y,
                edge_color,
                edge_thickness,
                has_arrow,
                config,
                font,
                edge_data,
                &label_placements,
                dash_array,
            );
            continue;
        }

        // ---------------------------------------------------------------
        // Build waypoints: source → (dummies) → target
        // ---------------------------------------------------------------
        var waypoints = std.ArrayListUnmanaged(Vec2){};
        defer waypoints.deinit(allocator);

        try waypoints.append(allocator, .{
            .x = v_node.x + offset_x,
            .y = v_node.y + offset_y,
        });

        var current_target: []const u8 = entry.w;
        while (true) {
            const t_node = graph.getNode(current_target) orelse break;
            if (!t_node.dummy) {
                try waypoints.append(allocator, .{
                    .x = t_node.x + offset_x,
                    .y = t_node.y + offset_y,
                });
                break;
            }
            try waypoints.append(allocator, .{
                .x = t_node.x + offset_x,
                .y = t_node.y + offset_y,
            });
            const next = graph_mod.nextInChain(graph, current_target) orelse break;
            current_target = next;
        }

        if (waypoints.items.len < 2) continue;

        // ---------------------------------------------------------------
        // If the layout router has set explicit waypoints on this edge
        // (e.g. to route around containers), use those instead.
        // ---------------------------------------------------------------
        if (edge_data) |ed| {
            if (ed.points.items.len >= 2) {
                waypoints.clearRetainingCapacity();
                for (ed.points.items) |pt| {
                    try waypoints.append(allocator, .{
                        .x = pt.x + offset_x,
                        .y = pt.y + offset_y,
                    });
                }
            }
        }

        // ---------------------------------------------------------------
        // Clip to source node border
        // ---------------------------------------------------------------
        {
            const src_hw = v_node.width / 2.0;
            const src_hh = v_node.height / 2.0;
            const src_centre = waypoints.items[0];
            const next_pt = waypoints.items[1];
            waypoints.items[0] = graph_mod.clipLineToShape(
                next_pt,
                src_centre,
                src_centre.x,
                src_centre.y,
                src_hw,
                src_hh,
                v_node.shape,
            );
        }

        // ---------------------------------------------------------------
        // Clip to target node border
        // ---------------------------------------------------------------
        {
            const last_idx = waypoints.items.len - 1;
            if (graph.getNode(current_target)) |tgt_node| {
                if (!tgt_node.dummy) {
                    const tgt_hw = tgt_node.width / 2.0;
                    const tgt_hh = tgt_node.height / 2.0;
                    const tgt_centre = waypoints.items[last_idx];
                    const prev_pt = waypoints.items[last_idx - 1];
                    waypoints.items[last_idx] = graph_mod.clipLineToShape(
                        prev_pt,
                        tgt_centre,
                        tgt_centre.x,
                        tgt_centre.y,
                        tgt_hw,
                        tgt_hh,
                        tgt_node.shape,
                    );
                }
            }
        }

        // ---------------------------------------------------------------
        // Preserve explicit routed waypoints as-is. Smoothing them back
        // into Catmull-Rom splines can bow valid obstacle routes into
        // container boxes again.
        // ---------------------------------------------------------------
        const has_explicit_route = if (edge_data) |ed| ed.points.items.len >= 2 else false;
        var smooth = std.ArrayListUnmanaged(graph_mod.Vec2){};
        defer smooth.deinit(allocator);
        if (has_explicit_route) {
            try smooth.appendSlice(allocator, waypoints.items);
        } else {
            smooth = try graph_mod.tessellateSpline(allocator, waypoints.items);
        }

        // ---------------------------------------------------------------
        // Save arrowhead anchor points before shortening
        // ---------------------------------------------------------------
        var target_tip: Vec2 = undefined;
        var target_from: Vec2 = undefined;
        var source_tip: Vec2 = undefined;
        var source_from: Vec2 = undefined;

        if (has_arrow and smooth.items.len >= 2) {
            const s_last = smooth.items.len - 1;
            target_tip = smooth.items[s_last];
            target_from = smooth.items[s_last - 1];
        }
        if (has_source_arrow and smooth.items.len >= 2) {
            source_tip = smooth.items[0];
            source_from = smooth.items[1];
        }

        // Shorten polyline at arrowhead ends
        if (has_arrow) {
            graph_mod.shortenPolylineEnd(&smooth, config.arrow_size);
        }
        if (has_source_arrow) {
            graph_mod.shortenPolylineStart(&smooth, config.arrow_size);
        }

        // ---------------------------------------------------------------
        // Build SVG path from the smooth polyline
        // ---------------------------------------------------------------
        if (smooth.items.len >= 2) {
            // Convert Vec2 items to [2]f64 for catmullRomToSVGPath.
            // For the SVG path we use the original waypoints (not the
            // tessellated polyline) to get clean cubic beziers.
            // However, the tessellated polyline has already been clipped
            // and shortened, so we use it as a polyline path.
            var pts = std.ArrayListUnmanaged([2]f64){};
            defer pts.deinit(allocator);
            for (smooth.items) |p| {
                try pts.append(allocator, .{ p.x, p.y });
            }

            const d = try SvgWriter.polylineToSVGPath(allocator, pts.items);
            defer allocator.free(d);

            try svg.path(d, null, edge_color, edge_thickness, dash_array);
        }

        // ---------------------------------------------------------------
        // Arrowheads
        // ---------------------------------------------------------------
        if (has_arrow and smooth.items.len >= 1) {
            try svg.arrowhead(target_from.x, target_from.y, target_tip.x, target_tip.y, config.arrow_size, edge_color);
        }
        if (has_source_arrow and smooth.items.len >= 1) {
            try svg.arrowhead(source_from.x, source_from.y, source_tip.x, source_tip.y, config.arrow_size, edge_color);
        }

        // ---------------------------------------------------------------
        // Collect edge label placement
        // ---------------------------------------------------------------
        {
            const label_text: ?[]const u8 = if (edge_data) |ed| ed.label else null;
            if (label_text) |lbl| {
                if (lbl.len > 0) {
                    const label_offset: f64 = 22.0;
                    const mid: Vec2 = if (smooth.items.len >= 2)
                        graph_mod.pointAlongCurve(smooth.items, label_offset)
                    else
                        Vec2.lerp(waypoints.items[0], waypoints.items[1], 0.15);

                    var tan_x: f64 = 0;
                    var tan_y: f64 = 1;
                    if (smooth.items.len >= 2) {
                        const t_idx = @min(@as(usize, 1), smooth.items.len - 1);
                        tan_x = smooth.items[t_idx].x - smooth.items[0].x;
                        tan_y = smooth.items[t_idx].y - smooth.items[0].y;
                        const tlen = @sqrt(tan_x * tan_x + tan_y * tan_y);
                        if (tlen > 0.001) {
                            tan_x /= tlen;
                            tan_y /= tlen;
                        }
                    }

                    const label_font_size = config.text_size * 0.85;

                    // Measure label dimensions
                    var tw: f32 = 0;
                    if (font) |f| {
                        tw = f.measureText(lbl, label_font_size);
                    } else {
                        tw = @as(f32, @floatFromInt(lbl.len)) * 7.0;
                    }
                    const th: f32 = label_font_size * 1.3;

                    const pad_x: f64 = 4.0;
                    const pad_y: f64 = 2.0;

                    try label_placements.append(allocator, .{
                        .text = lbl,
                        .x = mid.x,
                        .y = mid.y,
                        .orig_x = mid.x,
                        .orig_y = mid.y,
                        .half_w = @as(f64, @floatCast(tw)) / 2.0 + pad_x,
                        .half_h = @as(f64, @floatCast(th)) / 2.0 + pad_y,
                        .tangent_x = tan_x,
                        .tangent_y = tan_y,
                        .font_size = label_font_size,
                        .color = config.text_color,
                    });
                }
            }
        }
    }

    try svg.closeGroup();

    // ---------------------------------------------------------------
    // Resolve label collisions and draw labels
    // ---------------------------------------------------------------
    if (label_placements.items.len > 0) {
        try graph_mod.resolveLabelPlacements(
            allocator,
            label_placements.items,
            graph,
            offset_x,
            offset_y,
        );

        try svg.openGroup("edge-labels");
        for (label_placements.items) |lbl| {
            // Background box (translucent white)
            try svg.rect(
                lbl.x - lbl.half_w,
                lbl.y - lbl.half_h,
                lbl.half_w * 2,
                lbl.half_h * 2,
                2,
                2,
                [4]u8{ 255, 255, 255, 220 },
                null,
                0,
            );
            // Label text
            try svg.textCentered(
                lbl.x,
                lbl.y,
                lbl.text,
                @floatCast(lbl.font_size),
                lbl.color,
                default_font_family,
            );
        }
        try svg.closeGroup();
    }
}

// -----------------------------------------------------------------------
// Self-edge loop
// -----------------------------------------------------------------------

fn drawSelfEdgeLoop(
    allocator: Allocator,
    svg: *SvgWriter,
    node: NodeData,
    offset_x: f64,
    offset_y: f64,
    edge_color: [4]u8,
    edge_thickness: f64,
    has_arrow: bool,
    config: RenderConfig,
    font: ?*Font,
    edge_data: ?EdgeData,
    label_placements: *std.ArrayListUnmanaged(LabelPlacement),
    dash_array: ?[]const u8,
) !void {
    const cx = node.x + offset_x;
    const cy = node.y + offset_y;
    const hw = node.width / 2.0;
    const hh = node.height / 2.0;

    const loop_offset_x: f64 = @max(hw * 0.6, 20.0);
    const loop_offset_y: f64 = @max(hh * 0.6, 15.0);

    const start_x = cx + hw;
    const start_y = cy - loop_offset_y;
    const end_x = cx + hw;
    const end_y = cy + loop_offset_y;
    const bulge_x = cx + hw + loop_offset_x;

    // Generate loop points (same parametric curve as PNG renderer)
    const num_segments: usize = 20;
    var loop_points = std.ArrayListUnmanaged(Vec2){};
    defer loop_points.deinit(allocator);
    try loop_points.ensureTotalCapacity(allocator, num_segments + 1);

    for (0..num_segments + 1) |i| {
        const t = @as(f64, @floatFromInt(i)) / @as(f64, @floatFromInt(num_segments));
        const angle = -std.math.pi / 2.0 + t * std.math.pi;
        const px = cx + hw + loop_offset_x * @cos(angle) * @cos(angle);
        const py = cy + (loop_offset_y + loop_offset_x * 0.3) * @sin(angle);
        const border_pull = 1.0 - 4.0 * (t - 0.5) * (t - 0.5);
        const final_x = start_x + (px - start_x) * border_pull + (bulge_x - start_x) * border_pull * 0.3;
        loop_points.appendAssumeCapacity(.{ .x = final_x, .y = py });
    }

    loop_points.items[0] = .{ .x = start_x, .y = start_y };
    loop_points.items[num_segments] = .{ .x = end_x, .y = end_y };

    // Save arrowhead points before shortening
    var loop_tip: Vec2 = undefined;
    var loop_before_tip: Vec2 = undefined;
    if (has_arrow and loop_points.items.len >= 2) {
        const s_last = loop_points.items.len - 1;
        loop_tip = loop_points.items[s_last];
        loop_before_tip = loop_points.items[s_last - 1];
        graph_mod.shortenPolylineEnd(&loop_points, config.arrow_size);
    }

    // Convert to SVG path
    if (loop_points.items.len >= 2) {
        var pts = std.ArrayListUnmanaged([2]f64){};
        defer pts.deinit(allocator);
        for (loop_points.items) |p| {
            try pts.append(allocator, .{ p.x, p.y });
        }
        const d = try SvgWriter.polylineToSVGPath(allocator, pts.items);
        defer allocator.free(d);
        try svg.path(d, null, edge_color, edge_thickness, dash_array);
    }

    // Arrowhead
    if (has_arrow and loop_points.items.len >= 1) {
        try svg.arrowhead(loop_before_tip.x, loop_before_tip.y, loop_tip.x, loop_tip.y, config.arrow_size, edge_color);
    }

    // Label placement
    {
        const label_text: ?[]const u8 = if (edge_data) |ed| ed.label else null;
        if (label_text) |lbl| {
            if (lbl.len > 0) {
                const label_x = bulge_x + 8.0;
                const label_y = cy;
                const label_font_size = config.text_size * 0.85;

                var tw: f32 = 0;
                if (font) |f| {
                    tw = f.measureText(lbl, label_font_size);
                } else {
                    tw = @as(f32, @floatFromInt(lbl.len)) * 7.0;
                }
                const th: f32 = label_font_size * 1.3;
                const pad_x: f64 = 4.0;
                const pad_y: f64 = 2.0;

                try label_placements.append(allocator, .{
                    .text = lbl,
                    .x = label_x,
                    .y = label_y,
                    .orig_x = label_x,
                    .orig_y = label_y,
                    .half_w = @as(f64, @floatCast(tw)) / 2.0 + pad_x,
                    .half_h = @as(f64, @floatCast(th)) / 2.0 + pad_y,
                    .tangent_x = 0.0,
                    .tangent_y = 1.0,
                    .font_size = label_font_size,
                    .color = config.text_color,
                });
            }
        }
    }
}

// -----------------------------------------------------------------------
// Simple word-wrap heuristic (no font metrics)
// -----------------------------------------------------------------------

/// Split `text` into lines so that each line is approximately within
/// `max_width` pixels, assuming ~8px per character.
fn simpleWordWrap(
    text: []const u8,
    max_width: f32,
    out: *std.ArrayListUnmanaged([]const u8),
    allocator: Allocator,
) !void {
    const chars_per_line: usize = @max(4, @as(usize, @intFromFloat(max_width / 8.0)));

    var line_start: usize = 0;
    var last_space: usize = 0;
    var last_space_valid = false;

    for (text, 0..) |ch, i| {
        if (ch == ' ') {
            last_space = i;
            last_space_valid = true;
        }
        if (i - line_start >= chars_per_line) {
            if (last_space_valid and last_space > line_start) {
                try out.append(allocator, text[line_start..last_space]);
                line_start = last_space + 1;
                last_space_valid = false;
            }
        }
    }
    if (line_start < text.len) {
        try out.append(allocator, text[line_start..]);
    }
}

// -----------------------------------------------------------------------
// Tests
// -----------------------------------------------------------------------

const testing = std.testing;

test "svg_render: renderGraphToSVGString empty graph" {
    var graph = Graph.init(testing.allocator);
    defer graph.deinitDeep();

    const config = RenderConfig{};
    const svg_data = try renderGraphToSVGString(testing.allocator, &graph, config, null);
    defer testing.allocator.free(svg_data);

    try testing.expect(std.mem.indexOf(u8, svg_data, "<svg") != null);
    try testing.expect(std.mem.indexOf(u8, svg_data, "</svg>") != null);
}

test "svg_render: renderGraphToSVGString single node" {
    var graph = Graph.init(testing.allocator);
    defer graph.deinitDeep();

    try graph.setNode("A", .{ .width = 100, .height = 50, .label = "Hello" });

    const config = RenderConfig{};
    const svg_data = try renderGraphToSVGString(testing.allocator, &graph, config, null);
    defer testing.allocator.free(svg_data);

    try testing.expect(std.mem.indexOf(u8, svg_data, "Hello") != null);
    try testing.expect(std.mem.indexOf(u8, svg_data, "<rect") != null);
}

test "svg_render: renderGraphToSVGString two nodes with edge" {
    var graph = Graph.init(testing.allocator);
    defer graph.deinitDeep();

    try graph.setNode("A", .{ .width = 100, .height = 50, .x = 100, .y = 50, .label = "Start" });
    try graph.setNode("B", .{ .width = 100, .height = 50, .x = 100, .y = 150, .label = "End" });
    try graph.setEdge("A", "B", .{}, null);

    const config = RenderConfig{};
    const svg_data = try renderGraphToSVGString(testing.allocator, &graph, config, null);
    defer testing.allocator.free(svg_data);

    try testing.expect(std.mem.indexOf(u8, svg_data, "Start") != null);
    try testing.expect(std.mem.indexOf(u8, svg_data, "End") != null);
    try testing.expect(std.mem.indexOf(u8, svg_data, "<path") != null);
    // Should have arrowhead polygon
    try testing.expect(std.mem.indexOf(u8, svg_data, "<polygon") != null);
}

test "svg_render: renderGraphToSVGString circle node" {
    var graph = Graph.init(testing.allocator);
    defer graph.deinitDeep();

    try graph.setNode("C", .{ .width = 80, .height = 80, .shape = .circle, .label = "Circle" });

    const config = RenderConfig{};
    const svg_data = try renderGraphToSVGString(testing.allocator, &graph, config, null);
    defer testing.allocator.free(svg_data);

    try testing.expect(std.mem.indexOf(u8, svg_data, "<ellipse") != null);
    try testing.expect(std.mem.indexOf(u8, svg_data, "Circle") != null);
}

test "svg_render: renderGraphToSVGString diamond node" {
    var graph = Graph.init(testing.allocator);
    defer graph.deinitDeep();

    try graph.setNode("D", .{ .width = 100, .height = 80, .shape = .diamond, .label = "Decision" });

    const config = RenderConfig{};
    const svg_data = try renderGraphToSVGString(testing.allocator, &graph, config, null);
    defer testing.allocator.free(svg_data);

    try testing.expect(std.mem.indexOf(u8, svg_data, "<polygon") != null);
    try testing.expect(std.mem.indexOf(u8, svg_data, "Decision") != null);
}

test "svg_render: renderGraphToSVGString rounded node" {
    var graph = Graph.init(testing.allocator);
    defer graph.deinitDeep();

    try graph.setNode("R", .{ .width = 100, .height = 50, .shape = .round, .label = "Rounded" });

    const config = RenderConfig{};
    const svg_data = try renderGraphToSVGString(testing.allocator, &graph, config, null);
    defer testing.allocator.free(svg_data);

    try testing.expect(std.mem.indexOf(u8, svg_data, "rx=") != null);
    try testing.expect(std.mem.indexOf(u8, svg_data, "Rounded") != null);
}

test "svg_render: renderGraphToSVGString edge with label" {
    var graph = Graph.init(testing.allocator);
    defer graph.deinitDeep();

    try graph.setNode("A", .{ .width = 100, .height = 50, .x = 100, .y = 50 });
    try graph.setNode("B", .{ .width = 100, .height = 50, .x = 100, .y = 200 });
    try graph.setEdge("A", "B", .{ .label = "Yes" }, null);

    const config = RenderConfig{};
    const svg_data = try renderGraphToSVGString(testing.allocator, &graph, config, null);
    defer testing.allocator.free(svg_data);

    try testing.expect(std.mem.indexOf(u8, svg_data, "Yes") != null);
    try testing.expect(std.mem.indexOf(u8, svg_data, "edge-labels") != null);
}

test "svg_render: renderGraphToSVGString dashed edge" {
    var graph = Graph.init(testing.allocator);
    defer graph.deinitDeep();

    try graph.setNode("A", .{ .width = 100, .height = 50, .x = 100, .y = 50 });
    try graph.setNode("B", .{ .width = 100, .height = 50, .x = 100, .y = 200 });
    try graph.setEdge("A", "B", .{ .line_style = .dashed }, null);

    const config = RenderConfig{};
    const svg_data = try renderGraphToSVGString(testing.allocator, &graph, config, null);
    defer testing.allocator.free(svg_data);

    try testing.expect(std.mem.indexOf(u8, svg_data, "stroke-dasharray") != null);
}

test "svg_render: renderGraphToSVGString self edge" {
    var graph = Graph.init(testing.allocator);
    defer graph.deinitDeep();

    try graph.setNode("A", .{ .width = 100, .height = 50, .x = 100, .y = 100 });
    try graph.setEdge("A", "A", .{ .label = "loop" }, null);

    const config = RenderConfig{};
    const svg_data = try renderGraphToSVGString(testing.allocator, &graph, config, null);
    defer testing.allocator.free(svg_data);

    try testing.expect(std.mem.indexOf(u8, svg_data, "loop") != null);
    try testing.expect(std.mem.indexOf(u8, svg_data, "<path") != null);
}

test "svg_render: renderGraphToSVGString custom colors" {
    var graph = Graph.init(testing.allocator);
    defer graph.deinitDeep();

    try graph.setNode("A", .{
        .width = 100,
        .height = 50,
        .label = "Styled",
        .fill_color = [4]u8{ 255, 200, 200, 255 },
        .stroke_color = [4]u8{ 200, 0, 0, 255 },
    });

    const config = RenderConfig{};
    const svg_data = try renderGraphToSVGString(testing.allocator, &graph, config, null);
    defer testing.allocator.free(svg_data);

    try testing.expect(std.mem.indexOf(u8, svg_data, "rgb(255,200,200)") != null);
    try testing.expect(std.mem.indexOf(u8, svg_data, "rgb(200,0,0)") != null);
}

test "svg_render: renderGraphToSVGString hexagon shape" {
    var graph = Graph.init(testing.allocator);
    defer graph.deinitDeep();

    try graph.setNode("H", .{ .width = 120, .height = 60, .shape = .hexagon, .label = "Hex" });

    const config = RenderConfig{};
    const svg_data = try renderGraphToSVGString(testing.allocator, &graph, config, null);
    defer testing.allocator.free(svg_data);

    // Hexagon = polygon with 6 points
    try testing.expect(std.mem.indexOf(u8, svg_data, "<polygon") != null);
    try testing.expect(std.mem.indexOf(u8, svg_data, "Hex") != null);
}

test "svg_render: renderGraphToSVGString subgraph" {
    var graph = Graph.init(testing.allocator);
    defer graph.deinitDeep();

    try graph.setNode("sg1", .{
        .width = 200,
        .height = 150,
        .x = 100,
        .y = 75,
        .is_subgraph = true,
        .subgraph_title = "My Subgraph",
    });
    try graph.setNode("A", .{ .width = 80, .height = 40, .x = 80, .y = 60, .label = "Inside" });
    try graph.setParent("A", "sg1");

    const config = RenderConfig{};
    const svg_data = try renderGraphToSVGString(testing.allocator, &graph, config, null);
    defer testing.allocator.free(svg_data);

    try testing.expect(std.mem.indexOf(u8, svg_data, "My Subgraph") != null);
    try testing.expect(std.mem.indexOf(u8, svg_data, "subgraphs") != null);
    try testing.expect(std.mem.indexOf(u8, svg_data, "Inside") != null);
}

test "svg_render: renderGraphToSVGString bidirectional edge" {
    var graph = Graph.init(testing.allocator);
    defer graph.deinitDeep();

    try graph.setNode("A", .{ .width = 100, .height = 50, .x = 100, .y = 50 });
    try graph.setNode("B", .{ .width = 100, .height = 50, .x = 100, .y = 200 });
    try graph.setEdge("A", "B", .{ .arrowtail = "normal" }, null);

    const config = RenderConfig{};
    const svg_data = try renderGraphToSVGString(testing.allocator, &graph, config, null);
    defer testing.allocator.free(svg_data);

    // Two arrowhead polygons
    var count: usize = 0;
    var search: []const u8 = svg_data;
    while (std.mem.indexOf(u8, search, "<polygon")) |idx| {
        count += 1;
        search = search[idx + 8 ..];
    }
    try testing.expect(count >= 2);
}

test "svg_render: renderGraphToSVGString no-arrow edge" {
    var graph = Graph.init(testing.allocator);
    defer graph.deinitDeep();

    try graph.setNode("A", .{ .width = 100, .height = 50, .x = 100, .y = 50 });
    try graph.setNode("B", .{ .width = 100, .height = 50, .x = 100, .y = 200 });
    try graph.setEdge("A", "B", .{ .arrowhead = "none" }, null);

    const config = RenderConfig{};
    const svg_data = try renderGraphToSVGString(testing.allocator, &graph, config, null);
    defer testing.allocator.free(svg_data);

    // Should have path but no polygon arrowhead
    try testing.expect(std.mem.indexOf(u8, svg_data, "<path") != null);
    // No arrowhead polygon should be present (for this edge at least)
    // The <polygon tag should not appear since no arrows
    try testing.expect(std.mem.indexOf(u8, svg_data, "<polygon") == null);
}

test "svg_render: saveToFile roundtrip" {
    var graph = Graph.init(testing.allocator);
    defer graph.deinitDeep();

    try graph.setNode("A", .{ .width = 80, .height = 40, .x = 50, .y = 30, .label = "Node" });

    const config = RenderConfig{};
    const tmp_path = "/tmp/merrow_svg_render_test.svg";

    try renderGraphToSVGWithFont(testing.allocator, &graph, tmp_path, config, null);

    // Read back and verify
    const data = try std.fs.cwd().readFileAlloc(testing.allocator, tmp_path, 256 * 1024);
    defer testing.allocator.free(data);
    try testing.expect(std.mem.indexOf(u8, data, "Node") != null);
    try testing.expect(std.mem.indexOf(u8, data, "<svg") != null);

    // Clean up
    try std.fs.cwd().deleteFile(tmp_path);
}

test "svg_render: simpleWordWrap" {
    var lines = std.ArrayListUnmanaged([]const u8){};
    defer lines.deinit(testing.allocator);

    try simpleWordWrap("Hello World How Are You", 80, &lines, testing.allocator);
    try testing.expect(lines.items.len >= 2);
}

test "svg_render: renderGraphToSVGString stadium shape" {
    var graph = Graph.init(testing.allocator);
    defer graph.deinitDeep();

    try graph.setNode("S", .{ .width = 120, .height = 50, .shape = .stadium, .label = "Stadium" });

    const config = RenderConfig{};
    const svg_data = try renderGraphToSVGString(testing.allocator, &graph, config, null);
    defer testing.allocator.free(svg_data);

    try testing.expect(std.mem.indexOf(u8, svg_data, "rx=") != null);
    try testing.expect(std.mem.indexOf(u8, svg_data, "Stadium") != null);
}

test "svg_render: renderGraphToSVGString subroutine shape" {
    var graph = Graph.init(testing.allocator);
    defer graph.deinitDeep();

    try graph.setNode("Sub", .{ .width = 120, .height = 50, .shape = .subroutine, .label = "Process" });

    const config = RenderConfig{};
    const svg_data = try renderGraphToSVGString(testing.allocator, &graph, config, null);
    defer testing.allocator.free(svg_data);

    // Should have the main rect plus two inner vertical lines
    var rect_count: usize = 0;
    var search: []const u8 = svg_data;
    while (std.mem.indexOf(u8, search, "<rect")) |idx| {
        rect_count += 1;
        search = search[idx + 5 ..];
    }
    // At least 1 rect for the body + 1 for background
    try testing.expect(rect_count >= 1);

    // Should have two inner lines
    var line_count: usize = 0;
    search = svg_data;
    while (std.mem.indexOf(u8, search, "<line")) |idx| {
        line_count += 1;
        search = search[idx + 5 ..];
    }
    try testing.expect(line_count >= 2);
    try testing.expect(std.mem.indexOf(u8, svg_data, "Process") != null);
}

test "svg_render: renderGraphToSVGString trapezoid shape" {
    var graph = Graph.init(testing.allocator);
    defer graph.deinitDeep();

    try graph.setNode("T", .{ .width = 100, .height = 50, .shape = .trapezoid, .label = "Trap" });

    const config = RenderConfig{};
    const svg_data = try renderGraphToSVGString(testing.allocator, &graph, config, null);
    defer testing.allocator.free(svg_data);

    try testing.expect(std.mem.indexOf(u8, svg_data, "<polygon") != null);
    try testing.expect(std.mem.indexOf(u8, svg_data, "Trap") != null);
}

test "svg_render: renderGraphToSVGString cylinder shape" {
    var graph = Graph.init(testing.allocator);
    defer graph.deinitDeep();

    try graph.setNode("DB", .{ .width = 100, .height = 70, .shape = .cylinder, .label = "Database" });

    const config = RenderConfig{};
    const svg_data = try renderGraphToSVGString(testing.allocator, &graph, config, null);
    defer testing.allocator.free(svg_data);

    // Should have ellipses for caps
    try testing.expect(std.mem.indexOf(u8, svg_data, "<ellipse") != null);
    try testing.expect(std.mem.indexOf(u8, svg_data, "Database") != null);
}

test "svg_render: renderGraphToSVGString multiple shapes" {
    var graph = Graph.init(testing.allocator);
    defer graph.deinitDeep();

    try graph.setNode("A", .{ .width = 80, .height = 40, .x = 50, .y = 30, .shape = .box, .label = "Box" });
    try graph.setNode("B", .{ .width = 80, .height = 80, .x = 150, .y = 50, .shape = .circle, .label = "Circle" });
    try graph.setNode("C", .{ .width = 100, .height = 60, .x = 250, .y = 40, .shape = .diamond, .label = "?" });
    try graph.setEdge("A", "B", .{}, null);
    try graph.setEdge("B", "C", .{ .label = "maybe" }, null);

    const config = RenderConfig{};
    const svg_data = try renderGraphToSVGString(testing.allocator, &graph, config, null);
    defer testing.allocator.free(svg_data);

    try testing.expect(std.mem.indexOf(u8, svg_data, "Box") != null);
    try testing.expect(std.mem.indexOf(u8, svg_data, "Circle") != null);
    try testing.expect(std.mem.indexOf(u8, svg_data, "maybe") != null);
    try testing.expect(std.mem.indexOf(u8, svg_data, "<rect") != null);
    try testing.expect(std.mem.indexOf(u8, svg_data, "<ellipse") != null);
    try testing.expect(std.mem.indexOf(u8, svg_data, "<polygon") != null);
}

test "svg_render: renderGraphToSVGString dotted edge" {
    var graph = Graph.init(testing.allocator);
    defer graph.deinitDeep();

    try graph.setNode("A", .{ .width = 80, .height = 40, .x = 50, .y = 30 });
    try graph.setNode("B", .{ .width = 80, .height = 40, .x = 50, .y = 130 });
    try graph.setEdge("A", "B", .{ .line_style = .dotted }, null);

    const config = RenderConfig{};
    const svg_data = try renderGraphToSVGString(testing.allocator, &graph, config, null);
    defer testing.allocator.free(svg_data);

    try testing.expect(std.mem.indexOf(u8, svg_data, "stroke-dasharray=\"4,4\"") != null);
}

test "svg_render: renderGraphToSVGString thick edge" {
    var graph = Graph.init(testing.allocator);
    defer graph.deinitDeep();

    try graph.setNode("A", .{ .width = 80, .height = 40, .x = 50, .y = 30 });
    try graph.setNode("B", .{ .width = 80, .height = 40, .x = 50, .y = 130 });
    try graph.setEdge("A", "B", .{ .line_style = .thick }, null);

    const config = RenderConfig{};
    const svg_data = try renderGraphToSVGString(testing.allocator, &graph, config, null);
    defer testing.allocator.free(svg_data);

    // Thick edges should have a wider stroke-width (base*2 = 4)
    try testing.expect(std.mem.indexOf(u8, svg_data, "stroke-width=\"4") != null);
}
