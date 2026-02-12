const std = @import("std");
const Allocator = std.mem.Allocator;
const Digraph = @import("../graph/digraph.zig").Digraph;
const model = @import("../model.zig");
const NodeData = model.NodeData;
const EdgeData = model.EdgeData;
const GraphData = model.GraphData;
const Point = model.Point;

const Graph = Digraph(NodeData, EdgeData, GraphData);

/// Information about a self-edge that was removed before layout.
/// Stored so it can be restored to the graph after layout completes.
const SelfEdgeInfo = struct {
    /// Node ID (v == w for self-edges).  Points into the graph's node
    /// key storage, so it's valid as long as the node exists.
    node_id: []const u8,
    /// Edge data (label, style, arrowhead, etc.).  Ownership of any
    /// allocated fields (e.g. label with label_owned=true) is transferred
    /// here while the edge is removed from the graph.
    edge_data: EdgeData,
    /// Optional edge name (owned copy — freed on restore or cleanup).
    edge_name: ?[]const u8,
    edge_name_owned: bool,
};

// Import layout phases
const acyclic = @import("dagre/acyclic.zig");
const rank = @import("dagre/rank.zig");
const normalize = @import("dagre/normalize.zig");
const order_mod = @import("dagre/order.zig");
const position_mod = @import("dagre/position.zig");

/// Dagre layout configuration
pub const DagreConfig = struct {
    /// Direction: TB (top-bottom), BT (bottom-top), LR (left-right), RL (right-left)
    rankdir: RankDir = .TB,
    /// Separation between nodes in the same rank (pixels)
    nodesep: f64 = 50.0,
    /// Separation between edges (pixels)
    edgesep: f64 = 10.0,
    /// Separation between ranks (pixels)
    ranksep: f64 = 50.0,
    /// Horizontal margin (pixels)
    marginx: f64 = 0.0,
    /// Vertical margin (pixels)
    marginy: f64 = 0.0,
    /// Algorithm for making graph acyclic
    acyclicer: Acyclicer = .greedy,
    /// Algorithm for assigning ranks
    ranker: Ranker = .network_simplex,
};

pub const RankDir = enum {
    /// Top to bottom
    TB,
    /// Bottom to top
    BT,
    /// Left to right
    LR,
    /// Right to left
    RL,
};

pub const Acyclicer = enum {
    /// Greedy algorithm (faster, good enough)
    greedy,
    /// Depth-first search based algorithm
    dfs,
};

pub const Ranker = enum {
    /// Network simplex algorithm (optimal, recommended)
    network_simplex,
    /// Tight tree algorithm
    tight_tree,
    /// Longest path algorithm (simple, fast)
    longest_path,
};

/// Main layout function - applies Dagre layout algorithm to graph.
///
/// Dispatches to either the hierarchical container-first pipeline
/// (when the graph contains subgraphs) or the flat pipeline (original
/// Dagre phases).  Coordinate system adjustment/undo wraps both paths
/// so the entire layout operates in normalized TB space.
pub fn layout(
    allocator: std.mem.Allocator,
    graph: *Digraph(NodeData, EdgeData, GraphData),
    config: DagreConfig,
) !void {
    std.debug.print("[dagre] Layout starting...\n", .{});
    std.debug.print("[dagre] Config: rankdir={s}, nodesep={d}, ranksep={d}\n", .{
        @tagName(config.rankdir),
        config.nodesep,
        config.ranksep,
    });

    // Phase 0: Adjust coordinate system for LR/RL
    try adjustCoordinateSystem(allocator, graph, config.rankdir);

    if (hasSubgraphs(graph)) {
        // Hierarchical container-first layout.
        // We are already in adjusted (TB) coordinate space, so pass TB
        // to children to prevent double-flipping during recursion.
        std.debug.print("[dagre] Graph has subgraphs — using hierarchical layout\n", .{});
        var child_config = config;
        child_config.rankdir = .TB;
        try layoutHierarchical(allocator, graph, child_config);
    } else {
        try layoutFlat(allocator, graph, config);
    }

    // Phase 20: Undo coordinate system transformation.
    std.debug.print("[dagre] Undoing coordinate system adjustment (rankdir={s})...\n", .{@tagName(config.rankdir)});
    try undoCoordinateSystem(allocator, graph, config.rankdir);

    std.debug.print("[dagre] Layout complete\n", .{});
}

/// Check whether the graph contains any subgraph nodes.
fn hasSubgraphs(graph: *Graph) bool {
    var it = graph.nodes.iterator();
    while (it.next()) |entry| {
        if (entry.value_ptr.is_subgraph) return true;
    }
    return false;
}

/// The original flat Dagre layout pipeline (phases 1–19).
/// Used for graphs without subgraphs, and also called recursively
/// for internal container layouts.
fn layoutFlat(
    allocator: std.mem.Allocator,
    graph: *Digraph(NodeData, EdgeData, GraphData),
    config: DagreConfig,
) !void {
    // Phase 1.5: Remove self-edges
    std.debug.print("[dagre] Phase 1.5: Removing self-edges...\n", .{});
    var self_edges = std.ArrayListUnmanaged(SelfEdgeInfo){};
    defer {
        for (self_edges.items) |*se| {
            if (se.edge_name_owned) {
                if (se.edge_name) |n| allocator.free(n);
            }
            se.edge_data.deinit(allocator);
        }
        self_edges.deinit(allocator);
    }
    try removeSelfEdges(allocator, graph, &self_edges);
    std.debug.print("[dagre]   Removed {d} self-edge(s)\n", .{self_edges.items.len});

    // Phase 2: Make graph acyclic
    std.debug.print("[dagre] Phase 2: Making graph acyclic...\n", .{});
    try acyclic.run(allocator, graph, config.acyclicer);

    // Phase 4: Assign ranks
    std.debug.print("[dagre] Phase 4: Assigning ranks...\n", .{});
    try rank.assignRanks(allocator, graph, config.ranker);

    // Phase 5: Normalize edges
    std.debug.print("[dagre] Phase 5: Normalizing edges...\n", .{});
    try normalize.normalizeEdges(allocator, graph);

    // Phase 12: Order nodes within ranks
    std.debug.print("[dagre] Phase 12: Ordering nodes...\n", .{});
    try order_mod.order(allocator, graph);

    // Phase 13: Assign coordinates
    std.debug.print("[dagre] Phase 13: Assigning coordinates...\n", .{});
    try position_mod.position(allocator, graph, config);

    // Undo acyclic transformation
    std.debug.print("[dagre] Undoing acyclic transformation...\n", .{});
    try acyclic.undo(allocator, graph);

    // Restore self-edges
    std.debug.print("[dagre] Restoring {d} self-edge(s)...\n", .{self_edges.items.len});
    try restoreSelfEdges(allocator, graph, &self_edges);

    // Phase 18b–19b: Subgraph fixups (only for the top-level flat path;
    // internal container layouts skip these since they have no subgraphs).
    std.debug.print("[dagre] Compacting subgraph children...\n", .{});
    try compactSubgraphChildren(allocator, graph, config);

    std.debug.print("[dagre] Computing subgraph bounds...\n", .{});
    try computeSubgraphBounds(allocator, graph);

    std.debug.print("[dagre] Separating sibling subgraphs...\n", .{});
    try separateSiblingSubgraphs(allocator, graph);
}

