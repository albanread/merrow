const std = @import("std");
const win32 = @import("win32");

const gdi = win32.graphics.gdi;
const ui = win32.ui.windows_and_messaging;

pub fn releaseShellFont(shell_font: *?gdi.HFONT, status_font: *?gdi.HFONT) void {
    if (shell_font.*) |font| {
        _ = gdi.DeleteObject(font);
        shell_font.* = null;
    }
    if (status_font.*) |font| {
        _ = gdi.DeleteObject(font);
        status_font.* = null;
    }
}

pub fn ensureShellFont(shell_font: *?gdi.HFONT, status_font: *?gdi.HFONT) ?gdi.HFONT {
    if (shell_font.* != null) return shell_font.*;

    var metrics = std.mem.zeroes(ui.NONCLIENTMETRICSA);
    metrics.cbSize = @sizeOf(ui.NONCLIENTMETRICSA);
    if (ui.SystemParametersInfoA(ui.SPI_GETNONCLIENTMETRICS, metrics.cbSize, @ptrCast(&metrics), .{}) == 0) {
        return null;
    }

    var toolbar_logfont = metrics.lfMenuFont;
    if (toolbar_logfont.lfHeight < 0) {
        toolbar_logfont.lfHeight += 1;
    } else if (toolbar_logfont.lfHeight > 0) {
        toolbar_logfont.lfHeight -= 1;
    }

    shell_font.* = gdi.CreateFontIndirectA(&toolbar_logfont);
    status_font.* = gdi.CreateFontIndirectA(&metrics.lfStatusFont);
    return shell_font.*;
}

pub fn configureShellFonts(child_windows: anytype, shell_font: *?gdi.HFONT, status_font: *?gdi.HFONT) void {
    const toolbar_font = ensureShellFont(shell_font, status_font) orelse return;
    if (child_windows.toolbar) |toolbar| {
        _ = ui.SendMessageA(toolbar, ui.WM_SETFONT, @intFromPtr(toolbar_font), 1);
    }
    if (child_windows.status) |status| {
        _ = ui.SendMessageA(status, ui.WM_SETFONT, @intFromPtr(status_font.* orelse toolbar_font), 1);
    }
    if (child_windows.apply_button) |apply_button| {
        _ = ui.SendMessageA(apply_button, ui.WM_SETFONT, @intFromPtr(toolbar_font), 1);
    }
    if (child_windows.diagram_label) |diagram_label| {
        _ = ui.SendMessageA(diagram_label, ui.WM_SETFONT, @intFromPtr(toolbar_font), 1);
    }
    if (child_windows.diagram_prev_button) |diagram_prev_button| {
        _ = ui.SendMessageA(diagram_prev_button, ui.WM_SETFONT, @intFromPtr(toolbar_font), 1);
    }
    if (child_windows.diagram_next_button) |diagram_next_button| {
        _ = ui.SendMessageA(diagram_next_button, ui.WM_SETFONT, @intFromPtr(toolbar_font), 1);
    }
    if (child_windows.command) |command| {
        _ = ui.SendMessageA(command, ui.WM_SETFONT, @intFromPtr(toolbar_font), 1);
    }
}
