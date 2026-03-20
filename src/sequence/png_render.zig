//! PNG rendering pipeline for sequence diagrams.
//!
//! Takes a laid-out `SequenceDiagram` (coordinates already computed by
//! `layout.zig`) and renders to a PNG file via the shared `Canvas`.
//!
//! Rendering order (same as SVG pipeline):
//!   1. Title (if present)
//!   2. Fragment boxes (behind everything else)
//!   3. Lifelines (dashed vertical lines)
//!   4. Activation bars (on top of lifelines)
//!   5. Messages (arrows with labels)
//!   6. Notes
//!   7. Participant header & footer boxes (on top of lifelines)

const std = @import("std");
const Allocator = std.mem.Allocator;

const canvas_mod = @import("../render/canvas.zig");
const Canvas = canvas_mod.Canvas;

const text_mod = @import("../render/text.zig");
const Font = text_mod.Font;

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
// Render configuration (mirrors SVG SeqRenderConfig but for PNG)
// -----------------------------------------------------------------------

pub const SeqPngRenderConfig = struct {
    /// Scale factor for HD rendering (2.0 = retina).
    scale_factor: f64 = 4.0,

    /// Font size for participant labels.
    participant_font_size: f32 = 14.0,
    /// Font size for message labels.
    message_font_size: f32 = 13.0,
    /// Font size for note text.
    note_font_size: f32 = 12.0,
    /// Font size for fragment labels.
    fragment_font_size: f32 = 12.0,
    /// Font size for title.
    title_font_size: f32 = 18.0,

    // Colors (RGBA)
    background_color: [4]u8 = .{ 255, 255, 255, 255 },

    participant_fill: [4]u8 = .{ 173, 216, 230, 255 },
    participant_stroke: [4]u8 = .{ 70, 130, 180, 255 },
    participant_text_color: [4]u8 = .{ 30, 30, 30, 255 },
    participant_stroke_width: i32 = 2,
    participant_corner_radius: f64 = 5.0,

    lifeline_color: [4]u8 = .{ 140, 140, 140, 255 },
    lifeline_width: i32 = 1,
    lifeline_dash_len: f64 = 6.0,
    lifeline_gap_len: f64 = 4.0,

    message_color: [4]u8 = .{ 60, 60, 60, 255 },
    message_width: i32 = 2,
    message_text_color: [4]u8 = .{ 40, 40, 40, 255 },
    arrowhead_size: f64 = 8.0,
    cross_size: f64 = 8.0,

    activation_fill: [4]u8 = .{ 173, 216, 230, 180 },
    activation_stroke: [4]u8 = .{ 70, 130, 180, 255 },
    activation_stroke_width: i32 = 1,

    note_fill: [4]u8 = .{ 255, 255, 210, 255 },
    note_stroke: [4]u8 = .{ 200, 180, 80, 255 },
    note_text_color: [4]u8 = .{ 50, 50, 50, 255 },
    note_stroke_width: i32 = 1,

    fragment_stroke: [4]u8 = .{ 100, 100, 100, 255 },
    fragment_fill: [4]u8 = .{ 240, 240, 245, 60 },
    fragment_label_bg: [4]u8 = .{ 220, 220, 230, 255 },
    fragment_text_color: [4]u8 = .{ 60, 60, 60, 255 },
    fragment_stroke_width: i32 = 1,
    fragment_separator_dash_len: f64 = 6.0,
    fragment_separator_gap_len: f64 = 4.0,

    title_color: [4]u8 = .{ 30, 30, 30, 255 },

    actor_color: [4]u8 = .{ 70, 130, 180, 255 },
    actor_stroke_width: i32 = 2,
};

// -----------------------------------------------------------------------
// Public API
// -----------------------------------------------------------------------

/// Render a laid-out sequence diagram to a PNG file.
pub fn renderToPNGFile(
    allocator: Allocator,
    diag: *const SequenceDiagram,
    layout_result: LayoutResult,
    filename: []const u8,
    layout_config: LayoutConfig,
    render_config: SeqPngRenderConfig,
    font: ?*Font,
) !void {
    const canvas_w = @as(usize, @intFromFloat(@ceil(layout_result.width)));
    const canvas_h = @as(usize, @intFromFloat(@ceil(layout_result.height)));

    if (canvas_w == 0 or canvas_h == 0) return error.InvalidDimensions;

    var canvas = try Canvas.initWithScale(allocator, canvas_w, canvas_h, render_config.scale_factor);
    defer canvas.deinit();

    // Fill background
    const bg = render_config.background_color;
    canvas.fill(bg[0], bg[1], bg[2], bg[3]);

    // 1. Title
    if (diag.title) |title_text| {
        drawTitle(&canvas, title_text, layout_result, render_config, font);
    }

    // 2. Fragment boxes (behind everything)
    try drawFragments(allocator, &canvas, diag, layout_config, render_config, font);

    // 3. Lifelines
    drawLifelines(&canvas, diag, layout_result, layout_config, render_config);

    // 4. Activation bars
    drawActivations(&canvas, diag, layout_config, render_config);

    // 5. Messages
    try drawMessages(allocator, &canvas, diag, layout_config, render_config, font);

    // 6. Notes
    try drawNotes(allocator, &canvas, diag, layout_config, render_config, font);

    // 7. Participant boxes (header + footer)
    drawParticipantBoxes(&canvas, diag, layout_result, layout_config, render_config, font);

    // Save to file
    try canvas.saveToPNG(filename);
}

