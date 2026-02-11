const std = @import("std");
const Allocator = std.mem.Allocator;
const ArrayListUnmanaged = std.ArrayListUnmanaged;
const StringHashMap = std.StringHashMap;

pub const EdgeKey = struct {
    v: []const u8,
    w: []const u8,
    name: ?[]const u8 = null,
    name_owned: bool = false,

    pub fn init(v: []const u8, w: []const u8, name: ?[]const u8) EdgeKey {
        return .{ .v = v, .w = w, .name = name };
    }

    /// Free the owned name string, if any.
    pub fn deinitName(self: *EdgeKey, allocator: Allocator) void {
        if (self.name_owned) {
            if (self.name) |n| allocator.free(n);
            self.name = null;
            self.name_owned = false;
        }
    }
};

pub const EdgeKeyContext = struct {
    pub fn hash(self: @This(), key: EdgeKey) u64 {
        _ = self;
        var hasher = std.hash.Wyhash.init(0);
        hasher.update(key.v);
        // We rely on the hashing of string content.
        // Adding separator helps differentiate (a, b) from (ab, "").
        hasher.update("|");
        hasher.update(key.w);
        if (key.name) |n| {
            hasher.update("|");
            hasher.update(n);
        }
        return hasher.final();
    }

    pub fn eql(self: @This(), a: EdgeKey, b: EdgeKey) bool {
        _ = self;
        if (!std.mem.eql(u8, a.v, b.v)) return false;
        if (!std.mem.eql(u8, a.w, b.w)) return false;

        if (a.name == null and b.name == null) return true;
        if (a.name != null and b.name != null) {
            return std.mem.eql(u8, a.name.?, b.name.?);
        }
        return false;
    }
};

