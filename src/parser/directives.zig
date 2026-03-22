//! Parses `%%` comment directives that configure canvas and font settings.
//!
//! Directives are standard mermaid comments (`%%`) with a `@` prefix keyword:
//!
//!   %% @canvas width=15cm height=10cm
//!   %% @font family=lato node=14 group=12 edge=11
//!
//! Each key=value pair is space-separated. Unknown keys are ignored.
//! Multiple directive comments can appear anywhere in the source.

const std = @import("std");

pub const FontFamily = enum {
    lato,
    segoe_ui,
    arial,
    consolas,

    pub fn fromString(s: []const u8) ?FontFamily {
        const map = .{
            .{ "lato", FontFamily.lato },
            .{ "segoe_ui", FontFamily.segoe_ui },
            .{ "segoe-ui", FontFamily.segoe_ui },
            .{ "segoeui", FontFamily.segoe_ui },
            .{ "arial", FontFamily.arial },
            .{ "consolas", FontFamily.consolas },
        };
        const lower = asciiLowerBuf(s) orelse return null;
        inline for (map) |entry| {
            if (std.mem.eql(u8, lower[0..s.len], entry[0])) return entry[1];
        }
        return null;
    }
};

/// Parsed directives from mermaid comment lines.
/// Fields are optional — `null` means the directive was not present.
pub const Directives = struct {
    canvas_width_cm: ?f64 = null,
    canvas_height_cm: ?f64 = null,
    font_family: ?FontFamily = null,
    node_font_size: ?f32 = null,
    group_font_size: ?f32 = null,
    edge_font_size: ?f32 = null,

    /// Returns true if any field was set by a directive.
    pub fn hasAny(self: Directives) bool {
        return self.canvas_width_cm != null or
            self.canvas_height_cm != null or
            self.font_family != null or
            self.node_font_size != null or
            self.group_font_size != null or
            self.edge_font_size != null;
    }
};

/// Scan mermaid source text and extract all `%% @canvas` and `%% @font` directives.
pub fn parse(source: []const u8) Directives {
    var result = Directives{};
    var offset: usize = 0;

    while (offset < source.len) {
        // Find start of next line
        const line_start = offset;
        const line_end = std.mem.indexOfScalar(u8, source[offset..], '\n') orelse source.len - offset;
        const line = std.mem.trim(u8, source[line_start .. line_start + line_end], " \t\r");
        offset = line_start + line_end + 1;

        // Must start with %%
        if (!std.mem.startsWith(u8, line, "%%")) continue;
        const after_pct = std.mem.trimLeft(u8, line[2..], " \t");

        if (std.mem.startsWith(u8, after_pct, "@canvas")) {
            parseCanvasDirective(after_pct["@canvas".len..], &result);
        } else if (std.mem.startsWith(u8, after_pct, "@font")) {
            parseFontDirective(after_pct["@font".len..], &result);
        }
    }

    return result;
}

fn parseCanvasDirective(body: []const u8, out: *Directives) void {
    var iter = std.mem.tokenizeAny(u8, body, " \t");
    while (iter.next()) |token| {
        if (parseKeyValue(token, "width")) |v| {
            out.canvas_width_cm = parseCmValue(v);
        } else if (parseKeyValue(token, "height")) |v| {
            out.canvas_height_cm = parseCmValue(v);
        }
    }
}

fn parseFontDirective(body: []const u8, out: *Directives) void {
    var iter = std.mem.tokenizeAny(u8, body, " \t");
    while (iter.next()) |token| {
        if (parseKeyValue(token, "family")) |v| {
            out.font_family = FontFamily.fromString(v);
        } else if (parseKeyValue(token, "node")) |v| {
            out.node_font_size = parseF32(v);
        } else if (parseKeyValue(token, "group")) |v| {
            out.group_font_size = parseF32(v);
        } else if (parseKeyValue(token, "edge")) |v| {
            out.edge_font_size = parseF32(v);
        }
    }
}