pub fn renderToPNGBytes(
    allocator: Allocator,
    diag: *const SequenceDiagram,
    layout_result: LayoutResult,
    layout_config: LayoutConfig,
    render_config: SeqPngRenderConfig,
    font: ?*Font,
) ![]u8 {
    const canvas_w = @as(usize, @intFromFloat(@ceil(layout_result.width)));
    const canvas_h = @as(usize, @intFromFloat(@ceil(layout_result.height)));

    if (canvas_w == 0 or canvas_h == 0) return error.InvalidDimensions;

    var canvas = try Canvas.initWithScale(allocator, canvas_w, canvas_h, render_config.scale_factor);
    defer canvas.deinit();

    const bg = render_config.background_color;
    canvas.fill(bg[0], bg[1], bg[2], bg[3]);

    if (diag.title) |title_text| {
        drawTitle(&canvas, title_text, layout_result, render_config, font);
    }

    try drawFragments(allocator, &canvas, diag, layout_config, render_config, font);
    drawLifelines(&canvas, diag, layout_result, layout_config, render_config);
    drawActivations(&canvas, diag, layout_config, render_config);
    try drawMessages(allocator, &canvas, diag, layout_config, render_config, font);
    try drawNotes(allocator, &canvas, diag, layout_config, render_config, font);
    drawParticipantBoxes(&canvas, diag, layout_result, layout_config, render_config, font);

    return canvas.saveToPNGBytes();
}

// -----------------------------------------------------------------------
// Title
// -----------------------------------------------------------------------

fn drawTitle(
    canvas: *Canvas,
    title_text: []const u8,
    layout_result: LayoutResult,
    config: SeqPngRenderConfig,
    font: ?*Font,
) void {
    if (font) |f| {
        const cx: f32 = @floatCast(layout_result.width / 2.0);
        const cy: f32 = @floatCast(layout_result.title_y);
        const tc = config.title_color;
        const tw = f.measureText(title_text, config.title_font_size);
        f.drawText(canvas, title_text, cx - tw / 2.0, cy, config.title_font_size, tc[0], tc[1], tc[2], tc[3]) catch {};
    }
}

// -----------------------------------------------------------------------
// Fragment boxes
// -----------------------------------------------------------------------

