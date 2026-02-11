const std = @import("std");
const Allocator = std.mem.Allocator;

/// SVG document writer that accumulates SVG elements into a buffer.
///
/// Usage:
///   var svg = try SvgWriter.init(allocator, 800, 600);
///   defer svg.deinit();
///   svg.rect(10, 20, 100, 50, ...);
///   svg.text(60, 45, "Hello", ...);
///   try svg.saveToFile("output.svg");
///
pub const SvgWriter = struct {
    buffer: std.ArrayListUnmanaged(u8),
    allocator: Allocator,
    width: f64,
    height: f64,
    /// Number of currently-open groups (for indentation).
    group_depth: usize,

    // -------------------------------------------------------------------
    // Marker bookkeeping — we define arrowhead markers lazily and
    // reference them by id.
    // -------------------------------------------------------------------
    marker_defs: std.ArrayListUnmanaged(u8),
    next_marker_id: usize,

    pub fn init(allocator: Allocator, width: f64, height: f64) !SvgWriter {
        return SvgWriter{
            .buffer = std.ArrayListUnmanaged(u8){},
            .allocator = allocator,
            .width = width,
            .height = height,
            .group_depth = 0,
            .marker_defs = std.ArrayListUnmanaged(u8){},
            .next_marker_id = 0,
        };
    }

    pub fn deinit(self: *SvgWriter) void {
        self.buffer.deinit(self.allocator);
        self.marker_defs.deinit(self.allocator);
    }

    // ===================================================================
    // Indentation helper
    // ===================================================================

    fn writeIndent(self: *SvgWriter) !void {
        const depth = self.group_depth + 1; // +1 for being inside <svg>
        for (0..depth) |_| {
            try self.buffer.appendSlice(self.allocator, "  ");
        }
    }

    // ===================================================================
    // Color / style formatting helpers
    // ===================================================================

    /// Write fill="..." stroke="..." stroke-width="..." attributes.
    fn writeStyleAttrs(
        self: *SvgWriter,
        fill: ?[4]u8,
        stroke: ?[4]u8,
        stroke_width: ?f64,
    ) !void {
        if (fill) |f| {
            try self.buffer.appendSlice(self.allocator, " fill=\"");
            try self.writeColor(f);
            try self.buffer.append(self.allocator, '"');
            if (f[3] < 255 and f[3] > 0) {
                try self.buffer.appendSlice(self.allocator, " fill-opacity=\"");
                try self.writeF64((@as(f64, @floatFromInt(f[3])) / 255.0), 2);
                try self.buffer.append(self.allocator, '"');
            }
        } else {
            try self.buffer.appendSlice(self.allocator, " fill=\"none\"");
        }

        if (stroke) |s| {
            try self.buffer.appendSlice(self.allocator, " stroke=\"");
            try self.writeColor(s);
            try self.buffer.append(self.allocator, '"');
            if (s[3] < 255 and s[3] > 0) {
                try self.buffer.appendSlice(self.allocator, " stroke-opacity=\"");
                try self.writeF64((@as(f64, @floatFromInt(s[3])) / 255.0), 2);
                try self.buffer.append(self.allocator, '"');
            }
        }

        if (stroke_width) |sw| {
            try self.buffer.appendSlice(self.allocator, " stroke-width=\"");
            try self.writeF64(sw, 1);
            try self.buffer.append(self.allocator, '"');
        }
    }

    fn writeColor(self: *SvgWriter, color: [4]u8) !void {
        if (color[3] == 0) {
            try self.buffer.appendSlice(self.allocator, "none");
            return;
        }
        var buf: [24]u8 = undefined;
        const len = (std.fmt.bufPrint(&buf, "rgb({d},{d},{d})", .{ color[0], color[1], color[2] }) catch return).len;
        try self.buffer.appendSlice(self.allocator, buf[0..len]);
    }

    fn writeF64(self: *SvgWriter, val: f64, decimals: u8) !void {
        var buf: [32]u8 = undefined;
        const len = switch (decimals) {
            0 => (std.fmt.bufPrint(&buf, "{d:.0}", .{val}) catch return).len,
            1 => (std.fmt.bufPrint(&buf, "{d:.1}", .{val}) catch return).len,
            2 => (std.fmt.bufPrint(&buf, "{d:.2}", .{val}) catch return).len,
            3 => (std.fmt.bufPrint(&buf, "{d:.3}", .{val}) catch return).len,
            else => (std.fmt.bufPrint(&buf, "{d:.2}", .{val}) catch return).len,
        };
        try self.buffer.appendSlice(self.allocator, buf[0..len]);
    }

    // ===================================================================
    // SVG element methods
    // ===================================================================

    /// Draw a rectangle. `rx`/`ry` for rounded corners (0 = sharp).
    pub fn rect(
        self: *SvgWriter,
        x: f64,
        y: f64,
        w: f64,
        h: f64,
        rx: f64,
        ry: f64,
        fill: ?[4]u8,
        stroke: ?[4]u8,
        stroke_width: f64,
    ) !void {
        try self.writeIndent();
        try self.buffer.appendSlice(self.allocator, "<rect x=\"");
        try self.writeF64(x, 1);
        try self.buffer.appendSlice(self.allocator, "\" y=\"");
        try self.writeF64(y, 1);
        try self.buffer.appendSlice(self.allocator, "\" width=\"");
        try self.writeF64(w, 1);
        try self.buffer.appendSlice(self.allocator, "\" height=\"");
        try self.writeF64(h, 1);
        try self.buffer.append(self.allocator, '"');
        if (rx > 0.01) {
            try self.buffer.appendSlice(self.allocator, " rx=\"");
            try self.writeF64(rx, 1);
            try self.buffer.append(self.allocator, '"');
        }
        if (ry > 0.01) {
            try self.buffer.appendSlice(self.allocator, " ry=\"");
            try self.writeF64(ry, 1);
            try self.buffer.append(self.allocator, '"');
        }
        try self.writeStyleAttrs(fill, stroke, stroke_width);
        try self.buffer.appendSlice(self.allocator, "/>\n");
    }

    /// Draw an ellipse.
    pub fn ellipse(
        self: *SvgWriter,
        cx: f64,
        cy: f64,
        rx: f64,
        ry: f64,
        fill: ?[4]u8,
        stroke: ?[4]u8,
        stroke_width: f64,
    ) !void {
        try self.writeIndent();
        try self.buffer.appendSlice(self.allocator, "<ellipse cx=\"");
        try self.writeF64(cx, 1);
        try self.buffer.appendSlice(self.allocator, "\" cy=\"");
        try self.writeF64(cy, 1);
        try self.buffer.appendSlice(self.allocator, "\" rx=\"");
        try self.writeF64(rx, 1);
        try self.buffer.appendSlice(self.allocator, "\" ry=\"");
        try self.writeF64(ry, 1);
        try self.buffer.append(self.allocator, '"');
        try self.writeStyleAttrs(fill, stroke, stroke_width);
        try self.buffer.appendSlice(self.allocator, "/>\n");
    }

    /// Draw a polygon from a list of (x, y) pairs.
    pub fn polygon(
        self: *SvgWriter,
        points: []const [2]f64,
        fill: ?[4]u8,
        stroke: ?[4]u8,
        stroke_width: f64,
    ) !void {
        if (points.len < 2) return;
        try self.writeIndent();
        try self.buffer.appendSlice(self.allocator, "<polygon points=\"");
        for (points, 0..) |pt, i| {
            if (i > 0) try self.buffer.append(self.allocator, ' ');
            try self.writeF64(pt[0], 1);
            try self.buffer.append(self.allocator, ',');
            try self.writeF64(pt[1], 1);
        }
        try self.buffer.append(self.allocator, '"');
        try self.writeStyleAttrs(fill, stroke, stroke_width);
        try self.buffer.appendSlice(self.allocator, "/>\n");
    }

    /// Draw a straight line.
    pub fn line(
        self: *SvgWriter,
        x1: f64,
        y1: f64,
        x2: f64,
        y2: f64,
        stroke_color: [4]u8,
        stroke_width: f64,
        dash_array: ?[]const u8,
    ) !void {
        try self.writeIndent();
        try self.buffer.appendSlice(self.allocator, "<line x1=\"");
        try self.writeF64(x1, 1);
        try self.buffer.appendSlice(self.allocator, "\" y1=\"");
        try self.writeF64(y1, 1);
        try self.buffer.appendSlice(self.allocator, "\" x2=\"");
        try self.writeF64(x2, 1);
        try self.buffer.appendSlice(self.allocator, "\" y2=\"");
        try self.writeF64(y2, 1);
        try self.buffer.append(self.allocator, '"');
        try self.writeStyleAttrs(null, stroke_color, stroke_width);
        if (dash_array) |da| {
            try self.buffer.appendSlice(self.allocator, " stroke-dasharray=\"");
            try self.buffer.appendSlice(self.allocator, da);
            try self.buffer.append(self.allocator, '"');
        }
        try self.buffer.appendSlice(self.allocator, "/>\n");
    }

    /// Draw a polyline (unfilled open path).
    pub fn polyline(
        self: *SvgWriter,
        points: []const [2]f64,
        stroke_color: [4]u8,
        stroke_width: f64,
        dash_array: ?[]const u8,
    ) !void {
        if (points.len < 2) return;
        try self.writeIndent();
        try self.buffer.appendSlice(self.allocator, "<polyline points=\"");
        for (points, 0..) |pt, i| {
            if (i > 0) try self.buffer.append(self.allocator, ' ');
            try self.writeF64(pt[0], 1);
            try self.buffer.append(self.allocator, ',');
            try self.writeF64(pt[1], 1);
        }
        try self.buffer.appendSlice(self.allocator, "\" fill=\"none\"");
        try self.buffer.appendSlice(self.allocator, " stroke=\"");
        try self.writeColor(stroke_color);
        try self.buffer.append(self.allocator, '"');
        if (stroke_color[3] < 255 and stroke_color[3] > 0) {
            try self.buffer.appendSlice(self.allocator, " stroke-opacity=\"");
            try self.writeF64((@as(f64, @floatFromInt(stroke_color[3])) / 255.0), 2);
            try self.buffer.append(self.allocator, '"');
        }
        try self.buffer.appendSlice(self.allocator, " stroke-width=\"");
        try self.writeF64(stroke_width, 1);
        try self.buffer.append(self.allocator, '"');
        if (dash_array) |da| {
            try self.buffer.appendSlice(self.allocator, " stroke-dasharray=\"");
            try self.buffer.appendSlice(self.allocator, da);
            try self.buffer.append(self.allocator, '"');
        }
        try self.buffer.appendSlice(self.allocator, " stroke-linecap=\"round\" stroke-linejoin=\"round\"/>\n");
    }

    /// Write a raw SVG `<path>` element with a pre-built `d` attribute.
    pub fn path(
        self: *SvgWriter,
        d: []const u8,
        fill: ?[4]u8,
        stroke: ?[4]u8,
        stroke_width: f64,
        dash_array: ?[]const u8,
    ) !void {
        try self.writeIndent();
        try self.buffer.appendSlice(self.allocator, "<path d=\"");
        try self.buffer.appendSlice(self.allocator, d);
        try self.buffer.append(self.allocator, '"');
        try self.writeStyleAttrs(fill, stroke, stroke_width);
        if (dash_array) |da| {
            try self.buffer.appendSlice(self.allocator, " stroke-dasharray=\"");
            try self.buffer.appendSlice(self.allocator, da);
            try self.buffer.append(self.allocator, '"');
        }
        try self.buffer.appendSlice(self.allocator, " stroke-linecap=\"round\" stroke-linejoin=\"round\"/>\n");
    }

    /// Build a cubic-bezier SVG path `d` string from Catmull-Rom control
    /// points.  Each span (P[i]..P[i+1]) is converted to a cubic bezier
    /// using the standard Catmull-Rom -> cubic conversion.
    ///
    /// Caller owns the returned slice and must free it with `allocator`.
    pub fn catmullRomToSVGPath(
        allocator: Allocator,
        waypoints: []const [2]f64,
    ) ![]u8 {
        var buf = std.ArrayListUnmanaged(u8){};
        errdefer buf.deinit(allocator);

        if (waypoints.len < 2) return buf.toOwnedSlice(allocator);

        // Move to the first point
        try buf.appendSlice(allocator, "M");
        try appendF64(&buf, allocator, waypoints[0][0], 2);
        try buf.append(allocator, ',');
        try appendF64(&buf, allocator, waypoints[0][1], 2);

        if (waypoints.len == 2) {
            // Straight line
            try buf.appendSlice(allocator, " L");
            try appendF64(&buf, allocator, waypoints[1][0], 2);
            try buf.append(allocator, ',');
            try appendF64(&buf, allocator, waypoints[1][1], 2);
            return buf.toOwnedSlice(allocator);
        }

        // For each span, convert Catmull-Rom to cubic bezier.
        // Given 4 Catmull-Rom points P0, P1, P2, P3, the cubic bezier
        // control points for the segment P1->P2 are:
        //   CP1 = P1 + (P2 - P0) / 6
        //   CP2 = P2 - (P3 - P1) / 6
        const n = waypoints.len;
        for (0..n - 1) |i| {
            const p0 = if (i == 0) waypoints[0] else waypoints[i - 1];
            const p1 = waypoints[i];
            const p2 = waypoints[i + 1];
            const p3 = if (i + 2 < n) waypoints[i + 2] else waypoints[n - 1];

            const cp1_x = p1[0] + (p2[0] - p0[0]) / 6.0;
            const cp1_y = p1[1] + (p2[1] - p0[1]) / 6.0;
            const cp2_x = p2[0] - (p3[0] - p1[0]) / 6.0;
            const cp2_y = p2[1] - (p3[1] - p1[1]) / 6.0;

            try buf.appendSlice(allocator, " C");
            try appendF64(&buf, allocator, cp1_x, 2);
            try buf.append(allocator, ',');
            try appendF64(&buf, allocator, cp1_y, 2);
            try buf.append(allocator, ' ');
            try appendF64(&buf, allocator, cp2_x, 2);
            try buf.append(allocator, ',');
            try appendF64(&buf, allocator, cp2_y, 2);
            try buf.append(allocator, ' ');
            try appendF64(&buf, allocator, p2[0], 2);
            try buf.append(allocator, ',');
            try appendF64(&buf, allocator, p2[1], 2);
        }

        return buf.toOwnedSlice(allocator);
    }

    /// Build a polyline SVG path `d` string from a densely-sampled
    /// polyline (e.g. output of tessellateSpline).
    ///
    /// If the polyline has only 2 points, emits a straight line.
    pub fn polylineToSVGPath(
        allocator: Allocator,
        points: []const [2]f64,
    ) ![]u8 {
        var buf = std.ArrayListUnmanaged(u8){};
        errdefer buf.deinit(allocator);

        if (points.len < 2) return buf.toOwnedSlice(allocator);

        try buf.appendSlice(allocator, "M");
        try appendF64(&buf, allocator, points[0][0], 2);
        try buf.append(allocator, ',');
        try appendF64(&buf, allocator, points[0][1], 2);

        if (points.len == 2) {
            try buf.appendSlice(allocator, " L");
            try appendF64(&buf, allocator, points[1][0], 2);
            try buf.append(allocator, ',');
            try appendF64(&buf, allocator, points[1][1], 2);
            return buf.toOwnedSlice(allocator);
        }

        // Emit line segments for the polyline
        for (points[1..]) |pt| {
            try buf.appendSlice(allocator, " L");
            try appendF64(&buf, allocator, pt[0], 2);
            try buf.append(allocator, ',');
            try appendF64(&buf, allocator, pt[1], 2);
        }

        return buf.toOwnedSlice(allocator);
    }

    /// Draw a single-line text element, horizontally centred at (cx, cy).
    pub fn textCentered(
        self: *SvgWriter,
        cx: f64,
        cy: f64,
        content: []const u8,
        font_size: f64,
        fill: [4]u8,
        font_family: []const u8,
    ) !void {
        try self.writeIndent();
        try self.buffer.appendSlice(self.allocator, "<text x=\"");
        try self.writeF64(cx, 1);
        try self.buffer.appendSlice(self.allocator, "\" y=\"");
        try self.writeF64(cy, 1);
        try self.buffer.appendSlice(self.allocator, "\" text-anchor=\"middle\" dominant-baseline=\"central\"");
        try self.buffer.appendSlice(self.allocator, " font-family=\"");
        try self.buffer.appendSlice(self.allocator, font_family);
        try self.buffer.appendSlice(self.allocator, "\" font-size=\"");
        try self.writeF64(font_size, 1);
        try self.buffer.append(self.allocator, '"');
        try self.buffer.appendSlice(self.allocator, " fill=\"");
        try self.writeColor(fill);
        try self.buffer.append(self.allocator, '"');
        if (fill[3] < 255 and fill[3] > 0) {
            try self.buffer.appendSlice(self.allocator, " fill-opacity=\"");
            try self.writeF64((@as(f64, @floatFromInt(fill[3])) / 255.0), 2);
            try self.buffer.append(self.allocator, '"');
        }
        try self.buffer.append(self.allocator, '>');
        try self.writeEscaped(content);
        try self.buffer.appendSlice(self.allocator, "</text>\n");
    }

    /// Draw a text element positioned at (x, y) with a given anchor.
    pub fn textAt(
        self: *SvgWriter,
        x: f64,
        y: f64,
        content: []const u8,
        font_size: f64,
        fill: [4]u8,
        font_family: []const u8,
        anchor: TextAnchor,
    ) !void {
        try self.writeIndent();
        try self.buffer.appendSlice(self.allocator, "<text x=\"");
        try self.writeF64(x, 1);
        try self.buffer.appendSlice(self.allocator, "\" y=\"");
        try self.writeF64(y, 1);
        try self.buffer.appendSlice(self.allocator, "\" text-anchor=\"");
        try self.buffer.appendSlice(self.allocator, switch (anchor) {
            .start => "start",
            .middle => "middle",
            .end => "end",
        });
        try self.buffer.appendSlice(self.allocator, "\" dominant-baseline=\"central\"");
        try self.buffer.appendSlice(self.allocator, " font-family=\"");
        try self.buffer.appendSlice(self.allocator, font_family);
        try self.buffer.appendSlice(self.allocator, "\" font-size=\"");
        try self.writeF64(font_size, 1);
        try self.buffer.append(self.allocator, '"');
        try self.buffer.appendSlice(self.allocator, " fill=\"");
        try self.writeColor(fill);
        try self.buffer.append(self.allocator, '"');
        if (fill[3] < 255 and fill[3] > 0) {
            try self.buffer.appendSlice(self.allocator, " fill-opacity=\"");
            try self.writeF64((@as(f64, @floatFromInt(fill[3])) / 255.0), 2);
            try self.buffer.append(self.allocator, '"');
        }
        try self.buffer.append(self.allocator, '>');
        try self.writeEscaped(content);
        try self.buffer.appendSlice(self.allocator, "</text>\n");
    }

    /// Draw multi-line wrapped text centred at (cx, cy).
    /// Each line is a separate `<tspan>`.
    pub fn textWrapped(
        self: *SvgWriter,
        cx: f64,
        cy: f64,
        lines: []const []const u8,
        font_size: f64,
        line_height: f64,
        fill: [4]u8,
        font_family: []const u8,
    ) !void {
        if (lines.len == 0) return;

        // Compute vertical starting position so the block is centred at cy.
        const total_h = @as(f64, @floatFromInt(lines.len)) * line_height;
        const start_y = cy - total_h / 2.0 + line_height / 2.0;

        try self.writeIndent();
        try self.buffer.appendSlice(self.allocator, "<text text-anchor=\"middle\"");
        try self.buffer.appendSlice(self.allocator, " font-family=\"");
        try self.buffer.appendSlice(self.allocator, font_family);
        try self.buffer.appendSlice(self.allocator, "\" font-size=\"");
        try self.writeF64(font_size, 1);
        try self.buffer.append(self.allocator, '"');
        try self.buffer.appendSlice(self.allocator, " fill=\"");
        try self.writeColor(fill);
        try self.buffer.append(self.allocator, '"');
        if (fill[3] < 255 and fill[3] > 0) {
            try self.buffer.appendSlice(self.allocator, " fill-opacity=\"");
            try self.writeF64((@as(f64, @floatFromInt(fill[3])) / 255.0), 2);
            try self.buffer.append(self.allocator, '"');
        }
        try self.buffer.appendSlice(self.allocator, ">\n");

        for (lines, 0..) |line_text, li| {
            try self.writeIndent();
            try self.buffer.appendSlice(self.allocator, "  <tspan x=\"");
            try self.writeF64(cx, 1);
            try self.buffer.appendSlice(self.allocator, "\" y=\"");
            try self.writeF64(start_y + @as(f64, @floatFromInt(li)) * line_height, 1);
            try self.buffer.appendSlice(self.allocator, "\" dominant-baseline=\"central\">");
            try self.writeEscaped(line_text);
            try self.buffer.appendSlice(self.allocator, "</tspan>\n");
        }

        try self.writeIndent();
        try self.buffer.appendSlice(self.allocator, "</text>\n");
    }

    /// Write an arrowhead triangle as a `<polygon>`.
    /// `from` is a point along the edge before the tip; `tip` is the
    /// point of the arrowhead.
    pub fn arrowhead(
        self: *SvgWriter,
        from_x: f64,
        from_y: f64,
        tip_x: f64,
        tip_y: f64,
        size: f64,
        fill: [4]u8,
    ) !void {
        const dx = tip_x - from_x;
        const dy = tip_y - from_y;
        const len = @sqrt(dx * dx + dy * dy);
        if (len < 0.001) return;

        const ux = dx / len;
        const uy = dy / len;
        const px = -uy;
        const py = ux;
        const half_w = size * 0.45;

        const p0 = [2]f64{ tip_x, tip_y };
        const p1 = [2]f64{ tip_x - ux * size + px * half_w, tip_y - uy * size + py * half_w };
        const p2 = [2]f64{ tip_x - ux * size - px * half_w, tip_y - uy * size - py * half_w };

        try self.polygon(&[_][2]f64{ p0, p1, p2 }, fill, null, 0);
    }

    // ===================================================================
    // Group / structure
    // ===================================================================

    /// Open an `<a>` hyperlink wrapper element.
    /// `url` is the href target, `tooltip` is optional hover text,
    /// `target` is the link target (e.g. "_blank").
    pub fn openLink(self: *SvgWriter, url: []const u8, tooltip: ?[]const u8, target: ?[]const u8) !void {
        try self.writeIndent();
        try self.buffer.appendSlice(self.allocator, "<a href=\"");
        try self.writeEscaped(url);
        try self.buffer.appendSlice(self.allocator, "\"");
        if (target) |t| {
            try self.buffer.appendSlice(self.allocator, " target=\"");
            try self.buffer.appendSlice(self.allocator, t);
            try self.buffer.appendSlice(self.allocator, "\"");
        }
        try self.buffer.appendSlice(self.allocator, ">\n");
        self.group_depth += 1;
        if (tooltip) |tt| {
            try self.writeIndent();
            try self.buffer.appendSlice(self.allocator, "<title>");
            try self.writeEscaped(tt);
            try self.buffer.appendSlice(self.allocator, "</title>\n");
        }
    }

    /// Close the most recent `<a>` hyperlink wrapper.
    pub fn closeLink(self: *SvgWriter) !void {
        if (self.group_depth > 0) self.group_depth -= 1;
        try self.writeIndent();
        try self.buffer.appendSlice(self.allocator, "</a>\n");
    }

    /// Open a `<g>` group with an optional class attribute.
    pub fn openGroup(self: *SvgWriter, class: ?[]const u8) !void {
        try self.writeIndent();
        if (class) |c| {
            try self.buffer.appendSlice(self.allocator, "<g class=\"");
            try self.buffer.appendSlice(self.allocator, c);
            try self.buffer.appendSlice(self.allocator, "\">\n");
        } else {
            try self.buffer.appendSlice(self.allocator, "<g>\n");
        }
        self.group_depth += 1;
    }

    /// Close the most recent `<g>` group.
    pub fn closeGroup(self: *SvgWriter) !void {
        if (self.group_depth > 0) self.group_depth -= 1;
        try self.writeIndent();
        try self.buffer.appendSlice(self.allocator, "</g>\n");
    }

    /// Write a raw XML comment.
    pub fn comment(self: *SvgWriter, text: []const u8) !void {
        try self.writeIndent();
        try self.buffer.appendSlice(self.allocator, "<!-- ");
        try self.buffer.appendSlice(self.allocator, text);
        try self.buffer.appendSlice(self.allocator, " -->\n");
    }

    // ===================================================================
    // Marker definitions (for arrowheads via <marker>)
    // ===================================================================

    /// Register an arrowhead marker and return its id string (e.g. "ah0").
    /// The marker is a filled triangle pointing in the direction of the
    /// path.  `color` sets the fill.  `size` controls the marker extents.
    pub fn addArrowMarker(self: *SvgWriter, color: [4]u8, size: f64) ![]const u8 {
        const id_num = self.next_marker_id;
        self.next_marker_id += 1;

        // Build "ah0", "ah1", ...
        var id_buf: [16]u8 = undefined;
        const id_len = (std.fmt.bufPrint(&id_buf, "ah{d}", .{id_num}) catch return "ah0").len;
        const id = try self.allocator.dupe(u8, id_buf[0..id_len]);

        var m = &self.marker_defs;
        try m.appendSlice(self.allocator, "    <marker id=\"");
        try m.appendSlice(self.allocator, id);
        try m.appendSlice(self.allocator, "\" markerWidth=\"");
        try appendF64(m, self.allocator, size, 1);
        try m.appendSlice(self.allocator, "\" markerHeight=\"");
        try appendF64(m, self.allocator, size, 1);
        try m.appendSlice(self.allocator, "\" refX=\"");
        try appendF64(m, self.allocator, size, 1);
        try m.appendSlice(self.allocator, "\" refY=\"");
        try appendF64(m, self.allocator, size / 2.0, 1);
        try m.appendSlice(self.allocator, "\" orient=\"auto\" markerUnits=\"userSpaceOnUse\">\n");
        try m.appendSlice(self.allocator, "      <polygon points=\"0,0 ");
        try appendF64(m, self.allocator, size, 1);
        try m.append(self.allocator, ',');
        try appendF64(m, self.allocator, size / 2.0, 1);
        try m.appendSlice(self.allocator, " 0,");
        try appendF64(m, self.allocator, size, 1);
        try m.appendSlice(self.allocator, "\" fill=\"");
        try appendColor(m, self.allocator, color);
        try m.appendSlice(self.allocator, "\"/>\n");
        try m.appendSlice(self.allocator, "    </marker>\n");

        return id;
    }

    // ===================================================================
    // Finalization / output
    // ===================================================================

    /// Assemble the complete SVG document and return it as an owned slice.
    /// Caller must free the returned slice with `allocator`.
    pub fn finalize(self: *SvgWriter) ![]u8 {
        var out = std.ArrayListUnmanaged(u8){};
        errdefer out.deinit(self.allocator);

        // XML declaration + SVG opening tag
        try out.appendSlice(self.allocator, "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n");
        try out.appendSlice(self.allocator, "<svg xmlns=\"http://www.w3.org/2000/svg\"");
        try out.appendSlice(self.allocator, " width=\"");
        try appendF64(&out, self.allocator, self.width, 0);
        try out.appendSlice(self.allocator, "\" height=\"");
        try appendF64(&out, self.allocator, self.height, 0);
        try out.appendSlice(self.allocator, "\" viewBox=\"0 0 ");
        try appendF64(&out, self.allocator, self.width, 0);
        try out.append(self.allocator, ' ');
        try appendF64(&out, self.allocator, self.height, 0);
        try out.appendSlice(self.allocator, "\">\n");

        // Embedded stylesheet
        try out.appendSlice(self.allocator, "  <style>\n");
        try out.appendSlice(self.allocator, "    text { font-family: 'Lato', 'Helvetica Neue', Arial, sans-serif; }\n");
        try out.appendSlice(self.allocator, "    .edge-path { fill: none; stroke-linecap: round; stroke-linejoin: round; }\n");
        try out.appendSlice(self.allocator, "  </style>\n");

        // Defs (markers, etc.)
        if (self.marker_defs.items.len > 0) {
            try out.appendSlice(self.allocator, "  <defs>\n");
            try out.appendSlice(self.allocator, self.marker_defs.items);
            try out.appendSlice(self.allocator, "  </defs>\n");
        }

        // Background
        try out.appendSlice(self.allocator, "  <rect width=\"100%\" height=\"100%\" fill=\"white\"/>\n");

        // Body elements
        try out.appendSlice(self.allocator, self.buffer.items);

        // Close SVG
        try out.appendSlice(self.allocator, "</svg>\n");

        return out.toOwnedSlice(self.allocator);
    }

    /// Assemble and write the SVG to a file.
    pub fn saveToFile(self: *SvgWriter, filename: []const u8) !void {
        const svg_data = try self.finalize();
        defer self.allocator.free(svg_data);

        const file = try std.fs.cwd().createFile(filename, .{});
        defer file.close();
        try file.writeAll(svg_data);
    }

    // ===================================================================
    // XML escaping
    // ===================================================================

    fn writeEscaped(self: *SvgWriter, text: []const u8) !void {
        for (text) |ch| {
            switch (ch) {
                '<' => try self.buffer.appendSlice(self.allocator, "&lt;"),
                '>' => try self.buffer.appendSlice(self.allocator, "&gt;"),
                '&' => try self.buffer.appendSlice(self.allocator, "&amp;"),
                '"' => try self.buffer.appendSlice(self.allocator, "&quot;"),
                '\'' => try self.buffer.appendSlice(self.allocator, "&#39;"),
                else => try self.buffer.append(self.allocator, ch),
            }
        }
    }
};

