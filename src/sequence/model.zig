//! Sequence diagram data model.
//!
//! Represents all the elements of a Mermaid sequence diagram:
//! participants, messages, activations, notes, and fragment blocks
//! (loop, alt, opt, par, critical, break, rect).

const std = @import("std");

// -----------------------------------------------------------------------
// Participant
// -----------------------------------------------------------------------

/// The visual shape used to render a participant header/footer.
pub const ParticipantKind = enum {
    /// Rectangular box (default `participant` keyword).
    box,
    /// Stick-figure actor (`actor` keyword).
    actor,
};

/// A participant (lifeline column) in the sequence diagram.
pub const Participant = struct {
    /// Internal identifier (the short name used in messages).
    id: []const u8,
    /// Display label. Falls back to `id` when null.
    alias: ?[]const u8 = null,
    alias_owned: bool = false,
    /// Whether this was declared with `actor` vs `participant`.
    kind: ParticipantKind = .box,

    // ---- Layout output (filled in by layout) ----
    /// Centre X of the lifeline column.
    center_x: f64 = 0,
    /// Width of the participant header box.
    box_width: f64 = 0,
    /// Height of the participant header box.
    box_height: f64 = 0,

    pub fn displayName(self: *const Participant) []const u8 {
        return self.alias orelse self.id;
    }

    pub fn deinit(self: *Participant, allocator: std.mem.Allocator) void {
        if (self.alias_owned) {
            if (self.alias) |a| allocator.free(a);
        }
    }
};

// -----------------------------------------------------------------------
// Messages
// -----------------------------------------------------------------------

/// Arrow/line style for a message between two participants.
pub const MessageArrowType = enum {
    /// `->` Solid line, no arrowhead.
    solid_line,
    /// `-->` Dotted line, no arrowhead.
    dotted_line,
    /// `->>` Solid line with filled arrowhead.
    solid_arrow,
    /// `-->>` Dotted line with filled arrowhead.
    dotted_arrow,
    /// `-x` Solid line with cross (lost message).
    solid_cross,
    /// `--x` Dotted line with cross (lost message).
    dotted_cross,
    /// `-)` Solid line with open arrowhead (async).
    solid_open,
    /// `--)` Dotted line with open arrowhead (async).
    dotted_open,

    pub fn isDashed(self: MessageArrowType) bool {
        return switch (self) {
            .dotted_line, .dotted_arrow, .dotted_cross, .dotted_open => true,
            else => false,
        };
    }

    pub fn hasArrowhead(self: MessageArrowType) bool {
        return switch (self) {
            .solid_arrow, .dotted_arrow, .solid_open, .dotted_open => true,
            else => false,
        };
    }

    pub fn isCross(self: MessageArrowType) bool {
        return switch (self) {
            .solid_cross, .dotted_cross => true,
            else => false,
        };
    }

    pub fn isOpenArrow(self: MessageArrowType) bool {
        return switch (self) {
            .solid_open, .dotted_open => true,
            else => false,
        };
    }
};

/// A message (arrow) between two participants.
pub const Message = struct {
    /// Index of the source participant.
    from: usize,
    /// Index of the destination participant.
    to: usize,
    /// Label text on the arrow.
    text: ?[]const u8 = null,
    text_owned: bool = false,
    /// Arrow style.
    arrow_type: MessageArrowType = .solid_arrow,
    /// `+` suffix → activate the target after this message.
    activate_target: bool = false,
    /// `-` suffix → deactivate the target after this message.
    deactivate_target: bool = false,

    // ---- Layout output ----
    /// Y coordinate of this message row.
    y: f64 = 0,

    pub fn isSelfMessage(self: *const Message) bool {
        return self.from == self.to;
    }

    pub fn deinit(self: *Message, allocator: std.mem.Allocator) void {
        if (self.text_owned) {
            if (self.text) |t| allocator.free(t);
        }
    }
};

// -----------------------------------------------------------------------
// Notes
// -----------------------------------------------------------------------

/// Position of a note relative to participant lifeline(s).
pub const NotePosition = enum {
    /// `Note left of X`
    left_of,
    /// `Note right of X`
    right_of,
    /// `Note over X` or `Note over X,Y`
    over,
};

