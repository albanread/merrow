//! ER (Entity-Relationship) diagram parser.
//!
//! Parses mermaid ER diagram syntax line-by-line, producing an ErDiagram model.
//! Supports: entities, relationships with cardinality, attributes, aliases,
//! titles, directions, and comments.

const std = @import("std");
const ErDiagram = @import("model.zig").ErDiagram;
const Entity = @import("model.zig").Entity;
const Attribute = @import("model.zig").Attribute;
const AttributeKey = @import("model.zig").AttributeKey;
const Cardinality = @import("model.zig").Cardinality;
const Identification = @import("model.zig").Identification;
const RelSpec = @import("model.zig").RelSpec;
const Direction = @import("model.zig").Direction;

pub const ParseError = error{
    OutOfMemory,
    InvalidSyntax,
    Overflow,
    InvalidCharacter,
};

/// Parse ER diagram source text into an ErDiagram model.
pub fn parse(allocator: std.mem.Allocator, source: []const u8) ParseError!ErDiagram {
    var diagram = ErDiagram.init(allocator);
    errdefer diagram.deinit();

    var lines = LineIterator.init(source);
    var header_seen = false;
    var in_attr_block = false;
    var current_entity: ?[]const u8 = null;
    // We need to track current_entity with owned memory
    var current_entity_owned: ?[]u8 = null;
    defer if (current_entity_owned) |e| allocator.free(e);
    var in_multiline_descr = false;

    while (lines.next()) |raw_line| {
        const line = trim(raw_line);

        // Skip empty lines
        if (line.len == 0) continue;

        // Skip %% comments
        if (startsWith(line, "%%")) continue;

        // Handle multiline accDescr { ... } block
        if (in_multiline_descr) {
            if (std.mem.indexOf(u8, line, "}") != null) {
                in_multiline_descr = false;
            }
            continue;
        }

        // ── Header ──────────────────────────────────────────────
        if (!header_seen) {
            if (startsWithCaseInsensitive(line, "erDiagram")) {
                header_seen = true;
                continue;
            }
            // Skip frontmatter/preamble
            continue;
        }

        // ── Inside attribute block ──────────────────────────────
        if (in_attr_block) {
            // Check for closing brace
            if (std.mem.eql(u8, line, "}")) {
                in_attr_block = false;
                if (current_entity_owned) |e| {
                    allocator.free(e);
                    current_entity_owned = null;
                }
                current_entity = null;
                continue;
            }

            // Parse attribute line: type name [key[,key]] ["comment"]
            if (current_entity) |entity_name| {
                var attr = try parseAttributeLine(allocator, line);
                if (attr) |*a| {
                    const entity = try diagram.ensureEntity(entity_name);
                    try entity.addAttribute(allocator, a.*);
                }
            }
            continue;
        }

        // ── Closing brace (should not happen outside attr block) ─
        if (std.mem.eql(u8, line, "}")) continue;

        // ── Directives ──────────────────────────────────────────

        // accTitle: <text>
        if (startsWithCaseInsensitive(line, "accTitle")) continue;

        // accDescr { ... } or accDescr: <text>
        if (startsWithCaseInsensitive(line, "accDescr")) {
            if (std.mem.indexOf(u8, line, "{") != null) {
                in_multiline_descr = true;
            }
            continue;
        }

        // title <text>
        if (startsWithCaseInsensitive(line, "title")) {
            const rest = trim(line[5..]);
            if (rest.len > 0) {
                try diagram.setTitle(rest);
            }
            continue;
        }

        // direction TB|BT|LR|RL
        if (startsWithCaseInsensitive(line, "direction")) {
            const rest = trim(line[9..]);
            if (rest.len >= 2) {
                diagram.direction = Direction.fromStr(rest[0..2]);
            }
            continue;
        }

        // classDef, class, style — skip for now
        if (startsWithCaseInsensitive(line, "classDef") or
            startsWithCaseInsensitive(line, "classdef"))
            continue;
        if (startsWithCaseInsensitive(line, "class ")) continue;
        if (startsWithCaseInsensitive(line, "style ")) continue;

        // ── Relationship ────────────────────────────────────────
        // Format: EntityA <card><rel><card> EntityB : "role"
        if (parseRelationship(allocator, &diagram, line)) |_| {
            continue;
        } else |_| {}

        // ── Entity with attribute block ─────────────────────────
        // Format: ENTITY_NAME ["alias"] [:::class] {
        if (std.mem.indexOf(u8, line, "{") != null) {
            const brace_pos = std.mem.indexOf(u8, line, "{").?;
            const before_brace = trim(line[0..brace_pos]);
            if (before_brace.len > 0) {
                const parsed = parseEntityDecl(before_brace);
                const entity = try diagram.addEntity(parsed.name, parsed.alias);
                _ = entity;
                in_attr_block = true;
                if (current_entity_owned) |e| allocator.free(e);
                current_entity_owned = try allocator.dupe(u8, parsed.name);
                current_entity = current_entity_owned;
            }
            continue;
        }

        // ── Standalone entity declaration ───────────────────────
        // Format: ENTITY_NAME ["alias"] [:::class]
        if (isValidEntityName(line)) {
            const parsed = parseEntityDecl(line);
            _ = try diagram.addEntity(parsed.name, parsed.alias);
            continue;
        }

        // Try entity with alias: EntityName["alias"]
        if (line.len > 0 and (std.ascii.isAlphabetic(line[0]) or line[0] == '_' or line[0] == '"')) {
            const parsed = parseEntityDecl(line);
            if (parsed.name.len > 0) {
                _ = try diagram.addEntity(parsed.name, parsed.alias);
                continue;
            }
        }

        // Unknown lines are silently ignored (lenient parsing)
    }

    return diagram;
}

