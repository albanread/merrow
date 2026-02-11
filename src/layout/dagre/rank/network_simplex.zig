//! Network simplex algorithm for optimal rank assignment
//!
//! Implements the network simplex algorithm as described in:
//! Gansner et al. "A Technique for Drawing Directed Graphs" (1993)
//!
//! The algorithm finds an optimal rank assignment that minimizes the
//! weighted sum of edge lengths while respecting minimum length constraints.
//! It produces tighter, more balanced layouts than the longest-path ranker.

const std = @import("std");
const Allocator = std.mem.Allocator;
const Digraph = @import("../../../graph/digraph.zig").Digraph;
const EdgeKey = @import("../../../graph/digraph.zig").EdgeKey;
const model = @import("../../../model.zig");
const NodeData = model.NodeData;
const EdgeData = model.EdgeData;
const GraphData = model.GraphData;
const util = @import("util.zig");
const longest_path = @import("longest_path.zig");

const Graph = Digraph(NodeData, EdgeData, GraphData);

// ---------------------------------------------------------------------------
// String-pair key for the spanning tree edge map
// ---------------------------------------------------------------------------

const StrPair = struct {
    a: []const u8,
    b: []const u8,
};

const StrPairContext = struct {
    pub fn hash(_: @This(), key: StrPair) u64 {
        var hasher = std.hash.Wyhash.init(0);
        hasher.update(key.a);
        hasher.update("\x00");
        hasher.update(key.b);
        return hasher.final();
    }
    pub fn eql(_: @This(), a: StrPair, b: StrPair) bool {
        return std.mem.eql(u8, a.a, b.a) and std.mem.eql(u8, a.b, b.b);
    }
};

// ---------------------------------------------------------------------------
// TreeEdge / TreeNode
// ---------------------------------------------------------------------------

const TreeEdge = struct {
    cutvalue: ?i32 = null,
};

const TreeNode = struct {
    low: ?i32 = null,
    lim: ?i32 = null,
    parent: ?[]const u8 = null,
};

// ---------------------------------------------------------------------------
// SpanningTree
// ---------------------------------------------------------------------------

const SpanningTree = struct {
    allocator: Allocator,
    /// Tree node metadata (low, lim, parent).
    nodes: std.StringHashMap(TreeNode),
    /// Tree edges stored in both directions (undirected).
    edges: std.HashMap(StrPair, TreeEdge, StrPairContext, 80),
    /// Root of the spanning tree.
    root: ?[]const u8 = null,

    fn init(allocator: Allocator) SpanningTree {
        return .{
            .allocator = allocator,
            .nodes = std.StringHashMap(TreeNode).init(allocator),
            .edges = std.HashMap(StrPair, TreeEdge, StrPairContext, 80).init(allocator),
        };
    }

    fn deinit(self: *SpanningTree) void {
        self.nodes.deinit();
        self.edges.deinit();
    }

    fn setEdge(self: *SpanningTree, v: []const u8, w: []const u8, edge: TreeEdge) !void {
        try self.edges.put(.{ .a = v, .b = w }, edge);
        try self.edges.put(.{ .a = w, .b = v }, edge);
    }

    fn removeEdge(self: *SpanningTree, v: []const u8, w: []const u8) void {
        _ = self.edges.remove(.{ .a = v, .b = w });
        _ = self.edges.remove(.{ .a = w, .b = v });
    }

    fn hasEdge(self: *const SpanningTree, v: []const u8, w: []const u8) bool {
        return self.edges.contains(.{ .a = v, .b = w });
    }

    fn getEdge(self: *const SpanningTree, v: []const u8, w: []const u8) ?TreeEdge {
        return self.edges.get(.{ .a = v, .b = w });
    }

    fn getEdgePtr(self: *SpanningTree, v: []const u8, w: []const u8) ?*TreeEdge {
        return self.edges.getPtr(.{ .a = v, .b = w });
    }

    fn setNode(self: *SpanningTree, v: []const u8, node: TreeNode) !void {
        try self.nodes.put(v, node);
    }

    fn getNode(self: *const SpanningTree, v: []const u8) ?TreeNode {
        return self.nodes.get(v);
    }

    fn getNodePtr(self: *SpanningTree, v: []const u8) ?*TreeNode {
        return self.nodes.getPtr(v);
    }

    /// Set the cutvalue on a tree edge (both directions).
    fn setEdgeCutvalue(self: *SpanningTree, v: []const u8, w: []const u8, cv: i32) void {
        if (self.getEdgePtr(v, w)) |e| e.cutvalue = cv;
        if (self.getEdgePtr(w, v)) |e| e.cutvalue = cv;
    }

    /// Collect deduplicated list of tree edges.  Each undirected edge
    /// appears once, with the lexicographically smaller node first.
    fn edgesList(self: *const SpanningTree, allocator: Allocator) ![]StrPair {
        var result = std.ArrayListUnmanaged(StrPair){};
        errdefer result.deinit(allocator);

        var seen = std.HashMap(StrPair, void, StrPairContext, 80).init(allocator);
        defer seen.deinit();

        // Collect keys and sort for determinism
        var keys = std.ArrayListUnmanaged(StrPair){};
        defer keys.deinit(allocator);

        var key_iter = self.edges.keyIterator();
        while (key_iter.next()) |kp| {
            try keys.append(allocator, kp.*);
        }
        std.mem.sort(StrPair, keys.items, {}, struct {
            fn lessThan(_: void, lhs: StrPair, rhs: StrPair) bool {
                const ca = std.mem.order(u8, lhs.a, rhs.a);
                if (ca != .eq) return ca == .lt;
                return std.mem.order(u8, lhs.b, rhs.b) == .lt;
            }
        }.lessThan);

        for (keys.items) |pair| {
            const rev = StrPair{ .a = pair.b, .b = pair.a };
            if (!seen.contains(rev)) {
                try result.append(allocator, pair);
                try seen.put(pair, {});
            }
        }
        return result.toOwnedSlice(allocator);
    }

    /// Get neighbors of a node in the tree.
    fn neighbors(self: *const SpanningTree, v: []const u8, allocator: Allocator) ![]const []const u8 {
        var result = std.ArrayListUnmanaged([]const u8){};
        errdefer result.deinit(allocator);

        var iter = self.edges.keyIterator();
        while (iter.next()) |kp| {
            if (std.mem.eql(u8, kp.a, v)) {
                try result.append(allocator, kp.b);
            }
        }

        // Sort for determinism
        std.mem.sort([]const u8, result.items, {}, struct {
            fn lessThan(_: void, a: []const u8, b: []const u8) bool {
                return std.mem.order(u8, a, b) == .lt;
            }
        }.lessThan);

        return result.toOwnedSlice(allocator);
    }
};

