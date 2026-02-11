//! User journey diagram PNG renderer.
//!
//! Renders a `JourneyDiagram` model to a PNG file using the Canvas rasteriser.
//! Produces:
//!   - Actor legend on the left with colored circles
//!   - Section header bands
//!   - Task boxes with actor circles
//!   - Score-based face emojis (happy/neutral/sad)
//!   - Activity line connecting tasks
//!   - Optional title above the diagram

const std = @import("std");
const Allocator = std.mem.Allocator;
const JourneyDiagram = @import("model.zig").JourneyDiagram;
const journey_model = @import("model.zig");
const Canvas = @import("../render/canvas.zig").Canvas;
const Font = @import("../render/text.zig").Font;

// -----------------------------------------------------------------------
// Layout constants (matching SVG renderer / mermaid.js defaults)
// -----------------------------------------------------------------------

const LEFT_MARGIN: f64 = 150.0;
const DIAGRAM_MARGIN_X: f64 = 50.0;
const DIAGRAM_MARGIN_Y: f64 = 10.0;
const TASK_WIDTH: f64 = 150.0;
const TASK_HEIGHT: f64 = 50.0;

const SECTION_Y: f64 = 50.0;
const TASK_Y: f64 = 110.0;
const ACTIVITY_LINE_Y: f64 = 200.0;
const LEGEND_START_Y: f64 = 60.0;
const LEGEND_SPACING: f64 = 20.0;
const EXTRA_VERT_FOR_TITLE: f64 = 70.0;

const FACE_BASE_Y: f64 = 300.0;
const FACE_SCORE_MULTIPLIER: f64 = 30.0;
const FACE_RADIUS: f64 = 15.0;
const TASK_FONT_SIZE: f64 = 14.0;
const TITLE_FONT_SIZE: f64 = 22.0;
const LEGEND_FONT_SIZE: f64 = 13.0;

const SCALE_FACTOR: f64 = 2.0;

// -----------------------------------------------------------------------
// Public API
// -----------------------------------------------------------------------

/// Render a `JourneyDiagram` to a PNG file at `output_path`.
/// If `maybe_font` is provided, text labels are rendered with the font;
/// otherwise labels are omitted.
pub fn renderJourneyToPNG(
    allocator: Allocator,
    diagram: *const JourneyDiagram,
    output_path: []const u8,
    maybe_font: ?*Font,
) !void {
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
    const title_offset: f64 = if (has_title) 40.0 else 0.0;

    const canvas_w: u32 = @intFromFloat(@max(@ceil(width), 400.0));
    const canvas_h: u32 = @intFromFloat(@max(@ceil(total_height), 200.0));

    var canvas = try Canvas.initWithScale(allocator, canvas_w, canvas_h, SCALE_FACTOR);
    defer canvas.deinit();
    canvas.fill(255, 255, 255, 255);

    // Title
    if (diagram.title) |title| {
        if (maybe_font) |font| {
            const tw = font.measureText(title, @floatCast(TITLE_FONT_SIZE));
            const tx: f32 = @floatCast(width / 2.0 - @as(f64, tw) / 2.0);
            font.drawText(&canvas, title, tx, 8.0, @floatCast(TITLE_FONT_SIZE), 51, 51, 51, 255) catch {};
        }
    }

    // Actor legend
    renderActorLegend(&canvas, actors, &actor_color_map, title_offset, maybe_font);

    // Sections and tasks
    renderSectionsAndTasks(&canvas, tasks, LEFT_MARGIN, title_offset, &actor_color_map, maybe_font);

    // Activity line (dashed)
    canvas.drawDashedLine(
        LEFT_MARGIN,
        ACTIVITY_LINE_Y + title_offset,
        LEFT_MARGIN + task_total_width,
        ACTIVITY_LINE_Y + title_offset,
        1,
        102,
        102,
        102,
        255,
        4.0,
        2.0,
    );

    try canvas.saveToPNG(output_path);
}

// -----------------------------------------------------------------------
// Actor legend rendering
// -----------------------------------------------------------------------

