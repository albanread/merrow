const std = @import("std");
const Allocator = std.mem.Allocator;

/// High-quality RGBA canvas for rendering with antialiasing support
pub const Canvas = struct {
    width: usize,
    height: usize,
    pixels: []u8, // RGBA format: 4 bytes per pixel
    allocator: Allocator,
    scale_factor: f64, // For HD rendering (1.0, 2.0, 3.0, etc.)

    pub fn init(allocator: Allocator, width: usize, height: usize) !Canvas {
        return initWithScale(allocator, width, height, 1.0);
    }

    pub fn initWithScale(allocator: Allocator, width: usize, height: usize, scale: f64) !Canvas {
        const scaled_width = @as(usize, @intFromFloat(@as(f64, @floatFromInt(width)) * scale));
        const scaled_height = @as(usize, @intFromFloat(@as(f64, @floatFromInt(height)) * scale));
        const pixel_count = scaled_width * scaled_height * 4; // RGBA
        const pixels = try allocator.alloc(u8, pixel_count);

        // Initialize to white background
        @memset(pixels, 255);

        return Canvas{
            .width = scaled_width,
            .height = scaled_height,
            .pixels = pixels,
            .allocator = allocator,
            .scale_factor = scale,
        };
    }

    pub fn deinit(self: *Canvas) void {
        self.allocator.free(self.pixels);
    }

    /// Set pixel color at (x, y) with alpha blending
    pub fn setPixel(self: *Canvas, x: i32, y: i32, r: u8, g: u8, b: u8, a: u8) void {
        if (x < 0 or y < 0 or x >= @as(i32, @intCast(self.width)) or y >= @as(i32, @intCast(self.height))) {
            return; // Out of bounds
        }

        const ux = @as(usize, @intCast(x));
        const uy = @as(usize, @intCast(y));
        const idx = (uy * self.width + ux) * 4;

        if (a == 255) {
            // Fully opaque - just set directly
            self.pixels[idx + 0] = r;
            self.pixels[idx + 1] = g;
            self.pixels[idx + 2] = b;
            self.pixels[idx + 3] = a;
        } else {
            // Alpha blending
            const alpha = @as(f32, @floatFromInt(a)) / 255.0;
            const inv_alpha = 1.0 - alpha;

            self.pixels[idx + 0] = @intFromFloat(@as(f32, @floatFromInt(r)) * alpha + @as(f32, @floatFromInt(self.pixels[idx + 0])) * inv_alpha);
            self.pixels[idx + 1] = @intFromFloat(@as(f32, @floatFromInt(g)) * alpha + @as(f32, @floatFromInt(self.pixels[idx + 1])) * inv_alpha);
            self.pixels[idx + 2] = @intFromFloat(@as(f32, @floatFromInt(b)) * alpha + @as(f32, @floatFromInt(self.pixels[idx + 2])) * inv_alpha);
            self.pixels[idx + 3] = 255; // Keep background alpha at 255
        }
    }

    /// Set pixel with fractional alpha for antialiasing
    pub fn setPixelAA(self: *Canvas, x: i32, y: i32, r: u8, g: u8, b: u8, alpha: f64) void {
        const a = @as(u8, @intFromFloat(@min(255.0, @max(0.0, alpha * 255.0))));
        self.setPixel(x, y, r, g, b, a);
    }

    /// Fill entire canvas with color
    pub fn fill(self: *Canvas, r: u8, g: u8, b: u8, a: u8) void {
        var i: usize = 0;
        while (i < self.width * self.height) : (i += 1) {
            const idx = i * 4;
            self.pixels[idx + 0] = r;
            self.pixels[idx + 1] = g;
            self.pixels[idx + 2] = b;
            self.pixels[idx + 3] = a;
        }
    }

    /// Draw a filled rectangle
    pub fn fillRect(self: *Canvas, x: f64, y: f64, w: f64, h: f64, r: u8, g: u8, b: u8, a: u8) void {
        // Coordinates are already in scaled space (canvas dimensions are scaled)
        const x0 = @as(i32, @intFromFloat(@floor(x * self.scale_factor)));
        const y0 = @as(i32, @intFromFloat(@floor(y * self.scale_factor)));
        const x1 = @as(i32, @intFromFloat(@ceil((x + w) * self.scale_factor)));
        const y1 = @as(i32, @intFromFloat(@ceil((y + h) * self.scale_factor)));

        var py = y0;
        while (py < y1) : (py += 1) {
            var px = x0;
            while (px < x1) : (px += 1) {
                self.setPixel(px, py, r, g, b, a);
            }
        }
    }

    /// Draw a rectangle outline
    pub fn strokeRect(self: *Canvas, x: f64, y: f64, w: f64, h: f64, thickness: i32, r: u8, g: u8, b: u8, a: u8) void {
        // Coordinates are already in scaled space (canvas dimensions are scaled)
        const x0 = @as(i32, @intFromFloat(@floor(x * self.scale_factor)));
        const y0 = @as(i32, @intFromFloat(@floor(y * self.scale_factor)));
        const x1 = @as(i32, @intFromFloat(@ceil((x + w) * self.scale_factor)));
        const y1 = @as(i32, @intFromFloat(@ceil((y + h) * self.scale_factor)));
        const sthickness = @as(i32, @intFromFloat(@as(f64, @floatFromInt(thickness)) * self.scale_factor));

        // Top and bottom edges
        var t: i32 = 0;
        while (t < sthickness) : (t += 1) {
            var px = x0;
            while (px < x1) : (px += 1) {
                self.setPixel(px, y0 + t, r, g, b, a); // Top
                self.setPixel(px, y1 - 1 - t, r, g, b, a); // Bottom
            }
        }

        // Left and right edges
        t = 0;
        while (t < sthickness) : (t += 1) {
            var py = y0;
            while (py < y1) : (py += 1) {
                self.setPixel(x0 + t, py, r, g, b, a); // Left
                self.setPixel(x1 - 1 - t, py, r, g, b, a); // Right
            }
        }
    }

    /// Fill an ellipse centered at (cx, cy) with radii (rx, ry).
    pub fn fillEllipse(self: *Canvas, cx: f64, cy: f64, rx: f64, ry: f64, r: u8, g: u8, b: u8, a: u8) void {
        const scx = cx * self.scale_factor;
        const scy = cy * self.scale_factor;
        const srx = rx * self.scale_factor;
        const sry = ry * self.scale_factor;

        const iy_start: i32 = @intFromFloat(@floor(scy - sry));
        const iy_end: i32 = @intFromFloat(@ceil(scy + sry));
        var iy: i32 = iy_start;
        while (iy <= iy_end) : (iy += 1) {
            const dy = @as(f64, @floatFromInt(iy)) + 0.5 - scy;
            // Half-width at this scanline from ellipse equation
            const ratio_y = dy / sry;
            if (@abs(ratio_y) > 1.0) continue;
            const half_w = srx * @sqrt(1.0 - ratio_y * ratio_y);
            const ix_start: i32 = @intFromFloat(@floor(scx - half_w));
            const ix_end: i32 = @intFromFloat(@ceil(scx + half_w));
            var ix: i32 = ix_start;
            while (ix <= ix_end) : (ix += 1) {
                const dx = @as(f64, @floatFromInt(ix)) + 0.5 - scx;
                const ex = dx / srx;
                const ey = dy / sry;
                if (ex * ex + ey * ey <= 1.0) {
                    self.setPixel(ix, iy, r, g, b, a);
                }
            }
        }
    }

    /// Stroke (outline) an ellipse centered at (cx, cy) with radii (rx, ry).
    pub fn strokeEllipse(self: *Canvas, cx: f64, cy: f64, rx: f64, ry: f64, thickness: i32, r: u8, g: u8, b: u8, a: u8) void {
        const segs: usize = 48;
        const two_pi = std.math.pi * 2.0;
        var prev_x = cx + rx;
        var prev_y = cy;
        for (1..segs + 1) |s| {
            const t = @as(f64, @floatFromInt(s)) / @as(f64, @floatFromInt(segs));
            const angle = t * two_pi;
            const ax = cx + rx * @cos(angle);
            const ay = cy + ry * @sin(angle);
            self.drawLine(prev_x, prev_y, ax, ay, thickness, r, g, b, a);
            prev_x = ax;
            prev_y = ay;
        }
    }

    /// Fill a diamond (rhombus) centered at (cx, cy) with half-widths (hw, hh).
    /// The four vertices are at (cx, cy-hh), (cx+hw, cy), (cx, cy+hh), (cx-hw, cy).
    pub fn fillDiamond(self: *Canvas, cx: f64, cy: f64, hw: f64, hh: f64, r: u8, g: u8, b: u8, a: u8) void {
        const scx = cx * self.scale_factor;
        const scy = cy * self.scale_factor;
        const shw = hw * self.scale_factor;
        const shh = hh * self.scale_factor;

        const iy_start: i32 = @intFromFloat(@floor(scy - shh));
        const iy_end: i32 = @intFromFloat(@ceil(scy + shh));
        var iy: i32 = iy_start;
        while (iy <= iy_end) : (iy += 1) {
            const dy = @as(f64, @floatFromInt(iy)) + 0.5 - scy;
            // At this y, the diamond half-width is hw * (1 - |dy|/hh)
            const frac = @abs(dy) / shh;
            if (frac > 1.0) continue;
            const row_hw = shw * (1.0 - frac);
            const ix_start: i32 = @intFromFloat(@floor(scx - row_hw));
            const ix_end: i32 = @intFromFloat(@ceil(scx + row_hw));
            var ix: i32 = ix_start;
            while (ix <= ix_end) : (ix += 1) {
                self.setPixel(ix, iy, r, g, b, a);
            }
        }
    }

    /// Stroke (outline) a diamond centered at (cx, cy) with half-widths (hw, hh).
    pub fn strokeDiamond(self: *Canvas, cx: f64, cy: f64, hw: f64, hh: f64, thickness: i32, r: u8, g: u8, b: u8, a: u8) void {
        // Four vertices: top, right, bottom, left
        const top_x = cx;
        const top_y = cy - hh;
        const right_x = cx + hw;
        const right_y = cy;
        const bottom_x = cx;
        const bottom_y = cy + hh;
        const left_x = cx - hw;
        const left_y = cy;

        self.drawLine(top_x, top_y, right_x, right_y, thickness, r, g, b, a);
        self.drawLine(right_x, right_y, bottom_x, bottom_y, thickness, r, g, b, a);
        self.drawLine(bottom_x, bottom_y, left_x, left_y, thickness, r, g, b, a);
        self.drawLine(left_x, left_y, top_x, top_y, thickness, r, g, b, a);
    }

    /// Draw antialiased line using Xiaolin Wu's algorithm with thickness support
    pub fn drawLine(self: *Canvas, x0: f64, y0: f64, x1: f64, y1: f64, thickness: i32, r: u8, g: u8, b: u8, a: u8) void {
        // Scale coordinates by scale factor
        const sx0 = x0 * self.scale_factor;
        const sy0 = y0 * self.scale_factor;
        const sx1 = x1 * self.scale_factor;
        const sy1 = y1 * self.scale_factor;
        const sthick = @as(f64, @floatFromInt(thickness)) * self.scale_factor;

        if (sthick <= 1.5) {
            // Thin line - use single antialiased line
            self.drawLineAA(sx0, sy0, sx1, sy1, r, g, b, a);
        } else {
            // Thick line - draw multiple parallel lines
            const dx = sx1 - sx0;
            const dy = sy1 - sy0;
            const len = @sqrt(dx * dx + dy * dy);
            if (len < 0.001) return;

            // Perpendicular unit vector
            const px = -dy / len;
            const py = dx / len;

            // Draw parallel lines from -half_thick to +half_thick
            const half_thick = sthick / 2.0;
            const num_lines = @as(i32, @intFromFloat(sthick * 2.0)) + 1;
            const step = sthick / @as(f64, @floatFromInt(num_lines - 1));

            var i: i32 = 0;
            while (i < num_lines) : (i += 1) {
                const offset = -half_thick + @as(f64, @floatFromInt(i)) * step;
                const ox = offset * px;
                const oy = offset * py;
                self.drawLineAA(sx0 + ox, sy0 + oy, sx1 + ox, sy1 + oy, r, g, b, a);
            }
        }
    }

    /// Draw a dashed or dotted line between two points.
    ///
    /// `dash_len` is the length of each visible dash (in logical coords).
    /// `gap_len` is the length of each gap between dashes (in logical coords).
    /// The pattern repeats along the full length of the line.
    pub fn drawDashedLine(
        self: *Canvas,
        x0: f64,
        y0: f64,
        x1: f64,
        y1: f64,
        thickness: i32,
        r: u8,
        g: u8,
        b: u8,
        a: u8,
        dash_len: f64,
        gap_len: f64,
    ) void {
        const dx = x1 - x0;
        const dy = y1 - y0;
        const total_len = @sqrt(dx * dx + dy * dy);
        if (total_len < 0.001) return;

        // Unit direction vector
        const ux = dx / total_len;
        const uy = dy / total_len;

        const cycle = dash_len + gap_len;
        var dist: f64 = 0.0;

        while (dist < total_len) {
            const seg_start = dist;
            const seg_end = @min(dist + dash_len, total_len);

            self.drawLine(
                x0 + ux * seg_start,
                y0 + uy * seg_start,
                x0 + ux * seg_end,
                y0 + uy * seg_end,
                thickness,
                r,
                g,
                b,
                a,
            );

            dist += cycle;
        }
    }

    /// Draw antialiased line using Xiaolin Wu's algorithm
    fn drawLineAA(self: *Canvas, x0: f64, y0: f64, x1: f64, y1: f64, r: u8, g: u8, b: u8, a: u8) void {
        const steep = @abs(y1 - y0) > @abs(x1 - x0);

        var xa = x0;
        var ya = y0;
        var xb = x1;
        var yb = y1;

        if (steep) {
            // Swap x and y
            const tmp_xa = xa;
            xa = ya;
            ya = tmp_xa;
            const tmp_xb = xb;
            xb = yb;
            yb = tmp_xb;
        }

        if (xa > xb) {
            // Swap start and end
            const tmp_x = xa;
            xa = xb;
            xb = tmp_x;
            const tmp_y = ya;
            ya = yb;
            yb = tmp_y;
        }

        const dx = xb - xa;
        const dy = yb - ya;
        const gradient = if (dx < 0.001) 1.0 else dy / dx;

        // Handle first endpoint
        const xend = @round(xa);
        const yend = ya + gradient * (xend - xa);
        const xgap = 1.0 - fpart(xa + 0.5);
        const xpxl1 = xend;
        const ypxl1 = @floor(yend);

        if (steep) {
            self.setPixelAA(@intFromFloat(ypxl1), @intFromFloat(xpxl1), r, g, b, (1.0 - fpart(yend)) * xgap * (@as(f64, @floatFromInt(a)) / 255.0));
            self.setPixelAA(@intFromFloat(ypxl1 + 1.0), @intFromFloat(xpxl1), r, g, b, fpart(yend) * xgap * (@as(f64, @floatFromInt(a)) / 255.0));
        } else {
            self.setPixelAA(@intFromFloat(xpxl1), @intFromFloat(ypxl1), r, g, b, (1.0 - fpart(yend)) * xgap * (@as(f64, @floatFromInt(a)) / 255.0));
            self.setPixelAA(@intFromFloat(xpxl1), @intFromFloat(ypxl1 + 1.0), r, g, b, fpart(yend) * xgap * (@as(f64, @floatFromInt(a)) / 255.0));
        }

        var intery = yend + gradient;

        // Handle second endpoint
        const xend2 = @round(xb);
        const yend2 = yb + gradient * (xend2 - xb);
        const xgap2 = fpart(xb + 0.5);
        const xpxl2 = xend2;
        const ypxl2 = @floor(yend2);

        if (steep) {
            self.setPixelAA(@intFromFloat(ypxl2), @intFromFloat(xpxl2), r, g, b, (1.0 - fpart(yend2)) * xgap2 * (@as(f64, @floatFromInt(a)) / 255.0));
            self.setPixelAA(@intFromFloat(ypxl2 + 1.0), @intFromFloat(xpxl2), r, g, b, fpart(yend2) * xgap2 * (@as(f64, @floatFromInt(a)) / 255.0));
        } else {
            self.setPixelAA(@intFromFloat(xpxl2), @intFromFloat(ypxl2), r, g, b, (1.0 - fpart(yend2)) * xgap2 * (@as(f64, @floatFromInt(a)) / 255.0));
            self.setPixelAA(@intFromFloat(xpxl2), @intFromFloat(ypxl2 + 1.0), r, g, b, fpart(yend2) * xgap2 * (@as(f64, @floatFromInt(a)) / 255.0));
        }

        // Main loop
        var x = xpxl1 + 1.0;
        while (x < xpxl2) : (x += 1.0) {
            const y_floor = @floor(intery);
            const alpha_val = @as(f64, @floatFromInt(a)) / 255.0;

            if (steep) {
                self.setPixelAA(@intFromFloat(y_floor), @intFromFloat(x), r, g, b, (1.0 - fpart(intery)) * alpha_val);
                self.setPixelAA(@intFromFloat(y_floor + 1.0), @intFromFloat(x), r, g, b, fpart(intery) * alpha_val);
            } else {
                self.setPixelAA(@intFromFloat(x), @intFromFloat(y_floor), r, g, b, (1.0 - fpart(intery)) * alpha_val);
                self.setPixelAA(@intFromFloat(x), @intFromFloat(y_floor + 1.0), r, g, b, fpart(intery) * alpha_val);
            }

            intery += gradient;
        }
    }

    /// Save canvas to PNG file using stb_image_write
    pub fn saveToPNG(self: *Canvas, filename: []const u8) !void {
        // Add null terminator for C string
        const c_filename = try self.allocator.dupeZ(u8, filename);
        defer self.allocator.free(c_filename);

        const result = stbi_write_png(
            c_filename.ptr,
            @as(c_int, @intCast(self.width)),
            @as(c_int, @intCast(self.height)),
            4, // RGBA
            self.pixels.ptr,
            @as(c_int, @intCast(self.width * 4)),
        );

        if (result == 0) {
            return error.PNGWriteFailed;
        }
    }
};

