//! SVG rendering pipeline for sequence diagrams.
//!
//! Takes a laid-out `SequenceDiagram` (coordinates already computed by
//! `layout.zig`) and emits SVG XML via the shared `SvgWriter`.
//!
//! Rendering order:
//!   1. Title (if present)
//!   2. Fragment boxes (behind everything else)
//!   3. Lifelines (dashed vertical lines)
//!   4. Activation bars (on top of lifelines)
//!   5. Messages (arrows with labels)
//!   6. Notes
//!   7. Participant header & footer boxes (on top of lifelines)

const std = @import("std");
const Allocator = std.mem.Allocator;

const svg_mod = @import("../render/svg.zig");
const SvgWriter = svg_mod.SvgWriter;
const TextAnchor = svg_mod.TextAnchor;

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
const Event = seq_model.Event;
const EventKind = seq_model.EventKind;

const seq_layout = @import("layout.zig");
const LayoutConfig = seq_layout.LayoutConfig;
const LayoutResult = seq_layout.LayoutResult;

// -----------------------------------------------------------------------
// Render configuration
// -----------------------------------------------------------------------

pub const SeqRenderConfig = struct {
    /// Font family for all text elements.
    font_family: []const u8 = "Lato, 'Helvetica Neue', Arial, sans-serif",
    /// Font size for participant labels.
    participant_font_size: f64 = 14.0,
    /// Font size for message labels.
    message_font_size: f64 = 13.0,
    /// Font size for note text.
    note_font_size: f64 = 12.0,
    /// Font size for fragment labels.
    fragment_font_size: f64 = 12.0,
    /// Font size for title.
    title_font_size: f64 = 18.0,
    /// Font size for autonumber badges.
    autonumber_font_size: f64 = 11.0,

    // Colors (RGBA)
    /// Background color of the SVG.
    background_color: [4]u8 = .{ 255, 255, 255, 255 },
    /// Participant box fill.
    participant_fill: [4]u8 = .{ 173, 216, 230, 255 }, // light blue
    /// Participant box stroke.
    participant_stroke: [4]u8 = .{ 70, 130, 180, 255 }, // steel blue
    /// Participant text color.
    participant_text_color: [4]u8 = .{ 30, 30, 30, 255 },
    /// Participant box stroke width.
    participant_stroke_width: f64 = 2.0,
    /// Participant box corner radius.
    participant_corner_radius: f64 = 5.0,

    /// Lifeline color.
    lifeline_color: [4]u8 = .{ 140, 140, 140, 255 },
    /// Lifeline stroke width.
    lifeline_width: f64 = 1.5,
    /// Lifeline dash pattern.
    lifeline_dash: []const u8 = "6,4",

    /// Message arrow line color.
    message_color: [4]u8 = .{ 60, 60, 60, 255 },
    /// Message arrow line width.
    message_width: f64 = 1.5,
    /// Message label text color.
    message_text_color: [4]u8 = .{ 40, 40, 40, 255 },
    /// Arrowhead size.
    arrowhead_size: f64 = 8.0,
    /// Cross marker size.
    cross_size: f64 = 8.0,

    /// Activation bar fill.
    activation_fill: [4]u8 = .{ 173, 216, 230, 180 },
    /// Activation bar stroke.
    activation_stroke: [4]u8 = .{ 70, 130, 180, 255 },
    /// Activation bar stroke width.
    activation_stroke_width: f64 = 1.5,

    /// Note box fill.
    note_fill: [4]u8 = .{ 255, 255, 210, 255 }, // light yellow
    /// Note box stroke.
    note_stroke: [4]u8 = .{ 200, 180, 80, 255 },
    /// Note text color.
    note_text_color: [4]u8 = .{ 50, 50, 50, 255 },
    /// Note stroke width.
    note_stroke_width: f64 = 1.0,

    /// Fragment box stroke.
    fragment_stroke: [4]u8 = .{ 100, 100, 100, 255 },
    /// Fragment box fill (semi-transparent).
    fragment_fill: [4]u8 = .{ 240, 240, 245, 60 },
    /// Fragment label background.
    fragment_label_bg: [4]u8 = .{ 220, 220, 230, 255 },
    /// Fragment text color.
    fragment_text_color: [4]u8 = .{ 60, 60, 60, 255 },
    /// Fragment stroke width.
    fragment_stroke_width: f64 = 1.5,
    /// Fragment separator dash pattern.
    fragment_separator_dash: []const u8 = "6,4",

    /// Title text color.
    title_color: [4]u8 = .{ 30, 30, 30, 255 },

    /// Autonumber badge fill.
    autonumber_fill: [4]u8 = .{ 80, 80, 80, 255 },
    /// Autonumber badge text color.
    autonumber_text_color: [4]u8 = .{ 255, 255, 255, 255 },

    /// Actor stick-figure color.
    actor_color: [4]u8 = .{ 70, 130, 180, 255 },
    /// Actor stroke width.
    actor_stroke_width: f64 = 2.0,
};