/// Check if the source text is an ER diagram.
pub fn isErDiagram(source: []const u8) bool {
    var lines = LineIterator.init(source);
    while (lines.next()) |raw_line| {
        const line = trim(raw_line);
        if (line.len == 0) continue;
        if (startsWith(line, "%%{")) continue;
        if (startsWith(line, "%%")) continue;
        if (startsWith(line, "---")) continue;

        // Check for erDiagram keyword
        if (startsWithCaseInsensitive(line, "erDiagram")) return true;

        // If we see another diagram keyword first, it's not ER
        if (startsWithCaseInsensitive(line, "stateDiagram") or
            startsWithCaseInsensitive(line, "sequenceDiagram") or
            startsWithCaseInsensitive(line, "classDiagram") or
            startsWithCaseInsensitive(line, "flowchart") or
            startsWithCaseInsensitive(line, "graph") or
            startsWithCaseInsensitive(line, "pie") or
            startsWithCaseInsensitive(line, "gantt") or
            startsWithCaseInsensitive(line, "journey") or
            startsWithCaseInsensitive(line, "gitGraph") or
            startsWithCaseInsensitive(line, "mindmap") or
            startsWithCaseInsensitive(line, "timeline"))
            return false;

        return false;
    }
    return false;
}

// -----------------------------------------------------------------------
// Relationship parsing
// -----------------------------------------------------------------------

/// Try to parse a relationship line.
/// Format: EntityA ||--o{ EntityB : "role label"
///
/// The relationship spec is composed of:
///   left-cardinality + rel-type + right-cardinality
///
/// Cardinality symbols:
///   ||  only_one
///   |o  zero_or_one     o|  zero_or_one
///   }o  zero_or_more    o{  zero_or_more
///   }|  one_or_more     |{  one_or_more
///
/// Rel-type:
///   --  identifying
///   ..  non_identifying
fn parseRelationship(
    allocator: std.mem.Allocator,
    diagram: *ErDiagram,
    line: []const u8,
) ParseError!void {
    // Must contain a colon for the role label
    const colon_pos = std.mem.indexOf(u8, line, ":") orelse return ParseError.InvalidSyntax;
    const before_colon = trim(line[0..colon_pos]);
    const role_raw = trim(line[colon_pos + 1 ..]);

    // Strip quotes from role
    const role = stripQuotes(role_raw);

    // Parse the part before the colon: EntityA <relspec> EntityB
    // Find the relationship spec by looking for the pattern of cardinality+reltype+cardinality
    const rel_info = findRelSpec(before_colon) orelse return ParseError.InvalidSyntax;

    const entity_a_raw = trim(before_colon[0..rel_info.start]);
    const entity_b_raw = trim(before_colon[rel_info.end..]);

    if (entity_a_raw.len == 0 or entity_b_raw.len == 0) return ParseError.InvalidSyntax;

    // Strip class shorthands (:::classname) from entity names
    const entity_a = stripClassShorthand(entity_a_raw);
    const entity_b = stripClassShorthand(entity_b_raw);

    // Strip quotes from entity names
    const entity_a_clean = stripQuotes(entity_a);
    const entity_b_clean = stripQuotes(entity_b);

    if (entity_a_clean.len == 0 or entity_b_clean.len == 0) return ParseError.InvalidSyntax;

    try diagram.addRelationship(
        entity_a_clean,
        entity_b_clean,
        role,
        rel_info.spec,
    );
    _ = allocator;
}

