/// Direct2D drawing for the freeform canvas.
/// Renders nodes, subgraphs, edges, labels, selection outlines, and resize handles.
const std = @import("std");
const win32 = @import("win32");
const project_settings = @import("../project_settings.zig");
const state = @import("state.zig");
const hit_test = @import("hit_test.zig");

const d2d = win32.graphics.direct2d;
const d2d_common = win32.graphics.direct2d.common;
const dwrite = win32.graphics.direct_write;
const foundation = win32.foundation;

const StudioEditableGraph = state.StudioEditableGraph;
const StudioEditableNode = state.StudioEditableNode;
const StudioEditableSubgraph = state.StudioEditableSubgraph;
const StudioEditableEdge = state.StudioEditableEdge;
const StudioColor = state.StudioColor;
const Viewport = state.Viewport;
const Selection = state.Selection;
const SelectionKind = state.SelectionKind;
const HandlePos = state.HandlePos;
const d2d_factory_type = d2d.ID2D1Factory;
const FontFamily = project_settings.FontFamily;

const font_family_lato_w = [_:0]u16{ 'L', 'a', 't', 'o' };
const font_family_segoe_ui_w = [_:0]u16{ 'S', 'e', 'g', 'o', 'e', ' ', 'U', 'I' };
const font_family_arial_w = [_:0]u16{ 'A', 'r', 'i', 'a', 'l' };
const font_family_consolas_w = [_:0]u16{ 'C', 'o', 'n', 's', 'o', 'l', 'a', 's' };
const locale_name_w = [_:0]u16{ 'e', 'n', '-', 'U', 'S' };

// ---------------------------------------------------------------------------
// Color helpers
// ---------------------------------------------------------------------------

fn d2dColor(c: StudioColor) d2d_common.D2D_COLOR_F {
    return .{
        .r = @as(f32, @floatFromInt(c.r)) / 255.0,
        .g = @as(f32, @floatFromInt(c.g)) / 255.0,
        .b = @as(f32, @floatFromInt(c.b)) / 255.0,
        .a = @as(f32, @floatFromInt(c.a)) / 255.0,
    };
}

fn d2dColorRgb(r: u8, g: u8, b: u8) d2d_common.D2D_COLOR_F {
    return d2dColor(.{ .r = r, .g = g, .b = b, .a = 255 });
}

fn d2dColorRgba(r: u8, g: u8, b: u8, a: u8) d2d_common.D2D_COLOR_F {
    return d2dColor(.{ .r = r, .g = g, .b = b, .a = a });
}

// ---------------------------------------------------------------------------
// Viewport → screen transform helpers
// ---------------------------------------------------------------------------

fn rectF(l: f32, t: f32, r: f32, b: f32) d2d_common.D2D_RECT_F {
    return .{ .left = l, .top = t, .right = r, .bottom = b };
}

fn point2F(x: f32, y: f32) d2d_common.D2D_POINT_2F {
    return .{ .x = x, .y = y };
}

fn ellipseF(cx: f32, cy: f32, rx: f32, ry: f32) d2d.D2D1_ELLIPSE {
    return .{ .point = point2F(cx, cy), .radiusX = rx, .radiusY = ry };
}

fn rounded_rect(l: f32, t: f32, r: f32, b: f32, radius: f32) d2d.D2D1_ROUNDED_RECT {
    return .{ .rect = rectF(l, t, r, b), .radiusX = radius, .radiusY = radius };
}

/// Convert a canvas-space bounding box to screen-space (f32).
fn canvasRectToScreen(vp: Viewport, x: f64, y: f64, w: f64, h: f64) struct {
    l: f32,
    t: f32,
    r: f32,
    b: f32,
} {
    const s = vp.canvasToScreen(x, y);
    return .{
        .l = @floatCast(s.x),
        .t = @floatCast(s.y),
        .r = @floatCast(s.x + w * vp.zoom),
        .b = @floatCast(s.y + h * vp.zoom),
    };
}

// ---------------------------------------------------------------------------
// Solid-colour brush cache (one brush per draw call, recreated on demand)
// ---------------------------------------------------------------------------

/// Acquire a solid-colour brush.  Caller must NOT release it — it is owned by
/// the render target and reused each frame through `SetColor`.
fn makeBrush(
    rt: *d2d.ID2D1RenderTarget,
    color: d2d_common.D2D_COLOR_F,
    out: *?*d2d.ID2D1SolidColorBrush,
) void {
    if (out.* == null) {
        _ = rt.CreateSolidColorBrush(&color, null, @ptrCast(out));
    } else {
        out.*.?.SetColor(&color);
    }
}

// ---------------------------------------------------------------------------
// Node shape rendering
// ---------------------------------------------------------------------------

/// Node shape codes (mirror values used in app/preview.zig and the Obj-C canvas).
const Shape = enum(u32) {
    rectangle = 0,
    rounded_rectangle = 1,
    diamond = 2,
    circle = 3,
    hexagon = 4,
    cylinder = 5,
    stadium = 6, // pill / capsule
    trapezoid = 7,
    trapezoid_alt = 8,
    parallelogram = 9,
    parallelogram_alt = 10,
    subroutine = 11,
    end_state = 12, // circle within a circle (mermaid state diagram end node)
    note = 13,      // rectangle with folded top-right corner
    actor = 14,     // stick figure (sequence diagram participant)
    other = 0xffff_ffff,
    _,
};

fn drawClosedPolygon(
    factory: *d2d_factory_type,
    rt: *d2d.ID2D1RenderTarget,
    points: []const d2d_common.D2D_POINT_2F,
    fill_brush: *d2d.ID2D1SolidColorBrush,
    stroke_brush: *d2d.ID2D1SolidColorBrush,
    stroke_w: f32,
) void {
    if (points.len < 3) return;

    var path_raw: *d2d.ID2D1PathGeometry = undefined;
    if (factory.CreatePathGeometry(&path_raw) < 0) return;
    const path_geometry: ?*d2d.ID2D1PathGeometry = path_raw;
    defer {
        if (path_geometry) |g| _ = g.IUnknown.Release();
    }

    var sink_raw: *d2d.ID2D1GeometrySink = undefined;
    if (path_raw.Open(&sink_raw) < 0) return;
    const sink: ?*d2d.ID2D1GeometrySink = sink_raw;
    defer {
        if (sink) |s| _ = s.IUnknown.Release();
    }

    sink.?.ID2D1SimplifiedGeometrySink.BeginFigure(points[0], d2d_common.D2D1_FIGURE_BEGIN_FILLED);
    var idx: usize = 1;
    while (idx < points.len) : (idx += 1) {
        sink.?.AddLine(points[idx]);
    }
    sink.?.ID2D1SimplifiedGeometrySink.EndFigure(d2d_common.D2D1_FIGURE_END_CLOSED);
    if (sink.?.ID2D1SimplifiedGeometrySink.Close() < 0) return;

    rt.FillGeometry(@ptrCast(path_geometry), @ptrCast(fill_brush), null);
    rt.DrawGeometry(@ptrCast(path_geometry), @ptrCast(stroke_brush), stroke_w, null);
}

