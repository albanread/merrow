//! State diagram parser for Mermaid `stateDiagram` / `stateDiagram-v2` syntax.
//!
//! Supports the following grammar elements:
//!
//!   stateDiagram[-v2]
//!       [*] --> State1
//!       State1 --> State2 : label
//!       state State1 {
//!           [*] --> Inner1
//!           Inner1 --> [*]
//!       }
//!       state "Description" as State3
//!       state State4 <<fork>>
//!       state State5 <<join>>
//!       state State6 <<choice>>
//!       State1 : description text
//!       note right of State1 : note text
//!       note left of State1
//!           multiline note
//!       end note
//!       direction LR
//!       classDef myClass fill:#f00,stroke:#000
//!       class State1 myClass
//!       hide empty description
//!       %% comments
//!       accTitle: text
//!       accDescr: text

const std = @import("std");
const StateDiagram = @import("model.zig").StateDiagram;
const State = @import("model.zig").State;
const StateType = @import("model.zig").StateType;
const Direction = @import("model.zig").Direction;
const NotePosition = @import("model.zig").NotePosition;
const Relation = @import("model.zig").Relation;
const Statement = @import("model.zig").Statement;

pub const ParseError = error{
    InvalidSyntax,
    OutOfMemory,
    Overflow,
};

/// Parse a complete Mermaid state diagram source string into a `StateDiagram`.
/// Caller owns the returned `StateDiagram` and must call `.deinit()`.
pub fn parse(allocator: std.mem.Allocator, source: []const u8) ParseError!StateDiagram {
    var diagram = StateDiagram.init(allocator);
    errdefer diagram.deinit();

    var lines = LineIterator.init(source);
    var header_seen = false;
    var in_multiline_descr = false;

    // Stack for tracking composite state nesting.
    // Each entry is the parent state ID (owned, must be freed).
    var parent_stack = std.ArrayListUnmanaged([]const u8){};
    defer {
        for (parent_stack.items) |p| allocator.free(p);
        parent_stack.deinit(allocator);
    }

    // Track brace depth for composite states
    var brace_depth: usize = 0;

    while (lines.next()) |raw_line| {
        const line = trim(raw_line);

        // Skip empty lines
        if (line.len == 0) continue;

        // Skip %%{init: ...}%% directives
        if (startsWith(line, "%%{")) continue;

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
            if (startsWithCaseInsensitive(line, "stateDiagram")) {
                header_seen = true;
                // Skip optional -v2 suffix
                continue;
            }
            // Skip preamble lines before header
            continue;
        }

        // ── Handle multiline note end ───────────────────────────
        // Check if we're collecting note lines (handled at call site below)

        // ── Closing brace for composite state ───────────────────
        if (std.mem.eql(u8, line, "}")) {
            if (brace_depth > 0) {
                brace_depth -= 1;
                if (parent_stack.items.len > 0) {
                    const popped = parent_stack.items[parent_stack.items.len - 1];
                    parent_stack.items.len -= 1;
                    allocator.free(popped);
                }
            }
            continue;
        }

        // ── Body (after header) ─────────────────────────────────
        const current_parent: ?[]const u8 = if (parent_stack.items.len > 0)
            parent_stack.items[parent_stack.items.len - 1]
        else
            null;

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

        // hide empty description
        if (startsWithCaseInsensitive(line, "hide empty")) {
            diagram.hide_empty = true;
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

        // classDef <name> <styles>
        if (startsWithCaseInsensitive(line, "classDef") or startsWithCaseInsensitive(line, "classdef")) {
            const rest = trim(line[8..]);
            if (parseClassDef(rest)) |result| {
                try diagram.addClassDef(result.name, result.styles);
            }
            continue;
        }

        // class <stateId> <className>
        if (startsWithCaseInsensitive(line, "class ")) {
            const rest = trim(line[6..]);
            if (parseClassAssignment(rest)) |result| {
                try diagram.applyClass(result.state_id, result.class_name);
            }
            continue;
        }

        // scale <number> (ignored)
        if (startsWithCaseInsensitive(line, "scale")) continue;

        // style <ids> <styles> (ignored for now)
        if (startsWithCaseInsensitive(line, "style ")) continue;

        // note right of / note left of
        if (startsWithCaseInsensitive(line, "note")) {
            try parseNote(allocator, &diagram, line, &lines);
            continue;
        }

        // state keyword declarations
        if (startsWithCaseInsensitive(line, "state ") or startsWithCaseInsensitive(line, "state\t")) {
            // Make sure it's not just a state ID starting with "state" like "stateA"
            const after_state = line[5..];
            const trimmed_after = trim(after_state);
            if (trimmed_after.len > 0) {
                try parseStateDeclaration(allocator, &diagram, trimmed_after, current_parent, &parent_stack, &brace_depth);
                continue;
            }
        }

        // Divider: standalone -- (not part of arrow)
        if (std.mem.eql(u8, line, "--")) {
            const div_id = try diagram.nextDividerId();
            defer allocator.free(div_id);
            _ = try diagram.addStateWithType(div_id, .divider);
            continue;
        }

        // Transition: State1 --> State2 : label
        if (parseTransition(line)) |result| {
            if (result.label) |lbl| {
                const unescaped_lbl = try unescapeText(allocator, lbl);
                defer allocator.free(unescaped_lbl);
                try diagram.addRelation(result.from, result.to, unescaped_lbl, current_parent);
            } else {
                try diagram.addRelation(result.from, result.to, null, current_parent);
            }
            continue;
        }

        // State with description: StateId : description
        if (parseStateWithDescription(line)) |result| {
            const unescaped_desc = try unescapeText(allocator, result.description);
            defer allocator.free(unescaped_desc);
            try diagram.addDescription(result.id, unescaped_desc);
            if (current_parent) |p| {
                try diagram.setParent(result.id, p);
            }
            continue;
        }

        // Bare state ID (just a name on its own line)
        if (isValidStateId(line)) {
            _ = try diagram.ensureState(line);
            if (current_parent) |p| {
                try diagram.setParent(line, p);
            }
            continue;
        }

        // Unknown lines are silently ignored (lenient parsing)
    }

    return diagram;
}

