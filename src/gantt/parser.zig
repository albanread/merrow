//! Gantt chart parser.
//!
//! Parses mermaid Gantt diagram syntax line-by-line, producing a GanttDiagram
//! model.  Supports: title, dateFormat, axisFormat, sections, tasks with
//! flags/dates/durations, excludes, inclusiveEndDates, todayMarker, and
//! comments.

const std = @import("std");
const GanttDiagram = @import("model.zig").GanttDiagram;
const Task = @import("model.zig").Task;
const TaskFlags = @import("model.zig").TaskFlags;

pub const ParseError = error{
    OutOfMemory,
    InvalidSyntax,
    Overflow,
    InvalidCharacter,
};

/// Parse Gantt diagram source text into a GanttDiagram model.
pub fn parse(allocator: std.mem.Allocator, source: []const u8) ParseError!GanttDiagram {
    var diagram = GanttDiagram.init(allocator);
    errdefer diagram.deinit();

    var lines = LineIterator.init(source);
    var header_seen = false;
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
            if (startsWithCaseInsensitive(line, "gantt")) {
                header_seen = true;
                continue;
            }
            // Skip preamble/frontmatter
            continue;
        }

        // ── Directives (after header) ───────────────────────────

        // accTitle: <text>
        if (startsWithCaseInsensitive(line, "accTitle")) continue;

        // accDescr
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

        // dateFormat <format>
        if (startsWithCaseInsensitive(line, "dateFormat") or
            startsWithCaseInsensitive(line, "dateformat"))
        {
            const keyword_len: usize = 10;
            if (line.len > keyword_len) {
                const rest = trim(line[keyword_len..]);
                if (rest.len > 0) {
                    try diagram.setDateFormat(rest);
                }
            }
            continue;
        }

        // axisFormat <format>
        if (startsWithCaseInsensitive(line, "axisFormat") or
            startsWithCaseInsensitive(line, "axisformat"))
        {
            const keyword_len: usize = 10;
            if (line.len > keyword_len) {
                const rest = trim(line[keyword_len..]);
                if (rest.len > 0) {
                    try diagram.setAxisFormat(rest);
                }
            }
            continue;
        }

        // tickInterval <interval>
        if (startsWithCaseInsensitive(line, "tickInterval") or
            startsWithCaseInsensitive(line, "tickinterval"))
        {
            // Ignored for now
            continue;
        }

        // inclusiveEndDates
        if (startsWithCaseInsensitive(line, "inclusiveEndDates") or
            startsWithCaseInsensitive(line, "inclusiveenddates"))
        {
            diagram.inclusive_end_dates = true;
            continue;
        }

        // topAxis
        if (startsWithCaseInsensitive(line, "topAxis") or
            startsWithCaseInsensitive(line, "topaxis"))
        {
            // Ignored for now
            continue;
        }

        // todayMarker <value>
        if (startsWithCaseInsensitive(line, "todayMarker") or
            startsWithCaseInsensitive(line, "todaymarker"))
        {
            // Ignored for now
            continue;
        }

        // excludes <value>
        if (startsWithCaseInsensitive(line, "excludes")) {
            const rest = trim(line[8..]);
            if (std.mem.indexOf(u8, rest, "weekends") != null) {
                diagram.exclude_weekends = true;
            }
            continue;
        }

        // includes <value>
        if (startsWithCaseInsensitive(line, "includes")) {
            continue;
        }

        // weekday <value>
        if (startsWithCaseInsensitive(line, "weekday")) {
            continue;
        }

        // weekend <value>
        if (startsWithCaseInsensitive(line, "weekend")) {
            continue;
        }

        // click <taskId> ...
        if (startsWithCaseInsensitive(line, "click ")) {
            continue;
        }

        // section <name>
        if (startsWithCaseInsensitive(line, "section")) {
            const rest = trim(line[7..]);
            if (rest.len > 0) {
                try diagram.addSection(rest);
            }
            continue;
        }

        // ── Task line ───────────────────────────────────────────
        // Format: Task Name : [metadata]
        // The colon separates the task label from its data.
        if (std.mem.indexOf(u8, line, ":")) |colon_pos| {
            const label = trim(line[0..colon_pos]);
            const data = trim(line[colon_pos + 1 ..]);
            if (label.len > 0) {
                try diagram.addTask(label, data);
                continue;
            }
        }

        // A line without a colon could be a bare task name with defaults
        // (some Gantt variants allow this). We'll treat it as a task with
        // an empty data section.
        if (line.len > 0 and !startsWithCaseInsensitive(line, "%%")) {
            // Only if it looks like a task name (not a keyword we missed)
            if (!isKnownKeyword(line)) {
                try diagram.addTask(line, "");
                continue;
            }
        }

        // Unknown lines are silently ignored (lenient parsing)
    }

    // Resolve after-dependencies
    diagram.resolveDependencies();

    return diagram;
}

