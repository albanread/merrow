const std = @import("std");
const sqlite = @cImport({
    @cInclude("sqlite3.h");
});

pub const database_file_name = "merrow.db";

pub const schema_sql =
    \\CREATE TABLE IF NOT EXISTS ffm (
    \\    content_hash    TEXT PRIMARY KEY,
    \\    graph_type      INTEGER NOT NULL,
    \\    diagram_name    TEXT,
    \\    source_file     TEXT,
    \\    mermaid_source  TEXT NOT NULL,
    \\    graph_blob      BLOB NOT NULL,
    \\    canvas_width_cm REAL,
    \\    canvas_height_cm REAL,
    \\    created_at      TEXT NOT NULL DEFAULT (datetime('now')),
    \\    modified_at     TEXT NOT NULL DEFAULT (datetime('now'))
    \\);
    \\CREATE TABLE IF NOT EXISTS recent_files (
    \\    path            TEXT PRIMARY KEY,
    \\    last_opened     TEXT NOT NULL DEFAULT (datetime('now')),
    \\    diagram_index   INTEGER NOT NULL DEFAULT 0
    \\);
    \\CREATE TABLE IF NOT EXISTS preferences (
    \\    key             TEXT PRIMARY KEY,
    \\    value           TEXT
    \\);
;

pub fn defaultDatabasePath(allocator: std.mem.Allocator, library_dir: []const u8) ![]u8 {
    return std.fs.path.join(allocator, &.{ library_dir, database_file_name });
}

pub const DbError = error{
    OpenFailed,
    CloseFailed,
    PrepareFailed,
    BindFailed,
    StepFailed,
    SchemaFailed,
};

pub const FfmSaveRecord = struct {
    graph_type: u32,
    diagram_name: ?[]const u8 = null,
    source_file: ?[]const u8 = null,
    mermaid_source: []const u8,
    graph_blob: []const u8,
    canvas_width_cm: ?f64 = null,
    canvas_height_cm: ?f64 = null,
};

pub const FfmRecord = struct {
    graph_type: u32,
    diagram_name: ?[]u8,
    source_file: ?[]u8,
    mermaid_source: []u8,
    graph_blob: []u8,
    canvas_width_cm: ?f64,
    canvas_height_cm: ?f64,

    pub fn deinit(self: *FfmRecord, allocator: std.mem.Allocator) void {
        if (self.diagram_name) |value| allocator.free(value);
        if (self.source_file) |value| allocator.free(value);
        allocator.free(self.mermaid_source);
        allocator.free(self.graph_blob);
        self.* = undefined;
    }
};

pub const RecentFileRecord = struct {
    path: []u8,
    diagram_index: usize,

    pub fn deinit(self: *RecentFileRecord, allocator: std.mem.Allocator) void {
        allocator.free(self.path);
        self.* = undefined;
    }
};

