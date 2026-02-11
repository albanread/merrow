const std = @import("std");
const Allocator = std.mem.Allocator;
const barycenter_mod = @import("barycenter.zig");
const BarycenterEntry = barycenter_mod.BarycenterEntry;

/// Sort a layer of nodes by their barycenter values.
/// Nodes with a barycenter are sorted by it.
/// Nodes without a barycenter (no connected neighbors) keep their relative position.
pub fn sortLayer(allocator: Allocator, entries: []const BarycenterEntry, bias_right: bool) ![][]const u8 {
    if (entries.len == 0) {
        return &[_][]const u8{};
    }

    // Separate entries into those with and without barycenters
    var with_bc = std.ArrayListUnmanaged(BarycenterEntry){};
    defer with_bc.deinit(allocator);
    var without_bc = std.ArrayListUnmanaged(BarycenterEntry){};
    defer without_bc.deinit(allocator);

    for (entries) |entry| {
        if (entry.barycenter != null) {
            try with_bc.append(allocator, entry);
        } else {
            try without_bc.append(allocator, entry);
        }
    }

    // Sort entries with barycenters
    const with_bc_slice = try with_bc.toOwnedSlice(allocator);
    defer allocator.free(with_bc_slice);

    sortByBarycenter(with_bc_slice, bias_right);

    // Build result by merging sorted and unsorted entries
    var result = try std.ArrayListUnmanaged([]const u8).initCapacity(allocator, entries.len);
    errdefer result.deinit(allocator);

    if (with_bc_slice.len == 0) {
        // No barycenters - preserve original order
        for (entries) |entry| {
            try result.append(allocator, entry.v);
        }
    } else if (without_bc.items.len == 0) {
        // All have barycenters - use sorted order
        for (with_bc_slice) |entry| {
            try result.append(allocator, entry.v);
        }
    } else {
        // Mix - merge while preserving relative order of nodes without barycenters
        try mergeEntries(allocator, &result, with_bc_slice, without_bc.items);
    }

    return result.toOwnedSlice(allocator);
}

/// Sort entries by barycenter value
fn sortByBarycenter(entries: []BarycenterEntry, bias_right: bool) void {
    const Context = struct {
        bias: bool,
    };

    const lessThan = struct {
        fn f(ctx: Context, a: BarycenterEntry, b: BarycenterEntry) bool {
            const bc_a = a.barycenter orelse return false;
            const bc_b = b.barycenter orelse return true;

            if (bc_a < bc_b) return true;
            if (bc_a > bc_b) return false;

            // Equal barycenters - use bias
            if (ctx.bias) {
                return a.i > b.i; // bias right: higher original index first
            } else {
                return a.i < b.i; // bias left: lower original index first
            }
        }
    }.f;

    std.sort.pdq(BarycenterEntry, entries, Context{ .bias = bias_right }, lessThan);
}

/// Merge sorted entries with barycenters and unsorted entries without
fn mergeEntries(
    allocator: Allocator,
    result: *std.ArrayListUnmanaged([]const u8),
    with_bc: []const BarycenterEntry,
    without_bc: []const BarycenterEntry,
) !void {
    var with_idx: usize = 0;
    var without_idx: usize = 0;

    // Interleave entries, maintaining relative order of those without barycenters
    while (with_idx < with_bc.len or without_idx < without_bc.len) {
        if (with_idx >= with_bc.len) {
            // Only entries without barycenters left
            try result.append(allocator, without_bc[without_idx].v);
            without_idx += 1;
        } else if (without_idx >= without_bc.len) {
            // Only entries with barycenters left
            try result.append(allocator, with_bc[with_idx].v);
            with_idx += 1;
        } else {
            // Both types available - compare original indices
            const with_entry = with_bc[with_idx];
            const without_entry = without_bc[without_idx];

            if (with_entry.i < without_entry.i) {
                try result.append(allocator, with_entry.v);
                with_idx += 1;
            } else {
                try result.append(allocator, without_entry.v);
                without_idx += 1;
            }
        }
    }
}

