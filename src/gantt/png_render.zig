//! Gantt chart PNG renderer.
//!
//! Renders a `GanttDiagram` to a PNG file using the Canvas rasteriser and
//! optional TrueType font for text labels.  The layout logic mirrors the
//! SVG renderer so that the two outputs look consistent.

const std = @import("std");
const Allocator = std.mem.Allocator;
const GanttDiagram = @import("model.zig").GanttDiagram;
const Task = @import("model.zig").Task;
const SectionInfo = @import("model.zig").SectionInfo;
const gantt_model = @import("model.zig");
const Canvas = @import("../render/canvas.zig").Canvas;
const Font = @import("../render/text.zig").Font;

// -----------------------------------------------------------------------
// Layout constants (matching SVG renderer)
// -----------------------------------------------------------------------

const BAR_HEIGHT: f64 = 20.0;
const BAR_GAP: f64 = 4.0;
const ROW_HEIGHT: f64 = BAR_HEIGHT + BAR_GAP;
const TOP_PADDING: f64 = 50.0;
const LEFT_PADDING: f64 = 75.0;
const RIGHT_PADDING: f64 = 75.0;
const TITLE_TOP_MARGIN: f64 = 25.0;
const GRID_LINE_START_PADDING: f64 = 35.0;
const FONT_SIZE: f64 = 11.0;
const TITLE_FONT_SIZE: f64 = 18.0;
const SECTION_FONT_SIZE: f64 = 11.0;
const AXIS_FONT_SIZE: f64 = 10.0;
const TARGET_WIDTH: f64 = 784.0;
const SCALE_FACTOR: f64 = 2.0;

// -----------------------------------------------------------------------
// Public API
// -----------------------------------------------------------------------

/// Render a Gantt diagram to a PNG file.
pub fn renderGanttToPNG(
    allocator: Allocator,
    diagram: *const GanttDiagram,
    output_path: []const u8,
    maybe_font: ?*Font,
) !void {
    const task_count = diagram.taskCount();

    // ── Empty diagram ───────────────────────────────────────────
    if (task_count == 0) {
        var canvas = try Canvas.initWithScale(allocator, 400, 200, SCALE_FACTOR);
        defer canvas.deinit();
        canvas.fill(255, 255, 255, 255);
        if (diagram.title) |title| {
            if (maybe_font) |font| {
                const tw = font.measureText(title, @floatCast(TITLE_FONT_SIZE));
                const tx: f32 = @floatCast(200.0 - @as(f64, tw) / 2.0);
                font.drawText(&canvas, title, tx, 22.0, @floatCast(TITLE_FONT_SIZE), gantt_model.title_color[0], gantt_model.title_color[1], gantt_model.title_color[2], 255) catch {};
            }
        }
        if (maybe_font) |font| {
            const msg = "(empty Gantt chart)";
            const tw = font.measureText(msg, @floatCast(FONT_SIZE));
            const tx: f32 = @floatCast(200.0 - @as(f64, tw) / 2.0);
            font.drawText(&canvas, msg, tx, 90.0, @floatCast(FONT_SIZE), 128, 128, 128, 255) catch {};
        }
        try canvas.saveToPNG(output_path);
        return;
    }

    // ── Collect section info ────────────────────────────────────
    const sections = try diagram.collectSections();
    defer allocator.free(sections);

    // ── Calculate dimensions ────────────────────────────────────
    const total_width = TARGET_WIDTH;
    const chart_width = total_width - LEFT_PADDING - RIGHT_PADDING;
    const total_height = 2.0 * TOP_PADDING + @as(f64, @floatFromInt(task_count)) * ROW_HEIGHT;

    // Day range
    const range = diagram.dayRange();
    const days_range = @max(range.max - range.min, 1.0);
    const px_per_day = chart_width / days_range;
    const min_day = range.min;

    const canvas_w: u32 = @intFromFloat(@ceil(total_width));
    const canvas_h: u32 = @intFromFloat(@ceil(total_height));

    var canvas = try Canvas.initWithScale(allocator, canvas_w, canvas_h, SCALE_FACTOR);
    defer canvas.deinit();

    // White background
    canvas.fill(255, 255, 255, 255);

    // ── Section backgrounds ─────────────────────────────────────
    renderSectionBackgrounds(&canvas, sections, total_width);

    // ── Grid and axis ───────────────────────────────────────────
    try renderGridAndAxis(&canvas, allocator, diagram, min_day, days_range, total_height, px_per_day, maybe_font);

    // ── Task bars ───────────────────────────────────────────────
    renderTaskBars(&canvas, diagram, sections, min_day, px_per_day, maybe_font);

    // ── Section labels ──────────────────────────────────────────
    renderSectionLabels(&canvas, sections, maybe_font);

    // ── Title ───────────────────────────────────────────────────
    if (diagram.title) |title| {
        if (maybe_font) |font| {
            const tw = font.measureText(title, @floatCast(TITLE_FONT_SIZE));
            const tx: f32 = @floatCast(total_width / 2.0 - @as(f64, tw) / 2.0);
            font.drawText(&canvas, title, tx, @floatCast(TITLE_TOP_MARGIN), @floatCast(TITLE_FONT_SIZE), gantt_model.title_color[0], gantt_model.title_color[1], gantt_model.title_color[2], 255) catch {};
        }
    }

    try canvas.saveToPNG(output_path);
}