fn renderActorLegend(
    canvas: *Canvas,
    actors: []const journey_model.OwnedString,
    actor_color_map: *const std.StringHashMap(usize),
    title_offset: f64,
    maybe_font: ?*Font,
) void {
    for (actors) |actor| {
        const color_idx = actor_color_map.get(actor.data) orelse 0;
        const y_pos = LEGEND_START_Y + title_offset + @as(f64, @floatFromInt(color_idx)) * LEGEND_SPACING;

        const color = journey_model.actorColor(color_idx);

        // Colored circle
        canvas.fillEllipse(20.0, y_pos, 7.0, 7.0, color[0], color[1], color[2], color[3]);
        canvas.strokeEllipse(20.0, y_pos, 7.0, 7.0, 1, 0, 0, 0, 255);

        // Actor name text
        if (maybe_font) |font| {
            const tx: f32 = 40.0;
            const ty: f32 = @floatCast(y_pos - 6.0);
            font.drawText(canvas, actor.data, tx, ty, @floatCast(LEGEND_FONT_SIZE), 51, 51, 51, 255) catch {};
        }
    }
}

// -----------------------------------------------------------------------
// Sections and tasks rendering
// -----------------------------------------------------------------------

fn renderSectionsAndTasks(
    canvas: *Canvas,
    tasks: []const journey_model.JourneyTask,
    left_margin: f64,
    title_offset: f64,
    actor_color_map: *const std.StringHashMap(usize),
    maybe_font: ?*Font,
) void {
    if (tasks.len == 0) {
        if (maybe_font) |font| {
            const msg = "(no tasks defined)";
            const tw = font.measureText(msg, @floatCast(TASK_FONT_SIZE));
            const tx: f32 = @floatCast(left_margin + 200.0 - @as(f64, tw) / 2.0);
            const ty: f32 = @floatCast(TASK_Y + title_offset + TASK_HEIGHT / 2.0 - 7.0);
            font.drawText(canvas, msg, tx, ty, @floatCast(TASK_FONT_SIZE), 128, 128, 128, 255) catch {};
        }
        return;
    }

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

                renderSection(
                    canvas,
                    task.section,
                    section_x,
                    SECTION_Y + title_offset,
                    section_width,
                    current_section_number,
                    maybe_font,
                );

                current_last_section = task.section;
                current_section_number += 1;
            }
            i += 1;
        }
    }

    // Second pass: draw tasks
    var last_section: []const u8 = "";
    var section_number: usize = 0;

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

        renderTask(canvas, &task, task_x, TASK_Y + title_offset, section_idx, actor_color_map, title_offset, maybe_font);
    }
}

fn renderSection(
    canvas: *Canvas,
    text: []const u8,
    x: f64,
    y: f64,
    width: f64,
    section_num: usize,
    maybe_font: ?*Font,
) void {
    const fill = journey_model.sectionFill(section_num);

    // Section background rectangle
    canvas.fillRect(x, y, width, TASK_HEIGHT, fill[0], fill[1], fill[2], fill[3]);
    canvas.strokeRect(x, y, width, TASK_HEIGHT, 1, 102, 102, 102, 255);

    // Section label - centered
    if (maybe_font) |font| {
        const tw = font.measureText(text, @floatCast(TASK_FONT_SIZE));
        const tx: f32 = @floatCast(x + width / 2.0 - @as(f64, tw) / 2.0);
        const ty: f32 = @floatCast(y + TASK_HEIGHT / 2.0 - 7.0);
        font.drawText(canvas, text, tx, ty, @floatCast(TASK_FONT_SIZE), 51, 51, 51, 255) catch {};
    }
}

