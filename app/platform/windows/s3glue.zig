const std = @import("std");
const win32 = @import("win32");

const windows_common = @import("common.zig");
const loader = win32.system.library_loader;

pub const ModuleHandle = @TypeOf(loader.LoadLibraryA("Riched20.dll").?);

pub const Status = u32;
pub const Library = ?*anyopaque;
pub const Client = ?*anyopaque;

pub const abi_version: u32 = 1;
pub const ok: Status = 0;

pub const CredentialMode = enum(u32) {
    default = 0,
    static = 1,
    profile = 2,
};

pub const RuntimeOptions = extern struct {
    abi_version: u32,
    flags: u32,
};

pub const ClientOptions = extern struct {
    utf8_region: ?[*:0]const u8,
    utf8_endpoint_override: ?[*:0]const u8,
    utf8_profile_name: ?[*:0]const u8,
    utf8_access_key_id: ?[*:0]const u8,
    utf8_secret_access_key: ?[*:0]const u8,
    utf8_session_token: ?[*:0]const u8,
    credential_mode: CredentialMode,
    verify_ssl: u32,
    connect_timeout_ms: u32,
    request_timeout_ms: u32,
    flags: u32,
};

pub const ListOptions = extern struct {
    utf8_prefix: ?[*:0]const u8,
    utf8_delimiter: ?[*:0]const u8,
    utf8_continuation_token: ?[*:0]const u8,
    max_keys: u32,
    flags: u32,
};

pub const PutOptions = extern struct {
    utf8_content_type: ?[*:0]const u8,
    utf8_cache_control: ?[*:0]const u8,
    flags: u32,
};

pub const ListEntry = extern struct {
    utf8_key: ?[*:0]const u8,
    utf8_etag: ?[*:0]const u8,
    size_bytes: u64,
    last_modified_epoch_seconds: i64,
};

pub const ListResult = extern struct {
    object_count: u32,
    objects: ?[*]ListEntry,
    is_truncated: u32,
    utf8_next_continuation_token: ?[*:0]const u8,
};

pub const ErrorInfo = extern struct {
    status: Status,
    http_status: i32,
    aws_error: u32,
    utf8_message: ?[*:0]const u8,
    utf8_function: ?[*:0]const u8,
};

pub const Error = error{
    DllNotFound,
    MissingExports,
};

pub const SessionError = Error || error{
    OutOfMemory,
    MissingProfileName,
    MissingStaticCredentials,
    CreateLibraryFailed,
    CreateClientFailed,
};

pub const StaticCredentials = struct {
    access_key_id: []const u8,
    secret_access_key: []const u8,
    session_token: ?[]const u8 = null,
};

pub const Credentials = union(enum) {
    default,
    profile: []const u8,
    static: StaticCredentials,
};

pub const SessionConfig = struct {
    region: ?[]const u8 = null,
    endpoint_override: ?[]const u8 = null,
    credentials: Credentials = .default,
    verify_ssl: bool = true,
    connect_timeout_ms: u32 = 0,
    request_timeout_ms: u32 = 0,
    flags: u32 = 0,
};

pub const Session = struct {
    loaded: Loaded,
    library: Library,
    client: Client,

    pub fn deinit(self: *Session) void {
        if (self.client != null) {
            _ = self.loaded.api.destroy_client(self.client);
        }
        if (self.library != null) {
            _ = self.loaded.api.destroy_library(self.library);
        }
        self.loaded.unload();
    }
};