// ===========================================================================
// Hierarchical container-first layout
// ===========================================================================

/// Bounding box of a container's internal layout.
const BBox = struct {
    min_x: f64 = std.math.floatMax(f64),
    min_y: f64 = std.math.floatMax(f64),
    max_x: f64 = -std.math.floatMax(f64),
    max_y: f64 = -std.math.floatMax(f64),

    fn width(self: BBox) f64 {
        return self.max_x - self.min_x;
    }
    fn height(self: BBox) f64 {
        return self.max_y - self.min_y;
    }
    fn centerX(self: BBox) f64 {
        return (self.min_x + self.max_x) / 2.0;
    }
    fn centerY(self: BBox) f64 {
        return (self.min_y + self.max_y) / 2.0;
    }
};

/// Reference to an edge in the original graph.
const EdgeRef = struct {
    v: []const u8,
    w: []const u8,
    name: ?[]const u8,
};

/// Information about a root-level container (subgraph).
const ContainerInfo = struct {
    id: []const u8,
    children: std.ArrayListUnmanaged([]const u8),
    intra_edges: std.ArrayListUnmanaged(EdgeRef),
    internal_bounds: BBox,

    fn deinit(self: *ContainerInfo, allocator: std.mem.Allocator) void {
        self.children.deinit(allocator);
        self.intra_edges.deinit(allocator);
    }
};

/// An edge that crosses container boundaries.
const InterEdge = struct {
    src_node: []const u8,
    tgt_node: []const u8,
    src_container: ?[]const u8, // null = free node
    tgt_container: ?[]const u8, // null = free node
    edge_name: ?[]const u8,
};

/// Walk the parent chain to find the root-level container a node belongs to.
/// Returns null if the node is a free node (no subgraph parent).
fn findRootContainer(graph: *Graph, node_id: []const u8) ?[]const u8 {
    var root: ?[]const u8 = null;
    var cursor: ?[]const u8 = graph.getParent(node_id);
    while (cursor) |pid| {
        const p = graph.getNode(pid) orelse break;
        if (p.is_subgraph) {
            root = pid;
        }
        cursor = graph.getParent(pid);
    }
    return root;
}

/// Find the immediate container (direct subgraph parent) of a node.
fn findImmediateContainer(graph: *Graph, node_id: []const u8) ?[]const u8 {
    var cursor: ?[]const u8 = graph.getParent(node_id);
    while (cursor) |pid| {
        const p = graph.getNode(pid) orelse break;
        if (p.is_subgraph) return pid;
        cursor = graph.getParent(pid);
    }
    return null;
}

/// Phase 1: Classify all nodes and edges into containers, free nodes,
/// intra-container edges and inter-container edges.
fn classifyNodesAndEdges(
    allocator: std.mem.Allocator,
    graph: *Graph,
    containers: *std.StringHashMap(ContainerInfo),
    free_nodes: *std.ArrayListUnmanaged([]const u8),
    inter_edges: *std.ArrayListUnmanaged(InterEdge),
) !void {
    // First pass: identify containers and free nodes.
    var node_it = graph.nodes.iterator();
    while (node_it.next()) |entry| {
        const id = entry.key_ptr.*;
        const node = entry.value_ptr.*;
        if (node.is_subgraph) {
            // Register as container.
            const gop = try containers.getOrPut(id);
            if (!gop.found_existing) {
                gop.value_ptr.* = .{
                    .id = id,
                    .children = .{},
                    .intra_edges = .{},
                    .internal_bounds = .{},
                };
            }
        } else if (!node.dummy) {
            // Leaf node — find its root container.
            const root = findRootContainer(graph, id);
            if (root) |container_id| {
                var gop = try containers.getOrPut(container_id);
                if (!gop.found_existing) {
                    gop.value_ptr.* = .{
                        .id = container_id,
                        .children = .{},
                        .intra_edges = .{},
                        .internal_bounds = .{},
                    };
                }
                try gop.value_ptr.children.append(allocator, id);
            } else {
                try free_nodes.append(allocator, id);
            }
        }
    }

    // Second pass: classify edges.
    var edge_it = graph.edgeIterator();
    while (edge_it.next()) |entry| {
        const v = entry.v;
        const w = entry.w;
        const name = entry.name;
        const src_container = findRootContainer(graph, v);
        const tgt_container = findRootContainer(graph, w);

        // Same container → intra; different or null → inter.
        const same = blk: {
            if (src_container == null and tgt_container == null) break :blk true;
            if (src_container) |sc| {
                if (tgt_container) |tc| {
                    break :blk std.mem.eql(u8, sc, tc);
                }
            }
            break :blk false;
        };

        if (same) {
            if (src_container) |sc| {
                if (containers.getPtr(sc)) |ci| {
                    try ci.intra_edges.append(allocator, .{
                        .v = v,
                        .w = w,
                        .name = name,
                    });
                }
            }
            // If both are free nodes with no container, that's a "root-level"
            // edge; it will be handled via the meta-graph as a free→free edge.
            if (src_container == null and tgt_container == null) {
                try inter_edges.append(allocator, .{
                    .src_node = v,
                    .tgt_node = w,
                    .src_container = null,
                    .tgt_container = null,
                    .edge_name = name,
                });
            }
        } else {
            try inter_edges.append(allocator, .{
                .src_node = v,
                .tgt_node = w,
                .src_container = src_container,
                .tgt_container = tgt_container,
                .edge_name = name,
            });
        }
    }
}

/// Recursively collect all leaf (non-subgraph, non-dummy) descendants of a node.
fn collectAllLeafDescendants(
    allocator: std.mem.Allocator,
    graph: *Graph,
    root_id: []const u8,
    result: *std.ArrayListUnmanaged([]const u8),
) !void {
    const children = graph.getChildren(root_id);
    for (children) |cid| {
        const child = graph.getNode(cid) orelse continue;
        if (child.is_subgraph) {
            try collectAllLeafDescendants(allocator, graph, cid, result);
        } else if (!child.dummy) {
            try result.append(allocator, cid);
        }
    }
}