/// Text anchor values for SVG text-anchor attribute.
pub const TextAnchor = enum {
    start,
    middle,
    end,
};

// ===================================================================
// Free-standing helpers used by both SvgWriter methods and external code
// ===================================================================

/// Append a formatted f64 to an ArrayListUnmanaged(u8).
pub fn appendF64(buf: *std.ArrayListUnmanaged(u8), allocator: Allocator, val: f64, decimals: u8) !void {
    var tmp: [32]u8 = undefined;
    const len = switch (decimals) {
        0 => (std.fmt.bufPrint(&tmp, "{d:.0}", .{val}) catch return).len,
        1 => (std.fmt.bufPrint(&tmp, "{d:.1}", .{val}) catch return).len,
        2 => (std.fmt.bufPrint(&tmp, "{d:.2}", .{val}) catch return).len,
        3 => (std.fmt.bufPrint(&tmp, "{d:.3}", .{val}) catch return).len,
        else => (std.fmt.bufPrint(&tmp, "{d:.2}", .{val}) catch return).len,
    };
    try buf.appendSlice(allocator, tmp[0..len]);
}

fn appendColor(buf: *std.ArrayListUnmanaged(u8), allocator: Allocator, color: [4]u8) !void {
    var tmp: [24]u8 = undefined;
    const len = (std.fmt.bufPrint(&tmp, "rgb({d},{d},{d})", .{ color[0], color[1], color[2] }) catch return).len;
    try buf.appendSlice(allocator, tmp[0..len]);
}