const RelSpecInfo = struct {
    start: usize,
    end: usize,
    spec: RelSpec,
};

/// Scan through the line to find a relationship spec pattern.
/// Returns the byte range [start, end) and the parsed RelSpec.
fn findRelSpec(s: []const u8) ?RelSpecInfo {
    // We need at least 4 chars for a minimal relspec like ||--|{
    // Scan for the relationship type markers (-- or ..)
    var i: usize = 0;
    while (i + 1 < s.len) : (i += 1) {
        // Look for -- or .. (the rel type in the middle)
        if ((s[i] == '-' and s[i + 1] == '-') or
            (s[i] == '.' and s[i + 1] == '.') or
            (s[i] == '.' and s[i + 1] == '-') or
            (s[i] == '-' and s[i + 1] == '.'))
        {
            // Found potential rel type at position i..i+2
            // Now look backward for left cardinality (2 chars before rel type)
            if (i < 2) continue;

            const left_card_str = s[i - 2 .. i];
            const left_card = parseCardinalitySymbol(left_card_str) orelse continue;

            // Look forward for right cardinality (2 chars after rel type)
            if (i + 4 > s.len) continue;
            const right_card_str = s[i + 2 .. i + 4];
            const right_card = parseCardinalitySymbol(right_card_str) orelse continue;

            const rel_type_str = s[i .. i + 2];
            const rel_type = if (std.mem.eql(u8, rel_type_str, "--"))
                Identification.identifying
            else
                Identification.non_identifying;

            return .{
                .start = i - 2,
                .end = i + 4,
                .spec = RelSpec.init(left_card, right_card, rel_type),
            };
        }
    }
    return null;
}

/// Parse a 2-character cardinality symbol
fn parseCardinalitySymbol(s: []const u8) ?Cardinality {
    if (s.len != 2) return null;
    if (s[0] == '|' and s[1] == '|') return .only_one;
    if (s[0] == '|' and s[1] == 'o') return .zero_or_one;
    if (s[0] == 'o' and s[1] == '|') return .zero_or_one;
    if (s[0] == '}' and s[1] == 'o') return .zero_or_more;
    if (s[0] == 'o' and s[1] == '{') return .zero_or_more;
    if (s[0] == '}' and s[1] == '|') return .one_or_more;
    if (s[0] == '|' and s[1] == '{') return .one_or_more;
    return null;
}

// -----------------------------------------------------------------------
// Entity declaration parsing
// -----------------------------------------------------------------------

const EntityDecl = struct {
    name: []const u8,
    alias: ?[]const u8,
};

/// Parse entity declaration: ENTITY_NAME ["alias"] [:::class]
fn parseEntityDecl(line: []const u8) EntityDecl {
    var s = line;

    // Strip :::class shorthand from end
    s = stripClassShorthand(s);
    s = trim(s);

    // Check for alias in square brackets: ENTITY[alias] or ENTITY["alias"]
    if (std.mem.indexOf(u8, s, "[") != null) {
        const bracket_start = std.mem.indexOf(u8, s, "[").?;
        const bracket_end = std.mem.lastIndexOf(u8, s, "]");
        if (bracket_end) |be| {
            if (be > bracket_start) {
                const name = trim(s[0..bracket_start]);
                var alias_text = s[bracket_start + 1 .. be];
                alias_text = stripQuotes(alias_text);
                return .{ .name = stripQuotes(name), .alias = if (alias_text.len > 0) alias_text else null };
            }
        }
    }

    // Might have quoted name
    const name = stripQuotes(trim(s));
    return .{ .name = name, .alias = null };
}

// -----------------------------------------------------------------------
// Attribute line parsing
// -----------------------------------------------------------------------