fn drawFragments(
    allocator: Allocator,
    canvas: *Canvas,
    diag: *const SequenceDiagram,
    layout_config: LayoutConfig,
    config: SeqPngRenderConfig,
    font: ?*Font,
) !void {
    if (diag.fragments.items.len == 0) return;

    for (diag.fragments.items) |frag| {
        // Main fragment box
        const ff = if (frag.kind == .rect_block and frag.bg_color != null)
            frag.bg_color.?
        else
            config.fragment_fill;
        const fs = config.fragment_stroke;
        canvas.fillRect(frag.x, frag.y, frag.width, frag.height, ff[0], ff[1], ff[2], ff[3]);
        canvas.strokeRect(frag.x, frag.y, frag.width, frag.height, config.fragment_stroke_width, fs[0], fs[1], fs[2], fs[3]);

        // Fragment kind label
        const kind_label = fragmentKindLabel(frag.kind);
        const label_w: f64 = @as(f64, @floatFromInt(kind_label.len)) * 7.5 + 16.0;
        const label_h: f64 = layout_config.fragment_label_height;

        // Label background (simplified to rectangle for PNG)
        const lb = config.fragment_label_bg;
        canvas.fillRect(frag.x, frag.y, label_w, label_h, lb[0], lb[1], lb[2], lb[3]);
        canvas.strokeRect(frag.x, frag.y, label_w, label_h, 1, fs[0], fs[1], fs[2], fs[3]);

        // Draw the cut-corner line for the pentagon effect
        const cut = 6.0;
        canvas.drawLine(
            frag.x + label_w,
            frag.y + label_h - cut,
            frag.x + label_w - cut,
            frag.y + label_h,
            1,
            fs[0],
            fs[1],
            fs[2],
            fs[3],
        );

        // Label text
        if (font) |f| {
            const ft = config.fragment_text_color;
            f.drawText(
                canvas,
                kind_label,
                @floatCast(frag.x + 8.0),
                @floatCast(frag.y + label_h / 2.0),
                config.fragment_font_size,
                ft[0],
                ft[1],
                ft[2],
                ft[3],
            ) catch {};
        }

        // Section label (condition text)
        if (frag.sections.items.len > 0) {
            if (frag.sections.items[0].label) |sec_label| {
                if (font) |f| {
                    const cond_text = try std.fmt.allocPrint(allocator, "[{s}]", .{sec_label});
                    defer allocator.free(cond_text);

                    const ft = config.fragment_text_color;
                    f.drawText(
                        canvas,
                        cond_text,
                        @floatCast(frag.x + label_w + 10.0),
                        @floatCast(frag.y + label_h / 2.0),
                        config.fragment_font_size,
                        ft[0],
                        ft[1],
                        ft[2],
                        ft[3],
                    ) catch {};
                }
            }
        }

        // Draw separators between sections (else/and lines)
        if (frag.sections.items.len > 1) {
            for (frag.sections.items[1..]) |sec| {
                const sep_y = sec.start_y - layout_config.row_height / 2.0;
                canvas.drawDashedLine(
                    frag.x,
                    sep_y,
                    frag.x + frag.width,
                    sep_y,
                    config.fragment_stroke_width,
                    config.fragment_stroke[0],
                    config.fragment_stroke[1],
                    config.fragment_stroke[2],
                    config.fragment_stroke[3],
                    config.fragment_separator_dash_len,
                    config.fragment_separator_gap_len,
                );

                // Section label
                if (sec.label) |sec_label| {
                    if (font) |f| {
                        const cond_text = try std.fmt.allocPrint(allocator, "[{s}]", .{sec_label});
                        defer allocator.free(cond_text);

                        const ft = config.fragment_text_color;
                        f.drawText(
                            canvas,
                            cond_text,
                            @floatCast(frag.x + 12.0),
                            @floatCast(sep_y + 16.0),
                            config.fragment_font_size,
                            ft[0],
                            ft[1],
                            ft[2],
                            ft[3],
                        ) catch {};
                    }
                }
            }
        }
    }
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

// -----------------------------------------------------------------------
// Lifelines
// -----------------------------------------------------------------------

fn drawLifelines(
    canvas: *Canvas,
    diag: *const SequenceDiagram,
    layout_result: LayoutResult,
    layout_config: LayoutConfig,
    config: SeqPngRenderConfig,
) void {
    const lifeline_top = layout_result.header_y + layout_config.participant_box_height;
    const lifeline_bottom = layout_result.footer_y;
    const lc = config.lifeline_color;

    for (diag.participants.items) |p| {
        canvas.drawDashedLine(
            p.center_x,
            lifeline_top,
            p.center_x,
            lifeline_bottom,
            config.lifeline_width,
            lc[0],
            lc[1],
            lc[2],
            lc[3],
            config.lifeline_dash_len,
            config.lifeline_gap_len,
        );
    }
}

// -----------------------------------------------------------------------
// Activation bars
// -----------------------------------------------------------------------

fn drawActivations(
    canvas: *Canvas,
    diag: *const SequenceDiagram,
    layout_config: LayoutConfig,
    config: SeqPngRenderConfig,
) void {
    if (diag.activations.items.len == 0) return;

    for (diag.activations.items) |act| {
        if (act.participant >= diag.participants.items.len) continue;

        const p = diag.participants.items[act.participant];
        const bar_w = layout_config.activation_bar_width;
        const nest_offset = @as(f64, @floatFromInt(act.depth)) * layout_config.activation_nest_offset;
        const bar_x = p.center_x - bar_w / 2.0 + nest_offset;
        const bar_h = act.end_y - act.start_y;

        if (bar_h > 0) {
            const af = config.activation_fill;
            const as_ = config.activation_stroke;
            canvas.fillRect(bar_x, act.start_y, bar_w, bar_h, af[0], af[1], af[2], af[3]);
            canvas.strokeRect(bar_x, act.start_y, bar_w, bar_h, config.activation_stroke_width, as_[0], as_[1], as_[2], as_[3]);
        }
    }
}

// -----------------------------------------------------------------------
// Messages
// -----------------------------------------------------------------------

fn drawMessages(
    allocator: Allocator,
    canvas: *Canvas,
    diag: *const SequenceDiagram,
    layout_config: LayoutConfig,
    config: SeqPngRenderConfig,
    font: ?*Font,
) !void {
    if (diag.messages.items.len == 0) return;

    const mc = config.message_color;
    var msg_number: usize = 0;

    for (diag.messages.items) |msg| {
        msg_number += 1;

        if (msg.from >= diag.participants.items.len or
            msg.to >= diag.participants.items.len) continue;

        const from_x = diag.participants.items[msg.from].center_x;
        const to_x = diag.participants.items[msg.to].center_x;
        const y = msg.y;

        if (msg.isSelfMessage()) {
            drawSelfMessage(canvas, from_x, y, layout_config, config, msg);
        } else {
            // Determine if dashed
            const is_dashed = msg.arrow_type.isDashed();

            // Draw the line
            if (is_dashed) {
                canvas.drawDashedLine(from_x, y, to_x, y, config.message_width, mc[0], mc[1], mc[2], mc[3], 6.0, 4.0);
            } else {
                canvas.drawLine(from_x, y, to_x, y, config.message_width, mc[0], mc[1], mc[2], mc[3]);
            }

            // Draw arrowhead or cross at the destination end
            if (msg.arrow_type.hasArrowhead()) {
                if (msg.arrow_type.isOpenArrow()) {
                    drawOpenArrowhead(canvas, from_x, to_x, y, config);
                } else {
                    // Filled arrowhead
                    drawFilledArrowhead(canvas, from_x, y, to_x, y, config);
                }
            } else if (msg.arrow_type.isCross()) {
                drawCross(canvas, to_x, y, config);
            }
        }

        // Message label text
        if (font) |f| {
            const mt = config.message_text_color;

            if (msg.text) |text| {
                const label_text = if (diag.autonumber) blk: {
                    break :blk try std.fmt.allocPrint(allocator, "{d}. {s}", .{ msg_number, text });
                } else text;
                defer if (diag.autonumber) allocator.free(label_text);

                if (msg.isSelfMessage()) {
                    f.drawText(
                        canvas,
                        label_text,
                        @floatCast(from_x + layout_config.self_message_width + 8.0),
                        @floatCast(y + layout_config.self_message_height / 2.0),
                        config.message_font_size,
                        mt[0],
                        mt[1],
                        mt[2],
                        mt[3],
                    ) catch {};
                } else {
                    // Centre label above the arrow
                    const tw = f.measureText(label_text, config.message_font_size);
                    const mid_x = (from_x + to_x) / 2.0;
                    f.drawText(
                        canvas,
                        label_text,
                        @as(f32, @floatCast(mid_x)) - tw / 2.0,
                        @floatCast(y - 8.0),
                        config.message_font_size,
                        mt[0],
                        mt[1],
                        mt[2],
                        mt[3],
                    ) catch {};
                }
            } else if (diag.autonumber) {
                const num_text = try std.fmt.allocPrint(allocator, "{d}", .{msg_number});
                defer allocator.free(num_text);

                const tw = f.measureText(num_text, config.message_font_size);
                const mid_x: f32 = if (msg.isSelfMessage())
                    @floatCast(from_x + layout_config.self_message_width + 8.0)
                else
                    @floatCast((from_x + to_x) / 2.0);
                const label_y: f32 = if (msg.isSelfMessage())
                    @floatCast(y + layout_config.self_message_height / 2.0)
                else
                    @floatCast(y - 8.0);

                f.drawText(
                    canvas,
                    num_text,
                    mid_x - tw / 2.0,
                    label_y,
                    config.message_font_size,
                    mt[0],
                    mt[1],
                    mt[2],
                    mt[3],
                ) catch {};
            }
        }
    }
}

/// Draw a self-message loop (arrow from a participant back to itself).
fn drawSelfMessage(
    canvas: *Canvas,
    x: f64,
    y: f64,
    layout_config: LayoutConfig,
    config: SeqPngRenderConfig,
    msg: Message,
) void {
    const w = layout_config.self_message_width;
    const h = layout_config.self_message_height;
    const mc = config.message_color;
    const is_dashed = msg.arrow_type.isDashed();

    // Draw as three line segments: right, down, left
    if (is_dashed) {
        canvas.drawDashedLine(x, y, x + w, y, config.message_width, mc[0], mc[1], mc[2], mc[3], 6.0, 4.0);
        canvas.drawDashedLine(x + w, y, x + w, y + h, config.message_width, mc[0], mc[1], mc[2], mc[3], 6.0, 4.0);
        canvas.drawDashedLine(x + w, y + h, x, y + h, config.message_width, mc[0], mc[1], mc[2], mc[3], 6.0, 4.0);
    } else {
        canvas.drawLine(x, y, x + w, y, config.message_width, mc[0], mc[1], mc[2], mc[3]);
        canvas.drawLine(x + w, y, x + w, y + h, config.message_width, mc[0], mc[1], mc[2], mc[3]);
        canvas.drawLine(x + w, y + h, x, y + h, config.message_width, mc[0], mc[1], mc[2], mc[3]);
    }

    // Arrowhead at the return point
    if (msg.arrow_type.hasArrowhead()) {
        if (msg.arrow_type.isOpenArrow()) {
            drawOpenArrowhead(canvas, x + w, x, y + h, config);
        } else {
            drawFilledArrowhead(canvas, x + w, y + h, x, y + h, config);
        }
    } else if (msg.arrow_type.isCross()) {
        drawCross(canvas, x, y + h, config);
    }
}

/// Draw an open (unfilled) arrowhead — two lines forming a "V".
fn drawOpenArrowhead(
    canvas: *Canvas,
    from_x: f64,
    to_x: f64,
    y: f64,
    config: SeqPngRenderConfig,
) void {
    const size = config.arrowhead_size;
    const dir: f64 = if (to_x > from_x) -1.0 else 1.0;
    const mc = config.message_color;

    const tip_x = to_x;
    canvas.drawLine(tip_x + dir * size, y - size * 0.5, tip_x, y, config.message_width, mc[0], mc[1], mc[2], mc[3]);
    canvas.drawLine(tip_x, y, tip_x + dir * size, y + size * 0.5, config.message_width, mc[0], mc[1], mc[2], mc[3]);
}

/// Draw a filled arrowhead triangle.
fn drawFilledArrowhead(
    canvas: *Canvas,
    from_x: f64,
    _: f64,
    to_x: f64,
    to_y: f64,
    config: SeqPngRenderConfig,
) void {
    const size = config.arrowhead_size;
    const mc = config.message_color;

    // Direction from source to target
    const dx = to_x - from_x;
    const dir: f64 = if (dx >= 0) 1.0 else -1.0;

    // Triangle vertices
    const tip_x = to_x;
    const tip_y = to_y;
    const back_x = tip_x - dir * size;
    const top_y = tip_y - size * 0.5;
    const bot_y = tip_y + size * 0.5;

    // Fill the triangle by scanline
    fillTriangle(
        canvas,
        tip_x,
        tip_y,
        back_x,
        top_y,
        back_x,
        bot_y,
        mc[0],
        mc[1],
        mc[2],
        mc[3],
    );
}

/// Draw a cross (X) at the end of a message.
fn drawCross(
    canvas: *Canvas,
    x: f64,
    y: f64,
    config: SeqPngRenderConfig,
) void {
    const s = config.cross_size / 2.0;
    const mc = config.message_color;
    canvas.drawLine(x - s, y - s, x + s, y + s, config.message_width + 1, mc[0], mc[1], mc[2], mc[3]);
    canvas.drawLine(x - s, y + s, x + s, y - s, config.message_width + 1, mc[0], mc[1], mc[2], mc[3]);
}

// -----------------------------------------------------------------------
// Notes
// -----------------------------------------------------------------------

fn drawNotes(
    allocator: Allocator,
    canvas: *Canvas,
    diag: *const SequenceDiagram,
    layout_config: LayoutConfig,
    config: SeqPngRenderConfig,
    font: ?*Font,
) !void {
    if (diag.notes.items.len == 0) return;

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

        // Draw note box
        const nf = config.note_fill;
        const ns = config.note_stroke;
        canvas.fillRect(note_x, note_y, note_w, note_h, nf[0], nf[1], nf[2], nf[3]);
        canvas.strokeRect(note_x, note_y, note_w, note_h, config.note_stroke_width, ns[0], ns[1], ns[2], ns[3]);

        // Fold triangle in the top-right corner
        const fold: f64 = 8.0;
        fillTriangle(
            canvas,
            note_x + note_w - fold,
            note_y,
            note_x + note_w,
            note_y + fold,
            note_x + note_w - fold,
            note_y + fold,
            ns[0],
            ns[1],
            ns[2],
            ns[3],
        );

        // Note text
        if (note.text) |text| {
            if (font) |f| {
                const normalized = try normalizeNoteText(allocator, text);
                defer allocator.free(normalized);

                const nt = config.note_text_color;
                f.drawWrappedText(
                    canvas,
                    normalized,
                    @floatCast(note_x + note_w / 2.0),
                    @floatCast(note_y + note_h / 2.0),
                    config.note_font_size,
                    @floatCast(@max(1.0, note_w - layout_config.note_padding_h * 2.0)),
                    nt[0],
                    nt[1],
                    nt[2],
                    nt[3],
                ) catch {};
            }
        }
    }
}

