const std = @import("std");
const win32 = @import("win32");
const merrow = @import("merrow");
const merrow_lexer = merrow.lexer;
const windows_app_state = @import("windows/app_state.zig");
const windows_canvas = @import("windows/canvas.zig");
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
const dxgi_common = win32.graphics.dxgi.common;
const dwrite = win32.graphics.direct_write;
const gdi = win32.graphics.gdi;
const imaging = win32.graphics.imaging;
const file_system = win32.storage.file_system;
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
const canvas_class_name = windows_constants.canvas_class_name;
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
const menu_id_mode_mermaid = windows_constants.menu_id_mode_mermaid;
const menu_id_mode_freeform = windows_constants.menu_id_mode_freeform;
const toolbar_id_reserved_1 = windows_constants.toolbar_id_reserved_1;
const toolbar_id_reserved_2 = windows_constants.toolbar_id_reserved_2;
const toolbar_id_reserved_3 = windows_constants.toolbar_id_reserved_3;
const toolbar_slot_1_label = windows_constants.toolbar_slot_1_label;
const toolbar_slot_2_label = windows_constants.toolbar_slot_2_label;
const toolbar_slot_3_label = windows_constants.toolbar_slot_3_label;
const Layout = windows_constants.Layout;
const ViewAnchor = windows_constants.ViewAnchor;

const AppMode = windows_app_state.AppMode;
const ChildWindows = windows_app_state.ChildWindows;
const PreviewRenderer = windows_app_state.PreviewRenderer;
const CanvasRenderer = windows_app_state.CanvasRenderer;
extern fn merrow_studio_build_editable_graph(source_ptr: [*]const u8, source_len: u32, out_message: [*]u8, out_message_len: u32) callconv(.c) ?*windows_canvas.StudioEditableGraph;
extern fn merrow_studio_check_mermaid_syntax(source_ptr: [*]const u8, source_len: u32, out_message: [*]u8, out_message_len: u32) callconv(.c) c_int;
extern fn merrow_studio_render_preview_png_bytes(source_ptr: [*]const u8, source_len: u32, out_png_len: *u32, out_message: [*]u8, out_message_len: u32) callconv(.c) [*c]u8;
extern fn merrow_studio_apply_command(source_ptr: [*]const u8, source_len: u32, command_ptr: [*]const u8, command_len: u32, context_id_ptr: [*]const u8, context_id_len: u32, out_context_id: [*]u8, out_context_id_len: u32, out_context_display: [*]u8, out_context_display_len: u32, out_message: [*]u8, out_message_len: u32) callconv(.c) [*c]u8;
extern fn merrow_studio_shuffle_diagram(source_ptr: [*]const u8, source_len: u32, out_message: [*]u8, out_message_len: u32) callconv(.c) [*c]u8;
extern fn merrow_studio_free_string(text: [*c]u8) callconv(.c) void;
extern fn merrow_studio_free_buffer(buffer: [*c]u8, buffer_len: u32) callconv(.c) void;

var app_mode: AppMode = .mermaid;
var child_windows = ChildWindows{};
var preview_renderer = PreviewRenderer{};
var canvas_renderer = CanvasRenderer.init(c_allocator);
var canvas_dwrite_factory: ?*dwrite.IDWriteFactory = null;
var main_window: ?foundation.HWND = null;
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
const preview_bitmap_scale: f64 = 4.0;
// Minimum virtual border around the image in display pixels; actual margin is
// max(preview_pan_margin, viewport/4) so it grows with window size.
const preview_pan_margin: i32 = 200;

const PreviewAxisBounds = struct {
    min: i32,
    max: i32,
    default_pos: i32,
};

fn previewAxisBounds(content: i32, viewport: i32) PreviewAxisBounds {
    const margin: i32 = @max(preview_pan_margin, @divTrunc(viewport, 4));
    const raw_min: i32 = -margin;
    const raw_max: i32 = content - viewport + margin;

    if (raw_max <= raw_min) {
        // The image plus both margins fits entirely inside the viewport.
        // Center the image and disable panning (scrollbar appears grayed-out).
        const centered: i32 = @divTrunc(content - viewport, 2);
        return .{ .min = centered, .max = centered, .default_pos = centered };
    }

    // For images that fit the viewport: center as the start position.
    // For images larger than the viewport: start at the top-left (position 0).
    const default_pos: i32 = if (content <= viewport) @divTrunc(content - viewport, 2) else 0;
    return .{ .min = raw_min, .max = raw_max, .default_pos = default_pos };
}

fn previewLogicalWidth() i32 {
    return @max(0, @as(i32, @intFromFloat(@ceil(@as(f64, @floatFromInt(preview_renderer.bitmap_width)) / preview_bitmap_scale))));
}

fn previewLogicalHeight() i32 {
    return @max(0, @as(i32, @intFromFloat(@ceil(@as(f64, @floatFromInt(preview_renderer.bitmap_height)) / preview_bitmap_scale))));
}

