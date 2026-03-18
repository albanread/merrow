//! Edge normalization for the Dagre layout engine.
//!
//! Breaks long edges (spanning more than one rank) into chains of unit-length
//! edges connected by dummy nodes. After normalization every edge in the graph
//! connects two nodes whose ranks differ by exactly 1.
//!
//! Ported from the Merrow (Rust) reference implementation (MIT).

const std = @import("std");
const Digraph = @import("../../graph/digraph.zig").Digraph;
const EdgeKey = @import("../../graph/digraph.zig").EdgeKey;
const model = @import("../../model.zig");
const NodeData = model.NodeData;
const EdgeData = model.EdgeData;
const GraphData = model.GraphData;
const NormalizedEdgeChain = model.NormalizedEdgeChain;
const Point = model.Point;

const LineStyle = model.LineStyle;
const Graph = Digraph(NodeData, EdgeData, GraphData);

/// Information about a long edge collected before mutation.
const LongEdge = struct {
    v: []const u8,
    w: []const u8,
    name: ?[]const u8,
    /// When true the `name` slice was duplicated by `normalizeEdges` and
    /// must be freed after `removeEdge` invalidates the original pointer.
    name_duped: bool = false,
    v_rank: i32,
    w_rank: i32,
    edge_data: EdgeData,
};

/// Normalize edges: replace every edge that spans more than one rank with a
/// chain of dummy nodes connected by unit-length edges.
///
/// Dummy node ID strings are allocated with `allocator` and tracked in
/// `graph.graph_label.dummy_chains` so the caller can free them later
/// (or they are freed by `denormalize`).
pub fn normalizeEdges(
    allocator: std.mem.Allocator,
    graph: *Graph,
) !void {
    // ------------------------------------------------------------------
    // 1. Collect edges that span more than one rank.
    //    We must snapshot first because we mutate the graph below.
    // ------------------------------------------------------------------
    var long_edges = std.ArrayListUnmanaged(LongEdge){};
    defer {
        for (long_edges.items) |*edge| {
            if (edge.name_duped) {
                if (edge.name) |name| allocator.free(name);
            }
            edge.edge_data.deinit(allocator);
        }
        long_edges.deinit(allocator);
    }

    const node_ids = try graph.allNodes(allocator);
    defer {
        for (node_ids) |id| allocator.free(id);
        allocator.free(node_ids);
    }

    for (node_ids) |node_id| {
        const v_rank = (graph.getNode(node_id) orelse continue).rank orelse continue;
        const out_edges = graph.outEdges(node_id) orelse continue;
        for (out_edges) |edge_key| {
            const w_rank = (graph.getNode(edge_key.w) orelse continue).rank orelse continue;
            if (w_rank == v_rank + 1) continue;

            const duped_name: ?[]const u8 = if (edge_key.name) |name|
                try allocator.dupe(u8, name)
            else
                null;

            try long_edges.append(allocator, .{
                .v = edge_key.v,
                .w = edge_key.w,
                .name = duped_name,
                .name_duped = duped_name != null,
                .v_rank = v_rank,
                .w_rank = w_rank,
                .edge_data = graph.edge(edge_key.v, edge_key.w, edge_key.name) orelse continue,
            });
        }
    }

    // ------------------------------------------------------------------
    // 2. Replace each long edge with a chain of dummy nodes/edges.
    // ------------------------------------------------------------------
    var dummy_counter: usize = 0;

    for (long_edges.items) |*le| {
        // Remove the original long edge.  The edge data (including any
        // owned label) has been snapshotted into `le` above.  removeEdge
        // does NOT free the EdgeData's owned resources — we take over
        // ownership here and either transfer or explicitly free them.
        graph.removeEdge(le.v, le.w, le.name);

        var prev_node: []const u8 = le.v;
        var first_dummy: ?[]const u8 = null;

        // Insert a dummy node for every intermediate rank.
        var rank: i32 = le.v_rank + 1;
        while (rank < le.w_rank) : (rank += 1) {
            // Build a unique dummy id into a persistent allocation.
            const dummy_id = try std.fmt.allocPrint(allocator, "_d{d}_{d}", .{ rank, dummy_counter });
            dummy_counter += 1;

            // Track the allocation so it can be freed later.
            try graph.graph_label.dummy_chains.append(allocator, dummy_id);

            try graph.setNode(dummy_id, .{
                .rank = rank,
                .dummy = true,
                .dummy_kind = .edge,
            });

            if (first_dummy == null) first_dummy = dummy_id;

            try graph.setEdge(prev_node, dummy_id, .{
                .weight = le.edge_data.weight,
                .compound_redirect_id = le.edge_data.compound_redirect_id,
            }, null);

            prev_node = dummy_id;
        }

        if (first_dummy) |start_dummy| {
            try graph.setEdge(prev_node, le.w, .{
                .weight = le.edge_data.weight,
                .compound_redirect_id = le.edge_data.compound_redirect_id,
            }, null);

            try graph.graph_label.normalized_edge_chains.append(allocator, .{
                .original_v = le.v,
                .original_w = le.w,
                .original_name = le.name,
                .original_name_owned = le.name_duped,
                .first_dummy = start_dummy,
                .edge_data = le.edge_data,
            });

            le.name = null;
            le.name_duped = false;
            le.edge_data = .{};
        } else {
            try graph.setEdge(le.v, le.w, le.edge_data, le.name);
            if (le.name_duped) {
                if (le.name) |name| allocator.free(name);
            }
            le.name = null;
            le.name_duped = false;
            le.edge_data = .{};
        }
    }
}

