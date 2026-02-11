//! Longest path ranking algorithm
//!
//! A simple O(V+E) algorithm that assigns ranks based on the longest path
//! from any source node.

const std = @import("std");
const Digraph = @import("../../../graph/digraph.zig").Digraph;
const EdgeKey = @import("../../../graph/digraph.zig").EdgeKey;
const model = @import("../../../model.zig");
const NodeData = model.NodeData;
const EdgeData = model.EdgeData;
const GraphData = model.GraphData;

/// Assign ranks using the longest path algorithm
pub fn run(allocator: std.mem.Allocator, graph: *Digraph(NodeData, EdgeData, GraphData)) !void {
    // Get all nodes
    const all_nodes = try graph.allNodes(allocator);
    defer {
        for (all_nodes) |node_id| {
            allocator.free(node_id);
        }
        allocator.free(all_nodes);
    }

    // Initialize all ranks to null
    for (all_nodes) |node_id| {
        if (graph.getNodePtr(node_id)) |node| {
            node.rank = null;
        }
    }

    // Find source nodes (no predecessors) and set them to rank 0.
    // Skip subgraph (container) nodes — they don't participate in layout;
    // their position is computed post-layout from their children's bounds.
    for (all_nodes) |node_id| {
        const node = graph.getNodePtr(node_id) orelse continue;
        if (node.is_subgraph) continue;

        const in_edges = graph.inEdges(node_id) orelse &[_]EdgeKey{};
        if (in_edges.len == 0) {
            node.rank = 0;
        }
    }

    // Iteratively assign ranks until all nodes have ranks
    // Use a fixed-point iteration approach
    var changed = true;
    var iterations: usize = 0;
    const max_iterations = all_nodes.len * 10; // Safety limit

    while (changed and iterations < max_iterations) {
        changed = false;
        iterations += 1;

        for (all_nodes) |node_id| {
            const node = graph.getNodePtr(node_id) orelse continue;

            // Skip subgraph nodes — they are containers, not layout nodes.
            if (node.is_subgraph) continue;

            // If node already has a rank, check if we need to update it
            const in_edges = graph.inEdges(node_id) orelse &[_]EdgeKey{};
            if (in_edges.len == 0) {
                // Source node - should already be rank 0
                continue;
            }

            // Calculate rank as max(predecessor_rank + minlen) over all predecessors
            var max_rank: ?i32 = null;
            var all_preds_have_rank = true;

            for (in_edges) |edge_key| {
                const pred_node = graph.getNode(edge_key.v) orelse continue;

                if (pred_node.rank) |pred_rank| {
                    const edge_data = graph.edge(edge_key.v, edge_key.w, edge_key.name) orelse continue;
                    const candidate = pred_rank + edge_data.minlen;

                    if (max_rank) |mr| {
                        max_rank = @max(mr, candidate);
                    } else {
                        max_rank = candidate;
                    }
                } else {
                    all_preds_have_rank = false;
                }
            }

            // Only update if all predecessors have ranks
            if (all_preds_have_rank and max_rank != null) {
                if (node.rank) |current_rank| {
                    if (max_rank.? > current_rank) {
                        node.rank = max_rank.?;
                        changed = true;
                    }
                } else {
                    node.rank = max_rank.?;
                    changed = true;
                }
            }
        }
    }

    // Tighten sources: move isolated sources closer to their targets
    for (all_nodes) |node_id| {
        const node_check = graph.getNode(node_id) orelse continue;
        if (node_check.is_subgraph) continue;

        const in_edges = graph.inEdges(node_id) orelse &[_]EdgeKey{};
        if (in_edges.len > 0) continue; // Not a source

        const out_edges = graph.outEdges(node_id) orelse &[_]EdgeKey{};
        if (out_edges.len == 0) continue; // Isolated node

        var min_successor_rank: i32 = std.math.maxInt(i32);
        for (out_edges) |edge_key| {
            const succ_node = graph.getNode(edge_key.w) orelse continue;
            const succ_rank = succ_node.rank orelse continue;

            const edge_data = graph.edge(edge_key.v, edge_key.w, edge_key.name) orelse continue;
            const minlen = edge_data.minlen;
            min_successor_rank = @min(min_successor_rank, succ_rank - minlen);
        }

        if (min_successor_rank > 0 and min_successor_rank != std.math.maxInt(i32)) {
            if (graph.getNodePtr(node_id)) |node| {
                node.rank = min_successor_rank;
            }
        }
    }
}

// Tests
const testing = std.testing;

test "longest_path: single node" {
    var graph = Digraph(NodeData, EdgeData, GraphData).init(testing.allocator);
    defer graph.deinit();

    try graph.setNode("a", .{});

    try run(testing.allocator, &graph);

    try testing.expectEqual(@as(?i32, 0), graph.getNode("a").?.rank);
}

test "longest_path: chain" {
    var graph = Digraph(NodeData, EdgeData, GraphData).init(testing.allocator);
    defer graph.deinit();

    try graph.setNode("a", .{});
    try graph.setNode("b", .{});
    try graph.setNode("c", .{});
    try graph.setEdge("a", "b", .{}, null);
    try graph.setEdge("b", "c", .{}, null);

    try run(testing.allocator, &graph);

    try testing.expectEqual(@as(?i32, 0), graph.getNode("a").?.rank);
    try testing.expectEqual(@as(?i32, 1), graph.getNode("b").?.rank);
    try testing.expectEqual(@as(?i32, 2), graph.getNode("c").?.rank);
}

test "longest_path: diamond" {
    var graph = Digraph(NodeData, EdgeData, GraphData).init(testing.allocator);
    defer graph.deinit();

    try graph.setNode("a", .{});
    try graph.setNode("b", .{});
    try graph.setNode("c", .{});
    try graph.setNode("d", .{});
    try graph.setEdge("a", "b", .{}, null);
    try graph.setEdge("b", "d", .{}, null);
    try graph.setEdge("a", "c", .{}, null);
    try graph.setEdge("c", "d", .{}, null);

    try run(testing.allocator, &graph);

    try testing.expectEqual(@as(?i32, 0), graph.getNode("a").?.rank);
    try testing.expectEqual(@as(?i32, 1), graph.getNode("b").?.rank);
    try testing.expectEqual(@as(?i32, 1), graph.getNode("c").?.rank);
    try testing.expectEqual(@as(?i32, 2), graph.getNode("d").?.rank);
}

test "longest_path: respects minlen" {
    var graph = Digraph(NodeData, EdgeData, GraphData).init(testing.allocator);
    defer graph.deinit();

    try graph.setNode("a", .{});
    try graph.setNode("b", .{});
    try graph.setEdge("a", "b", .{ .minlen = 3 }, null);

    try run(testing.allocator, &graph);

    try testing.expectEqual(@as(?i32, 0), graph.getNode("a").?.rank);
    try testing.expectEqual(@as(?i32, 3), graph.getNode("b").?.rank);
}

test "longest_path: isolated node" {
    var graph = Digraph(NodeData, EdgeData, GraphData).init(testing.allocator);
    defer graph.deinit();

    try graph.setNode("a", .{});
    try graph.setNode("b", .{});
    try graph.setEdge("a", "b", .{}, null);

    try graph.setNode("orphan", .{});

    try run(testing.allocator, &graph);

    try testing.expectEqual(@as(?i32, 0), graph.getNode("orphan").?.rank);
}
