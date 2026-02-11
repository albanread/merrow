//! Pie chart PNG renderer.
//!
//! Renders a `PieData` model to a PNG file using the Canvas rasteriser.
//! Produces filled arc slices (via angle-based scanline fill), percentage
//! labels inside slices, a legend on the right, and an optional title.

const std = @import("std");
const Allocator = std.mem.Allocator;
const PieData = @import("model.zig").PieData;
const pie_model = @import("model.zig");
const Canvas = @import("../render/canvas.zig").Canvas;
const Font = @import("../render/text.zig").Font;

// -----------------------------------------------------------------------
// Layout constants (matching mermaid.js / SVG renderer)
// -----------------------------------------------------------------------

const MARGIN: f64 = 40.0;
const PIE_HEIGHT: f64 = 450.0;
const LEGEND_RECT_SIZE: f64 = 18.0;
const LEGEND_SPACING: f64 = 4.0;
const LEGEND_TEXT_OFFSET_X: f64 = 24.0;
const LEGEND_TEXT_OFFSET_Y: f64 = 14.0;
const TITLE_FONT_SIZE: f64 = 22.0;
const LABEL_FONT_SIZE: f64 = 15.0;
const LEGEND_FONT_SIZE: f64 = 14.0;
const CHAR_WIDTH_ESTIMATE: f64 = 8.0;
const SCALE_FACTOR: f64 = 2.0;

const PI: f64 = std.math.pi;
const TWO_PI: f64 = 2.0 * PI;

// -----------------------------------------------------------------------
// Public API
// -----------------------------------------------------------------------