// -----------------------------------------------------------------------
// Public API
// -----------------------------------------------------------------------

/// Render a laid-out sequence diagram to an SVG file.
pub fn renderToSVGFile(
    allocator: Allocator,
    diag: *const SequenceDiagram,
    layout_result: LayoutResult,
    filename: []const u8,
    layout_config: LayoutConfig,
    render_config: SeqRenderConfig,
) !void {
    const svg_data = try renderToSVGString(allocator, diag, layout_result, layout_config, render_config);
    defer allocator.free(svg_data);

    const file = try std.fs.cwd().createFile(filename, .{});
    defer file.close();
    try file.writeAll(svg_data);
}

/// Render a laid-out sequence diagram to an SVG string.
/// Caller owns the returned slice and must free it with `allocator`.
pub fn renderToSVGString(
    allocator: Allocator,
    diag: *const SequenceDiagram,
    layout_result: LayoutResult,
    layout_config: LayoutConfig,
    render_config: SeqRenderConfig,
) ![]u8 {
    var svg = try SvgWriter.init(allocator, layout_result.width, layout_result.height);
    defer svg.deinit();

    // 1. Title
    if (diag.title) |title_text| {
        try drawTitle(&svg, title_text, layout_result, render_config);
    }

    // 2. Fragment boxes (behind everything)
    try drawFragments(allocator, &svg, diag, layout_config, render_config);

    // 3. Lifelines
    try drawLifelines(&svg, diag, layout_result, layout_config, render_config);

    // 4. Activation bars
    try drawActivations(&svg, diag, layout_config, render_config);

    // 5. Messages
    try drawMessages(allocator, &svg, diag, layout_config, render_config);

    // 6. Notes
    try drawNotes(&svg, diag, render_config);

    // 7. Participant boxes (header + footer)
    try drawParticipantBoxes(allocator, &svg, diag, layout_result, layout_config, render_config);

    return svg.finalize();
}

// -----------------------------------------------------------------------
// Title
// -----------------------------------------------------------------------

fn drawTitle(
    svg: *SvgWriter,
    title_text: []const u8,
    layout_result: LayoutResult,
    config: SeqRenderConfig,
) !void {
    try svg.openGroup("title");
    try svg.textCentered(
        layout_result.width / 2.0,
        layout_result.title_y,
        title_text,
        config.title_font_size,
        config.title_color,
        config.font_family,
    );
    try svg.closeGroup();
}

// -----------------------------------------------------------------------
// Fragment boxes
// -----------------------------------------------------------------------