fn drawNodeShape(
    factory: *d2d_factory_type,
    rt: *d2d.ID2D1RenderTarget,
    fill_brush: *d2d.ID2D1SolidColorBrush,
    stroke_brush: *d2d.ID2D1SolidColorBrush,
    node: *const StudioEditableNode,
    vp: Viewport,
) void {
    const sr = canvasRectToScreen(vp, node.x, node.y, node.width, node.height);
    const stroke_w: f32 = @floatCast(@as(f64, node.stroke_width) * vp.zoom);
    const shape: Shape = @enumFromInt(node.shape);

    switch (shape) {
        .circle => {
            const cx = (sr.l + sr.r) / 2.0;
            const cy = (sr.t + sr.b) / 2.0;
            const rx = (sr.r - sr.l) / 2.0;
            const ry = (sr.b - sr.t) / 2.0;
            const el = ellipseF(cx, cy, rx, ry);
            rt.FillEllipse(&el, @ptrCast(fill_brush));
            rt.DrawEllipse(&el, @ptrCast(stroke_brush), stroke_w, null);
        },
        .end_state => {
            // Outer ring (white fill + stroke).
            const cx = (sr.l + sr.r) / 2.0;
            const cy = (sr.t + sr.b) / 2.0;
            const rx = (sr.r - sr.l) / 2.0;
            const ry = (sr.b - sr.t) / 2.0;
            const outer = ellipseF(cx, cy, rx, ry);
            rt.FillEllipse(&outer, @ptrCast(fill_brush));
            rt.DrawEllipse(&outer, @ptrCast(stroke_brush), stroke_w, null);
            // Inner filled circle (40% of outer radius).
            const inner_r = rx * 0.52;
            const inner = ellipseF(cx, cy, inner_r, inner_r);
            rt.FillEllipse(&inner, @ptrCast(stroke_brush));
        },
        .diamond => {
            const cx = (sr.l + sr.r) / 2.0;
            const cy = (sr.t + sr.b) / 2.0;
            const points = [_]d2d_common.D2D_POINT_2F{
                point2F(cx, sr.t),
                point2F(sr.r, cy),
                point2F(cx, sr.b),
                point2F(sr.l, cy),
            };
            drawClosedPolygon(factory, rt, &points, fill_brush, stroke_brush, stroke_w);
        },
        .hexagon => {
            const inset = (sr.r - sr.l) * 0.22;
            const points = [_]d2d_common.D2D_POINT_2F{
                point2F(sr.l + inset, sr.t),
                point2F(sr.r - inset, sr.t),
                point2F(sr.r, (sr.t + sr.b) / 2.0),
                point2F(sr.r - inset, sr.b),
                point2F(sr.l + inset, sr.b),
                point2F(sr.l, (sr.t + sr.b) / 2.0),
            };
            drawClosedPolygon(factory, rt, &points, fill_brush, stroke_brush, stroke_w);
        },
        .rounded_rectangle, .stadium => {
            const radius: f32 = if (shape == .stadium)
                (sr.b - sr.t) / 2.0
            else
                @floatCast(8.0 * vp.zoom);
            const rr = rounded_rect(sr.l, sr.t, sr.r, sr.b, radius);
            rt.FillRoundedRectangle(&rr, @ptrCast(fill_brush));
            rt.DrawRoundedRectangle(&rr, @ptrCast(stroke_brush), stroke_w, null);
        },
        .parallelogram, .parallelogram_alt => {
            const inset = (sr.r - sr.l) * 0.18;
            const points = if (shape == .parallelogram)
                [_]d2d_common.D2D_POINT_2F{
                    point2F(sr.l + inset, sr.t),
                    point2F(sr.r, sr.t),
                    point2F(sr.r - inset, sr.b),
                    point2F(sr.l, sr.b),
                }
            else
                [_]d2d_common.D2D_POINT_2F{
                    point2F(sr.l, sr.t),
                    point2F(sr.r - inset, sr.t),
                    point2F(sr.r, sr.b),
                    point2F(sr.l + inset, sr.b),
                };
            drawClosedPolygon(factory, rt, &points, fill_brush, stroke_brush, stroke_w);
        },
        .trapezoid, .trapezoid_alt => {
            const inset = (sr.r - sr.l) * 0.18;
            const points = if (shape == .trapezoid)
                [_]d2d_common.D2D_POINT_2F{
                    point2F(sr.l + inset, sr.t),
                    point2F(sr.r - inset, sr.t),
                    point2F(sr.r, sr.b),
                    point2F(sr.l, sr.b),
                }
            else
                [_]d2d_common.D2D_POINT_2F{
                    point2F(sr.l, sr.t),
                    point2F(sr.r, sr.t),
                    point2F(sr.r - inset, sr.b),
                    point2F(sr.l + inset, sr.b),
                };
            drawClosedPolygon(factory, rt, &points, fill_brush, stroke_brush, stroke_w);
        },
        .cylinder => {
            const cap_h = @min((sr.b - sr.t) * 0.22, 18.0 * @as(f32, @floatCast(vp.zoom)));
            const body = rectF(sr.l, sr.t + cap_h * 0.5, sr.r, sr.b - cap_h * 0.5);
            const top = ellipseF((sr.l + sr.r) / 2.0, sr.t + cap_h * 0.5, (sr.r - sr.l) / 2.0, cap_h * 0.5);
            const bottom = ellipseF((sr.l + sr.r) / 2.0, sr.b - cap_h * 0.5, (sr.r - sr.l) / 2.0, cap_h * 0.5);
            rt.FillRectangle(&body, @ptrCast(fill_brush));
            rt.FillEllipse(&top, @ptrCast(fill_brush));
            rt.FillEllipse(&bottom, @ptrCast(fill_brush));
            rt.DrawEllipse(&top, @ptrCast(stroke_brush), stroke_w, null);
            rt.DrawEllipse(&bottom, @ptrCast(stroke_brush), stroke_w, null);
            rt.DrawLine(point2F(sr.l, sr.t + cap_h * 0.5), point2F(sr.l, sr.b - cap_h * 0.5), @ptrCast(stroke_brush), stroke_w, null);
            rt.DrawLine(point2F(sr.r, sr.t + cap_h * 0.5), point2F(sr.r, sr.b - cap_h * 0.5), @ptrCast(stroke_brush), stroke_w, null);
        },
        .subroutine => {
            const rc = rectF(sr.l, sr.t, sr.r, sr.b);
            const inset = @max(8.0, (sr.r - sr.l) * 0.1);
            rt.FillRectangle(&rc, @ptrCast(fill_brush));
            rt.DrawRectangle(&rc, @ptrCast(stroke_brush), stroke_w, null);
            rt.DrawLine(point2F(sr.l + inset, sr.t), point2F(sr.l + inset, sr.b), @ptrCast(stroke_brush), stroke_w, null);
            rt.DrawLine(point2F(sr.r - inset, sr.t), point2F(sr.r - inset, sr.b), @ptrCast(stroke_brush), stroke_w, null);
        },
        .note => {
            // Rectangle with folded top-right corner.
            const h = sr.b - sr.t;
            const max_fold: f32 = 14.0 * @as(f32, @floatCast(vp.zoom));
            const fold = @min(max_fold, @min((sr.r - sr.l) * 0.20, h * 0.30));
            const poly = [_]d2d_common.D2D_POINT_2F{
                point2F(sr.l, sr.t),
                point2F(sr.r - fold, sr.t),
                point2F(sr.r, sr.t + fold),
                point2F(sr.r, sr.b),
                point2F(sr.l, sr.b),
            };
            drawClosedPolygon(factory, rt, &poly, fill_brush, stroke_brush, stroke_w);
            // Fold crease lines (the triangular ear).
            rt.DrawLine(point2F(sr.r - fold, sr.t), point2F(sr.r - fold, sr.t + fold), @ptrCast(stroke_brush), stroke_w, null);
            rt.DrawLine(point2F(sr.r - fold, sr.t + fold), point2F(sr.r, sr.t + fold), @ptrCast(stroke_brush), stroke_w, null);
        },
        .actor => {
            // Stick figure icon in the top 58% + filled name box in the bottom 42%.
            const h = sr.b - sr.t;
            const w = sr.r - sr.l;
            const fig_frac: f32 = 0.58;
            const fig_h = h * fig_frac;
            const name_top = sr.t + fig_h;
            const cx = (sr.l + sr.r) / 2.0;
            // Name box (lower portion).
            const name_rc = rectF(sr.l, name_top, sr.r, sr.b);
            rt.FillRectangle(&name_rc, @ptrCast(fill_brush));
            rt.DrawRectangle(&name_rc, @ptrCast(stroke_brush), stroke_w, null);
            // Stick figure strokes.
            const head_r = @min(w * 0.18, fig_h * 0.30);
            const head_cy = sr.t + head_r + fig_h * 0.04;
            const body_top = head_cy + head_r + 1.0;
            const body_bottom = sr.t + fig_h * 0.72;
            const arm_y = sr.t + fig_h * 0.52;
            const arm_half = w * 0.36;
            const leg_spread = w * 0.28;
            const head_el = ellipseF(cx, head_cy, head_r, head_r);
            rt.DrawEllipse(&head_el, @ptrCast(stroke_brush), stroke_w, null);
            rt.DrawLine(point2F(cx, body_top), point2F(cx, body_bottom), @ptrCast(stroke_brush), stroke_w, null);
            rt.DrawLine(point2F(cx - arm_half, arm_y), point2F(cx + arm_half, arm_y), @ptrCast(stroke_brush), stroke_w, null);
            rt.DrawLine(point2F(cx, body_bottom), point2F(cx - leg_spread, name_top - stroke_w), @ptrCast(stroke_brush), stroke_w, null);
            rt.DrawLine(point2F(cx, body_bottom), point2F(cx + leg_spread, name_top - stroke_w), @ptrCast(stroke_brush), stroke_w, null);
        },
        else => {
            // Default: rectangle.
            const rc = rectF(sr.l, sr.t, sr.r, sr.b);
            rt.FillRectangle(&rc, @ptrCast(fill_brush));
            rt.DrawRectangle(&rc, @ptrCast(stroke_brush), stroke_w, null);
        },
    }
}

