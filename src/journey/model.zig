//! User journey diagram data model.
//!
//! Represents all elements of a Mermaid user journey diagram:
//! tasks with satisfaction scores, actors/people involved,
//! section grouping, and an optional title.

const std = @import("std");

/// A single task in the user journey
pub const JourneyTask = struct {
    /// Task name/description
    task: []const u8,
    task_owned: bool = false,
    /// Satisfaction score (typically 1-5)
    score: i32 = 0,
    /// People/actors involved in this task
    people: std.ArrayListUnmanaged(OwnedString) = .{},
    /// Section this task belongs to
    section: []const u8,
    section_owned: bool = false,

    pub fn deinit(self: *JourneyTask, allocator: std.mem.Allocator) void {
        if (self.task_owned) allocator.free(self.task);
        for (self.people.items) |*p| {
            p.deinit(allocator);
        }
        self.people.deinit(allocator);
        if (self.section_owned) allocator.free(self.section);
    }
};

/// An owned string that tracks allocation
pub const OwnedString = struct {
    data: []const u8,
    owned: bool = false,

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

/// The user journey diagram database
pub const JourneyDiagram = struct {
    /// Diagram title
    title: ?[]const u8 = null,
    title_owned: bool = false,
    /// Accessibility title
    acc_title: ?[]const u8 = null,
    acc_title_owned: bool = false,
    /// Accessibility description
    acc_descr: ?[]const u8 = null,
    acc_descr_owned: bool = false,
    /// All sections in order (unique)
    sections: std.ArrayListUnmanaged(OwnedString) = .{},
    /// Current section name for task assignment
    current_section: []const u8 = "",
    current_section_owned: bool = false,
    /// All tasks in order
    tasks: std.ArrayListUnmanaged(JourneyTask) = .{},
    /// Allocator
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) JourneyDiagram {
        return .{
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *JourneyDiagram) void {
        if (self.title_owned) {
            if (self.title) |t| self.allocator.free(t);
        }
        if (self.acc_title_owned) {
            if (self.acc_title) |t| self.allocator.free(t);
        }
        if (self.acc_descr_owned) {
            if (self.acc_descr) |d| self.allocator.free(d);
        }
        for (self.sections.items) |*s| {
            s.deinit(self.allocator);
        }
        self.sections.deinit(self.allocator);
        if (self.current_section_owned) {
            self.allocator.free(self.current_section);
        }
        for (self.tasks.items) |*t| {
            t.deinit(self.allocator);
        }
        self.tasks.deinit(self.allocator);
    }

    /// Set the diagram title
    pub fn setTitle(self: *JourneyDiagram, title: []const u8) !void {
        if (self.title_owned) {
            if (self.title) |t| self.allocator.free(t);
        }
        self.title = try self.allocator.dupe(u8, title);
        self.title_owned = true;
    }

    /// Set the accessibility title
    pub fn setAccTitle(self: *JourneyDiagram, title: []const u8) !void {
        if (self.acc_title_owned) {
            if (self.acc_title) |t| self.allocator.free(t);
        }
        self.acc_title = try self.allocator.dupe(u8, title);
        self.acc_title_owned = true;
    }

    /// Set the accessibility description
    pub fn setAccDescr(self: *JourneyDiagram, descr: []const u8) !void {
        if (self.acc_descr_owned) {
            if (self.acc_descr) |d| self.allocator.free(d);
        }
        self.acc_descr = try self.allocator.dupe(u8, descr);
        self.acc_descr_owned = true;
    }

    /// Add a section. Sets the current section for subsequent tasks.
    pub fn addSection(self: *JourneyDiagram, name: []const u8) !void {
        const trimmed = trimSlice(name);
        if (trimmed.len == 0) return;

        // Check for duplicate section names
        var found = false;
        for (self.sections.items) |sec| {
            if (std.mem.eql(u8, sec.data, trimmed)) {
                found = true;
                break;
            }
        }
        if (!found) {
            try self.sections.append(self.allocator, try OwnedString.init(self.allocator, trimmed));
        }

        // Update current section
        if (self.current_section_owned) {
            self.allocator.free(self.current_section);
        }
        self.current_section = try self.allocator.dupe(u8, trimmed);
        self.current_section_owned = true;
    }

    /// Add a task with data string.
    /// Task data format: `:score:actor1, actor2, ...`
    /// Or: `score: actor1, actor2`
    pub fn addTask(self: *JourneyDiagram, task_name: []const u8, task_data: []const u8) !void {
        const trimmed_name = trimSlice(task_name);
        const trimmed_data = trimSlice(task_data);

        var task = JourneyTask{
            .task = try self.allocator.dupe(u8, trimmed_name),
            .task_owned = true,
            .section = try self.allocator.dupe(u8, self.current_section),
            .section_owned = true,
        };
        errdefer task.deinit(self.allocator);

        // Parse task data: split by colon to get score and actors
        var parts_iter = std.mem.splitScalar(u8, trimmed_data, ':');
        while (parts_iter.next()) |part| {
            const trimmed_part = trimSlice(part);
            if (trimmed_part.len == 0) continue;

            // Try to parse as integer score
            const score = std.fmt.parseInt(i32, trimmed_part, 10) catch {
                // Not a number — must be actor list (comma separated)
                var actor_iter = std.mem.splitScalar(u8, trimmed_part, ',');
                while (actor_iter.next()) |actor| {
                    const trimmed_actor = trimSlice(actor);
                    if (trimmed_actor.len > 0) {
                        try task.people.append(self.allocator, try OwnedString.init(self.allocator, trimmed_actor));
                    }
                }
                continue;
            };
            task.score = score;
        }

        try self.tasks.append(self.allocator, task);
    }

    /// Get all tasks
    pub fn getTasks(self: *const JourneyDiagram) []const JourneyTask {
        return self.tasks.items;
    }

    /// Get all sections
    pub fn getSections(self: *const JourneyDiagram) []const OwnedString {
        return self.sections.items;
    }

    /// Get number of tasks
    pub fn taskCount(self: *const JourneyDiagram) usize {
        return self.tasks.items.len;
    }

    /// Get number of sections
    pub fn sectionCount(self: *const JourneyDiagram) usize {
        return self.sections.items.len;
    }

    /// Get all unique actors (sorted, deduplicated)
    pub fn getActors(self: *const JourneyDiagram) ![]OwnedString {
        var actor_set = std.StringHashMap(void).init(self.allocator);
        defer actor_set.deinit();

        for (self.tasks.items) |task| {
            for (task.people.items) |person| {
                try actor_set.put(person.data, {});
            }
        }

        var actors = std.ArrayListUnmanaged(OwnedString){};
        var iter = actor_set.iterator();
        while (iter.next()) |entry| {
            try actors.append(self.allocator, .{
                .data = entry.key_ptr.*,
                .owned = false, // these point into task people, don't double-free
            });
        }

        // Sort alphabetically
        std.mem.sort(OwnedString, actors.items, {}, struct {
            fn cmp(_: void, a: OwnedString, b: OwnedString) bool {
                return std.mem.order(u8, a.data, b.data) == .lt;
            }
        }.cmp);

        return actors.toOwnedSlice(self.allocator);
    }
};

// -----------------------------------------------------------------------
// Default journey color palette
// -----------------------------------------------------------------------

/// Actor colors (matching mermaid.js defaults)
pub const actor_colors: [8][4]u8 = .{
    .{ 143, 188, 143, 255 }, // #8FBC8F DarkSeaGreen
    .{ 100, 149, 237, 255 }, // #6495ED CornflowerBlue
    .{ 255, 182, 193, 255 }, // #FFB6C1 LightPink
    .{ 255, 215, 0, 255 }, //   #FFD700 Gold
    .{ 221, 160, 221, 255 }, // #DDA0DD Plum
    .{ 240, 128, 128, 255 }, // #F08080 LightCoral
    .{ 144, 238, 144, 255 }, // #90EE90 LightGreen
    .{ 173, 216, 230, 255 }, // #ADD8E6 LightBlue
};

/// Section fill colors (matching mermaid.js defaults)
pub const section_fills: [8][4]u8 = .{
    .{ 135, 206, 250, 128 }, // light blue, semi-transparent
    .{ 255, 228, 181, 128 }, // moccasin, semi-transparent
    .{ 152, 251, 152, 128 }, // pale green, semi-transparent
    .{ 255, 182, 193, 128 }, // light pink, semi-transparent
    .{ 230, 230, 250, 128 }, // lavender, semi-transparent
    .{ 255, 218, 185, 128 }, // peach puff, semi-transparent
    .{ 176, 224, 230, 128 }, // powder blue, semi-transparent
    .{ 255, 255, 224, 128 }, // light yellow, semi-transparent
};

/// Face color
pub const face_color: [4]u8 = .{ 255, 255, 255, 255 }; // white

/// Section stroke
pub const section_stroke: [4]u8 = .{ 102, 102, 102, 255 }; // #666

/// Text color
pub const text_color: [4]u8 = .{ 51, 51, 51, 255 }; // #333

/// Return the actor color for a given index (wraps around the palette)
pub fn actorColor(index: usize) [4]u8 {
    return actor_colors[index % actor_colors.len];
}

/// Return the section fill color for a given index
pub fn sectionFill(index: usize) [4]u8 {
    return section_fills[index % section_fills.len];
}

// -----------------------------------------------------------------------
// Utility
// -----------------------------------------------------------------------

fn trimSlice(s: []const u8) []const u8 {
    var start: usize = 0;
    while (start < s.len and isWhitespace(s[start])) start += 1;
    var end = s.len;
    while (end > start and isWhitespace(s[end - 1])) end -= 1;
    return s[start..end];
}

fn isWhitespace(c: u8) bool {
    return c == ' ' or c == '\t' or c == '\r' or c == '\n';
}

// -----------------------------------------------------------------------
// Tests
// -----------------------------------------------------------------------

test "journey model: create empty" {
    const allocator = std.testing.allocator;
    var diagram = JourneyDiagram.init(allocator);
    defer diagram.deinit();

    try std.testing.expectEqual(@as(usize, 0), diagram.taskCount());
    try std.testing.expectEqual(@as(usize, 0), diagram.sectionCount());
    try std.testing.expect(diagram.title == null);
}

test "journey model: set title" {
    const allocator = std.testing.allocator;
    var diagram = JourneyDiagram.init(allocator);
    defer diagram.deinit();

    try diagram.setTitle("Shopping Journey");
    try std.testing.expect(diagram.title != null);
    try std.testing.expectEqualStrings("Shopping Journey", diagram.title.?);
}

test "journey model: add sections" {
    const allocator = std.testing.allocator;
    var diagram = JourneyDiagram.init(allocator);
    defer diagram.deinit();

    try diagram.addSection("Getting Ready");
    try diagram.addSection("Going Out");

    try std.testing.expectEqual(@as(usize, 2), diagram.sectionCount());
    try std.testing.expectEqualStrings("Getting Ready", diagram.sections.items[0].data);
    try std.testing.expectEqualStrings("Going Out", diagram.sections.items[1].data);
}

test "journey model: duplicate sections not added" {
    const allocator = std.testing.allocator;
    var diagram = JourneyDiagram.init(allocator);
    defer diagram.deinit();

    try diagram.addSection("Shopping");
    try diagram.addSection("Shopping");

    try std.testing.expectEqual(@as(usize, 1), diagram.sectionCount());
}

test "journey model: add tasks with scores and actors" {
    const allocator = std.testing.allocator;
    var diagram = JourneyDiagram.init(allocator);
    defer diagram.deinit();

    try diagram.addSection("Journey to the shops");
    try diagram.addTask("Get car keys", ":5:Dad");
    try diagram.addTask("Go to car", ":3:Dad, Mum, Child");
    try diagram.addTask("Drive to supermarket", ":4:Dad");

    try diagram.addSection("Do shopping");
    try diagram.addTask("Go shopping", ":5:Mum");

    const tasks = diagram.getTasks();
    try std.testing.expectEqual(@as(usize, 4), tasks.len);

    // Check first task
    try std.testing.expectEqualStrings("Get car keys", tasks[0].task);
    try std.testing.expectEqual(@as(i32, 5), tasks[0].score);
    try std.testing.expectEqual(@as(usize, 1), tasks[0].people.items.len);
    try std.testing.expectEqualStrings("Dad", tasks[0].people.items[0].data);
    try std.testing.expectEqualStrings("Journey to the shops", tasks[0].section);

    // Check second task (multiple actors)
    try std.testing.expectEqualStrings("Go to car", tasks[1].task);
    try std.testing.expectEqual(@as(i32, 3), tasks[1].score);
    try std.testing.expectEqual(@as(usize, 3), tasks[1].people.items.len);
    try std.testing.expectEqualStrings("Dad", tasks[1].people.items[0].data);
    try std.testing.expectEqualStrings("Mum", tasks[1].people.items[1].data);
    try std.testing.expectEqualStrings("Child", tasks[1].people.items[2].data);

    // Check fourth task (in second section)
    try std.testing.expectEqualStrings("Go shopping", tasks[3].task);
    try std.testing.expectEqual(@as(i32, 5), tasks[3].score);
    try std.testing.expectEqualStrings("Do shopping", tasks[3].section);
}

test "journey model: get actors sorted and deduplicated" {
    const allocator = std.testing.allocator;
    var diagram = JourneyDiagram.init(allocator);
    defer diagram.deinit();

    try diagram.addSection("Section 1");
    try diagram.addTask("Task A", ":5:Charlie, Alice");
    try diagram.addTask("Task B", ":4:Bob, Alice");

    const actors = try diagram.getActors();
    defer allocator.free(actors);

    try std.testing.expectEqual(@as(usize, 3), actors.len);
    try std.testing.expectEqualStrings("Alice", actors[0].data);
    try std.testing.expectEqualStrings("Bob", actors[1].data);
    try std.testing.expectEqualStrings("Charlie", actors[2].data);
}

test "journey model: task data without leading colon" {
    const allocator = std.testing.allocator;
    var diagram = JourneyDiagram.init(allocator);
    defer diagram.deinit();

    try diagram.addSection("Test");
    try diagram.addTask("test1", "4: id1, id3");
    try diagram.addTask("test2", "2: id2");

    const tasks = diagram.getTasks();
    try std.testing.expectEqual(@as(i32, 4), tasks[0].score);
    try std.testing.expectEqual(@as(usize, 2), tasks[0].people.items.len);
    try std.testing.expectEqualStrings("id1", tasks[0].people.items[0].data);
    try std.testing.expectEqualStrings("id3", tasks[0].people.items[1].data);
    try std.testing.expectEqual(@as(i32, 2), tasks[1].score);
    try std.testing.expectEqual(@as(usize, 1), tasks[1].people.items.len);
}

test "journey model: accessibility fields" {
    const allocator = std.testing.allocator;
    var diagram = JourneyDiagram.init(allocator);
    defer diagram.deinit();

    try diagram.setAccTitle("Shopping");
    try diagram.setAccDescr("A user journey for shopping");

    try std.testing.expectEqualStrings("Shopping", diagram.acc_title.?);
    try std.testing.expectEqualStrings("A user journey for shopping", diagram.acc_descr.?);
}

test "journey model: empty actors list" {
    const allocator = std.testing.allocator;
    var diagram = JourneyDiagram.init(allocator);
    defer diagram.deinit();

    const actors = try diagram.getActors();
    defer allocator.free(actors);

    try std.testing.expectEqual(@as(usize, 0), actors.len);
}

test "journey model: color palette wraps" {
    try std.testing.expectEqual(actor_colors[0], actorColor(8));
    try std.testing.expectEqual(actor_colors[3], actorColor(11));
    try std.testing.expectEqual(section_fills[0], sectionFill(8));
    try std.testing.expectEqual(section_fills[2], sectionFill(10));
}
