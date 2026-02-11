//! State diagram data model.
//!
//! Represents all elements of a Mermaid state diagram:
//! states (with types like start, end, fork, join, choice),
//! transitions/relations between states, notes, composite states,
//! and direction settings.

const std = @import("std");

/// State types matching mermaid.js stateDiagram
pub const StateType = enum {
    default,
    start,
    end,
    fork,
    join,
    choice,
    divider,

    pub fn fromStr(s: []const u8) StateType {
        if (eqlIgnoreCase(s, "fork")) return .fork;
        if (eqlIgnoreCase(s, "join")) return .join;
        if (eqlIgnoreCase(s, "choice")) return .choice;
        if (eqlIgnoreCase(s, "start")) return .start;
        if (eqlIgnoreCase(s, "end")) return .end;
        if (eqlIgnoreCase(s, "divider")) return .divider;
        return .default;
    }

    pub fn asStr(self: StateType) []const u8 {
        return switch (self) {
            .default => "default",
            .start => "start",
            .end => "end",
            .fork => "fork",
            .join => "join",
            .choice => "choice",
            .divider => "divider",
        };
    }
};

/// Note position (left or right of a state)
pub const NotePosition = enum {
    right_of,
    left_of,

    pub fn fromStr(s: []const u8) NotePosition {
        if (eqlIgnoreCase(s, "left of") or eqlIgnoreCase(s, "leftof") or eqlIgnoreCase(s, "left")) {
            return .left_of;
        }
        return .right_of;
    }
};

/// A note attached to a state
pub const Note = struct {
    position: NotePosition,
    text: []const u8,
    text_owned: bool = false,

    pub fn deinit(self: *Note, allocator: std.mem.Allocator) void {
        if (self.text_owned) {
            allocator.free(self.text);
        }
    }
};

/// Diagram direction
pub const Direction = enum {
    TB,
    BT,
    LR,
    RL,

    pub fn fromStr(s: []const u8) Direction {
        if (eqlIgnoreCase(s, "LR")) return .LR;
        if (eqlIgnoreCase(s, "RL")) return .RL;
        if (eqlIgnoreCase(s, "BT")) return .BT;
        return .TB;
    }

    pub fn asStr(self: Direction) []const u8 {
        return switch (self) {
            .TB => "TB",
            .BT => "BT",
            .LR => "LR",
            .RL => "RL",
        };
    }
};

/// A state in the diagram
pub const State = struct {
    /// State identifier
    id: []const u8,
    id_owned: bool = false,
    /// State type (default, start, end, fork, join, choice, divider)
    state_type: StateType = .default,
    /// Primary description (from `state ID : description`)
    description: ?[]const u8 = null,
    description_owned: bool = false,
    /// Additional descriptions
    descriptions: std.ArrayListUnmanaged(OwnedString) = .{},
    /// Note attached to this state
    note: ?Note = null,
    /// CSS classes applied
    classes: std.ArrayListUnmanaged(OwnedString) = .{},
    /// Nested statements for composite states
    children: std.ArrayListUnmanaged(Statement) = .{},
    /// Display alias (from `state "Description" as ID`)
    alias: ?[]const u8 = null,
    alias_owned: bool = false,
    /// Parent state ID for nested states
    parent: ?[]const u8 = null,
    parent_owned: bool = false,

    pub fn init(allocator: std.mem.Allocator, id: []const u8) !State {
        const owned_id = try allocator.dupe(u8, id);
        return .{
            .id = owned_id,
            .id_owned = true,
        };
    }

    pub fn initWithType(allocator: std.mem.Allocator, id: []const u8, state_type: StateType) !State {
        var s = try init(allocator, id);
        s.state_type = state_type;
        return s;
    }

    pub fn deinit(self: *State, allocator: std.mem.Allocator) void {
        if (self.id_owned) allocator.free(self.id);
        if (self.description_owned) {
            if (self.description) |d| allocator.free(d);
        }
        for (self.descriptions.items) |*item| {
            item.deinit(allocator);
        }
        self.descriptions.deinit(allocator);
        if (self.note) |*n| {
            var note = n.*;
            note.deinit(allocator);
        }
        for (self.classes.items) |*item| {
            item.deinit(allocator);
        }
        self.classes.deinit(allocator);
        for (self.children.items) |*child| {
            child.deinit(allocator);
        }
        self.children.deinit(allocator);
        if (self.alias_owned) {
            if (self.alias) |a| allocator.free(a);
        }
        if (self.parent_owned) {
            if (self.parent) |p| allocator.free(p);
        }
    }

    /// Get the display label for this state (alias or id — never description)
    pub fn displayLabel(self: *const State) []const u8 {
        if (self.alias) |a| return a;
        return self.id;
    }

    /// Returns true if this state has any descriptions (primary or additional)
    pub fn hasDescriptions(self: *const State) bool {
        return self.description != null or self.descriptions.items.len > 0;
    }

    /// Collect all descriptions (primary + additional) for rendering
    pub fn allDescriptions(self: *const State) struct { primary: ?[]const u8, extra: []const OwnedString } {
        return .{
            .primary = self.description,
            .extra = self.descriptions.items,
        };
    }

    /// Returns true if this state has nested children (composite state)
    pub fn isComposite(self: *const State) bool {
        return self.children.items.len > 0;
    }
};

