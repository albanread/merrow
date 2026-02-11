//! Class diagram parser for Mermaid `classDiagram` syntax.
//!
//! Supports the following grammar:
//!
//!   classDiagram
//!       direction TB|BT|LR|RL
//!       class ClassName {
//!           +attribute: type
//!           -method(param) returnType
//!       }
//!       class ClassName
//!       ClassName : +member
//!       ClassName <|-- OtherClass : label
//!       ClassName "1" --o "0..*" OtherClass
//!       <<interface>> ClassName
//!       note "text"
//!       note for ClassName "text"
//!       %% comments
//!       accTitle: text
//!       accDescr: text

const std = @import("std");
const Allocator = std.mem.Allocator;
const class_model = @import("model.zig");
const ClassDiagram = class_model.ClassDiagram;
const ClassRelation = class_model.ClassRelation;
const RelationDetails = class_model.RelationDetails;
const parseRelationArrow = class_model.parseRelationArrow;

pub const ParseError = error{
    InvalidSyntax,
    OutOfMemory,
    Overflow,
    NegativeValue,
};

// -----------------------------------------------------------------------
// Public API
// -----------------------------------------------------------------------

/// Parse a complete Mermaid class diagram source into a `ClassDiagram`.
/// Caller owns the returned value and must call `.deinit()`.
pub fn parse(allocator: Allocator, source: []const u8) ParseError!ClassDiagram {
    var diagram = ClassDiagram.init(allocator);
    errdefer diagram.deinit();

    var line_iter = LineIterator.init(source);
    var header_seen = false;
    var in_class_body = false;
    var current_class: ?[]const u8 = null;
    var in_multiline_descr = false;

    while (line_iter.next()) |raw_line| {
        const line = trimWhitespace(raw_line);

        // Skip empty lines.
        if (line.len == 0) continue;

        // Skip %%{init: ...}%% directives.
        if (startsWith(line, "%%{")) continue;

        // Skip %% comments.
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
            if (startsWithCI(line, "classDiagram")) {
                header_seen = true;
                continue;
            }
            // Skip preamble lines before header.
            continue;
        }

        // ── Inside a class body { ... } ─────────────────────────
        if (in_class_body) {
            // Check for closing brace.
            if (line[0] == '}') {
                in_class_body = false;
                current_class = null;
                continue;
            }

            // Check for annotation inside body: <<interface>>
            if (startsWithCI(line, "<<") or startsWithCI(line, "&lt;&lt;")) {
                if (current_class) |cls_id| {
                    if (parseAnnotationText(line)) |ann_text| {
                        try diagram.addAnnotation(cls_id, ann_text);
                    }
                }
                continue;
            }

            // Skip separator lines (-- or == or .. or __)
            if (isSeparatorLine(line)) continue;

            // Skip %% comments inside body.
            if (startsWith(line, "%%")) continue;

            // Otherwise it's a member line.
            if (current_class) |cls_id| {
                try diagram.addMember(cls_id, line);
            }
            continue;
        }

        // ── Body statements ─────────────────────────────────────

        // accTitle: ...
        if (startsWithCI(line, "accTitle")) continue;

        // accDescr { ... } or accDescr: ...
        if (startsWithCI(line, "accDescr")) {
            if (std.mem.indexOf(u8, line, "{") != null) {
                in_multiline_descr = true;
            }
            continue;
        }

        // direction TB|BT|LR|RL
        if (startsWithCI(line, "direction")) {
            const rest = trimWhitespace(line[9..]);
            if (rest.len >= 2) {
                const dir = rest[0..2];
                if (eqlCI(dir, "TB") or eqlCI(dir, "BT") or eqlCI(dir, "LR") or eqlCI(dir, "RL")) {
                    diagram.setDirection(dir);
                }
            }
            continue;
        }

        // title ...
        if (startsWithCI(line, "title")) {
            const title_text = trimWhitespace(line[5..]);
            if (title_text.len > 0) {
                try diagram.setTitle(title_text);
            }
            continue;
        }

        // Annotation statement: <<annotation>> ClassName
        if (startsWith(line, "<<") or startsWith(line, "&lt;&lt;")) {
            if (parseAnnotationStatement(line)) |result| {
                try diagram.addAnnotation(result.class_name, result.annotation);
            }
            continue;
        }

        // note for ... or note "..."
        if (startsWithCI(line, "note")) {
            // We parse but don't store notes in the current model (can add later).
            continue;
        }

        // classDef, cssClass, style, click, link, callback — skip for now
        if (startsWithCI(line, "classDef") or
            startsWithCI(line, "cssClass") or
            startsWithCI(line, "style ") or
            startsWithCI(line, "click ") or
            startsWithCI(line, "link ") or
            startsWithCI(line, "callback "))
        {
            continue;
        }

        // class ClassName { ... } or class ClassName
        if (startsWithCI(line, "class ")) {
            const rest = trimWhitespace(line[6..]);
            if (rest.len == 0) continue;

            // Extract class name (may include generic ~T~, text label [...], ::: css)
            const class_info = parseClassNameAndExtras(rest);
            const cls = try diagram.ensureClass(class_info.name);

            if (class_info.generic) |g| {
                if (cls.generic == null) {
                    cls.generic = try allocator.dupe(u8, g);
                    cls.generic_owned = true;
                }
            }

            if (class_info.label) |lbl| {
                if (cls.label == null) {
                    cls.label = try allocator.dupe(u8, lbl);
                    cls.label_owned = true;
                }
            }

            // Check if there's an opening brace on this line.
            if (std.mem.indexOf(u8, rest, "{") != null) {
                in_class_body = true;
                current_class = cls.id;
            }
            continue;
        }

        // Try relationship: ClassA <rel> ClassB : label
        if (tryParseRelationship(allocator, line)) |rel| {
            try diagram.addRelation(rel);
            continue;
        }

        // Try member statement: ClassName : memberText
        if (tryParseMemberStatement(line)) |ms| {
            try diagram.addMember(ms.class_name, ms.member_text);
            continue;
        }

        // Unknown lines are silently ignored (lenient parsing).
    }

    return diagram;
}

