//! ER (Entity-Relationship) diagram SVG renderer.
//!
//! Renders an ErDiagram model to SVG, drawing entity boxes with attributes,
//! relationship lines with cardinality markers, and optional titles.

const std = @import("std");
const Allocator = std.mem.Allocator;
const ErDiagram = @import("model.zig").ErDiagram;
const Entity = @import("model.zig").Entity;
const Attribute = @import("model.zig").Attribute;
const AttributeKey = @import("model.zig").AttributeKey;
const Cardinality = @import("model.zig").Cardinality;
const Identification = @import("model.zig").Identification;
const RelSpec = @import("model.zig").RelSpec;
const Direction = @import("model.zig").Direction;
const er_model = @import("model.zig");
const svg_mod = @import("../render/svg.zig");
const SvgWriter = svg_mod.SvgWriter;
const TextAnchor = svg_mod.TextAnchor;

// -----------------------------------------------------------------------
// Layout constants
// -----------------------------------------------------------------------

const MARGIN: f64 = 50.0;
const TITLE_FONT_SIZE: f64 = 20.0;
const ENTITY_NAME_FONT_SIZE: f64 = 14.0;
const ATTR_FONT_SIZE: f64 = 12.0;
const CHAR_WIDTH: f64 = 8.0;
const ATTR_CHAR_WIDTH: f64 = 7.2;
const HEADER_HEIGHT: f64 = 42.75;
const ATTR_ROW_HEIGHT: f64 = 28.0;
const ENTITY_MIN_WIDTH: f64 = 120.0;
const ENTITY_PADDING: f64 = 12.0;
const NODESEP: f64 = 80.0;
const RANKSEP: f64 = 80.0;
const EDGE_STROKE_WIDTH: f64 = 1.5;
const LABEL_FONT_SIZE: f64 = 12.0;

// -----------------------------------------------------------------------
// Public API
// -----------------------------------------------------------------------

/// Render an ER diagram to an SVG file.
pub fn renderErToSVG(
    allocator: Allocator,
    diagram: *const ErDiagram,
    output_path: []const u8,
) !void {
    const svg_content = try renderErToSVGString(allocator, diagram);
    defer allocator.free(svg_content);

    const file = try std.fs.cwd().createFile(output_path, .{});
    defer file.close();
    try file.writeAll(svg_content);
}