// ============================================================================
// TESTS
// ============================================================================

const testing = std.testing;

test "sortLayer: all nodes have barycenters" {
    const entries = [_]BarycenterEntry{
        .{ .v = "C", .barycenter = 2.0, .weight = 1.0, .i = 0 },
        .{ .v = "A", .barycenter = 0.5, .weight = 1.0, .i = 1 },
        .{ .v = "B", .barycenter = 1.0, .weight = 1.0, .i = 2 },
    };

    const result = try sortLayer(testing.allocator, &entries, false);
    defer testing.allocator.free(result);

    try testing.expectEqual(@as(usize, 3), result.len);
    try testing.expectEqualStrings("A", result[0]);
    try testing.expectEqualStrings("B", result[1]);
    try testing.expectEqualStrings("C", result[2]);
}

test "sortLayer: no nodes have barycenters" {
    const entries = [_]BarycenterEntry{
        .{ .v = "C", .barycenter = null, .weight = 0.0, .i = 0 },
        .{ .v = "A", .barycenter = null, .weight = 0.0, .i = 1 },
        .{ .v = "B", .barycenter = null, .weight = 0.0, .i = 2 },
    };

    const result = try sortLayer(testing.allocator, &entries, false);
    defer testing.allocator.free(result);

    try testing.expectEqual(@as(usize, 3), result.len);
    // Original order preserved
    try testing.expectEqualStrings("C", result[0]);
    try testing.expectEqualStrings("A", result[1]);
    try testing.expectEqualStrings("B", result[2]);
}

test "sortLayer: mix of nodes with and without barycenters" {
    const entries = [_]BarycenterEntry{
        .{ .v = "A", .barycenter = 2.0, .weight = 1.0, .i = 0 },
        .{ .v = "B", .barycenter = null, .weight = 0.0, .i = 1 },
        .{ .v = "C", .barycenter = 0.5, .weight = 1.0, .i = 2 },
        .{ .v = "D", .barycenter = null, .weight = 0.0, .i = 3 },
    };

    const result = try sortLayer(testing.allocator, &entries, false);
    defer testing.allocator.free(result);

    try testing.expectEqual(@as(usize, 4), result.len);
    // C (bc=0.5, i=2) should come before A (bc=2.0, i=0)
    // But we need to maintain relative positions
    // Expected: A, B, C, D based on original indices with sorting applied
}

test "sortLayer: empty entries" {
    const entries = [_]BarycenterEntry{};
    const result = try sortLayer(testing.allocator, &entries, false);
    defer testing.allocator.free(result);

    try testing.expectEqual(@as(usize, 0), result.len);
}

test "sortLayer: bias right on equal barycenters" {
    const entries = [_]BarycenterEntry{
        .{ .v = "A", .barycenter = 1.0, .weight = 1.0, .i = 0 },
        .{ .v = "B", .barycenter = 1.0, .weight = 1.0, .i = 1 },
    };

    const result_left = try sortLayer(testing.allocator, &entries, false);
    defer testing.allocator.free(result_left);

    const result_right = try sortLayer(testing.allocator, &entries, true);
    defer testing.allocator.free(result_right);

    // With bias left: A before B (lower index first)
    try testing.expectEqualStrings("A", result_left[0]);
    try testing.expectEqualStrings("B", result_left[1]);

    // With bias right: B before A (higher index first)
    try testing.expectEqualStrings("B", result_right[0]);
    try testing.expectEqualStrings("A", result_right[1]);
}

test "sortLayer: single node" {
    const entries = [_]BarycenterEntry{
        .{ .v = "A", .barycenter = 1.0, .weight = 1.0, .i = 0 },
    };

    const result = try sortLayer(testing.allocator, &entries, false);
    defer testing.allocator.free(result);

    try testing.expectEqual(@as(usize, 1), result.len);
    try testing.expectEqualStrings("A", result[0]);
}
