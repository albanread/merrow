const std = @import("std");

pub const EdgeKey = struct {
    v: []const u8,
    w: []const u8,
    name: ?[]const u8 = null,
};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Attempt to initialize an ArrayList of EdgeKey
    var list = std.ArrayList(EdgeKey).init(allocator);
    defer list.deinit();

    try list.append(.{ .v = "a", .w = "b" });

    std.debug.print("Successfully created list with {d} items\n", .{list.items.len});
}
