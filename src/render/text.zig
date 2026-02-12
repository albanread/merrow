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

/// Cached glyph bitmap entry.
const CachedGlyph = struct {
    /// Pre-rendered alpha bitmap (one byte per pixel).
    bitmap: []u8,
    /// Width of the bitmap in pixels.
    w: i32,
    /// Height of the bitmap in pixels.
    h: i32,
    /// Horizontal offset from the glyph origin to the left edge of the bitmap.
    ix0: i32,
    /// Vertical offset from the baseline to the top edge of the bitmap.
    iy0: i32,
    /// Horizontal advance width in scaled pixels.
    advance: f32,
};

/// Key for the glyph cache: codepoint + quantised scale.
/// We quantise the scale to 1/64ths to avoid unbounded cache growth from
/// floating-point variations while still being precise enough for rendering.
const GlyphCacheKey = struct {
    codepoint: u21,
    /// Scale multiplied by 64 and truncated to integer.  This gives us
    /// sub-pixel precision (1/64 of a pixel) which is more than enough.
    scale_q: u32,
};

/// Maximum number of cached glyphs before we stop caching new ones.
/// 512 unique (codepoint, size) pairs is plenty for any diagram.
const MAX_CACHE_ENTRIES = 512;

/// Simple font for rendering text with glyph caching
pub const Font = struct {
    info: stbtt_fontinfo,
    font_data: []const u8,
    allocator: Allocator,

    // Glyph cache: maps (codepoint, quantised_scale) -> pre-rendered bitmap.
    // Using parallel arrays for keys and values since the cache is small and
    // linear scan is cache-friendly for < 512 entries.
    cache_keys: [MAX_CACHE_ENTRIES]GlyphCacheKey,
    cache_vals: [MAX_CACHE_ENTRIES]CachedGlyph,
    cache_count: usize,

    pub fn initFromMemory(allocator: Allocator, font_data: []const u8) !Font {
        var font = Font{
            .info = undefined,
            .font_data = font_data,
            .allocator = allocator,
            .cache_keys = undefined,
            .cache_vals = undefined,
            .cache_count = 0,
        };

        const result = stbtt_InitFont(&font.info, font_data.ptr, 0);
        if (result == 0) {
            return error.FontInitFailed;
        }

        return font;
    }

    pub fn deinit(self: *Font) void {
        // Free all cached glyph bitmaps
        for (0..self.cache_count) |i| {
            self.allocator.free(self.cache_vals[i].bitmap);
        }
        self.cache_count = 0;
    }

    /// Quantise a scale factor to an integer for cache lookup.
    inline fn quantiseScale(scale: f32) u32 {
        return @intFromFloat(@max(0.0, scale * 64.0));
    }

    /// Look up a cached glyph.  Returns the entry or null if not cached.
    fn getCachedGlyph(self: *const Font, codepoint: u8, scale_q: u32) ?*const CachedGlyph {
        const cp: u21 = codepoint;
        for (0..self.cache_count) |i| {
            if (self.cache_keys[i].codepoint == cp and self.cache_keys[i].scale_q == scale_q) {
                return &self.cache_vals[i];
            }
        }
        return null;
    }

    /// Rasterise a glyph and store it in the cache.  Returns a pointer to the
    /// cached entry, or null if the cache is full.
    fn cacheGlyph(self: *Font, codepoint: u8, scale: f32, scale_q: u32) !?*const CachedGlyph {
        if (self.cache_count >= MAX_CACHE_ENTRIES) return null;

        var advance_raw: c_int = 0;
        var lsb: c_int = 0;
        stbtt_GetCodepointHMetrics(&self.info, codepoint, &advance_raw, &lsb);

        var ix0: c_int = 0;
        var iy0: c_int = 0;
        var ix1: c_int = 0;
        var iy1: c_int = 0;
        stbtt_GetCodepointBitmapBox(&self.info, codepoint, scale, scale, &ix0, &iy0, &ix1, &iy1);

        const w = ix1 - ix0;
        const h = iy1 - iy0;

        var bitmap: []u8 = &.{};
        if (w > 0 and h > 0) {
            const bitmap_size = @as(usize, @intCast(w)) * @as(usize, @intCast(h));
            bitmap = try self.allocator.alloc(u8, bitmap_size);
            @memset(bitmap, 0);

            stbtt_MakeCodepointBitmap(
                &self.info,
                bitmap.ptr,
                w,
                h,
                w,
                scale,
                scale,
                codepoint,
            );
        } else {
            // Zero-size glyph (e.g. space).  Allocate a 0-length slice so
            // deinit can always call free.
            bitmap = try self.allocator.alloc(u8, 0);
        }

        const idx = self.cache_count;
        self.cache_keys[idx] = .{
            .codepoint = codepoint,
            .scale_q = scale_q,
        };
        self.cache_vals[idx] = .{
            .bitmap = bitmap,
            .w = w,
            .h = h,
            .ix0 = ix0,
            .iy0 = iy0,
            .advance = @as(f32, @floatFromInt(advance_raw)) * scale,
        };
        self.cache_count += 1;

        return &self.cache_vals[idx];
    }

    /// Get or create a cached glyph for the given codepoint at the given scale.
    fn getOrCacheGlyph(self: *Font, codepoint: u8, scale: f32, scale_q: u32) !?*const CachedGlyph {
        if (self.getCachedGlyph(codepoint, scale_q)) |cached| {
            return cached;
        }
        return try self.cacheGlyph(codepoint, scale, scale_q);
    }

    /// Get scale factor for desired pixel height
    pub fn getScale(self: *const Font, pixel_height: f32) f32 {
        return stbtt_ScaleForPixelHeight(&self.info, pixel_height);
    }

    /// Measure text width using cached advance widths where possible.
    pub fn measureText(self: *Font, text: []const u8, font_size: f32) f32 {
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

    /// Const-compatible measureText for callers that have *const Font.
    pub fn measureTextConst(self: *const Font, text: []const u8, font_size: f32) f32 {
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
            const w = self.measureTextConst(text[span.start..span.end], font_size_arg);
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
        self: *Font,
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

    /// Draw text onto canvas at position, using the glyph cache.
    ///
    /// `x` and `y` are in **logical** (unscaled) coordinates — the same
    /// coordinate space used by `Canvas.fillRect`, `Canvas.drawLine`, etc.
    /// `y` is the vertical *centre* of the text (not the baseline).
    /// The function applies the canvas `scale_factor` automatically so that
    /// text size and position match the rest of the drawing.
    pub fn drawText(
        self: *Font,
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
        const scale_q = quantiseScale(scale);

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

        // Pre-compute alpha factor for blending
        const a_factor = @as(f32, @floatFromInt(a));

        for (text) |ch| {
            // Try to use cached glyph
            if (try self.getOrCacheGlyph(ch, scale, scale_q)) |cached| {
                // Use cached bitmap
                if (cached.w > 0 and cached.h > 0) {
                    const glyph_x = @as(i32, @intFromFloat(@floor(cursor_x))) + cached.ix0;
                    const glyph_y = @as(i32, @intFromFloat(@floor(baseline_y))) + cached.iy0;

                    // Blit the cached bitmap onto the canvas
                    blitGlyphBitmap(canvas, cached.bitmap, cached.w, cached.h, glyph_x, glyph_y, r, g, b, a_factor);
                }
                cursor_x += cached.advance;
            } else {
                // Cache is full — fall back to uncached rendering
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
                    const bitmap_size = @as(usize, @intCast(w * h));
                    const bitmap = try self.allocator.alloc(u8, bitmap_size);
                    defer self.allocator.free(bitmap);
                    @memset(bitmap, 0);

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

                    const glyph_x = @as(i32, @intFromFloat(@floor(cursor_x))) + ix0;
                    const glyph_y = @as(i32, @intFromFloat(@floor(baseline_y))) + iy0;

                    blitGlyphBitmap(canvas, bitmap, w, h, glyph_x, glyph_y, r, g, b, a_factor);
                }

                cursor_x += @as(f32, @floatFromInt(advance)) * scale;
            }
        }
    }
};

/// Blit a glyph alpha bitmap onto the canvas with optimised row processing.
/// This is factored out so both cached and uncached paths use the same
/// optimised blitting code.
fn blitGlyphBitmap(
    canvas: *Canvas,
    bitmap: []const u8,
    w: i32,
    h: i32,
    glyph_x: i32,
    glyph_y: i32,
    r: u8,
    g: u8,
    b: u8,
    a_factor: f32,
) void {
    const canvas_w: i32 = @intCast(canvas.width);
    const canvas_h: i32 = @intCast(canvas.height);

    // Early reject: entire glyph is off-screen
    if (glyph_x + w <= 0 or glyph_x >= canvas_w or
        glyph_y + h <= 0 or glyph_y >= canvas_h) return;

    // Clamp row/column ranges to canvas bounds
    const row_start: i32 = @max(0, -glyph_y);
    const row_end: i32 = @min(h, canvas_h - glyph_y);
    const col_start: i32 = @max(0, -glyph_x);
    const col_end: i32 = @min(w, canvas_w - glyph_x);

    if (row_start >= row_end or col_start >= col_end) return;

    const stride = canvas.width * 4;
    const bw: usize = @intCast(w);

    // Pre-compute float colours
    const rf = @as(f32, @floatFromInt(r));
    const gf = @as(f32, @floatFromInt(g));
    const bf = @as(f32, @floatFromInt(b));

    var py = row_start;
    while (py < row_end) : (py += 1) {
        const screen_y: usize = @intCast(glyph_y + py);
        const row_base = screen_y * stride;
        const bitmap_row: usize = @intCast(py);
        const bitmap_row_offset = bitmap_row * bw;

        var px = col_start;
        while (px < col_end) : (px += 1) {
            const bitmap_idx = bitmap_row_offset + @as(usize, @intCast(px));
            const alpha_byte = bitmap[bitmap_idx];
            if (alpha_byte == 0) continue;

            const screen_x: usize = @intCast(glyph_x + px);
            const idx = row_base + screen_x * 4;

            const alpha_f = @as(f32, @floatFromInt(alpha_byte)) / 255.0;
            const final_alpha = a_factor * alpha_f / 255.0;
            const inv_alpha = 1.0 - final_alpha;

            canvas.pixels[idx + 0] = @intFromFloat(rf * final_alpha + @as(f32, @floatFromInt(canvas.pixels[idx + 0])) * inv_alpha);
            canvas.pixels[idx + 1] = @intFromFloat(gf * final_alpha + @as(f32, @floatFromInt(canvas.pixels[idx + 1])) * inv_alpha);
            canvas.pixels[idx + 2] = @intFromFloat(bf * final_alpha + @as(f32, @floatFromInt(canvas.pixels[idx + 2])) * inv_alpha);
            // Keep alpha at 255 (opaque background)
        }
    }
}

/// Embedded default font (DejaVu Sans subset - we'll need to embed this)
/// For now, returns error if no font data provided
pub fn getDefaultFont(allocator: Allocator) !Font {
    _ = allocator;
    return error.NoEmbeddedFont;
}
