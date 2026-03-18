const std = @import("std");
const Digraph = @import("../../graph/digraph.zig").Digraph;
const model = @import("../../model.zig");

const NodeData = model.NodeData;
const EdgeData = model.EdgeData;
const GraphData = model.GraphData;
const Graph = Digraph(NodeData, EdgeData, GraphData);

pub fn run(allocator: std.mem.Allocator, graph: *Graph) !void {
    if (!hasCompoundNodes(graph)) return;

    var depths = std.StringHashMap(i32).init(allocator);
    defer depths.deinit();
    try computeTreeDepths(allocator, graph, &depths);

    var max_depth: i32 = 1;
    var depth_it = depths.valueIterator();
    while (depth_it.next()) |depth| {
        if (depth.* > max_depth) max_depth = depth.*;
    }

    const height = @max(max_depth - 1, 0);
    const node_sep: i32 = if (height > 0) 2 * height + 1 else 1;

    var edge_it = graph.edgeIterator();
    while (edge_it.next()) |entry| {
        if (graph.getEdgePtr(entry.v, entry.w, entry.name)) |edge| {
            edge.minlen *= node_sep;
        }
    }

    const total_weight = sumEdgeWeights(graph) + 1;
    const root = try addDummyNode(allocator, graph, "_root", .{ .dummy = true, .dummy_kind = .nesting });
    graph.graph_label.nesting_root = root;

    var node_it = graph.nodes.iterator();
    while (node_it.next()) |entry| {
        const id = entry.key_ptr.*;
        if (graph.getParent(id) != null) continue;
        if (std.mem.eql(u8, id, root)) continue;
        try dfsCreateNesting(allocator, graph, root, node_sep, total_weight, height, &depths, id);
    }

    graph.graph_label.node_rank_factor = node_sep;
}

pub fn cleanup(graph: *Graph) void {
    const root = graph.graph_label.nesting_root;
    graph.graph_label.nesting_root = null;

    var nesting_edges = std.ArrayListUnmanaged(struct { v: []const u8, w: []const u8, name: ?[]const u8 }){};
    defer nesting_edges.deinit(graph.allocator);

    var edge_it = graph.edgeIterator();
    while (edge_it.next()) |entry| {
        if (!entry.data.nesting_edge) continue;
        nesting_edges.append(graph.allocator, .{ .v = entry.v, .w = entry.w, .name = entry.name }) catch continue;
    }

    if (root) |root_id| {
        graph.removeNode(root_id);
    }

    for (nesting_edges.items) |edge| {
        if (graph.hasEdge(edge.v, edge.w, edge.name)) {
            graph.removeEdge(edge.v, edge.w, edge.name);
        }
    }
}

fn hasCompoundNodes(graph: *Graph) bool {
    var node_it = graph.nodes.iterator();
    while (node_it.next()) |entry| {
        if (!entry.value_ptr.is_subgraph) continue;
        if (graph.getChildren(entry.key_ptr.*).len > 0) return true;
    }
    return false;
}

fn computeTreeDepths(
    allocator: std.mem.Allocator,
    graph: *Graph,
    depths: *std.StringHashMap(i32),
) !void {
    var roots = std.ArrayListUnmanaged([]const u8){};
    defer roots.deinit(allocator);

    var node_it = graph.nodes.iterator();
    while (node_it.next()) |entry| {
        const id = entry.key_ptr.*;
        if (graph.getParent(id) == null) {
            try roots.append(allocator, id);
        }
    }

    for (roots.items) |root_id| {
        try dfsDepth(graph, depths, root_id, 1);
    }
}

fn dfsDepth(graph: *Graph, depths: *std.StringHashMap(i32), node_id: []const u8, depth: i32) !void {
    const children = graph.getChildren(node_id);
    for (children) |child_id| {
        try dfsDepth(graph, depths, child_id, depth + 1);
    }
    try depths.put(node_id, depth);
}

