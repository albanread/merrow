//! Coordinate assignment for dagre layout
//!
//! Y-coordinates are based on rank with ranksep separation.
//! X-coordinates use the Brandes-Köpf algorithm:
//!   "Fast and Simple Horizontal Coordinate Assignment" (2002)
//!
//! The algorithm runs four alignment passes (up-left, up-right, down-left,
//! down-right), compacts each horizontally, then balances by taking the
//! median of the four x-coordinates for each node.

const std = @import("std");
const Allocator = std.mem.Allocator;
const Digraph = @import("../../graph/digraph.zig").Digraph;
const EdgeKey = @import("../../graph/digraph.zig").EdgeKey;
const NodeData = @import("../../model.zig").NodeData;
const EdgeData = @import("../../model.zig").EdgeData;
const GraphData = @import("../../model.zig").GraphData;
const DagreConfig = @import("../dagre.zig").DagreConfig;
const RankDir = @import("../dagre.zig").RankDir;

const Graph = Digraph(NodeData, EdgeData, GraphData);

// ============================================================================
// Public API
// ============================================================================

/// Assign X and Y coordinates to all nodes in the graph.
pub fn position(allocator: Allocator, graph: *Graph, config: DagreConfig) !void {
    // ------------------------------------------------------------------
    // Find max rank
    // ------------------------------------------------------------------
    const max_rank = blk: {
        var max: i32 = 0;
        const nodes = try graph.allNodes(allocator);
        defer {
            for (nodes) |id| allocator.free(id);
            allocator.free(nodes);
        }
        for (nodes) |id| {
            if (graph.getNode(id)) |node| {
                if (node.rank) |r| {
                    if (r > max) max = r;
                }
            }
        }
        break :blk max;
    };

    if (max_rank < 0) return;

    const num_layers = @as(usize, @intCast(max_rank + 1));

    // ------------------------------------------------------------------
    // Build layer matrix (nodes grouped by rank, sorted by order)
    // ------------------------------------------------------------------
    const layering = try buildLayering(allocator, graph, num_layers);
    defer {
        for (layering) |layer| {
            for (layer) |id| allocator.free(id);
            allocator.free(layer);
        }
        allocator.free(layering);
    }

    // ------------------------------------------------------------------
    // Y coordinates (rank-based)
    // ------------------------------------------------------------------
    var max_heights = try allocator.alloc(f64, num_layers);
    defer allocator.free(max_heights);
    @memset(max_heights, 0.0);

    for (layering, 0..) |layer, rank_idx| {
        for (layer) |id| {
            if (graph.getNode(id)) |node| {
                if (node.height > max_heights[rank_idx]) {
                    max_heights[rank_idx] = node.height;
                }
            }
        }
    }

    var rank_positions = try allocator.alloc(f64, num_layers);
    defer allocator.free(rank_positions);
    {
        var cumulative_y: f64 = 0.0;
        for (0..num_layers) |i| {
            rank_positions[i] = cumulative_y + max_heights[i] / 2.0;
            cumulative_y += max_heights[i] + config.ranksep;
        }
    }

    for (layering, 0..) |layer, rank_idx| {
        for (layer) |id| {
            if (graph.getNodePtr(id)) |node| {
                node.y = rank_positions[rank_idx];
            }
        }
    }

    // ------------------------------------------------------------------
    // X coordinates (Brandes-Köpf)
    // ------------------------------------------------------------------
    try positionX(allocator, graph, layering, config);
}

// ============================================================================
// Brandes-Köpf X coordinate assignment
// ============================================================================

/// Assign X coordinates using four BK alignment passes + median balancing.
fn positionX(
    allocator: Allocator,
    graph: *Graph,
    layering: []const []const []const u8,
    config: DagreConfig,
) !void {
    const nodesep = config.nodesep;
    const edgesep = config.edgesep;

    // Find type-1 conflicts (non-inner edges crossing inner segments)
    var conflicts = try findType1Conflicts(allocator, graph, layering);
    defer conflicts.deinit();

    // Find type-2 conflicts (dummy edges crossing border boundaries)
    // and merge into the same conflict set
    {
        var type2 = try findType2Conflicts(allocator, graph, layering);
        defer type2.deinit();
        try conflicts.merge(&type2);
    }

    // Collect all node ids (for result maps) — borrowed from layering
    var all_nodes = std.ArrayListUnmanaged([]const u8){};
    defer all_nodes.deinit(allocator);
    for (layering) |layer| {
        for (layer) |id| {
            try all_nodes.append(allocator, id);
        }
    }

    // Storage for four alignment results
    var xs_ul = std.StringHashMap(f64).init(allocator);
    defer xs_ul.deinit();
    var xs_ur = std.StringHashMap(f64).init(allocator);
    defer xs_ur.deinit();
    var xs_dl = std.StringHashMap(f64).init(allocator);
    defer xs_dl.deinit();
    var xs_dr = std.StringHashMap(f64).init(allocator);
    defer xs_dr.deinit();

    // -- Run four passes -----------------------------------------------
    // Each pass is (vertical direction, horizontal direction).
    // vertical:   up = iterate layers top-to-bottom using predecessors
    //             down = iterate layers bottom-to-top using successors
    // horizontal: left = layer order left-to-right
    //             right = layer order right-to-left (then flip x)

    const passes = [_]struct { vert: enum { up, down }, horiz: enum { left, right } }{
        .{ .vert = .up, .horiz = .left },
        .{ .vert = .up, .horiz = .right },
        .{ .vert = .down, .horiz = .left },
        .{ .vert = .down, .horiz = .right },
    };

    for (passes, 0..) |pass, pass_idx| {
        // Build adjusted layers: reverse layer order for "down" passes
        var adjusted = try allocator.alloc([]const []const u8, layering.len);
        defer allocator.free(adjusted);

        if (pass.vert == .up) {
            @memcpy(adjusted, layering);
        } else {
            for (0..layering.len) |i| {
                adjusted[i] = layering[layering.len - 1 - i];
            }
        }

        // For "right" passes, reverse each layer's node order
        var reversed_layers: ?[][]const []const u8 = null;
        defer {
            if (reversed_layers) |rl| {
                for (rl) |layer| allocator.free(layer);
                allocator.free(rl);
            }
        }

        var aligned_layers: []const []const []const u8 = undefined;
        if (pass.horiz == .right) {
            var rev = try allocator.alloc([]const []const u8, adjusted.len);
            for (adjusted, 0..) |layer, i| {
                var rev_layer = try allocator.alloc([]const u8, layer.len);
                for (layer, 0..) |id, j| {
                    rev_layer[layer.len - 1 - j] = id;
                }
                rev[i] = rev_layer;
            }
            reversed_layers = rev;
            aligned_layers = rev;
        } else {
            aligned_layers = adjusted;
        }

        // Vertical alignment
        var root_map = std.StringHashMap([]const u8).init(allocator);
        defer root_map.deinit();
        var align_map = std.StringHashMap([]const u8).init(allocator);
        defer align_map.deinit();

        try verticalAlignment(
            allocator,
            graph,
            aligned_layers,
            &conflicts,
            &root_map,
            &align_map,
            pass.vert == .up,
        );

        // Horizontal compaction
        var xs = try horizontalCompaction(
            allocator,
            graph,
            aligned_layers,
            &root_map,
            nodesep,
            edgesep,
            pass.horiz == .right,
        );
        defer xs.deinit();

        // Flip x for right-aligned passes
        if (pass.horiz == .right) {
            var it = xs.iterator();
            while (it.next()) |entry| {
                entry.value_ptr.* = -entry.value_ptr.*;
            }
        }

        // Store results into the appropriate pass map
        var target_map = switch (pass_idx) {
            0 => &xs_ul,
            1 => &xs_ur,
            2 => &xs_dl,
            3 => &xs_dr,
            else => unreachable,
        };

        var xit = xs.iterator();
        while (xit.next()) |entry| {
            try target_map.put(entry.key_ptr.*, entry.value_ptr.*);
        }
    }

    // -- Balance: find smallest-width alignment and take median ----------
    const alignment_maps = [_]*const std.StringHashMap(f64){ &xs_ul, &xs_ur, &xs_dl, &xs_dr };

    // Find smallest-width alignment (accounting for node widths)
    var best_idx: usize = 0;
    var best_width: f64 = std.math.inf(f64);
    for (alignment_maps, 0..) |m, idx| {
        var min_bound: f64 = std.math.inf(f64);
        var max_bound: f64 = -std.math.inf(f64);
        for (all_nodes.items) |v| {
            const x = m.get(v) orelse continue;
            const hw = if (graph.getNode(v)) |n| n.width / 2.0 else 0.0;
            const lo = x - hw;
            const hi = x + hw;
            if (lo < min_bound) min_bound = lo;
            if (hi > max_bound) max_bound = hi;
        }
        const w = max_bound - min_bound;
        if (w < best_width) {
            best_width = w;
            best_idx = idx;
        }
    }

    // Compute alignment deltas (align all passes to the best one)
    var deltas: [4]f64 = .{ 0, 0, 0, 0 };
    {
        const ref_map = alignment_maps[best_idx];
        var ref_min: f64 = std.math.inf(f64);
        var ref_max: f64 = -std.math.inf(f64);
        var rit = ref_map.iterator();
        while (rit.next()) |entry| {
            if (entry.value_ptr.* < ref_min) ref_min = entry.value_ptr.*;
            if (entry.value_ptr.* > ref_max) ref_max = entry.value_ptr.*;
        }

        const is_left = [4]bool{ true, false, true, false };

        for (alignment_maps, 0..) |m, idx| {
            if (idx == best_idx) continue;
            var m_min: f64 = std.math.inf(f64);
            var m_max: f64 = -std.math.inf(f64);
            var mit = m.iterator();
            while (mit.next()) |entry| {
                if (entry.value_ptr.* < m_min) m_min = entry.value_ptr.*;
                if (entry.value_ptr.* > m_max) m_max = entry.value_ptr.*;
            }
            deltas[idx] = if (is_left[idx]) ref_min - m_min else ref_max - m_max;
        }
    }

    // Median of four aligned values for each node
    for (all_nodes.items) |v| {
        var coords: [4]f64 = undefined;
        var count: usize = 0;
        for (alignment_maps, 0..) |m, idx| {
            if (m.get(v)) |x| {
                coords[count] = x + deltas[idx];
                count += 1;
            }
        }

        const x: f64 = if (count >= 4) blk: {
            std.mem.sort(f64, coords[0..count], {}, struct {
                fn lt(_: void, a: f64, b: f64) bool {
                    return a < b;
                }
            }.lt);
            break :blk (coords[1] + coords[2]) / 2.0;
        } else if (count >= 2) blk: {
            std.mem.sort(f64, coords[0..count], {}, struct {
                fn lt(_: void, a: f64, b: f64) bool {
                    return a < b;
                }
            }.lt);
            break :blk (coords[0] + coords[count - 1]) / 2.0;
        } else if (count == 1)
            coords[0]
        else
            0.0;

        if (graph.getNodePtr(v)) |node| {
            node.x = x;
        }
    }
}