// ===================================================================
// Tests
// ===================================================================

const testing = std.testing;

test "svg: init and finalize empty document" {
    var svg = try SvgWriter.init(testing.allocator, 100, 50);
    defer svg.deinit();

    const result = try svg.finalize();
    defer testing.allocator.free(result);

    try testing.expect(std.mem.indexOf(u8, result, "<svg") != null);
    try testing.expect(std.mem.indexOf(u8, result, "</svg>") != null);
    try testing.expect(std.mem.indexOf(u8, result, "width=\"100\"") != null);
    try testing.expect(std.mem.indexOf(u8, result, "height=\"50\"") != null);
}

test "svg: rect element" {
    var svg = try SvgWriter.init(testing.allocator, 200, 100);
    defer svg.deinit();

    try svg.rect(10, 20, 80, 40, 0, 0, [4]u8{ 255, 0, 0, 255 }, [4]u8{ 0, 0, 0, 255 }, 2);

    const result = try svg.finalize();
    defer testing.allocator.free(result);

    try testing.expect(std.mem.indexOf(u8, result, "<rect") != null);
    try testing.expect(std.mem.indexOf(u8, result, "x=\"10.0\"") != null);
    try testing.expect(std.mem.indexOf(u8, result, "fill=\"rgb(255,0,0)\"") != null);
}

