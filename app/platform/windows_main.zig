const std = @import("std");
const win32 = @import("win32");
const merrow = @import("merrow");
const ffm_serializer = @import("../ffm_serializer.zig");
const mermaid_export = @import("../mermaid_export.zig");
const mermaid_serializer = @import("../mermaid_serializer.zig");
const library_db = @import("../library_db.zig");
const markdown_parser = @import("../markdown_parser.zig");
const document_model = @import("../document_model.zig");
const merrow_lexer = merrow.lexer;
const merrow_directives = merrow.directives;
const windows_app_state = @import("windows/app_state.zig");
const windows_canvas = @import("windows/canvas.zig");
const windows_common = @import("windows/common.zig");
const windows_constants = @import("windows/constants.zig");
const windows_dpi = @import("windows/dpi.zig");
const windows_document = @import("windows/document.zig");
const windows_editor = @import("windows/editor.zig");
const windows_layout = @import("windows/layout.zig");
const windows_credentials = @import("windows/credentials.zig");
const windows_s3glue = @import("windows/s3glue.zig");
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

const build_options = @import("build_options");

comptime {
    _ = windows_credentials;
    _ = windows_s3glue;
}
const about_image_png = @embedFile("../assets/merrow-studio-icon.png");

const c_allocator = std.heap.c_allocator;
const class_name = windows_constants.class_name;
const preview_class_name = windows_constants.preview_class_name;
const canvas_class_name = windows_constants.canvas_class_name;
const about_class_name: [*:0]const u8 = "MerrowStudioAboutWindowClass";
const about_image_class_name: [*:0]const u8 = "MerrowStudioAboutImageWindowClass";
const about_window_title: [*:0]const u8 = "About Merrow Studio";
const cloud_storage_class_name: [*:0]const u8 = "MerrowStudioCloudStorageWindowClass";
const cloud_storage_window_title: [*:0]const u8 = "Cloud Storage";
const cloud_storage_region_label_text: [*:0]const u8 = "Region";
const cloud_storage_bucket_label_text: [*:0]const u8 = "Bucket ARN";
const cloud_storage_api_label_text: [*:0]const u8 = "API ID";
const cloud_storage_key_label_text: [*:0]const u8 = "Secret Key";
const cloud_storage_credential_target_region = "merrow_region";
const cloud_storage_credential_target_bucket = "merrow_bucket";
const cloud_storage_credential_target_id = "merrow_id";
const cloud_storage_credential_target_key = "merrow_key";
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
const menu_open_recent_label = windows_constants.menu_open_recent_label;
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
const menu_id_open_recent_empty = windows_constants.menu_id_open_recent_empty;
const menu_id_open_recent_first = windows_constants.menu_id_open_recent_first;
const menu_id_open_recent_last = windows_constants.menu_id_open_recent_last;
const menu_id_save = windows_constants.menu_id_save;
const menu_id_save_as = windows_constants.menu_id_save_as;
const menu_id_font_settings = windows_constants.menu_id_font_settings;
const menu_id_export_word = windows_constants.menu_id_export_word;
const menu_id_export_mermaid = windows_constants.menu_id_export_mermaid;
const menu_id_cloud_storage = windows_constants.menu_id_cloud_storage;
const menu_id_sync_cloud = windows_constants.menu_id_sync_cloud;
const menu_id_about = windows_constants.menu_id_about;
const control_id_editor = windows_constants.control_id_editor;
const control_id_command = windows_constants.control_id_command;
const control_id_apply_button = windows_constants.control_id_apply_button;
const control_id_diagram_selector = windows_constants.control_id_diagram_selector;
const control_id_diagram_prev = windows_constants.control_id_diagram_prev;
const control_id_diagram_next = windows_constants.control_id_diagram_next;
const control_id_diagram_label = windows_constants.control_id_diagram_label;
const control_id_about_image = windows_constants.control_id_about_image;
const control_id_about_title = windows_constants.control_id_about_title;
const control_id_about_version = windows_constants.control_id_about_version;
const control_id_about_license = windows_constants.control_id_about_license;
const control_id_about_ok = windows_constants.control_id_about_ok;
const control_id_cloud_storage_region_label = windows_constants.control_id_cloud_storage_region_label;
const control_id_cloud_storage_region_edit = windows_constants.control_id_cloud_storage_region_edit;
const control_id_cloud_storage_bucket_label = windows_constants.control_id_cloud_storage_bucket_label;
const control_id_cloud_storage_bucket_edit = windows_constants.control_id_cloud_storage_bucket_edit;
const control_id_cloud_storage_api_label = windows_constants.control_id_cloud_storage_api_label;
const control_id_cloud_storage_api_edit = windows_constants.control_id_cloud_storage_api_edit;
const control_id_cloud_storage_key_label = windows_constants.control_id_cloud_storage_key_label;
const control_id_cloud_storage_key_edit = windows_constants.control_id_cloud_storage_key_edit;
const control_id_cloud_storage_ok = windows_constants.control_id_cloud_storage_ok;
const main_timer_id_editor_refresh = windows_constants.main_timer_id_editor_refresh;
const main_timer_id_ffm_persist = windows_constants.main_timer_id_ffm_persist;
const main_timer_id_graph_source_writeback = windows_constants.main_timer_id_graph_source_writeback;
const menu_id_toggle_source_panel = windows_constants.menu_id_toggle_source_panel;
const menu_id_toggle_snap_to_grid = windows_constants.menu_id_toggle_snap_to_grid;
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
extern "user32" fn EnableWindow(hwnd: ?foundation.HWND, enable: foundation.BOOL) callconv(.winapi) foundation.BOOL;

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
const WCG_UNIT_MM: u32 = 2;
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
extern fn merrow_studio_free_editable_graph(graph: ?*windows_canvas.StudioEditableGraph) callconv(.c) void;
extern fn merrow_studio_check_mermaid_syntax(source_ptr: [*]const u8, source_len: u32, out_message: [*]u8, out_message_len: u32) callconv(.c) c_int;
extern fn merrow_studio_render_editable_graph_png_bytes(graph: ?*const windows_canvas.StudioEditableGraph, target_width: u32, target_height: u32, out_png_len: *u32, out_message: [*]u8, out_message_len: u32) callconv(.c) [*c]u8;
extern fn merrow_studio_render_editable_graph_svg(graph: ?*const windows_canvas.StudioEditableGraph, output_path_ptr: [*:0]const u8, target_width: u32, target_height: u32, out_message: [*]u8, out_message_len: u32) callconv(.c) c_int;
extern fn merrow_studio_render_preview_png_bytes(source_ptr: [*]const u8, source_len: u32, target_width: u32, target_height: u32, out_png_len: *u32, out_message: [*]u8, out_message_len: u32) callconv(.c) [*c]u8;
extern fn merrow_studio_apply_command(source_ptr: [*]const u8, source_len: u32, command_ptr: [*]const u8, command_len: u32, context_id_ptr: [*]const u8, context_id_len: u32, out_context_id: [*]u8, out_context_id_len: u32, out_context_display: [*]u8, out_context_display_len: u32, out_message: [*]u8, out_message_len: u32) callconv(.c) [*c]u8;
extern fn merrow_studio_shuffle_diagram(source_ptr: [*]const u8, source_len: u32, out_message: [*]u8, out_message_len: u32) callconv(.c) [*c]u8;
extern fn merrow_studio_free_string(text: [*c]u8) callconv(.c) void;
extern fn merrow_studio_free_buffer(buffer: [*c]u8, buffer_len: u32) callconv(.c) void;

// Unified canvas mode — source panel visibility is independently toggled.
const recent_file_menu_limit: usize = menu_id_open_recent_last - menu_id_open_recent_first + 1;
var child_windows = ChildWindows{};
var preview_renderer = PreviewRenderer{};
var canvas_renderer = CanvasRenderer.init(c_allocator);
var canvas_dwrite_factory: ?*dwrite.IDWriteFactory = null;
var main_window: ?foundation.HWND = null;
var canvas_snap_to_grid_enabled = true;
var current_document_path: ?[]u8 = null;
var current_markdown_document: ?document_model.MarkdownDocument = null;
var selected_diagram_index: usize = 0;
var show_source_panel = true;
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
var source_write_locked = false;
var last_editor_text_hash: u64 = 0;
var startup_layout_done = false;
var about_window: ?foundation.HWND = null;
var about_controls = AboutControls{};
var about_image_renderer = AboutImageRenderer{};
var about_title_font: ?gdi.HFONT = null;
var about_body_font: ?gdi.HFONT = null;
var cloud_storage_window: ?foundation.HWND = null;
var cloud_storage_controls = CloudStorageControls{};
const s3_virtual_path_prefix = "s3://";
const s3_library_key_prefix = "library/";
const s3_cache_dir_name = "s3-cache";
const s3_debug_log_name = "s3-debug.log";

const S3StorageError = error{
    MissingBucket,
    MissingSession,
    InvalidBucketArn,
    InvalidS3Path,
    RequestFailed,
};

const S3StorageState = struct {
    session: ?windows_s3glue.Session = null,
    bucket_name: ?[]u8 = null,
    bucket_arn: ?[]u8 = null,
    region: ?[]u8 = null,

    fn deinit(self: *S3StorageState) void {
        if (self.session) |*session| {
            session.deinit();
            self.session = null;
        }
        if (self.bucket_name) |value| {
            c_allocator.free(value);
            self.bucket_name = null;
        }
        if (self.bucket_arn) |value| {
            c_allocator.free(value);
            self.bucket_arn = null;
        }
        if (self.region) |value| {
            c_allocator.free(value);
            self.region = null;
        }
    }

    fn enabled(self: *const S3StorageState) bool {
        return self.session != null and self.bucket_name != null;
    }
};

var s3_storage = S3StorageState{};
var s3_in_use = false;
/// Last known mouse position within the canvas window (screen coords), for link preview.
var canvas_mouse_screen_x: i32 = 0;
var canvas_mouse_screen_y: i32 = 0;

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
const preview_min_zoom: f64 = 0.25;
const preview_max_zoom: f64 = 32.0;
const ffm_persist_debounce_ms: u32 = 450;
const graph_source_writeback_debounce_ms: u32 = 450;
const about_auto_close_timer_id: usize = 2303;
// Minimum virtual border around the image in display pixels; actual margin is
// max(preview_pan_margin, viewport/4) so it grows with window size.
const preview_pan_margin: i32 = 200;
const app_version = build_options.app_version;

const AboutControls = struct {
    image: ?foundation.HWND = null,
    title: ?foundation.HWND = null,
    version: ?foundation.HWND = null,
    license: ?foundation.HWND = null,
    ok_button: ?foundation.HWND = null,
};

const AboutImageRenderer = struct {
    render_target: ?*d2d.ID2D1HwndRenderTarget = null,
    bitmap: ?*d2d.ID2D1Bitmap = null,
    bitmap_width: u32 = 0,
    bitmap_height: u32 = 0,
};

const CloudStorageControls = struct {
    region_label: ?foundation.HWND = null,
    region_edit: ?foundation.HWND = null,
    bucket_label: ?foundation.HWND = null,
    bucket_edit: ?foundation.HWND = null,
    api_label: ?foundation.HWND = null,
    api_edit: ?foundation.HWND = null,
    key_label: ?foundation.HWND = null,
    key_edit: ?foundation.HWND = null,
    ok_button: ?foundation.HWND = null,
};

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

