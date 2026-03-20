const std = @import("std");
const win32 = @import("win32");
const constants = @import("constants.zig");

const controls = win32.ui.controls;
const foundation = win32.foundation;
const ui = win32.ui.windows_and_messaging;

pub fn setStatusBarPartText(allocator: std.mem.Allocator, status_hwnd: ?foundation.HWND, part: usize, text: []const u8) void {
    const hwnd = status_hwnd orelse return;
    const z_text = allocator.allocSentinel(u8, text.len, 0) catch return;
    defer allocator.free(z_text);
    @memcpy(z_text[0..text.len], text);
    _ = ui.SendMessageA(hwnd, controls.SB_SETTEXTA, part, @bitCast(@intFromPtr(z_text.ptr)));
}

pub fn updateStatusBarParts(status_hwnd: ?foundation.HWND, total_width: i32) void {
    const hwnd = status_hwnd orelse return;
    var parts = [_]i32{ @max(0, total_width - 116), -1 };
    _ = ui.SendMessageA(hwnd, controls.SB_SETPARTS, parts.len, @bitCast(@intFromPtr(&parts)));
}

pub fn refreshStatusDisplay(allocator: std.mem.Allocator, status_hwnd: ?foundation.HWND, current_status_message: ?[]u8, zoom: f64) void {
    if (status_hwnd == null) return;
    const base = current_status_message orelse constants.status_placeholder[0..std.mem.len(constants.status_placeholder)];
    const zoom_pct: i32 = @intFromFloat(@round(zoom * 100.0));
    const zoom_text = std.fmt.allocPrint(allocator, "Zoom {d}%", .{zoom_pct}) catch return;
    defer allocator.free(zoom_text);
    setStatusBarPartText(allocator, status_hwnd, 0, base);
    setStatusBarPartText(allocator, status_hwnd, 1, zoom_text);
}