test "svg: rect with rounded corners" {
    var svg = try SvgWriter.init(testing.allocator, 200, 100);
    defer svg.deinit();

    try svg.rect(10, 20, 80, 40, 5, 5, [4]u8{ 200, 200, 255, 255 }, [4]u8{ 50, 50, 100, 255 }, 1);

    const result = try svg.finalize();
    defer testing.allocator.free(result);

    try testing.expect(std.mem.indexOf(u8, result, "rx=\"5.0\"") != null);
    try testing.expect(std.mem.indexOf(u8, result, "ry=\"5.0\"") != null);
}

test "svg: ellipse element" {
    var svg = try SvgWriter.init(testing.allocator, 200, 100);
    defer svg.deinit();

    try svg.ellipse(50, 50, 30, 20, [4]u8{ 0, 255, 0, 255 }, [4]u8{ 0, 0, 0, 255 }, 1);

    const result = try svg.finalize();
    defer testing.allocator.free(result);

    try testing.expect(std.mem.indexOf(u8, result, "<ellipse") != null);
    try testing.expect(std.mem.indexOf(u8, result, "cx=\"50.0\"") != null);
}

test "svg: polygon element" {
    var svg = try SvgWriter.init(testing.allocator, 200, 200);
    defer svg.deinit();

    const pts = [_][2]f64{
        .{ 100, 10 },
        .{ 190, 100 },
        .{ 100, 190 },
        .{ 10, 100 },
    };
    try svg.polygon(&pts, [4]u8{ 255, 255, 0, 255 }, [4]u8{ 0, 0, 0, 255 }, 2);

    const result = try svg.finalize();
    defer testing.allocator.free(result);

    try testing.expect(std.mem.indexOf(u8, result, "<polygon") != null);
}

