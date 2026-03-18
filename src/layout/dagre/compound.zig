const std = @import("std");
const Digraph = @import("../../graph/digraph.zig").Digraph;
const model = @import("../../model.zig");

const NodeData = model.NodeData;
const EdgeData = model.EdgeData;
const GraphData = model.GraphData;
const Graph = Digraph(NodeData, EdgeData, GraphData);

pub fn assignRankMinMax(graph: *Graph) void {
    var max_rank: i32 = 0;

    var node_it = graph.nodes.iterator();
    while (node_it.next()) |entry| {
        const id = entry.key_ptr.*;
        if (graph.getChildren(id).len == 0) continue;

        const node = entry.value_ptr.*;
        const border_top = node.border_top orelse continue;
        const border_bottom = node.border_bottom orelse continue;
        const top_rank = (graph.getNode(border_top) orelse continue).rank orelse continue;
        const bottom_rank = (graph.getNode(border_bottom) orelse continue).rank orelse continue;

        if (graph.getNodePtr(id)) |ptr| {
            ptr.min_rank = top_rank;
            ptr.max_rank = bottom_rank;
        }

        if (bottom_rank > max_rank) max_rank = bottom_rank;
    }

    graph.graph_label.max_rank = max_rank;
}

pub fn addBorderSegments(allocator: std.mem.Allocator, graph: *Graph) !void {
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
        try dfsAddBorderSegments(allocator, graph, root_id);
    }
}

fn dfsAddBorderSegments(allocator: std.mem.Allocator, graph: *Graph, node_id: []const u8) !void {
    var children = std.ArrayListUnmanaged([]const u8){};
    defer children.deinit(allocator);

    for (graph.getChildren(node_id)) |child_id| {
        const child = graph.getNode(child_id) orelse continue;
        if (child.dummy_kind != null and child.dummy_kind.? == .border) continue;
        try children.append(allocator, child_id);
    }

    for (children.items) |child_id| {
        try dfsAddBorderSegments(allocator, graph, child_id);
    }

    const node = graph.getNode(node_id) orelse return;
    const min_rank = node.min_rank orelse return;
    const max_rank = node.max_rank orelse return;
    if (max_rank < min_rank) return;

    if (graph.getNodePtr(node_id)) |ptr| {
        ptr.border_left.deinit(allocator);
        ptr.border_left = .{};
        ptr.border_right.deinit(allocator);
        ptr.border_right = .{};

        const count = @as(usize, @intCast(max_rank - min_rank + 1));
        try ptr.border_left.ensureTotalCapacity(allocator, count);
        try ptr.border_right.ensureTotalCapacity(allocator, count);
        var i: usize = 0;
        while (i < count) : (i += 1) {
            ptr.border_left.appendAssumeCapacity(null);
            ptr.border_right.appendAssumeCapacity(null);
        }
    }

    var rank = min_rank;
    while (rank <= max_rank) : (rank += 1) {
        try addBorderNode(allocator, graph, node_id, rank, .left);
        try addBorderNode(allocator, graph, node_id, rank, .right);
    }
}

fn addBorderNode(
    allocator: std.mem.Allocator,
    graph: *Graph,
    subgraph_id: []const u8,
    rank: i32,
    side: model.BorderKind,
) !void {
    const prefix = switch (side) {
        .left => "_bl",
        .right => "_br",
        else => unreachable,
    };
    const border_width: f64 = 10.0;
    const id = try std.fmt.allocPrint(allocator, "{s}{d}", .{ prefix, graph.graph_label.dummy_chains.items.len });
    try graph.graph_label.dummy_chains.append(allocator, id);
    try graph.setNode(id, .{
        .width = border_width,
        .height = 0.0,
        .rank = rank,
        .dummy = true,
        .dummy_kind = .border,
        .border_kind = side,
    });
    try graph.setParent(id, subgraph_id);

    const min_rank = (graph.getNode(subgraph_id) orelse return).min_rank orelse return;
    const idx = @as(usize, @intCast(rank - min_rank));

    var prev_id: ?[]const u8 = null;
    if (graph.getNode(subgraph_id)) |node| {
        if (idx > 0) {
            prev_id = switch (side) {
                .left => node.border_left.items[idx - 1],
                .right => node.border_right.items[idx - 1],
                else => null,
            };
        }
    }

    if (graph.getNodePtr(subgraph_id)) |ptr| {
        switch (side) {
            .left => ptr.border_left.items[idx] = id,
            .right => ptr.border_right.items[idx] = id,
            else => {},
        }
    }

    if (prev_id) |prev| {
        try graph.setEdge(prev, id, .{ .weight = 1 }, null);
    }
}

const testing = std.testing;

test "compound assignRankMinMax derives rank bounds from top and bottom borders" {
    var graph = Graph.init(testing.allocator);
    defer {
        @import("normalize.zig").freeDummyIds(testing.allocator, &graph);
        graph.deinitDeep();
    }

    try graph.setNode("cluster", .{ .is_subgraph = true });
    try graph.setNode("top", .{ .rank = 2, .dummy = true, .dummy_kind = .border, .border_kind = .top });
    try graph.setNode("bottom", .{ .rank = 5, .dummy = true, .dummy_kind = .border, .border_kind = .bottom });
    try graph.setParent("top", "cluster");
    try graph.setParent("bottom", "cluster");
    if (graph.getNodePtr("cluster")) |ptr| {
        ptr.border_top = "top";
        ptr.border_bottom = "bottom";
    }

    assignRankMinMax(&graph);

    const cluster = graph.getNode("cluster").?;
    try testing.expectEqual(@as(?i32, 2), cluster.min_rank);
    try testing.expectEqual(@as(?i32, 5), cluster.max_rank);
    try testing.expectEqual(@as(?i32, 5), graph.graph_label.max_rank);
}

test "compound addBorderSegments creates per-rank left and right chains" {
    var graph = Graph.init(testing.allocator);
    defer {
        @import("normalize.zig").freeDummyIds(testing.allocator, &graph);
        graph.deinitDeep();
    }

    try graph.setNode("cluster", .{ .is_subgraph = true, .min_rank = 1, .max_rank = 3 });
    try graph.setNode("leaf", .{});
    try graph.setParent("leaf", "cluster");

    try addBorderSegments(testing.allocator, &graph);

    const cluster = graph.getNode("cluster").?;
    try testing.expectEqual(@as(usize, 3), cluster.border_left.items.len);
    try testing.expectEqual(@as(usize, 3), cluster.border_right.items.len);

    for (cluster.border_left.items, 0..) |maybe_id, idx| {
        const id = maybe_id orelse return error.TestExpectedEqual;
        const node = graph.getNode(id).?;
        try testing.expectEqual(model.BorderKind.left, node.border_kind.?);
        try testing.expectEqual(@as(?i32, @intCast(idx + 1)), node.rank);
    }
    for (cluster.border_right.items, 0..) |maybe_id, idx| {
        const id = maybe_id orelse return error.TestExpectedEqual;
        const node = graph.getNode(id).?;
        try testing.expectEqual(model.BorderKind.right, node.border_kind.?);
        try testing.expectEqual(@as(?i32, @intCast(idx + 1)), node.rank);
    }

    try testing.expect(graph.edge(cluster.border_left.items[0].?, cluster.border_left.items[1].?, null) != null);
    try testing.expect(graph.edge(cluster.border_right.items[1].?, cluster.border_right.items[2].?, null) != null);
}