/// Parse an attribute line inside a { } block.
/// Format: type name [PK[,FK[,UK]]] ["comment"]
fn parseAttributeLine(allocator: std.mem.Allocator, line: []const u8) ParseError!?Attribute {
    var s = trim(line);
    if (s.len == 0) return null;

    // Skip lines that are just braces
    if (std.mem.eql(u8, s, "{") or std.mem.eql(u8, s, "}")) return null;

    // Tokenize: split by whitespace, but respect quoted strings
    var tokens = std.ArrayListUnmanaged([]const u8){};
    defer tokens.deinit(allocator);

    var pos: usize = 0;
    while (pos < s.len) {
        // Skip whitespace
        while (pos < s.len and isWhitespace(s[pos])) pos += 1;
        if (pos >= s.len) break;

        if (s[pos] == '"') {
            // Quoted token — find closing quote
            const start = pos;
            pos += 1;
            while (pos < s.len and s[pos] != '"') pos += 1;
            if (pos < s.len) pos += 1; // skip closing quote
            try tokens.append(allocator, s[start..pos]);
        } else {
            const start = pos;
            while (pos < s.len and !isWhitespace(s[pos])) pos += 1;
            try tokens.append(allocator, s[start..pos]);
        }
    }

    if (tokens.items.len < 2) return null;

    const attr_type = tokens.items[0];
    const attr_name = tokens.items[1];

    var attr = try Attribute.init(allocator, attr_type, attr_name);

    // Parse remaining tokens as keys and/or comment
    var idx: usize = 2;
    while (idx < tokens.items.len) : (idx += 1) {
        const tok = tokens.items[idx];

        if (tok.len > 0 and tok[0] == '"') {
            // Comment token
            const comment = stripQuotes(tok);
            if (comment.len > 0) {
                try attr.setComment(allocator, comment);
            }
        } else {
            // Could be key(s) separated by commas: PK,FK
            var key_iter = std.mem.splitScalar(u8, tok, ',');
            while (key_iter.next()) |key_str| {
                const key_trimmed = trim(key_str);
                if (key_trimmed.len > 0) {
                    if (AttributeKey.fromStr(key_trimmed)) |key| {
                        try attr.addKey(allocator, key);
                    }
                }
            }
        }
    }

    return attr;
}

// -----------------------------------------------------------------------
// Helpers
// -----------------------------------------------------------------------

fn isValidEntityName(s: []const u8) bool {
    if (s.len == 0) return false;
    // Must start with alpha, underscore, or quote
    const first = s[0];
    if (first == '"') return true; // quoted name
    if (!std.ascii.isAlphabetic(first) and first != '_') return false;
    // Rest must be alphanumeric, underscore, hyphen, or dot
    for (s[1..]) |c| {
        if (!std.ascii.isAlphanumeric(c) and c != '_' and c != '-' and c != '.') return false;
    }
    return true;
}

fn stripQuotes(s: []const u8) []const u8 {
    if (s.len >= 2 and s[0] == '"' and s[s.len - 1] == '"') {
        return s[1 .. s.len - 1];
    }
    return s;
}

fn stripClassShorthand(s: []const u8) []const u8 {
    if (std.mem.indexOf(u8, s, ":::")) |pos| {
        return trim(s[0..pos]);
    }
    return s;
}

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
        const line_end = self.pos;
        if (self.pos < self.source.len) self.pos += 1; // skip \n
        // Strip trailing \r
        var end = line_end;
        if (end > start and self.source[end - 1] == '\r') end -= 1;
        return self.source[start..end];
    }
};

fn isWhitespace(c: u8) bool {
    return c == ' ' or c == '\t' or c == '\r';
}

fn trim(s: []const u8) []const u8 {
    var start: usize = 0;
    while (start < s.len and isWhitespace(s[start])) start += 1;
    var end = s.len;
    while (end > start and isWhitespace(s[end - 1])) end -= 1;
    return s[start..end];
}

fn startsWith(s: []const u8, prefix: []const u8) bool {
    return s.len >= prefix.len and std.mem.eql(u8, s[0..prefix.len], prefix);
}

fn startsWithCaseInsensitive(s: []const u8, prefix: []const u8) bool {
    if (s.len < prefix.len) return false;
    for (s[0..prefix.len], prefix) |a, b| {
        if (std.ascii.toLower(a) != std.ascii.toLower(b)) return false;
    }
    return true;
}