/// Render an ER diagram to an SVG string. Caller owns the returned slice.
pub fn renderErToSVGString(
    allocator: Allocator,
    diagram: *const ErDiagram,
) ![]u8 {
    const mutable_diagram = @constCast(diagram);
    const entity_count = mutable_diagram.entities.count();

    if (entity_count == 0) {
        var svg = try SvgWriter.init(allocator, 400, 200);
        defer svg.deinit();
        if (diagram.title) |title| {
            try svg.textCentered(200, 30, title, TITLE_FONT_SIZE, er_model.entity_name_color, "sans-serif");
        }
        try svg.textCentered(200, 100, "(empty ER diagram)", ENTITY_NAME_FONT_SIZE, .{ 128, 128, 128, 255 }, "sans-serif");
        return try svg.finalize();
    }

    // Collect sorted entity names for deterministic layout
    const sorted_names = try diagram.sortedEntityNames();
    defer allocator.free(sorted_names);

    // Compute entity dimensions
    var entity_widths = std.StringHashMap(f64).init(allocator);
    defer entity_widths.deinit();
    var entity_heights = std.StringHashMap(f64).init(allocator);
    defer entity_heights.deinit();
    var col_widths_map = std.StringHashMap([3]f64).init(allocator);
    defer col_widths_map.deinit();

    for (sorted_names) |name| {
        if (mutable_diagram.entities.getPtr(name)) |entity| {
            const dims = computeEntityDimensions(entity);
            try entity_widths.put(name, dims.width);
            try entity_heights.put(name, dims.height);
            try col_widths_map.put(name, dims.col_widths);
        }
    }

    // Assign positions using a simple grid/layer layout
    var positions = std.StringHashMap(Position).init(allocator);
    defer positions.deinit();

    try layoutEntities(allocator, diagram, sorted_names, &entity_widths, &entity_heights, &positions);

    // Compute bounding box
    var min_x: f64 = std.math.inf(f64);
    var min_y: f64 = std.math.inf(f64);
    var max_x: f64 = -std.math.inf(f64);
    var max_y: f64 = -std.math.inf(f64);

    for (sorted_names) |name| {
        if (positions.get(name)) |pos| {
            const w = entity_widths.get(name) orelse ENTITY_MIN_WIDTH;
            const h = entity_heights.get(name) orelse HEADER_HEIGHT;
            const left = pos.x;
            const top = pos.y;
            const right = pos.x + w;
            const bottom = pos.y + h;

            if (left < min_x) min_x = left;
            if (top < min_y) min_y = top;
            if (right > max_x) max_x = right;
            if (bottom > max_y) max_y = bottom;
        }
    }

    const title_offset: f64 = if (diagram.title != null) 40.0 else 0.0;
    const svg_width = (max_x - min_x) + MARGIN * 2;
    const svg_height = (max_y - min_y) + MARGIN * 2 + title_offset;
    const offset_x = MARGIN - min_x;
    const offset_y = MARGIN - min_y + title_offset;

    var svg = try SvgWriter.init(allocator, @max(@ceil(svg_width), 200), @max(@ceil(svg_height), 150));
    defer svg.deinit();

    // Background
    try svg.rect(0, 0, @max(svg_width, 200), @max(svg_height, 150), 0, 0, .{ 255, 255, 255, 255 }, null, 0);

    // Title
    if (diagram.title) |title| {
        try svg.textCentered(
            svg_width / 2.0,
            30.0,
            title,
            TITLE_FONT_SIZE,
            er_model.entity_name_color,
            "sans-serif",
        );
    }

    // Draw relationships first (behind entities)
    for (diagram.relationships.items) |rel| {
        const from_pos = positions.get(rel.entity_a) orelse continue;
        const to_pos = positions.get(rel.entity_b) orelse continue;
        const from_w = entity_widths.get(rel.entity_a) orelse ENTITY_MIN_WIDTH;
        const from_h = entity_heights.get(rel.entity_a) orelse HEADER_HEIGHT;
        const to_w = entity_widths.get(rel.entity_b) orelse ENTITY_MIN_WIDTH;
        const to_h = entity_heights.get(rel.entity_b) orelse HEADER_HEIGHT;

        try renderRelationship(
            &svg,
            from_pos.x + offset_x,
            from_pos.y + offset_y,
            from_w,
            from_h,
            to_pos.x + offset_x,
            to_pos.y + offset_y,
            to_w,
            to_h,
            rel.role,
            rel.rel_spec,
            std.mem.eql(u8, rel.entity_a, rel.entity_b),
        );
    }

    // Draw entities
    for (sorted_names) |name| {
        const pos = positions.get(name) orelse continue;
        const entity_ptr = mutable_diagram.entities.getPtr(name) orelse continue;
        const w = entity_widths.get(name) orelse ENTITY_MIN_WIDTH;
        const h = entity_heights.get(name) orelse HEADER_HEIGHT;
        const cols = col_widths_map.get(name) orelse [3]f64{ 65.0, 75.0, 47.0 };

        try renderEntity(
            &svg,
            entity_ptr,
            pos.x + offset_x,
            pos.y + offset_y,
            w,
            h,
            cols,
        );
    }

    return try svg.finalize();
}

// -----------------------------------------------------------------------
// Dimension computation
// -----------------------------------------------------------------------

const EntityDimensions = struct {
    width: f64,
    height: f64,
    col_widths: [3]f64,
};

fn computeEntityDimensions(entity: *const Entity) EntityDimensions {
    const display_name = entity.displayName();
    const name_width = @as(f64, @floatFromInt(display_name.len)) * CHAR_WIDTH + ENTITY_PADDING * 2;

    if (entity.attributes.items.len == 0) {
        const w = @max(name_width, ENTITY_MIN_WIDTH);
        return .{
            .width = w,
            .height = HEADER_HEIGHT,
            .col_widths = .{ w / 3.0, w / 3.0, w / 3.0 },
        };
    }

    // Measure column widths from attribute data
    var type_max: f64 = 40.0;
    var name_max: f64 = 40.0;
    var key_max: f64 = 30.0;

    for (entity.attributes.items) |attr| {
        const tw = @as(f64, @floatFromInt(attr.attr_type.len)) * ATTR_CHAR_WIDTH + ENTITY_PADDING * 2;
        if (tw > type_max) type_max = tw;

        const nw = @as(f64, @floatFromInt(attr.name.len)) * ATTR_CHAR_WIDTH + ENTITY_PADDING * 2;
        if (nw > name_max) name_max = nw;

        var key_len: usize = 0;
        for (attr.keys.items, 0..) |key, ki| {
            key_len += key.asStr().len;
            if (ki > 0) key_len += 1; // comma
        }
        if (key_len > 0) {
            const kw = @as(f64, @floatFromInt(key_len)) * ATTR_CHAR_WIDTH + ENTITY_PADDING * 2;
            if (kw > key_max) key_max = kw;
        }
    }

    const total_width = type_max + name_max + key_max;
    const w = @max(@max(total_width, name_width), ENTITY_MIN_WIDTH);
    const h = HEADER_HEIGHT + @as(f64, @floatFromInt(entity.attributes.items.len)) * ATTR_ROW_HEIGHT;

    return .{
        .width = w,
        .height = h,
        .col_widths = .{ type_max, name_max, key_max },
    };
}

