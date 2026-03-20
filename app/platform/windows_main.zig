const std = @import("std");
const win32 = @import("win32");
const merrow = @import("merrow");
const merrow_lexer = merrow.lexer;
const windows_app_state = @import("windows/app_state.zig");
const windows_common = @import("windows/common.zig");
const windows_constants = @import("windows/constants.zig");
const windows_dpi = @import("windows/dpi.zig");
const windows_document = @import("windows/document.zig");
const windows_editor = @import("windows/editor.zig");
const windows_layout = @import("windows/layout.zig");
const windows_status_bar = @import("windows/status_bar.zig");
const windows_toolbar = @import("windows/toolbar.zig");

const com = win32.system.com;
const foundation = win32.foundation;
const d2d = win32.graphics.direct2d;
const d2d_common = win32.graphics.direct2d.common;
const dw = win32.graphics.direct_write;
const dxgi_common = win32.graphics.dxgi.common;
const gdi = win32.graphics.gdi;
const loader = win32.system.library_loader;
const controls = win32.ui.controls;
const dialogs = win32.ui.controls.dialogs;
const rich_edit = win32.ui.controls.rich_edit;
const dpi = win32.ui.hi_dpi;
const mouse = win32.ui.input.keyboard_and_mouse;
const ui = win32.ui.windows_and_messaging;

const c_allocator = std.heap.c_allocator;
const class_name = windows_constants.class_name;
const preview_class_name = windows_constants.preview_class_name;
const window_title = windows_constants.window_title;
const static_class = windows_constants.static_class;
const edit_class = windows_constants.edit_class;
const rich_edit_class = windows_constants.rich_edit_class;
const button_class = windows_constants.button_class;
const toolbar_class = windows_constants.toolbar_class;
const status_placeholder = windows_constants.status_placeholder;
const file_menu_label = windows_constants.file_menu_label;
const menu_open_label = windows_constants.menu_open_label;
const menu_save_label = windows_constants.menu_save_label;
const menu_save_as_label = windows_constants.menu_save_as_label;
const open_dialog_title = windows_constants.open_dialog_title;
const save_dialog_title = windows_constants.save_dialog_title;
const default_extension = windows_constants.default_extension;
const mermaid_dialog_filter = windows_constants.mermaid_dialog_filter;
const initial_source = windows_constants.initial_source;
const menu_id_open = windows_constants.menu_id_open;
const menu_id_save = windows_constants.menu_id_save;
const menu_id_save_as = windows_constants.menu_id_save_as;
const toolbar_id_reserved_1 = windows_constants.toolbar_id_reserved_1;
const toolbar_id_reserved_2 = windows_constants.toolbar_id_reserved_2;
const toolbar_id_reserved_3 = windows_constants.toolbar_id_reserved_3;
const toolbar_slot_1_label = windows_constants.toolbar_slot_1_label;
const toolbar_slot_2_label = windows_constants.toolbar_slot_2_label;
const toolbar_slot_3_label = windows_constants.toolbar_slot_3_label;
const Layout = windows_constants.Layout;
const ViewAnchor = windows_constants.ViewAnchor;

const ChildWindows = windows_app_state.ChildWindows;
const PreviewRenderer = windows_app_state.PreviewRenderer;

const StudioColor = extern struct {
    r: u8,
    g: u8,
    b: u8,
    a: u8,
};

const StudioScene = extern struct {
    width: f64,
    height: f64,
    background: StudioColor,
    subgraphs: [*c]StudioSubgraph,
    subgraph_count: usize,
    nodes: [*c]StudioNode,
    node_count: usize,
    edges: [*c]StudioEdge,
    edge_count: usize,
    edge_labels: [*c]StudioEdgeLabel,
    edge_label_count: usize,
};

const StudioPoint = extern struct {
    x: f64,
    y: f64,
};

const StudioSubgraph = extern struct {
    x: f64,
    y: f64,
    width: f64,
    height: f64,
    corner_radius: f64,
    fill: StudioColor,
    stroke: StudioColor,
    stroke_width: f32,
    title: [*c]const u8,
    title_x: f64,
    title_y: f64,
    title_font_size: f32,
    title_color: StudioColor,
};

const StudioNode = extern struct {
    shape: u32,
    x: f64,
    y: f64,
    width: f64,
    height: f64,
    fill: StudioColor,
    stroke: StudioColor,
    stroke_width: f32,
    label: [*c]const u8,
    label_color: StudioColor,
    label_font_size: f32,
    max_text_width: f64,
    subtitle: [*c]const u8,
    attributes_text: [*c]const u8,
    methods_text: [*c]const u8,
    body_fill: StudioColor,
    body_text_color: StudioColor,
};

const StudioEdge = extern struct {
    points: [*c]StudioPoint,
    point_count: usize,
    color: StudioColor,
    thickness: f32,
    line_style: u32,
    has_arrow: u8,
    has_source_arrow: u8,
    target_from: StudioPoint,
    target_tip: StudioPoint,
    source_from: StudioPoint,
    source_tip: StudioPoint,
};

const StudioEdgeLabel = extern struct {
    text: [*c]const u8,
    x: f64,
    y: f64,
    half_w: f64,
    half_h: f64,
    font_size: f32,
    color: StudioColor,
};

extern fn merrow_studio_build_scene(source_ptr: [*]const u8, source_len: u32) callconv(.c) ?*StudioScene;
extern fn merrow_studio_free_scene(scene: ?*StudioScene) callconv(.c) void;
extern fn merrow_studio_check_mermaid_syntax(source_ptr: [*]const u8, source_len: u32, out_message: [*]u8, out_message_len: u32) callconv(.c) c_int;
extern fn merrow_studio_apply_command(source_ptr: [*]const u8, source_len: u32, command_ptr: [*]const u8, command_len: u32, context_id_ptr: [*]const u8, context_id_len: u32, out_context_id: [*]u8, out_context_id_len: u32, out_context_display: [*]u8, out_context_display_len: u32, out_message: [*]u8, out_message_len: u32) callconv(.c) [*c]u8;
extern fn merrow_studio_shuffle_diagram(source_ptr: [*]const u8, source_len: u32, out_message: [*]u8, out_message_len: u32) callconv(.c) [*c]u8;
extern fn merrow_studio_free_string(text: [*c]u8) callconv(.c) void;

var child_windows = ChildWindows{};
var preview_renderer = PreviewRenderer{};
var main_window: ?foundation.HWND = null;
var current_scene: ?*StudioScene = null;
var current_document_path: ?[]u8 = null;
var private_font_path: ?[:0]u8 = null;
var rich_edit_module: ?@TypeOf(loader.LoadLibraryA("Riched20.dll").?) = null;
var editor_font: ?gdi.HFONT = null;
var shell_font: ?gdi.HFONT = null;
var status_font: ?gdi.HFONT = null;
var current_status_message: ?[]u8 = null;
var is_document_dirty = false;
var suppress_editor_change = false;

const EditorTheme = windows_editor.EditorTheme;
const EditorTokenStyle = windows_editor.EditorTokenStyle;
const editor_theme = windows_editor.editor_theme;

const empty_c_string = windows_constants.empty_c_string;
const font_family_name_w = windows_constants.font_family_name_w;
const locale_name_w = windows_constants.locale_name_w;
const setPosFlagsBits = windows_common.setPosFlagsBits;
const redrawFlagsBits = windows_common.redrawFlagsBits;
const makeRedrawFlags = windows_common.makeRedrawFlags;
const styleBits = windows_common.styleBits;
const exStyleBits = windows_common.exStyleBits;
const makeStyle = windows_common.makeStyle;
const makeExStyle = windows_common.makeExStyle;
const scrollMaskBits = windows_common.scrollMaskBits;
const makeScrollMask = windows_common.makeScrollMask;
const hrFailed = windows_common.hrFailed;
const dupeSentinel = windows_common.dupeSentinel;
const fileExistsAbsolute = windows_common.fileExistsAbsolute;
const resolveRepoPathZ = windows_common.resolveRepoPathZ;
const releaseUnknown = windows_common.releaseUnknown;
const fileDialogFlagBits = windows_common.fileDialogFlagBits;
const makeFileDialogFlags = windows_common.makeFileDialogFlags;

fn freeCurrentDocumentPath() void {
    windows_document.freeCurrentDocumentPath(c_allocator, &current_document_path);
}

fn freeCurrentStatusMessage() void {
    if (current_status_message) |message| {
        c_allocator.free(message);
        current_status_message = null;
    }
}

fn registerPreviewFont() void {
    if (private_font_path != null) return;

    const font_path = resolveRepoPathZ(c_allocator, "fonts/Lato-Regular.ttf") catch return;
    const flags = gdi.FR_PRIVATE;

    if (gdi.AddFontResourceExA(font_path.ptr, flags, null) <= 0) {
        c_allocator.free(font_path);
        return;
    }

    private_font_path = font_path;
}

fn unregisterPreviewFont() void {
    if (private_font_path) |font_path| {
        _ = gdi.RemoveFontResourceExA(font_path.ptr, @intFromEnum(gdi.FR_PRIVATE), null);
        c_allocator.free(font_path);
        private_font_path = null;
    }
}

fn ensureRichEditLibrary() bool {
    return windows_editor.ensureRichEditLibrary(&rich_edit_module);
}

fn releaseEditorFont() void {
    windows_editor.releaseEditorFont(&editor_font);
}

fn releaseShellFont() void {
    windows_dpi.releaseShellFont(&shell_font, &status_font);
}

