const std = @import("std");
const Digraph = @import("../../graph/digraph.zig").Digraph;
const model = @import("../../model.zig");
const NodeData = model.NodeData;
const EdgeData = model.EdgeData;
const GraphData = model.GraphData;
const Acyclicer = @import("../dagre.zig").Acyclicer;

/// Make the graph acyclic by reversing back edges
pub fn run(
    allocator: std.mem.Allocator,
    graph: *Digraph(NodeData, EdgeData, GraphData),
    method: Acyclicer,
) !void {
    var fas = switch (method) {
        .greedy => try greedyFas(allocator, graph),
        .dfs => try dfsFas(allocator, graph),
    };
    defer {
        for (fas.items) |edge| {
            allocator.free(edge.v);
            allocator.free(edge.w);
            if (edge.name) |n| allocator.free(n);
        }
        fas.deinit(allocator);
    }

    // Reverse each edge in the feedback arc set
    for (fas.items) |edge_key| {
        // Get the edge data
        const edge_data = graph.edge(edge_key.v, edge_key.w, edge_key.name) orelse continue;

        // Remove original edge
        graph.removeEdge(edge_key.v, edge_key.w, edge_key.name);

        // Create reversed edge with unique name
        const rev_name = try std.fmt.allocPrint(allocator, "rev_{s}_{s}", .{
            edge_key.w,
            edge_key.v,
        });
        defer allocator.free(rev_name);

        var new_edge_data = edge_data;
        new_edge_data.reversed = true;
        new_edge_data.forward_name = if (edge_key.name) |n| try allocator.dupe(u8, n) else null;

        try graph.setEdge(edge_key.w, edge_key.v, new_edge_data, rev_name);
    }
}

/// Undo the cycle removal - restore reversed edges to original direction
pub fn undo(
    allocator: std.mem.Allocator,
    graph: *Digraph(NodeData, EdgeData, GraphData),
) !void {
    var reversed_edges = std.ArrayListUnmanaged(EdgeInfo){};
    defer reversed_edges.deinit(allocator);

    // Collect all reversed edges
    var edge_iter = graph.edgeIterator();
    while (edge_iter.next()) |entry| {
        if (entry.data.reversed) {
            try reversed_edges.append(allocator, .{
                .v = try allocator.dupe(u8, entry.v),
                .w = try allocator.dupe(u8, entry.w),
                .name = if (entry.name) |n| try allocator.dupe(u8, n) else null,
            });
        }
    }

    // Restore each reversed edge
    for (reversed_edges.items) |edge_key| {
        defer {
            allocator.free(edge_key.v);
            allocator.free(edge_key.w);
            if (edge_key.name) |n| allocator.free(n);
        }

        const edge_data = graph.edge(edge_key.v, edge_key.w, edge_key.name) orelse continue;

        // Restore original data
        var restored_data = edge_data;
        restored_data.reversed = false;

        // Get forward name (allocated by `run`) and take ownership so we
        // can free it after setEdge dupes it for the key.
        const forward_name = edge_data.forward_name;
        restored_data.forward_name = null; // clear from restored data

        // Remove reversed edge
        graph.removeEdge(edge_key.v, edge_key.w, edge_key.name);

        // Restore original edge
        try graph.setEdge(edge_key.w, edge_key.v, restored_data, forward_name);

        // Free the forward_name allocation — setEdge has already duped it
        // for the edge key, so the original is no longer needed.
        if (forward_name) |fn_ptr| allocator.free(fn_ptr);
    }
}

const EdgeInfo = struct {
    v: []const u8,
    w: []const u8,
    name: ?[]const u8,
};

/// Find feedback arc set using DFS
fn dfsFas(
    allocator: std.mem.Allocator,
    graph: *const Digraph(NodeData, EdgeData, GraphData),
) !std.ArrayListUnmanaged(EdgeInfo) {
    var fas = std.ArrayListUnmanaged(EdgeInfo){};
    errdefer {
        for (fas.items) |edge| {
            allocator.free(edge.v);
            allocator.free(edge.w);
            if (edge.name) |n| allocator.free(n);
        }
        fas.deinit(allocator);
    }

    var visited = std.StringHashMap(void).init(allocator);
    defer visited.deinit();

    var stack = std.StringHashMap(void).init(allocator);
    defer stack.deinit();

    // Get all nodes and sort for determinism
    const nodes = try graph.allNodes(allocator);
    defer {
        for (nodes) |n| allocator.free(n);
        allocator.free(nodes);
    }

    // Sort nodes
    std.mem.sort([]const u8, nodes, {}, struct {
        fn lessThan(_: void, a: []const u8, b: []const u8) bool {
            return std.mem.order(u8, a, b) == .lt;
        }
    }.lessThan);

    // Find source nodes (no incoming edges)
    var sources = std.ArrayListUnmanaged([]const u8){};
    defer sources.deinit(allocator);

    for (nodes) |node| {
        const in_edges = graph.inEdges(node) orelse &.{};
        if (in_edges.len == 0) {
            try sources.append(allocator, node);
        }
    }

    // DFS from sources first
    for (sources.items) |node| {
        try dfsVisit(allocator, graph, node, &visited, &stack, &fas);
    }

    // Then visit remaining nodes
    for (nodes) |node| {
        try dfsVisit(allocator, graph, node, &visited, &stack, &fas);
    }

    return fas;
}