// ---------------------------------------------------------------------------
// Public entry point
// ---------------------------------------------------------------------------

/// Run the network simplex algorithm to assign optimal ranks.
pub fn run(allocator: Allocator, graph: *Graph) !void {
    // Collect compound / subgraph nodes — these are excluded from ranking
    // because their position is determined by their children, not edges.
    var compound_nodes = std.StringHashMap(void).init(allocator);
    defer compound_nodes.deinit();
    {
        var niter = graph.nodes.iterator();
        while (niter.next()) |entry| {
            if (entry.value_ptr.is_subgraph) {
                try compound_nodes.put(entry.key_ptr.*, {});
            }
        }
    }

    // Step 1: initialise with longest-path ranking
    try longest_path.run(allocator, graph);

    // Step 2: build feasible spanning tree
    var tree = try feasibleTree(allocator, graph, &compound_nodes);
    defer tree.deinit();

    // Step 3: initialise DFS low/lim numbering
    try initLowLimValues(allocator, &tree, tree.root);

    // Step 4: initialise cut values
    try initCutValues(allocator, &tree, graph);

    // Step 5: iterate — find leaving edge, find entering edge, exchange
    const max_iterations = graph.nodeCount() * graph.edgeCount() + 1;
    var iterations: usize = 0;

    // Track exchange counts for cycle detection
    const ExKey = struct { leave: StrPair, enter: StrPair };
    const ExKeyCtx = struct {
        pub fn hash(_: @This(), key: ExKey) u64 {
            var h = std.hash.Wyhash.init(0);
            h.update(key.leave.a);
            h.update("\x01");
            h.update(key.leave.b);
            h.update("\x02");
            h.update(key.enter.a);
            h.update("\x03");
            h.update(key.enter.b);
            return h.final();
        }
        pub fn eql(_: @This(), a: ExKey, b: ExKey) bool {
            return std.mem.eql(u8, a.leave.a, b.leave.a) and
                std.mem.eql(u8, a.leave.b, b.leave.b) and
                std.mem.eql(u8, a.enter.a, b.enter.a) and
                std.mem.eql(u8, a.enter.b, b.enter.b);
        }
    };
    var exchange_counts = std.HashMap(ExKey, usize, ExKeyCtx, 80).init(allocator);
    defer exchange_counts.deinit();

    while (iterations < max_iterations) {
        const leave = try leaveEdge(allocator, &tree) orelse break;
        iterations += 1;

        // Try to find a valid entering edge, with cycle-detection fallback
        var excluded = std.ArrayListUnmanaged(StrPair){};
        defer excluded.deinit(allocator);
        var found_valid = false;

        while (true) {
            const exclude_pair: ?StrPair = if (excluded.items.len > 0)
                excluded.items[excluded.items.len - 1]
            else
                null;

            const enter = try enterEdge(allocator, &tree, graph, leave, exclude_pair) orelse break;

            // Normalise the exchange for cycle detection
            const norm_leave = if (std.mem.order(u8, leave.a, leave.b) == .lt)
                leave
            else
                StrPair{ .a = leave.b, .b = leave.a };
            const norm_enter = if (std.mem.order(u8, enter.a, enter.b) == .lt)
                enter
            else
                StrPair{ .a = enter.b, .b = enter.a };
            const ex_key = ExKey{ .leave = norm_leave, .enter = norm_enter };

            const gop = try exchange_counts.getOrPut(ex_key);
            if (!gop.found_existing) gop.value_ptr.* = 0;
            gop.value_ptr.* += 1;
            if (gop.value_ptr.* > 2) break; // cycling

            if (try exchangeEdges(allocator, &tree, graph, leave, enter)) {
                found_valid = true;
                break;
            }

            // Exchange was reverted (cycle in tree) — try another edge
            try excluded.append(allocator, enter);
            if (excluded.items.len > 10) break;
        }

        if (!found_valid) {
            // Mark the leaving edge as neutral so it won't be picked again
            tree.setEdgeCutvalue(leave.a, leave.b, 0);
        }
    }

    // Ranks are now optimal.  normalizeRanks is called by the caller (rank.zig).
}