// ============================================================================
// Type-1 conflict detection
// ============================================================================

/// A set of conflicting node pairs.  For each pair the lexicographically
/// smaller node is the key, the larger is in the value set.
const ConflictSet = struct {
    map: std.StringHashMap(std.StringHashMap(void)),
    allocator: Allocator,

    fn init(allocator: Allocator) ConflictSet {
        return .{
            .map = std.StringHashMap(std.StringHashMap(void)).init(allocator),
            .allocator = allocator,
        };
    }

    fn deinit(self: *ConflictSet) void {
        var it = self.map.valueIterator();
        while (it.next()) |inner| {
            var copy = inner.*;
            copy.deinit();
        }
        self.map.deinit();
    }

    fn add(self: *ConflictSet, a: []const u8, b: []const u8) !void {
        const lo = if (std.mem.order(u8, a, b) == .gt) b else a;
        const hi = if (std.mem.order(u8, a, b) == .gt) a else b;
        const gop = try self.map.getOrPut(lo);
        if (!gop.found_existing) {
            gop.value_ptr.* = std.StringHashMap(void).init(self.allocator);
        }
        try gop.value_ptr.put(hi, {});
    }

    fn has(self: *const ConflictSet, a: []const u8, b: []const u8) bool {
        const lo = if (std.mem.order(u8, a, b) == .gt) b else a;
        const hi = if (std.mem.order(u8, a, b) == .gt) a else b;
        if (self.map.get(lo)) |inner| {
            return inner.contains(hi);
        }
        return false;
    }

    /// Merge all conflict pairs from `other` into this set.
    fn merge(self: *ConflictSet, other: *ConflictSet) !void {
        var it = other.map.iterator();
        while (it.next()) |entry| {
            const lo = entry.key_ptr.*;
            var inner_it = entry.value_ptr.iterator();
            while (inner_it.next()) |inner_entry| {
                const hi = inner_entry.key_ptr.*;
                try self.add(lo, hi);
            }
        }
    }
};

/// Detect type-1 conflicts: a non-inner edge that crosses an inner segment.
/// An inner segment is a dummy-to-dummy edge.  Aligning across such a
/// crossing would bend the inner segment, so we mark it as a conflict.
fn findType1Conflicts(
    allocator: Allocator,
    graph: *const Graph,
    layering: []const []const []const u8,
) !ConflictSet {
    var conflicts = ConflictSet.init(allocator);
    errdefer conflicts.deinit();

    if (layering.len < 2) return conflicts;

    for (1..layering.len) |i| {
        const prev_layer = layering[i - 1];
        const layer = layering[i];
        const prev_len = prev_layer.len;

        var k0: usize = 0;
        var scan_pos: usize = 0;

        for (layer, 0..) |v, i_in_layer| {
            // Check if v is a dummy with a dummy predecessor (inner segment)
            const w = findOtherInnerSegmentNode(graph, v);
            const k1 = if (w) |ww|
                (if (graph.getNode(ww)) |n| n.order orelse prev_len else prev_len)
            else
                prev_len;

            const is_last = i_in_layer == layer.len - 1;

            if (w != null or is_last) {
                const end = i_in_layer + 1;
                for (layer[scan_pos..end]) |scan_node| {
                    // Get predecessors of scan_node
                    const in_edges = graph.inEdges(scan_node) orelse &[_]EdgeKey{};
                    for (in_edges) |ek| {
                        const u_id = ek.v;
                        const u_order = if (graph.getNode(u_id)) |n| n.order orelse 0 else 0;
                        const u_is_dummy = if (graph.getNode(u_id)) |n| n.dummy else false;
                        const scan_is_dummy = if (graph.getNode(scan_node)) |n| n.dummy else false;

                        if ((u_order < k0 or k1 < u_order) and !(u_is_dummy and scan_is_dummy)) {
                            try conflicts.add(u_id, scan_node);
                        }
                    }
                }
                scan_pos = end;
                k0 = k1;
            }
        }
    }

    return conflicts;
}

/// If v is a dummy node, find a dummy predecessor (= the other end of an inner segment).
fn findOtherInnerSegmentNode(graph: *const Graph, v: []const u8) ?[]const u8 {
    const node = graph.getNode(v) orelse return null;
    if (!node.dummy) return null;

    const in_edges = graph.inEdges(v) orelse return null;
    for (in_edges) |ek| {
        if (graph.getNode(ek.v)) |pred_node| {
            if (pred_node.dummy) return ek.v;
        }
    }
    return null;
}

