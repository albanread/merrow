const std = @import("std");

/// RGBA color type
pub const Color = struct {
    r: u8,
    g: u8,
    b: u8,
    a: u8,

    pub fn init(r: u8, g: u8, b: u8) Color {
        return .{ .r = r, .g = g, .b = b, .a = 255 };
    }

    pub fn initAlpha(r: u8, g: u8, b: u8, a: u8) Color {
        return .{ .r = r, .g = g, .b = b, .a = a };
    }

    pub fn toArray(self: Color) [4]u8 {
        return .{ self.r, self.g, self.b, self.a };
    }

    pub fn fromHex(hex: u32) Color {
        return .{
            .r = @intCast((hex >> 16) & 0xFF),
            .g = @intCast((hex >> 8) & 0xFF),
            .b = @intCast(hex & 0xFF),
            .a = 255,
        };
    }
};

// Predefined color palette for diagram nodes
pub const Palette = struct {
    // Reds
    pub const RED = Color.fromHex(0xFF4444);
    pub const DARK_RED = Color.fromHex(0xCC0000);
    pub const LIGHT_RED = Color.fromHex(0xFF9999);

    // Oranges
    pub const ORANGE = Color.fromHex(0xFF8C00);
    pub const LIGHT_ORANGE = Color.fromHex(0xFFB347);
    pub const DARK_ORANGE = Color.fromHex(0xE67300);

    // Yellows
    pub const YELLOW = Color.fromHex(0xFFD700);
    pub const LIGHT_YELLOW = Color.fromHex(0xFFFF99);
    pub const DARK_YELLOW = Color.fromHex(0xCCAA00);

    // Greens
    pub const LIGHT_GREEN = Color.fromHex(0x90EE90);
    pub const GREEN = Color.fromHex(0x4CAF50);
    pub const DARK_GREEN = Color.fromHex(0x2E7D32);
    pub const FOREST_GREEN = Color.fromHex(0x228B22);

    // Blues
    pub const LIGHT_BLUE = Color.fromHex(0xC8DCFF);
    pub const BLUE = Color.fromHex(0x2196F3);
    pub const DARK_BLUE = Color.fromHex(0x1565C0);
    pub const NAVY = Color.fromHex(0x000080);

    // Cyans
    pub const CYAN = Color.fromHex(0x00CED1);
    pub const LIGHT_CYAN = Color.fromHex(0xE0FFFF);
    pub const DARK_CYAN = Color.fromHex(0x008B8B);

    // Purples
    pub const PURPLE = Color.fromHex(0x9C27B0);
    pub const LIGHT_PURPLE = Color.fromHex(0xE1BEE7);
    pub const DARK_PURPLE = Color.fromHex(0x6A1B9A);

    // Pinks
    pub const PINK = Color.fromHex(0xFF69B4);
    pub const LIGHT_PINK = Color.fromHex(0xFFB6C1);
    pub const DARK_PINK = Color.fromHex(0xC71585);

    // Grays
    pub const WHITE = Color.fromHex(0xFFFFFF);
    pub const LIGHT_GRAY = Color.fromHex(0xD3D3D3);
    pub const GRAY = Color.fromHex(0x808080);
    pub const DARK_GRAY = Color.fromHex(0x505050);
    pub const BLACK = Color.fromHex(0x000000);

    // Browns
    pub const BROWN = Color.fromHex(0x8B4513);
    pub const LIGHT_BROWN = Color.fromHex(0xD2B48C);
    pub const DARK_BROWN = Color.fromHex(0x5C4033);

    // Special colors for diagrams
    pub const SUCCESS = Color.fromHex(0x4CAF50); // Green
    pub const WARNING = Color.fromHex(0xFFB347); // Orange
    pub const ERROR = Color.fromHex(0xFF4444); // Red
    pub const INFO = Color.fromHex(0x2196F3); // Blue
};

