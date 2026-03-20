const std = @import("std");
const win32 = @import("win32");
const canvas_mod = @import("canvas.zig");

const foundation = win32.foundation;
const d2d = win32.graphics.direct2d;
const imaging = win32.graphics.imaging;

/// Top-level application mode.
pub const AppMode = enum {
    /// Mermaid source editor + preview panel.
    mermaid,
    /// Freeform interactive canvas + inspector panel.
    freeform,
};

pub const ChildWindows = struct {
    preview: ?foundation.HWND = null,
    editor: ?foundation.HWND = null,
    toolbar: ?foundation.HWND = null,
    command: ?foundation.HWND = null,
    apply_button: ?foundation.HWND = null,
    status: ?foundation.HWND = null,
    /// Freeform canvas draw surface (replaces preview in freeform mode).
    canvas: ?foundation.HWND = null,
};

pub const CanvasRenderer = struct {
    /// Live graph data — owned by CanvasState.
    canvas_state: canvas_mod.CanvasState,
    /// Inspector panel controls.
    inspector: canvas_mod.InspectorControls,
    /// D2D factory shared with the preview renderer.
    factory: ?*d2d.ID2D1Factory = null,
    /// Per-window D2D render target for the canvas child window.
    render_target: ?*d2d.ID2D1HwndRenderTarget = null,

    pub fn init(allocator: std.mem.Allocator) CanvasRenderer {
        return .{
            .canvas_state = canvas_mod.CanvasState.init(allocator),
            .inspector = .{},
        };
    }

    pub fn deinit(self: *CanvasRenderer) void {
        self.canvas_state.deinit();
    }
};

pub const PreviewRenderer = struct {
    factory: ?*d2d.ID2D1Factory = null,
    wic_factory: ?*imaging.IWICImagingFactory = null,
    render_target: ?*d2d.ID2D1HwndRenderTarget = null,
    bitmap: ?*d2d.ID2D1Bitmap = null,
    preview_png: ?[]u8 = null,
    bitmap_width: u32 = 0,
    bitmap_height: u32 = 0,
    com_initialized: bool = false,
    zoom: f64 = 1.0,
    scroll_x: i32 = 0,
    scroll_y: i32 = 0,
    is_dragging: bool = false,
    drag_last_x: i32 = 0,
    drag_last_y: i32 = 0,
};
