//! Sequence diagram parser for Mermaid syntax.
//!
//! Parses the text-based Mermaid sequence diagram format into a
//! `SequenceDiagram` model that can be laid out and rendered.
//!
//! Supported syntax:
//!   - `sequenceDiagram` header
//!   - `participant X` / `participant X as Alias`
//!   - `actor X` / `actor X as Alias`
//!   - `autonumber`
//!   - `title: text`
//!   - Messages: `A->>B: text`, `A-->>B: text`, `A-)B: text`, etc.
//!   - Activation: `activate X`, `deactivate X`, `+`/`-` suffixes
//!   - Notes: `Note left of X: text`, `Note right of X: text`,
//!            `Note over X: text`, `Note over X,Y: text`
//!   - Fragments: `loop`, `alt`/`else`, `opt`, `par`/`and`,
//!                `critical`/`option`, `break`, `rect` ... `end`

const std = @import("std");
const seq_model = @import("model.zig");

const SequenceDiagram = seq_model.SequenceDiagram;
const Participant = seq_model.Participant;
const ParticipantKind = seq_model.ParticipantKind;
const Message = seq_model.Message;
const MessageArrowType = seq_model.MessageArrowType;
const Note = seq_model.Note;
const NotePosition = seq_model.NotePosition;
const Activation = seq_model.Activation;
const Fragment = seq_model.Fragment;
const FragmentKind = seq_model.FragmentKind;
const FragmentSection = seq_model.FragmentSection;
const Event = seq_model.Event;
const EventKind = seq_model.EventKind;

pub const ParseError = error{
    UnexpectedToken,
    InvalidArrow,
    UnknownParticipant,
    UnterminatedFragment,
    OutOfMemory,
    MismatchedEnd,
};

/// Maximum fragment nesting depth.
const max_fragment_depth = 32;

// =======================================================================
// Parser
// =======================================================================