fn drawFragments(
    allocator: Allocator,
    svg: *SvgWriter,
    diag: *const SequenceDiagram,
    layout_config: LayoutConfig,
    config: SeqRenderConfig,
) !void {
    if (diag.fragments.items.len == 0) return;

    try svg.openGroup("fragments");

    for (diag.fragments.items) |frag| {
        // Main fragment box.
        try svg.rect(
            frag.x,
            frag.y,
            frag.width,
            frag.height,
            3.0,
            3.0,
            config.fragment_fill,
            config.fragment_stroke,
            config.fragment_stroke_width,
        );

        // Fragment type label in top-left corner.
        const kind_label = fragmentKindLabel(frag.kind);
        const label_w: f64 = @as(f64, @floatFromInt(kind_label.len)) * 7.5 + 16.0;
        const label_h: f64 = layout_config.fragment_label_height;

        // Label background pentagon (with cut corner).
        const pts = [_][2]f64{
            .{ frag.x, frag.y },
            .{ frag.x + label_w, frag.y },
            .{ frag.x + label_w, frag.y + label_h - 6.0 },
            .{ frag.x + label_w - 6.0, frag.y + label_h },
            .{ frag.x, frag.y + label_h },
        };
        try svg.polygon(&pts, config.fragment_label_bg, config.fragment_stroke, config.fragment_stroke_width);

        // Label text.
        try svg.textAt(
            frag.x + 8.0,
            frag.y + label_h / 2.0,
            kind_label,
            config.fragment_font_size,
            config.fragment_text_color,
            config.font_family,
            .start,
        );

        // Section label (condition text) to the right of the kind label.
        if (frag.sections.items.len > 0) {
            if (frag.sections.items[0].label) |sec_label| {
                const cond_text = try formatFragmentCondition(allocator, sec_label);
                defer if (cond_text.ptr != sec_label.ptr) allocator.free(cond_text);

                try svg.textAt(
                    frag.x + label_w + 10.0,
                    frag.y + label_h / 2.0,
                    cond_text,
                    config.fragment_font_size,
                    config.fragment_text_color,
                    config.font_family,
                    .start,
                );
            }
        }

        // Draw separators between sections (else/and lines).
        if (frag.sections.items.len > 1) {
            for (frag.sections.items[1..]) |sec| {
                const sep_y = sec.start_y - layout_config.row_height / 2.0;
                try svg.line(
                    frag.x,
                    sep_y,
                    frag.x + frag.width,
                    sep_y,
                    config.fragment_stroke,
                    config.fragment_stroke_width,
                    config.fragment_separator_dash,
                );

                // Section label.
                if (sec.label) |sec_label| {
                    const cond_text = try formatFragmentCondition(allocator, sec_label);
                    defer if (cond_text.ptr != sec_label.ptr) allocator.free(cond_text);

                    try svg.textAt(
                        frag.x + 12.0,
                        sep_y + 16.0,
                        cond_text,
                        config.fragment_font_size,
                        config.fragment_text_color,
                        config.font_family,
                        .start,
                    );
                }
            }
        }
    }

    try svg.closeGroup();
}

fn fragmentKindLabel(kind: FragmentKind) []const u8 {
    return switch (kind) {
        .loop_block => "loop",
        .alt_block => "alt",
        .opt_block => "opt",
        .par_block => "par",
        .critical_block => "critical",
        .break_block => "break",
        .rect_block => "rect",
    };
}

/// Format a fragment condition label, wrapping in brackets if present.
/// Returns the original slice if no formatting is needed.
fn formatFragmentCondition(allocator: Allocator, label: []const u8) ![]const u8 {
    if (label.len == 0) return label;
    return try std.fmt.allocPrint(allocator, "[{s}]", .{label});
}

// -----------------------------------------------------------------------
// Lifelines
// -----------------------------------------------------------------------

fn drawLifelines(
    svg: *SvgWriter,
    diag: *const SequenceDiagram,
    layout_result: LayoutResult,
    layout_config: LayoutConfig,
    config: SeqRenderConfig,
) !void {
    try svg.openGroup("lifelines");

    const lifeline_top = layout_result.header_y + layout_config.participant_box_height;
    const lifeline_bottom = layout_result.footer_y;

    for (diag.participants.items) |p| {
        try svg.line(
            p.center_x,
            lifeline_top,
            p.center_x,
            lifeline_bottom,
            config.lifeline_color,
            config.lifeline_width,
            config.lifeline_dash,
        );
    }

    try svg.closeGroup();
}