// -----------------------------------------------------------------------
// Tests
// -----------------------------------------------------------------------

test "er parser: isErDiagram detection" {
    try std.testing.expect(isErDiagram("erDiagram\n"));
    try std.testing.expect(isErDiagram("  erDiagram\n  CUSTOMER\n"));
    try std.testing.expect(!isErDiagram("sequenceDiagram\n"));
    try std.testing.expect(!isErDiagram("pie\n"));
    try std.testing.expect(!isErDiagram(""));
}

test "er parser: empty diagram" {
    const allocator = std.testing.allocator;
    var diagram = try parse(allocator,
        \\erDiagram
    );
    defer diagram.deinit();
    try std.testing.expectEqual(@as(usize, 0), diagram.entityCount());
}

test "er parser: standalone entity" {
    const allocator = std.testing.allocator;
    var diagram = try parse(allocator,
        \\erDiagram
        \\    CUSTOMER
    );
    defer diagram.deinit();
    try std.testing.expectEqual(@as(usize, 1), diagram.entityCount());
    try std.testing.expect(diagram.getEntity("CUSTOMER") != null);
}

test "er parser: entity with alias" {
    const allocator = std.testing.allocator;
    var diagram = try parse(allocator,
        \\erDiagram
        \\    CUSTOMER["The Customer"]
    );
    defer diagram.deinit();
    const entity = diagram.getEntity("CUSTOMER").?;
    try std.testing.expectEqualStrings("The Customer", entity.displayName());
}