fn ensureEditorFont() ?gdi.HFONT {
    return windows_editor.ensureEditorFont(&editor_font);
}

fn ensureShellFont() ?gdi.HFONT {
    return windows_dpi.ensureShellFont(&shell_font, &status_font);
}

fn sendEditorMessage(message: u32, w_param: usize, l_param: isize) foundation.LRESULT {
    return ui.SendMessageA(child_windows.editor, message, w_param, l_param);
}

fn richMaskBits(mask: rich_edit.CFM_MASK) u32 {
    return @bitCast(mask);
}

fn makeRichMask(bits: u32) rich_edit.CFM_MASK {
    return @bitCast(bits);
}

fn richEffectsBits(effects: rich_edit.CFE_EFFECTS) u32 {
    return @bitCast(effects);
}

fn makeRichEffects(bits: u32) rich_edit.CFE_EFFECTS {
    return @bitCast(bits);
}

fn setEditorSelection(start: i32, end: i32) void {
    var range = rich_edit.CHARRANGE{ .cpMin = start, .cpMax = end };
    _ = sendEditorMessage(rich_edit.EM_EXSETSEL, 0, @bitCast(@intFromPtr(&range)));
}

fn applyEditorFormat(start: i32, end: i32, text_color: u32, back_color: ?u32, bold: bool) void {
    var format = std.mem.zeroes(rich_edit.CHARFORMAT2A);
    format.Base.cbSize = @sizeOf(rich_edit.CHARFORMAT2A);
    var mask_bits = richMaskBits(rich_edit.CFM_COLOR);
    if (back_color != null) mask_bits |= richMaskBits(rich_edit.CFM_BACKCOLOR);
    if (bold) mask_bits |= richMaskBits(rich_edit.CFM_BOLD);
    format.Base.dwMask = makeRichMask(mask_bits);
    format.Base.dwEffects = if (bold) rich_edit.CFE_EFFECTS{ .BOLD = 1 } else makeRichEffects(0);
    format.Base.crTextColor = text_color;
    format.crBackColor = back_color orelse editor_theme.background;
    setEditorSelection(start, end);
    _ = sendEditorMessage(rich_edit.EM_SETCHARFORMAT, rich_edit.SCF_SELECTION, @bitCast(@intFromPtr(&format)));
}

fn applyEditorBaseStyle() void {
    var format = std.mem.zeroes(rich_edit.CHARFORMAT2A);
    format.Base.cbSize = @sizeOf(rich_edit.CHARFORMAT2A);
    format.Base.dwMask = makeRichMask(
        richMaskBits(rich_edit.CFM_COLOR) |
            richMaskBits(rich_edit.CFM_BACKCOLOR) |
            richMaskBits(rich_edit.CFM_FACE) |
            richMaskBits(rich_edit.CFM_SIZE),
    );
    format.Base.dwEffects = makeRichEffects(0);
    format.Base.crTextColor = editor_theme.default_text;
    format.crBackColor = editor_theme.background;
    format.Base.yHeight = 220;
    @memcpy(format.Base.szFaceName[0..8], "Consolas"[0..8]);
    setEditorSelection(0, -1);
    _ = sendEditorMessage(rich_edit.EM_SETCHARFORMAT, rich_edit.SCF_ALL, @bitCast(@intFromPtr(&format)));
}

fn applyEditorSyntaxHighlight(text: []const u8, syntax_ok: bool) void {
    windows_editor.applyEditorSyntaxHighlight(child_windows.editor, text, syntax_ok);
}

fn configureEditorControl() void {
    windows_editor.configureEditorControl(child_windows.editor, &editor_font);
}

fn configureShellFonts() void {
    windows_dpi.configureShellFonts(child_windows, &shell_font, &status_font);
}

fn initializeToolbarControl() void {
    windows_toolbar.initializeToolbarControl(child_windows.toolbar);
}

fn setCurrentDocumentPath(path: ?[]const u8) void {
    windows_document.setCurrentDocumentPath(c_allocator, &current_document_path, path, main_window, is_document_dirty);
}

fn setDocumentDirty(dirty: bool) void {
    windows_document.setDocumentDirty(c_allocator, &is_document_dirty, dirty, main_window, current_document_path);
}

fn updateWindowTitle() void {
    windows_document.updateWindowTitle(c_allocator, main_window, current_document_path, is_document_dirty);
}

fn setEditorText(text: []const u8) void {
    windows_editor.setEditorText(c_allocator, child_windows.editor, &suppress_editor_change, text);
}

fn installMenuBar(hwnd: ?foundation.HWND) bool {
    return windows_toolbar.installMenuBar(hwnd);
}

fn chooseDocumentPath(save: bool) ?[]u8 {
    return windows_document.chooseDocumentPath(c_allocator, main_window, current_document_path, save);
}

fn loadSourceFromPath(path: []const u8) ![]u8 {
    return windows_document.loadSourceFromPath(c_allocator, path);
}

fn saveSourceToPath(path: []const u8, source: []const u8) !void {
    return windows_document.saveSourceToPath(path, source);
}

fn openDocumentFromDialog() void {
    const selected_path = chooseDocumentPath(false) orelse return;
    defer c_allocator.free(selected_path);

    const source = loadSourceFromPath(selected_path) catch {
        setStatusMessage("Failed to open file");
        return;
    };
    defer c_allocator.free(source);

    setEditorText(source);
    setCurrentDocumentPath(selected_path);
    updateEditorDerivedState();
    setDocumentDirty(false);
    setStatusMessage("Opened Mermaid source");
}

fn saveDocumentToPath(path: []const u8) bool {
    const source = getEditorText(c_allocator) catch {
        setStatusMessage("Failed to read editor text");
        return false;
    };
    defer c_allocator.free(source);

    saveSourceToPath(path, source) catch {
        setStatusMessage("Failed to save file");
        return false;
    };

    setCurrentDocumentPath(path);
    setDocumentDirty(false);
    setStatusMessage("Saved Mermaid source");
    return true;
}

fn saveDocument(save_as: bool) void {
    if (!save_as) {
        if (current_document_path) |path| {
            _ = saveDocumentToPath(path);
            return;
        }
    }

    const selected_path = chooseDocumentPath(true) orelse return;
    defer c_allocator.free(selected_path);
    _ = saveDocumentToPath(selected_path);
}

fn replaceCurrentScene(next_scene: ?*StudioScene) void {
    if (current_scene) |scene| {
        merrow_studio_free_scene(scene);
    }
    current_scene = next_scene;
}

fn direct2dColor(color: StudioColor) d2d_common.D2D_COLOR_F {
    return .{
        .r = @as(f32, @floatFromInt(color.r)) / 255.0,
        .g = @as(f32, @floatFromInt(color.g)) / 255.0,
        .b = @as(f32, @floatFromInt(color.b)) / 255.0,
        .a = @as(f32, @floatFromInt(color.a)) / 255.0,
    };
}

fn previewBrush() ?*d2d.ID2D1Brush {
    const brush = preview_renderer.brush orelse return null;
    return @ptrCast(brush);
}

fn setBrushColor(color: StudioColor) void {
    const brush = preview_renderer.brush orelse return;
    var d2d_color = direct2dColor(color);
    brush.SetColor(&d2d_color);
}

fn scalePoint(x: f64, y: f64, scale: f64, offset_x: f64, offset_y: f64) d2d_common.D2D_POINT_2F {
    return .{
        .x = @floatCast(x * scale + offset_x),
        .y = @floatCast(y * scale + offset_y),
    };
}

fn scaleRect(x: f64, y: f64, width: f64, height: f64, scale: f64, offset_x: f64, offset_y: f64) d2d_common.D2D_RECT_F {
    return .{
        .left = @floatCast(x * scale + offset_x),
        .top = @floatCast(y * scale + offset_y),
        .right = @floatCast((x + width) * scale + offset_x),
        .bottom = @floatCast((y + height) * scale + offset_y),
    };
}

fn drawArrowHead(
    render_target: *const d2d.ID2D1RenderTarget,
    brush: *d2d.ID2D1Brush,
    tip: d2d_common.D2D_POINT_2F,
    from: d2d_common.D2D_POINT_2F,
    stroke_width: f32,
) void {
    const dx = @as(f64, tip.x) - @as(f64, from.x);
    const dy = @as(f64, tip.y) - @as(f64, from.y);
    const length = @sqrt(dx * dx + dy * dy);
    if (length < 0.001) return;

    const ux = dx / length;
    const uy = dy / length;
    const px = -uy;
    const py = ux;
    const arrow_len = @max(8.0, @as(f64, stroke_width) * 5.0);
    const arrow_half_width = @max(4.0, @as(f64, stroke_width) * 2.5);
    const base_x = @as(f64, tip.x) - ux * arrow_len;
    const base_y = @as(f64, tip.y) - uy * arrow_len;

    const left = d2d_common.D2D_POINT_2F{
        .x = @floatCast(base_x + px * arrow_half_width),
        .y = @floatCast(base_y + py * arrow_half_width),
    };
    const right = d2d_common.D2D_POINT_2F{
        .x = @floatCast(base_x - px * arrow_half_width),
        .y = @floatCast(base_y - py * arrow_half_width),
    };

    const factory = preview_renderer.factory orelse return;
    var path_geometry_raw: *d2d.ID2D1PathGeometry = undefined;
    if (hrFailed(factory.CreatePathGeometry(&path_geometry_raw))) return;
    var path_geometry: ?*d2d.ID2D1PathGeometry = path_geometry_raw;
    defer releaseUnknown(&path_geometry);

    var sink_raw: *d2d.ID2D1GeometrySink = undefined;
    if (hrFailed(path_geometry_raw.Open(&sink_raw))) return;
    var sink: ?*d2d.ID2D1GeometrySink = sink_raw;
    defer releaseUnknown(&sink);

    sink.?.ID2D1SimplifiedGeometrySink.BeginFigure(tip, d2d_common.D2D1_FIGURE_BEGIN_FILLED);
    sink.?.AddLine(left);
    sink.?.AddLine(right);
    sink.?.ID2D1SimplifiedGeometrySink.EndFigure(d2d_common.D2D1_FIGURE_END_CLOSED);
    if (hrFailed(sink.?.ID2D1SimplifiedGeometrySink.Close())) return;

    render_target.FillGeometry(@ptrCast(path_geometry), brush, null);
}

