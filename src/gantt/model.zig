//! Gantt chart model types.
//!
//! Provides a simplified Gantt model that tracks tasks with ordinal day
//! positions rather than full calendar date arithmetic.  This is sufficient
//! for rendering bars on a timeline while avoiding the complexity of a
//! complete date/time library.
//!
//! Mirrors the Rust selkie implementation:
//!   selkie/src/diagrams/gantt/types.rs

const std = @import("std");

// -----------------------------------------------------------------------
// Duration helpers
// -----------------------------------------------------------------------

pub const DurationUnit = enum {
    milliseconds,
    seconds,
    minutes,
    hours,
    days,
    weeks,

    pub fn fromStr(s: []const u8) ?DurationUnit {
        if (eql(s, "ms")) return .milliseconds;
        if (eql(s, "s")) return .seconds;
        if (eql(s, "m")) return .minutes;
        if (eql(s, "h")) return .hours;
        if (eql(s, "d")) return .days;
        if (eql(s, "w")) return .weeks;
        return null;
    }

    pub fn asStr(self: DurationUnit) []const u8 {
        return switch (self) {
            .milliseconds => "ms",
            .seconds => "s",
            .minutes => "m",
            .hours => "h",
            .days => "d",
            .weeks => "w",
        };
    }

    /// Convert a count of this unit to days (fractional).
    pub fn toDays(self: DurationUnit, value: f64) f64 {
        return switch (self) {
            .milliseconds => value / (24.0 * 60.0 * 60.0 * 1000.0),
            .seconds => value / (24.0 * 60.0 * 60.0),
            .minutes => value / (24.0 * 60.0),
            .hours => value / 24.0,
            .days => value,
            .weeks => value * 7.0,
        };
    }
};

pub const Duration = struct {
    value: f64,
    unit: DurationUnit,

    pub fn init(value: f64, unit: DurationUnit) Duration {
        return .{ .value = value, .unit = unit };
    }

    /// Duration expressed in days.
    pub fn toDays(self: Duration) f64 {
        return self.unit.toDays(self.value);
    }
};

/// Try to parse a duration string such as "3d", "1w", "2h", "500ms".
/// Returns null if the string is not a valid duration.
pub fn parseDuration(s: []const u8) ?Duration {
    if (s.len == 0) return null;

    // Find where the numeric part ends
    var num_end: usize = 0;
    var has_dot = false;
    while (num_end < s.len) : (num_end += 1) {
        const c = s[num_end];
        if (c == '.') {
            if (has_dot) break; // second dot
            has_dot = true;
        } else if (c < '0' or c > '9') {
            break;
        }
    }

    if (num_end == 0) return null;

    const value = std.fmt.parseFloat(f64, s[0..num_end]) catch return null;
    const unit_str = s[num_end..];
    const unit = DurationUnit.fromStr(unit_str) orelse return null;

    return Duration.init(value, unit);
}

// -----------------------------------------------------------------------
// Simple date representation (year-month-day)
// -----------------------------------------------------------------------

