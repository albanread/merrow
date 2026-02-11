//! Edge crossing counting for Dagre layout
//!
//! Counts edge crossings between adjacent layers using the accumulator tree
//! algorithm from Barth et al., "Bilayer Cross Counting."

const std = @import("std");
const Digraph = @import("../../../graph/digraph.zig").Digraph;
const model = @import("../../../model.zig");
const NodeData = model.NodeData;
const EdgeData = model.EdgeData;
const GraphData = model.GraphData;
const Allocator = std.mem.Allocator;
const StringHashMap = std.StringHashMap;

const Graph = Digraph(NodeData, EdgeData, GraphData);

/// Count total edge crossings in the layering
pub fn crossCount(allocator: Allocator, graph: *const Graph, layering: []const []const []const u8) !i32 {
    var cc: i32 = 0;
    var i: usize = 1;
    while (i < layering.len) : (i += 1) {
        cc += try twoLayerCrossCount(allocator, graph, layering[i - 1], layering[i]);
    }
    return cc;
}

/// Count crossings between two adjacent layers using accumulator tree
fn twoLayerCrossCount(allocator: Allocator, graph: *const Graph, north: []const []const u8, south: []const []const u8) !i32 {
    if (south.len == 0) return 0;

    // Map south layer nodes to their positions
    var south_pos = StringHashMap(usize).init(allocator);
    defer south_pos.deinit();

    for (south, 0..) |node_id, i| {
        south_pos.put(node_id, i) catch continue;
    }

    // Define EdgeEntry type once
    const EdgeEntry = struct { pos: usize, weight: i32 };

    // Collect edges from north to south with positions and weights
    var south_entries = std.ArrayListUnmanaged(EdgeEntry){};
    defer south_entries.deinit(allocator);

    for (north) |v| {
        const out_edges = graph.outEdges(v) orelse continue;

        // Collect edges for this node
        var edges_for_v = std.ArrayListUnmanaged(EdgeEntry){};
        defer edges_for_v.deinit(allocator);

        for (out_edges) |edge| {
            if (south_pos.get(edge.w)) |pos| {
                const edge_data = graph.edge(edge.v, edge.w, edge.name);
                const weight = if (edge_data) |e| e.weight else 1;
                edges_for_v.append(allocator, .{ .pos = pos, .weight = weight }) catch continue;
            }
        }

        // Sort by position
        const SortContext = struct {
            pub fn lessThan(_: void, a: EdgeEntry, b: EdgeEntry) bool {
                return a.pos < b.pos;
            }
        };
        std.mem.sort(EdgeEntry, edges_for_v.items, {}, SortContext.lessThan);

        // Add to main list
        south_entries.appendSlice(allocator, edges_for_v.items) catch continue;
    }

    // Build accumulator tree
    // Find first power of 2 >= south.len
    var first_index: usize = 1;
    while (first_index < south.len) {
        first_index <<= 1;
    }
    const tree_size = 2 * first_index - 1;
    first_index -= 1;

    var tree = std.ArrayListUnmanaged(i32){};
    defer tree.deinit(allocator);
    tree.resize(allocator, tree_size) catch return 0;
    @memset(tree.items, 0);

    // Calculate weighted crossings
    var cc: i32 = 0;
    for (south_entries.items) |entry| {
        var index = entry.pos + first_index;
        if (index < tree.items.len) {
            tree.items[index] += entry.weight;
        }

        var weight_sum: i32 = 0;
        while (index > 0) {
            if (index % 2 == 1 and index + 1 < tree.items.len) {
                weight_sum += tree.items[index + 1];
            }
            index = (index - 1) >> 1;
            if (index < tree.items.len) {
                tree.items[index] += entry.weight;
            }
        }
        cc += entry.weight * weight_sum;
    }

    return cc;
}

// =====================
// Tests
// =====================
const testing = std.testing;

test "crossCount: no crossings" {
    var g = Graph.init(testing.allocator);
    defer g.deinitDeep();

    try g.setNode("a", .{ .rank = 0 });
    try g.setNode("b", .{ .rank = 0 });
    try g.setNode("c", .{ .rank = 1 });
    try g.setNode("d", .{ .rank = 1 });
    try g.setEdge("a", "c", .{}, null);
    try g.setEdge("b", "d", .{}, null);

    const layering = [_][]const []const u8{
        &[_][]const u8{ "a", "b" },
        &[_][]const u8{ "c", "d" },
    };

    const cc = try crossCount(testing.allocator, &g, &layering);
    try testing.expectEqual(@as(i32, 0), cc);
}

test "crossCount: one crossing" {
    var g = Graph.init(testing.allocator);
    defer g.deinitDeep();

    try g.setNode("a", .{ .rank = 0 });
    try g.setNode("b", .{ .rank = 0 });
    try g.setNode("c", .{ .rank = 1 });
    try g.setNode("d", .{ .rank = 1 });
    try g.setEdge("a", "d", .{}, null);
    try g.setEdge("b", "c", .{}, null);

    const layering = [_][]const []const u8{
        &[_][]const u8{ "a", "b" },
        &[_][]const u8{ "c", "d" },
    };

    const cc = try crossCount(testing.allocator, &g, &layering);
    try testing.expectEqual(@as(i32, 1), cc);
}

test "crossCount: weighted crossing" {
    var g = Graph.init(testing.allocator);
    defer g.deinitDeep();

    try g.setNode("a", .{ .rank = 0 });
    try g.setNode("b", .{ .rank = 0 });
    try g.setNode("c", .{ .rank = 1 });
    try g.setNode("d", .{ .rank = 1 });
    try g.setEdge("a", "d", .{ .weight = 3 }, null);
    try g.setEdge("b", "c", .{}, null);

    const layering = [_][]const []const u8{
        &[_][]const u8{ "a", "b" },
        &[_][]const u8{ "c", "d" },
    };

    const cc = try crossCount(testing.allocator, &g, &layering);
    try testing.expectEqual(@as(i32, 3), cc);
}

test "crossCount: empty layer" {
    var g = Graph.init(testing.allocator);
    defer g.deinitDeep();

    try g.setNode("a", .{ .rank = 0 });

    const layering = [_][]const []const u8{
        &[_][]const u8{"a"},
        &[_][]const u8{},
    };

    const cc = try crossCount(testing.allocator, &g, &layering);
    try testing.expectEqual(@as(i32, 0), cc);
}
