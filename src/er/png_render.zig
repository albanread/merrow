//! ER (Entity-Relationship) diagram PNG renderer.
//!
//! Renders an `ErDiagram` to a PNG file using the Canvas rasteriser and
//! optional TrueType font for text labels.  The layout logic mirrors the
//! SVG renderer so that the two outputs look consistent.

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
const Canvas = @import("../render/canvas.zig").Canvas;
const Font = @import("../render/text.zig").Font;

// -----------------------------------------------------------------------
// Layout constants (matching SVG renderer)
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
const EDGE_STROKE_WIDTH: i32 = 2;
const LABEL_FONT_SIZE: f64 = 12.0;
const SCALE_FACTOR: f64 = 2.0;

// -----------------------------------------------------------------------
// Helper types
// -----------------------------------------------------------------------

const Position = struct { x: f64, y: f64 };

const EntityDimensions = struct {
    width: f64,
    height: f64,
    col_widths: [3]f64,
};

// -----------------------------------------------------------------------
// Public API
// -----------------------------------------------------------------------

/// Render an ER diagram to a PNG file.
pub fn renderErToPNG(
    allocator: Allocator,
    diagram: *const ErDiagram,
    output_path: []const u8,
    maybe_font: ?*Font,
) !void {
    const mutable_diagram = @constCast(diagram);
    const entity_count = mutable_diagram.entities.count();

    // ── Empty diagram ───────────────────────────────────────────
    if (entity_count == 0) {
        var canvas = try Canvas.initWithScale(allocator, 400, 200, SCALE_FACTOR);
        defer canvas.deinit();
        canvas.fill(255, 255, 255, 255);
        if (maybe_font) |font| {
            const msg = "(empty ER diagram)";
            const tw = font.measureText(msg, @floatCast(ENTITY_NAME_FONT_SIZE));
            font.drawText(&canvas, msg, @as(f32, @floatCast(200.0 - @as(f64, tw) / 2.0)), 90.0, @floatCast(ENTITY_NAME_FONT_SIZE), 128, 128, 128, 255) catch {};
        }
        try canvas.saveToPNG(output_path);
        return;
    }

    // ── Collect sorted entity names ─────────────────────────────
    const sorted_names = try diagram.sortedEntityNames();
    defer allocator.free(sorted_names);

    // ── Compute entity dimensions ───────────────────────────────
    var entity_widths = std.StringHashMap(f64).init(allocator);
    defer entity_widths.deinit();
    var entity_heights = std.StringHashMap(f64).init(allocator);
    defer entity_heights.deinit();
    var col_widths_map = std.StringHashMap([3]f64).init(allocator);
    defer col_widths_map.deinit();

    for (sorted_names) |name| {
        if (mutable_diagram.entities.getPtr(name)) |entity| {
            const dims = computeEntityDimensions(entity, maybe_font);
            try entity_widths.put(name, dims.width);
            try entity_heights.put(name, dims.height);
            try col_widths_map.put(name, dims.col_widths);
        }
    }

    // ── Layout entities ─────────────────────────────────────────
    var positions = std.StringHashMap(Position).init(allocator);
    defer positions.deinit();

    try layoutEntities(allocator, diagram, sorted_names, &entity_widths, &entity_heights, &positions);

    // ── Bounding box ────────────────────────────────────────────
    var min_x: f64 = std.math.inf(f64);
    var min_y: f64 = std.math.inf(f64);
    var max_x: f64 = -std.math.inf(f64);
    var max_y: f64 = -std.math.inf(f64);

    for (sorted_names) |name| {
        if (positions.get(name)) |pos| {
            const w = entity_widths.get(name) orelse ENTITY_MIN_WIDTH;
            const h = entity_heights.get(name) orelse HEADER_HEIGHT;
            if (pos.x < min_x) min_x = pos.x;
            if (pos.y < min_y) min_y = pos.y;
            if (pos.x + w > max_x) max_x = pos.x + w;
            if (pos.y + h > max_y) max_y = pos.y + h;
        }
    }

    const title_offset: f64 = if (diagram.title != null) 40.0 else 0.0;
    const canvas_w_f = @max((max_x - min_x) + MARGIN * 2, 200.0);
    const canvas_h_f = @max((max_y - min_y) + MARGIN * 2 + title_offset, 150.0);
    const offset_x = MARGIN - min_x;
    const offset_y = MARGIN - min_y + title_offset;

    const canvas_w: u32 = @intFromFloat(@ceil(canvas_w_f));
    const canvas_h: u32 = @intFromFloat(@ceil(canvas_h_f));

    var canvas = try Canvas.initWithScale(allocator, canvas_w, canvas_h, SCALE_FACTOR);
    defer canvas.deinit();

    // White background
    canvas.fill(255, 255, 255, 255);

    // ── Title ───────────────────────────────────────────────────
    if (diagram.title) |title| {
        if (maybe_font) |font| {
            const tw = font.measureText(title, @floatCast(TITLE_FONT_SIZE));
            const tx: f32 = @floatCast(canvas_w_f / 2.0 - @as(f64, tw) / 2.0);
            font.drawText(&canvas, title, tx, 22.0, @floatCast(TITLE_FONT_SIZE), er_model.entity_name_color[0], er_model.entity_name_color[1], er_model.entity_name_color[2], 255) catch {};
        }
    }

    // ── Relationships (behind entities) ─────────────────────────
    for (diagram.relationships.items) |rel| {
        const from_pos = positions.get(rel.entity_a) orelse continue;
        const to_pos = positions.get(rel.entity_b) orelse continue;
        const from_w = entity_widths.get(rel.entity_a) orelse ENTITY_MIN_WIDTH;
        const from_h = entity_heights.get(rel.entity_a) orelse HEADER_HEIGHT;
        const to_w = entity_widths.get(rel.entity_b) orelse ENTITY_MIN_WIDTH;
        const to_h = entity_heights.get(rel.entity_b) orelse HEADER_HEIGHT;

        renderRelationship(
            &canvas,
            maybe_font,
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

    // ── Entities ────────────────────────────────────────────────
    for (sorted_names) |name| {
        const pos = positions.get(name) orelse continue;
        const entity_ptr = mutable_diagram.entities.getPtr(name) orelse continue;
        const w = entity_widths.get(name) orelse ENTITY_MIN_WIDTH;
        const h = entity_heights.get(name) orelse HEADER_HEIGHT;
        const cols = col_widths_map.get(name) orelse [3]f64{ 65.0, 75.0, 47.0 };

        renderEntity(
            &canvas,
            maybe_font,
            entity_ptr,
            pos.x + offset_x,
            pos.y + offset_y,
            w,
            h,
            cols,
        );
    }

    try canvas.saveToPNG(output_path);
}

// -----------------------------------------------------------------------
// Dimension computation
// -----------------------------------------------------------------------

fn computeEntityDimensions(entity: *const Entity, maybe_font: ?*Font) EntityDimensions {
    const display_name = entity.displayName();
    const name_width = if (maybe_font) |font|
        @as(f64, font.measureText(display_name, @floatCast(ENTITY_NAME_FONT_SIZE))) + ENTITY_PADDING * 2
    else
        @as(f64, @floatFromInt(display_name.len)) * CHAR_WIDTH + ENTITY_PADDING * 2;

    if (entity.attributes.items.len == 0) {
        const w = @max(name_width, ENTITY_MIN_WIDTH);
        return .{
            .width = w,
            .height = HEADER_HEIGHT,
            .col_widths = .{ w / 3.0, w / 3.0, w / 3.0 },
        };
    }

    var type_max: f64 = 40.0;
    var name_max: f64 = 40.0;
    var key_max: f64 = 30.0;

    for (entity.attributes.items) |attr| {
        const tw = if (maybe_font) |font|
            @as(f64, font.measureText(attr.attr_type, @floatCast(ATTR_FONT_SIZE))) + ENTITY_PADDING * 2
        else
            @as(f64, @floatFromInt(attr.attr_type.len)) * ATTR_CHAR_WIDTH + ENTITY_PADDING * 2;
        if (tw > type_max) type_max = tw;

        const nw = if (maybe_font) |font|
            @as(f64, font.measureText(attr.name, @floatCast(ATTR_FONT_SIZE))) + ENTITY_PADDING * 2
        else
            @as(f64, @floatFromInt(attr.name.len)) * ATTR_CHAR_WIDTH + ENTITY_PADDING * 2;
        if (nw > name_max) name_max = nw;

        var key_len: usize = 0;
        for (attr.keys.items, 0..) |key, ki| {
            key_len += key.asStr().len;
            if (ki > 0) key_len += 1;
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
// Layout (identical logic to SVG renderer)
// -----------------------------------------------------------------------

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

    var connected_to = std.StringHashMap(std.ArrayListUnmanaged([]const u8)).init(allocator);
    defer {
        var iter = connected_to.iterator();
        while (iter.next()) |entry| {
            entry.value_ptr.deinit(allocator);
        }
        connected_to.deinit();
    }

    var in_rel = std.StringHashMap(bool).init(allocator);
    defer in_rel.deinit();

    for (diagram.relationships.items) |rel| {
        try in_rel.put(rel.entity_a, true);
        try in_rel.put(rel.entity_b, true);

        const entry_a = try connected_to.getOrPut(rel.entity_a);
        if (!entry_a.found_existing) {
            entry_a.value_ptr.* = .{};
        }
        try entry_a.value_ptr.append(allocator, rel.entity_b);
    }

    var layer_map = std.StringHashMap(usize).init(allocator);
    defer layer_map.deinit();

    var queue = std.ArrayListUnmanaged([]const u8){};
    defer queue.deinit(allocator);

    for (sorted_names) |name| {
        if (in_rel.contains(name) and !layer_map.contains(name)) {
            try layer_map.put(name, 0);
            try queue.append(allocator, name);

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

    const is_horizontal = (diagram.direction == .LR or diagram.direction == .RL);

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
    canvas: *Canvas,
    maybe_font: ?*Font,
    entity: *const Entity,
    x: f64,
    y: f64,
    width: f64,
    height: f64,
    col_widths: [3]f64,
) void {
    const display_name = entity.displayName();
    const num_attrs = entity.attributes.items.len;

    // Header background
    canvas.fillRect(x, y, width, @min(HEADER_HEIGHT, height), er_model.entity_header_fill[0], er_model.entity_header_fill[1], er_model.entity_header_fill[2], er_model.entity_header_fill[3]);

    // Outer border
    canvas.strokeRect(x, y, width, height, 2, er_model.entity_stroke[0], er_model.entity_stroke[1], er_model.entity_stroke[2], er_model.entity_stroke[3]);

    if (num_attrs == 0) {
        // Simple entity box — centered name
        if (maybe_font) |font| {
            const tw = font.measureText(display_name, @floatCast(ENTITY_NAME_FONT_SIZE));
            const tx: f32 = @floatCast(x + width / 2.0 - @as(f64, tw) / 2.0);
            const ty: f32 = @floatCast(y + height / 2.0);
            font.drawText(canvas, display_name, tx, ty, @floatCast(ENTITY_NAME_FONT_SIZE), er_model.entity_name_color[0], er_model.entity_name_color[1], er_model.entity_name_color[2], 255) catch {};
        }
        return;
    }

    // ── Header text ─────────────────────────────────────────────
    if (maybe_font) |font| {
        const tw = font.measureText(display_name, @floatCast(ENTITY_NAME_FONT_SIZE));
        const tx: f32 = @floatCast(x + width / 2.0 - @as(f64, tw) / 2.0);
        const ty: f32 = @floatCast(y + HEADER_HEIGHT / 2.0);
        font.drawText(canvas, display_name, tx, ty, @floatCast(ENTITY_NAME_FONT_SIZE), er_model.entity_name_color[0], er_model.entity_name_color[1], er_model.entity_name_color[2], 255) catch {};
    }

    // ── Horizontal divider under header ─────────────────────────
    const content_y = y + HEADER_HEIGHT;
    canvas.drawLine(x, content_y, x + width, content_y, 2, er_model.entity_stroke[0], er_model.entity_stroke[1], er_model.entity_stroke[2], er_model.entity_stroke[3]);

    // ── Vertical column dividers in attribute area ───────────────
    const type_col_end = x + col_widths[0];
    const name_col_end = type_col_end + col_widths[1];
    const divider_bottom = y + height;

    canvas.drawLine(type_col_end, content_y, type_col_end, divider_bottom, 1, er_model.entity_stroke[0], er_model.entity_stroke[1], er_model.entity_stroke[2], er_model.entity_stroke[3]);
    canvas.drawLine(name_col_end, content_y, name_col_end, divider_bottom, 1, er_model.entity_stroke[0], er_model.entity_stroke[1], er_model.entity_stroke[2], er_model.entity_stroke[3]);

    // ── Attribute rows ──────────────────────────────────────────
    for (entity.attributes.items, 0..) |attr, i| {
        const row_y = content_y + @as(f64, @floatFromInt(i)) * ATTR_ROW_HEIGHT;

        // Alternating row background
        const row_fill: [4]u8 = if (i % 2 == 0) er_model.entity_row_odd_fill else er_model.entity_row_even_fill;
        canvas.fillRect(x + 1, row_y + 1, width - 2, ATTR_ROW_HEIGHT - 1, row_fill[0], row_fill[1], row_fill[2], row_fill[3]);

        // Row separator line
        if (i > 0) {
            canvas.drawLine(x, row_y, x + width, row_y, 1, er_model.entity_stroke[0], er_model.entity_stroke[1], er_model.entity_stroke[2], 128);
        }

        // Text
        if (maybe_font) |font| {
            const text_y: f32 = @floatCast(row_y + ATTR_ROW_HEIGHT / 2.0);

            // Type column
            font.drawText(canvas, attr.attr_type, @floatCast(x + ENTITY_PADDING), text_y, @floatCast(ATTR_FONT_SIZE), er_model.attr_text_color[0], er_model.attr_text_color[1], er_model.attr_text_color[2], 255) catch {};

            // Name column
            font.drawText(canvas, attr.name, @floatCast(type_col_end + ENTITY_PADDING), text_y, @floatCast(ATTR_FONT_SIZE), er_model.attr_text_color[0], er_model.attr_text_color[1], er_model.attr_text_color[2], 255) catch {};

            // Keys column
            if (attr.keys.items.len > 0) {
                var key_buf: [64]u8 = undefined;
                var key_len: usize = 0;
                for (attr.keys.items, 0..) |key, ki| {
                    if (ki > 0) {
                        if (key_len < key_buf.len) {
                            key_buf[key_len] = ',';
                            key_len += 1;
                        }
                    }
                    const ks = key.asStr();
                    const copy_len = @min(ks.len, key_buf.len - key_len);
                    if (copy_len > 0) {
                        @memcpy(key_buf[key_len .. key_len + copy_len], ks[0..copy_len]);
                        key_len += copy_len;
                    }
                }
                if (key_len > 0) {
                    font.drawText(canvas, key_buf[0..key_len], @floatCast(name_col_end + ENTITY_PADDING), text_y, @floatCast(ATTR_FONT_SIZE), er_model.attr_text_color[0], er_model.attr_text_color[1], er_model.attr_text_color[2], 255) catch {};
                }
            }
        }
    }
}

// -----------------------------------------------------------------------
// Relationship rendering
// -----------------------------------------------------------------------

fn renderRelationship(
    canvas: *Canvas,
    maybe_font: ?*Font,
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
) void {
    const from_cx = from_x + from_w / 2.0;
    const from_cy = from_y + from_h / 2.0;
    const to_cx = to_x + to_w / 2.0;
    const to_cy = to_y + to_h / 2.0;

    const line_r = er_model.rel_line_color[0];
    const line_g = er_model.rel_line_color[1];
    const line_b = er_model.rel_line_color[2];

    if (is_self_ref) {
        const loop_offset: f64 = 40.0;
        const start_x = from_x + from_w;
        const start_y = from_cy - 10.0;
        const end_y = from_cy + 10.0;

        canvas.drawLine(start_x, start_y, start_x + loop_offset, start_y, EDGE_STROKE_WIDTH, line_r, line_g, line_b, 255);
        canvas.drawLine(start_x + loop_offset, start_y, start_x + loop_offset, end_y, EDGE_STROKE_WIDTH, line_r, line_g, line_b, 255);
        canvas.drawLine(start_x + loop_offset, end_y, start_x, end_y, EDGE_STROKE_WIDTH, line_r, line_g, line_b, 255);

        renderCardinalityMarker(canvas, start_x + 4.0, start_y, 1.0, 0.0, rel_spec.card_a);
        renderCardinalityMarker(canvas, start_x + 4.0, end_y, -1.0, 0.0, rel_spec.card_b);

        if (role.len > 0) {
            renderRoleLabel(canvas, maybe_font, start_x + loop_offset / 2.0, start_y - 12.0, role);
        }
        return;
    }

    const start = computeRectEdgeIntersection(from_cx, from_cy, from_w, from_h, to_cx, to_cy);
    const end = computeRectEdgeIntersection(to_cx, to_cy, to_w, to_h, from_cx, from_cy);

    const dx = end.x - start.x;
    const dy = end.y - start.y;
    const len = @sqrt(dx * dx + dy * dy);
    const ndx = if (len > 0.001) dx / len else 0.0;
    const ndy = if (len > 0.001) dy / len else 1.0;

    // Draw relationship line
    if (rel_spec.rel_type == .non_identifying) {
        canvas.drawDashedLine(start.x, start.y, end.x, end.y, EDGE_STROKE_WIDTH, 6.0, 3.0, line_r, line_g, line_b, 255);
    } else {
        canvas.drawLine(start.x, start.y, end.x, end.y, EDGE_STROKE_WIDTH, line_r, line_g, line_b, 255);
    }

    // Cardinality markers
    const marker_offset: f64 = 18.0;
    renderCardinalityMarker(
        canvas,
        start.x + ndx * marker_offset,
        start.y + ndy * marker_offset,
        ndx,
        ndy,
        rel_spec.card_a,
    );
    renderCardinalityMarker(
        canvas,
        end.x - ndx * marker_offset,
        end.y - ndy * marker_offset,
        -ndx,
        -ndy,
        rel_spec.card_b,
    );

    // Role label at midpoint
    if (role.len > 0) {
        const mid_x = (start.x + end.x) / 2.0;
        const mid_y = (start.y + end.y) / 2.0;
        const perp_x = -ndy * 14.0;
        const perp_y = ndx * 14.0;
        renderRoleLabel(canvas, maybe_font, mid_x + perp_x, mid_y + perp_y, role);
    }
}

// -----------------------------------------------------------------------
// Rect-edge intersection (same as SVG renderer)
// -----------------------------------------------------------------------

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

    var t: f64 = std.math.inf(f64);

    if (dx > 0.001) {
        const t_right = half_w / dx;
        const y_at = dy * t_right;
        if (@abs(y_at) <= half_h and t_right < t) t = t_right;
    }
    if (dx < -0.001) {
        const t_left = -half_w / dx;
        const y_at = dy * t_left;
        if (@abs(y_at) <= half_h and t_left < t) t = t_left;
    }
    if (dy > 0.001) {
        const t_bottom = half_h / dy;
        const x_at = dx * t_bottom;
        if (@abs(x_at) <= half_w and t_bottom < t) t = t_bottom;
    }
    if (dy < -0.001) {
        const t_top = -half_h / dy;
        const x_at = dx * t_top;
        if (@abs(x_at) <= half_w and t_top < t) t = t_top;
    }

    if (t == std.math.inf(f64)) {
        return .{ .x = cx, .y = cy };
    }

    return .{ .x = cx + dx * t, .y = cy + dy * t };
}

// -----------------------------------------------------------------------
// Cardinality markers
// -----------------------------------------------------------------------

fn renderCardinalityMarker(
    canvas: *Canvas,
    x: f64,
    y: f64,
    dx: f64,
    dy: f64,
    card: Cardinality,
) void {
    const px = -dy;
    const py = dx;
    const mark_size: f64 = 8.0;
    const line_size: f64 = 10.0;

    const r = er_model.rel_line_color[0];
    const g = er_model.rel_line_color[1];
    const b = er_model.rel_line_color[2];

    switch (card) {
        .only_one => {
            // Two parallel lines perpendicular to the relationship line
            canvas.drawLine(
                x + px * mark_size,
                y + py * mark_size,
                x - px * mark_size,
                y - py * mark_size,
                EDGE_STROKE_WIDTH,
                r,
                g,
                b,
                255,
            );
            canvas.drawLine(
                x + dx * 5.0 + px * mark_size,
                y + dy * 5.0 + py * mark_size,
                x + dx * 5.0 - px * mark_size,
                y + dy * 5.0 - py * mark_size,
                EDGE_STROKE_WIDTH,
                r,
                g,
                b,
                255,
            );
        },
        .zero_or_one => {
            // One line + circle
            canvas.drawLine(
                x + px * mark_size,
                y + py * mark_size,
                x - px * mark_size,
                y - py * mark_size,
                EDGE_STROKE_WIDTH,
                r,
                g,
                b,
                255,
            );
            // Circle (filled white, then stroked)
            const circle_x = x + dx * line_size;
            const circle_y = y + dy * line_size;
            canvas.fillEllipse(circle_x, circle_y, 5.0, 5.0, 255, 255, 255, 255);
            canvas.strokeEllipse(circle_x, circle_y, 5.0, 5.0, EDGE_STROKE_WIDTH, r, g, b, 255);
        },
        .one_or_more => {
            // One line + crow's foot
            canvas.drawLine(
                x + px * mark_size,
                y + py * mark_size,
                x - px * mark_size,
                y - py * mark_size,
                EDGE_STROKE_WIDTH,
                r,
                g,
                b,
                255,
            );
            const foot_x = x + dx * line_size;
            const foot_y = y + dy * line_size;
            canvas.drawLine(foot_x, foot_y, x + px * mark_size, y + py * mark_size, EDGE_STROKE_WIDTH, r, g, b, 255);
            canvas.drawLine(foot_x, foot_y, x - px * mark_size, y - py * mark_size, EDGE_STROKE_WIDTH, r, g, b, 255);
        },
        .zero_or_more => {
            // Circle + crow's foot
            canvas.fillEllipse(x, y, 5.0, 5.0, 255, 255, 255, 255);
            canvas.strokeEllipse(x, y, 5.0, 5.0, EDGE_STROKE_WIDTH, r, g, b, 255);
            const foot_x = x + dx * line_size;
            const foot_y = y + dy * line_size;
            canvas.drawLine(foot_x, foot_y, x + px * mark_size, y + py * mark_size, EDGE_STROKE_WIDTH, r, g, b, 255);
            canvas.drawLine(foot_x, foot_y, x - px * mark_size, y - py * mark_size, EDGE_STROKE_WIDTH, r, g, b, 255);
        },
    }
}

// -----------------------------------------------------------------------
// Role label
// -----------------------------------------------------------------------

fn renderRoleLabel(
    canvas: *Canvas,
    maybe_font: ?*Font,
    x: f64,
    y: f64,
    role: []const u8,
) void {
    if (role.len == 0) return;

    // Background rect for readability
    const label_w = @as(f64, @floatFromInt(role.len)) * 7.0 + 12.0;
    const label_h: f64 = 20.0;
    canvas.fillRect(
        x - label_w / 2.0,
        y - label_h / 2.0,
        label_w,
        label_h,
        er_model.label_bg_color[0],
        er_model.label_bg_color[1],
        er_model.label_bg_color[2],
        er_model.label_bg_color[3],
    );

    if (maybe_font) |font| {
        const tw = font.measureText(role, @floatCast(LABEL_FONT_SIZE));
        const tx: f32 = @floatCast(x - @as(f64, tw) / 2.0);
        const ty: f32 = @floatCast(y);
        font.drawText(canvas, role, tx, ty, @floatCast(LABEL_FONT_SIZE), er_model.rel_label_color[0], er_model.rel_label_color[1], er_model.rel_label_color[2], 255) catch {};
    }
}

// -----------------------------------------------------------------------
// Tests
// -----------------------------------------------------------------------

test "er png: renders without crash (no font)" {
    const allocator = std.testing.allocator;
    var diagram = ErDiagram.init(allocator);
    defer diagram.deinit();

    _ = try diagram.addEntity("CUSTOMER", null);
    _ = try diagram.addEntity("ORDER", null);

    try diagram.addRelationship("CUSTOMER", "ORDER", "places", .{
        .card_a = .only_one,
        .card_b = .zero_or_more,
        .rel_type = .identifying,
    });

    try renderErToPNG(allocator, &diagram, "/tmp/merrow_er_png_test.png", null);

    const stat = try std.fs.cwd().statFile("/tmp/merrow_er_png_test.png");
    try std.testing.expect(stat.size > 0);
}

test "er png: empty diagram renders without crash" {
    const allocator = std.testing.allocator;
    var diagram = ErDiagram.init(allocator);
    defer diagram.deinit();

    try renderErToPNG(allocator, &diagram, "/tmp/merrow_er_png_empty_test.png", null);

    const stat = try std.fs.cwd().statFile("/tmp/merrow_er_png_empty_test.png");
    try std.testing.expect(stat.size > 0);
}

test "er png: entity with attributes renders" {
    const allocator = std.testing.allocator;
    var diagram = ErDiagram.init(allocator);
    defer diagram.deinit();

    const entity = try diagram.addEntity("PRODUCT", null);
    var attr1 = try Attribute.init(allocator, "int", "id");
    try attr1.addKey(allocator, .primary_key);
    try entity.addAttribute(allocator, attr1);
    const attr2 = try Attribute.init(allocator, "string", "name");
    try entity.addAttribute(allocator, attr2);

    try renderErToPNG(allocator, &diagram, "/tmp/merrow_er_png_attrs_test.png", null);

    const stat = try std.fs.cwd().statFile("/tmp/merrow_er_png_attrs_test.png");
    try std.testing.expect(stat.size > 0);
}

test "er png: self-referencing relationship renders" {
    const allocator = std.testing.allocator;
    var diagram = ErDiagram.init(allocator);
    defer diagram.deinit();

    _ = try diagram.addEntity("CATEGORY", null);
    try diagram.addRelationship("CATEGORY", "CATEGORY", "parent of", .{
        .card_a = .only_one,
        .card_b = .zero_or_more,
        .rel_type = .non_identifying,
    });

    try renderErToPNG(allocator, &diagram, "/tmp/merrow_er_png_selfref_test.png", null);

    const stat = try std.fs.cwd().statFile("/tmp/merrow_er_png_selfref_test.png");
    try std.testing.expect(stat.size > 0);
}

test "er png: multiple entities and relationships" {
    const allocator = std.testing.allocator;
    var diagram = ErDiagram.init(allocator);
    defer diagram.deinit();

    _ = try diagram.addEntity("CUSTOMER", null);
    _ = try diagram.addEntity("ORDER", null);
    _ = try diagram.addEntity("PRODUCT", null);

    try diagram.addRelationship("CUSTOMER", "ORDER", "places", .{
        .card_a = .only_one,
        .card_b = .zero_or_more,
        .rel_type = .identifying,
    });
    try diagram.addRelationship("ORDER", "PRODUCT", "contains", .{
        .card_a = .only_one,
        .card_b = .one_or_more,
        .rel_type = .identifying,
    });

    try renderErToPNG(allocator, &diagram, "/tmp/merrow_er_png_multi_test.png", null);

    const stat = try std.fs.cwd().statFile("/tmp/merrow_er_png_multi_test.png");
    try std.testing.expect(stat.size > 0);
}

test "er png: with title" {
    const allocator = std.testing.allocator;
    var diagram = ErDiagram.init(allocator);
    defer diagram.deinit();

    try diagram.setTitle("Test ER Diagram");
    _ = try diagram.addEntity("ENTITY_A", null);

    try renderErToPNG(allocator, &diagram, "/tmp/merrow_er_png_title_test.png", null);

    const stat = try std.fs.cwd().statFile("/tmp/merrow_er_png_title_test.png");
    try std.testing.expect(stat.size > 0);
}