/// Undo normalization by collecting dummy-node positions into the original edge,
/// removing the dummy chain, and restoring the original edge metadata.
pub fn undo(allocator: std.mem.Allocator, graph: *Graph) !void {
    for (graph.graph_label.normalized_edge_chains.items) |*chain| {
        if (!graph.hasNode(chain.first_dummy)) continue;

        var points = std.ArrayListUnmanaged(Point){};
        errdefer points.deinit(allocator);

        const original_src = graph.getNode(chain.original_v) orelse continue;
        const original_tgt = graph.getNode(chain.original_w) orelse continue;

        try points.append(allocator, .{ .x = original_src.x, .y = original_src.y });

        var current = chain.first_dummy;
        while (true) {
            const node = graph.getNode(current) orelse break;
            if (!node.dummy or node.dummy_kind == null or node.dummy_kind.? != .edge) break;

            try points.append(allocator, .{ .x = node.x, .y = node.y });

            const next = blk: {
                const out_edges = graph.outEdges(current) orelse break :blk null;
                if (out_edges.len == 0) break :blk null;
                break :blk out_edges[0].w;
            };

            if (graph.inEdges(current)) |in_edges| {
                if (in_edges.len > 0) {
                    graph.removeEdge(in_edges[0].v, in_edges[0].w, in_edges[0].name);
                }
            }
            if (graph.outEdges(current)) |out_edges| {
                if (out_edges.len > 0) {
                    graph.removeEdge(out_edges[0].v, out_edges[0].w, out_edges[0].name);
                }
            }
            graph.removeNode(current);

            current = next orelse break;
        }

        try points.append(allocator, .{ .x = original_tgt.x, .y = original_tgt.y });

        chain.edge_data.points = points;
        try graph.setEdge(chain.original_v, chain.original_w, chain.edge_data, chain.original_name);

        if (chain.original_name_owned) {
            if (chain.original_name) |name| allocator.free(name);
        }
        chain.original_name = null;
        chain.original_name_owned = false;
        chain.edge_data = .{};
    }

    graph.graph_label.normalized_edge_chains.clearRetainingCapacity();
}