// ---------------------------------------------------------------------------
// Label rendering (simple; DirectWrite not required for scaffolding)
// ---------------------------------------------------------------------------

fn drawLabel(
    rt: *d2d.ID2D1RenderTarget,
    dwrite_factory: *dwrite.IDWriteFactory,
    font_family: FontFamily,
    text_brush: *d2d.ID2D1SolidColorBrush,
    text: [*c]const u8,
    font_size_pt: f32,
    center_x: f32,
    center_y: f32,
    max_w: f32,
) void {
    if (text == null) return;
    const text_slice = std.mem.span(text);
    if (text_slice.len == 0) return;

    // Build a temporary wide string for DirectWrite.
    var arena_buf: [1024]u8 = undefined;
    var arena = std.heap.FixedBufferAllocator.init(&arena_buf);
    const alloc = arena.allocator();
    const wide = std.unicode.utf8ToUtf16LeAllocZ(alloc, text_slice) catch return;
    defer alloc.free(wide);

    var format: ?*dwrite.IDWriteTextFormat = null;
    const hr = dwrite_factory.CreateTextFormat(
        fontFamilyNameW(font_family),
        null,
        dwrite.DWRITE_FONT_WEIGHT_NORMAL,
        dwrite.DWRITE_FONT_STYLE_NORMAL,
        dwrite.DWRITE_FONT_STRETCH_NORMAL,
        font_size_pt,
        &locale_name_w,
        @ptrCast(&format),
    );
    if (hr < 0 or format == null) return;
    defer _ = format.?.IUnknown.Release();

    _ = format.?.SetTextAlignment(dwrite.DWRITE_TEXT_ALIGNMENT_CENTER);
    _ = format.?.SetParagraphAlignment(dwrite.DWRITE_PARAGRAPH_ALIGNMENT_CENTER);

    const half_w = max_w / 2.0;
    const half_h: f32 = font_size_pt * 1.4;
    const text_rect = rectF(center_x - half_w, center_y - half_h, center_x + half_w, center_y + half_h);

    rt.DrawText(
        wide.ptr,
        @intCast(wide.len),
        format.?,
        &text_rect,
        @ptrCast(text_brush),
        d2d.D2D1_DRAW_TEXT_OPTIONS_NONE,
        dwrite.DWRITE_MEASURING_MODE_NATURAL,
    );
}

fn drawLabelAligned(
    rt: *d2d.ID2D1RenderTarget,
    dwrite_factory: *dwrite.IDWriteFactory,
    font_family: FontFamily,
    text_brush: *d2d.ID2D1SolidColorBrush,
    text: [*c]const u8,
    font_size_pt: f32,
    center_x: f32,
    center_y: f32,
    max_w: f32,
    h_align: dwrite.DWRITE_TEXT_ALIGNMENT,
) void {
    if (text == null) return;
    const text_slice = std.mem.span(text);
    if (text_slice.len == 0) return;

    var arena_buf: [1024]u8 = undefined;
    var arena = std.heap.FixedBufferAllocator.init(&arena_buf);
    const alloc = arena.allocator();
    const wide = std.unicode.utf8ToUtf16LeAllocZ(alloc, text_slice) catch return;
    defer alloc.free(wide);

    var format: ?*dwrite.IDWriteTextFormat = null;
    const hr = dwrite_factory.CreateTextFormat(
        fontFamilyNameW(font_family),
        null,
        dwrite.DWRITE_FONT_WEIGHT_NORMAL,
        dwrite.DWRITE_FONT_STYLE_NORMAL,
        dwrite.DWRITE_FONT_STRETCH_NORMAL,
        font_size_pt,
        &locale_name_w,
        @ptrCast(&format),
    );
    if (hr < 0 or format == null) return;
    defer _ = format.?.IUnknown.Release();

    _ = format.?.SetTextAlignment(h_align);
    _ = format.?.SetParagraphAlignment(dwrite.DWRITE_PARAGRAPH_ALIGNMENT_CENTER);

    const half_w = max_w / 2.0;
    const half_h: f32 = font_size_pt * 1.4;
    const text_rect = rectF(center_x - half_w, center_y - half_h, center_x + half_w, center_y + half_h);

    rt.DrawText(
        wide.ptr,
        @intCast(wide.len),
        format.?,
        &text_rect,
        @ptrCast(text_brush),
        d2d.D2D1_DRAW_TEXT_OPTIONS_NONE,
        dwrite.DWRITE_MEASURING_MODE_NATURAL,
    );
}

fn fontFamilyNameW(family: FontFamily) [*:0]const u16 {
    return switch (family) {
        .lato => &font_family_lato_w,
        .segoe_ui => &font_family_segoe_ui_w,
        .arial => &font_family_arial_w,
        .consolas => &font_family_consolas_w,
    };
}

// ---------------------------------------------------------------------------
// Selection outline + handles
// ---------------------------------------------------------------------------