const OwnedClientOptions = struct {
    region: ?[:0]u8 = null,
    endpoint_override: ?[:0]u8 = null,
    profile_name: ?[:0]u8 = null,
    access_key_id: ?[:0]u8 = null,
    secret_access_key: ?[:0]u8 = null,
    session_token: ?[:0]u8 = null,
    options: ClientOptions,

    fn init(allocator: std.mem.Allocator, config: SessionConfig) SessionError!OwnedClientOptions {
        var owned = OwnedClientOptions{
            .options = .{
                .utf8_region = null,
                .utf8_endpoint_override = null,
                .utf8_profile_name = null,
                .utf8_access_key_id = null,
                .utf8_secret_access_key = null,
                .utf8_session_token = null,
                .credential_mode = .default,
                .verify_ssl = if (config.verify_ssl) 1 else 0,
                .connect_timeout_ms = config.connect_timeout_ms,
                .request_timeout_ms = config.request_timeout_ms,
                .flags = config.flags,
            },
        };
        errdefer owned.deinit(allocator);

        owned.region = try dupeOptionalZ(allocator, config.region);
        owned.endpoint_override = try dupeOptionalZ(allocator, config.endpoint_override);

        switch (config.credentials) {
            .default => {
                owned.options.credential_mode = .default;
            },
            .profile => |profile_name| {
                if (profile_name.len == 0) return error.MissingProfileName;
                owned.profile_name = try dupeOptionalZ(allocator, profile_name);
                owned.options.credential_mode = .profile;
            },
            .static => |credentials| {
                if (credentials.access_key_id.len == 0 or credentials.secret_access_key.len == 0) {
                    return error.MissingStaticCredentials;
                }
                owned.access_key_id = try dupeOptionalZ(allocator, credentials.access_key_id);
                owned.secret_access_key = try dupeOptionalZ(allocator, credentials.secret_access_key);
                owned.session_token = try dupeOptionalZ(allocator, credentials.session_token);
                owned.options.credential_mode = .static;
            },
        }

        owned.refreshPointers();
        return owned;
    }

    fn deinit(self: *OwnedClientOptions, allocator: std.mem.Allocator) void {
        freeOptionalZ(allocator, &self.region);
        freeOptionalZ(allocator, &self.endpoint_override);
        freeOptionalZ(allocator, &self.profile_name);
        wipeAndFreeOptionalZ(allocator, &self.access_key_id);
        wipeAndFreeOptionalZ(allocator, &self.secret_access_key);
        wipeAndFreeOptionalZ(allocator, &self.session_token);
        self.* = undefined;
    }

    fn refreshPointers(self: *OwnedClientOptions) void {
        self.options.utf8_region = optionalPtr(self.region);
        self.options.utf8_endpoint_override = optionalPtr(self.endpoint_override);
        self.options.utf8_profile_name = optionalPtr(self.profile_name);
        self.options.utf8_access_key_id = optionalPtr(self.access_key_id);
        self.options.utf8_secret_access_key = optionalPtr(self.secret_access_key);
        self.options.utf8_session_token = optionalPtr(self.session_token);
    }
};

const GetAbiVersionFn = *const fn () callconv(.c) u32;
const CreateLibraryFn = *const fn (options: ?*const RuntimeOptions, out_library: *Library) callconv(.c) Status;
const DestroyLibraryFn = *const fn (library: Library) callconv(.c) Status;
const CreateClientFn = *const fn (library: Library, options: ?*const ClientOptions, out_client: *Client) callconv(.c) Status;
const DestroyClientFn = *const fn (client: Client) callconv(.c) Status;
const ListObjectsFn = *const fn (client: Client, utf8_bucket: [*:0]const u8, options: ?*const ListOptions, out_result: *ListResult) callconv(.c) Status;
const FreeListResultFn = *const fn (result: *ListResult) callconv(.c) Status;
const PutObjectFileFn = *const fn (client: Client, utf8_bucket: [*:0]const u8, utf8_key: [*:0]const u8, utf8_local_path: [*:0]const u8, options: ?*const PutOptions) callconv(.c) Status;
const GetObjectFileFn = *const fn (client: Client, utf8_bucket: [*:0]const u8, utf8_key: [*:0]const u8, utf8_local_path: [*:0]const u8) callconv(.c) Status;
const DeleteObjectFn = *const fn (client: Client, utf8_bucket: [*:0]const u8, utf8_key: [*:0]const u8) callconv(.c) Status;
const GetLastErrorFn = *const fn (library: Library, out_error: *ErrorInfo) callconv(.c) Status;
const ClearLastErrorFn = *const fn (library: Library) callconv(.c) Status;