pub const Parser = struct {
    allocator: std.mem.Allocator,
    source: []const u8,
    pos: usize,
    diagram: SequenceDiagram,

    /// Stack of open fragment indices for nesting.
    fragment_stack_buf: [max_fragment_depth]usize = undefined,
    fragment_stack_len: usize = 0,

    /// Per-participant activation depth (for computing nesting level of
    /// activation bars). Fixed-size buffer; supports up to 64 participants.
    activation_depth: [64]usize = [_]usize{0} ** 64,

    /// Stack of open activation indices per participant so we can pair
    /// activate / deactivate. Up to 64 participants * 8 nesting = 512.
    activation_stack_buf: [512]usize = undefined,
    activation_stack_len: usize = 0,

    /// Running message counter (for autonumber).
    message_counter: usize = 0,

    pub fn init(allocator: std.mem.Allocator, source: []const u8) Parser {
        return .{
            .allocator = allocator,
            .source = source,
            .pos = 0,
            .diagram = SequenceDiagram.init(allocator),
        };
    }

    pub fn deinit(self: *Parser) void {
        self.diagram.deinit();
    }

    // -------------------------------------------------------------------
    // Public entry point
    // -------------------------------------------------------------------

    /// Parse the full source and return the populated diagram. The caller
    /// takes ownership of the diagram and must call `deinit()` on it.
    pub fn parse(self: *Parser) !SequenceDiagram {
        // Skip leading whitespace / blank lines.
        self.skipWhitespace();

        // Expect the `sequenceDiagram` header keyword.
        if (!self.matchLiteral("sequenceDiagram")) {
            return ParseError.UnexpectedToken;
        }
        self.skipToNextLine();

        // Parse statements until EOF.
        while (self.pos < self.source.len) {
            self.skipWhitespace();
            if (self.pos >= self.source.len) break;

            // Skip blank lines and comments.
            if (self.currentChar() == '\n') {
                self.pos += 1;
                continue;
            }
            if (self.startsWith("%%")) {
                self.skipToNextLine();
                continue;
            }

            try self.parseStatement();
        }

        // Close any remaining open activations (extend to last event).
        try self.closeAllActivations();

        // Return the diagram and replace self.diagram with a fresh empty
        // one so that deinit on the parser is a no-op.
        const result = self.diagram;
        self.diagram = SequenceDiagram.init(self.allocator);
        return result;
    }

    // -------------------------------------------------------------------
    // Statement dispatcher
    // -------------------------------------------------------------------

    fn parseStatement(self: *Parser) !void {
        // Try each statement type.
        if (self.matchLiteral("participant")) {
            try self.parseParticipantDecl(.box);
        } else if (self.matchLiteral("actor")) {
            try self.parseParticipantDecl(.actor);
        } else if (self.matchLiteral("autonumber")) {
            self.diagram.autonumber = true;
            self.skipToNextLine();
        } else if (self.matchLiteral("title")) {
            try self.parseTitleDirective();
        } else if (self.matchLiteralNoCase("note")) {
            try self.parseNote();
        } else if (self.matchLiteral("activate")) {
            try self.parseActivate();
        } else if (self.matchLiteral("deactivate")) {
            try self.parseDeactivate();
        } else if (self.matchLiteral("loop")) {
            try self.parseFragmentStart(.loop_block);
        } else if (self.matchLiteral("alt")) {
            try self.parseFragmentStart(.alt_block);
        } else if (self.matchLiteral("opt")) {
            try self.parseFragmentStart(.opt_block);
        } else if (self.matchLiteral("par")) {
            try self.parseFragmentStart(.par_block);
        } else if (self.matchLiteral("critical")) {
            try self.parseFragmentStart(.critical_block);
        } else if (self.matchLiteral("break")) {
            try self.parseFragmentStart(.break_block);
        } else if (self.matchLiteral("rect")) {
            try self.parseFragmentStart(.rect_block);
        } else if (self.matchLiteral("else") or self.matchLiteral("and") or self.matchLiteral("option")) {
            try self.parseFragmentSeparator();
        } else if (self.matchLiteral("end")) {
            try self.parseFragmentEnd();
        } else {
            // Must be a message: `From arrow To: text`
            try self.parseMessage();
        }
    }

    // -------------------------------------------------------------------
    // participant / actor
    // -------------------------------------------------------------------

    fn parseParticipantDecl(self: *Parser, kind: ParticipantKind) !void {
        self.skipInlineWhitespace();
        const id = self.readIdentifier();
        if (id.len == 0) {
            self.skipToNextLine();
            return;
        }

        // Check for `as Alias`.
        self.skipInlineWhitespace();
        var alias: ?[]const u8 = null;
        if (self.matchLiteral("as")) {
            self.skipInlineWhitespace();
            alias = self.readRestOfLine();
        } else {
            self.skipToNextLine();
        }

        // Create or update participant.
        const idx = try self.diagram.ensureParticipant(id);
        self.diagram.participants.items[idx].kind = kind;
        if (alias) |a| {
            if (a.len > 0) {
                self.diagram.participants.items[idx].alias = a;
            }
        }
    }

    // -------------------------------------------------------------------
    // title
    // -------------------------------------------------------------------

    fn parseTitleDirective(self: *Parser) !void {
        self.skipInlineWhitespace();
        // Optional colon after `title`.
        if (self.pos < self.source.len and self.currentChar() == ':') {
            self.pos += 1;
        }
        self.skipInlineWhitespace();
        const text = self.readRestOfLine();
        if (text.len > 0) {
            self.diagram.title = text;
        }
    }

    // -------------------------------------------------------------------
    // Note
    // -------------------------------------------------------------------

    fn parseNote(self: *Parser) !void {
        self.skipInlineWhitespace();

        var position: NotePosition = .right_of;

        if (self.matchLiteral("left")) {
            position = .left_of;
            self.skipInlineWhitespace();
            _ = self.matchLiteral("of");
        } else if (self.matchLiteral("right")) {
            position = .right_of;
            self.skipInlineWhitespace();
            _ = self.matchLiteral("of");
        } else if (self.matchLiteral("over")) {
            position = .over;
        } else {
            self.skipToNextLine();
            return;
        }

        self.skipInlineWhitespace();

        const first_id = self.readIdentifier();
        if (first_id.len == 0) {
            self.skipToNextLine();
            return;
        }
        const p1 = try self.diagram.ensureParticipant(first_id);

        var p2 = p1;
        // Check for comma-separated second participant (over X,Y).
        self.skipInlineWhitespace();
        if (self.pos < self.source.len and self.currentChar() == ',') {
            self.pos += 1; // skip comma
            self.skipInlineWhitespace();
            const second_id = self.readIdentifier();
            if (second_id.len > 0) {
                p2 = try self.diagram.ensureParticipant(second_id);
            }
        }

        // Expect `:` then text.
        self.skipInlineWhitespace();
        if (self.pos < self.source.len and self.currentChar() == ':') {
            self.pos += 1;
        }
        self.skipInlineWhitespace();
        const text = self.readRestOfLine();

        _ = try self.diagram.addNote(.{
            .position = position,
            .participant1 = p1,
            .participant2 = p2,
            .text = if (text.len > 0) text else null,
        });
    }

    // -------------------------------------------------------------------
    // activate / deactivate
    // -------------------------------------------------------------------

    fn parseActivate(self: *Parser) !void {
        self.skipInlineWhitespace();
        const id = self.readIdentifier();
        self.skipToNextLine();
        if (id.len == 0) return;
        const idx = try self.diagram.ensureParticipant(id);
        try self.pushActivation(idx);
    }

    fn parseDeactivate(self: *Parser) !void {
        self.skipInlineWhitespace();
        const id = self.readIdentifier();
        self.skipToNextLine();
        if (id.len == 0) return;
        const idx = try self.diagram.ensureParticipant(id);
        try self.popActivation(idx);
    }

    fn pushActivation(self: *Parser, participant: usize) !void {
        if (participant >= 64) return;
        const depth = self.activation_depth[participant];
        self.activation_depth[participant] += 1;

        const act_idx = self.diagram.activations.items.len;
        try self.diagram.activations.append(self.allocator, .{
            .participant = participant,
            .start_event = if (self.diagram.events.items.len > 0) self.diagram.events.items.len - 1 else 0,
            .end_event = 0, // will be filled on deactivate
            .depth = depth,
        });

        // Push onto stack.
        if (self.activation_stack_len < self.activation_stack_buf.len) {
            self.activation_stack_buf[self.activation_stack_len] = act_idx;
            self.activation_stack_len += 1;
        }
    }

    fn popActivation(self: *Parser, participant: usize) !void {
        if (participant >= 64) return;
        if (self.activation_depth[participant] > 0) {
            self.activation_depth[participant] -= 1;
        }

        // Find the most recent open activation for this participant.
        var i = self.activation_stack_len;
        while (i > 0) {
            i -= 1;
            const act_idx = self.activation_stack_buf[i];
            if (self.diagram.activations.items[act_idx].participant == participant and
                self.diagram.activations.items[act_idx].end_event == 0)
            {
                const end_ev = if (self.diagram.events.items.len > 0) self.diagram.events.items.len - 1 else 0;
                self.diagram.activations.items[act_idx].end_event = end_ev;
                // Remove from stack by shifting.
                if (i < self.activation_stack_len - 1) {
                    var j = i;
                    while (j < self.activation_stack_len - 1) : (j += 1) {
                        self.activation_stack_buf[j] = self.activation_stack_buf[j + 1];
                    }
                }
                self.activation_stack_len -= 1;
                break;
            }
        }
    }

    fn closeAllActivations(self: *Parser) !void {
        const end_ev = if (self.diagram.events.items.len > 0) self.diagram.events.items.len - 1 else 0;
        for (self.diagram.activations.items) |*act| {
            if (act.end_event == 0 and end_ev > 0) {
                act.end_event = end_ev;
            }
        }
    }

    // -------------------------------------------------------------------
    // Fragment blocks (loop, alt, opt, par, etc.)
    // -------------------------------------------------------------------

    fn parseFragmentStart(self: *Parser, kind: FragmentKind) !void {
        self.skipInlineWhitespace();
        const label = self.readRestOfLine();

        const frag_idx = self.diagram.fragments.items.len;
        var frag = Fragment{ .kind = kind };

        // First section.
        try frag.sections.append(self.allocator, .{
            .label = if (label.len > 0) label else null,
            .start_event = self.diagram.events.items.len,
        });

        frag.start_event = self.diagram.events.items.len;

        try self.diagram.fragments.append(self.allocator, frag);

        // Add fragment_start event.
        _ = try self.diagram.addEvent(.{ .kind = .fragment_start, .index = frag_idx });

        // Push onto nesting stack.
        if (self.fragment_stack_len < max_fragment_depth) {
            self.fragment_stack_buf[self.fragment_stack_len] = frag_idx;
            self.fragment_stack_len += 1;
        }
    }

    fn parseFragmentSeparator(self: *Parser) !void {
        self.skipInlineWhitespace();
        const label = self.readRestOfLine();

        if (self.fragment_stack_len == 0) return; // no open fragment

        const frag_idx = self.fragment_stack_buf[self.fragment_stack_len - 1];
        var frag = &self.diagram.fragments.items[frag_idx];

        // Close previous section.
        if (frag.sections.items.len > 0) {
            const prev = &frag.sections.items[frag.sections.items.len - 1];
            prev.end_event = if (self.diagram.events.items.len > 0) self.diagram.events.items.len - 1 else 0;
        }

        // Add separator event.
        _ = try self.diagram.addEvent(.{ .kind = .fragment_separator, .index = frag_idx });

        // Start new section.
        try frag.sections.append(self.allocator, .{
            .label = if (label.len > 0) label else null,
            .start_event = self.diagram.events.items.len,
        });
    }

    fn parseFragmentEnd(self: *Parser) !void {
        self.skipToNextLine();

        if (self.fragment_stack_len == 0) return; // mismatched end — ignore

        self.fragment_stack_len -= 1;
        const frag_idx = self.fragment_stack_buf[self.fragment_stack_len];
        var frag = &self.diagram.fragments.items[frag_idx];

        // Close last section.
        if (frag.sections.items.len > 0) {
            const last = &frag.sections.items[frag.sections.items.len - 1];
            last.end_event = if (self.diagram.events.items.len > 0) self.diagram.events.items.len - 1 else 0;
        }

        frag.end_event = if (self.diagram.events.items.len > 0) self.diagram.events.items.len - 1 else 0;

        // Add fragment_end event.
        _ = try self.diagram.addEvent(.{ .kind = .fragment_end, .index = frag_idx });

        // Compute participant span — scan all messages/notes in the
        // event range to find left/right-most participants.
        var left: usize = self.diagram.participants.items.len;
        var right: usize = 0;
        for (self.diagram.events.items) |ev| {
            switch (ev.kind) {
                .message => {
                    if (ev.index < self.diagram.messages.items.len) {
                        const m = self.diagram.messages.items[ev.index];
                        left = @min(left, @min(m.from, m.to));
                        right = @max(right, @max(m.from, m.to));
                    }
                },
                .note => {
                    if (ev.index < self.diagram.notes.items.len) {
                        const n = self.diagram.notes.items[ev.index];
                        left = @min(left, @min(n.participant1, n.participant2));
                        right = @max(right, @max(n.participant1, n.participant2));
                    }
                },
                else => {},
            }
        }
        if (left > right) {
            left = 0;
            right = if (self.diagram.participants.items.len > 0)
                self.diagram.participants.items.len - 1
            else
                0;
        }
        frag.left_participant = left;
        frag.right_participant = right;
    }

    // -------------------------------------------------------------------
    // Message: `From arrow To: text`
    // -------------------------------------------------------------------

    fn parseMessage(self: *Parser) !void {
        const from_id = self.readIdentifier();
        if (from_id.len == 0) {
            self.skipToNextLine();
            return;
        }

        // Parse arrow.
        const arrow = self.readArrow() orelse {
            // Not a recognized arrow — skip line.
            self.skipToNextLine();
            return;
        };

        // Destination — may have +/- suffix.
        self.skipInlineWhitespace();
        var activate = false;
        var deactivate = false;

        // Check for +/- before the identifier.
        if (self.pos < self.source.len and self.currentChar() == '+') {
            activate = true;
            self.pos += 1;
        } else if (self.pos < self.source.len and self.currentChar() == '-') {
            deactivate = true;
            self.pos += 1;
        }

        const to_id = self.readIdentifier();
        if (to_id.len == 0) {
            self.skipToNextLine();
            return;
        }

        // Check for +/- suffix on destination.
        if (self.pos < self.source.len and self.currentChar() == '+') {
            activate = true;
            self.pos += 1;
        } else if (self.pos < self.source.len and self.currentChar() == '-') {
            deactivate = true;
            self.pos += 1;
        }

        // Colon + message text (optional).
        self.skipInlineWhitespace();
        var text: ?[]const u8 = null;
        if (self.pos < self.source.len and self.currentChar() == ':') {
            self.pos += 1; // skip ':'
            self.skipInlineWhitespace();
            const t = self.readRestOfLine();
            if (t.len > 0) text = t;
        } else {
            self.skipToNextLine();
        }

        const from_idx = try self.diagram.ensureParticipant(from_id);
        const to_idx = try self.diagram.ensureParticipant(to_id);

        self.message_counter += 1;

        _ = try self.diagram.addMessage(.{
            .from = from_idx,
            .to = to_idx,
            .text = text,
            .arrow_type = arrow,
            .activate_target = activate,
            .deactivate_target = deactivate,
        });

        // Handle activation/deactivation from +/- suffixes.
        if (activate) {
            try self.pushActivation(to_idx);
        }
        if (deactivate) {
            try self.popActivation(to_idx);
        }
    }

    // -------------------------------------------------------------------
    // Arrow parsing
    // -------------------------------------------------------------------

    fn readArrow(self: *Parser) ?MessageArrowType {
        // Try each arrow pattern from longest to shortest to avoid
        // prefix-matching issues.
        //
        // We use matchExact (no word-boundary check) because arrows
        // are immediately followed by the destination participant
        // name, e.g. `A->>B: text`.
        //
        // Dashed arrows (--):
        //   -->>  dotted_arrow
        //   --x   dotted_cross
        //   --)   dotted_open
        //   -->   dotted_line
        //
        // Solid arrows (-):
        //   ->>   solid_arrow
        //   -x    solid_cross
        //   -)    solid_open
        //   ->    solid_line

        if (self.matchExact("-->>")) return .dotted_arrow;
        if (self.matchExactNoCase("--x")) return .dotted_cross;
        if (self.matchExact("--)")) return .dotted_open;
        if (self.matchExact("-->")) return .dotted_line;
        if (self.matchExact("->>")) return .solid_arrow;
        if (self.matchExactNoCase("-x")) return .solid_cross;
        if (self.matchExact("-)")) return .solid_open;
        if (self.matchExact("->")) return .solid_line;

        return null;
    }

    // -------------------------------------------------------------------
    // Low-level helpers
    // -------------------------------------------------------------------

    fn currentChar(self: *const Parser) u8 {
        return self.source[self.pos];
    }

    fn startsWith(self: *const Parser, prefix: []const u8) bool {
        if (self.pos + prefix.len > self.source.len) return false;
        return std.mem.eql(u8, self.source[self.pos .. self.pos + prefix.len], prefix);
    }

    /// Try to match a literal keyword at the current position. The match
    /// only succeeds if followed by a non-alphanumeric / non-underscore
    /// character (word boundary). Advances `pos` past the keyword on
    /// success.
    fn matchLiteral(self: *Parser, keyword: []const u8) bool {
        if (self.pos + keyword.len > self.source.len) return false;
        if (!std.mem.eql(u8, self.source[self.pos .. self.pos + keyword.len], keyword)) return false;
        // Check word boundary.
        if (self.pos + keyword.len < self.source.len) {
            const next = self.source[self.pos + keyword.len];
            if (isIdentChar(next)) return false;
        }
        self.pos += keyword.len;
        return true;
    }

    /// Case-insensitive variant of `matchLiteral`.
    fn matchLiteralNoCase(self: *Parser, keyword: []const u8) bool {
        if (self.pos + keyword.len > self.source.len) return false;
        for (0..keyword.len) |i| {
            if (std.ascii.toLower(self.source[self.pos + i]) != std.ascii.toLower(keyword[i])) return false;
        }
        // Word boundary.
        if (self.pos + keyword.len < self.source.len) {
            const next = self.source[self.pos + keyword.len];
            if (isIdentChar(next)) return false;
        }
        self.pos += keyword.len;
        return true;
    }

    /// Match an exact byte sequence at the current position without any
    /// word-boundary check. Used for arrow/operator tokens that are
    /// immediately followed by identifier characters.
    fn matchExact(self: *Parser, pattern: []const u8) bool {
        if (self.pos + pattern.len > self.source.len) return false;
        if (!std.mem.eql(u8, self.source[self.pos .. self.pos + pattern.len], pattern)) return false;
        self.pos += pattern.len;
        return true;
    }

    /// Case-insensitive variant of `matchExact`.
    fn matchExactNoCase(self: *Parser, pattern: []const u8) bool {
        if (self.pos + pattern.len > self.source.len) return false;
        for (0..pattern.len) |i| {
            if (std.ascii.toLower(self.source[self.pos + i]) != std.ascii.toLower(pattern[i])) return false;
        }
        self.pos += pattern.len;
        return true;
    }

    /// Read an identifier (sequence of alphanumeric + `_` chars).
    fn readIdentifier(self: *Parser) []const u8 {
        self.skipInlineWhitespace();
        const start = self.pos;
        while (self.pos < self.source.len and isIdentChar(self.source[self.pos])) {
            self.pos += 1;
        }
        return self.source[start..self.pos];
    }

    /// Read everything until end-of-line. Trims trailing whitespace.
    fn readRestOfLine(self: *Parser) []const u8 {
        const start = self.pos;
        while (self.pos < self.source.len and self.source[self.pos] != '\n') {
            self.pos += 1;
        }
        // Skip the newline.
        if (self.pos < self.source.len) self.pos += 1;

        // Trim trailing whitespace / CR.
        var end = self.pos;
        if (end > start and self.source[end - 1] == '\n') end -= 1;
        if (end > start and self.source[end - 1] == '\r') end -= 1;
        while (end > start and self.source[end - 1] == ' ') end -= 1;
        return self.source[start..end];
    }

    fn skipWhitespace(self: *Parser) void {
        while (self.pos < self.source.len) {
            const c = self.source[self.pos];
            if (c == ' ' or c == '\t' or c == '\r' or c == '\n') {
                self.pos += 1;
            } else {
                break;
            }
        }
    }

    fn skipInlineWhitespace(self: *Parser) void {
        while (self.pos < self.source.len) {
            const c = self.source[self.pos];
            if (c == ' ' or c == '\t' or c == '\r') {
                self.pos += 1;
            } else {
                break;
            }
        }
    }

    fn skipToNextLine(self: *Parser) void {
        while (self.pos < self.source.len and self.source[self.pos] != '\n') {
            self.pos += 1;
        }
        if (self.pos < self.source.len) self.pos += 1; // skip '\n'
    }
};