/// Phase 2: Lay out a single container's children in a temporary graph.
/// Writes positions back to the original graph and returns the bounding box.
fn layoutContainerInternal(
    allocator: std.mem.Allocator,
    graph: *Graph,
    container: *ContainerInfo,
    config: DagreConfig,
) !BBox {
    // Collect all leaf descendants (handles nested subgraphs).
    var all_leaves = std.ArrayListUnmanaged([]const u8){};
    defer all_leaves.deinit(allocator);
    try collectAllLeafDescendants(allocator, graph, container.id, &all_leaves);

    if (all_leaves.items.len == 0) {
        return BBox{ .min_x = 0, .min_y = 0, .max_x = 80, .max_y = 40 };
    }

    // Build temporary graph with only this container's leaves + intra edges.
    var temp = Graph.init(allocator);
    defer {
        normalize.freeDummyIds(allocator, &temp);
        temp.deinitDeep();
    }

    // Add leaf nodes.
    for (all_leaves.items) |cid| {
        const orig = graph.getNode(cid) orelse continue;
        try temp.setNode(cid, .{
            .width = orig.width,
            .height = orig.height,
            .shape = orig.shape,
            .label = orig.label,
        });
    }

    // Add intra-edges (only if both endpoints are in the temp graph).
    for (container.intra_edges.items) |eref| {
        if (temp.hasNode(eref.v) and temp.hasNode(eref.w)) {
            const orig_ed = graph.edge(eref.v, eref.w, eref.name);
            if (orig_ed) |ed| {
                try temp.setEdge(eref.v, eref.w, .{
                    .minlen = ed.minlen,
                    .weight = ed.weight,
                }, eref.name);
            } else {
                try temp.setEdge(eref.v, eref.w, .{}, eref.name);
            }
        }
    }

    // Run flat layout on the temp graph.
    try layoutFlat(allocator, &temp, config);

    // Read positions back and compute bounding box.
    var bb = BBox{};
    for (all_leaves.items) |cid| {
        const temp_node = temp.getNode(cid) orelse continue;
        if (graph.getNodePtr(cid)) |orig_ptr| {
            orig_ptr.x = temp_node.x;
            orig_ptr.y = temp_node.y;
        }
        const half_w = temp_node.width / 2.0;
        const half_h = temp_node.height / 2.0;
        if (temp_node.x - half_w < bb.min_x) bb.min_x = temp_node.x - half_w;
        if (temp_node.x + half_w > bb.max_x) bb.max_x = temp_node.x + half_w;
        if (temp_node.y - half_h < bb.min_y) bb.min_y = temp_node.y - half_h;
        if (temp_node.y + half_h > bb.max_y) bb.max_y = temp_node.y + half_h;
    }

    return bb;
}

/// Phase 4: Offset children positions by the meta-graph container position.
fn applyMetaPositions(
    allocator: std.mem.Allocator,
    graph: *Graph,
    meta: *Graph,
    containers: *std.StringHashMap(ContainerInfo),
    free_nodes: []const []const u8,
) !void {
    // Position containers and their children.
    var it = containers.iterator();
    while (it.next()) |entry| {
        const ci = entry.value_ptr;
        const meta_node = meta.getNode(ci.id) orelse continue;

        const bb = ci.internal_bounds;
        const offset_x = meta_node.x - bb.centerX();
        const offset_y = meta_node.y - bb.centerY() + subgraph_title_height / 2.0;

        // Offset all leaf descendants.
        var all_leaves = std.ArrayListUnmanaged([]const u8){};
        defer all_leaves.deinit(allocator);
        try collectAllLeafDescendants(allocator, graph, ci.id, &all_leaves);

        for (all_leaves.items) |cid| {
            if (graph.getNodePtr(cid)) |ptr| {
                ptr.x += offset_x;
                ptr.y += offset_y;
            }
        }

        // Set the container node's position and size.
        if (graph.getNodePtr(ci.id)) |sg_ptr| {
            sg_ptr.x = meta_node.x;
            sg_ptr.y = meta_node.y;
            sg_ptr.width = meta_node.width;
            sg_ptr.height = meta_node.height;
        }
    }

    // Position free nodes directly from meta-graph.
    for (free_nodes) |fid| {
        const meta_node = meta.getNode(fid) orelse continue;
        if (graph.getNodePtr(fid)) |ptr| {
            ptr.x = meta_node.x;
            ptr.y = meta_node.y;
        }
    }
}

/// Phase 5: Compute waypoints for inter-container edges.
/// Simple routing: source center → source container border →
/// target container border → target center.
fn routeInterContainerEdges(
    allocator: std.mem.Allocator,
    graph: *Graph,
    inter_edges_list: []const InterEdge,
) !void {
    _ = allocator;
    for (inter_edges_list) |ie| {
        const ed_ptr = graph.getEdgePtr(ie.src_node, ie.tgt_node, ie.edge_name) orelse continue;

        const src = graph.getNode(ie.src_node) orelse continue;
        const tgt = graph.getNode(ie.tgt_node) orelse continue;

        ed_ptr.points.clearRetainingCapacity();

        // Simple 2-point path: source center → target center.
        // The renderer will clip to node borders.
        try ed_ptr.points.append(graph.allocator, .{ .x = src.x, .y = src.y });
        try ed_ptr.points.append(graph.allocator, .{ .x = tgt.x, .y = tgt.y });
    }
}

/// Main hierarchical layout orchestrator.
fn layoutHierarchical(
    allocator: std.mem.Allocator,
    graph: *Graph,
    config: DagreConfig,
) !void {
    // Phase 1: Classify nodes and edges.
    std.debug.print("[dagre-hier] Phase 1: Classifying nodes and edges...\n", .{});
    var containers = std.StringHashMap(ContainerInfo).init(allocator);
    defer {
        var cit = containers.iterator();
        while (cit.next()) |entry| {
            entry.value_ptr.deinit(allocator);
        }
        containers.deinit();
    }

    var free_nodes = std.ArrayListUnmanaged([]const u8){};
    defer free_nodes.deinit(allocator);

    var inter_edges = std.ArrayListUnmanaged(InterEdge){};
    defer inter_edges.deinit(allocator);

    try classifyNodesAndEdges(allocator, graph, &containers, &free_nodes, &inter_edges);

    std.debug.print("[dagre-hier]   {d} containers, {d} free nodes, {d} inter-edges\n", .{
        containers.count(),
        free_nodes.items.len,
        inter_edges.items.len,
    });

    // Phase 2: Internal layout per container.
    std.debug.print("[dagre-hier] Phase 2: Internal container layouts...\n", .{});
    {
        var cit = containers.iterator();
        while (cit.next()) |entry| {
            const ci = entry.value_ptr;
            std.debug.print("[dagre-hier]   Laying out container '{s}' ({d} children)...\n", .{
                ci.id, ci.children.items.len,
            });
            ci.internal_bounds = try layoutContainerInternal(allocator, graph, ci, config);
            std.debug.print("[dagre-hier]   Container '{s}' bounds: [{d:.1}, {d:.1}] to [{d:.1}, {d:.1}]\n", .{
                ci.id,
                ci.internal_bounds.min_x,
                ci.internal_bounds.min_y,
                ci.internal_bounds.max_x,
                ci.internal_bounds.max_y,
            });
        }
    }

    // Phase 3: Build and layout meta-graph.
    std.debug.print("[dagre-hier] Phase 3: Meta-graph layout...\n", .{});
    var meta = Graph.init(allocator);
    defer {
        normalize.freeDummyIds(allocator, &meta);
        meta.deinitDeep();
    }

    // Add container nodes to meta-graph (sized by internal bounds + padding).
    {
        var cit = containers.iterator();
        while (cit.next()) |entry| {
            const ci = entry.value_ptr;
            const sg = graph.getNode(ci.id) orelse continue;
            const pad = sg.subgraph_padding;
            const bb = ci.internal_bounds;
            const meta_w = bb.width() + pad * 2.0;
            const meta_h = bb.height() + pad * 2.0 + subgraph_title_height;

            try meta.setNode(ci.id, .{
                .width = meta_w,
                .height = meta_h,
                // NOT a subgraph in the meta-graph — treat as opaque box.
                .is_subgraph = false,
            });
        }
    }

    // Add free nodes to meta-graph.
    for (free_nodes.items) |fid| {
        const orig = graph.getNode(fid) orelse continue;
        try meta.setNode(fid, .{
            .width = orig.width,
            .height = orig.height,
            .shape = orig.shape,
        });
    }

    // Add inter-edges to meta-graph.
    for (inter_edges.items) |ie| {
        const src_meta = ie.src_container orelse ie.src_node;
        const tgt_meta = ie.tgt_container orelse ie.tgt_node;
        // Skip self-edges in meta-graph (same container on both ends).
        if (std.mem.eql(u8, src_meta, tgt_meta)) continue;
        // Check both nodes exist in meta-graph.
        if (!meta.hasNode(src_meta) or !meta.hasNode(tgt_meta)) continue;
        try meta.setEdge(src_meta, tgt_meta, .{}, null);
    }

    // Run flat layout on meta-graph.
    try layoutFlat(allocator, &meta, config);

    // Phase 4: Apply meta-graph positions.
    std.debug.print("[dagre-hier] Phase 4: Applying meta positions...\n", .{});
    try applyMetaPositions(allocator, graph, &meta, &containers, free_nodes.items);

    // Phase 5: Route inter-container edges.
    std.debug.print("[dagre-hier] Phase 5: Routing inter-container edges...\n", .{});
    try routeInterContainerEdges(allocator, graph, inter_edges.items);

    std.debug.print("[dagre-hier] Hierarchical layout complete\n", .{});
}

