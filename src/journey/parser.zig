//! User journey diagram parser for Mermaid `journey` syntax.
//!
//! Supports the following grammar:
//!
//!   journey
//!       title My working day
//!       section Go to work
//!           Make tea: 5: Me
//!           Go upstairs: 3: Me, Cat
//!           Do work: 1: Me, Cat, Dog
//!       section Go home
//!           Go downstairs: 5: Me
//!           Sit down: 5: Me
//!
//! Also handles:
//!   - `%%` comments
//!   - `accTitle: <text>` (parsed but stored in model)
//!   - `accDescr: <text>` and `accDescr { ... }` (parsed but stored)
//!   - `%%{init: ...}%%` directives (skipped)

const std = @import("std");
const JourneyDiagram = @import("model.zig").JourneyDiagram;

pub const ParseError = error{
    InvalidSyntax,
    OutOfMemory,
    Overflow,
};

/// Parse a complete Mermaid journey diagram source string into a `JourneyDiagram`.
/// Caller owns the returned `JourneyDiagram` and must call `.deinit()`.
pub fn parse(allocator: std.mem.Allocator, source: []const u8) ParseError!JourneyDiagram {
    var diagram = JourneyDiagram.init(allocator);
    errdefer diagram.deinit();

    var line_iter = LineIterator.init(source);
    var header_seen = false;
    var in_multiline_descr = false;

    while (line_iter.next()) |raw_line| {
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
            if (startsWithCaseInsensitive(line, "journey")) {
                header_seen = true;
                continue;
            }
            // Skip preamble lines before header
            continue;
        }

        // ── Body (after header) ─────────────────────────────────

        // accTitle: <text>
        if (startsWithCaseInsensitive(line, "accTitle")) {
            const after = skipPastColon(line, 8);
            if (after.len > 0) {
                try diagram.setAccTitle(after);
            }
            continue;
        }

        // accDescr { ... } (multiline) or accDescr: <text>
        if (startsWithCaseInsensitive(line, "accDescr")) {
            if (std.mem.indexOf(u8, line, "{") != null) {
                in_multiline_descr = true;
            } else {
                const after = skipPastColon(line, 8);
                if (after.len > 0) {
                    try diagram.setAccDescr(after);
                }
            }
            continue;
        }

        // title <text>
        if (startsWithCaseInsensitive(line, "title")) {
            const title_text = trim(line[5..]);
            if (title_text.len > 0) {
                // Handle "title : text" or "title text"
                if (title_text.len > 0 and title_text[0] == ':') {
                    const after_colon = trim(title_text[1..]);
                    if (after_colon.len > 0) {
                        try diagram.setTitle(after_colon);
                    }
                } else {
                    try diagram.setTitle(title_text);
                }
            }
            continue;
        }

        // section <name>
        if (startsWithCaseInsensitive(line, "section")) {
            const section_name = trim(line[7..]);
            if (section_name.len > 0) {
                try diagram.addSection(section_name);
            }
            continue;
        }

        // Task line: TaskName: score: actor1, actor2, ...
        // Or: TaskName: score
        if (parseTaskLine(line)) |result| {
            try diagram.addTask(result.task_name, result.task_data);
            continue;
        }

        // Unknown lines are silently ignored (lenient parsing)
    }

    return diagram;
}

// -----------------------------------------------------------------------
// Task line parser
// -----------------------------------------------------------------------

const TaskLineResult = struct {
    task_name: []const u8,
    task_data: []const u8,
};

/// Try to parse a line matching `TaskName: score: actor1, actor2`
/// The task name is everything before the first colon.
/// The task data is everything after the first colon.
fn parseTaskLine(line: []const u8) ?TaskLineResult {
    // Find the first colon
    const colon_idx = std.mem.indexOf(u8, line, ":") orelse return null;

    // Task name must not be empty
    const task_name = trim(line[0..colon_idx]);
    if (task_name.len == 0) return null;

    // Task data is everything after the first colon
    const task_data = line[colon_idx + 1 ..];

    // The task data should contain at least a score (a number)
    // Quick sanity check: there should be a digit somewhere in the data
    var has_digit = false;
    for (task_data) |c| {
        if (c >= '0' and c <= '9') {
            has_digit = true;
            break;
        }
    }
    if (!has_digit) return null;

    return .{
        .task_name = task_name,
        .task_data = task_data,
    };
}

// -----------------------------------------------------------------------
// Diagram type detection
// -----------------------------------------------------------------------

/// Returns true if `source` starts with the `journey` keyword
/// (after optional leading whitespace / directives).
pub fn isJourneyDiagram(source: []const u8) bool {
    var i: usize = 0;

    // Skip leading whitespace
    while (i < source.len and isWhitespace(source[i])) i += 1;

    // Skip %%{init: ...}%% directive on the first line if present
    if (i + 3 <= source.len and std.mem.eql(u8, source[i .. i + 3], "%%{")) {
        while (i < source.len and source[i] != '\n') i += 1;
        while (i < source.len and isWhitespace(source[i])) i += 1;
    }

    // Check for "journey" keyword (case-insensitive)
    const keyword = "journey";
    if (i + keyword.len > source.len) return false;
    if (!eqlIgnoreCase(source[i .. i + keyword.len], keyword)) return false;

    // After keyword, must be followed by whitespace, EOL, or EOF
    const after = i + keyword.len;
    if (after >= source.len) return true;
    const next = source[after];
    if (next == ' ' or next == '\t' or next == '\r' or next == '\n') return true;

    return false;
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
        // Strip trailing \r for Windows line endings
        const line_end = if (end > start and self.source[end - 1] == '\r') end - 1 else end;
        return self.source[start..line_end];
    }
};