// ---------------------------------------------------------------------------
// Feasible spanning tree construction
// ---------------------------------------------------------------------------

/// Build an initial feasible spanning tree using tight edges (slack = 0).
fn feasibleTree(
    allocator: Allocator,
    graph: *Graph,
    compound_nodes: *const std.StringHashMap(void),
) !SpanningTree {
    var tree = SpanningTree.init(allocator);
    errdefer tree.deinit();

    // Add all non-compound nodes to the tree
    var niter = graph.nodes.keyIterator();
    while (niter.next()) |kp| {
        if (!compound_nodes.contains(kp.*)) {
            try tree.setNode(kp.*, .{});
        }
    }

    const target_count = tree.nodes.count();
    if (target_count == 0) return tree;

    // Pick a root node (first non-compound node, deterministically)
    var first_node: ?[]const u8 = null;
    {
        var sorted = std.ArrayListUnmanaged([]const u8){};
        defer sorted.deinit(allocator);
        var ki = tree.nodes.keyIterator();
        while (ki.next()) |kp| try sorted.append(allocator, kp.*);
        std.mem.sort([]const u8, sorted.items, {}, struct {
            fn lt(_: void, a: []const u8, b: []const u8) bool {
                return std.mem.order(u8, a, b) == .lt;
            }
        }.lt);
        if (sorted.items.len > 0) first_node = sorted.items[0];
    }

    var in_tree = std.StringHashMap(void).init(allocator);
    defer in_tree.deinit();

    if (first_node) |f| {
        try in_tree.put(f, {});
        tree.root = f;
    }

    while (in_tree.count() < target_count) {
        try expandTightTree(allocator, &tree, graph, compound_nodes, &in_tree);

        if (in_tree.count() >= target_count) break;

        // Find non-tree edge with minimum slack where exactly one endpoint is in tree
        const min_edge = try findMinSlackEdge(allocator, graph, compound_nodes, &in_tree);
        if (min_edge == null) break;
        const me = min_edge.?;

        const s = util.slack(@as(*const Graph, graph), me.v, me.w) orelse 0;
        const delta: i32 = if (in_tree.contains(me.v)) s else -s;

        if (delta != 0) {
            // Shift all in-tree node ranks to make this edge tight
            var it = in_tree.keyIterator();
            while (it.next()) |kp| {
                if (graph.getNodePtr(kp.*)) |node| {
                    if (node.rank) |r| node.rank = r + delta;
                }
            }
        }
    }

    return tree;
}

/// DFS expansion: add all reachable tight edges (slack == 0) to the tree.
fn expandTightTree(
    allocator: Allocator,
    tree: *SpanningTree,
    graph: *const Graph,
    compound_nodes: *const std.StringHashMap(void),
    in_tree: *std.StringHashMap(void),
) !void {
    // Collect current in-tree nodes as a stack
    var stack = std.ArrayListUnmanaged([]const u8){};
    defer stack.deinit(allocator);
    {
        var it = in_tree.keyIterator();
        while (it.next()) |kp| try stack.append(allocator, kp.*);
    }

    while (stack.items.len > 0) {
        const v = stack.items[stack.items.len - 1];
        stack.items.len -= 1;

        // Check all incident edges (in + out)
        const in_edges = graph.inEdges(v) orelse &[_]EdgeKey{};
        const out_edges = graph.outEdges(v) orelse &[_]EdgeKey{};

        for ([_][]const EdgeKey{ in_edges, out_edges }) |edge_list| {
            for (edge_list) |ek| {
                const w = if (std.mem.eql(u8, ek.v, v)) ek.w else ek.v;

                if (compound_nodes.contains(w)) continue;
                if (in_tree.contains(w)) continue;

                const s = util.slack(@as(*const Graph, graph), ek.v, ek.w) orelse continue;
                if (s == 0) {
                    try tree.setEdge(ek.v, ek.w, .{});
                    try in_tree.put(w, {});
                    try stack.append(allocator, w);
                }
            }
        }
    }
}