// -----------------------------------------------------------------------
// Layout
// -----------------------------------------------------------------------

const Position = struct {
    x: f64,
    y: f64,
};

/// Simple layered layout for entities based on relationships.
/// Entities involved in relationships are placed in a dependency-based layout;
/// orphan entities are placed in a final row.
fn layoutEntities(
    allocator: Allocator,
    diagram: *const ErDiagram,
    sorted_names: []const []const u8,
    widths: *const std.StringHashMap(f64),
    heights: *const std.StringHashMap(f64),
    positions: *std.StringHashMap(Position),
) !void {
    const n = sorted_names.len;
    if (n == 0) return;

    // Build adjacency: for each entity, track which entities it connects to
    var connected_to = std.StringHashMap(std.ArrayListUnmanaged([]const u8)).init(allocator);
    defer {
        var iter = connected_to.iterator();
        while (iter.next()) |entry| {
            entry.value_ptr.deinit(allocator);
        }
        connected_to.deinit();
    }

    // Track all entities that appear in relationships
    var in_rel = std.StringHashMap(bool).init(allocator);
    defer in_rel.deinit();

    for (diagram.relationships.items) |rel| {
        try in_rel.put(rel.entity_a, true);
        try in_rel.put(rel.entity_b, true);

        // entity_a -> entity_b
        const entry_a = try connected_to.getOrPut(rel.entity_a);
        if (!entry_a.found_existing) {
            entry_a.value_ptr.* = .{};
        }
        try entry_a.value_ptr.append(allocator, rel.entity_b);
    }

    // Assign layers using BFS from entities that appear first in relationships
    var layer_map = std.StringHashMap(usize).init(allocator);
    defer layer_map.deinit();

    var queue = std.ArrayListUnmanaged([]const u8){};
    defer queue.deinit(allocator);

    // Seed: entities that are sources (entity_a) but prioritize sorted order
    for (sorted_names) |name| {
        if (in_rel.contains(name) and !layer_map.contains(name)) {
            try layer_map.put(name, 0);
            try queue.append(allocator, name);

            // BFS
            var qi: usize = 0;
            while (qi < queue.items.len) : (qi += 1) {
                const current = queue.items[qi];
                const current_layer = layer_map.get(current) orelse 0;

                if (connected_to.getPtr(current)) |neighbors| {
                    for (neighbors.items) |neighbor| {
                        if (!layer_map.contains(neighbor)) {
                            try layer_map.put(neighbor, current_layer + 1);
                            try queue.append(allocator, neighbor);
                        }
                    }
                }
            }
        }
    }

    // Orphan entities (not in any relationship) get the next layer
    var max_layer: usize = 0;
    {
        var iter = layer_map.iterator();
        while (iter.next()) |entry| {
            if (entry.value_ptr.* > max_layer) max_layer = entry.value_ptr.*;
        }
    }

    for (sorted_names) |name| {
        if (!layer_map.contains(name)) {
            try layer_map.put(name, max_layer + 1);
        }
    }

    // Group entities by layer
    const total_layers = max_layer + 2;
    var layers = try allocator.alloc(std.ArrayListUnmanaged([]const u8), total_layers);
    defer {
        for (layers) |*l| l.deinit(allocator);
        allocator.free(layers);
    }
    for (layers) |*l| l.* = .{};

    for (sorted_names) |name| {
        const layer = layer_map.get(name) orelse 0;
        if (layer < total_layers) {
            try layers[layer].append(allocator, name);
        }
    }

    // Determine direction
    const is_horizontal = (diagram.direction == .LR or diagram.direction == .RL);

    // Assign positions layer by layer
    var layer_offset: f64 = 0;
    for (layers) |layer_entities| {
        if (layer_entities.items.len == 0) continue;

        var cross_offset: f64 = 0;
        var max_primary: f64 = 0;

        for (layer_entities.items) |name| {
            const w = widths.get(name) orelse ENTITY_MIN_WIDTH;
            const h = heights.get(name) orelse HEADER_HEIGHT;

            if (is_horizontal) {
                try positions.put(name, .{ .x = layer_offset, .y = cross_offset });
                cross_offset += h + NODESEP;
                if (w > max_primary) max_primary = w;
            } else {
                try positions.put(name, .{ .x = cross_offset, .y = layer_offset });
                cross_offset += w + NODESEP;
                if (h > max_primary) max_primary = h;
            }
        }

        layer_offset += max_primary + RANKSEP;
    }
}