pub const Api = struct {
    get_abi_version: GetAbiVersionFn,
    create_library: CreateLibraryFn,
    destroy_library: DestroyLibraryFn,
    create_client: CreateClientFn,
    destroy_client: DestroyClientFn,
    list_objects: ListObjectsFn,
    free_list_result: FreeListResultFn,
    put_object_file: PutObjectFileFn,
    get_object_file: GetObjectFileFn,
    delete_object: DeleteObjectFn,
    get_last_error: GetLastErrorFn,
    clear_last_error: ClearLastErrorFn,
};

pub const Loaded = struct {
    module: ModuleHandle,
    api: Api,

    pub fn unload(self: *Loaded) void {
        _ = loader.FreeLibrary(self.module);
        self.* = undefined;
    }
};

pub fn defaultRuntimeOptions() RuntimeOptions {
    return .{
        .abi_version = abi_version,
        .flags = 0,
    };
}

pub fn openSession(allocator: std.mem.Allocator, config: SessionConfig) SessionError!Session {
    var loaded = try load(allocator);
    errdefer loaded.unload();

    var runtime_options = defaultRuntimeOptions();
    var library: Library = null;
    if (loaded.api.create_library(&runtime_options, &library) != ok or library == null) {
        return error.CreateLibraryFailed;
    }
    errdefer _ = loaded.api.destroy_library(library);

    var owned_options = try OwnedClientOptions.init(allocator, config);
    defer owned_options.deinit(allocator);

    var client: Client = null;
    if (loaded.api.create_client(library, &owned_options.options, &client) != ok or client == null) {
        return error.CreateClientFailed;
    }

    return .{
        .loaded = loaded,
        .library = library,
        .client = client,
    };
}

pub fn load(allocator: std.mem.Allocator) Error!Loaded {
    const module = loadModule(allocator) orelse return error.DllNotFound;
    errdefer _ = loader.FreeLibrary(module);

    const api = Api{
        .get_abi_version = loadProc(GetAbiVersionFn, module, "s3g_get_abi_version") orelse return error.MissingExports,
        .create_library = loadProc(CreateLibraryFn, module, "s3g_create_library") orelse return error.MissingExports,
        .destroy_library = loadProc(DestroyLibraryFn, module, "s3g_destroy_library") orelse return error.MissingExports,
        .create_client = loadProc(CreateClientFn, module, "s3g_create_client") orelse return error.MissingExports,
        .destroy_client = loadProc(DestroyClientFn, module, "s3g_destroy_client") orelse return error.MissingExports,
        .list_objects = loadProc(ListObjectsFn, module, "s3g_list_objects") orelse return error.MissingExports,
        .free_list_result = loadProc(FreeListResultFn, module, "s3g_free_list_result") orelse return error.MissingExports,
        .put_object_file = loadProc(PutObjectFileFn, module, "s3g_put_object_file") orelse return error.MissingExports,
        .get_object_file = loadProc(GetObjectFileFn, module, "s3g_get_object_file") orelse return error.MissingExports,
        .delete_object = loadProc(DeleteObjectFn, module, "s3g_delete_object") orelse return error.MissingExports,
        .get_last_error = loadProc(GetLastErrorFn, module, "s3g_get_last_error") orelse return error.MissingExports,
        .clear_last_error = loadProc(ClearLastErrorFn, module, "s3g_clear_last_error") orelse return error.MissingExports,
    };

    return .{
        .module = module,
        .api = api,
    };
}

fn loadModule(allocator: std.mem.Allocator) ?ModuleHandle {
    if (loader.LoadLibraryA("s3glue.dll")) |module| return module;

    const candidates = [_][]const u8{
        "s3glue/build/Debug/s3glue.dll",
        "s3glue/build/Release/s3glue.dll",
        "s3glue/build/RelWithDebInfo/s3glue.dll",
        "s3glue/build/MinSizeRel/s3glue.dll",
    };

    for (candidates) |relative_path| {
        const dll_path = windows_common.resolveRepoPathZ(allocator, relative_path) catch continue;
        defer allocator.free(dll_path);
        if (loader.LoadLibraryA(dll_path.ptr)) |module| return module;
    }

    return null;
}