// -----------------------------------------------------------------------
// Activation bars
// -----------------------------------------------------------------------

fn drawActivations(
    svg: *SvgWriter,
    diag: *const SequenceDiagram,
    layout_config: LayoutConfig,
    config: SeqRenderConfig,
) !void {
    if (diag.activations.items.len == 0) return;

    try svg.openGroup("activations");

    for (diag.activations.items) |act| {
        if (act.participant >= diag.participants.items.len) continue;

        const p = diag.participants.items[act.participant];
        const bar_w = layout_config.activation_bar_width;
        const nest_offset = @as(f64, @floatFromInt(act.depth)) * layout_config.activation_nest_offset;
        const bar_x = p.center_x - bar_w / 2.0 + nest_offset;
        const bar_h = act.end_y - act.start_y;

        if (bar_h > 0) {
            try svg.rect(
                bar_x,
                act.start_y,
                bar_w,
                bar_h,
                0,
                0,
                config.activation_fill,
                config.activation_stroke,
                config.activation_stroke_width,
            );
        }
    }

    try svg.closeGroup();
}

// -----------------------------------------------------------------------
// Messages
// -----------------------------------------------------------------------

fn drawMessages(
    allocator: Allocator,
    svg: *SvgWriter,
    diag: *const SequenceDiagram,
    layout_config: LayoutConfig,
    config: SeqRenderConfig,
) !void {
    if (diag.messages.items.len == 0) return;

    try svg.openGroup("messages");

    var msg_number: usize = 0;
    for (diag.messages.items) |msg| {
        msg_number += 1;

        if (msg.from >= diag.participants.items.len or
            msg.to >= diag.participants.items.len) continue;

        const from_x = diag.participants.items[msg.from].center_x;
        const to_x = diag.participants.items[msg.to].center_x;
        const y = msg.y;

        if (msg.isSelfMessage()) {
            try drawSelfMessage(svg, from_x, y, layout_config, config, msg);
        } else {
            // Determine dash pattern.
            const dash: ?[]const u8 = if (msg.arrow_type.isDashed()) "6,4" else null;

            // Draw the line.
            try svg.line(from_x, y, to_x, y, config.message_color, config.message_width, dash);

            // Draw arrowhead or cross at the destination end.
            if (msg.arrow_type.hasArrowhead()) {
                if (msg.arrow_type.isOpenArrow()) {
                    try drawOpenArrowhead(svg, from_x, to_x, y, config);
                } else {
                    // Filled arrowhead.
                    try svg.arrowhead(from_x, y, to_x, y, config.arrowhead_size, config.message_color);
                }
            } else if (msg.arrow_type.isCross()) {
                try drawCross(svg, to_x, y, config);
            }
        }

        // Message label text.
        if (msg.text) |text| {
            const label_text = if (diag.autonumber) blk: {
                break :blk try std.fmt.allocPrint(allocator, "{d}. {s}", .{ msg_number, text });
            } else text;
            defer if (diag.autonumber) allocator.free(label_text);

            if (msg.isSelfMessage()) {
                // Position label to the right of the self-message loop.
                try svg.textAt(
                    from_x + layout_config.self_message_width + 8.0,
                    y + layout_config.self_message_height / 2.0,
                    label_text,
                    config.message_font_size,
                    config.message_text_color,
                    config.font_family,
                    .start,
                );
            } else {
                // Centre label above the arrow.
                const mid_x = (from_x + to_x) / 2.0;
                try svg.textCentered(
                    mid_x,
                    y - 8.0,
                    label_text,
                    config.message_font_size,
                    config.message_text_color,
                    config.font_family,
                );
            }
        } else if (diag.autonumber) {
            // Autonumber badge even without text.
            const num_text = try std.fmt.allocPrint(allocator, "{d}", .{msg_number});
            defer allocator.free(num_text);

            const mid_x = if (msg.isSelfMessage())
                from_x + layout_config.self_message_width + 8.0
            else
                (from_x + to_x) / 2.0;
            const label_y = if (msg.isSelfMessage())
                y + layout_config.self_message_height / 2.0
            else
                y - 8.0;

            try svg.textCentered(
                mid_x,
                label_y,
                num_text,
                config.message_font_size,
                config.message_text_color,
                config.font_family,
            );
        }
    }

    try svg.closeGroup();
}