fn normalizeNoteText(allocator: Allocator, text: []const u8) ![]u8 {
    var buffer = std.ArrayList(u8){};
    defer buffer.deinit(allocator);

    var i: usize = 0;
    while (i < text.len) {
        if (matchesBreakTag(text, i)) |tag_len| {
            try buffer.append(allocator, '\n');
            i += tag_len;
            continue;
        }

        try buffer.append(allocator, text[i]);
        i += 1;
    }

    return buffer.toOwnedSlice(allocator);
}

fn matchesBreakTag(text: []const u8, start: usize) ?usize {
    const tags = [_][]const u8{ "<br/>", "<br />", "<br>" };
    for (tags) |tag| {
        if (start + tag.len <= text.len and std.ascii.eqlIgnoreCase(text[start .. start + tag.len], tag)) {
            return tag.len;
        }
    }
    return null;
}

// -----------------------------------------------------------------------
// Participant boxes (header + footer)
// -----------------------------------------------------------------------

fn drawParticipantBoxes(
    canvas: *Canvas,
    diag: *const SequenceDiagram,
    layout_result: LayoutResult,
    layout_config: LayoutConfig,
    config: SeqPngRenderConfig,
    font: ?*Font,
) void {
    for (diag.participants.items) |p| {
        const label = p.displayName();

        // Header box
        drawParticipantBox(canvas, p, layout_result.header_y, layout_config, config, label, font);

        // Footer box (mirrored at the bottom)
        drawParticipantBox(canvas, p, layout_result.footer_y, layout_config, config, label, font);
    }
}