fn drawSelectionOutline(
    rt: *d2d.ID2D1RenderTarget,
    l: f32,
    t: f32,
    r: f32,
    b: f32,
    sel_brush: *d2d.ID2D1SolidColorBrush,
    zoom: f64,
) void {
    const stroke_w: f32 = @floatCast(2.0 / zoom);
    // Expand slightly outside the object bounds.
    const pad: f32 = @floatCast(4.0 / zoom);
    rt.DrawRectangle(
        &rectF(l - pad, t - pad, r + pad, b + pad),
        @ptrCast(sel_brush),
        stroke_w,
        null,
    );
}

fn drawResizeHandles(
    rt: *d2d.ID2D1RenderTarget,
    rect: hit_test.Rect,
    vp: Viewport,
    fill_brush: *d2d.ID2D1SolidColorBrush,
    stroke_brush: *d2d.ID2D1SolidColorBrush,
) void {
    const handle_half: f32 = 5.0;
    const stroke_w: f32 = 1.0;
    for (hit_test.handlesForRect(rect)) |h| {
        const sp = vp.canvasToScreen(h.cx, h.cy);
        const hx: f32 = @floatCast(sp.x);
        const hy: f32 = @floatCast(sp.y);
        const hr = rectF(hx - handle_half, hy - handle_half, hx + handle_half, hy + handle_half);
        rt.FillRectangle(&hr, @ptrCast(fill_brush));
        rt.DrawRectangle(&hr, @ptrCast(stroke_brush), stroke_w, null);
    }
}

fn drawPointHandle(
    rt: *d2d.ID2D1RenderTarget,
    x: f32,
    y: f32,
    fill_brush: *d2d.ID2D1SolidColorBrush,
    stroke_brush: *d2d.ID2D1SolidColorBrush,
) void {
    const handle_half: f32 = 4.0;
    const stroke_w: f32 = 1.0;
    const rect = rectF(x - handle_half, y - handle_half, x + handle_half, y + handle_half);
    rt.FillRectangle(&rect, @ptrCast(fill_brush));
    rt.DrawRectangle(&rect, @ptrCast(stroke_brush), stroke_w, null);
}

// ---------------------------------------------------------------------------
// Edge rendering
// ---------------------------------------------------------------------------

fn drawEdge(
    factory: *d2d_factory_type,
    rt: *d2d.ID2D1RenderTarget,
    dwrite_factory: *dwrite.IDWriteFactory,
    font_family: FontFamily,
    graph: *const StudioEditableGraph,
    edge: *const StudioEditableEdge,
    vp: Viewport,
    stroke_brush: *d2d.ID2D1SolidColorBrush,
    label_fill_brush: *d2d.ID2D1SolidColorBrush,
    text_brush: *d2d.ID2D1SolidColorBrush,
) void {
    // Detect self-message (source_id == target_id).
    const is_self = edge.source_id != null and edge.target_id != null and
        std.mem.eql(u8, std.mem.span(edge.source_id), std.mem.span(edge.target_id));

    if (is_self) {
        // Draw a right-hook: three segments forming a loop to the right.
        const src = findNodeOrSubgraphCentre(graph, edge.source_id) orelse return;
        const src_s = vp.canvasToScreen(src[0], src[1]);
        const cx: f32 = @floatCast(src_s.x);
        const cy: f32 = @floatCast(src_s.y);
        const zoom_scale: f32 = @floatCast(@max(vp.zoom, 0.25));
        const stroke_w: f32 = @max(1.0, edge.thickness * zoom_scale);
        const hook_w: f32 = 36.0 * zoom_scale;
        const hook_h: f32 = 24.0 * zoom_scale;
        const tip_len: f32 = @max(8.0, stroke_w * 4.5);

        // Build dashed style if needed (bit 0 of line_style = dashed).
        var dash_style: ?*d2d.ID2D1StrokeStyle = null;
        if (edge.line_style & 1 != 0) {
            const props = d2d.D2D1_STROKE_STYLE_PROPERTIES{
                .startCap = d2d.D2D1_CAP_STYLE_FLAT,
                .endCap = d2d.D2D1_CAP_STYLE_FLAT,
                .dashCap = d2d.D2D1_CAP_STYLE_FLAT,
                .lineJoin = d2d.D2D1_LINE_JOIN_MITER,
                .miterLimit = 10.0,
                .dashStyle = d2d.D2D1_DASH_STYLE_DASH,
                .dashOffset = 0.0,
            };
            var s: *d2d.ID2D1StrokeStyle = undefined;
            if (factory.CreateStrokeStyle(&props, null, 0, &s) >= 0) dash_style = s;
        }
        defer if (dash_style) |s| {
            _ = s.IUnknown.Release();
        };

        // Three segments: right → down → left-to-return (with arrow at bottom).
        const p0 = point2F(cx, cy);
        const p1 = point2F(cx + hook_w, cy);
        const p2 = point2F(cx + hook_w, cy + hook_h);
        const p3_full = point2F(cx, cy + hook_h);
        // Shorten last segment so arrowhead base lands at cx.
        const p3_short = point2F(cx + tip_len, cy + hook_h);

        rt.DrawLine(p0, p1, @ptrCast(stroke_brush), stroke_w, @ptrCast(dash_style));
        rt.DrawLine(p1, p2, @ptrCast(stroke_brush), stroke_w, @ptrCast(dash_style));
        if (edge.has_arrow != 0) {
            rt.DrawLine(p2, p3_short, @ptrCast(stroke_brush), stroke_w, @ptrCast(dash_style));
            if (edge.line_style & 2 != 0) {
                drawOpenArrowTip(factory, rt, stroke_brush, p2.x, p2.y, p3_full.x, p3_full.y, stroke_w);
            } else {
                drawArrowTip(factory, rt, stroke_brush, p2.x, p2.y, p3_full.x, p3_full.y, stroke_w);
            }
        } else if (edge.target_end_style == 10) {
            rt.DrawLine(p2, p3_full, @ptrCast(stroke_brush), stroke_w, @ptrCast(dash_style));
            drawCrossMarker(rt, stroke_brush, p3_full.x, p3_full.y, stroke_w);
        } else {
            rt.DrawLine(p2, p3_full, @ptrCast(stroke_brush), stroke_w, @ptrCast(dash_style));
        }

        const label_pts = EdgeScreenEndpoints{ .src_x = cx, .src_y = cy, .dst_x = cx + hook_w, .dst_y = cy + hook_h };
        drawEdgeLabel(rt, dwrite_factory, font_family, edge, label_pts, label_fill_brush, text_brush);
        return;
    }

    const points = edgeScreenEndpoints(graph, edge, vp) orelse return;
    drawEdgeSegment(factory, rt, points.src_x, points.src_y, points.dst_x, points.dst_y, edge, stroke_brush, 1.0, vp.zoom);
    drawEdgeLabel(rt, dwrite_factory, font_family, edge, points, label_fill_brush, text_brush);
}

const EdgeScreenEndpoints = struct {
    src_x: f32,
    src_y: f32,
    dst_x: f32,
    dst_y: f32,
};