fn ensurePreviewFactory() bool {
    if (preview_renderer.factory == null) {
        var factory: ?*d2d.ID2D1Factory = null;
        const hr = d2d.D2D1CreateFactory(
            d2d.D2D1_FACTORY_TYPE_SINGLE_THREADED,
            d2d.IID_ID2D1Factory,
            null,
            @ptrCast(&factory),
        );
        if (hrFailed(hr) or factory == null) return false;
        preview_renderer.factory = factory;
    }

    if (preview_renderer.write_factory == null) {
        var write_factory: ?*dw.IDWriteFactory = null;
        const write_hr = dw.DWriteCreateFactory(
            dw.DWRITE_FACTORY_TYPE_SHARED,
            dw.IID_IDWriteFactory,
            @ptrCast(&write_factory),
        );
        if (hrFailed(write_hr) or write_factory == null) return false;
        preview_renderer.write_factory = write_factory;
    }

    return true;
}

fn currentPreviewPixelSize(hwnd: ?foundation.HWND) ?d2d_common.D2D_SIZE_U {
    var rect = std.mem.zeroes(foundation.RECT);
    if (ui.GetClientRect(hwnd, &rect) == 0) return null;
    const width = rect.right - rect.left;
    const height = rect.bottom - rect.top;
    if (width <= 0 or height <= 0) return null;
    return .{ .width = @intCast(width), .height = @intCast(height) };
}

fn mouseCoordFromLParam(l_param: foundation.LPARAM) struct { x: i32, y: i32 } {
    const raw: usize = @bitCast(l_param);
    const x: i16 = @bitCast(@as(u16, @truncate(raw & 0xffff)));
    const y: i16 = @bitCast(@as(u16, @truncate((raw >> 16) & 0xffff)));
    return .{ .x = x, .y = y };
}

fn wheelDeltaFromWParam(w_param: foundation.WPARAM) i16 {
    const raw: usize = @bitCast(w_param);
    return @bitCast(@as(u16, @truncate((raw >> 16) & 0xffff)));
}

fn viewportAnchor(hwnd: ?foundation.HWND) ViewAnchor {
    const size = currentPreviewPixelSize(hwnd) orelse return .{ .x = 0, .y = 0 };
    return .{ .x = @divTrunc(@as(i32, @intCast(size.width)), 2), .y = @divTrunc(@as(i32, @intCast(size.height)), 2) };
}

fn viewportAnchorFromWheel(hwnd: ?foundation.HWND, l_param: foundation.LPARAM) ViewAnchor {
    const size = currentPreviewPixelSize(hwnd) orelse return .{ .x = 0, .y = 0 };
    var point = foundation.POINT{
        .x = mouseCoordFromLParam(l_param).x,
        .y = mouseCoordFromLParam(l_param).y,
    };
    if (gdi.ScreenToClient(hwnd, &point) == 0) return viewportAnchor(hwnd);

    return .{
        .x = std.math.clamp(point.x, 0, @max(0, @as(i32, @intCast(size.width)) - 1)),
        .y = std.math.clamp(point.y, 0, @max(0, @as(i32, @intCast(size.height)) - 1)),
    };
}

fn scenePixelWidth() i32 {
    if (current_scene) |scene| {
        const extent = sceneContentExtent(scene).width;
        return @max(0, @as(i32, @intFromFloat(@ceil(extent * preview_renderer.zoom))));
    }
    return 0;
}

fn scenePixelHeight() i32 {
    if (current_scene) |scene| {
        const extent = sceneContentExtent(scene).height;
        return @max(0, @as(i32, @intFromFloat(@ceil(extent * preview_renderer.zoom))));
    }
    return 0;
}

fn sceneContentExtent(scene: *const StudioScene) struct { width: f64, height: f64 } {
    const content_margin_x = 24.0;
    const content_margin_y = 56.0;

    var max_x = scene.width;
    var max_y = scene.height;

    var subgraph_index: usize = 0;
    while (subgraph_index < scene.subgraph_count) : (subgraph_index += 1) {
        const subgraph = scene.subgraphs[subgraph_index];
        max_x = @max(max_x, subgraph.x + subgraph.width + content_margin_x);
        max_y = @max(max_y, subgraph.y + subgraph.height + content_margin_y);
        max_x = @max(max_x, subgraph.title_x + 220.0);
        max_y = @max(max_y, subgraph.title_y + @as(f64, subgraph.title_font_size) * 1.8 + 20.0);
    }

    var node_index: usize = 0;
    while (node_index < scene.node_count) : (node_index += 1) {
        const node = scene.nodes[node_index];
        max_x = @max(max_x, node.x + node.width / 2.0 + content_margin_x);
        max_y = @max(max_y, node.y + node.height / 2.0 + content_margin_y);
    }

    var edge_index: usize = 0;
    while (edge_index < scene.edge_count) : (edge_index += 1) {
        const edge = scene.edges[edge_index];
        var point_index: usize = 0;
        while (point_index < edge.point_count) : (point_index += 1) {
            const point = edge.points[point_index];
            max_x = @max(max_x, point.x + content_margin_x);
            max_y = @max(max_y, point.y + content_margin_y);
        }
        max_x = @max(max_x, edge.target_tip.x + content_margin_x);
        max_x = @max(max_x, edge.source_tip.x + content_margin_x);
        max_y = @max(max_y, edge.target_tip.y + content_margin_y);
        max_y = @max(max_y, edge.source_tip.y + content_margin_y);
    }

    var label_index: usize = 0;
    while (label_index < scene.edge_label_count) : (label_index += 1) {
        const label = scene.edge_labels[label_index];
        max_x = @max(max_x, label.x + label.half_w + content_margin_x);
        max_y = @max(max_y, label.y + label.half_h + content_margin_y);
    }

    return .{ .width = max_x, .height = max_y };
}

fn updatePreviewScrollbars(hwnd: ?foundation.HWND) void {
    const size = currentPreviewPixelSize(hwnd) orelse return;
    const scene_width = scenePixelWidth();
    const scene_height = scenePixelHeight();
    const page_x: i32 = @intCast(size.width);
    const page_y: i32 = @intCast(size.height);
    const max_x = @max(0, scene_width - page_x);
    const max_y = @max(0, scene_height - page_y);

    preview_renderer.scroll_x = std.math.clamp(preview_renderer.scroll_x, 0, max_x);
    preview_renderer.scroll_y = std.math.clamp(preview_renderer.scroll_y, 0, max_y);

    var x_info = ui.SCROLLINFO{
        .cbSize = @sizeOf(ui.SCROLLINFO),
        .fMask = makeScrollMask(scrollMaskBits(ui.SIF_RANGE) | scrollMaskBits(ui.SIF_PAGE) | scrollMaskBits(ui.SIF_POS) | scrollMaskBits(ui.SIF_DISABLENOSCROLL)),
        .nMin = 0,
        .nMax = @max(0, scene_width - 1),
        .nPage = size.width,
        .nPos = preview_renderer.scroll_x,
        .nTrackPos = 0,
    };
    _ = controls.SetScrollInfo(hwnd, ui.SB_HORZ, &x_info, 1);

    var y_info = ui.SCROLLINFO{
        .cbSize = @sizeOf(ui.SCROLLINFO),
        .fMask = makeScrollMask(scrollMaskBits(ui.SIF_RANGE) | scrollMaskBits(ui.SIF_PAGE) | scrollMaskBits(ui.SIF_POS) | scrollMaskBits(ui.SIF_DISABLENOSCROLL)),
        .nMin = 0,
        .nMax = @max(0, scene_height - 1),
        .nPage = size.height,
        .nPos = preview_renderer.scroll_y,
        .nTrackPos = 0,
    };
    _ = controls.SetScrollInfo(hwnd, ui.SB_VERT, &y_info, 1);
}

fn applyPreviewScroll(hwnd: ?foundation.HWND, bar: ui.SCROLLBAR_CONSTANTS, request: u16) void {
    var info = ui.SCROLLINFO{
        .cbSize = @sizeOf(ui.SCROLLINFO),
        .fMask = makeScrollMask(scrollMaskBits(ui.SIF_ALL)),
        .nMin = 0,
        .nMax = 0,
        .nPage = 0,
        .nPos = 0,
        .nTrackPos = 0,
    };
    if (ui.GetScrollInfo(hwnd, bar, &info) == 0) return;

    const page: i32 = @intCast(info.nPage);
    const max_pos = @max(0, info.nMax - page + 1);
    var next_pos = info.nPos;
    switch (@as(u32, request)) {
        0 => next_pos -= 24,
        1 => next_pos += 24,
        2 => next_pos -= page,
        3 => next_pos += page,
        4, 5 => next_pos = info.nTrackPos,
        else => return,
    }

    next_pos = std.math.clamp(next_pos, 0, max_pos);
    info.fMask = makeScrollMask(scrollMaskBits(ui.SIF_POS));
    info.nPos = next_pos;
    _ = controls.SetScrollInfo(hwnd, bar, &info, 1);

    if (@as(u32, @bitCast(bar)) == @as(u32, @bitCast(ui.SB_HORZ))) {
        preview_renderer.scroll_x = next_pos;
    } else {
        preview_renderer.scroll_y = next_pos;
    }
    requestPreviewRefresh();
}