/// A simple calendar date (no time-of-day).  Used to position tasks on
/// the Gantt timeline without pulling in a full datetime library.
pub const SimpleDate = struct {
    year: i32,
    month: u8, // 1..12
    day: u8, // 1..31

    pub fn init(year: i32, month: u8, day: u8) SimpleDate {
        return .{ .year = year, .month = month, .day = day };
    }

    /// Approximate ordinal day number for comparison / layout.
    /// Not astronomically precise but sufficient for chart rendering.
    pub fn toOrdinal(self: SimpleDate) i64 {
        const y: i64 = @intCast(self.year);
        const m: i64 = @intCast(self.month);
        const d: i64 = @intCast(self.day);
        // Rata Die–style day number (good enough for spans of a few years)
        return y * 365 + @divTrunc(y, 4) - @divTrunc(y, 100) + @divTrunc(y, 400) +
            @divTrunc((153 * (if (m > 2) m - 3 else m + 9)) + 2, 5) + d + (if (m <= 2) @as(i64, -365) else @as(i64, -306));
    }

    /// Add `n` days and return a new SimpleDate.
    /// Uses a brute-force approach (sufficient for small offsets used in Gantt charts).
    pub fn addDays(self: SimpleDate, n: i32) SimpleDate {
        var y = self.year;
        var m: i32 = @intCast(self.month);
        var d: i32 = @intCast(self.day);

        if (n >= 0) {
            var remaining = n;
            while (remaining > 0) {
                const dim = daysInMonth(@intCast(m), y);
                const left_in_month = dim - d;
                if (remaining <= left_in_month) {
                    d += remaining;
                    remaining = 0;
                } else {
                    remaining -= (left_in_month + 1);
                    d = 1;
                    m += 1;
                    if (m > 12) {
                        m = 1;
                        y += 1;
                    }
                }
            }
        } else {
            var remaining = -n;
            while (remaining > 0) {
                if (remaining < d) {
                    d -= remaining;
                    remaining = 0;
                } else {
                    remaining -= d;
                    m -= 1;
                    if (m < 1) {
                        m = 12;
                        y -= 1;
                    }
                    d = daysInMonth(@intCast(m), y);
                }
            }
        }

        return SimpleDate.init(y, @intCast(m), @intCast(d));
    }

    /// Format as "YYYY-MM-DD" into a caller-provided buffer.
    pub fn format(self: SimpleDate, buf: []u8) []const u8 {
        if (buf.len < 10) return "????-??-??";
        // Manually format to avoid Zig version-specific format specifier issues
        const y: u32 = if (self.year >= 0) @intCast(self.year) else 0;
        const m: u32 = @intCast(self.month);
        const d: u32 = @intCast(self.day);
        buf[0] = '0' + @as(u8, @intCast(y / 1000 % 10));
        buf[1] = '0' + @as(u8, @intCast(y / 100 % 10));
        buf[2] = '0' + @as(u8, @intCast(y / 10 % 10));
        buf[3] = '0' + @as(u8, @intCast(y % 10));
        buf[4] = '-';
        buf[5] = '0' + @as(u8, @intCast(m / 10));
        buf[6] = '0' + @as(u8, @intCast(m % 10));
        buf[7] = '-';
        buf[8] = '0' + @as(u8, @intCast(d / 10));
        buf[9] = '0' + @as(u8, @intCast(d % 10));
        return buf[0..10];
    }

    pub fn eql(self: SimpleDate, other: SimpleDate) bool {
        return self.year == other.year and self.month == other.month and self.day == other.day;
    }
};

fn isLeapYear(y: i32) bool {
    if (@mod(y, 400) == 0) return true;
    if (@mod(y, 100) == 0) return false;
    if (@mod(y, 4) == 0) return true;
    return false;
}

fn daysInMonth(m: u8, y: i32) i32 {
    const table = [_]i32{ 31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31 };
    if (m < 1 or m > 12) return 30;
    var d = table[m - 1];
    if (m == 2 and isLeapYear(y)) d = 29;
    return d;
}

/// Try to parse a date string.  Supported formats:
///   YYYY-MM-DD
///   YYYY/MM/DD
///   MM/DD/YYYY  (if first component <= 12)
///   DD.MM.YYYY
pub fn parseDate(s: []const u8) ?SimpleDate {
    const trimmed = trimStr(s);
    if (trimmed.len < 8) return null;

    // YYYY-MM-DD or YYYY/MM/DD
    if (trimmed.len >= 10 and (trimmed[4] == '-' or trimmed[4] == '/')) {
        const year = parseInt(i32, trimmed[0..4]) orelse return null;
        const month = parseInt(u8, trimmed[5..7]) orelse return null;
        const day = parseInt(u8, trimmed[8..10]) orelse return null;
        if (month >= 1 and month <= 12 and day >= 1 and day <= 31) {
            return SimpleDate.init(year, month, day);
        }
        return null;
    }

    // MM/DD/YYYY
    if (trimmed.len >= 10 and trimmed[2] == '/') {
        const month = parseInt(u8, trimmed[0..2]) orelse return null;
        const day = parseInt(u8, trimmed[3..5]) orelse return null;
        const year = parseInt(i32, trimmed[6..10]) orelse return null;
        if (month >= 1 and month <= 12 and day >= 1 and day <= 31) {
            return SimpleDate.init(year, month, day);
        }
        return null;
    }

    // DD.MM.YYYY
    if (trimmed.len >= 10 and trimmed[2] == '.') {
        const day = parseInt(u8, trimmed[0..2]) orelse return null;
        const month = parseInt(u8, trimmed[3..5]) orelse return null;
        const year = parseInt(i32, trimmed[6..10]) orelse return null;
        if (month >= 1 and month <= 12 and day >= 1 and day <= 31) {
            return SimpleDate.init(year, month, day);
        }
        return null;
    }

    return null;
}

fn parseInt(comptime T: type, s: []const u8) ?T {
    return std.fmt.parseInt(T, s, 10) catch return null;
}

// -----------------------------------------------------------------------
// Task flags
// -----------------------------------------------------------------------

pub const TaskFlags = struct {
    active: bool = false,
    done: bool = false,
    critical: bool = false,
    milestone: bool = false,

    pub const default_flags = TaskFlags{};
};