/// Parse color name to RGBA array
pub fn parseColorName(name: []const u8) ?[4]u8 {
    const map = std.ComptimeStringMap(Color, .{
        // Reds
        .{ "red", Palette.RED },
        .{ "darkred", Palette.DARK_RED },
        .{ "lightred", Palette.LIGHT_RED },

        // Oranges
        .{ "orange", Palette.ORANGE },
        .{ "lightorange", Palette.LIGHT_ORANGE },
        .{ "darkorange", Palette.DARK_ORANGE },

        // Yellows
        .{ "yellow", Palette.YELLOW },
        .{ "lightyellow", Palette.LIGHT_YELLOW },
        .{ "darkyellow", Palette.DARK_YELLOW },

        // Greens
        .{ "lightgreen", Palette.LIGHT_GREEN },
        .{ "green", Palette.GREEN },
        .{ "darkgreen", Palette.DARK_GREEN },
        .{ "forestgreen", Palette.FOREST_GREEN },

        // Blues
        .{ "lightblue", Palette.LIGHT_BLUE },
        .{ "blue", Palette.BLUE },
        .{ "darkblue", Palette.DARK_BLUE },
        .{ "navy", Palette.NAVY },

        // Cyans
        .{ "cyan", Palette.CYAN },
        .{ "lightcyan", Palette.LIGHT_CYAN },
        .{ "darkcyan", Palette.DARK_CYAN },

        // Purples
        .{ "purple", Palette.PURPLE },
        .{ "lightpurple", Palette.LIGHT_PURPLE },
        .{ "darkpurple", Palette.DARK_PURPLE },

        // Pinks
        .{ "pink", Palette.PINK },
        .{ "lightpink", Palette.LIGHT_PINK },
        .{ "darkpink", Palette.DARK_PINK },

        // Grays
        .{ "white", Palette.WHITE },
        .{ "lightgray", Palette.LIGHT_GRAY },
        .{ "gray", Palette.GRAY },
        .{ "darkgray", Palette.DARK_GRAY },
        .{ "black", Palette.BLACK },

        // Browns
        .{ "brown", Palette.BROWN },
        .{ "lightbrown", Palette.LIGHT_BROWN },
        .{ "darkbrown", Palette.DARK_BROWN },

        // Semantic colors
        .{ "success", Palette.SUCCESS },
        .{ "warning", Palette.WARNING },
        .{ "error", Palette.ERROR },
        .{ "info", Palette.INFO },
    });

    if (map.get(name)) |color| {
        return color.toArray();
    }
    return null;
}

/// Parse hex color string (e.g., "#FF0000" or "FF0000")
pub fn parseHexColor(hex_str: []const u8) ?[4]u8 {
    var hex = hex_str;

    // Skip leading '#' if present
    if (hex.len > 0 and hex[0] == '#') {
        hex = hex[1..];
    }

    if (hex.len != 6) return null;

    var value: u32 = 0;
    for (hex) |c| {
        value *= 16;
        if (c >= '0' and c <= '9') {
            value += c - '0';
        } else if (c >= 'a' and c <= 'f') {
            value += 10 + c - 'a';
        } else if (c >= 'A' and c <= 'F') {
            value += 10 + c - 'A';
        } else {
            return null;
        }
    }

    return Color.fromHex(value).toArray();
}

/// Lighten a color by a factor (0.0 to 1.0)
pub fn lighten(color: [4]u8, factor: f32) [4]u8 {
    const f = @min(1.0, @max(0.0, factor));
    return .{
        @intFromFloat(@min(255.0, @as(f32, @floatFromInt(color[0])) + (255.0 - @as(f32, @floatFromInt(color[0]))) * f)),
        @intFromFloat(@min(255.0, @as(f32, @floatFromInt(color[1])) + (255.0 - @as(f32, @floatFromInt(color[1]))) * f)),
        @intFromFloat(@min(255.0, @as(f32, @floatFromInt(color[2])) + (255.0 - @as(f32, @floatFromInt(color[2]))) * f)),
        color[3],
    };
}

/// Darken a color by a factor (0.0 to 1.0)
pub fn darken(color: [4]u8, factor: f32) [4]u8 {
    const f = @min(1.0, @max(0.0, factor));
    return .{
        @intFromFloat(@as(f32, @floatFromInt(color[0])) * (1.0 - f)),
        @intFromFloat(@as(f32, @floatFromInt(color[1])) * (1.0 - f)),
        @intFromFloat(@as(f32, @floatFromInt(color[2])) * (1.0 - f)),
        color[3],
    };
}

test "color parsing" {
    const red = parseColorName("red");
    try std.testing.expect(red != null);
    try std.testing.expectEqual(@as(u8, 255), red.?[0]); // R

    const hex_blue = parseHexColor("#0000FF");
    try std.testing.expect(hex_blue != null);
    try std.testing.expectEqual(@as(u8, 0), hex_blue.?[0]); // R
    try std.testing.expectEqual(@as(u8, 0), hex_blue.?[1]); // G
    try std.testing.expectEqual(@as(u8, 255), hex_blue.?[2]); // B
}

test "color manipulation" {
    const red = Palette.RED.toArray();
    const lightened = lighten(red, 0.5);
    try std.testing.expect(lightened[0] > red[0]);

    const darkened = darken(red, 0.5);
    try std.testing.expect(darkened[0] < red[0]);
}