/// A generic directed graph implementation supporting multigraphs and compound nodes.
///
/// TNode: Type of data stored in nodes.
/// TEdge: Type of data stored in edges.
/// TGraph: Type of data stored for the graph itself.
pub fn Digraph(comptime TNode: type, comptime TEdge: type, comptime TGraph: type) type {
    return struct {
        const Self = @This();

        allocator: Allocator,

        // Data storage
        nodes: StringHashMap(TNode),
        edges: std.HashMap(EdgeKey, TEdge, EdgeKeyContext, 80),
        graph_label: TGraph,

        // Topology
        in_edges: StringHashMap(ArrayListUnmanaged(EdgeKey)),
        out_edges: StringHashMap(ArrayListUnmanaged(EdgeKey)),

        // Compound structure
        parent: StringHashMap([]const u8),
        children: StringHashMap(ArrayListUnmanaged([]const u8)),

        edge_counter: usize,

        pub fn init(allocator: Allocator) Self {
            return .{
                .allocator = allocator,
                .nodes = StringHashMap(TNode).init(allocator),
                .edges = std.HashMap(EdgeKey, TEdge, EdgeKeyContext, 80).init(allocator),
                .graph_label = if (@typeInfo(TGraph) == .@"struct") .{} else undefined,
                .in_edges = StringHashMap(ArrayListUnmanaged(EdgeKey)).init(allocator),
                .out_edges = StringHashMap(ArrayListUnmanaged(EdgeKey)).init(allocator),
                .parent = StringHashMap([]const u8).init(allocator),
                .children = StringHashMap(ArrayListUnmanaged([]const u8)).init(allocator),
                .edge_counter = 0,
            };
        }

        pub fn deinitDeep(self: *Self) void {
            var node_iter = self.nodes.valueIterator();
            while (node_iter.next()) |node| {
                if (@hasDecl(TNode, "deinit")) {
                    node.deinit(self.allocator);
                }
            }

            var edge_iter = self.edges.valueIterator();
            while (edge_iter.next()) |e| {
                if (@hasDecl(TEdge, "deinit")) {
                    e.deinit(self.allocator);
                }
            }
            self.deinit();
        }

        pub fn deinit(self: *Self) void {
            self.nodes.deinit();

            // Free owned edge name strings from the authoritative edges map.
            // NOTE: in_edges / out_edges lists share the same name pointers,
            // so we must NOT free names from those lists (would double-free).
            {
                var ek_iter = self.edges.keyIterator();
                while (ek_iter.next()) |key_ptr| {
                    var k = key_ptr.*;
                    k.deinitName(self.allocator);
                }
            }
            self.edges.deinit();

            var in_iter = self.in_edges.valueIterator();
            while (in_iter.next()) |list| list.deinit(self.allocator);
            self.in_edges.deinit();

            var out_iter = self.out_edges.valueIterator();
            while (out_iter.next()) |list| list.deinit(self.allocator);
            self.out_edges.deinit();

            self.parent.deinit();

            var child_iter = self.children.valueIterator();
            while (child_iter.next()) |list| list.deinit(self.allocator);
            self.children.deinit();
        }

        pub fn setGraphLabel(self: *Self, label: TGraph) void {
            self.graph_label = label;
        }

        pub fn getGraphLabel(self: *Self) *TGraph {
            return &self.graph_label;
        }

        pub fn setNode(self: *Self, id: []const u8, label: TNode) !void {
            if (self.nodes.getPtr(id)) |existing| {
                // Free owned resources in the old value before overwriting.
                if (@hasDecl(TNode, "deinit")) {
                    existing.deinit(self.allocator);
                }
                try self.nodes.put(id, label);
            } else {
                try self.nodes.put(id, label);
                if (!self.in_edges.contains(id)) {
                    const list = ArrayListUnmanaged(EdgeKey){};
                    try self.in_edges.put(id, list);
                }
                if (!self.out_edges.contains(id)) {
                    const list = ArrayListUnmanaged(EdgeKey){};
                    try self.out_edges.put(id, list);
                }
            }
        }

        pub fn hasNode(self: *const Self, id: []const u8) bool {
            return self.nodes.contains(id);
        }

        pub fn getNode(self: *const Self, id: []const u8) ?TNode {
            return self.nodes.get(id);
        }

        pub fn getNodePtr(self: *Self, id: []const u8) ?*TNode {
            return self.nodes.getPtr(id);
        }

        pub fn removeNode(self: *Self, id: []const u8) void {
            // Free owned resources in the node data before removing.
            if (@hasDecl(TNode, "deinit")) {
                if (self.nodes.getPtr(id)) |node| {
                    node.deinit(self.allocator);
                }
            }
            if (self.nodes.remove(id)) {
                // Cleanup lists
                if (self.in_edges.getPtr(id)) |list| list.deinit(self.allocator);
                _ = self.in_edges.remove(id);

                if (self.out_edges.getPtr(id)) |list| list.deinit(self.allocator);
                _ = self.out_edges.remove(id);

                // Cleanup hierarchy
                _ = self.parent.remove(id);
                if (self.children.getPtr(id)) |list| list.deinit(self.allocator);
                _ = self.children.remove(id);
            }
        }

        pub fn setEdge(self: *Self, v: []const u8, w: []const u8, label: TEdge, name: ?[]const u8) !void {
            // Use a temporary key (caller-provided slices) for the lookup.
            const lookup_key = EdgeKey.init(v, w, name);

            // Resolve stable node-key references from the nodes HashMap so
            // that EdgeKeys never hold dangling pointers to transient caller
            // strings.  (Node keys live as long as the node.)
            const v_entry = self.nodes.getEntry(v) orelse return error.SourceNodeMissing;
            const w_entry = self.nodes.getEntry(w) orelse return error.TargetNodeMissing;
            const stable_v = v_entry.key_ptr.*;
            const stable_w = w_entry.key_ptr.*;

            if (self.edges.getPtr(lookup_key)) |existing| {
                // Edge already exists — free owned resources in the old value
                // before overwriting.
                if (@hasDecl(TEdge, "deinit")) {
                    existing.deinit(self.allocator);
                }
                // Re-use the existing key (which already has a stable name).
                try self.edges.put(lookup_key, label);
            } else {
                // New edge — duplicate the name so the graph owns it.
                const owned_name: ?[]const u8 = if (name) |n|
                    try self.allocator.dupe(u8, n)
                else
                    null;

                const key = EdgeKey{
                    .v = stable_v,
                    .w = stable_w,
                    .name = owned_name,
                    .name_owned = owned_name != null,
                };

                self.edge_counter += 1;
                try self.edges.put(key, label);

                var out = self.out_edges.getPtr(stable_v).?;
                try out.append(self.allocator, key);

                var in = self.in_edges.getPtr(stable_w).?;
                try in.append(self.allocator, key);
            }
        }

        pub fn edge(self: *const Self, v: []const u8, w: []const u8, name: ?[]const u8) ?TEdge {
            const key = EdgeKey.init(v, w, name);
            return self.edges.get(key);
        }

        pub fn getEdgePtr(self: *Self, v: []const u8, w: []const u8, name: ?[]const u8) ?*TEdge {
            const key = EdgeKey.init(v, w, name);
            return self.edges.getPtr(key);
        }

        pub fn outEdges(self: *const Self, v: []const u8) ?[]const EdgeKey {
            if (self.out_edges.get(v)) |list| {
                return list.items;
            }
            return null;
        }

        pub fn inEdges(self: *const Self, w: []const u8) ?[]const EdgeKey {
            if (self.in_edges.get(w)) |list| {
                return list.items;
            }
            return null;
        }

        pub fn nodeCount(self: *const Self) usize {
            return self.nodes.count();
        }

        pub fn edgeCount(self: *const Self) usize {
            return self.edges.count();
        }

        pub fn nodesIterator(self: *const Self) StringHashMap(TNode).KeyIterator {
            return self.nodes.keyIterator();
        }

        pub fn allNodes(self: *const Self, allocator: Allocator) ![][]const u8 {
            var result = std.ArrayListUnmanaged([]const u8){};
            errdefer result.deinit(allocator);

            var iter = self.nodes.keyIterator();
            while (iter.next()) |key| {
                const duped = try allocator.dupe(u8, key.*);
                try result.append(allocator, duped);
            }

            return result.toOwnedSlice(allocator);
        }

        pub fn hasEdge(self: *const Self, v: []const u8, w: []const u8, name: ?[]const u8) bool {
            const key = EdgeKey.init(v, w, name);
            return self.edges.contains(key);
        }

        pub fn removeEdge(self: *Self, v: []const u8, w: []const u8, name: ?[]const u8) void {
            const lookup_key = EdgeKey.init(v, w, name);

            // Save the owned name pointer BEFORE removing anything, so we
            // can free it AFTER all list comparisons are done (they need
            // to read the name via the shared pointer).
            var owned_name_to_free: ?[]const u8 = null;
            var is_owned = false;
            if (self.edges.getEntry(lookup_key)) |entry| {
                if (entry.key_ptr.name_owned) {
                    owned_name_to_free = entry.key_ptr.name;
                    is_owned = true;
                }
            }

            if (self.edges.remove(lookup_key)) {
                // Remove from out_edges
                if (self.out_edges.getPtr(v)) |out_list| {
                    for (out_list.items, 0..) |edge_key, i| {
                        if (std.mem.eql(u8, edge_key.v, v) and
                            std.mem.eql(u8, edge_key.w, w) and
                            ((edge_key.name == null and name == null) or
                             (edge_key.name != null and name != null and std.mem.eql(u8, edge_key.name.?, name.?)))) {
                            _ = out_list.orderedRemove(i);
                            break;
                        }
                    }
                }

                // Remove from in_edges
                if (self.in_edges.getPtr(w)) |in_list| {
                    for (in_list.items, 0..) |edge_key, i| {
                        if (std.mem.eql(u8, edge_key.v, v) and
                            std.mem.eql(u8, edge_key.w, w) and
                            ((edge_key.name == null and name == null) or
                             (edge_key.name != null and name != null and std.mem.eql(u8, edge_key.name.?, name.?)))) {
                            _ = in_list.orderedRemove(i);
                            break;
                        }
                    }
                }

                // Now that all comparisons are done, free the owned name.
                if (is_owned) {
                    if (owned_name_to_free) |n| self.allocator.free(n);
                }
            }
        }

        pub const EdgeIterator = struct {
            hash_iter: std.HashMap(EdgeKey, TEdge, EdgeKeyContext, 80).Iterator,

            pub fn next(self: *EdgeIterator) ?EdgeEntry {
                if (self.hash_iter.next()) |entry| {
                    return EdgeEntry{
                        .v = entry.key_ptr.v,
                        .w = entry.key_ptr.w,
                        .name = entry.key_ptr.name,
                        .data = entry.value_ptr.*,
                    };
                }
                return null;
            }
        };

        pub const EdgeEntry = struct {
            v: []const u8,
            w: []const u8,
            name: ?[]const u8,
            data: TEdge,
        };

        pub fn edgeIterator(self: *const Self) EdgeIterator {
            return EdgeIterator{
                .hash_iter = self.edges.iterator(),
            };
        }

        // Compound Graph Methods

        pub fn setParent(self: *Self, child: []const u8, parent_id: ?[]const u8) !void {
            if (parent_id) |p| {
                try self.parent.put(child, p);

                var children_entry = try self.children.getOrPut(p);
                if (!children_entry.found_existing) {
                    children_entry.value_ptr.* = ArrayListUnmanaged([]const u8){};
                }
                try children_entry.value_ptr.append(self.allocator, child);
            } else {
                // If removing parent
                 if (self.parent.get(child)) |old_parent| {
                     _ = self.parent.remove(child);
                     // Remove from old_parent's children list
                     if (self.children.getPtr(old_parent)) |list| {
                         for (list.items, 0..) |c, i| {
                             if (std.mem.eql(u8, c, child)) {
                                 _ = list.orderedRemove(i);
                                 break;
                             }
                         }
                     }
                 }
            }
        }

        pub fn getParent(self: *const Self, child: []const u8) ?[]const u8 {
            return self.parent.get(child);
        }

        pub fn getChildren(self: *const Self, parent_id: []const u8) []const []const u8 {
            if (self.children.get(parent_id)) |list| {
                return list.items;
            }
            return &.{};
        }
    };
}