// ============================================================================
// Type-2 conflict detection
// ============================================================================

/// Detect type-2 conflicts: dummy edges that cross subgraph border boundaries.
/// A type-2 conflict occurs when a dummy-to-dummy edge crosses the boundary
/// defined by a border node in the same layer pair.
fn findType2Conflicts(
    allocator: Allocator,
    graph: *const Graph,
    layering: []const []const []const u8,
) !ConflictSet {
    var conflicts = ConflictSet.init(allocator);
    errdefer conflicts.deinit();

    if (layering.len < 2) return conflicts;

    for (1..layering.len) |i| {
        const north = layering[i - 1];
        const south = layering[i];
        var prev_north_pos: i64 = -1;
        var south_pos: usize = 0;

        for (south, 0..) |v, south_lookahead| {
            // Check if v is a border dummy node.
            // In the current model, border dummies are identified by checking
            // whether any subgraph's border_left/border_right lists contain this node.
            // For now we use a heuristic: a dummy node whose id starts with "_border".
            const v_node = graph.getNode(v) orelse continue;
            const v_is_border = v_node.dummy and isBorderNode(v);

            if (v_is_border) {
                // Find predecessor in north layer
                const in_edges = graph.inEdges(v) orelse continue;
                if (in_edges.len == 0) continue;

                const pred = in_edges[0].v;
                const pred_node = graph.getNode(pred) orelse continue;
                const next_north_pos = @as(i64, @intCast(pred_node.order orelse 0));

                // Scan dummy nodes in [south_pos..south_lookahead]
                for (south[south_pos..south_lookahead]) |scan_node| {
                    const scan_nd = graph.getNode(scan_node) orelse continue;
                    if (!scan_nd.dummy) continue;

                    const scan_in = graph.inEdges(scan_node) orelse continue;
                    for (scan_in) |ek| {
                        const u_nd = graph.getNode(ek.v) orelse continue;
                        if (!u_nd.dummy) continue;

                        const u_order = @as(i64, @intCast(u_nd.order orelse 0));
                        if (u_order < prev_north_pos or u_order > next_north_pos) {
                            try conflicts.add(ek.v, scan_node);
                        }
                    }
                }

                south_pos = south_lookahead;
                prev_north_pos = next_north_pos;
            }
        }

        // Final scan from south_pos to end of south layer
        const next_north_pos = @as(i64, @intCast(north.len));
        for (south[south_pos..]) |scan_node| {
            const scan_nd = graph.getNode(scan_node) orelse continue;
            if (!scan_nd.dummy) continue;

            const scan_in = graph.inEdges(scan_node) orelse continue;
            for (scan_in) |ek| {
                const u_nd = graph.getNode(ek.v) orelse continue;
                if (!u_nd.dummy) continue;

                const u_order = @as(i64, @intCast(u_nd.order orelse 0));
                if (u_order < prev_north_pos or u_order > next_north_pos) {
                    try conflicts.add(ek.v, scan_node);
                }
            }
        }
    }

    return conflicts;
}

/// Check if a node id looks like a border node (used by compound graph support).
fn isBorderNode(id: []const u8) bool {
    return std.mem.startsWith(u8, id, "_border");
}

// ============================================================================
// Vertical alignment
// ============================================================================

/// Build vertical alignment: assign each node a block root and an alignment
/// chain pointer.  Uses median-neighbor selection with conflict avoidance.
fn verticalAlignment(
    allocator: Allocator,
    graph: *const Graph,
    layers: []const []const []const u8,
    conflicts: *const ConflictSet,
    root_map: *std.StringHashMap([]const u8),
    align_map: *std.StringHashMap([]const u8),
    use_predecessors: bool,
) !void {
    // Initialise: each node is its own root and aligned to itself
    // Also build a position map (order within the aligned layer)
    var pos = std.StringHashMap(usize).init(allocator);
    defer pos.deinit();

    for (layers) |layer| {
        for (layer, 0..) |v, order| {
            try root_map.put(v, v);
            try align_map.put(v, v);
            try pos.put(v, order);
        }
    }

    // Process layers
    for (layers) |layer| {
        var prev_idx: i64 = -1;

        for (layer) |v| {
            // Collect neighbors (predecessors or successors)
            var neighbors = std.ArrayListUnmanaged([]const u8){};
            defer neighbors.deinit(allocator);

            if (use_predecessors) {
                const in_edges = graph.inEdges(v) orelse &[_]EdgeKey{};
                for (in_edges) |ek| {
                    try neighbors.append(allocator, ek.v);
                }
            } else {
                const out_edges = graph.outEdges(v) orelse &[_]EdgeKey{};
                for (out_edges) |ek| {
                    try neighbors.append(allocator, ek.w);
                }
            }

            if (neighbors.items.len == 0) continue;

            // Sort neighbors by position
            const PosCtx = struct {
                p: *const std.StringHashMap(usize),
            };
            std.mem.sort([]const u8, neighbors.items, PosCtx{ .p = &pos }, struct {
                fn lt(ctx: PosCtx, a: []const u8, b: []const u8) bool {
                    const ap = ctx.p.get(a) orelse 0;
                    const bp = ctx.p.get(b) orelse 0;
                    return ap < bp;
                }
            }.lt);

            // Median neighbor indices
            const len = neighbors.items.len;
            const mp = (@as(f64, @floatFromInt(len)) - 1.0) / 2.0;
            const median_low = @as(usize, @intFromFloat(@floor(mp)));
            const median_high = @as(usize, @intFromFloat(@ceil(mp)));

            var idx = median_low;
            while (idx <= median_high) : (idx += 1) {
                if (idx >= neighbors.items.len) break;
                const w = neighbors.items[idx];
                const w_pos = @as(i64, @intCast(pos.get(w) orelse 0));

                // Can align if:
                // 1. v is still its own alignment (not yet chained)
                // 2. No crossing (w_pos > prev_idx)
                // 3. No type-1 conflict
                const v_align = align_map.get(v) orelse v;
                if (std.mem.eql(u8, v_align, v) and prev_idx < w_pos and !conflicts.has(v, w)) {
                    try align_map.put(w, v);
                    const r = root_map.get(w) orelse w;
                    try root_map.put(v, r);
                    try align_map.put(v, r);
                    prev_idx = w_pos;
                }
            }
        }
    }
}

// ============================================================================
// Horizontal compaction
// ============================================================================

/// Separation between two adjacent nodes in the same layer.
/// Matches the dagre.js sep() function, including labelpos adjustments
/// for dummy edge-label nodes.
fn calculateSep(
    graph: *const Graph,
    v: []const u8,
    u_id: []const u8,
    nodesep: f64,
    edgesep: f64,
    reverse_sep: bool,
) f64 {
    const v_node = graph.getNode(v);
    const u_node = graph.getNode(u_id);

    const v_width = if (v_node) |n| n.width else 0.0;
    const u_width = if (u_node) |n| n.width else 0.0;
    const v_is_dummy = if (v_node) |n| n.dummy else false;
    const u_is_dummy = if (u_node) |n| n.dummy else false;

    var sum: f64 = 0.0;

    // v's width contribution + labelpos adjustment
    sum += v_width / 2.0;
    if (v_node) |n| {
        if (n.label_pos) |lp| {
            const delta: f64 = if (std.mem.eql(u8, lp, "l"))
                -v_width / 2.0
            else if (std.mem.eql(u8, lp, "r"))
                v_width / 2.0
            else
                0.0;
            if (delta != 0.0) {
                sum += if (reverse_sep) delta else -delta;
            }
        }
    }

    // Add separation based on whether nodes are dummies
    sum += if (v_is_dummy) edgesep / 2.0 else nodesep / 2.0;
    sum += if (u_is_dummy) edgesep / 2.0 else nodesep / 2.0;

    // u's width contribution + labelpos adjustment (note: delta signs are inverted vs v)
    sum += u_width / 2.0;
    if (u_node) |n| {
        if (n.label_pos) |lp| {
            const delta: f64 = if (std.mem.eql(u8, lp, "l"))
                u_width / 2.0
            else if (std.mem.eql(u8, lp, "r"))
                -u_width / 2.0
            else
                0.0;
            if (delta != 0.0) {
                sum += if (reverse_sep) delta else -delta;
            }
        }
    }

    return sum;
}