// -----------------------------------------------------------------------
// State declaration parser
// -----------------------------------------------------------------------

fn parseStateDeclaration(
    allocator: std.mem.Allocator,
    diagram: *StateDiagram,
    rest: []const u8,
    current_parent: ?[]const u8,
    parent_stack: *std.ArrayListUnmanaged([]const u8),
    brace_depth: *usize,
) !void {
    // Case 1: state "Description" as StateId
    if (rest.len > 0 and rest[0] == '"') {
        if (parseQuotedAlias(rest)) |result| {
            const state = try diagram.ensureState(result.id);
            if (state.alias == null) {
                state.alias = try allocator.dupe(u8, result.description);
                state.alias_owned = true;
            }
            if (current_parent) |p| {
                try diagram.setParent(result.id, p);
            }
            // Check if followed by { for composite
            if (result.has_body) {
                brace_depth.* += 1;
                try parent_stack.append(allocator, try allocator.dupe(u8, result.id));
            }
            return;
        }
    }

    // Case 2: state StateId <<fork|join|choice>>
    if (parseSpecialState(rest)) |result| {
        _ = try diagram.addStateWithType(result.id, result.state_type);
        if (current_parent) |p| {
            try diagram.setParent(result.id, p);
        }
        return;
    }

    // Case 3: state StateId { ... } (composite state with body)
    // Find the state ID, then check for { at end
    var id_end: usize = 0;
    // ID can be a quoted string or plain identifier
    if (rest.len > 0 and rest[0] == '"') {
        // Quoted: find closing quote
        var pos: usize = 1;
        while (pos < rest.len and rest[pos] != '"') pos += 1;
        if (pos < rest.len) pos += 1; // skip closing quote
        id_end = pos;
    } else {
        while (id_end < rest.len and !isWhitespace(rest[id_end]) and rest[id_end] != '{' and rest[id_end] != ':') {
            id_end += 1;
        }
    }

    if (id_end == 0) return;

    const raw_id = trim(rest[0..id_end]);
    // Strip quotes if present
    const state_id = if (raw_id.len >= 2 and raw_id[0] == '"' and raw_id[raw_id.len - 1] == '"')
        raw_id[1 .. raw_id.len - 1]
    else
        raw_id;

    if (state_id.len == 0) return;

    const after_id = trim(rest[id_end..]);

    // Check for alias: `state StateId as "Alias"`
    if (after_id.len >= 3 and startsWithCaseInsensitive(after_id, "as ")) {
        const alias_part = trim(after_id[3..]);
        const alias_text = if (alias_part.len >= 2 and alias_part[0] == '"' and alias_part[alias_part.len - 1] == '"')
            alias_part[1 .. alias_part.len - 1]
        else
            alias_part;
        if (alias_text.len > 0) {
            const state = try diagram.ensureState(state_id);
            if (state.alias == null) {
                state.alias = try allocator.dupe(u8, alias_text);
                state.alias_owned = true;
            }
        }
        if (current_parent) |p| {
            try diagram.setParent(state_id, p);
        }
        return;
    }

    // Check for composite body {
    if (after_id.len > 0 and after_id[0] == '{') {
        _ = try diagram.ensureState(state_id);
        if (current_parent) |p| {
            try diagram.setParent(state_id, p);
        }
        brace_depth.* += 1;
        try parent_stack.append(allocator, try allocator.dupe(u8, state_id));
        return;
    }

    // Check for description: state StateId : description
    if (after_id.len > 0 and after_id[0] == ':') {
        const desc = trim(after_id[1..]);
        if (desc.len > 0) {
            const unescaped_desc = try unescapeText(allocator, desc);
            defer allocator.free(unescaped_desc);
            try diagram.addDescription(state_id, unescaped_desc);
        } else {
            _ = try diagram.ensureState(state_id);
        }
        if (current_parent) |p| {
            try diagram.setParent(state_id, p);
        }
        return;
    }

    // Simple state declaration
    _ = try diagram.ensureState(state_id);
    if (current_parent) |p| {
        try diagram.setParent(state_id, p);
    }
}