/// Find the non-tree edge with minimum slack where exactly one endpoint is in the tree.
fn findMinSlackEdge(
    allocator: Allocator,
    graph: *const Graph,
    compound_nodes: *const std.StringHashMap(void),
    in_tree: *const std.StringHashMap(void),
) !?EdgeKey {
    _ = allocator;

    var best_edge: ?EdgeKey = null;
    var best_slack: i32 = std.math.maxInt(i32);

    var iter = graph.edges.iterator();
    while (iter.next()) |entry| {
        const ek = entry.key_ptr.*;
        if (compound_nodes.contains(ek.v) or compound_nodes.contains(ek.w)) continue;

        const v_in = in_tree.contains(ek.v);
        const w_in = in_tree.contains(ek.w);
        if (v_in == w_in) continue; // both in or both out

        if (util.slack(@as(*const Graph, graph), ek.v, ek.w)) |s| {
            const abs_s = if (s < 0) -s else s;
            if (abs_s < best_slack) {
                best_slack = abs_s;
                best_edge = ek;
            }
        }
    }

    return best_edge;
}

// ---------------------------------------------------------------------------
// DFS low / lim numbering
// ---------------------------------------------------------------------------

/// Initialise the low and lim values on the spanning tree via a DFS from the root.
/// These values enable O(1) ancestor-queries via `isDescendant()`.
fn initLowLimValues(allocator: Allocator, tree: *SpanningTree, root: ?[]const u8) !void {
    const r = root orelse blk: {
        var ki = tree.nodes.keyIterator();
        break :blk if (ki.next()) |kp| kp.* else return;
    };
    var counter: i32 = 0;
    try dfsAssign(allocator, tree, r, null, &counter);
}

fn dfsAssign(
    allocator: Allocator,
    tree: *SpanningTree,
    v: []const u8,
    parent: ?[]const u8,
    counter: *i32,
) !void {
    counter.* += 1;
    const low = counter.*;

    if (tree.getNodePtr(v)) |node| {
        node.parent = parent;
    }

    const nbrs = try tree.neighbors(v, allocator);
    defer allocator.free(nbrs);

    for (nbrs) |w| {
        if (parent) |p| {
            if (std.mem.eql(u8, p, w)) continue;
        }
        try dfsAssign(allocator, tree, w, v, counter);
    }

    counter.* += 1;
    const lim = counter.*;

    if (tree.getNodePtr(v)) |node| {
        node.low = low;
        node.lim = lim;
    }
}

// ---------------------------------------------------------------------------
// Cut values
// ---------------------------------------------------------------------------

/// Initialise cut values for every tree edge.
fn initCutValues(allocator: Allocator, tree: *SpanningTree, graph: *const Graph) !void {
    const r = tree.root orelse blk: {
        var ki = tree.nodes.keyIterator();
        break :blk if (ki.next()) |kp| kp.* else return;
    };

    // Postorder traversal — compute cut values bottom-up
    var order = std.ArrayListUnmanaged([]const u8){};
    defer order.deinit(allocator);
    try dfsPostorder(allocator, tree, r, null, &order);

    for (order.items) |v| {
        if (std.mem.eql(u8, v, r)) continue;
        const parent = (tree.getNode(v) orelse continue).parent orelse continue;
        const cv = try calcCutValue(allocator, tree, graph, v, parent);
        tree.setEdgeCutvalue(v, parent, cv);
    }
}