/// Block graph edge: predecessor block root → required separation.
const BlockEdge = struct {
    pred: []const u8,
    sep: f64,
};

/// Assign x coordinates by building a block graph and running two DFS passes.
fn horizontalCompaction(
    allocator: Allocator,
    graph: *const Graph,
    layers: []const []const []const u8,
    root_map: *const std.StringHashMap([]const u8),
    nodesep: f64,
    edgesep: f64,
    reverse_sep: bool,
) !std.StringHashMap(f64) {

    // -- Build block graph ----------------------------------------------
    // Nodes are block roots (in layer-insertion order).
    // Edges encode separation constraints between adjacent blocks.
    var block_order = std.ArrayListUnmanaged([]const u8){};
    defer block_order.deinit(allocator);

    var block_seen = std.StringHashMap(void).init(allocator);
    defer block_seen.deinit();

    // predecessor edges per block root:  target -> list of (pred, sep)
    var block_pred = std.StringHashMap(std.ArrayListUnmanaged(BlockEdge)).init(allocator);
    defer {
        var vit = block_pred.valueIterator();
        while (vit.next()) |lst| {
            var copy = lst.*;
            copy.deinit(allocator);
        }
        block_pred.deinit();
    }

    for (layers) |layer| {
        var prev: ?[]const u8 = null;
        for (layer) |v| {
            const v_root = root_map.get(v) orelse v;
            if (!block_seen.contains(v_root)) {
                try block_seen.put(v_root, {});
                try block_order.append(allocator, v_root);
            }

            if (prev) |u_id| {
                const u_root = root_map.get(u_id) orelse u_id;
                const sep = calculateSep(graph, v, u_id, nodesep, edgesep, reverse_sep);

                const gop = try block_pred.getOrPut(v_root);
                if (!gop.found_existing) {
                    gop.value_ptr.* = std.ArrayListUnmanaged(BlockEdge){};
                }

                // Keep maximum separation for each (u_root → v_root) pair
                var found = false;
                for (gop.value_ptr.items) |*be| {
                    if (std.mem.eql(u8, be.pred, u_root)) {
                        if (sep > be.sep) be.sep = sep;
                        found = true;
                        break;
                    }
                }
                if (!found) {
                    try gop.value_ptr.append(allocator, .{ .pred = u_root, .sep = sep });
                }
            }

            prev = v;
        }
    }

    // Build successor map (for pass 2)
    var block_succ = std.StringHashMap(std.ArrayListUnmanaged(BlockEdge)).init(allocator);
    defer {
        var vit = block_succ.valueIterator();
        while (vit.next()) |lst| {
            var copy = lst.*;
            copy.deinit(allocator);
        }
        block_succ.deinit();
    }

    {
        var pit = block_pred.iterator();
        while (pit.next()) |entry| {
            const target = entry.key_ptr.*;
            for (entry.value_ptr.items) |be| {
                const gop = try block_succ.getOrPut(be.pred);
                if (!gop.found_existing) {
                    gop.value_ptr.* = std.ArrayListUnmanaged(BlockEdge){};
                }
                try gop.value_ptr.append(allocator, .{ .pred = target, .sep = be.sep });
            }
        }
    }

    // -- DFS iteration (matching dagre.js two-phase stack pattern) -------
    var xs = std.StringHashMap(f64).init(allocator);
    errdefer xs.deinit();

    // Pass 1: assign smallest x (predecessors first)
    {
        var stack = std.ArrayListUnmanaged([]const u8){};
        defer stack.deinit(allocator);
        var visited = std.StringHashMap(void).init(allocator);
        defer visited.deinit();

        // Initial stack: block_order (push in reverse so first pops first)
        var idx = block_order.items.len;
        while (idx > 0) {
            idx -= 1;
            try stack.append(allocator, block_order.items[idx]);
        }

        while (stack.items.len > 0) {
            const elem = stack.items[stack.items.len - 1];
            stack.items.len -= 1;

            if (visited.contains(elem)) {
                // Second visit: process
                var x: f64 = 0.0;
                if (block_pred.get(elem)) |preds| {
                    for (preds.items) |be| {
                        if (xs.get(be.pred)) |px| {
                            const candidate = px + be.sep;
                            if (candidate > x) x = candidate;
                        }
                    }
                }
                try xs.put(elem, x);
            } else {
                // First visit: mark and push self + predecessors
                try visited.put(elem, {});
                try stack.append(allocator, elem);
                if (block_pred.get(elem)) |preds| {
                    for (preds.items) |be| {
                        try stack.append(allocator, be.pred);
                    }
                }
            }
        }
    }

    // Pass 2: pull toward maximum (successors first)
    {
        var stack = std.ArrayListUnmanaged([]const u8){};
        defer stack.deinit(allocator);
        var visited = std.StringHashMap(void).init(allocator);
        defer visited.deinit();

        var idx = block_order.items.len;
        while (idx > 0) {
            idx -= 1;
            try stack.append(allocator, block_order.items[idx]);
        }

        while (stack.items.len > 0) {
            const elem = stack.items[stack.items.len - 1];
            stack.items.len -= 1;

            if (visited.contains(elem)) {
                // Second visit: pull toward max
                var min_x: f64 = std.math.inf(f64);
                if (block_succ.get(elem)) |succs| {
                    for (succs.items) |be| {
                        if (xs.get(be.pred)) |sx| {
                            const candidate = sx - be.sep;
                            if (candidate < min_x) min_x = candidate;
                        }
                    }
                }
                if (min_x != std.math.inf(f64)) {
                    if (xs.getPtr(elem)) |cur| {
                        if (min_x > cur.*) cur.* = min_x;
                    }
                }
            } else {
                try visited.put(elem, {});
                try stack.append(allocator, elem);
                if (block_succ.get(elem)) |succs| {
                    for (succs.items) |be| {
                        try stack.append(allocator, be.pred);
                    }
                }
            }
        }
    }

    // -- Map block root x to each node in the block ----------------------
    var result = std.StringHashMap(f64).init(allocator);
    errdefer result.deinit();

    var rit = root_map.iterator();
    while (rit.next()) |entry| {
        const v = entry.key_ptr.*;
        const r = entry.value_ptr.*;
        if (xs.get(r)) |rx| {
            try result.put(v, rx);
        }
    }

    xs.deinit();
    return result;
}

// ============================================================================
// Layer matrix construction
// ============================================================================