// -----------------------------------------------------------------------
// Task
// -----------------------------------------------------------------------

pub const Task = struct {
    /// Task identifier (auto-generated or user-specified)
    id: []const u8,
    id_owned: bool,
    /// Display label
    label: []const u8,
    label_owned: bool,
    /// Section this task belongs to
    section: []const u8,
    section_owned: bool,
    /// Insertion order
    order: usize,
    /// Computed start day (ordinal, relative to diagram base)
    start_day: f64,
    /// Computed duration in days
    duration_days: f64,
    /// Task flags
    flags: TaskFlags,
    /// After-dependency IDs (owned strings)
    after: std.ArrayListUnmanaged(OwnedString),
    /// Raw start date (if any)
    raw_start: ?[]const u8,
    raw_start_owned: bool,
    /// Raw duration string (if any)
    raw_duration: ?[]const u8,
    raw_duration_owned: bool,

    pub fn init(allocator: std.mem.Allocator, id: []const u8, label: []const u8, section: []const u8, order: usize) !Task {
        return .{
            .id = try allocator.dupe(u8, id),
            .id_owned = true,
            .label = try allocator.dupe(u8, label),
            .label_owned = true,
            .section = try allocator.dupe(u8, section),
            .section_owned = true,
            .order = order,
            .start_day = 0,
            .duration_days = 1,
            .flags = .{},
            .after = .{},
            .raw_start = null,
            .raw_start_owned = false,
            .raw_duration = null,
            .raw_duration_owned = false,
        };
    }

    pub fn deinit(self: *Task, allocator: std.mem.Allocator) void {
        if (self.id_owned) allocator.free(self.id);
        if (self.label_owned) allocator.free(self.label);
        if (self.section_owned) allocator.free(self.section);
        if (self.raw_start_owned) {
            if (self.raw_start) |rs| allocator.free(rs);
        }
        if (self.raw_duration_owned) {
            if (self.raw_duration) |rd| allocator.free(rd);
        }
        for (self.after.items) |*item| {
            item.deinit(allocator);
        }
        self.after.deinit(allocator);
    }

    pub fn setRawStart(self: *Task, allocator: std.mem.Allocator, raw: []const u8) !void {
        if (self.raw_start_owned) {
            if (self.raw_start) |rs| allocator.free(rs);
        }
        self.raw_start = try allocator.dupe(u8, raw);
        self.raw_start_owned = true;
    }

    pub fn setRawDuration(self: *Task, allocator: std.mem.Allocator, raw: []const u8) !void {
        if (self.raw_duration_owned) {
            if (self.raw_duration) |rd| allocator.free(rd);
        }
        self.raw_duration = try allocator.dupe(u8, raw);
        self.raw_duration_owned = true;
    }

    pub fn addAfter(self: *Task, allocator: std.mem.Allocator, dep_id: []const u8) !void {
        try self.after.append(allocator, try OwnedString.init(allocator, dep_id));
    }
};

// -----------------------------------------------------------------------
// OwnedString helper
// -----------------------------------------------------------------------

pub const OwnedString = struct {
    data: []const u8,
    owned: bool,

    pub fn init(allocator: std.mem.Allocator, s: []const u8) !OwnedString {
        return .{
            .data = try allocator.dupe(u8, s),
            .owned = true,
        };
    }

    pub fn deinit(self: *OwnedString, allocator: std.mem.Allocator) void {
        if (self.owned) allocator.free(self.data);
    }
};

// -----------------------------------------------------------------------
// GanttDiagram — top-level container
// -----------------------------------------------------------------------

