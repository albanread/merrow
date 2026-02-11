const std = @import("std");
const merrow = @import("merrow");
const Canvas = merrow.render.canvas.Canvas;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    std.debug.print("\n=== Box-Line Alignment Test ===\n\n", .{});

    // Test with 1x scale
    std.debug.print("Test 1: 1x scale (baseline)\n", .{});
    try testAlignment(allocator, 1.0, "alignment_1x.png");

    // Test with 2x scale
    std.debug.print("Test 2: 2x scale (HD)\n", .{});
    try testAlignment(allocator, 2.0, "alignment_2x.png");

    // Test with 3x scale
    std.debug.print("Test 3: 3x scale (Ultra-HD)\n", .{});
    try testAlignment(allocator, 3.0, "alignment_3x.png");

    std.debug.print("\n✓ All alignment tests complete!\n", .{});
    std.debug.print("Check output files - lines should connect to box centers\n", .{});
}

fn testAlignment(allocator: std.mem.Allocator, scale: f64, filename: []const u8) !void {
    var canvas = try Canvas.initWithScale(allocator, 600, 400, scale);
    defer canvas.deinit();

    // White background
    canvas.fill(255, 255, 255, 255);

    // Define three boxes in LOGICAL coordinates
    // Box A: top-left
    const box_a_center_x: f64 = 100.0;
    const box_a_center_y: f64 = 100.0;
    const box_a_width: f64 = 120.0;
    const box_a_height: f64 = 60.0;

    // Box B: top-right
    const box_b_center_x: f64 = 400.0;
    const box_b_center_y: f64 = 100.0;
    const box_b_width: f64 = 120.0;
    const box_b_height: f64 = 60.0;

    // Box C: bottom-center
    const box_c_center_x: f64 = 250.0;
    const box_c_center_y: f64 = 300.0;
    const box_c_width: f64 = 120.0;
    const box_c_height: f64 = 60.0;

    // Draw edges FIRST (should connect center-to-center)
    // A -> B
    canvas.drawLine(
        box_a_center_x,
        box_a_center_y,
        box_b_center_x,
        box_b_center_y,
        2,
        255,
        0,
        0,
        255, // Red
    );

    // A -> C
    canvas.drawLine(
        box_a_center_x,
        box_a_center_y,
        box_c_center_x,
        box_c_center_y,
        2,
        0,
        255,
        0,
        255, // Green
    );

    // B -> C
    canvas.drawLine(
        box_b_center_x,
        box_b_center_y,
        box_c_center_x,
        box_c_center_y,
        2,
        0,
        0,
        255,
        255, // Blue
    );

    // Draw boxes SECOND (on top of lines)
    // Box A (light blue)
    const box_a_x = box_a_center_x - box_a_width / 2.0;
    const box_a_y = box_a_center_y - box_a_height / 2.0;
    canvas.fillRect(box_a_x, box_a_y, box_a_width, box_a_height, 200, 220, 255, 255);
    canvas.strokeRect(box_a_x, box_a_y, box_a_width, box_a_height, 2, 50, 100, 200, 255);

    // Box B (light green)
    const box_b_x = box_b_center_x - box_b_width / 2.0;
    const box_b_y = box_b_center_y - box_b_height / 2.0;
    canvas.fillRect(box_b_x, box_b_y, box_b_width, box_b_height, 200, 255, 200, 255);
    canvas.strokeRect(box_b_x, box_b_y, box_b_width, box_b_height, 2, 50, 150, 50, 255);

    // Box C (light orange)
    const box_c_x = box_c_center_x - box_c_width / 2.0;
    const box_c_y = box_c_center_y - box_c_height / 2.0;
    canvas.fillRect(box_c_x, box_c_y, box_c_width, box_c_height, 255, 220, 180, 255);
    canvas.strokeRect(box_c_x, box_c_y, box_c_width, box_c_height, 2, 200, 120, 50, 255);

    // Draw small dots at the centers to verify alignment
    // These should be exactly where the lines meet
    drawCrosshair(&canvas, box_a_center_x, box_a_center_y, 5, 0, 0, 0, 255);
    drawCrosshair(&canvas, box_b_center_x, box_b_center_y, 5, 0, 0, 0, 255);
    drawCrosshair(&canvas, box_c_center_x, box_c_center_y, 5, 0, 0, 0, 255);

    try canvas.saveToPNG(filename);
    std.debug.print("  ✓ Saved: {s} (scale={d}x)\n", .{ filename, scale });
}

fn drawCrosshair(canvas: *Canvas, center_x: f64, center_y: f64, size: i32, r: u8, g: u8, b: u8, a: u8) void {
    const s = @as(f64, @floatFromInt(size));
    canvas.drawLine(center_x - s, center_y, center_x + s, center_y, 1, r, g, b, a);
    canvas.drawLine(center_x, center_y - s, center_x, center_y + s, 1, r, g, b, a);
}