/// Skip past "keyword" of given length and any following colon+whitespace
fn skipPastColon(line: []const u8, keyword_len: usize) []const u8 {
    var pos = keyword_len;
    // Skip whitespace
    while (pos < line.len and isWhitespace(line[pos])) pos += 1;
    // Skip optional colon
    if (pos < line.len and line[pos] == ':') pos += 1;
    // Skip whitespace after colon
    while (pos < line.len and isWhitespace(line[pos])) pos += 1;
    return trim(line[pos..]);
}

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

test "journey parser: isJourneyDiagram detection" {
    try std.testing.expect(isJourneyDiagram("journey\n  title My Day"));
    try std.testing.expect(isJourneyDiagram("  journey\n  title My Day"));
    try std.testing.expect(isJourneyDiagram("journey"));
    try std.testing.expect(!isJourneyDiagram("flowchart TD\n  A-->B"));
    try std.testing.expect(!isJourneyDiagram("sequenceDiagram\n  A->>B: Hi"));
    try std.testing.expect(!isJourneyDiagram("pie\n  \"A\" : 1"));
    try std.testing.expect(!isJourneyDiagram("journeyman")); // not a full keyword match
}

test "journey parser: empty diagram" {
    const allocator = std.testing.allocator;
    var diagram = try parse(allocator, "journey\n");
    defer diagram.deinit();

    try std.testing.expectEqual(@as(usize, 0), diagram.taskCount());
    try std.testing.expectEqual(@as(usize, 0), diagram.sectionCount());
}

test "journey parser: title" {
    const allocator = std.testing.allocator;
    var diagram = try parse(allocator,
        \\journey
        \\    title My working day
    );
    defer diagram.deinit();

    try std.testing.expect(diagram.title != null);
    try std.testing.expectEqualStrings("My working day", diagram.title.?);
}

test "journey parser: sections and tasks" {
    const allocator = std.testing.allocator;
    var diagram = try parse(allocator,
        \\journey
        \\    title My working day
        \\    section Go to work
        \\        Make tea: 5: Me
        \\        Go upstairs: 3: Me, Cat
        \\        Do work: 1: Me, Cat, Dog
        \\    section Go home
        \\        Go downstairs: 5: Me
        \\        Sit down: 5: Me
    );
    defer diagram.deinit();

    try std.testing.expectEqualStrings("My working day", diagram.title.?);
    try std.testing.expectEqual(@as(usize, 2), diagram.sectionCount());
    try std.testing.expectEqualStrings("Go to work", diagram.sections.items[0].data);
    try std.testing.expectEqualStrings("Go home", diagram.sections.items[1].data);

    try std.testing.expectEqual(@as(usize, 5), diagram.taskCount());

    const tasks = diagram.getTasks();

    // First task
    try std.testing.expectEqualStrings("Make tea", tasks[0].task);
    try std.testing.expectEqual(@as(i32, 5), tasks[0].score);
    try std.testing.expectEqual(@as(usize, 1), tasks[0].people.items.len);
    try std.testing.expectEqualStrings("Me", tasks[0].people.items[0].data);
    try std.testing.expectEqualStrings("Go to work", tasks[0].section);

    // Second task (multiple actors)
    try std.testing.expectEqualStrings("Go upstairs", tasks[1].task);
    try std.testing.expectEqual(@as(i32, 3), tasks[1].score);
    try std.testing.expectEqual(@as(usize, 2), tasks[1].people.items.len);
    try std.testing.expectEqualStrings("Me", tasks[1].people.items[0].data);
    try std.testing.expectEqualStrings("Cat", tasks[1].people.items[1].data);

    // Third task (three actors)
    try std.testing.expectEqualStrings("Do work", tasks[2].task);
    try std.testing.expectEqual(@as(i32, 1), tasks[2].score);
    try std.testing.expectEqual(@as(usize, 3), tasks[2].people.items.len);

    // Fourth task (in second section)
    try std.testing.expectEqualStrings("Go downstairs", tasks[3].task);
    try std.testing.expectEqual(@as(i32, 5), tasks[3].score);
    try std.testing.expectEqualStrings("Go home", tasks[3].section);

    // Fifth task
    try std.testing.expectEqualStrings("Sit down", tasks[4].task);
    try std.testing.expectEqual(@as(i32, 5), tasks[4].score);
}

test "journey parser: comments ignored" {
    const allocator = std.testing.allocator;
    var diagram = try parse(allocator,
        \\journey
        \\    %% this is a comment
        \\    title Chart
        \\    section Work
        \\        Task A: 3: Alice
    );
    defer diagram.deinit();

    try std.testing.expectEqual(@as(usize, 1), diagram.taskCount());
    try std.testing.expect(diagram.title != null);
    try std.testing.expectEqualStrings("Chart", diagram.title.?);
}

