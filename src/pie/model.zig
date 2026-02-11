//! Pie chart data model.
//!
//! Represents all the elements of a Mermaid pie chart:
//! title, sections (label + value), and the showData flag.

const std = @import("std");

/// A single slice of the pie chart.
pub const Section = struct {
    /// Display label for the slice.
    label: []const u8,
    label_owned: bool = false,
    /// Numeric value (must be >= 0).
    value: f64,

    pub fn deinit(self: *Section, allocator: std.mem.Allocator) void {
        if (self.label_owned) {
            allocator.free(self.label);
        }
    }
};

/// Complete pie chart data parsed from Mermaid syntax.
pub const PieData = struct {
    /// Optional diagram title (displayed above the pie).
    title: ?[]const u8 = null,
    title_owned: bool = false,

    /// Whether to show raw data values alongside labels in the legend.
    show_data: bool = false,

    /// Pie sections in declaration order.
    sections: std.ArrayListUnmanaged(Section) = .{},

    /// Allocator used for owned strings and the section list.
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) PieData {
        return .{
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *PieData) void {
        if (self.title_owned) {
            if (self.title) |t| self.allocator.free(t);
        }
        for (self.sections.items) |*sec| {
            var s = sec.*;
            s.deinit(self.allocator);
        }
        self.sections.deinit(self.allocator);
    }

    /// Add a section. The label is duped (owned by PieData).
    pub fn addSection(self: *PieData, label: []const u8, value: f64) !void {
        // Reject negative values.
        if (value < 0) return error.NegativeValue;

        // Ignore duplicate labels (keep first occurrence, like mermaid.js).
        for (self.sections.items) |sec| {
            if (std.mem.eql(u8, sec.label, label)) return;
        }

        const owned_label = try self.allocator.dupe(u8, label);
        try self.sections.append(self.allocator, .{
            .label = owned_label,
            .label_owned = true,
            .value = value,
        });
    }

    /// Set the diagram title. The string is duped (owned).
    pub fn setTitle(self: *PieData, title: []const u8) !void {
        if (self.title_owned) {
            if (self.title) |t| self.allocator.free(t);
        }
        self.title = try self.allocator.dupe(u8, title);
        self.title_owned = true;
    }

    /// Compute the total value across all sections.
    pub fn total(self: *const PieData) f64 {
        var sum: f64 = 0;
        for (self.sections.items) |sec| {
            sum += sec.value;
        }
        return sum;
    }

    /// Return the number of sections.
    pub fn sectionCount(self: *const PieData) usize {
        return self.sections.items.len;
    }

    /// Get the percentage for a given section index (0–100).
    pub fn percentage(self: *const PieData, index: usize) f64 {
        const t = self.total();
        if (t <= 0) return 0;
        return (self.sections.items[index].value / t) * 100.0;
    }
};

// -----------------------------------------------------------------------
// Default pie color palette (matches mermaid.js default theme)
// -----------------------------------------------------------------------

/// Mermaid.js default pie chart colors (8 colors, cycled for >8 slices).
pub const pie_colors: [8][4]u8 = .{
    .{ 78, 121, 167, 255 }, // #4e79a7  steel blue
    .{ 242, 142, 44, 255 }, // #f28e2c  orange
    .{ 225, 87, 89, 255 }, // #e15759  red
    .{ 118, 183, 178, 255 }, // #76b7b2  teal
    .{ 89, 161, 79, 255 }, // #59a14f  green
    .{ 237, 201, 73, 255 }, // #edc949  yellow
    .{ 175, 122, 161, 255 }, // #af7aa1  purple
    .{ 255, 157, 167, 255 }, // #ff9da7  pink
};

/// Return the color for a given slice index (wraps around the palette).
pub fn sliceColor(index: usize) [4]u8 {
    return pie_colors[index % pie_colors.len];
}

// -----------------------------------------------------------------------
// Tests
// -----------------------------------------------------------------------

test "pie: basic model operations" {
    const allocator = std.testing.allocator;
    var pie = PieData.init(allocator);
    defer pie.deinit();

    try pie.addSection("Dogs", 40);
    try pie.addSection("Cats", 35);
    try pie.addSection("Birds", 25);

    try std.testing.expectEqual(@as(usize, 3), pie.sectionCount());
    try std.testing.expectApproxEqAbs(@as(f64, 100.0), pie.total(), 0.001);
    try std.testing.expectApproxEqAbs(@as(f64, 40.0), pie.percentage(0), 0.001);
    try std.testing.expectApproxEqAbs(@as(f64, 35.0), pie.percentage(1), 0.001);
    try std.testing.expectApproxEqAbs(@as(f64, 25.0), pie.percentage(2), 0.001);
}

test "pie: set title" {
    const allocator = std.testing.allocator;
    var pie = PieData.init(allocator);
    defer pie.deinit();

    try pie.setTitle("My Chart");
    try std.testing.expect(pie.title != null);
    try std.testing.expectEqualStrings("My Chart", pie.title.?);
}

test "pie: duplicate labels ignored" {
    const allocator = std.testing.allocator;
    var pie = PieData.init(allocator);
    defer pie.deinit();

    try pie.addSection("A", 10);
    try pie.addSection("A", 20); // should be ignored
    try std.testing.expectEqual(@as(usize, 1), pie.sectionCount());
    try std.testing.expectApproxEqAbs(@as(f64, 10.0), pie.sections.items[0].value, 0.001);
}

test "pie: negative value rejected" {
    const allocator = std.testing.allocator;
    var pie = PieData.init(allocator);
    defer pie.deinit();

    const result = pie.addSection("Bad", -5);
    try std.testing.expectError(error.NegativeValue, result);
}

test "pie: show_data flag" {
    const allocator = std.testing.allocator;
    var pie = PieData.init(allocator);
    defer pie.deinit();

    try std.testing.expect(!pie.show_data);
    pie.show_data = true;
    try std.testing.expect(pie.show_data);
}

test "pie: empty pie total is zero" {
    const allocator = std.testing.allocator;
    var pie = PieData.init(allocator);
    defer pie.deinit();

    try std.testing.expectApproxEqAbs(@as(f64, 0.0), pie.total(), 0.001);
    try std.testing.expectApproxEqAbs(@as(f64, 0.0), pie.percentage(0), 0.001);
}

test "pie: slice colors wrap around" {
    // 8 colors defined; index 8 should wrap to index 0.
    try std.testing.expectEqual(pie_colors[0], sliceColor(8));
    try std.testing.expectEqual(pie_colors[3], sliceColor(11));
}