fn panPreviewBy(hwnd: ?foundation.HWND, delta_x: i32, delta_y: i32) void {
    const size = currentPreviewPixelSize(hwnd) orelse return;
    const scene_width = scenePixelWidth();
    const scene_height = scenePixelHeight();
    const max_x = @max(0, scene_width - @as(i32, @intCast(size.width)));
    const max_y = @max(0, scene_height - @as(i32, @intCast(size.height)));

    preview_renderer.scroll_x = std.math.clamp(preview_renderer.scroll_x + delta_x, 0, max_x);
    preview_renderer.scroll_y = std.math.clamp(preview_renderer.scroll_y + delta_y, 0, max_y);
    requestPreviewRefresh();
}

fn setPreviewZoom(new_zoom: f64, anchor_x: i32, anchor_y: i32) void {
    const clamped_zoom = std.math.clamp(new_zoom, 0.25, 4.0);
    if (@abs(clamped_zoom - preview_renderer.zoom) < 0.001) return;

    const old_zoom = preview_renderer.zoom;
    const world_x = (@as(f64, @floatFromInt(preview_renderer.scroll_x + anchor_x))) / old_zoom;
    const world_y = (@as(f64, @floatFromInt(preview_renderer.scroll_y + anchor_y))) / old_zoom;

    preview_renderer.zoom = clamped_zoom;
    preview_renderer.scroll_x = @intFromFloat(@round(world_x * clamped_zoom - @as(f64, @floatFromInt(anchor_x))));
    preview_renderer.scroll_y = @intFromFloat(@round(world_y * clamped_zoom - @as(f64, @floatFromInt(anchor_y))));
    refreshStatusDisplay();
    requestPreviewRefresh();
}

fn stepPreviewZoom(hwnd: ?foundation.HWND, zoom_in: bool) void {
    const anchor = viewportAnchor(hwnd);
    const factor: f64 = if (zoom_in) 1.1 else (1.0 / 1.1);
    setPreviewZoom(preview_renderer.zoom * factor, anchor.x, anchor.y);
}

fn stepPreviewZoomAtAnchor(anchor_x: i32, anchor_y: i32, zoom_in: bool) void {
    const factor: f64 = if (zoom_in) 1.1 else (1.0 / 1.1);
    setPreviewZoom(preview_renderer.zoom * factor, anchor_x, anchor_y);
}

fn ensurePreviewRenderTarget(hwnd: ?foundation.HWND) bool {
    if (!ensurePreviewFactory()) return false;

    const pixel_size = currentPreviewPixelSize(hwnd) orelse return false;
    const factory = preview_renderer.factory orelse return false;

    if (preview_renderer.render_target) |render_target| {
        if (hrFailed(render_target.Resize(&pixel_size))) {
            releaseUnknown(&preview_renderer.brush);
            releaseUnknown(&preview_renderer.render_target);
        } else {
            return true;
        }
    }

    var target_properties = d2d.D2D1_RENDER_TARGET_PROPERTIES{
        .type = d2d.D2D1_RENDER_TARGET_TYPE_DEFAULT,
        .pixelFormat = .{
            .format = dxgi_common.DXGI_FORMAT_UNKNOWN,
            .alphaMode = d2d_common.D2D1_ALPHA_MODE_IGNORE,
        },
        .dpiX = 0,
        .dpiY = 0,
        .usage = d2d.D2D1_RENDER_TARGET_USAGE_NONE,
        .minLevel = d2d.D2D1_FEATURE_LEVEL_DEFAULT,
    };
    var hwnd_properties = d2d.D2D1_HWND_RENDER_TARGET_PROPERTIES{
        .hwnd = hwnd,
        .pixelSize = pixel_size,
        .presentOptions = d2d.D2D1_PRESENT_OPTIONS_NONE,
    };

    var render_target: ?*d2d.ID2D1HwndRenderTarget = null;
    if (hrFailed(factory.CreateHwndRenderTarget(&target_properties, &hwnd_properties, @ptrCast(&render_target))) or render_target == null) {
        return false;
    }
    preview_renderer.render_target = render_target;

    var brush_color = direct2dColor(.{ .r = 0, .g = 0, .b = 0, .a = 255 });
    var brush: ?*d2d.ID2D1SolidColorBrush = null;
    if (hrFailed(render_target.?.ID2D1RenderTarget.CreateSolidColorBrush(&brush_color, null, @ptrCast(&brush))) or brush == null) {
        releaseUnknown(&preview_renderer.render_target);
        return false;
    }
    preview_renderer.brush = brush;
    preview_renderer.render_target.?.ID2D1RenderTarget.SetTextAntialiasMode(d2d.D2D1_TEXT_ANTIALIAS_MODE_GRAYSCALE);
    return true;
}