pub const GanttDiagram = struct {
    /// All tasks in insertion order
    tasks: std.ArrayListUnmanaged(Task),
    /// Section names in order of appearance
    sections: std.ArrayListUnmanaged(OwnedString),
    /// Current section name for newly added tasks
    current_section: ?[]const u8,
    current_section_owned: bool,
    /// Diagram title
    title: ?[]const u8,
    title_owned: bool,
    /// Date format string
    date_format: ?[]const u8,
    date_format_owned: bool,
    /// Axis format string
    axis_format: ?[]const u8,
    axis_format_owned: bool,
    /// Whether end dates are inclusive
    inclusive_end_dates: bool,
    /// Excludes weekends
    exclude_weekends: bool,
    /// Task ID counter for auto-generated IDs
    task_counter: usize,
    /// Base date for ordinal calculations (earliest parsed date)
    base_date: ?SimpleDate,

    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) GanttDiagram {
        return .{
            .tasks = .{},
            .sections = .{},
            .current_section = null,
            .current_section_owned = false,
            .title = null,
            .title_owned = false,
            .date_format = null,
            .date_format_owned = false,
            .axis_format = null,
            .axis_format_owned = false,
            .inclusive_end_dates = false,
            .exclude_weekends = false,
            .task_counter = 0,
            .base_date = null,
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *GanttDiagram) void {
        for (self.tasks.items) |*task| {
            task.deinit(self.allocator);
        }
        self.tasks.deinit(self.allocator);

        for (self.sections.items) |*sec| {
            sec.deinit(self.allocator);
        }
        self.sections.deinit(self.allocator);

        if (self.current_section_owned) {
            if (self.current_section) |cs| self.allocator.free(cs);
        }
        if (self.title_owned) {
            if (self.title) |t| self.allocator.free(t);
        }
        if (self.date_format_owned) {
            if (self.date_format) |df| self.allocator.free(df);
        }
        if (self.axis_format_owned) {
            if (self.axis_format) |af| self.allocator.free(af);
        }
    }

    // -- Setters ----------------------------------------------------------

    pub fn setTitle(self: *GanttDiagram, title: []const u8) !void {
        if (self.title_owned) {
            if (self.title) |t| self.allocator.free(t);
        }
        self.title = try self.allocator.dupe(u8, title);
        self.title_owned = true;
    }

    pub fn setDateFormat(self: *GanttDiagram, fmt: []const u8) !void {
        if (self.date_format_owned) {
            if (self.date_format) |df| self.allocator.free(df);
        }
        self.date_format = try self.allocator.dupe(u8, fmt);
        self.date_format_owned = true;
    }

    pub fn setAxisFormat(self: *GanttDiagram, fmt: []const u8) !void {
        if (self.axis_format_owned) {
            if (self.axis_format) |af| self.allocator.free(af);
        }
        self.axis_format = try self.allocator.dupe(u8, fmt);
        self.axis_format_owned = true;
    }

    pub fn addSection(self: *GanttDiagram, name: []const u8) !void {
        // Check for duplicates
        for (self.sections.items) |sec| {
            if (std.mem.eql(u8, sec.data, name)) {
                // Already exists, just update current
                if (self.current_section_owned) {
                    if (self.current_section) |cs| self.allocator.free(cs);
                }
                self.current_section = try self.allocator.dupe(u8, name);
                self.current_section_owned = true;
                return;
            }
        }
        try self.sections.append(self.allocator, try OwnedString.init(self.allocator, name));
        if (self.current_section_owned) {
            if (self.current_section) |cs| self.allocator.free(cs);
        }
        self.current_section = try self.allocator.dupe(u8, name);
        self.current_section_owned = true;
    }

    /// Generate the next auto task ID ("task1", "task2", ...)
    fn nextTaskId(self: *GanttDiagram) ![]u8 {
        self.task_counter += 1;
        return try std.fmt.allocPrint(self.allocator, "task{d}", .{self.task_counter});
    }

    /// Add a task.  `data` is the comma-separated metadata string from the
    /// Gantt syntax (e.g. "done, des1, 2024-01-06, 2024-01-08").
    pub fn addTask(self: *GanttDiagram, label: []const u8, data: []const u8) !void {
        const section = self.current_section orelse "";

        // Parse the task data tokens
        var parsed = try self.parseTaskData(data);

        const id_slice: []const u8 = if (parsed.id) |pid| pid else blk: {
            const auto = try self.nextTaskId();
            parsed.auto_id = auto;
            break :blk auto;
        };

        var task = try Task.init(self.allocator, id_slice, label, section, self.tasks.items.len);

        // Free auto id after Task.init dupes it
        if (parsed.auto_id) |auto| self.allocator.free(auto);

        task.flags = parsed.flags;

        // Handle `after` dependencies
        for (parsed.after_deps.items) |dep| {
            try task.addAfter(self.allocator, dep.data);
        }

        // Resolve start day from raw start date or after-dependencies
        if (parsed.start_date) |start_str| {
            if (parseDate(start_str)) |sd| {
                if (self.base_date == null) {
                    self.base_date = sd;
                }
                const base = self.base_date.?;
                task.start_day = @floatFromInt(sd.toOrdinal() - base.toOrdinal());
            }
            try task.setRawStart(self.allocator, start_str);
        } else {
            // Default: starts after previous task (or day 0)
            if (self.tasks.items.len > 0) {
                const prev = &self.tasks.items[self.tasks.items.len - 1];
                task.start_day = prev.start_day + prev.duration_days;
            }
        }

        // Resolve duration
        if (parsed.duration_str) |dur_str| {
            if (parseDuration(dur_str)) |dur| {
                task.duration_days = dur.toDays();
            }
            try task.setRawDuration(self.allocator, dur_str);
        } else if (parsed.end_date) |end_str| {
            if (parseDate(end_str)) |ed| {
                if (self.base_date == null) {
                    self.base_date = SimpleDate.init(2024, 1, 1);
                }
                const base = self.base_date.?;
                const end_day: f64 = @floatFromInt(ed.toOrdinal() - base.toOrdinal());
                const dur = end_day - task.start_day;
                task.duration_days = if (dur > 0) dur else 1;
            }
        } else {
            // Default duration
            if (task.flags.milestone) {
                task.duration_days = 0;
            } else {
                task.duration_days = 1;
            }
        }

        try self.tasks.append(self.allocator, task);

        // Clean up parsed temporaries
        for (parsed.after_deps.items) |*dep| {
            dep.deinit(self.allocator);
        }
        parsed.after_deps.deinit(self.allocator);
    }

    // -- Task data parsing -----------------------------------------------

    const ParsedTaskData = struct {
        id: ?[]const u8,
        auto_id: ?[]u8,
        flags: TaskFlags,
        after_deps: std.ArrayListUnmanaged(OwnedString),
        start_date: ?[]const u8,
        end_date: ?[]const u8,
        duration_str: ?[]const u8,
    };

    fn parseTaskData(self: *GanttDiagram, data: []const u8) !ParsedTaskData {
        var result = ParsedTaskData{
            .id = null,
            .auto_id = null,
            .flags = .{},
            .after_deps = .{},
            .start_date = null,
            .end_date = null,
            .duration_str = null,
        };

        if (data.len == 0) return result;

        // Split by commas
        var iter = std.mem.splitScalar(u8, data, ',');
        var positional: usize = 0; // count of non-flag positional tokens

        while (iter.next()) |raw_tok| {
            const tok = trimStr(raw_tok);
            if (tok.len == 0) continue;

            // Check for flags
            if (eqlIgnoreCase(tok, "active")) {
                result.flags.active = true;
                continue;
            }
            if (eqlIgnoreCase(tok, "done")) {
                result.flags.done = true;
                continue;
            }
            if (eqlIgnoreCase(tok, "crit") or eqlIgnoreCase(tok, "critical")) {
                result.flags.critical = true;
                continue;
            }
            if (eqlIgnoreCase(tok, "milestone")) {
                result.flags.milestone = true;
                continue;
            }

            // Check for "after" dependency
            if (tok.len > 6 and startsWithCaseInsensitive(tok, "after ")) {
                const dep_part = trimStr(tok[6..]);
                // May be space-separated list of IDs
                var dep_iter = std.mem.splitScalar(u8, dep_part, ' ');
                while (dep_iter.next()) |dep_tok| {
                    const dep = trimStr(dep_tok);
                    if (dep.len > 0) {
                        try result.after_deps.append(self.allocator, try OwnedString.init(self.allocator, dep));
                    }
                }
                continue;
            }

            // Positional tokens: id, start_date, end_date/duration
            // The order depends on what's present:
            //   With explicit ID:  id, start_date, end_date_or_duration
            //   Without:           start_date, end_date_or_duration
            switch (positional) {
                0 => {
                    // Could be id or start_date
                    if (parseDate(tok) != null) {
                        result.start_date = tok;
                    } else if (parseDuration(tok) != null) {
                        result.duration_str = tok;
                    } else {
                        result.id = tok;
                    }
                },
                1 => {
                    if (parseDate(tok) != null) {
                        if (result.start_date == null) {
                            result.start_date = tok;
                        } else {
                            result.end_date = tok;
                        }
                    } else if (parseDuration(tok) != null) {
                        result.duration_str = tok;
                    } else if (result.id == null) {
                        result.id = tok;
                    }
                },
                2 => {
                    if (parseDate(tok) != null) {
                        result.end_date = tok;
                    } else if (parseDuration(tok) != null) {
                        result.duration_str = tok;
                    }
                },
                else => {},
            }
            positional += 1;
        }

        return result;
    }

    // -- Dependency resolution -------------------------------------------

    /// Resolve `after` dependencies by adjusting start_day of dependent
    /// tasks.  Must be called after all tasks have been added.
    pub fn resolveDependencies(self: *GanttDiagram) void {
        // Simple single-pass resolution (handles non-circular deps)
        for (self.tasks.items) |*task| {
            if (task.after.items.len > 0) {
                var latest_end: f64 = 0;
                for (task.after.items) |dep| {
                    for (self.tasks.items) |other| {
                        if (std.mem.eql(u8, other.id, dep.data)) {
                            const end = other.start_day + other.duration_days;
                            if (end > latest_end) latest_end = end;
                        }
                    }
                }
                task.start_day = latest_end;
            }
        }
    }

    // -- Queries ----------------------------------------------------------

    pub fn taskCount(self: *const GanttDiagram) usize {
        return self.tasks.items.len;
    }

    pub fn sectionCount(self: *const GanttDiagram) usize {
        return self.sections.items.len;
    }

    /// Find the overall day range [min_start, max_end].
    pub fn dayRange(self: *const GanttDiagram) struct { min: f64, max: f64 } {
        if (self.tasks.items.len == 0) return .{ .min = 0, .max = 30 };
        var lo: f64 = std.math.inf(f64);
        var hi: f64 = -std.math.inf(f64);
        for (self.tasks.items) |task| {
            if (task.start_day < lo) lo = task.start_day;
            const end = task.start_day + task.duration_days;
            if (end > hi) hi = end;
        }
        if (lo == std.math.inf(f64)) return .{ .min = 0, .max = 30 };
        if (hi - lo < 1) hi = lo + 1;
        return .{ .min = lo, .max = hi };
    }

    /// Get a task by ID (linear search).
    pub fn getTaskById(self: *const GanttDiagram, id: []const u8) ?*const Task {
        for (self.tasks.items) |*task| {
            if (std.mem.eql(u8, task.id, id)) return task;
        }
        return null;
    }

    /// Collect section info: (name, first_task_index, task_count).
    /// Caller owns returned slice.
    pub fn collectSections(self: *const GanttDiagram) ![]SectionInfo {
        var result = std.ArrayListUnmanaged(SectionInfo){};

        for (self.tasks.items, 0..) |task, idx| {
            const section_name = if (task.section.len > 0) task.section else "(default)";

            // Find existing
            var found = false;
            for (result.items) |*si| {
                if (std.mem.eql(u8, si.name, section_name)) {
                    si.count += 1;
                    found = true;
                    break;
                }
            }
            if (!found) {
                try result.append(self.allocator, .{
                    .name = section_name,
                    .first_task = idx,
                    .count = 1,
                });
            }
        }

        return result.toOwnedSlice(self.allocator);
    }
};