/// Build layering: array of arrays where layering[rank] is list of node IDs in order
fn buildLayering(allocator: Allocator, graph: *Graph, num_layers: usize) ![]const []const []const u8 {
    var layers = try allocator.alloc(std.ArrayListUnmanaged([]const u8), num_layers);
    errdefer allocator.free(layers);

    for (layers) |*layer| {
        layer.* = std.ArrayListUnmanaged([]const u8){};
    }

    errdefer {
        for (layers) |*layer| {
            for (layer.items) |id| allocator.free(id);
            layer.deinit(allocator);
        }
        allocator.free(layers);
    }

    const nodes = try graph.allNodes(allocator);
    defer {
        for (nodes) |id| allocator.free(id);
        allocator.free(nodes);
    }

    for (nodes) |id| {
        if (graph.getNode(id)) |node| {
            if (node.rank) |r| {
                const rank_usize = @as(usize, @intCast(r));
                const id_copy = try allocator.dupe(u8, id);
                try layers[rank_usize].append(allocator, id_copy);
            }
        }
    }

    // Sort each layer by order
    for (layers) |*layer| {
        const Context = struct { g: *Graph };
        const lessThan = struct {
            fn f(ctx: Context, a: []const u8, b: []const u8) bool {
                const a_node = ctx.g.getNode(a) orelse return false;
                const b_node = ctx.g.getNode(b) orelse return true;
                const a_order = a_node.order orelse return false;
                const b_order = b_node.order orelse return true;
                return a_order < b_order;
            }
        }.f;
        std.sort.pdq([]const u8, layer.items, Context{ .g = graph }, lessThan);
    }

    var result = try allocator.alloc([]const []const u8, layers.len);
    for (layers, 0..) |*layer, i| {
        result[i] = try layer.toOwnedSlice(allocator);
    }
    allocator.free(layers);

    return result;
}

// ============================================================================
// Tests
// ============================================================================

const testing = std.testing;

test "position: single node gets coordinates" {
    var graph = Graph.init(testing.allocator);
    defer graph.deinit();

    try graph.setNode("A", .{ .rank = 0, .order = 0, .width = 100, .height = 40 });

    const config = DagreConfig{};
    try position(testing.allocator, &graph, config);

    const a = graph.getNode("A").?;
    try testing.expectEqual(@as(f64, 0.0), a.x);
    try testing.expectEqual(@as(f64, 20.0), a.y);
}

test "position: two nodes in same rank are spaced" {
    var graph = Graph.init(testing.allocator);
    defer graph.deinit();

    try graph.setNode("A", .{ .rank = 0, .order = 0, .width = 100, .height = 40 });
    try graph.setNode("B", .{ .rank = 0, .order = 1, .width = 100, .height = 40 });

    const config = DagreConfig{ .nodesep = 50 };
    try position(testing.allocator, &graph, config);

    const a = graph.getNode("A").?;
    const b = graph.getNode("B").?;

    // Both at same Y (rank 0)
    try testing.expectEqual(a.y, b.y);

    // B should be to the right of A
    try testing.expect(b.x > a.x);

    // They should be separated appropriately (no overlap)
    const actual_sep = b.x - a.x;
    // A half width (50) + nodesep (50) + B half width (50) = 150 minimum
    try testing.expect(actual_sep >= 100.0);
}

test "position: chain has increasing Y coordinates" {
    var graph = Graph.init(testing.allocator);
    defer graph.deinit();

    try graph.setNode("A", .{ .rank = 0, .order = 0, .width = 100, .height = 40 });
    try graph.setNode("B", .{ .rank = 1, .order = 0, .width = 100, .height = 40 });
    try graph.setNode("C", .{ .rank = 2, .order = 0, .width = 100, .height = 40 });
    try graph.setEdge("A", "B", .{}, null);
    try graph.setEdge("B", "C", .{}, null);

    const config = DagreConfig{ .ranksep = 50 };
    try position(testing.allocator, &graph, config);

    const a = graph.getNode("A").?;
    const b = graph.getNode("B").?;
    const c = graph.getNode("C").?;

    // Y coordinates increase by height + ranksep
    try testing.expectApproxEqAbs(@as(f64, 20.0), a.y, 0.1);
    try testing.expectApproxEqAbs(@as(f64, 110.0), b.y, 0.1);
    try testing.expectApproxEqAbs(@as(f64, 200.0), c.y, 0.1);

    // Single-node layers should be vertically aligned
    try testing.expect(@abs(a.x - b.x) < 1.0);
    try testing.expect(@abs(b.x - c.x) < 1.0);
}

test "position: diamond structure has proper layout" {
    var graph = Graph.init(testing.allocator);
    defer graph.deinit();

    try graph.setNode("A", .{ .rank = 0, .order = 0, .width = 100, .height = 40 });
    try graph.setNode("B", .{ .rank = 1, .order = 0, .width = 100, .height = 40 });
    try graph.setNode("C", .{ .rank = 1, .order = 1, .width = 100, .height = 40 });
    try graph.setNode("D", .{ .rank = 2, .order = 0, .width = 100, .height = 40 });
    try graph.setEdge("A", "B", .{}, null);
    try graph.setEdge("A", "C", .{}, null);
    try graph.setEdge("B", "D", .{}, null);
    try graph.setEdge("C", "D", .{}, null);

    const config = DagreConfig{ .nodesep = 50, .ranksep = 50 };
    try position(testing.allocator, &graph, config);

    const a = graph.getNode("A").?;
    const b = graph.getNode("B").?;
    const c = graph.getNode("C").?;
    const d = graph.getNode("D").?;

    // B and C at same Y, different X
    try testing.expectEqual(b.y, c.y);
    try testing.expect(b.x != c.x);

    // Y coordinates increasing
    try testing.expect(a.y < b.y);
    try testing.expect(b.y < d.y);
}

test "position: different node sizes respected" {
    var graph = Graph.init(testing.allocator);
    defer graph.deinit();

    try graph.setNode("A", .{ .rank = 0, .order = 0, .width = 200, .height = 60 });
    try graph.setNode("B", .{ .rank = 0, .order = 1, .width = 100, .height = 40 });

    const config = DagreConfig{ .nodesep = 50 };
    try position(testing.allocator, &graph, config);

    const a = graph.getNode("A").?;
    const b = graph.getNode("B").?;

    // Both at same Y
    try testing.expectEqual(a.y, b.y);

    // Check spacing accounts for different widths
    const spacing = b.x - a.x;
    // A half width (100) + nodesep (50) + B half width (50) = 200
    try testing.expect(spacing >= 190.0);
}

test "position: BT rankdir produces TB-space coordinates" {
    var graph = Graph.init(testing.allocator);
    defer graph.deinit();

    try graph.setNode("A", .{ .rank = 0, .order = 0, .width = 100, .height = 40 });
    try graph.setNode("B", .{ .rank = 1, .order = 0, .width = 100, .height = 40 });

    const config = DagreConfig{ .rankdir = .BT };
    try position(testing.allocator, &graph, config);

    const a = graph.getNode("A").?;
    const b = graph.getNode("B").?;

    // Position always works in TB-space — Y increases with rank.
    try testing.expect(a.y < b.y);
}

test "position: LR rankdir produces TB-space coordinates" {
    var graph = Graph.init(testing.allocator);
    defer graph.deinit();

    try graph.setNode("A", .{ .rank = 0, .order = 0, .width = 100, .height = 40 });
    try graph.setNode("B", .{ .rank = 1, .order = 0, .width = 100, .height = 40 });

    const config = DagreConfig{ .rankdir = .LR };
    try position(testing.allocator, &graph, config);

    const a = graph.getNode("A").?;
    const b = graph.getNode("B").?;

    try testing.expect(a.y < b.y);
}

test "position: conflict detection does not crash on simple graph" {
    var graph = Graph.init(testing.allocator);
    defer graph.deinit();

    try graph.setNode("A", .{ .rank = 0, .order = 0, .width = 60, .height = 38 });
    try graph.setNode("B", .{ .rank = 0, .order = 1, .width = 60, .height = 38 });
    try graph.setNode("C", .{ .rank = 1, .order = 0, .width = 60, .height = 38 });
    try graph.setNode("D", .{ .rank = 1, .order = 1, .width = 60, .height = 38 });
    try graph.setEdge("A", "C", .{}, null);
    try graph.setEdge("B", "D", .{}, null);

    const config = DagreConfig{ .nodesep = 50, .ranksep = 50 };
    try position(testing.allocator, &graph, config);

    // All nodes should have valid coordinates
    try testing.expect(graph.getNode("A").?.x != graph.getNode("B").?.x);
    try testing.expect(graph.getNode("C").?.x != graph.getNode("D").?.x);
}