/// Draw a self-message loop (arrow from a participant back to itself).
fn drawSelfMessage(
    svg: *SvgWriter,
    x: f64,
    y: f64,
    layout_config: LayoutConfig,
    config: SeqRenderConfig,
    msg: Message,
) !void {
    const w = layout_config.self_message_width;
    const h = layout_config.self_message_height;
    const dash: ?[]const u8 = if (msg.arrow_type.isDashed()) "6,4" else null;

    // Draw as three line segments: right, down, left.
    const points = [_][2]f64{
        .{ x, y },
        .{ x + w, y },
        .{ x + w, y + h },
        .{ x, y + h },
    };
    try svg.polyline(&points, config.message_color, config.message_width, dash);

    // Arrowhead at the return point.
    if (msg.arrow_type.hasArrowhead()) {
        if (msg.arrow_type.isOpenArrow()) {
            try drawOpenArrowhead(svg, x + w, x, y + h, config);
        } else {
            try svg.arrowhead(x + w, y + h, x, y + h, config.arrowhead_size, config.message_color);
        }
    } else if (msg.arrow_type.isCross()) {
        try drawCross(svg, x, y + h, config);
    }
}

/// Draw an open (unfilled) arrowhead — two lines forming a "V".
fn drawOpenArrowhead(
    svg: *SvgWriter,
    from_x: f64,
    to_x: f64,
    y: f64,
    config: SeqRenderConfig,
) !void {
    const size = config.arrowhead_size;
    const dir: f64 = if (to_x > from_x) -1.0 else 1.0;

    const tip_x = to_x;
    const p1 = [2]f64{ tip_x + dir * size, y - size * 0.5 };
    const p2 = [2]f64{ tip_x, y };
    const p3 = [2]f64{ tip_x + dir * size, y + size * 0.5 };

    const points = [_][2]f64{ p1, p2, p3 };
    try svg.polyline(&points, config.message_color, config.message_width, null);
}

/// Draw a cross (X) at the end of a message.
fn drawCross(
    svg: *SvgWriter,
    x: f64,
    y: f64,
    config: SeqRenderConfig,
) !void {
    const s = config.cross_size / 2.0;
    try svg.line(x - s, y - s, x + s, y + s, config.message_color, config.message_width + 0.5, null);
    try svg.line(x - s, y + s, x + s, y - s, config.message_color, config.message_width + 0.5, null);
}

// -----------------------------------------------------------------------
// Notes
// -----------------------------------------------------------------------

fn drawNotes(
    svg: *SvgWriter,
    diag: *const SequenceDiagram,
    config: SeqRenderConfig,
) !void {
    if (diag.notes.items.len == 0) return;

    try svg.openGroup("notes");

    for (diag.notes.items) |note| {
        if (note.participant1 >= diag.participants.items.len) continue;

        const p1 = diag.participants.items[note.participant1];
        var note_x: f64 = undefined;
        const note_w = note.width;
        const note_h = note.height;
        const note_y = note.y - note_h / 2.0;

        switch (note.position) {
            .right_of => {
                note_x = p1.center_x + p1.box_width / 2.0 + 8.0;
            },
            .left_of => {
                note_x = p1.center_x - p1.box_width / 2.0 - note_w - 8.0;
            },
            .over => {
                if (note.participant2 < diag.participants.items.len and note.participant2 != note.participant1) {
                    const p2 = diag.participants.items[note.participant2];
                    const mid_x = (p1.center_x + p2.center_x) / 2.0;
                    note_x = mid_x - note_w / 2.0;
                } else {
                    note_x = p1.center_x - note_w / 2.0;
                }
            },
        }

        // Draw note box with a folded corner effect.
        const fold: f64 = 8.0;

        // Main rectangle (slightly shorter to leave room for fold).
        try svg.rect(
            note_x,
            note_y,
            note_w,
            note_h,
            0,
            0,
            config.note_fill,
            config.note_stroke,
            config.note_stroke_width,
        );

        // Fold triangle in the top-right corner.
        const fold_pts = [_][2]f64{
            .{ note_x + note_w - fold, note_y },
            .{ note_x + note_w, note_y + fold },
            .{ note_x + note_w - fold, note_y + fold },
        };
        try svg.polygon(&fold_pts, config.note_stroke, config.note_stroke, 0.5);

        // Note text.
        if (note.text) |text| {
            // Strip <br/> tags and show as single line for now.
            const clean = stripBrTags(text);
            try svg.textCentered(
                note_x + note_w / 2.0,
                note_y + note_h / 2.0,
                clean,
                config.note_font_size,
                config.note_text_color,
                config.font_family,
            );
        }
    }

    try svg.closeGroup();
}