fn edgeScreenEndpoints(
    graph: *const StudioEditableGraph,
    edge: *const StudioEditableEdge,
    vp: Viewport,
) ?EdgeScreenEndpoints {
    // Find source and target centres in canvas space.
    const src = findNodeOrSubgraphCentre(graph, edge.source_id) orelse return null;
    const dst = findNodeOrSubgraphCentre(graph, edge.target_id) orelse return null;

    // Clip endpoints to node/subgraph boundaries so lines start/end at the
    // border rather than going through the object body.
    const src_rect = hit_test.findNodeOrSubgraphRect(graph, edge.source_id);
    const dst_rect = hit_test.findNodeOrSubgraphRect(graph, edge.target_id);
    const clipped_src = if (src_rect) |sr| hit_test.clipPointToRectBorder(src[0], src[1], dst[0], dst[1], sr) else src;
    const clipped_dst = if (dst_rect) |dr| hit_test.clipPointToRectBorder(dst[0], dst[1], src[0], src[1], dr) else dst;

    const src_s = vp.canvasToScreen(clipped_src[0], clipped_src[1]);
    const dst_s = vp.canvasToScreen(clipped_dst[0], clipped_dst[1]);

    return .{
        .src_x = @floatCast(src_s.x),
        .src_y = @floatCast(src_s.y),
        .dst_x = @floatCast(dst_s.x),
        .dst_y = @floatCast(dst_s.y),
    };
}

fn drawEdgeSegment(
    factory: *d2d_factory_type,
    rt: *d2d.ID2D1RenderTarget,
    src_x: f32,
    src_y: f32,
    dst_x: f32,
    dst_y: f32,
    edge: *const StudioEditableEdge,
    stroke_brush: *d2d.ID2D1SolidColorBrush,
    stroke_scale: f32,
    zoom: f64,
) void {
    const zoom_scale: f32 = @floatCast(@max(zoom, 0.25));
    const stroke_w: f32 = @max(1.0, edge.thickness * zoom_scale * stroke_scale);
    const tip_len: f32 = @max(10.0, stroke_w * 5.0);

    // Build a dashed stroke style when bit 0 of line_style is set.
    var dash_style: ?*d2d.ID2D1StrokeStyle = null;
    if (edge.line_style & 1 != 0) {
        const props = d2d.D2D1_STROKE_STYLE_PROPERTIES{
            .startCap = d2d.D2D1_CAP_STYLE_FLAT,
            .endCap = d2d.D2D1_CAP_STYLE_FLAT,
            .dashCap = d2d.D2D1_CAP_STYLE_FLAT,
            .lineJoin = d2d.D2D1_LINE_JOIN_MITER,
            .miterLimit = 10.0,
            .dashStyle = d2d.D2D1_DASH_STYLE_DASH,
            .dashOffset = 0.0,
        };
        var s: *d2d.ID2D1StrokeStyle = undefined;
        if (factory.CreateStrokeStyle(&props, null, 0, &s) >= 0) {
            dash_style = s;
        }
    }
    defer if (dash_style) |s| {
        _ = s.IUnknown.Release();
    };

    // Shorten the line endpoints so it stops at each arrowhead base, not the tip.
    const seg_dx = dst_x - src_x;
    const seg_dy = dst_y - src_y;
    const seg_len = @sqrt(seg_dx * seg_dx + seg_dy * seg_dy);
    var line_src_x = src_x;
    var line_src_y = src_y;
    var line_dst_x = dst_x;
    var line_dst_y = dst_y;
    if (seg_len > 1.0) {
        const ux = seg_dx / seg_len;
        const uy = seg_dy / seg_len;
        if (edge.has_arrow != 0) {
            line_dst_x = dst_x - ux * tip_len;
            line_dst_y = dst_y - uy * tip_len;
        }
        if (edge.has_source_arrow != 0) {
            line_src_x = src_x + ux * tip_len;
            line_src_y = src_y + uy * tip_len;
        }
    }
    rt.DrawLine(
        point2F(line_src_x, line_src_y),
        point2F(line_dst_x, line_dst_y),
        @ptrCast(stroke_brush),
        stroke_w,
        @ptrCast(dash_style),
    );

    // Arrow tip at target end.
    if (edge.has_arrow != 0) {
        if (edge.line_style & 2 != 0) {
            drawOpenArrowTip(factory, rt, stroke_brush, src_x, src_y, dst_x, dst_y, stroke_w);
        } else {
            drawArrowTip(factory, rt, stroke_brush, src_x, src_y, dst_x, dst_y, stroke_w);
        }
    } else if (edge.target_end_style == 10) {
        // Cross marker (-x / --x style).
        drawCrossMarker(rt, stroke_brush, dst_x, dst_y, stroke_w);
    }
    // Arrow tip at source end.
    if (edge.has_source_arrow != 0) {
        drawArrowTip(factory, rt, stroke_brush, dst_x, dst_y, src_x, src_y, stroke_w);
    }
}

fn drawEdgeLabel(
    rt: *d2d.ID2D1RenderTarget,
    dwrite_factory: *dwrite.IDWriteFactory,
    font_family: FontFamily,
    edge: *const StudioEditableEdge,
    points: EdgeScreenEndpoints,
    label_fill_brush: *d2d.ID2D1SolidColorBrush,
    text_brush: *d2d.ID2D1SolidColorBrush,
) void {
    if (edge.label == null) return;

    const text = std.mem.trim(u8, std.mem.span(edge.label), " \t\r\n");
    if (text.len == 0) return;

    const dx = points.dst_x - points.src_x;
    const dy = points.dst_y - points.src_y;
    const seg_len = @sqrt(dx * dx + dy * dy);
    if (seg_len < 1.0) return;

    const nx = -dy / seg_len;
    const ny = dx / seg_len;
    const center_x = (points.src_x + points.dst_x) / 2.0 + nx * 12.0;
    const center_y = (points.src_y + points.dst_y) / 2.0 + ny * 12.0;

    const font_size: f32 = std.math.clamp(edge.label_font_size, 6.0, 48.0);
    const text_w = @max(26.0, @as(f32, @floatFromInt(text.len)) * font_size * 0.56);
    const text_h: f32 = font_size * 1.55;
    const pad_x: f32 = 7.0;
    const pad_y: f32 = 3.0;
    const bg = rectF(
        center_x - text_w / 2.0 - pad_x,
        center_y - text_h / 2.0 - pad_y,
        center_x + text_w / 2.0 + pad_x,
        center_y + text_h / 2.0 + pad_y,
    );

    label_fill_brush.SetColor(&d2dColorRgba(255, 255, 255, 235));
    rt.FillRectangle(&bg, @ptrCast(label_fill_brush));
    text_brush.SetColor(&d2dColorRgb(32, 32, 32));

    drawLabel(rt, dwrite_factory, font_family, text_brush, edge.label, font_size, center_x, center_y, text_w);
}

