const std = @import("std");
const win32 = @import("win32");
const common = @import("common.zig");
const constants = @import("constants.zig");
const status_bar = @import("status_bar.zig");

const foundation = win32.foundation;
const ui = win32.ui.windows_and_messaging;

pub fn applyChildLayout(hwnd: ?foundation.HWND, child_windows: anytype, source_panel_visible: bool) void {
    if (child_windows.preview == null or child_windows.diagram_label == null or child_windows.editor == null or child_windows.toolbar == null or child_windows.diagram_prev_button == null or child_windows.diagram_next_button == null or child_windows.command == null or child_windows.apply_button == null or child_windows.status == null) return;

    var rect = std.mem.zeroes(foundation.RECT);
    if (ui.GetClientRect(hwnd, &rect) == 0) return;

    const layout = constants.Layout{};
    const client_width = rect.right - rect.left;
    const client_height = rect.bottom - rect.top;
    if (client_width <= 0 or client_height <= 0) return;

    const status_y = client_height - layout.status_height;
    const content_top = layout.padding;
    const content_height = status_y - content_top - layout.gutter;
    if (content_height <= layout.diagram_selector_height + layout.gutter) return;

    const content_width = client_width - (layout.padding * 2);
    if (content_width <= layout.gutter) return;

    const split_width = content_width - layout.gutter;
    if (split_width < layout.min_preview_width + layout.min_editor_width) return;

    // Unified layout: canvas always gets primary space, source pane on the right when visible.
    const canvas_width = @max(0, content_width - layout.inspector_width - layout.gutter);
    const diagram_band_y = content_top;
    const diagram_content_y = diagram_band_y + layout.diagram_selector_height + layout.gutter;
    const preview_height = content_height - layout.diagram_selector_height - layout.gutter;

    // When source panel is visible, split the canvas area to share with editor.
    const effective_canvas_width = if (source_panel_visible) blk: {
        const max_canvas = canvas_width - layout.gutter - layout.min_editor_width;
        if (max_canvas < layout.min_preview_width) break :blk canvas_width; // too narrow, give all to canvas
        const preferred_canvas = @divTrunc(canvas_width * layout.left_ratio_num, layout.left_ratio_den) - @divTrunc(layout.gutter, 2);
        break :blk std.math.clamp(preferred_canvas, layout.min_preview_width, max_canvas);
    } else canvas_width;

    const editor_width = if (source_panel_visible) canvas_width - effective_canvas_width - layout.gutter else 1;
    const editor_x = if (source_panel_visible) layout.padding + effective_canvas_width + layout.gutter else -1;
    const toolbar_y = content_top;
    const editor_y = if (source_panel_visible) toolbar_y + layout.command_bar_height + layout.gutter else -1;
    const editor_height = if (source_panel_visible) content_height - layout.command_bar_height - layout.gutter else 1;
    const apply_x = editor_x;
    const command_x = if (source_panel_visible) apply_x + layout.command_button_width + layout.gutter else -1;
    const command_width = if (source_panel_visible)
        @max(layout.min_command_width, editor_x + editor_width - command_x - layout.toolbar_inner_padding)
    else
        1;
    const band_child_y = toolbar_y + 2;
    const band_child_y_hidden = -1;
    const band_child_height = if (source_panel_visible) layout.command_bar_height - 4 else 1;
    const diagram_band_width = if (!source_panel_visible) canvas_width else effective_canvas_width;

    // Diagram band layout: [Fit][2x][4x]  [Diagram N of M]  ... [Prev][Next]
    const zoom_toolbar_x = layout.padding;
    const zoom_toolbar_width = layout.toolbar_button_width * 3;
    const diagram_label_x = zoom_toolbar_x + zoom_toolbar_width + layout.diagram_header_padding;
    const diagram_prev_x = layout.padding + diagram_band_width - layout.diagram_nav_button_width * 2 - layout.diagram_header_padding;
    const diagram_next_x = layout.padding + diagram_band_width - layout.diagram_nav_button_width;
    const diagram_label_width = @max(layout.diagram_label_width, diagram_prev_x - diagram_label_x - layout.diagram_header_padding);

    const defer_flags = @as(u32, common.setPosFlagsBits(ui.SWP_NOZORDER)) | @as(u32, common.setPosFlagsBits(ui.SWP_NOACTIVATE));
    var dwp = ui.BeginDeferWindowPos(10);
    if (dwp == 0) return;
    // Preview window — positioned off-screen (retained for export rendering only).
    dwp = ui.DeferWindowPos(dwp, child_windows.preview, null, -1, -1, 1, 1, @bitCast(defer_flags));
    if (dwp == 0) return;
    dwp = ui.DeferWindowPos(dwp, child_windows.diagram_label, null, diagram_label_x, diagram_band_y, diagram_label_width, layout.diagram_selector_height, @bitCast(defer_flags));
    if (dwp == 0) return;
    dwp = ui.DeferWindowPos(dwp, child_windows.toolbar, null, zoom_toolbar_x, diagram_band_y, zoom_toolbar_width, layout.diagram_selector_height, @bitCast(defer_flags));
    if (dwp == 0) return;
    dwp = ui.DeferWindowPos(dwp, child_windows.diagram_prev_button, null, diagram_prev_x, diagram_band_y, layout.diagram_nav_button_width, layout.diagram_selector_height, @bitCast(defer_flags));
    if (dwp == 0) return;
    dwp = ui.DeferWindowPos(dwp, child_windows.diagram_next_button, null, diagram_next_x, diagram_band_y, layout.diagram_nav_button_width, layout.diagram_selector_height, @bitCast(defer_flags));
    if (dwp == 0) return;
    dwp = ui.DeferWindowPos(dwp, child_windows.apply_button, null, apply_x, if (source_panel_visible) band_child_y else band_child_y_hidden, if (source_panel_visible) layout.command_button_width else 1, band_child_height, @bitCast(defer_flags));
    if (dwp == 0) return;
    dwp = ui.DeferWindowPos(dwp, child_windows.command, null, command_x, if (source_panel_visible) band_child_y else band_child_y_hidden, command_width, band_child_height, @bitCast(defer_flags));
    if (dwp == 0) return;
    dwp = ui.DeferWindowPos(dwp, child_windows.editor, null, editor_x, editor_y, editor_width, editor_height, @bitCast(defer_flags));
    if (dwp == 0) return;
    dwp = ui.DeferWindowPos(dwp, child_windows.status, null, 0, status_y, client_width, layout.status_height, @bitCast(defer_flags));
    if (dwp == 0) return;
    // Canvas — always visible, primary diagram surface.
    if (child_windows.canvas) |cw| {
        dwp = ui.DeferWindowPos(dwp, cw, null, layout.padding, diagram_content_y, effective_canvas_width, preview_height, @bitCast(defer_flags));
        if (dwp == 0) return;
    }
    _ = ui.EndDeferWindowPos(dwp);
    status_bar.updateStatusBarParts(child_windows.status, client_width);
}

pub fn minimumClientSize() constants.WindowSize {
    const layout = constants.Layout{};
    const min_width = layout.padding * 2 + layout.gutter + layout.min_preview_width + layout.min_editor_width;
    const min_height = layout.padding + layout.diagram_selector_height + layout.gutter + layout.min_content_height + layout.status_height;
    return .{ .width = min_width, .height = min_height };
}

pub fn minimumWindowTrackSize() constants.WindowSize {
    const client = minimumClientSize();
    var rect = foundation.RECT{ .left = 0, .top = 0, .right = client.width, .bottom = client.height };
    _ = ui.AdjustWindowRectEx(&rect, common.makeStyle(common.styleBits(ui.WS_OVERLAPPEDWINDOW) | common.styleBits(ui.WS_CLIPCHILDREN)), 1, .{});
    return .{ .width = rect.right - rect.left, .height = rect.bottom - rect.top };
}