/// A transition/relation between two states
pub const Relation = struct {
    /// Source state ID
    from: []const u8,
    from_owned: bool = false,
    /// Target state ID
    to: []const u8,
    to_owned: bool = false,
    /// Optional transition label
    label: ?[]const u8 = null,
    label_owned: bool = false,

    pub fn init(allocator: std.mem.Allocator, from: []const u8, to: []const u8, label: ?[]const u8) !Relation {
        const owned_from = try allocator.dupe(u8, from);
        errdefer allocator.free(owned_from);
        const owned_to = try allocator.dupe(u8, to);
        errdefer allocator.free(owned_to);
        const owned_label = if (label) |l| try allocator.dupe(u8, l) else null;

        return .{
            .from = owned_from,
            .from_owned = true,
            .to = owned_to,
            .to_owned = true,
            .label = owned_label,
            .label_owned = owned_label != null,
        };
    }

    pub fn deinit(self: *Relation, allocator: std.mem.Allocator) void {
        if (self.from_owned) allocator.free(self.from);
        if (self.to_owned) allocator.free(self.to);
        if (self.label_owned) {
            if (self.label) |l| allocator.free(l);
        }
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

/// Statement types in a state diagram document
pub const Statement = union(enum) {
    state: State,
    relation: Relation,
    direction: Direction,
    class_def: ClassDef,
    apply_class: ApplyClass,
    note: NoteStmt,

    pub fn deinit(self: *Statement, allocator: std.mem.Allocator) void {
        switch (self.*) {
            .state => |*s| s.deinit(allocator),
            .relation => |*r| r.deinit(allocator),
            .direction => {},
            .class_def => |*c| c.deinit(allocator),
            .apply_class => |*a| a.deinit(allocator),
            .note => |*n| n.deinit(allocator),
        }
    }
};

/// Style class definition: `classDef myClass fill:#f00,stroke:#000`
pub const ClassDef = struct {
    name: []const u8,
    name_owned: bool = false,
    styles: []const u8,
    styles_owned: bool = false,

    pub fn init(allocator: std.mem.Allocator, name: []const u8, styles: []const u8) !ClassDef {
        return .{
            .name = try allocator.dupe(u8, name),
            .name_owned = true,
            .styles = try allocator.dupe(u8, styles),
            .styles_owned = true,
        };
    }

    pub fn deinit(self: *ClassDef, allocator: std.mem.Allocator) void {
        if (self.name_owned) allocator.free(self.name);
        if (self.styles_owned) allocator.free(self.styles);
    }
};

/// Apply a class to a state: `class State1 myClass`
pub const ApplyClass = struct {
    state_id: []const u8,
    state_id_owned: bool = false,
    class_name: []const u8,
    class_name_owned: bool = false,

    pub fn init(allocator: std.mem.Allocator, state_id: []const u8, class_name: []const u8) !ApplyClass {
        return .{
            .state_id = try allocator.dupe(u8, state_id),
            .state_id_owned = true,
            .class_name = try allocator.dupe(u8, class_name),
            .class_name_owned = true,
        };
    }

    pub fn deinit(self: *ApplyClass, allocator: std.mem.Allocator) void {
        if (self.state_id_owned) allocator.free(self.state_id);
        if (self.class_name_owned) allocator.free(self.class_name);
    }
};

/// A note statement: `note right of State1 : text` or multiline
pub const NoteStmt = struct {
    state_id: []const u8,
    state_id_owned: bool = false,
    position: NotePosition,
    text: []const u8,
    text_owned: bool = false,

    pub fn init(allocator: std.mem.Allocator, state_id: []const u8, position: NotePosition, text: []const u8) !NoteStmt {
        return .{
            .state_id = try allocator.dupe(u8, state_id),
            .state_id_owned = true,
            .position = position,
            .text = try allocator.dupe(u8, text),
            .text_owned = true,
        };
    }

    pub fn deinit(self: *NoteStmt, allocator: std.mem.Allocator) void {
        if (self.state_id_owned) allocator.free(self.state_id);
        if (self.text_owned) allocator.free(self.text);
    }
};

/// The state diagram database — holds all parsed data
pub const StateDiagram = struct {
    /// All states indexed by ID
    states: std.StringHashMapUnmanaged(State) = .{},
    /// All transitions/relations
    relations: std.ArrayListUnmanaged(Relation) = .{},
    /// Root document statements (preserving order)
    root_doc: std.ArrayListUnmanaged(Statement) = .{},
    /// Style class definitions
    class_defs: std.StringHashMapUnmanaged(OwnedString) = .{},
    /// Diagram direction
    direction: Direction = .TB,
    /// Diagram title
    title: ?[]const u8 = null,
    title_owned: bool = false,
    /// Hide empty descriptions flag
    hide_empty: bool = false,
    /// Counters for generating unique IDs
    divider_cnt: usize = 0,
    start_cnt: usize = 0,
    end_cnt: usize = 0,
    /// Allocator
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) StateDiagram {
        return .{
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *StateDiagram) void {
        // Free all states
        var state_iter = self.states.iterator();
        while (state_iter.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
            entry.value_ptr.deinit(self.allocator);
        }
        self.states.deinit(self.allocator);

        // Free relations
        for (self.relations.items) |*r| {
            r.deinit(self.allocator);
        }
        self.relations.deinit(self.allocator);

        // Free root doc
        for (self.root_doc.items) |*stmt| {
            stmt.deinit(self.allocator);
        }
        self.root_doc.deinit(self.allocator);

        // Free class defs
        var class_iter = self.class_defs.iterator();
        while (class_iter.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
            entry.value_ptr.deinit(self.allocator);
        }
        self.class_defs.deinit(self.allocator);

        // Free title
        if (self.title_owned) {
            if (self.title) |t| self.allocator.free(t);
        }
    }

    /// Set the diagram title
    pub fn setTitle(self: *StateDiagram, title: []const u8) !void {
        if (self.title_owned) {
            if (self.title) |t| self.allocator.free(t);
        }
        self.title = try self.allocator.dupe(u8, title);
        self.title_owned = true;
    }

    /// Add or get a state by ID. Creates it if it doesn't exist.
    pub fn ensureState(self: *StateDiagram, id: []const u8) !*State {
        const gop = try self.states.getOrPut(self.allocator, id);
        if (!gop.found_existing) {
            // We need to dupe the key since StringHashMap doesn't own it
            const owned_key = try self.allocator.dupe(u8, id);
            gop.key_ptr.* = owned_key;
            gop.value_ptr.* = .{
                .id = owned_key,
                .id_owned = false, // owned by the hashmap key
            };
        }
        return gop.value_ptr;
    }

    /// Add a state with a specific type
    pub fn addStateWithType(self: *StateDiagram, id: []const u8, state_type: StateType) !*State {
        const state = try self.ensureState(id);
        state.state_type = state_type;
        return state;
    }

    /// Get a state by ID (read-only)
    pub fn getState(self: *const StateDiagram, id: []const u8) ?*const State {
        // Need to cast away const for the hashmap lookup
        const mutable_self = @constCast(self);
        if (mutable_self.states.getPtr(id)) |ptr| {
            return ptr;
        }
        return null;
    }

    /// Add a description to a state
    pub fn addDescription(self: *StateDiagram, state_id: []const u8, desc: []const u8) !void {
        const state = try self.ensureState(state_id);
        if (state.description == null) {
            state.description = try self.allocator.dupe(u8, desc);
            state.description_owned = true;
        } else {
            try state.descriptions.append(self.allocator, try OwnedString.init(self.allocator, desc));
        }
    }

    /// Add a transition/relation between states.
    /// Handles [*] specially: converts to start/end states with unique IDs.
    pub fn addRelation(self: *StateDiagram, from: []const u8, to: []const u8, label: ?[]const u8, parent: ?[]const u8) !void {
        const actual_from = try self.resolveStarState(from, true, parent);
        defer self.allocator.free(actual_from);
        const actual_to = try self.resolveStarState(to, false, parent);
        defer self.allocator.free(actual_to);

        const rel = try Relation.init(self.allocator, actual_from, actual_to, label);
        try self.relations.append(self.allocator, rel);
    }

    /// Resolve [*] to a start or end state ID
    fn resolveStarState(self: *StateDiagram, id: []const u8, is_source: bool, parent: ?[]const u8) ![]const u8 {
        if (!std.mem.eql(u8, id, "[*]")) {
            _ = try self.ensureState(id);
            if (parent) |p| {
                try self.setParent(id, p);
            }
            return try self.allocator.dupe(u8, id);
        }

        const parent_name = parent orelse "root";
        if (is_source) {
            // [*] as source → start state
            const start_id = try std.fmt.allocPrint(self.allocator, "{s}_start", .{parent_name});
            const state = try self.ensureState(start_id);
            state.state_type = .start;
            if (parent) |p| {
                if (!state.parent_owned and state.parent == null) {
                    state.parent = try self.allocator.dupe(u8, p);
                    state.parent_owned = true;
                }
            }
            return start_id;
        } else {
            // [*] as target → end state
            const end_id = try std.fmt.allocPrint(self.allocator, "{s}_end", .{parent_name});
            const state = try self.ensureState(end_id);
            state.state_type = .end;
            if (parent) |p| {
                if (!state.parent_owned and state.parent == null) {
                    state.parent = try self.allocator.dupe(u8, p);
                    state.parent_owned = true;
                }
            }
            return end_id;
        }
    }

    /// Set a state's parent
    pub fn setParent(self: *StateDiagram, state_id: []const u8, parent_id: []const u8) !void {
        const state = try self.ensureState(state_id);
        if (state.parent == null) {
            state.parent = try self.allocator.dupe(u8, parent_id);
            state.parent_owned = true;
        }
    }

    /// Add a note to a state
    pub fn addNote(self: *StateDiagram, state_id: []const u8, position: NotePosition, text: []const u8) !void {
        const state = try self.ensureState(state_id);
        if (state.note) |*n| {
            var note = n.*;
            note.deinit(self.allocator);
        }
        state.note = .{
            .position = position,
            .text = try self.allocator.dupe(u8, text),
            .text_owned = true,
        };
    }

    /// Add a style class definition
    pub fn addClassDef(self: *StateDiagram, name: []const u8, styles: []const u8) !void {
        const gop = try self.class_defs.getOrPut(self.allocator, name);
        if (!gop.found_existing) {
            gop.key_ptr.* = try self.allocator.dupe(u8, name);
            gop.value_ptr.* = try OwnedString.init(self.allocator, styles);
        }
    }

    /// Apply a class to a state
    pub fn applyClass(self: *StateDiagram, state_id: []const u8, class_name: []const u8) !void {
        const state = try self.ensureState(state_id);
        try state.classes.append(self.allocator, try OwnedString.init(self.allocator, class_name));
    }

    /// Generate a unique divider ID
    pub fn nextDividerId(self: *StateDiagram) ![]const u8 {
        const id = try std.fmt.allocPrint(self.allocator, "divider-id-{d}", .{self.divider_cnt});
        self.divider_cnt += 1;
        return id;
    }

    /// Get all state IDs (caller must free the returned slice)
    pub fn allStateIds(self: *const StateDiagram) ![][]const u8 {
        const mutable = @constCast(self);
        var ids = std.ArrayListUnmanaged([]const u8){};
        var iter = mutable.states.iterator();
        while (iter.next()) |entry| {
            try ids.append(self.allocator, try self.allocator.dupe(u8, entry.key_ptr.*));
        }
        return ids.toOwnedSlice(self.allocator);
    }

    /// Get all relations
    pub fn getRelations(self: *const StateDiagram) []const Relation {
        return self.relations.items;
    }

    /// Get number of states
    pub fn stateCount(self: *const StateDiagram) usize {
        return @constCast(self).states.count();
    }

    /// Get number of relations
    pub fn relationCount(self: *const StateDiagram) usize {
        return self.relations.items.len;
    }
};

// -----------------------------------------------------------------------
// Mermaid-style state colors
// -----------------------------------------------------------------------

/// Default state fill color (light blue-grey, matching mermaid default theme)
pub const state_fill_color: [4]u8 = .{ 236, 236, 255, 255 }; // #ececff
/// Default state stroke color
pub const state_stroke_color: [4]u8 = .{ 147, 147, 210, 255 }; // #9393d2
/// Start/end state fill (black)
pub const start_end_fill: [4]u8 = .{ 0, 0, 0, 255 }; // #000000
/// Fork/join fill (black)
pub const fork_join_fill: [4]u8 = .{ 0, 0, 0, 255 }; // #000000
/// Choice diamond fill
pub const choice_fill: [4]u8 = .{ 236, 236, 255, 255 }; // same as state
/// Composite state header fill
pub const composite_header_fill: [4]u8 = .{ 220, 220, 248, 255 }; // slightly darker
/// Text color
pub const text_color: [4]u8 = .{ 51, 51, 51, 255 }; // #333333
/// Edge color
pub const edge_color: [4]u8 = .{ 51, 51, 51, 255 }; // #333333
/// Note fill color (light yellow)
pub const note_fill: [4]u8 = .{ 255, 255, 222, 255 }; // #ffffde
/// Note stroke color
pub const note_stroke: [4]u8 = .{ 170, 170, 51, 255 }; // #aaaa33

// -----------------------------------------------------------------------
// Helper
// -----------------------------------------------------------------------

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

test "state model: StateType fromStr" {
    try std.testing.expectEqual(StateType.fork, StateType.fromStr("fork"));
    try std.testing.expectEqual(StateType.fork, StateType.fromStr("Fork"));
    try std.testing.expectEqual(StateType.fork, StateType.fromStr("FORK"));
    try std.testing.expectEqual(StateType.join, StateType.fromStr("join"));
    try std.testing.expectEqual(StateType.choice, StateType.fromStr("choice"));
    try std.testing.expectEqual(StateType.start, StateType.fromStr("start"));
    try std.testing.expectEqual(StateType.end, StateType.fromStr("end"));
    try std.testing.expectEqual(StateType.default, StateType.fromStr("unknown"));
}

test "state model: Direction fromStr" {
    try std.testing.expectEqual(Direction.TB, Direction.fromStr("TB"));
    try std.testing.expectEqual(Direction.LR, Direction.fromStr("LR"));
    try std.testing.expectEqual(Direction.RL, Direction.fromStr("RL"));
    try std.testing.expectEqual(Direction.BT, Direction.fromStr("BT"));
    try std.testing.expectEqual(Direction.TB, Direction.fromStr("TD"));
}

test "state model: NotePosition fromStr" {
    try std.testing.expectEqual(NotePosition.left_of, NotePosition.fromStr("left of"));
    try std.testing.expectEqual(NotePosition.left_of, NotePosition.fromStr("left"));
    try std.testing.expectEqual(NotePosition.right_of, NotePosition.fromStr("right of"));
    try std.testing.expectEqual(NotePosition.right_of, NotePosition.fromStr("right"));
}

test "state model: create StateDiagram" {
    const allocator = std.testing.allocator;
    var diagram = StateDiagram.init(allocator);
    defer diagram.deinit();

    try std.testing.expectEqual(@as(usize, 0), diagram.stateCount());
    try std.testing.expectEqual(@as(usize, 0), diagram.relationCount());
}

test "state model: add states" {
    const allocator = std.testing.allocator;
    var diagram = StateDiagram.init(allocator);
    defer diagram.deinit();

    _ = try diagram.ensureState("Idle");
    _ = try diagram.ensureState("Active");
    _ = try diagram.ensureState("Idle"); // duplicate, should not increase count

    try std.testing.expectEqual(@as(usize, 2), diagram.stateCount());
}

test "state model: add state with type" {
    const allocator = std.testing.allocator;
    var diagram = StateDiagram.init(allocator);
    defer diagram.deinit();

    _ = try diagram.addStateWithType("forkNode", .fork);
    const state = diagram.getState("forkNode").?;
    try std.testing.expectEqual(StateType.fork, state.state_type);
}

test "state model: add description" {
    const allocator = std.testing.allocator;
    var diagram = StateDiagram.init(allocator);
    defer diagram.deinit();

    try diagram.addDescription("Idle", "Waiting for input");
    const state = diagram.getState("Idle").?;
    try std.testing.expect(state.description != null);
    try std.testing.expectEqualStrings("Waiting for input", state.description.?);
}

test "state model: add relation" {
    const allocator = std.testing.allocator;
    var diagram = StateDiagram.init(allocator);
    defer diagram.deinit();

    try diagram.addRelation("Idle", "Active", "activate", null);

    try std.testing.expectEqual(@as(usize, 1), diagram.relationCount());
    try std.testing.expectEqual(@as(usize, 2), diagram.stateCount());
    try std.testing.expectEqualStrings("Idle", diagram.relations.items[0].from);
    try std.testing.expectEqualStrings("Active", diagram.relations.items[0].to);
    try std.testing.expectEqualStrings("activate", diagram.relations.items[0].label.?);
}

test "state model: star state becomes start/end" {
    const allocator = std.testing.allocator;
    var diagram = StateDiagram.init(allocator);
    defer diagram.deinit();

    try diagram.addRelation("[*]", "Idle", null, null);
    try diagram.addRelation("Done", "[*]", null, null);

    try std.testing.expectEqual(@as(usize, 2), diagram.relationCount());

    // [*] as source should become root_start
    try std.testing.expectEqualStrings("root_start", diagram.relations.items[0].from);
    const start_state = diagram.getState("root_start").?;
    try std.testing.expectEqual(StateType.start, start_state.state_type);

    // [*] as target should become root_end
    try std.testing.expectEqualStrings("root_end", diagram.relations.items[1].to);
    const end_state = diagram.getState("root_end").?;
    try std.testing.expectEqual(StateType.end, end_state.state_type);
}

test "state model: add note" {
    const allocator = std.testing.allocator;
    var diagram = StateDiagram.init(allocator);
    defer diagram.deinit();

    try diagram.addNote("Idle", .right_of, "This is a note");
    const state = diagram.getState("Idle").?;
    try std.testing.expect(state.note != null);
    try std.testing.expectEqualStrings("This is a note", state.note.?.text);
    try std.testing.expectEqual(NotePosition.right_of, state.note.?.position);
}

test "state model: set title" {
    const allocator = std.testing.allocator;
    var diagram = StateDiagram.init(allocator);
    defer diagram.deinit();

    try diagram.setTitle("My State Diagram");
    try std.testing.expect(diagram.title != null);
    try std.testing.expectEqualStrings("My State Diagram", diagram.title.?);
}

test "state model: class def" {
    const allocator = std.testing.allocator;
    var diagram = StateDiagram.init(allocator);
    defer diagram.deinit();

    try diagram.addClassDef("highlight", "fill:#ff0,stroke:#000");
    try diagram.applyClass("Idle", "highlight");

    const state = diagram.getState("Idle").?;
    try std.testing.expectEqual(@as(usize, 1), state.classes.items.len);
    try std.testing.expectEqualStrings("highlight", state.classes.items[0].data);
}

test "state model: set parent" {
    const allocator = std.testing.allocator;
    var diagram = StateDiagram.init(allocator);
    defer diagram.deinit();

    _ = try diagram.ensureState("Inner");
    try diagram.setParent("Inner", "Outer");

    const state = diagram.getState("Inner").?;
    try std.testing.expect(state.parent != null);
    try std.testing.expectEqualStrings("Outer", state.parent.?);
}

test "state model: display label" {
    const allocator = std.testing.allocator;
    var diagram = StateDiagram.init(allocator);
    defer diagram.deinit();

    // State with no description or alias returns ID
    _ = try diagram.ensureState("Idle");
    const s1 = diagram.getState("Idle").?;
    try std.testing.expectEqualStrings("Idle", s1.displayLabel());

    // State with description still returns ID (description is supplementary)
    try diagram.addDescription("Active", "Processing");
    const s2 = diagram.getState("Active").?;
    try std.testing.expectEqualStrings("Active", s2.displayLabel());
    try std.testing.expect(s2.hasDescriptions());
    try std.testing.expectEqualStrings("Processing", s2.allDescriptions().primary.?);
}

test "state model: direction" {
    const allocator = std.testing.allocator;
    var diagram = StateDiagram.init(allocator);
    defer diagram.deinit();

    try std.testing.expectEqual(Direction.TB, diagram.direction);
    diagram.direction = .LR;
    try std.testing.expectEqual(Direction.LR, diagram.direction);
}

test "state model: divider counter" {
    const allocator = std.testing.allocator;
    var diagram = StateDiagram.init(allocator);
    defer diagram.deinit();

    const id1 = try diagram.nextDividerId();
    defer allocator.free(id1);
    const id2 = try diagram.nextDividerId();
    defer allocator.free(id2);

    try std.testing.expectEqualStrings("divider-id-0", id1);
    try std.testing.expectEqualStrings("divider-id-1", id2);
}