/// Calculate the cut value for the tree edge (v, parent).
fn calcCutValue(
    allocator: Allocator,
    tree: *const SpanningTree,
    graph: *const Graph,
    v: []const u8,
    w: []const u8,
) !i32 {
    // Determine which side is the child in the tree
    const child = if ((tree.getNode(v) orelse TreeNode{}).parent) |p|
        (if (std.mem.eql(u8, p, w)) v else w)
    else
        w;
    const parent = if (std.mem.eql(u8, child, v)) w else v;

    var child_is_tail = true;
    var graph_edge_weight: i32 = 0;
    if (graph.edge(child, parent, null)) |e| {
        graph_edge_weight = e.weight;
    } else if (graph.edge(parent, child, null)) |e| {
        graph_edge_weight = e.weight;
        child_is_tail = false;
    }

    var cutvalue: i32 = graph_edge_weight;

    // Collect all incident graph edges of the child node (deduplicated)
    var incident = std.ArrayListUnmanaged(EdgeKey){};
    defer incident.deinit(allocator);

    if (graph.inEdges(child)) |in_e| {
        for (in_e) |ek| try incident.append(allocator, ek);
    }
    if (graph.outEdges(child)) |out_e| {
        for (out_e) |ek| try incident.append(allocator, ek);
    }

    // Deduplicate (simple O(n²) since incident lists are small)
    var deduped = std.ArrayListUnmanaged(EdgeKey){};
    defer deduped.deinit(allocator);
    for (incident.items) |ek| {
        var dup = false;
        for (deduped.items) |d| {
            if (std.mem.eql(u8, ek.v, d.v) and std.mem.eql(u8, ek.w, d.w)) {
                dup = true;
                break;
            }
        }
        if (!dup) try deduped.append(allocator, ek);
    }

    for (deduped.items) |ek| {
        const is_out_edge = std.mem.eql(u8, ek.v, child);
        const other = if (is_out_edge) ek.w else ek.v;
        if (std.mem.eql(u8, other, parent)) continue;

        const points_to_head = is_out_edge == child_is_tail;
        const other_weight = if (graph.edge(ek.v, ek.w, ek.name)) |e| e.weight else 1;

        cutvalue += if (points_to_head) other_weight else -other_weight;

        if (tree.hasEdge(child, other)) {
            const other_cut = (tree.getEdge(child, other) orelse TreeEdge{}).cutvalue orelse 0;
            cutvalue += if (points_to_head) -other_cut else other_cut;
        }
    }

    return cutvalue;
}

/// Check if node v is a descendant of node u in the tree using low/lim intervals.
fn isDescendant(tree: *const SpanningTree, v: []const u8, u: []const u8) bool {
    const v_node = tree.getNode(v) orelse return false;
    const u_node = tree.getNode(u) orelse return false;

    const v_low = v_node.low orelse return false;
    const v_lim = v_node.lim orelse return false;
    const u_low = u_node.low orelse return false;
    const u_lim = u_node.lim orelse return false;

    return u_low <= v_low and v_lim <= u_lim;
}

// ---------------------------------------------------------------------------
// Leave / enter edge selection
// ---------------------------------------------------------------------------

/// Find a tree edge with negative cut value (candidate to leave the tree).
fn leaveEdge(allocator: Allocator, tree: *const SpanningTree) !?StrPair {
    const edges = try tree.edgesList(allocator);
    defer allocator.free(edges);

    for (edges) |pair| {
        if (tree.getEdge(pair.a, pair.b)) |e| {
            if (e.cutvalue) |cv| {
                if (cv < 0) return pair;
            }
        }
    }
    return null;
}

/// Find a non-tree edge with minimum slack that crosses the cut defined by
/// removing the leaving edge.  Optionally exclude a specific edge (anti-cycling).
fn enterEdge(
    allocator: Allocator,
    tree: *const SpanningTree,
    graph: *const Graph,
    leave: StrPair,
    exclude: ?StrPair,
) !?StrPair {
    _ = allocator;

    var v = leave.a;
    var w = leave.b;

    // Orient the leaving edge so that (v, w) is a graph edge
    if (graph.edge(v, w, null) == null) {
        const tmp = v;
        v = w;
        w = tmp;
    }

    const v_label = tree.getNode(v) orelse return null;
    const w_label = tree.getNode(w) orelse return null;

    var tail = v;
    var flip = false;

    if ((v_label.lim orelse 0) > (w_label.lim orelse 0)) {
        tail = w;
        flip = true;
    }

    var best_edge: ?StrPair = null;
    var best_slack: i32 = std.math.maxInt(i32);

    var iter = graph.edges.keyIterator();
    while (iter.next()) |kp| {
        const ek = kp.*;

        // Skip tree edges
        if (tree.hasEdge(ek.v, ek.w)) continue;

        // Skip excluded edge
        if (exclude) |ex| {
            if ((std.mem.eql(u8, ek.v, ex.a) and std.mem.eql(u8, ek.w, ex.b)) or
                (std.mem.eql(u8, ek.v, ex.b) and std.mem.eql(u8, ek.w, ex.a)))
                continue;
        }

        const v_in_tail = isDescendant(tree, ek.v, tail);
        const w_in_tail = isDescendant(tree, ek.w, tail);

        // Edge must cross the cut
        if (flip == v_in_tail and flip != w_in_tail) {
            if (util.slack(@as(*const Graph, graph), ek.v, ek.w)) |s| {
                if (s < best_slack) {
                    best_slack = s;
                    best_edge = .{ .a = ek.v, .b = ek.w };
                }
            }
        }
    }

    return best_edge;
}

// ---------------------------------------------------------------------------
// Edge exchange
// ---------------------------------------------------------------------------