pub const SectionInfo = struct {
    name: []const u8,
    first_task: usize,
    count: usize,
};

// -----------------------------------------------------------------------
// Rendering color constants
// -----------------------------------------------------------------------

/// Task bar fill colors (cycle through 4 section colors)
pub const task_fills = [4][4]u8{
    .{ 119, 174, 255, 255 }, // blue
    .{ 255, 183, 77, 255 }, // orange
    .{ 129, 199, 132, 255 }, // green
    .{ 206, 147, 216, 255 }, // purple
};

/// Task bar stroke colors
pub const task_strokes = [4][4]u8{
    .{ 42, 111, 196, 255 },
    .{ 196, 120, 20, 255 },
    .{ 56, 142, 60, 255 },
    .{ 142, 68, 173, 255 },
};

/// Done task fill
pub const done_fill: [4]u8 = .{ 189, 189, 189, 255 };
pub const done_stroke: [4]u8 = .{ 117, 117, 117, 255 };

/// Active task fill
pub const active_fill: [4]u8 = .{ 144, 202, 249, 255 };
pub const active_stroke: [4]u8 = .{ 30, 136, 229, 255 };

/// Critical task fill
pub const crit_fill: [4]u8 = .{ 255, 138, 128, 255 };
pub const crit_stroke: [4]u8 = .{ 213, 0, 0, 255 };

