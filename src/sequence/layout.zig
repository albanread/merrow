//! Sequence diagram layout engine.
//!
//! Takes a parsed `SequenceDiagram` and computes X/Y coordinates for
//! every element: participant boxes, lifelines, message arrows, notes,
//! activation bars, and fragment boxes.
//!
//! The layout is column-based:
//!   - Each participant occupies a vertical column (lifeline).
//!   - Events (messages, notes, fragment boundaries) are stacked
//!     vertically in declaration order, each occupying a "row".

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

// -----------------------------------------------------------------------
// Layout configuration
// -----------------------------------------------------------------------

pub const LayoutConfig = struct {
    /// Minimum horizontal distance between participant lifeline centres.
    participant_spacing: f64 = 200.0,
    /// Vertical distance between consecutive event rows.
    row_height: f64 = 50.0,
    /// Height of the participant header/footer box.
    participant_box_height: f64 = 40.0,
    /// Minimum width of a participant box.
    participant_min_width: f64 = 100.0,
    /// Horizontal padding inside the participant box around the label.
    participant_padding_h: f64 = 24.0,
    /// Vertical gap between the header box bottom and the first event.
    header_gap: f64 = 20.0,
    /// Vertical gap between the last event and the footer box top.
    footer_gap: f64 = 20.0,
    /// Width of the activation bar drawn on a lifeline.
    activation_bar_width: f64 = 16.0,
    /// Horizontal offset per nested activation bar.
    activation_nest_offset: f64 = 6.0,
    /// Note box default width.
    note_width: f64 = 150.0,
    /// Note box default height.
    note_height: f64 = 36.0,
    /// Extra characters-per-pixel estimate when no font is available.
    char_width_estimate: f64 = 8.0,
    /// Horizontal padding around fragments (beyond participant edges).
    fragment_padding_h: f64 = 20.0,
    /// Vertical padding at top/bottom of fragment boxes.
    fragment_padding_v: f64 = 10.0,
    /// Extra height for the fragment label header area.
    fragment_label_height: f64 = 24.0,
    /// Self-message loop width (horizontal extent of the loop-back).
    self_message_width: f64 = 40.0,
    /// Self-message loop height (vertical extent).
    self_message_height: f64 = 30.0,
    /// Extra row height for note events (notes may be taller).
    note_row_extra: f64 = 10.0,
    /// Left margin before the first participant.
    margin_left: f64 = 40.0,
    /// Top margin before the header boxes.
    margin_top: f64 = 30.0,
    /// Title area height (only used when title is present).
    title_height: f64 = 30.0,
    /// Minimum arrow length between adjacent participants.
    min_arrow_length: f64 = 80.0,
};

// -----------------------------------------------------------------------
// Layout result — overall dimensions
// -----------------------------------------------------------------------

pub const LayoutResult = struct {
    /// Total width of the diagram canvas.
    width: f64,
    /// Total height of the diagram canvas.
    height: f64,
    /// Y of the top edge of header participant boxes.
    header_y: f64,
    /// Y of the top edge of footer participant boxes.
    footer_y: f64,
    /// Y where the first event row lives.
    first_event_y: f64,
    /// Y where the last event row lives.
    last_event_y: f64,
    /// Title Y (centre baseline). 0 when no title.
    title_y: f64,
};

// -----------------------------------------------------------------------
// Public API
// -----------------------------------------------------------------------

