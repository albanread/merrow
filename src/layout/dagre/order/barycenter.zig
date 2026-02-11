const std = @import("std");
const Allocator = std.mem.Allocator;
const Digraph = @import("../../../graph/digraph.zig").Digraph;
const NodeData = @import("../../../model.zig").NodeData;
const EdgeData = @import("../../../model.zig").EdgeData;
const GraphData = @import("../../../model.zig").GraphData;

const Graph = Digraph(NodeData, EdgeData, GraphData);

/// Entry for barycenter calculation with weighted average position
pub const BarycenterEntry = struct {
    v: []const u8,
    barycenter: ?f64,
    weight: f64,
    i: usize, // original index for tie-breaking
};

/// Calculate barycenter (weighted average position) for nodes based on predecessors
/// Used for upward sweep in crossing minimization
pub fn barycenter(allocator: Allocator, graph: *const Graph, movable: []const []const u8) ![]BarycenterEntry {
    var result = try std.ArrayListUnmanaged(BarycenterEntry).initCapacity(allocator, movable.len);
    errdefer result.deinit(allocator);

    for (movable, 0..) |node_id, i| {
        const in_edges = graph.inEdges(node_id) orelse {
            // No predecessors - barycenter is null
            try result.append(allocator, .{
                .v = node_id,
                .barycenter = null,
                .weight = 0.0,
                .i = i,
            });
            continue;
        };

        var sum: f64 = 0.0;
        var total_weight: f64 = 0.0;

        // Calculate weighted average of predecessor order values
        for (in_edges) |edge_key| {
            const pred_node = graph.getNode(edge_key.v) orelse continue;
            const edge = graph.edge(edge_key.v, edge_key.w, edge_key.name) orelse continue;

            if (pred_node.order) |order_val| {
                const weight = @as(f64, @floatFromInt(edge.weight));
                sum += @as(f64, @floatFromInt(order_val)) * weight;
                total_weight += weight;
            }
        }

        const bc = if (total_weight > 0.0) blk: {
            // Add tiny epsilon based on original position to break ties
            const epsilon = @as(f64, @floatFromInt(i)) * 1e-6;
            break :blk (sum / total_weight) + epsilon;
        } else null;

        try result.append(allocator, .{
            .v = node_id,
            .barycenter = bc,
            .weight = total_weight,
            .i = i,
        });
    }

    return result.toOwnedSlice(allocator);
}

/// Calculate barycenter based on successors (for downward sweep)
pub fn barycenterDown(allocator: Allocator, graph: *const Graph, movable: []const []const u8) ![]BarycenterEntry {
    var result = try std.ArrayListUnmanaged(BarycenterEntry).initCapacity(allocator, movable.len);
    errdefer result.deinit(allocator);

    for (movable, 0..) |node_id, i| {
        const out_edges = graph.outEdges(node_id) orelse {
            // No successors - barycenter is null
            try result.append(allocator, .{
                .v = node_id,
                .barycenter = null,
                .weight = 0.0,
                .i = i,
            });
            continue;
        };

        var sum: f64 = 0.0;
        var total_weight: f64 = 0.0;

        // Calculate weighted average of successor order values
        for (out_edges) |edge_key| {
            const succ_node = graph.getNode(edge_key.w) orelse continue;
            const edge = graph.edge(edge_key.v, edge_key.w, edge_key.name) orelse continue;

            if (succ_node.order) |order_val| {
                const weight = @as(f64, @floatFromInt(edge.weight));
                sum += @as(f64, @floatFromInt(order_val)) * weight;
                total_weight += weight;
            }
        }

        const bc = if (total_weight > 0.0) blk: {
            // Add tiny epsilon based on original position to break ties
            const epsilon = @as(f64, @floatFromInt(i)) * 1e-6;
            break :blk (sum / total_weight) + epsilon;
        } else null;

        try result.append(allocator, .{
            .v = node_id,
            .barycenter = bc,
            .weight = total_weight,
            .i = i,
        });
    }

    return result.toOwnedSlice(allocator);
}

// ============================================================================
// TESTS
// ============================================================================

const testing = std.testing;

test "barycenter: single predecessor at order 0" {
    var graph = Graph.init(testing.allocator);
    defer graph.deinit();

    try graph.setNode("A", .{ .order = 0 });
    try graph.setNode("B", .{});
    try graph.setEdge("A", "B", .{ .weight = 1 }, null);

    const movable = [_][]const u8{"B"};
    const entries = try barycenter(testing.allocator, &graph, &movable);
    defer testing.allocator.free(entries);

    try testing.expectEqual(@as(usize, 1), entries.len);
    try testing.expect(entries[0].barycenter != null);
    try testing.expectApproxEqAbs(@as(f64, 0.0), entries[0].barycenter.?, 1e-5);
    try testing.expectEqual(@as(f64, 1.0), entries[0].weight);
}