/// Grid / axis colors
pub const grid_color: [4]u8 = .{ 200, 200, 200, 255 };
pub const axis_text_color: [4]u8 = .{ 51, 51, 51, 255 };
pub const title_color: [4]u8 = .{ 51, 51, 51, 255 };
pub const task_text_color: [4]u8 = .{ 51, 51, 51, 255 };
pub const section_bg_odd: [4]u8 = .{ 240, 240, 255, 128 };
pub const section_bg_even: [4]u8 = .{ 255, 255, 240, 128 };
pub const section_label_color: [4]u8 = .{ 80, 80, 80, 255 };
pub const today_line_color: [4]u8 = .{ 255, 67, 54, 200 };

// -----------------------------------------------------------------------
// String helpers
// -----------------------------------------------------------------------

fn eql(a: []const u8, b: []const u8) bool {
    return std.mem.eql(u8, a, b);
}

fn eqlIgnoreCase(a: []const u8, b: []const u8) bool {
    if (a.len != b.len) return false;
    for (a, b) |ca, cb| {
        if (std.ascii.toLower(ca) != std.ascii.toLower(cb)) return false;
    }
    return true;
}

fn startsWithCaseInsensitive(s: []const u8, prefix: []const u8) bool {
    if (s.len < prefix.len) return false;
    for (s[0..prefix.len], prefix) |a, b| {
        if (std.ascii.toLower(a) != std.ascii.toLower(b)) return false;
    }
    return true;
}