fn drawParticipantBox(
    canvas: *Canvas,
    p: Participant,
    box_y: f64,
    layout_config: LayoutConfig,
    config: SeqPngRenderConfig,
    label: []const u8,
    font: ?*Font,
) void {
    _ = layout_config;

    const box_x = p.center_x - p.box_width / 2.0;

    switch (p.kind) {
        .box => {
            // Draw rounded rect (approximated with fill + stroke)
            const pf = config.participant_fill;
            const ps = config.participant_stroke;
            drawRoundedRect(canvas, box_x, box_y, p.box_width, p.box_height, config.participant_corner_radius, pf, ps, config.participant_stroke_width);

            // Text
            if (font) |f| {
                const pt = config.participant_text_color;
                const tw = f.measureText(label, config.participant_font_size);
                const cx: f32 = @floatCast(p.center_x);
                f.drawText(
                    canvas,
                    label,
                    cx - tw / 2.0,
                    @floatCast(box_y + p.box_height / 2.0),
                    config.participant_font_size,
                    pt[0],
                    pt[1],
                    pt[2],
                    pt[3],
                ) catch {};
            }
        },
        .actor => {
            drawActorFigure(canvas, p.center_x, box_y, p.box_height, config, label, font);
        },
    }
}

/// Draw a stick-figure actor at the given position.
fn drawActorFigure(
    canvas: *Canvas,
    cx: f64,
    top_y: f64,
    total_h: f64,
    config: SeqPngRenderConfig,
    label: []const u8,
    font: ?*Font,
) void {
    const ac = config.actor_color;
    const aw = config.actor_stroke_width;

    // Proportions within total_h (same as SVG renderer)
    const head_r: f64 = total_h * 0.15;
    const head_cy = top_y + head_r;
    const body_top = head_cy + head_r;
    const body_bottom = top_y + total_h * 0.7;
    const arm_y = body_top + (body_bottom - body_top) * 0.3;
    const arm_span: f64 = total_h * 0.3;
    const leg_bottom = top_y + total_h * 0.95;
    const leg_span: f64 = total_h * 0.2;

    // Head circle
    canvas.strokeEllipse(cx, head_cy, head_r, head_r, aw, ac[0], ac[1], ac[2], ac[3]);

    // Body line
    canvas.drawLine(cx, body_top, cx, body_bottom, aw, ac[0], ac[1], ac[2], ac[3]);

    // Arms
    canvas.drawLine(cx - arm_span, arm_y, cx + arm_span, arm_y, aw, ac[0], ac[1], ac[2], ac[3]);

    // Left leg
    canvas.drawLine(cx, body_bottom, cx - leg_span, leg_bottom, aw, ac[0], ac[1], ac[2], ac[3]);

    // Right leg
    canvas.drawLine(cx, body_bottom, cx + leg_span, leg_bottom, aw, ac[0], ac[1], ac[2], ac[3]);

    // Label below
    if (font) |f| {
        const pt = config.participant_text_color;
        const tw = f.measureText(label, config.participant_font_size);
        const lcx: f32 = @floatCast(cx);
        f.drawText(
            canvas,
            label,
            lcx - tw / 2.0,
            @floatCast(top_y + total_h + 12.0),
            config.participant_font_size,
            pt[0],
            pt[1],
            pt[2],
            pt[3],
        ) catch {};
    }
}

// -----------------------------------------------------------------------
// Utility: rounded rectangle
// -----------------------------------------------------------------------