test "barycenter: two predecessors average position" {
    var graph = Graph.init(testing.allocator);
    defer graph.deinit();

    try graph.setNode("A", .{ .order = 0 });
    try graph.setNode("B", .{ .order = 2 });
    try graph.setNode("C", .{});
    try graph.setEdge("A", "C", .{ .weight = 1 }, null);
    try graph.setEdge("B", "C", .{ .weight = 1 }, null);

    const movable = [_][]const u8{"C"};
    const entries = try barycenter(testing.allocator, &graph, &movable);
    defer testing.allocator.free(entries);

    try testing.expectEqual(@as(usize, 1), entries.len);
    try testing.expect(entries[0].barycenter != null);
    // Average of 0 and 2 is 1.0 (plus tiny epsilon)
    try testing.expectApproxEqAbs(@as(f64, 1.0), entries[0].barycenter.?, 1e-5);
}

test "barycenter: weighted predecessors" {
    var graph = Graph.init(testing.allocator);
    defer graph.deinit();

    try graph.setNode("A", .{ .order = 0 });
    try graph.setNode("B", .{ .order = 4 });
    try graph.setNode("C", .{});
    try graph.setEdge("A", "C", .{ .weight = 3 }, null);
    try graph.setEdge("B", "C", .{ .weight = 1 }, null);

    const movable = [_][]const u8{"C"};
    const entries = try barycenter(testing.allocator, &graph, &movable);
    defer testing.allocator.free(entries);

    try testing.expectEqual(@as(usize, 1), entries.len);
    try testing.expect(entries[0].barycenter != null);
    // Weighted average: (0*3 + 4*1) / (3+1) = 4/4 = 1.0
    try testing.expectApproxEqAbs(@as(f64, 1.0), entries[0].barycenter.?, 1e-5);
    try testing.expectEqual(@as(f64, 4.0), entries[0].weight);
}

test "barycenter: no predecessors gives null barycenter" {
    var graph = Graph.init(testing.allocator);
    defer graph.deinit();

    try graph.setNode("A", .{});

    const movable = [_][]const u8{"A"};
    const entries = try barycenter(testing.allocator, &graph, &movable);
    defer testing.allocator.free(entries);

    try testing.expectEqual(@as(usize, 1), entries.len);
    try testing.expect(entries[0].barycenter == null);
    try testing.expectEqual(@as(f64, 0.0), entries[0].weight);
}

test "barycenterDown: single successor at order 0" {
    var graph = Graph.init(testing.allocator);
    defer graph.deinit();

    try graph.setNode("A", .{});
    try graph.setNode("B", .{ .order = 0 });
    try graph.setEdge("A", "B", .{ .weight = 1 }, null);

    const movable = [_][]const u8{"A"};
    const entries = try barycenterDown(testing.allocator, &graph, &movable);
    defer testing.allocator.free(entries);

    try testing.expectEqual(@as(usize, 1), entries.len);
    try testing.expect(entries[0].barycenter != null);
    try testing.expectApproxEqAbs(@as(f64, 0.0), entries[0].barycenter.?, 1e-5);
}

test "barycenterDown: no successors gives null barycenter" {
    var graph = Graph.init(testing.allocator);
    defer graph.deinit();

    try graph.setNode("A", .{});

    const movable = [_][]const u8{"A"};
    const entries = try barycenterDown(testing.allocator, &graph, &movable);
    defer testing.allocator.free(entries);

    try testing.expectEqual(@as(usize, 1), entries.len);
    try testing.expect(entries[0].barycenter == null);
    try testing.expectEqual(@as(f64, 0.0), entries[0].weight);
}

test "barycenter: multiple nodes preserves indices" {
    var graph = Graph.init(testing.allocator);
    defer graph.deinit();

    try graph.setNode("A", .{ .order = 0 });
    try graph.setNode("B", .{});
    try graph.setNode("C", .{});
    try graph.setEdge("A", "B", .{ .weight = 1 }, null);

    const movable = [_][]const u8{ "B", "C" };
    const entries = try barycenter(testing.allocator, &graph, &movable);
    defer testing.allocator.free(entries);

    try testing.expectEqual(@as(usize, 2), entries.len);
    try testing.expectEqual(@as(usize, 0), entries[0].i);
    try testing.expectEqual(@as(usize, 1), entries[1].i);
}