fn trimStr(s: []const u8) []const u8 {
    var start: usize = 0;
    while (start < s.len and (s[start] == ' ' or s[start] == '\t' or s[start] == '\r')) start += 1;
    var end = s.len;
    while (end > start and (s[end - 1] == ' ' or s[end - 1] == '\t' or s[end - 1] == '\r')) end -= 1;
    return s[start..end];
}

// -----------------------------------------------------------------------
// Tests
// -----------------------------------------------------------------------

test "gantt model: DurationUnit fromStr" {
    try std.testing.expectEqual(DurationUnit.days, DurationUnit.fromStr("d").?);
    try std.testing.expectEqual(DurationUnit.weeks, DurationUnit.fromStr("w").?);
    try std.testing.expectEqual(DurationUnit.hours, DurationUnit.fromStr("h").?);
    try std.testing.expectEqual(DurationUnit.minutes, DurationUnit.fromStr("m").?);
    try std.testing.expectEqual(DurationUnit.seconds, DurationUnit.fromStr("s").?);
    try std.testing.expectEqual(DurationUnit.milliseconds, DurationUnit.fromStr("ms").?);
    try std.testing.expect(DurationUnit.fromStr("x") == null);
}

test "gantt model: parseDuration" {
    const d1 = parseDuration("3d").?;
    try std.testing.expectEqual(@as(f64, 3.0), d1.toDays());

    const d2 = parseDuration("2w").?;
    try std.testing.expectEqual(@as(f64, 14.0), d2.toDays());

    const d3 = parseDuration("24h").?;
    try std.testing.expectEqual(@as(f64, 1.0), d3.toDays());

    try std.testing.expect(parseDuration("abc") == null);
    try std.testing.expect(parseDuration("") == null);
}

test "gantt model: parseDate YYYY-MM-DD" {
    const d = parseDate("2024-01-15").?;
    try std.testing.expectEqual(@as(i32, 2024), d.year);
    try std.testing.expectEqual(@as(u8, 1), d.month);
    try std.testing.expectEqual(@as(u8, 15), d.day);
}

test "gantt model: parseDate YYYY/MM/DD" {
    const d = parseDate("2024/03/20").?;
    try std.testing.expectEqual(@as(i32, 2024), d.year);
    try std.testing.expectEqual(@as(u8, 3), d.month);
    try std.testing.expectEqual(@as(u8, 20), d.day);
}

test "gantt model: parseDate invalid" {
    try std.testing.expect(parseDate("not-a-date") == null);
    try std.testing.expect(parseDate("") == null);
    try std.testing.expect(parseDate("2024") == null);
}

test "gantt model: SimpleDate addDays" {
    const d = SimpleDate.init(2024, 1, 30);
    const d2 = d.addDays(3);
    try std.testing.expectEqual(@as(i32, 2024), d2.year);
    try std.testing.expectEqual(@as(u8, 2), d2.month);
    try std.testing.expectEqual(@as(u8, 2), d2.day);
}

test "gantt model: SimpleDate addDays across year" {
    const d = SimpleDate.init(2024, 12, 30);
    const d2 = d.addDays(5);
    try std.testing.expectEqual(@as(i32, 2025), d2.year);
    try std.testing.expectEqual(@as(u8, 1), d2.month);
    try std.testing.expectEqual(@as(u8, 4), d2.day);
}

test "gantt model: create GanttDiagram" {
    const allocator = std.testing.allocator;
    var diagram = GanttDiagram.init(allocator);
    defer diagram.deinit();

    try std.testing.expectEqual(@as(usize, 0), diagram.taskCount());
    try std.testing.expectEqual(@as(usize, 0), diagram.sectionCount());
}

test "gantt model: set title" {
    const allocator = std.testing.allocator;
    var diagram = GanttDiagram.init(allocator);
    defer diagram.deinit();

    try diagram.setTitle("My Gantt Chart");
    try std.testing.expectEqualStrings("My Gantt Chart", diagram.title.?);
}

test "gantt model: add section" {
    const allocator = std.testing.allocator;
    var diagram = GanttDiagram.init(allocator);
    defer diagram.deinit();

    try diagram.addSection("Design");
    try diagram.addSection("Development");
    try std.testing.expectEqual(@as(usize, 2), diagram.sectionCount());
    try std.testing.expectEqualStrings("Development", diagram.current_section.?);
}

