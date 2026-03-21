const std = @import("std");
const win32 = @import("win32");
const merrow = @import("merrow");
const ffm_serializer = @import("../ffm_serializer.zig");
const library_db = @import("../library_db.zig");
const markdown_parser = @import("../markdown_parser.zig");
const document_model = @import("../document_model.zig");
const merrow_lexer = merrow.lexer;
const windows_app_state = @import("windows/app_state.zig");
const windows_canvas = @import("windows/canvas.zig");
const windows_common = @import("windows/common.zig");
const windows_constants = @import("windows/constants.zig");
const windows_dpi = @import("windows/dpi.zig");
const windows_document = @import("windows/document.zig");
const windows_editor = @import("windows/editor.zig");
const windows_layout = @import("windows/layout.zig");
const windows_project_settings = @import("windows/project_settings.zig");
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
const combo_box_class = windows_constants.combo_box_class;
const status_placeholder = windows_constants.status_placeholder;
const file_menu_label = windows_constants.file_menu_label;
const menu_open_label = windows_constants.menu_open_label;
const menu_save_label = windows_constants.menu_save_label;
const menu_save_as_label = windows_constants.menu_save_as_label;
const menu_export_word_label = windows_constants.menu_export_word_label;
const open_dialog_title = windows_constants.open_dialog_title;
const save_dialog_title = windows_constants.save_dialog_title;
const export_word_dialog_title = windows_constants.export_word_dialog_title;
const default_extension = windows_constants.default_extension;
const word_default_extension = windows_constants.word_default_extension;
const mermaid_dialog_filter = windows_constants.mermaid_dialog_filter;
const word_dialog_filter = windows_constants.word_dialog_filter;
const initial_source = windows_constants.initial_source;
const menu_id_open = windows_constants.menu_id_open;
const menu_id_save = windows_constants.menu_id_save;
const menu_id_save_as = windows_constants.menu_id_save_as;
const menu_id_font_settings = windows_constants.menu_id_font_settings;
const menu_id_export_word = windows_constants.menu_id_export_word;
const control_id_editor = windows_constants.control_id_editor;
const control_id_command = windows_constants.control_id_command;
const control_id_apply_button = windows_constants.control_id_apply_button;
const control_id_diagram_selector = windows_constants.control_id_diagram_selector;
const control_id_diagram_prev = windows_constants.control_id_diagram_prev;
const control_id_diagram_next = windows_constants.control_id_diagram_next;
const control_id_diagram_label = windows_constants.control_id_diagram_label;
const main_timer_id_editor_refresh = windows_constants.main_timer_id_editor_refresh;
const main_timer_id_ffm_persist = windows_constants.main_timer_id_ffm_persist;
const menu_id_mode_mermaid = windows_constants.menu_id_mode_mermaid;
const menu_id_mode_freeform = windows_constants.menu_id_mode_freeform;
const menu_id_toggle_source_panel = windows_constants.menu_id_toggle_source_panel;
const toolbar_id_reserved_1 = windows_constants.toolbar_id_reserved_1;
const toolbar_id_reserved_2 = windows_constants.toolbar_id_reserved_2;
const toolbar_id_reserved_3 = windows_constants.toolbar_id_reserved_3;
const toolbar_slot_1_label = windows_constants.toolbar_slot_1_label;
const toolbar_slot_2_label = windows_constants.toolbar_slot_2_label;
const toolbar_slot_3_label = windows_constants.toolbar_slot_3_label;
const Layout = windows_constants.Layout;
const ViewAnchor = windows_constants.ViewAnchor;
const wm_mouseleave: u32 = 0x02A3;
const tme_leave: u32 = 0x00000002;

const TRACKMOUSEEVENT = extern struct {
    cbSize: u32,
    dwFlags: u32,
    hwndTrack: ?foundation.HWND,
    dwHoverTime: u32,
};

extern "user32" fn TrackMouseEvent(event_track: *TRACKMOUSEEVENT) callconv(.winapi) i32;

const AppMode = windows_app_state.AppMode;
const ChildWindows = windows_app_state.ChildWindows;
const PreviewRenderer = windows_app_state.PreviewRenderer;
const CanvasRenderer = windows_app_state.CanvasRenderer;
const CanvasDimensions = windows_project_settings.CanvasDimensions;
const ProjectFontSettings = windows_project_settings.ProjectFontSettings;
const ModuleHandle = @TypeOf(loader.LoadLibraryA("Riched20.dll").?);
const wcg_status = u32;
const wcg_library = ?*anyopaque;
const wcg_session = ?*anyopaque;
const wcg_document = ?*anyopaque;

const WCG_ABI_VERSION: u32 = 1;
const WCG_OK: wcg_status = 0;
const WCG_HIDDEN: u32 = 1;
const WCG_UNIT_PCT_CONTENT: u32 = 4;
const WCG_BANNER_ALL_PAGES: u32 = 0;
const WCG_TRAILER_FOOTER: u32 = 0;

const wcg_measurement = extern struct {
    unit: u32,
    value: f64,
};

const wcg_runtime_options = extern struct {
    abi_version: u32,
    flags: u32,
};

const wcg_word_options = extern struct {
    visibility: u32,
    flags: u32,
};

const wcg_font_spec = extern struct {
    utf8_family: ?[*:0]const u8,
    size_points: f64,
    flags: u32,
};

const wcg_heading_options = extern struct {
    level: u32,
    alignment: u32,
    spacing_before: wcg_measurement,
    spacing_after: wcg_measurement,
    page_break_before: u32,
    utf8_style_override: ?[*:0]const u8,
};

const wcg_paragraph_options = extern struct {
    alignment: u32,
    spacing_before: wcg_measurement,
    spacing_after: wcg_measurement,
    line_spacing: f64,
    utf8_style_override: ?[*:0]const u8,
};

const wcg_banner_options = extern struct {
    scope: u32,
    preserve_aspect_ratio: u32,
    spacing_after: wcg_measurement,
};

const wcg_trailer_options = extern struct {
    mode: u32,
    preserve_aspect_ratio: u32,
    repeat_every_page: u32,
    spacing_before: wcg_measurement,
};

const wcg_image_options = extern struct {
    placement: u32,
    alignment: u32,
    wrap: u32,
    width: wcg_measurement,
    height: wcg_measurement,
    max_width: wcg_measurement,
    max_height: wcg_measurement,
    spacing_before: wcg_measurement,
    spacing_after: wcg_measurement,
    preserve_aspect_ratio: u32,
    utf8_caption: ?[*:0]const u8,
    utf8_alt_text: ?[*:0]const u8,
};

const wcg_close_options = extern struct {
    save_before_close: u32,
};

const wcg_pdf_options = extern struct {
    open_after_export: u32,
    optimize_for: u32,
    range: u32,
    from_page: u32,
    to_page: u32,
    item: u32,
    include_doc_props: u32,
    keep_irm: u32,
    create_bookmarks: u32,
    doc_structure_tags: u32,
    bitmap_missing_fonts: u32,
    use_pdfa: u32,
};

const wcg_error_info = extern struct {
    status: wcg_status,
    hresult: i32,
    system_error: u32,
    utf8_message: ?[*:0]const u8,
    utf8_function: ?[*:0]const u8,
};

const wcg_create_library_fn = *const fn (options: ?*const wcg_runtime_options, out_library: *wcg_library) callconv(.c) wcg_status;
const wcg_destroy_library_fn = *const fn (library: wcg_library) callconv(.c) wcg_status;
const wcg_start_word_fn = *const fn (library: wcg_library, options: ?*const wcg_word_options, out_session: *wcg_session) callconv(.c) wcg_status;
const wcg_shutdown_word_fn = *const fn (session: wcg_session) callconv(.c) wcg_status;
const wcg_create_document_fn = *const fn (session: wcg_session, out_document: *wcg_document) callconv(.c) wcg_status;
const wcg_save_document_as_fn = *const fn (document: wcg_document, utf8_path: [*:0]const u8, options: ?*const anyopaque) callconv(.c) wcg_status;
const wcg_export_pdf_fn = *const fn (document: wcg_document, utf8_path: [*:0]const u8, options: ?*const wcg_pdf_options) callconv(.c) wcg_status;
const wcg_close_document_fn = *const fn (document: wcg_document, options: ?*const wcg_close_options) callconv(.c) wcg_status;
const wcg_set_document_font_fn = *const fn (document: wcg_document, font: ?*const wcg_font_spec) callconv(.c) wcg_status;
const wcg_insert_heading_fn = *const fn (document: wcg_document, utf8_text: [*:0]const u8, options: ?*const wcg_heading_options) callconv(.c) wcg_status;
const wcg_insert_paragraph_fn = *const fn (document: wcg_document, utf8_text: [*:0]const u8, options: ?*const wcg_paragraph_options) callconv(.c) wcg_status;
const wcg_insert_header_banner_fn = *const fn (document: wcg_document, utf8_png_path: [*:0]const u8, options: ?*const wcg_banner_options) callconv(.c) wcg_status;
const wcg_insert_footer_trailer_fn = *const fn (document: wcg_document, utf8_png_path: [*:0]const u8, options: ?*const wcg_trailer_options) callconv(.c) wcg_status;
const wcg_insert_image_fn = *const fn (document: wcg_document, utf8_png_path: [*:0]const u8, options: ?*const wcg_image_options) callconv(.c) wcg_status;
const wcg_get_last_error_fn = *const fn (library: wcg_library, out_error: *wcg_error_info) callconv(.c) wcg_status;

const WordComGlueApi = struct {
    create_library: wcg_create_library_fn,
    destroy_library: wcg_destroy_library_fn,
    start_word: wcg_start_word_fn,
    shutdown_word: wcg_shutdown_word_fn,
    create_document: wcg_create_document_fn,
    save_document_as: wcg_save_document_as_fn,
    export_pdf: wcg_export_pdf_fn,
    close_document: wcg_close_document_fn,
    set_document_font: wcg_set_document_font_fn,
    insert_heading: wcg_insert_heading_fn,
    insert_paragraph: wcg_insert_paragraph_fn,
    insert_header_banner: wcg_insert_header_banner_fn,
    insert_footer_trailer: wcg_insert_footer_trailer_fn,
    insert_image: wcg_insert_image_fn,
    get_last_error: wcg_get_last_error_fn,
};

