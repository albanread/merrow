//! User journey diagram SVG renderer.
//!
//! Renders a `JourneyDiagram` model to an SVG string using the `SvgWriter`.
//! Produces:
//!   - Actor legend on the left with colored circles
//!   - Section header bands
//!   - Task boxes with actor circles and labels
//!   - Score-based face emojis (happy/neutral/sad)
//!   - Activity line connecting tasks
//!   - Optional title above the diagram

const std = @import("std");
const Allocator = std.mem.Allocator;
const JourneyDiagram = @import("model.zig").JourneyDiagram;
const journey_model = @import("model.zig");
const SvgWriter = @import("../render/svg.zig").SvgWriter;

// -----------------------------------------------------------------------
// Layout constants (matching mermaid.js defaults)
// -----------------------------------------------------------------------

/// Margin on the left for actor legend
const LEFT_MARGIN: f64 = 150.0;
/// Margin around the diagram
const DIAGRAM_MARGIN_X: f64 = 50.0;
const DIAGRAM_MARGIN_Y: f64 = 10.0;
/// Width of each task box
const TASK_WIDTH: f64 = 150.0;
/// Height of each task/section box
const TASK_HEIGHT: f64 = 50.0;

/// Section header Y position
const SECTION_Y: f64 = 50.0;
/// Task Y position
const TASK_Y: f64 = 110.0;
/// Activity line Y position
const ACTIVITY_LINE_Y: f64 = 200.0;
/// Legend start Y position
const LEGEND_START_Y: f64 = 60.0;
/// Legend spacing between actors
const LEGEND_SPACING: f64 = 20.0;
/// Extra vertical space for title
const EXTRA_VERT_FOR_TITLE: f64 = 70.0;

/// Face vertical base position
const FACE_BASE_Y: f64 = 300.0;
/// Face score multiplier
const FACE_SCORE_MULTIPLIER: f64 = 30.0;
/// Face radius
const FACE_RADIUS: f64 = 15.0;
/// Task font size
const TASK_FONT_SIZE: f64 = 14.0;
/// Title font size
const TITLE_FONT_SIZE: f64 = 24.0;
/// Legend font size
const LEGEND_FONT_SIZE: f64 = 14.0;

/// Section fill SVG hex colors (matching mermaid.js defaults)
const section_svg_fills = [8][]const u8{
    "#87CEFA",
    "#FFE4B5",
    "#98FB98",
    "#FFB6C1",
    "#E6E6FA",
    "#FFDAB9",
    "#B0E0E6",
    "#FFFFE0",
};

/// Actor SVG hex colors
const actor_svg_colors = [8][]const u8{
    "#8FBC8F",
    "#6495ED",
    "#FFB6C1",
    "#FFD700",
    "#DDA0DD",
    "#F08080",
    "#90EE90",
    "#ADD8E6",
};

/// Task fill SVG hex colors (same palette as sections but more opaque)
const task_svg_fills = [8][]const u8{
    "#87CEFA",
    "#FFE4B5",
    "#98FB98",
    "#FFB6C1",
    "#E6E6FA",
    "#FFDAB9",
    "#B0E0E6",
    "#FFFFE0",
};

// -----------------------------------------------------------------------
// Public API
// -----------------------------------------------------------------------

/// Render a `JourneyDiagram` to SVG and write the result to a file at `output_path`.
pub fn renderJourneyToSVG(
    allocator: Allocator,
    diagram: *const JourneyDiagram,
    output_path: []const u8,
) !void {
    const svg_content = try renderJourneyToSVGString(allocator, diagram);
    defer allocator.free(svg_content);

    const file = try std.fs.cwd().createFile(output_path, .{});
    defer file.close();
    try file.writeAll(svg_content);
}