fn isIdentChar(c: u8) bool {
    return (c >= 'a' and c <= 'z') or
        (c >= 'A' and c <= 'Z') or
        (c >= '0' and c <= '9') or
        c == '_';
}

// =======================================================================
// Tests
// =======================================================================

const testing = std.testing;

test "parser: minimal diagram" {
    const src =
        \\sequenceDiagram
        \\    participant Alice
        \\    participant Bob
        \\    Alice->>Bob: Hello!
    ;
    var parser = Parser.init(testing.allocator, src);
    var diag = try parser.parse();
    defer diag.deinit();

    try testing.expectEqual(@as(usize, 2), diag.participants.items.len);
    try testing.expectEqualStrings("Alice", diag.participants.items[0].id);
    try testing.expectEqualStrings("Bob", diag.participants.items[1].id);
    try testing.expectEqual(@as(usize, 1), diag.messages.items.len);
    try testing.expectEqual(MessageArrowType.solid_arrow, diag.messages.items[0].arrow_type);
    try testing.expectEqualStrings("Hello!", diag.messages.items[0].text.?);
}

test "parser: participant with alias" {
    const src =
        \\sequenceDiagram
        \\    participant A as Alice Wonderland
        \\    participant B as Bob Builder
        \\    A->>B: Hi
    ;
    var parser = Parser.init(testing.allocator, src);
    var diag = try parser.parse();
    defer diag.deinit();

    try testing.expectEqualStrings("A", diag.participants.items[0].id);
    try testing.expectEqualStrings("Alice Wonderland", diag.participants.items[0].alias.?);
    try testing.expectEqualStrings("Bob Builder", diag.participants.items[1].alias.?);
}