/// Strip `<br/>` tags from text, replacing them with spaces.
/// Currently returns the text as-is — a future improvement would
/// split on `<br/>` and use `<tspan>` elements for multi-line notes.
fn stripBrTags(text: []const u8) []const u8 {
    return text;
}

// -----------------------------------------------------------------------
// Participant boxes (header + footer)
// -----------------------------------------------------------------------

fn drawParticipantBoxes(
    allocator: Allocator,
    svg: *SvgWriter,
    diag: *const SequenceDiagram,
    layout_result: LayoutResult,
    layout_config: LayoutConfig,
    config: SeqRenderConfig,
) !void {
    _ = allocator;

    try svg.openGroup("participants");

    for (diag.participants.items) |p| {
        const label = p.displayName();

        // Header box.
        try drawParticipantBox(svg, p, layout_result.header_y, layout_config, config, label);

        // Footer box (mirrored at the bottom).
        try drawParticipantBox(svg, p, layout_result.footer_y, layout_config, config, label);
    }

    try svg.closeGroup();
}

fn drawParticipantBox(
    svg: *SvgWriter,
    p: Participant,
    box_y: f64,
    layout_config: LayoutConfig,
    config: SeqRenderConfig,
    label: []const u8,
) !void {
    _ = layout_config;

    const box_x = p.center_x - p.box_width / 2.0;

    switch (p.kind) {
        .box => {
            try svg.rect(
                box_x,
                box_y,
                p.box_width,
                p.box_height,
                config.participant_corner_radius,
                config.participant_corner_radius,
                config.participant_fill,
                config.participant_stroke,
                config.participant_stroke_width,
            );
            try svg.textCentered(
                p.center_x,
                box_y + p.box_height / 2.0,
                label,
                config.participant_font_size,
                config.participant_text_color,
                config.font_family,
            );
        },
        .actor => {
            // Draw a stick figure.
            try drawActorFigure(svg, p.center_x, box_y, p.box_height, config, label);
        },
    }
}

/// Draw a stick-figure actor at the given position.
fn drawActorFigure(
    svg: *SvgWriter,
    cx: f64,
    top_y: f64,
    total_h: f64,
    config: SeqRenderConfig,
    label: []const u8,
) !void {
    // Proportions within total_h:
    //   head: top 30%, body: middle 40%, legs: bottom 30%
    const head_r: f64 = total_h * 0.15;
    const head_cy = top_y + head_r;
    const body_top = head_cy + head_r;
    const body_bottom = top_y + total_h * 0.7;
    const arm_y = body_top + (body_bottom - body_top) * 0.3;
    const arm_span: f64 = total_h * 0.3;
    const leg_bottom = top_y + total_h * 0.95;
    const leg_span: f64 = total_h * 0.2;

    // Head circle.
    try svg.ellipse(cx, head_cy, head_r, head_r, null, config.actor_color, config.actor_stroke_width);

    // Body line.
    try svg.line(cx, body_top, cx, body_bottom, config.actor_color, config.actor_stroke_width, null);

    // Arms.
    try svg.line(cx - arm_span, arm_y, cx + arm_span, arm_y, config.actor_color, config.actor_stroke_width, null);

    // Left leg.
    try svg.line(cx, body_bottom, cx - leg_span, leg_bottom, config.actor_color, config.actor_stroke_width, null);

    // Right leg.
    try svg.line(cx, body_bottom, cx + leg_span, leg_bottom, config.actor_color, config.actor_stroke_width, null);

    // Label below.
    try svg.textCentered(
        cx,
        top_y + total_h + 12.0,
        label,
        config.participant_font_size,
        config.participant_text_color,
        config.font_family,
    );
}