/// Returns true if `source` starts with the `classDiagram` keyword.
pub fn isClassDiagram(source: []const u8) bool {
    var i: usize = 0;

    // Skip leading whitespace.
    while (i < source.len and isWhitespace(source[i])) i += 1;

    // Skip %%{init: ...}%% directive if present.
    if (i + 3 <= source.len and std.mem.eql(u8, source[i .. i + 3], "%%{")) {
        while (i < source.len and source[i] != '\n') i += 1;
        while (i < source.len and isWhitespace(source[i])) i += 1;
    }

    // Check for "classDiagram" keyword (case-insensitive).
    const keyword = "classDiagram";
    if (i + keyword.len > source.len) return false;
    if (!eqlCI(source[i .. i + keyword.len], keyword)) return false;

    // Make sure it's followed by whitespace, newline, or EOF.
    if (i + keyword.len < source.len) {
        const next = source[i + keyword.len];
        if (next != ' ' and next != '\t' and next != '\r' and next != '\n' and next != '-') return false;
    }

    return true;
}

// -----------------------------------------------------------------------
// Relationship parser
// -----------------------------------------------------------------------

/// Known relationship arrow patterns (longer first for greedy matching).
const arrow_patterns = [_][]const u8{
    // Bidirectional
    "<|--|>",
    "<|..|>",
    "*--*",
    "<-->",
    // Extension (inheritance)
    "<|--",
    "--|>",
    "<|..",
    "..|>",
    // Composition
    "*--",
    "--*",
    "*..",
    "..*",
    // Aggregation
    "o--",
    "--o",
    "o..",
    "..o",
    // Dependency
    "<--",
    "-->",
    "<..",
    "..>",
    // Lollipop
    "()--",
    "--()",
    // Simple
    "--",
    "..",
};