/// ---------------------------------------------------------------------------
/// Subgraph compaction
/// ---------------------------------------------------------------------------
/// After position assignment, nodes from the same subgraph may be spread
/// across a wide x-range because each rank is centered independently.
/// This function computes a target center-x for each subgraph (from its
/// direct leaf children) and shifts all children in each rank toward that
/// center, then re-spaces to avoid overlaps within each rank.
fn compactSubgraphChildren(allocator: Allocator, graph: *Graph, config: DagreConfig) !void {
    const all_nodes = try graph.allNodes(allocator);
    defer {
        for (all_nodes) |id| allocator.free(id);
        allocator.free(all_nodes);
    }

    // Collect subgraph IDs.
    var subgraph_ids = std.ArrayListUnmanaged([]const u8){};
    defer subgraph_ids.deinit(allocator);

    for (all_nodes) |id| {
        const node = graph.getNode(id) orelse continue;
        if (node.is_subgraph) {
            try subgraph_ids.append(allocator, id);
        }
    }

    if (subgraph_ids.items.len == 0) return;

    // For each subgraph, compute the centroid x of its direct non-dummy,
    // non-subgraph children, then shift those children toward that centroid.
    for (subgraph_ids.items) |sg_id| {
        const children = graph.getChildren(sg_id);
        if (children.len == 0) continue;

        // Collect leaf children (non-subgraph, non-dummy) positions.
        var sum_x: f64 = 0;
        var count: f64 = 0;
        for (children) |cid| {
            const child = graph.getNode(cid) orelse continue;
            if (child.is_subgraph or child.dummy) continue;
            sum_x += child.x;
            count += 1;
        }
        if (count < 1) continue;
        const centroid_x = sum_x / count;

        // Group children by rank and compute per-rank group center.
        // Then shift each group toward the overall centroid.
        // We use a simple approach: for each child, compute desired_x as
        // its offset from its rank-group center, re-based on the centroid.
        const RankGroup = struct {
            center_x: f64,
            count: f64,
        };
        var rank_groups = std.AutoHashMap(i32, RankGroup).init(allocator);
        defer rank_groups.deinit();

        for (children) |cid| {
            const child = graph.getNode(cid) orelse continue;
            if (child.is_subgraph or child.dummy) continue;
            const r = child.rank orelse continue;
            var gop = try rank_groups.getOrPut(r);
            if (!gop.found_existing) {
                gop.value_ptr.* = .{ .center_x = 0, .count = 0 };
            }
            gop.value_ptr.center_x += child.x;
            gop.value_ptr.count += 1;
        }

        // Finalise rank group centers.
        var rg_iter = rank_groups.iterator();
        while (rg_iter.next()) |entry| {
            if (entry.value_ptr.count > 0) {
                entry.value_ptr.center_x /= entry.value_ptr.count;
            }
        }

        // Shift children: move each child so its rank-group center aligns
        // with the subgraph centroid.
        for (children) |cid| {
            if (graph.getNodePtr(cid)) |child| {
                if (child.is_subgraph or child.dummy) continue;
                const r = child.rank orelse continue;
                if (rank_groups.get(r)) |rg| {
                    const shift = centroid_x - rg.center_x;
                    child.x += shift;
                }
            }
        }
    }

    // After shifting, nodes within the same rank may overlap.  Re-space
    // each rank to enforce minimum nodesep while preserving order.
    try respaceRanks(allocator, graph, config);
}

/// Walk every rank and ensure adjacent nodes have at least `nodesep`
/// between them, pushing rightward nodes as needed.
fn respaceRanks(allocator: Allocator, graph: *Graph, config: DagreConfig) !void {
    // Find max rank.
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

    if (max_rank < 0) return;
    const num_ranks = @as(usize, @intCast(max_rank + 1));

    // Build sorted node lists per rank.
    var rank_lists = try allocator.alloc(std.ArrayListUnmanaged([]const u8), num_ranks);
    defer {
        for (rank_lists) |*rl| rl.deinit(allocator);
        allocator.free(rank_lists);
    }
    for (rank_lists) |*rl| rl.* = .{};

    {
        const nodes = try graph.allNodes(allocator);
        defer {
            for (nodes) |id| allocator.free(id);
            allocator.free(nodes);
        }
        for (nodes) |id| {
            const node = graph.getNode(id) orelse continue;
            if (node.is_subgraph) continue;
            const r = node.rank orelse continue;
            if (r < 0) continue;
            const ri = @as(usize, @intCast(r));
            try rank_lists[ri].append(allocator, id);
        }
    }

    // Sort each rank by current x, then enforce nodesep.
    for (rank_lists) |*rl| {
        if (rl.items.len < 2) continue;

        const SortCtx = struct {
            g: *Graph,
            pub fn lessThan(ctx: @This(), a: []const u8, b: []const u8) bool {
                const na = ctx.g.getNode(a) orelse return false;
                const nb = ctx.g.getNode(b) orelse return true;
                return na.x < nb.x;
            }
        };
        std.mem.sort([]const u8, rl.items, SortCtx{ .g = graph }, SortCtx.lessThan);

        // Walk left-to-right, pushing rightward if too close.
        for (1..rl.items.len) |i| {
            const left = graph.getNode(rl.items[i - 1]) orelse continue;
            const right_ptr = graph.getNodePtr(rl.items[i]) orelse continue;

            const min_right_x = left.x + left.width / 2.0 + config.nodesep + right_ptr.width / 2.0;
            if (right_ptr.x < min_right_x) {
                right_ptr.x = min_right_x;
            }
        }
    }
}

/// Extra top padding inside a subgraph box reserved for the title label.
/// This ensures children never overlap the title text.
const subgraph_title_height: f64 = 32.0;

/// Minimum gap between sibling subgraph boxes (pixels).
const sibling_subgraph_gap: f64 = 30.0;