/// Swap the leaving edge out of the tree and the entering edge in.
/// Returns true on success, false if reverted due to cycle detection.
fn exchangeEdges(
    allocator: Allocator,
    tree: *SpanningTree,
    graph: *Graph,
    leave: StrPair,
    enter: StrPair,
) !bool {
    // Remove leaving edge
    tree.removeEdge(leave.a, leave.b);

    // Add entering edge
    try tree.setEdge(enter.a, enter.b, .{});

    // Safety: check for cycles in the tree
    if (try hasCycle(allocator, tree)) {
        // Revert
        tree.removeEdge(enter.a, enter.b);
        try tree.setEdge(leave.a, leave.b, .{});

        try initLowLimValues(allocator, tree, tree.root);
        try initCutValues(allocator, tree, graph);

        tree.setEdgeCutvalue(leave.a, leave.b, 0);
        return false;
    }

    // Recompute DFS numbering and cut values
    try initLowLimValues(allocator, tree, tree.root);
    try initCutValues(allocator, tree, graph);

    // Update ranks
    try updateRanks(allocator, tree, graph);

    return true;
}

/// Update node ranks based on the current spanning tree structure.
/// DFS from root, setting each child's rank = parent_rank ± minlen.
fn updateRanks(allocator: Allocator, tree: *const SpanningTree, graph: *Graph) !void {
    const root = tree.root orelse blk: {
        var ki = tree.nodes.keyIterator();
        break :blk if (ki.next()) |kp| kp.* else return;
    };

    // Ensure root has a rank
    if (graph.getNodePtr(root)) |node| {
        if (node.rank == null) node.rank = 0;
    }

    var ordered = std.ArrayListUnmanaged([]const u8){};
    defer ordered.deinit(allocator);
    try dfsPreorder(allocator, tree, root, null, &ordered);

    // Skip root (index 0)
    for (ordered.items[1..]) |v| {
        const parent = (tree.getNode(v) orelse continue).parent orelse continue;

        // Find the graph edge between v and parent (either direction)
        var minlen: i32 = 1;
        var flipped = false;
        if (graph.edge(v, parent, null)) |e| {
            minlen = e.minlen;
            flipped = false;
        } else if (graph.edge(parent, v, null)) |e| {
            minlen = e.minlen;
            flipped = true;
        } else continue;

        const parent_rank = if (graph.getNode(parent)) |pn| pn.rank orelse 0 else 0;
        const delta: i32 = if (flipped) minlen else -minlen;

        if (graph.getNodePtr(v)) |node| {
            node.rank = parent_rank + delta;
        }
    }
}

// ---------------------------------------------------------------------------
// DFS traversals
// ---------------------------------------------------------------------------

fn dfsPreorder(
    allocator: Allocator,
    tree: *const SpanningTree,
    v: []const u8,
    parent: ?[]const u8,
    out: *std.ArrayListUnmanaged([]const u8),
) !void {
    try out.append(allocator, v);
    const nbrs = try tree.neighbors(v, allocator);
    defer allocator.free(nbrs);
    for (nbrs) |w| {
        if (parent) |p| {
            if (std.mem.eql(u8, p, w)) continue;
        }
        try dfsPreorder(allocator, tree, w, v, out);
    }
}

fn dfsPostorder(
    allocator: Allocator,
    tree: *const SpanningTree,
    v: []const u8,
    parent: ?[]const u8,
    out: *std.ArrayListUnmanaged([]const u8),
) !void {
    const nbrs = try tree.neighbors(v, allocator);
    defer allocator.free(nbrs);
    for (nbrs) |w| {
        if (parent) |p| {
            if (std.mem.eql(u8, p, w)) continue;
        }
        try dfsPostorder(allocator, tree, w, v, out);
    }
    try out.append(allocator, v);
}

// ---------------------------------------------------------------------------
// Cycle detection
// ---------------------------------------------------------------------------

/// Check whether the spanning tree has a cycle (should never happen in a
/// valid tree, but used as a safety check after edge exchanges).
fn hasCycle(allocator: Allocator, tree: *const SpanningTree) !bool {
    var visited = std.StringHashMap(void).init(allocator);
    defer visited.deinit();

    // Pick any node as start
    var ki = tree.nodes.keyIterator();
    const start = if (ki.next()) |kp| kp.* else return false;

    return try dfsCycle(allocator, tree, start, null, &visited, 0);
}

fn dfsCycle(
    allocator: Allocator,
    tree: *const SpanningTree,
    v: []const u8,
    parent: ?[]const u8,
    visited: *std.StringHashMap(void),
    depth: usize,
) !bool {
    if (depth > 1000) return true; // depth-limit safety

    if (visited.contains(v)) return true; // cycle!
    try visited.put(v, {});

    const nbrs = try tree.neighbors(v, allocator);
    defer allocator.free(nbrs);

    for (nbrs) |w| {
        if (parent) |p| {
            if (std.mem.eql(u8, p, w)) continue;
        }
        if (try dfsCycle(allocator, tree, w, v, visited, depth + 1)) return true;
    }

    return false;
}