fn renderTask(
    canvas: *Canvas,
    task: *const journey_model.JourneyTask,
    x: f64,
    y: f64,
    section_num: usize,
    actor_color_map: *const std.StringHashMap(usize),
    title_offset: f64,
    maybe_font: ?*Font,
) void {
    const center_x = x + TASK_WIDTH / 2.0;

    // Task vertical line (dashed) - from task to face area
    const max_height = FACE_BASE_Y + title_offset + 5.0 * FACE_SCORE_MULTIPLIER;
    canvas.drawDashedLine(center_x, y, center_x, max_height, 1, 102, 102, 102, 255, 4.0, 2.0);

    // Face element based on score
    const clamped_score = @min(@max(task.score, 1), 5);
    const face_y = FACE_BASE_Y + title_offset + @as(f64, @floatFromInt(5 - clamped_score)) * FACE_SCORE_MULTIPLIER;
    renderFace(canvas, center_x, face_y, task.score);

    // Task background rectangle
    const fill = journey_model.sectionFill(section_num);
    canvas.fillRect(x, y, TASK_WIDTH, TASK_HEIGHT, fill[0], fill[1], fill[2], fill[3]);
    canvas.strokeRect(x, y, TASK_WIDTH, TASK_HEIGHT, 1, 102, 102, 102, 255);

    // Actor circles on the task
    var actor_x = x + 14.0;
    for (task.people.items) |person| {
        const color_idx = actor_color_map.get(person.data) orelse 0;
        const actor_color = journey_model.actorColor(color_idx);

        canvas.fillEllipse(actor_x, y, 7.0, 7.0, actor_color[0], actor_color[1], actor_color[2], actor_color[3]);
        canvas.strokeEllipse(actor_x, y, 7.0, 7.0, 1, 0, 0, 0, 255);
        actor_x += 10.0;
    }

    // Task label - centered in box
    if (maybe_font) |font| {
        const tw = font.measureText(task.task, @floatCast(TASK_FONT_SIZE));
        const tx: f32 = @floatCast(x + TASK_WIDTH / 2.0 - @as(f64, tw) / 2.0);
        const ty: f32 = @floatCast(y + TASK_HEIGHT / 2.0 - 7.0);
        font.drawText(canvas, task.task, tx, ty, @floatCast(TASK_FONT_SIZE), 51, 51, 51, 255) catch {};
    }
}

// -----------------------------------------------------------------------
// Face rendering (happy/neutral/sad based on score)
// -----------------------------------------------------------------------

fn renderFace(canvas: *Canvas, cx: f64, cy: f64, score: i32) void {
    // Face circle (white fill)
    canvas.fillEllipse(cx, cy, FACE_RADIUS, FACE_RADIUS, 255, 255, 255, 255);
    canvas.strokeEllipse(cx, cy, FACE_RADIUS, FACE_RADIUS, 2, 102, 102, 102, 255);

    // Left eye
    canvas.fillEllipse(cx - FACE_RADIUS / 3.0, cy - FACE_RADIUS / 3.0, 1.5, 1.5, 102, 102, 102, 255);

    // Right eye
    canvas.fillEllipse(cx + FACE_RADIUS / 3.0, cy - FACE_RADIUS / 3.0, 1.5, 1.5, 102, 102, 102, 255);

    // Mouth based on score
    if (score > 3) {
        // Happy face - approximate smile with a few short line segments forming an arc
        const inner_r = FACE_RADIUS / 2.0;
        const steps: usize = 8;
        var i: usize = 0;
        while (i < steps) : (i += 1) {
            const t0 = @as(f64, @floatFromInt(i)) / @as(f64, @floatFromInt(steps));
            const t1 = @as(f64, @floatFromInt(i + 1)) / @as(f64, @floatFromInt(steps));

            // Arc from left to right, curving downward (smile)
            const x0 = cx - inner_r + t0 * inner_r * 2.0;
            const x1 = cx - inner_r + t1 * inner_r * 2.0;
            // Parabolic arc: highest deflection at center
            const deflection0 = 4.0 * t0 * (1.0 - t0) * (inner_r * 0.4);
            const deflection1 = 4.0 * t1 * (1.0 - t1) * (inner_r * 0.4);
            const y0 = cy + 2.0 + deflection0;
            const y1 = cy + 2.0 + deflection1;

            canvas.drawLine(x0, y0, x1, y1, 2, 102, 102, 102, 255);
        }
    } else if (score < 3) {
        // Sad face - approximate frown with a few short line segments forming an upward arc
        const inner_r = FACE_RADIUS / 2.0;
        const steps: usize = 8;
        var i: usize = 0;
        while (i < steps) : (i += 1) {
            const t0 = @as(f64, @floatFromInt(i)) / @as(f64, @floatFromInt(steps));
            const t1 = @as(f64, @floatFromInt(i + 1)) / @as(f64, @floatFromInt(steps));

            const x0 = cx - inner_r + t0 * inner_r * 2.0;
            const x1 = cx - inner_r + t1 * inner_r * 2.0;
            // Parabolic arc curving upward (frown)
            const deflection0 = 4.0 * t0 * (1.0 - t0) * (inner_r * 0.4);
            const deflection1 = 4.0 * t1 * (1.0 - t1) * (inner_r * 0.4);
            const y0 = cy + 7.0 - deflection0;
            const y1 = cy + 7.0 - deflection1;

            canvas.drawLine(x0, y0, x1, y1, 2, 102, 102, 102, 255);
        }
    } else {
        // Neutral face - straight line
        canvas.drawLine(cx - 5.0, cy + 7.0, cx + 5.0, cy + 7.0, 1, 102, 102, 102, 255);
    }
}

