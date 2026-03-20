/// Direct2D drawing for the freeform canvas.
/// Renders nodes, subgraphs, edges, labels, selection outlines, and resize handles.
const std = @import("std");
const win32 = @import("win32");
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
    parallelogram = 2,
    diamond = 3,
    stadium = 4, // pill / capsule
    cylinder = 5,
    circle = 6,
    other = 0xffff_ffff,
    _,
};

fn drawNodeShape(
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
        .diamond => {
            // Draw a diamond as a rotated square approximated with 4 lines.
            const cx = (sr.l + sr.r) / 2.0;
            const cy = (sr.t + sr.b) / 2.0;
            // Use a path geometry via 4 DrawLine calls.
            rt.DrawLine(point2F(cx, sr.t), point2F(sr.r, cy), @ptrCast(stroke_brush), stroke_w, null);
            rt.DrawLine(point2F(sr.r, cy), point2F(cx, sr.b), @ptrCast(stroke_brush), stroke_w, null);
            rt.DrawLine(point2F(cx, sr.b), point2F(sr.l, cy), @ptrCast(stroke_brush), stroke_w, null);
            rt.DrawLine(point2F(sr.l, cy), point2F(cx, sr.t), @ptrCast(stroke_brush), stroke_w, null);
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
        &[_:0]u16{ 'L', 'a', 't', 'o' },
        null,
        dwrite.DWRITE_FONT_WEIGHT_NORMAL,
        dwrite.DWRITE_FONT_STYLE_NORMAL,
        dwrite.DWRITE_FONT_STRETCH_NORMAL,
        font_size_pt,
        &[_:0]u16{ 'e', 'n', '-', 'U', 'S' },
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
    rt: *d2d.ID2D1RenderTarget,
    graph: *const StudioEditableGraph,
    edge: *const StudioEditableEdge,
    vp: Viewport,
    stroke_brush: *d2d.ID2D1SolidColorBrush,
) void {
    const points = edgeScreenEndpoints(graph, edge, vp) orelse return;
    drawEdgeSegment(rt, points.src_x, points.src_y, points.dst_x, points.dst_y, edge, stroke_brush, 1.0);
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
    rt: *d2d.ID2D1RenderTarget,
    src_x: f32,
    src_y: f32,
    dst_x: f32,
    dst_y: f32,
    edge: *const StudioEditableEdge,
    stroke_brush: *d2d.ID2D1SolidColorBrush,
    stroke_scale: f32,
) void {
    const stroke_w: f32 = @max(1.0, @as(f32, @floatCast(edge.thickness)) * stroke_scale);
    rt.DrawLine(
        point2F(src_x, src_y),
        point2F(dst_x, dst_y),
        @ptrCast(stroke_brush),
        stroke_w,
        null,
    );

    // Arrow tip at target end.
    if (edge.has_arrow != 0) {
        drawArrowTip(
            rt,
            stroke_brush,
            src_x,
            src_y,
            dst_x,
            dst_y,
            stroke_w,
        );
    }
    // Arrow tip at source end.
    if (edge.has_source_arrow != 0) {
        drawArrowTip(
            rt,
            stroke_brush,
            dst_x,
            dst_y,
            src_x,
            src_y,
            stroke_w,
        );
    }
}

fn drawSelectionPass(
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
            handle_fill_brush.SetColor(&d2dColorRgb(255, 255, 255));
            sel_brush.SetColor(&d2dColorRgb(0, 120, 215));
            drawResizeHandles(rt, hit_test.subgraphRect(@ptrCast(sg)), vp, handle_fill_brush, sel_brush);
        },
        .edge => {
            if (selection.index >= graph.edge_count or graph.edges == null) return;
            const edge = &graph.edges[selection.index];
            const points = edgeScreenEndpoints(graph, @ptrCast(edge), vp) orelse return;
            sel_brush.SetColor(&d2dColorRgba(0, 120, 215, 220));
            drawEdgeSegment(rt, points.src_x, points.src_y, points.dst_x, points.dst_y, @ptrCast(edge), sel_brush, 1.8);
            handle_fill_brush.SetColor(&d2dColorRgb(255, 255, 255));
            sel_brush.SetColor(&d2dColorRgb(0, 120, 215));
            drawPointHandle(rt, points.src_x, points.src_y, handle_fill_brush, sel_brush);
            drawPointHandle(rt, points.dst_x, points.dst_y, handle_fill_brush, sel_brush);
        },
        else => {},
    }
}

fn drawHoverPass(
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
            drawEdgeSegment(rt, points.src_x, points.src_y, points.dst_x, points.dst_y, @ptrCast(edge), hover_brush, 1.35);
        },
        else => {},
    }
}

fn drawArrowTip(
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
    const tip_len: f32 = @max(8.0, stroke_w * 4.0);
    const tip_w: f32 = tip_len * 0.45;
    const base_x = dx - ux * tip_len;
    const base_y = dy - uy * tip_len;
    const left_x = base_x - uy * tip_w;
    const left_y = base_y + ux * tip_w;
    const right_x = base_x + uy * tip_w;
    const right_y = base_y - ux * tip_w;
    rt.DrawLine(point2F(dx, dy), point2F(left_x, left_y), @ptrCast(brush), stroke_w, null);
    rt.DrawLine(point2F(dx, dy), point2F(right_x, right_y), @ptrCast(brush), stroke_w, null);
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
    render_target: *d2d.ID2D1RenderTarget,
    dwrite_factory: *dwrite.IDWriteFactory,
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
                const title_s = vp.canvasToScreen(sg.title_x, sg.title_y);
                drawLabel(rt, ctx.dwrite_factory, tb, sg.title, sg.title_font_size * @as(f32, @floatCast(vp.zoom)), @floatCast(title_s.x), @floatCast(title_s.y), sr.r - sr.l);
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
            drawEdge(rt, graph, edge, vp, sb);
        }
    }

    // --- Nodes ---
    if (graph.node_count > 0 and graph.nodes != null) {
        const nodes = graph.nodes[0..graph.node_count];
        for (nodes, 0..) |*node, idx| {
            fb.SetColor(&d2dColor(node.fill));
            sb.SetColor(&d2dColor(node.stroke));
            drawNodeShape(rt, fb, sb, node, vp);

            // Label.
            if (node.label != null) {
                tb.SetColor(&d2dColor(node.label_color));
                const centre_s = vp.canvasToScreen(node.x + node.width / 2.0, node.y + node.height / 2.0);
                const max_w: f32 = @floatCast(node.width * vp.zoom);
                drawLabel(rt, ctx.dwrite_factory, tb, node.label, node.label_font_size * @as(f32, @floatCast(vp.zoom)), @floatCast(centre_s.x), @floatCast(centre_s.y), max_w);
            }
            _ = idx;
        }
    }

    drawHoverPass(rt, graph, vp, hover, selection, hovb);
    drawSelectionPass(rt, graph, vp, selection, selb, hfb);
}
