//! Pie chart parser for Mermaid `pie` syntax.
//!
//! Supports the following grammar:
//!
//!   pie [showData] [title <text>]
//!       "<label>" : <value>
//!       "<label>" : <value>
//!       ...
//!
//! Also handles:
//!   - `title <text>` on its own line
//!   - `%%` comments
//!   - `accTitle: <text>` (parsed but ignored — no accessibility model yet)
//!   - `accDescr: <text>` and `accDescr { ... }` (parsed but ignored)
//!   - `%%{init: ...}%%` directives (skipped)

const std = @import("std");
const PieData = @import("model.zig").PieData;

pub const ParseError = error{
    InvalidSyntax,
    InvalidNumber,
    NegativeValue,
    OutOfMemory,
    Overflow,
};

/// Parse a complete Mermaid pie chart source string into a `PieData`.
/// Caller owns the returned `PieData` and must call `.deinit()`.
pub fn parse(allocator: std.mem.Allocator, source: []const u8) ParseError!PieData {
    var pie = PieData.init(allocator);
    errdefer pie.deinit();

    var line_iter = LineIterator.init(source);
    var header_seen = false;
    var in_multiline_descr = false;

    while (line_iter.next()) |raw_line| {
        const line = trim(raw_line);

        // Skip empty lines.
        if (line.len == 0) continue;

        // Skip `%%{init: ...}%%` directives (may span one line).
        if (startsWith(line, "%%{")) continue;

        // Skip `%%` comments.
        if (startsWith(line, "%%")) continue;

        // Handle multiline accDescr { ... } block.
        if (in_multiline_descr) {
            if (std.mem.indexOf(u8, line, "}") != null) {
                in_multiline_descr = false;
            }
            continue;
        }

        // ── Header ──────────────────────────────────────────────
        if (!header_seen) {
            if (startsWithCaseInsensitive(line, "pie")) {
                header_seen = true;
                // Parse optional `showData` and/or `title` on the header line.
                var rest = line[3..]; // skip "pie"
                rest = trim(rest);

                // Check for showData
                if (startsWithCaseInsensitive(rest, "showData") or startsWithCaseInsensitive(rest, "showdata")) {
                    pie.show_data = true;
                    rest = trim(rest[8..]);
                }

                // Check for inline title: `pie title Foo` or `pie showData title Foo`
                if (startsWithCaseInsensitive(rest, "title")) {
                    const title_text = trim(rest[5..]);
                    if (title_text.len > 0) {
                        try pie.setTitle(title_text);
                    }
                }
                continue;
            }
            // If we haven't seen the header yet, skip any preamble lines.
            continue;
        }

        // ── Body (after header) ─────────────────────────────────

        // accTitle: <text>
        if (startsWithCaseInsensitive(line, "accTitle")) {
            // Parsed but ignored (no accessibility model).
            continue;
        }

        // accDescr { ... } (multiline) or accDescr: <text>
        if (startsWithCaseInsensitive(line, "accDescr")) {
            if (std.mem.indexOf(u8, line, "{") != null) {
                in_multiline_descr = true;
            }
            continue;
        }

        // title <text> on its own line
        if (startsWithCaseInsensitive(line, "title")) {
            const title_text = trim(line[5..]);
            if (title_text.len > 0) {
                try pie.setTitle(title_text);
            }
            continue;
        }

        // ── Section line: "<label>" : <value> ───────────────────
        if (parseSectionLine(line)) |result| {
            try pie.addSection(result.label, result.value);
            continue;
        }

        // Unknown lines are silently ignored (lenient parsing, like mermaid.js).
    }

    return pie;
}

// -----------------------------------------------------------------------
// Section line parser
// -----------------------------------------------------------------------

const SectionResult = struct {
    label: []const u8,
    value: f64,
};

/// Try to parse a line matching `"<label>" : <value>`.
/// Returns null if the line doesn't match the pattern.
fn parseSectionLine(line: []const u8) ?SectionResult {
    var pos: usize = 0;

    // Skip leading whitespace (already trimmed, but be safe).
    while (pos < line.len and isWhitespace(line[pos])) pos += 1;

    // Expect opening double-quote.
    if (pos >= line.len or line[pos] != '"') return null;
    pos += 1; // skip opening quote

    // Find closing double-quote.
    const label_start = pos;
    while (pos < line.len and line[pos] != '"') pos += 1;
    if (pos >= line.len) return null; // no closing quote
    const label = line[label_start..pos];
    pos += 1; // skip closing quote

    // Skip whitespace.
    while (pos < line.len and isWhitespace(line[pos])) pos += 1;

    // Expect colon.
    if (pos >= line.len or line[pos] != ':') return null;
    pos += 1;

    // Skip whitespace.
    while (pos < line.len and isWhitespace(line[pos])) pos += 1;

    // Parse numeric value (possibly negative, possibly decimal).
    const value_start = pos;
    if (pos < line.len and line[pos] == '-') pos += 1; // optional sign
    var has_digit = false;
    while (pos < line.len and line[pos] >= '0' and line[pos] <= '9') {
        has_digit = true;
        pos += 1;
    }
    if (pos < line.len and line[pos] == '.') {
        pos += 1;
        while (pos < line.len and line[pos] >= '0' and line[pos] <= '9') {
            has_digit = true;
            pos += 1;
        }
    }
    if (!has_digit) return null;

    const value_str = line[value_start..pos];
    const value = std.fmt.parseFloat(f64, value_str) catch return null;

    return .{ .label = label, .value = value };
}