/// Render a `JourneyDiagram` to an SVG string. Caller owns the returned slice.
pub fn renderJourneyToSVGString(
    allocator: Allocator,
    diagram: *const JourneyDiagram,
) ![]u8 {
    const tasks = diagram.getTasks();
    const has_title = diagram.title != null;

    // Get actors
    const actors = try diagram.getActors();
    defer allocator.free(actors);

    // Build actor color index map
    var actor_color_map = std.StringHashMap(usize).init(allocator);
    defer actor_color_map.deinit();
    for (actors, 0..) |actor, i| {
        try actor_color_map.put(actor.data, i);
    }

    // Calculate dimensions
    const num_tasks = @max(tasks.len, 1);
    const task_total_width = @as(f64, @floatFromInt(num_tasks)) * (TASK_WIDTH + DIAGRAM_MARGIN_X);
    const width = LEFT_MARGIN + task_total_width + DIAGRAM_MARGIN_X * 3.0;

    const max_face_y = FACE_BASE_Y + 5.0 * FACE_SCORE_MULTIPLIER;
    const base_height = max_face_y + 2.0 * DIAGRAM_MARGIN_Y;
    const total_height = if (has_title) base_height + EXTRA_VERT_FOR_TITLE else base_height;

    var svg = try SvgWriter.init(allocator, @ceil(width), @ceil(total_height));
    defer svg.deinit();

    // Background
    try svg.rect(0, 0, width, total_height, 0, 0, .{ 255, 255, 255, 255 }, null, 0);

    // Title
    const title_offset: f64 = if (has_title) 40.0 else 0.0;
    if (diagram.title) |title| {
        try svg.textCentered(
            width / 2.0,
            25.0,
            title,
            TITLE_FONT_SIZE,
            journey_model.text_color,
            "sans-serif",
        );
    }

    // Actor legend
    try renderActorLegend(&svg, actors, &actor_color_map, title_offset);

    // Sections and tasks
    try renderSectionsAndTasks(allocator, &svg, diagram, tasks, LEFT_MARGIN, title_offset, &actor_color_map);

    // Activity line
    try renderActivityLine(&svg, LEFT_MARGIN, ACTIVITY_LINE_Y + title_offset, task_total_width);

    return try svg.finalize();
}

// -----------------------------------------------------------------------
// Actor legend rendering
// -----------------------------------------------------------------------

fn renderActorLegend(
    svg: *SvgWriter,
    actors: []const journey_model.OwnedString,
    actor_color_map: *const std.StringHashMap(usize),
    title_offset: f64,
) !void {
    for (actors) |actor| {
        const color_idx = actor_color_map.get(actor.data) orelse 0;
        const y_pos = LEGEND_START_Y + title_offset + @as(f64, @floatFromInt(color_idx)) * LEGEND_SPACING;

        const color = journey_model.actorColor(color_idx);

        // Colored circle
        try svg.ellipse(
            20.0,
            y_pos,
            7.0,
            7.0,
            color,
            .{ 0, 0, 0, 255 },
            1,
        );

        // Actor name
        try svg.textAt(
            40.0,
            y_pos + 5.0,
            actor.data,
            LEGEND_FONT_SIZE,
            journey_model.text_color,
            "sans-serif",
            .start,
        );
    }
}

// -----------------------------------------------------------------------
// Sections and tasks rendering
// -----------------------------------------------------------------------

fn renderSectionsAndTasks(
    allocator: Allocator,
    svg: *SvgWriter,
    diagram: *const JourneyDiagram,
    tasks: []const journey_model.JourneyTask,
    left_margin: f64,
    title_offset: f64,
    actor_color_map: *const std.StringHashMap(usize),
) !void {
    _ = diagram;

    if (tasks.len == 0) {
        // Empty diagram message
        try svg.textCentered(
            left_margin + 200.0,
            TASK_Y + title_offset + TASK_HEIGHT / 2.0,
            "(no tasks defined)",
            TASK_FONT_SIZE,
            .{ 128, 128, 128, 255 },
            "sans-serif",
        );
        return;
    }

    var last_section: []const u8 = "";
    var section_number: usize = 0;

    // First pass: draw section backgrounds
    {
        var i: usize = 0;
        var current_last_section: []const u8 = "";
        var current_section_number: usize = 0;
        while (i < tasks.len) {
            const task = &tasks[i];

            if (!std.mem.eql(u8, task.section, current_last_section)) {
                // Count how many consecutive tasks share this section
                var task_count: usize = 0;
                var j = i;
                while (j < tasks.len and std.mem.eql(u8, tasks[j].section, task.section)) {
                    task_count += 1;
                    j += 1;
                }

                const section_x = @as(f64, @floatFromInt(i)) * (TASK_WIDTH + DIAGRAM_MARGIN_X) + left_margin;
                const section_width = @as(f64, @floatFromInt(task_count)) * TASK_WIDTH +
                    @as(f64, @floatFromInt(task_count -| 1)) * DIAGRAM_MARGIN_X;

                try renderSection(
                    svg,
                    task.section,
                    section_x,
                    SECTION_Y + title_offset,
                    section_width,
                    current_section_number,
                );

                current_last_section = task.section;
                current_section_number += 1;
            }
            i += 1;
        }
    }

    // Second pass: draw tasks
    last_section = "";
    section_number = 0;

    for (tasks, 0..) |task, i| {
        if (!std.mem.eql(u8, task.section, last_section)) {
            if (last_section.len > 0 or task.section.len > 0) {
                if (!std.mem.eql(u8, task.section, last_section)) {
                    section_number += 1;
                }
            }
            last_section = task.section;
        }

        const task_x = @as(f64, @floatFromInt(i)) * (TASK_WIDTH + DIAGRAM_MARGIN_X) + left_margin;
        const section_idx = if (section_number > 0) section_number - 1 else 0;

        try renderTask(
            allocator,
            svg,
            &task,
            task_x,
            TASK_Y + title_offset,
            section_idx,
            actor_color_map,
            i,
            title_offset,
        );
    }
}

