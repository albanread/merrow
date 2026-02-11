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
    weight: i32,
    /// Preserved from the original edge so we can transfer it to the chain.
    label: ?[]const u8 = null,
    label_owned: bool = false,
    arrowhead: ?[]const u8 = null,
    arrowtail: ?[]const u8 = null,
    style: ?[]const u8 = null,
    line_style: LineStyle = .solid,
    color: ?[4]u8 = null,
    thickness: ?i32 = null,
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
    defer long_edges.deinit(allocator);

    var edge_iter = graph.edgeIterator();
    while (edge_iter.next()) |entry| {
        const v_rank = (graph.getNode(entry.v) orelse continue).rank orelse continue;
        const w_rank = (graph.getNode(entry.w) orelse continue).rank orelse continue;

        if (w_rank != v_rank + 1) {
            // Duplicate the edge name (if any) so we hold a stable copy.
            // `removeEdge` frees the graph's owned name, which is the same
            // pointer the iterator returned — without this dupe we'd have a
            // use-after-free on named edges.
            const duped_name: ?[]const u8 = if (entry.name) |n|
                try allocator.dupe(u8, n)
            else
                null;

            try long_edges.append(allocator, .{
                .v = entry.v,
                .w = entry.w,
                .name = duped_name,
                .name_duped = duped_name != null,
                .v_rank = v_rank,
                .w_rank = w_rank,
                .weight = entry.data.weight,
                .label = entry.data.label,
                .label_owned = entry.data.label_owned,
                .arrowhead = entry.data.arrowhead,
                .arrowtail = entry.data.arrowtail,
                .style = entry.data.style,
                .line_style = entry.data.line_style,
                .color = entry.data.color,
                .thickness = entry.data.thickness,
            });
        }
    }

    // ------------------------------------------------------------------
    // 2. Replace each long edge with a chain of dummy nodes/edges.
    // ------------------------------------------------------------------
    var dummy_counter: usize = 0;

    for (long_edges.items) |le| {
        // Remove the original long edge.  The edge data (including any
        // owned label) has been snapshotted into `le` above.  removeEdge
        // does NOT free the EdgeData's owned resources — we take over
        // ownership here and either transfer or explicitly free them.
        graph.removeEdge(le.v, le.w, le.name);

        // Free the duplicated name now that removeEdge is done with it.
        if (le.name_duped) {
            if (le.name) |n| allocator.free(n);
        }

        var prev_node: []const u8 = le.v;
        var is_first_segment = true;

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
            });

            // Transfer original edge's label to the first segment of the
            // chain so it can still be rendered near the source node.
            var seg_data = EdgeData{
                .weight = le.weight,
                .line_style = le.line_style,
                .color = le.color,
                .thickness = le.thickness,
            };
            if (is_first_segment) {
                seg_data.label = le.label;
                seg_data.label_owned = le.label_owned;
                seg_data.arrowhead = le.arrowhead;
                seg_data.arrowtail = le.arrowtail;
                seg_data.style = le.style;
                is_first_segment = false;
            }

            try graph.setEdge(prev_node, dummy_id, seg_data, null);

            prev_node = dummy_id;
        }

        // Final edge from last dummy (or original source) to target.
        // If the chain had no intermediate dummies (shouldn't happen for
        // long edges, but be safe), transfer label here.
        var final_data = EdgeData{
            .weight = le.weight,
            .line_style = le.line_style,
            .color = le.color,
            .thickness = le.thickness,
        };
        if (is_first_segment) {
            // Single-segment chain: both arrowhead and arrowtail stay here.
            final_data.label = le.label;
            final_data.label_owned = le.label_owned;
            final_data.arrowhead = le.arrowhead;
            final_data.arrowtail = le.arrowtail;
            final_data.style = le.style;
        } else {
            // Multi-segment chain: arrowhead goes on the last segment so
            // it renders at the target.  arrowtail was already placed on
            // the first segment above so it renders at the source.
            final_data.arrowhead = le.arrowhead;
        }
        try graph.setEdge(prev_node, le.w, final_data, null);
    }
}

/// Free all dummy node ID strings tracked in graph_label.dummy_chains,
/// remove dummy nodes from the graph, and restore original long edges.
/// (Placeholder — will be fully implemented with the denormalize phase.)
pub fn freeDummyIds(allocator: std.mem.Allocator, graph: *Graph) void {
    for (graph.graph_label.dummy_chains.items) |id| {
        graph.removeNode(id);
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