/// Run layout on a `SequenceDiagram`. Mutates the coordinate fields on
/// participants, messages, notes, events, activations, and fragments
/// in-place.
pub fn layout(diag: *SequenceDiagram, config: LayoutConfig) LayoutResult {
    const num_participants = diag.participants.items.len;
    if (num_participants == 0) {
        return .{
            .width = config.margin_left * 2,
            .height = config.margin_top * 2,
            .header_y = config.margin_top,
            .footer_y = config.margin_top,
            .first_event_y = config.margin_top,
            .last_event_y = config.margin_top,
            .title_y = 0,
        };
    }

    // ----- Title -----
    var title_y: f64 = 0;
    var title_offset: f64 = 0;
    if (diag.title != null) {
        title_y = config.margin_top + config.title_height / 2.0;
        title_offset = config.title_height + 10.0;
    }

    // ----- Size participant boxes -----
    for (diag.participants.items) |*p| {
        const label = p.displayName();
        const text_w = @as(f64, @floatFromInt(label.len)) * config.char_width_estimate;
        p.box_width = @max(config.participant_min_width, text_w + config.participant_padding_h * 2);
        p.box_height = config.participant_box_height;
    }

    // ----- Compute participant X centres -----
    // Equal-spacing layout.
    {
        var cx: f64 = config.margin_left + diag.participants.items[0].box_width / 2.0;
        for (diag.participants.items) |*p| {
            p.center_x = cx;
            cx += config.participant_spacing;
        }
    }

    // ----- Header Y -----
    const header_y = config.margin_top + title_offset;

    // ----- Event Y coordinates -----
    const first_event_y = header_y + config.participant_box_height + config.header_gap;
    var current_y = first_event_y;

    for (diag.events.items) |*ev| {
        ev.y = current_y;

        // Propagate Y to messages / notes.
        switch (ev.kind) {
            .message => {
                if (ev.index < diag.messages.items.len) {
                    diag.messages.items[ev.index].y = current_y;
                    // Self-messages need extra vertical space.
                    if (diag.messages.items[ev.index].isSelfMessage()) {
                        current_y += config.self_message_height;
                    }
                }
            },
            .note => {
                if (ev.index < diag.notes.items.len) {
                    const note = &diag.notes.items[ev.index];
                    note.y = current_y;
                    // Estimate note dimensions.
                    if (note.text) |txt| {
                        const text_w = @as(f64, @floatFromInt(txt.len)) * config.char_width_estimate;
                        note.width = @max(config.note_width, text_w + 20.0);
                    } else {
                        note.width = config.note_width;
                    }
                    note.height = config.note_height;
                }
            },
            .fragment_start, .fragment_end, .fragment_separator => {},
        }
        current_y += config.row_height;
    }

    const last_event_y = if (diag.events.items.len > 0)
        diag.events.items[diag.events.items.len - 1].y
    else
        first_event_y;

    // ----- Footer Y -----
    const footer_y = last_event_y + config.footer_gap;

    // ----- Activation bars -----
    for (diag.activations.items) |*act| {
        // Map event indices to Y coordinates.
        act.start_y = eventY(diag, act.start_event);
        act.end_y = eventY(diag, act.end_event);
        // Ensure minimum height.
        if (act.end_y <= act.start_y) {
            act.end_y = act.start_y + config.row_height;
        }
    }

    // ----- Fragment boxes -----
    for (diag.fragments.items) |*frag| {
        // Vertical extent from start to end events.
        const frag_start_y = eventY(diag, frag.start_event) - config.fragment_padding_v - config.fragment_label_height;
        const frag_end_y = eventY(diag, frag.end_event) + config.fragment_padding_v;

        // Horizontal extent from participant columns.
        const left_x = if (frag.left_participant < diag.participants.items.len)
            diag.participants.items[frag.left_participant].center_x - diag.participants.items[frag.left_participant].box_width / 2.0 - config.fragment_padding_h
        else
            config.margin_left;

        const right_x = if (frag.right_participant < diag.participants.items.len)
            diag.participants.items[frag.right_participant].center_x + diag.participants.items[frag.right_participant].box_width / 2.0 + config.fragment_padding_h
        else
            config.margin_left + config.participant_spacing;

        frag.x = left_x;
        frag.y = frag_start_y;
        frag.width = right_x - left_x;
        frag.height = frag_end_y - frag_start_y;

        // Lay out sections.
        for (frag.sections.items) |*sec| {
            sec.start_y = eventY(diag, sec.start_event);
            sec.end_y = eventY(diag, sec.end_event);
        }
    }

    // ----- Overall dimensions -----
    const last_participant = &diag.participants.items[num_participants - 1];
    const total_width = last_participant.center_x + last_participant.box_width / 2.0 + config.margin_left;
    const total_height = footer_y + config.participant_box_height + config.margin_top;

    return .{
        .width = total_width,
        .height = total_height,
        .header_y = header_y,
        .footer_y = footer_y,
        .first_event_y = first_event_y,
        .last_event_y = last_event_y,
        .title_y = title_y,
    };
}