// -----------------------------------------------------------------------
// Section backgrounds
// -----------------------------------------------------------------------

fn renderSectionBackgrounds(
    canvas: *Canvas,
    sections: []const SectionInfo,
    total_width: f64,
) void {
    var task_offset: usize = 0;
    for (sections, 0..) |sec, si| {
        const y = TOP_PADDING + @as(f64, @floatFromInt(task_offset)) * ROW_HEIGHT;
        const h = @as(f64, @floatFromInt(sec.count)) * ROW_HEIGHT;
        const fill: [4]u8 = if (si % 2 == 0) gantt_model.section_bg_odd else gantt_model.section_bg_even;
        canvas.fillRect(0, y, total_width, h, fill[0], fill[1], fill[2], fill[3]);
        task_offset += sec.count;
    }
}

// -----------------------------------------------------------------------
// Grid & Axis
// -----------------------------------------------------------------------

fn renderGridAndAxis(
    canvas: *Canvas,
    allocator: Allocator,
    diagram: *const GanttDiagram,
    min_day: f64,
    days_range: f64,
    total_height: f64,
    px_per_day: f64,
    maybe_font: ?*Font,
) !void {
    const grid_bottom = total_height - GRID_LINE_START_PADDING;

    // Choose tick interval
    const raw_interval = @max(1.0, @ceil(days_range / 8.0));
    const tick_interval: f64 = if (raw_interval <= 1)
        1.0
    else if (raw_interval <= 7)
        raw_interval
    else if (raw_interval <= 14)
        7.0
    else if (raw_interval <= 30)
        14.0
    else
        30.0;

    var day: f64 = 0;
    while (day <= days_range + tick_interval) : (day += tick_interval) {
        const x = LEFT_PADDING + day * px_per_day;
        if (x > TARGET_WIDTH - RIGHT_PADDING + 1) break;

        // Vertical grid line
        canvas.drawLine(
            x,
            GRID_LINE_START_PADDING,
            x,
            grid_bottom,
            1,
            gantt_model.grid_color[0],
            gantt_model.grid_color[1],
            gantt_model.grid_color[2],
            gantt_model.grid_color[3],
        );

        // Axis label
        if (maybe_font) |font| {
            const abs_day = min_day + day;
            if (diagram.base_date) |base| {
                const day_int: i32 = @intFromFloat(abs_day);
                const label_date = base.addDays(day_int);
                var buf: [16]u8 = undefined;
                const label_text = label_date.format(&buf);
                const owned_label = try allocator.dupe(u8, label_text);
                defer allocator.free(owned_label);
                const tw = font.measureText(owned_label, @floatCast(AXIS_FONT_SIZE));
                const tx: f32 = @floatCast(x - @as(f64, tw) / 2.0);
                const ty: f32 = @floatCast(grid_bottom + 14.0);
                font.drawText(canvas, owned_label, tx, ty, @floatCast(AXIS_FONT_SIZE), gantt_model.axis_text_color[0], gantt_model.axis_text_color[1], gantt_model.axis_text_color[2], 255) catch {};
            } else {
                var num_buf: [16]u8 = undefined;
                const num_str = std.fmt.bufPrint(&num_buf, "Day {d}", .{@as(i32, @intFromFloat(abs_day))}) catch "?";
                const tw = font.measureText(num_str, @floatCast(AXIS_FONT_SIZE));
                const tx: f32 = @floatCast(x - @as(f64, tw) / 2.0);
                const ty: f32 = @floatCast(grid_bottom + 14.0);
                font.drawText(canvas, num_str, tx, ty, @floatCast(AXIS_FONT_SIZE), gantt_model.axis_text_color[0], gantt_model.axis_text_color[1], gantt_model.axis_text_color[2], 255) catch {};
            }
        }
    }
}