test "parser: actor declaration" {
    const src =
        \\sequenceDiagram
        \\    actor User
        \\    participant Server
        \\    User->>Server: Request
    ;
    var parser = Parser.init(testing.allocator, src);
    var diag = try parser.parse();
    defer diag.deinit();

    try testing.expectEqual(ParticipantKind.actor, diag.participants.items[0].kind);
    try testing.expectEqual(ParticipantKind.box, diag.participants.items[1].kind);
}

test "parser: all arrow types" {
    const src =
        \\sequenceDiagram
        \\    participant A
        \\    participant B
        \\    A->B: solid line
        \\    A-->B: dotted line
        \\    A->>B: solid arrow
        \\    A-->>B: dotted arrow
        \\    A-xB: solid cross
        \\    A--xB: dotted cross
        \\    A-)B: solid open
        \\    A--)B: dotted open
    ;
    var parser = Parser.init(testing.allocator, src);
    var diag = try parser.parse();
    defer diag.deinit();

    try testing.expectEqual(@as(usize, 8), diag.messages.items.len);
    try testing.expectEqual(MessageArrowType.solid_line, diag.messages.items[0].arrow_type);
    try testing.expectEqual(MessageArrowType.dotted_line, diag.messages.items[1].arrow_type);
    try testing.expectEqual(MessageArrowType.solid_arrow, diag.messages.items[2].arrow_type);
    try testing.expectEqual(MessageArrowType.dotted_arrow, diag.messages.items[3].arrow_type);
    try testing.expectEqual(MessageArrowType.solid_cross, diag.messages.items[4].arrow_type);
    try testing.expectEqual(MessageArrowType.dotted_cross, diag.messages.items[5].arrow_type);
    try testing.expectEqual(MessageArrowType.solid_open, diag.messages.items[6].arrow_type);
    try testing.expectEqual(MessageArrowType.dotted_open, diag.messages.items[7].arrow_type);
}