/// After layout, compute the bounding box of every subgraph node from
/// its children's positions and sizes.  The subgraph node's (x, y, width,
/// height) are set to enclose all children with padding.  Handles nesting:
/// processes leaf-most subgraphs first so that inner subgraphs are sized
/// before their parents read them.
fn computeSubgraphBounds(allocator: Allocator, graph: *Graph) !void {
    // Collect all subgraph node IDs.
    const all_nodes = try graph.allNodes(allocator);
    defer {
        for (all_nodes) |id| allocator.free(id);
        allocator.free(all_nodes);
    }

    // Build a list of subgraph IDs.  We need to process them bottom-up
    // (deepest nesting first).  A simple approach: repeatedly scan and
    // process any subgraph whose children are all already sized (i.e.
    // non-subgraph or already processed subgraphs).
    var subgraph_ids = std.ArrayListUnmanaged([]const u8){};
    defer subgraph_ids.deinit(allocator);

    for (all_nodes) |id| {
        const node = graph.getNode(id) orelse continue;
        if (node.is_subgraph) {
            try subgraph_ids.append(allocator, id);
        }
    }

    if (subgraph_ids.items.len == 0) return;

    // Reset all subgraph sizes to 0 so the bottom-up pass can detect
    // which ones have been processed.
    for (subgraph_ids.items) |sg_id| {
        if (graph.getNodePtr(sg_id)) |ptr| {
            ptr.width = 0;
            ptr.height = 0;
        }
    }

    // Track which subgraphs have been processed (by marking width > 0
    // after computing bounds — subgraphs start with width = 0).
    var remaining = subgraph_ids.items.len;
    var max_iters: usize = subgraph_ids.items.len + 2;
    while (remaining > 0 and max_iters > 0) : (max_iters -= 1) {
        for (subgraph_ids.items) |sg_id| {
            const sg_node = graph.getNode(sg_id) orelse continue;
            if (!sg_node.is_subgraph) continue;
            // Already processed?
            if (sg_node.width > 0.1) continue;

            const children = graph.getChildren(sg_id);
            if (children.len == 0) {
                // Empty subgraph — give it a small default size.
                if (graph.getNodePtr(sg_id)) |ptr| {
                    ptr.width = 80;
                    ptr.height = 40;
                    ptr.x = 0;
                    ptr.y = 0;
                }
                remaining -= 1;
                continue;
            }

            // Check if all children are sized (non-subgraph children always
            // have width from the sizing phase; subgraph children need to
            // have been processed already).
            var all_ready = true;
            for (children) |child_id| {
                const child = graph.getNode(child_id) orelse continue;
                if (child.is_subgraph and child.width < 0.1) {
                    all_ready = false;
                    break;
                }
            }
            if (!all_ready) continue;

            // Compute bounding box of children.
            var min_x: f64 = std.math.floatMax(f64);
            var min_y: f64 = std.math.floatMax(f64);
            var max_x: f64 = -std.math.floatMax(f64);
            var max_y: f64 = -std.math.floatMax(f64);

            for (children) |child_id| {
                const child = graph.getNode(child_id) orelse continue;
                if (child.dummy) continue;

                const cw = child.width;
                const ch = child.height;
                const left = child.x - cw / 2.0;
                const right = child.x + cw / 2.0;
                const top = child.y - ch / 2.0;
                const bottom = child.y + ch / 2.0;

                if (left < min_x) min_x = left;
                if (right > max_x) max_x = right;
                if (top < min_y) min_y = top;
                if (bottom > max_y) max_y = bottom;
            }

            if (min_x > max_x) {
                // No valid children found — skip.
                continue;
            }

            const pad = sg_node.subgraph_padding;

            // The box extends:
            //   left/right: pad on each side
            //   top: pad + title_height (title is drawn at top of box)
            //   bottom: pad
            const sg_width = (max_x - min_x) + pad * 2.0;
            const sg_height = (max_y - min_y) + pad * 2.0 + subgraph_title_height;
            const sg_cx = (min_x + max_x) / 2.0;
            // Shift center down so the extra title space is at the top
            const sg_cy = (min_y + max_y) / 2.0 + subgraph_title_height / 2.0;

            if (graph.getNodePtr(sg_id)) |ptr| {
                ptr.width = sg_width;
                ptr.height = sg_height;
                ptr.x = sg_cx;
                ptr.y = sg_cy;
            }

            remaining -= 1;

            std.debug.print("[dagre]   Subgraph '{s}': ({d:.1}, {d:.1}) [{d:.0}x{d:.0}]\n", .{
                sg_id, sg_cx, sg_cy, sg_width, sg_height,
            });
        }
    }
}

/// Collect all descendant node IDs of a given node (recursive).
/// Returns owned slice — caller must free each ID and the slice.
fn collectDescendants(allocator: Allocator, graph: *Graph, root_id: []const u8) ![][]const u8 {
    var result = std.ArrayListUnmanaged([]const u8){};
    errdefer {
        for (result.items) |id| allocator.free(id);
        result.deinit(allocator);
    }

    // Use a simple stack-based traversal.
    var stack = std.ArrayListUnmanaged([]const u8){};
    defer stack.deinit(allocator);

    // Seed with direct children.
    const direct = graph.getChildren(root_id);
    for (direct) |child_id| {
        try stack.append(allocator, child_id);
    }

    while (stack.items.len > 0) {
        const id = stack.pop().?;
        const id_copy = try allocator.dupe(u8, id);
        try result.append(allocator, id_copy);

        // If this child is itself a subgraph, recurse into its children.
        const grandchildren = graph.getChildren(id);
        for (grandchildren) |gc| {
            try stack.append(allocator, gc);
        }
    }

    return try result.toOwnedSlice(allocator);
}

/// Shift a node and all its descendants by (dx, dy).
fn shiftSubtree(allocator: Allocator, graph: *Graph, sg_id: []const u8, dx: f64, dy: f64) !void {
    // Shift the subgraph node itself.
    if (graph.getNodePtr(sg_id)) |ptr| {
        ptr.x += dx;
        ptr.y += dy;
    }

    // Shift all descendants.
    const descendants = try collectDescendants(allocator, graph, sg_id);
    defer {
        for (descendants) |id| allocator.free(id);
        allocator.free(descendants);
    }

    for (descendants) |id| {
        if (graph.getNodePtr(id)) |ptr| {
            ptr.x += dx;
            ptr.y += dy;
        }
    }
}