fn drawSelectionPass(
    factory: *d2d_factory_type,
    rt: *d2d.ID2D1RenderTarget,
    graph: *const StudioEditableGraph,
    vp: Viewport,
    selection: Selection,
    sel_brush: *d2d.ID2D1SolidColorBrush,
    handle_fill_brush: *d2d.ID2D1SolidColorBrush,
) void {
    switch (selection.kind) {
        .node => {
            if (selection.index >= graph.node_count or graph.nodes == null) return;
            const node = &graph.nodes[selection.index];
            const sr = canvasRectToScreen(vp, node.x, node.y, node.width, node.height);
            sel_brush.SetColor(&d2dColorRgba(0, 120, 215, 220));
            drawSelectionOutline(rt, sr.l, sr.t, sr.r, sr.b, sel_brush, vp.zoom);
            handle_fill_brush.SetColor(&d2dColorRgb(255, 255, 255));
            sel_brush.SetColor(&d2dColorRgb(0, 120, 215));
            drawResizeHandles(rt, hit_test.nodeRect(@ptrCast(node)), vp, handle_fill_brush, sel_brush);
        },
        .subgraph => {
            if (selection.index >= graph.subgraph_count or graph.subgraphs == null) return;
            const sg = &graph.subgraphs[selection.index];
            const sr = canvasRectToScreen(vp, sg.x, sg.y, sg.width, sg.height);
            sel_brush.SetColor(&d2dColorRgba(0, 120, 215, 220));
            drawSelectionOutline(rt, sr.l, sr.t, sr.r, sr.b, sel_brush, vp.zoom);

            if (graph.nodes != null) {
                sel_brush.SetColor(&d2dColorRgba(0, 120, 215, 150));
                for (graph.nodes[0..graph.node_count], 0..) |*node, idx| {
                    if (!state.nodeBelongsToSubgraph(graph, idx, selection.index)) continue;
                    const node_sr = canvasRectToScreen(vp, node.x, node.y, node.width, node.height);
                    drawSelectionOutline(rt, node_sr.l, node_sr.t, node_sr.r, node_sr.b, sel_brush, vp.zoom);
                }
            }

            if (graph.subgraphs != null) {
                sel_brush.SetColor(&d2dColorRgba(0, 120, 215, 150));
                for (graph.subgraphs[0..graph.subgraph_count], 0..) |*child, idx| {
                    if (!state.subgraphBelongsToSubgraph(graph, idx, selection.index)) continue;
                    const child_sr = canvasRectToScreen(vp, child.x, child.y, child.width, child.height);
                    drawSelectionOutline(rt, child_sr.l, child_sr.t, child_sr.r, child_sr.b, sel_brush, vp.zoom);
                }
            }

            if (graph.edges != null) {
                sel_brush.SetColor(&d2dColorRgba(0, 120, 215, 180));
                for (graph.edges[0..graph.edge_count], 0..) |*edge, idx| {
                    if (!state.edgeBelongsToSubgraph(graph, idx, selection.index)) continue;
                    const points = edgeScreenEndpoints(graph, @ptrCast(edge), vp) orelse continue;
                    drawEdgeSegment(factory, rt, points.src_x, points.src_y, points.dst_x, points.dst_y, @ptrCast(edge), sel_brush, 1.35, vp.zoom);
                }
            }

            handle_fill_brush.SetColor(&d2dColorRgb(255, 255, 255));
            sel_brush.SetColor(&d2dColorRgb(0, 120, 215));
            drawResizeHandles(rt, hit_test.subgraphRect(@ptrCast(sg)), vp, handle_fill_brush, sel_brush);
        },
        .edge => {
            if (selection.index >= graph.edge_count or graph.edges == null) return;
            const edge = &graph.edges[selection.index];
            const points = edgeScreenEndpoints(graph, @ptrCast(edge), vp) orelse return;
            sel_brush.SetColor(&d2dColorRgba(0, 120, 215, 220));
            drawEdgeSegment(factory, rt, points.src_x, points.src_y, points.dst_x, points.dst_y, @ptrCast(edge), sel_brush, 1.8, vp.zoom);
            handle_fill_brush.SetColor(&d2dColorRgb(255, 255, 255));
            sel_brush.SetColor(&d2dColorRgb(0, 120, 215));
            drawPointHandle(rt, points.src_x, points.src_y, handle_fill_brush, sel_brush);
            drawPointHandle(rt, points.dst_x, points.dst_y, handle_fill_brush, sel_brush);
        },
        else => {},
    }
}

fn drawHoverPass(
    factory: *d2d_factory_type,
    rt: *d2d.ID2D1RenderTarget,
    graph: *const StudioEditableGraph,
    vp: Viewport,
    hover: Selection,
    selection: Selection,
    hover_brush: *d2d.ID2D1SolidColorBrush,
) void {
    if (hover.kind == .none) return;
    if (hover.kind == selection.kind and hover.index == selection.index) return;

    switch (hover.kind) {
        .node => {
            if (hover.index >= graph.node_count or graph.nodes == null) return;
            const node = &graph.nodes[hover.index];
            const sr = canvasRectToScreen(vp, node.x, node.y, node.width, node.height);
            hover_brush.SetColor(&d2dColorRgba(0, 120, 215, 120));
            drawSelectionOutline(rt, sr.l, sr.t, sr.r, sr.b, hover_brush, vp.zoom);
        },
        .subgraph => {
            if (hover.index >= graph.subgraph_count or graph.subgraphs == null) return;
            const sg = &graph.subgraphs[hover.index];
            const sr = canvasRectToScreen(vp, sg.x, sg.y, sg.width, sg.height);
            hover_brush.SetColor(&d2dColorRgba(0, 120, 215, 110));
            drawSelectionOutline(rt, sr.l, sr.t, sr.r, sr.b, hover_brush, vp.zoom);
        },
        .edge => {
            if (hover.index >= graph.edge_count or graph.edges == null) return;
            const edge = &graph.edges[hover.index];
            const points = edgeScreenEndpoints(graph, @ptrCast(edge), vp) orelse return;
            hover_brush.SetColor(&d2dColorRgba(0, 120, 215, 150));
            drawEdgeSegment(factory, rt, points.src_x, points.src_y, points.dst_x, points.dst_y, @ptrCast(edge), hover_brush, 1.35, vp.zoom);
        },
        else => {},
    }
}

/// Draw an open chevron arrowhead (two lines forming a ">") at (dx, dy) pointing
/// away from (sx, sy).  Used for sequence diagram "async" messages (-))).
fn drawOpenArrowTip(
    _: *d2d_factory_type,
    rt: *d2d.ID2D1RenderTarget,
    brush: *d2d.ID2D1SolidColorBrush,
    sx: f32,
    sy: f32,
    dx: f32,
    dy: f32,
    stroke_w: f32,
) void {
    const len = @sqrt((dx - sx) * (dx - sx) + (dy - sy) * (dy - sy));
    if (len < 1.0) return;
    const ux = (dx - sx) / len;
    const uy = (dy - sy) / len;
    const tip_len: f32 = @max(10.0, stroke_w * 5.0);
    const tip_w: f32 = tip_len * 0.5;
    const base_x = dx - ux * tip_len;
    const base_y = dy - uy * tip_len;
    // Perpendicular unit vector.
    const px = -uy;
    const py = ux;
    const left_x = base_x + px * tip_w;
    const left_y = base_y + py * tip_w;
    const right_x = base_x - px * tip_w;
    const right_y = base_y - py * tip_w;
    rt.DrawLine(point2F(left_x, left_y), point2F(dx, dy), @ptrCast(brush), stroke_w, null);
    rt.DrawLine(point2F(right_x, right_y), point2F(dx, dy), @ptrCast(brush), stroke_w, null);
}

/// Draw a cross (×) marker at (px, py).  Used for sequence diagram "lost
/// message" (-x / --x) arrows.
fn drawCrossMarker(
    rt: *d2d.ID2D1RenderTarget,
    brush: *d2d.ID2D1SolidColorBrush,
    px: f32,
    py: f32,
    stroke_w: f32,
) void {
    const r: f32 = @max(5.0, stroke_w * 3.5);
    rt.DrawLine(point2F(px - r, py - r), point2F(px + r, py + r), @ptrCast(brush), stroke_w, null);
    rt.DrawLine(point2F(px + r, py - r), point2F(px - r, py + r), @ptrCast(brush), stroke_w, null);
}