fn renderSection(
    svg: *SvgWriter,
    text: []const u8,
    x: f64,
    y: f64,
    width: f64,
    section_num: usize,
) !void {
    const section_idx = section_num % section_svg_fills.len;

    // Parse the hex color for fill
    const fill_color = parseHexColor(section_svg_fills[section_idx]);

    // Section background rectangle
    try svg.rect(x, y, width, TASK_HEIGHT, 3, 3, fill_color, .{ 102, 102, 102, 255 }, 1);

    // Section label - centered
    try svg.textCentered(
        x + width / 2.0,
        y + TASK_HEIGHT / 2.0 + 5.0,
        text,
        TASK_FONT_SIZE,
        journey_model.text_color,
        "sans-serif",
    );
}

fn renderTask(
    allocator: Allocator,
    svg: *SvgWriter,
    task: *const journey_model.JourneyTask,
    x: f64,
    y: f64,
    section_num: usize,
    actor_color_map: *const std.StringHashMap(usize),
    task_index: usize,
    title_offset: f64,
) !void {
    _ = allocator;
    const center_x = x + TASK_WIDTH / 2.0;

    // Task vertical line (dashed) - from task to face area
    const max_height = FACE_BASE_Y + title_offset + 5.0 * FACE_SCORE_MULTIPLIER;
    try svg.line(
        center_x,
        y,
        center_x,
        max_height,
        .{ 102, 102, 102, 255 },
        1,
        "4 2",
    );

    // Face element based on score
    const clamped_score = @min(@max(task.score, 1), 5);
    const face_y = FACE_BASE_Y + title_offset + @as(f64, @floatFromInt(5 - clamped_score)) * FACE_SCORE_MULTIPLIER;
    try renderFace(svg, center_x, face_y, task.score);

    // Task background rectangle
    const task_section_idx = section_num % task_svg_fills.len;
    const task_fill = parseHexColor(task_svg_fills[task_section_idx]);
    try svg.rect(x, y, TASK_WIDTH, TASK_HEIGHT, 3, 3, task_fill, .{ 102, 102, 102, 255 }, 1);

    // Actor circles on the task
    var actor_x = x + 14.0;
    for (task.people.items) |person| {
        const color_idx = actor_color_map.get(person.data) orelse 0;
        const actor_color = journey_model.actorColor(color_idx);

        try svg.ellipse(
            actor_x,
            y,
            7.0,
            7.0,
            actor_color,
            .{ 0, 0, 0, 255 },
            1,
        );
        actor_x += 10.0;
    }

    // Task label - centered in box
    try svg.textCentered(
        x + TASK_WIDTH / 2.0,
        y + TASK_HEIGHT / 2.0 + 5.0,
        task.task,
        TASK_FONT_SIZE,
        journey_model.text_color,
        "sans-serif",
    );

    _ = task_index;
}

// -----------------------------------------------------------------------
// Face rendering (happy/neutral/sad based on score)
// -----------------------------------------------------------------------