fn drawSceneToPreview(hwnd: ?foundation.HWND) void {
    if (!ensurePreviewRenderTarget(hwnd)) return;

    const render_target = preview_renderer.render_target orelse return;
    const brush = previewBrush() orelse return;
    render_target.ID2D1RenderTarget.BeginDraw();

    if (current_scene) |scene| {
        var background = direct2dColor(scene.background);
        render_target.ID2D1RenderTarget.Clear(&background);
        const scale = preview_renderer.zoom;
        const offset_x = -@as(f64, @floatFromInt(preview_renderer.scroll_x));
        const offset_y = -@as(f64, @floatFromInt(preview_renderer.scroll_y));

        var subgraph_index: usize = 0;
        while (subgraph_index < scene.subgraph_count) : (subgraph_index += 1) {
            const subgraph = scene.subgraphs[subgraph_index];
            var rounded_rect = d2d.D2D1_ROUNDED_RECT{
                .rect = scaleRect(subgraph.x, subgraph.y, subgraph.width, subgraph.height, scale, offset_x, offset_y),
                .radiusX = @floatCast(subgraph.corner_radius * scale),
                .radiusY = @floatCast(subgraph.corner_radius * scale),
            };
            setBrushColor(subgraph.fill);
            render_target.ID2D1RenderTarget.FillRoundedRectangle(&rounded_rect, brush);
            setBrushColor(subgraph.stroke);
            render_target.ID2D1RenderTarget.DrawRoundedRectangle(&rounded_rect, brush, @max(1.0, subgraph.stroke_width * @as(f32, @floatCast(scale))), null);

            const title_inset_left = @max(0.0, subgraph.title_x - subgraph.x);
            const title_width = @max(40.0, subgraph.width - title_inset_left - 12.0);
            const title_height = @max(18.0, @as(f64, subgraph.title_font_size) * 1.8);
            const title_rect = scaleRect(
                subgraph.title_x,
                subgraph.title_y - @as(f64, subgraph.title_font_size) * 0.9,
                title_width,
                title_height,
                scale,
                offset_x,
                offset_y,
            );
            drawSceneText(
                &render_target.ID2D1RenderTarget,
                subgraph.title,
                @max(10.0, subgraph.title_font_size * @as(f32, @floatCast(scale))),
                subgraph.title_color,
                title_rect,
                dw.DWRITE_TEXT_ALIGNMENT_LEADING,
                dw.DWRITE_PARAGRAPH_ALIGNMENT_NEAR,
            );
        }

        var edge_index: usize = 0;
        while (edge_index < scene.edge_count) : (edge_index += 1) {
            const edge = scene.edges[edge_index];
            setBrushColor(edge.color);
            const stroke_width = @max(1.0, edge.thickness * @as(f32, @floatCast(scale)));

            if (edge.has_source_arrow != 0) {
                const source_from = scalePoint(edge.source_from.x, edge.source_from.y, scale, offset_x, offset_y);
                const source_tip = scalePoint(edge.source_tip.x, edge.source_tip.y, scale, offset_x, offset_y);
                render_target.ID2D1RenderTarget.DrawLine(
                    source_from,
                    source_tip,
                    brush,
                    stroke_width,
                    null,
                );
                drawArrowHead(&render_target.ID2D1RenderTarget, brush, source_tip, source_from, stroke_width);
            }

            if (edge.point_count >= 2) {
                var point_index: usize = 1;
                while (point_index < edge.point_count) : (point_index += 1) {
                    const start = edge.points[point_index - 1];
                    const end = edge.points[point_index];
                    render_target.ID2D1RenderTarget.DrawLine(
                        scalePoint(start.x, start.y, scale, offset_x, offset_y),
                        scalePoint(end.x, end.y, scale, offset_x, offset_y),
                        brush,
                        stroke_width,
                        null,
                    );
                }
            }

            if (edge.has_arrow != 0) {
                const target_from = scalePoint(edge.target_from.x, edge.target_from.y, scale, offset_x, offset_y);
                const target_tip = scalePoint(edge.target_tip.x, edge.target_tip.y, scale, offset_x, offset_y);
                render_target.ID2D1RenderTarget.DrawLine(
                    target_from,
                    target_tip,
                    brush,
                    stroke_width,
                    null,
                );
                drawArrowHead(&render_target.ID2D1RenderTarget, brush, target_tip, target_from, stroke_width);
            }
        }

        var node_index: usize = 0;
        while (node_index < scene.node_count) : (node_index += 1) {
            const node = scene.nodes[node_index];
            const left = node.x - node.width / 2.0;
            const top = node.y - node.height / 2.0;
            const rect = scaleRect(left, top, node.width, node.height, scale, offset_x, offset_y);
            const horizontal_text_padding = 10.0;
            const vertical_text_padding = 12.0;

            if (node.shape == 12) {
                const annotation_lines = countSceneTextLines(node.subtitle);
                const member_lines = countSceneTextLines(node.attributes_text);
                const method_lines = countSceneTextLines(node.methods_text);
                const line_height = @max(22.0 * scale, @as(f64, node.label_font_size) * @as(f64, @floatCast(scale)) * 1.25);
                const section_pad = 8.0 * scale;
                const header_lines = 1 + annotation_lines;
                const header_height = @max(26.0 * scale, @as(f64, @floatFromInt(header_lines)) * line_height + section_pad * 2.0);
                const attrs_height = if (member_lines > 0)
                    @as(f64, @floatFromInt(member_lines)) * line_height + section_pad * 2.0
                else
                    section_pad * 2.0;
                const methods_height = if (method_lines > 0)
                    @as(f64, @floatFromInt(method_lines)) * line_height + section_pad * 2.0
                else
                    section_pad * 2.0;
                const minimum_total_height = header_height + attrs_height + methods_height;
                const extra_height = @max(0.0, (@as(f64, rect.bottom) - @as(f64, rect.top)) - minimum_total_height);
                const attrs_rect_height = attrs_height + extra_height * 0.35;
                const methods_rect_height = methods_height + extra_height * 0.65;

                var header_rect = d2d_common.D2D_RECT_F{
                    .left = rect.left,
                    .top = rect.top,
                    .right = rect.right,
                    .bottom = @floatCast(@min(@as(f64, rect.bottom), @as(f64, rect.top) + header_height)),
                };
                var attrs_rect = d2d_common.D2D_RECT_F{
                    .left = rect.left,
                    .top = header_rect.bottom,
                    .right = rect.right,
                    .bottom = @floatCast(@min(@as(f64, rect.bottom), @as(f64, header_rect.bottom) + attrs_rect_height)),
                };
                var methods_rect = d2d_common.D2D_RECT_F{
                    .left = rect.left,
                    .top = attrs_rect.bottom,
                    .right = rect.right,
                    .bottom = @floatCast(@min(@as(f64, rect.bottom), @as(f64, attrs_rect.bottom) + methods_rect_height)),
                };
                methods_rect.bottom = rect.bottom;

                setBrushColor(node.fill);
                render_target.ID2D1RenderTarget.FillRectangle(&header_rect, brush);
                setBrushColor(node.body_fill);
                render_target.ID2D1RenderTarget.FillRectangle(&attrs_rect, brush);
                render_target.ID2D1RenderTarget.FillRectangle(&methods_rect, brush);
                setBrushColor(node.stroke);
                var mutable_rect = rect;
                const stroke_width = @max(1.0, node.stroke_width * @as(f32, @floatCast(scale)));
                render_target.ID2D1RenderTarget.DrawRectangle(&mutable_rect, brush, stroke_width, null);
                render_target.ID2D1RenderTarget.DrawLine(
                    .{ .x = rect.left, .y = header_rect.bottom },
                    .{ .x = rect.right, .y = header_rect.bottom },
                    brush,
                    stroke_width,
                    null,
                );
                render_target.ID2D1RenderTarget.DrawLine(
                    .{ .x = rect.left, .y = attrs_rect.bottom },
                    .{ .x = rect.right, .y = attrs_rect.bottom },
                    brush,
                    stroke_width,
                    null,
                );

                const header_text_rect = insetSceneRect(header_rect, 10.0 * scale, 8.0 * scale);
                const attrs_text_rect = d2d_common.D2D_RECT_F{
                    .left = @floatCast(@as(f64, attrs_rect.left) + 10.0 * scale),
                    .top = @floatCast(@as(f64, attrs_rect.top) + 8.0 * scale),
                    .right = @floatCast(@max(@as(f64, attrs_rect.left) + 11.0 * scale, @as(f64, attrs_rect.right) - 10.0 * scale)),
                    .bottom = @floatCast(@max(@as(f64, attrs_rect.top) + 10.0 * scale, @as(f64, attrs_rect.bottom) - 3.0 * scale)),
                };
                const methods_text_rect = d2d_common.D2D_RECT_F{
                    .left = @floatCast(@as(f64, methods_rect.left) + 10.0 * scale),
                    .top = @floatCast(@as(f64, methods_rect.top) + 8.0 * scale),
                    .right = @floatCast(@max(@as(f64, methods_rect.left) + 11.0 * scale, @as(f64, methods_rect.right) - 10.0 * scale)),
                    .bottom = @floatCast(@max(@as(f64, methods_rect.top) + 10.0 * scale, @as(f64, methods_rect.bottom) - 3.0 * scale)),
                };

                drawSceneText(
                    &render_target.ID2D1RenderTarget,
                    node.subtitle,
                    @max(9.0, (node.label_font_size - 2.0) * @as(f32, @floatCast(scale))),
                    node.label_color,
                    d2d_common.D2D_RECT_F{
                        .left = header_text_rect.left,
                        .top = header_text_rect.top,
                        .right = header_text_rect.right,
                        .bottom = @floatCast(@min(@as(f64, header_text_rect.bottom), @as(f64, header_text_rect.top) + @as(f64, @floatFromInt(annotation_lines)) * line_height + section_pad)),
                    },
                    dw.DWRITE_TEXT_ALIGNMENT_CENTER,
                    dw.DWRITE_PARAGRAPH_ALIGNMENT_NEAR,
                );

                const name_top = if (annotation_lines > 0)
                    header_text_rect.top + @as(f32, @floatCast(@as(f64, @floatFromInt(annotation_lines)) * line_height))
                else
                    header_text_rect.top + @as(f32, @floatCast(section_pad * 0.25));
                drawSceneText(
                    &render_target.ID2D1RenderTarget,
                    node.label,
                    @max(10.0, node.label_font_size * @as(f32, @floatCast(scale))),
                    node.label_color,
                    d2d_common.D2D_RECT_F{
                        .left = header_text_rect.left,
                        .top = name_top,
                        .right = header_text_rect.right,
                        .bottom = header_text_rect.bottom,
                    },
                    dw.DWRITE_TEXT_ALIGNMENT_CENTER,
                    dw.DWRITE_PARAGRAPH_ALIGNMENT_NEAR,
                );

                drawSceneText(
                    &render_target.ID2D1RenderTarget,
                    node.attributes_text,
                    @max(9.0, (node.label_font_size - 1.0) * @as(f32, @floatCast(scale))),
                    node.body_text_color,
                    attrs_text_rect,
                    dw.DWRITE_TEXT_ALIGNMENT_LEADING,
                    dw.DWRITE_PARAGRAPH_ALIGNMENT_NEAR,
                );
                drawSceneText(
                    &render_target.ID2D1RenderTarget,
                    node.methods_text,
                    @max(9.0, (node.label_font_size - 1.0) * @as(f32, @floatCast(scale))),
                    node.body_text_color,
                    methods_text_rect,
                    dw.DWRITE_TEXT_ALIGNMENT_LEADING,
                    dw.DWRITE_PARAGRAPH_ALIGNMENT_NEAR,
                );
                continue;
            }

            switch (node.shape) {
                1, 5, 6 => {
                    var rounded_rect = d2d.D2D1_ROUNDED_RECT{
                        .rect = rect,
                        .radiusX = @floatCast(@min(node.width, node.height) * scale * 0.2),
                        .radiusY = @floatCast(@min(node.width, node.height) * scale * 0.2),
                    };
                    setBrushColor(node.fill);
                    render_target.ID2D1RenderTarget.FillRoundedRectangle(&rounded_rect, brush);
                    setBrushColor(node.stroke);
                    render_target.ID2D1RenderTarget.DrawRoundedRectangle(&rounded_rect, brush, @max(1.0, node.stroke_width * @as(f32, @floatCast(scale))), null);
                },
                3 => {
                    var ellipse = d2d.D2D1_ELLIPSE{
                        .point = scalePoint(node.x, node.y, scale, offset_x, offset_y),
                        .radiusX = @floatCast(node.width * scale * 0.5),
                        .radiusY = @floatCast(node.height * scale * 0.5),
                    };
                    setBrushColor(node.fill);
                    render_target.ID2D1RenderTarget.FillEllipse(&ellipse, brush);
                    setBrushColor(node.stroke);
                    render_target.ID2D1RenderTarget.DrawEllipse(&ellipse, brush, @max(1.0, node.stroke_width * @as(f32, @floatCast(scale))), null);
                },
                else => {
                    var mutable_rect = rect;
                    setBrushColor(node.fill);
                    render_target.ID2D1RenderTarget.FillRectangle(&mutable_rect, brush);
                    setBrushColor(node.stroke);
                    render_target.ID2D1RenderTarget.DrawRectangle(&mutable_rect, brush, @max(1.0, node.stroke_width * @as(f32, @floatCast(scale))), null);
                },
            }

            const max_label_width = if (node.max_text_width > 0)
                @min(node.max_text_width, node.width - horizontal_text_padding * 2.0)
            else
                @max(24.0, node.width - horizontal_text_padding * 2.0);
            const label_rect = scaleRect(
                node.x - max_label_width / 2.0,
                node.y - node.height / 2.0 + vertical_text_padding,
                max_label_width,
                @max(18.0, node.height - vertical_text_padding * 2.0),
                scale,
                offset_x,
                offset_y,
            );
            drawSceneText(
                &render_target.ID2D1RenderTarget,
                node.label,
                @max(10.0, node.label_font_size * @as(f32, @floatCast(scale))),
                node.label_color,
                label_rect,
                dw.DWRITE_TEXT_ALIGNMENT_CENTER,
                dw.DWRITE_PARAGRAPH_ALIGNMENT_CENTER,
            );
        }

        var edge_label_index: usize = 0;
        while (edge_label_index < scene.edge_label_count) : (edge_label_index += 1) {
            const edge_label = scene.edge_labels[edge_label_index];
            const label_rect = scaleRect(
                edge_label.x - edge_label.half_w,
                edge_label.y - edge_label.half_h,
                edge_label.half_w * 2.0,
                edge_label.half_h * 2.0,
                scale,
                offset_x,
                offset_y,
            );
            drawSceneText(
                &render_target.ID2D1RenderTarget,
                edge_label.text,
                @max(9.0, edge_label.font_size * @as(f32, @floatCast(scale))),
                edge_label.color,
                label_rect,
                dw.DWRITE_TEXT_ALIGNMENT_CENTER,
                dw.DWRITE_PARAGRAPH_ALIGNMENT_CENTER,
            );
        }
    } else {
        var clear = d2d_common.D2D_COLOR_F{ .r = 0.96, .g = 0.97, .b = 0.98, .a = 1.0 };
        render_target.ID2D1RenderTarget.Clear(&clear);
    }

    _ = render_target.ID2D1RenderTarget.EndDraw(null, null);
}