/// Draw a filled and stroked rounded rectangle.
/// Uses a simplified approach: fills the main body and corner arcs.
fn drawRoundedRect(
    canvas: *Canvas,
    x: f64,
    y: f64,
    w: f64,
    h: f64,
    radius: f64,
    fill_color: [4]u8,
    stroke_color: [4]u8,
    stroke_width: i32,
) void {
    const r = @min(radius, @min(w / 2.0, h / 2.0));

    // Fill the center cross (avoiding corners)
    canvas.fillRect(x + r, y, w - 2.0 * r, h, fill_color[0], fill_color[1], fill_color[2], fill_color[3]);
    canvas.fillRect(x, y + r, r, h - 2.0 * r, fill_color[0], fill_color[1], fill_color[2], fill_color[3]);
    canvas.fillRect(x + w - r, y + r, r, h - 2.0 * r, fill_color[0], fill_color[1], fill_color[2], fill_color[3]);

    // Fill the four corner quadrants using filled ellipse clipped to quadrant
    fillCornerArc(canvas, x + r, y + r, r, fill_color, .top_left);
    fillCornerArc(canvas, x + w - r, y + r, r, fill_color, .top_right);
    fillCornerArc(canvas, x + r, y + h - r, r, fill_color, .bottom_left);
    fillCornerArc(canvas, x + w - r, y + h - r, r, fill_color, .bottom_right);

    // Stroke the outline
    const sc = stroke_color;

    // Top edge
    canvas.drawLine(x + r, y, x + w - r, y, stroke_width, sc[0], sc[1], sc[2], sc[3]);
    // Bottom edge
    canvas.drawLine(x + r, y + h, x + w - r, y + h, stroke_width, sc[0], sc[1], sc[2], sc[3]);
    // Left edge
    canvas.drawLine(x, y + r, x, y + h - r, stroke_width, sc[0], sc[1], sc[2], sc[3]);
    // Right edge
    canvas.drawLine(x + w, y + r, x + w, y + h - r, stroke_width, sc[0], sc[1], sc[2], sc[3]);

    // Corner arcs (approximated with short line segments)
    strokeCornerArc(canvas, x + r, y + r, r, stroke_width, sc, .top_left);
    strokeCornerArc(canvas, x + w - r, y + r, r, stroke_width, sc, .top_right);
    strokeCornerArc(canvas, x + r, y + h - r, r, stroke_width, sc, .bottom_left);
    strokeCornerArc(canvas, x + w - r, y + h - r, r, stroke_width, sc, .bottom_right);
}

const CornerQuadrant = enum { top_left, top_right, bottom_left, bottom_right };

/// Fill a quarter-circle arc for rounded corners.
fn fillCornerArc(
    canvas: *Canvas,
    cx: f64,
    cy: f64,
    r: f64,
    color: [4]u8,
    quadrant: CornerQuadrant,
) void {
    const sf = canvas.scale_factor;
    const scx = cx * sf;
    const scy = cy * sf;
    const sr = r * sf;

    const iy_start: i32 = @intFromFloat(@floor(scy - sr));
    const iy_end: i32 = @intFromFloat(@ceil(scy + sr));

    var iy: i32 = iy_start;
    while (iy <= iy_end) : (iy += 1) {
        const dy = @as(f64, @floatFromInt(iy)) + 0.5 - scy;

        // Only process the relevant vertical half
        switch (quadrant) {
            .top_left, .top_right => {
                if (dy > 0) continue;
            },
            .bottom_left, .bottom_right => {
                if (dy < 0) continue;
            },
        }

        const ratio_y = dy / sr;
        if (@abs(ratio_y) > 1.0) continue;
        const half_w = sr * @sqrt(1.0 - ratio_y * ratio_y);

        const ix_start: i32 = @intFromFloat(@floor(scx - half_w));
        const ix_end: i32 = @intFromFloat(@ceil(scx + half_w));

        var ix: i32 = ix_start;
        while (ix <= ix_end) : (ix += 1) {
            const dx = @as(f64, @floatFromInt(ix)) + 0.5 - scx;

            // Only process the relevant horizontal half
            switch (quadrant) {
                .top_left, .bottom_left => {
                    if (dx > 0) continue;
                },
                .top_right, .bottom_right => {
                    if (dx < 0) continue;
                },
            }

            const ex = dx / sr;
            const ey = dy / sr;
            if (ex * ex + ey * ey <= 1.0) {
                canvas.setPixel(ix, iy, color[0], color[1], color[2], color[3]);
            }
        }
    }
}

/// Stroke a quarter-circle arc for rounded corners.
fn strokeCornerArc(
    canvas: *Canvas,
    cx: f64,
    cy: f64,
    r: f64,
    thickness: i32,
    color: [4]u8,
    quadrant: CornerQuadrant,
) void {
    const segs: usize = 12;
    const half_pi = std.math.pi / 2.0;

    // Determine the start angle for this quadrant
    const base_angle: f64 = switch (quadrant) {
        .top_left => std.math.pi,
        .top_right => 3.0 * std.math.pi / 2.0,
        .bottom_left => std.math.pi / 2.0,
        .bottom_right => 0.0,
    };

    var prev_x = cx + r * @cos(base_angle);
    var prev_y = cy + r * @sin(base_angle);

    for (1..segs + 1) |s| {
        const t = @as(f64, @floatFromInt(s)) / @as(f64, @floatFromInt(segs));
        const angle = base_angle + t * half_pi;
        const ax = cx + r * @cos(angle);
        const ay = cy + r * @sin(angle);
        canvas.drawLine(prev_x, prev_y, ax, ay, thickness, color[0], color[1], color[2], color[3]);
        prev_x = ax;
        prev_y = ay;
    }
}