/// Helper function: fractional part of x
fn fpart(x: f64) f64 {
    return x - @floor(x);
}

// C interface to stb_image_write
extern fn stbi_write_png(
    filename: [*c]const u8,
    w: c_int,
    h: c_int,
    comp: c_int,
    data: *const anyopaque,
    stride_in_bytes: c_int,
) c_int;

// Tests
const testing = std.testing;

test "canvas: create and destroy" {
    var canvas = try Canvas.init(testing.allocator, 100, 100);
    defer canvas.deinit();

    try testing.expectEqual(@as(usize, 100), canvas.width);
    try testing.expectEqual(@as(usize, 100), canvas.height);
    try testing.expectEqual(@as(usize, 100 * 100 * 4), canvas.pixels.len);
}

test "canvas: set pixel" {
    var canvas = try Canvas.init(testing.allocator, 10, 10);
    defer canvas.deinit();

    canvas.setPixel(5, 5, 255, 0, 0, 255);

    const idx = (5 * 10 + 5) * 4;
    try testing.expectEqual(@as(u8, 255), canvas.pixels[idx + 0]);
    try testing.expectEqual(@as(u8, 0), canvas.pixels[idx + 1]);
    try testing.expectEqual(@as(u8, 0), canvas.pixels[idx + 2]);
    try testing.expectEqual(@as(u8, 255), canvas.pixels[idx + 3]);
}

test "canvas: fill rect" {
    var canvas = try Canvas.init(testing.allocator, 100, 100);
    defer canvas.deinit();

    canvas.fill(255, 255, 255, 255); // White background
    canvas.fillRect(10, 10, 20, 20, 0, 0, 255, 255); // Blue rectangle

    // Check a pixel inside the rectangle
    const idx = (15 * 100 + 15) * 4;
    try testing.expectEqual(@as(u8, 0), canvas.pixels[idx + 0]);
    try testing.expectEqual(@as(u8, 0), canvas.pixels[idx + 1]);
    try testing.expectEqual(@as(u8, 255), canvas.pixels[idx + 2]);
}