fn tryParseRelationship(allocator: Allocator, line: []const u8) ?ClassRelation {
    // Strategy: scan for arrow patterns in the line.
    // Before the arrow = left class (possibly with cardinality).
    // After the arrow = right class (possibly with cardinality), then optional : label.

    for (arrow_patterns) |arrow| {
        // Find the arrow in the line. We need to be careful not to match
        // arrows inside quoted strings. Simple approach: find the first
        // occurrence that's not inside quotes.
        const arrow_pos = findArrowInLine(line, arrow) orelse continue;

        const left_part = trimWhitespace(line[0..arrow_pos]);
        const after_arrow = line[arrow_pos + arrow.len ..];

        // Parse left: ClassName [generic] ["cardinality"]
        // or "cardinality" ClassName
        // The left part should be the first class ref, possibly with cardinality.
        const left_info = parseClassRef(left_part) orelse continue;

        // Parse right: look for ": label" first, then class ref.
        var right_text: []const u8 = undefined;
        var rel_label: ?[]const u8 = null;

        if (findColonOutsideQuotes(after_arrow)) |colon_pos| {
            right_text = trimWhitespace(after_arrow[0..colon_pos]);
            rel_label = trimWhitespace(after_arrow[colon_pos + 1 ..]);
            if (rel_label.?.len == 0) rel_label = null;
        } else {
            right_text = trimWhitespace(after_arrow);
        }

        const right_info = parseClassRef(right_text) orelse continue;

        // Both class names must be valid identifiers.
        if (!isValidClassName(left_info.name) or !isValidClassName(right_info.name)) continue;

        const relation = parseRelationArrow(arrow);

        var rel = ClassRelation{
            .id1 = allocator.dupe(u8, left_info.name) catch return null,
            .id1_owned = true,
            .id2 = allocator.dupe(u8, right_info.name) catch return null,
            .id2_owned = true,
            .relation = relation,
        };

        // Set cardinality.
        if (left_info.cardinality) |c| {
            rel.cardinality1 = allocator.dupe(u8, c) catch null;
            rel.cardinality1_owned = true;
        }
        if (right_info.cardinality) |c| {
            rel.cardinality2 = allocator.dupe(u8, c) catch null;
            rel.cardinality2_owned = true;
        }

        // Set label.
        if (rel_label) |lbl| {
            rel.label = allocator.dupe(u8, lbl) catch null;
            rel.label_owned = true;
        }

        return rel;
    }

    return null;
}

const ClassRefInfo = struct {
    name: []const u8,
    cardinality: ?[]const u8 = null,
};

fn parseClassRef(text: []const u8) ?ClassRefInfo {
    var t = trimWhitespace(text);
    if (t.len == 0) return null;

    var cardinality: ?[]const u8 = null;

    // Check for leading cardinality: "1" ClassName
    if (t[0] == '"') {
        const close = std.mem.indexOf(u8, t[1..], "\"") orelse return null;
        cardinality = t[1 .. 1 + close];
        t = trimWhitespace(t[2 + close ..]);
        if (t.len == 0) return null;
    }

    // Extract class name: take identifier characters.
    var name_end: usize = 0;
    while (name_end < t.len and isIdentChar(t[name_end])) : (name_end += 1) {}
    if (name_end == 0) return null;

    const name = t[0..name_end];
    const rest = trimWhitespace(t[name_end..]);

    // Skip optional generic ~T~ after name.
    var remaining = rest;
    if (remaining.len > 0 and remaining[0] == '~') {
        const close_tilde = std.mem.indexOf(u8, remaining[1..], "~");
        if (close_tilde) |ct| {
            remaining = trimWhitespace(remaining[2 + ct ..]);
        }
    }

    // Skip optional ::: css
    if (startsWith(remaining, ":::")) {
        remaining = "";
    }

    // Check for trailing cardinality: ClassName "1"
    if (cardinality == null and remaining.len > 0 and remaining[0] == '"') {
        const close = std.mem.indexOf(u8, remaining[1..], "\"");
        if (close) |c| {
            cardinality = remaining[1 .. 1 + c];
        }
    }

    return .{
        .name = name,
        .cardinality = cardinality,
    };
}

fn findArrowInLine(line: []const u8, arrow: []const u8) ?usize {
    // Find arrow that's not at position 0 (there must be a left side).
    // Also skip occurrences inside quoted strings.
    var i: usize = 0;
    var in_quotes = false;

    while (i < line.len) {
        if (line[i] == '"') {
            in_quotes = !in_quotes;
            i += 1;
            continue;
        }

        if (in_quotes) {
            i += 1;
            continue;
        }

        if (i > 0 and i + arrow.len <= line.len) {
            if (std.mem.eql(u8, line[i .. i + arrow.len], arrow)) {
                // Make sure left side is not empty.
                const left = trimWhitespace(line[0..i]);
                if (left.len > 0) return i;
            }
        }

        i += 1;
    }

    return null;
}

