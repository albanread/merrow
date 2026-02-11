//! Gantt chart SVG renderer.
//!
//! Renders a GanttDiagram model to SVG, drawing task bars grouped by
//! section with a time axis, grid lines, and optional title.

const std = @import("std");
const Allocator = std.mem.Allocator;
const GanttDiagram = @import("model.zig").GanttDiagram;
const Task = @import("model.zig").Task;
const SectionInfo = @import("model.zig").SectionInfo;
const gantt_model = @import("model.zig");
const svg_mod = @import("../render/svg.zig");
const SvgWriter = svg_mod.SvgWriter;
const TextAnchor = svg_mod.TextAnchor;

// -----------------------------------------------------------------------
// Layout constants (matching mermaid.js defaults)
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
const BAR_RADIUS: f64 = 3.0;

// -----------------------------------------------------------------------
// Public API
// -----------------------------------------------------------------------

/// Render a Gantt diagram to an SVG file.
pub fn renderGanttToSVG(
    allocator: Allocator,
    diagram: *const GanttDiagram,
    output_path: []const u8,
) !void {
    const svg_content = try renderGanttToSVGString(allocator, diagram);
    defer allocator.free(svg_content);

    const file = try std.fs.cwd().createFile(output_path, .{});
    defer file.close();
    try file.writeAll(svg_content);
}

/// Render a Gantt diagram to an SVG string.  Caller owns the returned slice.
pub fn renderGanttToSVGString(
    allocator: Allocator,
    diagram: *const GanttDiagram,
) ![]u8 {
    const task_count = diagram.taskCount();

    if (task_count == 0) {
        var svg = try SvgWriter.init(allocator, 400, 200);
        defer svg.deinit();
        if (diagram.title) |title| {
            try svg.textCentered(200, 30, title, TITLE_FONT_SIZE, gantt_model.title_color, "sans-serif");
        }
        try svg.textCentered(200, 100, "(empty Gantt chart)", FONT_SIZE, .{ 128, 128, 128, 255 }, "sans-serif");
        return try svg.finalize();
    }

    // Collect section info
    const sections = try diagram.collectSections();
    defer allocator.free(sections);

    // Calculate dimensions
    const total_width = TARGET_WIDTH;
    const chart_width = total_width - LEFT_PADDING - RIGHT_PADDING;
    const total_height = 2.0 * TOP_PADDING + @as(f64, @floatFromInt(task_count)) * ROW_HEIGHT;

    // Day range
    const range = diagram.dayRange();
    const days_range = @max(range.max - range.min, 1.0);
    const px_per_day = chart_width / days_range;
    const min_day = range.min;

    var svg = try SvgWriter.init(allocator, @ceil(total_width), @ceil(total_height));
    defer svg.deinit();

    // Background
    try svg.rect(0, 0, total_width, total_height, 0, 0, .{ 255, 255, 255, 255 }, null, 0);

    // ── Grid and axis ───────────────────────────────────────────
    try renderGridAndAxis(
        &svg,
        allocator,
        diagram,
        min_day,
        days_range,
        total_height,
        px_per_day,
    );

    // ── Section backgrounds ─────────────────────────────────────
    try renderSectionBackgrounds(&svg, sections, total_width);

    // ── Task bars ───────────────────────────────────────────────
    try renderTaskBars(&svg, diagram, sections, min_day, px_per_day);

    // ── Section labels ──────────────────────────────────────────
    try renderSectionLabels(&svg, diagram, sections);

    // ── Title ───────────────────────────────────────────────────
    if (diagram.title) |title| {
        try svg.textCentered(
            total_width / 2.0,
            TITLE_TOP_MARGIN,
            title,
            TITLE_FONT_SIZE,
            gantt_model.title_color,
            "sans-serif",
        );
    }

    return try svg.finalize();
}

// -----------------------------------------------------------------------
// Grid & Axis
// -----------------------------------------------------------------------