// -----------------------------------------------------------------------
// Entity rendering
// -----------------------------------------------------------------------

fn renderEntity(
    svg: *SvgWriter,
    entity: *const Entity,
    x: f64,
    y: f64,
    width: f64,
    height: f64,
    col_widths: [3]f64,
) !void {
    const display_name = entity.displayName();
    const num_attrs = entity.attributes.items.len;

    // Main entity box
    try svg.rect(x, y, width, height, 0, 0, er_model.entity_header_fill, er_model.entity_stroke, 1.3);

    if (num_attrs == 0) {
        // Simple box with centered name
        try svg.textCentered(
            x + width / 2.0,
            y + height / 2.0 + 5.0,
            display_name,
            ENTITY_NAME_FONT_SIZE,
            er_model.entity_name_color,
            "sans-serif",
        );
        return;
    }

    // Header: entity name centered
    try svg.textCentered(
        x + width / 2.0,
        y + HEADER_HEIGHT / 2.0 + 5.0,
        display_name,
        ENTITY_NAME_FONT_SIZE,
        er_model.entity_name_color,
        "sans-serif",
    );

    // Horizontal divider under header
    const content_y = y + HEADER_HEIGHT;
    try svg.line(x, content_y, x + width, content_y, er_model.entity_stroke, 1.3, null);

    // Column positions
    const type_col_end = x + col_widths[0];
    const name_col_end = type_col_end + col_widths[1];

    // Vertical dividers in attribute area
    const divider_bottom = y + height;
    try svg.line(type_col_end, content_y, type_col_end, divider_bottom, er_model.entity_stroke, 1.0, null);
    try svg.line(name_col_end, content_y, name_col_end, divider_bottom, er_model.entity_stroke, 1.0, null);

    // Attribute rows
    for (entity.attributes.items, 0..) |attr, i| {
        const row_y = content_y + @as(f64, @floatFromInt(i)) * ATTR_ROW_HEIGHT;

        // Alternating row background
        const row_fill: [4]u8 = if (i % 2 == 0) er_model.entity_row_odd_fill else er_model.entity_row_even_fill;
        try svg.rect(x + 0.5, row_y + 0.5, width - 1.0, ATTR_ROW_HEIGHT - 0.5, 0, 0, row_fill, null, 0);

        // Row separator line
        if (i > 0) {
            try svg.line(x, row_y, x + width, row_y, er_model.entity_stroke, 0.5, null);
        }

        // Text y position (vertically centered in row)
        const text_y = row_y + ATTR_ROW_HEIGHT / 2.0 + 4.0;

        // Type column
        try svg.textAt(
            x + ENTITY_PADDING,
            text_y,
            attr.attr_type,
            ATTR_FONT_SIZE,
            er_model.attr_text_color,
            "sans-serif",
            TextAnchor.start,
        );

        // Name column
        try svg.textAt(
            type_col_end + ENTITY_PADDING,
            text_y,
            attr.name,
            ATTR_FONT_SIZE,
            er_model.attr_text_color,
            "sans-serif",
            TextAnchor.start,
        );

        // Keys column
        if (attr.keys.items.len > 0) {
            // Build key string
            var key_buf: [64]u8 = undefined;
            var key_len: usize = 0;
            for (attr.keys.items, 0..) |key, ki| {
                if (ki > 0) {
                    key_buf[key_len] = ',';
                    key_len += 1;
                }
                const ks = key.asStr();
                if (key_len + ks.len <= key_buf.len) {
                    @memcpy(key_buf[key_len .. key_len + ks.len], ks);
                    key_len += ks.len;
                }
            }
            try svg.textAt(
                name_col_end + ENTITY_PADDING,
                text_y,
                key_buf[0..key_len],
                ATTR_FONT_SIZE,
                er_model.attr_text_color,
                "sans-serif",
                TextAnchor.start,
            );
        }
    }
}