// -----------------------------------------------------------------------
// Utility: triangle fill (for arrowheads and note fold corners)
// -----------------------------------------------------------------------

/// Fill a triangle defined by three vertices using scanline rasterization.
fn fillTriangle(
    canvas: *Canvas,
    x0: f64,
    y0: f64,
    x1: f64,
    y1: f64,
    x2: f64,
    y2: f64,
    r: u8,
    g: u8,
    b: u8,
    a: u8,
) void {
    const sf = canvas.scale_factor;
    const sx0 = x0 * sf;
    const sy0 = y0 * sf;
    const sx1 = x1 * sf;
    const sy1 = y1 * sf;
    const sx2 = x2 * sf;
    const sy2 = y2 * sf;

    // Bounding box
    const min_y = @min(sy0, @min(sy1, sy2));
    const max_y = @max(sy0, @max(sy1, sy2));
    const min_x = @min(sx0, @min(sx1, sx2));
    const max_x = @max(sx0, @max(sx1, sx2));

    const iy_start: i32 = @intFromFloat(@floor(min_y));
    const iy_end: i32 = @intFromFloat(@ceil(max_y));
    const ix_start: i32 = @intFromFloat(@floor(min_x));
    const ix_end: i32 = @intFromFloat(@ceil(max_x));

    var iy: i32 = iy_start;
    while (iy <= iy_end) : (iy += 1) {
        var ix: i32 = ix_start;
        while (ix <= ix_end) : (ix += 1) {
            const px = @as(f64, @floatFromInt(ix)) + 0.5;
            const py = @as(f64, @floatFromInt(iy)) + 0.5;

            if (pointInTriangleF64(px, py, sx0, sy0, sx1, sy1, sx2, sy2)) {
                canvas.setPixel(ix, iy, r, g, b, a);
            }
        }
    }
}

/// Check if point (px, py) is inside the triangle defined by (x0,y0), (x1,y1), (x2,y2).
fn pointInTriangleF64(
    px: f64,
    py: f64,
    x0: f64,
    y0: f64,
    x1: f64,
    y1: f64,
    x2: f64,
    y2: f64,
) bool {
    const d1 = (px - x1) * (y0 - y1) - (x0 - x1) * (py - y1);
    const d2 = (px - x2) * (y1 - y2) - (x1 - x2) * (py - y2);
    const d3 = (px - x0) * (y2 - y0) - (x2 - x0) * (py - y0);

    const has_neg = (d1 < 0) or (d2 < 0) or (d3 < 0);
    const has_pos = (d1 > 0) or (d2 > 0) or (d3 > 0);

    return !(has_neg and has_pos);
}

// -----------------------------------------------------------------------
// Error set
// -----------------------------------------------------------------------

pub const RenderError = error{
    InvalidDimensions,
    PNGWriteFailed,
    OutOfMemory,
    FontInitFailed,
};

// =======================================================================
// Tests
// =======================================================================

const testing = std.testing;

test "png_seq_render: empty diagram produces no crash" {
    var diag = SequenceDiagram.init(testing.allocator);
    defer diag.deinit();

    const layout_config = LayoutConfig{};
    const layout_result = seq_layout.layout(&diag, layout_config);
    const render_config = SeqPngRenderConfig{};

    // Empty diagram has zero-size canvas — we expect InvalidDimensions
    const result = renderToPNGFile(
        testing.allocator,
        &diag,
        layout_result,
        "/tmp/test_seq_empty.png",
        layout_config,
        render_config,
        null,
    );
    // Zero-size diagram may or may not error; just ensure no crash.
    if (result) |_| {} else |_| {}
}

test "png_seq_render: two participants with message" {
    var diag = SequenceDiagram.init(testing.allocator);
    defer diag.deinit();

    _ = try diag.ensureParticipant("Alice");
    _ = try diag.ensureParticipant("Bob");

    _ = try diag.addMessage(.{
        .from = 0,
        .to = 1,
        .text = "Hello",
        .text_owned = false,
        .arrow_type = .solid_arrow,
        .activate_target = false,
        .deactivate_target = false,
        .y = 0,
    });

    const layout_config = LayoutConfig{};
    const layout_result = seq_layout.layout(&diag, layout_config);
    const render_config = SeqPngRenderConfig{};

    // Render without font (no text, but should not crash)
    try renderToPNGFile(
        testing.allocator,
        &diag,
        layout_result,
        "/tmp/test_seq_two_participants.png",
        layout_config,
        render_config,
        null,
    );
}

test "png_seq_render: self-message" {
    var diag = SequenceDiagram.init(testing.allocator);
    defer diag.deinit();

    _ = try diag.ensureParticipant("Alice");

    _ = try diag.addMessage(.{
        .from = 0,
        .to = 0,
        .text = "think",
        .text_owned = false,
        .arrow_type = .solid_arrow,
        .activate_target = false,
        .deactivate_target = false,
        .y = 0,
    });

    const layout_config = LayoutConfig{};
    const layout_result = seq_layout.layout(&diag, layout_config);
    const render_config = SeqPngRenderConfig{};

    try renderToPNGFile(
        testing.allocator,
        &diag,
        layout_result,
        "/tmp/test_seq_self_msg.png",
        layout_config,
        render_config,
        null,
    );
}

