const std = @import("std");
const Digraph = @import("../../../graph/digraph.zig").Digraph;
const EdgeKey = @import("../../../graph/digraph.zig").EdgeKey;
const model = @import("../../../model.zig");
const NodeData = model.NodeData;
const EdgeData = model.EdgeData;
const GraphData = model.GraphData;
const Allocator = std.mem.Allocator;
const StringHashMap = std.StringHashMap;

const Graph = Digraph(NodeData, EdgeData, GraphData);

/// DFS helper to visit nodes and assign them to layers in order
fn dfsVisit(
    allocator: Allocator,
    graph: *Graph,
    v: []const u8,
    visited: *StringHashMap(void),
    layer_lists: []std.ArrayListUnmanaged([]const u8),
) !void {
    if (visited.contains(v)) return;
    try visited.put(v, {});

    const node = graph.getNode(v) orelse return;
    const rank = node.rank orelse return;
    if (rank < 0) return;

    const rank_idx = @as(usize, @intCast(rank));
    if (rank_idx >= layer_lists.len) return;

    const id_copy = try allocator.dupe(u8, v);
    try layer_lists[rank_idx].append(allocator, id_copy);

    const out_edges = graph.outEdges(v) orelse return;
    for (out_edges) |edge| {
        try dfsVisit(allocator, graph, edge.w, visited, layer_lists);
    }
}

/// Walk the parent chain of a node to find the top-level (root) subgraph it
/// belongs to.  Returns the root subgraph ID, or the empty string "" if the
/// node is at the top level (no parent subgraph).
fn rootSubgraph(graph: *Graph, node_id: []const u8) []const u8 {
    var cur = node_id;
    var root: []const u8 = "";
    while (true) {
        const p = graph.getParent(cur) orelse break;
        root = p;
        cur = p;
    }
    return root;
}

/// Get the immediate parent subgraph of a node, or "" if none.
fn parentSubgraph(graph: *Graph, node_id: []const u8) []const u8 {
    return graph.getParent(node_id) orelse "";
}

/// Returns a layering: array of arrays where layering[rank] is a list of node IDs in order.
/// Nodes that belong to the same parent subgraph are grouped together within
/// each rank so that sibling subgraph bounding boxes do not interleave.
/// Caller must free each node ID string, each layer slice, and the outer slice.
pub fn initOrder(allocator: Allocator, graph: *Graph) ![]const []const []const u8 {
    // Find max rank
    var max_rank: i32 = 0;
    {
        const nodes = try graph.allNodes(allocator);
        defer {
            for (nodes) |id| allocator.free(id);
            allocator.free(nodes);
        }
        for (nodes) |id| {
            if (graph.getNode(id)) |node| {
                if (node.rank) |r| {
                    if (r > max_rank) max_rank = r;
                }
            }
        }
    }

    const num_layers = @as(usize, @intCast(max_rank + 1));

    // Create mutable layer lists
    const layer_lists = try allocator.alloc(std.ArrayListUnmanaged([]const u8), num_layers);
    defer {
        for (layer_lists) |*lst| lst.deinit(allocator);
        allocator.free(layer_lists);
    }
    for (layer_lists) |*lst| {
        lst.* = .{};
    }

    // Collect and sort nodes
    const all_nodes = try graph.allNodes(allocator);
    defer {
        for (all_nodes) |id| allocator.free(id);
        allocator.free(all_nodes);
    }

    const NodeSort = struct {
        id: []const u8,
        rank: i32,
        has_edges: bool,
        parent_sg: []const u8,
        root_sg: []const u8,
    };

    var sortable = try allocator.alloc(NodeSort, all_nodes.len);
    defer allocator.free(sortable);

    for (all_nodes, 0..) |id, i| {
        const node = graph.getNode(id);
        const r = if (node) |n| n.rank orelse std.math.maxInt(i32) else std.math.maxInt(i32);

        const out = graph.outEdges(id);
        const in = graph.inEdges(id);
        const has_edges = (out != null and out.?.len > 0) or (in != null and in.?.len > 0);

        sortable[i] = .{
            .id = id,
            .rank = r,
            .has_edges = has_edges,
            .parent_sg = parentSubgraph(graph, id),
            .root_sg = rootSubgraph(graph, id),
        };
    }

    // Sort primarily by rank, then group by root subgraph, then by
    // immediate parent subgraph, then prefer nodes with edges, then
    // alphabetical.  This ensures nodes from the same subgraph cluster
    // together in each rank.
    const SortContext = struct {
        pub fn lessThan(_: void, a: NodeSort, b: NodeSort) bool {
            if (a.rank != b.rank) return a.rank < b.rank;
            // Group by root-level subgraph first.
            const root_cmp = std.mem.order(u8, a.root_sg, b.root_sg);
            if (root_cmp != .eq) return root_cmp == .lt;
            // Then by immediate parent subgraph.
            const parent_cmp = std.mem.order(u8, a.parent_sg, b.parent_sg);
            if (parent_cmp != .eq) return parent_cmp == .lt;
            // Prefer nodes with edges.
            if (a.has_edges != b.has_edges) return a.has_edges and !b.has_edges;
            return std.mem.lessThan(u8, a.id, b.id);
        }
    };
    std.mem.sort(NodeSort, sortable, {}, SortContext.lessThan);

    // DFS from each unvisited node
    var visited = StringHashMap(void).init(allocator);
    defer visited.deinit();

    for (sortable) |entry| {
        try dfsVisit(allocator, graph, entry.id, &visited, layer_lists);
    }

    // Post-process: re-sort each layer to group by parent subgraph.
    // The DFS traversal may have broken the subgraph-grouping established
    // above, so we enforce it again on the final layer contents.
    for (layer_lists) |*layer| {
        const LayerSortCtx = struct {
            g: *Graph,
            pub fn lessThan(ctx: @This(), a: []const u8, b: []const u8) bool {
                const a_root = rootSubgraph(ctx.g, a);
                const b_root = rootSubgraph(ctx.g, b);
                const root_cmp = std.mem.order(u8, a_root, b_root);
                if (root_cmp != .eq) return root_cmp == .lt;
                const a_parent = parentSubgraph(ctx.g, a);
                const b_parent = parentSubgraph(ctx.g, b);
                const parent_cmp = std.mem.order(u8, a_parent, b_parent);
                if (parent_cmp != .eq) return parent_cmp == .lt;
                return std.mem.lessThan(u8, a, b);
            }
        };
        std.mem.sort([]const u8, layer.items, LayerSortCtx{ .g = graph }, LayerSortCtx.lessThan);
    }

    // Convert to output format
    var layers = try allocator.alloc([]const []const u8, num_layers);
    for (layer_lists, 0..) |*lst, i| {
        layers[i] = try lst.toOwnedSlice(allocator);
    }

    return layers;
}