fn renderFace(svg: *SvgWriter, cx: f64, cy: f64, score: i32) !void {
    // Face circle (white fill)
    try svg.ellipse(
        cx,
        cy,
        FACE_RADIUS,
        FACE_RADIUS,
        journey_model.face_color,
        .{ 102, 102, 102, 255 },
        2,
    );

    // Left eye
    try svg.ellipse(
        cx - FACE_RADIUS / 3.0,
        cy - FACE_RADIUS / 3.0,
        1.5,
        1.5,
        .{ 102, 102, 102, 255 },
        .{ 102, 102, 102, 255 },
        1,
    );

    // Right eye
    try svg.ellipse(
        cx + FACE_RADIUS / 3.0,
        cy - FACE_RADIUS / 3.0,
        1.5,
        1.5,
        .{ 102, 102, 102, 255 },
        .{ 102, 102, 102, 255 },
        1,
    );

    // Mouth based on score
    if (score > 3) {
        // Happy face - smile arc
        const inner_r = FACE_RADIUS / 2.0;
        var path_buf: [256]u8 = undefined;
        const path = std.fmt.bufPrint(&path_buf, "M{d:.1},{d:.1}A{d:.1},{d:.1},0,0,0,{d:.1},{d:.1}", .{
            cx - inner_r,
            cy + 2.0,
            inner_r,
            inner_r / 1.1,
            cx + inner_r,
            cy + 2.0,
        }) catch "M0,0";
        try svg.path(path, null, .{ 102, 102, 102, 255 }, 2.0, null);
    } else if (score < 3) {
        // Sad face - frown arc
        const inner_r = FACE_RADIUS / 2.0;
        var path_buf: [256]u8 = undefined;
        const path = std.fmt.bufPrint(&path_buf, "M{d:.1},{d:.1}A{d:.1},{d:.1},0,0,1,{d:.1},{d:.1}", .{
            cx - inner_r,
            cy + 7.0,
            inner_r,
            inner_r / 1.1,
            cx + inner_r,
            cy + 7.0,
        }) catch "M0,0";
        try svg.path(path, null, .{ 102, 102, 102, 255 }, 2.0, null);
    } else {
        // Neutral face - straight line
        try svg.line(
            cx - 5.0,
            cy + 7.0,
            cx + 5.0,
            cy + 7.0,
            .{ 102, 102, 102, 255 },
            1,
            null,
        );
    }
}

// -----------------------------------------------------------------------
// Activity line rendering
// -----------------------------------------------------------------------

fn renderActivityLine(svg: *SvgWriter, left_margin: f64, y: f64, width: f64) !void {
    try svg.line(
        left_margin,
        y,
        left_margin + width,
        y,
        .{ 102, 102, 102, 255 },
        1,
        "4 2",
    );
}

// -----------------------------------------------------------------------
// Hex color parser
// -----------------------------------------------------------------------

fn parseHexColor(hex: []const u8) [4]u8 {
    // Parse #RRGGBB format
    if (hex.len < 7 or hex[0] != '#') return .{ 200, 200, 200, 255 };

    const r = parseHexByte(hex[1..3]) catch 200;
    const g = parseHexByte(hex[3..5]) catch 200;
    const b = parseHexByte(hex[5..7]) catch 200;

    return .{ r, g, b, 255 };
}

fn parseHexByte(s: []const u8) !u8 {
    if (s.len != 2) return error.InvalidLength;
    const high = hexDigit(s[0]) orelse return error.InvalidHex;
    const low = hexDigit(s[1]) orelse return error.InvalidHex;
    return high * 16 + low;
}

fn hexDigit(c: u8) ?u8 {
    if (c >= '0' and c <= '9') return c - '0';
    if (c >= 'a' and c <= 'f') return c - 'a' + 10;
    if (c >= 'A' and c <= 'F') return c - 'A' + 10;
    return null;
}

// -----------------------------------------------------------------------
// Tests
// -----------------------------------------------------------------------

test "journey svg: renders empty diagram" {
    const allocator = std.testing.allocator;
    var diagram = JourneyDiagram.init(allocator);
    defer diagram.deinit();

    const svg = try renderJourneyToSVGString(allocator, &diagram);
    defer allocator.free(svg);

    try std.testing.expect(std.mem.indexOf(u8, svg, "<svg") != null);
    try std.testing.expect(std.mem.indexOf(u8, svg, "</svg>") != null);
    try std.testing.expect(std.mem.indexOf(u8, svg, "no tasks defined") != null);
}

test "journey svg: renders title" {
    const allocator = std.testing.allocator;
    var diagram = JourneyDiagram.init(allocator);
    defer diagram.deinit();

    try diagram.setTitle("My Working Day");
    try diagram.addSection("Go to work");
    try diagram.addTask("Make tea", ":5:Me");

    const svg = try renderJourneyToSVGString(allocator, &diagram);
    defer allocator.free(svg);

    try std.testing.expect(std.mem.indexOf(u8, svg, "My Working Day") != null);
}