test "position: dummy nodes in chain get aligned" {
    var graph = Graph.init(testing.allocator);
    defer graph.deinit();

    // Simulate a normalized edge: A -> d1 -> d2 -> B
    try graph.setNode("A", .{ .rank = 0, .order = 0, .width = 80, .height = 38 });
    try graph.setNode("d1", .{ .rank = 1, .order = 0, .width = 0, .height = 0, .dummy = true });
    try graph.setNode("d2", .{ .rank = 2, .order = 0, .width = 0, .height = 0, .dummy = true });
    try graph.setNode("B", .{ .rank = 3, .order = 0, .width = 80, .height = 38 });
    try graph.setEdge("A", "d1", .{}, null);
    try graph.setEdge("d1", "d2", .{}, null);
    try graph.setEdge("d2", "B", .{}, null);

    const config = DagreConfig{ .nodesep = 50, .ranksep = 50 };
    try position(testing.allocator, &graph, config);

    // All should be roughly vertically aligned (single node per layer)
    const ax = graph.getNode("A").?.x;
    const d1x = graph.getNode("d1").?.x;
    const d2x = graph.getNode("d2").?.x;
    const bx = graph.getNode("B").?.x;

    try testing.expect(@abs(ax - d1x) < 1.0);
    try testing.expect(@abs(d1x - d2x) < 1.0);
    try testing.expect(@abs(d2x - bx) < 1.0);
}

test "position: wide graph with multiple paths" {
    var graph = Graph.init(testing.allocator);
    defer graph.deinit();

    // a -> b -> d, a -> c -> d, d -> e
    try graph.setNode("a", .{ .rank = 0, .order = 0, .width = 60, .height = 38 });
    try graph.setNode("b", .{ .rank = 1, .order = 0, .width = 60, .height = 38 });
    try graph.setNode("c", .{ .rank = 1, .order = 1, .width = 60, .height = 38 });
    try graph.setNode("d", .{ .rank = 2, .order = 0, .width = 60, .height = 38 });
    try graph.setNode("e", .{ .rank = 3, .order = 0, .width = 60, .height = 38 });
    try graph.setEdge("a", "b", .{}, null);
    try graph.setEdge("a", "c", .{}, null);
    try graph.setEdge("b", "d", .{}, null);
    try graph.setEdge("c", "d", .{}, null);
    try graph.setEdge("d", "e", .{}, null);

    const config = DagreConfig{ .nodesep = 50, .ranksep = 50 };
    try position(testing.allocator, &graph, config);

    const a = graph.getNode("a").?;
    const b = graph.getNode("b").?;
    const c = graph.getNode("c").?;
    const d = graph.getNode("d").?;
    const e = graph.getNode("e").?;

    // b and c should be separated
    try testing.expect(@abs(b.x - c.x) >= 50.0);

    // Y ordering
    try testing.expect(a.y < b.y);
    try testing.expect(b.y < d.y);
    try testing.expect(d.y < e.y);
}

// ============================================================================
// BK-specific unit tests
// ============================================================================

test "bk: type-1 conflict — non-inner edge crossing inner segment" {
    // Layer 0:  a(0)    d0(1)
    //            \      |        <- a→b crosses inner segment d0→d1
    // Layer 1:  d1(0)   b(1)
    //
    // d0→d1 is an inner segment (both dummy). a→b is a non-inner edge
    // that crosses it (a is at order 0, b at order 1, d0 at order 1,
    // d1 at order 0 — the inner segment swaps sides).
    var graph = Graph.init(testing.allocator);
    defer graph.deinit();

    try graph.setNode("a", .{ .rank = 0, .order = 0 });
    try graph.setNode("d0", .{ .rank = 0, .order = 1, .dummy = true });
    try graph.setNode("d1", .{ .rank = 1, .order = 0, .dummy = true });
    try graph.setNode("b", .{ .rank = 1, .order = 1 });

    try graph.setEdge("a", "b", .{}, null);
    try graph.setEdge("d0", "d1", .{}, null);

    const layering = &[_][]const []const u8{
        &[_][]const u8{ "a", "d0" },
        &[_][]const u8{ "d1", "b" },
    };

    var conflicts = try findType1Conflicts(testing.allocator, &graph, layering);
    defer conflicts.deinit();

    // a→b crosses the inner segment d0→d1, so (a, b) should be conflicting
    try testing.expect(conflicts.has("a", "b"));
    // The inner segment itself should NOT be a conflict
    try testing.expect(!conflicts.has("d0", "d1"));
}

test "bk: type-1 no conflict when no crossing" {
    // Layer 0:  a(0)   b(1)
    //            |      |
    // Layer 1:  c(0)   d(1)
    var graph = Graph.init(testing.allocator);
    defer graph.deinit();

    try graph.setNode("a", .{ .rank = 0, .order = 0 });
    try graph.setNode("b", .{ .rank = 0, .order = 1 });
    try graph.setNode("c", .{ .rank = 1, .order = 0 });
    try graph.setNode("d", .{ .rank = 1, .order = 1 });

    try graph.setEdge("a", "c", .{}, null);
    try graph.setEdge("b", "d", .{}, null);

    const layering = &[_][]const []const u8{
        &[_][]const u8{ "a", "b" },
        &[_][]const u8{ "c", "d" },
    };

    var conflicts = try findType1Conflicts(testing.allocator, &graph, layering);
    defer conflicts.deinit();

    try testing.expect(!conflicts.has("a", "c"));
    try testing.expect(!conflicts.has("b", "d"));
}

test "bk: conflict add and has are symmetric" {
    var cs = ConflictSet.init(testing.allocator);
    defer cs.deinit();

    try cs.add("x", "y");

    // Detectable in either argument order
    try testing.expect(cs.has("x", "y"));
    try testing.expect(cs.has("y", "x"));

    // Unrelated pair should not be a conflict
    try testing.expect(!cs.has("x", "z"));
}

test "bk: merge conflicts combines both maps" {
    var a_cs = ConflictSet.init(testing.allocator);
    defer a_cs.deinit();
    try a_cs.add("a", "b");

    var b_cs = ConflictSet.init(testing.allocator);
    defer b_cs.deinit();
    try b_cs.add("c", "d");

    try a_cs.merge(&b_cs);

    try testing.expect(a_cs.has("a", "b"));
    try testing.expect(a_cs.has("c", "d"));
}

test "bk: type-2 conflict detection runs without crash" {
    // Type-2 conflicts apply to border dummy nodes. Since the current
    // codebase doesn't create border dummies, this just verifies
    // the function doesn't crash on a simple graph.
    var graph = Graph.init(testing.allocator);
    defer graph.deinit();

    try graph.setNode("a", .{ .rank = 0, .order = 0 });
    try graph.setNode("b", .{ .rank = 1, .order = 0 });
    try graph.setEdge("a", "b", .{}, null);

    const layering = &[_][]const []const u8{
        &[_][]const u8{"a"},
        &[_][]const u8{"b"},
    };

    var conflicts = try findType2Conflicts(testing.allocator, &graph, layering);
    defer conflicts.deinit();

    // No border nodes, so no type-2 conflicts expected
    try testing.expect(!conflicts.has("a", "b"));
}

