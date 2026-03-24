const std = @import("std");
const win32 = @import("win32");

const foundation = win32.foundation;

pub const generic_credential_max_bytes: usize = 5 * 512;

pub const CredentialError = error{
    EmptyTargetName,
    CredentialTooLarge,
    NotFound,
    StoreFailed,
    LoadFailed,
    DeleteFailed,
    OutOfMemory,
};

const cred_type_generic: u32 = 1;
const cred_persist_local_machine: u32 = 2;
const error_not_found: u32 = 1168;
const error_no_such_logon_session: u32 = 1312;

const CREDENTIAL_ATTRIBUTEA = extern struct {
    Keyword: [*c]u8,
    Flags: u32,
    ValueSize: u32,
    Value: [*c]u8,
};

const CREDENTIALA = extern struct {
    Flags: u32,
    Type: u32,
    TargetName: [*c]u8,
    Comment: [*c]u8,
    LastWritten: foundation.FILETIME,
    CredentialBlobSize: u32,
    CredentialBlob: [*c]u8,
    Persist: u32,
    AttributeCount: u32,
    Attributes: ?*CREDENTIAL_ATTRIBUTEA,
    TargetAlias: [*c]u8,
    UserName: [*c]u8,
};

extern "advapi32" fn CredWriteA(credential: *const CREDENTIALA, flags: u32) callconv(.winapi) foundation.BOOL;
extern "advapi32" fn CredReadA(target_name: [*:0]const u8, credential_type: u32, flags: u32, out_credential: *?*CREDENTIALA) callconv(.winapi) foundation.BOOL;
extern "advapi32" fn CredDeleteA(target_name: [*:0]const u8, credential_type: u32, flags: u32) callconv(.winapi) foundation.BOOL;
extern "advapi32" fn CredFree(buffer: ?*anyopaque) callconv(.winapi) void;
extern "kernel32" fn GetLastError() callconv(.winapi) u32;

fn dupeZ(allocator: std.mem.Allocator, text: []const u8) ![:0]u8 {
    const out = try allocator.allocSentinel(u8, text.len, 0);
    @memcpy(out[0..text.len], text);
    return out;
}

pub fn storeString(allocator: std.mem.Allocator, target_name: []const u8, credential_text: []const u8) CredentialError!void {
    if (target_name.len == 0) return error.EmptyTargetName;
    if (credential_text.len > generic_credential_max_bytes) return error.CredentialTooLarge;

    const target_name_z = dupeZ(allocator, target_name) catch return error.OutOfMemory;
    defer allocator.free(target_name_z);

    var credential = std.mem.zeroes(CREDENTIALA);
    credential.Type = cred_type_generic;
    credential.TargetName = @ptrCast(target_name_z.ptr);
    credential.CredentialBlobSize = @intCast(credential_text.len);
    credential.CredentialBlob = if (credential_text.len > 0) @ptrCast(@constCast(credential_text.ptr)) else null;
    credential.Persist = cred_persist_local_machine;

    if (CredWriteA(&credential, 0) == 0) return error.StoreFailed;
}

pub fn loadString(allocator: std.mem.Allocator, target_name: []const u8) CredentialError![]u8 {
    if (target_name.len == 0) return error.EmptyTargetName;

    const target_name_z = dupeZ(allocator, target_name) catch return error.OutOfMemory;
    defer allocator.free(target_name_z);

    var credential_ptr: ?*CREDENTIALA = null;
    if (CredReadA(target_name_z.ptr, cred_type_generic, 0, &credential_ptr) == 0) {
        const last_error = GetLastError();
        if (last_error == error_not_found or last_error == error_no_such_logon_session) {
            return error.NotFound;
        }
        return error.LoadFailed;
    }
    defer CredFree(credential_ptr);

    const credential = credential_ptr orelse return error.LoadFailed;
    const blob_len: usize = credential.CredentialBlobSize;
    if (blob_len == 0) return allocator.alloc(u8, 0) catch error.OutOfMemory;
    if (credential.CredentialBlob == null) return error.LoadFailed;

    const secret = allocator.alloc(u8, blob_len) catch return error.OutOfMemory;
    errdefer allocator.free(secret);
    @memcpy(secret, credential.CredentialBlob[0..blob_len]);
    return secret;
}

pub fn deleteString(allocator: std.mem.Allocator, target_name: []const u8) CredentialError!void {
    if (target_name.len == 0) return error.EmptyTargetName;

    const target_name_z = dupeZ(allocator, target_name) catch return error.OutOfMemory;
    defer allocator.free(target_name_z);

    if (CredDeleteA(target_name_z.ptr, cred_type_generic, 0) == 0) {
        const last_error = GetLastError();
        if (last_error == error_not_found or last_error == error_no_such_logon_session) {
            return error.NotFound;
        }
        return error.DeleteFailed;
    }
}

pub fn wipeAndFree(allocator: std.mem.Allocator, secret: []u8) void {
    volatileZero(secret);
    allocator.free(secret);
}

fn volatileZero(secret: []u8) void {
    const bytes: [*]volatile u8 = @ptrCast(secret.ptr);
    var index: usize = 0;
    while (index < secret.len) : (index += 1) {
        bytes[index] = 0;
    }
}

test "volatileZero clears bytes" {
    var bytes = [_]u8{ 1, 2, 3 };
    volatileZero(bytes[0..]);
    try std.testing.expectEqualSlices(u8, &[_]u8{ 0, 0, 0 }, bytes[0..]);
}

test "credential manager roundtrip stores and retrieves string" {
    const allocator = std.testing.allocator;
    const target_name = try std.fmt.allocPrint(
        allocator,
        "Merrow/Test/Credentials/{d}",
        .{std.time.nanoTimestamp()},
    );
    defer allocator.free(target_name);

    deleteString(allocator, target_name) catch |err| switch (err) {
        error.NotFound => {},
        else => return err,
    };
    defer deleteString(allocator, target_name) catch {};

    const credential_text = "Server=tcp:db01;Database=Merrow;User ID=merrow_user;AuthTag=test-credential;Encrypt=true";

    try storeString(allocator, target_name, credential_text);

    const loaded = try loadString(allocator, target_name);
    defer wipeAndFree(allocator, loaded);

    try std.testing.expectEqualStrings(credential_text, loaded);

    try deleteString(allocator, target_name);
    try std.testing.expectError(error.NotFound, loadString(allocator, target_name));
}