/// Assigns order values to nodes based on the layering
pub fn assignOrder(graph: *Graph, layering: []const []const []const u8) void {
    for (layering) |layer| {
        for (layer, 0..) |id, i| {
            if (graph.getNodePtr(id)) |node| {
                node.order = i;
            }
        }
    }
}

// =====================
// Tests
// =====================
const testing = std.testing;

test "initOrder: single node" {
    var g = Graph.init(testing.allocator);
    defer g.deinitDeep();

    try g.setNode("a", .{ .rank = 0 });

    const layers = try initOrder(testing.allocator, &g);
    defer {
        for (layers) |layer| {
            for (layer) |id| testing.allocator.free(id);
            testing.allocator.free(layer);
        }
        testing.allocator.free(layers);
    }

    try testing.expectEqual(@as(usize, 1), layers.len);
    try testing.expectEqual(@as(usize, 1), layers[0].len);
    try testing.expectEqualStrings("a", layers[0][0]);
}

test "initOrder: chain" {
    var g = Graph.init(testing.allocator);
    defer g.deinitDeep();

    try g.setNode("a", .{ .rank = 0 });
    try g.setNode("b", .{ .rank = 1 });
    try g.setNode("c", .{ .rank = 2 });
    try g.setEdge("a", "b", .{}, null);
    try g.setEdge("b", "c", .{}, null);

    const layers = try initOrder(testing.allocator, &g);
    defer {
        for (layers) |layer| {
            for (layer) |id| testing.allocator.free(id);
            testing.allocator.free(layer);
        }
        testing.allocator.free(layers);
    }

    try testing.expectEqual(@as(usize, 3), layers.len);
    try testing.expectEqual(@as(usize, 1), layers[0].len);
    try testing.expectEqualStrings("a", layers[0][0]);
    try testing.expectEqual(@as(usize, 1), layers[1].len);
    try testing.expectEqualStrings("b", layers[1][0]);
    try testing.expectEqual(@as(usize, 1), layers[2].len);
    try testing.expectEqualStrings("c", layers[2][0]);
}

test "initOrder: diamond" {
    var g = Graph.init(testing.allocator);
    defer g.deinitDeep();

    try g.setNode("a", .{ .rank = 0 });
    try g.setNode("b", .{ .rank = 1 });
    try g.setNode("c", .{ .rank = 1 });
    try g.setNode("d", .{ .rank = 2 });
    try g.setEdge("a", "b", .{}, null);
    try g.setEdge("a", "c", .{}, null);
    try g.setEdge("b", "d", .{}, null);
    try g.setEdge("c", "d", .{}, null);

    const layers = try initOrder(testing.allocator, &g);
    defer {
        for (layers) |layer| {
            for (layer) |id| testing.allocator.free(id);
            testing.allocator.free(layer);
        }
        testing.allocator.free(layers);
    }

    try testing.expectEqual(@as(usize, 3), layers.len);
    try testing.expectEqual(@as(usize, 1), layers[0].len);
    try testing.expectEqualStrings("a", layers[0][0]);

    try testing.expectEqual(@as(usize, 2), layers[1].len);
    var found_b = false;
    var found_c = false;
    for (layers[1]) |id| {
        if (std.mem.eql(u8, id, "b")) found_b = true;
        if (std.mem.eql(u8, id, "c")) found_c = true;
    }
    try testing.expect(found_b and found_c);

    try testing.expectEqual(@as(usize, 1), layers[2].len);
    try testing.expectEqualStrings("d", layers[2][0]);
}

test "assignOrder: sets node order values" {
    var g = Graph.init(testing.allocator);
    defer g.deinitDeep();

    try g.setNode("a", .{ .rank = 0 });
    try g.setNode("b", .{ .rank = 1 });
    try g.setNode("c", .{ .rank = 1 });
    try g.setNode("d", .{ .rank = 2 });
    try g.setEdge("a", "b", .{}, null);
    try g.setEdge("a", "c", .{}, null);
    try g.setEdge("b", "d", .{}, null);
    try g.setEdge("c", "d", .{}, null);

    const layers = try initOrder(testing.allocator, &g);
    defer {
        for (layers) |layer| {
            for (layer) |id| testing.allocator.free(id);
            testing.allocator.free(layer);
        }
        testing.allocator.free(layers);
    }

    assignOrder(&g, layers);

    try testing.expectEqual(@as(?usize, 0), g.getNode("a").?.order);
    try testing.expect(g.getNode("b").?.order != null);
    try testing.expect(g.getNode("c").?.order != null);
    try testing.expectEqual(@as(?usize, 0), g.getNode("d").?.order);
}
