const std = @import("std");
const win32 = @import("win32");
const constants = @import("constants.zig");

const controls = win32.ui.controls;
const foundation = win32.foundation;
const ui = win32.ui.windows_and_messaging;

fn appendMenuItem(menu: ?ui.HMENU, flags: ui.MENU_ITEM_FLAGS, item_id: usize, text: ?[*:0]const u8) bool {
    return ui.AppendMenuA(menu, flags, item_id, text) != 0;
}

pub fn installMenuBar(hwnd: ?foundation.HWND) bool {
    const main_menu = ui.CreateMenu() orelse return false;
    const file_menu = ui.CreatePopupMenu() orelse return false;

    if (!appendMenuItem(file_menu, ui.MF_STRING, constants.menu_id_open, constants.menu_open_label)) return false;
    if (!appendMenuItem(file_menu, ui.MF_STRING, constants.menu_id_save, constants.menu_save_label)) return false;
    if (!appendMenuItem(file_menu, ui.MF_STRING, constants.menu_id_save_as, constants.menu_save_as_label)) return false;
    if (!appendMenuItem(main_menu, ui.MF_POPUP, @intFromPtr(file_menu), constants.file_menu_label)) return false;
    if (ui.SetMenu(hwnd, main_menu) == 0) return false;
    _ = ui.DrawMenuBar(hwnd);
    return true;
}

pub fn initializeToolbarControl(toolbar_hwnd: ?foundation.HWND) void {
    const toolbar = toolbar_hwnd orelse return;
    const layout = constants.Layout{};

    _ = ui.SendMessageA(toolbar, controls.TB_BUTTONSTRUCTSIZE, @sizeOf(controls.TBBUTTON), 0);
    _ = ui.SendMessageA(
        toolbar,
        controls.TB_SETBUTTONSIZE,
        0,
        (@as(isize, layout.command_bar_height - 6) << 16) | @as(isize, layout.toolbar_button_width),
    );

    var buttons = [_]controls.TBBUTTON{
        .{
            .iBitmap = controls.I_IMAGENONE,
            .idCommand = @intCast(constants.toolbar_id_reserved_1),
            .fsState = @intCast(controls.TBSTATE_ENABLED),
            .fsStyle = @intCast(controls.BTNS_BUTTON | controls.BTNS_SHOWTEXT),
            .bReserved = std.mem.zeroes(@FieldType(controls.TBBUTTON, "bReserved")),
            .dwData = 0,
            .iString = @bitCast(@intFromPtr(constants.toolbar_slot_1_label)),
        },
        .{
            .iBitmap = controls.I_IMAGENONE,
            .idCommand = @intCast(constants.toolbar_id_reserved_2),
            .fsState = @intCast(controls.TBSTATE_ENABLED),
            .fsStyle = @intCast(controls.BTNS_BUTTON | controls.BTNS_SHOWTEXT),
            .bReserved = std.mem.zeroes(@FieldType(controls.TBBUTTON, "bReserved")),
            .dwData = 0,
            .iString = @bitCast(@intFromPtr(constants.toolbar_slot_2_label)),
        },
        .{
            .iBitmap = controls.I_IMAGENONE,
            .idCommand = @intCast(constants.toolbar_id_reserved_3),
            .fsState = @intCast(controls.TBSTATE_ENABLED),
            .fsStyle = @intCast(controls.BTNS_BUTTON | controls.BTNS_SHOWTEXT),
            .bReserved = std.mem.zeroes(@FieldType(controls.TBBUTTON, "bReserved")),
            .dwData = 0,
            .iString = @bitCast(@intFromPtr(constants.toolbar_slot_3_label)),
        },
    };

    _ = ui.SendMessageA(toolbar, controls.TB_ADDBUTTONSA, buttons.len, @bitCast(@intFromPtr(&buttons[0])));
    _ = ui.SendMessageA(toolbar, controls.TB_AUTOSIZE, 0, 0);
}