// =======================================================================
// Tests
// =======================================================================

const testing = std.testing;

test "svg_seq_render: empty diagram produces valid SVG" {
    var diag = SequenceDiagram.init(testing.allocator);
    defer diag.deinit();

    const lr = seq_layout.layout(&diag, .{});

    const svg_data = try renderToSVGString(testing.allocator, &diag, lr, .{}, .{});
    defer testing.allocator.free(svg_data);

    try testing.expect(std.mem.indexOf(u8, svg_data, "<svg") != null);
    try testing.expect(std.mem.indexOf(u8, svg_data, "</svg>") != null);
}

test "svg_seq_render: two participants with message" {
    var diag = SequenceDiagram.init(testing.allocator);
    defer diag.deinit();

    _ = try diag.ensureParticipant("Alice");
    _ = try diag.ensureParticipant("Bob");
    _ = try diag.addMessage(.{ .from = 0, .to = 1, .text = "Hello", .arrow_type = .solid_arrow });

    const lr = seq_layout.layout(&diag, .{});

    const svg_data = try renderToSVGString(testing.allocator, &diag, lr, .{}, .{});
    defer testing.allocator.free(svg_data);

    try testing.expect(std.mem.indexOf(u8, svg_data, "Alice") != null);
    try testing.expect(std.mem.indexOf(u8, svg_data, "Bob") != null);
    try testing.expect(std.mem.indexOf(u8, svg_data, "Hello") != null);
    // Should have lifelines group.
    try testing.expect(std.mem.indexOf(u8, svg_data, "class=\"lifelines\"") != null);
    // Should have messages group.
    try testing.expect(std.mem.indexOf(u8, svg_data, "class=\"messages\"") != null);
    // Should have participants group.
    try testing.expect(std.mem.indexOf(u8, svg_data, "class=\"participants\"") != null);
}

test "svg_seq_render: self-message" {
    var diag = SequenceDiagram.init(testing.allocator);
    defer diag.deinit();

    _ = try diag.ensureParticipant("A");
    _ = try diag.addMessage(.{ .from = 0, .to = 0, .text = "Think", .arrow_type = .solid_arrow });

    const lr = seq_layout.layout(&diag, .{});

    const svg_data = try renderToSVGString(testing.allocator, &diag, lr, .{}, .{});
    defer testing.allocator.free(svg_data);

    try testing.expect(std.mem.indexOf(u8, svg_data, "Think") != null);
    // Self-message uses polyline.
    try testing.expect(std.mem.indexOf(u8, svg_data, "<polyline") != null);
}

test "svg_seq_render: note renders" {
    var diag = SequenceDiagram.init(testing.allocator);
    defer diag.deinit();

    _ = try diag.ensureParticipant("X");
    _ = try diag.addNote(.{ .position = .right_of, .participant1 = 0, .participant2 = 0, .text = "A note" });

    const lr = seq_layout.layout(&diag, .{});

    const svg_data = try renderToSVGString(testing.allocator, &diag, lr, .{}, .{});
    defer testing.allocator.free(svg_data);

    try testing.expect(std.mem.indexOf(u8, svg_data, "class=\"notes\"") != null);
    try testing.expect(std.mem.indexOf(u8, svg_data, "A note") != null);
}