/// A note box attached to one or two participants.
pub const Note = struct {
    position: NotePosition = .right_of,
    /// Index of the first (or only) participant.
    participant1: usize = 0,
    /// Index of the second participant (for `over X,Y`).  Same as
    /// `participant1` when only one participant is specified.
    participant2: usize = 0,
    /// Note text content.
    text: ?[]const u8 = null,
    text_owned: bool = false,

    // ---- Layout output ----
    /// Y of this note row (same row coordinate system as messages).
    y: f64 = 0,
    /// Computed width.
    width: f64 = 0,
    /// Computed height.
    height: f64 = 0,

    pub fn deinit(self: *Note, allocator: std.mem.Allocator) void {
        if (self.text_owned) {
            if (self.text) |t| allocator.free(t);
        }
    }
};

// -----------------------------------------------------------------------
// Activations
// -----------------------------------------------------------------------

/// Represents a period of activation (thickened lifeline bar) on a
/// participant.  Start/end are expressed as *event indices* (row numbers
/// in the event list) so layout can convert them to Y coordinates.
pub const Activation = struct {
    /// Participant index.
    participant: usize,
    /// Event index where activation starts.
    start_event: usize = 0,
    /// Event index where activation ends.
    end_event: usize = 0,
    /// Nesting depth (0 = outermost).  Used to offset overlapping bars.
    depth: usize = 0,

    // ---- Layout output ----
    start_y: f64 = 0,
    end_y: f64 = 0,
};

// -----------------------------------------------------------------------
// Fragments (combined / interaction blocks)
// -----------------------------------------------------------------------

/// The kind of interaction fragment.
pub const FragmentKind = enum {
    loop_block,
    alt_block,
    opt_block,
    par_block,
    critical_block,
    break_block,
    rect_block,
};

/// One section within a fragment. An `alt` block has an initial section
/// and one `else` section for each `else` keyword. A `par` block has
/// one section per `and` keyword plus the initial section.
pub const FragmentSection = struct {
    /// Label (condition / description) for this section. For the first
    /// section this is the fragment header text, for `else`/`and` sections
    /// it is the text after the keyword.
    label: ?[]const u8 = null,
    label_owned: bool = false,
    /// Index of the first event in this section.
    start_event: usize = 0,
    /// Index of the last event in this section (inclusive).
    end_event: usize = 0,

    // ---- Layout output ----
    start_y: f64 = 0,
    end_y: f64 = 0,

    pub fn deinit(self: *FragmentSection, allocator: std.mem.Allocator) void {
        if (self.label_owned) {
            if (self.label) |l| allocator.free(l);
        }
    }
};

/// An interaction fragment (loop, alt, opt, par, critical, break, rect).
pub const Fragment = struct {
    kind: FragmentKind,
    sections: std.ArrayListUnmanaged(FragmentSection) = .{},
    /// Depth of nesting (0 = outermost).
    depth: usize = 0,
    /// Index of the first event covered by the entire fragment.
    start_event: usize = 0,
    /// Index of the last event covered (inclusive).
    end_event: usize = 0,
    /// Left-most participant index involved.
    left_participant: usize = 0,
    /// Right-most participant index involved.
    right_participant: usize = 0,

    // ---- Layout output ----
    x: f64 = 0,
    y: f64 = 0,
    width: f64 = 0,
    height: f64 = 0,

    /// Background color for `rect` fragments.  RGBA.
    bg_color: ?[4]u8 = null,

    pub fn deinit(self: *Fragment, allocator: std.mem.Allocator) void {
        for (self.sections.items) |*s| s.deinit(allocator);
        self.sections.deinit(allocator);
    }
};

// -----------------------------------------------------------------------
// Events  — a flat, ordered list of "things that happen" used as the
// backbone for vertical layout.
// -----------------------------------------------------------------------

pub const EventKind = enum {
    message,
    note,
    /// Separator line between `else`/`and` sections within a fragment.
    fragment_separator,
    /// Opening of a fragment block.
    fragment_start,
    /// Closing of a fragment block.
    fragment_end,
};