// -----------------------------------------------------------------------
// Tests
// -----------------------------------------------------------------------

test "journey png: renders without crash (no font)" {
    const allocator = std.testing.allocator;
    var diagram = JourneyDiagram.init(allocator);
    defer diagram.deinit();

    try diagram.setTitle("Test Journey");
    try diagram.addSection("Morning");
    try diagram.addTask("Wake up", ":3:Me");
    try diagram.addTask("Breakfast", ":5:Me, Cat");
    try diagram.addSection("Work");
    try diagram.addTask("Code", ":4:Me");

    try renderJourneyToPNG(allocator, &diagram, "/tmp/merrow_journey_test.png", null);

    const stat = try std.fs.cwd().statFile("/tmp/merrow_journey_test.png");
    try std.testing.expect(stat.size > 0);
}

test "journey png: empty diagram renders without crash" {
    const allocator = std.testing.allocator;
    var diagram = JourneyDiagram.init(allocator);
    defer diagram.deinit();

    try renderJourneyToPNG(allocator, &diagram, "/tmp/merrow_journey_empty_test.png", null);

    const stat = try std.fs.cwd().statFile("/tmp/merrow_journey_empty_test.png");
    try std.testing.expect(stat.size > 0);
}

test "journey png: single task renders without crash" {
    const allocator = std.testing.allocator;
    var diagram = JourneyDiagram.init(allocator);
    defer diagram.deinit();

    try diagram.addSection("Solo");
    try diagram.addTask("Only task", ":5:Actor");

    try renderJourneyToPNG(allocator, &diagram, "/tmp/merrow_journey_single_test.png", null);

    const stat = try std.fs.cwd().statFile("/tmp/merrow_journey_single_test.png");
    try std.testing.expect(stat.size > 0);
}

test "journey png: all score levels render without crash" {
    const allocator = std.testing.allocator;
    var diagram = JourneyDiagram.init(allocator);
    defer diagram.deinit();

    try diagram.addSection("Scores");
    try diagram.addTask("Very sad", ":1:A");
    try diagram.addTask("Sad", ":2:A");
    try diagram.addTask("Neutral", ":3:A");
    try diagram.addTask("Happy", ":4:A");
    try diagram.addTask("Very happy", ":5:A");

    try renderJourneyToPNG(allocator, &diagram, "/tmp/merrow_journey_scores_test.png", null);

    const stat = try std.fs.cwd().statFile("/tmp/merrow_journey_scores_test.png");
    try std.testing.expect(stat.size > 0);
}

test "journey png: multiple actors render without crash" {
    const allocator = std.testing.allocator;
    var diagram = JourneyDiagram.init(allocator);
    defer diagram.deinit();

    try diagram.setTitle("Team Work");
    try diagram.addSection("Sprint");
    try diagram.addTask("Planning", ":4:Alice, Bob, Charlie, Diana");
    try diagram.addTask("Coding", ":3:Alice, Bob");
    try diagram.addTask("Review", ":5:Charlie, Diana");

    try renderJourneyToPNG(allocator, &diagram, "/tmp/merrow_journey_actors_test.png", null);

    const stat = try std.fs.cwd().statFile("/tmp/merrow_journey_actors_test.png");
    try std.testing.expect(stat.size > 0);
}
