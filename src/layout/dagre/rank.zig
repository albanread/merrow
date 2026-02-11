//! Rank assignment algorithms for dagre layout
//!
//! Assigns each node to a layer (rank) in the graph. The goal is to minimize
//! the total edge length while respecting minimum length constraints.

const std = @import("std");
const Digraph = @import("../../graph/digraph.zig").Digraph;
const EdgeKey = @import("../../graph/digraph.zig").EdgeKey;
const model = @import("../../model.zig");
const NodeData = model.NodeData;
const EdgeData = model.EdgeData;
const GraphData = model.GraphData;
const Ranker = @import("../dagre.zig").Ranker;

pub const util = @import("rank/util.zig");
pub const longest_path = @import("rank/longest_path.zig");
pub const network_simplex = @import("rank/network_simplex.zig");

/// Assign ranks to all nodes in the graph
pub fn assignRanks(
    allocator: std.mem.Allocator,
    graph: *Digraph(NodeData, EdgeData, GraphData),
    method: Ranker,
) !void {
    switch (method) {
        .longest_path => {
            try longest_path.run(allocator, graph);
            // Pull source-only nodes closer to their targets to minimize edge length.
            // Longest-path assigns all source nodes to rank 0, but nodes that only
            // connect to targets at deeper ranks should be pulled down to reduce
            // edge length and produce narrower layouts.
            try pullSourcesTowardTargets(allocator, graph);
        },
        .tight_tree => {
            // Tight tree uses longest path as initial assignment, then tightens
            try longest_path.run(allocator, graph);
            // TODO: implement tight tree refinement
        },
        .network_simplex => {
            try network_simplex.run(allocator, graph);
        },
    }

    // Normalize ranks to start at 0
    try util.normalizeRanks(graph);
}

/// After longest-path ranking, pull source-only nodes down toward their targets.
///
/// Longest-path assigns all source nodes (no predecessors) to rank 0.
/// But for nodes that connect to targets at deeper ranks, this creates
/// unnecessarily long edges. This post-processing step moves such nodes
/// as close to their targets as possible, matching network-simplex behavior.
fn pullSourcesTowardTargets(
    allocator: std.mem.Allocator,
    graph: *Digraph(NodeData, EdgeData, GraphData),
) !void {
    const all_nodes = try graph.allNodes(allocator);
    defer {
        for (all_nodes) |node_id| {
            allocator.free(node_id);
        }
        allocator.free(all_nodes);
    }

    for (all_nodes) |v| {
        // Only process source nodes (no incoming edges)
        const in_edges = graph.inEdges(v) orelse &[_]EdgeKey{};
        if (in_edges.len > 0) {
            continue;
        }

        const out_edges = graph.outEdges(v) orelse &[_]EdgeKey{};
        const has_out_edges = out_edges.len > 0;

        if (!has_out_edges) {
            continue; // Disconnected node, leave at rank 0
        }

        // Find the minimum rank we can assign and the minimum minlen.
        // The minlen matters because make_space_for_edge_labels doubles it,
        // which inflates apparent rank spans.
        var max_rank: i32 = std.math.maxInt(i32);
        var min_minlen: i32 = std.math.maxInt(i32);

        for (out_edges) |edge_key| {
            const target_node = graph.getNode(edge_key.w) orelse continue;
            const target_rank = target_node.rank orelse continue;

            const edge_data = graph.edge(edge_key.v, edge_key.w, edge_key.name) orelse continue;
            const minlen = edge_data.minlen;
            max_rank = @min(max_rank, target_rank - minlen);
            min_minlen = @min(min_minlen, minlen);
        }

        // Only pull when the rank gap exceeds one "real" layer (minlen).
        // After make_space_for_edge_labels doubles minlen, a 2-layer span
        // becomes a 4-rank gap. Using minlen as threshold ensures we only
        // pull when there are genuinely multiple layers of slack.
        if (max_rank != std.math.maxInt(i32) and min_minlen != std.math.maxInt(i32)) {
            if (graph.getNodePtr(v)) |node| {
                if (node.rank) |current_rank| {
                    if (max_rank - current_rank > min_minlen) {
                        node.rank = max_rank;
                    }
                }
            }
        }
    }
}

// Tests
const testing = std.testing;

test "assignRanks: single node" {
    var graph = Digraph(NodeData, EdgeData, GraphData).init(testing.allocator);
    defer graph.deinit();

    try graph.setNode("a", .{});

    try assignRanks(testing.allocator, &graph, .longest_path);

    try testing.expectEqual(@as(?i32, 0), graph.getNode("a").?.rank);
}