fn dfsVisit(
    allocator: std.mem.Allocator,
    graph: *const Digraph(NodeData, EdgeData, GraphData),
    v: []const u8,
    visited: *std.StringHashMap(void),
    stack: *std.StringHashMap(void),
    fas: *std.ArrayListUnmanaged(EdgeInfo),
) !void {
    if (visited.contains(v)) {
        return;
    }

    try visited.put(v, {});
    try stack.put(v, {});

    const out_edges = graph.outEdges(v) orelse &.{};
    for (out_edges) |edge| {
        if (stack.contains(edge.w)) {
            // Back edge found - add to feedback arc set
            try fas.append(allocator, .{
                .v = try allocator.dupe(u8, v),
                .w = try allocator.dupe(u8, edge.w),
                .name = if (edge.name) |n| try allocator.dupe(u8, n) else null,
            });
        } else {
            try dfsVisit(allocator, graph, edge.w, visited, stack, fas);
        }
    }

    _ = stack.remove(v);
}

/// Find feedback arc set using greedy algorithm
fn greedyFas(
    allocator: std.mem.Allocator,
    graph: *const Digraph(NodeData, EdgeData, GraphData),
) !std.ArrayListUnmanaged(EdgeInfo) {
    var fas = std.ArrayListUnmanaged(EdgeInfo){};
    errdefer {
        for (fas.items) |edge| {
            allocator.free(edge.v);
            allocator.free(edge.w);
            if (edge.name) |n| allocator.free(n);
        }
        fas.deinit(allocator);
    }

    const nodes = try graph.allNodes(allocator);
    defer {
        for (nodes) |n| allocator.free(n);
        allocator.free(nodes);
    }

    if (nodes.len == 0) {
        return fas;
    }

    // Track in/out degrees
    var in_degree = std.StringHashMap(i32).init(allocator);
    defer in_degree.deinit();

    var out_degree = std.StringHashMap(i32).init(allocator);
    defer out_degree.deinit();

    var active_nodes = std.StringHashMap(void).init(allocator);
    defer active_nodes.deinit();

    // Initialize degrees
    for (nodes) |node| {
        const in_edges = graph.inEdges(node) orelse &.{};
        const out_edges = graph.outEdges(node) orelse &.{};
        try in_degree.put(node, @intCast(in_edges.len));
        try out_degree.put(node, @intCast(out_edges.len));
        try active_nodes.put(node, {});
    }

    var sources = std.ArrayListUnmanaged([]const u8){};
    defer sources.deinit(allocator);

    var sinks = std.ArrayListUnmanaged([]const u8){};
    defer sinks.deinit(allocator);

    // Process until graph is empty
    while (active_nodes.count() > 0) {
        sources.clearRetainingCapacity();
        sinks.clearRetainingCapacity();

        // Find sources and sinks
        var iter = active_nodes.keyIterator();
        while (iter.next()) |node| {
            const in_deg = in_degree.get(node.*) orelse 0;
            const out_deg = out_degree.get(node.*) orelse 0;

            if (in_deg == 0) {
                try sources.append(allocator, node.*);
            }
            if (out_deg == 0) {
                try sinks.append(allocator, node.*);
            }
        }

        // Remove sources
        for (sources.items) |node| {
            const out_edges = graph.outEdges(node) orelse &.{};
            for (out_edges) |edge| {
                if (active_nodes.contains(edge.w)) {
                    const deg = in_degree.get(edge.w) orelse 0;
                    try in_degree.put(edge.w, deg - 1);
                }
            }
            _ = active_nodes.remove(node);
        }

        // Remove sinks
        for (sinks.items) |node| {
            const in_edges = graph.inEdges(node) orelse &.{};
            for (in_edges) |edge| {
                if (active_nodes.contains(edge.v)) {
                    const deg = out_degree.get(edge.v) orelse 0;
                    try out_degree.put(edge.v, deg - 1);
                }
            }
            _ = active_nodes.remove(node);
        }

        // If there are remaining nodes, we have a cycle
        if (active_nodes.count() > 0) {
            var best_node: ?[]const u8 = null;
            var best_score: i32 = std.math.minInt(i32);

            var node_iter = active_nodes.keyIterator();
            while (node_iter.next()) |node| {
                const in_deg = in_degree.get(node.*) orelse 0;
                const out_deg = out_degree.get(node.*) orelse 0;
                const score = out_deg - in_deg;

                if (score > best_score) {
                    best_score = score;
                    best_node = node.*;
                }
            }

            if (best_node) |node| {
                // Add incoming edges to FAS
                const in_edges = graph.inEdges(node) orelse &.{};
                for (in_edges) |edge| {
                    if (active_nodes.contains(edge.v)) {
                        try fas.append(allocator, .{
                            .v = try allocator.dupe(u8, edge.v),
                            .w = try allocator.dupe(u8, edge.w),
                            .name = if (edge.name) |n| try allocator.dupe(u8, n) else null,
                        });
                        const deg = out_degree.get(edge.v) orelse 0;
                        try out_degree.put(edge.v, deg - 1);
                    }
                }

                // Update outgoing edge degrees
                const out_edges = graph.outEdges(node) orelse &.{};
                for (out_edges) |edge| {
                    if (active_nodes.contains(edge.w)) {
                        const deg = in_degree.get(edge.w) orelse 0;
                        try in_degree.put(edge.w, deg - 1);
                    }
                }

                _ = active_nodes.remove(node);
            }
        }
    }

    return fas;
}

