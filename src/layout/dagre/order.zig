const std = @import("std");
const Allocator = std.mem.Allocator;
const Digraph = @import("../../graph/digraph.zig").Digraph;
const NodeData = @import("../../model.zig").NodeData;
const EdgeData = @import("../../model.zig").EdgeData;
const GraphData = @import("../../model.zig").GraphData;

const Graph = Digraph(NodeData, EdgeData, GraphData);

pub const init_order = @import("order/init_order.zig");
pub const cross_count = @import("order/cross_count.zig");
pub const barycenter_mod = @import("order/barycenter.zig");
pub const sort_mod = @import("order/sort.zig");

/// Main ordering function - minimizes edge crossings using barycenter heuristic
pub fn order(allocator: Allocator, graph: *Graph) !void {
    // Get initial ordering
    const initial_layering = try init_order.initOrder(allocator, graph);
    defer {
        for (initial_layering) |layer| {
            for (layer) |id| allocator.free(id);
            allocator.free(layer);
        }
        allocator.free(initial_layering);
    }

    // Assign initial order values to nodes
    init_order.assignOrder(graph, initial_layering);

    // Find max rank
    const max_rank = blk: {
        var max: usize = 0;
        const nodes = try graph.allNodes(allocator);
        defer {
            for (nodes) |id| allocator.free(id);
            allocator.free(nodes);
        }
        for (nodes) |id| {
            if (graph.getNode(id)) |node| {
                if (node.rank) |r| {
                    const rank_usize = @as(usize, @intCast(r));
                    if (rank_usize > max) max = rank_usize;
                }
            }
        }
        break :blk max;
    };

    // Single layer - no crossings possible
    if (max_rank == 0) return;

    // Track best solution
    var best_cc = try cross_count.crossCount(allocator, graph, initial_layering);
    var best_layering = try copyLayering(allocator, initial_layering);
    defer {
        for (best_layering) |layer| {
            for (layer) |id| allocator.free(id);
            allocator.free(layer);
        }
        allocator.free(best_layering);
    }

    var no_improvement_count: usize = 0;
    const max_iterations = 24;
    const patience = 4;

    var iteration: usize = 0;
    while (iteration < max_iterations) : (iteration += 1) {
        // Stop if no improvement in last 'patience' iterations
        if (no_improvement_count >= patience) break;

        if (iteration % 2 == 0) {
            // Even iterations: sweep down
            try sweepDown(allocator, graph, max_rank);
        } else {
            // Odd iterations: sweep up
            try sweepUp(allocator, graph, max_rank);
        }

        // Build layering from current order and count crossings
        const current_layering = try buildLayerMatrix(allocator, graph, max_rank);
        defer {
            for (current_layering) |layer| {
                for (layer) |id| allocator.free(id);
                allocator.free(layer);
            }
            allocator.free(current_layering);
        }

        const current_cc = try cross_count.crossCount(allocator, graph, current_layering);

        if (current_cc < best_cc) {
            // Improved - save this ordering
            best_cc = current_cc;
            for (best_layering) |layer| {
                for (layer) |id| allocator.free(id);
                allocator.free(layer);
            }
            allocator.free(best_layering);
            best_layering = try copyLayering(allocator, current_layering);
            no_improvement_count = 0;
        } else {
            no_improvement_count += 1;
        }
    }

    // Apply best ordering
    init_order.assignOrder(graph, best_layering);
}

/// Sweep down: process layers top to bottom, ordering by predecessor barycenters
fn sweepDown(allocator: Allocator, graph: *Graph, max_rank: usize) !void {
    var rank: usize = 1;
    while (rank <= max_rank) : (rank += 1) {
        const layer = try getLayerNodes(allocator, graph, rank);
        defer {
            for (layer) |id| allocator.free(id);
            allocator.free(layer);
        }

        if (layer.len == 0) continue;

        // Calculate barycenters from predecessors
        const entries = try barycenter_mod.barycenter(allocator, graph, layer);
        defer allocator.free(entries);

        // Sort by barycenter
        const sorted = try sort_mod.sortLayer(allocator, entries, rank % 2 == 1);
        defer allocator.free(sorted);

        // Assign new order values
        for (sorted, 0..) |node_id, order_val| {
            if (graph.getNodePtr(node_id)) |node| {
                node.order = order_val;
            }
        }
    }
}