fn findColonOutsideQuotes(text: []const u8) ?usize {
    var i: usize = 0;
    var in_quotes = false;

    while (i < text.len) {
        if (text[i] == '"') {
            in_quotes = !in_quotes;
        } else if (text[i] == ':' and !in_quotes) {
            // Make sure it's not part of ":::" (CSS shorthand).
            if (i + 2 < text.len and text[i + 1] == ':' and text[i + 2] == ':') {
                i += 3;
                continue;
            }
            return i;
        }
        i += 1;
    }

    return null;
}

// -----------------------------------------------------------------------
// Member statement parser
// -----------------------------------------------------------------------

const MemberStatementResult = struct {
    class_name: []const u8,
    member_text: []const u8,
};

fn tryParseMemberStatement(line: []const u8) ?MemberStatementResult {
    // Pattern: ClassName : memberText
    // But we need to be careful not to match relationship lines.
    // A member statement has a single class name before the colon,
    // and no arrow pattern in the line.

    // First, check there's no arrow pattern.
    for (arrow_patterns) |arrow| {
        if (std.mem.indexOf(u8, line, arrow) != null) return null;
    }

    // Find the first colon that's not part of ":::".
    const colon_pos = findColonOutsideQuotes(line) orelse return null;

    const left = trimWhitespace(line[0..colon_pos]);
    const right = trimWhitespace(line[colon_pos + 1 ..]);

    if (left.len == 0 or right.len == 0) return null;

    // Left must be a valid class name (possibly with generic).
    var name_end: usize = 0;
    while (name_end < left.len and isIdentChar(left[name_end])) : (name_end += 1) {}
    if (name_end == 0) return null;

    const class_name = left[0..name_end];
    if (!isValidClassName(class_name)) return null;

    return .{
        .class_name = class_name,
        .member_text = right,
    };
}

// -----------------------------------------------------------------------
// Class statement helpers
// -----------------------------------------------------------------------

const ClassNameExtras = struct {
    name: []const u8,
    generic: ?[]const u8 = null,
    label: ?[]const u8 = null,
};

fn parseClassNameAndExtras(rest: []const u8) ClassNameExtras {
    var result = ClassNameExtras{ .name = "" };

    var pos: usize = 0;
    // Extract class name.
    while (pos < rest.len and isIdentChar(rest[pos])) : (pos += 1) {}
    if (pos == 0) {
        result.name = rest;
        return result;
    }
    result.name = rest[0..pos];

    // Check for generic ~T~
    if (pos < rest.len and rest[pos] == '~') {
        const start = pos + 1;
        const close = std.mem.indexOf(u8, rest[start..], "~");
        if (close) |c| {
            result.generic = rest[start .. start + c];
            pos = start + c + 1;
        }
    }

    // Skip whitespace.
    while (pos < rest.len and isWhitespace(rest[pos])) : (pos += 1) {}

    // Check for text label ["..."]
    if (pos < rest.len and rest[pos] == '[') {
        const after_bracket = pos + 1;
        // Find the label inside: ["label"] or [label]
        if (after_bracket < rest.len and rest[after_bracket] == '"') {
            const label_start = after_bracket + 1;
            const close_quote = std.mem.indexOf(u8, rest[label_start..], "\"");
            if (close_quote) |cq| {
                result.label = rest[label_start .. label_start + cq];
            }
        }
    }

    return result;
}

// -----------------------------------------------------------------------
// Annotation parsers
// -----------------------------------------------------------------------

const AnnotationStatementResult = struct {
    annotation: []const u8,
    class_name: []const u8,
};

fn parseAnnotationStatement(line: []const u8) ?AnnotationStatementResult {
    // Pattern: <<annotation>> ClassName
    var rest = line;

    // Skip << or &lt;&lt;
    if (startsWith(rest, "<<")) {
        rest = rest[2..];
    } else if (startsWith(rest, "&lt;&lt;")) {
        rest = rest[8..];
    } else {
        return null;
    }

    // Find closing >> or &gt;&gt;
    var ann_end: usize = 0;
    var close_len: usize = 0;

    if (std.mem.indexOf(u8, rest, ">>")) |idx| {
        ann_end = idx;
        close_len = 2;
    } else if (std.mem.indexOf(u8, rest, "&gt;&gt;")) |idx| {
        ann_end = idx;
        close_len = 8;
    } else {
        return null;
    }

    const annotation = trimWhitespace(rest[0..ann_end]);
    const after_close = trimWhitespace(rest[ann_end + close_len ..]);

    if (annotation.len == 0 or after_close.len == 0) return null;

    // Extract class name.
    var name_end: usize = 0;
    while (name_end < after_close.len and isIdentChar(after_close[name_end])) : (name_end += 1) {}
    if (name_end == 0) return null;

    return .{
        .annotation = annotation,
        .class_name = after_close[0..name_end],
    };
}