/// Free all dummy node ID strings tracked in graph_label.dummy_chains,
/// remove dummy nodes from the graph, and restore original long edges.
/// (Placeholder — will be fully implemented with the denormalize phase.)
pub fn freeDummyIds(allocator: std.mem.Allocator, graph: *Graph) void {
    for (graph.graph_label.normalized_edge_chains.items) |*chain| {
        chain.deinit(allocator);
    }
    graph.graph_label.normalized_edge_chains.deinit(allocator);
    graph.graph_label.normalized_edge_chains = .{};

    for (graph.graph_label.dummy_chains.items) |id| {
        if (graph.hasNode(id)) {
            graph.removeNode(id);
        }
        allocator.free(id);
    }
    graph.graph_label.dummy_chains.deinit(allocator);
    graph.graph_label.dummy_chains = .{};
}

// ======================================================================
// Tests
// ======================================================================
const testing = std.testing;

test "adjacent ranks are untouched" {
    var g = Graph.init(testing.allocator);
    defer {
        freeDummyIds(testing.allocator, &g);
        g.deinitDeep();
    }

    try g.setNode("A", .{ .rank = 0 });
    try g.setNode("B", .{ .rank = 1 });
    try g.setEdge("A", "B", .{}, null);

    try normalizeEdges(testing.allocator, &g);

    // Edge should still exist directly.
    try testing.expect(g.hasEdge("A", "B", null));
    // No dummy nodes created.
    try testing.expectEqual(@as(usize, 2), g.nodeCount());
    try testing.expectEqual(@as(usize, 0), g.graph_label.dummy_chains.items.len);
}

test "two-rank gap inserts one dummy" {
    var g = Graph.init(testing.allocator);
    defer {
        freeDummyIds(testing.allocator, &g);
        g.deinitDeep();
    }

    try g.setNode("A", .{ .rank = 0 });
    try g.setNode("B", .{ .rank = 2 });
    try g.setEdge("A", "B", .{ .weight = 3 }, null);

    try normalizeEdges(testing.allocator, &g);

    // Original long edge gone.
    try testing.expect(!g.hasEdge("A", "B", null));

    // One dummy node created: A + B + 1 dummy = 3.
    try testing.expectEqual(@as(usize, 3), g.nodeCount());
    try testing.expectEqual(@as(usize, 1), g.graph_label.dummy_chains.items.len);

    const dummy_id = g.graph_label.dummy_chains.items[0];
    const dummy = g.getNode(dummy_id).?;
    try testing.expectEqual(@as(?i32, 1), dummy.rank);
    try testing.expect(dummy.dummy);

    // Chain: A -> dummy -> B
    try testing.expect(g.hasEdge("A", dummy_id, null));
    try testing.expect(g.hasEdge(dummy_id, "B", null));

    // Weight preserved.
    try testing.expectEqual(@as(i32, 3), g.edge("A", dummy_id, null).?.weight);
    try testing.expectEqual(@as(i32, 3), g.edge(dummy_id, "B", null).?.weight);
}

test "three-rank gap inserts two dummies" {
    var g = Graph.init(testing.allocator);
    defer {
        freeDummyIds(testing.allocator, &g);
        g.deinitDeep();
    }

    try g.setNode("A", .{ .rank = 0 });
    try g.setNode("B", .{ .rank = 3 });
    try g.setEdge("A", "B", .{}, null);

    try normalizeEdges(testing.allocator, &g);

    // A + B + 2 dummies = 4
    try testing.expectEqual(@as(usize, 4), g.nodeCount());
    try testing.expectEqual(@as(usize, 2), g.graph_label.dummy_chains.items.len);
    try testing.expect(!g.hasEdge("A", "B", null));

    // Verify ranks 1 and 2 are occupied by dummies.
    const d0 = g.getNode(g.graph_label.dummy_chains.items[0]).?;
    const d1 = g.getNode(g.graph_label.dummy_chains.items[1]).?;
    try testing.expectEqual(@as(?i32, 1), d0.rank);
    try testing.expectEqual(@as(?i32, 2), d1.rank);
}