test "parser: auto-declare participants from messages" {
    const src =
        \\sequenceDiagram
        \\    Alice->>Bob: Hello
        \\    Bob-->>Alice: Hi
    ;
    var parser = Parser.init(testing.allocator, src);
    var diag = try parser.parse();
    defer diag.deinit();

    try testing.expectEqual(@as(usize, 2), diag.participants.items.len);
    try testing.expectEqual(@as(usize, 2), diag.messages.items.len);
}

test "parser: notes" {
    const src =
        \\sequenceDiagram
        \\    participant A
        \\    participant B
        \\    Note right of A: Right note
        \\    Note left of B: Left note
        \\    Note over A,B: Spanning note
    ;
    var parser = Parser.init(testing.allocator, src);
    var diag = try parser.parse();
    defer diag.deinit();

    try testing.expectEqual(@as(usize, 3), diag.notes.items.len);
    try testing.expectEqual(NotePosition.right_of, diag.notes.items[0].position);
    try testing.expectEqual(NotePosition.left_of, diag.notes.items[1].position);
    try testing.expectEqual(NotePosition.over, diag.notes.items[2].position);
    try testing.expectEqualStrings("Right note", diag.notes.items[0].text.?);
    try testing.expectEqual(@as(usize, 0), diag.notes.items[2].participant1);
    try testing.expectEqual(@as(usize, 1), diag.notes.items[2].participant2);
}