fn freeCurrentDocumentPath() void {
    windows_document.freeCurrentDocumentPath(c_allocator, &current_document_path);
}

fn freeCurrentStatusMessage() void {
    if (current_status_message) |message| {
        c_allocator.free(message);
        current_status_message = null;
    }
}

fn releasePreviewBitmap() void {
    releaseUnknown(&preview_renderer.bitmap);
}

fn freePreviewPng() void {
    if (preview_renderer.preview_png) |png| {
        c_allocator.free(png);
        preview_renderer.preview_png = null;
    }
}

fn clearPreviewImageState() void {
    releasePreviewBitmap();
    freePreviewPng();
    preview_renderer.bitmap_width = 0;
    preview_renderer.bitmap_height = 0;
    preview_renderer.scroll_x = 0;
    preview_renderer.scroll_y = 0;
}

fn replacePreviewPng(png_bytes: []const u8) bool {
    const duplicated = c_allocator.alloc(u8, png_bytes.len) catch return false;
    @memcpy(duplicated, png_bytes);
    freePreviewPng();
    preview_renderer.preview_png = duplicated;
    return true;
}

fn ensurePreviewImagingFactory() bool {
    if (!preview_renderer.com_initialized) {
        const init_hr = com.CoInitializeEx(null, com.COINIT_APARTMENTTHREADED);
        if (hrFailed(init_hr) and init_hr != foundation.RPC_E_CHANGED_MODE) return false;
        preview_renderer.com_initialized = true;
    }

    if (preview_renderer.wic_factory == null) {
        var factory: ?*imaging.IWICImagingFactory = null;
        const create_hr = com.CoCreateInstance(
            &imaging.CLSID_WICImagingFactory,
            null,
            com.CLSCTX_INPROC_SERVER,
            imaging.IID_IWICImagingFactory,
            @ptrCast(&factory),
        );
        if (hrFailed(create_hr) or factory == null) return false;
        preview_renderer.wic_factory = factory;
    }

    return true;
}