fn renderGridAndAxis(
    svg: *SvgWriter,
    allocator: Allocator,
    diagram: *const GanttDiagram,
    min_day: f64,
    days_range: f64,
    total_height: f64,
    px_per_day: f64,
) !void {
    const grid_bottom = total_height - GRID_LINE_START_PADDING;

    // Choose tick interval: aim for roughly 5-10 ticks
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
        try svg.line(
            x,
            GRID_LINE_START_PADDING,
            x,
            grid_bottom,
            gantt_model.grid_color,
            0.5,
            null,
        );

        // Axis label
        const abs_day = min_day + day;
        if (diagram.base_date) |base| {
            const day_int: i32 = @intFromFloat(abs_day);
            const label_date = base.addDays(day_int);
            var buf: [16]u8 = undefined;
            const label_text = label_date.format(&buf);
            // We need to dupe because svg.textAt takes a slice that must
            // live long enough for the SVG buffer append.
            const owned_label = try allocator.dupe(u8, label_text);
            defer allocator.free(owned_label);
            try svg.textCentered(
                x,
                grid_bottom + 14.0,
                owned_label,
                AXIS_FONT_SIZE,
                gantt_model.axis_text_color,
                "sans-serif",
            );
        } else {
            // No base date — show day numbers
            var num_buf: [16]u8 = undefined;
            const num_len = (std.fmt.bufPrint(&num_buf, "Day {d}", .{@as(i32, @intFromFloat(abs_day))}) catch "?").len;
            try svg.textCentered(
                x,
                grid_bottom + 14.0,
                num_buf[0..num_len],
                AXIS_FONT_SIZE,
                gantt_model.axis_text_color,
                "sans-serif",
            );
        }
    }
}

// -----------------------------------------------------------------------
// Section backgrounds
// -----------------------------------------------------------------------

fn renderSectionBackgrounds(
    svg: *SvgWriter,
    sections: []const SectionInfo,
    total_width: f64,
) !void {
    var task_offset: usize = 0;
    for (sections, 0..) |sec, si| {
        const y = TOP_PADDING + @as(f64, @floatFromInt(task_offset)) * ROW_HEIGHT;
        const h = @as(f64, @floatFromInt(sec.count)) * ROW_HEIGHT;
        const fill: [4]u8 = if (si % 2 == 0) gantt_model.section_bg_odd else gantt_model.section_bg_even;
        try svg.rect(0, y, total_width, h, 0, 0, fill, null, 0);
        task_offset += sec.count;
    }
}

// -----------------------------------------------------------------------
// Task bars
// -----------------------------------------------------------------------

fn renderTaskBars(
    svg: *SvgWriter,
    diagram: *const GanttDiagram,
    sections: []const SectionInfo,
    min_day: f64,
    px_per_day: f64,
) !void {
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
            // Milestone: small diamond
            const mid_x = bar_x + bar_width / 2.0;
            const mid_y = bar_y + BAR_HEIGHT / 2.0;
            const half = BAR_HEIGHT / 2.0;
            var points: [4][2]f64 = undefined;
            points[0] = .{ mid_x, mid_y - half };
            points[1] = .{ mid_x + half, mid_y };
            points[2] = .{ mid_x, mid_y + half };
            points[3] = .{ mid_x - half, mid_y };
            try svg.polygon(&points, fill, stroke, 1.5);
        } else {
            // Standard bar
            try svg.rect(bar_x, bar_y, bar_width, BAR_HEIGHT, BAR_RADIUS, BAR_RADIUS, fill, stroke, 1.0);
        }

        // Task label text
        const label = task.label;
        const estimated_text_width = @as(f64, @floatFromInt(label.len)) * FONT_SIZE * 0.5;
        const text_y = bar_y + BAR_HEIGHT / 2.0 + (FONT_SIZE / 2.0 - 2.0);

        if (estimated_text_width <= bar_width and !task.flags.milestone) {
            // Text inside bar
            try svg.textCentered(
                bar_x + bar_width / 2.0,
                text_y,
                label,
                FONT_SIZE,
                .{ 255, 255, 255, 255 },
                "sans-serif",
            );
        } else {
            // Text to the right of bar
            try svg.textAt(
                bar_x + bar_width + 5.0,
                text_y,
                label,
                FONT_SIZE,
                gantt_model.task_text_color,
                "sans-serif",
                TextAnchor.start,
            );
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
    svg: *SvgWriter,
    diagram: *const GanttDiagram,
    sections: []const SectionInfo,
) !void {
    _ = diagram;
    var task_offset: usize = 0;
    for (sections) |sec| {
        if (sec.count == 0) continue;
        const y = TOP_PADDING + @as(f64, @floatFromInt(task_offset)) * ROW_HEIGHT;
        const h = @as(f64, @floatFromInt(sec.count)) * ROW_HEIGHT;
        const label_y = y + h / 2.0 + SECTION_FONT_SIZE / 2.0 - 2.0;

        try svg.textAt(
            5.0,
            label_y,
            sec.name,
            SECTION_FONT_SIZE,
            gantt_model.section_label_color,
            "sans-serif",
            TextAnchor.start,
        );
        task_offset += sec.count;
    }
}

// -----------------------------------------------------------------------
// Tests
// -----------------------------------------------------------------------