test "png_seq_render: note renders" {
    var diag = SequenceDiagram.init(testing.allocator);
    defer diag.deinit();

    _ = try diag.ensureParticipant("Alice");

    _ = try diag.addNote(.{
        .position = .right_of,
        .participant1 = 0,
        .participant2 = 0,
        .text = "A note",
        .text_owned = false,
        .y = 0,
        .width = 80,
        .height = 40,
    });

    const layout_config = LayoutConfig{};
    const layout_result = seq_layout.layout(&diag, layout_config);
    const render_config = SeqPngRenderConfig{};

    try renderToPNGFile(
        testing.allocator,
        &diag,
        layout_result,
        "/tmp/test_seq_note.png",
        layout_config,
        render_config,
        null,
    );
}

test "png_seq_render: activation bar renders" {
    var diag = SequenceDiagram.init(testing.allocator);
    defer diag.deinit();

    _ = try diag.ensureParticipant("Alice");
    _ = try diag.ensureParticipant("Bob");

    _ = try diag.addMessage(.{
        .from = 0,
        .to = 1,
        .text = "call",
        .text_owned = false,
        .arrow_type = .solid_arrow,
        .activate_target = true,
        .deactivate_target = false,
        .y = 0,
    });

    _ = try diag.addMessage(.{
        .from = 1,
        .to = 0,
        .text = "return",
        .text_owned = false,
        .arrow_type = .dotted_arrow,
        .activate_target = false,
        .deactivate_target = true,
        .y = 0,
    });

    // Add activation manually
    try diag.activations.append(diag.allocator, .{
        .participant = 1,
        .start_event = 0,
        .end_event = 1,
        .depth = 0,
        .start_y = 0,
        .end_y = 0,
    });

    const layout_config = LayoutConfig{};
    const layout_result = seq_layout.layout(&diag, layout_config);
    const render_config = SeqPngRenderConfig{};

    try renderToPNGFile(
        testing.allocator,
        &diag,
        layout_result,
        "/tmp/test_seq_activation.png",
        layout_config,
        render_config,
        null,
    );
}

test "png_seq_render: dashed arrow" {
    var diag = SequenceDiagram.init(testing.allocator);
    defer diag.deinit();

    _ = try diag.ensureParticipant("Alice");
    _ = try diag.ensureParticipant("Bob");

    _ = try diag.addMessage(.{
        .from = 0,
        .to = 1,
        .text = "reply",
        .text_owned = false,
        .arrow_type = .dotted_arrow,
        .activate_target = false,
        .deactivate_target = false,
        .y = 0,
    });

    const layout_config = LayoutConfig{};
    const layout_result = seq_layout.layout(&diag, layout_config);
    const render_config = SeqPngRenderConfig{};

    try renderToPNGFile(
        testing.allocator,
        &diag,
        layout_result,
        "/tmp/test_seq_dashed.png",
        layout_config,
        render_config,
        null,
    );
}

test "png_seq_render: fragment box" {
    var diag = SequenceDiagram.init(testing.allocator);
    defer diag.deinit();

    _ = try diag.ensureParticipant("Alice");
    _ = try diag.ensureParticipant("Bob");

    _ = try diag.addMessage(.{
        .from = 0,
        .to = 1,
        .text = "in loop",
        .text_owned = false,
        .arrow_type = .solid_arrow,
        .activate_target = false,
        .deactivate_target = false,
        .y = 0,
    });

    var frag = Fragment{ .kind = .loop_block };
    try frag.sections.append(diag.allocator, .{
        .label = "every 5s",
        .label_owned = false,
        .start_event = 0,
        .end_event = 0,
        .start_y = 0,
        .end_y = 0,
    });

    frag.left_participant = 0;
    frag.right_participant = 1;

    try diag.fragments.append(diag.allocator, frag);

    const layout_config = LayoutConfig{};
    const layout_result = seq_layout.layout(&diag, layout_config);
    const render_config = SeqPngRenderConfig{};

    try renderToPNGFile(
        testing.allocator,
        &diag,
        layout_result,
        "/tmp/test_seq_fragment.png",
        layout_config,
        render_config,
        null,
    );
}

test "png_seq_render: fillTriangle basic" {
    const allocator = testing.allocator;
    var canvas = try Canvas.init(allocator, 20, 20);
    defer canvas.deinit();
    canvas.fill(255, 255, 255, 255);

    // Draw a small triangle
    fillTriangle(&canvas, 5.0, 5.0, 15.0, 5.0, 10.0, 15.0, 0, 0, 0, 255);

    // Centre of the triangle should be filled (black)
    const idx = (10 * 20 + 10) * 4;
    try testing.expectEqual(@as(u8, 0), canvas.pixels[idx]); // R
    try testing.expectEqual(@as(u8, 0), canvas.pixels[idx + 1]); // G
    try testing.expectEqual(@as(u8, 0), canvas.pixels[idx + 2]); // B
}

test "png_seq_render: pointInTriangleF64" {
    // Inside
    try testing.expect(pointInTriangleF64(5.0, 5.0, 0.0, 0.0, 10.0, 0.0, 5.0, 10.0));
    // Outside
    try testing.expect(!pointInTriangleF64(0.0, 10.0, 0.0, 0.0, 10.0, 0.0, 5.0, 10.0));
}

test "png_seq_render: drawRoundedRect no crash" {
    const allocator = testing.allocator;
    var canvas = try Canvas.init(allocator, 100, 60);
    defer canvas.deinit();
    canvas.fill(255, 255, 255, 255);

    drawRoundedRect(
        &canvas,
        10.0,
        10.0,
        80.0,
        40.0,
        5.0,
        .{ 200, 200, 255, 255 },
        .{ 100, 100, 200, 255 },
        2,
    );

    // Interior should be filled
    const idx = (30 * 100 + 50) * 4;
    try testing.expectEqual(@as(u8, 200), canvas.pixels[idx]);
}