// -----------------------------------------------------------------------
// Diagram type detection
// -----------------------------------------------------------------------

/// Returns true if `source` starts with the `pie` keyword (after optional
/// leading whitespace / directives).
pub fn isPieDiagram(source: []const u8) bool {
    var i: usize = 0;

    // Skip leading whitespace.
    while (i < source.len and isWhitespace(source[i])) i += 1;

    // Skip %%{init: ...}%% directive on the first line if present.
    if (i + 3 <= source.len and std.mem.eql(u8, source[i .. i + 3], "%%{")) {
        // Find the end of the directive.
        while (i < source.len and source[i] != '\n') i += 1;
        // Skip newline + whitespace.
        while (i < source.len and isWhitespace(source[i])) i += 1;
    }

    // Check for "pie" keyword (case-insensitive).
    if (i + 3 > source.len) return false;
    const word = source[i .. i + 3];
    if (!eqlIgnoreCase(word, "pie")) return false;

    // Make sure it's the full keyword (followed by whitespace, EOL, or EOF).
    if (i + 3 < source.len) {
        const next = source[i + 3];
        if (next != ' ' and next != '\t' and next != '\r' and next != '\n') return false;
    }

    return true;
}

// -----------------------------------------------------------------------
// Utility helpers
// -----------------------------------------------------------------------

const LineIterator = struct {
    source: []const u8,
    pos: usize,

    fn init(source: []const u8) LineIterator {
        return .{ .source = source, .pos = 0 };
    }

    fn next(self: *LineIterator) ?[]const u8 {
        if (self.pos >= self.source.len) return null;
        const start = self.pos;
        while (self.pos < self.source.len and self.source[self.pos] != '\n') {
            self.pos += 1;
        }
        const end = self.pos;
        if (self.pos < self.source.len) self.pos += 1; // skip '\n'
        // Strip trailing \r for Windows line endings.
        const line_end = if (end > start and self.source[end - 1] == '\r') end - 1 else end;
        return self.source[start..line_end];
    }
};

fn isWhitespace(c: u8) bool {
    return c == ' ' or c == '\t' or c == '\r' or c == '\n';
}

fn trim(s: []const u8) []const u8 {
    var start: usize = 0;
    while (start < s.len and isWhitespace(s[start])) start += 1;
    var end = s.len;
    while (end > start and isWhitespace(s[end - 1])) end -= 1;
    return s[start..end];
}

fn startsWith(haystack: []const u8, prefix: []const u8) bool {
    if (haystack.len < prefix.len) return false;
    return std.mem.eql(u8, haystack[0..prefix.len], prefix);
}

fn startsWithCaseInsensitive(haystack: []const u8, prefix: []const u8) bool {
    if (haystack.len < prefix.len) return false;
    return eqlIgnoreCase(haystack[0..prefix.len], prefix);
}

fn eqlIgnoreCase(a: []const u8, b: []const u8) bool {
    if (a.len != b.len) return false;
    for (a, b) |ca, cb| {
        if (toLower(ca) != toLower(cb)) return false;
    }
    return true;
}

fn toLower(c: u8) u8 {
    if (c >= 'A' and c <= 'Z') return c + 32;
    return c;
}

// -----------------------------------------------------------------------
// Tests
// -----------------------------------------------------------------------

test "pie parser: simple pie" {
    const allocator = std.testing.allocator;
    var pie = try parse(allocator,
        \\pie
        \\    "Dogs" : 40
        \\    "Cats" : 35
        \\    "Birds" : 25
    );
    defer pie.deinit();

    try std.testing.expectEqual(@as(usize, 3), pie.sectionCount());
    try std.testing.expectEqualStrings("Dogs", pie.sections.items[0].label);
    try std.testing.expectApproxEqAbs(@as(f64, 40.0), pie.sections.items[0].value, 0.001);
    try std.testing.expectEqualStrings("Cats", pie.sections.items[1].label);
    try std.testing.expectApproxEqAbs(@as(f64, 35.0), pie.sections.items[1].value, 0.001);
    try std.testing.expectEqualStrings("Birds", pie.sections.items[2].label);
    try std.testing.expectApproxEqAbs(@as(f64, 25.0), pie.sections.items[2].value, 0.001);
}