fn drawArrowTip(
    factory: *d2d_factory_type,
    rt: *d2d.ID2D1RenderTarget,
    brush: *d2d.ID2D1SolidColorBrush,
    sx: f32,
    sy: f32,
    dx: f32,
    dy: f32,
    stroke_w: f32,
) void {
    const len = @sqrt((dx - sx) * (dx - sx) + (dy - sy) * (dy - sy));
    if (len < 1.0) return;
    const ux = (dx - sx) / len;
    const uy = (dy - sy) / len;
    const tip_len: f32 = @max(10.0, stroke_w * 5.0);
    const tip_w: f32 = tip_len * 0.5;
    const base_x = dx - ux * tip_len;
    const base_y = dy - uy * tip_len;
    const left_x = base_x - uy * tip_w;
    const left_y = base_y + ux * tip_w;
    const right_x = base_x + uy * tip_w;
    const right_y = base_y - ux * tip_w;

    var path_raw: *d2d.ID2D1PathGeometry = undefined;
    if (factory.CreatePathGeometry(&path_raw) < 0) return;
    defer _ = path_raw.IUnknown.Release();

    var sink_raw: *d2d.ID2D1GeometrySink = undefined;
    if (path_raw.Open(&sink_raw) < 0) return;
    sink_raw.ID2D1SimplifiedGeometrySink.BeginFigure(point2F(dx, dy), d2d_common.D2D1_FIGURE_BEGIN_FILLED);
    sink_raw.AddLine(point2F(left_x, left_y));
    sink_raw.AddLine(point2F(right_x, right_y));
    sink_raw.ID2D1SimplifiedGeometrySink.EndFigure(d2d_common.D2D1_FIGURE_END_CLOSED);
    if (sink_raw.ID2D1SimplifiedGeometrySink.Close() < 0) {
        _ = sink_raw.IUnknown.Release();
        return;
    }
    _ = sink_raw.IUnknown.Release();
    rt.FillGeometry(@ptrCast(path_raw), @ptrCast(brush), null);
}

fn findNodeOrSubgraphCentre(graph: *const StudioEditableGraph, id: [*c]const u8) ?[2]f64 {
    if (id == null) return null;
    const id_s = std.mem.span(id);
    if (graph.node_count > 0 and graph.nodes != null) {
        for (graph.nodes[0..graph.node_count]) |*n| {
            if (n.id != null and std.mem.eql(u8, std.mem.span(n.id), id_s)) {
                return .{ n.x + n.width / 2.0, n.y + n.height / 2.0 };
            }
        }
    }
    if (graph.subgraph_count > 0 and graph.subgraphs != null) {
        for (graph.subgraphs[0..graph.subgraph_count]) |*sg| {
            if (sg.id != null and std.mem.eql(u8, std.mem.span(sg.id), id_s)) {
                return .{ sg.x + sg.width / 2.0, sg.y + sg.height / 2.0 };
            }
        }
    }
    return null;
}

// ---------------------------------------------------------------------------
// Public draw entry point
// ---------------------------------------------------------------------------

pub const DrawContext = struct {
    d2d_factory: *d2d_factory_type,
    render_target: *d2d.ID2D1RenderTarget,
    dwrite_factory: *dwrite.IDWriteFactory,
    font_family: FontFamily,
    viewport_width: f32,
    viewport_height: f32,
};