test "svg: text centered" {
    var svg = try SvgWriter.init(testing.allocator, 200, 100);
    defer svg.deinit();

    try svg.textCentered(100, 50, "Hello World", 14, [4]u8{ 0, 0, 0, 255 }, "Lato, sans-serif");

    const result = try svg.finalize();
    defer testing.allocator.free(result);

    try testing.expect(std.mem.indexOf(u8, result, "<text") != null);
    try testing.expect(std.mem.indexOf(u8, result, "Hello World") != null);
    try testing.expect(std.mem.indexOf(u8, result, "text-anchor=\"middle\"") != null);
}

test "svg: text escaping" {
    var svg = try SvgWriter.init(testing.allocator, 200, 100);
    defer svg.deinit();

    try svg.textCentered(100, 50, "A < B & C > D", 14, [4]u8{ 0, 0, 0, 255 }, "sans-serif");

    const result = try svg.finalize();
    defer testing.allocator.free(result);

    try testing.expect(std.mem.indexOf(u8, result, "&lt;") != null);
    try testing.expect(std.mem.indexOf(u8, result, "&amp;") != null);
    try testing.expect(std.mem.indexOf(u8, result, "&gt;") != null);
}

test "svg: line element" {
    var svg = try SvgWriter.init(testing.allocator, 200, 100);
    defer svg.deinit();

    try svg.line(10, 20, 190, 80, [4]u8{ 100, 100, 100, 255 }, 2, null);

    const result = try svg.finalize();
    defer testing.allocator.free(result);

    try testing.expect(std.mem.indexOf(u8, result, "<line") != null);
    try testing.expect(std.mem.indexOf(u8, result, "x1=\"10.0\"") != null);
}

