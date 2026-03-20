const std = @import("std");

pub const FontFamily = enum {
    lato,
    segoe_ui,
    arial,
    consolas,
};

pub fn fontFamilyDisplayName(family: FontFamily) []const u8 {
    return switch (family) {
        .lato => "Lato",
        .segoe_ui => "Segoe UI",
        .arial => "Arial",
        .consolas => "Consolas",
    };
}

pub const ProjectFontSettings = struct {
    font_family: FontFamily = .lato,
    node_label_size: f32 = 14.0,
    group_title_size: f32 = 12.0,
    edge_label_size: f32 = 11.0,

    pub fn sanitized(self: ProjectFontSettings) ProjectFontSettings {
        return .{
            .font_family = self.font_family,
            .node_label_size = clampFontSize(self.node_label_size),
            .group_title_size = clampFontSize(self.group_title_size),
            .edge_label_size = clampFontSize(self.edge_label_size),
        };
    }
};

pub fn loadProjectFontSettings(allocator: std.mem.Allocator, document_path: []const u8) !?ProjectFontSettings {
    const settings_path = try buildSettingsPath(allocator, document_path);
    defer allocator.free(settings_path);

    const file = std.fs.openFileAbsolute(settings_path, .{}) catch |err| switch (err) {
        error.FileNotFound => return null,
        else => return err,
    };
    defer file.close();

    const json_text = try file.readToEndAlloc(allocator, 64 * 1024);
    defer allocator.free(json_text);

    var parsed = try std.json.parseFromSlice(ProjectFontSettings, allocator, json_text, .{
        .ignore_unknown_fields = true,
    });
    defer parsed.deinit();

    return parsed.value.sanitized();
}

pub fn saveProjectFontSettings(allocator: std.mem.Allocator, document_path: []const u8, settings: ProjectFontSettings) !void {
    const settings_path = try buildSettingsPath(allocator, document_path);
    defer allocator.free(settings_path);

    const value = settings.sanitized();
    const payload = try std.fmt.allocPrint(
        allocator,
        "{{\n  \"font_family\": \"{s}\",\n  \"node_label_size\": {d:.1},\n  \"group_title_size\": {d:.1},\n  \"edge_label_size\": {d:.1}\n}}\n",
        .{ @tagName(value.font_family), value.node_label_size, value.group_title_size, value.edge_label_size },
    );
    defer allocator.free(payload);

    const file = try std.fs.createFileAbsolute(settings_path, .{ .truncate = true });
    defer file.close();
    try file.writeAll(payload);
}

fn buildSettingsPath(allocator: std.mem.Allocator, document_path: []const u8) ![]u8 {
    return std.fmt.allocPrint(allocator, "{s}.merrow.json", .{document_path});
}

fn clampFontSize(value: f32) f32 {
    return std.math.clamp(value, 6.0, 48.0);
}