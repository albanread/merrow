const win32 = @import("win32");

const foundation = win32.foundation;
const d2d = win32.graphics.direct2d;
const dw = win32.graphics.direct_write;

pub const ChildWindows = struct {
    preview: ?foundation.HWND = null,
    editor: ?foundation.HWND = null,
    toolbar: ?foundation.HWND = null,
    command: ?foundation.HWND = null,
    apply_button: ?foundation.HWND = null,
    status: ?foundation.HWND = null,
};

pub const PreviewRenderer = struct {
    factory: ?*d2d.ID2D1Factory = null,
    write_factory: ?*dw.IDWriteFactory = null,
    render_target: ?*d2d.ID2D1HwndRenderTarget = null,
    brush: ?*d2d.ID2D1SolidColorBrush = null,
    zoom: f64 = 1.0,
    scroll_x: i32 = 0,
    scroll_y: i32 = 0,
    is_dragging: bool = false,
    drag_last_x: i32 = 0,
    drag_last_y: i32 = 0,
};