test "bk: vertical alignment with single-neighbor median" {
    // a → c, b → c  — c should align with its median predecessor
    var graph = Graph.init(testing.allocator);
    defer graph.deinit();

    try graph.setNode("a", .{ .rank = 0, .order = 0, .width = 50 });
    try graph.setNode("b", .{ .rank = 0, .order = 1, .width = 50 });
    try graph.setNode("c", .{ .rank = 1, .order = 0, .width = 50 });

    try graph.setEdge("a", "c", .{}, null);
    try graph.setEdge("b", "c", .{}, null);

    const layering = &[_][]const []const u8{
        &[_][]const u8{ "a", "b" },
        &[_][]const u8{"c"},
    };

    var conflicts = ConflictSet.init(testing.allocator);
    defer conflicts.deinit();

    var root_map = std.StringHashMap([]const u8).init(testing.allocator);
    defer root_map.deinit();
    var align_map = std.StringHashMap([]const u8).init(testing.allocator);
    defer align_map.deinit();

    try verticalAlignment(
        testing.allocator,
        &graph,
        layering,
        &conflicts,
        &root_map,
        &align_map,
        true, // use predecessors
    );

    // c should be aligned to one of its predecessors (a or b)
    // With two predecessors at positions 0 and 1, median is 0..1
    // First median candidate is at index 0 (a), should align
    const c_root = root_map.get("c") orelse "c";
    try testing.expect(
        std.mem.eql(u8, c_root, "a") or std.mem.eql(u8, c_root, "b"),
    );
}

test "bk: vertical alignment respects conflicts" {
    // a → b, with a conflict marked between them — alignment should NOT happen
    var graph = Graph.init(testing.allocator);
    defer graph.deinit();

    try graph.setNode("a", .{ .rank = 0, .order = 0, .width = 50 });
    try graph.setNode("b", .{ .rank = 1, .order = 0, .width = 50 });

    try graph.setEdge("a", "b", .{}, null);

    const layering = &[_][]const []const u8{
        &[_][]const u8{"a"},
        &[_][]const u8{"b"},
    };

    var conflicts = ConflictSet.init(testing.allocator);
    defer conflicts.deinit();
    try conflicts.add("a", "b");

    var root_map = std.StringHashMap([]const u8).init(testing.allocator);
    defer root_map.deinit();
    var align_map = std.StringHashMap([]const u8).init(testing.allocator);
    defer align_map.deinit();

    try verticalAlignment(
        testing.allocator,
        &graph,
        layering,
        &conflicts,
        &root_map,
        &align_map,
        true,
    );

    // b should remain its own root (conflict prevented alignment)
    const b_root = root_map.get("b") orelse "b";
    try testing.expect(std.mem.eql(u8, b_root, "b"));
}

test "bk: calculateSep basic separation" {
    var graph = Graph.init(testing.allocator);
    defer graph.deinit();

    try graph.setNode("a", .{ .width = 100 });
    try graph.setNode("b", .{ .width = 100 });

    // sep = a_width/2 + nodesep/2 + nodesep/2 + b_width/2
    //     = 50 + 25 + 25 + 50 = 150
    const sep = calculateSep(&graph, "a", "b", 50.0, 20.0, false);
    try testing.expectApproxEqAbs(@as(f64, 150.0), sep, 0.01);
}

test "bk: calculateSep with dummy node uses edgesep" {
    var graph = Graph.init(testing.allocator);
    defer graph.deinit();

    try graph.setNode("a", .{ .width = 100 });
    try graph.setNode("d", .{ .width = 0, .dummy = true });

    // sep = a_width/2 + nodesep/2 + edgesep/2 + d_width/2
    //     = 50 + 25 + 10 + 0 = 85
    const sep = calculateSep(&graph, "a", "d", 50.0, 20.0, false);
    try testing.expectApproxEqAbs(@as(f64, 85.0), sep, 0.01);
}

test "bk: horizontalCompaction single node" {
    var graph = Graph.init(testing.allocator);
    defer graph.deinit();

    try graph.setNode("a", .{ .rank = 0, .order = 0, .width = 50 });

    const layering = &[_][]const []const u8{
        &[_][]const u8{"a"},
    };

    var root_map = std.StringHashMap([]const u8).init(testing.allocator);
    defer root_map.deinit();
    try root_map.put("a", "a");

    var xs = try horizontalCompaction(
        testing.allocator,
        &graph,
        layering,
        &root_map,
        50.0,
        20.0,
        false,
    );
    defer xs.deinit();

    try testing.expect(xs.contains("a"));
    // Single node should get x=0
    try testing.expectApproxEqAbs(@as(f64, 0.0), xs.get("a").?, 0.01);
}

test "bk: horizontalCompaction two nodes same layer" {
    var graph = Graph.init(testing.allocator);
    defer graph.deinit();

    try graph.setNode("a", .{ .rank = 0, .order = 0, .width = 50 });
    try graph.setNode("b", .{ .rank = 0, .order = 1, .width = 50 });

    const layering = &[_][]const []const u8{
        &[_][]const u8{ "a", "b" },
    };

    // Each node is its own root (no alignment)
    var root_map = std.StringHashMap([]const u8).init(testing.allocator);
    defer root_map.deinit();
    try root_map.put("a", "a");
    try root_map.put("b", "b");

    var xs = try horizontalCompaction(
        testing.allocator,
        &graph,
        layering,
        &root_map,
        50.0,
        20.0,
        false,
    );
    defer xs.deinit();

    try testing.expect(xs.contains("a"));
    try testing.expect(xs.contains("b"));

    // b should be to the right of a by at least sep
    try testing.expect(xs.get("b").? > xs.get("a").?);

    // They should not overlap (sep = 50/2 + 25 + 25 + 50/2 = 100)
    const actual_sep = xs.get("b").? - xs.get("a").?;
    try testing.expect(actual_sep >= 99.0);
}

test "bk: block graph preserves layer insertion order" {
    // Verify that block roots appear in layer order, not alphabetical.
    // z at order 0, a at order 1 — z should come before a.
    var graph = Graph.init(testing.allocator);
    defer graph.deinit();

    try graph.setNode("z", .{ .rank = 0, .order = 0, .width = 50 });
    try graph.setNode("a", .{ .rank = 0, .order = 1, .width = 50 });
    try graph.setNode("m", .{ .rank = 1, .order = 0, .width = 50 });

    const layering = &[_][]const []const u8{
        &[_][]const u8{ "z", "a" },
        &[_][]const u8{"m"},
    };

    // Each node is its own root
    var root_map = std.StringHashMap([]const u8).init(testing.allocator);
    defer root_map.deinit();
    try root_map.put("z", "z");
    try root_map.put("a", "a");
    try root_map.put("m", "m");

    var xs = try horizontalCompaction(
        testing.allocator,
        &graph,
        layering,
        &root_map,
        50.0,
        20.0,
        false,
    );
    defer xs.deinit();

    // z should be at x=0 (first in layer, first block root)
    try testing.expectApproxEqAbs(@as(f64, 0.0), xs.get("z").?, 0.01);
    // a should be to the right of z
    try testing.expect(xs.get("a").? > xs.get("z").?);
}

test "bk: positionX single node" {
    var graph = Graph.init(testing.allocator);
    defer graph.deinit();

    try graph.setNode("a", .{ .rank = 0, .order = 0, .width = 50, .height = 40 });

    const layering = &[_][]const []const u8{
        &[_][]const u8{"a"},
    };

    const config = DagreConfig{};
    try positionX(testing.allocator, &graph, layering, config);

    const a = graph.getNode("a").?;
    // Single node — should have some x coordinate (all four passes give same result)
    // The exact value depends on implementation but it should be finite
    try testing.expect(!std.math.isNan(a.x));
    try testing.expect(!std.math.isInf(a.x));
}