// -----------------------------------------------------------------------
// Task bars
// -----------------------------------------------------------------------

fn renderTaskBars(
    canvas: *Canvas,
    diagram: *const GanttDiagram,
    sections: []const SectionInfo,
    min_day: f64,
    px_per_day: f64,
    maybe_font: ?*Font,
) void {
    for (diagram.tasks.items, 0..) |task, idx| {
        const start_offset = task.start_day - min_day;
        const bar_x = LEFT_PADDING + start_offset * px_per_day;
        const bar_width = @max(task.duration_days * px_per_day, 2.0);
        const bar_y = @as(f64, @floatFromInt(idx)) * ROW_HEIGHT + TOP_PADDING;

        // Determine section index for color cycling
        const sec_idx = sectionIndexForTask(sections, idx);
        const color_idx = sec_idx % 4;

        // Choose fill/stroke based on flags
        var fill: [4]u8 = undefined;
        var stroke: [4]u8 = undefined;

        if (task.flags.critical) {
            fill = gantt_model.crit_fill;
            stroke = gantt_model.crit_stroke;
        } else if (task.flags.done) {
            fill = gantt_model.done_fill;
            stroke = gantt_model.done_stroke;
        } else if (task.flags.active) {
            fill = gantt_model.active_fill;
            stroke = gantt_model.active_stroke;
        } else {
            fill = gantt_model.task_fills[color_idx];
            stroke = gantt_model.task_strokes[color_idx];
        }

        if (task.flags.milestone) {
            // Milestone: diamond shape
            const mid_x = bar_x + bar_width / 2.0;
            const mid_y = bar_y + BAR_HEIGHT / 2.0;
            const half = BAR_HEIGHT / 2.0;

            canvas.fillDiamond(mid_x, mid_y, half, half, fill[0], fill[1], fill[2], fill[3]);
            canvas.strokeDiamond(mid_x, mid_y, half, half, 2, stroke[0], stroke[1], stroke[2], stroke[3]);
        } else {
            // Standard bar — filled rounded rectangle approximated with fillRect + strokeRect
            canvas.fillRect(bar_x, bar_y, bar_width, BAR_HEIGHT, fill[0], fill[1], fill[2], fill[3]);
            canvas.strokeRect(bar_x, bar_y, bar_width, BAR_HEIGHT, 1, stroke[0], stroke[1], stroke[2], stroke[3]);
        }

        // Task label text
        const label = task.label;

        if (maybe_font) |font| {
            const tw_f = font.measureText(label, @floatCast(FONT_SIZE));
            const estimated_text_width: f64 = @floatCast(tw_f);
            const text_y: f32 = @floatCast(bar_y + BAR_HEIGHT / 2.0);

            if (estimated_text_width <= bar_width and !task.flags.milestone) {
                // Text inside bar (white)
                const tx: f32 = @floatCast(bar_x + bar_width / 2.0 - estimated_text_width / 2.0);
                font.drawText(canvas, label, tx, text_y, @floatCast(FONT_SIZE), 255, 255, 255, 255) catch {};
            } else {
                // Text to the right of bar
                const tx: f32 = @floatCast(bar_x + bar_width + 5.0);
                font.drawText(canvas, label, tx, text_y, @floatCast(FONT_SIZE), gantt_model.task_text_color[0], gantt_model.task_text_color[1], gantt_model.task_text_color[2], 255) catch {};
            }
        }
    }
}

fn sectionIndexForTask(sections: []const SectionInfo, task_idx: usize) usize {
    var offset: usize = 0;
    for (sections, 0..) |sec, si| {
        if (task_idx >= offset and task_idx < offset + sec.count) return si;
        offset += sec.count;
    }
    return 0;
}

// -----------------------------------------------------------------------
// Section labels
// -----------------------------------------------------------------------

