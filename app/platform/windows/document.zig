const std = @import("std");
const win32 = @import("win32");
const library_db = @import("../../library_db.zig");
const common = @import("common.zig");
const constants = @import("constants.zig");

const dialogs = win32.ui.controls.dialogs;
const foundation = win32.foundation;
const shell = win32.ui.shell;
const com = win32.system.com;
const ui = win32.ui.windows_and_messaging;

pub const MerrowUserFolders = struct {
    root: []u8,
    generated: []u8,
    temp: []u8,
    assets: []u8,
    library: []u8,

    pub fn deinit(self: MerrowUserFolders, allocator: std.mem.Allocator) void {
        allocator.free(self.library);
        allocator.free(self.assets);
        allocator.free(self.temp);
        allocator.free(self.generated);
        allocator.free(self.root);
    }
};

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
    if (path) |value| {
        if (current_document_path.*) |existing| {
            if (std.mem.eql(u8, existing, value)) {
                updateWindowTitle(allocator, hwnd, current_document_path.*, is_document_dirty);
                return;
            }
        }
    } else if (current_document_path.* == null) {
        updateWindowTitle(allocator, hwnd, current_document_path.*, is_document_dirty);
        return;
    }

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
    const initial_path = if (save)
        if (current_document_path) |path|
            allocator.dupe(u8, path) catch null
        else
            defaultDocumentPath(allocator) catch null
    else
        null;
    defer if (initial_path) |path| allocator.free(path);

    const initial_dir = if (save) null else defaultLibraryOpenDirectory(allocator) catch null;
    defer if (initial_dir) |path| allocator.free(path);

    return chooseCustomPath(
        allocator,
        owner_hwnd,
        initial_path,
        initial_dir,
        save,
        constants.mermaid_dialog_filter,
        if (save) constants.save_dialog_title else constants.open_dialog_title,
        constants.default_extension,
    );
}

pub fn chooseCustomPath(
    allocator: std.mem.Allocator,
    owner_hwnd: ?foundation.HWND,
    initial_path: ?[]const u8,
    initial_dir: ?[]const u8,
    save: bool,
    filter: [*:0]const u8,
    title: [*:0]const u8,
    default_extension: [*:0]const u8,
) ?[]u8 {
    var path_buffer = [_]u8{0} ** 1024;
    if (initial_path) |path| {
        const copy_len = @min(path.len, path_buffer.len - 1);
        @memcpy(path_buffer[0..copy_len], path[0..copy_len]);
        path_buffer[copy_len] = 0;
    }

    const initial_dir_z = if (initial_dir) |path| allocator.dupeZ(u8, path) catch null else null;
    defer if (initial_dir_z) |path| allocator.free(path);

    var dialog = std.mem.zeroes(dialogs.OPENFILENAMEA);
    dialog.lStructSize = @sizeOf(dialogs.OPENFILENAMEA);
    dialog.hwndOwner = owner_hwnd;
    dialog.lpstrFilter = filter;
    dialog.lpstrFile = @ptrCast(path_buffer[0..].ptr);
    dialog.nMaxFile = path_buffer.len;
    dialog.lpstrInitialDir = if (initial_dir_z) |path| path.ptr else null;
    dialog.lpstrTitle = title;
    dialog.lpstrDefExt = default_extension;
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
    try ensureParentDirectoryExists(path);
    const file = try std.fs.createFileAbsolute(path, .{ .truncate = true });
    defer file.close();
    try file.writeAll(source);
}

pub fn getMerrowUserFolders(allocator: std.mem.Allocator) !MerrowUserFolders {
    const documents_root = getDocumentsFolder(allocator) catch try getHomeDocumentsFallback(allocator);
    defer allocator.free(documents_root);

    const merrow_root = try std.fs.path.join(allocator, &.{ documents_root, "Merrow" });
    errdefer allocator.free(merrow_root);
    const merrow_generated = try std.fs.path.join(allocator, &.{ merrow_root, "generated" });
    errdefer allocator.free(merrow_generated);
    const merrow_temp = try std.fs.path.join(allocator, &.{ merrow_root, "temp" });
    errdefer allocator.free(merrow_temp);
    const merrow_assets = try std.fs.path.join(allocator, &.{ merrow_root, "assets" });
    errdefer allocator.free(merrow_assets);
    const merrow_library = try std.fs.path.join(allocator, &.{ merrow_root, "library" });
    errdefer allocator.free(merrow_library);

    try ensureDirectoryExists(merrow_root);
    try ensureDirectoryExists(merrow_generated);
    try ensureDirectoryExists(merrow_temp);
    try ensureDirectoryExists(merrow_assets);
    try ensureDirectoryExists(merrow_library);

    return .{
        .root = merrow_root,
        .generated = merrow_generated,
        .temp = merrow_temp,
        .assets = merrow_assets,
        .library = merrow_library,
    };
}

pub fn defaultLibraryDbPath(allocator: std.mem.Allocator) ![]u8 {
    const folders = try getMerrowUserFolders(allocator);
    defer folders.deinit(allocator);
    return library_db.defaultDatabasePath(allocator, folders.library);
}

pub fn defaultLibraryOpenDirectory(allocator: std.mem.Allocator) ![]u8 {
    const folders = try getMerrowUserFolders(allocator);
    defer folders.deinit(allocator);
    return allocator.dupe(u8, folders.library);
}

pub fn defaultDocumentPath(allocator: std.mem.Allocator) ![]u8 {
    const folders = try getMerrowUserFolders(allocator);
    defer folders.deinit(allocator);
    return std.fs.path.join(allocator, &.{ folders.generated, "untitled.mmd" });
}

fn ensureParentDirectoryExists(path: []const u8) !void {
    const parent = std.fs.path.dirname(path) orelse return;
    try ensureDirectoryExists(parent);
}

fn ensureDirectoryExists(path: []const u8) !void {
    std.fs.makeDirAbsolute(path) catch |err| switch (err) {
        error.PathAlreadyExists => return,
        else => return err,
    };
}

fn getDocumentsFolder(allocator: std.mem.Allocator) ![]u8 {
    var wide_path: ?[*:0]u16 = null;
    const hr = shell.SHGetKnownFolderPath(&shell.FOLDERID_Documents, 0, null, @ptrCast(&wide_path));
    if (!common.hrFailed(hr) and wide_path != null) {
        defer com.CoTaskMemFree(wide_path);
        return std.unicode.utf16LeToUtf8Alloc(allocator, std.mem.span(wide_path.?));
    }

    const user_profile = try std.process.getEnvVarOwned(allocator, "USERPROFILE");
    defer allocator.free(user_profile);
    return std.fs.path.join(allocator, &.{ user_profile, "Documents" });
}

fn getHomeDocumentsFallback(allocator: std.mem.Allocator) ![]u8 {
    const home_drive = try std.process.getEnvVarOwned(allocator, "HOMEDRIVE");
    defer allocator.free(home_drive);
    const home_path = try std.process.getEnvVarOwned(allocator, "HOMEPATH");
    defer allocator.free(home_path);
    return std.fs.path.join(allocator, &.{ home_drive, home_path, "Documents" });
}