// -----------------------------------------------------------------------
// Relationship rendering
// -----------------------------------------------------------------------

fn renderRelationship(
    svg: *SvgWriter,
    from_x: f64,
    from_y: f64,
    from_w: f64,
    from_h: f64,
    to_x: f64,
    to_y: f64,
    to_w: f64,
    to_h: f64,
    role: []const u8,
    rel_spec: RelSpec,
    is_self_ref: bool,
) !void {
    // Calculate center points of entities
    const from_cx = from_x + from_w / 2.0;
    const from_cy = from_y + from_h / 2.0;
    const to_cx = to_x + to_w / 2.0;
    const to_cy = to_y + to_h / 2.0;

    if (is_self_ref) {
        // Self-referencing: draw a loop
        const loop_offset: f64 = 40.0;
        const start_x = from_x + from_w;
        const start_y = from_cy - 10.0;
        const end_x = from_x + from_w;
        const end_y = from_cy + 10.0;

        // Draw three line segments forming a loop
        try svg.line(start_x, start_y, start_x + loop_offset, start_y, er_model.rel_line_color, EDGE_STROKE_WIDTH, null);
        try svg.line(start_x + loop_offset, start_y, start_x + loop_offset, end_y, er_model.rel_line_color, EDGE_STROKE_WIDTH, null);
        try svg.line(start_x + loop_offset, end_y, end_x, end_y, er_model.rel_line_color, EDGE_STROKE_WIDTH, null);

        // Cardinality markers
        try renderCardinalityMarker(svg, start_x + 4.0, start_y, 1.0, 0.0, rel_spec.card_a);
        try renderCardinalityMarker(svg, end_x + 4.0, end_y, -1.0, 0.0, rel_spec.card_b);

        // Role label
        if (role.len > 0) {
            const label_x = start_x + loop_offset / 2.0;
            const label_y = start_y - 8.0;
            try renderRoleLabel(svg, label_x, label_y, role);
        }
        return;
    }

    // Calculate edge attachment points (intersect entity boundaries)
    const start = computeExitPoint(from_x, from_y, from_w, from_h, to_cx, to_cy);
    const end = computeEntryPoint(to_x, to_y, to_w, to_h, from_cx, from_cy);

    // Direction vector for cardinality markers
    const dx = end.x - start.x;
    const dy = end.y - start.y;
    const len = @sqrt(dx * dx + dy * dy);
    const ndx = if (len > 0.001) dx / len else 0.0;
    const ndy = if (len > 0.001) dy / len else 1.0;

    // Draw relationship line
    const dash: ?[]const u8 = if (rel_spec.rel_type == .non_identifying) "6 3" else null;
    try svg.line(start.x, start.y, end.x, end.y, er_model.rel_line_color, EDGE_STROKE_WIDTH, dash);

    // Draw cardinality markers near each end
    const marker_offset: f64 = 18.0;
    try renderCardinalityMarker(
        svg,
        start.x + ndx * marker_offset,
        start.y + ndy * marker_offset,
        ndx,
        ndy,
        rel_spec.card_a,
    );
    try renderCardinalityMarker(
        svg,
        end.x - ndx * marker_offset,
        end.y - ndy * marker_offset,
        -ndx,
        -ndy,
        rel_spec.card_b,
    );

    // Draw role label at midpoint
    if (role.len > 0) {
        const mid_x = (start.x + end.x) / 2.0;
        const mid_y = (start.y + end.y) / 2.0;
        // Offset label perpendicular to the line
        const perp_x = -ndy * 12.0;
        const perp_y = ndx * 12.0;
        try renderRoleLabel(svg, mid_x + perp_x, mid_y + perp_y, role);
    }
}

fn computeExitPoint(
    rect_x: f64,
    rect_y: f64,
    rect_w: f64,
    rect_h: f64,
    target_x: f64,
    target_y: f64,
) Position {
    return computeRectEdgeIntersection(
        rect_x + rect_w / 2.0,
        rect_y + rect_h / 2.0,
        rect_w,
        rect_h,
        target_x,
        target_y,
    );
}