/// Sweep up: process layers bottom to top, ordering by successor barycenters
fn sweepUp(allocator: Allocator, graph: *Graph, max_rank: usize) !void {
    if (max_rank == 0) return;

    var rank = max_rank - 1;
    while (true) {
        const layer = try getLayerNodes(allocator, graph, rank);
        defer {
            for (layer) |id| allocator.free(id);
            allocator.free(layer);
        }

        if (layer.len > 0) {
            // Calculate barycenters from successors
            const entries = try barycenter_mod.barycenterDown(allocator, graph, layer);
            defer allocator.free(entries);

            // Sort by barycenter
            const sorted = try sort_mod.sortLayer(allocator, entries, rank % 2 == 1);
            defer allocator.free(sorted);

            // Assign new order values
            for (sorted, 0..) |node_id, order_val| {
                if (graph.getNodePtr(node_id)) |node| {
                    node.order = order_val;
                }
            }
        }

        if (rank == 0) break;
        rank -= 1;
    }
}

/// Build layer matrix from current node order values
fn buildLayerMatrix(allocator: Allocator, graph: *Graph, max_rank: usize) ![]const []const []const u8 {
    var layers = try allocator.alloc(std.ArrayListUnmanaged([]const u8), max_rank + 1);
    errdefer allocator.free(layers);

    for (layers) |*layer| {
        layer.* = std.ArrayListUnmanaged([]const u8){};
    }

    errdefer {
        for (layers) |*layer| {
            for (layer.items) |id| allocator.free(id);
            layer.deinit(allocator);
        }
        allocator.free(layers);
    }

    const nodes = try graph.allNodes(allocator);
    defer {
        for (nodes) |id| allocator.free(id);
        allocator.free(nodes);
    }

    // Collect nodes by rank
    for (nodes) |id| {
        if (graph.getNode(id)) |node| {
            if (node.rank) |r| {
                const rank_usize = @as(usize, @intCast(r));
                const id_copy = try allocator.dupe(u8, id);
                try layers[rank_usize].append(allocator, id_copy);
            }
        }
    }

    // Sort each layer by order
    for (layers) |*layer| {
        const Context = struct {
            g: *Graph,
        };
        const lessThan = struct {
            fn f(ctx: Context, a: []const u8, b: []const u8) bool {
                const a_node = ctx.g.getNode(a) orelse return false;
                const b_node = ctx.g.getNode(b) orelse return true;
                const a_order = a_node.order orelse return false;
                const b_order = b_node.order orelse return true;
                return a_order < b_order;
            }
        }.f;
        std.sort.pdq([]const u8, layer.items, Context{ .g = graph }, lessThan);
    }

    // Convert to slice of slices
    var result = try allocator.alloc([]const []const u8, layers.len);
    for (layers, 0..) |*layer, i| {
        result[i] = try layer.toOwnedSlice(allocator);
    }
    allocator.free(layers);

    return result;
}

/// Get all nodes at a specific rank, sorted by current order
fn getLayerNodes(allocator: Allocator, graph: *Graph, rank: usize) ![][]const u8 {
    var result = std.ArrayListUnmanaged([]const u8){};
    errdefer {
        for (result.items) |id| allocator.free(id);
        result.deinit(allocator);
    }

    const nodes = try graph.allNodes(allocator);
    defer {
        for (nodes) |id| allocator.free(id);
        allocator.free(nodes);
    }

    for (nodes) |id| {
        if (graph.getNode(id)) |node| {
            if (node.rank) |r| {
                if (@as(usize, @intCast(r)) == rank) {
                    const id_copy = try allocator.dupe(u8, id);
                    try result.append(allocator, id_copy);
                }
            }
        }
    }

    // Sort by order
    const Context = struct {
        g: *Graph,
    };
    const lessThan = struct {
        fn f(ctx: Context, a: []const u8, b: []const u8) bool {
            const a_node = ctx.g.getNode(a) orelse return false;
            const b_node = ctx.g.getNode(b) orelse return true;
            const a_order = a_node.order orelse return false;
            const b_order = b_node.order orelse return true;
            return a_order < b_order;
        }
    }.f;
    std.sort.pdq([]const u8, result.items, Context{ .g = graph }, lessThan);

    return result.toOwnedSlice(allocator);
}