test "mixed long and short edges" {
    var g = Graph.init(testing.allocator);
    defer {
        freeDummyIds(testing.allocator, &g);
        g.deinitDeep();
    }

    try g.setNode("A", .{ .rank = 0 });
    try g.setNode("B", .{ .rank = 1 });
    try g.setNode("C", .{ .rank = 3 });

    try g.setEdge("A", "B", .{}, null); // short – keep
    try g.setEdge("A", "C", .{}, null); // long  – split

    try normalizeEdges(testing.allocator, &g);

    // Short edge untouched.
    try testing.expect(g.hasEdge("A", "B", null));
    // Long edge removed.
    try testing.expect(!g.hasEdge("A", "C", null));
    // A + B + C + 2 dummies = 5
    try testing.expectEqual(@as(usize, 5), g.nodeCount());
    try testing.expectEqual(@as(usize, 2), g.graph_label.dummy_chains.items.len);
}

test "normalize preserves compound redirect metadata on split edges" {
    var g = Graph.init(testing.allocator);
    defer {
        freeDummyIds(testing.allocator, &g);
        g.deinitDeep();
    }

    try g.setNode("A", .{ .rank = 0 });
    try g.setNode("B", .{ .rank = 3 });
    try g.setEdge("A", "B", .{ .compound_redirect_id = 7 }, null);

    try normalizeEdges(testing.allocator, &g);

    const first_dummy = g.graph_label.dummy_chains.items[0];
    try testing.expectEqual(@as(?usize, 7), g.edge("A", first_dummy, null).?.compound_redirect_id);
}

test "undo restores long edge with collected points and metadata" {
    var g = Graph.init(testing.allocator);
    defer {
        freeDummyIds(testing.allocator, &g);
        g.deinitDeep();
    }

    try g.setNode("A", .{ .rank = 0, .x = 10, .y = 10 });
    try g.setNode("B", .{ .rank = 3, .x = 10, .y = 130 });
    try g.setEdge("A", "B", .{ .label = "edge", .reversed = true, .compound_redirect_id = 9 }, null);

    try normalizeEdges(testing.allocator, &g);

    const d0 = g.graph_label.dummy_chains.items[0];
    const d1 = g.graph_label.dummy_chains.items[1];
    if (g.getNodePtr(d0)) |node| {
        node.x = 20;
        node.y = 40;
    }
    if (g.getNodePtr(d1)) |node| {
        node.x = 30;
        node.y = 90;
    }

    try undo(testing.allocator, &g);

    try testing.expect(g.hasEdge("A", "B", null));
    const edge = g.edge("A", "B", null).?;
    try testing.expectEqual(@as(usize, 4), edge.points.items.len);
    try testing.expectEqual(@as(f64, 10), edge.points.items[0].x);
    try testing.expectEqual(@as(f64, 10), edge.points.items[0].y);
    try testing.expectEqual(@as(f64, 20), edge.points.items[1].x);
    try testing.expectEqual(@as(f64, 90), edge.points.items[2].y);
    try testing.expectEqual(@as(f64, 10), edge.points.items[3].x);
    try testing.expectEqual(@as(f64, 130), edge.points.items[3].y);
    try testing.expectEqual(@as(?usize, 9), edge.compound_redirect_id);
    try testing.expect(edge.reversed);
    try testing.expect(!g.hasNode(d0));
    try testing.expect(!g.hasNode(d1));
}

test "freeDummyIds cleans up" {
    var g = Graph.init(testing.allocator);
    defer g.deinitDeep();

    try g.setNode("A", .{ .rank = 0 });
    try g.setNode("B", .{ .rank = 3 });
    try g.setEdge("A", "B", .{}, null);

    try normalizeEdges(testing.allocator, &g);

    try testing.expectEqual(@as(usize, 4), g.nodeCount());

    // Free dummies — should leave only A and B.
    freeDummyIds(testing.allocator, &g);

    try testing.expectEqual(@as(usize, 2), g.nodeCount());
    try testing.expect(g.hasNode("A"));
    try testing.expect(g.hasNode("B"));
}