test "parser: activate / deactivate" {
    const src =
        \\sequenceDiagram
        \\    participant A
        \\    participant B
        \\    A->>B: Request
        \\    activate B
        \\    B-->>A: Response
        \\    deactivate B
    ;
    var parser = Parser.init(testing.allocator, src);
    var diag = try parser.parse();
    defer diag.deinit();

    try testing.expectEqual(@as(usize, 1), diag.activations.items.len);
    try testing.expectEqual(@as(usize, 1), diag.activations.items[0].participant);
}

test "parser: +/- activation shorthand" {
    const src =
        \\sequenceDiagram
        \\    participant A
        \\    participant B
        \\    A->>+B: Request
        \\    B-->>-A: Response
    ;
    var parser = Parser.init(testing.allocator, src);
    var diag = try parser.parse();
    defer diag.deinit();

    try testing.expectEqual(@as(usize, 1), diag.activations.items.len);
    try testing.expectEqual(@as(usize, 1), diag.activations.items[0].participant);
    try testing.expect(diag.messages.items[0].activate_target);
    try testing.expect(diag.messages.items[1].deactivate_target);
}

test "parser: loop fragment" {
    const src =
        \\sequenceDiagram
        \\    participant A
        \\    participant B
        \\    loop Every minute
        \\        A->>B: Ping
        \\        B-->>A: Pong
        \\    end
    ;
    var parser = Parser.init(testing.allocator, src);
    var diag = try parser.parse();
    defer diag.deinit();

    try testing.expectEqual(@as(usize, 1), diag.fragments.items.len);
    try testing.expectEqual(FragmentKind.loop_block, diag.fragments.items[0].kind);
    try testing.expectEqual(@as(usize, 1), diag.fragments.items[0].sections.items.len);
    try testing.expectEqualStrings("Every minute", diag.fragments.items[0].sections.items[0].label.?);
}