test "journey parser: accTitle and accDescr" {
    const allocator = std.testing.allocator;
    var diagram = try parse(allocator,
        \\journey
        \\    accTitle: My Accessibility Title
        \\    accDescr: My description
        \\    title Chart
        \\    section S1
        \\        Task: 5: Actor
    );
    defer diagram.deinit();

    try std.testing.expect(diagram.acc_title != null);
    try std.testing.expectEqualStrings("My Accessibility Title", diagram.acc_title.?);
    try std.testing.expect(diagram.acc_descr != null);
    try std.testing.expectEqualStrings("My description", diagram.acc_descr.?);
}

test "journey parser: multiline accDescr ignored" {
    const allocator = std.testing.allocator;
    var diagram = try parse(allocator,
        \\journey
        \\    accDescr {
        \\        line one
        \\        line two
        \\    }
        \\    section S1
        \\        Task: 3: Actor
    );
    defer diagram.deinit();

    try std.testing.expectEqual(@as(usize, 1), diagram.taskCount());
}

test "journey parser: task data without leading colon" {
    const allocator = std.testing.allocator;
    var diagram = try parse(allocator,
        \\journey
        \\    section Test
        \\        Task A: 4: Alice, Bob
        \\        Task B: 2: Charlie
    );
    defer diagram.deinit();

    const tasks = diagram.getTasks();
    try std.testing.expectEqual(@as(usize, 2), tasks.len);
    try std.testing.expectEqual(@as(i32, 4), tasks[0].score);
    try std.testing.expectEqual(@as(usize, 2), tasks[0].people.items.len);
    try std.testing.expectEqual(@as(i32, 2), tasks[1].score);
    try std.testing.expectEqual(@as(usize, 1), tasks[1].people.items.len);
}

test "journey parser: init directive skipped" {
    const allocator = std.testing.allocator;
    var diagram = try parse(allocator,
        \\%%{init: {"theme": "dark"}}%%
        \\journey
        \\    title Dark Theme Journey
        \\    section S1
        \\        Task: 3: Actor
    );
    defer diagram.deinit();

    try std.testing.expect(diagram.title != null);
    try std.testing.expectEqualStrings("Dark Theme Journey", diagram.title.?);
    try std.testing.expectEqual(@as(usize, 1), diagram.taskCount());
}

test "journey parser: multiple sections with many tasks" {
    const allocator = std.testing.allocator;
    var diagram = try parse(allocator,
        \\journey
        \\    title Shopping Trip
        \\    section Getting Ready
        \\        Get car keys: 5: Dad
        \\        Get shopping list: 4: Mum
        \\    section At the Store
        \\        Find parking: 2: Dad
        \\        Get groceries: 3: Dad, Mum
        \\        Pay: 4: Mum
        \\    section Going Home
        \\        Drive home: 5: Dad
        \\        Unpack: 3: Dad, Mum
    );
    defer diagram.deinit();

    try std.testing.expectEqual(@as(usize, 3), diagram.sectionCount());
    try std.testing.expectEqual(@as(usize, 7), diagram.taskCount());

    try std.testing.expectEqualStrings("Getting Ready", diagram.sections.items[0].data);
    try std.testing.expectEqualStrings("At the Store", diagram.sections.items[1].data);
    try std.testing.expectEqualStrings("Going Home", diagram.sections.items[2].data);

    // Verify section assignment
    const tasks = diagram.getTasks();
    try std.testing.expectEqualStrings("Getting Ready", tasks[0].section);
    try std.testing.expectEqualStrings("Getting Ready", tasks[1].section);
    try std.testing.expectEqualStrings("At the Store", tasks[2].section);
    try std.testing.expectEqualStrings("At the Store", tasks[3].section);
    try std.testing.expectEqualStrings("At the Store", tasks[4].section);
    try std.testing.expectEqualStrings("Going Home", tasks[5].section);
    try std.testing.expectEqualStrings("Going Home", tasks[6].section);
}

test "journey parser: task without section" {
    const allocator = std.testing.allocator;
    var diagram = try parse(allocator,
        \\journey
        \\    title No Sections
        \\    Task A: 3: Actor
        \\    Task B: 5: Actor
    );
    defer diagram.deinit();

    // Tasks should still parse even without an explicit section
    try std.testing.expectEqual(@as(usize, 2), diagram.taskCount());
    // Section will be empty string (the default current_section)
    const tasks = diagram.getTasks();
    try std.testing.expectEqualStrings("", tasks[0].section);
}

test "journey parser: non-task lines after header are ignored" {
    const allocator = std.testing.allocator;
    var diagram = try parse(allocator,
        \\journey
        \\    title Test
        \\    some random text without a score
        \\    section S1
        \\        Valid Task: 5: Actor
    );
    defer diagram.deinit();

    // Only the valid task line should be parsed
    try std.testing.expectEqual(@as(usize, 1), diagram.taskCount());
}