fn syncPreviewBitmapFromMemory(hwnd: ?foundation.HWND) bool {
    const preview_png = preview_renderer.preview_png orelse {
        releasePreviewBitmap();
        preview_renderer.bitmap_width = 0;
        preview_renderer.bitmap_height = 0;
        return false;
    };
    if (!ensurePreviewImagingFactory()) return false;

    const wic_factory = preview_renderer.wic_factory orelse return false;

    var stream: ?*imaging.IWICStream = null;
    if (hrFailed(wic_factory.CreateStream(&stream)) or stream == null) return false;
    defer releaseUnknown(&stream);

    if (hrFailed(stream.?.InitializeFromMemory(@ptrCast(preview_png.ptr), @intCast(preview_png.len)))) return false;

    var decoder: ?*imaging.IWICBitmapDecoder = null;
    const decoder_hr = wic_factory.CreateDecoderFromStream(
        @ptrCast(stream.?),
        null,
        imaging.WICDecodeMetadataCacheOnLoad,
        &decoder,
    );
    if (hrFailed(decoder_hr) or decoder == null) return false;
    defer releaseUnknown(&decoder);

    var frame: ?*imaging.IWICBitmapFrameDecode = null;
    if (hrFailed(decoder.?.GetFrame(0, &frame)) or frame == null) return false;
    defer releaseUnknown(&frame);

    var converter: ?*imaging.IWICFormatConverter = null;
    if (hrFailed(wic_factory.CreateFormatConverter(&converter)) or converter == null) return false;
    defer releaseUnknown(&converter);

    var pixel_format = imaging.GUID_WICPixelFormat32bppPBGRA;
    if (hrFailed(converter.?.Initialize(
        @ptrCast(frame.?),
        &pixel_format,
        imaging.WICBitmapDitherTypeNone,
        null,
        0.0,
        imaging.WICBitmapPaletteTypeCustom,
    ))) return false;

    var width: u32 = 0;
    var height: u32 = 0;
    if (hrFailed((@as(*imaging.IWICBitmapSource, @ptrCast(converter.?))).GetSize(&width, &height))) return false;

    preview_renderer.bitmap_width = width;
    preview_renderer.bitmap_height = height;
    releasePreviewBitmap();

    if (!ensurePreviewRenderTarget(hwnd)) return true;
    const render_target = preview_renderer.render_target orelse return true;

    var bitmap_raw: *d2d.ID2D1Bitmap = undefined;
    if (hrFailed(render_target.ID2D1RenderTarget.CreateBitmapFromWicBitmap(@ptrCast(converter.?), null, &bitmap_raw))) {
        preview_renderer.bitmap_width = 0;
        preview_renderer.bitmap_height = 0;
        return false;
    }

    preview_renderer.bitmap = bitmap_raw;
    return true;
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
    updateEditorDerivedState(true);
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

fn rgba8Color(r: u8, g: u8, b: u8, a: u8) d2d_common.D2D_COLOR_F {
    return .{
        .r = @as(f32, @floatFromInt(r)) / 255.0,
        .g = @as(f32, @floatFromInt(g)) / 255.0,
        .b = @as(f32, @floatFromInt(b)) / 255.0,
        .a = @as(f32, @floatFromInt(a)) / 255.0,
    };
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

fn previewContentPixelWidth() i32 {
    return @max(0, @as(i32, @intFromFloat(@ceil(@as(f64, @floatFromInt(previewLogicalWidth())) * preview_renderer.zoom))));
}

fn previewContentPixelHeight() i32 {
    return @max(0, @as(i32, @intFromFloat(@ceil(@as(f64, @floatFromInt(previewLogicalHeight())) * preview_renderer.zoom))));
}

fn previewBounds(hwnd: ?foundation.HWND) ?struct {
    x: PreviewAxisBounds,
    y: PreviewAxisBounds,
    viewport_width: i32,
    viewport_height: i32,
} {
    const size = currentPreviewPixelSize(hwnd) orelse return null;
    const viewport_width: i32 = @intCast(size.width);
    const viewport_height: i32 = @intCast(size.height);
    return .{
        .x = previewAxisBounds(previewContentPixelWidth(), viewport_width),
        .y = previewAxisBounds(previewContentPixelHeight(), viewport_height),
        .viewport_width = viewport_width,
        .viewport_height = viewport_height,
    };
}

fn updatePreviewScrollbars(hwnd: ?foundation.HWND) void {
    const bounds = previewBounds(hwnd) orelse return;

    preview_renderer.scroll_x = std.math.clamp(preview_renderer.scroll_x, bounds.x.min, bounds.x.max);
    preview_renderer.scroll_y = std.math.clamp(preview_renderer.scroll_y, bounds.y.min, bounds.y.max);

    var x_info = ui.SCROLLINFO{
        .cbSize = @sizeOf(ui.SCROLLINFO),
        .fMask = makeScrollMask(scrollMaskBits(ui.SIF_RANGE) | scrollMaskBits(ui.SIF_PAGE) | scrollMaskBits(ui.SIF_POS) | scrollMaskBits(ui.SIF_DISABLENOSCROLL)),
        .nMin = bounds.x.min,
        .nMax = bounds.x.max + bounds.viewport_width - 1,
        .nPage = @intCast(bounds.viewport_width),
        .nPos = preview_renderer.scroll_x,
        .nTrackPos = 0,
    };
    _ = controls.SetScrollInfo(hwnd, ui.SB_HORZ, &x_info, 1);

    var y_info = ui.SCROLLINFO{
        .cbSize = @sizeOf(ui.SCROLLINFO),
        .fMask = makeScrollMask(scrollMaskBits(ui.SIF_RANGE) | scrollMaskBits(ui.SIF_PAGE) | scrollMaskBits(ui.SIF_POS) | scrollMaskBits(ui.SIF_DISABLENOSCROLL)),
        .nMin = bounds.y.min,
        .nMax = bounds.y.max + bounds.viewport_height - 1,
        .nPage = @intCast(bounds.viewport_height),
        .nPos = preview_renderer.scroll_y,
        .nTrackPos = 0,
    };
    _ = controls.SetScrollInfo(hwnd, ui.SB_VERT, &y_info, 1);
}

fn applyPreviewScroll(hwnd: ?foundation.HWND, bar: ui.SCROLLBAR_CONSTANTS, request: u16) void {
    const bounds = previewBounds(hwnd) orelse return;
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
    const axis_min = if (@as(u32, @bitCast(bar)) == @as(u32, @bitCast(ui.SB_HORZ))) bounds.x.min else bounds.y.min;
    const axis_max = if (@as(u32, @bitCast(bar)) == @as(u32, @bitCast(ui.SB_HORZ))) bounds.x.max else bounds.y.max;
    var next_pos = info.nPos;
    switch (@as(u32, request)) {
        0 => next_pos -= 24,
        1 => next_pos += 24,
        2 => next_pos -= page,
        3 => next_pos += page,
        4, 5 => next_pos = info.nTrackPos,
        else => return,
    }

    next_pos = std.math.clamp(next_pos, axis_min, axis_max);
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
    const bounds = previewBounds(hwnd) orelse return;

    preview_renderer.scroll_x = std.math.clamp(preview_renderer.scroll_x + delta_x, bounds.x.min, bounds.x.max);
    preview_renderer.scroll_y = std.math.clamp(preview_renderer.scroll_y + delta_y, bounds.y.min, bounds.y.max);
    requestPreviewRefresh();
}

fn resetPreviewView(hwnd: ?foundation.HWND) void {
    preview_renderer.zoom = 1.0;
    if (previewBounds(hwnd)) |bounds| {
        preview_renderer.scroll_x = bounds.x.default_pos;
        preview_renderer.scroll_y = bounds.y.default_pos;
    } else {
        preview_renderer.scroll_x = 0;
        preview_renderer.scroll_y = 0;
    }
    refreshStatusDisplay();
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
            releasePreviewBitmap();
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
    return true;
}

fn drawPreviewBitmap(hwnd: ?foundation.HWND) void {
    if (!ensurePreviewRenderTarget(hwnd)) return;

    if (preview_renderer.bitmap == null and preview_renderer.preview_png != null) {
        _ = syncPreviewBitmapFromMemory(hwnd);
    }

    const render_target = preview_renderer.render_target orelse return;
    render_target.ID2D1RenderTarget.BeginDraw();
    var background = rgba8Color(255, 255, 255, 255);
    render_target.ID2D1RenderTarget.Clear(&background);

    if (preview_renderer.bitmap) |bitmap| {
        const viewport_size = currentPreviewPixelSize(hwnd) orelse {
            _ = render_target.ID2D1RenderTarget.EndDraw(null, null);
            return;
        };
        const dest_left = @as(f64, @floatFromInt(@max(0, -preview_renderer.scroll_x)));
        const dest_top = @as(f64, @floatFromInt(@max(0, -preview_renderer.scroll_y)));
        const source_left = @as(f64, @floatFromInt(@max(0, preview_renderer.scroll_x))) / preview_renderer.zoom * preview_bitmap_scale;
        const source_top = @as(f64, @floatFromInt(@max(0, preview_renderer.scroll_y))) / preview_renderer.zoom * preview_bitmap_scale;
        const visible_display_width = @max(
            0.0,
            @min(
                @as(f64, @floatFromInt(previewContentPixelWidth() - @max(0, preview_renderer.scroll_x))),
                @as(f64, @floatFromInt(@as(i32, @intCast(viewport_size.width)) - @max(0, -preview_renderer.scroll_x))),
            ),
        );
        const visible_display_height = @max(
            0.0,
            @min(
                @as(f64, @floatFromInt(previewContentPixelHeight() - @max(0, preview_renderer.scroll_y))),
                @as(f64, @floatFromInt(@as(i32, @intCast(viewport_size.height)) - @max(0, -preview_renderer.scroll_y))),
            ),
        );
        const source_width = visible_display_width / preview_renderer.zoom * preview_bitmap_scale;
        const source_height = visible_display_height / preview_renderer.zoom * preview_bitmap_scale;
        const dest_rect = d2d_common.D2D_RECT_F{
            .left = @floatCast(dest_left),
            .top = @floatCast(dest_top),
            .right = @floatCast(dest_left + visible_display_width),
            .bottom = @floatCast(dest_top + visible_display_height),
        };
        const source_rect = d2d_common.D2D_RECT_F{
            .left = @as(f32, @floatCast(std.math.clamp(source_left, 0.0, @as(f64, @floatFromInt(preview_renderer.bitmap_width))))),
            .top = @as(f32, @floatCast(std.math.clamp(source_top, 0.0, @as(f64, @floatFromInt(preview_renderer.bitmap_height))))),
            .right = @as(f32, @floatCast(std.math.clamp(source_left + source_width, 0.0, @as(f64, @floatFromInt(preview_renderer.bitmap_width))))),
            .bottom = @as(f32, @floatCast(std.math.clamp(source_top + source_height, 0.0, @as(f64, @floatFromInt(preview_renderer.bitmap_height))))),
        };
        // Prefer ID2D1DeviceContext.DrawBitmap which supports
        // HIGH_QUALITY_CUBIC — a proper downsampling filter that avoids
        // the bilinear jaggies produced by ID2D1RenderTarget.DrawBitmap.
        var device_ctx: ?*d2d.ID2D1DeviceContext = null;
        const qi_hr = render_target.IUnknown.QueryInterface(d2d.IID_ID2D1DeviceContext, @ptrCast(&device_ctx));
        if (!hrFailed(qi_hr)) {
            if (device_ctx) |dc| {
                dc.DrawBitmap(
                    bitmap,
                    &dest_rect,
                    1.0,
                    d2d.D2D1_INTERPOLATION_MODE_HIGH_QUALITY_CUBIC,
                    &source_rect,
                    null,
                );
                _ = dc.IUnknown.Release();
            }
        } else {
            render_target.ID2D1RenderTarget.DrawBitmap(
                bitmap,
                &dest_rect,
                1.0,
                d2d.D2D1_BITMAP_INTERPOLATION_MODE_LINEAR,
                &source_rect,
            );
        }
    }

    _ = render_target.ID2D1RenderTarget.EndDraw(null, null);
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
            drawPreviewBitmap(hwnd);
            _ = gdi.EndPaint(hwnd, &paint);
            return 0;
        },
        else => return ui.DefWindowProcA(hwnd, message, w_param, l_param),
    }
}