fn countSceneTextLines(text_ptr: [*c]const u8) usize {
    if (text_ptr == null) return 0;
    const text = std.mem.sliceTo(text_ptr, 0);
    if (text.len == 0) return 0;

    var count: usize = 1;
    for (text) |ch| {
        if (ch == '\n') count += 1;
    }
    return count;
}

fn insetSceneRect(rect: d2d_common.D2D_RECT_F, inset_x: f64, inset_y: f64) d2d_common.D2D_RECT_F {
    return .{
        .left = @floatCast(@as(f64, rect.left) + inset_x),
        .top = @floatCast(@as(f64, rect.top) + inset_y),
        .right = @floatCast(@max(@as(f64, rect.left) + inset_x + 1.0, @as(f64, rect.right) - inset_x)),
        .bottom = @floatCast(@max(@as(f64, rect.top) + inset_y + 1.0, @as(f64, rect.bottom) - inset_y)),
    };
}

fn drawSceneText(
    render_target: *const d2d.ID2D1RenderTarget,
    text_ptr: [*c]const u8,
    requested_font_size: f32,
    color: StudioColor,
    layout_rect: d2d_common.D2D_RECT_F,
    text_alignment: dw.DWRITE_TEXT_ALIGNMENT,
    paragraph_alignment: dw.DWRITE_PARAGRAPH_ALIGNMENT,
) void {
    if (text_ptr == null) return;

    const text = std.mem.sliceTo(text_ptr, 0);
    if (text.len == 0) return;

    const write_factory = preview_renderer.write_factory orelse return;
    const utf16_text = std.unicode.utf8ToUtf16LeAllocZ(c_allocator, text) catch return;
    defer c_allocator.free(utf16_text);

    const layout_width = @max(1.0, layout_rect.right - layout_rect.left);
    const layout_height = @max(1.0, layout_rect.bottom - layout_rect.top);
    const has_break_opportunities = std.mem.indexOfAny(u8, text, " \t\r\n-/") != null;
    const width_factor: f32 = if (has_break_opportunities) 0.88 else 0.98;
    const height_factor: f32 = if (has_break_opportunities) 0.58 else 0.88;
    const width_limit = layout_width * width_factor;
    const height_limit = layout_height * height_factor;
    const wrapping_mode = if (has_break_opportunities) dw.DWRITE_WORD_WRAPPING_WRAP else dw.DWRITE_WORD_WRAPPING_NO_WRAP;

    var fitted_font_size = requested_font_size;
    var text_format: ?*dw.IDWriteTextFormat = null;
    var text_layout: ?*dw.IDWriteTextLayout = null;

    while (fitted_font_size >= 7.0) : (fitted_font_size -= 0.5) {
        releaseUnknown(&text_layout);
        releaseUnknown(&text_format);

        const create_hr = write_factory.CreateTextFormat(
            font_family_name_w[0..font_family_name_w.len :0].ptr,
            null,
            dw.DWRITE_FONT_WEIGHT_NORMAL,
            dw.DWRITE_FONT_STYLE_NORMAL,
            dw.DWRITE_FONT_STRETCH_NORMAL,
            fitted_font_size,
            locale_name_w[0..locale_name_w.len :0].ptr,
            @ptrCast(&text_format),
        );
        if (hrFailed(create_hr) or text_format == null) return;

        _ = text_format.?.SetTextAlignment(text_alignment);
        _ = text_format.?.SetParagraphAlignment(paragraph_alignment);
        _ = text_format.?.SetWordWrapping(wrapping_mode);

        const layout_hr = write_factory.CreateTextLayout(
            utf16_text.ptr,
            @intCast(utf16_text.len),
            text_format,
            layout_width,
            layout_height,
            @ptrCast(&text_layout),
        );
        if (hrFailed(layout_hr) or text_layout == null) return;

        var metrics = std.mem.zeroes(dw.DWRITE_TEXT_METRICS);
        if (hrFailed(text_layout.?.GetMetrics(&metrics))) return;
        const width_ok = metrics.width <= width_limit + 0.5 and metrics.widthIncludingTrailingWhitespace <= layout_width + 0.5;
        const height_ok = metrics.height <= height_limit + 0.5;
        const line_count_ok = has_break_opportunities or metrics.lineCount <= 1;
        if (width_ok and height_ok and line_count_ok) {
            break;
        }
    }

    defer releaseUnknown(&text_layout);
    defer releaseUnknown(&text_format);
    if (text_layout == null) return;

    setBrushColor(color);
    render_target.DrawTextLayout(
        .{ .x = layout_rect.left, .y = layout_rect.top },
        text_layout,
        previewBrush(),
        d2d.D2D1_DRAW_TEXT_OPTIONS_NONE,
    );
}

fn requestPreviewRefresh() void {
    if (child_windows.preview) |preview| {
        updatePreviewScrollbars(preview);
        _ = gdi.InvalidateRect(preview, null, 1);
    }
}

fn previewWindowProc(
    hwnd: ?foundation.HWND,
    message: u32,
    w_param: foundation.WPARAM,
    l_param: foundation.LPARAM,
) callconv(.winapi) foundation.LRESULT {
    switch (message) {
        ui.WM_ERASEBKGND => return 1,
        ui.WM_LBUTTONDOWN => {
            const mouse_pos = mouseCoordFromLParam(l_param);
            preview_renderer.is_dragging = true;
            preview_renderer.drag_last_x = mouse_pos.x;
            preview_renderer.drag_last_y = mouse_pos.y;
            _ = mouse.SetFocus(hwnd);
            _ = mouse.SetCapture(hwnd);
            return 0;
        },
        ui.WM_MOUSEWHEEL => {
            const delta = wheelDeltaFromWParam(w_param);
            const anchor = viewportAnchorFromWheel(hwnd, l_param);
            if (delta > 0) {
                stepPreviewZoomAtAnchor(anchor.x, anchor.y, true);
            } else if (delta < 0) {
                stepPreviewZoomAtAnchor(anchor.x, anchor.y, false);
            }
            return 0;
        },
        ui.WM_KEYDOWN, ui.WM_SYSKEYDOWN => {
            const ctrl_down = mouse.GetKeyState(@intFromEnum(mouse.VK_CONTROL)) < 0;
            if (ctrl_down) {
                switch (@as(u16, @truncate(w_param))) {
                    @intFromEnum(mouse.VK_ADD), @intFromEnum(mouse.VK_OEM_PLUS) => {
                        stepPreviewZoom(hwnd, true);
                        return 0;
                    },
                    @intFromEnum(mouse.VK_SUBTRACT), @intFromEnum(mouse.VK_OEM_MINUS) => {
                        stepPreviewZoom(hwnd, false);
                        return 0;
                    },
                    @intFromEnum(mouse.VK_0), @intFromEnum(mouse.VK_NUMPAD0) => {
                        const anchor = viewportAnchor(hwnd);
                        setPreviewZoom(1.0, anchor.x, anchor.y);
                        return 0;
                    },
                    else => {},
                }
            }
            return ui.DefWindowProcA(hwnd, message, w_param, l_param);
        },
        ui.WM_MOUSEMOVE => {
            if (preview_renderer.is_dragging) {
                const mouse_pos = mouseCoordFromLParam(l_param);
                const dx = mouse_pos.x - preview_renderer.drag_last_x;
                const dy = mouse_pos.y - preview_renderer.drag_last_y;
                preview_renderer.drag_last_x = mouse_pos.x;
                preview_renderer.drag_last_y = mouse_pos.y;
                if (dx != 0 or dy != 0) {
                    panPreviewBy(hwnd, -dx, -dy);
                }
                return 0;
            }
            return ui.DefWindowProcA(hwnd, message, w_param, l_param);
        },
        ui.WM_LBUTTONUP => {
            if (preview_renderer.is_dragging) {
                preview_renderer.is_dragging = false;
                _ = mouse.ReleaseCapture();
            }
            return 0;
        },
        ui.WM_SIZE => {
            if (preview_renderer.render_target) |render_target| {
                if (currentPreviewPixelSize(hwnd)) |size| {
                    _ = render_target.Resize(&size);
                }
            }
            updatePreviewScrollbars(hwnd);
            requestPreviewRefresh();
            return 0;
        },
        ui.WM_HSCROLL => {
            applyPreviewScroll(hwnd, ui.SB_HORZ, @truncate(w_param & 0xffff));
            return 0;
        },
        ui.WM_VSCROLL => {
            applyPreviewScroll(hwnd, ui.SB_VERT, @truncate(w_param & 0xffff));
            return 0;
        },
        ui.WM_PAINT => {
            var paint = std.mem.zeroes(gdi.PAINTSTRUCT);
            _ = gdi.BeginPaint(hwnd, &paint);
            drawSceneToPreview(hwnd);
            _ = gdi.EndPaint(hwnd, &paint);
            return 0;
        },
        else => return ui.DefWindowProcA(hwnd, message, w_param, l_param),
    }
}

