const std = @import("std");
const Allocator = std.mem.Allocator;
const Canvas = @import("canvas.zig").Canvas;

/// Result of word-wrapping a text string.  Each "line" is a byte-offset
/// range into the original text so we avoid allocating copies.
pub const WrappedText = struct {
    /// Slice of line descriptors (start, end byte offsets into source text).
    lines: []const LineSpan,
    /// Number of lines.
    line_count: usize,
    /// Maximum line width (logical pixels) across all lines.
    max_line_width: f32,
    /// Total height (logical pixels) = line_count * line_height.
    total_height: f32,
    /// Per-line height used during layout.
    line_height: f32,

    allocator: Allocator,

    pub fn deinit(self: *WrappedText) void {
        self.allocator.free(self.lines);
    }

    /// Get the text content of a line from the original source.
    pub fn lineText(self: *const WrappedText, line_idx: usize, source: []const u8) []const u8 {
        const span = self.lines[line_idx];
        return source[span.start..span.end];
    }
};

pub const LineSpan = struct {
    start: usize,
    end: usize,
};

// C interface to stb_truetype
const stbtt_fontinfo = extern struct {
    userdata: ?*anyopaque,
    data: [*c]const u8,
    fontstart: c_int,
    numGlyphs: c_int,
    loca: c_int,
    head: c_int,
    glyf: c_int,
    hhea: c_int,
    hmtx: c_int,
    kern: c_int,
    gpos: c_int,
    svg: c_int,
    index_map: c_int,
    indexToLocFormat: c_int,
    cff: extern struct {
        data: [*c]const u8,
        cursor: c_int,
        size: c_int,
    },
    charstrings: extern struct {
        data: [*c]const u8,
        cursor: c_int,
        size: c_int,
    },
    gsubrs: extern struct {
        data: [*c]const u8,
        cursor: c_int,
        size: c_int,
    },
    subrs: extern struct {
        data: [*c]const u8,
        cursor: c_int,
        size: c_int,
    },
    fontdicts: extern struct {
        data: [*c]const u8,
        cursor: c_int,
        size: c_int,
    },
    fdselect: extern struct {
        data: [*c]const u8,
        cursor: c_int,
        size: c_int,
    },
};

extern fn stbtt_InitFont(info: *stbtt_fontinfo, data: [*c]const u8, offset: c_int) c_int;
extern fn stbtt_ScaleForPixelHeight(info: *const stbtt_fontinfo, pixels: f32) f32;
extern fn stbtt_GetFontVMetrics(info: *const stbtt_fontinfo, ascent: *c_int, descent: *c_int, lineGap: *c_int) void;
extern fn stbtt_GetCodepointHMetrics(info: *const stbtt_fontinfo, codepoint: c_int, advanceWidth: *c_int, leftSideBearing: *c_int) void;
extern fn stbtt_GetCodepointBitmapBox(info: *const stbtt_fontinfo, codepoint: c_int, scale_x: f32, scale_y: f32, ix0: *c_int, iy0: *c_int, ix1: *c_int, iy1: *c_int) void;
extern fn stbtt_MakeCodepointBitmap(info: *const stbtt_fontinfo, output: [*c]u8, out_w: c_int, out_h: c_int, out_stride: c_int, scale_x: f32, scale_y: f32, codepoint: c_int) void;