test "svg: dashed line" {
    var svg = try SvgWriter.init(testing.allocator, 200, 100);
    defer svg.deinit();

    try svg.line(10, 20, 190, 80, [4]u8{ 100, 100, 100, 255 }, 2, "10,6");

    const result = try svg.finalize();
    defer testing.allocator.free(result);

    try testing.expect(std.mem.indexOf(u8, result, "stroke-dasharray=\"10,6\"") != null);
}

test "svg: arrowhead" {
    var svg = try SvgWriter.init(testing.allocator, 200, 100);
    defer svg.deinit();

    try svg.arrowhead(50, 50, 100, 50, 10, [4]u8{ 80, 80, 80, 255 });

    const result = try svg.finalize();
    defer testing.allocator.free(result);

    try testing.expect(std.mem.indexOf(u8, result, "<polygon") != null);
}

test "svg: groups" {
    var svg = try SvgWriter.init(testing.allocator, 200, 100);
    defer svg.deinit();

    try svg.openGroup("nodes");
    try svg.rect(10, 10, 50, 30, 0, 0, [4]u8{ 255, 0, 0, 255 }, null, 0);
    try svg.closeGroup();

    const result = try svg.finalize();
    defer testing.allocator.free(result);

    try testing.expect(std.mem.indexOf(u8, result, "<g class=\"nodes\">") != null);
    try testing.expect(std.mem.indexOf(u8, result, "</g>") != null);
}