fn parseAnnotationText(line: []const u8) ?[]const u8 {
    // Parse <<text>> from a line inside a class body.
    var rest = line;

    if (startsWith(rest, "<<")) {
        rest = rest[2..];
    } else if (startsWith(rest, "&lt;&lt;")) {
        rest = rest[8..];
    } else {
        return null;
    }

    var ann_end: usize = 0;

    if (std.mem.indexOf(u8, rest, ">>")) |idx| {
        ann_end = idx;
    } else if (std.mem.indexOf(u8, rest, "&gt;&gt;")) |idx| {
        ann_end = idx;
    } else {
        return null;
    }

    const annotation = trimWhitespace(rest[0..ann_end]);
    return if (annotation.len > 0) annotation else null;
}

fn isSeparatorLine(line: []const u8) bool {
    if (line.len < 2) return false;
    const prefix = line[0..2];
    return std.mem.eql(u8, prefix, "--") or
        std.mem.eql(u8, prefix, "==") or
        std.mem.eql(u8, prefix, "..") or
        std.mem.eql(u8, prefix, "__");
}

// -----------------------------------------------------------------------
// Validation helpers
// -----------------------------------------------------------------------

fn isValidClassName(name: []const u8) bool {
    if (name.len == 0) return false;
    // Must start with letter or underscore.
    const first = name[0];
    if (!((first >= 'a' and first <= 'z') or (first >= 'A' and first <= 'Z') or first == '_')) return false;

    // Reject known keywords.
    const keywords = [_][]const u8{
        "class",     "classDiagram", "direction", "note",     "style",
        "click",     "link",         "callback",  "classDef", "cssClass",
        "namespace", "title",        "accTitle",  "accDescr",
    };
    for (keywords) |kw| {
        if (eqlCI(name, kw)) return false;
    }

    return true;
}

fn isIdentChar(c: u8) bool {
    return (c >= 'a' and c <= 'z') or
        (c >= 'A' and c <= 'Z') or
        (c >= '0' and c <= '9') or
        c == '_' or c == '-';
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
        if (self.pos < self.source.len) self.pos += 1;
        const line_end = if (end > start and self.source[end - 1] == '\r') end - 1 else end;
        return self.source[start..line_end];
    }
};

fn isWhitespace(c: u8) bool {
    return c == ' ' or c == '\t' or c == '\r' or c == '\n';
}