/// Render a `PieData` to a PNG file at `output_path`.
/// If `maybe_font` is provided, text labels are rendered with the font;
/// otherwise labels are omitted.
pub fn renderPieToPNG(
    allocator: Allocator,
    pie: *const PieData,
    output_path: []const u8,
    maybe_font: ?*Font,
) !void {
    const sections = pie.sections.items;
    const total = pie.total();
    const num_sections = sections.len;

    // ── Dimensions (logical, before scaling) ─────────────────────
    const radius: f64 = (PIE_HEIGHT / 2.0) - MARGIN; // 185
    const cx: f64 = PIE_HEIGHT / 2.0; // 225
    const cy: f64 = PIE_HEIGHT / 2.0; // 225

    // Estimate legend width.
    var max_label_len: usize = 0;
    for (sections) |sec| {
        var label_len = sec.label.len;
        if (pie.show_data) label_len += 10;
        if (label_len > max_label_len) max_label_len = label_len;
    }
    const legend_text_width = @as(f64, @floatFromInt(max_label_len)) * CHAR_WIDTH_ESTIMATE;
    const canvas_width_f = PIE_HEIGHT + MARGIN + LEGEND_RECT_SIZE + LEGEND_SPACING + legend_text_width + MARGIN;
    const canvas_w: u32 = @intFromFloat(@ceil(canvas_width_f));
    const canvas_h: u32 = @intFromFloat(@ceil(PIE_HEIGHT));

    var canvas = try Canvas.initWithScale(allocator, canvas_w, canvas_h, SCALE_FACTOR);
    defer canvas.deinit();

    // White background.
    canvas.fill(255, 255, 255, 255);

    // ── Title ───────────────────────────────────────────────────
    if (pie.title) |title| {
        if (maybe_font) |font| {
            const title_w = font.measureText(title, @floatCast(TITLE_FONT_SIZE));
            const tx: f32 = @floatCast(cx - @as(f64, title_w) / 2.0);
            font.drawText(&canvas, title, tx, 10.0, @as(f32, @floatCast(TITLE_FONT_SIZE)), 51, 51, 51, 255) catch {};
        }
    }

    // ── Empty chart shortcut ────────────────────────────────────
    if (num_sections == 0 or total <= 0) {
        if (maybe_font) |font| {
            const msg = "(empty pie chart)";
            const mw = font.measureText(msg, @floatCast(LABEL_FONT_SIZE));
            const mx: f32 = @floatCast(cx - @as(f64, mw) / 2.0);
            const my: f32 = @floatCast(cy - 8.0);
            font.drawText(&canvas, msg, mx, my, @as(f32, @floatCast(LABEL_FONT_SIZE)), 128, 128, 128, 255) catch {};
        }
        try canvas.saveToPNG(output_path);
        return;
    }

    // ── Draw pie slices (scanline fill by angle) ────────────────
    // Pre-compute cumulative angles for each section.
    var cum_angles: [64]f64 = undefined;
    const max_slices = @min(num_sections, 64);
    {
        var running: f64 = 0;
        for (0..max_slices) |i| {
            running += (sections[i].value / total) * TWO_PI;
            cum_angles[i] = running;
        }
    }

    // Fill the pie circle pixel-by-pixel using angle lookup.
    // We work in scaled pixel coordinates for accuracy.
    const scx = cx * SCALE_FACTOR;
    const scy = cy * SCALE_FACTOR;
    const sr = radius * SCALE_FACTOR;
    const sr2 = sr * sr;

    const iy_start: i32 = @intFromFloat(@floor(scy - sr));
    const iy_end: i32 = @intFromFloat(@ceil(scy + sr));
    var iy: i32 = iy_start;
    while (iy <= iy_end) : (iy += 1) {
        const dy = @as(f64, @floatFromInt(iy)) + 0.5 - scy;
        // Horizontal half-width at this scanline from circle equation.
        const dy2 = dy * dy;
        if (dy2 > sr2) continue;
        const half_w = @sqrt(sr2 - dy2);
        const ix_start: i32 = @intFromFloat(@floor(scx - half_w));
        const ix_end: i32 = @intFromFloat(@ceil(scx + half_w));
        var ix: i32 = ix_start;
        while (ix <= ix_end) : (ix += 1) {
            const dx = @as(f64, @floatFromInt(ix)) + 0.5 - scx;
            if (dx * dx + dy2 > sr2) continue;

            // Compute angle from centre, starting at 12-o'clock (-PI/2).
            var angle = std.math.atan2(dy, dx) + PI / 2.0;
            if (angle < 0) angle += TWO_PI;

            // Find which slice this angle belongs to.
            var slice_idx: usize = 0;
            for (0..max_slices) |s| {
                if (angle <= cum_angles[s]) {
                    slice_idx = s;
                    break;
                }
                slice_idx = s;
            }

            const color = pie_model.sliceColor(slice_idx);
            canvas.setPixel(ix, iy, color[0], color[1], color[2], color[3]);
        }
    }

    // ── Slice border lines (from centre to each slice boundary) ─
    {
        for (0..max_slices) |s| {
            const a = cum_angles[s];
            // Convert back to standard angle for cos/sin (subtract PI/2 offset).
            const real_angle = a - PI / 2.0;
            const ex = cx + radius * @cos(real_angle);
            const ey = cy + radius * @sin(real_angle);
            canvas.drawLine(cx, cy, ex, ey, 2, 255, 255, 255, 255);
        }
    }

    // ── Outer circle stroke ─────────────────────────────────────
    canvas.strokeEllipse(cx, cy, radius, radius, 2, 170, 170, 170, 255);

    // ── Percentage labels inside slices ──────────────────────────
    if (maybe_font) |font| {
        var prev_cum: f64 = 0;
        for (0..max_slices) |i| {
            const pct = (sections[i].value / total) * 100.0;
            if (pct < 2.0) {
                prev_cum = cum_angles[i];
                continue; // skip tiny slices
            }

            // Mid-angle of this slice (in our 12-o'clock-is-zero system).
            const mid_a = (prev_cum + cum_angles[i]) / 2.0;
            const real_mid = mid_a - PI / 2.0;
            const label_r = radius * 0.6;
            const lx = cx + label_r * @cos(real_mid);
            const ly = cy + label_r * @sin(real_mid);

            var pct_buf: [16]u8 = undefined;
            const pct_int: i32 = @intFromFloat(@round(pct));
            const pct_str = std.fmt.bufPrint(&pct_buf, "{d}%", .{pct_int}) catch "?%";
            const tw = font.measureText(pct_str, @floatCast(LABEL_FONT_SIZE));
            const draw_x: f32 = @floatCast(lx - @as(f64, tw) / 2.0);
            const draw_y: f32 = @floatCast(ly - 6.0);
            font.drawText(&canvas, pct_str, draw_x, draw_y, @as(f32, @floatCast(LABEL_FONT_SIZE)), 51, 51, 51, 255) catch {};

            prev_cum = cum_angles[i];
        }
    }

    // ── Legend ───────────────────────────────────────────────────
    const legend_x = cx + 12.0 * LEGEND_RECT_SIZE;
    const legend_item_h = LEGEND_RECT_SIZE + LEGEND_SPACING;
    const legend_total_h = @as(f64, @floatFromInt(num_sections)) * legend_item_h;
    const legend_start_y = cy - legend_total_h / 2.0;

    for (sections, 0..) |sec, idx| {
        const item_y = legend_start_y + @as(f64, @floatFromInt(idx)) * legend_item_h;
        const color = pie_model.sliceColor(idx);

        // Color swatch.
        canvas.fillRect(
            legend_x,
            item_y,
            LEGEND_RECT_SIZE,
            LEGEND_RECT_SIZE,
            color[0],
            color[1],
            color[2],
            color[3],
        );

        // Label text.
        if (maybe_font) |font| {
            var legend_buf: [256]u8 = undefined;
            const legend_text = blk: {
                if (pie.show_data) {
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

            const ltx: f32 = @floatCast(legend_x + LEGEND_TEXT_OFFSET_X);
            const lty: f32 = @floatCast(item_y + LEGEND_TEXT_OFFSET_Y - 10.0);
            font.drawText(
                &canvas,
                legend_text,
                ltx,
                lty,
                @as(f32, @floatCast(LEGEND_FONT_SIZE)),
                51,
                51,
                51,
                255,
            ) catch {};
        }
    }

    try canvas.saveToPNG(output_path);
}

// -----------------------------------------------------------------------
// Tests
// -----------------------------------------------------------------------

test "pie png: renders without crash (no font)" {
    const allocator = std.testing.allocator;
    var pie = PieData.init(allocator);
    defer pie.deinit();

    try pie.addSection("A", 60);
    try pie.addSection("B", 40);

    try renderPieToPNG(allocator, &pie, "/tmp/merrow_pie_test.png", null);

    // Verify the file was created.
    const stat = try std.fs.cwd().statFile("/tmp/merrow_pie_test.png");
    try std.testing.expect(stat.size > 0);
}

test "pie png: empty pie renders without crash" {
    const allocator = std.testing.allocator;
    var pie = PieData.init(allocator);
    defer pie.deinit();

    try renderPieToPNG(allocator, &pie, "/tmp/merrow_pie_empty_test.png", null);

    const stat = try std.fs.cwd().statFile("/tmp/merrow_pie_empty_test.png");
    try std.testing.expect(stat.size > 0);
}

test "pie png: single slice renders without crash" {
    const allocator = std.testing.allocator;
    var pie = PieData.init(allocator);
    defer pie.deinit();

    try pie.addSection("Only", 100);

    try renderPieToPNG(allocator, &pie, "/tmp/merrow_pie_single_test.png", null);

    const stat = try std.fs.cwd().statFile("/tmp/merrow_pie_single_test.png");
    try std.testing.expect(stat.size > 0);
}

test "pie png: many slices render without crash" {
    const allocator = std.testing.allocator;
    var pie = PieData.init(allocator);
    defer pie.deinit();

    const labels = [_][]const u8{ "A", "B", "C", "D", "E", "F", "G", "H", "I", "J" };
    for (labels) |label| {
        try pie.addSection(label, 10);
    }

    try renderPieToPNG(allocator, &pie, "/tmp/merrow_pie_many_test.png", null);

    const stat = try std.fs.cwd().statFile("/tmp/merrow_pie_many_test.png");
    try std.testing.expect(stat.size > 0);
}

test "pie png: with title renders without crash" {
    const allocator = std.testing.allocator;
    var pie = PieData.init(allocator);
    defer pie.deinit();

    try pie.setTitle("My Chart");
    try pie.addSection("X", 70);
    try pie.addSection("Y", 30);

    try renderPieToPNG(allocator, &pie, "/tmp/merrow_pie_title_test.png", null);

    const stat = try std.fs.cwd().statFile("/tmp/merrow_pie_title_test.png");
    try std.testing.expect(stat.size > 0);
}