fn dupeOptionalZ(allocator: std.mem.Allocator, value: ?[]const u8) SessionError!?[:0]u8 {
    const text = value orelse return null;
    const out = allocator.allocSentinel(u8, text.len, 0) catch return error.OutOfMemory;
    @memcpy(out[0..text.len], text);
    return out;
}

fn freeOptionalZ(allocator: std.mem.Allocator, value: *?[:0]u8) void {
    if (value.*) |buffer| {
        allocator.free(buffer);
        value.* = null;
    }
}

fn wipeAndFreeOptionalZ(allocator: std.mem.Allocator, value: *?[:0]u8) void {
    if (value.*) |buffer| {
        volatileZero(buffer[0..buffer.len]);
        allocator.free(buffer);
        value.* = null;
    }
}

fn optionalPtr(value: ?[:0]u8) ?[*:0]const u8 {
    return if (value) |buffer| buffer.ptr else null;
}

fn volatileZero(secret: []u8) void {
    const bytes: [*]volatile u8 = @ptrCast(secret.ptr);
    var index: usize = 0;
    while (index < secret.len) : (index += 1) {
        bytes[index] = 0;
    }
}

fn loadProc(comptime Proc: type, module: ModuleHandle, name: [*:0]const u8) ?Proc {
    const symbol = loader.GetProcAddress(module, name) orelse return null;
    return @ptrCast(symbol);
}

test "default runtime options use current ABI" {
    const options = defaultRuntimeOptions();
    try std.testing.expectEqual(abi_version, options.abi_version);
    try std.testing.expectEqual(@as(u32, 0), options.flags);
}

test "owned client options encode static credentials" {
    const allocator = std.testing.allocator;
    var owned = try OwnedClientOptions.init(allocator, .{
        .region = "us-east-1",
        .endpoint_override = "https://s3.amazonaws.com",
        .credentials = .{ .static = .{
            .access_key_id = "AKIATESTKEY",
            .secret_access_key = "top-secret",
            .session_token = "session-token",
        } },
        .verify_ssl = false,
        .connect_timeout_ms = 1500,
        .request_timeout_ms = 2500,
        .flags = 99,
    });
    defer owned.deinit(allocator);

    try std.testing.expectEqual(CredentialMode.static, owned.options.credential_mode);
    try std.testing.expectEqual(@as(u32, 0), owned.options.verify_ssl);
    try std.testing.expectEqual(@as(u32, 1500), owned.options.connect_timeout_ms);
    try std.testing.expectEqual(@as(u32, 2500), owned.options.request_timeout_ms);
    try std.testing.expectEqual(@as(u32, 99), owned.options.flags);
    try std.testing.expectEqualStrings("us-east-1", std.mem.sliceTo(owned.options.utf8_region.?, 0));
    try std.testing.expectEqualStrings("https://s3.amazonaws.com", std.mem.sliceTo(owned.options.utf8_endpoint_override.?, 0));
    try std.testing.expectEqualStrings("AKIATESTKEY", std.mem.sliceTo(owned.options.utf8_access_key_id.?, 0));
    try std.testing.expectEqualStrings("top-secret", std.mem.sliceTo(owned.options.utf8_secret_access_key.?, 0));
    try std.testing.expectEqualStrings("session-token", std.mem.sliceTo(owned.options.utf8_session_token.?, 0));
}

test "owned client options reject empty static credentials" {
    const allocator = std.testing.allocator;
    try std.testing.expectError(error.MissingStaticCredentials, OwnedClientOptions.init(allocator, .{
        .credentials = .{ .static = .{
            .access_key_id = "",
            .secret_access_key = "",
        } },
    }));
}