fn computeEntryPoint(
    rect_x: f64,
    rect_y: f64,
    rect_w: f64,
    rect_h: f64,
    source_x: f64,
    source_y: f64,
) Position {
    return computeRectEdgeIntersection(
        rect_x + rect_w / 2.0,
        rect_y + rect_h / 2.0,
        rect_w,
        rect_h,
        source_x,
        source_y,
    );
}

/// Compute where a line from (cx, cy) toward (tx, ty) intersects a rectangle
/// centered at (cx, cy) with given width and height.
fn computeRectEdgeIntersection(
    cx: f64,
    cy: f64,
    w: f64,
    h: f64,
    tx: f64,
    ty: f64,
) Position {
    const dx = tx - cx;
    const dy = ty - cy;

    if (@abs(dx) < 0.001 and @abs(dy) < 0.001) {
        return .{ .x = cx, .y = cy };
    }

    const half_w = w / 2.0;
    const half_h = h / 2.0;

    // Calculate intersection with each side
    var t: f64 = std.math.inf(f64);

    // Right side
    if (dx > 0.001) {
        const t_right = half_w / dx;
        const y_at_right = dy * t_right;
        if (@abs(y_at_right) <= half_h and t_right < t) t = t_right;
    }
    // Left side
    if (dx < -0.001) {
        const t_left = -half_w / dx;
        const y_at_left = dy * t_left;
        if (@abs(y_at_left) <= half_h and t_left < t) t = t_left;
    }
    // Bottom side
    if (dy > 0.001) {
        const t_bottom = half_h / dy;
        const x_at_bottom = dx * t_bottom;
        if (@abs(x_at_bottom) <= half_w and t_bottom < t) t = t_bottom;
    }
    // Top side
    if (dy < -0.001) {
        const t_top = -half_h / dy;
        const x_at_top = dx * t_top;
        if (@abs(x_at_top) <= half_w and t_top < t) t = t_top;
    }

    if (t == std.math.inf(f64)) {
        return .{ .x = cx, .y = cy };
    }

    return .{
        .x = cx + dx * t,
        .y = cy + dy * t,
    };
}

// -----------------------------------------------------------------------
// Cardinality markers
// -----------------------------------------------------------------------

/// Render a cardinality marker at position (x, y) with direction (dx, dy).
fn renderCardinalityMarker(
    svg: *SvgWriter,
    x: f64,
    y: f64,
    dx: f64,
    dy: f64,
    card: Cardinality,
) !void {
    // Perpendicular direction
    const px = -dy;
    const py = dx;
    const mark_size: f64 = 8.0;
    const line_size: f64 = 10.0;

    switch (card) {
        .only_one => {
            // Two parallel lines perpendicular to the relationship line
            try svg.line(
                x + px * mark_size,
                y + py * mark_size,
                x - px * mark_size,
                y - py * mark_size,
                er_model.rel_line_color,
                EDGE_STROKE_WIDTH,
                null,
            );
            try svg.line(
                x + dx * 5.0 + px * mark_size,
                y + dy * 5.0 + py * mark_size,
                x + dx * 5.0 - px * mark_size,
                y + dy * 5.0 - py * mark_size,
                er_model.rel_line_color,
                EDGE_STROKE_WIDTH,
                null,
            );
        },
        .zero_or_one => {
            // One line + circle
            try svg.line(
                x + px * mark_size,
                y + py * mark_size,
                x - px * mark_size,
                y - py * mark_size,
                er_model.rel_line_color,
                EDGE_STROKE_WIDTH,
                null,
            );
            try svg.ellipse(
                x + dx * line_size,
                y + dy * line_size,
                5.0,
                5.0,
                .{ 255, 255, 255, 255 },
                er_model.rel_line_color,
                EDGE_STROKE_WIDTH,
            );
        },
        .one_or_more => {
            // One line + crow's foot (three lines fanning out)
            try svg.line(
                x + px * mark_size,
                y + py * mark_size,
                x - px * mark_size,
                y - py * mark_size,
                er_model.rel_line_color,
                EDGE_STROKE_WIDTH,
                null,
            );
            // Crow's foot
            const foot_x = x + dx * line_size;
            const foot_y = y + dy * line_size;
            try svg.line(foot_x, foot_y, x + px * mark_size, y + py * mark_size, er_model.rel_line_color, EDGE_STROKE_WIDTH, null);
            try svg.line(foot_x, foot_y, x - px * mark_size, y - py * mark_size, er_model.rel_line_color, EDGE_STROKE_WIDTH, null);
        },
        .zero_or_more => {
            // Circle + crow's foot
            try svg.ellipse(
                x,
                y,
                5.0,
                5.0,
                .{ 255, 255, 255, 255 },
                er_model.rel_line_color,
                EDGE_STROKE_WIDTH,
            );
            const foot_x = x + dx * line_size;
            const foot_y = y + dy * line_size;
            try svg.line(foot_x, foot_y, x + px * mark_size, y + py * mark_size, er_model.rel_line_color, EDGE_STROKE_WIDTH, null);
            try svg.line(foot_x, foot_y, x - px * mark_size, y - py * mark_size, er_model.rel_line_color, EDGE_STROKE_WIDTH, null);
        },
    }
}