test "assignRanks: two connected nodes" {
    var graph = Digraph(NodeData, EdgeData, GraphData).init(testing.allocator);
    defer graph.deinit();

    try graph.setNode("a", .{});
    try graph.setNode("b", .{});
    try graph.setEdge("a", "b", .{}, null);

    try assignRanks(testing.allocator, &graph, .longest_path);

    try testing.expectEqual(@as(?i32, 0), graph.getNode("a").?.rank);
    try testing.expectEqual(@as(?i32, 1), graph.getNode("b").?.rank);
}

test "assignRanks: diamond" {
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

    try assignRanks(testing.allocator, &graph, .longest_path);

    try testing.expectEqual(@as(?i32, 0), graph.getNode("a").?.rank);
    try testing.expectEqual(@as(?i32, 1), graph.getNode("b").?.rank);
    try testing.expectEqual(@as(?i32, 1), graph.getNode("c").?.rank);
    try testing.expectEqual(@as(?i32, 2), graph.getNode("d").?.rank);
}

test "assignRanks: respects minlen" {
    var graph = Digraph(NodeData, EdgeData, GraphData).init(testing.allocator);
    defer graph.deinit();

    try graph.setNode("a", .{});
    try graph.setNode("b", .{});
    try graph.setNode("c", .{});
    try graph.setNode("d", .{});
    try graph.setEdge("a", "b", .{}, null);
    try graph.setEdge("b", "d", .{}, null);
    try graph.setEdge("a", "c", .{}, null);
    try graph.setEdge("c", "d", .{ .minlen = 2 }, null);

    try assignRanks(testing.allocator, &graph, .longest_path);

    const a_rank = graph.getNode("a").?.rank.?;
    const c_rank = graph.getNode("c").?.rank.?;
    const d_rank = graph.getNode("d").?.rank.?;

    // c -> d should be at least 2 ranks apart
    try testing.expect(d_rank - c_rank >= 2);
    try testing.expect(c_rank >= a_rank);
}

test "assignRanks: gansner graph" {
    // The classic example from the paper (Gansner et al. 1993)
    var graph = Digraph(NodeData, EdgeData, GraphData).init(testing.allocator);
    defer graph.deinit();

    try graph.setNode("a", .{});
    try graph.setNode("b", .{});
    try graph.setNode("c", .{});
    try graph.setNode("d", .{});
    try graph.setNode("e", .{});
    try graph.setNode("f", .{});
    try graph.setNode("g", .{});
    try graph.setNode("h", .{});

    // Path: a -> b -> c -> d -> h
    try graph.setEdge("a", "b", .{}, null);
    try graph.setEdge("b", "c", .{}, null);
    try graph.setEdge("c", "d", .{}, null);
    try graph.setEdge("d", "h", .{}, null);

    // Path: a -> e -> g -> h
    try graph.setEdge("a", "e", .{}, null);
    try graph.setEdge("e", "g", .{}, null);
    try graph.setEdge("g", "h", .{}, null);

    // Path: a -> f -> g
    try graph.setEdge("a", "f", .{}, null);
    try graph.setEdge("f", "g", .{}, null);

    try assignRanks(testing.allocator, &graph, .longest_path);

    try testing.expectEqual(@as(?i32, 0), graph.getNode("a").?.rank);
    try testing.expectEqual(@as(?i32, 1), graph.getNode("b").?.rank);
    try testing.expectEqual(@as(?i32, 2), graph.getNode("c").?.rank);
    try testing.expectEqual(@as(?i32, 3), graph.getNode("d").?.rank);
    try testing.expectEqual(@as(?i32, 4), graph.getNode("h").?.rank);
    try testing.expectEqual(@as(?i32, 1), graph.getNode("e").?.rank);
    try testing.expectEqual(@as(?i32, 1), graph.getNode("f").?.rank);
    try testing.expectEqual(@as(?i32, 2), graph.getNode("g").?.rank);
}

test "assignRanks: flowchart diamond structure" {
    // This replicates a common case from flowchart rendering:
    // A -> B -> C -> D, C -> E, D -> F, E -> F
    var graph = Digraph(NodeData, EdgeData, GraphData).init(testing.allocator);
    defer graph.deinit();

    try graph.setNode("A", .{});
    try graph.setNode("B", .{});
    try graph.setNode("C", .{});
    try graph.setNode("D", .{});
    try graph.setNode("E", .{});
    try graph.setNode("F", .{});

    try graph.setEdge("A", "B", .{}, null);
    try graph.setEdge("B", "C", .{}, null);
    try graph.setEdge("C", "D", .{}, null);
    try graph.setEdge("D", "F", .{}, null);
    try graph.setEdge("C", "E", .{}, null);
    try graph.setEdge("E", "F", .{}, null);

    try assignRanks(testing.allocator, &graph, .longest_path);

    try testing.expectEqual(@as(?i32, 0), graph.getNode("A").?.rank);
    try testing.expectEqual(@as(?i32, 1), graph.getNode("B").?.rank);
    try testing.expectEqual(@as(?i32, 2), graph.getNode("C").?.rank);
    try testing.expectEqual(@as(?i32, 3), graph.getNode("D").?.rank);
    try testing.expectEqual(@as(?i32, 3), graph.getNode("E").?.rank);
    try testing.expectEqual(@as(?i32, 4), graph.getNode("F").?.rank);
}