pub const LibraryDb = struct {
    handle: *sqlite.sqlite3,

    pub fn open(path: []const u8) !LibraryDb {
        const z_path = try std.heap.c_allocator.dupeZ(u8, path);
        defer std.heap.c_allocator.free(z_path);

        var handle: ?*sqlite.sqlite3 = null;
        const rc = sqlite.sqlite3_open_v2(
            z_path.ptr,
            &handle,
            sqlite.SQLITE_OPEN_READWRITE | sqlite.SQLITE_OPEN_CREATE | sqlite.SQLITE_OPEN_NOMUTEX,
            null,
        );
        if (rc != sqlite.SQLITE_OK or handle == null) {
            if (handle) |db| _ = sqlite.sqlite3_close(db);
            return DbError.OpenFailed;
        }

        _ = sqlite.sqlite3_busy_timeout(handle, 1000);
        return .{ .handle = handle.? };
    }

    pub fn close(self: *LibraryDb) !void {
        if (sqlite.sqlite3_close(self.handle) != sqlite.SQLITE_OK) {
            return DbError.CloseFailed;
        }
        self.* = undefined;
    }

    pub fn ensureSchema(self: *LibraryDb) !void {
        if (sqlite.sqlite3_exec(self.handle, schema_sql.ptr, null, null, null) != sqlite.SQLITE_OK) {
            return DbError.SchemaFailed;
        }
    }

    pub fn saveFfm(self: *LibraryDb, content_hash: []const u8, record: FfmSaveRecord) !void {
        const sql =
            "INSERT INTO ffm (content_hash, graph_type, diagram_name, source_file, mermaid_source, graph_blob, canvas_width_cm, canvas_height_cm, created_at, modified_at) " ++
            "VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, datetime('now'), datetime('now')) " ++
            "ON CONFLICT(content_hash) DO UPDATE SET " ++
            "graph_type = excluded.graph_type, " ++
            "diagram_name = excluded.diagram_name, " ++
            "source_file = excluded.source_file, " ++
            "mermaid_source = excluded.mermaid_source, " ++
            "graph_blob = excluded.graph_blob, " ++
            "canvas_width_cm = excluded.canvas_width_cm, " ++
            "canvas_height_cm = excluded.canvas_height_cm, " ++
            "modified_at = datetime('now');";

        const statement = try prepare(self.handle, sql);
        defer _ = sqlite.sqlite3_finalize(statement);

        try bindText(statement, 1, content_hash);
        try bindInt(statement, 2, record.graph_type);
        try bindOptionalText(statement, 3, record.diagram_name);
        try bindOptionalText(statement, 4, record.source_file);
        try bindText(statement, 5, record.mermaid_source);
        try bindBlob(statement, 6, record.graph_blob);
        try bindOptionalDouble(statement, 7, record.canvas_width_cm);
        try bindOptionalDouble(statement, 8, record.canvas_height_cm);
        try stepDone(statement);
    }

    pub fn loadFfm(self: *LibraryDb, allocator: std.mem.Allocator, content_hash: []const u8) !?FfmRecord {
        const sql =
            "SELECT graph_blob, graph_type, diagram_name, source_file, mermaid_source, canvas_width_cm, canvas_height_cm " ++
            "FROM ffm WHERE content_hash = ?1 LIMIT 1;";

        const statement = try prepare(self.handle, sql);
        defer _ = sqlite.sqlite3_finalize(statement);

        try bindText(statement, 1, content_hash);

        const rc = sqlite.sqlite3_step(statement);
        if (rc == sqlite.SQLITE_DONE) return null;
        if (rc != sqlite.SQLITE_ROW) return DbError.StepFailed;

        return .{
            .graph_blob = try dupeColumnBlob(allocator, statement, 0),
            .graph_type = @intCast(sqlite.sqlite3_column_int(statement, 1)),
            .diagram_name = try dupeOptionalColumnText(allocator, statement, 2),
            .source_file = try dupeOptionalColumnText(allocator, statement, 3),
            .mermaid_source = try dupeColumnText(allocator, statement, 4),
            .canvas_width_cm = optionalColumnDouble(statement, 5),
            .canvas_height_cm = optionalColumnDouble(statement, 6),
        };
    }

    pub fn saveRecentFile(self: *LibraryDb, path: []const u8, diagram_index: usize) !void {
        const sql =
            "INSERT INTO recent_files (path, last_opened, diagram_index) VALUES (?1, datetime('now'), ?2) " ++
            "ON CONFLICT(path) DO UPDATE SET last_opened = datetime('now'), diagram_index = excluded.diagram_index;";

        const statement = try prepare(self.handle, sql);
        defer _ = sqlite.sqlite3_finalize(statement);

        try bindText(statement, 1, path);
        try bindInt(statement, 2, diagram_index);
        try stepDone(statement);
    }

    pub fn loadRecentFiles(self: *LibraryDb, allocator: std.mem.Allocator, limit: usize) ![]RecentFileRecord {
        const sql =
            "SELECT path, diagram_index " ++
            "FROM recent_files ORDER BY last_opened DESC LIMIT ?1;";

        const statement = try prepare(self.handle, sql);
        defer _ = sqlite.sqlite3_finalize(statement);

        try bindInt(statement, 1, limit);

        var records = std.ArrayList(RecentFileRecord){};
        defer records.deinit(allocator);

        while (true) {
            const rc = sqlite.sqlite3_step(statement);
            if (rc == sqlite.SQLITE_DONE) break;
            if (rc != sqlite.SQLITE_ROW) return DbError.StepFailed;

            try records.append(allocator, .{
                .path = try dupeColumnText(allocator, statement, 0),
                .diagram_index = @intCast(sqlite.sqlite3_column_int64(statement, 1)),
            });
        }

        return records.toOwnedSlice(allocator);
    }
};