fn trimWhitespace(s: []const u8) []const u8 {
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

fn startsWithCI(haystack: []const u8, prefix: []const u8) bool {
    if (haystack.len < prefix.len) return false;
    return eqlCI(haystack[0..prefix.len], prefix);
}

fn eqlCI(a: []const u8, b: []const u8) bool {
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

test "class parser: isClassDiagram detection" {
    try std.testing.expect(isClassDiagram("classDiagram\n  class Foo"));
    try std.testing.expect(isClassDiagram("  classDiagram\n  class Foo"));
    try std.testing.expect(isClassDiagram("classDiagram-v2\n  class Foo"));
    try std.testing.expect(!isClassDiagram("flowchart TD\n  A-->B"));
    try std.testing.expect(!isClassDiagram("pie\n  \"A\" : 1"));
    try std.testing.expect(!isClassDiagram("classDiagramExtra")); // not keyword boundary
}

test "class parser: empty diagram" {
    const allocator = std.testing.allocator;
    var diagram = try parse(allocator, "classDiagram\n");
    defer diagram.deinit();

    try std.testing.expectEqual(@as(usize, 0), diagram.classCount());
}

test "class parser: simple class statement" {
    const allocator = std.testing.allocator;
    var diagram = try parse(allocator,
        \\classDiagram
        \\    class Animal
    );
    defer diagram.deinit();

    try std.testing.expectEqual(@as(usize, 1), diagram.classCount());
    try std.testing.expect(diagram.classes.get("Animal") != null);
}

test "class parser: class with body" {
    const allocator = std.testing.allocator;
    var diagram = try parse(allocator,
        \\classDiagram
        \\    class Animal {
        \\        +name: string
        \\        -age: int
        \\        +speak()
        \\        +move(distance) bool
        \\    }
    );
    defer diagram.deinit();

    try std.testing.expectEqual(@as(usize, 1), diagram.classCount());
    const node = diagram.classes.get("Animal").?;
    try std.testing.expectEqual(@as(usize, 2), node.members.items.len);
    try std.testing.expectEqual(@as(usize, 2), node.methods.items.len);
}

test "class parser: member colon syntax" {
    const allocator = std.testing.allocator;
    var diagram = try parse(allocator,
        \\classDiagram
        \\    Animal : +name
        \\    Animal : +speak()
    );
    defer diagram.deinit();

    const node = diagram.classes.get("Animal").?;
    try std.testing.expectEqual(@as(usize, 1), node.members.items.len);
    try std.testing.expectEqual(@as(usize, 1), node.methods.items.len);
}

test "class parser: basic relationship" {
    const allocator = std.testing.allocator;
    var diagram = try parse(allocator,
        \\classDiagram
        \\    Animal <|-- Dog
    );
    defer diagram.deinit();

    try std.testing.expectEqual(@as(usize, 2), diagram.classCount());
    try std.testing.expectEqual(@as(usize, 1), diagram.relationCount());

    const rel = diagram.relations.items[0];
    try std.testing.expectEqualStrings("Animal", rel.id1);
    try std.testing.expectEqualStrings("Dog", rel.id2);
    try std.testing.expectEqual(class_model.RelationEndType.extension, rel.relation.type1);
}

test "class parser: relationship with label" {
    const allocator = std.testing.allocator;
    var diagram = try parse(allocator,
        \\classDiagram
        \\    Dog --|> Animal : inherits
    );
    defer diagram.deinit();

    const rel = diagram.relations.items[0];
    try std.testing.expectEqualStrings("inherits", rel.label.?);
    try std.testing.expectEqual(class_model.RelationEndType.extension, rel.relation.type2);
}

test "class parser: relationship with cardinality" {
    const allocator = std.testing.allocator;
    var diagram = try parse(allocator,
        \\classDiagram
        \\    Customer "1" --> "*" Order
    );
    defer diagram.deinit();

    const rel = diagram.relations.items[0];
    try std.testing.expectEqualStrings("1", rel.cardinality1.?);
    try std.testing.expectEqualStrings("*", rel.cardinality2.?);
}

test "class parser: composition relationship" {
    const allocator = std.testing.allocator;
    var diagram = try parse(allocator,
        \\classDiagram
        \\    Company *-- Employee
    );
    defer diagram.deinit();

    const rel = diagram.relations.items[0];
    try std.testing.expectEqual(class_model.RelationEndType.composition, rel.relation.type1);
    try std.testing.expectEqual(class_model.LineType.solid, rel.relation.line_type);
}

test "class parser: aggregation dotted" {
    const allocator = std.testing.allocator;
    var diagram = try parse(allocator,
        \\classDiagram
        \\    Pond o.. Duck
    );
    defer diagram.deinit();

    const rel = diagram.relations.items[0];
    try std.testing.expectEqual(class_model.RelationEndType.aggregation, rel.relation.type1);
    try std.testing.expectEqual(class_model.LineType.dotted, rel.relation.line_type);
}

test "class parser: annotation statement" {
    const allocator = std.testing.allocator;
    var diagram = try parse(allocator,
        \\classDiagram
        \\    class Shape
        \\    <<interface>> Shape
    );
    defer diagram.deinit();

    const node = diagram.classes.get("Shape").?;
    try std.testing.expectEqual(@as(usize, 1), node.annotations.items.len);
    try std.testing.expectEqualStrings("interface", node.annotations.items[0]);
}

test "class parser: annotation inside class body" {
    const allocator = std.testing.allocator;
    var diagram = try parse(allocator,
        \\classDiagram
        \\    class Shape {
        \\        <<interface>>
        \\        +draw()
        \\    }
    );
    defer diagram.deinit();

    const node = diagram.classes.get("Shape").?;
    try std.testing.expectEqual(@as(usize, 1), node.annotations.items.len);
    try std.testing.expectEqualStrings("interface", node.annotations.items[0]);
    try std.testing.expectEqual(@as(usize, 1), node.methods.items.len);
}

test "class parser: direction" {
    const allocator = std.testing.allocator;
    var diagram = try parse(allocator,
        \\classDiagram
        \\    direction LR
        \\    class Foo
    );
    defer diagram.deinit();

    try std.testing.expectEqualStrings("LR", diagram.direction);
}

test "class parser: comments ignored" {
    const allocator = std.testing.allocator;
    var diagram = try parse(allocator,
        \\classDiagram
        \\    %% this is a comment
        \\    class Foo
    );
    defer diagram.deinit();

    try std.testing.expectEqual(@as(usize, 1), diagram.classCount());
}

test "class parser: multiple relationships" {
    const allocator = std.testing.allocator;
    var diagram = try parse(allocator,
        \\classDiagram
        \\    Animal <|-- Dog
        \\    Animal <|-- Cat
        \\    Animal *-- Leg
        \\    Dog ..> Food
    );
    defer diagram.deinit();

    try std.testing.expectEqual(@as(usize, 4), diagram.relationCount());
    try std.testing.expectEqual(@as(usize, 5), diagram.classCount()); // Animal, Dog, Cat, Leg, Food
}

test "class parser: class with generic" {
    const allocator = std.testing.allocator;
    var diagram = try parse(allocator,
        \\classDiagram
        \\    class List~T~ {
        \\        +add(item: T)
        \\        +size() int
        \\    }
    );
    defer diagram.deinit();

    const node = diagram.classes.get("List").?;
    try std.testing.expect(node.generic != null);
    try std.testing.expectEqualStrings("T", node.generic.?);
    try std.testing.expectEqual(@as(usize, 2), node.methods.items.len);
}

test "class parser: complex diagram" {
    const allocator = std.testing.allocator;
    var diagram = try parse(allocator,
        \\classDiagram
        \\    class Animal {
        \\        <<abstract>>
        \\        +String name
        \\        +int age
        \\        +makeSound()*
        \\        +move(int distance)$
        \\    }
        \\    class Dog {
        \\        +String breed
        \\        +bark()
        \\    }
        \\    class Cat {
        \\        +String color
        \\        +purr()
        \\    }
        \\    Animal <|-- Dog
        \\    Animal <|-- Cat
    );
    defer diagram.deinit();

    try std.testing.expectEqual(@as(usize, 3), diagram.classCount());
    try std.testing.expectEqual(@as(usize, 2), diagram.relationCount());

    const animal = diagram.classes.get("Animal").?;
    try std.testing.expectEqual(@as(usize, 1), animal.annotations.items.len);
    try std.testing.expectEqualStrings("abstract", animal.annotations.items[0]);
    try std.testing.expectEqual(@as(usize, 2), animal.members.items.len);
    try std.testing.expectEqual(@as(usize, 2), animal.methods.items.len);
}

test "class parser: dependency dotted arrow" {
    const allocator = std.testing.allocator;
    var diagram = try parse(allocator,
        \\classDiagram
        \\    Service ..> Repository : uses
    );
    defer diagram.deinit();

    const rel = diagram.relations.items[0];
    try std.testing.expectEqual(class_model.RelationEndType.dependency, rel.relation.type2);
    try std.testing.expectEqual(class_model.LineType.dotted, rel.relation.line_type);
    try std.testing.expectEqualStrings("uses", rel.label.?);
}

test "class parser: simple association" {
    const allocator = std.testing.allocator;
    var diagram = try parse(allocator,
        \\classDiagram
        \\    ClassA -- ClassB
    );
    defer diagram.deinit();

    try std.testing.expectEqual(@as(usize, 1), diagram.relationCount());
    const rel = diagram.relations.items[0];
    try std.testing.expectEqual(class_model.RelationEndType.none, rel.relation.type1);
    try std.testing.expectEqual(class_model.RelationEndType.none, rel.relation.type2);
    try std.testing.expectEqual(class_model.LineType.solid, rel.relation.line_type);
}