test "svg_seq_render: activation bar renders" {
    var diag = SequenceDiagram.init(testing.allocator);
    defer diag.deinit();

    _ = try diag.ensureParticipant("A");
    _ = try diag.ensureParticipant("B");
    _ = try diag.addMessage(.{ .from = 0, .to = 1, .text = "req" });

    try diag.activations.append(testing.allocator, .{
        .participant = 1,
        .start_event = 0,
        .end_event = 0,
        .depth = 0,
    });

    const lr = seq_layout.layout(&diag, .{});

    const svg_data = try renderToSVGString(testing.allocator, &diag, lr, .{}, .{});
    defer testing.allocator.free(svg_data);

    try testing.expect(std.mem.indexOf(u8, svg_data, "class=\"activations\"") != null);
}

test "svg_seq_render: title renders" {
    var diag = SequenceDiagram.init(testing.allocator);
    defer diag.deinit();

    _ = try diag.ensureParticipant("A");
    diag.title = "My Diagram";

    const lr = seq_layout.layout(&diag, .{});

    const svg_data = try renderToSVGString(testing.allocator, &diag, lr, .{}, .{});
    defer testing.allocator.free(svg_data);

    try testing.expect(std.mem.indexOf(u8, svg_data, "class=\"title\"") != null);
    try testing.expect(std.mem.indexOf(u8, svg_data, "My Diagram") != null);
}

test "svg_seq_render: dashed arrow" {
    var diag = SequenceDiagram.init(testing.allocator);
    defer diag.deinit();

    _ = try diag.ensureParticipant("A");
    _ = try diag.ensureParticipant("B");
    _ = try diag.addMessage(.{ .from = 0, .to = 1, .text = "reply", .arrow_type = .dotted_arrow });

    const lr = seq_layout.layout(&diag, .{});

    const svg_data = try renderToSVGString(testing.allocator, &diag, lr, .{}, .{});
    defer testing.allocator.free(svg_data);

    // Dashed line should have stroke-dasharray.
    try testing.expect(std.mem.indexOf(u8, svg_data, "stroke-dasharray") != null);
}

test "svg_seq_render: fragment box" {
    var diag = SequenceDiagram.init(testing.allocator);
    defer diag.deinit();

    _ = try diag.ensureParticipant("A");
    _ = try diag.ensureParticipant("B");

    var frag = Fragment{ .kind = .loop_block };
    try frag.sections.append(testing.allocator, .{ .label = "Retry 3x", .start_event = 0, .end_event = 0 });
    frag.start_event = 0;
    frag.end_event = 0;
    frag.left_participant = 0;
    frag.right_participant = 1;
    try diag.fragments.append(testing.allocator, frag);

    _ = try diag.addMessage(.{ .from = 0, .to = 1, .text = "ping" });

    const lr = seq_layout.layout(&diag, .{});

    const svg_data = try renderToSVGString(testing.allocator, &diag, lr, .{}, .{});
    defer testing.allocator.free(svg_data);

    try testing.expect(std.mem.indexOf(u8, svg_data, "class=\"fragments\"") != null);
    try testing.expect(std.mem.indexOf(u8, svg_data, "loop") != null);
    try testing.expect(std.mem.indexOf(u8, svg_data, "Retry 3x") != null);
}

test "svg_seq_render: actor stick figure" {
    var diag = SequenceDiagram.init(testing.allocator);
    defer diag.deinit();

    try diag.participants.append(testing.allocator, .{
        .id = "User",
        .kind = .actor,
    });
    _ = try diag.ensureParticipant("Server");
    _ = try diag.addMessage(.{ .from = 0, .to = 1, .text = "Request" });

    const lr = seq_layout.layout(&diag, .{});

    const svg_data = try renderToSVGString(testing.allocator, &diag, lr, .{}, .{});
    defer testing.allocator.free(svg_data);

    // Actor draws a circle (ellipse) for the head.
    try testing.expect(std.mem.indexOf(u8, svg_data, "<ellipse") != null);
    try testing.expect(std.mem.indexOf(u8, svg_data, "User") != null);
}