// -----------------------------------------------------------------------
// Transition parser: State1 --> State2 : label
// -----------------------------------------------------------------------

const TransitionResult = struct {
    from: []const u8,
    to: []const u8,
    label: ?[]const u8,
};

fn parseTransition(line: []const u8) ?TransitionResult {
    // Find --> or -> arrow
    const arrow_idx = findArrow(line) orelse return null;
    const arrow_len = arrowLength(line, arrow_idx);

    const from_part = trim(line[0..arrow_idx]);
    if (from_part.len == 0) return null;

    const after_arrow = line[arrow_idx + arrow_len ..];
    // Split after_arrow on : for label
    var to_part: []const u8 = undefined;
    var label_part: ?[]const u8 = null;

    if (std.mem.indexOf(u8, after_arrow, ":")) |colon_idx| {
        to_part = trim(after_arrow[0..colon_idx]);
        const raw_label = trim(after_arrow[colon_idx + 1 ..]);
        if (raw_label.len > 0) {
            label_part = raw_label;
        }
    } else {
        to_part = trim(after_arrow);
    }

    if (to_part.len == 0) return null;

    return .{
        .from = from_part,
        .to = to_part,
        .label = label_part,
    };
}

fn findArrow(line: []const u8) ?usize {
    // Look for --> first
    if (std.mem.indexOf(u8, line, "-->")) |idx| return idx;
    // Then -> (but be careful not to match inside -->)
    if (std.mem.indexOf(u8, line, "->")) |idx| return idx;
    return null;
}

fn arrowLength(line: []const u8, idx: usize) usize {
    if (idx + 2 < line.len and line[idx] == '-' and line[idx + 1] == '-' and line[idx + 2] == '>') {
        return 3; // -->
    }
    return 2; // ->
}

// -----------------------------------------------------------------------
// State with description: StateId : description
// -----------------------------------------------------------------------

const StateDescResult = struct {
    id: []const u8,
    description: []const u8,
};

fn parseStateWithDescription(line: []const u8) ?StateDescResult {
    const colon_idx = std.mem.indexOf(u8, line, ":") orelse return null;
    if (colon_idx == 0) return null;

    const id = trim(line[0..colon_idx]);
    const desc = trim(line[colon_idx + 1 ..]);

    if (id.len == 0 or desc.len == 0) return null;
    if (!isValidStateId(id)) return null;

    return .{
        .id = id,
        .description = desc,
    };
}

// -----------------------------------------------------------------------
// Special state: state StateId <<fork|join|choice>> or [[fork|join|choice]]
// -----------------------------------------------------------------------

const SpecialStateResult = struct {
    id: []const u8,
    state_type: StateType,
};

fn parseSpecialState(rest: []const u8) ?SpecialStateResult {
    // rest is everything after "state "
    // Format: StateId <<type>> or StateId [[type]]
    var pos: usize = 0;

    // Read state ID
    while (pos < rest.len and !isWhitespace(rest[pos]) and rest[pos] != '<' and rest[pos] != '[') {
        pos += 1;
    }
    if (pos == 0) return null;
    const id = rest[0..pos];

    // Skip whitespace
    while (pos < rest.len and isWhitespace(rest[pos])) pos += 1;

    // Check for << >> markers
    if (pos + 2 < rest.len and rest[pos] == '<' and rest[pos + 1] == '<') {
        pos += 2;
        const type_start = pos;
        while (pos < rest.len and rest[pos] != '>' and rest[pos] != '<') pos += 1;
        const type_str = trim(rest[type_start..pos]);
        if (type_str.len > 0) {
            const st = StateType.fromStr(type_str);
            if (st != .default) {
                return .{ .id = id, .state_type = st };
            }
        }
        return null;
    }

    // Check for [[ ]] markers
    if (pos + 2 < rest.len and rest[pos] == '[' and rest[pos + 1] == '[') {
        pos += 2;
        const type_start = pos;
        while (pos < rest.len and rest[pos] != ']') pos += 1;
        const type_str = trim(rest[type_start..pos]);
        if (type_str.len > 0) {
            const st = StateType.fromStr(type_str);
            if (st != .default) {
                return .{ .id = id, .state_type = st };
            }
        }
        return null;
    }

    return null;
}