fn releaseAboutImageResources() void {
    releaseUnknown(&about_image_renderer.bitmap);
    releaseUnknown(&about_image_renderer.render_target);
    about_image_renderer.bitmap_width = 0;
    about_image_renderer.bitmap_height = 0;
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

fn createBitmapFromPngBytes(
    render_target: *d2d.ID2D1HwndRenderTarget,
    png_bytes: []const u8,
    out_bitmap: *?*d2d.ID2D1Bitmap,
    out_width: *u32,
    out_height: *u32,
) bool {
    if (!ensurePreviewImagingFactory()) return false;
    const wic_factory = preview_renderer.wic_factory orelse return false;

    var stream: ?*imaging.IWICStream = null;
    if (hrFailed(wic_factory.CreateStream(&stream)) or stream == null) return false;
    defer releaseUnknown(&stream);

    if (hrFailed(stream.?.InitializeFromMemory(@ptrCast(@constCast(png_bytes.ptr)), @intCast(png_bytes.len)))) return false;

    var decoder: ?*imaging.IWICBitmapDecoder = null;
    if (hrFailed(wic_factory.CreateDecoderFromStream(@ptrCast(stream.?), null, imaging.WICDecodeMetadataCacheOnLoad, &decoder)) or decoder == null) {
        return false;
    }
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

    if (hrFailed((@as(*imaging.IWICBitmapSource, @ptrCast(converter.?))).GetSize(out_width, out_height))) return false;

    var bitmap_raw: *d2d.ID2D1Bitmap = undefined;
    if (hrFailed(render_target.ID2D1RenderTarget.CreateBitmapFromWicBitmap(@ptrCast(converter.?), null, &bitmap_raw))) {
        return false;
    }

    out_bitmap.* = bitmap_raw;
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

fn disableCloudStorage() void {
    if (s3_in_use or s3_storage.bucket_name != null or s3_storage.bucket_arn != null) {
        appendS3Debug("cloud storage disabled");
    }
    s3_storage.deinit();
    s3_in_use = false;
}

fn s3DebugLogPath() ![]u8 {
    const folders = try windows_document.getMerrowUserFolders(c_allocator);
    defer folders.deinit(c_allocator);
    return std.fs.path.join(c_allocator, &.{ folders.temp, s3_debug_log_name });
}

fn appendS3Debug(message: []const u8) void {
    const log_path = s3DebugLogPath() catch return;
    defer c_allocator.free(log_path);

    const file = std.fs.createFileAbsolute(log_path, .{ .read = true, .truncate = false }) catch return;
    defer file.close();
    file.seekFromEnd(0) catch return;

    const line = std.fmt.allocPrint(
        c_allocator,
        "{d} | {s}\r\n",
        .{ std.time.timestamp(), message },
    ) catch return;
    defer c_allocator.free(line);

    file.writeAll(line) catch return;
}

fn appendS3DebugFmt(comptime fmt: []const u8, args: anytype) void {
    const message = std.fmt.allocPrint(c_allocator, fmt, args) catch return;
    defer c_allocator.free(message);
    appendS3Debug(message);
}

fn appendLastS3Error(session: *const windows_s3glue.Session, context: []const u8) void {
    var error_info = std.mem.zeroes(windows_s3glue.ErrorInfo);
    if (session.loaded.api.get_last_error(session.library, &error_info) != windows_s3glue.ok) {
        appendS3DebugFmt("{s}: no s3glue error details available", .{context});
        return;
    }

    const message = if (error_info.utf8_message) |value| std.mem.span(value) else "";
    const function_name = if (error_info.utf8_function) |value| std.mem.span(value) else "";
    appendS3DebugFmt(
        "{s}: status={d} http={d} aws={d} function={s} message={s}",
        .{ context, error_info.status, error_info.http_status, error_info.aws_error, function_name, message },
    );
}

fn storageUsesS3() bool {
    return s3_in_use and s3_storage.enabled();
}

fn isS3VirtualPath(path: []const u8) bool {
    return std.mem.startsWith(u8, path, s3_virtual_path_prefix);
}

fn parseS3BucketName(bucket_arn: []const u8) ?[]const u8 {
    if (bucket_arn.len == 0) return null;
    if (!std.mem.startsWith(u8, bucket_arn, "arn:")) return bucket_arn;

    const marker = ":::";
    const marker_index = std.mem.indexOf(u8, bucket_arn, marker) orelse return null;
    const tail = bucket_arn[marker_index + marker.len ..];
    if (tail.len == 0) return null;
    const end = std.mem.indexOfAny(u8, tail, "/:") orelse tail.len;
    if (end == 0) return null;
    return tail[0..end];
}

fn buildS3VirtualPathForKey(key: []const u8) ![]u8 {
    const bucket_name = s3_storage.bucket_name orelse return S3StorageError.MissingBucket;
    return std.fmt.allocPrint(c_allocator, "{s}{s}/{s}", .{ s3_virtual_path_prefix, bucket_name, key });
}

fn buildS3VirtualPathForDocumentName(file_name: []const u8) ![]u8 {
    const key = try std.fmt.allocPrint(c_allocator, "{s}{s}", .{ s3_library_key_prefix, file_name });
    defer c_allocator.free(key);
    return buildS3VirtualPathForKey(key);
}

fn s3KeyFromVirtualPath(path: []const u8) ?[]const u8 {
    if (!isS3VirtualPath(path)) return null;

    const remainder = path[s3_virtual_path_prefix.len..];
    const slash_index = std.mem.indexOfScalar(u8, remainder, '/') orelse return null;
    const bucket_name = remainder[0..slash_index];
    const expected_bucket_name = s3_storage.bucket_name orelse return null;
    if (!std.mem.eql(u8, bucket_name, expected_bucket_name)) return null;

    const key = remainder[slash_index + 1 ..];
    if (key.len == 0) return null;
    return key;
}

fn buildProjectSettingsStoragePath(document_path: []const u8) ![]u8 {
    return std.fmt.allocPrint(c_allocator, "{s}.merrow.json", .{document_path});
}

fn ensureS3CacheDirectory() ![]u8 {
    const folders = try windows_document.getMerrowUserFolders(c_allocator);
    defer folders.deinit(c_allocator);

    const cache_dir = try std.fs.path.join(c_allocator, &.{ folders.temp, s3_cache_dir_name });
    errdefer c_allocator.free(cache_dir);
    std.fs.makeDirAbsolute(cache_dir) catch |err| switch (err) {
        error.PathAlreadyExists => {},
        else => return err,
    };
    return cache_dir;
}

fn buildS3CachePath(key: []const u8) ![]u8 {
    const cache_dir = try ensureS3CacheDirectory();
    defer c_allocator.free(cache_dir);

    const file_name = try std.fmt.allocPrint(
        c_allocator,
        "{x}-{s}",
        .{ std.hash.Wyhash.hash(0, key), std.fs.path.basename(key) },
    );
    defer c_allocator.free(file_name);

    return std.fs.path.join(c_allocator, &.{ cache_dir, file_name });
}

fn loadBytesFromS3Path(path: []const u8) ![]u8 {
    const session = &(s3_storage.session orelse return S3StorageError.MissingSession);
    const bucket_name = s3_storage.bucket_name orelse return S3StorageError.MissingBucket;
    const key = s3KeyFromVirtualPath(path) orelse return S3StorageError.InvalidS3Path;

    appendS3DebugFmt("download start bucket={s} key={s}", .{ bucket_name, key });

    const bucket_name_z = try c_allocator.dupeZ(u8, bucket_name);
    defer c_allocator.free(bucket_name_z);
    const key_z = try c_allocator.dupeZ(u8, key);
    defer c_allocator.free(key_z);

    const temp_path = try buildS3CachePath(key);
    defer c_allocator.free(temp_path);
    defer std.fs.deleteFileAbsolute(temp_path) catch {};
    const temp_path_z = try c_allocator.dupeZ(u8, temp_path);
    defer c_allocator.free(temp_path_z);

    if (session.loaded.api.get_object_file(session.client, bucket_name_z.ptr, key_z.ptr, temp_path_z.ptr) != windows_s3glue.ok) {
        appendLastS3Error(session, "download failed");
        return S3StorageError.RequestFailed;
    }

    appendS3DebugFmt("download complete bucket={s} key={s}", .{ bucket_name, key });

    return windows_document.loadSourceFromPath(c_allocator, temp_path);
}

fn saveBytesToS3Path(path: []const u8, bytes: []const u8) !void {
    const session = &(s3_storage.session orelse return S3StorageError.MissingSession);
    const bucket_name = s3_storage.bucket_name orelse return S3StorageError.MissingBucket;
    const key = s3KeyFromVirtualPath(path) orelse return S3StorageError.InvalidS3Path;

    appendS3DebugFmt("upload start bucket={s} key={s} bytes={d}", .{ bucket_name, key, bytes.len });

    const temp_path = try buildS3CachePath(key);
    defer c_allocator.free(temp_path);
    defer std.fs.deleteFileAbsolute(temp_path) catch {};
    try windows_document.saveSourceToPath(temp_path, bytes);

    const bucket_name_z = try c_allocator.dupeZ(u8, bucket_name);
    defer c_allocator.free(bucket_name_z);
    const key_z = try c_allocator.dupeZ(u8, key);
    defer c_allocator.free(key_z);
    const temp_path_z = try c_allocator.dupeZ(u8, temp_path);
    defer c_allocator.free(temp_path_z);

    if (session.loaded.api.put_object_file(session.client, bucket_name_z.ptr, key_z.ptr, temp_path_z.ptr, null) != windows_s3glue.ok) {
        appendLastS3Error(session, "upload failed");
        return S3StorageError.RequestFailed;
    }

    appendS3DebugFmt("upload complete bucket={s} key={s}", .{ bucket_name, key });
}

fn loadBytesFromStoragePath(path: []const u8) ![]u8 {
    return windows_document.loadSourceFromPath(c_allocator, path);
}

fn saveBytesToStoragePath(path: []const u8, bytes: []const u8) !void {
    return windows_document.saveSourceToPath(path, bytes);
}

/// Compute the MD5 of a local file and return it as a lowercase hex string.
/// Returns null on any I/O error. Caller must free the returned slice with c_allocator.
fn computeLocalMd5Hex(path: []const u8) ?[]u8 {
    const f = std.fs.openFileAbsolute(path, .{}) catch return null;
    defer f.close();
    var md5 = std.crypto.hash.Md5.init(.{});
    var buf: [8192]u8 = undefined;
    while (true) {
        const n = f.read(&buf) catch break;
        if (n == 0) break;
        md5.update(buf[0..n]);
    }
    var digest: [std.crypto.hash.Md5.digest_length]u8 = undefined;
    md5.final(&digest);
    const result = c_allocator.alloc(u8, 32) catch return null;
    const hex = "0123456789abcdef";
    for (digest, 0..) |byte, i| {
        result[i * 2] = hex[byte >> 4];
        result[i * 2 + 1] = hex[byte & 0xf];
    }
    return result;
}

/// Strip wrapping quotes from an S3 ETag. Returns null for multipart ETags
/// (those containing '-', e.g. "abc-3") since they cannot be compared to a local MD5.
fn normalizeEtag(raw: []const u8) ?[]const u8 {
    var s = raw;
    if (s.len >= 2 and s[0] == '"' and s[s.len - 1] == '"') s = s[1 .. s.len - 1];
    if (std.mem.indexOfScalar(u8, s, '-') != null) return null;
    return s;
}

/// Returns true if the local file content matches the S3 ETag (MD5 comparison).
/// False if ETag is missing, multipart, or computation fails.
fn localMatchesS3Etag(path: []const u8, raw_etag: ?[*:0]const u8) bool {
    const etag_z = raw_etag orelse return false;
    const s3_hash = normalizeEtag(std.mem.sliceTo(etag_z, 0)) orelse return false;
    const local_hash = computeLocalMd5Hex(path) orelse return false;
    defer c_allocator.free(local_hash);
    return std.mem.eql(u8, local_hash, s3_hash);
}

/// Upload a local file to S3 under the library/ prefix using its basename as the key.
/// Logs debug info; returns an error on failure (caller decides whether to surface it).
fn uploadLocalFileToS3(local_path: []const u8) !void {
    const session = &(s3_storage.session orelse return S3StorageError.MissingSession);
    const bucket_name = s3_storage.bucket_name orelse return S3StorageError.MissingBucket;

    const key = try std.fmt.allocPrint(c_allocator, "{s}{s}", .{ s3_library_key_prefix, std.fs.path.basename(local_path) });
    defer c_allocator.free(key);

    const bucket_z = try c_allocator.dupeZ(u8, bucket_name);
    defer c_allocator.free(bucket_z);
    const key_z = try c_allocator.dupeZ(u8, key);
    defer c_allocator.free(key_z);
    const path_z = try c_allocator.dupeZ(u8, local_path);
    defer c_allocator.free(path_z);

    appendS3DebugFmt("upload start key={s}", .{key});
    if (session.loaded.api.put_object_file(session.client, bucket_z.ptr, key_z.ptr, path_z.ptr, null) != windows_s3glue.ok) {
        appendLastS3Error(session, "upload failed");
        return S3StorageError.RequestFailed;
    }
    appendS3DebugFmt("upload complete key={s}", .{key});
}

/// Bidirectional sync between the local Merrow library folder and the S3 library/ prefix.
/// Files newer locally are uploaded; files newer on S3 (or absent locally) are downloaded.
fn syncCloudStorage() void {
    if (!storageUsesS3()) {
        setStatusMessage("Cloud storage not connected — configure it in Settings > Cloud Storage");
        return;
    }

    const session = &(s3_storage.session orelse return);
    const bucket_name = s3_storage.bucket_name orelse return;

    appendS3Debug("sync started");
    setStatusMessage("Syncing with cloud storage...");

    const folders = windows_document.getMerrowUserFolders(c_allocator) catch {
        setStatusMessage("Sync failed: could not resolve library folder");
        return;
    };
    defer folders.deinit(c_allocator);

    // List all S3 objects under library/ (up to 1 000 — enough for personal teams).
    const bucket_z = c_allocator.dupeZ(u8, bucket_name) catch return;
    defer c_allocator.free(bucket_z);
    const prefix_z = c_allocator.dupeZ(u8, s3_library_key_prefix) catch return;
    defer c_allocator.free(prefix_z);

    var list_options = windows_s3glue.ListOptions{
        .utf8_prefix = prefix_z.ptr,
        .utf8_delimiter = null,
        .utf8_continuation_token = null,
        .max_keys = 1000,
        .flags = 0,
    };
    var list_result = std.mem.zeroes(windows_s3glue.ListResult);
    if (session.loaded.api.list_objects(session.client, bucket_z.ptr, &list_options, &list_result) != windows_s3glue.ok) {
        appendLastS3Error(session, "sync list failed");
        setStatusMessage("Sync failed: could not list S3 objects");
        return;
    }
    defer _ = session.loaded.api.free_list_result(&list_result);

    const s3_objects: []const windows_s3glue.ListEntry = if (list_result.objects) |objs|
        objs[0..list_result.object_count]
    else
        &[_]windows_s3glue.ListEntry{};

    var uploads: usize = 0;
    var downloads: usize = 0;
    var errors: usize = 0;

    // --- Phase 1: upload local files that are newer than S3 ---
    var lib_dir = std.fs.openDirAbsolute(folders.library, .{ .iterate = true }) catch {
        setStatusMessage("Sync failed: could not open library folder");
        return;
    };
    defer lib_dir.close();

    var iter = lib_dir.iterate();
    while (iter.next() catch null) |entry| {
        if (entry.kind != .file) continue;
        const name = entry.name;
        if (!std.mem.endsWith(u8, name, ".mmd") and
            !std.mem.endsWith(u8, name, ".merrow.json") and
            !std.mem.endsWith(u8, name, ".ffm")) continue;

        const local_path = std.fs.path.join(c_allocator, &.{ folders.library, name }) catch continue;
        defer c_allocator.free(local_path);

        const local_mtime_sec = blk: {
            const f = std.fs.openFileAbsolute(local_path, .{}) catch break :blk null;
            defer f.close();
            const st = f.stat() catch break :blk null;
            const sec: i64 = @intCast(@divTrunc(st.mtime, std.time.ns_per_s));
            break :blk sec;
        };
        if (local_mtime_sec == null) continue;

        const s3_key = std.fmt.allocPrint(c_allocator, "{s}{s}", .{ s3_library_key_prefix, name }) catch continue;
        defer c_allocator.free(s3_key);

        var s3_mtime: ?i64 = null;
        var s3_raw_etag: ?[*:0]const u8 = null;
        for (s3_objects) |obj| {
            const obj_key = if (obj.utf8_key) |k| std.mem.sliceTo(k, 0) else continue;
            if (std.mem.eql(u8, obj_key, s3_key)) {
                s3_mtime = obj.last_modified_epoch_seconds;
                s3_raw_etag = obj.utf8_etag;
                break;
            }
        }

        // Hash check: skip upload entirely if the content is already identical on S3.
        if (s3_raw_etag != null and localMatchesS3Etag(local_path, s3_raw_etag)) {
            appendS3DebugFmt("sync skip upload (hash match) {s}", .{name});
            continue;
        }

        const should_upload = if (s3_mtime) |s3t| local_mtime_sec.? > s3t else true;
        if (should_upload) {
            uploadLocalFileToS3(local_path) catch |err| {
                appendS3DebugFmt("sync upload failed {s}: {s}", .{ name, @errorName(err) });
                errors += 1;
                continue;
            };
            uploads += 1;
        }
    }

    // --- Phase 2: download S3 files that are newer than (or absent from) local ---
    for (s3_objects) |obj| {
        const obj_key = if (obj.utf8_key) |k| std.mem.sliceTo(k, 0) else continue;
        if (!std.mem.startsWith(u8, obj_key, s3_library_key_prefix)) continue;
        const file_name = obj_key[s3_library_key_prefix.len..];
        if (file_name.len == 0) continue;
        if (!std.mem.endsWith(u8, file_name, ".mmd") and
            !std.mem.endsWith(u8, file_name, ".merrow.json") and
            !std.mem.endsWith(u8, file_name, ".ffm")) continue;

        const local_path = std.fs.path.join(c_allocator, &.{ folders.library, file_name }) catch continue;
        defer c_allocator.free(local_path);

        const local_mtime_sec: ?i64 = blk: {
            const f = std.fs.openFileAbsolute(local_path, .{}) catch break :blk null;
            defer f.close();
            const st = f.stat() catch break :blk null;
            const sec: i64 = @intCast(@divTrunc(st.mtime, std.time.ns_per_s));
            break :blk sec;
        };

        const s3_mtime = obj.last_modified_epoch_seconds;

        // Hash check: skip download entirely if the content is already identical locally.
        if (local_mtime_sec != null and localMatchesS3Etag(local_path, obj.utf8_etag)) {
            appendS3DebugFmt("sync skip download (hash match) {s}", .{file_name});
            continue;
        }

        const should_download = if (local_mtime_sec) |lmt| s3_mtime > lmt else true;
        if (!should_download) continue;

        const key_z = c_allocator.dupeZ(u8, obj_key) catch continue;
        defer c_allocator.free(key_z);
        const path_z = c_allocator.dupeZ(u8, local_path) catch continue;
        defer c_allocator.free(path_z);

        appendS3DebugFmt("sync download key={s}", .{obj_key});
        if (session.loaded.api.get_object_file(session.client, bucket_z.ptr, key_z.ptr, path_z.ptr) != windows_s3glue.ok) {
            appendLastS3Error(session, "sync download failed");
            errors += 1;
            continue;
        }
        downloads += 1;
    }

    appendS3DebugFmt("sync complete uploads={d} downloads={d} errors={d}", .{ uploads, downloads, errors });

    const message = std.fmt.allocPrint(
        c_allocator,
        "Sync complete: {d} uploaded, {d} downloaded{s}",
        .{ uploads, downloads, if (errors > 0) " (some errors — see s3-debug.log)" else "" },
    ) catch {
        setStatusMessage("Sync complete");
        return;
    };
    defer c_allocator.free(message);
    setStatusMessage(message);
    if (downloads > 0) refreshRecentFilesMenu();
}

fn validateS3Connection(session: *windows_s3glue.Session, bucket_name: []const u8) bool {
    const bucket_name_z = c_allocator.dupeZ(u8, bucket_name) catch return false;
    defer c_allocator.free(bucket_name_z);
    const prefix_z = c_allocator.dupeZ(u8, s3_library_key_prefix) catch return false;
    defer c_allocator.free(prefix_z);

    var list_options = windows_s3glue.ListOptions{
        .utf8_prefix = prefix_z.ptr,
        .utf8_delimiter = null,
        .utf8_continuation_token = null,
        .max_keys = 1,
        .flags = 0,
    };
    var list_result = std.mem.zeroes(windows_s3glue.ListResult);
    const status = session.loaded.api.list_objects(session.client, bucket_name_z.ptr, &list_options, &list_result);
    if (status == windows_s3glue.ok) {
        _ = session.loaded.api.free_list_result(&list_result);
        appendS3DebugFmt("connection validated for bucket={s} prefix={s}", .{ bucket_name, s3_library_key_prefix });
        return true;
    }
    appendLastS3Error(session, "connection validation failed");
    return false;
}

fn refreshCloudStorageState(report_failures: bool) bool {
    appendS3Debug("cloud storage refresh started");
    disableCloudStorage();

    const region = windows_credentials.loadString(c_allocator, cloud_storage_credential_target_region) catch null;
    defer if (region) |value| windows_credentials.wipeAndFree(c_allocator, value);
    const bucket_arn = windows_credentials.loadString(c_allocator, cloud_storage_credential_target_bucket) catch null;
    defer if (bucket_arn) |value| windows_credentials.wipeAndFree(c_allocator, value);
    const api_id = windows_credentials.loadString(c_allocator, cloud_storage_credential_target_id) catch null;
    defer if (api_id) |value| windows_credentials.wipeAndFree(c_allocator, value);
    const secret_key = windows_credentials.loadString(c_allocator, cloud_storage_credential_target_key) catch null;
    defer if (secret_key) |value| windows_credentials.wipeAndFree(c_allocator, value);

    appendS3DebugFmt(
        "credential presence region={any} bucket={any} api_id={any} secret_key={any}",
        .{ region != null, bucket_arn != null, api_id != null, secret_key != null },
    );

    if (region == null or bucket_arn == null or api_id == null or secret_key == null) {
        appendS3Debug("cloud storage refresh skipped due to missing credentials");
        return false;
    }
    if (region.?.len == 0 or bucket_arn.?.len == 0 or api_id.?.len == 0 or secret_key.?.len == 0) {
        appendS3DebugFmt(
            "cloud storage refresh skipped due to empty values region_len={d} bucket_len={d} api_id_len={d} secret_key_len={d}",
            .{ region.?.len, bucket_arn.?.len, api_id.?.len, secret_key.?.len },
        );
        return false;
    }

    const bucket_name = parseS3BucketName(bucket_arn.?) orelse {
        appendS3DebugFmt("bucket arn parse failed value={s}", .{bucket_arn.?});
        if (report_failures) setStatusMessage("S3 bucket ARN is invalid; using local storage");
        return false;
    };

    appendS3DebugFmt(
        "attempting S3 session region={s} bucket_arn={s} bucket_name={s} api_id_len={d} secret_key_len={d}",
        .{ region.?, bucket_arn.?, bucket_name, api_id.?.len, secret_key.?.len },
    );

    var session = windows_s3glue.openSession(c_allocator, .{
        .region = region.?,
        .credentials = .{ .static = .{
            .access_key_id = api_id.?,
            .secret_access_key = secret_key.?,
        } },
    }) catch |err| {
        appendS3DebugFmt("s3 session creation failed before validation error={s}", .{@errorName(err)});
        if (report_failures) setStatusMessage("S3 session could not be created; using local storage");
        return false;
    };

    appendS3Debug("s3 session created; validating bucket access");

    if (!validateS3Connection(&session, bucket_name)) {
        session.deinit();
        if (report_failures) setStatusMessage("S3 credentials were rejected; using local storage");
        return false;
    }

    const bucket_name_copy = c_allocator.dupe(u8, bucket_name) catch {
        session.deinit();
        return false;
    };
    errdefer c_allocator.free(bucket_name_copy);
    const bucket_arn_copy = c_allocator.dupe(u8, bucket_arn.?) catch {
        session.deinit();
        return false;
    };
    errdefer c_allocator.free(bucket_arn_copy);
    const region_copy = c_allocator.dupe(u8, region.?) catch {
        session.deinit();
        return false;
    };

    s3_storage.session = session;
    s3_storage.bucket_name = bucket_name_copy;
    s3_storage.bucket_arn = bucket_arn_copy;
    s3_storage.region = region_copy;
    s3_in_use = true;
    appendS3DebugFmt("cloud storage enabled bucket={s} region={s}", .{ bucket_name_copy, region_copy });
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
    refreshRecentFilesMenu();
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

fn setEditorReadOnly(read_only: bool) void {
    windows_editor.setEditorReadOnly(child_windows.editor, read_only);
}

fn setSourceWriteLocked(locked: bool) void {
    if (source_write_locked == locked) return;
    source_write_locked = locked;
    setEditorReadOnly(locked);
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
        null,
        true,
        word_dialog_filter,
        export_word_dialog_title,
        word_default_extension,
    );
}

fn getRecentFilesMenu() ?ui.HMENU {
    const hwnd = main_window orelse return null;
    const main_menu = ui.GetMenu(hwnd) orelse return null;
    const file_menu = ui.GetSubMenu(main_menu, 0) orelse return null;
    return ui.GetSubMenu(file_menu, 1);
}

fn clearMenuItems(menu: ui.HMENU) void {
    while (ui.GetMenuItemCount(menu) > 0) {
        _ = ui.DeleteMenu(menu, 0, ui.MF_BYPOSITION);
    }
}

fn refreshRecentFilesMenu() void {
    const recent_menu = getRecentFilesMenu() orelse return;
    clearMenuItems(recent_menu);

    var db = &(library_database orelse {
        _ = ui.AppendMenuA(recent_menu, ui.MF_STRING, menu_id_open_recent_empty, "(No recent files)");
        return;
    });

    const records = db.loadRecentFiles(c_allocator, recent_file_menu_limit) catch {
        _ = ui.AppendMenuA(recent_menu, ui.MF_STRING, menu_id_open_recent_empty, "(No recent files)");
        return;
    };
    defer {
        for (records) |*record| record.deinit(c_allocator);
        c_allocator.free(records);
    }

    if (records.len == 0) {
        _ = ui.AppendMenuA(recent_menu, ui.MF_STRING, menu_id_open_recent_empty, "(No recent files)");
        return;
    }

    for (records, 0..) |record, idx| {
        const label = std.fmt.allocPrint(c_allocator, "&{d} {s}", .{ idx + 1, std.fs.path.basename(record.path) }) catch continue;
        defer c_allocator.free(label);
        const label_z = c_allocator.dupeZ(u8, label) catch continue;
        defer c_allocator.free(label_z);
        _ = ui.AppendMenuA(recent_menu, ui.MF_STRING, menu_id_open_recent_first + idx, label_z.ptr);
    }
}

fn loadSourceFromPath(path: []const u8) ![]u8 {
    return loadBytesFromStoragePath(path);
}

fn saveSourceToPath(path: []const u8, source: []const u8) !void {
    return saveBytesToStoragePath(path, source);
}

const CanvasSizeCm = struct {
    width_cm: f64,
    height_cm: f64,
};

fn currentProjectCanvasSizeCm() CanvasSizeCm {
    return .{
        .width_cm = project_font_settings.canvas_width_cm,
        .height_cm = project_font_settings.canvas_height_cm,
    };
}

fn canvasDimensionsForSizeCm(size_cm: CanvasSizeCm) CanvasDimensions {
    return windows_project_settings.canvasDimensionsFromCentimeters(size_cm.width_cm, size_cm.height_cm);
}

fn currentProjectCanvasDimensions() CanvasDimensions {
    return canvasDimensionsForSizeCm(currentProjectCanvasSizeCm());
}

fn exportDimensionsForSizeCm(size_cm: CanvasSizeCm) CanvasDimensions {
    return windows_project_settings.exportDimensionsFromCentimeters(size_cm.width_cm, size_cm.height_cm);
}

// ---------------------------------------------------------------------------
// Freeform canvas context menu
// ---------------------------------------------------------------------------

/// Node shape u32 constants (must stay in sync with src/model.zig NodeShape enum order).
const node_shape_box: u32 = 0;
const node_shape_round: u32 = 1;
const node_shape_diamond: u32 = 2;
const node_shape_circle: u32 = 3;
const node_shape_hexagon: u32 = 4;
const node_shape_cylinder: u32 = 5;
const node_shape_stadium: u32 = 6;

/// Graph type constants (must stay in sync with StudioGraphType enum in preview.zig).
const graph_type_flowchart: u32 = 0;

/// Show the canvas right-click context menu when nothing is selected (no-selection state).
/// Returns immediately via TPM_RETURNCMD and dispatches the result.
fn showCanvasContextMenuEmpty(hwnd: foundation.HWND, client_x: i32, client_y: i32) void {
    const g = canvas_renderer.canvas_state.graph orelse return;
    if (g.graph_type != graph_type_flowchart) return;

    const menu = ui.CreatePopupMenu() orelse return;
    defer _ = ui.DestroyMenu(menu);

    _ = ui.AppendMenuA(menu, ui.MF_STRING, windows_constants.ctx_menu_add_box, "Add Box");
    _ = ui.AppendMenuA(menu, ui.MF_STRING, windows_constants.ctx_menu_add_round, "Add Rounded Box");
    _ = ui.AppendMenuA(menu, ui.MF_STRING, windows_constants.ctx_menu_add_diamond, "Add Diamond (Decision)");
    _ = ui.AppendMenuA(menu, ui.MF_STRING, windows_constants.ctx_menu_add_circle, "Add Circle");
    _ = ui.AppendMenuA(menu, ui.MF_STRING, windows_constants.ctx_menu_add_stadium, "Add Stadium (Pill)");
    _ = ui.AppendMenuA(menu, ui.MF_STRING, windows_constants.ctx_menu_add_hexagon, "Add Hexagon");
    _ = ui.AppendMenuA(menu, ui.MF_STRING, windows_constants.ctx_menu_add_cylinder, "Add Cylinder (Database)");
    _ = ui.AppendMenuA(menu, ui.MF_SEPARATOR, 0, null);
    _ = ui.AppendMenuA(menu, ui.MF_STRING, windows_constants.ctx_menu_add_subgraph, "Add Group");

    // Convert client coords to screen coords for popup placement.
    var pt = foundation.POINT{ .x = client_x, .y = client_y };
    _ = gdi.ClientToScreen(hwnd, &pt);

    // TPM_LEFTALIGN=0x0000 | TPM_TOPALIGN=0x0000 | TPM_RETURNCMD=0x0100
    const tpm_flags: ui.TRACK_POPUP_MENU_FLAGS = @bitCast(@as(u32, 0x0100));
    const cmd_raw = ui.TrackPopupMenu(
        menu,
        tpm_flags,
        pt.x,
        pt.y,
        0,
        hwnd,
        null,
    );

    const cmd: usize = @intCast(cmd_raw);
    if (cmd == 0) return; // user dismissed

    const shape: ?u32 = switch (cmd) {
        windows_constants.ctx_menu_add_box => node_shape_box,
        windows_constants.ctx_menu_add_round => node_shape_round,
        windows_constants.ctx_menu_add_diamond => node_shape_diamond,
        windows_constants.ctx_menu_add_circle => node_shape_circle,
        windows_constants.ctx_menu_add_stadium => node_shape_stadium,
        windows_constants.ctx_menu_add_hexagon => node_shape_hexagon,
        windows_constants.ctx_menu_add_cylinder => node_shape_cylinder,
        else => null,
    };

    if (cmd == windows_constants.ctx_menu_add_subgraph) {
        // Activate subgraph insertion mode.
        canvas_renderer.canvas_state.insertion = .{ .kind = .subgraph };
        windows_canvas.interaction.setCursor(ui.IDC_CROSS);
        _ = gdi.InvalidateRect(hwnd, null, 0);
        setStatusMessage("Click on the canvas to place a group");
        return;
    }

    if (shape) |s| {
        canvas_renderer.canvas_state.insertion = .{ .kind = .node, .node_shape = s };
        windows_canvas.interaction.setCursor(ui.IDC_CROSS);
        _ = gdi.InvalidateRect(hwnd, null, 0);
        setStatusMessage("Click on the canvas to place the shape");
    }
}

/// Right-click context menu shown when an object is selected.
fn showCanvasContextMenuSelected(hwnd: foundation.HWND, client_x: i32, client_y: i32) void {
    const canvas = &canvas_renderer.canvas_state;
    const in_link_mode = canvas.insertion.kind == .connector_source;

    const menu = ui.CreatePopupMenu() orelse return;
    defer _ = ui.DestroyMenu(menu);

    if (in_link_mode) {
        // If something is selected we can complete the link here.
        if (canvas.hasSelection()) {
            _ = ui.AppendMenuA(menu, ui.MF_STRING, windows_constants.ctx_menu_end_link, "End Link Here");
            _ = ui.AppendMenuA(menu, ui.MF_SEPARATOR, 0, null);
        }
        _ = ui.AppendMenuA(menu, ui.MF_STRING, windows_constants.ctx_menu_cancel_link, "Cancel Link");
    } else {
        _ = ui.AppendMenuA(menu, ui.MF_STRING, windows_constants.ctx_menu_delete, "Delete");
        if (canvas.selection.kind != .edge) {
            _ = ui.AppendMenuA(menu, ui.MF_SEPARATOR, 0, null);
            _ = ui.AppendMenuA(menu, ui.MF_STRING, windows_constants.ctx_menu_begin_link, "Begin Link");
        }
        // Allow adding a group even when something is already selected.
        if (canvas.graph) |g| {
            if (g.graph_type == graph_type_flowchart) {
                _ = ui.AppendMenuA(menu, ui.MF_SEPARATOR, 0, null);
                _ = ui.AppendMenuA(menu, ui.MF_STRING, windows_constants.ctx_menu_add_subgraph, "Add Group");
            }
        }
    }

    var pt = foundation.POINT{ .x = client_x, .y = client_y };
    _ = gdi.ClientToScreen(hwnd, &pt);

    const tpm_flags: ui.TRACK_POPUP_MENU_FLAGS = @bitCast(@as(u32, 0x0100));
    const cmd_raw = ui.TrackPopupMenu(menu, tpm_flags, pt.x, pt.y, 0, hwnd, null);
    const cmd: usize = @intCast(cmd_raw);
    if (cmd == 0) return;

    switch (cmd) {
        windows_constants.ctx_menu_delete => {
            deleteSelectedObject();
            windows_canvas.inspector.refresh(&canvas_renderer.inspector, &canvas_renderer.canvas_state);
            onEditableGraphMutated();
            _ = gdi.InvalidateRect(hwnd, null, 0);
        },
        windows_constants.ctx_menu_begin_link => {
            beginLinkFromSelection();
            _ = gdi.InvalidateRect(hwnd, null, 0);
        },
        windows_constants.ctx_menu_end_link => {
            const src = canvas.insertion.connector_source_id orelse return;
            canvas.cancelInsertion();
            completeCanvasLink(src);
            windows_canvas.inspector.refresh(&canvas_renderer.inspector, &canvas_renderer.canvas_state);
            onEditableGraphMutated();
            _ = gdi.InvalidateRect(hwnd, null, 0);
        },
        windows_constants.ctx_menu_cancel_link => {
            canvas.cancelInsertion();
            _ = gdi.InvalidateRect(hwnd, null, 0);
            setStatusMessage("Link cancelled");
        },
        windows_constants.ctx_menu_add_subgraph => {
            canvas_renderer.canvas_state.insertion = .{ .kind = .subgraph };
            windows_canvas.interaction.setCursor(ui.IDC_CROSS);
            _ = gdi.InvalidateRect(hwnd, null, 0);
            setStatusMessage("Click on the canvas to place a group");
        },
        else => {},
    }
}

/// Enter link-source mode for the currently selected node or subgraph.
fn beginLinkFromSelection() void {
    const canvas = &canvas_renderer.canvas_state;
    const g = canvas.graph orelse return;
    const src_id: ?[*:0]const u8 = switch (canvas.selection.kind) {
        .node => blk: {
            if (canvas.selection.index >= g.node_count or g.nodes == null) break :blk null;
            const raw: [*c]const u8 = g.nodes[canvas.selection.index].id;
            if (raw == null) break :blk null;
            break :blk @ptrCast(raw);
        },
        .subgraph => blk: {
            if (canvas.selection.index >= g.subgraph_count or g.subgraphs == null) break :blk null;
            const raw: [*c]const u8 = g.subgraphs[canvas.selection.index].id;
            if (raw == null) break :blk null;
            break :blk @ptrCast(raw);
        },
        else => null,
    };
    if (src_id == null) return;
    canvas.insertion = .{ .kind = .connector_source, .connector_source_id = src_id };
    windows_canvas.interaction.setCursor(ui.IDC_CROSS);
    setStatusMessage("Click a target node to complete the link, or right-click to cancel");
}

/// Complete a link from `source_id` to the currently selected object.
fn completeCanvasLink(source_id: [*:0]const u8) void {
    const canvas = &canvas_renderer.canvas_state;
    const g = canvas.graph orelse return;

    const target_id: [*c]const u8 = switch (canvas.selection.kind) {
        .node => blk: {
            if (canvas.selection.index >= g.node_count or g.nodes == null) break :blk null;
            break :blk g.nodes[canvas.selection.index].id;
        },
        .subgraph => blk: {
            if (canvas.selection.index >= g.subgraph_count or g.subgraphs == null) break :blk null;
            break :blk g.subgraphs[canvas.selection.index].id;
        },
        else => null,
    } orelse return;

    // Avoid self-loops.
    if (std.mem.eql(u8, std.mem.span(source_id), std.mem.span(target_id))) return;

    addCanvasEdge(source_id, target_id);
    setStatusMessage("Link created");
}

/// Add a directed edge to the live graph.
fn addCanvasEdge(source_id: [*:0]const u8, target_id: [*c]const u8) void {
    const g = canvas_renderer.canvas_state.graph orelse return;

    const src_copy = std.fmt.allocPrint(c_allocator, "{s}\x00", .{std.mem.span(source_id)}) catch return;
    const dst_copy = std.fmt.allocPrint(c_allocator, "{s}\x00", .{std.mem.span(target_id)}) catch {
        c_allocator.free(src_copy);
        return;
    };

    const new_edge = windows_canvas.StudioEditableEdge{
        .source_id = src_copy.ptr,
        .target_id = dst_copy.ptr,
        .label = null,
        .label_font_size = project_font_settings.edge_label_size,
        .color = .{ .r = 80, .g = 80, .b = 80, .a = 255 },
        .thickness = 2.0,
        .line_style = 0, // solid
        .has_arrow = 1,
        .has_source_arrow = 0,
        .source_end_style = 0,
        .target_end_style = 0,
    };

    const old_count = g.edge_count;
    const new_count = old_count + 1;

    const new_edges = c_allocator.alloc(windows_canvas.StudioEditableEdge, new_count) catch {
        c_allocator.free(src_copy);
        c_allocator.free(dst_copy);
        return;
    };
    if (old_count > 0 and g.edges != null) {
        @memcpy(new_edges[0..old_count], g.edges[0..old_count]);
        c_allocator.free(g.edges[0..old_count]);
    }
    new_edges[old_count] = new_edge;
    g.edges = new_edges.ptr;
    g.edge_count = new_count;

    canvas_renderer.canvas_state.selection = .{ .kind = .edge, .index = old_count };
}

/// Remove the currently selected object (node, subgraph, or edge) from the graph.
fn deleteSelectedObject() void {
    const canvas = &canvas_renderer.canvas_state;
    const g = canvas.graph orelse return;

    switch (canvas.selection.kind) {
        .node => deleteNodeAtIndex(g, canvas.selection.index),
        .subgraph => deleteSubgraphAtIndex(g, canvas.selection.index),
        .edge => deleteEdgeAtIndex(g, canvas.selection.index),
        .none => return,
    }
    canvas.clearSelection();
    canvas.drag = .{};
}

fn deleteNodeAtIndex(g: *windows_canvas.StudioEditableGraph, idx: usize) void {
    if (idx >= g.node_count or g.nodes == null) return;
    const node = g.nodes[idx];
    // Free node strings.
    freeCStringPtr(node.id);
    freeCStringPtr(node.label);
    freeCStringPtr(node.subtitle);
    freeCStringPtr(node.attributes_text);
    freeCStringPtr(node.methods_text);
    freeCStringPtr(node.parent_subgraph_id);

    // Remove edges that reference this node.
    if (node.id != null) {
        const id_s = std.mem.span(node.id);
        deleteEdgesReferencingId(g, id_s);
    }

    // Compact the node array.
    const old_count = g.node_count;
    const new_count = old_count - 1;
    if (new_count == 0) {
        c_allocator.free(g.nodes[0..old_count]);
        g.nodes = null;
        g.node_count = 0;
        return;
    }
    const new_nodes = c_allocator.alloc(windows_canvas.StudioEditableNode, new_count) catch {
        // Can't resize; just zero out the entry and leave a gap.
        g.nodes[idx] = std.mem.zeroes(windows_canvas.StudioEditableNode);
        return;
    };
    if (idx > 0) @memcpy(new_nodes[0..idx], g.nodes[0..idx]);
    if (idx < new_count) @memcpy(new_nodes[idx..new_count], g.nodes[idx + 1 .. old_count]);
    c_allocator.free(g.nodes[0..old_count]);
    g.nodes = new_nodes.ptr;
    g.node_count = new_count;
}

fn deleteSubgraphAtIndex(g: *windows_canvas.StudioEditableGraph, idx: usize) void {
    if (idx >= g.subgraph_count or g.subgraphs == null) return;
    const sg = g.subgraphs[idx];
    if (sg.id != null) {
        const id_s = std.mem.span(sg.id);
        deleteEdgesReferencingId(g, id_s);
    }
    freeCStringPtr(sg.id);
    freeCStringPtr(sg.title);
    freeCStringPtr(sg.parent_subgraph_id);

    const old_count = g.subgraph_count;
    const new_count = old_count - 1;
    if (new_count == 0) {
        c_allocator.free(g.subgraphs[0..old_count]);
        g.subgraphs = null;
        g.subgraph_count = 0;
        return;
    }
    const new_sgs = c_allocator.alloc(windows_canvas.StudioEditableSubgraph, new_count) catch {
        g.subgraphs[idx] = std.mem.zeroes(windows_canvas.StudioEditableSubgraph);
        return;
    };
    if (idx > 0) @memcpy(new_sgs[0..idx], g.subgraphs[0..idx]);
    if (idx < new_count) @memcpy(new_sgs[idx..new_count], g.subgraphs[idx + 1 .. old_count]);
    c_allocator.free(g.subgraphs[0..old_count]);
    g.subgraphs = new_sgs.ptr;
    g.subgraph_count = new_count;
}

fn deleteEdgeAtIndex(g: *windows_canvas.StudioEditableGraph, idx: usize) void {
    if (idx >= g.edge_count or g.edges == null) return;
    const edge = g.edges[idx];
    freeCStringPtr(edge.source_id);
    freeCStringPtr(edge.target_id);
    freeCStringPtr(edge.label);

    const old_count = g.edge_count;
    const new_count = old_count - 1;
    if (new_count == 0) {
        c_allocator.free(g.edges[0..old_count]);
        g.edges = null;
        g.edge_count = 0;
        return;
    }
    const new_edges = c_allocator.alloc(windows_canvas.StudioEditableEdge, new_count) catch {
        g.edges[idx] = std.mem.zeroes(windows_canvas.StudioEditableEdge);
        return;
    };
    if (idx > 0) @memcpy(new_edges[0..idx], g.edges[0..idx]);
    if (idx < new_count) @memcpy(new_edges[idx..new_count], g.edges[idx + 1 .. old_count]);
    c_allocator.free(g.edges[0..old_count]);
    g.edges = new_edges.ptr;
    g.edge_count = new_count;
}

/// Delete all edges whose source_id or target_id matches `id`.
fn deleteEdgesReferencingId(g: *windows_canvas.StudioEditableGraph, id: []const u8) void {
    if (g.edge_count == 0 or g.edges == null) return;

    // Collect surviving edges using a fixed stack buffer.
    var keep_buf: [4096]windows_canvas.StudioEditableEdge = undefined;
    var keep_len: usize = 0;
    for (g.edges[0..g.edge_count]) |edge| {
        const matches_src = edge.source_id != null and std.mem.eql(u8, std.mem.span(edge.source_id), id);
        const matches_dst = edge.target_id != null and std.mem.eql(u8, std.mem.span(edge.target_id), id);
        if (matches_src or matches_dst) {
            freeCStringPtr(edge.source_id);
            freeCStringPtr(edge.target_id);
            freeCStringPtr(edge.label);
        } else {
            if (keep_len < keep_buf.len) {
                keep_buf[keep_len] = edge;
                keep_len += 1;
            }
        }
    }

    c_allocator.free(g.edges[0..g.edge_count]);
    if (keep_len == 0) {
        g.edges = null;
        g.edge_count = 0;
        return;
    }
    const new_edges = c_allocator.alloc(windows_canvas.StudioEditableEdge, keep_len) catch {
        g.edges = null;
        g.edge_count = 0;
        return;
    };
    @memcpy(new_edges, keep_buf[0..keep_len]);
    g.edges = new_edges.ptr;
    g.edge_count = keep_len;
}

fn freeCStringPtr(ptr: [*c]const u8) void {
    if (ptr == null) return;
    const s = std.mem.span(ptr);
    // Free the slice including the null terminator.
    c_allocator.free(ptr[0 .. s.len + 1]);
}

/// Label strings for each node shape (used when generating default node labels).
fn defaultLabelForShape(shape: u32) []const u8 {
    return switch (shape) {
        node_shape_box => "Box",
        node_shape_round => "Step",
        node_shape_diamond => "Decision",
        node_shape_circle => "Circle",
        node_shape_stadium => "Start",
        node_shape_hexagon => "Prepare",
        node_shape_cylinder => "Database",
        else => "Node",
    };
}

/// Node dimensions for each shape.
fn defaultSizeForShape(shape: u32) struct { w: f64, h: f64 } {
    return switch (shape) {
        node_shape_diamond => .{ .w = 100, .h = 80 },
        node_shape_circle => .{ .w = 72, .h = 72 },
        node_shape_cylinder => .{ .w = 100, .h = 80 },
        else => .{ .w = 120, .h = 56 },
    };
}

/// Default fill/stroke colors matching the flowchart default render config.
const default_node_fill = windows_canvas.StudioColor{ .r = 240, .g = 240, .b = 250, .a = 255 };
const default_node_stroke = windows_canvas.StudioColor{ .r = 100, .g = 100, .b = 150, .a = 255 };
const default_node_text = windows_canvas.StudioColor{ .r = 40, .g = 40, .b = 40, .a = 255 };

/// Insert a new node into the live graph in memory at the given canvas position.
/// The node ID is generated automatically and the node is selected after insertion.
fn addCanvasNodeAtPosition(shape: u32, canvas_x: f64, canvas_y: f64) void {
    const g = canvas_renderer.canvas_state.graph orelse return;

    // Generate a unique ID: count existing nodes + subgraphs to avoid collisions.
    const next_num = g.node_count + g.subgraph_count + 1;
    const id_str = std.fmt.allocPrint(c_allocator, "n{d}\x00", .{next_num}) catch return;
    const label_str = std.fmt.allocPrint(c_allocator, "{s}\x00", .{defaultLabelForShape(shape)}) catch {
        c_allocator.free(id_str);
        return;
    };

    const size = defaultSizeForShape(shape);

    const new_node = windows_canvas.StudioEditableNode{
        .id = id_str.ptr,
        .label = label_str.ptr,
        .subtitle = null,
        .attributes_text = null,
        .methods_text = null,
        .parent_subgraph_id = null,
        .shape = shape,
        .x = canvas_x - size.w * 0.5,
        .y = canvas_y - size.h * 0.5,
        .width = size.w,
        .height = size.h,
        .fill = default_node_fill,
        .body_fill = default_node_fill,
        .stroke = default_node_stroke,
        .stroke_width = 2.0,
        .label_color = default_node_text,
        .label_font_size = project_font_settings.node_label_size,
    };

    // Extend the nodes array with a c_allocator realloc-equivalent.
    const old_count = g.node_count;
    const new_count = old_count + 1;

    const new_nodes = c_allocator.alloc(windows_canvas.StudioEditableNode, new_count) catch {
        c_allocator.free(id_str);
        c_allocator.free(label_str);
        return;
    };
    if (old_count > 0 and g.nodes != null) {
        @memcpy(new_nodes[0..old_count], g.nodes[0..old_count]);
        c_allocator.free(g.nodes[0..old_count]);
    }
    new_nodes[old_count] = new_node;
    g.nodes = new_nodes.ptr;
    g.node_count = new_count;

    // Select the new node.
    canvas_renderer.canvas_state.selection = .{ .kind = .node, .index = old_count };
}

/// Insert a new subgraph group into the live graph at the given canvas position.
fn addCanvasSubgraphAtPosition(canvas_x: f64, canvas_y: f64) void {
    const g = canvas_renderer.canvas_state.graph orelse return;

    const next_num = g.node_count + g.subgraph_count + 1;
    const id_str = std.fmt.allocPrint(c_allocator, "sg{d}\x00", .{next_num}) catch return;
    const title_str = std.fmt.allocPrint(c_allocator, "Group\x00", .{}) catch {
        c_allocator.free(id_str);
        return;
    };

    const sg_w: f64 = 200;
    const sg_h: f64 = 160;

    const new_sg = windows_canvas.StudioEditableSubgraph{
        .id = id_str.ptr,
        .title = title_str.ptr,
        .parent_subgraph_id = null,
        .x = canvas_x - sg_w * 0.5,
        .y = canvas_y - sg_h * 0.5,
        .width = sg_w,
        .height = sg_h,
        .corner_radius = 8.0,
        .fill = .{ .r = 230, .g = 240, .b = 255, .a = 160 },
        .stroke = .{ .r = 80, .g = 120, .b = 200, .a = 255 },
        .stroke_width = 1.5,
        .title_x = canvas_x,
        .title_y = canvas_y - sg_h * 0.5 + 16.0,
        .title_font_size = project_font_settings.group_title_size,
        .title_color = .{ .r = 40, .g = 40, .b = 40, .a = 255 },
        .title_position = 0, // top_left
    };

    const old_count = g.subgraph_count;
    const new_count = old_count + 1;

    const new_subgraphs = c_allocator.alloc(windows_canvas.StudioEditableSubgraph, new_count) catch {
        c_allocator.free(id_str);
        c_allocator.free(title_str);
        return;
    };
    if (old_count > 0 and g.subgraphs != null) {
        @memcpy(new_subgraphs[0..old_count], g.subgraphs[0..old_count]);
        c_allocator.free(g.subgraphs[0..old_count]);
    }
    new_subgraphs[old_count] = new_sg;
    g.subgraphs = new_subgraphs.ptr;
    g.subgraph_count = new_count;

    canvas_renderer.canvas_state.selection = .{ .kind = .subgraph, .index = old_count };
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
    if (refresh_inspector) {
        windows_canvas.inspector.refresh(&canvas_renderer.inspector, &canvas_renderer.canvas_state);
    }
}

/// Apply `%% @canvas` and `%% @font` directives from mermaid source to project settings.
/// Directive values override the current settings; fields not present in the source are left unchanged.
fn applyDirectivesFromSource(source: []const u8) void {
    const d = merrow_directives.parse(source);
    if (!d.hasAny()) return;

    if (d.canvas_width_cm) |w| project_font_settings.canvas_width_cm = w;
    if (d.canvas_height_cm) |h| project_font_settings.canvas_height_cm = h;
    if (d.font_family) |f| project_font_settings.font_family = directiveFontToProjectFont(f);
    if (d.node_font_size) |s| project_font_settings.node_label_size = s;
    if (d.group_font_size) |s| project_font_settings.group_title_size = s;
    if (d.edge_font_size) |s| project_font_settings.edge_label_size = s;

    project_font_settings = project_font_settings.sanitized();
}

fn directiveFontToProjectFont(f: merrow_directives.FontFamily) windows_project_settings.FontFamily {
    return switch (f) {
        .lato => .lato,
        .segoe_ui => .segoe_ui,
        .arial => .arial,
        .consolas => .consolas,
    };
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
    return show_source_panel;
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
    const show_source = sourcePanelVisible();

    // Preview window is always hidden in unified mode.
    if (child_windows.preview) |w| _ = ui.ShowWindow(w, ui.SW_HIDE);
    // Canvas is always visible.
    if (child_windows.canvas) |w| _ = ui.ShowWindow(w, ui.SW_SHOWNA);

    if (child_windows.editor) |w| _ = ui.ShowWindow(w, if (show_source) ui.SW_SHOWNA else ui.SW_HIDE);
    if (child_windows.command) |w| _ = ui.ShowWindow(w, if (show_source) ui.SW_SHOWNA else ui.SW_HIDE);
    if (child_windows.apply_button) |w| _ = ui.ShowWindow(w, if (show_source) ui.SW_SHOWNA else ui.SW_HIDE);

    if (child_windows.toolbar) |w| _ = ui.ShowWindow(w, ui.SW_SHOWNA);
    if (child_windows.diagram_label) |w| _ = ui.ShowWindow(w, ui.SW_SHOWNA);
    if (child_windows.diagram_prev_button) |w| _ = ui.ShowWindow(w, ui.SW_SHOWNA);
    if (child_windows.diagram_next_button) |w| _ = ui.ShowWindow(w, ui.SW_SHOWNA);

    windows_canvas.inspector.show(&canvas_renderer.inspector, true);
}

fn toggleSourcePanelVisibility() void {
    show_source_panel = !show_source_panel;
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
    setStatusMessage(if (show_source_panel) "Source panel shown" else "Source panel hidden");
}

fn updateDiagramSelectorControl() void {
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

    if (refresh_view and index != selected_diagram_index) {
        flushPendingGraphSourceWriteback();
        flushPendingFreeformPersist();
    }

    selected_diagram_index = @min(index, document.diagram_count - 1);
    updateDiagramHeaderControls();

    if (!refresh_view) return;
    rebuildFreeformCanvas(true);
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

fn onDiagramSelectionChanged() void {}

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
    onEditableGraphMutated();
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

const PersistedDiagramGraph = struct {
    graph: *windows_canvas.StudioEditableGraph,
    canvas_width_cm: ?f64,
    canvas_height_cm: ?f64,
};

fn applyPersistedCanvasSize(width_cm: ?f64, height_cm: ?f64) void {
    project_font_settings.canvas_width_cm = width_cm orelse windows_project_settings.default_canvas_width_cm;
    project_font_settings.canvas_height_cm = height_cm orelse windows_project_settings.default_canvas_height_cm;
}

fn loadPersistedFreeformGraph() ?PersistedDiagramGraph {
    return null;
}

fn rememberCurrentRecentFile() void {
    var db = &(library_database orelse return);
    const path = current_document_path orelse return;
    db.saveRecentFile(path, selected_diagram_index) catch {};
    refreshRecentFilesMenu();
}

fn scheduleFreeformPersist() void {
    const hwnd = main_window orelse return;
    _ = ui.SetTimer(hwnd, main_timer_id_ffm_persist, ffm_persist_debounce_ms, null);
}

fn scheduleGraphSourceWriteback() void {
    const hwnd = main_window orelse return;
    setSourceWriteLocked(true);
    _ = ui.SetTimer(hwnd, main_timer_id_graph_source_writeback, graph_source_writeback_debounce_ms, null);
}

fn cancelScheduledFreeformPersist() void {
    const hwnd = main_window orelse return;
    _ = ui.KillTimer(hwnd, main_timer_id_ffm_persist);
}

fn cancelScheduledGraphSourceWriteback() void {
    const hwnd = main_window orelse return;
    _ = ui.KillTimer(hwnd, main_timer_id_graph_source_writeback);
}

fn flushPendingFreeformPersist() void {
    cancelScheduledFreeformPersist();
    persistCurrentFreeformGraph();
}

fn flushPendingGraphSourceWriteback() void {
    cancelScheduledGraphSourceWriteback();
    applyGraphSourceWriteback();
}

fn persistCurrentFreeformGraph() void {
    rememberCurrentRecentFile();
}

fn buildGraphWritebackDocumentSource() ![]u8 {
    const active_graph = canvas_renderer.canvas_state.graph orelse return error.NoGraph;

    const fallback_source = duplicateSelectedDiagramSource(c_allocator) catch null;
    defer if (fallback_source) |text| c_allocator.free(text);

    const mermaid_text = try mermaid_export.serializeForMenuExport(c_allocator, active_graph, fallback_source);
    defer c_allocator.free(mermaid_text);

    const diagram_source = try std.fmt.allocPrint(
        c_allocator,
        "%% @canvas width={d:.2}cm height={d:.2}cm\n%% @font family={s} node={d:.1} group={d:.1} edge={d:.1}\n{s}",
        .{
            project_font_settings.canvas_width_cm,
            project_font_settings.canvas_height_cm,
            @tagName(project_font_settings.font_family),
            project_font_settings.node_label_size,
            project_font_settings.group_title_size,
            project_font_settings.edge_label_size,
            mermaid_text,
        },
    );
    defer c_allocator.free(diagram_source);

    return replaceSelectedDiagramSource(diagram_source);
}

fn applyGraphSourceWriteback() void {
    if (!source_write_locked) return;

    const rebuilt_source = buildGraphWritebackDocumentSource() catch {
        setSourceWriteLocked(false);
        setStatusMessage("Failed to update source from graph");
        return;
    };
    defer c_allocator.free(rebuilt_source);

    applyUpdatedSource(rebuilt_source, "Updated source from graph");
    setSourceWriteLocked(false);
}

fn onEditableGraphMutated() void {
    scheduleFreeformPersist();
    scheduleGraphSourceWriteback();
}

fn onFreeformGraphChanged() void {
    onEditableGraphMutated();
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

    if (loadPersistedFreeformGraph()) |saved| {
        applyPersistedCanvasSize(saved.canvas_width_cm, saved.canvas_height_cm);
        canvas_renderer.canvas_state.setGraph(saved.graph);
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
    applyDirectivesFromSource(source);
    canvas_renderer.canvas_state.setGraph(eg);
    updateCanvasPresentation(fit_view);

    const eg_status = std.mem.sliceTo(&eg_message, 0);
    setStatusMessage(if (eg == null and eg_status.len > 0) eg_status else if (eg == null) "Failed to build freeform canvas" else "Freeform canvas mode");
    rememberCurrentRecentFile();
}

fn toggleFontInspector() void {
    const active = !windows_canvas.inspector.fontInspectorActive();
    windows_canvas.inspector.setFontInspectorActive(active);
    windows_canvas.inspector.refresh(&canvas_renderer.inspector, &canvas_renderer.canvas_state);
    setStatusMessage(if (active) "Project inspector" else "Selection inspector");
}

fn openDocumentPath(path: []const u8, preferred_diagram_index: ?usize) void {
    flushPendingGraphSourceWriteback();
    const source = loadSourceFromPath(path) catch {
        setStatusMessage("Failed to open file");
        return;
    };
    defer c_allocator.free(source);

    setEditorText(source);
    loadProjectFontSettingsForPath(path);
    setCurrentDocumentPath(path);
    if (preferred_diagram_index) |idx| {
        selected_diagram_index = idx;
    }
    updateEditorDerivedState(true);
    if (preferred_diagram_index) |idx| {
        selectDiagramIndex(idx, false);
        updateEditorDerivedState(true);
    }
    rebuildFreeformCanvas(true);
    setDocumentDirty(false);
    rememberCurrentRecentFile();
    refreshRecentFilesMenu();
    setStatusMessage("Opened source document");
}

fn openRecentDocument(slot: usize) void {
    var db = &(library_database orelse return);
    const records = db.loadRecentFiles(c_allocator, recent_file_menu_limit) catch {
        setStatusMessage("Failed to load recent files");
        return;
    };
    defer {
        for (records) |*record| record.deinit(c_allocator);
        c_allocator.free(records);
    }

    if (slot >= records.len) return;
    openDocumentPath(records[slot].path, records[slot].diagram_index);
}

fn openDocumentFromDialog() void {
    const selected_path = chooseDocumentPath(false) orelse return;
    defer c_allocator.free(selected_path);

    openDocumentPath(selected_path, null);
}

fn saveDocumentToPath(path: []const u8) bool {
    flushPendingGraphSourceWriteback();
    const source = getEditorText(c_allocator) catch {
        setStatusMessage("Failed to read editor text");
        return false;
    };
    defer c_allocator.free(source);

    saveSourceToPath(path, source) catch {
        setStatusMessage("Failed to save file");
        return false;
    };

    // Push to S3 after a successful local write (best-effort: log but don't fail the save).
    if (storageUsesS3()) {
        uploadLocalFileToS3(path) catch |err| {
            appendS3DebugFmt("post-save upload failed: {s}", .{@errorName(err)});
        };
    }

    if (!saveProjectFontSettingsForPath(path)) return false;

    setCurrentDocumentPath(path);
    _ = refreshCurrentMarkdownDocument(source);
    setDocumentDirty(false);
    rememberCurrentRecentFile();

    if (saveFfmSidecar(path)) {
        setStatusMessage("Saved source and diagram layout");
    } else {
        setStatusMessage("Saved source document");
    }
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

    flushPendingFreeformPersist();

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

    if (header_path) |path| {
        const path_z = dupeSentinel(c_allocator, path) catch {
            setStatusMessage("Failed to prepare header asset path");
            return;
        };
        defer c_allocator.free(path_z);

        const banner = wcg_banner_options{
            .scope = WCG_BANNER_ALL_PAGES,
            .preserve_aspect_ratio = 1,
            .spacing_after = .{ .unit = 0, .value = 0.0 },
        };
        if (api.insert_header_banner(document, path_z.ptr, &banner) != WCG_OK) {
            setWordComStatusMessage(api, library, "Failed to insert header banner");
            return;
        }
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
        .optimize_for = 0,
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

fn exportDiagramToMermaid() void {
    const active_graph = canvas_renderer.canvas_state.graph orelse {
        setStatusMessage("No diagram loaded");
        return;
    };

    const fallback_source = if (mermaid_export.graphHasSourceRecords(active_graph)) null else duplicateSelectedDiagramSource(c_allocator) catch {
        setStatusMessage("Failed to rebuild Mermaid export graph");
        return;
    };
    defer if (fallback_source) |text| c_allocator.free(text);

    const mermaid_text = mermaid_export.serializeForMenuExport(c_allocator, active_graph, fallback_source) catch {
        setStatusMessage("Failed to serialize diagram to Mermaid");
        return;
    };
    defer c_allocator.free(mermaid_text);

    const mermaid_export_text = std.fmt.allocPrint(
        c_allocator,
        "%% @canvas width={d:.2}cm height={d:.2}cm\n%% @font family={s} node={d:.1} group={d:.1} edge={d:.1}\n{s}",
        .{
            project_font_settings.canvas_width_cm,
            project_font_settings.canvas_height_cm,
            @tagName(project_font_settings.font_family),
            project_font_settings.node_label_size,
            project_font_settings.group_title_size,
            project_font_settings.edge_label_size,
            mermaid_text,
        },
    ) catch {
        setStatusMessage("Failed to serialize export directives");
        return;
    };
    defer c_allocator.free(mermaid_export_text);

    const export_path = windows_document.chooseCustomPath(
        c_allocator,
        main_window,
        null,
        null,
        true,
        windows_constants.mermaid_export_filter,
        windows_constants.export_mermaid_dialog_title,
        windows_constants.mermaid_default_extension,
    ) orelse return;
    defer c_allocator.free(export_path);

    const file = std.fs.createFileAbsolute(export_path, .{}) catch {
        setStatusMessage("Failed to create Mermaid export file");
        return;
    };
    defer file.close();

    file.writeAll(mermaid_export_text) catch {
        setStatusMessage("Failed to write Mermaid export file");
        return;
    };

    const status_text = std.fmt.allocPrint(c_allocator, "Exported Mermaid: {s}", .{std.fs.path.basename(export_path)}) catch {
        setStatusMessage("Exported Mermaid file");
        return;
    };
    defer c_allocator.free(status_text);
    setStatusMessage(status_text);
}

fn exportMarkdownDocumentToWord(api: *const WordComGlueApi, library: wcg_library, document_handle: wcg_document, markdown_document: *const document_model.MarkdownDocument) bool {
    var temp_export_paths = std.ArrayList([]u8){};
    defer {
        for (temp_export_paths.items) |temp_path| {
            std.fs.deleteFileAbsolute(temp_path) catch {};
            c_allocator.free(temp_path);
        }
        temp_export_paths.deinit(c_allocator);
    }

    var diagram_index: usize = 0;

    for (markdown_document.blocks) |block| {
        switch (block) {
            .text => |text_block| {
                if (!exportMarkdownTextBlockToWord(api, library, document_handle, text_block.content)) {
                    return false;
                }
            },
            .diagram => |diagram_block| {
                const canvas_size_cm = if (loadPersistedGraphForDiagram(&diagram_block)) |saved| blk: {
                    defer ffm_serializer.freeGraph(saved.graph);
                    break :blk CanvasSizeCm{
                        .width_cm = saved.canvas_width_cm orelse project_font_settings.canvas_width_cm,
                        .height_cm = saved.canvas_height_cm orelse project_font_settings.canvas_height_cm,
                    };
                } else currentProjectCanvasSizeCm();

                const diagram_asset_path = blk: {
                    if (diagram_index == selected_diagram_index) {
                        if (canvas_renderer.canvas_state.graph) |active_graph| {
                            break :blk renderEditableGraphToExportSvg(active_graph, canvas_size_cm) catch renderEditableGraphToExportPng(active_graph, canvas_size_cm) catch renderDiagramBlockToExportPng(&diagram_block, canvas_size_cm) catch |err| {
                                setStatusMessage(@errorName(err));
                                return false;
                            };
                        }
                    }
                    break :blk renderDiagramBlockToExportSvg(&diagram_block, canvas_size_cm) catch renderDiagramBlockToExportPng(&diagram_block, canvas_size_cm) catch |err| {
                        setStatusMessage(@errorName(err));
                        return false;
                    };
                };

                diagram_index += 1;

                temp_export_paths.append(c_allocator, diagram_asset_path) catch {
                    std.fs.deleteFileAbsolute(diagram_asset_path) catch {};
                    c_allocator.free(diagram_asset_path);
                    setStatusMessage("Failed to track temporary diagram export");
                    return false;
                };

                const diagram_asset_z = dupeSentinel(c_allocator, diagram_asset_path) catch {
                    setStatusMessage("Failed to prepare diagram image path");
                    return false;
                };
                defer c_allocator.free(diagram_asset_z);

                const image_options = wcg_image_options{
                    .placement = 0,
                    .alignment = 1,
                    .wrap = 0,
                    .width = .{ .unit = WCG_UNIT_MM, .value = canvas_size_cm.width_cm * 10.0 },
                    .height = .{ .unit = WCG_UNIT_MM, .value = canvas_size_cm.height_cm * 10.0 },
                    .max_width = .{ .unit = 0, .value = 0.0 },
                    .max_height = .{ .unit = 0, .value = 0.0 },
                    .spacing_before = .{ .unit = 0, .value = 0.0 },
                    .spacing_after = .{ .unit = 0, .value = 12.0 },
                    .preserve_aspect_ratio = 0,
                    .utf8_caption = null,
                    .utf8_alt_text = null,
                };
                if (api.insert_image(document_handle, diagram_asset_z.ptr, &image_options) != WCG_OK) {
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

/// Save the current freeform canvas graph as a sidecar .ffm file next to `doc_path`.
/// The file is named `<stem>_<diagram_index>.ffm`.
/// Returns true on success.
fn saveFfmSidecar(doc_path: []const u8) bool {
    const graph = canvas_renderer.canvas_state.graph orelse return false;

    const graph_blob = ffm_serializer.serializeGraph(c_allocator, graph) catch return false;
    defer c_allocator.free(graph_blob);

    const ext = std.fs.path.extension(doc_path);
    const stem = doc_path[0 .. doc_path.len - ext.len];
    const ffm_path = std.fmt.allocPrint(
        c_allocator,
        "{s}_{d}.ffm",
        .{ stem, selected_diagram_index },
    ) catch return false;
    defer c_allocator.free(ffm_path);

    saveBytesToStoragePath(ffm_path, graph_blob) catch return false;
    return true;
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

/// Render an editable graph to a PNG file using Direct2D + WIC (high quality).
fn renderGraphToD2DPng(
    graph: *const windows_canvas.StudioEditableGraph,
    out_w: u32,
    out_h: u32,
    out_dpi: f64,
    out_path: []const u8,
) !void {
    if (!ensureCanvasD2DFactory()) return error.RenderPreviewFailed;
    if (!ensureCanvasDWriteFactory()) return error.RenderPreviewFailed;
    if (!ensurePreviewImagingFactory()) return error.RenderPreviewFailed;
    const d2d_factory = canvas_renderer.factory orelse return error.RenderPreviewFailed;
    const dw_factory = canvas_dwrite_factory orelse return error.RenderPreviewFailed;
    const wic_factory = preview_renderer.wic_factory orelse return error.RenderPreviewFailed;

    // 1. Create off-screen WIC bitmap in D2D's native premultiplied BGRA format.
    var wic_bitmap: ?*imaging.IWICBitmap = null;
    var pf_guid = imaging.GUID_WICPixelFormat32bppPBGRA;
    if (hrFailed(wic_factory.CreateBitmap(out_w, out_h, &pf_guid, imaging.WICBitmapCacheOnLoad, &wic_bitmap)) or wic_bitmap == null)
        return error.RenderPreviewFailed;
    defer _ = wic_bitmap.?.IUnknown.Release();

    // 2. Create a D2D render target backed by the WIC bitmap.
    var render_target: *d2d.ID2D1RenderTarget = undefined;
    const rt_props = d2d.D2D1_RENDER_TARGET_PROPERTIES{
        .type = d2d.D2D1_RENDER_TARGET_TYPE_DEFAULT,
        .pixelFormat = .{
            .format = dxgi_common.DXGI_FORMAT_UNKNOWN,
            .alphaMode = d2d_common.D2D1_ALPHA_MODE_PREMULTIPLIED,
        },
        .dpiX = 96.0,
        .dpiY = 96.0,
        .usage = d2d.D2D1_RENDER_TARGET_USAGE_NONE,
        .minLevel = d2d.D2D1_FEATURE_LEVEL_DEFAULT,
    };
    if (hrFailed(d2d_factory.CreateWicBitmapRenderTarget(wic_bitmap, &rt_props, &render_target)))
        return error.RenderPreviewFailed;
    defer _ = render_target.IUnknown.Release();
    const rt = render_target;

    // 3. Compute a viewport that maps the full graph canvas into the output bitmap.
    const zoom: f64 = if (graph.width > 0) @as(f64, @floatFromInt(out_w)) / graph.width else 1.0;
    const vp = windows_canvas.state.Viewport{ .zoom = zoom };
    const ctx = windows_canvas.draw.DrawContext{
        .d2d_factory = d2d_factory,
        .render_target = rt,
        .dwrite_factory = dw_factory,
        .font_family = project_font_settings.font_family,
        .viewport_width = @floatFromInt(out_w),
        .viewport_height = @floatFromInt(out_h),
    };

    // 4. Draw the graph into the off-screen bitmap.
    rt.BeginDraw();
    windows_canvas.draw.drawCanvas(&ctx, graph, vp, .{}, .{}, .{}, 0.0, 0.0, false);
    if (hrFailed(rt.EndDraw(null, null))) return error.RenderPreviewFailed;

    // 5. Encode the WIC bitmap to a PNG file via WIC.
    const path_w = try std.unicode.utf8ToUtf16LeAllocZ(c_allocator, out_path);
    defer c_allocator.free(path_w);

    var wic_stream: ?*imaging.IWICStream = null;
    if (hrFailed(wic_factory.CreateStream(&wic_stream)) or wic_stream == null)
        return error.RenderPreviewFailed;
    defer _ = wic_stream.?.IUnknown.Release();
    const GENERIC_WRITE: u32 = 0x40000000;
    if (hrFailed(wic_stream.?.InitializeFromFilename(path_w.ptr, GENERIC_WRITE)))
        return error.RenderPreviewFailed;

    var encoder: ?*imaging.IWICBitmapEncoder = null;
    if (hrFailed(wic_factory.CreateEncoder(&imaging.GUID_ContainerFormatPng, null, &encoder)) or encoder == null)
        return error.RenderPreviewFailed;
    defer _ = encoder.?.IUnknown.Release();
    if (hrFailed(encoder.?.Initialize(&wic_stream.?.IStream, imaging.WICBitmapEncoderNoCache)))
        return error.RenderPreviewFailed;

    var frame: ?*imaging.IWICBitmapFrameEncode = null;
    if (hrFailed(encoder.?.CreateNewFrame(&frame, null)) or frame == null)
        return error.RenderPreviewFailed;
    defer _ = frame.?.IUnknown.Release();

    if (hrFailed(frame.?.Initialize(null))) return error.RenderPreviewFailed;
    if (hrFailed(frame.?.SetSize(out_w, out_h))) return error.RenderPreviewFailed;
    if (hrFailed(frame.?.SetResolution(out_dpi, out_dpi))) return error.RenderPreviewFailed;
    var frame_pf = pf_guid;
    if (hrFailed(frame.?.SetPixelFormat(&frame_pf))) return error.RenderPreviewFailed;
    if (hrFailed(frame.?.WriteSource(&wic_bitmap.?.IWICBitmapSource, null))) return error.RenderPreviewFailed;
    if (hrFailed(frame.?.Commit())) return error.RenderPreviewFailed;
    if (hrFailed(encoder.?.Commit())) return error.RenderPreviewFailed;
}

fn renderEditableGraphToTempPng(graph: *const windows_canvas.StudioEditableGraph) ![]u8 {
    const w: u32 = @max(1, @as(u32, @intFromFloat(graph.width)));
    const h: u32 = @max(1, @as(u32, @intFromFloat(graph.height)));
    const temp_path = try createTempExportPath(".png");
    errdefer c_allocator.free(temp_path);
    try renderGraphToD2DPng(graph, w, h, 96.0, temp_path);
    return temp_path;
}

fn sourceHasEditableElementAnnotations(source: []const u8) bool {
    var line_iter = std.mem.splitScalar(u8, source, '\n');
    while (line_iter.next()) |raw_line| {
        const trimmed = std.mem.trim(u8, std.mem.trimRight(u8, raw_line, "\r"), " \t");
        if (!std.mem.startsWith(u8, trimmed, "%%")) continue;
        const ann = std.mem.trimLeft(u8, trimmed[2..], " \t");
        if (std.mem.startsWith(u8, ann, "@shape=") or
            std.mem.startsWith(u8, ann, "@edge") or
            std.mem.startsWith(u8, ann, "@pos="))
        {
            return true;
        }
    }
    return false;
}

fn buildEditableGraphFromAnnotatedSource(source: []const u8) ?*windows_canvas.StudioEditableGraph {
    if (!sourceHasEditableElementAnnotations(source)) return null;

    var eg_message: [256]u8 = std.mem.zeroes([256]u8);
    const graph = merrow_studio_build_editable_graph(
        source.ptr,
        @intCast(source.len),
        &eg_message,
        eg_message.len,
    );
    return graph;
}

fn loadPersistedGraphForDiagram(diagram: *const document_model.DiagramBlock) ?PersistedDiagramGraph {
    _ = diagram;
    return null;
}

fn renderDiagramBlockToTempPng(diagram: *const document_model.DiagramBlock) ![]u8 {
    if (loadPersistedGraphForDiagram(diagram)) |saved| {
        defer ffm_serializer.freeGraph(saved.graph);
        if (saved.graph.graph_type == export_editable_graph_type_flowchart or
            saved.graph.graph_type == export_editable_graph_type_sequence)
        {
            return renderEditableGraphToTempPng(saved.graph) catch renderDiagramToTempPng(diagram.mermaid_source);
        }
    }
    return renderDiagramToTempPng(diagram.mermaid_source);
}

fn renderDiagramToExportPng(source: []const u8, size_cm: CanvasSizeCm) ![]u8 {
    var preview_message: [256]u8 = std.mem.zeroes([256]u8);
    var preview_png_len: u32 = 0;
    const export_dims = exportDimensionsForSizeCm(size_cm);
    const preview_png_ptr = merrow_studio_render_preview_png_bytes(
        source.ptr,
        @intCast(source.len),
        export_dims.width,
        export_dims.height,
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

fn renderEditableGraphToExportPng(graph: *const windows_canvas.StudioEditableGraph, size_cm: CanvasSizeCm) ![]u8 {
    const export_dims = exportDimensionsForSizeCm(size_cm);
    const temp_path = try createTempExportPath(".png");
    errdefer c_allocator.free(temp_path);
    try renderGraphToD2DPng(graph, export_dims.width, export_dims.height, windows_project_settings.export_raster_dpi, temp_path);
    return temp_path;
}

fn renderEditableGraphToExportSvg(graph: *const windows_canvas.StudioEditableGraph, size_cm: CanvasSizeCm) ![]u8 {
    var message: [256]u8 = std.mem.zeroes([256]u8);
    const export_dims = exportDimensionsForSizeCm(size_cm);
    const temp_path = try createTempExportPath(".svg");
    errdefer c_allocator.free(temp_path);
    const temp_path_z = try dupeSentinel(c_allocator, temp_path);
    defer c_allocator.free(temp_path_z);

    const result = merrow_studio_render_editable_graph_svg(
        graph,
        temp_path_z.ptr,
        export_dims.width,
        export_dims.height,
        &message,
        message.len,
    );
    if (result != 0) {
        const status = std.mem.sliceTo(&message, 0);
        if (status.len > 0) setStatusMessage(status);
        return error.RenderPreviewFailed;
    }
    return temp_path;
}

fn renderDiagramBlockToExportPng(diagram: *const document_model.DiagramBlock, size_cm: CanvasSizeCm) ![]u8 {
    if (loadPersistedGraphForDiagram(diagram)) |saved| {
        defer ffm_serializer.freeGraph(saved.graph);
        if (saved.graph.graph_type == export_editable_graph_type_flowchart or
            saved.graph.graph_type == export_editable_graph_type_sequence)
        {
            return renderEditableGraphToExportPng(saved.graph, size_cm) catch renderDiagramToExportPng(diagram.mermaid_source, size_cm);
        }
    }

    if (buildEditableGraphFromAnnotatedSource(diagram.mermaid_source)) |graph| {
        defer merrow_studio_free_editable_graph(graph);
        return renderEditableGraphToExportPng(graph, size_cm) catch renderDiagramToExportPng(diagram.mermaid_source, size_cm);
    }

    return renderDiagramToExportPng(diagram.mermaid_source, size_cm);
}

fn renderDiagramBlockToExportSvg(diagram: *const document_model.DiagramBlock, size_cm: CanvasSizeCm) ![]u8 {
    if (loadPersistedGraphForDiagram(diagram)) |saved| {
        defer ffm_serializer.freeGraph(saved.graph);
        if (saved.graph.graph_type == export_editable_graph_type_flowchart or
            saved.graph.graph_type == export_editable_graph_type_sequence)
        {
            return renderEditableGraphToExportSvg(saved.graph, size_cm);
        }
    }

    if (buildEditableGraphFromAnnotatedSource(diagram.mermaid_source)) |graph| {
        defer merrow_studio_free_editable_graph(graph);
        return renderEditableGraphToExportSvg(graph, size_cm);
    }

    return error.RenderPreviewFailed;
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
    preview_renderer.zoom = previewFitZoom(hwnd) orelse return;

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

fn previewFitZoom(hwnd: ?foundation.HWND) ?f64 {
    const viewport = currentPreviewPixelSize(hwnd) orelse return null;
    const page_width = previewPageWidth();
    const page_height = previewPageHeight();
    if (page_width <= 0 or page_height <= 0) return null;

    const zoom_x = @as(f64, @floatFromInt(viewport.width)) / @as(f64, @floatFromInt(page_width));
    const zoom_y = @as(f64, @floatFromInt(viewport.height)) / @as(f64, @floatFromInt(page_height));
    return std.math.clamp(@min(zoom_x, zoom_y), preview_min_zoom, preview_max_zoom);
}

fn setPreviewZoom(new_zoom: f64, anchor_x: i32, anchor_y: i32) void {
    const clamped_zoom = std.math.clamp(new_zoom, preview_min_zoom, preview_max_zoom);
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

fn setPreviewZoomAbsolute(hwnd: ?foundation.HWND, level: f64) void {
    const fit_zoom = previewFitZoom(hwnd) orelse 1.0;
    preview_renderer.zoom = std.math.clamp(fit_zoom * level, preview_min_zoom, preview_max_zoom);
    // Align content top-left.
    preview_renderer.scroll_x = 0;
    preview_renderer.scroll_y = 0;
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
        // HIGH_QUALITY_CUBIC ��� a proper downsampling filter that avoids
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

fn applyControlFont(hwnd: ?foundation.HWND) void {
    const font = ensureShellFont() orelse return;
    _ = ui.SendMessageA(hwnd, ui.WM_SETFONT, @intFromPtr(font), 1);
}

fn createAboutFont(height: i32, weight: i32) ?gdi.HFONT {
    var logfont = std.mem.zeroes(gdi.LOGFONTA);
    logfont.lfHeight = -height;
    logfont.lfWeight = @enumFromInt(@as(u32, @intCast(weight)));
    const face_name = "Lato";
    for (face_name, 0..) |char, idx| {
        logfont.lfFaceName[idx] = @as(@TypeOf(logfont.lfFaceName[0]), @intCast(char));
    }
    return gdi.CreateFontIndirectA(&logfont);
}

fn ensureAboutFonts() void {
    if (about_title_font == null) {
        about_title_font = createAboutFont(24, 700);
    }
    if (about_body_font == null) {
        about_body_font = createAboutFont(16, 500);
    }
}

fn releaseAboutFonts() void {
    if (about_title_font) |font| {
        _ = gdi.DeleteObject(font);
        about_title_font = null;
    }
    if (about_body_font) |font| {
        _ = gdi.DeleteObject(font);
        about_body_font = null;
    }
}

fn applyAboutFonts() void {
    ensureAboutFonts();
    if (about_controls.title) |control| {
        _ = ui.SendMessageA(control, ui.WM_SETFONT, @intFromPtr(about_title_font orelse ensureShellFont() orelse return), 1);
    }
    if (about_controls.version) |control| {
        _ = ui.SendMessageA(control, ui.WM_SETFONT, @intFromPtr(about_body_font orelse ensureShellFont() orelse return), 1);
    }
    if (about_controls.license) |control| {
        _ = ui.SendMessageA(control, ui.WM_SETFONT, @intFromPtr(about_body_font orelse ensureShellFont() orelse return), 1);
    }
    if (about_controls.ok_button) |control| {
        applyControlFont(control);
    }
}

fn applyCloudStorageFonts() void {
    if (cloud_storage_controls.region_label) |control| applyControlFont(control);
    if (cloud_storage_controls.region_edit) |control| applyControlFont(control);
    if (cloud_storage_controls.bucket_label) |control| applyControlFont(control);
    if (cloud_storage_controls.bucket_edit) |control| applyControlFont(control);
    if (cloud_storage_controls.api_label) |control| applyControlFont(control);
    if (cloud_storage_controls.api_edit) |control| applyControlFont(control);
    if (cloud_storage_controls.key_label) |control| applyControlFont(control);
    if (cloud_storage_controls.key_edit) |control| applyControlFont(control);
    if (cloud_storage_controls.ok_button) |control| applyControlFont(control);
}

fn layoutCloudStorageWindow(hwnd: ?foundation.HWND) void {
    var rect = std.mem.zeroes(foundation.RECT);
    if (ui.GetClientRect(hwnd, &rect) == 0) return;

    const padding: i32 = 16;
    const label_height: i32 = 18;
    const edit_height: i32 = 26;
    const field_gap: i32 = 6;
    const row_gap: i32 = 16;
    const button_width: i32 = 96;
    const button_height: i32 = 28;
    const client_width = rect.right - rect.left;
    const client_height = rect.bottom - rect.top;
    const field_width = @max(120, client_width - padding * 2);

    var y = padding;
    if (cloud_storage_controls.region_label) |control| {
        _ = ui.MoveWindow(control, padding, y, field_width, label_height, 1);
    }
    y += label_height + field_gap;
    if (cloud_storage_controls.region_edit) |control| {
        _ = ui.MoveWindow(control, padding, y, field_width, edit_height, 1);
    }
    y += edit_height + row_gap;
    if (cloud_storage_controls.bucket_label) |control| {
        _ = ui.MoveWindow(control, padding, y, field_width, label_height, 1);
    }
    y += label_height + field_gap;
    if (cloud_storage_controls.bucket_edit) |control| {
        _ = ui.MoveWindow(control, padding, y, field_width, edit_height, 1);
    }
    y += edit_height + row_gap;
    if (cloud_storage_controls.api_label) |control| {
        _ = ui.MoveWindow(control, padding, y, field_width, label_height, 1);
    }
    y += label_height + field_gap;
    if (cloud_storage_controls.api_edit) |control| {
        _ = ui.MoveWindow(control, padding, y, field_width, edit_height, 1);
    }
    y += edit_height + row_gap;
    if (cloud_storage_controls.key_label) |control| {
        _ = ui.MoveWindow(control, padding, y, field_width, label_height, 1);
    }
    y += label_height + field_gap;
    if (cloud_storage_controls.key_edit) |control| {
        _ = ui.MoveWindow(control, padding, y, field_width, edit_height, 1);
    }

    if (cloud_storage_controls.ok_button) |control| {
        _ = ui.MoveWindow(control, client_width - padding - button_width, client_height - padding - button_height, button_width, button_height, 1);
    }
}

fn getWindowTextAlloc(hwnd: ?foundation.HWND) ?[]u8 {
    const text_len_i32 = ui.GetWindowTextLengthA(hwnd);
    if (text_len_i32 < 0) return null;
    const text_len: usize = @intCast(text_len_i32);
    const buffer = c_allocator.allocSentinel(u8, text_len, 0) catch return null;
    errdefer c_allocator.free(buffer);

    const copied = ui.GetWindowTextA(hwnd, buffer.ptr, @intCast(text_len + 1));
    if (copied < 0) return null;
    return buffer[0..@intCast(copied)];
}

fn loadCloudStorageCredentialsIntoDialog() void {
    const region_edit = cloud_storage_controls.region_edit orelse return;
    const bucket_edit = cloud_storage_controls.bucket_edit orelse return;
    const api_edit = cloud_storage_controls.api_edit orelse return;
    const key_edit = cloud_storage_controls.key_edit orelse return;

    const region = windows_credentials.loadString(c_allocator, cloud_storage_credential_target_region) catch null;
    defer if (region) |value| windows_credentials.wipeAndFree(c_allocator, value);
    if (region) |value| setWindowText(region_edit, value);

    const bucket = windows_credentials.loadString(c_allocator, cloud_storage_credential_target_bucket) catch null;
    defer if (bucket) |value| windows_credentials.wipeAndFree(c_allocator, value);
    if (bucket) |value| setWindowText(bucket_edit, value);

    const api_id = windows_credentials.loadString(c_allocator, cloud_storage_credential_target_id) catch null;
    defer if (api_id) |value| windows_credentials.wipeAndFree(c_allocator, value);
    if (api_id) |value| setWindowText(api_edit, value);

    const secret_key = windows_credentials.loadString(c_allocator, cloud_storage_credential_target_key) catch null;
    defer if (secret_key) |value| windows_credentials.wipeAndFree(c_allocator, value);
    if (secret_key) |value| setWindowText(key_edit, value);
}

fn saveCloudStorageCredentialsFromDialog() bool {
    const region_edit = cloud_storage_controls.region_edit orelse return false;
    const bucket_edit = cloud_storage_controls.bucket_edit orelse return false;
    const api_edit = cloud_storage_controls.api_edit orelse return false;
    const key_edit = cloud_storage_controls.key_edit orelse return false;

    const region = getWindowTextAlloc(region_edit) orelse {
        setStatusMessage("Failed to read region field");
        return false;
    };
    defer windows_credentials.wipeAndFree(c_allocator, region);

    const bucket = getWindowTextAlloc(bucket_edit) orelse {
        setStatusMessage("Failed to read bucket field");
        return false;
    };
    defer windows_credentials.wipeAndFree(c_allocator, bucket);

    const api_id = getWindowTextAlloc(api_edit) orelse {
        setStatusMessage("Failed to read API ID field");
        return false;
    };
    defer windows_credentials.wipeAndFree(c_allocator, api_id);

    const secret_key = getWindowTextAlloc(key_edit) orelse {
        setStatusMessage("Failed to read secret key field");
        return false;
    };
    defer windows_credentials.wipeAndFree(c_allocator, secret_key);

    windows_credentials.storeString(c_allocator, cloud_storage_credential_target_region, region) catch {
        setStatusMessage("Failed to save region to Credential Manager");
        return false;
    };
    windows_credentials.storeString(c_allocator, cloud_storage_credential_target_bucket, bucket) catch {
        setStatusMessage("Failed to save bucket to Credential Manager");
        return false;
    };
    windows_credentials.storeString(c_allocator, cloud_storage_credential_target_id, api_id) catch {
        setStatusMessage("Failed to save API ID to Credential Manager");
        return false;
    };
    windows_credentials.storeString(c_allocator, cloud_storage_credential_target_key, secret_key) catch {
        setStatusMessage("Failed to save secret key to Credential Manager");
        return false;
    };

    if (refreshCloudStorageState(true)) {
        setStatusMessage("Connected to S3");
    } else {
        setStatusMessage("Cloud storage settings saved");
    }
    return true;
}

fn currentAboutImagePixelSize(hwnd: ?foundation.HWND) ?d2d_common.D2D_SIZE_U {
    var rect = std.mem.zeroes(foundation.RECT);
    if (ui.GetClientRect(hwnd, &rect) == 0) return null;
    const width = rect.right - rect.left;
    const height = rect.bottom - rect.top;
    if (width <= 0 or height <= 0) return null;
    return .{ .width = @intCast(width), .height = @intCast(height) };
}

fn ensureAboutImageRenderTarget(hwnd: ?foundation.HWND) bool {
    if (!ensurePreviewFactory()) return false;

    const pixel_size = currentAboutImagePixelSize(hwnd) orelse return false;
    const factory = preview_renderer.factory orelse return false;

    if (about_image_renderer.render_target) |render_target| {
        if (hrFailed(render_target.Resize(&pixel_size))) {
            releaseAboutImageResources();
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

    about_image_renderer.render_target = render_target;
    return true;
}

fn ensureAboutImageBitmap(hwnd: ?foundation.HWND) bool {
    if (!ensureAboutImageRenderTarget(hwnd)) return false;
    if (about_image_renderer.bitmap != null) return true;
    const render_target = about_image_renderer.render_target orelse return false;
    return createBitmapFromPngBytes(
        render_target,
        about_image_png,
        &about_image_renderer.bitmap,
        &about_image_renderer.bitmap_width,
        &about_image_renderer.bitmap_height,
    );
}

fn drawAboutImage(hwnd: ?foundation.HWND) void {
    if (!ensureAboutImageRenderTarget(hwnd)) return;
    _ = ensureAboutImageBitmap(hwnd);

    const render_target = about_image_renderer.render_target orelse return;
    render_target.ID2D1RenderTarget.BeginDraw();
    var background = rgba8Color(248, 247, 242, 255);
    render_target.ID2D1RenderTarget.Clear(&background);

    if (about_image_renderer.bitmap) |bitmap| {
        const pixel_size = currentAboutImagePixelSize(hwnd) orelse {
            _ = render_target.ID2D1RenderTarget.EndDraw(null, null);
            return;
        };
        const viewport_width = @as(f32, @floatFromInt(pixel_size.width));
        const viewport_height = @as(f32, @floatFromInt(pixel_size.height));
        const image_width = @as(f32, @floatFromInt(about_image_renderer.bitmap_width));
        const image_height = @as(f32, @floatFromInt(about_image_renderer.bitmap_height));
        if (image_width > 0 and image_height > 0) {
            const max_width = viewport_width - 24.0;
            const max_height = viewport_height - 24.0;
            const scale = @min(max_width / image_width, max_height / image_height);
            const drawn_width = image_width * scale;
            const drawn_height = image_height * scale;
            const dest_rect = d2d_common.D2D_RECT_F{
                .left = (viewport_width - drawn_width) / 2.0,
                .top = (viewport_height - drawn_height) / 2.0,
                .right = (viewport_width + drawn_width) / 2.0,
                .bottom = (viewport_height + drawn_height) / 2.0,
            };
            const src_rect = d2d_common.D2D_RECT_F{
                .left = 0,
                .top = 0,
                .right = image_width,
                .bottom = image_height,
            };
            render_target.ID2D1RenderTarget.DrawBitmap(
                bitmap,
                &dest_rect,
                1.0,
                d2d.D2D1_BITMAP_INTERPOLATION_MODE_LINEAR,
                &src_rect,
            );
        }
    }

    _ = render_target.ID2D1RenderTarget.EndDraw(null, null);
}

fn layoutAboutWindow(hwnd: ?foundation.HWND) void {
    var rect = std.mem.zeroes(foundation.RECT);
    if (ui.GetClientRect(hwnd, &rect) == 0) return;

    const width = rect.right - rect.left;
    const height = rect.bottom - rect.top;
    const padding: i32 = 16;
    const image_height: i32 = 176;
    const text_top = padding + image_height + 12;
    const content_width = width - padding * 2;

    if (about_controls.image) |control| {
        _ = ui.SetWindowPos(control, null, padding, padding, content_width, image_height, ui.SWP_NOZORDER);
    }
    if (about_controls.title) |control| {
        _ = ui.SetWindowPos(control, null, padding, text_top, content_width, 30, ui.SWP_NOZORDER);
    }
    if (about_controls.version) |control| {
        _ = ui.SetWindowPos(control, null, padding, text_top + 36, content_width, 24, ui.SWP_NOZORDER);
    }
    if (about_controls.license) |control| {
        _ = ui.SetWindowPos(control, null, padding, text_top + 66, content_width, 40, ui.SWP_NOZORDER);
    }
    if (about_controls.ok_button) |control| {
        const button_width = 96;
        const button_height = 28;
        _ = ui.SetWindowPos(control, null, @divTrunc(width - button_width, 2), height - padding - button_height, button_width, button_height, ui.SWP_NOZORDER);
    }
}

fn createAboutWindowText(text: []const u8) ?[:0]u8 {
    return dupeSentinel(c_allocator, text) catch null;
}

fn showAboutWindow() void {
    if (about_window) |existing| {
        _ = ui.ShowWindow(existing, ui.SW_SHOW);
        _ = ui.SetForegroundWindow(existing);
        return;
    }

    const owner = main_window;
    var owner_rect = foundation.RECT{ .left = 120, .top = 120, .right = 600, .bottom = 640 };
    if (owner != null) {
        _ = ui.GetWindowRect(owner, &owner_rect);
    }

    const width = 420;
    const height = 360;
    const x = owner_rect.left + @divTrunc((owner_rect.right - owner_rect.left - width), 2);
    const y = owner_rect.top + @divTrunc((owner_rect.bottom - owner_rect.top - height), 2);

    const hwnd = ui.CreateWindowExA(
        makeExStyle(exStyleBits(ui.WS_EX_DLGMODALFRAME)),
        about_class_name,
        about_window_title,
        makeStyle(styleBits(ui.WS_OVERLAPPED) | styleBits(ui.WS_CAPTION) | styleBits(ui.WS_SYSMENU) | styleBits(ui.WS_CLIPCHILDREN)),
        x,
        y,
        width,
        height,
        owner,
        null,
        loader.GetModuleHandleA(null),
        null,
    ) orelse return;

    about_window = hwnd;
    _ = ui.ShowWindow(hwnd, ui.SW_SHOW);
    _ = ui.SetForegroundWindow(hwnd);
}

fn showCloudStorageWindow() void {
    if (cloud_storage_window) |existing| {
        _ = ui.ShowWindow(existing, ui.SW_SHOW);
        _ = ui.SetForegroundWindow(existing);
        return;
    }

    const owner = main_window;
    var owner_rect = foundation.RECT{ .left = 120, .top = 120, .right = 600, .bottom = 500 };
    if (owner != null) {
        _ = ui.GetWindowRect(owner, &owner_rect);
    }

    const width = 560;
    const height = 360;
    const x = owner_rect.left + @divTrunc((owner_rect.right - owner_rect.left - width), 2);
    const y = owner_rect.top + @divTrunc((owner_rect.bottom - owner_rect.top - height), 2);

    const hwnd = ui.CreateWindowExA(
        makeExStyle(exStyleBits(ui.WS_EX_DLGMODALFRAME)),
        cloud_storage_class_name,
        cloud_storage_window_title,
        makeStyle(styleBits(ui.WS_OVERLAPPED) | styleBits(ui.WS_CAPTION) | styleBits(ui.WS_SYSMENU) | styleBits(ui.WS_CLIPCHILDREN)),
        x,
        y,
        width,
        height,
        owner,
        null,
        loader.GetModuleHandleA(null),
        null,
    ) orelse return;

    cloud_storage_window = hwnd;
    if (owner) |owner_hwnd| _ = EnableWindow(owner_hwnd, 0);
    _ = ui.ShowWindow(hwnd, ui.SW_SHOW);
    _ = ui.SetForegroundWindow(hwnd);
}

fn aboutImageWindowProc(
    hwnd: ?foundation.HWND,
    message: u32,
    w_param: foundation.WPARAM,
    l_param: foundation.LPARAM,
) callconv(.winapi) foundation.LRESULT {
    switch (message) {
        ui.WM_ERASEBKGND => return 1,
        ui.WM_SIZE => {
            if (about_image_renderer.render_target) |render_target| {
                if (currentAboutImagePixelSize(hwnd)) |size| {
                    _ = render_target.Resize(&size);
                }
            }
            _ = gdi.InvalidateRect(hwnd, null, 0);
            return 0;
        },
        ui.WM_PAINT => {
            var paint = std.mem.zeroes(gdi.PAINTSTRUCT);
            _ = gdi.BeginPaint(hwnd, &paint);
            drawAboutImage(hwnd);
            _ = gdi.EndPaint(hwnd, &paint);
            return 0;
        },
        else => return ui.DefWindowProcA(hwnd, message, w_param, l_param),
    }
}

fn aboutWindowProc(
    hwnd: ?foundation.HWND,
    message: u32,
    w_param: foundation.WPARAM,
    l_param: foundation.LPARAM,
) callconv(.winapi) foundation.LRESULT {
    switch (message) {
        ui.WM_CREATE => {
            const title_text = createAboutWindowText("Merrow Studio") orelse return -1;
            defer c_allocator.free(title_text);
            const version_plain = std.fmt.allocPrint(c_allocator, "Version {s}", .{app_version}) catch return -1;
            defer c_allocator.free(version_plain);
            const version_text = createAboutWindowText(version_plain) orelse return -1;
            defer c_allocator.free(version_text);
            const license_text = createAboutWindowText("(c) Alban Read 2026\r\nMIT Licensed") orelse return -1;
            defer c_allocator.free(license_text);

            about_controls = .{};
            about_controls.image = ui.CreateWindowExA(.{}, about_image_class_name, "", makeStyle(styleBits(ui.WS_CHILD) | styleBits(ui.WS_VISIBLE)), 0, 0, 100, 100, hwnd, @ptrFromInt(control_id_about_image), loader.GetModuleHandleA(null), null);
            about_controls.title = ui.CreateWindowExA(.{}, static_class, title_text.ptr, makeStyle(styleBits(ui.WS_CHILD) | styleBits(ui.WS_VISIBLE)), 0, 0, 100, 20, hwnd, @ptrFromInt(control_id_about_title), loader.GetModuleHandleA(null), null);
            about_controls.version = ui.CreateWindowExA(.{}, static_class, version_text.ptr, makeStyle(styleBits(ui.WS_CHILD) | styleBits(ui.WS_VISIBLE)), 0, 0, 100, 20, hwnd, @ptrFromInt(control_id_about_version), loader.GetModuleHandleA(null), null);
            about_controls.license = ui.CreateWindowExA(.{}, static_class, license_text.ptr, makeStyle(styleBits(ui.WS_CHILD) | styleBits(ui.WS_VISIBLE)), 0, 0, 100, 40, hwnd, @ptrFromInt(control_id_about_license), loader.GetModuleHandleA(null), null);
            about_controls.ok_button = ui.CreateWindowExA(.{}, button_class, "OK", makeStyle(styleBits(ui.WS_CHILD) | styleBits(ui.WS_VISIBLE)), 0, 0, 96, 28, hwnd, @ptrFromInt(control_id_about_ok), loader.GetModuleHandleA(null), null);

            if (about_controls.image == null or about_controls.title == null or about_controls.version == null or about_controls.license == null or about_controls.ok_button == null) {
                return -1;
            }

            applyAboutFonts();
            layoutAboutWindow(hwnd);
            _ = ui.SetTimer(hwnd, about_auto_close_timer_id, 6000, null);
            return 0;
        },
        ui.WM_COMMAND => {
            const command_id: u16 = @truncate(w_param & 0xffff);
            if (command_id == control_id_about_ok) {
                _ = ui.DestroyWindow(hwnd);
                return 0;
            }
            return ui.DefWindowProcA(hwnd, message, w_param, l_param);
        },
        ui.WM_SIZE => {
            layoutAboutWindow(hwnd);
            return 0;
        },
        ui.WM_TIMER => {
            if (@as(usize, @bitCast(w_param)) == about_auto_close_timer_id) {
                _ = ui.DestroyWindow(hwnd);
                return 0;
            }
            return ui.DefWindowProcA(hwnd, message, w_param, l_param);
        },
        ui.WM_KEYDOWN => {
            const vkey: u16 = @truncate(w_param);
            if (vkey == @intFromEnum(mouse.VK_ESCAPE) or vkey == @intFromEnum(mouse.VK_RETURN)) {
                _ = ui.DestroyWindow(hwnd);
                return 0;
            }
            return ui.DefWindowProcA(hwnd, message, w_param, l_param);
        },
        ui.WM_CLOSE => {
            _ = ui.DestroyWindow(hwnd);
            return 0;
        },
        ui.WM_DESTROY => {
            _ = ui.KillTimer(hwnd, about_auto_close_timer_id);
            releaseAboutImageResources();
            releaseAboutFonts();
            about_controls = .{};
            about_window = null;
            return 0;
        },
        else => return ui.DefWindowProcA(hwnd, message, w_param, l_param),
    }
}

fn cloudStorageWindowProc(
    hwnd: ?foundation.HWND,
    message: u32,
    w_param: foundation.WPARAM,
    l_param: foundation.LPARAM,
) callconv(.winapi) foundation.LRESULT {
    switch (message) {
        ui.WM_CREATE => {
            cloud_storage_controls = .{};
            const child_style_bits = styleBits(ui.WS_CHILD) | styleBits(ui.WS_VISIBLE);
            const plain_edit_style_bits = child_style_bits |
                styleBits(ui.WS_TABSTOP) |
                @as(u32, @bitCast(ui.ES_AUTOHSCROLL));
            const secret_edit_style_bits = child_style_bits |
                styleBits(ui.WS_TABSTOP) |
                @as(u32, @bitCast(ui.ES_AUTOHSCROLL)) |
                @as(u32, @bitCast(ui.ES_PASSWORD));

            cloud_storage_controls.region_label = ui.CreateWindowExA(.{}, static_class, cloud_storage_region_label_text, makeStyle(child_style_bits), 0, 0, 100, 18, hwnd, @ptrFromInt(control_id_cloud_storage_region_label), loader.GetModuleHandleA(null), null);
            cloud_storage_controls.region_edit = ui.CreateWindowExA(makeExStyle(exStyleBits(ui.WS_EX_CLIENTEDGE)), edit_class, "", makeStyle(plain_edit_style_bits), 0, 0, 100, 24, hwnd, @ptrFromInt(control_id_cloud_storage_region_edit), loader.GetModuleHandleA(null), null);
            cloud_storage_controls.bucket_label = ui.CreateWindowExA(.{}, static_class, cloud_storage_bucket_label_text, makeStyle(child_style_bits), 0, 0, 100, 18, hwnd, @ptrFromInt(control_id_cloud_storage_bucket_label), loader.GetModuleHandleA(null), null);
            cloud_storage_controls.bucket_edit = ui.CreateWindowExA(makeExStyle(exStyleBits(ui.WS_EX_CLIENTEDGE)), edit_class, "", makeStyle(plain_edit_style_bits), 0, 0, 100, 24, hwnd, @ptrFromInt(control_id_cloud_storage_bucket_edit), loader.GetModuleHandleA(null), null);
            cloud_storage_controls.api_label = ui.CreateWindowExA(.{}, static_class, cloud_storage_api_label_text, makeStyle(child_style_bits), 0, 0, 100, 18, hwnd, @ptrFromInt(control_id_cloud_storage_api_label), loader.GetModuleHandleA(null), null);
            cloud_storage_controls.api_edit = ui.CreateWindowExA(makeExStyle(exStyleBits(ui.WS_EX_CLIENTEDGE)), edit_class, "", makeStyle(secret_edit_style_bits), 0, 0, 100, 24, hwnd, @ptrFromInt(control_id_cloud_storage_api_edit), loader.GetModuleHandleA(null), null);
            cloud_storage_controls.key_label = ui.CreateWindowExA(.{}, static_class, cloud_storage_key_label_text, makeStyle(child_style_bits), 0, 0, 100, 18, hwnd, @ptrFromInt(control_id_cloud_storage_key_label), loader.GetModuleHandleA(null), null);
            cloud_storage_controls.key_edit = ui.CreateWindowExA(makeExStyle(exStyleBits(ui.WS_EX_CLIENTEDGE)), edit_class, "", makeStyle(secret_edit_style_bits), 0, 0, 100, 24, hwnd, @ptrFromInt(control_id_cloud_storage_key_edit), loader.GetModuleHandleA(null), null);
            cloud_storage_controls.ok_button = ui.CreateWindowExA(.{}, button_class, "OK", makeStyle(child_style_bits | styleBits(ui.WS_TABSTOP)), 0, 0, 96, 28, hwnd, @ptrFromInt(control_id_cloud_storage_ok), loader.GetModuleHandleA(null), null);

            if (cloud_storage_controls.region_label == null or cloud_storage_controls.region_edit == null or cloud_storage_controls.bucket_label == null or cloud_storage_controls.bucket_edit == null or cloud_storage_controls.api_label == null or cloud_storage_controls.api_edit == null or cloud_storage_controls.key_label == null or cloud_storage_controls.key_edit == null or cloud_storage_controls.ok_button == null) {
                return -1;
            }

            applyCloudStorageFonts();
            layoutCloudStorageWindow(hwnd);
            loadCloudStorageCredentialsIntoDialog();
            _ = mouse.SetFocus(cloud_storage_controls.region_edit);
            return 0;
        },
        ui.WM_COMMAND => {
            const command_id: u16 = @truncate(w_param & 0xffff);
            const notification_code: u16 = @truncate((w_param >> 16) & 0xffff);
            if (notification_code == ui.BN_CLICKED and command_id == control_id_cloud_storage_ok) {
                if (saveCloudStorageCredentialsFromDialog()) {
                    _ = ui.DestroyWindow(hwnd);
                }
                return 0;
            }
            return ui.DefWindowProcA(hwnd, message, w_param, l_param);
        },
        ui.WM_SIZE => {
            layoutCloudStorageWindow(hwnd);
            return 0;
        },
        ui.WM_CLOSE => {
            _ = ui.DestroyWindow(hwnd);
            return 0;
        },
        ui.WM_DESTROY => {
            if (main_window) |owner| {
                _ = EnableWindow(owner, 1);
                _ = ui.SetForegroundWindow(owner);
            }
            cloud_storage_controls = .{};
            cloud_storage_window = null;
            return 0;
        },
        else => return ui.DefWindowProcA(hwnd, message, w_param, l_param),
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
            // Scroll pans the view vertically; zoom is toolbar-only.
            const delta = wheelDeltaFromWParam(w_param);
            const scroll_amount: i32 = @divTrunc(@as(i32, delta) * 40, 120);
            panPreviewBy(hwnd, 0, -scroll_amount);
            return 0;
        },
        ui.WM_KEYDOWN, ui.WM_SYSKEYDOWN => {
            const ctrl_down = mouse.GetKeyState(@intFromEnum(mouse.VK_CONTROL)) < 0;
            if (handleDiagramNavigationShortcut(@truncate(w_param), ctrl_down)) return 0;
            const vkey: u16 = @truncate(w_param);
            const pan_step: i32 = 40;
            switch (vkey) {
                @intFromEnum(mouse.VK_LEFT) => {
                    panPreviewBy(hwnd, -pan_step, 0);
                    return 0;
                },
                @intFromEnum(mouse.VK_RIGHT) => {
                    panPreviewBy(hwnd, pan_step, 0);
                    return 0;
                },
                @intFromEnum(mouse.VK_UP) => {
                    panPreviewBy(hwnd, 0, -pan_step);
                    return 0;
                },
                @intFromEnum(mouse.VK_DOWN) => {
                    panPreviewBy(hwnd, 0, pan_step);
                    return 0;
                },
                else => {},
            }
            return ui.DefWindowProcA(hwnd, message, w_param, l_param);
        },
        ui.WM_MOUSEMOVE => {
            if (mouse.GetFocus() != hwnd) _ = mouse.SetFocus(hwnd);
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
        windows_canvas.draw.drawCanvas(&ctx, graph, canvas_renderer.canvas_state.viewport, canvas_renderer.canvas_state.selection, canvas_renderer.canvas_state.hover, canvas_renderer.canvas_state.insertion, @floatFromInt(canvas_mouse_screen_x), @floatFromInt(canvas_mouse_screen_y), canvas_snap_to_grid_enabled);
    } else {
        var bg = rgba8Color(245, 245, 245, 255);
        rt.ID2D1RenderTarget.Clear(&bg);
    }
    _ = rt.ID2D1RenderTarget.EndDraw(null, null);
}

fn toggleCanvasSnapToGrid() void {
    canvas_snap_to_grid_enabled = !canvas_snap_to_grid_enabled;
    if (child_windows.canvas) |canvas_hwnd| _ = gdi.InvalidateRect(canvas_hwnd, null, 0);
    setStatusMessage(if (canvas_snap_to_grid_enabled) "Snap to grid enabled" else "Snap to grid disabled");
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
            if (result.node_inserted) {
                addCanvasNodeAtPosition(result.insert_shape, result.insert_x, result.insert_y);
            }
            if (result.subgraph_inserted) {
                addCanvasSubgraphAtPosition(result.insert_x, result.insert_y);
            }
            if (result.link_completed) {
                if (result.link_source_id) |src| {
                    completeCanvasLink(src);
                }
            }
            if (result.document_mutated) onEditableGraphMutated();
            if (result.selection_changed or result.node_inserted or result.subgraph_inserted or result.link_completed) {
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
            canvas_mouse_screen_x = pos.x;
            canvas_mouse_screen_y = pos.y;
            const result = windows_canvas.interaction.onMouseMove(
                &canvas_renderer.canvas_state,
                pos.x,
                pos.y,
                canvas_snap_to_grid_enabled,
            );
            if (result.document_mutated) onEditableGraphMutated();
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
            // Scroll pans the canvas vertically; zoom is toolbar-only.
            const delta = wheelDeltaFromWParam(w_param);
            const scroll_amount: f64 = @as(f64, @floatFromInt(delta)) * 40.0 / 120.0;
            canvas_renderer.canvas_state.viewport.pan_y += scroll_amount / canvas_renderer.canvas_state.viewport.zoom;
            _ = gdi.InvalidateRect(hwnd, null, 0);
            return 0;
        },
        ui.WM_RBUTTONDOWN => {
            const pos = mouseCoordFromLParam(l_param);
            const result = windows_canvas.interaction.onRightButtonDown(
                &canvas_renderer.canvas_state,
                pos.x,
                pos.y,
            );
            if (result.document_mutated) onEditableGraphMutated();
            if (result.selection_changed) {
                windows_canvas.inspector.refresh(&canvas_renderer.inspector, &canvas_renderer.canvas_state);
                _ = gdi.InvalidateRect(hwnd, null, 0);
            }
            // Show the appropriate context menu based on selection state.
            if (canvas_renderer.canvas_state.hasSelection()) {
                showCanvasContextMenuSelected(hwnd.?, pos.x, pos.y);
            } else {
                showCanvasContextMenuEmpty(hwnd.?, pos.x, pos.y);
            }
            _ = gdi.InvalidateRect(hwnd, null, 0);
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
            // This ensures clicking text feels responsive ��� the first click
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
            // Alt+Arrow — resize every node/subgraph by one grid step.
            const alt_down = mouse.GetKeyState(@intFromEnum(mouse.VK_MENU)) < 0;
            if (alt_down) {
                const resize_step: f64 = 10.0;
                const resize_result = switch (vkey) {
                    @intFromEnum(mouse.VK_LEFT) => windows_canvas.interaction.resizeAllBy(&canvas_renderer.canvas_state, -resize_step, 0.0),
                    @intFromEnum(mouse.VK_RIGHT) => windows_canvas.interaction.resizeAllBy(&canvas_renderer.canvas_state, resize_step, 0.0),
                    @intFromEnum(mouse.VK_UP) => windows_canvas.interaction.resizeAllBy(&canvas_renderer.canvas_state, 0.0, -resize_step),
                    @intFromEnum(mouse.VK_DOWN) => windows_canvas.interaction.resizeAllBy(&canvas_renderer.canvas_state, 0.0, resize_step),
                    else => null,
                };
                if (resize_result) |result| {
                    if (result.document_mutated) onEditableGraphMutated();
                    if (result.needs_redraw) _ = gdi.InvalidateRect(hwnd, null, 0);
                    return 0;
                }
            }
            // Ctrl+Arrow — nudge the entire graph layout (all objects together).
            if (ctrl_down) {
                const nudge_step: f64 = 10.0;
                const all_result = switch (vkey) {
                    @intFromEnum(mouse.VK_LEFT) => windows_canvas.interaction.nudgeAllBy(&canvas_renderer.canvas_state, -nudge_step, 0.0),
                    @intFromEnum(mouse.VK_RIGHT) => windows_canvas.interaction.nudgeAllBy(&canvas_renderer.canvas_state, nudge_step, 0.0),
                    @intFromEnum(mouse.VK_UP) => windows_canvas.interaction.nudgeAllBy(&canvas_renderer.canvas_state, 0.0, -nudge_step),
                    @intFromEnum(mouse.VK_DOWN) => windows_canvas.interaction.nudgeAllBy(&canvas_renderer.canvas_state, 0.0, nudge_step),
                    else => null,
                };
                if (all_result) |result| {
                    if (result.document_mutated) onEditableGraphMutated();
                    if (result.needs_redraw) _ = gdi.InvalidateRect(hwnd, null, 0);
                    return 0;
                }
            }
            if (canvas_renderer.canvas_state.hasSelection()) {
                const nudge_result = switch (vkey) {
                    @intFromEnum(mouse.VK_LEFT) => windows_canvas.interaction.nudgeSelectionBy(&canvas_renderer.canvas_state, -10.0, 0.0),
                    @intFromEnum(mouse.VK_RIGHT) => windows_canvas.interaction.nudgeSelectionBy(&canvas_renderer.canvas_state, 10.0, 0.0),
                    @intFromEnum(mouse.VK_UP) => windows_canvas.interaction.nudgeSelectionBy(&canvas_renderer.canvas_state, 0.0, -10.0),
                    @intFromEnum(mouse.VK_DOWN) => windows_canvas.interaction.nudgeSelectionBy(&canvas_renderer.canvas_state, 0.0, 10.0),
                    else => null,
                };
                if (nudge_result) |result| {
                    if (result.document_mutated) {
                        onEditableGraphMutated();
                    }
                    if (result.selection_changed) {
                        windows_canvas.inspector.refresh(&canvas_renderer.inspector, &canvas_renderer.canvas_state);
                    }
                    if (result.needs_redraw) _ = gdi.InvalidateRect(hwnd, null, 0);
                    return 0;
                }
            }
            // Arrow keys pan when nothing is selected.
            if (!canvas_renderer.canvas_state.hasSelection()) {
                const pan_step: f64 = 40.0 / canvas_renderer.canvas_state.viewport.zoom;
                switch (vkey) {
                    @intFromEnum(mouse.VK_LEFT) => {
                        canvas_renderer.canvas_state.viewport.pan_x += pan_step;
                        _ = gdi.InvalidateRect(hwnd, null, 0);
                        return 0;
                    },
                    @intFromEnum(mouse.VK_RIGHT) => {
                        canvas_renderer.canvas_state.viewport.pan_x -= pan_step;
                        _ = gdi.InvalidateRect(hwnd, null, 0);
                        return 0;
                    },
                    @intFromEnum(mouse.VK_UP) => {
                        canvas_renderer.canvas_state.viewport.pan_y += pan_step;
                        _ = gdi.InvalidateRect(hwnd, null, 0);
                        return 0;
                    },
                    @intFromEnum(mouse.VK_DOWN) => {
                        canvas_renderer.canvas_state.viewport.pan_y -= pan_step;
                        _ = gdi.InvalidateRect(hwnd, null, 0);
                        return 0;
                    },
                    else => {},
                }
            }
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
            if (result.document_mutated) onEditableGraphMutated();
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
    child_windows.diagram_prev_button = diagram_prev_button;
    child_windows.diagram_next_button = diagram_next_button;
    child_windows.command = command;
    child_windows.apply_button = apply_button;
    child_windows.status = status;

    // Canvas child window — visible from startup (unified diagram surface).
    const canvas = ui.CreateWindowExA(
        .{},
        canvas_class_name,
        null,
        makeStyle(styleBits(ui.WS_CHILD) | styleBits(ui.WS_VISIBLE) | styleBits(ui.WS_CLIPSIBLINGS) | styleBits(ui.WS_TABSTOP)),
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
    windows_layout.applyChildLayout(hwnd, child_windows, sourcePanelVisible());
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
        clearCanvasGraphIfNeeded();
        setSyntaxErrorStatus(diagnostic.?);
        return;
    }

    applyDirectivesFromSource(diagram.mermaid_source);

    // Rebuild the editable graph for the unified canvas.
    var eg_message: [256]u8 = std.mem.zeroes([256]u8);
    const eg = merrow_studio_build_editable_graph(
        diagram.mermaid_source.ptr,
        @intCast(diagram.mermaid_source.len),
        &eg_message,
        eg_message.len,
    );
    canvas_renderer.canvas_state.setGraph(eg);
    updateCanvasPresentation(reset_view);

    const eg_status = std.mem.sliceTo(&eg_message, 0);
    const status_text = if (eg == null and eg_status.len > 0) eg_status else if (eg == null) "Failed to build diagram" else syntax_text;
    setStatusMessage(status_text);
}

fn applyUpdatedSource(source: []const u8, status_text: []const u8) void {
    setEditorText(source);
    setStatusMessage(status_text);
    updateEditorDerivedState(false);
    setDocumentDirty(true);
}

fn runReservedToolbarAction(slot: u8) void {
    const level: f64 = switch (slot) {
        1 => 1.0,
        2 => 2.0,
        3 => 4.0,
        else => return,
    };
    canvas_renderer.canvas_state.viewport.zoom = std.math.clamp(level, 0.1, 8.0);
    canvas_renderer.canvas_state.viewport.pan_x = 0;
    canvas_renderer.canvas_state.viewport.pan_y = 0;
    if (child_windows.canvas) |canvas_hwnd| _ = gdi.InvalidateRect(canvas_hwnd, null, 0);
    const label = switch (slot) {
        1 => "Canvas zoom: fit",
        2 => "Canvas zoom: 2x",
        3 => "Canvas zoom: 4x",
        else => "Canvas zoom",
    };
    setStatusMessage(label);
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
            applyModeVisibility();
            layoutChildWindows(hwnd);
            _ = ui.SetTimer(hwnd, main_timer_id_editor_refresh, 120, null);
            updateEditorDerivedState(true);
            updateWindowTitle();
            openLibraryDatabase();
            if (refreshCloudStorageState(false)) {
                setStatusMessage("Connected to S3");
            } else if (startup_preflight_message) |message_text| {
                setStatusMessage(message_text);
            }
            startup_layout_done = true;
            return 0;
        },
        ui.WM_COMMAND => {
            const command_id: u16 = @truncate(w_param & 0xffff);
            const notification_code: u16 = @truncate((w_param >> 16) & 0xffff);
            const source_hwnd: ?foundation.HWND = if (l_param == 0) null else @ptrFromInt(@as(usize, @bitCast(l_param)));
            // Handle toolbar button commands (source_hwnd is the toolbar control).
            if (notification_code == 0) {
                switch (command_id) {
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
            // Handle menu commands (source_hwnd is null for menus).
            if (notification_code == 0 and source_hwnd == null) {
                switch (command_id) {
                    menu_id_open => {
                        openDocumentFromDialog();
                        return 0;
                    },
                    menu_id_open_recent_empty => {
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
                    menu_id_export_mermaid => {
                        exportDiagramToMermaid();
                        return 0;
                    },
                    menu_id_font_settings => {
                        toggleFontInspector();
                        return 0;
                    },
                    menu_id_cloud_storage => {
                        showCloudStorageWindow();
                        return 0;
                    },
                    menu_id_sync_cloud => {
                        syncCloudStorage();
                        return 0;
                    },
                    menu_id_toggle_source_panel => {
                        toggleSourcePanelVisibility();
                        return 0;
                    },
                    menu_id_toggle_snap_to_grid => {
                        toggleCanvasSnapToGrid();
                        return 0;
                    },
                    menu_id_about => {
                        showAboutWindow();
                        return 0;
                    },
                    else => {},
                }

                if (command_id >= menu_id_open_recent_first and command_id <= menu_id_open_recent_last) {
                    openRecentDocument(command_id - menu_id_open_recent_first);
                    return 0;
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
            if (@as(usize, @bitCast(w_param)) == main_timer_id_graph_source_writeback) {
                cancelScheduledGraphSourceWriteback();
                applyGraphSourceWriteback();
                return 0;
            }
            return ui.DefWindowProcA(hwnd, message, w_param, l_param);
        },
        ui.WM_INITMENUPOPUP => {
            refreshRecentFilesMenu();
            const hmenu: ui.HMENU = @ptrFromInt(@as(usize, @bitCast(w_param)));
            _ = ui.CheckMenuItem(hmenu, menu_id_toggle_source_panel, if (sourcePanelVisible()) @as(u32, @bitCast(ui.MF_CHECKED)) else @as(u32, @bitCast(ui.MF_UNCHECKED)));
            _ = ui.CheckMenuItem(hmenu, menu_id_toggle_snap_to_grid, if (canvas_snap_to_grid_enabled) @as(u32, @bitCast(ui.MF_CHECKED)) else @as(u32, @bitCast(ui.MF_UNCHECKED)));
            _ = ui.CheckMenuItem(hmenu, menu_id_font_settings, if (windows_canvas.inspector.fontInspectorActive()) @as(u32, @bitCast(ui.MF_CHECKED)) else @as(u32, @bitCast(ui.MF_UNCHECKED)));
            return 0;
        },
        ui.WM_SIZE => {
            if (!startup_layout_done) return 0;
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
            if (about_window) |window| {
                _ = ui.DestroyWindow(window);
                about_window = null;
            }
            _ = ui.KillTimer(hwnd, main_timer_id_editor_refresh);
            _ = ui.KillTimer(hwnd, main_timer_id_ffm_persist);
            _ = ui.KillTimer(hwnd, main_timer_id_graph_source_writeback);
            flushPendingGraphSourceWriteback();
            persistCurrentFreeformGraph();
            closeLibraryDatabase();
            disableCloudStorage();
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

    var about_class = std.mem.zeroes(ui.WNDCLASSEXA);
    about_class.cbSize = @sizeOf(ui.WNDCLASSEXA);
    about_class.lpfnWndProc = aboutWindowProc;
    about_class.hInstance = h_instance;
    about_class.hCursor = ui.LoadCursorW(null, ui.IDC_ARROW);
    about_class.lpszClassName = about_class_name;
    if (ui.RegisterClassExA(&about_class) == 0) {
        return 1;
    }

    var about_image_class = std.mem.zeroes(ui.WNDCLASSEXA);
    about_image_class.cbSize = @sizeOf(ui.WNDCLASSEXA);
    about_image_class.lpfnWndProc = aboutImageWindowProc;
    about_image_class.hInstance = h_instance;
    about_image_class.hCursor = ui.LoadCursorW(null, ui.IDC_ARROW);
    about_image_class.lpszClassName = about_image_class_name;
    if (ui.RegisterClassExA(&about_image_class) == 0) {
        return 1;
    }

    var cloud_storage_class = std.mem.zeroes(ui.WNDCLASSEXA);
    cloud_storage_class.cbSize = @sizeOf(ui.WNDCLASSEXA);
    cloud_storage_class.lpfnWndProc = cloudStorageWindowProc;
    cloud_storage_class.hInstance = h_instance;
    cloud_storage_class.hCursor = ui.LoadCursorW(null, ui.IDC_ARROW);
    cloud_storage_class.lpszClassName = cloud_storage_class_name;
    if (ui.RegisterClassExA(&cloud_storage_class) == 0) {
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
