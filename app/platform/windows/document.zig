const std = @import("std");
const win32 = @import("win32");
const common = @import("common.zig");
const constants = @import("constants.zig");

const dialogs = win32.ui.controls.dialogs;
const foundation = win32.foundation;
const ui = win32.ui.windows_and_messaging;

fn setWindowText(allocator: std.mem.Allocator, hwnd: ?foundation.HWND, text: []const u8) void {
    const z_text = allocator.allocSentinel(u8, text.len, 0) catch return;
    defer allocator.free(z_text);
    @memcpy(z_text[0..text.len], text);
    _ = ui.SetWindowTextA(hwnd, z_text.ptr);
}

pub fn freeCurrentDocumentPath(allocator: std.mem.Allocator, current_document_path: *?[]u8) void {
    if (current_document_path.*) |path| {
        allocator.free(path);
        current_document_path.* = null;
    }
}

pub fn updateWindowTitle(
    allocator: std.mem.Allocator,
    hwnd: ?foundation.HWND,
    current_document_path: ?[]u8,
    is_document_dirty: bool,
) void {
    const base_name = if (current_document_path) |path| std.fs.path.basename(path) else "Untitled";
    const title_text = std.fmt.allocPrint(
        allocator,
        "Merrow Studio (Windows Scaffold) - {s}{s}",
        .{ base_name, if (is_document_dirty) " *" else "" },
    ) catch return;
    defer allocator.free(title_text);
    setWindowText(allocator, hwnd, title_text);
}

pub fn setCurrentDocumentPath(
    allocator: std.mem.Allocator,
    current_document_path: *?[]u8,
    path: ?[]const u8,
    hwnd: ?foundation.HWND,
    is_document_dirty: bool,
) void {
    freeCurrentDocumentPath(allocator, current_document_path);
    if (path) |value| {
        current_document_path.* = allocator.dupe(u8, value) catch null;
    }
    updateWindowTitle(allocator, hwnd, current_document_path.*, is_document_dirty);
}

pub fn setDocumentDirty(
    allocator: std.mem.Allocator,
    is_document_dirty: *bool,
    dirty: bool,
    hwnd: ?foundation.HWND,
    current_document_path: ?[]u8,
) void {
    is_document_dirty.* = dirty;
    updateWindowTitle(allocator, hwnd, current_document_path, dirty);
}

pub fn chooseDocumentPath(
    allocator: std.mem.Allocator,
    owner_hwnd: ?foundation.HWND,
    current_document_path: ?[]u8,
    save: bool,
) ?[]u8 {
    var path_buffer = [_]u8{0} ** 1024;
    if (current_document_path) |path| {
        const copy_len = @min(path.len, path_buffer.len - 1);
        @memcpy(path_buffer[0..copy_len], path[0..copy_len]);
        path_buffer[copy_len] = 0;
    }

    var dialog = std.mem.zeroes(dialogs.OPENFILENAMEA);
    dialog.lStructSize = @sizeOf(dialogs.OPENFILENAMEA);
    dialog.hwndOwner = owner_hwnd;
    dialog.lpstrFilter = constants.mermaid_dialog_filter;
    dialog.lpstrFile = @ptrCast(path_buffer[0..].ptr);
    dialog.nMaxFile = path_buffer.len;
    dialog.lpstrTitle = if (save) constants.save_dialog_title else constants.open_dialog_title;
    dialog.lpstrDefExt = constants.default_extension;
    dialog.Flags = common.makeFileDialogFlags(
        common.fileDialogFlagBits(dialogs.OFN_PATHMUSTEXIST) |
            if (save) common.fileDialogFlagBits(dialogs.OFN_OVERWRITEPROMPT) else common.fileDialogFlagBits(dialogs.OFN_FILEMUSTEXIST),
    );

    const ok = if (save) dialogs.GetSaveFileNameA(&dialog) else dialogs.GetOpenFileNameA(&dialog);
    if (ok == 0) return null;
    const selected = std.mem.sliceTo(&path_buffer, 0);
    return allocator.dupe(u8, selected) catch null;
}

pub fn loadSourceFromPath(allocator: std.mem.Allocator, path: []const u8) ![]u8 {
    const file = try std.fs.openFileAbsolute(path, .{});
    defer file.close();
    return file.readToEndAlloc(allocator, 16 * 1024 * 1024);
}

pub fn saveSourceToPath(path: []const u8, source: []const u8) !void {
    const file = try std.fs.createFileAbsolute(path, .{ .truncate = true });
    defer file.close();
    try file.writeAll(source);
}