test "bk: positionX two nodes same rank separated" {
    var graph = Graph.init(testing.allocator);
    defer graph.deinit();

    try graph.setNode("a", .{ .rank = 0, .order = 0, .width = 50, .height = 40 });
    try graph.setNode("b", .{ .rank = 0, .order = 1, .width = 50, .height = 40 });

    const layering = &[_][]const []const u8{
        &[_][]const u8{ "a", "b" },
    };

    const config = DagreConfig{ .nodesep = 50 };
    try positionX(testing.allocator, &graph, layering, config);

    const a = graph.getNode("a").?;
    const b = graph.getNode("b").?;

    // b should be to the right of a
    try testing.expect(b.x > a.x);

    // They should be separated appropriately (no overlap)
    const half_widths = 25.0 + 25.0;
    const actual_gap = b.x - a.x - half_widths;
    try testing.expect(actual_gap >= 0.0);
}

test "bk: positionX chain — nodes vertically aligned" {
    var graph = Graph.init(testing.allocator);
    defer graph.deinit();

    try graph.setNode("a", .{ .rank = 0, .order = 0, .width = 50, .height = 40 });
    try graph.setNode("b", .{ .rank = 1, .order = 0, .width = 50, .height = 40 });
    try graph.setEdge("a", "b", .{}, null);

    const layering = &[_][]const []const u8{
        &[_][]const u8{"a"},
        &[_][]const u8{"b"},
    };

    const config = DagreConfig{};
    try positionX(testing.allocator, &graph, layering, config);

    const a = graph.getNode("a").?;
    const b = graph.getNode("b").?;

    // Single node per layer — they should be close to vertically aligned
    try testing.expectApproxEqAbs(a.x, b.x, 1.0);
}

test "bk: positionX diamond — b and c separated, a and d centered" {
    var graph = Graph.init(testing.allocator);
    defer graph.deinit();

    try graph.setNode("a", .{ .rank = 0, .order = 0, .width = 50, .height = 50 });
    try graph.setNode("b", .{ .rank = 1, .order = 0, .width = 50, .height = 50 });
    try graph.setNode("c", .{ .rank = 1, .order = 1, .width = 50, .height = 50 });
    try graph.setNode("d", .{ .rank = 2, .order = 0, .width = 50, .height = 50 });
    try graph.setEdge("a", "b", .{}, null);
    try graph.setEdge("a", "c", .{}, null);
    try graph.setEdge("b", "d", .{}, null);
    try graph.setEdge("c", "d", .{}, null);

    const layering = &[_][]const []const u8{
        &[_][]const u8{"a"},
        &[_][]const u8{ "b", "c" },
        &[_][]const u8{"d"},
    };

    const config = DagreConfig{ .nodesep = 50 };
    try positionX(testing.allocator, &graph, layering, config);

    const a = graph.getNode("a").?;
    const b = graph.getNode("b").?;
    const c = graph.getNode("c").?;
    const d = graph.getNode("d").?;

    // b and c should be separated by at least nodesep
    try testing.expect(@abs(b.x - c.x) >= 50.0);

    // a and d should be approximately centered between b and c
    const mid_bc = (b.x + c.x) / 2.0;
    try testing.expectApproxEqAbs(mid_bc, a.x, 2.0);
    try testing.expectApproxEqAbs(mid_bc, d.x, 2.0);
}

test "bk: full position diamond with edge normalization" {
    // Full integration test: position() with a diamond graph including edges.
    // This tests that the entire BK pipeline (conflict detection, alignment,
    // compaction, balance) produces a reasonable layout.
    var graph = Graph.init(testing.allocator);
    defer graph.deinit();

    try graph.setNode("A", .{ .rank = 0, .order = 0, .width = 100, .height = 40 });
    try graph.setNode("B", .{ .rank = 1, .order = 0, .width = 100, .height = 40 });
    try graph.setNode("C", .{ .rank = 1, .order = 1, .width = 100, .height = 40 });
    try graph.setNode("D", .{ .rank = 2, .order = 0, .width = 100, .height = 40 });
    try graph.setEdge("A", "B", .{}, null);
    try graph.setEdge("A", "C", .{}, null);
    try graph.setEdge("B", "D", .{}, null);
    try graph.setEdge("C", "D", .{}, null);

    const config = DagreConfig{ .nodesep = 50, .ranksep = 50 };
    try position(testing.allocator, &graph, config);

    const a_node = graph.getNode("A").?;
    const b_node = graph.getNode("B").?;
    const c_node = graph.getNode("C").?;
    const d_node = graph.getNode("D").?;

    // Y ordering
    try testing.expect(a_node.y < b_node.y);
    try testing.expect(b_node.y < d_node.y);
    try testing.expectApproxEqAbs(b_node.y, c_node.y, 0.01);

    // B and C are separated
    try testing.expect(@abs(b_node.x - c_node.x) >= 100.0);

    // A and D are centered between B and C
    const mid = (b_node.x + c_node.x) / 2.0;
    try testing.expectApproxEqAbs(mid, a_node.x, 2.0);
    try testing.expectApproxEqAbs(mid, d_node.x, 2.0);
}

test "bk: compaction quality — total spread is compact" {
    // A tree-like graph: a→{b,c,d}, all at rank 1.
    // With BK compaction, total spread should be no more than
    // 3 × width + 2 × nodesep = 3×80 + 2×50 = 340.
    var graph = Graph.init(testing.allocator);
    defer graph.deinit();

    try graph.setNode("root", .{ .rank = 0, .order = 0, .width = 80, .height = 40 });
    try graph.setNode("b", .{ .rank = 1, .order = 0, .width = 80, .height = 40 });
    try graph.setNode("c", .{ .rank = 1, .order = 1, .width = 80, .height = 40 });
    try graph.setNode("d", .{ .rank = 1, .order = 2, .width = 80, .height = 40 });
    try graph.setEdge("root", "b", .{}, null);
    try graph.setEdge("root", "c", .{}, null);
    try graph.setEdge("root", "d", .{}, null);

    const config = DagreConfig{ .nodesep = 50, .ranksep = 50 };
    try position(testing.allocator, &graph, config);

    const root_n = graph.getNode("root").?;
    const b_n = graph.getNode("b").?;
    const c_n = graph.getNode("c").?;
    const d_n = graph.getNode("d").?;

    // Find total x-spread including node widths
    var min_x: f64 = std.math.inf(f64);
    var max_x: f64 = -std.math.inf(f64);
    for ([_]NodeData{ root_n, b_n, c_n, d_n }) |n| {
        const lo = n.x - n.width / 2.0;
        const hi = n.x + n.width / 2.0;
        if (lo < min_x) min_x = lo;
        if (hi > max_x) max_x = hi;
    }

    const spread = max_x - min_x;
    // With 3 nodes at rank 1: width spread = 80 + 50 + 80 + 50 + 80 = 340
    // Plus root may extend further, but total should be reasonable
    try testing.expect(spread < 500.0);
}

test "bk: empty layering does not crash" {
    var graph = Graph.init(testing.allocator);
    defer graph.deinit();

    const layering = &[_][]const []const u8{};

    var conflicts = try findType1Conflicts(testing.allocator, &graph, layering);
    defer conflicts.deinit();

    var type2 = try findType2Conflicts(testing.allocator, &graph, layering);
    defer type2.deinit();
}

test "bk: single-layer layering has no conflicts" {
    var graph = Graph.init(testing.allocator);
    defer graph.deinit();

    try graph.setNode("a", .{ .rank = 0, .order = 0 });
    try graph.setNode("b", .{ .rank = 0, .order = 1 });

    const layering = &[_][]const []const u8{
        &[_][]const u8{ "a", "b" },
    };

    var conflicts = try findType1Conflicts(testing.allocator, &graph, layering);
    defer conflicts.deinit();

    // Single layer → no inter-layer crossings possible
    try testing.expect(!conflicts.has("a", "b"));
}

test "bk: isBorderNode recognizes _border prefix" {
    try testing.expect(isBorderNode("_border_left_0"));
    try testing.expect(isBorderNode("_borderRight1"));
    try testing.expect(!isBorderNode("normal_node"));
    try testing.expect(!isBorderNode("border")); // no underscore prefix
}