extern fn merrow_studio_build_editable_graph(source_ptr: [*]const u8, source_len: u32, out_message: [*]u8, out_message_len: u32) callconv(.c) ?*windows_canvas.StudioEditableGraph;
extern fn merrow_studio_check_mermaid_syntax(source_ptr: [*]const u8, source_len: u32, out_message: [*]u8, out_message_len: u32) callconv(.c) c_int;
extern fn merrow_studio_render_editable_graph_png_bytes(graph: ?*const windows_canvas.StudioEditableGraph, target_width: u32, target_height: u32, out_png_len: *u32, out_message: [*]u8, out_message_len: u32) callconv(.c) [*c]u8;
extern fn merrow_studio_render_preview_png_bytes(source_ptr: [*]const u8, source_len: u32, target_width: u32, target_height: u32, out_png_len: *u32, out_message: [*]u8, out_message_len: u32) callconv(.c) [*c]u8;
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
var current_markdown_document: ?document_model.MarkdownDocument = null;
var selected_diagram_index: usize = 0;
var show_source_panel_in_freeform = false;
var library_database: ?library_db.LibraryDb = null;
var project_font_settings = ProjectFontSettings{};
var private_font_path: ?[:0]u8 = null;
var rich_edit_module: ?@TypeOf(loader.LoadLibraryA("Riched20.dll").?) = null;
var wordcomglue_module: ?ModuleHandle = null;
var wordcomglue_api: ?WordComGlueApi = null;
var startup_preflight_message: ?[]u8 = null;
var editor_font: ?gdi.HFONT = null;

const export_editable_graph_type_flowchart: u32 = 0;
const export_editable_graph_type_sequence: u32 = 1;
var shell_font: ?gdi.HFONT = null;
var status_font: ?gdi.HFONT = null;
var current_status_message: ?[]u8 = null;
var is_document_dirty = false;
var suppress_editor_change = false;
var last_editor_text_hash: u64 = 0;

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
const ffm_persist_debounce_ms: u32 = 450;
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
    const page_width = previewPageWidth();
    const bitmap_width: i32 = @intFromFloat(@round(previewBitmapLogicalWidth()));
    return @max(page_width, bitmap_width);
}

fn previewLogicalHeight() i32 {
    const page_height = previewPageHeight();
    const bitmap_height: i32 = @intFromFloat(@round(previewBitmapLogicalHeight()));
    return @max(page_height, bitmap_height);
}

fn previewPageWidth() i32 {
    const dims = currentProjectCanvasDimensions();
    return @intCast(dims.width);
}

fn previewPageHeight() i32 {
    const dims = currentProjectCanvasDimensions();
    return @intCast(dims.height);
}

fn previewBitmapLogicalWidth() f64 {
    return @as(f64, @floatFromInt(preview_renderer.bitmap_width)) / preview_bitmap_scale;
}

fn previewBitmapLogicalHeight() f64 {
    return @as(f64, @floatFromInt(preview_renderer.bitmap_height)) / preview_bitmap_scale;
}

fn freeCurrentDocumentPath() void {
    windows_document.freeCurrentDocumentPath(c_allocator, &current_document_path);
}