// ===========================================================================
// Tests
// ===========================================================================

const testing = std.testing;

test "network_simplex: single node" {
    var graph = Graph.init(testing.allocator);
    defer graph.deinit();

    try graph.setNode("a", .{});

    try run(testing.allocator, &graph);

    try testing.expectEqual(@as(?i32, 0), graph.getNode("a").?.rank);
}

test "network_simplex: two connected nodes" {
    var graph = Graph.init(testing.allocator);
    defer graph.deinit();

    try graph.setNode("a", .{});
    try graph.setNode("b", .{});
    try graph.setEdge("a", "b", .{}, null);

    try run(testing.allocator, &graph);

    const a_rank = graph.getNode("a").?.rank.?;
    const b_rank = graph.getNode("b").?.rank.?;
    // b must be exactly 1 rank below a (minlen default = 1)
    try testing.expectEqual(@as(i32, 1), b_rank - a_rank);
}

test "network_simplex: diamond" {
    var graph = Graph.init(testing.allocator);
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

    const a = graph.getNode("a").?.rank.?;
    const b = graph.getNode("b").?.rank.?;
    const c = graph.getNode("c").?.rank.?;
    const d = graph.getNode("d").?.rank.?;

    // a should be at rank 0, b and c at rank 1, d at rank 2
    try testing.expectEqual(@as(i32, 0), a);
    try testing.expectEqual(@as(i32, 1), b);
    try testing.expectEqual(@as(i32, 1), c);
    try testing.expectEqual(@as(i32, 2), d);
}

test "network_simplex: respects minlen" {
    var graph = Graph.init(testing.allocator);
    defer graph.deinit();

    try graph.setNode("a", .{});
    try graph.setNode("b", .{});
    try graph.setEdge("a", "b", .{ .minlen = 3 }, null);

    try run(testing.allocator, &graph);

    const a = graph.getNode("a").?.rank.?;
    const b = graph.getNode("b").?.rank.?;
    try testing.expect(b - a >= 3);
}

test "network_simplex: chain" {
    var graph = Graph.init(testing.allocator);
    defer graph.deinit();

    try graph.setNode("a", .{});
    try graph.setNode("b", .{});
    try graph.setNode("c", .{});
    try graph.setNode("d", .{});
    try graph.setEdge("a", "b", .{}, null);
    try graph.setEdge("b", "c", .{}, null);
    try graph.setEdge("c", "d", .{}, null);

    try run(testing.allocator, &graph);

    const a = graph.getNode("a").?.rank.?;
    const b = graph.getNode("b").?.rank.?;
    const c = graph.getNode("c").?.rank.?;
    const d = graph.getNode("d").?.rank.?;

    try testing.expectEqual(@as(i32, 0), a);
    try testing.expectEqual(@as(i32, 1), b);
    try testing.expectEqual(@as(i32, 2), c);
    try testing.expectEqual(@as(i32, 3), d);
}

test "network_simplex: gansner graph" {
    // Classic example from Gansner et al. 1993
    var graph = Graph.init(testing.allocator);
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

    try run(testing.allocator, &graph);

    const a = graph.getNode("a").?.rank.?;
    const b = graph.getNode("b").?.rank.?;
    const c = graph.getNode("c").?.rank.?;
    const d = graph.getNode("d").?.rank.?;
    const e = graph.getNode("e").?.rank.?;
    const f = graph.getNode("f").?.rank.?;
    const g = graph.getNode("g").?.rank.?;
    const h = graph.getNode("h").?.rank.?;

    // a should be at the top
    try testing.expectEqual(@as(i32, 0), a);
    // h should be at the bottom
    try testing.expectEqual(@as(i32, 4), h);

    // All edges must respect minlen = 1
    try testing.expect(b - a >= 1);
    try testing.expect(c - b >= 1);
    try testing.expect(d - c >= 1);
    try testing.expect(h - d >= 1);
    try testing.expect(e - a >= 1);
    try testing.expect(g - e >= 1);
    try testing.expect(h - g >= 1);
    try testing.expect(f - a >= 1);
    try testing.expect(g - f >= 1);
}

test "network_simplex: disconnected nodes" {
    var graph = Graph.init(testing.allocator);
    defer graph.deinit();

    try graph.setNode("a", .{});
    try graph.setNode("b", .{});
    try graph.setEdge("a", "b", .{}, null);
    try graph.setNode("orphan", .{});

    try run(testing.allocator, &graph);

    // All nodes should have a rank
    try testing.expect(graph.getNode("a").?.rank != null);
    try testing.expect(graph.getNode("b").?.rank != null);
    try testing.expect(graph.getNode("orphan").?.rank != null);
}