test "pullSources: long edge" {
    // Source with a long edge should be pulled down when gap > minlen
    var graph = Digraph(NodeData, EdgeData, GraphData).init(testing.allocator);
    defer graph.deinit();

    // Chain: a(0) -> b(1) -> c(2) -> d(3) -> e(4)
    try graph.setNode("a", .{});
    try graph.setNode("b", .{});
    try graph.setNode("c", .{});
    try graph.setNode("d", .{});
    try graph.setNode("e", .{});
    try graph.setEdge("a", "b", .{}, null);
    try graph.setEdge("b", "c", .{}, null);
    try graph.setEdge("c", "d", .{}, null);
    try graph.setEdge("d", "e", .{}, null);

    // src -> d, 3-layer gap
    try graph.setNode("src", .{});
    try graph.setEdge("src", "d", .{}, null);

    try assignRanks(testing.allocator, &graph, .longest_path);

    // src should be pulled from rank 0 to rank 2 (d is at rank 3, minlen=1, gap=2 > 1)
    try testing.expectEqual(@as(?i32, 0), graph.getNode("a").?.rank);
    try testing.expectEqual(@as(?i32, 2), graph.getNode("src").?.rank);
    try testing.expectEqual(@as(?i32, 3), graph.getNode("d").?.rank);
}

test "pullSources: short edge no pull" {
    // Source with only 1-layer gap should NOT be pulled
    var graph = Digraph(NodeData, EdgeData, GraphData).init(testing.allocator);
    defer graph.deinit();

    try graph.setNode("a", .{});
    try graph.setNode("b", .{});
    try graph.setEdge("a", "b", .{}, null);

    try graph.setNode("src", .{});
    try graph.setEdge("src", "b", .{}, null);

    try assignRanks(testing.allocator, &graph, .longest_path);

    // src should stay at rank 0 (gap of 1 is not > minlen of 1)
    try testing.expectEqual(@as(?i32, 0), graph.getNode("src").?.rank);
    try testing.expectEqual(@as(?i32, 1), graph.getNode("b").?.rank);
}

test "pullSources: multiple outgoing edges" {
    // Source with multiple outgoing edges should be pulled to the
    // tightest constraint (minimum of target_rank - minlen).
    var graph = Digraph(NodeData, EdgeData, GraphData).init(testing.allocator);
    defer graph.deinit();

    // Chain: a(0)->b(1)->c(2)->d(3)->e(4)
    try graph.setNode("a", .{});
    try graph.setNode("b", .{});
    try graph.setNode("c", .{});
    try graph.setNode("d", .{});
    try graph.setNode("e", .{});
    try graph.setEdge("a", "b", .{}, null);
    try graph.setEdge("b", "c", .{}, null);
    try graph.setEdge("c", "d", .{}, null);
    try graph.setEdge("d", "e", .{}, null);

    try graph.setNode("src", .{});
    try graph.setEdge("src", "d", .{}, null); // src -> d (rank 3)
    try graph.setEdge("src", "e", .{}, null); // src -> e (rank 4)

    try assignRanks(testing.allocator, &graph, .longest_path);

    // src should be pulled to rank 2 = min(3-1, 4-1) = min(2, 3) = 2
    // The tighter constraint (d at rank 3) limits how far src can move.
    try testing.expectEqual(@as(?i32, 2), graph.getNode("src").?.rank);
}

test "pullSources: disconnected node stays at zero" {
    // Disconnected nodes (no edges) should stay at rank 0
    var graph = Digraph(NodeData, EdgeData, GraphData).init(testing.allocator);
    defer graph.deinit();

    try graph.setNode("a", .{});
    try graph.setNode("b", .{});
    try graph.setEdge("a", "b", .{}, null);

    try graph.setNode("orphan", .{});

    try assignRanks(testing.allocator, &graph, .longest_path);

    try testing.expectEqual(@as(?i32, 0), graph.getNode("orphan").?.rank);
}
