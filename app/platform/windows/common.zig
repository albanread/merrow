const std = @import("std");
const win32 = @import("win32");

const foundation = win32.foundation;
const gdi = win32.graphics.gdi;
const dialogs = win32.ui.controls.dialogs;
const ui = win32.ui.windows_and_messaging;

pub fn setPosFlagsBits(flags: ui.SET_WINDOW_POS_FLAGS) u32 {
    return @bitCast(flags);
}

pub fn redrawFlagsBits(flags: gdi.REDRAW_WINDOW_FLAGS) u32 {
    return @bitCast(flags);
}

pub fn makeRedrawFlags(bits: u32) gdi.REDRAW_WINDOW_FLAGS {
    return @bitCast(bits);
}

pub fn styleBits(style: ui.WINDOW_STYLE) u32 {
    return @bitCast(style);
}

pub fn exStyleBits(style: ui.WINDOW_EX_STYLE) u32 {
    return @bitCast(style);
}

pub fn makeStyle(bits: u32) ui.WINDOW_STYLE {
    return @bitCast(bits);
}

pub fn makeExStyle(bits: u32) ui.WINDOW_EX_STYLE {
    return @bitCast(bits);
}

pub fn scrollMaskBits(mask: ui.SCROLLINFO_MASK) u32 {
    return @bitCast(mask);
}

pub fn makeScrollMask(bits: u32) ui.SCROLLINFO_MASK {
    return @bitCast(bits);
}

pub fn hrFailed(hr: foundation.HRESULT) bool {
    return hr < 0;
}

pub fn dupeSentinel(allocator: std.mem.Allocator, bytes: []const u8) ![:0]u8 {
    const out = try allocator.allocSentinel(u8, bytes.len, 0);
    @memcpy(out[0..bytes.len], bytes);
    return out;
}

pub fn fileExistsAbsolute(path: []const u8) bool {
    const file = std.fs.openFileAbsolute(path, .{}) catch return false;
    file.close();
    return true;
}

pub fn resolveRepoPathZ(allocator: std.mem.Allocator, relative_path: []const u8) ![:0]u8 {
    var exe_dir_buf: [std.fs.max_path_bytes]u8 = undefined;
    const exe_dir = try std.fs.selfExeDirPath(&exe_dir_buf);
    const prefixes = [_][]const u8{ "/../../", "/../", "/" };

    for (prefixes) |prefix| {
        const candidate = try std.fmt.allocPrint(allocator, "{s}{s}{s}", .{ exe_dir, prefix, relative_path });
        defer allocator.free(candidate);
        if (fileExistsAbsolute(candidate)) {
            return dupeSentinel(allocator, candidate);
        }
    }

    return error.FileNotFound;
}

pub fn releaseUnknown(ptr: anytype) void {
    if (ptr.*) |value| {
        _ = value.IUnknown.Release();
        ptr.* = null;
    }
}

pub fn fileDialogFlagBits(flags: dialogs.OPEN_FILENAME_FLAGS) u32 {
    return @bitCast(flags);
}

pub fn makeFileDialogFlags(bits: u32) dialogs.OPEN_FILENAME_FLAGS {
    return @bitCast(bits);
}