fn dfsCreateNesting(
    allocator: std.mem.Allocator,
    graph: *Graph,
    root: []const u8,
    node_sep: i32,
    total_weight: i32,
    height: i32,
    depths: *const std.StringHashMap(i32),
    node_id: []const u8,
) !void {
    var children = std.ArrayListUnmanaged([]const u8){};
    defer children.deinit(allocator);

    for (graph.getChildren(node_id)) |child_id| {
        const child = graph.getNode(child_id) orelse continue;
        if (child.dummy_kind != null and child.dummy_kind.? == .border) continue;
        try children.append(allocator, child_id);
    }

    if (children.items.len == 0) {
        if (!std.mem.eql(u8, node_id, root)) {
            try graph.setEdge(root, node_id, .{
                .weight = 0,
                .minlen = node_sep,
                .nesting_edge = true,
            }, null);
        }
        return;
    }

    const top = try addDummyNode(allocator, graph, "_bt", .{
        .dummy = true,
        .dummy_kind = .border,
        .border_kind = .top,
    });
    const bottom = try addDummyNode(allocator, graph, "_bb", .{
        .dummy = true,
        .dummy_kind = .border,
        .border_kind = .bottom,
    });

    try graph.setParent(top, node_id);
    try graph.setParent(bottom, node_id);

    if (graph.getNodePtr(node_id)) |node| {
        node.border_top = top;
        node.border_bottom = bottom;
    }

    for (children.items) |child_id| {
        try dfsCreateNesting(allocator, graph, root, node_sep, total_weight, height, depths, child_id);

        const child_node = graph.getNode(child_id) orelse continue;
        const child_top = child_node.border_top orelse child_id;
        const child_bottom = child_node.border_bottom orelse child_id;
        const child_has_border = child_node.border_top != null;
        const edge_weight = if (child_has_border) total_weight else 2 * total_weight;
        const node_depth = depths.get(node_id) orelse 0;
        const minlen = if (!std.mem.eql(u8, child_top, child_bottom)) 1 else height - node_depth + 1;

        try graph.setEdge(top, child_top, .{
            .weight = edge_weight,
            .minlen = minlen,
            .nesting_edge = true,
        }, null);
        try graph.setEdge(child_bottom, bottom, .{
            .weight = edge_weight,
            .minlen = minlen,
            .nesting_edge = true,
        }, null);
    }

    if (graph.getParent(node_id) == null) {
        const node_depth = depths.get(node_id) orelse 0;
        try graph.setEdge(root, top, .{
            .weight = 0,
            .minlen = height + node_depth,
            .nesting_edge = true,
        }, null);
    }
}

fn addDummyNode(
    allocator: std.mem.Allocator,
    graph: *Graph,
    prefix: []const u8,
    label: NodeData,
) ![]const u8 {
    const id = try std.fmt.allocPrint(allocator, "{s}{d}", .{ prefix, graph.graph_label.dummy_chains.items.len });
    try graph.graph_label.dummy_chains.append(allocator, id);
    try graph.setNode(id, label);
    return id;
}

fn sumEdgeWeights(graph: *Graph) i32 {
    var total: i32 = 0;
    var edge_it = graph.edgeIterator();
    while (edge_it.next()) |entry| {
        total += entry.data.weight;
    }
    return total;
}

const testing = std.testing;

test "nesting run creates top and bottom border dummies" {
    var graph = Graph.init(testing.allocator);
    defer {
        @import("normalize.zig").freeDummyIds(testing.allocator, &graph);
        graph.deinitDeep();
    }

    try graph.setNode("cluster", .{ .is_subgraph = true });
    try graph.setNode("child", .{});
    try graph.setParent("child", "cluster");

    try run(testing.allocator, &graph);

    const cluster = graph.getNode("cluster").?;
    try testing.expect(cluster.border_top != null);
    try testing.expect(cluster.border_bottom != null);
    try testing.expect(graph.graph_label.nesting_root != null);
    try testing.expect(graph.graph_label.node_rank_factor != null);

    const top = graph.getNode(cluster.border_top.?).?;
    const bottom = graph.getNode(cluster.border_bottom.?).?;
    try testing.expectEqual(model.DummyKind.border, top.dummy_kind.?);
    try testing.expectEqual(model.BorderKind.top, top.border_kind.?);
    try testing.expectEqual(model.BorderKind.bottom, bottom.border_kind.?);
}

test "nesting run marks nesting edges and scales minlen" {
    var graph = Graph.init(testing.allocator);
    defer {
        @import("normalize.zig").freeDummyIds(testing.allocator, &graph);
        graph.deinitDeep();
    }

    try graph.setNode("outer", .{ .is_subgraph = true });
    try graph.setNode("inner", .{ .is_subgraph = true });
    try graph.setNode("leaf", .{});
    try graph.setParent("inner", "outer");
    try graph.setParent("leaf", "inner");
    try graph.setEdge("inner", "leaf", .{ .minlen = 2, .weight = 3 }, null);

    try run(testing.allocator, &graph);

    const scaled = graph.edge("inner", "leaf", null).?;
    try testing.expectEqual(@as(i32, 5), graph.graph_label.node_rank_factor.?);
    try testing.expectEqual(@as(i32, 10), scaled.minlen);

    var found_nesting_edge = false;
    var edge_it = graph.edgeIterator();
    while (edge_it.next()) |entry| {
        if (entry.data.nesting_edge) {
            found_nesting_edge = true;
            break;
        }
    }
    try testing.expect(found_nesting_edge);
}

test "nesting cleanup removes nesting root and nesting edges" {
    var graph = Graph.init(testing.allocator);
    defer {
        @import("normalize.zig").freeDummyIds(testing.allocator, &graph);
        graph.deinitDeep();
    }

    try graph.setNode("cluster", .{ .is_subgraph = true });
    try graph.setNode("child", .{});
    try graph.setParent("child", "cluster");

    try run(testing.allocator, &graph);
    const border_top = graph.getNode("cluster").?.border_top.?;

    cleanup(&graph);

    try testing.expect(graph.graph_label.nesting_root == null);
    try testing.expect(graph.hasNode(border_top));

    var edge_it = graph.edgeIterator();
    while (edge_it.next()) |entry| {
        try testing.expect(!entry.data.nesting_edge);
    }
}