// -----------------------------------------------------------------------
// Quoted alias: "Description" as StateId [{ ... }]
// -----------------------------------------------------------------------

const QuotedAliasResult = struct {
    id: []const u8,
    description: []const u8,
    has_body: bool,
};

fn parseQuotedAlias(rest: []const u8) ?QuotedAliasResult {
    if (rest.len < 2 or rest[0] != '"') return null;

    // Find closing quote
    var pos: usize = 1;
    while (pos < rest.len and rest[pos] != '"') pos += 1;
    if (pos >= rest.len) return null;

    const description = rest[1..pos];
    pos += 1; // skip closing quote

    // Skip whitespace
    while (pos < rest.len and isWhitespace(rest[pos])) pos += 1;

    // Expect "as"
    if (pos + 2 > rest.len) return null;
    if (!eqlIgnoreCase(rest[pos .. pos + 2], "as")) return null;
    pos += 2;

    // Skip whitespace
    while (pos < rest.len and isWhitespace(rest[pos])) pos += 1;

    // Read state ID
    const id_start = pos;
    while (pos < rest.len and !isWhitespace(rest[pos]) and rest[pos] != '{') {
        pos += 1;
    }
    if (pos == id_start) return null;

    const id = rest[id_start..pos];

    // Check for { after whitespace
    while (pos < rest.len and isWhitespace(rest[pos])) pos += 1;
    const has_body = (pos < rest.len and rest[pos] == '{');

    return .{
        .id = id,
        .description = description,
        .has_body = has_body,
    };
}

// -----------------------------------------------------------------------
// Note parser
// -----------------------------------------------------------------------

fn parseNote(
    allocator: std.mem.Allocator,
    diagram: *StateDiagram,
    line: []const u8,
    lines: *LineIterator,
) !void {
    // Skip "note" keyword
    var rest = trim(line[4..]);

    // Parse position: "right of" or "left of"
    var position: NotePosition = .right_of;
    if (startsWithCaseInsensitive(rest, "right of")) {
        position = .right_of;
        rest = trim(rest[8..]);
    } else if (startsWithCaseInsensitive(rest, "left of")) {
        position = .left_of;
        rest = trim(rest[7..]);
    } else if (startsWithCaseInsensitive(rest, "right")) {
        position = .right_of;
        rest = trim(rest[5..]);
        // skip optional "of"
        if (startsWithCaseInsensitive(rest, "of")) {
            rest = trim(rest[2..]);
        }
    } else if (startsWithCaseInsensitive(rest, "left")) {
        position = .left_of;
        rest = trim(rest[4..]);
        // skip optional "of"
        if (startsWithCaseInsensitive(rest, "of")) {
            rest = trim(rest[2..]);
        }
    }

    // Parse state ID
    var id_end: usize = 0;
    while (id_end < rest.len and !isWhitespace(rest[id_end]) and rest[id_end] != ':' and rest[id_end] != '\n') {
        id_end += 1;
    }
    if (id_end == 0) return;
    const state_id = rest[0..id_end];
    rest = trim(rest[id_end..]);

    // Inline note: note right of State1 : text
    if (rest.len > 0 and rest[0] == ':') {
        const note_text = trim(rest[1..]);
        if (note_text.len > 0) {
            const unescaped = try unescapeText(allocator, note_text);
            defer allocator.free(unescaped);
            try diagram.addNote(state_id, position, unescaped);
        }
        return;
    }

    // Multiline note: collect until "end note"
    var note_buf = std.ArrayListUnmanaged(u8){};
    defer note_buf.deinit(allocator);

    while (lines.next()) |note_line| {
        const trimmed = trim(note_line);
        if (startsWithCaseInsensitive(trimmed, "end note") or startsWithCaseInsensitive(trimmed, "endnote")) {
            break;
        }
        if (note_buf.items.len > 0) {
            try note_buf.append(allocator, '\n');
        }
        try note_buf.appendSlice(allocator, trimmed);
    }

    if (note_buf.items.len > 0) {
        try diagram.addNote(state_id, position, note_buf.items);
    }
}