fn freeCurrentMarkdownDocument() void {
    if (current_markdown_document) |*document| {
        document.deinit();
        current_markdown_document = null;
    }
    selected_diagram_index = 0;
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

fn freeStartupPreflightMessage() void {
    if (startup_preflight_message) |message| {
        c_allocator.free(message);
        startup_preflight_message = null;
    }
}

fn showStartupErrorMessage(text: []const u8) void {
    const z_text = dupeSentinel(c_allocator, text) catch return;
    defer c_allocator.free(z_text);
    _ = ui.MessageBoxA(null, z_text.ptr, "Merrow Startup Error", ui.MB_ICONERROR);
}

fn runWindowsPreflight() bool {
    freeStartupPreflightMessage();

    const folders = windows_document.getMerrowUserFolders(c_allocator) catch |err| {
        const text = std.fmt.allocPrint(
            c_allocator,
            "Could not prepare Merrow folders under Documents: {s}",
            .{@errorName(err)},
        ) catch null;
        if (text) |message| {
            defer c_allocator.free(message);
            showStartupErrorMessage(message);
        } else {
            showStartupErrorMessage("Could not prepare Merrow folders under Documents.");
        }
        return false;
    };
    defer folders.deinit(c_allocator);

    const db_path = windows_document.defaultLibraryDbPath(c_allocator) catch null;
    defer if (db_path) |path| c_allocator.free(path);

    startup_preflight_message = if (db_path) |path|
        std.fmt.allocPrint(
            c_allocator,
            "Merrow folders ready: {s} | SQLite library path reserved: {s}",
            .{ folders.root, path },
        ) catch null
    else
        std.fmt.allocPrint(
            c_allocator,
            "Merrow folders ready: {s} | SQLite schema staged for {s}",
            .{ folders.root, library_db.database_file_name },
        ) catch null;

    return true;
}

fn closeLibraryDatabase() void {
    if (library_database) |*db| {
        db.close() catch {};
        library_database = null;
    }
}

fn openLibraryDatabase() void {
    closeLibraryDatabase();

    const db_path = windows_document.defaultLibraryDbPath(c_allocator) catch {
        setStatusMessage("Failed to resolve SQLite library path");
        return;
    };
    defer c_allocator.free(db_path);

    var db = library_db.LibraryDb.open(db_path) catch {
        setStatusMessage("SQLite library unavailable; freeform persistence disabled");
        return;
    };
    errdefer db.close() catch {};

    db.ensureSchema() catch {
        setStatusMessage("SQLite schema initialization failed; freeform persistence disabled");
        return;
    };

    library_database = db;
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

fn chooseExportWordPath() ?[]u8 {
    const suggested_path = buildDefaultWordExportPath() catch null;
    defer if (suggested_path) |path| c_allocator.free(path);

    return windows_document.chooseCustomPath(
        c_allocator,
        main_window,
        suggested_path,
        true,
        word_dialog_filter,
        export_word_dialog_title,
        word_default_extension,
    );
}

fn loadSourceFromPath(path: []const u8) ![]u8 {
    return windows_document.loadSourceFromPath(c_allocator, path);
}

fn saveSourceToPath(path: []const u8, source: []const u8) !void {
    return windows_document.saveSourceToPath(path, source);
}

fn currentProjectCanvasDimensions() CanvasDimensions {
    return windows_project_settings.canvasPresetDimensions(project_font_settings.canvas_preset);
}

fn applyProjectSettingsToGraph(graph: *windows_canvas.StudioEditableGraph) void {
    const canvas_dims = currentProjectCanvasDimensions();
    graph.width = @floatFromInt(canvas_dims.width);
    graph.height = @floatFromInt(canvas_dims.height);

    if (graph.nodes != null) {
        for (graph.nodes[0..graph.node_count]) |*node| {
            node.label_font_size = project_font_settings.node_label_size;
        }
    }
    if (graph.subgraphs != null) {
        for (graph.subgraphs[0..graph.subgraph_count]) |*subgraph| {
            subgraph.title_font_size = project_font_settings.group_title_size;
        }
    }
    if (graph.edges != null) {
        for (graph.edges[0..graph.edge_count]) |*edge| {
            edge.label_font_size = project_font_settings.edge_label_size;
        }
    }
}

fn applyProjectSettingsToCanvas(refresh_inspector: bool) void {
    const graph = canvas_renderer.canvas_state.graph orelse return;
    applyProjectSettingsToGraph(graph);

    if (child_windows.canvas) |canvas_hwnd| {
        _ = gdi.InvalidateRect(canvas_hwnd, null, 0);
    }
    if (refresh_inspector and app_mode == .freeform) {
        windows_canvas.inspector.refresh(&canvas_renderer.inspector, &canvas_renderer.canvas_state);
    }
}

fn refreshCurrentMarkdownDocument(source: []const u8) bool {
    freeCurrentMarkdownDocument();

    const document = markdown_parser.parseSourceDocument(c_allocator, source, current_document_path) catch {
        setStatusMessage("Failed to parse source document");
        return false;
    };

    if (document.diagram_count == 0) {
        selected_diagram_index = 0;
    } else if (selected_diagram_index >= document.diagram_count) {
        selected_diagram_index = 0;
    }

    current_markdown_document = document;
    updateDiagramSelectorControl();
    return true;
}

fn currentSelectedDiagramBlock() ?*const document_model.DiagramBlock {
    if (current_markdown_document) |*document| {
        return document.diagramAt(selected_diagram_index);
    }
    return null;
}

fn duplicateSelectedDiagramSource(allocator: std.mem.Allocator) ![]u8 {
    const diagram = currentSelectedDiagramBlock() orelse return error.NoDiagramSelected;
    return allocator.dupe(u8, diagram.mermaid_source);
}

fn replaceSelectedDiagramSource(updated_diagram_source: []const u8) ![]u8 {
    const document = current_markdown_document orelse return c_allocator.dupe(u8, updated_diagram_source);
    const block_index = document.blockIndexForDiagram(selected_diagram_index) orelse return c_allocator.dupe(u8, updated_diagram_source);
    const block = switch (document.blocks[block_index]) {
        .diagram => |diagram| diagram,
        else => return c_allocator.dupe(u8, updated_diagram_source),
    };

    var combined = std.ArrayList(u8){};
    defer combined.deinit(c_allocator);

    try combined.appendSlice(c_allocator, document.source[0..block.start_offset]);
    try combined.appendSlice(c_allocator, updated_diagram_source);
    try combined.appendSlice(c_allocator, document.source[block.end_offset..]);
    return combined.toOwnedSlice(c_allocator);
}

fn adjustDiagnosticForDiagram(diagnostic: windows_editor.EditorDiagnostic, diagram: *const document_model.DiagramBlock) windows_editor.EditorDiagnostic {
    var adjusted = diagnostic;
    if (adjusted.line) |line| adjusted.line = line + diagram.start_line - 1;
    adjusted.start += diagram.start_offset;
    adjusted.end += diagram.start_offset;
    return adjusted;
}

fn clearCanvasGraphIfNeeded() void {
    canvas_renderer.canvas_state.clearGraph();
    windows_canvas.inspector.refresh(&canvas_renderer.inspector, &canvas_renderer.canvas_state);
    if (child_windows.canvas) |canvas_hwnd| _ = gdi.InvalidateRect(canvas_hwnd, null, 0);
}

fn previewStatusPrefix() []const u8 {
    const document = current_markdown_document orelse return "Preview ready";
    if (document.diagram_count == 0) return "No mermaid diagrams found";
    if (document.diagram_count == 1) return "Preview ready";
    const diagram = currentSelectedDiagramBlock() orelse return "Preview ready";
    return diagram.name orelse "Preview ready";
}

fn sourcePanelVisible() bool {
    return app_mode == .mermaid or show_source_panel_in_freeform;
}

fn updateDiagramHeaderControls() void {
    const label = child_windows.diagram_label;
    const prev_button = child_windows.diagram_prev_button;
    const next_button = child_windows.diagram_next_button;

    if (label == null or prev_button == null or next_button == null) return;

    setWindowText(prev_button, "Prev");
    setWindowText(next_button, "Next");

    const document = current_markdown_document orelse {
        setWindowText(label, "Diagrams");
        return;
    };

    if (document.diagram_count == 0) {
        setWindowText(label, "No diagrams");
        return;
    }

    const safe_index = @min(selected_diagram_index, document.diagram_count - 1);
    if (document.diagramAt(safe_index)) |diagram| {
        if (diagram.name) |name| {
            const header_text = std.fmt.allocPrint(c_allocator, "{d}/{d}  {s}", .{ safe_index + 1, document.diagram_count, name }) catch null;
            defer if (header_text) |text| c_allocator.free(text);
            if (header_text) |text| {
                setWindowText(label, text);
                return;
            }
        }

        const fallback = std.fmt.allocPrint(c_allocator, "Diagram {d} of {d}", .{ safe_index + 1, document.diagram_count }) catch null;
        defer if (fallback) |text| c_allocator.free(text);
        if (fallback) |text| {
            setWindowText(label, text);
            return;
        }
    }

    setWindowText(label, "Diagrams");
}

fn applyModeVisibility() void {
    const show_source_panel = sourcePanelVisible();

    if (child_windows.preview) |w| _ = ui.ShowWindow(w, if (app_mode == .mermaid) ui.SW_SHOWNA else ui.SW_HIDE);
    if (child_windows.canvas) |w| _ = ui.ShowWindow(w, if (app_mode == .freeform) ui.SW_SHOWNA else ui.SW_HIDE);

    if (child_windows.editor) |w| _ = ui.ShowWindow(w, if (show_source_panel) ui.SW_SHOWNA else ui.SW_HIDE);
    if (child_windows.command) |w| _ = ui.ShowWindow(w, if (show_source_panel) ui.SW_SHOWNA else ui.SW_HIDE);
    if (child_windows.apply_button) |w| _ = ui.ShowWindow(w, if (show_source_panel) ui.SW_SHOWNA else ui.SW_HIDE);

    if (child_windows.toolbar) |w| _ = ui.ShowWindow(w, if (app_mode == .mermaid) ui.SW_SHOWNA else ui.SW_HIDE);
    if (child_windows.diagram_label) |w| _ = ui.ShowWindow(w, ui.SW_SHOWNA);
    if (child_windows.diagram_selector) |w| _ = ui.ShowWindow(w, ui.SW_SHOWNA);
    if (child_windows.diagram_prev_button) |w| _ = ui.ShowWindow(w, ui.SW_SHOWNA);
    if (child_windows.diagram_next_button) |w| _ = ui.ShowWindow(w, ui.SW_SHOWNA);

    if (app_mode == .freeform) {
        windows_canvas.inspector.show(&canvas_renderer.inspector, true);
    } else {
        windows_canvas.inspector.setFontInspectorActive(false);
        windows_canvas.inspector.show(&canvas_renderer.inspector, false);
    }
}

fn toggleSourcePanelVisibility() void {
    if (app_mode != .freeform) {
        setStatusMessage("Source panel is always visible in Mermaid mode");
        return;
    }

    show_source_panel_in_freeform = !show_source_panel_in_freeform;
    applyModeVisibility();
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
    setStatusMessage(if (show_source_panel_in_freeform) "Source panel shown" else "Source panel hidden");
}

fn updateDiagramSelectorControl() void {
    const selector = child_windows.diagram_selector orelse return;
    _ = ui.SendMessageA(selector, ui.CB_RESETCONTENT, 0, 0);

    const document = current_markdown_document orelse {
        const text = "No diagrams";
        _ = ui.SendMessageA(selector, ui.CB_ADDSTRING, 0, @bitCast(@intFromPtr(text)));
        _ = ui.SendMessageA(selector, ui.CB_SETCURSEL, 0, 0);
        updateDiagramHeaderControls();
        return;
    };

    if (document.diagram_count == 0) {
        const text = "No diagrams";
        _ = ui.SendMessageA(selector, ui.CB_ADDSTRING, 0, @bitCast(@intFromPtr(text)));
        _ = ui.SendMessageA(selector, ui.CB_SETCURSEL, 0, 0);
        updateDiagramHeaderControls();
        return;
    }

    var diagram_index: usize = 0;
    for (document.blocks) |block| {
        switch (block) {
            .diagram => |diagram| {
                const label = if (diagram.name) |name|
                    c_allocator.dupe(u8, name) catch null
                else
                    std.fmt.allocPrint(c_allocator, "Diagram {d}", .{diagram_index + 1}) catch null;
                defer if (label) |owned| c_allocator.free(owned);

                const text = label orelse "Diagram";
                const text_z = dupeSentinel(c_allocator, text) catch continue;
                defer c_allocator.free(text_z);
                _ = ui.SendMessageA(selector, ui.CB_ADDSTRING, 0, @bitCast(@intFromPtr(text_z.ptr)));
                diagram_index += 1;
            },
            else => {},
        }
    }

    _ = ui.SendMessageA(selector, ui.CB_SETCURSEL, @min(selected_diagram_index, document.diagram_count - 1), 0);
    updateDiagramHeaderControls();
}

fn selectDiagramIndex(index: usize, refresh_view: bool) void {
    const document = current_markdown_document orelse {
        updateDiagramHeaderControls();
        return;
    };
    if (document.diagram_count == 0) {
        selected_diagram_index = 0;
        updateDiagramHeaderControls();
        return;
    }

    selected_diagram_index = @min(index, document.diagram_count - 1);
    if (child_windows.diagram_selector) |selector| {
        _ = ui.SendMessageA(selector, ui.CB_SETCURSEL, selected_diagram_index, 0);
    }
    updateDiagramHeaderControls();

    if (!refresh_view) return;
    if (app_mode == .freeform) {
        rebuildFreeformCanvas(true);
    } else {
        updateEditorDerivedState(true);
    }
}

fn selectAdjacentDiagram(delta: i32) void {
    const document = current_markdown_document orelse return;
    if (document.diagram_count == 0) return;

    const current_index: i32 = @intCast(selected_diagram_index);
    const max_index: i32 = @intCast(document.diagram_count - 1);
    const next_index = std.math.clamp(current_index + delta, 0, max_index);
    if (next_index == current_index) return;
    selectDiagramIndex(@intCast(next_index), true);
}

fn handleDiagramNavigationShortcut(vkey: u16, ctrl_down: bool) bool {
    if (!ctrl_down) return false;

    switch (vkey) {
        @as(u16, @intCast(@intFromEnum(mouse.VK_PRIOR))) => {
            selectAdjacentDiagram(-1);
            return true;
        },
        @as(u16, @intCast(@intFromEnum(mouse.VK_NEXT))) => {
            selectAdjacentDiagram(1);
            return true;
        },
        else => return false,
    }
}

fn onDiagramSelectionChanged() void {
    const selector = child_windows.diagram_selector orelse return;
    const selection = ui.SendMessageA(selector, ui.CB_GETCURSEL, 0, 0);
    if (selection < 0) return;
    selectDiagramIndex(@intCast(selection), true);
}

fn syncDiagramSelectionToSourceOffset(offset: usize, refresh_view: bool) void {
    const document = current_markdown_document orelse return;
    const next_index = document.diagramIndexForOffset(offset) orelse return;
    if (next_index == selected_diagram_index) return;
    selectDiagramIndex(next_index, refresh_view);
}

fn syncDiagramSelectionToEditorCaret(source_text: []const u8, refresh_view: bool) void {
    const offset = windows_editor.getEditorCaretSourceOffset(child_windows.editor, source_text);
    syncDiagramSelectionToSourceOffset(offset, refresh_view);
}

fn onEditorSelectionChanged() void {
    if (current_markdown_document) |document| {
        syncDiagramSelectionToEditorCaret(document.source, true);
        return;
    }

    const editor_text = getEditorText(c_allocator) catch return;
    defer c_allocator.free(editor_text);
    if (!refreshCurrentMarkdownDocument(editor_text)) return;
    syncDiagramSelectionToEditorCaret(editor_text, true);
}

fn onProjectFontSettingsChanged() void {
    applyProjectSettingsToCanvas(true);
    updateEditorDerivedState(false);
    setDocumentDirty(true);
    setStatusMessage("Updated project settings");
}

fn loadProjectFontSettingsForPath(path: []const u8) void {
    project_font_settings = windows_project_settings.loadProjectFontSettings(c_allocator, path) catch null orelse ProjectFontSettings{};
    applyProjectSettingsToCanvas(true);
}

fn saveProjectFontSettingsForPath(path: []const u8) bool {
    windows_project_settings.saveProjectFontSettings(c_allocator, path, project_font_settings) catch {
        setStatusMessage("Failed to save project font settings");
        return false;
    };
    return true;
}

fn selectedDiagramBlock() ?*const document_model.DiagramBlock {
    const document = current_markdown_document orelse return null;
    return document.diagramAt(selected_diagram_index);
}

fn diagramHashText(diagram: *const document_model.DiagramBlock, buffer: *[16]u8) ?[]const u8 {
    return std.fmt.bufPrint(buffer, "{x:0>16}", .{diagram.content_hash}) catch null;
}

fn selectedDiagramHashText(buffer: *[16]u8) ?[]const u8 {
    const diagram = selectedDiagramBlock() orelse return null;
    return diagramHashText(diagram, buffer);
}

fn updateCanvasPresentation(fit_view: bool) void {
    if (canvas_renderer.canvas_state.graph) |graph| applyProjectSettingsToGraph(graph);

    if (fit_view) {
        if (child_windows.canvas) |cw| {
            var r = std.mem.zeroes(foundation.RECT);
            if (ui.GetClientRect(cw, &r) != 0) {
                canvas_renderer.canvas_state.fitToViewport(
                    @floatFromInt(r.right - r.left),
                    @floatFromInt(r.bottom - r.top),
                );
            }
        }
    }

    windows_canvas.inspector.refresh(&canvas_renderer.inspector, &canvas_renderer.canvas_state);
    if (child_windows.canvas) |canvas_hwnd| _ = gdi.InvalidateRect(canvas_hwnd, null, 0);
}

fn loadPersistedFreeformGraph() ?*windows_canvas.StudioEditableGraph {
    const diagram = selectedDiagramBlock() orelse return null;
    return loadPersistedGraphForDiagram(diagram);
}

fn rememberCurrentRecentFile() void {
    var db = &(library_database orelse return);
    const path = current_document_path orelse return;
    db.saveRecentFile(path, selected_diagram_index) catch {};
}

fn scheduleFreeformPersist() void {
    const hwnd = main_window orelse return;
    _ = ui.SetTimer(hwnd, main_timer_id_ffm_persist, ffm_persist_debounce_ms, null);
}

fn cancelScheduledFreeformPersist() void {
    const hwnd = main_window orelse return;
    _ = ui.KillTimer(hwnd, main_timer_id_ffm_persist);
}

fn persistCurrentFreeformGraph() void {
    if (app_mode != .freeform) return;

    var db = &(library_database orelse return);
    const diagram = selectedDiagramBlock() orelse return;
    const graph = canvas_renderer.canvas_state.graph orelse return;

    var hash_buffer: [16]u8 = undefined;
    const content_hash = selectedDiagramHashText(&hash_buffer) orelse return;

    const graph_blob = ffm_serializer.serializeGraph(c_allocator, graph) catch {
        setStatusMessage("Failed to serialize freeform diagram");
        return;
    };
    defer c_allocator.free(graph_blob);

    db.saveFfm(content_hash, .{
        .graph_type = graph.graph_type,
        .diagram_name = diagram.name,
        .source_file = current_document_path,
        .mermaid_source = diagram.mermaid_source,
        .graph_blob = graph_blob,
    }) catch {
        setStatusMessage("Failed to save freeform diagram");
        return;
    };

    rememberCurrentRecentFile();
}

fn onFreeformGraphChanged() void {
    scheduleFreeformPersist();
}

fn rebuildFreeformCanvas(fit_view: bool) void {
    const editor_text = getEditorText(c_allocator) catch {
        setStatusMessage("Could not read source for canvas mode");
        return;
    };
    defer c_allocator.free(editor_text);

    if (current_markdown_document == null and !refreshCurrentMarkdownDocument(editor_text)) {
        clearCanvasGraphIfNeeded();
        return;
    }

    const source = duplicateSelectedDiagramSource(c_allocator) catch {
        clearCanvasGraphIfNeeded();
        setStatusMessage("Document has no mermaid diagram to edit");
        return;
    };
    defer c_allocator.free(source);

    if (loadPersistedFreeformGraph()) |saved_graph| {
        canvas_renderer.canvas_state.setGraph(saved_graph);
        updateCanvasPresentation(fit_view);
        setStatusMessage("Freeform canvas mode (saved layout)");
        rememberCurrentRecentFile();
        return;
    }

    var eg_message: [256]u8 = std.mem.zeroes([256]u8);
    const eg = merrow_studio_build_editable_graph(
        source.ptr,
        @intCast(source.len),
        &eg_message,
        eg_message.len,
    );
    canvas_renderer.canvas_state.setGraph(eg);
    updateCanvasPresentation(fit_view);

    const eg_status = std.mem.sliceTo(&eg_message, 0);
    setStatusMessage(if (eg == null and eg_status.len > 0) eg_status else if (eg == null) "Failed to build freeform canvas" else "Freeform canvas mode");
    rememberCurrentRecentFile();
}

fn toggleFontInspector() void {
    if (app_mode != .freeform) {
        setStatusMessage("Project inspector is only available in freeform mode");
        return;
    }

    const active = !windows_canvas.inspector.fontInspectorActive();
    windows_canvas.inspector.setFontInspectorActive(active);
    windows_canvas.inspector.refresh(&canvas_renderer.inspector, &canvas_renderer.canvas_state);
    setStatusMessage(if (active) "Project inspector" else "Selection inspector");
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
    loadProjectFontSettingsForPath(selected_path);
    setCurrentDocumentPath(selected_path);
    updateEditorDerivedState(true);
    if (app_mode == .freeform) rebuildFreeformCanvas(true);
    setDocumentDirty(false);
    rememberCurrentRecentFile();
    setStatusMessage("Opened source document");
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
    if (!saveProjectFontSettingsForPath(path)) return false;

    setCurrentDocumentPath(path);
    _ = refreshCurrentMarkdownDocument(source);
    setDocumentDirty(false);
    rememberCurrentRecentFile();
    setStatusMessage("Saved source document");
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

fn ensureWordComGlueLoaded() ?*const WordComGlueApi {
    if (wordcomglue_api != null) return &wordcomglue_api.?;

    const module = loadWordComGlueModule() orelse {
        setStatusMessage("wordcomglue.dll not found. Build it with scripts/build_wordcomglue.ps1.");
        return null;
    };

    wordcomglue_api = .{
        .create_library = loadWordComGlueProc(wcg_create_library_fn, module, "wcg_create_library") orelse return unloadWordComGlueOnLoadFailure(),
        .destroy_library = loadWordComGlueProc(wcg_destroy_library_fn, module, "wcg_destroy_library") orelse return unloadWordComGlueOnLoadFailure(),
        .start_word = loadWordComGlueProc(wcg_start_word_fn, module, "wcg_start_word") orelse return unloadWordComGlueOnLoadFailure(),
        .shutdown_word = loadWordComGlueProc(wcg_shutdown_word_fn, module, "wcg_shutdown_word") orelse return unloadWordComGlueOnLoadFailure(),
        .create_document = loadWordComGlueProc(wcg_create_document_fn, module, "wcg_create_document") orelse return unloadWordComGlueOnLoadFailure(),
        .save_document_as = loadWordComGlueProc(wcg_save_document_as_fn, module, "wcg_save_document_as") orelse return unloadWordComGlueOnLoadFailure(),
        .export_pdf = loadWordComGlueProc(wcg_export_pdf_fn, module, "wcg_export_pdf") orelse return unloadWordComGlueOnLoadFailure(),
        .close_document = loadWordComGlueProc(wcg_close_document_fn, module, "wcg_close_document") orelse return unloadWordComGlueOnLoadFailure(),
        .set_document_font = loadWordComGlueProc(wcg_set_document_font_fn, module, "wcg_set_document_font") orelse return unloadWordComGlueOnLoadFailure(),
        .insert_heading = loadWordComGlueProc(wcg_insert_heading_fn, module, "wcg_insert_heading") orelse return unloadWordComGlueOnLoadFailure(),
        .insert_paragraph = loadWordComGlueProc(wcg_insert_paragraph_fn, module, "wcg_insert_paragraph") orelse return unloadWordComGlueOnLoadFailure(),
        .insert_header_banner = loadWordComGlueProc(wcg_insert_header_banner_fn, module, "wcg_insert_header_banner") orelse return unloadWordComGlueOnLoadFailure(),
        .insert_footer_trailer = loadWordComGlueProc(wcg_insert_footer_trailer_fn, module, "wcg_insert_footer_trailer") orelse return unloadWordComGlueOnLoadFailure(),
        .insert_image = loadWordComGlueProc(wcg_insert_image_fn, module, "wcg_insert_image") orelse return unloadWordComGlueOnLoadFailure(),
        .get_last_error = loadWordComGlueProc(wcg_get_last_error_fn, module, "wcg_get_last_error") orelse return unloadWordComGlueOnLoadFailure(),
    };

    return &wordcomglue_api.?;
}

fn unloadWordComGlueOnLoadFailure() ?*const WordComGlueApi {
    unloadWordComGlue();
    setStatusMessage("wordcomglue.dll is missing required exports");
    return null;
}

fn loadWordComGlueModule() ?ModuleHandle {
    if (wordcomglue_module) |module| return module;

    if (loader.LoadLibraryA("wordcomglue.dll")) |module| {
        wordcomglue_module = module;
        return module;
    }

    const repo_relative = "wordcomglue/build/wordcomglue.dll";
    const dll_path = resolveRepoPathZ(c_allocator, repo_relative) catch return null;
    defer c_allocator.free(dll_path);

    const module = loader.LoadLibraryA(dll_path.ptr) orelse return null;
    wordcomglue_module = module;
    return module;
}

fn unloadWordComGlue() void {
    wordcomglue_api = null;
    if (wordcomglue_module) |module| {
        _ = loader.FreeLibrary(module);
        wordcomglue_module = null;
    }
}

fn loadWordComGlueProc(comptime Proc: type, module: ModuleHandle, name: [*:0]const u8) ?Proc {
    const symbol = loader.GetProcAddress(module, name) orelse return null;
    return @ptrCast(symbol);
}

fn exportDiagramToWord() void {
    const api = ensureWordComGlueLoaded() orelse return;

    seedDefaultWordAssets() catch {};

    const export_docx_path = chooseExportWordPath() orelse return;
    defer c_allocator.free(export_docx_path);

    const editor_text = getEditorText(c_allocator) catch {
        setStatusMessage("Failed to read editor text");
        return;
    };
    defer c_allocator.free(editor_text);

    if (!refreshCurrentMarkdownDocument(editor_text)) return;

    const markdown_document = current_markdown_document orelse {
        setStatusMessage("Failed to prepare document export model");
        return;
    };

    const pdf_path = replaceFileExtension(export_docx_path, ".pdf") catch {
        setStatusMessage("Failed to prepare PDF output path");
        return;
    };
    defer c_allocator.free(pdf_path);

    const header_path = findOptionalWordAsset("diagrams_header.png") catch null;
    defer if (header_path) |path| c_allocator.free(path);

    const trailer_path = findOptionalWordAsset("diagrams_trailer.png") catch null;
    defer if (trailer_path) |path| c_allocator.free(path);

    const export_title = buildWordExportTitle() catch c_allocator.dupe(u8, "Merrow Diagram Export") catch null;
    defer if (export_title) |title| c_allocator.free(title);

    const docx_z = dupeSentinel(c_allocator, export_docx_path) catch {
        setStatusMessage("Failed to prepare Word output path");
        return;
    };
    defer c_allocator.free(docx_z);

    const pdf_z = dupeSentinel(c_allocator, pdf_path) catch {
        setStatusMessage("Failed to prepare PDF output path");
        return;
    };
    defer c_allocator.free(pdf_z);

    var library: wcg_library = null;
    var session: wcg_session = null;
    var document: wcg_document = null;

    const runtime_options = wcg_runtime_options{ .abi_version = WCG_ABI_VERSION, .flags = 0 };
    if (api.create_library(&runtime_options, &library) != WCG_OK) {
        setStatusMessage("Failed to initialize Word export library");
        return;
    }
    defer _ = api.destroy_library(library);

    const word_options = wcg_word_options{ .visibility = WCG_HIDDEN, .flags = 0 };
    if (api.start_word(library, &word_options, &session) != WCG_OK) {
        setWordComStatusMessage(api, library, "Failed to start Microsoft Word");
        return;
    }
    defer _ = api.shutdown_word(session);

    if (api.create_document(session, &document) != WCG_OK) {
        setWordComStatusMessage(api, library, "Failed to create Word document");
        return;
    }
    defer {
        const close_options = wcg_close_options{ .save_before_close = 0 };
        _ = api.close_document(document, &close_options);
    }

    if (!markdownDocumentHasTextContent(&markdown_document)) {
        if (export_title) |title| {
            if (!insertWordHeading(api, library, document, title, 1, "Failed to add export title")) {
                return;
            }
        }
    }

    if (!exportMarkdownDocumentToWord(api, library, document, &markdown_document)) {
        return;
    }

    if (trailer_path) |path| {
        const path_z = dupeSentinel(c_allocator, path) catch {
            setStatusMessage("Failed to prepare trailer asset path");
            return;
        };
        defer c_allocator.free(path_z);

        const trailer = wcg_trailer_options{
            .mode = WCG_TRAILER_FOOTER,
            .preserve_aspect_ratio = 1,
            .repeat_every_page = 0,
            .spacing_before = .{ .unit = 0, .value = 0.0 },
        };
        if (api.insert_footer_trailer(document, path_z.ptr, &trailer) != WCG_OK) {
            setWordComStatusMessage(api, library, "Failed to insert trailer artwork");
            return;
        }
    }

    if (api.save_document_as(document, docx_z.ptr, null) != WCG_OK) {
        setWordComStatusMessage(api, library, "Failed to save Word document");
        return;
    }
    const pdf_options = wcg_pdf_options{
        .open_after_export = 0,
        .optimize_for = 1,
        .range = 0,
        .from_page = 0,
        .to_page = 0,
        .item = 0,
        .include_doc_props = 0,
        .keep_irm = 0,
        .create_bookmarks = 1,
        .doc_structure_tags = 1,
        .bitmap_missing_fonts = 1,
        .use_pdfa = 0,
    };
    if (api.export_pdf(document, pdf_z.ptr, &pdf_options) != WCG_OK) {
        setWordComStatusMessage(api, library, "Failed to save PDF export");
        return;
    }

    if (!fileExistsAbsolute(export_docx_path) or !fileExistsAbsolute(pdf_path)) {
        const missing_output_message = std.fmt.allocPrint(
            c_allocator,
            "Word export reported success but output files are missing: {s} / {s}",
            .{ std.fs.path.basename(export_docx_path), std.fs.path.basename(pdf_path) },
        ) catch null;
        if (missing_output_message) |text| {
            defer c_allocator.free(text);
            setStatusMessage(text);
        } else {
            setStatusMessage("Word export reported success but output files are missing");
        }
        return;
    }

    const status_text = std.fmt.allocPrint(c_allocator, "Exported Word and PDF: {s}", .{std.fs.path.basename(export_docx_path)}) catch {
        setStatusMessage("Exported Word and PDF");
        return;
    };
    defer c_allocator.free(status_text);
    setStatusMessage(status_text);
}

fn exportMarkdownDocumentToWord(api: *const WordComGlueApi, library: wcg_library, document_handle: wcg_document, markdown_document: *const document_model.MarkdownDocument) bool {
    var temp_png_paths = std.ArrayList([]u8){};
    defer {
        for (temp_png_paths.items) |temp_path| {
            std.fs.deleteFileAbsolute(temp_path) catch {};
            c_allocator.free(temp_path);
        }
        temp_png_paths.deinit(c_allocator);
    }

    for (markdown_document.blocks) |block| {
        switch (block) {
            .text => |text_block| {
                if (!exportMarkdownTextBlockToWord(api, library, document_handle, text_block.content)) {
                    return false;
                }
            },
            .diagram => |diagram_block| {
                const diagram_png_path = renderDiagramToTempPng(diagram_block.mermaid_source) catch |err| {
                    setStatusMessage(@errorName(err));
                    return false;
                };
                temp_png_paths.append(c_allocator, diagram_png_path) catch {
                    std.fs.deleteFileAbsolute(diagram_png_path) catch {};
                    c_allocator.free(diagram_png_path);
                    setStatusMessage("Failed to track temporary diagram export");
                    return false;
                };

                const diagram_png_z = dupeSentinel(c_allocator, diagram_png_path) catch {
                    setStatusMessage("Failed to prepare diagram image path");
                    return false;
                };
                defer c_allocator.free(diagram_png_z);

                const image_options = wcg_image_options{
                    .placement = 0,
                    .alignment = 1,
                    .wrap = 0,
                    .width = .{ .unit = WCG_UNIT_PCT_CONTENT, .value = 100.0 },
                    .height = .{ .unit = 0, .value = 0.0 },
                    .max_width = .{ .unit = 0, .value = 0.0 },
                    .max_height = .{ .unit = 0, .value = 0.0 },
                    .spacing_before = .{ .unit = 0, .value = 0.0 },
                    .spacing_after = .{ .unit = 0, .value = 12.0 },
                    .preserve_aspect_ratio = 1,
                    .utf8_caption = null,
                    .utf8_alt_text = null,
                };
                if (api.insert_image(document_handle, diagram_png_z.ptr, &image_options) != WCG_OK) {
                    setWordComStatusMessage(api, library, "Failed to insert diagram image");
                    return false;
                }
            },
        }
    }

    return true;
}

fn exportMarkdownTextBlockToWord(api: *const WordComGlueApi, library: wcg_library, document_handle: wcg_document, content: []const u8) bool {
    var paragraph = std.ArrayList(u8){};
    defer paragraph.deinit(c_allocator);

    var lines = std.mem.splitScalar(u8, content, '\n');
    while (lines.next()) |raw_line| {
        const line = std.mem.trimRight(u8, raw_line, "\r");
        if (parseMarkdownHeadingLine(line)) |heading| {
            if (!flushMarkdownParagraph(api, library, document_handle, &paragraph)) return false;
            if (!insertWordHeading(api, library, document_handle, heading.text, heading.level, "Failed to insert markdown heading")) {
                return false;
            }
            continue;
        }

        const trimmed = std.mem.trim(u8, line, " \t");
        if (trimmed.len == 0) {
            if (!flushMarkdownParagraph(api, library, document_handle, &paragraph)) return false;
            continue;
        }

        if (paragraph.items.len > 0) {
            paragraph.append(c_allocator, ' ') catch {
                setStatusMessage("Failed to prepare markdown paragraph");
                return false;
            };
        }
        paragraph.appendSlice(c_allocator, trimmed) catch {
            setStatusMessage("Failed to prepare markdown paragraph");
            return false;
        };
    }

    return flushMarkdownParagraph(api, library, document_handle, &paragraph);
}

fn flushMarkdownParagraph(api: *const WordComGlueApi, library: wcg_library, document_handle: wcg_document, paragraph: *std.ArrayList(u8)) bool {
    const trimmed = std.mem.trim(u8, paragraph.items, " \t\r\n");
    if (trimmed.len == 0) {
        paragraph.clearRetainingCapacity();
        return true;
    }

    if (!insertWordParagraph(api, library, document_handle, trimmed, "Failed to insert markdown paragraph")) {
        return false;
    }
    paragraph.clearRetainingCapacity();
    return true;
}

const MarkdownHeading = struct {
    level: u32,
    text: []const u8,
};

fn parseMarkdownHeadingLine(line: []const u8) ?MarkdownHeading {
    const trimmed_left = std.mem.trimLeft(u8, line, " \t");
    if (trimmed_left.len < 2 or trimmed_left[0] != '#') return null;

    var level: usize = 0;
    while (level < trimmed_left.len and trimmed_left[level] == '#') : (level += 1) {}
    if (level == 0 or level > 6 or level >= trimmed_left.len or trimmed_left[level] != ' ') return null;

    const text = std.mem.trim(u8, trimmed_left[level + 1 ..], " \t");
    if (text.len == 0) return null;
    return .{ .level = @intCast(level), .text = text };
}

fn markdownDocumentHasTextContent(markdown_document: *const document_model.MarkdownDocument) bool {
    for (markdown_document.blocks) |block| {
        switch (block) {
            .text => |text_block| {
                if (std.mem.trim(u8, text_block.content, " \t\r\n").len > 0) return true;
            },
            else => {},
        }
    }
    return false;
}
fn insertWordHeading(api: *const WordComGlueApi, library: wcg_library, document: wcg_document, text: []const u8, level: u32, fallback: []const u8) bool {
    const text_z = dupeSentinel(c_allocator, text) catch {
        setStatusMessage("Failed to prepare heading text");
        return false;
    };
    defer c_allocator.free(text_z);

    const heading = wcg_heading_options{
        .level = level,
        .alignment = 0,
        .spacing_before = .{ .unit = 0, .value = 0.0 },
        .spacing_after = .{ .unit = 0, .value = if (level == 1) 12.0 else 8.0 },
        .page_break_before = 0,
        .utf8_style_override = null,
    };
    if (api.insert_heading(document, text_z.ptr, &heading) != WCG_OK) {
        setWordComStatusMessage(api, library, fallback);
        return false;
    }
    return true;
}

fn insertWordParagraph(api: *const WordComGlueApi, library: wcg_library, document: wcg_document, text: []const u8, fallback: []const u8) bool {
    const text_z = dupeSentinel(c_allocator, text) catch {
        setStatusMessage("Failed to prepare paragraph text");
        return false;
    };
    defer c_allocator.free(text_z);

    const paragraph = wcg_paragraph_options{
        .alignment = 0,
        .spacing_before = .{ .unit = 0, .value = 0.0 },
        .spacing_after = .{ .unit = 0, .value = 8.0 },
        .line_spacing = 0.0,
        .utf8_style_override = null,
    };
    if (api.insert_paragraph(document, text_z.ptr, &paragraph) != WCG_OK) {
        setWordComStatusMessage(api, library, fallback);
        return false;
    }
    return true;
}

fn buildDefaultWordExportPath() ![]u8 {
    const folders = try windows_document.getMerrowUserFolders(c_allocator);
    defer folders.deinit(c_allocator);

    if (current_document_path) |path| {
        const file_name = std.fs.path.basename(path);
        const extension = std.fs.path.extension(file_name);
        const stem = file_name[0 .. file_name.len - extension.len];
        const export_name = try std.fmt.allocPrint(c_allocator, "{s}.docx", .{stem});
        defer c_allocator.free(export_name);
        return std.fs.path.join(c_allocator, &.{ folders.generated, export_name });
    }

    return std.fs.path.join(c_allocator, &.{ folders.generated, "merrow-export.docx" });
}

fn buildWordExportTitle() ![]u8 {
    if (current_document_path) |path| {
        const file_name = std.fs.path.basename(path);
        const extension = std.fs.path.extension(file_name);
        const stem = file_name[0 .. file_name.len - extension.len];
        return std.fmt.allocPrint(c_allocator, "{s}", .{stem});
    }

    return c_allocator.dupe(u8, "Merrow Diagram Export");
}

fn replaceFileExtension(path: []const u8, new_extension: []const u8) ![]u8 {
    const existing_extension = std.fs.path.extension(path);
    const base = path[0 .. path.len - existing_extension.len];
    return std.fmt.allocPrint(c_allocator, "{s}{s}", .{ base, new_extension });
}

fn renderDiagramToTempPng(source: []const u8) ![]u8 {
    var preview_message: [256]u8 = std.mem.zeroes([256]u8);
    var preview_png_len: u32 = 0;
    const canvas_dims = currentProjectCanvasDimensions();
    const preview_png_ptr = merrow_studio_render_preview_png_bytes(
        source.ptr,
        @intCast(source.len),
        canvas_dims.width,
        canvas_dims.height,
        &preview_png_len,
        &preview_message,
        preview_message.len,
    );
    const preview_status = std.mem.sliceTo(&preview_message, 0);
    if (preview_png_ptr == null or preview_png_len == 0) {
        if (preview_status.len > 0) setStatusMessage(preview_status);
        return error.RenderPreviewFailed;
    }
    defer merrow_studio_free_buffer(preview_png_ptr, preview_png_len);

    const temp_path = try createTempExportPath(".png");
    const output_file = try std.fs.createFileAbsolute(temp_path, .{ .truncate = true });
    defer output_file.close();
    try output_file.writeAll(preview_png_ptr[0..preview_png_len]);
    return temp_path;
}

fn renderEditableGraphToTempPng(graph: *const windows_canvas.StudioEditableGraph) ![]u8 {
    var preview_message: [256]u8 = std.mem.zeroes([256]u8);
    var preview_png_len: u32 = 0;
    const canvas_dims = currentProjectCanvasDimensions();
    const preview_png_ptr = merrow_studio_render_editable_graph_png_bytes(
        graph,
        canvas_dims.width,
        canvas_dims.height,
        &preview_png_len,
        &preview_message,
        preview_message.len,
    );
    const preview_status = std.mem.sliceTo(&preview_message, 0);
    if (preview_png_ptr == null or preview_png_len == 0) {
        if (preview_status.len > 0) setStatusMessage(preview_status);
        return error.RenderPreviewFailed;
    }
    defer merrow_studio_free_buffer(preview_png_ptr, preview_png_len);

    const temp_path = try createTempExportPath(".png");
    const output_file = try std.fs.createFileAbsolute(temp_path, .{ .truncate = true });
    defer output_file.close();
    try output_file.writeAll(preview_png_ptr[0..preview_png_len]);
    return temp_path;
}

fn loadPersistedGraphForDiagram(diagram: *const document_model.DiagramBlock) ?*windows_canvas.StudioEditableGraph {
    var db = &(library_database orelse return null);
    var hash_buffer: [16]u8 = undefined;
    const content_hash = diagramHashText(diagram, &hash_buffer) orelse return null;
    var record = db.loadFfm(c_allocator, content_hash) catch return null;
    if (record) |*saved| {
        defer saved.deinit(c_allocator);
        return ffm_serializer.deserializeGraph(saved.graph_blob) catch null;
    }
    return null;
}

fn renderDiagramBlockToTempPng(diagram: *const document_model.DiagramBlock) ![]u8 {
    if (loadPersistedGraphForDiagram(diagram)) |saved_graph| {
        defer ffm_serializer.freeGraph(saved_graph);
        if (saved_graph.graph_type == export_editable_graph_type_flowchart or
            saved_graph.graph_type == export_editable_graph_type_sequence)
        {
            return renderEditableGraphToTempPng(saved_graph) catch renderDiagramToTempPng(diagram.mermaid_source);
        }
    }
    return renderDiagramToTempPng(diagram.mermaid_source);
}

fn createTempExportPath(suffix: []const u8) ![]u8 {
    const folders = try windows_document.getMerrowUserFolders(c_allocator);
    defer folders.deinit(c_allocator);

    const stamp = @as(u64, @intCast(@abs(std.time.nanoTimestamp())));
    const file_name = try std.fmt.allocPrint(c_allocator, "merrow-studio-export-{d}{s}", .{ stamp, suffix });
    defer c_allocator.free(file_name);

    return std.fs.path.join(c_allocator, &.{ folders.temp, file_name });
}

fn findOptionalWordAsset(file_name: []const u8) !?[]u8 {
    const folders = windows_document.getMerrowUserFolders(c_allocator) catch null;
    defer if (folders) |value| value.deinit(c_allocator);
    if (folders) |value| {
        if (try joinExistingFilePath(value.assets, file_name)) |candidate| return candidate;
    }

    if (current_document_path) |path| {
        if (std.fs.path.dirname(path)) |dir| {
            if (try joinExistingFilePath(dir, file_name)) |candidate| return candidate;
            if (try joinExistingNestedFilePath(dir, "assets", file_name)) |candidate| return candidate;
        }
    }

    const cwd = std.process.getCwdAlloc(c_allocator) catch null;
    defer if (cwd) |path| c_allocator.free(path);
    if (cwd) |path| {
        if (try joinExistingFilePath(path, file_name)) |candidate| return candidate;
        if (try joinExistingNestedFilePath(path, "assets", file_name)) |candidate| return candidate;
    }

    const repo_relative = try std.fmt.allocPrint(c_allocator, "app/assets/{s}", .{file_name});
    defer c_allocator.free(repo_relative);
    const repo_path = resolveRepoPathZ(c_allocator, repo_relative) catch return null;
    defer c_allocator.free(repo_path);
    return try c_allocator.dupe(u8, repo_path[0..repo_path.len]);
}

fn seedDefaultWordAssets() !void {
    try seedDefaultWordAsset("diagrams_header.png");
    try seedDefaultWordAsset("diagrams_trailer.png");
}

fn seedDefaultWordAsset(file_name: []const u8) !void {
    const folders = try windows_document.getMerrowUserFolders(c_allocator);
    defer folders.deinit(c_allocator);

    const destination_path = try std.fs.path.join(c_allocator, &.{ folders.assets, file_name });
    defer c_allocator.free(destination_path);
    if (fileExistsAbsolute(destination_path)) return;

    const source_path = findPackagedAssetPath(file_name) orelse return;
    defer c_allocator.free(source_path);

    try copyFileAbsolute(source_path, destination_path);
}

fn findPackagedAssetPath(file_name: []const u8) ?[]u8 {
    const executable_dir = std.fs.selfExeDirPathAlloc(c_allocator) catch return null;
    defer c_allocator.free(executable_dir);

    const packaged_path = std.fs.path.join(c_allocator, &.{ executable_dir, "assets", file_name }) catch return null;
    if (fileExistsAbsolute(packaged_path)) return packaged_path;
    c_allocator.free(packaged_path);

    const repo_relative = std.fmt.allocPrint(c_allocator, "app/assets/{s}", .{file_name}) catch return null;
    defer c_allocator.free(repo_relative);
    const repo_path = resolveRepoPathZ(c_allocator, repo_relative) catch return null;
    defer c_allocator.free(repo_path);
    return c_allocator.dupe(u8, repo_path[0..repo_path.len]) catch null;
}

fn copyFileAbsolute(source_path: []const u8, destination_path: []const u8) !void {
    const source_file = try std.fs.openFileAbsolute(source_path, .{});
    defer source_file.close();
    const destination_file = try std.fs.createFileAbsolute(destination_path, .{ .truncate = true });
    defer destination_file.close();

    var buffer: [8192]u8 = undefined;
    while (true) {
        const bytes_read = try source_file.read(&buffer);
        if (bytes_read == 0) break;
        try destination_file.writeAll(buffer[0..bytes_read]);
    }
}

fn joinExistingFilePath(base_dir: []const u8, file_name: []const u8) !?[]u8 {
    const candidate = try std.fs.path.join(c_allocator, &.{ base_dir, file_name });
    errdefer c_allocator.free(candidate);
    if (fileExistsAbsolute(candidate)) return candidate;
    c_allocator.free(candidate);
    return null;
}

fn joinExistingNestedFilePath(base_dir: []const u8, sub_dir: []const u8, file_name: []const u8) !?[]u8 {
    const candidate = try std.fs.path.join(c_allocator, &.{ base_dir, sub_dir, file_name });
    errdefer c_allocator.free(candidate);
    if (fileExistsAbsolute(candidate)) return candidate;
    c_allocator.free(candidate);
    return null;
}

fn setWordComStatusMessage(api: *const WordComGlueApi, library: wcg_library, fallback: []const u8) void {
    var error_info = std.mem.zeroes(wcg_error_info);
    if (library != null and api.get_last_error(library, &error_info) == WCG_OK) {
        const message = if (error_info.utf8_message) |value| std.mem.span(value) else "";
        const function_name = if (error_info.utf8_function) |value| std.mem.span(value) else "";
        if (message.len > 0) {
            const formatted = (if (function_name.len > 0)
                std.fmt.allocPrint(c_allocator, "{s}: {s}", .{ function_name, message })
            else
                std.fmt.allocPrint(c_allocator, "{s}", .{message})) catch null;
            if (formatted) |text| {
                defer c_allocator.free(text);
                setStatusMessage(text);
                return;
            }
            setStatusMessage(message);
            return;
        }
    }
    setStatusMessage(fallback);
}

fn rgba8Color(r: u8, g: u8, b: u8, a: u8) d2d_common.D2D_COLOR_F {
    return .{
        .r = @as(f32, @floatFromInt(r)) / 255.0,
        .g = @as(f32, @floatFromInt(g)) / 255.0,
        .b = @as(f32, @floatFromInt(b)) / 255.0,
        .a = @as(f32, @floatFromInt(a)) / 255.0,
    };
}

fn makeSolidColorBrush(
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

fn currentCanvasPixelSize(hwnd: ?foundation.HWND) ?struct { width: i32, height: i32 } {
    var rect = std.mem.zeroes(foundation.RECT);
    if (ui.GetClientRect(hwnd, &rect) == 0) return null;
    const width = rect.right - rect.left;
    const height = rect.bottom - rect.top;
    if (width <= 0 or height <= 0) return null;
    return .{ .width = width, .height = height };
}

fn scrollCanvasByPage(hwnd: ?foundation.HWND, direction: i32) bool {
    const size = currentCanvasPixelSize(hwnd) orelse return false;
    const zoom = canvas_renderer.canvas_state.viewport.zoom;
    if (zoom <= 0.0) return false;

    const page_step = @as(f64, @floatFromInt(size.height)) * 0.9 / zoom;
    canvas_renderer.canvas_state.viewport.pan_y += page_step * @as(f64, @floatFromInt(direction));
    return true;
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

fn centerPreviewPage(hwnd: ?foundation.HWND) void {
    const viewport = currentPreviewPixelSize(hwnd) orelse return;
    const page_width = previewPageWidth();
    const page_height = previewPageHeight();

    const centered_x = @as(i32, @intFromFloat(@round((@as(f64, @floatFromInt(page_width)) * preview_renderer.zoom - @as(f64, @floatFromInt(viewport.width))) / 2.0)));
    const centered_y = @as(i32, @intFromFloat(@round((@as(f64, @floatFromInt(page_height)) * preview_renderer.zoom - @as(f64, @floatFromInt(viewport.height))) / 2.0)));

    if (previewBounds(hwnd)) |bounds| {
        preview_renderer.scroll_x = std.math.clamp(centered_x, bounds.x.min, bounds.x.max);
        preview_renderer.scroll_y = std.math.clamp(centered_y, bounds.y.min, bounds.y.max);
    } else {
        preview_renderer.scroll_x = centered_x;
        preview_renderer.scroll_y = centered_y;
    }
    refreshStatusDisplay();
    requestPreviewRefresh();
}

fn fitPreviewPageInView(hwnd: ?foundation.HWND) void {
    const viewport = currentPreviewPixelSize(hwnd) orelse return;
    const page_width = previewPageWidth();
    const page_height = previewPageHeight();
    if (page_width <= 0 or page_height <= 0) return;

    const zoom_x = @as(f64, @floatFromInt(viewport.width)) / @as(f64, @floatFromInt(page_width));
    const zoom_y = @as(f64, @floatFromInt(viewport.height)) / @as(f64, @floatFromInt(page_height));
    preview_renderer.zoom = std.math.clamp(@min(zoom_x, zoom_y), 0.25, 4.0);

    if (previewBounds(hwnd)) |bounds| {
        preview_renderer.scroll_x = bounds.x.default_pos;
        preview_renderer.scroll_y = bounds.y.default_pos;
    } else {
        preview_renderer.scroll_x = 0;
        preview_renderer.scroll_y = 0;
    }
    refreshStatusDisplay();
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
        _ = currentPreviewPixelSize(hwnd) orelse {
            _ = render_target.ID2D1RenderTarget.EndDraw(null, null);
            return;
        };
        const page_w = @as(f64, @floatFromInt(previewPageWidth()));
        const page_h = @as(f64, @floatFromInt(previewPageHeight()));
        const bmp_w = previewBitmapLogicalWidth();
        const bmp_h = previewBitmapLogicalHeight();
        if (page_w <= 0.0 or page_h <= 0.0 or bmp_w <= 0.0 or bmp_h <= 0.0) {
            _ = render_target.ID2D1RenderTarget.EndDraw(null, null);
            return;
        }

        const placed_w = bmp_w;
        const placed_h = bmp_h;
        const placed_x = 0.0;
        const placed_y = 0.0;

        const page_left = -@as(f64, @floatFromInt(preview_renderer.scroll_x));
        const page_top = -@as(f64, @floatFromInt(preview_renderer.scroll_y));
        const page_rect = d2d_common.D2D_RECT_F{
            .left = @floatCast(page_left),
            .top = @floatCast(page_top),
            .right = @floatCast(page_left + page_w * preview_renderer.zoom),
            .bottom = @floatCast(page_top + page_h * preview_renderer.zoom),
        };

        var page_border_brush: ?*d2d.ID2D1SolidColorBrush = null;
        defer {
            if (page_border_brush) |b| {
                _ = b.IUnknown.Release();
            }
        }
        makeSolidColorBrush(&render_target.ID2D1RenderTarget, rgba8Color(214, 214, 214, 255), &page_border_brush);
        if (page_border_brush) |brush| {
            render_target.ID2D1RenderTarget.DrawRectangle(&page_rect, @ptrCast(brush), 1.0, null);
        }

        const dest_rect = d2d_common.D2D_RECT_F{
            .left = @floatCast(page_left + placed_x * preview_renderer.zoom),
            .top = @floatCast(page_top + placed_y * preview_renderer.zoom),
            .right = @floatCast(page_left + (placed_x + placed_w) * preview_renderer.zoom),
            .bottom = @floatCast(page_top + (placed_y + placed_h) * preview_renderer.zoom),
        };
        const source_rect = d2d_common.D2D_RECT_F{
            .left = 0,
            .top = 0,
            .right = @floatFromInt(preview_renderer.bitmap_width),
            .bottom = @floatFromInt(preview_renderer.bitmap_height),
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
            if (handleDiagramNavigationShortcut(@truncate(w_param), ctrl_down)) return 0;
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
        .d2d_factory = canvas_renderer.factory orelse return,
        .render_target = &rt.ID2D1RenderTarget,
        .dwrite_factory = dw_factory,
        .font_family = project_font_settings.font_family,
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
            if (result.document_mutated) scheduleFreeformPersist();
            if (result.selection_changed) {
                windows_canvas.inspector.refresh(&canvas_renderer.inspector, &canvas_renderer.canvas_state);
            }
            if (result.needs_redraw) _ = gdi.InvalidateRect(hwnd, null, 0);
            return 0;
        },
        ui.WM_MOUSEMOVE => {
            var track = std.mem.zeroes(TRACKMOUSEEVENT);
            track.cbSize = @sizeOf(TRACKMOUSEEVENT);
            track.dwFlags = tme_leave;
            track.hwndTrack = hwnd;
            _ = TrackMouseEvent(&track);

            const pos = mouseCoordFromLParam(l_param);
            const result = windows_canvas.interaction.onMouseMove(
                &canvas_renderer.canvas_state,
                pos.x,
                pos.y,
            );
            if (result.document_mutated) scheduleFreeformPersist();
            if (result.selection_changed) {
                windows_canvas.inspector.refresh(&canvas_renderer.inspector, &canvas_renderer.canvas_state);
            }
            if (result.needs_redraw) _ = gdi.InvalidateRect(hwnd, null, 0);
            return 0;
        },
        wm_mouseleave => {
            const result = windows_canvas.interaction.onMouseLeave(&canvas_renderer.canvas_state);
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
            if (result.document_mutated) scheduleFreeformPersist();
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
            const ctrl_down = mouse.GetKeyState(@intFromEnum(mouse.VK_CONTROL)) < 0;
            if (handleDiagramNavigationShortcut(vkey, ctrl_down)) return 0;
            switch (vkey) {
                @as(u16, @intCast(@intFromEnum(mouse.VK_PRIOR))) => {
                    if (scrollCanvasByPage(hwnd, -1)) _ = gdi.InvalidateRect(hwnd, null, 0);
                    return 0;
                },
                @as(u16, @intCast(@intFromEnum(mouse.VK_NEXT))) => {
                    if (scrollCanvasByPage(hwnd, 1)) _ = gdi.InvalidateRect(hwnd, null, 0);
                    return 0;
                },
                else => {},
            }
            const result = windows_canvas.interaction.onKeyDown(&canvas_renderer.canvas_state, vkey);
            if (result.document_mutated) scheduleFreeformPersist();
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
        rich_edit_class,
        initial_source,
        makeStyle(editor_style_bits),
        0,
        0,
        100,
        100,
        hwnd,
        @ptrFromInt(control_id_editor),
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

    const diagram_selector_style_bits = child_visible_bits |
        styleBits(ui.WS_TABSTOP) |
        styleBits(ui.WS_VSCROLL) |
        @as(u32, @intCast(ui.CBS_DROPDOWNLIST));
    const diagram_selector = ui.CreateWindowExA(
        .{},
        combo_box_class,
        null,
        makeStyle(diagram_selector_style_bits),
        0,
        0,
        180,
        240,
        hwnd,
        @ptrFromInt(control_id_diagram_selector),
        h_instance,
        null,
    ) orelse return false;

    const diagram_label = ui.CreateWindowExA(
        .{},
        static_class,
        "Diagrams",
        makeStyle(child_visible_bits),
        0,
        0,
        120,
        32,
        hwnd,
        @ptrFromInt(control_id_diagram_label),
        h_instance,
        null,
    ) orelse return false;

    const diagram_prev_button = ui.CreateWindowExA(
        .{},
        button_class,
        "Prev",
        makeStyle(child_visible_bits | styleBits(ui.WS_TABSTOP)),
        0,
        0,
        56,
        32,
        hwnd,
        @ptrFromInt(control_id_diagram_prev),
        h_instance,
        null,
    ) orelse return false;

    const diagram_next_button = ui.CreateWindowExA(
        .{},
        button_class,
        "Next",
        makeStyle(child_visible_bits | styleBits(ui.WS_TABSTOP)),
        0,
        0,
        56,
        32,
        hwnd,
        @ptrFromInt(control_id_diagram_next),
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
        @ptrFromInt(control_id_command),
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
        @ptrFromInt(control_id_apply_button),
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
    child_windows.diagram_label = diagram_label;
    child_windows.editor = editor;
    child_windows.toolbar = toolbar;
    child_windows.diagram_selector = diagram_selector;
    child_windows.diagram_prev_button = diagram_prev_button;
    child_windows.diagram_next_button = diagram_next_button;
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
    windows_canvas.inspector.setCanvasRef(&canvas_renderer.canvas_state, child_windows.canvas, &canvas_renderer.inspector, &project_font_settings, onProjectFontSettingsChanged, onFreeformGraphChanged);

    initializeToolbarControl();
    configureShellFonts();
    configureEditorControl();
    updateDiagramSelectorControl();
    refreshStatusDisplay();
    return true;
}

fn layoutChildWindows(hwnd: ?foundation.HWND) void {
    windows_layout.applyChildLayout(hwnd, child_windows, app_mode, sourcePanelVisible());
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

fn hashEditorText(text: []const u8) u64 {
    var hasher = std.hash.Wyhash.init(0);
    var index: usize = 0;
    while (index < text.len) {
        const char = text[index];
        if (char == '\r') {
            hasher.update("\n");
            if (index + 1 < text.len and text[index + 1] == '\n') {
                index += 2;
            } else {
                index += 1;
            }
            continue;
        }
        hasher.update(text[index .. index + 1]);
        index += 1;
    }
    return hasher.final();
}

fn refreshEditorStateFromLiveText(mark_dirty: bool, reset_view: bool) void {
    const editor_text = getEditorText(c_allocator) catch {
        setStatusMessage("Failed to read editor text");
        return;
    };
    defer c_allocator.free(editor_text);

    const next_hash = hashEditorText(editor_text);
    if (next_hash == last_editor_text_hash) return;

    last_editor_text_hash = next_hash;
    if (mark_dirty and !suppress_editor_change) {
        setDocumentDirty(true);
    }
    updateEditorDerivedState(reset_view);
}

fn setSyntaxErrorStatus(diagnostic: windows_editor.EditorDiagnostic) void {
    const status_text = if (diagnostic.line != null and diagnostic.column != null)
        std.fmt.allocPrint(c_allocator, "Line {d}:{d} | {s}", .{ diagnostic.line.?, diagnostic.column.?, diagnostic.message })
    else if (diagnostic.line != null)
        std.fmt.allocPrint(c_allocator, "Line {d} | {s}", .{ diagnostic.line.?, diagnostic.message })
    else
        std.fmt.allocPrint(c_allocator, "{s}", .{diagnostic.message});

    const owned_status = status_text catch {
        setStatusMessage(diagnostic.message);
        return;
    };
    defer c_allocator.free(owned_status);
    setStatusMessage(owned_status);
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
    last_editor_text_hash = hashEditorText(editor_text);

    if (!refreshCurrentMarkdownDocument(editor_text)) {
        clearPreviewImageState();
        clearCanvasGraphIfNeeded();
        requestPreviewRefresh();
        return;
    }

    syncDiagramSelectionToEditorCaret(editor_text, false);

    const diagram = currentSelectedDiagramBlock() orelse {
        windows_editor.applyEditorSyntaxHighlight(child_windows.editor, editor_text, &current_markdown_document.?, null);
        clearPreviewImageState();
        clearCanvasGraphIfNeeded();
        setStatusMessage("Document has no mermaid diagram blocks");
        requestPreviewRefresh();
        return;
    };

    var syntax_message: [256]u8 = std.mem.zeroes([256]u8);
    const syntax_result = merrow_studio_check_mermaid_syntax(diagram.mermaid_source.ptr, @intCast(diagram.mermaid_source.len), &syntax_message, syntax_message.len);
    const syntax_slice = std.mem.sliceTo(&syntax_message, 0);
    const syntax_text = if (syntax_slice.len > 0) syntax_slice else "Syntax check unavailable";

    const diagnostic = if (syntax_result != 0)
        adjustDiagnosticForDiagram(windows_editor.inferSyntaxDiagnostic(diagram.mermaid_source, syntax_text), diagram)
    else
        null;

    windows_editor.applyEditorSyntaxHighlight(child_windows.editor, editor_text, &current_markdown_document.?, diagnostic);

    if (syntax_result != 0) {
        clearPreviewImageState();
        setSyntaxErrorStatus(diagnostic.?);
        requestPreviewRefresh();
        return;
    }

    var preview_message: [256]u8 = std.mem.zeroes([256]u8);
    var preview_png_len: u32 = 0;
    const canvas_dims = currentProjectCanvasDimensions();
    const preview_png_ptr = merrow_studio_render_preview_png_bytes(
        diagram.mermaid_source.ptr,
        @intCast(diagram.mermaid_source.len),
        canvas_dims.width,
        canvas_dims.height,
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
        .{ previewStatusPrefix(), if (preview_status.len > 0) preview_status else syntax_text },
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
    if (app_mode == .mermaid) {
        switch (slot) {
            1 => {
                fitPreviewPageInView(child_windows.preview);
                setStatusMessage("Preview fit to page");
                return;
            },
            2 => {
                resetPreviewView(child_windows.preview);
                setStatusMessage("Preview at 100%");
                requestPreviewRefresh();
                return;
            },
            3 => {
                centerPreviewPage(child_windows.preview);
                setStatusMessage("Preview page centered");
                return;
            },
            else => {},
        }
    }

    const text = switch (slot) {
        1 => "Fit Page unavailable",
        2 => "100% unavailable",
        3 => "Center unavailable",
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
            show_source_panel_in_freeform = false;
            applyModeVisibility();
            setStatusMessage("Mermaid source mode");
        },
        .freeform => {
            show_source_panel_in_freeform = false;
            applyModeVisibility();

            // Layout must happen BEFORE fitToViewport so the canvas window
            // has its real dimensions (not the 100x100 creation default).
            layoutChildWindows(main_window);
            rebuildFreeformCanvas(true);
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
    const editor_text = getEditorText(c_allocator) catch return;
    defer c_allocator.free(editor_text);
    if (!refreshCurrentMarkdownDocument(editor_text)) return;

    const source = duplicateSelectedDiagramSource(c_allocator) catch {
        setStatusMessage("Document has no mermaid diagram for commands");
        return;
    };
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
        const rebuilt_source = replaceSelectedDiagramSource(std.mem.sliceTo(ptr, 0)) catch {
            setStatusMessage("Failed to merge updated diagram into document");
            return;
        };
        defer c_allocator.free(rebuilt_source);
        applyUpdatedSource(rebuilt_source, if (message_text.len > 0) message_text else "Command applied");
        setWindowText(child_windows.command, "");
    } else {
        const fallback = if (message_text.len > 0) message_text else "Command failed";
        setStatusMessage(fallback);
    }
}

fn shuffleDiagram() void {
    const editor_text = getEditorText(c_allocator) catch return;
    defer c_allocator.free(editor_text);
    if (!refreshCurrentMarkdownDocument(editor_text)) return;

    const source = duplicateSelectedDiagramSource(c_allocator) catch {
        setStatusMessage("Document has no mermaid diagram to shuffle");
        return;
    };
    defer c_allocator.free(source);

    var message: [256]u8 = std.mem.zeroes([256]u8);
    const updated_source = merrow_studio_shuffle_diagram(source.ptr, @intCast(source.len), &message, message.len);
    const message_text = std.mem.sliceTo(&message, 0);
    if (updated_source) |ptr| {
        defer merrow_studio_free_string(ptr);
        const rebuilt_source = replaceSelectedDiagramSource(std.mem.sliceTo(ptr, 0)) catch {
            setStatusMessage("Failed to merge shuffled diagram into document");
            return;
        };
        defer c_allocator.free(rebuilt_source);
        applyUpdatedSource(rebuilt_source, if (message_text.len > 0) message_text else "Shuffle applied");
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
            _ = ui.SetTimer(hwnd, main_timer_id_editor_refresh, 120, null);
            updateEditorDerivedState(true);
            updateWindowTitle();
            if (startup_preflight_message) |message_text| {
                setStatusMessage(message_text);
            }
            openLibraryDatabase();
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
                    menu_id_export_word => {
                        exportDiagramToWord();
                        return 0;
                    },
                    menu_id_font_settings => {
                        toggleFontInspector();
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
                    menu_id_toggle_source_panel => {
                        toggleSourcePanelVisibility();
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
            if (notification_code == ui.BN_CLICKED and (command_id == control_id_apply_button or source_hwnd == child_windows.apply_button)) {
                runDiagramCommand();
                return 0;
            }
            if (notification_code == ui.BN_CLICKED and (command_id == control_id_diagram_prev or source_hwnd == child_windows.diagram_prev_button)) {
                selectAdjacentDiagram(-1);
                return 0;
            }
            if (notification_code == ui.BN_CLICKED and (command_id == control_id_diagram_next or source_hwnd == child_windows.diagram_next_button)) {
                selectAdjacentDiagram(1);
                return 0;
            }
            if (notification_code == ui.CBN_SELCHANGE and (command_id == control_id_diagram_selector or source_hwnd == child_windows.diagram_selector)) {
                onDiagramSelectionChanged();
                return 0;
            }
            if (notification_code == ui.EN_CHANGE and (command_id == control_id_editor or source_hwnd == child_windows.editor)) {
                refreshEditorStateFromLiveText(true, false);
                return 0;
            }
            return ui.DefWindowProcA(hwnd, message, w_param, l_param);
        },
        ui.WM_NOTIFY => {
            const header: *const controls.NMHDR = @ptrFromInt(@as(usize, @bitCast(l_param)));
            if (header.hwndFrom == child_windows.editor and header.idFrom == control_id_editor and header.code == rich_edit.EN_SELCHANGE) {
                onEditorSelectionChanged();
                return 0;
            }
            return ui.DefWindowProcA(hwnd, message, w_param, l_param);
        },
        ui.WM_TIMER => {
            if (@as(usize, @bitCast(w_param)) == main_timer_id_editor_refresh) {
                refreshEditorStateFromLiveText(true, false);
                return 0;
            }
            if (@as(usize, @bitCast(w_param)) == main_timer_id_ffm_persist) {
                cancelScheduledFreeformPersist();
                persistCurrentFreeformGraph();
                return 0;
            }
            return ui.DefWindowProcA(hwnd, message, w_param, l_param);
        },
        ui.WM_INITMENUPOPUP => {
            // Tick the active mode in the View menu and keep the project inspector command freeform-only.
            const hmenu: ui.HMENU = @ptrFromInt(@as(usize, @bitCast(w_param)));
            _ = ui.CheckMenuItem(hmenu, menu_id_mode_mermaid, if (app_mode == .mermaid) @as(u32, @bitCast(ui.MF_CHECKED)) else @as(u32, @bitCast(ui.MF_UNCHECKED)));
            _ = ui.CheckMenuItem(hmenu, menu_id_mode_freeform, if (app_mode == .freeform) @as(u32, @bitCast(ui.MF_CHECKED)) else @as(u32, @bitCast(ui.MF_UNCHECKED)));
            _ = ui.CheckMenuItem(hmenu, menu_id_toggle_source_panel, if (sourcePanelVisible()) @as(u32, @bitCast(ui.MF_CHECKED)) else @as(u32, @bitCast(ui.MF_UNCHECKED)));
            _ = ui.CheckMenuItem(hmenu, menu_id_font_settings, if (app_mode == .freeform and windows_canvas.inspector.fontInspectorActive()) @as(u32, @bitCast(ui.MF_CHECKED)) else @as(u32, @bitCast(ui.MF_UNCHECKED)));
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
            _ = ui.KillTimer(hwnd, main_timer_id_editor_refresh);
            _ = ui.KillTimer(hwnd, main_timer_id_ffm_persist);
            persistCurrentFreeformGraph();
            closeLibraryDatabase();
            clearPreviewImageState();
            freeCurrentMarkdownDocument();
            unloadWordComGlue();
            freeStartupPreflightMessage();
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

    if (!ensureRichEditLibrary()) {
        return 1;
    }
    if (!runWindowsPreflight()) {
        return 1;
    }

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

        if (msg.hwnd == child_windows.editor and (msg.message == ui.WM_KEYDOWN or msg.message == ui.WM_SYSKEYDOWN)) {
            const ctrl_down = mouse.GetKeyState(@intFromEnum(mouse.VK_CONTROL)) < 0;
            if (handleDiagramNavigationShortcut(@truncate(msg.wParam), ctrl_down)) {
                continue;
            }
        }

        _ = ui.TranslateMessage(&msg);
        _ = ui.DispatchMessageA(&msg);
    }

    return 0;
}
