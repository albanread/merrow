//! Utility functions for ranking algorithms

const std = @import("std");
const Digraph = @import("../../../graph/digraph.zig").Digraph;
const model = @import("../../../model.zig");
const NodeData = model.NodeData;
const EdgeData = model.EdgeData;
const GraphData = model.GraphData;

/// Normalize ranks so that the minimum rank is 0
pub fn normalizeRanks(graph: *Digraph(NodeData, EdgeData, GraphData)) !void {
    const allocator = graph.allocator;

    // Find minimum rank
    const all_nodes = try graph.allNodes(allocator);
    defer {
        for (all_nodes) |node_id| {
            allocator.free(node_id);
        }
        allocator.free(all_nodes);
    }

    if (all_nodes.len == 0) return;

    var min_rank: ?i32 = null;
    for (all_nodes) |node_id| {
        if (graph.getNode(node_id)) |node| {
            if (node.rank) |rank| {
                if (min_rank) |mr| {
                    min_rank = @min(mr, rank);
                } else {
                    min_rank = rank;
                }
            }
        }
    }

    const min_rank_val = min_rank orelse return;
    if (min_rank_val == 0) return;

    // Adjust all ranks
    const nodes_to_adjust = try graph.allNodes(allocator);
    defer {
        for (nodes_to_adjust) |node_id| {
            allocator.free(node_id);
        }
        allocator.free(nodes_to_adjust);
    }

    for (nodes_to_adjust) |node_id| {
        if (graph.getNodePtr(node_id)) |node| {
            if (node.rank) |rank| {
                node.rank = rank - min_rank_val;
            }
        }
    }
}

/// Calculate the slack of an edge: actual rank difference minus minlen
/// Returns null if either node doesn't have a rank assigned
pub fn slack(
    graph: *const Digraph(NodeData, EdgeData, GraphData),
    v: []const u8,
    w: []const u8,
) ?i32 {
    const v_node = graph.getNode(v) orelse return null;
    const w_node = graph.getNode(w) orelse return null;

    const v_rank = v_node.rank orelse return null;
    const w_rank = w_node.rank orelse return null;

    const edge_data = graph.edge(v, w, null) orelse return null;
    const minlen = edge_data.minlen;

    return w_rank - v_rank - minlen;
}

// Tests
const testing = std.testing;

test "normalizeRanks: empty graph" {
    var graph = Digraph(NodeData, EdgeData, GraphData).init(testing.allocator);
    defer graph.deinit();

    try normalizeRanks(&graph);
}

test "normalizeRanks: already normalized" {
    var graph = Digraph(NodeData, EdgeData, GraphData).init(testing.allocator);
    defer graph.deinit();

    try graph.setNode("a", .{ .rank = 0 });
    try graph.setNode("b", .{ .rank = 2 });

    try normalizeRanks(&graph);

    try testing.expectEqual(@as(?i32, 0), graph.getNode("a").?.rank);
    try testing.expectEqual(@as(?i32, 2), graph.getNode("b").?.rank);
}

test "normalizeRanks: shifts to zero" {
    var graph = Digraph(NodeData, EdgeData, GraphData).init(testing.allocator);
    defer graph.deinit();

    try graph.setNode("a", .{ .rank = 2 });
    try graph.setNode("b", .{ .rank = 4 });

    try normalizeRanks(&graph);

    try testing.expectEqual(@as(?i32, 0), graph.getNode("a").?.rank);
    try testing.expectEqual(@as(?i32, 2), graph.getNode("b").?.rank);
}

test "normalizeRanks: negative ranks" {
    var graph = Digraph(NodeData, EdgeData, GraphData).init(testing.allocator);
    defer graph.deinit();

    try graph.setNode("a", .{ .rank = -3 });
    try graph.setNode("b", .{ .rank = 1 });

    try normalizeRanks(&graph);

    try testing.expectEqual(@as(?i32, 0), graph.getNode("a").?.rank);
    try testing.expectEqual(@as(?i32, 4), graph.getNode("b").?.rank);
}

test "slack: basic calculation" {
    var graph = Digraph(NodeData, EdgeData, GraphData).init(testing.allocator);
    defer graph.deinit();

    try graph.setNode("a", .{ .rank = 0 });
    try graph.setNode("b", .{ .rank = 3 });
    try graph.setEdge("a", "b", .{ .minlen = 1 }, null);

    const result = slack(&graph, "a", "b");
    try testing.expectEqual(@as(?i32, 2), result); // 3 - 0 - 1 = 2
}

test "slack: zero slack" {
    var graph = Digraph(NodeData, EdgeData, GraphData).init(testing.allocator);
    defer graph.deinit();

    try graph.setNode("a", .{ .rank = 0 });
    try graph.setNode("b", .{ .rank = 1 });
    try graph.setEdge("a", "b", .{ .minlen = 1 }, null);

    const result = slack(&graph, "a", "b");
    try testing.expectEqual(@as(?i32, 0), result); // 3 - 0 - 1 = 0 (tight edge)
}

test "slack: negative slack" {
    var graph = Digraph(NodeData, EdgeData, GraphData).init(testing.allocator);
    defer graph.deinit();

    try graph.setNode("a", .{ .rank = 5 });
    try graph.setNode("b", .{ .rank = 6 });
    try graph.setEdge("a", "b", .{ .minlen = 3 }, null);

    const result = slack(&graph, "a", "b");
    try testing.expectEqual(@as(?i32, -2), result); // 6 - 5 - 3 = -2
}

test "slack: null when node missing" {
    var graph = Digraph(NodeData, EdgeData, GraphData).init(testing.allocator);
    defer graph.deinit();

    try graph.setNode("a", .{ .rank = 0 });

    const result = slack(&graph, "a", "b");
    try testing.expectEqual(@as(?i32, null), result);
}

test "slack: null when rank not assigned" {
    var graph = Digraph(NodeData, EdgeData, GraphData).init(testing.allocator);
    defer graph.deinit();

    try graph.setNode("a", .{});
    try graph.setNode("b", .{ .rank = 1 });
    try graph.setEdge("a", "b", .{}, null);

    const result = slack(&graph, "a", "b");
    try testing.expectEqual(@as(?i32, null), result);
}