/// After initial subgraph bounds are computed, find sibling subgraphs
/// (subgraphs that share the same parent) and push them apart if their
/// bounding boxes overlap.
///
/// Works **bottom-up** by nesting depth: the deepest siblings are
/// separated first, then bounds are recomputed so that parent subgraphs
/// pick up the corrected child positions before *they* are separated
/// from *their* siblings.  This avoids the double-shift problem where a
/// parent shift plus a child shift would cascade.
fn separateSiblingSubgraphs(allocator: Allocator, graph: *Graph) !void {
    // ----------------------------------------------------------------
    // 1. Collect all subgraph IDs and compute their nesting depth.
    // ----------------------------------------------------------------
    const all_nodes = try graph.allNodes(allocator);
    defer {
        for (all_nodes) |id| allocator.free(id);
        allocator.free(all_nodes);
    }

    const SubgraphInfo = struct {
        id: []const u8,
        depth: usize,
        parent_id: []const u8, // "" for root-level
    };

    var sg_infos = std.ArrayListUnmanaged(SubgraphInfo){};
    defer sg_infos.deinit(allocator);

    var max_depth: usize = 0;

    for (all_nodes) |id| {
        const node = graph.getNode(id) orelse continue;
        if (!node.is_subgraph) continue;
        if (node.width < 0.1) continue;

        // Walk parent chain to compute depth.
        var depth: usize = 0;
        var cursor: ?[]const u8 = graph.getParent(id);
        while (cursor) |pid| {
            depth += 1;
            cursor = graph.getParent(pid);
        }
        if (depth > max_depth) max_depth = depth;

        const parent_id = graph.getParent(id) orelse "";
        try sg_infos.append(allocator, .{
            .id = id,
            .depth = depth,
            .parent_id = parent_id,
        });
    }

    if (sg_infos.items.len == 0) return;

    // ----------------------------------------------------------------
    // 2. Process from deepest level up to depth 0 (root siblings).
    //    At each level, separate overlapping siblings, then recompute
    //    ALL subgraph bounds so the next level sees correct sizes.
    // ----------------------------------------------------------------
    var current_depth: usize = max_depth;
    while (true) {
        // Build sibling groups at this depth.
        // Key: parent ID → list of subgraph IDs at `current_depth`.
        var parent_groups = std.StringHashMap(std.ArrayListUnmanaged([]const u8)).init(allocator);
        defer {
            var it = parent_groups.iterator();
            while (it.next()) |entry| {
                entry.value_ptr.deinit(allocator);
            }
            parent_groups.deinit();
        }

        for (sg_infos.items) |info| {
            if (info.depth != current_depth) continue;
            // Re-check that the subgraph still has valid size (could have
            // been reset by a prior recompute).
            const node = graph.getNode(info.id) orelse continue;
            if (!node.is_subgraph) continue;

            var gop = try parent_groups.getOrPut(info.parent_id);
            if (!gop.found_existing) {
                gop.value_ptr.* = std.ArrayListUnmanaged([]const u8){};
            }
            try gop.value_ptr.append(allocator, info.id);
        }

        // Separate each sibling group at this depth.
        var any_shifted = false;
        var group_iter = parent_groups.iterator();
        while (group_iter.next()) |entry| {
            const siblings = entry.value_ptr.items;
            if (siblings.len < 2) continue;

            // Sort siblings by left edge.
            const SortCtx = struct {
                g: *Graph,
                pub fn lessThan(ctx: @This(), a: []const u8, b: []const u8) bool {
                    const na = ctx.g.getNode(a) orelse return false;
                    const nb = ctx.g.getNode(b) orelse return true;
                    const a_left = na.x - na.width / 2.0;
                    const b_left = nb.x - nb.width / 2.0;
                    return a_left < b_left;
                }
            };
            std.mem.sort([]const u8, siblings, SortCtx{ .g = graph }, SortCtx.lessThan);

            // Walk left-to-right, pushing rightward siblings apart.
            for (1..siblings.len) |i| {
                const left_id = siblings[i - 1];
                const right_id = siblings[i];

                const left_node = graph.getNode(left_id) orelse continue;
                const right_node = graph.getNode(right_id) orelse continue;

                const left_right_edge = left_node.x + left_node.width / 2.0;
                const right_left_edge = right_node.x - right_node.width / 2.0;

                const overlap = left_right_edge - right_left_edge + sibling_subgraph_gap;
                if (overlap > 0) {
                    std.debug.print("[dagre]   depth {d}: separating '{s}' from '{s}' by {d:.1}px\n", .{
                        current_depth, right_id, left_id, overlap,
                    });
                    try shiftSubtree(allocator, graph, right_id, overlap, 0);
                    any_shifted = true;
                }
            }
        }

        // If anything was shifted at this depth, recompute ALL subgraph
        // bounds bottom-up so parent levels see correct sizes.
        if (any_shifted) {
            std.debug.print("[dagre]   Recomputing bounds after depth-{d} separation...\n", .{current_depth});
            try computeSubgraphBounds(allocator, graph);
        }

        if (current_depth == 0) break;
        current_depth -= 1;
    }
}

/// ---------------------------------------------------------------------------
/// Self-edge removal / restoration
/// ---------------------------------------------------------------------------
/// Scan the graph for self-edges (v == w) and move them into `out`.
/// The edges are removed from the graph so they don't interfere with
/// acyclic processing, ranking, or normalization.
fn removeSelfEdges(
    allocator: Allocator,
    graph: *Graph,
    out: *std.ArrayListUnmanaged(SelfEdgeInfo),
) !void {
    // Collect self-edge info first (we can't mutate while iterating).
    const SelfEdgeKey = struct {
        v: []const u8,
        w: []const u8,
        name: ?[]const u8,
    };
    var keys_to_remove = std.ArrayListUnmanaged(SelfEdgeKey){};
    defer keys_to_remove.deinit(allocator);

    var ek_iter = graph.edgeIterator();
    while (ek_iter.next()) |entry| {
        if (std.mem.eql(u8, entry.v, entry.w)) {
            try keys_to_remove.append(allocator, .{
                .v = entry.v,
                .w = entry.w,
                .name = entry.name,
            });
        }
    }

    for (keys_to_remove.items) |ek| {
        // Read the edge data before removing.
        const edge_data_opt = graph.edge(ek.v, ek.w, ek.name);
        if (edge_data_opt) |ed| {
            // Duplicate the edge name if present (graph owns the key's name
            // and will free it on removeEdge).
            const name_copy: ?[]const u8 = if (ek.name) |n|
                try allocator.dupe(u8, n)
            else
                null;

            // Copy the edge data.  We need to take ownership of any
            // allocated fields (label).  Create a copy and mark the
            // original as non-owning so removeEdge doesn't free them.
            const ed_copy = ed;
            // If the edge data owns a label, we take ownership in the copy
            // and clear ownership on the graph's copy so removeEdge/deinit
            // doesn't double-free.
            if (ed.label_owned) {
                if (graph.getEdgePtr(ek.v, ek.w, ek.name)) |graph_ed| {
                    graph_ed.label_owned = false;
                }
            }

            try out.append(allocator, .{
                .node_id = ek.v, // stable ref from graph's node HashMap
                .edge_data = ed_copy,
                .edge_name = name_copy,
                .edge_name_owned = name_copy != null,
            });
        }

        // Remove the edge from the graph.
        graph.removeEdge(ek.v, ek.w, ek.name);
    }
}

/// Re-insert previously removed self-edges into the graph.
fn restoreSelfEdges(
    allocator: Allocator,
    graph: *Graph,
    self_edge_list: *std.ArrayListUnmanaged(SelfEdgeInfo),
) !void {
    for (self_edge_list.items) |*se| {
        try graph.setEdge(se.node_id, se.node_id, se.edge_data, se.edge_name);

        // Free the name copy we made during removal — setEdge dupes it.
        if (se.edge_name_owned) {
            if (se.edge_name) |n| allocator.free(n);
        }
        // Mark as consumed so the defer cleanup doesn't double-free.
        se.edge_name = null;
        se.edge_name_owned = false;
        // Edge data ownership has been transferred to the graph via setEdge;
        // clear label_owned so defer doesn't free it again.
        se.edge_data.label_owned = false;
        se.edge_data.label = null;
    }
    self_edge_list.clearRetainingCapacity();
}