test "network_simplex: skip subgraph nodes" {
    var graph = Graph.init(testing.allocator);
    defer graph.deinit();

    try graph.setNode("a", .{});
    try graph.setNode("b", .{});
    try graph.setNode("sub", .{ .is_subgraph = true });
    try graph.setEdge("a", "b", .{}, null);

    try run(testing.allocator, &graph);

    try testing.expectEqual(@as(?i32, 0), graph.getNode("a").?.rank);
    try testing.expectEqual(@as(?i32, 1), graph.getNode("b").?.rank);
}

test "network_simplex: leaveEdge returns none for positive cutvalues" {
    var tree = SpanningTree.init(testing.allocator);
    defer tree.deinit();

    try tree.setNode("a", .{});
    try tree.setNode("b", .{});
    try tree.setNode("c", .{});
    try tree.setEdge("a", "b", .{ .cutvalue = 1 });
    try tree.setEdge("b", "c", .{ .cutvalue = 1 });

    const result = try leaveEdge(testing.allocator, &tree);
    try testing.expect(result == null);
}

test "network_simplex: leaveEdge returns negative cutvalue edge" {
    var tree = SpanningTree.init(testing.allocator);
    defer tree.deinit();

    try tree.setNode("a", .{});
    try tree.setNode("b", .{});
    try tree.setNode("c", .{});
    try tree.setEdge("a", "b", .{ .cutvalue = 1 });
    try tree.setEdge("b", "c", .{ .cutvalue = -1 });

    const result = try leaveEdge(testing.allocator, &tree);
    try testing.expect(result != null);
    const edge = result.?;
    try testing.expect(
        (std.mem.eql(u8, edge.a, "b") and std.mem.eql(u8, edge.b, "c")) or
            (std.mem.eql(u8, edge.a, "c") and std.mem.eql(u8, edge.b, "b")),
    );
}

test "network_simplex: isDescendant" {
    var tree = SpanningTree.init(testing.allocator);
    defer tree.deinit();

    try tree.setNode("a", .{});
    try tree.setNode("b", .{});
    try tree.setNode("c", .{});
    try tree.setEdge("a", "b", .{});
    try tree.setEdge("b", "c", .{});
    tree.root = "a";

    try initLowLimValues(testing.allocator, &tree, tree.root);

    try testing.expect(isDescendant(&tree, "b", "a")); // b is descendant of a
    try testing.expect(isDescendant(&tree, "c", "a")); // c is descendant of a
    try testing.expect(isDescendant(&tree, "c", "b")); // c is descendant of b
    try testing.expect(!isDescendant(&tree, "a", "b")); // a is NOT descendant of b
    try testing.expect(isDescendant(&tree, "a", "a")); // a is descendant of itself
}

test "network_simplex: hasCycle detects cycle" {
    var tree = SpanningTree.init(testing.allocator);
    defer tree.deinit();

    try tree.setNode("a", .{});
    try tree.setNode("b", .{});
    try tree.setNode("c", .{});
    try tree.setEdge("a", "b", .{});
    try tree.setEdge("b", "c", .{});

    // No cycle
    try testing.expect(!try hasCycle(testing.allocator, &tree));

    // Add an edge that creates a cycle: a-c
    try tree.setEdge("a", "c", .{});
    try testing.expect(try hasCycle(testing.allocator, &tree));
}

test "network_simplex: wide diamond with weighted edges" {
    // Network simplex should produce tighter ranks than longest-path
    // when edge weights differ
    var graph = Graph.init(testing.allocator);
    defer graph.deinit();

    try graph.setNode("a", .{});
    try graph.setNode("b", .{});
    try graph.setNode("c", .{});
    try graph.setNode("d", .{});
    try graph.setNode("e", .{});

    try graph.setEdge("a", "b", .{}, null);
    try graph.setEdge("a", "c", .{}, null);
    try graph.setEdge("b", "d", .{}, null);
    try graph.setEdge("c", "d", .{}, null);
    try graph.setEdge("d", "e", .{}, null);

    try run(testing.allocator, &graph);

    const a = graph.getNode("a").?.rank.?;
    const b = graph.getNode("b").?.rank.?;
    const c = graph.getNode("c").?.rank.?;
    const d = graph.getNode("d").?.rank.?;
    const e = graph.getNode("e").?.rank.?;

    // All edges must be satisfied
    try testing.expect(b - a >= 1);
    try testing.expect(c - a >= 1);
    try testing.expect(d - b >= 1);
    try testing.expect(d - c >= 1);
    try testing.expect(e - d >= 1);

    // Should be a tight ranking: a=0, b=c=1, d=2, e=3
    try testing.expectEqual(@as(i32, 0), a);
    try testing.expectEqual(@as(i32, 2), d);
    try testing.expectEqual(@as(i32, 3), e);
}
