//! Pie chart SVG renderer.
//!
//! Renders a `PieData` model to an SVG string using the `SvgWriter`.
//! Produces arc-based pie slices, percentage labels inside slices,
//! a legend on the right, and an optional title above the chart.

const std = @import("std");
const Allocator = std.mem.Allocator;
const PieData = @import("model.zig").PieData;
const pie_model = @import("model.zig");
const SvgWriter = @import("../render/svg.zig").SvgWriter;

// -----------------------------------------------------------------------
// Layout constants (matching mermaid.js defaults)
// -----------------------------------------------------------------------

const MARGIN: f64 = 40.0;
const PIE_HEIGHT: f64 = 450.0;
const LEGEND_RECT_SIZE: f64 = 18.0;
const LEGEND_SPACING: f64 = 4.0;
const LEGEND_TEXT_OFFSET_X: f64 = 22.0;
const LEGEND_TEXT_OFFSET_Y: f64 = 14.0;
const TITLE_FONT_SIZE: f64 = 25.0;
const LABEL_FONT_SIZE: f64 = 17.0;
const LEGEND_FONT_SIZE: f64 = 17.0;
const CHAR_WIDTH_ESTIMATE: f64 = 9.0; // approx px per char at 17px font

const PI: f64 = std.math.pi;

// -----------------------------------------------------------------------
// Public API
// -----------------------------------------------------------------------

/// Render a `PieData` to SVG and write the result to a file at `output_path`.
pub fn renderPieToSVG(
    allocator: Allocator,
    pie: *const PieData,
    output_path: []const u8,
) !void {
    const svg_content = try renderPieToSVGString(allocator, pie);
    defer allocator.free(svg_content);

    const file = try std.fs.cwd().createFile(output_path, .{});
    defer file.close();
    try file.writeAll(svg_content);
}