/// ---------------------------------------------------------------------------
/// Coordinate system adjustment
/// ---------------------------------------------------------------------------
/// Pre-layout coordinate system adjustment.
///
/// For LR and RL directions, the layout algorithm still runs in top-to-bottom
/// mode.  We swap each node's width and height so that the "horizontal" extent
/// in the final diagram (which becomes the within-rank dimension after the
/// post-layout undo) is treated as "height" by the TB layout, and vice versa.
///
/// TB and BT do not need a pre-layout swap — BT is handled by flipping Y in
/// the undo step.
fn adjustCoordinateSystem(allocator: Allocator, graph: *Graph, rankdir: RankDir) !void {
    switch (rankdir) {
        .TB, .BT => {}, // No pre-layout adjustment needed
        .LR, .RL => {
            const nodes = try graph.allNodes(allocator);
            defer {
                for (nodes) |id| allocator.free(id);
                allocator.free(nodes);
            }
            for (nodes) |id| {
                if (graph.getNodePtr(id)) |node| {
                    const tmp = node.width;
                    node.width = node.height;
                    node.height = tmp;
                }
            }
        },
    }
}

/// Post-layout coordinate system undo.
///
/// Transforms all node positions and sizes from the internal TB-space back
/// to the requested direction:
///
///   TB — no-op (already correct)
///   BT — flip the Y axis (negate y)
///   LR — swap x↔y and width↔height
///   RL — swap x↔y, negate new x (so flow goes right-to-left), swap w↔h
///
/// This is applied to ALL nodes including dummy nodes and subgraph container
/// nodes so that edge waypoints and subgraph bounding boxes are also correct.
fn undoCoordinateSystem(allocator: Allocator, graph: *Graph, rankdir: RankDir) !void {
    switch (rankdir) {
        .TB => {}, // Already in correct orientation
        .BT => {
            const nodes = try graph.allNodes(allocator);
            defer {
                for (nodes) |id| allocator.free(id);
                allocator.free(nodes);
            }
            for (nodes) |id| {
                if (graph.getNodePtr(id)) |node| {
                    node.y = -node.y;
                }
            }
        },
        .LR => {
            const nodes = try graph.allNodes(allocator);
            defer {
                for (nodes) |id| allocator.free(id);
                allocator.free(nodes);
            }
            for (nodes) |id| {
                if (graph.getNodePtr(id)) |node| {
                    // Swap position axes
                    const tmp_xy = node.x;
                    node.x = node.y;
                    node.y = tmp_xy;
                    // Swap size axes back to original orientation
                    const tmp_wh = node.width;
                    node.width = node.height;
                    node.height = tmp_wh;
                }
            }
        },
        .RL => {
            const nodes = try graph.allNodes(allocator);
            defer {
                for (nodes) |id| allocator.free(id);
                allocator.free(nodes);
            }
            for (nodes) |id| {
                if (graph.getNodePtr(id)) |node| {
                    // Swap axes, negate x so flow runs right-to-left
                    const tmp_xy = node.x;
                    node.x = -node.y;
                    node.y = tmp_xy;
                    // Swap size axes back
                    const tmp_wh = node.width;
                    node.width = node.height;
                    node.height = tmp_wh;
                }
            }
        },
    }
}

/// Reverse edge points for edges that were reversed during acyclic phase
fn reverse_points_for_reversed_edges(graph: *Digraph(NodeData, EdgeData, GraphData)) void {
    _ = graph;
    // TODO: Implement
}

/// Compute graph dimensions and translate to origin
fn compute_dimensions(graph: *Digraph(NodeData, EdgeData, GraphData)) void {
    _ = graph;
    // TODO: Implement
}

test "dagre config default" {
    const config = DagreConfig{};
    try std.testing.expectEqual(RankDir.TB, config.rankdir);
    try std.testing.expectEqual(50.0, config.nodesep);
    try std.testing.expectEqual(50.0, config.ranksep);
}

test "dagre layout with acyclic and ranking" {
    var graph = Digraph(NodeData, EdgeData, GraphData).init(std.testing.allocator);
    defer {
        normalize.freeDummyIds(std.testing.allocator, &graph);
        graph.deinitDeep();
    }

    try graph.setNode("A", .{ .width = 100, .height = 50 });
    try graph.setNode("B", .{ .width = 100, .height = 50 });
    try graph.setNode("C", .{ .width = 100, .height = 50 });
    try graph.setEdge("A", "B", .{}, null);
    try graph.setEdge("B", "C", .{}, null);

    const config = DagreConfig{ .ranker = .longest_path };
    try layout(std.testing.allocator, &graph, config);

    // Verify ranks were assigned
    try std.testing.expect(graph.getNode("A").?.rank != null);
    try std.testing.expect(graph.getNode("B").?.rank != null);
    try std.testing.expect(graph.getNode("C").?.rank != null);

    // Verify rank ordering
    const a_rank = graph.getNode("A").?.rank.?;
    const b_rank = graph.getNode("B").?.rank.?;
    const c_rank = graph.getNode("C").?.rank.?;
    try std.testing.expect(a_rank < b_rank);
    try std.testing.expect(b_rank < c_rank);
}

test "dagre full pipeline: diamond with coordinates" {
    var graph = Digraph(NodeData, EdgeData, GraphData).init(std.testing.allocator);
    defer {
        normalize.freeDummyIds(std.testing.allocator, &graph);
        graph.deinitDeep();
    }

    // Create diamond structure: A → B, A → C, B → D, C → D
    try graph.setNode("A", .{ .width = 100, .height = 40 });
    try graph.setNode("B", .{ .width = 100, .height = 40 });
    try graph.setNode("C", .{ .width = 100, .height = 40 });
    try graph.setNode("D", .{ .width = 100, .height = 40 });
    try graph.setEdge("A", "B", .{}, null);
    try graph.setEdge("A", "C", .{}, null);
    try graph.setEdge("B", "D", .{}, null);
    try graph.setEdge("C", "D", .{}, null);

    const config = DagreConfig{ .ranker = .longest_path, .nodesep = 50, .ranksep = 50 };
    try layout(std.testing.allocator, &graph, config);

    // Verify all nodes have coordinates
    const a = graph.getNode("A").?;
    const b = graph.getNode("B").?;
    const c = graph.getNode("C").?;
    const d = graph.getNode("D").?;

    // All nodes should have ranks assigned
    try std.testing.expect(a.rank != null);
    try std.testing.expect(b.rank != null);
    try std.testing.expect(c.rank != null);
    try std.testing.expect(d.rank != null);

    // All nodes should have orders assigned
    try std.testing.expect(a.order != null);
    try std.testing.expect(b.order != null);
    try std.testing.expect(c.order != null);
    try std.testing.expect(d.order != null);

    // Verify rank structure: A at rank 0, B and C at rank 1, D at rank 2
    try std.testing.expectEqual(@as(i32, 0), a.rank.?);
    try std.testing.expectEqual(@as(i32, 1), b.rank.?);
    try std.testing.expectEqual(@as(i32, 1), c.rank.?);
    try std.testing.expectEqual(@as(i32, 2), d.rank.?);

    // Verify Y coordinates increase with rank
    try std.testing.expect(a.y < b.y);
    try std.testing.expect(b.y < d.y);
    try std.testing.expectEqual(b.y, c.y); // B and C at same rank

    // Verify A and D are centered between B and C (BK compaction)
    const mid_bc = (b.x + c.x) / 2.0;
    try std.testing.expectApproxEqAbs(mid_bc, a.x, 1.0);
    try std.testing.expectApproxEqAbs(mid_bc, d.x, 1.0);

    // Verify B and C are horizontally spaced
    try std.testing.expect(b.x != c.x);
}