/// Check if the source text is a Gantt diagram.
pub fn isGanttDiagram(source: []const u8) bool {
    var lines = LineIterator.init(source);
    while (lines.next()) |raw_line| {
        const line = trim(raw_line);
        if (line.len == 0) continue;
        if (startsWith(line, "%%{")) continue;
        if (startsWith(line, "%%")) continue;
        if (startsWith(line, "---")) continue;

        // Check for gantt keyword
        if (startsWithCaseInsensitive(line, "gantt")) return true;

        // If we see another diagram keyword first, it's not Gantt
        if (startsWithCaseInsensitive(line, "stateDiagram") or
            startsWithCaseInsensitive(line, "sequenceDiagram") or
            startsWithCaseInsensitive(line, "classDiagram") or
            startsWithCaseInsensitive(line, "flowchart") or
            startsWithCaseInsensitive(line, "graph") or
            startsWithCaseInsensitive(line, "pie") or
            startsWithCaseInsensitive(line, "erDiagram") or
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
// Helpers
// -----------------------------------------------------------------------

fn isKnownKeyword(line: []const u8) bool {
    return startsWithCaseInsensitive(line, "gantt") or
        startsWithCaseInsensitive(line, "title") or
        startsWithCaseInsensitive(line, "dateFormat") or
        startsWithCaseInsensitive(line, "dateformat") or
        startsWithCaseInsensitive(line, "axisFormat") or
        startsWithCaseInsensitive(line, "axisformat") or
        startsWithCaseInsensitive(line, "tickInterval") or
        startsWithCaseInsensitive(line, "tickinterval") or
        startsWithCaseInsensitive(line, "inclusiveEndDates") or
        startsWithCaseInsensitive(line, "inclusiveenddates") or
        startsWithCaseInsensitive(line, "topAxis") or
        startsWithCaseInsensitive(line, "topaxis") or
        startsWithCaseInsensitive(line, "todayMarker") or
        startsWithCaseInsensitive(line, "todaymarker") or
        startsWithCaseInsensitive(line, "excludes") or
        startsWithCaseInsensitive(line, "includes") or
        startsWithCaseInsensitive(line, "weekday") or
        startsWithCaseInsensitive(line, "weekend") or
        startsWithCaseInsensitive(line, "section") or
        startsWithCaseInsensitive(line, "click ") or
        startsWithCaseInsensitive(line, "accTitle") or
        startsWithCaseInsensitive(line, "accDescr");
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

test "gantt parser: isGanttDiagram detection" {
    try std.testing.expect(isGanttDiagram("gantt\n"));
    try std.testing.expect(isGanttDiagram("  gantt\n  title My Chart\n"));
    try std.testing.expect(!isGanttDiagram("sequenceDiagram\n"));
    try std.testing.expect(!isGanttDiagram("pie\n"));
    try std.testing.expect(!isGanttDiagram(""));
}

test "gantt parser: empty diagram" {
    const allocator = std.testing.allocator;
    var diagram = try parse(allocator,
        \\gantt
    );
    defer diagram.deinit();
    try std.testing.expectEqual(@as(usize, 0), diagram.taskCount());
}

test "gantt parser: title" {
    const allocator = std.testing.allocator;
    var diagram = try parse(allocator,
        \\gantt
        \\    title My Gantt Chart
    );
    defer diagram.deinit();
    try std.testing.expectEqualStrings("My Gantt Chart", diagram.title.?);
}

test "gantt parser: dateFormat and axisFormat" {
    const allocator = std.testing.allocator;
    var diagram = try parse(allocator,
        \\gantt
        \\    dateFormat YYYY-MM-DD
        \\    axisFormat %Y-%m-%d
    );
    defer diagram.deinit();
    try std.testing.expectEqualStrings("YYYY-MM-DD", diagram.date_format.?);
    try std.testing.expectEqualStrings("%Y-%m-%d", diagram.axis_format.?);
}

test "gantt parser: section" {
    const allocator = std.testing.allocator;
    var diagram = try parse(allocator,
        \\gantt
        \\    section Design
        \\    section Development
    );
    defer diagram.deinit();
    try std.testing.expectEqual(@as(usize, 2), diagram.sectionCount());
}

test "gantt parser: simple task" {
    const allocator = std.testing.allocator;
    var diagram = try parse(allocator,
        \\gantt
        \\    section Planning
        \\    Create design    : 2024-01-06, 3d
    );
    defer diagram.deinit();
    try std.testing.expectEqual(@as(usize, 1), diagram.taskCount());
    try std.testing.expectEqualStrings("Create design", diagram.tasks.items[0].label);
    try std.testing.expectEqual(@as(f64, 3.0), diagram.tasks.items[0].duration_days);
}

test "gantt parser: task with id" {
    const allocator = std.testing.allocator;
    var diagram = try parse(allocator,
        \\gantt
        \\    Task A    : des1, 2024-01-01, 5d
    );
    defer diagram.deinit();
    try std.testing.expectEqualStrings("des1", diagram.tasks.items[0].id);
    try std.testing.expectEqual(@as(f64, 5.0), diagram.tasks.items[0].duration_days);
}

test "gantt parser: task with flags" {
    const allocator = std.testing.allocator;
    var diagram = try parse(allocator,
        \\gantt
        \\    Crit Task    : crit, 2024-01-01, 3d
        \\    Done Task    : done, 2024-01-04, 2d
        \\    Active Task  : active, 2024-01-06, 1d
    );
    defer diagram.deinit();
    try std.testing.expectEqual(@as(usize, 3), diagram.taskCount());
    try std.testing.expect(diagram.tasks.items[0].flags.critical);
    try std.testing.expect(diagram.tasks.items[1].flags.done);
    try std.testing.expect(diagram.tasks.items[2].flags.active);
}

test "gantt parser: task with date range" {
    const allocator = std.testing.allocator;
    var diagram = try parse(allocator,
        \\gantt
        \\    Task A    : des1, 2024-01-06, 2024-01-09
    );
    defer diagram.deinit();
    try std.testing.expectEqual(@as(usize, 1), diagram.taskCount());
    try std.testing.expect(diagram.tasks.items[0].duration_days >= 2.5);
}

test "gantt parser: multiple sections with tasks" {
    const allocator = std.testing.allocator;
    var diagram = try parse(allocator,
        \\gantt
        \\    title Project Plan
        \\    dateFormat YYYY-MM-DD
        \\    section Design
        \\    Mock-up      : des1, 2024-01-06, 3d
        \\    Prototype    : des2, 2024-01-09, 5d
        \\    section Development
        \\    Coding       : dev1, 2024-01-14, 10d
    );
    defer diagram.deinit();
    try std.testing.expectEqualStrings("Project Plan", diagram.title.?);
    try std.testing.expectEqual(@as(usize, 3), diagram.taskCount());
    try std.testing.expectEqual(@as(usize, 2), diagram.sectionCount());
    try std.testing.expectEqualStrings("Design", diagram.tasks.items[0].section);
    try std.testing.expectEqualStrings("Development", diagram.tasks.items[2].section);
}

test "gantt parser: comments ignored" {
    const allocator = std.testing.allocator;
    var diagram = try parse(allocator,
        \\gantt
        \\    %% this is a comment
        \\    title Test
        \\    %% another comment
        \\    Task A : 2024-01-01, 1d
    );
    defer diagram.deinit();
    try std.testing.expectEqualStrings("Test", diagram.title.?);
    try std.testing.expectEqual(@as(usize, 1), diagram.taskCount());
}

test "gantt parser: inclusiveEndDates" {
    const allocator = std.testing.allocator;
    var diagram = try parse(allocator,
        \\gantt
        \\    inclusiveEndDates
    );
    defer diagram.deinit();
    try std.testing.expect(diagram.inclusive_end_dates);
}

test "gantt parser: excludes weekends" {
    const allocator = std.testing.allocator;
    var diagram = try parse(allocator,
        \\gantt
        \\    excludes weekends
    );
    defer diagram.deinit();
    try std.testing.expect(diagram.exclude_weekends);
}

test "gantt parser: milestone task" {
    const allocator = std.testing.allocator;
    var diagram = try parse(allocator,
        \\gantt
        \\    Release    : milestone, 2024-01-15, 0d
    );
    defer diagram.deinit();
    try std.testing.expectEqual(@as(usize, 1), diagram.taskCount());
    try std.testing.expect(diagram.tasks.items[0].flags.milestone);
}

test "gantt parser: sequential tasks" {
    const allocator = std.testing.allocator;
    var diagram = try parse(allocator,
        \\gantt
        \\    Task A    : 2024-01-01, 3d
        \\    Task B    : 5d
    );
    defer diagram.deinit();
    try std.testing.expectEqual(@as(usize, 2), diagram.taskCount());
    // Task B should start after Task A ends
    try std.testing.expect(diagram.tasks.items[1].start_day >= 2.9);
}

test "gantt parser: complex diagram" {
    const allocator = std.testing.allocator;
    var diagram = try parse(allocator,
        \\gantt
        \\    title Adding GANTT diagram to mermaid
        \\    dateFormat YYYY-MM-DD
        \\    excludes weekends
        \\    section A section
        \\    Completed task          : done, des1, 2024-01-06, 2024-01-08
        \\    Active task             : active, des2, 2024-01-09, 3d
        \\    Future task             : des3, 2024-01-12, 5d
        \\    Future task2            : des4, 2024-01-12, 5d
        \\    section Critical tasks
        \\    Completed task in crit  : crit, done, 2024-01-06, 24h
        \\    Active crit             : crit, active, 2024-01-09, 3d
    );
    defer diagram.deinit();
    try std.testing.expectEqualStrings("Adding GANTT diagram to mermaid", diagram.title.?);
    try std.testing.expectEqual(@as(usize, 6), diagram.taskCount());
    try std.testing.expectEqual(@as(usize, 2), diagram.sectionCount());
    try std.testing.expect(diagram.exclude_weekends);
}