test "acyclic: dfs does not change acyclic graph" {
    var graph = Digraph(NodeData, EdgeData, GraphData).init(std.testing.allocator);
    defer graph.deinit();

    try graph.setNode("a", .{ .width = 50, .height = 50 });
    try graph.setNode("b", .{ .width = 50, .height = 50 });
    try graph.setNode("c", .{ .width = 50, .height = 50 });
    try graph.setNode("d", .{ .width = 50, .height = 50 });

    try graph.setEdge("a", "b", .{}, null);
    try graph.setEdge("a", "c", .{}, null);
    try graph.setEdge("b", "d", .{}, null);
    try graph.setEdge("c", "d", .{}, null);

    const initial_count = graph.edgeCount();

    try run(std.testing.allocator, &graph, .dfs);

    try std.testing.expectEqual(initial_count, graph.edgeCount());
    try std.testing.expect(graph.hasEdge("a", "b", null));
    try std.testing.expect(graph.hasEdge("a", "c", null));
    try std.testing.expect(graph.hasEdge("b", "d", null));
    try std.testing.expect(graph.hasEdge("c", "d", null));
}

test "acyclic: dfs breaks simple cycle" {
    var graph = Digraph(NodeData, EdgeData, GraphData).init(std.testing.allocator);
    defer graph.deinit();

    try graph.setNode("a", .{ .width = 50, .height = 50 });
    try graph.setNode("b", .{ .width = 50, .height = 50 });
    try graph.setNode("c", .{ .width = 50, .height = 50 });

    try graph.setEdge("a", "b", .{}, null);
    try graph.setEdge("b", "c", .{}, null);
    try graph.setEdge("c", "a", .{}, null);

    try run(std.testing.allocator, &graph, .dfs);

    // Should still have 3 edges, but no cycles
    try std.testing.expectEqual(@as(usize, 3), graph.edgeCount());

    // At least one edge should be reversed
    var has_reversed = false;
    var iter = graph.edgeIterator();
    while (iter.next()) |entry| {
        if (entry.data.reversed) {
            has_reversed = true;
            break;
        }
    }
    try std.testing.expect(has_reversed);
}

test "acyclic: greedy breaks cycle" {
    var graph = Digraph(NodeData, EdgeData, GraphData).init(std.testing.allocator);
    defer graph.deinit();

    try graph.setNode("a", .{ .width = 50, .height = 50 });
    try graph.setNode("b", .{ .width = 50, .height = 50 });
    try graph.setNode("c", .{ .width = 50, .height = 50 });

    try graph.setEdge("a", "b", .{}, null);
    try graph.setEdge("b", "c", .{}, null);
    try graph.setEdge("c", "a", .{}, null);

    try run(std.testing.allocator, &graph, .greedy);

    try std.testing.expectEqual(@as(usize, 3), graph.edgeCount());

    // At least one edge should be reversed
    var has_reversed = false;
    var iter = graph.edgeIterator();
    while (iter.next()) |entry| {
        if (entry.data.reversed) {
            has_reversed = true;
            break;
        }
    }
    try std.testing.expect(has_reversed);
}

test "acyclic: undo restores graph" {
    var graph = Digraph(NodeData, EdgeData, GraphData).init(std.testing.allocator);
    defer graph.deinit();

    try graph.setNode("a", .{ .width = 50, .height = 50 });
    try graph.setNode("b", .{ .width = 50, .height = 50 });

    try graph.setEdge("a", "b", .{ .weight = 5, .minlen = 2 }, null);

    try run(std.testing.allocator, &graph, .dfs);
    try undo(std.testing.allocator, &graph);

    const edge_data = graph.edge("a", "b", null);
    try std.testing.expect(edge_data != null);
    if (edge_data) |e| {
        try std.testing.expectEqual(@as(i32, 5), e.weight);
        try std.testing.expectEqual(@as(i32, 2), e.minlen);
    }
}