test "svg: catmullRomToSVGPath straight line" {
    const pts = [_][2]f64{
        .{ 0, 0 },
        .{ 100, 100 },
    };
    const d = try SvgWriter.catmullRomToSVGPath(testing.allocator, &pts);
    defer testing.allocator.free(d);

    try testing.expect(std.mem.indexOf(u8, d, "M") != null);
    try testing.expect(std.mem.indexOf(u8, d, "L") != null);
}

test "svg: catmullRomToSVGPath curve" {
    const pts = [_][2]f64{
        .{ 0, 0 },
        .{ 50, 100 },
        .{ 100, 0 },
    };
    const d = try SvgWriter.catmullRomToSVGPath(testing.allocator, &pts);
    defer testing.allocator.free(d);

    try testing.expect(std.mem.indexOf(u8, d, "M") != null);
    try testing.expect(std.mem.indexOf(u8, d, "C") != null);
}

test "svg: textWrapped" {
    var svg = try SvgWriter.init(testing.allocator, 200, 100);
    defer svg.deinit();

    const lines = [_][]const u8{ "Hello", "World" };
    try svg.textWrapped(100, 50, &lines, 14, 18, [4]u8{ 0, 0, 0, 255 }, "sans-serif");

    const result = try svg.finalize();
    defer testing.allocator.free(result);

    try testing.expect(std.mem.indexOf(u8, result, "<tspan") != null);
    try testing.expect(std.mem.indexOf(u8, result, "Hello") != null);
    try testing.expect(std.mem.indexOf(u8, result, "World") != null);
}