test "parser: alt/else fragment" {
    const src =
        \\sequenceDiagram
        \\    participant A
        \\    participant B
        \\    alt Success
        \\        A->>B: OK
        \\    else Failure
        \\        A->>B: Error
        \\    end
    ;
    var parser = Parser.init(testing.allocator, src);
    var diag = try parser.parse();
    defer diag.deinit();

    try testing.expectEqual(@as(usize, 1), diag.fragments.items.len);
    try testing.expectEqual(FragmentKind.alt_block, diag.fragments.items[0].kind);
    try testing.expectEqual(@as(usize, 2), diag.fragments.items[0].sections.items.len);
    try testing.expectEqualStrings("Success", diag.fragments.items[0].sections.items[0].label.?);
    try testing.expectEqualStrings("Failure", diag.fragments.items[0].sections.items[1].label.?);
}

test "parser: par/and fragment" {
    const src =
        \\sequenceDiagram
        \\    participant A
        \\    participant B
        \\    participant C
        \\    par Task 1
        \\        A->>B: Do X
        \\    and Task 2
        \\        A->>C: Do Y
        \\    end
    ;
    var parser = Parser.init(testing.allocator, src);
    var diag = try parser.parse();
    defer diag.deinit();

    try testing.expectEqual(@as(usize, 1), diag.fragments.items.len);
    try testing.expectEqual(FragmentKind.par_block, diag.fragments.items[0].kind);
    try testing.expectEqual(@as(usize, 2), diag.fragments.items[0].sections.items.len);
}

test "parser: autonumber" {
    const src =
        \\sequenceDiagram
        \\    autonumber
        \\    A->>B: First
        \\    B->>A: Second
    ;
    var parser = Parser.init(testing.allocator, src);
    var diag = try parser.parse();
    defer diag.deinit();

    try testing.expect(diag.autonumber);
}