/// Copy a layering (deep copy)
fn copyLayering(allocator: Allocator, layering: []const []const []const u8) ![]const []const []const u8 {
    var result = try allocator.alloc([]const []const u8, layering.len);
    errdefer allocator.free(result);

    for (layering, 0..) |layer, i| {
        var layer_copy = try allocator.alloc([]const u8, layer.len);
        for (layer, 0..) |id, j| {
            layer_copy[j] = try allocator.dupe(u8, id);
        }
        result[i] = layer_copy;
    }

    return result;
}

// ============================================================================
// TESTS
// ============================================================================

const testing = std.testing;

test "order: single layer has no effect" {
    var graph = Graph.init(testing.allocator);
    defer graph.deinit();

    try graph.setNode("A", .{ .rank = 0, .order = 0 });
    try graph.setNode("B", .{ .rank = 0, .order = 1 });

    try order(testing.allocator, &graph);

    const a = graph.getNode("A").?;
    const b = graph.getNode("B").?;
    try testing.expect(a.order != null);
    try testing.expect(b.order != null);
}

test "order: simple chain preserves structure" {
    var graph = Graph.init(testing.allocator);
    defer graph.deinit();

    try graph.setNode("A", .{ .rank = 0 });
    try graph.setNode("B", .{ .rank = 1 });
    try graph.setNode("C", .{ .rank = 2 });
    try graph.setEdge("A", "B", .{}, null);
    try graph.setEdge("B", "C", .{}, null);

    try order(testing.allocator, &graph);

    // All nodes should have order assigned
    try testing.expect(graph.getNode("A").?.order != null);
    try testing.expect(graph.getNode("B").?.order != null);
    try testing.expect(graph.getNode("C").?.order != null);

    // Each should be the only node in its layer, so order = 0
    try testing.expectEqual(@as(usize, 0), graph.getNode("A").?.order.?);
    try testing.expectEqual(@as(usize, 0), graph.getNode("B").?.order.?);
    try testing.expectEqual(@as(usize, 0), graph.getNode("C").?.order.?);
}

test "order: diamond structure" {
    var graph = Graph.init(testing.allocator);
    defer graph.deinit();

    try graph.setNode("A", .{ .rank = 0 });
    try graph.setNode("B", .{ .rank = 1 });
    try graph.setNode("C", .{ .rank = 1 });
    try graph.setNode("D", .{ .rank = 2 });
    try graph.setEdge("A", "B", .{}, null);
    try graph.setEdge("A", "C", .{}, null);
    try graph.setEdge("B", "D", .{}, null);
    try graph.setEdge("C", "D", .{}, null);

    try order(testing.allocator, &graph);

    // All nodes should have order assigned
    try testing.expect(graph.getNode("A").?.order != null);
    try testing.expect(graph.getNode("B").?.order != null);
    try testing.expect(graph.getNode("C").?.order != null);
    try testing.expect(graph.getNode("D").?.order != null);

    // B and C should have different orders
    const b_order = graph.getNode("B").?.order.?;
    const c_order = graph.getNode("C").?.order.?;
    try testing.expect(b_order != c_order);
}

test {
    std.testing.refAllDecls(@This());
    std.testing.refAllDecls(init_order);
    std.testing.refAllDecls(cross_count);
    std.testing.refAllDecls(barycenter_mod);
    std.testing.refAllDecls(sort_mod);
}