// ---------------------------------------------------------------------------
// Canvas D2D / DWrite helpers
// ---------------------------------------------------------------------------

fn ensureCanvasD2DFactory() bool {
    if (canvas_renderer.factory == null) {
        var factory: ?*d2d.ID2D1Factory = null;
        const hr = d2d.D2D1CreateFactory(
            d2d.D2D1_FACTORY_TYPE_SINGLE_THREADED,
            d2d.IID_ID2D1Factory,
            null,
            @ptrCast(&factory),
        );
        if (hrFailed(hr) or factory == null) return false;
        canvas_renderer.factory = factory;
    }
    return true;
}

fn ensureCanvasDWriteFactory() bool {
    if (canvas_dwrite_factory == null) {
        var factory: ?*dwrite.IDWriteFactory = null;
        const hr = dwrite.DWriteCreateFactory(.SHARED, dwrite.IID_IDWriteFactory, @ptrCast(&factory));
        if (hrFailed(hr) or factory == null) return false;
        canvas_dwrite_factory = factory;
    }
    return true;
}

fn ensureCanvasRenderTarget(hwnd: ?foundation.HWND) bool {
    if (!ensureCanvasD2DFactory()) return false;
    const factory = canvas_renderer.factory orelse return false;
    const render_dpi: f32 = 96.0;

    var rect = std.mem.zeroes(foundation.RECT);
    if (ui.GetClientRect(hwnd, &rect) == 0) return false;
    const w = rect.right - rect.left;
    const h = rect.bottom - rect.top;
    if (w <= 0 or h <= 0) return false;
    const pixel_size = d2d_common.D2D_SIZE_U{ .width = @intCast(w), .height = @intCast(h) };

    if (canvas_renderer.render_target) |rt| {
        if (hrFailed(rt.Resize(&pixel_size))) {
            releaseUnknown(&canvas_renderer.render_target);
        } else {
            rt.ID2D1RenderTarget.SetDpi(render_dpi, render_dpi);
            return true;
        }
    }

    var target_props = d2d.D2D1_RENDER_TARGET_PROPERTIES{
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
    var hwnd_props = d2d.D2D1_HWND_RENDER_TARGET_PROPERTIES{
        .hwnd = hwnd,
        .pixelSize = pixel_size,
        .presentOptions = d2d.D2D1_PRESENT_OPTIONS_NONE,
    };

    var render_target: ?*d2d.ID2D1HwndRenderTarget = null;
    if (hrFailed(factory.CreateHwndRenderTarget(&target_props, &hwnd_props, @ptrCast(&render_target))) or render_target == null) {
        return false;
    }
    render_target.?.ID2D1RenderTarget.SetDpi(render_dpi, render_dpi);
    canvas_renderer.render_target = render_target;
    return true;
}

fn drawCanvasFrame(hwnd: ?foundation.HWND) void {
    if (!ensureCanvasRenderTarget(hwnd) or !ensureCanvasDWriteFactory()) return;
    const rt = canvas_renderer.render_target orelse return;
    const dw_factory = canvas_dwrite_factory orelse return;

    var rect = std.mem.zeroes(foundation.RECT);
    if (ui.GetClientRect(hwnd, &rect) == 0) return;
    const w: f32 = @floatFromInt(@max(1, rect.right - rect.left));
    const h: f32 = @floatFromInt(@max(1, rect.bottom - rect.top));

    const ctx = windows_canvas.draw.DrawContext{
        .render_target = &rt.ID2D1RenderTarget,
        .dwrite_factory = dw_factory,
        .viewport_width = w,
        .viewport_height = h,
    };

    rt.ID2D1RenderTarget.BeginDraw();
    if (canvas_renderer.canvas_state.graph) |graph| {
        windows_canvas.draw.drawCanvas(&ctx, graph, canvas_renderer.canvas_state.viewport, canvas_renderer.canvas_state.selection, canvas_renderer.canvas_state.hover);
    } else {
        var bg = rgba8Color(245, 245, 245, 255);
        rt.ID2D1RenderTarget.Clear(&bg);
    }
    _ = rt.ID2D1RenderTarget.EndDraw(null, null);
}

// ---------------------------------------------------------------------------
// Canvas child window proc
// ---------------------------------------------------------------------------

fn canvasWindowProc(
    hwnd: ?foundation.HWND,
    message: u32,
    w_param: foundation.WPARAM,
    l_param: foundation.LPARAM,
) callconv(.winapi) foundation.LRESULT {
    switch (message) {
        ui.WM_ERASEBKGND => return 1,
        ui.WM_PAINT => {
            var paint = std.mem.zeroes(gdi.PAINTSTRUCT);
            _ = gdi.BeginPaint(hwnd, &paint);
            drawCanvasFrame(hwnd);
            _ = gdi.EndPaint(hwnd, &paint);
            return 0;
        },
        ui.WM_SIZE => {
            if (canvas_renderer.render_target) |rt| {
                var rect = std.mem.zeroes(foundation.RECT);
                if (ui.GetClientRect(hwnd, &rect) != 0) {
                    const pw: u32 = @intCast(@max(0, rect.right - rect.left));
                    const ph: u32 = @intCast(@max(0, rect.bottom - rect.top));
                    _ = rt.Resize(&d2d_common.D2D_SIZE_U{ .width = pw, .height = ph });
                }
            }
            _ = gdi.InvalidateRect(hwnd, null, 0);
            return 0;
        },
        ui.WM_LBUTTONDOWN => {
            _ = mouse.SetFocus(hwnd);
            const pos = mouseCoordFromLParam(l_param);
            const result = windows_canvas.interaction.onLeftButtonDown(
                &canvas_renderer.canvas_state,
                hwnd,
                pos.x,
                pos.y,
            );
            if (result.selection_changed) {
                windows_canvas.inspector.refresh(&canvas_renderer.inspector, &canvas_renderer.canvas_state);
            }
            if (result.needs_redraw) _ = gdi.InvalidateRect(hwnd, null, 0);
            return 0;
        },
        ui.WM_MOUSEMOVE => {
            const pos = mouseCoordFromLParam(l_param);
            const result = windows_canvas.interaction.onMouseMove(
                &canvas_renderer.canvas_state,
                pos.x,
                pos.y,
            );
            if (result.selection_changed) {
                windows_canvas.inspector.refresh(&canvas_renderer.inspector, &canvas_renderer.canvas_state);
            }
            if (result.needs_redraw) _ = gdi.InvalidateRect(hwnd, null, 0);
            return 0;
        },
        ui.WM_LBUTTONUP => {
            const pos = mouseCoordFromLParam(l_param);
            _ = windows_canvas.interaction.onLeftButtonUp(
                &canvas_renderer.canvas_state,
                pos.x,
                pos.y,
            );
            return 0;
        },
        ui.WM_MOUSEWHEEL => {
            const delta = wheelDeltaFromWParam(w_param);
            var pt = foundation.POINT{
                .x = mouseCoordFromLParam(l_param).x,
                .y = mouseCoordFromLParam(l_param).y,
            };
            _ = gdi.ScreenToClient(hwnd, &pt);
            const result = windows_canvas.interaction.onMouseWheel(
                &canvas_renderer.canvas_state,
                pt.x,
                pt.y,
                delta,
            );
            if (result.needs_redraw) _ = gdi.InvalidateRect(hwnd, null, 0);
            return 0;
        },
        ui.WM_RBUTTONDOWN => {
            const pos = mouseCoordFromLParam(l_param);
            const result = windows_canvas.interaction.onRightButtonDown(
                &canvas_renderer.canvas_state,
                pos.x,
                pos.y,
            );
            if (result.selection_changed) {
                windows_canvas.inspector.refresh(&canvas_renderer.inspector, &canvas_renderer.canvas_state);
            }
            if (result.needs_redraw) _ = gdi.InvalidateRect(hwnd, null, 0);
            return 0;
        },
        ui.WM_MBUTTONDOWN => {
            const pos = mouseCoordFromLParam(l_param);
            _ = windows_canvas.interaction.onMiddleButtonDown(
                &canvas_renderer.canvas_state,
                hwnd,
                pos.x,
                pos.y,
            );
            return 0;
        },
        ui.WM_MBUTTONUP => {
            const result = windows_canvas.interaction.onMiddleButtonUp(
                &canvas_renderer.canvas_state,
            );
            if (result.needs_redraw) _ = gdi.InvalidateRect(hwnd, null, 0);
            return 0;
        },
        ui.WM_LBUTTONDBLCLK => {
            // Double-click selects the object (same as single click for now).
            // This ensures clicking text feels responsive — the first click
            // selects, the double-click confirms the selection.
            _ = mouse.SetFocus(hwnd);
            const pos = mouseCoordFromLParam(l_param);
            const result = windows_canvas.interaction.onLeftButtonDown(
                &canvas_renderer.canvas_state,
                hwnd,
                pos.x,
                pos.y,
            );
            if (result.selection_changed) {
                windows_canvas.inspector.refresh(&canvas_renderer.inspector, &canvas_renderer.canvas_state);
            }
            if (result.needs_redraw) _ = gdi.InvalidateRect(hwnd, null, 0);
            return 0;
        },
        ui.WM_KEYDOWN, ui.WM_SYSKEYDOWN => {
            const vkey: u16 = @truncate(w_param);
            const result = windows_canvas.interaction.onKeyDown(&canvas_renderer.canvas_state, vkey);
            if (result.selection_changed) {
                windows_canvas.inspector.refresh(&canvas_renderer.inspector, &canvas_renderer.canvas_state);
            }
            if (result.needs_redraw) _ = gdi.InvalidateRect(hwnd, null, 0);
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

    // Canvas child window — hidden at startup (app starts in mermaid mode).
    const canvas = ui.CreateWindowExA(
        .{},
        canvas_class_name,
        null,
        makeStyle(styleBits(ui.WS_CHILD) | styleBits(ui.WS_CLIPSIBLINGS) | styleBits(ui.WS_TABSTOP)),
        0,
        0,
        100,
        100,
        hwnd,
        null,
        h_instance,
        null,
    ) orelse return false;
    child_windows.canvas = canvas;

    // Inspector panel (freeform mode sidebar).
    canvas_renderer.inspector = windows_canvas.inspector.createInspector(hwnd, h_instance);
    windows_canvas.inspector.setCanvasRef(&canvas_renderer.canvas_state, child_windows.canvas, &canvas_renderer.inspector);

    initializeToolbarControl();
    configureShellFonts();
    configureEditorControl();
    refreshStatusDisplay();
    return true;
}

fn layoutChildWindows(hwnd: ?foundation.HWND) void {
    windows_layout.applyChildLayout(hwnd, child_windows);
    var client_rect = std.mem.zeroes(foundation.RECT);
    if (ui.GetClientRect(hwnd, &client_rect) != 0) {
        const layout = Layout{};
        const status_y = client_rect.bottom - client_rect.top - layout.status_height;
        const content_top = layout.padding;
        const content_height = status_y - content_top - layout.gutter;
        if (content_height > 0) {
            windows_canvas.inspector.layoutInspector(
                &canvas_renderer.inspector,
                client_rect.right - client_rect.left,
                content_top,
                content_height,
                layout.inspector_width,
            );
        }
    }
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

fn updateEditorDerivedState(reset_view: bool) void {
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
        clearPreviewImageState();
        const status_text = std.fmt.allocPrint(c_allocator, "{s}", .{syntax_text}) catch return;
        defer c_allocator.free(status_text);
        setStatusMessage(status_text);
        requestPreviewRefresh();
        return;
    }

    var preview_message: [256]u8 = std.mem.zeroes([256]u8);
    var preview_png_len: u32 = 0;
    const preview_png_ptr = merrow_studio_render_preview_png_bytes(
        editor_text.ptr,
        @intCast(editor_text.len),
        &preview_png_len,
        &preview_message,
        preview_message.len,
    );
    const preview_status = std.mem.sliceTo(&preview_message, 0);

    if (preview_png_ptr == null or preview_png_len == 0) {
        clearPreviewImageState();
        setStatusMessage(if (preview_status.len > 0) preview_status else syntax_text);
        requestPreviewRefresh();
        return;
    }
    defer merrow_studio_free_buffer(preview_png_ptr, preview_png_len);

    const preview_png = preview_png_ptr[0..preview_png_len];

    if (!replacePreviewPng(preview_png) or !syncPreviewBitmapFromMemory(child_windows.preview)) {
        clearPreviewImageState();
        setStatusMessage("Preview image load failed");
        requestPreviewRefresh();
        return;
    }

    if (reset_view) {
        resetPreviewView(child_windows.preview);
    }

    const status_text = std.fmt.allocPrint(
        c_allocator,
        "{s} | {s}",
        .{ syntax_text, if (preview_status.len > 0) preview_status else "Preview ready" },
    ) catch return;
    defer c_allocator.free(status_text);
    setStatusMessage(status_text);
    requestPreviewRefresh();
}

fn applyUpdatedSource(source: []const u8, status_text: []const u8) void {
    setEditorText(source);
    setStatusMessage(status_text);
    updateEditorDerivedState(false);
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

/// Switch the app between Mermaid source mode and Freeform canvas mode.
/// Shows / hides the appropriate child windows and triggers a layout pass.
fn switchToMode(new_mode: AppMode) void {
    if (app_mode == new_mode) return;
    app_mode = new_mode;

    switch (new_mode) {
        .mermaid => {
            // Show Mermaid pane: preview + editor + command bar.
            if (child_windows.preview) |w| _ = ui.ShowWindow(w, ui.SW_SHOWNA);
            if (child_windows.editor) |w| _ = ui.ShowWindow(w, ui.SW_SHOWNA);
            if (child_windows.toolbar) |w| _ = ui.ShowWindow(w, ui.SW_SHOWNA);
            if (child_windows.command) |w| _ = ui.ShowWindow(w, ui.SW_SHOWNA);
            if (child_windows.apply_button) |w| _ = ui.ShowWindow(w, ui.SW_SHOWNA);
            // Hide canvas pane.
            if (child_windows.canvas) |w| _ = ui.ShowWindow(w, ui.SW_HIDE);
            windows_canvas.inspector.show(&canvas_renderer.inspector, false);
            setStatusMessage("Mermaid source mode");
        },
        .freeform => {
            // Build the editable graph from the current source.
            const source = getEditorText(c_allocator) catch {
                setStatusMessage("Could not read source for canvas mode");
                return;
            };
            defer c_allocator.free(source);

            var eg_message: [256]u8 = std.mem.zeroes([256]u8);
            const eg = merrow_studio_build_editable_graph(
                source.ptr,
                @intCast(source.len),
                &eg_message,
                eg_message.len,
            );
            canvas_renderer.canvas_state.setGraph(eg);

            // Show canvas pane; hide Mermaid pane.
            if (child_windows.canvas) |w| _ = ui.ShowWindow(w, ui.SW_SHOWNA);
            windows_canvas.inspector.show(&canvas_renderer.inspector, true);
            if (child_windows.preview) |w| _ = ui.ShowWindow(w, ui.SW_HIDE);
            if (child_windows.editor) |w| _ = ui.ShowWindow(w, ui.SW_HIDE);
            if (child_windows.toolbar) |w| _ = ui.ShowWindow(w, ui.SW_HIDE);
            if (child_windows.command) |w| _ = ui.ShowWindow(w, ui.SW_HIDE);
            if (child_windows.apply_button) |w| _ = ui.ShowWindow(w, ui.SW_HIDE);

            // Layout must happen BEFORE fitToViewport so the canvas window
            // has its real dimensions (not the 100x100 creation default).
            layoutChildWindows(main_window);

            // Now fit the viewport using the real canvas size.
            if (child_windows.canvas) |cw| {
                var r = std.mem.zeroes(foundation.RECT);
                if (ui.GetClientRect(cw, &r) != 0) {
                    canvas_renderer.canvas_state.fitToViewport(
                        @floatFromInt(r.right - r.left),
                        @floatFromInt(r.bottom - r.top),
                    );
                }
            }

            windows_canvas.inspector.refresh(&canvas_renderer.inspector, &canvas_renderer.canvas_state);

            const eg_status = std.mem.sliceTo(&eg_message, 0);
            setStatusMessage(if (eg == null) eg_status else "Freeform canvas mode");
        },
    }

    layoutChildWindows(main_window);
    _ = gdi.RedrawWindow(
        main_window,
        null,
        null,
        makeRedrawFlags(
            redrawFlagsBits(gdi.RDW_INVALIDATE) |
                redrawFlagsBits(gdi.RDW_ERASE) |
                redrawFlagsBits(gdi.RDW_ALLCHILDREN) |
                redrawFlagsBits(gdi.RDW_ERASENOW),
        ),
    );
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
            updateEditorDerivedState(true);
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
                    menu_id_mode_mermaid => {
                        switchToMode(.mermaid);
                        return 0;
                    },
                    menu_id_mode_freeform => {
                        switchToMode(.freeform);
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
                updateEditorDerivedState(false);
                return 0;
            }
            return ui.DefWindowProcA(hwnd, message, w_param, l_param);
        },
        ui.WM_INITMENUPOPUP => {
            // Tick the active mode in the View menu.
            const hmenu: ui.HMENU = @ptrFromInt(@as(usize, @bitCast(w_param)));
            _ = ui.CheckMenuItem(hmenu, menu_id_mode_mermaid, if (app_mode == .mermaid) @as(u32, @bitCast(ui.MF_CHECKED)) else @as(u32, @bitCast(ui.MF_UNCHECKED)));
            _ = ui.CheckMenuItem(hmenu, menu_id_mode_freeform, if (app_mode == .freeform) @as(u32, @bitCast(ui.MF_CHECKED)) else @as(u32, @bitCast(ui.MF_UNCHECKED)));
            return 0;
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
            clearPreviewImageState();
            freeCurrentDocumentPath();
            freeCurrentStatusMessage();
            releaseShellFont();
            releaseEditorFont();
            unregisterPreviewFont();
            releaseUnknown(&preview_renderer.render_target);
            releaseUnknown(&preview_renderer.wic_factory);
            releaseUnknown(&preview_renderer.factory);
            if (preview_renderer.com_initialized) {
                com.CoUninitialize();
                preview_renderer.com_initialized = false;
            }
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

    var canvas_class = std.mem.zeroes(ui.WNDCLASSEXA);
    canvas_class.cbSize = @sizeOf(ui.WNDCLASSEXA);
    canvas_class.style = ui.CS_DBLCLKS;
    canvas_class.lpfnWndProc = canvasWindowProc;
    canvas_class.hInstance = h_instance;
    canvas_class.hCursor = ui.LoadCursorW(null, ui.IDC_ARROW);
    canvas_class.lpszClassName = canvas_class_name;
    if (ui.RegisterClassExA(&canvas_class) == 0) {
        return 1;
    }

    // Inspector panel uses its own window class.
    _ = windows_canvas.inspector.registerInspectorClass(h_instance);

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