fn prepare(handle: *sqlite.sqlite3, sql_text: []const u8) !*sqlite.sqlite3_stmt {
    var statement: ?*sqlite.sqlite3_stmt = null;
    const rc = sqlite.sqlite3_prepare_v2(handle, sql_text.ptr, @intCast(sql_text.len), &statement, null);
    if (rc != sqlite.SQLITE_OK or statement == null) return DbError.PrepareFailed;
    return statement.?;
}

fn bindInt(statement: *sqlite.sqlite3_stmt, index: c_int, value: anytype) !void {
    if (sqlite.sqlite3_bind_int64(statement, index, @intCast(value)) != sqlite.SQLITE_OK) {
        return DbError.BindFailed;
    }
}

fn bindText(statement: *sqlite.sqlite3_stmt, index: c_int, value: []const u8) !void {
    if (sqlite.sqlite3_bind_text(statement, index, value.ptr, @intCast(value.len), null) != sqlite.SQLITE_OK) {
        return DbError.BindFailed;
    }
}

fn bindOptionalText(statement: *sqlite.sqlite3_stmt, index: c_int, value: ?[]const u8) !void {
    if (value) |text| {
        try bindText(statement, index, text);
    } else if (sqlite.sqlite3_bind_null(statement, index) != sqlite.SQLITE_OK) {
        return DbError.BindFailed;
    }
}

fn bindOptionalDouble(statement: *sqlite.sqlite3_stmt, index: c_int, value: ?f64) !void {
    if (value) |number| {
        if (sqlite.sqlite3_bind_double(statement, index, number) != sqlite.SQLITE_OK) {
            return DbError.BindFailed;
        }
    } else if (sqlite.sqlite3_bind_null(statement, index) != sqlite.SQLITE_OK) {
        return DbError.BindFailed;
    }
}

fn bindBlob(statement: *sqlite.sqlite3_stmt, index: c_int, value: []const u8) !void {
    if (sqlite.sqlite3_bind_blob(statement, index, value.ptr, @intCast(value.len), null) != sqlite.SQLITE_OK) {
        return DbError.BindFailed;
    }
}

fn stepDone(statement: *sqlite.sqlite3_stmt) !void {
    if (sqlite.sqlite3_step(statement) != sqlite.SQLITE_DONE) {
        return DbError.StepFailed;
    }
}

fn dupeColumnText(allocator: std.mem.Allocator, statement: *sqlite.sqlite3_stmt, column: c_int) ![]u8 {
    const raw = sqlite.sqlite3_column_text(statement, column) orelse return allocator.alloc(u8, 0);
    const len: usize = @intCast(sqlite.sqlite3_column_bytes(statement, column));
    return allocator.dupe(u8, @as([*]const u8, @ptrCast(raw))[0..len]);
}

fn dupeOptionalColumnText(allocator: std.mem.Allocator, statement: *sqlite.sqlite3_stmt, column: c_int) !?[]u8 {
    const raw = sqlite.sqlite3_column_text(statement, column) orelse return null;
    const len: usize = @intCast(sqlite.sqlite3_column_bytes(statement, column));
    return try allocator.dupe(u8, @as([*]const u8, @ptrCast(raw))[0..len]);
}

fn optionalColumnDouble(statement: *sqlite.sqlite3_stmt, column: c_int) ?f64 {
    if (sqlite.sqlite3_column_type(statement, column) == sqlite.SQLITE_NULL) return null;
    return sqlite.sqlite3_column_double(statement, column);
}

fn dupeColumnBlob(allocator: std.mem.Allocator, statement: *sqlite.sqlite3_stmt, column: c_int) ![]u8 {
    const raw = sqlite.sqlite3_column_blob(statement, column);
    const len: usize = @intCast(sqlite.sqlite3_column_bytes(statement, column));
    if (len == 0) return allocator.alloc(u8, 0);
    if (raw == null) return DbError.StepFailed;
    return allocator.dupe(u8, @as([*]const u8, @ptrCast(raw))[0..len]);
}