/// Draw the entire freeform canvas for one frame.
pub fn drawCanvas(
    ctx: *const DrawContext,
    graph: *const StudioEditableGraph,
    vp: Viewport,
    selection: Selection,
    hover: Selection,
    insertion: state.InsertionState,
    link_mouse_x: f32,
    link_mouse_y: f32,
) void {
    const rt = ctx.render_target;

    // Background.
    var bg_color = d2dColor(graph.background);
    // Ensure no fully-transparent background.
    bg_color.a = 1.0;
    rt.Clear(&bg_color);

    // Create reusable brushes.
    var fill_brush: ?*d2d.ID2D1SolidColorBrush = null;
    var stroke_brush: ?*d2d.ID2D1SolidColorBrush = null;
    var text_brush: ?*d2d.ID2D1SolidColorBrush = null;
    var sel_brush: ?*d2d.ID2D1SolidColorBrush = null;
    var handle_fill_brush: ?*d2d.ID2D1SolidColorBrush = null;
    var hover_brush: ?*d2d.ID2D1SolidColorBrush = null;
    defer {
        if (fill_brush) |b| _ = b.IUnknown.Release();
        if (stroke_brush) |b| _ = b.IUnknown.Release();
        if (text_brush) |b| _ = b.IUnknown.Release();
        if (sel_brush) |b| _ = b.IUnknown.Release();
        if (handle_fill_brush) |b| _ = b.IUnknown.Release();
        if (hover_brush) |b| _ = b.IUnknown.Release();
    }

    // Initial brush creation (colour set per-object below).
    makeBrush(rt, d2dColorRgb(200, 200, 200), &fill_brush);
    makeBrush(rt, d2dColorRgb(80, 80, 80), &stroke_brush);
    makeBrush(rt, d2dColorRgb(0, 0, 0), &text_brush);
    makeBrush(rt, d2dColorRgba(0, 120, 215, 200), &sel_brush);
    makeBrush(rt, d2dColorRgb(255, 255, 255), &handle_fill_brush);
    makeBrush(rt, d2dColorRgba(0, 120, 215, 110), &hover_brush);

    const fb = fill_brush orelse return;
    const sb = stroke_brush orelse return;
    const tb = text_brush orelse return;
    const selb = sel_brush orelse return;
    const hfb = handle_fill_brush orelse return;
    const hovb = hover_brush orelse return;

    // Visible page boundary for the configured working canvas.
    if (graph.width > 0 and graph.height > 0) {
        sb.SetColor(&d2dColorRgb(206, 206, 206));
        const page_rect = canvasRectToScreen(vp, 0.0, 0.0, graph.width, graph.height);
        rt.DrawRectangle(&rectF(page_rect.l, page_rect.t, page_rect.r, page_rect.b), @ptrCast(sb), 1.0, null);
    }

    // --- Subgraphs (drawn behind nodes) ---
    if (graph.subgraph_count > 0 and graph.subgraphs != null) {
        const subgraphs = graph.subgraphs[0..graph.subgraph_count];
        for (subgraphs) |*sg| {
            const sr = canvasRectToScreen(vp, sg.x, sg.y, sg.width, sg.height);
            const stroke_w: f32 = @floatCast(@as(f64, sg.stroke_width) * vp.zoom);
            const radius: f32 = @floatCast(sg.corner_radius * vp.zoom);

            fb.SetColor(&d2dColor(sg.fill));
            sb.SetColor(&d2dColor(sg.stroke));
            const rr = rounded_rect(sr.l, sr.t, sr.r, sr.b, radius);
            rt.FillRoundedRectangle(&rr, @ptrCast(fb));
            rt.DrawRoundedRectangle(&rr, @ptrCast(sb), stroke_w, null);

            // Title.
            if (sg.title != null) {
                tb.SetColor(&d2dColor(sg.title_color));
                const font_size = std.math.clamp(sg.title_font_size, 6.0, 48.0);
                const v_pad: f32 = font_size * 0.85;
                const h_inset: f32 = 8.0;
                const sg_center_x = (sr.l + sr.r) / 2.0;
                const sg_w = (sr.r - sr.l) - h_inset * 2.0;
                const lp: state.SubgraphLabelPosition = @enumFromInt(sg.title_position);
                const title_cy: f32 = switch (lp) {
                    .bottom_left, .bottom_center, .bottom_right => sr.b - v_pad,
                    else => sr.t + v_pad,
                };
                const h_align: dwrite.DWRITE_TEXT_ALIGNMENT = switch (lp) {
                    .top_left, .bottom_left => dwrite.DWRITE_TEXT_ALIGNMENT_LEADING,
                    .top_right, .bottom_right => dwrite.DWRITE_TEXT_ALIGNMENT_TRAILING,
                    else => dwrite.DWRITE_TEXT_ALIGNMENT_CENTER,
                };
                drawLabelAligned(rt, ctx.dwrite_factory, ctx.font_family, tb, sg.title, font_size, sg_center_x, title_cy, sg_w, h_align);
            }
        }
    }

    // --- Edges ---
    if (graph.edge_count > 0 and graph.edges != null) {
        const edges = graph.edges[0..graph.edge_count];
        for (edges, 0..) |*edge, idx| {
            var color = d2dColor(edge.color);
            color.a = 1.0;
            sb.SetColor(&color);
            _ = idx;
            drawEdge(ctx.d2d_factory, rt, ctx.dwrite_factory, ctx.font_family, graph, edge, vp, sb, fb, tb);
        }
    }

    // --- Nodes ---
    if (graph.node_count > 0 and graph.nodes != null) {
        const nodes = graph.nodes[0..graph.node_count];
        for (nodes, 0..) |*node, idx| {
            fb.SetColor(&d2dColor(node.fill));
            sb.SetColor(&d2dColor(node.stroke));
            drawNodeShape(ctx.d2d_factory, rt, fb, sb, node, vp);

            const has_subtitle = node.subtitle != null and std.mem.span(node.subtitle.?).len > 0;
            const has_attrs = node.attributes_text != null and std.mem.span(node.attributes_text.?).len > 0;
            const has_body = has_subtitle or has_attrs;

            const sr_n = canvasRectToScreen(vp, node.x, node.y, node.width, node.height);
            const stroke_w_n: f32 = @floatCast(@as(f64, node.stroke_width) * vp.zoom);
            const font_size_n = std.math.clamp(node.label_font_size, 6.0, 48.0);
            const max_w_n: f32 = @floatCast(node.width * vp.zoom);
            const cx_n = (sr_n.l + sr_n.r) / 2.0;

            if (has_body) {
                // Estimate header height in screen space from font size.
                const hdr_h_screen: f32 = font_size_n * 3.2;
                const divider_y = sr_n.t + hdr_h_screen;

                // Always paint body_fill over the lower panel so the background is correct.
                if (divider_y < sr_n.b - 2.0) {
                    fb.SetColor(&d2dColor(node.body_fill));
                    const body_rect = rectF(sr_n.l + stroke_w_n, divider_y, sr_n.r - stroke_w_n, sr_n.b - stroke_w_n);
                    rt.FillRectangle(&body_rect, @ptrCast(fb));
                    fb.SetColor(&d2dColor(node.fill));
                }

                // Divider line.
                if (divider_y < sr_n.b - 2.0) {
                    sb.SetColor(&d2dColor(node.stroke));
                    rt.DrawLine(point2F(sr_n.l, divider_y), point2F(sr_n.r, divider_y), @ptrCast(sb), stroke_w_n, null);
                }

                // Label in header region.
                if (node.label != null) {
                    tb.SetColor(&d2dColor(node.label_color));
                    const hdr_cy = (sr_n.t + @min(divider_y, sr_n.b)) / 2.0;
                    drawLabel(rt, ctx.dwrite_factory, ctx.font_family, tb, node.label, font_size_n, cx_n, hdr_cy, max_w_n);
                }

                // Subtitle in body region.
                if (has_subtitle and divider_y < sr_n.b - 4.0) {
                    tb.SetColor(&d2dColor(node.label_color));
                    const body_available = sr_n.b - divider_y;
                    var line_h = font_size_n * 1.5;
                    if (line_h > body_available) line_h = body_available * 0.8;
                    const subtitle_cy = divider_y + line_h / 2.0 + 6.0;
                    const sub_font = font_size_n * 0.85;
                    drawLabel(rt, ctx.dwrite_factory, ctx.font_family, tb, node.subtitle, sub_font, cx_n, subtitle_cy, max_w_n - 8.0);
                }

                // Attributes text below subtitle.
                if (has_attrs and divider_y < sr_n.b - 4.0) {
                    tb.SetColor(&d2dColor(node.label_color));
                    const sub_offset: f32 = if (has_subtitle) font_size_n * 1.5 + 6.0 else 6.0;
                    const attrs_cy = divider_y + sub_offset + font_size_n;
                    drawLabel(rt, ctx.dwrite_factory, ctx.font_family, tb, node.attributes_text, font_size_n * 0.8, cx_n, attrs_cy, max_w_n - 8.0);
                }
            } else {
                // No body — label centered in the full node rect.
                // For actor shape (14), place the label inside the lower name-box area.
                if (node.label != null) {
                    tb.SetColor(&d2dColor(node.label_color));
                    const label_cy = if (node.shape == 14)
                        sr_n.t + (sr_n.b - sr_n.t) * 0.80 // 80% down = in the name-box
                    else
                        (sr_n.t + sr_n.b) / 2.0;
                    drawLabel(rt, ctx.dwrite_factory, ctx.font_family, tb, node.label, font_size_n, cx_n, label_cy, max_w_n);
                }
            }
            _ = idx;
        }
    }

    drawHoverPass(ctx.d2d_factory, rt, graph, vp, hover, selection, hovb);
    drawSelectionPass(ctx.d2d_factory, rt, graph, vp, selection, selb, hfb);

    // --- Link preview (connector_source mode) ---
    if (insertion.kind == .connector_source) {
        if (insertion.connector_source_id) |src_id| {
            const id_slice = std.mem.span(src_id);
            var src_sx: ?f32 = null;
            var src_sy: ?f32 = null;

            if (graph.node_count > 0 and graph.nodes != null) {
                for (graph.nodes[0..graph.node_count]) |*n| {
                    if (n.id == null) continue;
                    if (std.mem.eql(u8, std.mem.span(n.id), id_slice)) {
                        const s = vp.canvasToScreen(n.x + n.width / 2.0, n.y + n.height / 2.0);
                        src_sx = @floatCast(s.x);
                        src_sy = @floatCast(s.y);
                        break;
                    }
                }
            }
            if (src_sx == null and graph.subgraph_count > 0 and graph.subgraphs != null) {
                for (graph.subgraphs[0..graph.subgraph_count]) |*sg| {
                    if (sg.id == null) continue;
                    if (std.mem.eql(u8, std.mem.span(sg.id), id_slice)) {
                        const s = vp.canvasToScreen(sg.x + sg.width / 2.0, sg.y + sg.height / 2.0);
                        src_sx = @floatCast(s.x);
                        src_sy = @floatCast(s.y);
                        break;
                    }
                }
            }

            if (src_sx) |scx| {
                const scy = src_sy.?;
                var link_brush: ?*d2d.ID2D1SolidColorBrush = null;
                makeBrush(rt, d2dColorRgba(30, 100, 220, 200), &link_brush);
                defer {
                    if (link_brush) |b| _ = b.IUnknown.Release();
                }
                if (link_brush) |lb| {
                    rt.DrawLine(point2F(scx, scy), point2F(link_mouse_x, link_mouse_y), @ptrCast(lb), 2.0, null);
                    const end_ell = ellipseF(link_mouse_x, link_mouse_y, 5.0, 5.0);
                    rt.FillEllipse(&end_ell, @ptrCast(lb));
                }
            }
        }
    }
}