test "journey svg: renders tasks and sections" {
    const allocator = std.testing.allocator;
    var diagram = JourneyDiagram.init(allocator);
    defer diagram.deinit();

    try diagram.setTitle("Shopping");
    try diagram.addSection("Prepare");
    try diagram.addTask("Get keys", ":5:Dad");
    try diagram.addTask("Go to car", ":3:Dad, Mum");
    try diagram.addSection("Shop");
    try diagram.addTask("Buy food", ":4:Mum");

    const svg = try renderJourneyToSVGString(allocator, &diagram);
    defer allocator.free(svg);

    try std.testing.expect(std.mem.indexOf(u8, svg, "<svg") != null);
    try std.testing.expect(std.mem.indexOf(u8, svg, "</svg>") != null);
    // Should contain task labels
    try std.testing.expect(std.mem.indexOf(u8, svg, "Get keys") != null);
    try std.testing.expect(std.mem.indexOf(u8, svg, "Go to car") != null);
    try std.testing.expect(std.mem.indexOf(u8, svg, "Buy food") != null);
    // Should contain section labels
    try std.testing.expect(std.mem.indexOf(u8, svg, "Prepare") != null);
    try std.testing.expect(std.mem.indexOf(u8, svg, "Shop") != null);
    // Should contain face elements (ellipses for the face circles)
    try std.testing.expect(std.mem.indexOf(u8, svg, "<ellipse") != null);
}

test "journey svg: renders actor legend" {
    const allocator = std.testing.allocator;
    var diagram = JourneyDiagram.init(allocator);
    defer diagram.deinit();

    try diagram.addSection("S1");
    try diagram.addTask("Task", ":5:Alice, Bob");

    const svg = try renderJourneyToSVGString(allocator, &diagram);
    defer allocator.free(svg);

    // Should contain actor names in legend
    try std.testing.expect(std.mem.indexOf(u8, svg, "Alice") != null);
    try std.testing.expect(std.mem.indexOf(u8, svg, "Bob") != null);
}

test "journey svg: renders faces for different scores" {
    const allocator = std.testing.allocator;
    var diagram = JourneyDiagram.init(allocator);
    defer diagram.deinit();

    try diagram.addSection("S1");
    try diagram.addTask("Happy", ":5:A");
    try diagram.addTask("Neutral", ":3:A");
    try diagram.addTask("Sad", ":1:A");

    const svg = try renderJourneyToSVGString(allocator, &diagram);
    defer allocator.free(svg);

    // Should have path elements for smile and frown arcs
    try std.testing.expect(std.mem.indexOf(u8, svg, "<path") != null);
    // Should have line element for neutral mouth
    try std.testing.expect(std.mem.indexOf(u8, svg, "<line") != null);
}

test "journey svg: write to file" {
    const allocator = std.testing.allocator;
    var diagram = JourneyDiagram.init(allocator);
    defer diagram.deinit();

    try diagram.setTitle("Test Journey");
    try diagram.addSection("Morning");
    try diagram.addTask("Wake up", ":3:Me");
    try diagram.addTask("Breakfast", ":5:Me, Cat");
    try diagram.addSection("Work");
    try diagram.addTask("Code", ":4:Me");

    try renderJourneyToSVG(allocator, &diagram, "/tmp/merrow_journey_test.svg");

    const stat = try std.fs.cwd().statFile("/tmp/merrow_journey_test.svg");
    try std.testing.expect(stat.size > 0);
}

test "journey svg: parseHexColor" {
    const c = parseHexColor("#FF8000");
    try std.testing.expectEqual(@as(u8, 255), c[0]);
    try std.testing.expectEqual(@as(u8, 128), c[1]);
    try std.testing.expectEqual(@as(u8, 0), c[2]);
    try std.testing.expectEqual(@as(u8, 255), c[3]);
}

test "journey svg: parseHexColor lowercase" {
    const c = parseHexColor("#ff8000");
    try std.testing.expectEqual(@as(u8, 255), c[0]);
    try std.testing.expectEqual(@as(u8, 128), c[1]);
    try std.testing.expectEqual(@as(u8, 0), c[2]);
}