test "svg: saveToFile" {
    var svg = try SvgWriter.init(testing.allocator, 100, 50);
    defer svg.deinit();

    try svg.rect(5, 5, 90, 40, 4, 4, [4]u8{ 200, 220, 255, 255 }, [4]u8{ 50, 100, 200, 255 }, 2);
    try svg.textCentered(50, 25, "Test", 12, [4]u8{ 0, 0, 0, 255 }, "sans-serif");

    // Save to a temp file and verify it exists
    const tmp_path = "/tmp/merrow_svg_test.svg";
    try svg.saveToFile(tmp_path);

    // Read it back and verify
    const data = try std.fs.cwd().readFileAlloc(testing.allocator, tmp_path, 64 * 1024);
    defer testing.allocator.free(data);
    try testing.expect(std.mem.indexOf(u8, data, "<svg") != null);
    try testing.expect(std.mem.indexOf(u8, data, "Test") != null);

    // Clean up
    try std.fs.cwd().deleteFile(tmp_path);
}

test "svg: polylineToSVGPath" {
    const pts = [_][2]f64{
        .{ 10, 20 },
        .{ 30, 40 },
        .{ 50, 20 },
    };
    const d = try SvgWriter.polylineToSVGPath(testing.allocator, &pts);
    defer testing.allocator.free(d);

    try testing.expect(std.mem.indexOf(u8, d, "M") != null);
    try testing.expect(std.mem.indexOf(u8, d, "L") != null);
}

test "svg: multiple elements compose" {
    var svg = try SvgWriter.init(testing.allocator, 400, 300);
    defer svg.deinit();

    // Subgraph background
    try svg.openGroup("subgraphs");
    try svg.rect(10, 10, 380, 280, 8, 8, [4]u8{ 245, 245, 250, 255 }, [4]u8{ 140, 140, 170, 255 }, 2);
    try svg.closeGroup();

    // Edges
    try svg.openGroup("edges");
    try svg.line(100, 50, 300, 50, [4]u8{ 80, 80, 80, 255 }, 2, null);
    try svg.arrowhead(280, 50, 300, 50, 10, [4]u8{ 80, 80, 80, 255 });
    try svg.closeGroup();

    // Nodes
    try svg.openGroup("nodes");
    try svg.rect(50, 30, 100, 40, 0, 0, [4]u8{ 240, 240, 250, 255 }, [4]u8{ 100, 100, 150, 255 }, 2);
    try svg.textCentered(100, 50, "Node A", 14, [4]u8{ 40, 40, 40, 255 }, "sans-serif");
    try svg.ellipse(300, 50, 50, 25, [4]u8{ 240, 240, 250, 255 }, [4]u8{ 100, 100, 150, 255 }, 2);
    try svg.textCentered(300, 50, "Node B", 14, [4]u8{ 40, 40, 40, 255 }, "sans-serif");
    try svg.closeGroup();

    const result = try svg.finalize();
    defer testing.allocator.free(result);

    // Verify structure
    try testing.expect(std.mem.indexOf(u8, result, "class=\"subgraphs\"") != null);
    try testing.expect(std.mem.indexOf(u8, result, "class=\"edges\"") != null);
    try testing.expect(std.mem.indexOf(u8, result, "class=\"nodes\"") != null);
    try testing.expect(std.mem.indexOf(u8, result, "Node A") != null);
    try testing.expect(std.mem.indexOf(u8, result, "Node B") != null);
}