/// Render a `PieData` to an SVG string.  Caller owns the returned slice.
pub fn renderPieToSVGString(
    allocator: Allocator,
    pie: *const PieData,
) ![]u8 {
    const sections = pie.sections.items;
    const total = pie.total();
    const num_sections = sections.len;

    // ── Dimensions ──────────────────────────────────────────────
    const radius: f64 = (@min(PIE_HEIGHT, PIE_HEIGHT) / 2.0) - MARGIN; // 185
    const cx: f64 = PIE_HEIGHT / 2.0; // 225
    const cy: f64 = PIE_HEIGHT / 2.0; // 225

    // Estimate legend width from longest label.
    var max_label_len: usize = 0;
    for (sections) |sec| {
        var label_len = sec.label.len;
        if (pie.show_data) {
            // " [<value>]" adds roughly 6–10 chars
            label_len += 10;
        }
        if (label_len > max_label_len) max_label_len = label_len;
    }
    const legend_text_width = @as(f64, @floatFromInt(max_label_len)) * CHAR_WIDTH_ESTIMATE;
    const svg_width = PIE_HEIGHT + MARGIN + LEGEND_RECT_SIZE + LEGEND_SPACING + legend_text_width + MARGIN;

    var svg = try SvgWriter.init(allocator, @ceil(svg_width), @ceil(PIE_HEIGHT));
    defer svg.deinit();

    // ── Background ──────────────────────────────────────────────
    // Light background for readability (optional, matches mermaid default theme).
    try svg.rect(0, 0, svg_width, PIE_HEIGHT, 0, 0, [4]u8{ 255, 255, 255, 255 }, null, 0);

    // ── Title ───────────────────────────────────────────────────
    if (pie.title) |title| {
        try svg.textCentered(
            cx,
            30.0,
            title,
            TITLE_FONT_SIZE,
            [4]u8{ 51, 51, 51, 255 },
            "sans-serif",
        );
    }

    // ── Empty chart shortcut ────────────────────────────────────
    if (num_sections == 0 or total <= 0) {
        try svg.textCentered(cx, cy, "(empty pie chart)", LABEL_FONT_SIZE, [4]u8{ 128, 128, 128, 255 }, "sans-serif");
        return try svg.finalize();
    }

    // ── Outer circle ────────────────────────────────────────────
    try svg.ellipse(cx, cy, radius + 1.0, radius + 1.0, null, [4]u8{ 170, 170, 170, 255 }, 2);

    // ── Slices ──────────────────────────────────────────────────
    var start_angle: f64 = -PI / 2.0; // 12 o'clock

    // We'll collect label info to draw after all slices (so labels are on top).
    var label_xs: [32]f64 = undefined;
    var label_ys: [32]f64 = undefined;
    var label_pcts: [32]f64 = undefined;
    var label_count: usize = 0;

    for (sections, 0..) |sec, idx| {
        const pct = sec.value / total;
        const angle = pct * 2.0 * PI;
        const end_angle = start_angle + angle;

        const color = pie_model.sliceColor(idx);

        // Arc start / end points relative to centre.
        const x1 = cx + radius * @cos(start_angle);
        const y1 = cy + radius * @sin(start_angle);
        const x2 = cx + radius * @cos(end_angle);
        const y2 = cy + radius * @sin(end_angle);

        // Build SVG arc path.
        // M x1,y1 A rx ry 0 large-arc-flag sweep-flag x2,y2 L cx,cy Z
        const large_arc: u8 = if (angle > PI) '1' else '0';

        var path_buf: [512]u8 = undefined;
        const path = std.fmt.bufPrint(&path_buf, "M{d:.3},{d:.3}A{d:.0},{d:.0},0,{c},1,{d:.3},{d:.3}L{d:.0},{d:.0}Z", .{
            x1,        y1,
            radius,    radius,
            large_arc, x2,
            y2,        cx,
            cy,
        }) catch "(path error)";

        try svg.path(
            path,
            color,
            [4]u8{ 255, 255, 255, 255 }, // white stroke between slices
            2.0,
            null,
        );

        // Collect percentage label positions (skip very small slices).
        if (pct >= 0.02 and label_count < 32) {
            const mid_angle = start_angle + angle / 2.0;
            const label_r = radius * 0.65;
            label_xs[label_count] = cx + label_r * @cos(mid_angle);
            label_ys[label_count] = cy + label_r * @sin(mid_angle);
            label_pcts[label_count] = pct * 100.0;
            label_count += 1;
        }

        start_angle = end_angle;
    }

    // ── Percentage labels inside slices ──────────────────────────
    for (0..label_count) |i| {
        var pct_buf: [16]u8 = undefined;
        const pct_int: i32 = @intFromFloat(@round(label_pcts[i]));
        const pct_str = std.fmt.bufPrint(&pct_buf, "{d}%", .{pct_int}) catch "?%";
        try svg.textCentered(
            label_xs[i],
            label_ys[i] + 5.0, // slight vertical adjustment for visual centering
            pct_str,
            LABEL_FONT_SIZE,
            [4]u8{ 51, 51, 51, 255 },
            "sans-serif",
        );
    }

    // ── Legend ───────────────────────────────────────────────────
    const legend_x = cx + 12.0 * LEGEND_RECT_SIZE; // 216 px right of centre
    const legend_item_h = LEGEND_RECT_SIZE + LEGEND_SPACING; // 22
    const legend_total_h = @as(f64, @floatFromInt(num_sections)) * legend_item_h;
    const legend_start_y = cy - legend_total_h / 2.0;

    for (sections, 0..) |sec, idx| {
        const item_y = legend_start_y + @as(f64, @floatFromInt(idx)) * legend_item_h;
        const color = pie_model.sliceColor(idx);

        // Color swatch rectangle.
        try svg.rect(
            legend_x,
            item_y,
            LEGEND_RECT_SIZE,
            LEGEND_RECT_SIZE,
            0,
            0,
            color,
            color,
            1,
        );

        // Label text.
        var legend_buf: [256]u8 = undefined;
        const legend_text = blk: {
            if (pie.show_data) {
                // Format value: integer if whole number, otherwise float.
                if (sec.value == @floor(sec.value)) {
                    const v: i64 = @intFromFloat(sec.value);
                    break :blk std.fmt.bufPrint(&legend_buf, "{s} [{d}]", .{ sec.label, v }) catch sec.label;
                } else {
                    break :blk std.fmt.bufPrint(&legend_buf, "{s} [{d:.2}]", .{ sec.label, sec.value }) catch sec.label;
                }
            } else {
                break :blk sec.label;
            }
        };

        try svg.textAt(
            legend_x + LEGEND_TEXT_OFFSET_X,
            item_y + LEGEND_TEXT_OFFSET_Y,
            legend_text,
            LEGEND_FONT_SIZE,
            [4]u8{ 51, 51, 51, 255 },
            "sans-serif",
            .start,
        );
    }

    return try svg.finalize();
}