/// An event is a single row in the sequence diagram. Messages, notes and
/// fragment boundaries all occupy rows.
pub const Event = struct {
    kind: EventKind,
    /// Index into the corresponding sub-array (messages, notes, or
    /// fragments) depending on `kind`.
    index: usize = 0,

    // ---- Layout output ----
    y: f64 = 0,
};

// -----------------------------------------------------------------------
// Top-level diagram container
// -----------------------------------------------------------------------

/// Complete sequence diagram model — the parser fills this in, and the
/// layout engine reads / writes the coordinate fields.
pub const SequenceDiagram = struct {
    allocator: std.mem.Allocator,

    participants: std.ArrayListUnmanaged(Participant) = .{},
    messages: std.ArrayListUnmanaged(Message) = .{},
    notes: std.ArrayListUnmanaged(Note) = .{},
    activations: std.ArrayListUnmanaged(Activation) = .{},
    fragments: std.ArrayListUnmanaged(Fragment) = .{},
    events: std.ArrayListUnmanaged(Event) = .{},

    /// Whether `autonumber` was specified.
    autonumber: bool = false,

    /// Title text (from `title:` directive), if any.
    title: ?[]const u8 = null,
    title_owned: bool = false,

    pub fn init(allocator: std.mem.Allocator) SequenceDiagram {
        return .{ .allocator = allocator };
    }

    pub fn deinit(self: *SequenceDiagram) void {
        for (self.participants.items) |*p| p.deinit(self.allocator);
        self.participants.deinit(self.allocator);

        for (self.messages.items) |*m| m.deinit(self.allocator);
        self.messages.deinit(self.allocator);

        for (self.notes.items) |*n| n.deinit(self.allocator);
        self.notes.deinit(self.allocator);

        self.activations.deinit(self.allocator);

        for (self.fragments.items) |*f| f.deinit(self.allocator);
        self.fragments.deinit(self.allocator);

        self.events.deinit(self.allocator);

        if (self.title_owned) {
            if (self.title) |t| self.allocator.free(t);
        }
    }

    // ----- Helpers used by the parser -----

    /// Look up a participant index by id, or return null.
    pub fn findParticipant(self: *const SequenceDiagram, id: []const u8) ?usize {
        for (self.participants.items, 0..) |p, i| {
            if (std.mem.eql(u8, p.id, id)) return i;
        }
        return null;
    }

    /// Ensure a participant exists and return its index. If the id is
    /// not yet known, a new participant is appended (auto-declaration).
    pub fn ensureParticipant(self: *SequenceDiagram, id: []const u8) !usize {
        if (self.findParticipant(id)) |idx| return idx;
        try self.participants.append(self.allocator, .{ .id = id });
        return self.participants.items.len - 1;
    }

    /// Add an event and return its index.
    pub fn addEvent(self: *SequenceDiagram, ev: Event) !usize {
        try self.events.append(self.allocator, ev);
        return self.events.items.len - 1;
    }

    /// Add a message, create a corresponding event, and return the
    /// message index.
    pub fn addMessage(self: *SequenceDiagram, msg: Message) !usize {
        try self.messages.append(self.allocator, msg);
        const msg_idx = self.messages.items.len - 1;
        _ = try self.addEvent(.{ .kind = .message, .index = msg_idx });
        return msg_idx;
    }

    /// Add a note, create a corresponding event, and return the note
    /// index.
    pub fn addNote(self: *SequenceDiagram, note: Note) !usize {
        try self.notes.append(self.allocator, note);
        const note_idx = self.notes.items.len - 1;
        _ = try self.addEvent(.{ .kind = .note, .index = note_idx });
        return note_idx;
    }

    /// Total number of events (rows) — used for vertical sizing.
    pub fn eventCount(self: *const SequenceDiagram) usize {
        return self.events.items.len;
    }
};

// =======================================================================
// Tests
// =======================================================================

const testing = std.testing;

test "model: SequenceDiagram init/deinit empty" {
    var diag = SequenceDiagram.init(testing.allocator);
    defer diag.deinit();

    try testing.expectEqual(@as(usize, 0), diag.participants.items.len);
    try testing.expectEqual(@as(usize, 0), diag.eventCount());
}

