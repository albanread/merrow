const std = @import("std");
const win32 = @import("win32");
const common = @import("common.zig");
const constants = @import("constants.zig");
const status_bar = @import("status_bar.zig");

const foundation = win32.foundation;
const ui = win32.ui.windows_and_messaging;

pub fn applyChildLayout(hwnd: ?foundation.HWND, child_windows: anytype) void {
    if (child_windows.preview == null or child_windows.editor == null or child_windows.toolbar == null or child_windows.command == null or child_windows.apply_button == null or child_windows.status == null) return;

    var rect = std.mem.zeroes(foundation.RECT);
    if (ui.GetClientRect(hwnd, &rect) == 0) return;

    const layout = constants.Layout{};
    const client_width = rect.right - rect.left;
    const client_height = rect.bottom - rect.top;
    if (client_width <= 0 or client_height <= 0) return;

    const status_y = client_height - layout.status_height;
    const content_top = layout.padding;
    const content_height = status_y - content_top - layout.gutter;
    if (content_height <= 0) return;

    const content_width = client_width - (layout.padding * 2);
    if (content_width <= layout.gutter) return;

    const split_width = content_width - layout.gutter;
    if (split_width < layout.min_preview_width + layout.min_editor_width) return;

    const preferred_preview_width = @divTrunc(content_width * layout.left_ratio_num, layout.left_ratio_den) - @divTrunc(layout.gutter, 2);
    const preview_width = std.math.clamp(preferred_preview_width, layout.min_preview_width, split_width - layout.min_editor_width);
    const editor_width = split_width - preview_width;
    const editor_x = layout.padding + preview_width + layout.gutter;
    const toolbar_y = content_top;
    const editor_y = toolbar_y + layout.command_bar_height + layout.gutter;
    const editor_height = content_height - layout.command_bar_height - layout.gutter;
    const reserved_width = layout.toolbar_button_width * 3;
    const toolbar_width = reserved_width;
    const apply_x = editor_x + toolbar_width + layout.gutter;
    const command_x = apply_x + layout.command_button_width + layout.gutter;
    const command_width = @max(layout.min_command_width, editor_x + editor_width - command_x - layout.toolbar_inner_padding);
    const band_child_y = toolbar_y + 2;
    const band_child_height = layout.command_bar_height - 4;

    const defer_flags = @as(u32, common.setPosFlagsBits(ui.SWP_NOZORDER)) | @as(u32, common.setPosFlagsBits(ui.SWP_NOACTIVATE)) | @as(u32, common.setPosFlagsBits(ui.SWP_NOREDRAW));
    var dwp = ui.BeginDeferWindowPos(7);
    if (dwp == 0) return;
    dwp = ui.DeferWindowPos(dwp, child_windows.preview, null, layout.padding, content_top, preview_width, content_height, @bitCast(defer_flags));
    if (dwp == 0) return;
    dwp = ui.DeferWindowPos(dwp, child_windows.toolbar, null, editor_x, toolbar_y, toolbar_width, layout.command_bar_height, @bitCast(defer_flags));
    if (dwp == 0) return;
    dwp = ui.DeferWindowPos(dwp, child_windows.apply_button, null, apply_x, band_child_y, layout.command_button_width, band_child_height, @bitCast(defer_flags));
    if (dwp == 0) return;
    dwp = ui.DeferWindowPos(dwp, child_windows.command, null, command_x, band_child_y, command_width, band_child_height, @bitCast(defer_flags));
    if (dwp == 0) return;
    dwp = ui.DeferWindowPos(dwp, child_windows.editor, null, editor_x, editor_y, editor_width, editor_height, @bitCast(defer_flags));
    if (dwp == 0) return;
    dwp = ui.DeferWindowPos(dwp, child_windows.status, null, 0, status_y, client_width, layout.status_height, @bitCast(defer_flags));
    if (dwp == 0) return;
    // Canvas (freeform mode) — always positioned so show/hide controls visibility.
    if (child_windows.canvas) |cw| {
        const canvas_width = @max(0, content_width - layout.inspector_width - layout.gutter);
        dwp = ui.DeferWindowPos(dwp, cw, null, layout.padding, content_top, canvas_width, content_height, @bitCast(defer_flags));
        if (dwp == 0) return;
    }
    _ = ui.EndDeferWindowPos(dwp);
    status_bar.updateStatusBarParts(child_windows.status, client_width);
}

pub fn minimumClientSize() constants.WindowSize {
    const layout = constants.Layout{};
    const min_width = layout.padding * 2 + layout.gutter + layout.min_preview_width + layout.min_editor_width;
    const min_height = layout.padding + layout.gutter + layout.command_bar_height + layout.gutter + layout.min_content_height + layout.status_height;
    return .{ .width = min_width, .height = min_height };
}

pub fn minimumWindowTrackSize() constants.WindowSize {
    const client = minimumClientSize();
    var rect = foundation.RECT{ .left = 0, .top = 0, .right = client.width, .bottom = client.height };
    _ = ui.AdjustWindowRectEx(&rect, common.makeStyle(common.styleBits(ui.WS_OVERLAPPEDWINDOW) | common.styleBits(ui.WS_CLIPCHILDREN)), 1, .{});
    return .{ .width = rect.right - rect.left, .height = rect.bottom - rect.top };
}