/// Simple font for rendering text
pub const Font = struct {
    info: stbtt_fontinfo,
    font_data: []const u8,
    allocator: Allocator,

    pub fn initFromMemory(allocator: Allocator, font_data: []const u8) !Font {
        var font = Font{
            .info = undefined,
            .font_data = font_data,
            .allocator = allocator,
        };

        const result = stbtt_InitFont(&font.info, font_data.ptr, 0);
        if (result == 0) {
            return error.FontInitFailed;
        }

        return font;
    }

    pub fn deinit(self: *Font) void {
        _ = self;
        // Font data is owned by caller
    }

    /// Get scale factor for desired pixel height
    pub fn getScale(self: *const Font, pixel_height: f32) f32 {
        return stbtt_ScaleForPixelHeight(&self.info, pixel_height);
    }

    /// Measure text width
    pub fn measureText(self: *const Font, text: []const u8, font_size: f32) f32 {
        const scale = self.getScale(font_size);
        var width: f32 = 0;

        for (text) |ch| {
            var advance: c_int = 0;
            var lsb: c_int = 0;
            stbtt_GetCodepointHMetrics(&self.info, ch, &advance, &lsb);
            width += @as(f32, @floatFromInt(advance)) * scale;
        }

        return width;
    }

    /// Word-wrap `text` so that no line exceeds `max_width` logical pixels.
    ///
    /// Breaking rules:
    ///  1. Break at spaces (consume the space).
    ///  2. If a single word is wider than `max_width`, keep it on its own
    ///     line without breaking mid-word.
    ///  3. Explicit newlines (`\n`) always force a break.
    ///
    /// Returns a `WrappedText` that references byte ranges in `text`.
    /// Caller must call `deinit()` on the result.
    pub fn wrapText(self: *const Font, text: []const u8, font_size_arg: f32, max_width: f32) !WrappedText {
        const line_height: f32 = font_size_arg * 1.4;
        var spans = std.ArrayListUnmanaged(LineSpan){};
        defer spans.deinit(self.allocator);

        var line_start: usize = 0;
        var last_break: usize = 0; // position after last space that could be a break point
        var last_break_valid: bool = false;
        var cursor: f32 = 0;

        var i: usize = 0;
        while (i < text.len) : (i += 1) {
            const ch = text[i];

            // Explicit newline
            if (ch == '\n') {
                try spans.append(self.allocator, .{ .start = line_start, .end = i });
                line_start = i + 1;
                last_break_valid = false;
                cursor = 0;
                continue;
            }

            // Measure this character's advance
            var advance_raw: c_int = 0;
            var lsb: c_int = 0;
            stbtt_GetCodepointHMetrics(&self.info, ch, &advance_raw, &lsb);
            const scale = self.getScale(font_size_arg);
            const char_w = @as(f32, @floatFromInt(advance_raw)) * scale;

            // Space is a candidate break point
            if (ch == ' ') {
                last_break = i;
                last_break_valid = true;
            }

            cursor += char_w;

            // Check if we exceed max_width
            if (cursor > max_width and i > line_start) {
                if (last_break_valid and last_break > line_start) {
                    // Break at the last space
                    try spans.append(self.allocator, .{ .start = line_start, .end = last_break });
                    line_start = last_break + 1; // skip the space
                    // Re-measure from line_start to current i (inclusive)
                    cursor = 0;
                    var j: usize = line_start;
                    while (j <= i) : (j += 1) {
                        var adv2: c_int = 0;
                        var lsb2: c_int = 0;
                        stbtt_GetCodepointHMetrics(&self.info, text[j], &adv2, &lsb2);
                        cursor += @as(f32, @floatFromInt(adv2)) * scale;
                    }
                    last_break_valid = false;
                } else {
                    // No break point found — the word is wider than max_width.
                    // Keep it as a single line; it will overflow but that's
                    // better than breaking mid-word.  We'll break *before*
                    // the next word instead.
                }
            }
        }

        // Final line
        if (line_start <= text.len) {
            try spans.append(self.allocator, .{ .start = line_start, .end = text.len });
        }

        // Compute max line width
        var max_w: f32 = 0;
        for (spans.items) |span| {
            const w = self.measureText(text[span.start..span.end], font_size_arg);
            if (w > max_w) max_w = w;
        }

        const owned_spans = try self.allocator.dupe(LineSpan, spans.items);

        return WrappedText{
            .lines = owned_spans,
            .line_count = owned_spans.len,
            .max_line_width = max_w,
            .total_height = @as(f32, @floatFromInt(owned_spans.len)) * line_height,
            .line_height = line_height,
            .allocator = self.allocator,
        };
    }

    /// Convenience: measure the width and height a wrapped label would need.
    /// Returns .{ .width, .height } in logical pixels.
    pub fn measureWrappedText(self: *const Font, text: []const u8, font_size_arg: f32, max_width: f32) !struct { width: f32, height: f32 } {
        var wrapped = try self.wrapText(text, font_size_arg, max_width);
        defer wrapped.deinit();
        return .{
            .width = wrapped.max_line_width,
            .height = wrapped.total_height,
        };
    }

    /// Draw multi-line wrapped text onto the canvas.
    ///
    /// `cx` / `cy` are the **centre** of the text block in logical coords.
    /// Each line is horizontally centred around `cx`.
    pub fn drawWrappedText(
        self: *const Font,
        canvas: *Canvas,
        text: []const u8,
        cx: f32,
        cy: f32,
        font_size_arg: f32,
        max_width: f32,
        r: u8,
        g: u8,
        b: u8,
        a: u8,
    ) !void {
        var wrapped = try self.wrapText(text, font_size_arg, max_width);
        defer wrapped.deinit();

        if (wrapped.line_count == 0) return;

        // Vertical start so the block is centred around cy
        const block_top = cy - wrapped.total_height / 2.0;

        for (0..wrapped.line_count) |li| {
            const line_text = wrapped.lineText(li, text);
            if (line_text.len == 0) continue;

            const tw = self.measureText(line_text, font_size_arg);
            const lx = cx - tw / 2.0;
            // y centre of this line
            const ly = block_top + (@as(f32, @floatFromInt(li)) + 0.5) * wrapped.line_height;

            try self.drawText(canvas, line_text, lx, ly, font_size_arg, r, g, b, a);
        }
    }

    /// Draw text onto canvas at position.
    ///
    /// `x` and `y` are in **logical** (unscaled) coordinates — the same
    /// coordinate space used by `Canvas.fillRect`, `Canvas.drawLine`, etc.
    /// `y` is the vertical *centre* of the text (not the baseline).
    /// The function applies the canvas `scale_factor` automatically so that
    /// text size and position match the rest of the drawing.
    pub fn drawText(
        self: *const Font,
        canvas: *Canvas,
        text: []const u8,
        x: f32,
        y: f32,
        font_size: f32,
        r: u8,
        g: u8,
        b: u8,
        a: u8,
    ) !void {
        // Scale the font size to match the canvas resolution, just like
        // fillRect / drawLine scale their coordinates.
        const sf: f32 = @floatCast(canvas.scale_factor);
        const scaled_font_size = font_size * sf;
        const scale = self.getScale(scaled_font_size);

        // Compute font vertical metrics so we can centre the text
        // vertically around the supplied `y`.
        var ascent_raw: c_int = 0;
        var descent_raw: c_int = 0;
        var line_gap_raw: c_int = 0;
        stbtt_GetFontVMetrics(&self.info, &ascent_raw, &descent_raw, &line_gap_raw);

        const ascent = @as(f32, @floatFromInt(ascent_raw)) * scale;
        const descent = @as(f32, @floatFromInt(descent_raw)) * scale; // negative
        const text_height = ascent - descent; // total em height

        // The baseline Y in *scaled* (pixel) space, positioned so that the
        // text is vertically centred around logical `y`.
        const baseline_y = y * sf - text_height / 2.0 + ascent;

        // Start cursor at scaled X position.
        var cursor_x = x * sf;

        for (text) |ch| {
            var advance: c_int = 0;
            var lsb: c_int = 0;
            stbtt_GetCodepointHMetrics(&self.info, ch, &advance, &lsb);

            var ix0: c_int = 0;
            var iy0: c_int = 0;
            var ix1: c_int = 0;
            var iy1: c_int = 0;
            stbtt_GetCodepointBitmapBox(&self.info, ch, scale, scale, &ix0, &iy0, &ix1, &iy1);

            const w = ix1 - ix0;
            const h = iy1 - iy0;

            if (w > 0 and h > 0) {
                // Allocate bitmap for glyph
                const bitmap_size = @as(usize, @intCast(w * h));
                const bitmap = try self.allocator.alloc(u8, bitmap_size);
                defer self.allocator.free(bitmap);
                @memset(bitmap, 0);

                // Render glyph at the scaled size
                stbtt_MakeCodepointBitmap(
                    &self.info,
                    bitmap.ptr,
                    w,
                    h,
                    w,
                    scale,
                    scale,
                    ch,
                );

                // Place glyph relative to the baseline in scaled pixel space
                const glyph_x = @as(i32, @intFromFloat(@floor(cursor_x))) + ix0;
                const glyph_y = @as(i32, @intFromFloat(@floor(baseline_y))) + iy0;

                var py: i32 = 0;
                while (py < h) : (py += 1) {
                    var px: i32 = 0;
                    while (px < w) : (px += 1) {
                        const bitmap_idx = @as(usize, @intCast(py * w + px));
                        const alpha = bitmap[bitmap_idx];

                        if (alpha > 0) {
                            const screen_x = glyph_x + px;
                            const screen_y = glyph_y + py;

                            // Alpha blend
                            const alpha_f = @as(f32, @floatFromInt(alpha)) / 255.0;
                            const final_a = @as(u8, @intFromFloat(@as(f32, @floatFromInt(a)) * alpha_f));

                            canvas.setPixel(screen_x, screen_y, r, g, b, final_a);
                        }
                    }
                }
            }

            cursor_x += @as(f32, @floatFromInt(advance)) * scale;
        }
    }
};

/// Embedded default font (DejaVu Sans subset - we'll need to embed this)
/// For now, returns error if no font data provided
pub fn getDefaultFont(allocator: Allocator) !Font {
    _ = allocator;
    return error.NoEmbeddedFont;
}