test "er parser: simple relationship" {
    const allocator = std.testing.allocator;
    var diagram = try parse(allocator,
        \\erDiagram
        \\    CUSTOMER ||--o{ ORDER : places
    );
    defer diagram.deinit();
    try std.testing.expectEqual(@as(usize, 2), diagram.entityCount());
    try std.testing.expectEqual(@as(usize, 1), diagram.relationshipCount());

    const rel = &diagram.relationships.items[0];
    try std.testing.expectEqualStrings("CUSTOMER", rel.entity_a);
    try std.testing.expectEqualStrings("ORDER", rel.entity_b);
    try std.testing.expectEqualStrings("places", rel.role);
    try std.testing.expectEqual(Cardinality.only_one, rel.rel_spec.card_a);
    try std.testing.expectEqual(Cardinality.zero_or_more, rel.rel_spec.card_b);
    try std.testing.expectEqual(Identification.identifying, rel.rel_spec.rel_type);
}

test "er parser: relationship with quoted role" {
    const allocator = std.testing.allocator;
    var diagram = try parse(allocator,
        \\erDiagram
        \\    CUSTOMER ||--o{ ORDER : "places an"
    );
    defer diagram.deinit();
    try std.testing.expectEqual(@as(usize, 1), diagram.relationshipCount());
    try std.testing.expectEqualStrings("places an", diagram.relationships.items[0].role);
}

test "er parser: non-identifying relationship" {
    const allocator = std.testing.allocator;
    var diagram = try parse(allocator,
        \\erDiagram
        \\    CUSTOMER ||..o{ ORDER : places
    );
    defer diagram.deinit();
    try std.testing.expectEqual(Identification.non_identifying, diagram.relationships.items[0].rel_spec.rel_type);
}

test "er parser: entity with attributes" {
    const allocator = std.testing.allocator;
    var diagram = try parse(allocator,
        \\erDiagram
        \\    CUSTOMER {
        \\        int id PK
        \\        string name
        \\        string email UK
        \\    }
    );
    defer diagram.deinit();
    try std.testing.expectEqual(@as(usize, 1), diagram.entityCount());
    const entity = diagram.getEntity("CUSTOMER").?;
    try std.testing.expectEqual(@as(usize, 3), entity.attributes.items.len);

    // First attribute: int id PK
    try std.testing.expectEqualStrings("int", entity.attributes.items[0].attr_type);
    try std.testing.expectEqualStrings("id", entity.attributes.items[0].name);
    try std.testing.expectEqual(@as(usize, 1), entity.attributes.items[0].keys.items.len);
    try std.testing.expectEqual(AttributeKey.primary_key, entity.attributes.items[0].keys.items[0]);

    // Second attribute: string name
    try std.testing.expectEqualStrings("string", entity.attributes.items[1].attr_type);
    try std.testing.expectEqualStrings("name", entity.attributes.items[1].name);
    try std.testing.expectEqual(@as(usize, 0), entity.attributes.items[1].keys.items.len);

    // Third attribute: string email UK
    try std.testing.expectEqualStrings("email", entity.attributes.items[2].name);
    try std.testing.expectEqual(AttributeKey.unique_key, entity.attributes.items[2].keys.items[0]);
}

test "er parser: attribute with comment" {
    const allocator = std.testing.allocator;
    var diagram = try parse(allocator,
        \\erDiagram
        \\    PRODUCT {
        \\        int id PK "product identifier"
        \\    }
    );
    defer diagram.deinit();
    const entity = diagram.getEntity("PRODUCT").?;
    try std.testing.expectEqual(@as(usize, 1), entity.attributes.items.len);
    try std.testing.expectEqualStrings("product identifier", entity.attributes.items[0].comment.?);
}

test "er parser: attribute with multiple keys" {
    const allocator = std.testing.allocator;
    var diagram = try parse(allocator,
        \\erDiagram
        \\    ORDER_ITEM {
        \\        int order_id PK,FK
        \\    }
    );
    defer diagram.deinit();
    const entity = diagram.getEntity("ORDER_ITEM").?;
    try std.testing.expectEqual(@as(usize, 2), entity.attributes.items[0].keys.items.len);
    try std.testing.expectEqual(AttributeKey.primary_key, entity.attributes.items[0].keys.items[0]);
    try std.testing.expectEqual(AttributeKey.foreign_key, entity.attributes.items[0].keys.items[1]);
}

test "er parser: multiple relationships" {
    const allocator = std.testing.allocator;
    var diagram = try parse(allocator,
        \\erDiagram
        \\    CUSTOMER ||--o{ ORDER : places
        \\    ORDER ||--|{ LINE-ITEM : contains
        \\    CUSTOMER }|..|{ DELIVERY-ADDRESS : uses
    );
    defer diagram.deinit();
    try std.testing.expectEqual(@as(usize, 4), diagram.entityCount());
    try std.testing.expectEqual(@as(usize, 3), diagram.relationshipCount());
}

test "er parser: self-referencing relationship" {
    const allocator = std.testing.allocator;
    var diagram = try parse(allocator,
        \\erDiagram
        \\    EMPLOYEE ||--o{ EMPLOYEE : manages
    );
    defer diagram.deinit();
    try std.testing.expectEqual(@as(usize, 1), diagram.entityCount());
    try std.testing.expectEqual(@as(usize, 1), diagram.relationshipCount());
}

test "er parser: title" {
    const allocator = std.testing.allocator;
    var diagram = try parse(allocator,
        \\erDiagram
        \\    title My ER Diagram
        \\    CUSTOMER
    );
    defer diagram.deinit();
    try std.testing.expectEqualStrings("My ER Diagram", diagram.title.?);
}

test "er parser: direction" {
    const allocator = std.testing.allocator;
    var diagram = try parse(allocator,
        \\erDiagram
        \\    direction LR
        \\    CUSTOMER
    );
    defer diagram.deinit();
    try std.testing.expectEqual(Direction.LR, diagram.direction);
}

test "er parser: comments ignored" {
    const allocator = std.testing.allocator;
    var diagram = try parse(allocator,
        \\erDiagram
        \\    %% this is a comment
        \\    CUSTOMER
    );
    defer diagram.deinit();
    try std.testing.expectEqual(@as(usize, 1), diagram.entityCount());
}

test "er parser: all cardinality types" {
    const allocator = std.testing.allocator;
    var diagram = try parse(allocator,
        \\erDiagram
        \\    A ||--|| B : r1
        \\    C |o--o| D : r2
        \\    E }o--o{ F : r3
        \\    G }|--|{ H : r4
    );
    defer diagram.deinit();
    try std.testing.expectEqual(@as(usize, 4), diagram.relationshipCount());

    // A ||--|| B
    try std.testing.expectEqual(Cardinality.only_one, diagram.relationships.items[0].rel_spec.card_a);
    try std.testing.expectEqual(Cardinality.only_one, diagram.relationships.items[0].rel_spec.card_b);

    // C |o--o| D  (zero_or_one on both sides)
    try std.testing.expectEqual(Cardinality.zero_or_one, diagram.relationships.items[1].rel_spec.card_a);
    try std.testing.expectEqual(Cardinality.zero_or_one, diagram.relationships.items[1].rel_spec.card_b);

    // E }o--o{ F  (zero_or_more on both sides)
    try std.testing.expectEqual(Cardinality.zero_or_more, diagram.relationships.items[2].rel_spec.card_a);
    try std.testing.expectEqual(Cardinality.zero_or_more, diagram.relationships.items[2].rel_spec.card_b);

    // G }|--|{ H  (one_or_more on both sides)
    try std.testing.expectEqual(Cardinality.one_or_more, diagram.relationships.items[3].rel_spec.card_a);
    try std.testing.expectEqual(Cardinality.one_or_more, diagram.relationships.items[3].rel_spec.card_b);
}

test "er parser: entity with hyphen and underscore" {
    const allocator = std.testing.allocator;
    var diagram = try parse(allocator,
        \\erDiagram
        \\    LINE-ITEM
        \\    ORDER_DETAIL
    );
    defer diagram.deinit();
    try std.testing.expectEqual(@as(usize, 2), diagram.entityCount());
    try std.testing.expect(diagram.getEntity("LINE-ITEM") != null);
    try std.testing.expect(diagram.getEntity("ORDER_DETAIL") != null);
}

test "er parser: empty attribute block" {
    const allocator = std.testing.allocator;
    var diagram = try parse(allocator,
        \\erDiagram
        \\    CUSTOMER {
        \\    }
    );
    defer diagram.deinit();
    try std.testing.expectEqual(@as(usize, 1), diagram.entityCount());
    const entity = diagram.getEntity("CUSTOMER").?;
    try std.testing.expectEqual(@as(usize, 0), entity.attributes.items.len);
}

test "er parser: complex diagram" {
    const allocator = std.testing.allocator;
    var diagram = try parse(allocator,
        \\erDiagram
        \\    CUSTOMER {
        \\        int id PK
        \\        string name
        \\    }
        \\    ORDER {
        \\        int id PK
        \\        int customer_id FK
        \\        date order_date
        \\    }
        \\    CUSTOMER ||--o{ ORDER : places
        \\    ORDER ||--|{ LINE-ITEM : contains
    );
    defer diagram.deinit();
    try std.testing.expectEqual(@as(usize, 3), diagram.entityCount());
    try std.testing.expectEqual(@as(usize, 2), diagram.relationshipCount());

    const customer = diagram.getEntity("CUSTOMER").?;
    try std.testing.expectEqual(@as(usize, 2), customer.attributes.items.len);

    const order = diagram.getEntity("ORDER").?;
    try std.testing.expectEqual(@as(usize, 3), order.attributes.items.len);
}

test "er parser: fixture diagrams parse successfully" {
    const allocator = std.testing.allocator;
    const fixtures = [_]struct {
        path: []const u8,
        min_entities: usize,
        min_relationships: usize,
        expected_entity: []const u8,
    }{
        .{ .path = "test-diagrams/er_simple.mmd", .min_entities = 3, .min_relationships = 2, .expected_entity = "CUSTOMER" },
        .{ .path = "test-diagrams/er_simple_v2.mmd", .min_entities = 3, .min_relationships = 2, .expected_entity = "AUTHOR" },
        .{ .path = "test-diagrams/er_complex.mmd", .min_entities = 8, .min_relationships = 8, .expected_entity = "PRODUCT" },
        .{ .path = "test-diagrams/er_complex_v2.mmd", .min_entities = 11, .min_relationships = 13, .expected_entity = "HOSPITAL" },
    };

    for (fixtures) |fixture| {
        const source = try std.fs.cwd().readFileAlloc(allocator, fixture.path, 1024 * 1024);
        defer allocator.free(source);

        try std.testing.expect(isErDiagram(source));

        var diagram = try parse(allocator, source);
        defer diagram.deinit();

        try std.testing.expect(diagram.entityCount() >= fixture.min_entities);
        try std.testing.expect(diagram.relationshipCount() >= fixture.min_relationships);
        try std.testing.expect(diagram.getEntity(fixture.expected_entity) != null);
    }
}