fn createChildWindows(hwnd: ?foundation.HWND, h_instance: ?foundation.HINSTANCE) bool {
    const child_visible_bits = styleBits(ui.WS_CHILD) | styleBits(ui.WS_VISIBLE) | styleBits(ui.WS_CLIPSIBLINGS);

    const preview = ui.CreateWindowExA(
        makeExStyle(exStyleBits(ui.WS_EX_CLIENTEDGE)),
        preview_class_name,
        null,
        makeStyle(child_visible_bits | styleBits(ui.WS_HSCROLL) | styleBits(ui.WS_VSCROLL) | styleBits(ui.WS_TABSTOP)),
        0,
        0,
        100,
        100,
        hwnd,
        null,
        h_instance,
        null,
    ) orelse return false;

    const editor_style_bits = child_visible_bits |
        styleBits(ui.WS_TABSTOP) |
        styleBits(ui.WS_VSCROLL) |
        styleBits(ui.WS_HSCROLL) |
        @as(u32, @bitCast(ui.ES_MULTILINE)) |
        @as(u32, @bitCast(ui.ES_AUTOVSCROLL)) |
        @as(u32, @bitCast(ui.ES_AUTOHSCROLL)) |
        @as(u32, @bitCast(ui.ES_WANTRETURN));
    const editor = ui.CreateWindowExA(
        makeExStyle(exStyleBits(ui.WS_EX_CLIENTEDGE)),
        edit_class,
        initial_source,
        makeStyle(editor_style_bits),
        0,
        0,
        100,
        100,
        hwnd,
        null,
        h_instance,
        null,
    ) orelse return false;

    const toolbar_style_bits = child_visible_bits |
        @as(u32, controls.TBSTYLE_FLAT) |
        @as(u32, controls.TBSTYLE_LIST) |
        @as(u32, controls.TBSTYLE_TRANSPARENT) |
        @as(u32, controls.TBSTYLE_TOOLTIPS) |
        @as(u32, @intCast(controls.CCS_NORESIZE)) |
        @as(u32, @intCast(controls.CCS_NOPARENTALIGN)) |
        @as(u32, @intCast(controls.CCS_NODIVIDER));
    const toolbar = ui.CreateWindowExA(
        .{},
        toolbar_class,
        null,
        makeStyle(toolbar_style_bits),
        0,
        0,
        100,
        32,
        hwnd,
        null,
        h_instance,
        null,
    ) orelse return false;

    const command = ui.CreateWindowExA(
        makeExStyle(exStyleBits(ui.WS_EX_CLIENTEDGE)),
        edit_class,
        "",
        makeStyle(child_visible_bits | styleBits(ui.WS_TABSTOP) | styleBits(ui.WS_BORDER)),
        0,
        0,
        100,
        28,
        hwnd,
        null,
        h_instance,
        null,
    ) orelse return false;

    const apply_button = ui.CreateWindowExA(
        .{},
        button_class,
        "Apply",
        makeStyle(child_visible_bits | styleBits(ui.WS_TABSTOP)),
        0,
        0,
        80,
        28,
        hwnd,
        null,
        h_instance,
        null,
    ) orelse return false;

    const status = ui.CreateWindowExA(
        .{},
        controls.STATUSCLASSNAMEA,
        null,
        makeStyle(child_visible_bits | controls.SBARS_SIZEGRIP),
        0,
        0,
        100,
        24,
        hwnd,
        null,
        h_instance,
        null,
    ) orelse return false;

    child_windows.preview = preview;
    child_windows.editor = editor;
    child_windows.toolbar = toolbar;
    child_windows.command = command;
    child_windows.apply_button = apply_button;
    child_windows.status = status;
    initializeToolbarControl();
    configureShellFonts();
    configureEditorControl();
    refreshStatusDisplay();
    return true;
}

fn layoutChildWindows(hwnd: ?foundation.HWND) void {
    windows_layout.applyChildLayout(hwnd, child_windows);
}

fn setWindowText(hwnd: ?foundation.HWND, text: []const u8) void {
    const z_text = c_allocator.allocSentinel(u8, text.len, 0) catch return;
    defer c_allocator.free(z_text);
    @memcpy(z_text[0..text.len], text);
    _ = ui.SetWindowTextA(hwnd, z_text.ptr);
}

fn setStatusBarPartText(part: usize, text: []const u8) void {
    windows_status_bar.setStatusBarPartText(c_allocator, child_windows.status, part, text);
}

fn updateStatusBarParts(total_width: i32) void {
    windows_status_bar.updateStatusBarParts(child_windows.status, total_width);
}

fn minimumClientSize() windows_constants.WindowSize {
    return windows_layout.minimumClientSize();
}

fn minimumWindowTrackSize() windows_constants.WindowSize {
    return windows_layout.minimumWindowTrackSize();
}

fn paintMainBackground(hdc: gdi.HDC, rect: *const foundation.RECT) void {
    const brush_obj = gdi.GetStockObject(gdi.WHITE_BRUSH) orelse return;
    const brush: gdi.HBRUSH = @ptrCast(brush_obj);
    _ = gdi.FillRect(hdc, rect, brush);
}

fn refreshStatusDisplay() void {
    windows_status_bar.refreshStatusDisplay(c_allocator, child_windows.status, current_status_message, preview_renderer.zoom);
}

fn setStatusMessage(text: []const u8) void {
    freeCurrentStatusMessage();
    current_status_message = c_allocator.dupe(u8, text) catch null;
    refreshStatusDisplay();
}

fn getWindowText(allocator: std.mem.Allocator, hwnd: ?foundation.HWND) ![:0]u8 {
    return windows_editor.getWindowText(allocator, hwnd);
}

fn getEditorText(allocator: std.mem.Allocator) ![:0]u8 {
    return windows_editor.getEditorText(allocator, child_windows.editor);
}

fn updateEditorDerivedState() void {
    const editor_text = getEditorText(c_allocator) catch {
        setStatusMessage("Failed to read editor text");
        return;
    };
    defer c_allocator.free(editor_text);

    var syntax_message: [256]u8 = std.mem.zeroes([256]u8);
    const syntax_result = merrow_studio_check_mermaid_syntax(editor_text.ptr, @intCast(editor_text.len), &syntax_message, syntax_message.len);
    const syntax_slice = std.mem.sliceTo(&syntax_message, 0);
    const syntax_text = if (syntax_slice.len > 0) syntax_slice else "Syntax check unavailable";

    if (syntax_result != 0) {
        replaceCurrentScene(null);
        const status_text = std.fmt.allocPrint(c_allocator, "{s}", .{syntax_text}) catch return;
        defer c_allocator.free(status_text);
        setStatusMessage(status_text);
        requestPreviewRefresh();
        return;
    }

    const next_scene = merrow_studio_build_scene(editor_text.ptr, @intCast(editor_text.len));
    if (next_scene) |built_scene| {
        replaceCurrentScene(built_scene);
        const status_text = std.fmt.allocPrint(
            c_allocator,
            "{s} | nodes {d} | edges {d}",
            .{ syntax_text, built_scene.node_count, built_scene.edge_count },
        ) catch return;
        defer c_allocator.free(status_text);
        setStatusMessage(status_text);
        requestPreviewRefresh();
        return;
    }

    replaceCurrentScene(null);
    setStatusMessage(syntax_text);
    requestPreviewRefresh();
}

fn applyUpdatedSource(source: []const u8, status_text: []const u8) void {
    setEditorText(source);
    setStatusMessage(status_text);
    updateEditorDerivedState();
    setDocumentDirty(true);
}

fn runReservedToolbarAction(slot: u8) void {
    const text = switch (slot) {
        1 => "Reserved toolbar slot 1",
        2 => "Reserved toolbar slot 2",
        3 => "Reserved toolbar slot 3",
        else => "Reserved toolbar slot",
    };
    setStatusMessage(text);
}