test "parser: title directive" {
    const src =
        \\sequenceDiagram
        \\    title: My Sequence
        \\    A->>B: Hello
    ;
    var parser = Parser.init(testing.allocator, src);
    var diag = try parser.parse();
    defer diag.deinit();

    try testing.expectEqualStrings("My Sequence", diag.title.?);
}

test "parser: comments ignored" {
    const src =
        \\sequenceDiagram
        \\    %% This is a comment
        \\    participant A
        \\    %% Another comment
        \\    A->>A: Self message
    ;
    var parser = Parser.init(testing.allocator, src);
    var diag = try parser.parse();
    defer diag.deinit();

    try testing.expectEqual(@as(usize, 1), diag.participants.items.len);
    try testing.expectEqual(@as(usize, 1), diag.messages.items.len);
    try testing.expect(diag.messages.items[0].isSelfMessage());
}

test "parser: self message" {
    const src =
        \\sequenceDiagram
        \\    participant A
        \\    A->>A: Think
    ;
    var parser = Parser.init(testing.allocator, src);
    var diag = try parser.parse();
    defer diag.deinit();

    try testing.expectEqual(@as(usize, 1), diag.messages.items.len);
    try testing.expect(diag.messages.items[0].isSelfMessage());
    try testing.expectEqualStrings("Think", diag.messages.items[0].text.?);
}

test "parser: complex diagram with multiple features" {
    const src =
        \\sequenceDiagram
        \\    participant A as Alice
        \\    participant B as Bob
        \\    participant C as Server
        \\    A->>B: Hello Bob!
        \\    B-->>A: Hi Alice!
        \\    Note over A,B: Authentication
        \\    A->>+C: Login request
        \\    C-->>-A: Token
        \\    A->>B: How are you?
        \\    B-->>A: I'm good, thanks!
        \\    Note right of B: Bob thinks
    ;
    var parser = Parser.init(testing.allocator, src);
    var diag = try parser.parse();
    defer diag.deinit();

    try testing.expectEqual(@as(usize, 3), diag.participants.items.len);
    try testing.expectEqualStrings("Alice", diag.participants.items[0].alias.?);
    try testing.expectEqual(@as(usize, 6), diag.messages.items.len);
    try testing.expectEqual(@as(usize, 2), diag.notes.items.len);
    try testing.expectEqual(@as(usize, 1), diag.activations.items.len);
}

test "parser: nested fragments" {
    const src =
        \\sequenceDiagram
        \\    participant A
        \\    participant B
        \\    alt Case 1
        \\        loop Retry
        \\            A->>B: Try
        \\        end
        \\    else Case 2
        \\        A->>B: Skip
        \\    end
    ;
    var parser = Parser.init(testing.allocator, src);
    var diag = try parser.parse();
    defer diag.deinit();

    try testing.expectEqual(@as(usize, 2), diag.fragments.items.len);
    // alt is first, loop is second (in order of opening).
    try testing.expectEqual(FragmentKind.alt_block, diag.fragments.items[0].kind);
    try testing.expectEqual(FragmentKind.loop_block, diag.fragments.items[1].kind);
}

test "parser: message without text" {
    const src =
        \\sequenceDiagram
        \\    A->>B:
    ;
    var parser = Parser.init(testing.allocator, src);
    var diag = try parser.parse();
    defer diag.deinit();

    try testing.expectEqual(@as(usize, 1), diag.messages.items.len);
    try testing.expect(diag.messages.items[0].text == null);
}

test "parser: opt fragment" {
    const src =
        \\sequenceDiagram
        \\    participant A
        \\    participant B
        \\    opt Optional step
        \\        A->>B: Maybe
        \\    end
    ;
    var parser = Parser.init(testing.allocator, src);
    var diag = try parser.parse();
    defer diag.deinit();

    try testing.expectEqual(@as(usize, 1), diag.fragments.items.len);
    try testing.expectEqual(FragmentKind.opt_block, diag.fragments.items[0].kind);
}

test "parser: events ordering" {
    const src =
        \\sequenceDiagram
        \\    participant A
        \\    participant B
        \\    A->>B: First
        \\    Note over A: A note
        \\    B->>A: Second
    ;
    var parser = Parser.init(testing.allocator, src);
    var diag = try parser.parse();
    defer diag.deinit();

    try testing.expectEqual(@as(usize, 3), diag.eventCount());
    try testing.expectEqual(EventKind.message, diag.events.items[0].kind);
    try testing.expectEqual(EventKind.note, diag.events.items[1].kind);
    try testing.expectEqual(EventKind.message, diag.events.items[2].kind);
}