test "dagre full pipeline: chain with proper spacing" {
    var graph = Digraph(NodeData, EdgeData, GraphData).init(std.testing.allocator);
    defer {
        normalize.freeDummyIds(std.testing.allocator, &graph);
        graph.deinitDeep();
    }

    // Create chain: A → B → C
    try graph.setNode("A", .{ .width = 100, .height = 40 });
    try graph.setNode("B", .{ .width = 100, .height = 40 });
    try graph.setNode("C", .{ .width = 100, .height = 40 });
    try graph.setEdge("A", "B", .{}, null);
    try graph.setEdge("B", "C", .{}, null);

    const config = DagreConfig{ .ranker = .longest_path, .ranksep = 60 };
    try layout(std.testing.allocator, &graph, config);

    const a = graph.getNode("A").?;
    const b = graph.getNode("B").?;
    const c = graph.getNode("C").?;

    // Verify all centered horizontally
    try std.testing.expectEqual(@as(f64, 0.0), a.x);
    try std.testing.expectEqual(@as(f64, 0.0), b.x);
    try std.testing.expectEqual(@as(f64, 0.0), c.x);

    // Verify Y spacing (40 height + 60 ranksep = 100 per level)
    try std.testing.expectApproxEqAbs(@as(f64, 20.0), a.y, 0.1); // half of 40
    try std.testing.expectApproxEqAbs(@as(f64, 120.0), b.y, 0.1); // 40 + 60 + 20
    try std.testing.expectApproxEqAbs(@as(f64, 220.0), c.y, 0.1); // 40 + 60 + 40 + 60 + 20
}

test "dagre full pipeline: diamond with network simplex ranker" {
    var graph = Digraph(NodeData, EdgeData, GraphData).init(std.testing.allocator);
    defer {
        normalize.freeDummyIds(std.testing.allocator, &graph);
        graph.deinitDeep();
    }

    // Create diamond structure: A → B, A → C, B → D, C → D
    try graph.setNode("A", .{ .width = 100, .height = 40 });
    try graph.setNode("B", .{ .width = 100, .height = 40 });
    try graph.setNode("C", .{ .width = 100, .height = 40 });
    try graph.setNode("D", .{ .width = 100, .height = 40 });
    try graph.setEdge("A", "B", .{}, null);
    try graph.setEdge("A", "C", .{}, null);
    try graph.setEdge("B", "D", .{}, null);
    try graph.setEdge("C", "D", .{}, null);

    const config = DagreConfig{ .ranker = .network_simplex, .nodesep = 50, .ranksep = 50 };
    try layout(std.testing.allocator, &graph, config);

    // Verify all nodes have coordinates
    const a = graph.getNode("A").?;
    const b = graph.getNode("B").?;
    const c = graph.getNode("C").?;
    const d = graph.getNode("D").?;

    // Verify rank ordering: A at top, B and C in middle, D at bottom
    try std.testing.expect(a.rank.? < b.rank.?);
    try std.testing.expect(a.rank.? < c.rank.?);
    try std.testing.expectEqual(b.rank.?, c.rank.?);
    try std.testing.expect(b.rank.? < d.rank.?);

    // Verify Y ordering follows ranks
    try std.testing.expect(a.y < b.y);
    try std.testing.expect(a.y < c.y);
    try std.testing.expect(b.y < d.y);
    try std.testing.expect(c.y < d.y);

    // B and C should be side by side (different X, same Y)
    try std.testing.expect(b.x != c.x);
    try std.testing.expectApproxEqAbs(b.y, c.y, 0.1);
}

test "dagre network simplex: larger graph produces valid layout" {
    var graph = Digraph(NodeData, EdgeData, GraphData).init(std.testing.allocator);
    defer {
        normalize.freeDummyIds(std.testing.allocator, &graph);
        graph.deinitDeep();
    }

    // Gansner-style graph: a -> b -> c -> d -> h, a -> e -> g -> h, a -> f -> g
    try graph.setNode("a", .{ .width = 60, .height = 38 });
    try graph.setNode("b", .{ .width = 60, .height = 38 });
    try graph.setNode("c", .{ .width = 60, .height = 38 });
    try graph.setNode("d", .{ .width = 60, .height = 38 });
    try graph.setNode("e", .{ .width = 60, .height = 38 });
    try graph.setNode("f", .{ .width = 60, .height = 38 });
    try graph.setNode("g", .{ .width = 60, .height = 38 });
    try graph.setNode("h", .{ .width = 60, .height = 38 });

    try graph.setEdge("a", "b", .{}, null);
    try graph.setEdge("b", "c", .{}, null);
    try graph.setEdge("c", "d", .{}, null);
    try graph.setEdge("d", "h", .{}, null);
    try graph.setEdge("a", "e", .{}, null);
    try graph.setEdge("e", "g", .{}, null);
    try graph.setEdge("g", "h", .{}, null);
    try graph.setEdge("a", "f", .{}, null);
    try graph.setEdge("f", "g", .{}, null);

    const config = DagreConfig{ .ranker = .network_simplex, .nodesep = 50, .ranksep = 50 };
    try layout(std.testing.allocator, &graph, config);

    // All nodes should have valid positions
    const a = graph.getNode("a").?;
    const h = graph.getNode("h").?;

    // a at top, h at bottom
    try std.testing.expect(a.y < h.y);

    // All edge constraints satisfied: every target below its source
    for ([_]struct { v: []const u8, w: []const u8 }{
        .{ .v = "a", .w = "b" },
        .{ .v = "b", .w = "c" },
        .{ .v = "c", .w = "d" },
        .{ .v = "d", .w = "h" },
        .{ .v = "a", .w = "e" },
        .{ .v = "e", .w = "g" },
        .{ .v = "g", .w = "h" },
        .{ .v = "a", .w = "f" },
        .{ .v = "f", .w = "g" },
    }) |edge| {
        const src = graph.getNode(edge.v).?;
        const tgt = graph.getNode(edge.w).?;
        try std.testing.expect(src.y < tgt.y);
    }
}

// TODO: Fix infinite loop in longest_path algorithm with cycles
// test "dagre layout breaks cycles" {
//     var graph = Digraph(NodeData, EdgeData, GraphData).init(std.testing.allocator);
//     defer graph.deinit();

//     try graph.setNode("A", .{ .width = 100, .height = 50 });
//     try graph.setNode("B", .{ .width = 100, .height = 50 });
//     try graph.setNode("C", .{ .width = 100, .height = 50 });
//     try graph.setEdge("A", "B", .{}, null);
//     try graph.setEdge("B", "C", .{}, null);
//     try graph.setEdge("C", "A", .{}, null); // Creates cycle

//     const config = DagreConfig{ .acyclicer = .dfs, .ranker = .longest_path };
//     try layout(std.testing.allocator, &graph, config);

//     // After layout, graph should be restored (undo reverses the edge reversals)
//     // Verify all nodes have ranks
//     try std.testing.expect(graph.getNode("A").?.rank != null);
//     try std.testing.expect(graph.getNode("B").?.rank != null);
//     try std.testing.expect(graph.getNode("C").?.rank != null);
// }