// -----------------------------------------------------------------------
// Helpers
// -----------------------------------------------------------------------

/// Get the Y coordinate for a given event index, falling back to 0.
fn eventY(diag: *const SequenceDiagram, event_idx: usize) f64 {
    if (event_idx < diag.events.items.len) {
        return diag.events.items[event_idx].y;
    }
    return 0;
}

// =======================================================================
// Tests
// =======================================================================

const testing = std.testing;

test "layout: empty diagram" {
    var diag = SequenceDiagram.init(testing.allocator);
    defer diag.deinit();

    const result = layout(&diag, .{});

    try testing.expect(result.width > 0);
    try testing.expect(result.height > 0);
}

test "layout: two participants" {
    var diag = SequenceDiagram.init(testing.allocator);
    defer diag.deinit();

    _ = try diag.ensureParticipant("Alice");
    _ = try diag.ensureParticipant("Bob");

    const config = LayoutConfig{};
    const result = layout(&diag, config);

    // Participants should be spaced apart.
    try testing.expect(diag.participants.items[1].center_x > diag.participants.items[0].center_x);

    // Both should have non-zero box dimensions.
    try testing.expect(diag.participants.items[0].box_width >= config.participant_min_width);
    try testing.expect(diag.participants.items[0].box_height == config.participant_box_height);

    // Overall canvas should be reasonable.
    try testing.expect(result.width > 0);
    try testing.expect(result.height > 0);
    try testing.expect(result.header_y > 0);
}

test "layout: messages get Y coordinates" {
    var diag = SequenceDiagram.init(testing.allocator);
    defer diag.deinit();

    _ = try diag.ensureParticipant("A");
    _ = try diag.ensureParticipant("B");
    _ = try diag.addMessage(.{ .from = 0, .to = 1, .text = "msg1" });
    _ = try diag.addMessage(.{ .from = 1, .to = 0, .text = "msg2" });
    _ = try diag.addMessage(.{ .from = 0, .to = 1, .text = "msg3" });

    const result = layout(&diag, .{});

    // Each message should have a Y > header.
    for (diag.messages.items) |m| {
        try testing.expect(m.y > result.header_y);
    }
    // Messages should be in increasing Y order.
    try testing.expect(diag.messages.items[1].y > diag.messages.items[0].y);
    try testing.expect(diag.messages.items[2].y > diag.messages.items[1].y);
}

test "layout: self message takes extra space" {
    var diag = SequenceDiagram.init(testing.allocator);
    defer diag.deinit();

    _ = try diag.ensureParticipant("A");
    _ = try diag.ensureParticipant("B");
    _ = try diag.addMessage(.{ .from = 0, .to = 0, .text = "self" }); // self-message
    _ = try diag.addMessage(.{ .from = 0, .to = 1, .text = "next" });

    const config = LayoutConfig{};
    _ = layout(&diag, config);

    // The gap after a self-message should be larger than the standard row_height.
    const gap = diag.messages.items[1].y - diag.messages.items[0].y;
    try testing.expect(gap >= config.row_height + config.self_message_height - 1.0);
}

