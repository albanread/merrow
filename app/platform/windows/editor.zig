const std = @import("std");
const win32 = @import("win32");

const foundation = win32.foundation;
const gdi = win32.graphics.gdi;
const loader = win32.system.library_loader;
const rich_edit = win32.ui.controls.rich_edit;
const ui = win32.ui.windows_and_messaging;

pub const EditorTheme = struct {
    background: u32,
    default_text: u32,
    keyword_text: u32,
    direction_text: u32,
    comment_text: u32,
    string_text: u32,
    symbol_text: u32,
    identifier_text: u32,
    error_background: u32,
};

pub const EditorTokenStyle = struct {
    color: u32,
    bold: bool,
};

pub const editor_theme = EditorTheme{
    .background = 0x00f7f7f4,
    .default_text = 0x00262b33,
    .keyword_text = 0x00a33b1f,
    .direction_text = 0x009f5a00,
    .comment_text = 0x0080705f,
    .string_text = 0x001f6fb2,
    .symbol_text = 0x00584fbf,
    .identifier_text = 0x00262b33,
    .error_background = 0x00e6f0ff,
};

pub fn ensureRichEditLibrary(rich_edit_module: anytype) bool {
    if (rich_edit_module.* != null) return true;
    rich_edit_module.* = loader.LoadLibraryA("Riched20.dll");
    return rich_edit_module.* != null;
}

pub fn releaseEditorFont(editor_font: *?gdi.HFONT) void {
    if (editor_font.*) |font| {
        _ = gdi.DeleteObject(font);
        editor_font.* = null;
    }
}

pub fn ensureEditorFont(editor_font: *?gdi.HFONT) ?gdi.HFONT {
    if (editor_font.* != null) return editor_font.*;

    editor_font.* = gdi.CreateFontA(
        -20,
        0,
        0,
        0,
        400,
        0,
        0,
        0,
        0,
        gdi.OUT_DEFAULT_PRECIS,
        gdi.CLIP_DEFAULT_PRECIS,
        gdi.CLEARTYPE_QUALITY,
        @enumFromInt(0),
        "Consolas",
    );
    return editor_font.*;
}

fn sendEditorMessage(editor_hwnd: ?foundation.HWND, message: u32, w_param: usize, l_param: isize) foundation.LRESULT {
    return ui.SendMessageA(editor_hwnd, message, w_param, l_param);
}

fn richMaskBits(mask: rich_edit.CFM_MASK) u32 {
    return @bitCast(mask);
}

fn makeRichMask(bits: u32) rich_edit.CFM_MASK {
    return @bitCast(bits);
}

fn makeRichEffects(bits: u32) rich_edit.CFE_EFFECTS {
    return @bitCast(bits);
}

fn setEditorSelection(editor_hwnd: ?foundation.HWND, start: i32, end: i32) void {
    var range = rich_edit.CHARRANGE{ .cpMin = start, .cpMax = end };
    _ = sendEditorMessage(editor_hwnd, rich_edit.EM_EXSETSEL, 0, @bitCast(@intFromPtr(&range)));
}

fn applyEditorBaseStyle(editor_hwnd: ?foundation.HWND) void {
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
    setEditorSelection(editor_hwnd, 0, -1);
    _ = sendEditorMessage(editor_hwnd, rich_edit.EM_SETCHARFORMAT, rich_edit.SCF_ALL, @bitCast(@intFromPtr(&format)));
}

pub fn applyEditorSyntaxHighlight(editor_hwnd: ?foundation.HWND, text: []const u8, syntax_ok: bool) void {
    _ = text;
    if (editor_hwnd == null) return;
    _ = sendEditorMessage(editor_hwnd, rich_edit.EM_HIDESELECTION, 1, 0);
    _ = sendEditorMessage(editor_hwnd, rich_edit.EM_SETBKGNDCOLOR, 0, @intCast(if (syntax_ok) editor_theme.background else editor_theme.error_background));
    applyEditorBaseStyle(editor_hwnd);
}

pub fn configureEditorControl(editor_hwnd: ?foundation.HWND, editor_font: *?gdi.HFONT) void {
    if (editor_hwnd == null) return;
    if (ensureEditorFont(editor_font)) |font| {
        _ = ui.SendMessageA(editor_hwnd, ui.WM_SETFONT, @intFromPtr(font), 1);
    }
}

pub fn setEditorText(allocator: std.mem.Allocator, editor_hwnd: ?foundation.HWND, suppress_editor_change: *bool, text: []const u8) void {
    suppress_editor_change.* = true;
    defer suppress_editor_change.* = false;

    const z_text = allocator.allocSentinel(u8, text.len, 0) catch return;
    defer allocator.free(z_text);
    @memcpy(z_text[0..text.len], text);
    _ = ui.SetWindowTextA(editor_hwnd, z_text.ptr);
}

pub fn getWindowText(allocator: std.mem.Allocator, hwnd: ?foundation.HWND) ![:0]u8 {
    const handle = hwnd orelse return error.WindowNotReady;
    const text_len = ui.GetWindowTextLengthA(handle);
    const safe_len: usize = if (text_len > 0) @intCast(text_len) else 0;
    const buffer = try allocator.allocSentinel(u8, safe_len, 0);
    errdefer allocator.free(buffer);

    const copied_len = ui.GetWindowTextA(handle, buffer.ptr, @intCast(buffer.len + 1));
    if (copied_len < 0) return error.Unexpected;
    return buffer;
}

pub fn getEditorText(allocator: std.mem.Allocator, editor_hwnd: ?foundation.HWND) ![:0]u8 {
    return getWindowText(allocator, editor_hwnd);
}