/// Extracts the value from "key=value", returning null if key doesn't match.
fn parseKeyValue(token: []const u8, key: []const u8) ?[]const u8 {
    const eq_pos = std.mem.indexOfScalar(u8, token, '=') orelse return null;
    if (eq_pos != key.len) return null;
    if (!std.mem.eql(u8, token[0..eq_pos], key)) return null;
    const val = token[eq_pos + 1 ..];
    return if (val.len > 0) val else null;
}

/// Parse a centimeter value, with optional "cm" suffix. E.g. "15", "15cm", "15.5cm".
fn parseCmValue(s: []const u8) ?f64 {
    const num_str = if (std.mem.endsWith(u8, s, "cm")) s[0 .. s.len - 2] else s;
    return std.fmt.parseFloat(f64, num_str) catch null;
}

fn parseF32(s: []const u8) ?f32 {
    return std.fmt.parseFloat(f32, s) catch null;
}

// Fixed-size buffer for case-insensitive comparison (max 32 chars).
const max_lower_len = 32;

fn asciiLowerBuf(s: []const u8) ?[max_lower_len]u8 {
    if (s.len > max_lower_len) return null;
    var buf: [max_lower_len]u8 = undefined;
    for (s, 0..) |c, i| {
        buf[i] = std.ascii.toLower(c);
    }
    return buf;
}

// --- Tests ---

test "parse empty source" {
    const d = parse("");
    try std.testing.expect(!d.hasAny());
}

test "parse canvas directive" {
    const d = parse("%% @canvas width=20cm height=12cm\nflowchart TD\n  A --> B\n");
    try std.testing.expectApproxEqAbs(@as(f64, 20.0), d.canvas_width_cm.?, 0.001);
    try std.testing.expectApproxEqAbs(@as(f64, 12.0), d.canvas_height_cm.?, 0.001);
}

test "parse canvas without cm suffix" {
    const d = parse("%% @canvas width=15 height=10\n");
    try std.testing.expectApproxEqAbs(@as(f64, 15.0), d.canvas_width_cm.?, 0.001);
    try std.testing.expectApproxEqAbs(@as(f64, 10.0), d.canvas_height_cm.?, 0.001);
}

test "parse font directive" {
    const d = parse("%% @font family=arial node=16 group=14 edge=12\n");
    try std.testing.expectEqual(FontFamily.arial, d.font_family.?);
    try std.testing.expectApproxEqAbs(@as(f32, 16.0), d.node_font_size.?, 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 14.0), d.group_font_size.?, 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 12.0), d.edge_font_size.?, 0.001);
}

test "parse both directives" {
    const source =
        \\%% @canvas width=25cm height=18cm
        \\%% @font family=consolas node=18
        \\flowchart LR
        \\  A --> B
    ;
    const d = parse(source);
    try std.testing.expectApproxEqAbs(@as(f64, 25.0), d.canvas_width_cm.?, 0.001);
    try std.testing.expectApproxEqAbs(@as(f64, 18.0), d.canvas_height_cm.?, 0.001);
    try std.testing.expectEqual(FontFamily.consolas, d.font_family.?);
    try std.testing.expectApproxEqAbs(@as(f32, 18.0), d.node_font_size.?, 0.001);
    try std.testing.expect(d.group_font_size == null);
    try std.testing.expect(d.edge_font_size == null);
}

test "parse directive mid-diagram" {
    const source =
        \\flowchart TD
        \\  A --> B
        \\%% @canvas width=30cm
        \\  B --> C
    ;
    const d = parse(source);
    try std.testing.expectApproxEqAbs(@as(f64, 30.0), d.canvas_width_cm.?, 0.001);
    try std.testing.expect(d.canvas_height_cm == null);
}

test "parse font family case insensitive" {
    const d = parse("%% @font family=Segoe_UI\n");
    try std.testing.expectEqual(FontFamily.segoe_ui, d.font_family.?);
}

test "ignore regular comments" {
    const d = parse("%% This is a regular comment\nflowchart TD\n  A --> B\n");
    try std.testing.expect(!d.hasAny());
}

test "partial canvas fields" {
    const d = parse("%% @canvas height=8cm\n");
    try std.testing.expect(d.canvas_width_cm == null);
    try std.testing.expectApproxEqAbs(@as(f64, 8.0), d.canvas_height_cm.?, 0.001);
}