fn runDiagramCommand() void {
    const source = getEditorText(c_allocator) catch return;
    defer c_allocator.free(source);
    const command = getWindowText(c_allocator, child_windows.command) catch return;
    defer c_allocator.free(command);

    const trimmed = std.mem.trim(u8, command, " \r\n\t");
    if (trimmed.len == 0) {
        setStatusMessage("Enter a diagram command first");
        return;
    }

    var context_id: [256]u8 = std.mem.zeroes([256]u8);
    var context_display: [256]u8 = std.mem.zeroes([256]u8);
    var message: [256]u8 = std.mem.zeroes([256]u8);
    const updated_source = merrow_studio_apply_command(
        source.ptr,
        @intCast(source.len),
        trimmed.ptr,
        @intCast(trimmed.len),
        &empty_c_string,
        0,
        &context_id,
        context_id.len,
        &context_display,
        context_display.len,
        &message,
        message.len,
    );
    const message_text = std.mem.sliceTo(&message, 0);
    if (updated_source) |ptr| {
        defer merrow_studio_free_string(ptr);
        applyUpdatedSource(std.mem.sliceTo(ptr, 0), if (message_text.len > 0) message_text else "Command applied");
        setWindowText(child_windows.command, "");
    } else {
        const fallback = if (message_text.len > 0) message_text else "Command failed";
        setStatusMessage(fallback);
    }
}

fn shuffleDiagram() void {
    const source = getEditorText(c_allocator) catch return;
    defer c_allocator.free(source);

    var message: [256]u8 = std.mem.zeroes([256]u8);
    const updated_source = merrow_studio_shuffle_diagram(source.ptr, @intCast(source.len), &message, message.len);
    const message_text = std.mem.sliceTo(&message, 0);
    if (updated_source) |ptr| {
        defer merrow_studio_free_string(ptr);
        applyUpdatedSource(std.mem.sliceTo(ptr, 0), if (message_text.len > 0) message_text else "Shuffle applied");
    } else {
        const fallback = if (message_text.len > 0) message_text else "Shuffle unavailable";
        setStatusMessage(fallback);
    }
}

fn windowProc(
    hwnd: ?foundation.HWND,
    message: u32,
    w_param: foundation.WPARAM,
    l_param: foundation.LPARAM,
) callconv(.winapi) foundation.LRESULT {
    switch (message) {
        ui.WM_NCCREATE => {
            _ = dpi.EnableNonClientDpiScaling(hwnd);
            return ui.DefWindowProcA(hwnd, message, w_param, l_param);
        },
        ui.WM_CREATE => {
            const create_struct: *ui.CREATESTRUCTA = @ptrFromInt(@as(usize, @bitCast(l_param)));
            main_window = hwnd;
            registerPreviewFont();
            if (!installMenuBar(hwnd)) {
                return -1;
            }
            if (!createChildWindows(hwnd, create_struct.hInstance)) {
                return -1;
            }
            layoutChildWindows(hwnd);
            updateEditorDerivedState();
            updateWindowTitle();
            return 0;
        },
        ui.WM_COMMAND => {
            const command_id: u16 = @truncate(w_param & 0xffff);
            const notification_code: u16 = @truncate((w_param >> 16) & 0xffff);
            const source_hwnd: ?foundation.HWND = if (l_param == 0) null else @ptrFromInt(@as(usize, @bitCast(l_param)));
            if (notification_code == 0 and source_hwnd == null) {
                switch (command_id) {
                    menu_id_open => {
                        openDocumentFromDialog();
                        return 0;
                    },
                    menu_id_save => {
                        saveDocument(false);
                        return 0;
                    },
                    menu_id_save_as => {
                        saveDocument(true);
                        return 0;
                    },
                    toolbar_id_reserved_1 => {
                        runReservedToolbarAction(1);
                        return 0;
                    },
                    toolbar_id_reserved_2 => {
                        runReservedToolbarAction(2);
                        return 0;
                    },
                    toolbar_id_reserved_3 => {
                        runReservedToolbarAction(3);
                        return 0;
                    },
                    else => {},
                }
            }
            if (notification_code == ui.BN_CLICKED and source_hwnd == child_windows.apply_button) {
                runDiagramCommand();
                return 0;
            }
            if (notification_code == ui.EN_CHANGE and source_hwnd == child_windows.editor) {
                if (!suppress_editor_change) {
                    setDocumentDirty(true);
                }
                updateEditorDerivedState();
                return 0;
            }
            return ui.DefWindowProcA(hwnd, message, w_param, l_param);
        },
        ui.WM_SIZE => {
            layoutChildWindows(hwnd);
            _ = gdi.RedrawWindow(
                hwnd,
                null,
                null,
                makeRedrawFlags(
                    redrawFlagsBits(gdi.RDW_INVALIDATE) |
                        redrawFlagsBits(gdi.RDW_ERASE) |
                        redrawFlagsBits(gdi.RDW_ALLCHILDREN) |
                        redrawFlagsBits(gdi.RDW_ERASENOW),
                ),
            );
            requestPreviewRefresh();
            return 0;
        },
        ui.WM_DPICHANGED => {
            const suggested: *const foundation.RECT = @ptrFromInt(@as(usize, @bitCast(l_param)));
            _ = ui.SetWindowPos(
                hwnd,
                null,
                suggested.left,
                suggested.top,
                suggested.right - suggested.left,
                suggested.bottom - suggested.top,
                ui.SWP_NOZORDER,
            );
            releaseShellFont();
            configureShellFonts();
            layoutChildWindows(hwnd);
            refreshStatusDisplay();
            requestPreviewRefresh();
            return 0;
        },
        ui.WM_GETMINMAXINFO => {
            const info: *ui.MINMAXINFO = @ptrFromInt(@as(usize, @bitCast(l_param)));
            const min_size = minimumWindowTrackSize();
            info.ptMinTrackSize.x = min_size.width;
            info.ptMinTrackSize.y = min_size.height;
            return 0;
        },
        ui.WM_ERASEBKGND => {
            const hdc: gdi.HDC = @ptrFromInt(@as(usize, @bitCast(w_param)));
            var rect = std.mem.zeroes(foundation.RECT);
            if (ui.GetClientRect(hwnd, &rect) != 0) {
                paintMainBackground(hdc, &rect);
            }
            return 1;
        },
        ui.WM_PAINT => {
            var paint = std.mem.zeroes(gdi.PAINTSTRUCT);
            const hdc = gdi.BeginPaint(hwnd, &paint) orelse return 0;
            paintMainBackground(hdc, &paint.rcPaint);
            _ = gdi.EndPaint(hwnd, &paint);
            return 0;
        },
        ui.WM_DESTROY => {
            replaceCurrentScene(null);
            freeCurrentDocumentPath();
            freeCurrentStatusMessage();
            releaseShellFont();
            releaseEditorFont();
            unregisterPreviewFont();
            releaseUnknown(&preview_renderer.brush);
            releaseUnknown(&preview_renderer.render_target);
            releaseUnknown(&preview_renderer.write_factory);
            releaseUnknown(&preview_renderer.factory);
            ui.PostQuitMessage(0);
            return 0;
        },
        else => return ui.DefWindowProcA(hwnd, message, w_param, l_param),
    }
}

pub export fn merrow_studio_main(argc: c_int, argv: [*]const [*:0]const u8) callconv(.c) c_int {
    _ = argc;
    _ = argv;

    _ = dpi.SetProcessDpiAwarenessContext(dpi.DPI_AWARENESS_CONTEXT_PER_MONITOR_AWARE_V2);

    var common_controls = controls.INITCOMMONCONTROLSEX{
        .dwSize = @sizeOf(controls.INITCOMMONCONTROLSEX),
        .dwICC = controls.ICC_BAR_CLASSES,
    };
    _ = controls.InitCommonControlsEx(&common_controls);

    const h_instance = loader.GetModuleHandleA(null) orelse return 1;

    var window_class = std.mem.zeroes(ui.WNDCLASSEXA);
    window_class.cbSize = @sizeOf(ui.WNDCLASSEXA);
    window_class.lpfnWndProc = windowProc;
    window_class.hInstance = h_instance;
    window_class.hCursor = ui.LoadCursorW(null, ui.IDC_ARROW);
    window_class.lpszClassName = class_name;

    if (ui.RegisterClassExA(&window_class) == 0) {
        return 1;
    }

    var preview_class = std.mem.zeroes(ui.WNDCLASSEXA);
    preview_class.cbSize = @sizeOf(ui.WNDCLASSEXA);
    preview_class.lpfnWndProc = previewWindowProc;
    preview_class.hInstance = h_instance;
    preview_class.hCursor = ui.LoadCursorW(null, ui.IDC_ARROW);
    preview_class.lpszClassName = preview_class_name;
    if (ui.RegisterClassExA(&preview_class) == 0) {
        return 1;
    }

    const hwnd = ui.CreateWindowExA(
        .{},
        class_name,
        window_title,
        makeStyle(styleBits(ui.WS_OVERLAPPEDWINDOW) | styleBits(ui.WS_CLIPCHILDREN)),
        ui.CW_USEDEFAULT,
        ui.CW_USEDEFAULT,
        1280,
        820,
        null,
        null,
        h_instance,
        null,
    ) orelse return 1;

    _ = ui.ShowWindow(hwnd, ui.SW_SHOW);

    var msg = std.mem.zeroes(ui.MSG);
    while (true) {
        const message_result = ui.GetMessageA(&msg, null, 0, 0);
        if (message_result == -1) {
            return 1;
        }
        if (message_result == 0) {
            break;
        }

        _ = ui.TranslateMessage(&msg);
        _ = ui.DispatchMessageA(&msg);
    }

    return 0;
}