test "layout: notes get coordinates" {
    var diag = SequenceDiagram.init(testing.allocator);
    defer diag.deinit();

    _ = try diag.ensureParticipant("X");
    _ = try diag.addNote(.{
        .position = .right_of,
        .participant1 = 0,
        .participant2 = 0,
        .text = "A note",
    });

    _ = layout(&diag, .{});

    try testing.expect(diag.notes.items[0].y > 0);
    try testing.expect(diag.notes.items[0].width > 0);
    try testing.expect(diag.notes.items[0].height > 0);
}

test "layout: activations get Y range" {
    var diag = SequenceDiagram.init(testing.allocator);
    defer diag.deinit();

    _ = try diag.ensureParticipant("A");
    _ = try diag.ensureParticipant("B");
    _ = try diag.addMessage(.{ .from = 0, .to = 1, .text = "req" });

    // Manually add an activation spanning events 0..0.
    try diag.activations.append(testing.allocator, .{
        .participant = 1,
        .start_event = 0,
        .end_event = 0,
        .depth = 0,
    });

    _ = layout(&diag, .{});

    try testing.expect(diag.activations.items[0].start_y > 0);
    try testing.expect(diag.activations.items[0].end_y > diag.activations.items[0].start_y);
}

test "layout: fragment box dimensions" {
    var diag = SequenceDiagram.init(testing.allocator);
    defer diag.deinit();

    _ = try diag.ensureParticipant("A");
    _ = try diag.ensureParticipant("B");

    // Simulate a fragment wrapping one message.
    var frag = Fragment{ .kind = .loop_block };
    try frag.sections.append(testing.allocator, .{ .label = "Retry", .start_event = 0, .end_event = 0 });
    frag.start_event = 0;
    frag.end_event = 0;
    frag.left_participant = 0;
    frag.right_participant = 1;
    try diag.fragments.append(testing.allocator, frag);

    _ = try diag.addMessage(.{ .from = 0, .to = 1, .text = "ping" });

    _ = layout(&diag, .{});

    try testing.expect(diag.fragments.items[0].width > 0);
    try testing.expect(diag.fragments.items[0].height > 0);
}

test "layout: title increases header offset" {
    var diag_no_title = SequenceDiagram.init(testing.allocator);
    defer diag_no_title.deinit();
    _ = try diag_no_title.ensureParticipant("A");
    const r1 = layout(&diag_no_title, .{});

    var diag_title = SequenceDiagram.init(testing.allocator);
    defer diag_title.deinit();
    _ = try diag_title.ensureParticipant("A");
    diag_title.title = "My Title";
    const r2 = layout(&diag_title, .{});

    try testing.expect(r2.header_y > r1.header_y);
    try testing.expect(r2.title_y > 0);
}

test "layout: many participants spread width" {
    var diag = SequenceDiagram.init(testing.allocator);
    defer diag.deinit();

    _ = try diag.ensureParticipant("A");
    _ = try diag.ensureParticipant("B");
    _ = try diag.ensureParticipant("C");
    _ = try diag.ensureParticipant("D");

    const result = layout(&diag, .{});

    // The diagram should be wide enough for 4 participants.
    try testing.expect(result.width > 600);
    // Participants should be in strictly increasing X order.
    for (1..diag.participants.items.len) |i| {
        try testing.expect(diag.participants.items[i].center_x > diag.participants.items[i - 1].center_x);
    }
}

test "layout: footer comes after last event" {
    var diag = SequenceDiagram.init(testing.allocator);
    defer diag.deinit();

    _ = try diag.ensureParticipant("A");
    _ = try diag.ensureParticipant("B");
    _ = try diag.addMessage(.{ .from = 0, .to = 1, .text = "m1" });
    _ = try diag.addMessage(.{ .from = 1, .to = 0, .text = "m2" });
    _ = try diag.addMessage(.{ .from = 0, .to = 1, .text = "m3" });

    const result = layout(&diag, .{});

    try testing.expect(result.footer_y > result.last_event_y);
    try testing.expect(result.height > result.footer_y);
}