// -----------------------------------------------------------------------
// Role label rendering
// -----------------------------------------------------------------------

fn renderRoleLabel(
    svg: *SvgWriter,
    x: f64,
    y: f64,
    role: []const u8,
) !void {
    if (role.len == 0) return;

    // Background rect for readability
    const label_w = @as(f64, @floatFromInt(role.len)) * 7.0 + 12.0;
    const label_h: f64 = 20.0;
    try svg.rect(
        x - label_w / 2.0,
        y - label_h / 2.0,
        label_w,
        label_h,
        3,
        3,
        er_model.label_bg_color,
        null,
        0,
    );

    try svg.textCentered(x, y + 4.0, role, LABEL_FONT_SIZE, er_model.rel_label_color, "sans-serif");
}

// -----------------------------------------------------------------------
// Tests
// -----------------------------------------------------------------------

test "er svg: renders empty diagram" {
    const allocator = std.testing.allocator;
    var diagram = ErDiagram.init(allocator);
    defer diagram.deinit();

    const svg = try renderErToSVGString(allocator, &diagram);
    defer allocator.free(svg);

    try std.testing.expect(svg.len > 0);
    try std.testing.expect(std.mem.indexOf(u8, svg, "<svg") != null);
    try std.testing.expect(std.mem.indexOf(u8, svg, "empty ER diagram") != null);
}

test "er svg: renders single entity" {
    const allocator = std.testing.allocator;
    var diagram = ErDiagram.init(allocator);
    defer diagram.deinit();

    _ = try diagram.addEntity("CUSTOMER", null);

    const svg = try renderErToSVGString(allocator, &diagram);
    defer allocator.free(svg);

    try std.testing.expect(std.mem.indexOf(u8, svg, "CUSTOMER") != null);
    try std.testing.expect(std.mem.indexOf(u8, svg, "<rect") != null);
}

test "er svg: renders entity with alias" {
    const allocator = std.testing.allocator;
    var diagram = ErDiagram.init(allocator);
    defer diagram.deinit();

    _ = try diagram.addEntity("CUST", "The Customer");

    const svg = try renderErToSVGString(allocator, &diagram);
    defer allocator.free(svg);

    try std.testing.expect(std.mem.indexOf(u8, svg, "The Customer") != null);
}

test "er svg: renders entity with attributes" {
    const allocator = std.testing.allocator;
    var diagram = ErDiagram.init(allocator);
    defer diagram.deinit();

    _ = try diagram.ensureEntity("ORDER");
    var attr1 = try @import("model.zig").Attribute.init(allocator, "int", "id");
    try attr1.addKey(allocator, .primary_key);
    const attr2 = try @import("model.zig").Attribute.init(allocator, "string", "name");
    try diagram.addAttributes("ORDER", &.{ attr1, attr2 });

    const svg = try renderErToSVGString(allocator, &diagram);
    defer allocator.free(svg);

    try std.testing.expect(std.mem.indexOf(u8, svg, "ORDER") != null);
    try std.testing.expect(std.mem.indexOf(u8, svg, "int") != null);
    try std.testing.expect(std.mem.indexOf(u8, svg, "id") != null);
    try std.testing.expect(std.mem.indexOf(u8, svg, "PK") != null);
    try std.testing.expect(std.mem.indexOf(u8, svg, "name") != null);
}

test "er svg: renders relationship" {
    const allocator = std.testing.allocator;
    var diagram = ErDiagram.init(allocator);
    defer diagram.deinit();

    try diagram.addRelationship(
        "CUSTOMER",
        "ORDER",
        "places",
        er_model.RelSpec.init(.only_one, .zero_or_more, .non_identifying),
    );

    const svg = try renderErToSVGString(allocator, &diagram);
    defer allocator.free(svg);

    try std.testing.expect(std.mem.indexOf(u8, svg, "CUSTOMER") != null);
    try std.testing.expect(std.mem.indexOf(u8, svg, "ORDER") != null);
    try std.testing.expect(std.mem.indexOf(u8, svg, "places") != null);
    try std.testing.expect(std.mem.indexOf(u8, svg, "<line") != null);
}