test "gantt svg: renders empty diagram" {
    const allocator = std.testing.allocator;
    var diagram = GanttDiagram.init(allocator);
    defer diagram.deinit();

    const svg_str = try renderGanttToSVGString(allocator, &diagram);
    defer allocator.free(svg_str);

    try std.testing.expect(svg_str.len > 0);
    try std.testing.expect(std.mem.indexOf(u8, svg_str, "<svg") != null);
    try std.testing.expect(std.mem.indexOf(u8, svg_str, "empty Gantt chart") != null);
}

test "gantt svg: renders single task" {
    const allocator = std.testing.allocator;
    var diagram = GanttDiagram.init(allocator);
    defer diagram.deinit();

    try diagram.addTask("Design", "2024-01-01, 5d");

    const svg_str = try renderGanttToSVGString(allocator, &diagram);
    defer allocator.free(svg_str);

    try std.testing.expect(std.mem.indexOf(u8, svg_str, "Design") != null);
    try std.testing.expect(std.mem.indexOf(u8, svg_str, "<rect") != null);
}

test "gantt svg: renders with title" {
    const allocator = std.testing.allocator;
    var diagram = GanttDiagram.init(allocator);
    defer diagram.deinit();

    try diagram.setTitle("Project Plan");
    try diagram.addTask("Task A", "2024-01-01, 3d");

    const svg_str = try renderGanttToSVGString(allocator, &diagram);
    defer allocator.free(svg_str);

    try std.testing.expect(std.mem.indexOf(u8, svg_str, "Project Plan") != null);
}

test "gantt svg: renders sections" {
    const allocator = std.testing.allocator;
    var diagram = GanttDiagram.init(allocator);
    defer diagram.deinit();

    try diagram.addSection("Design");
    try diagram.addTask("Mock-up", "2024-01-01, 3d");
    try diagram.addSection("Dev");
    try diagram.addTask("Coding", "2024-01-04, 5d");

    const svg_str = try renderGanttToSVGString(allocator, &diagram);
    defer allocator.free(svg_str);

    try std.testing.expect(std.mem.indexOf(u8, svg_str, "Design") != null);
    try std.testing.expect(std.mem.indexOf(u8, svg_str, "Dev") != null);
    try std.testing.expect(std.mem.indexOf(u8, svg_str, "Mock-up") != null);
    try std.testing.expect(std.mem.indexOf(u8, svg_str, "Coding") != null);
}

test "gantt svg: renders milestone" {
    const allocator = std.testing.allocator;
    var diagram = GanttDiagram.init(allocator);
    defer diagram.deinit();

    try diagram.addTask("Release", "milestone, 2024-01-15, 0d");

    const svg_str = try renderGanttToSVGString(allocator, &diagram);
    defer allocator.free(svg_str);

    try std.testing.expect(std.mem.indexOf(u8, svg_str, "Release") != null);
    // Milestones render as polygons
    try std.testing.expect(std.mem.indexOf(u8, svg_str, "<polygon") != null);
}

test "gantt svg: renders critical task" {
    const allocator = std.testing.allocator;
    var diagram = GanttDiagram.init(allocator);
    defer diagram.deinit();

    try diagram.addTask("Critical", "crit, 2024-01-01, 3d");
    try diagram.addTask("Normal", "2024-01-04, 2d");

    const svg_str = try renderGanttToSVGString(allocator, &diagram);
    defer allocator.free(svg_str);

    try std.testing.expect(std.mem.indexOf(u8, svg_str, "Critical") != null);
    try std.testing.expect(std.mem.indexOf(u8, svg_str, "Normal") != null);
}

test "gantt svg: renders grid lines" {
    const allocator = std.testing.allocator;
    var diagram = GanttDiagram.init(allocator);
    defer diagram.deinit();

    try diagram.addTask("A", "2024-01-01, 10d");

    const svg_str = try renderGanttToSVGString(allocator, &diagram);
    defer allocator.free(svg_str);

    // Should have grid lines
    try std.testing.expect(std.mem.indexOf(u8, svg_str, "<line") != null);
}

test "gantt svg: write to file" {
    const allocator = std.testing.allocator;
    var diagram = GanttDiagram.init(allocator);
    defer diagram.deinit();

    try diagram.setTitle("Test Gantt");
    try diagram.addSection("Phase 1");
    try diagram.addTask("Task A", "2024-01-01, 5d");
    try diagram.addTask("Task B", "2024-01-06, 3d");

    try renderGanttToSVG(allocator, &diagram, "/tmp/merrow_gantt_test.svg");

    // Verify file was created
    const file = try std.fs.cwd().openFile("/tmp/merrow_gantt_test.svg", .{});
    file.close();
}