test "pie parser: pie with title" {
    const allocator = std.testing.allocator;
    var pie = try parse(allocator,
        \\pie title My Favourite Pets
        \\    "Dogs" : 60
        \\    "Cats" : 40
    );
    defer pie.deinit();

    try std.testing.expect(pie.title != null);
    try std.testing.expectEqualStrings("My Favourite Pets", pie.title.?);
    try std.testing.expectEqual(@as(usize, 2), pie.sectionCount());
}

test "pie parser: pie with showData" {
    const allocator = std.testing.allocator;
    var pie = try parse(allocator,
        \\pie showData
        \\    "A" : 10
        \\    "B" : 20
    );
    defer pie.deinit();

    try std.testing.expect(pie.show_data);
    try std.testing.expectEqual(@as(usize, 2), pie.sectionCount());
}

test "pie parser: pie with showData and title" {
    const allocator = std.testing.allocator;
    var pie = try parse(allocator,
        \\pie showData title Cool Chart
        \\    "X" : 50
        \\    "Y" : 50
    );
    defer pie.deinit();

    try std.testing.expect(pie.show_data);
    try std.testing.expect(pie.title != null);
    try std.testing.expectEqualStrings("Cool Chart", pie.title.?);
}

test "pie parser: comments are ignored" {
    const allocator = std.testing.allocator;
    var pie = try parse(allocator,
        \\pie
        \\    %% this is a comment
        \\    "A" : 100
    );
    defer pie.deinit();

    try std.testing.expectEqual(@as(usize, 1), pie.sectionCount());
}

test "pie parser: decimal values" {
    const allocator = std.testing.allocator;
    var pie = try parse(allocator,
        \\pie
        \\    "A" : 60.67
        \\    "B" : 39.33
    );
    defer pie.deinit();

    try std.testing.expectApproxEqAbs(@as(f64, 60.67), pie.sections.items[0].value, 0.001);
    try std.testing.expectApproxEqAbs(@as(f64, 39.33), pie.sections.items[1].value, 0.001);
}

test "pie parser: negative value rejected" {
    const allocator = std.testing.allocator;
    const result = parse(allocator,
        \\pie
        \\    "Bad" : -10
    );
    try std.testing.expectError(error.NegativeValue, result);
}

test "pie parser: zero value accepted" {
    const allocator = std.testing.allocator;
    var pie = try parse(allocator,
        \\pie
        \\    "Zero" : 0
        \\    "Something" : 42
    );
    defer pie.deinit();

    try std.testing.expectApproxEqAbs(@as(f64, 0.0), pie.sections.items[0].value, 0.001);
}

test "pie parser: duplicate labels keep first" {
    const allocator = std.testing.allocator;
    var pie = try parse(allocator,
        \\pie
        \\    "A" : 10
        \\    "A" : 99
    );
    defer pie.deinit();

    try std.testing.expectEqual(@as(usize, 1), pie.sectionCount());
    try std.testing.expectApproxEqAbs(@as(f64, 10.0), pie.sections.items[0].value, 0.001);
}

test "pie parser: title on separate line" {
    const allocator = std.testing.allocator;
    var pie = try parse(allocator,
        \\pie
        \\    title A Separate Title
        \\    "X" : 100
    );
    defer pie.deinit();

    try std.testing.expect(pie.title != null);
    try std.testing.expectEqualStrings("A Separate Title", pie.title.?);
}

test "pie parser: isPieDiagram detection" {
    try std.testing.expect(isPieDiagram("pie\n  \"A\" : 1"));
    try std.testing.expect(isPieDiagram("  pie\n  \"A\" : 1"));
    try std.testing.expect(isPieDiagram("pie title Foo\n  \"A\" : 1"));
    try std.testing.expect(!isPieDiagram("flowchart TD\n  A-->B"));
    try std.testing.expect(!isPieDiagram("sequenceDiagram\n  A->>B: Hi"));
    try std.testing.expect(!isPieDiagram("pieceOfCake")); // "pie" not as full keyword
}

test "pie parser: accTitle and accDescr ignored" {
    const allocator = std.testing.allocator;
    var pie = try parse(allocator,
        \\pie title Chart
        \\    accTitle: my accessibility title
        \\    accDescr: my description
        \\    "A" : 50
        \\    "B" : 50
    );
    defer pie.deinit();

    try std.testing.expectEqual(@as(usize, 2), pie.sectionCount());
}

test "pie parser: multiline accDescr ignored" {
    const allocator = std.testing.allocator;
    var pie = try parse(allocator,
        \\pie
        \\    accDescr {
        \\        line one
        \\        line two
        \\    }
        \\    "A" : 100
    );
    defer pie.deinit();

    try std.testing.expectEqual(@as(usize, 1), pie.sectionCount());
}

test "pie parser: empty pie" {
    const allocator = std.testing.allocator;
    var pie = try parse(allocator, "pie\n");
    defer pie.deinit();

    try std.testing.expectEqual(@as(usize, 0), pie.sectionCount());
}