fn renderSectionLabels(
    canvas: *Canvas,
    sections: []const SectionInfo,
    maybe_font: ?*Font,
) void {
    const font = maybe_font orelse return;

    var task_offset: usize = 0;
    for (sections) |sec| {
        if (sec.count == 0) continue;
        const y = TOP_PADDING + @as(f64, @floatFromInt(task_offset)) * ROW_HEIGHT;
        const h = @as(f64, @floatFromInt(sec.count)) * ROW_HEIGHT;
        const label_y: f32 = @floatCast(y + h / 2.0);

        font.drawText(canvas, sec.name, 5.0, label_y, @floatCast(SECTION_FONT_SIZE), gantt_model.section_label_color[0], gantt_model.section_label_color[1], gantt_model.section_label_color[2], 255) catch {};
        task_offset += sec.count;
    }
}

// -----------------------------------------------------------------------
// Tests
// -----------------------------------------------------------------------

test "gantt png: renders without crash (no font)" {
    const allocator = std.testing.allocator;
    var diagram = GanttDiagram.init(allocator);
    defer diagram.deinit();

    try diagram.addTask("Task A", "2024-01-01, 5d");
    try diagram.addTask("Task B", "2024-01-06, 3d");

    try renderGanttToPNG(allocator, &diagram, "/tmp/merrow_gantt_png_test.png", null);

    const stat = try std.fs.cwd().statFile("/tmp/merrow_gantt_png_test.png");
    try std.testing.expect(stat.size > 0);
}

test "gantt png: empty diagram renders without crash" {
    const allocator = std.testing.allocator;
    var diagram = GanttDiagram.init(allocator);
    defer diagram.deinit();

    try renderGanttToPNG(allocator, &diagram, "/tmp/merrow_gantt_png_empty_test.png", null);

    const stat = try std.fs.cwd().statFile("/tmp/merrow_gantt_png_empty_test.png");
    try std.testing.expect(stat.size > 0);
}

test "gantt png: with title renders" {
    const allocator = std.testing.allocator;
    var diagram = GanttDiagram.init(allocator);
    defer diagram.deinit();

    try diagram.setTitle("My Project");
    try diagram.addTask("Design", "2024-01-01, 5d");

    try renderGanttToPNG(allocator, &diagram, "/tmp/merrow_gantt_png_title_test.png", null);

    const stat = try std.fs.cwd().statFile("/tmp/merrow_gantt_png_title_test.png");
    try std.testing.expect(stat.size > 0);
}

test "gantt png: sections render" {
    const allocator = std.testing.allocator;
    var diagram = GanttDiagram.init(allocator);
    defer diagram.deinit();

    try diagram.addSection("Phase 1");
    try diagram.addTask("Task 1", "2024-01-01, 5d");
    try diagram.addTask("Task 2", "2024-01-06, 3d");
    try diagram.addSection("Phase 2");
    try diagram.addTask("Task 3", "2024-01-10, 4d");

    try renderGanttToPNG(allocator, &diagram, "/tmp/merrow_gantt_png_sections_test.png", null);

    const stat = try std.fs.cwd().statFile("/tmp/merrow_gantt_png_sections_test.png");
    try std.testing.expect(stat.size > 0);
}

test "gantt png: critical and done tasks" {
    const allocator = std.testing.allocator;
    var diagram = GanttDiagram.init(allocator);
    defer diagram.deinit();

    try diagram.addTask("Done task", "done, 2024-01-01, 3d");
    try diagram.addTask("Active task", "active, 2024-01-04, 3d");
    try diagram.addTask("Critical task", "crit, 2024-01-07, 2d");

    try renderGanttToPNG(allocator, &diagram, "/tmp/merrow_gantt_png_flags_test.png", null);

    const stat = try std.fs.cwd().statFile("/tmp/merrow_gantt_png_flags_test.png");
    try std.testing.expect(stat.size > 0);
}

test "gantt png: milestone renders" {
    const allocator = std.testing.allocator;
    var diagram = GanttDiagram.init(allocator);
    defer diagram.deinit();

    try diagram.addTask("Planning", "2024-01-01, 5d");
    try diagram.addTask("Milestone 1", "milestone, 2024-01-06, 0d");
    try diagram.addTask("Implementation", "2024-01-06, 10d");

    try renderGanttToPNG(allocator, &diagram, "/tmp/merrow_gantt_png_milestone_test.png", null);

    const stat = try std.fs.cwd().statFile("/tmp/merrow_gantt_png_milestone_test.png");
    try std.testing.expect(stat.size > 0);
}