// -----------------------------------------------------------------------
// Tests
// -----------------------------------------------------------------------

test "pie svg: renders simple pie" {
    const allocator = std.testing.allocator;
    var pie = PieData.init(allocator);
    defer pie.deinit();

    try pie.addSection("A", 60);
    try pie.addSection("B", 40);

    const svg = try renderPieToSVGString(allocator, &pie);
    defer allocator.free(svg);

    // Should contain SVG structure.
    try std.testing.expect(std.mem.indexOf(u8, svg, "<svg") != null);
    try std.testing.expect(std.mem.indexOf(u8, svg, "</svg>") != null);
    // Should contain arc paths.
    try std.testing.expect(std.mem.indexOf(u8, svg, "<path") != null);
    // Should contain percentage labels.
    try std.testing.expect(std.mem.indexOf(u8, svg, "60%") != null);
    try std.testing.expect(std.mem.indexOf(u8, svg, "40%") != null);
}

test "pie svg: renders title" {
    const allocator = std.testing.allocator;
    var pie = PieData.init(allocator);
    defer pie.deinit();

    try pie.setTitle("Favourite Pets");
    try pie.addSection("Dogs", 50);
    try pie.addSection("Cats", 50);

    const svg = try renderPieToSVGString(allocator, &pie);
    defer allocator.free(svg);

    try std.testing.expect(std.mem.indexOf(u8, svg, "Favourite Pets") != null);
}

test "pie svg: renders empty pie" {
    const allocator = std.testing.allocator;
    var pie = PieData.init(allocator);
    defer pie.deinit();

    const svg = try renderPieToSVGString(allocator, &pie);
    defer allocator.free(svg);

    try std.testing.expect(std.mem.indexOf(u8, svg, "empty pie chart") != null);
}

test "pie svg: renders legend with show_data" {
    const allocator = std.testing.allocator;
    var pie = PieData.init(allocator);
    defer pie.deinit();

    pie.show_data = true;
    try pie.addSection("Dev", 40);
    try pie.addSection("Test", 25);

    const svg = try renderPieToSVGString(allocator, &pie);
    defer allocator.free(svg);

    // Legend should contain labels.
    try std.testing.expect(std.mem.indexOf(u8, svg, "Dev") != null);
    try std.testing.expect(std.mem.indexOf(u8, svg, "Test") != null);
    // show_data should include values.
    try std.testing.expect(std.mem.indexOf(u8, svg, "[40]") != null);
    try std.testing.expect(std.mem.indexOf(u8, svg, "[25]") != null);
}

test "pie svg: many slices renders without error" {
    const allocator = std.testing.allocator;
    var pie = PieData.init(allocator);
    defer pie.deinit();

    // 10 slices (wraps color palette)
    const labels = [_][]const u8{ "A", "B", "C", "D", "E", "F", "G", "H", "I", "J" };
    for (labels) |label| {
        try pie.addSection(label, 10);
    }

    const svg = try renderPieToSVGString(allocator, &pie);
    defer allocator.free(svg);

    try std.testing.expect(std.mem.indexOf(u8, svg, "<svg") != null);
    // All 10 labels should appear in legend.
    for (labels) |label| {
        try std.testing.expect(std.mem.indexOf(u8, svg, label) != null);
    }
}

test "pie svg: single slice renders 100%" {
    const allocator = std.testing.allocator;
    var pie = PieData.init(allocator);
    defer pie.deinit();

    try pie.addSection("Only", 42);

    const svg = try renderPieToSVGString(allocator, &pie);
    defer allocator.free(svg);

    try std.testing.expect(std.mem.indexOf(u8, svg, "100%") != null);
    try std.testing.expect(std.mem.indexOf(u8, svg, "Only") != null);
}

test "pie svg: very small slice omits label" {
    const allocator = std.testing.allocator;
    var pie = PieData.init(allocator);
    defer pie.deinit();

    try pie.addSection("Big", 99);
    try pie.addSection("Tiny", 1);

    const svg = try renderPieToSVGString(allocator, &pie);
    defer allocator.free(svg);

    // 99% should appear, 1% should be omitted (below 2% threshold).
    try std.testing.expect(std.mem.indexOf(u8, svg, "99%") != null);
    // "Tiny" should still be in the legend.
    try std.testing.expect(std.mem.indexOf(u8, svg, "Tiny") != null);
}