test "er svg: renders with title" {
    const allocator = std.testing.allocator;
    var diagram = ErDiagram.init(allocator);
    defer diagram.deinit();

    try diagram.setTitle("My ER Diagram");
    _ = try diagram.addEntity("CUSTOMER", null);

    const svg = try renderErToSVGString(allocator, &diagram);
    defer allocator.free(svg);

    try std.testing.expect(std.mem.indexOf(u8, svg, "My ER Diagram") != null);
}

test "er svg: renders multiple relationships" {
    const allocator = std.testing.allocator;
    var diagram = ErDiagram.init(allocator);
    defer diagram.deinit();

    try diagram.addRelationship(
        "CUSTOMER",
        "ORDER",
        "places",
        er_model.RelSpec.init(.only_one, .zero_or_more, .identifying),
    );
    try diagram.addRelationship(
        "ORDER",
        "LINE_ITEM",
        "contains",
        er_model.RelSpec.init(.only_one, .one_or_more, .identifying),
    );

    const svg = try renderErToSVGString(allocator, &diagram);
    defer allocator.free(svg);

    try std.testing.expect(std.mem.indexOf(u8, svg, "CUSTOMER") != null);
    try std.testing.expect(std.mem.indexOf(u8, svg, "ORDER") != null);
    try std.testing.expect(std.mem.indexOf(u8, svg, "LINE_ITEM") != null);
    try std.testing.expect(std.mem.indexOf(u8, svg, "places") != null);
    try std.testing.expect(std.mem.indexOf(u8, svg, "contains") != null);
}

test "er svg: computeRectEdgeIntersection" {
    // Target to the right
    const p1 = computeRectEdgeIntersection(100, 100, 80, 40, 200, 100);
    try std.testing.expect(@abs(p1.x - 140.0) < 1.0);
    try std.testing.expect(@abs(p1.y - 100.0) < 1.0);

    // Target below
    const p2 = computeRectEdgeIntersection(100, 100, 80, 40, 100, 200);
    try std.testing.expect(@abs(p2.x - 100.0) < 1.0);
    try std.testing.expect(@abs(p2.y - 120.0) < 1.0);
}

test "er svg: write to file" {
    const allocator = std.testing.allocator;
    var diagram = ErDiagram.init(allocator);
    defer diagram.deinit();

    try diagram.setTitle("Test ER");
    try diagram.addRelationship(
        "CUSTOMER",
        "ORDER",
        "places",
        er_model.RelSpec.init(.only_one, .zero_or_more, .identifying),
    );

    try renderErToSVG(allocator, &diagram, "/tmp/merrow_er_test.svg");

    // Verify file was created
    const file = try std.fs.cwd().openFile("/tmp/merrow_er_test.svg", .{});
    file.close();
}

test "er svg: fixture diagrams render to svg" {
    const allocator = std.testing.allocator;
    const fixtures = [_]struct {
        path: []const u8,
        expected_text: []const u8,
    }{
        .{ .path = "test-diagrams/er_simple.mmd", .expected_text = "CUSTOMER" },
        .{ .path = "test-diagrams/er_simple_v2.mmd", .expected_text = "AUTHOR" },
        .{ .path = "test-diagrams/er_complex.mmd", .expected_text = "PRODUCT" },
        .{ .path = "test-diagrams/er_complex_v2.mmd", .expected_text = "HOSPITAL" },
    };

    for (fixtures) |fixture| {
        const source = try std.fs.cwd().readFileAlloc(allocator, fixture.path, 1024 * 1024);
        defer allocator.free(source);

        var diagram = try @import("parser.zig").parse(allocator, source);
        defer diagram.deinit();

        const svg = try renderErToSVGString(allocator, &diagram);
        defer allocator.free(svg);

        try std.testing.expect(svg.len > 0);
        try std.testing.expect(std.mem.indexOf(u8, svg, "<svg") != null);
        try std.testing.expect(std.mem.indexOf(u8, svg, fixture.expected_text) != null);
        try std.testing.expect(std.mem.indexOf(u8, svg, "<rect") != null);
    }
}