test "gantt model: add task with dates" {
    const allocator = std.testing.allocator;
    var diagram = GanttDiagram.init(allocator);
    defer diagram.deinit();

    try diagram.addSection("Planning");
    try diagram.addTask("Design mock-up", "des1, 2024-01-06, 2024-01-09");
    try std.testing.expectEqual(@as(usize, 1), diagram.taskCount());

    const task = &diagram.tasks.items[0];
    try std.testing.expectEqualStrings("Design mock-up", task.label);
    try std.testing.expectEqualStrings("Planning", task.section);
    try std.testing.expect(task.duration_days >= 2.5);
}

test "gantt model: add task with duration" {
    const allocator = std.testing.allocator;
    var diagram = GanttDiagram.init(allocator);
    defer diagram.deinit();

    try diagram.addTask("Task A", "2024-01-01, 5d");
    try std.testing.expectEqual(@as(usize, 1), diagram.taskCount());
    try std.testing.expectEqual(@as(f64, 5.0), diagram.tasks.items[0].duration_days);
}

test "gantt model: task flags" {
    const allocator = std.testing.allocator;
    var diagram = GanttDiagram.init(allocator);
    defer diagram.deinit();

    try diagram.addTask("Critical Task", "crit, 2024-01-01, 3d");
    try std.testing.expect(diagram.tasks.items[0].flags.critical);

    try diagram.addTask("Done Task", "done, 2024-01-04, 2d");
    try std.testing.expect(diagram.tasks.items[1].flags.done);

    try diagram.addTask("Active Task", "active, 2024-01-06, 1d");
    try std.testing.expect(diagram.tasks.items[2].flags.active);

    try diagram.addTask("Milestone", "milestone, 2024-01-07, 0d");
    try std.testing.expect(diagram.tasks.items[3].flags.milestone);
}

test "gantt model: day range" {
    const allocator = std.testing.allocator;
    var diagram = GanttDiagram.init(allocator);
    defer diagram.deinit();

    try diagram.addTask("A", "2024-01-01, 5d");
    try diagram.addTask("B", "2024-01-06, 3d");

    const range = diagram.dayRange();
    try std.testing.expect(range.min <= 0.01);
    try std.testing.expect(range.max >= 7.5);
}

test "gantt model: collect sections" {
    const allocator = std.testing.allocator;
    var diagram = GanttDiagram.init(allocator);
    defer diagram.deinit();

    try diagram.addSection("Design");
    try diagram.addTask("A", "2024-01-01, 3d");
    try diagram.addTask("B", "2024-01-04, 2d");
    try diagram.addSection("Dev");
    try diagram.addTask("C", "2024-01-06, 5d");

    const secs = try diagram.collectSections();
    defer allocator.free(secs);

    try std.testing.expectEqual(@as(usize, 2), secs.len);
    try std.testing.expectEqualStrings("Design", secs[0].name);
    try std.testing.expectEqual(@as(usize, 2), secs[0].count);
    try std.testing.expectEqualStrings("Dev", secs[1].name);
    try std.testing.expectEqual(@as(usize, 1), secs[1].count);
}

test "gantt model: SimpleDate format" {
    const d = SimpleDate.init(2024, 3, 5);
    var buf: [16]u8 = undefined;
    const formatted = d.format(&buf);
    try std.testing.expectEqualStrings("2024-03-05", formatted);
}

test "gantt model: task auto id" {
    const allocator = std.testing.allocator;
    var diagram = GanttDiagram.init(allocator);
    defer diagram.deinit();

    try diagram.addTask("No ID task", "2024-01-01, 1d");
    try std.testing.expectEqualStrings("task1", diagram.tasks.items[0].id);
}

test "gantt model: task explicit id" {
    const allocator = std.testing.allocator;
    var diagram = GanttDiagram.init(allocator);
    defer diagram.deinit();

    try diagram.addTask("Has ID", "myTask, 2024-01-01, 3d");
    try std.testing.expectEqualStrings("myTask", diagram.tasks.items[0].id);
}

test "gantt model: sequential tasks default start" {
    const allocator = std.testing.allocator;
    var diagram = GanttDiagram.init(allocator);
    defer diagram.deinit();

    try diagram.addTask("A", "2024-01-01, 3d");
    try diagram.addTask("B", "5d");

    // B should start where A ends
    try std.testing.expect(diagram.tasks.items[1].start_day >= 2.9);
    try std.testing.expectEqual(@as(f64, 5.0), diagram.tasks.items[1].duration_days);
}