// -----------------------------------------------------------------------
// classDef parser: name styles
// -----------------------------------------------------------------------

const ClassDefResult = struct {
    name: []const u8,
    styles: []const u8,
};

fn parseClassDef(rest: []const u8) ?ClassDefResult {
    // rest is everything after "classDef "
    const trimmed = trim(rest);
    if (trimmed.len == 0) return null;

    // Name is first word
    var pos: usize = 0;
    while (pos < trimmed.len and !isWhitespace(trimmed[pos])) pos += 1;
    if (pos == 0) return null;
    const name = trimmed[0..pos];

    // Styles is the rest
    const styles = trim(trimmed[pos..]);
    if (styles.len == 0) return null;

    return .{ .name = name, .styles = styles };
}

// -----------------------------------------------------------------------
// class assignment parser: stateId className
// -----------------------------------------------------------------------

const ClassAssignResult = struct {
    state_id: []const u8,
    class_name: []const u8,
};

fn parseClassAssignment(rest: []const u8) ?ClassAssignResult {
    const trimmed = trim(rest);
    if (trimmed.len == 0) return null;

    // state IDs (comma separated) then class name
    // Simple case: single stateId className
    var pos: usize = 0;
    while (pos < trimmed.len and !isWhitespace(trimmed[pos])) pos += 1;
    if (pos == 0) return null;
    const state_id = trimmed[0..pos];

    while (pos < trimmed.len and isWhitespace(trimmed[pos])) pos += 1;

    var end: usize = pos;
    while (end < trimmed.len and !isWhitespace(trimmed[end])) end += 1;
    if (end == pos) return null;
    const class_name = trimmed[pos..end];

    return .{ .state_id = state_id, .class_name = class_name };
}

// -----------------------------------------------------------------------
// Diagram type detection
// -----------------------------------------------------------------------

/// Returns true if `source` starts with the `stateDiagram` keyword
/// (after optional leading whitespace / directives).
pub fn isStateDiagram(source: []const u8) bool {
    var i: usize = 0;

    // Skip leading whitespace
    while (i < source.len and isWhitespace(source[i])) i += 1;

    // Skip %%{init: ...}%% directive
    if (i + 3 <= source.len and std.mem.eql(u8, source[i .. i + 3], "%%{")) {
        while (i < source.len and source[i] != '\n') i += 1;
        while (i < source.len and isWhitespace(source[i])) i += 1;
    }

    // Check for "stateDiagram" keyword (case-insensitive)
    const keyword = "stateDiagram";
    if (i + keyword.len > source.len) return false;
    if (!eqlIgnoreCase(source[i .. i + keyword.len], keyword)) return false;

    // After keyword, allow -v2, whitespace, or EOL/EOF
    const after = i + keyword.len;
    if (after >= source.len) return true;
    const next = source[after];
    if (next == '-' or next == ' ' or next == '\t' or next == '\r' or next == '\n') return true;

    return false;
}

// -----------------------------------------------------------------------
// Validation helpers
// -----------------------------------------------------------------------

fn isValidStateId(s: []const u8) bool {
    if (s.len == 0) return false;
    // [*] is a valid state reference
    if (std.mem.eql(u8, s, "[*]")) return true;
    // State IDs: letters, digits, underscores
    for (s) |c| {
        if (!isAlphaNumeric(c) and c != '_') return false;
    }
    return true;
}

fn isAlphaNumeric(c: u8) bool {
    return (c >= 'a' and c <= 'z') or (c >= 'A' and c <= 'Z') or (c >= '0' and c <= '9');
}

// -----------------------------------------------------------------------
// Text escape processing
// -----------------------------------------------------------------------