test "model: ensureParticipant auto-creates" {
    var diag = SequenceDiagram.init(testing.allocator);
    defer diag.deinit();

    const idx1 = try diag.ensureParticipant("Alice");
    const idx2 = try diag.ensureParticipant("Bob");
    const idx1_again = try diag.ensureParticipant("Alice");

    try testing.expectEqual(@as(usize, 0), idx1);
    try testing.expectEqual(@as(usize, 1), idx2);
    try testing.expectEqual(idx1, idx1_again);
    try testing.expectEqual(@as(usize, 2), diag.participants.items.len);
}

test "model: addMessage creates event" {
    var diag = SequenceDiagram.init(testing.allocator);
    defer diag.deinit();

    _ = try diag.ensureParticipant("A");
    _ = try diag.ensureParticipant("B");

    _ = try diag.addMessage(.{ .from = 0, .to = 1, .text = "hello" });

    try testing.expectEqual(@as(usize, 1), diag.messages.items.len);
    try testing.expectEqual(@as(usize, 1), diag.eventCount());
    try testing.expectEqual(EventKind.message, diag.events.items[0].kind);
}

test "model: addNote creates event" {
    var diag = SequenceDiagram.init(testing.allocator);
    defer diag.deinit();

    _ = try diag.ensureParticipant("X");

    _ = try diag.addNote(.{ .position = .right_of, .participant1 = 0, .participant2 = 0, .text = "a note" });

    try testing.expectEqual(@as(usize, 1), diag.notes.items.len);
    try testing.expectEqual(@as(usize, 1), diag.eventCount());
    try testing.expectEqual(EventKind.note, diag.events.items[0].kind);
}

test "model: MessageArrowType helpers" {
    try testing.expect(MessageArrowType.dotted_arrow.isDashed());
    try testing.expect(!MessageArrowType.solid_arrow.isDashed());
    try testing.expect(MessageArrowType.solid_arrow.hasArrowhead());
    try testing.expect(!MessageArrowType.solid_line.hasArrowhead());
    try testing.expect(MessageArrowType.solid_cross.isCross());
    try testing.expect(MessageArrowType.solid_open.isOpenArrow());
}

test "model: Participant displayName" {
    const p1 = Participant{ .id = "A", .alias = "Alice" };
    try testing.expectEqualStrings("Alice", p1.displayName());

    const p2 = Participant{ .id = "B" };
    try testing.expectEqualStrings("B", p2.displayName());
}

test "model: Message isSelfMessage" {
    const self_msg = Message{ .from = 1, .to = 1 };
    try testing.expect(self_msg.isSelfMessage());

    const normal_msg = Message{ .from = 0, .to = 1 };
    try testing.expect(!normal_msg.isSelfMessage());
}

test "model: Fragment sections" {
    var frag = Fragment{ .kind = .alt_block };
    defer frag.deinit(testing.allocator);

    try frag.sections.append(testing.allocator, .{ .label = "condition1" });
    try frag.sections.append(testing.allocator, .{ .label = "condition2" });

    try testing.expectEqual(@as(usize, 2), frag.sections.items.len);
    try testing.expectEqualStrings("condition1", frag.sections.items[0].label.?);
}

test "model: mixed events ordering" {
    var diag = SequenceDiagram.init(testing.allocator);
    defer diag.deinit();

    _ = try diag.ensureParticipant("A");
    _ = try diag.ensureParticipant("B");

    _ = try diag.addMessage(.{ .from = 0, .to = 1, .text = "msg1" });
    _ = try diag.addNote(.{ .position = .over, .participant1 = 0, .participant2 = 1, .text = "note1" });
    _ = try diag.addMessage(.{ .from = 1, .to = 0, .text = "msg2" });

    try testing.expectEqual(@as(usize, 3), diag.eventCount());
    try testing.expectEqual(EventKind.message, diag.events.items[0].kind);
    try testing.expectEqual(EventKind.note, diag.events.items[1].kind);
    try testing.expectEqual(EventKind.message, diag.events.items[2].kind);
}