/// Convert literal escape sequences in parsed text to their actual characters.
/// Handles: \n → newline, \t → tab, \\ → backslash.
/// Caller owns the returned slice.
fn unescapeText(allocator: std.mem.Allocator, text: []const u8) ![]u8 {
    var result = std.ArrayListUnmanaged(u8){};
    errdefer result.deinit(allocator);

    var i: usize = 0;
    while (i < text.len) {
        if (i + 1 < text.len and text[i] == '\\') {
            switch (text[i + 1]) {
                'n' => {
                    try result.append(allocator, '\n');
                    i += 2;
                },
                't' => {
                    try result.append(allocator, '\t');
                    i += 2;
                },
                '\\' => {
                    try result.append(allocator, '\\');
                    i += 2;
                },
                else => {
                    try result.append(allocator, text[i]);
                    i += 1;
                },
            }
        } else {
            try result.append(allocator, text[i]);
            i += 1;
        }
    }

    return try result.toOwnedSlice(allocator);
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
        // Strip trailing \r
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

test "state parser: isStateDiagram detection" {
    try std.testing.expect(isStateDiagram("stateDiagram\n  [*] --> Idle"));
    try std.testing.expect(isStateDiagram("stateDiagram-v2\n  [*] --> Idle"));
    try std.testing.expect(isStateDiagram("  stateDiagram\n  [*] --> Idle"));
    try std.testing.expect(!isStateDiagram("flowchart TD\n  A-->B"));
    try std.testing.expect(!isStateDiagram("sequenceDiagram\n  A->>B: Hi"));
    try std.testing.expect(!isStateDiagram("pie\n  \"A\" : 1"));
    try std.testing.expect(!isStateDiagram("classDiagram\n  class A"));
}

test "state parser: empty diagram" {
    const allocator = std.testing.allocator;
    var diagram = try parse(allocator, "stateDiagram\n");
    defer diagram.deinit();

    try std.testing.expectEqual(@as(usize, 0), diagram.stateCount());
    try std.testing.expectEqual(@as(usize, 0), diagram.relationCount());
}

test "state parser: simple transition" {
    const allocator = std.testing.allocator;
    var diagram = try parse(allocator,
        \\stateDiagram
        \\    [*] --> Idle
        \\    Idle --> Active
        \\    Active --> [*]
    );
    defer diagram.deinit();

    try std.testing.expectEqual(@as(usize, 3), diagram.relationCount());
    // [*] source -> root_start, [*] target -> root_end
    try std.testing.expectEqualStrings("root_start", diagram.relations.items[0].from);
    try std.testing.expectEqualStrings("Idle", diagram.relations.items[0].to);
    try std.testing.expectEqualStrings("Idle", diagram.relations.items[1].from);
    try std.testing.expectEqualStrings("Active", diagram.relations.items[1].to);
    try std.testing.expectEqualStrings("Active", diagram.relations.items[2].from);
    try std.testing.expectEqualStrings("root_end", diagram.relations.items[2].to);
}

test "state parser: transition with label" {
    const allocator = std.testing.allocator;
    var diagram = try parse(allocator,
        \\stateDiagram-v2
        \\    Idle --> Active : user clicks
        \\    Active --> Idle : timeout
    );
    defer diagram.deinit();

    try std.testing.expectEqual(@as(usize, 2), diagram.relationCount());
    try std.testing.expectEqualStrings("user clicks", diagram.relations.items[0].label.?);
    try std.testing.expectEqualStrings("timeout", diagram.relations.items[1].label.?);
}

test "state parser: state with description" {
    const allocator = std.testing.allocator;
    var diagram = try parse(allocator,
        \\stateDiagram
        \\    Idle : Waiting for input
        \\    Active : Processing data
    );
    defer diagram.deinit();

    try std.testing.expectEqual(@as(usize, 2), diagram.stateCount());
    const idle = diagram.getState("Idle").?;
    try std.testing.expectEqualStrings("Waiting for input", idle.description.?);
    const active = diagram.getState("Active").?;
    try std.testing.expectEqualStrings("Processing data", active.description.?);
}

test "state parser: special state types" {
    const allocator = std.testing.allocator;
    var diagram = try parse(allocator,
        \\stateDiagram-v2
        \\    state forkNode <<fork>>
        \\    state joinNode <<join>>
        \\    state choiceNode <<choice>>
    );
    defer diagram.deinit();

    try std.testing.expectEqual(@as(usize, 3), diagram.stateCount());
    const fork = diagram.getState("forkNode").?;
    try std.testing.expectEqual(StateType.fork, fork.state_type);
    const join_state = diagram.getState("joinNode").?;
    try std.testing.expectEqual(StateType.join, join_state.state_type);
    const choice = diagram.getState("choiceNode").?;
    try std.testing.expectEqual(StateType.choice, choice.state_type);
}

test "state parser: quoted alias" {
    const allocator = std.testing.allocator;
    var diagram = try parse(allocator,
        \\stateDiagram-v2
        \\    state "Idle State" as Idle
    );
    defer diagram.deinit();

    const state = diagram.getState("Idle").?;
    try std.testing.expect(state.alias != null);
    try std.testing.expectEqualStrings("Idle State", state.alias.?);
}

test "state parser: direction" {
    const allocator = std.testing.allocator;
    var diagram = try parse(allocator,
        \\stateDiagram
        \\    direction LR
        \\    [*] --> Idle
    );
    defer diagram.deinit();

    try std.testing.expectEqual(Direction.LR, diagram.direction);
}

test "state parser: hide empty description" {
    const allocator = std.testing.allocator;
    var diagram = try parse(allocator,
        \\stateDiagram
        \\    hide empty description
        \\    [*] --> Idle
    );
    defer diagram.deinit();

    try std.testing.expect(diagram.hide_empty);
}

test "state parser: unescapeText basics" {
    const allocator = std.testing.allocator;

    // \n becomes a real newline
    const r1 = try unescapeText(allocator, "hello\\nworld");
    defer allocator.free(r1);
    try std.testing.expectEqualStrings("hello\nworld", r1);

    // \t becomes a real tab
    const r2 = try unescapeText(allocator, "col1\\tcol2");
    defer allocator.free(r2);
    try std.testing.expectEqualStrings("col1\tcol2", r2);

    // \\ becomes a single backslash
    const r3 = try unescapeText(allocator, "path\\\\file");
    defer allocator.free(r3);
    try std.testing.expectEqualStrings("path\\file", r3);

    // No escapes → unchanged
    const r4 = try unescapeText(allocator, "plain text");
    defer allocator.free(r4);
    try std.testing.expectEqualStrings("plain text", r4);

    // Multiple \n in a row
    const r5 = try unescapeText(allocator, "a\\nb\\nc");
    defer allocator.free(r5);
    try std.testing.expectEqualStrings("a\nb\nc", r5);

    // Unknown escape is kept literally
    const r6 = try unescapeText(allocator, "hello\\xworld");
    defer allocator.free(r6);
    try std.testing.expectEqualStrings("hello\\xworld", r6);
}

test "state parser: inline note" {
    const allocator = std.testing.allocator;
    var diagram = try parse(allocator,
        \\stateDiagram
        \\    [*] --> Idle
        \\    note right of Idle : This is a note
    );
    defer diagram.deinit();

    const state = diagram.getState("Idle").?;
    try std.testing.expect(state.note != null);
    try std.testing.expectEqualStrings("This is a note", state.note.?.text);
    try std.testing.expectEqual(NotePosition.right_of, state.note.?.position);
}

test "state parser: inline note with escaped newline" {
    const allocator = std.testing.allocator;
    var diagram = try parse(allocator,
        \\stateDiagram
        \\    [*] --> Idle
        \\    note right of Idle : Line one\nLine two
    );
    defer diagram.deinit();

    const state = diagram.getState("Idle").?;
    try std.testing.expect(state.note != null);
    // The literal \n in the source should become a real newline
    try std.testing.expectEqualStrings("Line one\nLine two", state.note.?.text);
}

test "state parser: transition label with escaped newline" {
    const allocator = std.testing.allocator;
    var diagram = try parse(allocator,
        \\stateDiagram
        \\    Idle --> Active : Start\nprocess
    );
    defer diagram.deinit();

    try std.testing.expectEqual(@as(usize, 1), diagram.relationCount());
    const rel = diagram.relations.items[0];
    try std.testing.expect(rel.label != null);
    try std.testing.expectEqualStrings("Start\nprocess", rel.label.?);
}

test "state parser: description with escaped newline" {
    const allocator = std.testing.allocator;
    var diagram = try parse(allocator,
        \\stateDiagram
        \\    Idle : Waiting\nfor input
    );
    defer diagram.deinit();

    const state = diagram.getState("Idle").?;
    try std.testing.expect(state.description != null);
    try std.testing.expectEqualStrings("Waiting\nfor input", state.description.?);
}

test "state parser: multiline note" {
    const allocator = std.testing.allocator;
    var diagram = try parse(allocator,
        \\stateDiagram
        \\    [*] --> Idle
        \\    note left of Idle
        \\        Line one
        \\        Line two
        \\    end note
    );
    defer diagram.deinit();

    const state = diagram.getState("Idle").?;
    try std.testing.expect(state.note != null);
    try std.testing.expectEqual(NotePosition.left_of, state.note.?.position);
    // Should contain both lines
    try std.testing.expect(std.mem.indexOf(u8, state.note.?.text, "Line one") != null);
    try std.testing.expect(std.mem.indexOf(u8, state.note.?.text, "Line two") != null);
}

test "state parser: composite state" {
    const allocator = std.testing.allocator;
    var diagram = try parse(allocator,
        \\stateDiagram-v2
        \\    [*] --> Outer
        \\    state Outer {
        \\        [*] --> Inner1
        \\        Inner1 --> Inner2
        \\        Inner2 --> [*]
        \\    }
    );
    defer diagram.deinit();

    // Inner states should have parent set
    if (diagram.getState("Inner1")) |inner| {
        try std.testing.expect(inner.parent != null);
        try std.testing.expectEqualStrings("Outer", inner.parent.?);
    }

    // Should have transitions with parent-scoped [*] states
    // [*] inside Outer becomes Outer_start and Outer_end
    var found_outer_start = false;
    var found_outer_end = false;
    for (diagram.relations.items) |rel| {
        if (std.mem.eql(u8, rel.from, "Outer_start")) found_outer_start = true;
        if (std.mem.eql(u8, rel.to, "Outer_end")) found_outer_end = true;
    }
    try std.testing.expect(found_outer_start);
    try std.testing.expect(found_outer_end);
}

test "state parser: comments ignored" {
    const allocator = std.testing.allocator;
    var diagram = try parse(allocator,
        \\stateDiagram
        \\    %% this is a comment
        \\    [*] --> Idle
    );
    defer diagram.deinit();

    try std.testing.expectEqual(@as(usize, 1), diagram.relationCount());
}

test "state parser: classDef and class" {
    const allocator = std.testing.allocator;
    var diagram = try parse(allocator,
        \\stateDiagram
        \\    classDef highlight fill:#ff0,stroke:#000
        \\    class Idle highlight
        \\    [*] --> Idle
    );
    defer diagram.deinit();

    const state = diagram.getState("Idle").?;
    try std.testing.expectEqual(@as(usize, 1), state.classes.items.len);
    try std.testing.expectEqualStrings("highlight", state.classes.items[0].data);
}

test "state parser: v2 syntax" {
    const allocator = std.testing.allocator;
    var diagram = try parse(allocator,
        \\stateDiagram-v2
        \\    [*] --> Still
        \\    Still --> [*]
        \\    Still --> Moving
        \\    Moving --> Still
        \\    Moving --> Crash
        \\    Crash --> [*]
    );
    defer diagram.deinit();

    try std.testing.expectEqual(@as(usize, 6), diagram.relationCount());
    // Should have Still, Moving, Crash plus root_start and root_end
    try std.testing.expect(diagram.getState("Still") != null);
    try std.testing.expect(diagram.getState("Moving") != null);
    try std.testing.expect(diagram.getState("Crash") != null);
    try std.testing.expect(diagram.getState("root_start") != null);
    try std.testing.expect(diagram.getState("root_end") != null);
}

test "state parser: state declaration with description" {
    const allocator = std.testing.allocator;
    var diagram = try parse(allocator,
        \\stateDiagram-v2
        \\    state Idle : Waiting for user
    );
    defer diagram.deinit();

    const state = diagram.getState("Idle").?;
    try std.testing.expect(state.description != null);
    try std.testing.expectEqualStrings("Waiting for user", state.description.?);
}

test "state parser: bracket choice syntax" {
    const allocator = std.testing.allocator;
    var diagram = try parse(allocator,
        \\stateDiagram-v2
        \\    state checkResult [[choice]]
    );
    defer diagram.deinit();

    const state = diagram.getState("checkResult").?;
    try std.testing.expectEqual(StateType.choice, state.state_type);
}

test "state parser: complex diagram" {
    const allocator = std.testing.allocator;
    var diagram = try parse(allocator,
        \\stateDiagram-v2
        \\    [*] --> Still
        \\    Still --> [*]
        \\    Still --> Moving
        \\    Moving --> Still
        \\    Moving --> Crash
        \\    Crash --> [*]
        \\
        \\    Still : Not moving
        \\    Moving : In motion
        \\    Crash : Collision detected
        \\
        \\    note right of Still : This is a note
    );
    defer diagram.deinit();

    try std.testing.expectEqual(@as(usize, 6), diagram.relationCount());
    const still = diagram.getState("Still").?;
    try std.testing.expectEqualStrings("Not moving", still.description.?);
    try std.testing.expect(still.note != null);
    try std.testing.expectEqualStrings("This is a note", still.note.?.text);
}

test "state parser: state with alias and body" {
    const allocator = std.testing.allocator;
    var diagram = try parse(allocator,
        \\stateDiagram-v2
        \\    state "Ready State" as Ready {
        \\        [*] --> Warmup
        \\        Warmup --> Done
        \\    }
    );
    defer diagram.deinit();

    const ready = diagram.getState("Ready").?;
    try std.testing.expect(ready.alias != null);
    try std.testing.expectEqualStrings("Ready State", ready.alias.?);

    // Inner states should have parent
    if (diagram.getState("Warmup")) |warmup| {
        try std.testing.expect(warmup.parent != null);
        try std.testing.expectEqualStrings("Ready", warmup.parent.?);
    }
}
