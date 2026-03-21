/// Canvas state: holds the live editable graph and all selection / viewport data.
/// This module is pure data — no Win32 or D2D calls.
const std = @import("std");

// ---------------------------------------------------------------------------
// FFI types re-exported from app/preview.zig.  We declare them here so that
// this module does not import the whole preview module.
// ---------------------------------------------------------------------------

pub const StudioColor = extern struct {
    r: u8,
    g: u8,
    b: u8,
    a: u8,
};

pub const StudioEditableNode = extern struct {
    id: [*c]const u8,
    label: [*c]const u8,
    subtitle: [*c]const u8,
    attributes_text: [*c]const u8,
    methods_text: [*c]const u8,
    parent_subgraph_id: [*c]const u8,
    shape: u32,
    x: f64,
    y: f64,
    width: f64,
    height: f64,
    fill: StudioColor,
    body_fill: StudioColor,
    stroke: StudioColor,
    stroke_width: f32,
    label_color: StudioColor,
    label_font_size: f32,
};

pub const StudioEditableEdge = extern struct {
    source_id: [*c]const u8,
    target_id: [*c]const u8,
    label: [*c]const u8,
    label_font_size: f32,
    color: StudioColor,
    thickness: f32,
    line_style: u32,
    has_arrow: u8,
    has_source_arrow: u8,
    source_end_style: u32,
    target_end_style: u32,
};

pub const StudioEditableSubgraph = extern struct {
    id: [*c]const u8,
    title: [*c]const u8,
    parent_subgraph_id: [*c]const u8,
    x: f64,
    y: f64,
    width: f64,
    height: f64,
    corner_radius: f64,
    fill: StudioColor,
    stroke: StudioColor,
    stroke_width: f32,
    title_x: f64,
    title_y: f64,
    title_font_size: f32,
    title_color: StudioColor,
};

pub const StudioEditableGraph = extern struct {
    width: f64,
    height: f64,
    graph_type: u32,
    background: StudioColor,
    subgraphs: [*c]StudioEditableSubgraph,
    subgraph_count: usize,
    nodes: [*c]StudioEditableNode,
    node_count: usize,
    edges: [*c]StudioEditableEdge,
    edge_count: usize,
};

// ---------------------------------------------------------------------------
// Selection model
// ---------------------------------------------------------------------------

pub const SelectionKind = enum(u8) {
    none,
    node,
    subgraph,
    edge,
};

pub const Selection = struct {
    kind: SelectionKind = .none,
    /// Index into the appropriate slice of the graph.  Only valid when kind != .none.
    index: usize = 0,
};

// ---------------------------------------------------------------------------
// Resize handle positions (8-way cardinal + corner)
// ---------------------------------------------------------------------------

pub const HandlePos = enum(u8) {
    top_left,
    top_center,
    top_right,
    mid_left,
    mid_right,
    bot_left,
    bot_center,
    bot_right,
};

// ---------------------------------------------------------------------------
// Viewport / pan / zoom
// ---------------------------------------------------------------------------

pub const Viewport = struct {
    /// Pan offset in canvas (logical) coordinates.
    pan_x: f64 = 0,
    pan_y: f64 = 0,
    /// Zoom factor.  1.0 = 100 %.
    zoom: f64 = 1.0,

    /// Convert a canvas point to a pixel position within the canvas window.
    pub fn canvasToScreen(self: Viewport, cx: f64, cy: f64) struct { x: f64, y: f64 } {
        return .{
            .x = (cx - self.pan_x) * self.zoom,
            .y = (cy - self.pan_y) * self.zoom,
        };
    }

    /// Convert a screen pixel position within the canvas window to canvas coords.
    pub fn screenToCanvas(self: Viewport, sx: f64, sy: f64) struct { x: f64, y: f64 } {
        return .{
            .x = sx / self.zoom + self.pan_x,
            .y = sy / self.zoom + self.pan_y,
        };
    }
};

pub const GraphBounds = struct {
    min_x: f64,
    min_y: f64,
    max_x: f64,
    max_y: f64,

    pub fn width(self: GraphBounds) f64 {
        return self.max_x - self.min_x;
    }

    pub fn height(self: GraphBounds) f64 {
        return self.max_y - self.min_y;
    }
};

pub fn graphBounds(graph: *const StudioEditableGraph) ?GraphBounds {
    var have_bounds = false;
    var min_x: f64 = 0;
    var min_y: f64 = 0;
    var max_x: f64 = 0;
    var max_y: f64 = 0;

    if (graph.subgraph_count > 0 and graph.subgraphs != null) {
        for (graph.subgraphs[0..graph.subgraph_count]) |*sg| {
            const left = sg.x;
            const top = sg.y;
            const right = sg.x + sg.width;
            const bottom = sg.y + sg.height;
            if (!have_bounds) {
                min_x = left;
                min_y = top;
                max_x = right;
                max_y = bottom;
                have_bounds = true;
            } else {
                min_x = @min(min_x, left);
                min_y = @min(min_y, top);
                max_x = @max(max_x, right);
                max_y = @max(max_y, bottom);
            }
        }
    }

    if (graph.node_count > 0 and graph.nodes != null) {
        for (graph.nodes[0..graph.node_count]) |*node| {
            const left = node.x;
            const top = node.y;
            const right = node.x + node.width;
            const bottom = node.y + node.height;
            if (!have_bounds) {
                min_x = left;
                min_y = top;
                max_x = right;
                max_y = bottom;
                have_bounds = true;
            } else {
                min_x = @min(min_x, left);
                min_y = @min(min_y, top);
                max_x = @max(max_x, right);
                max_y = @max(max_y, bottom);
            }
        }
    }

    if (have_bounds) {
        min_x = @min(min_x, 0.0);
        min_y = @min(min_y, 0.0);
        max_x = @max(max_x, graph.width);
        max_y = @max(max_y, graph.height);
        return .{ .min_x = min_x, .min_y = min_y, .max_x = max_x, .max_y = max_y };
    }

    if (graph.width > 0 and graph.height > 0) {
        return .{ .min_x = 0, .min_y = 0, .max_x = graph.width, .max_y = graph.height };
    }

    return null;
}

pub const ContentBounds = struct {
    min_x: f64,
    min_y: f64,
    max_x: f64,
    max_y: f64,
};

pub fn subgraphIndexById(graph: *const StudioEditableGraph, id: [*c]const u8) ?usize {
    if (id == null or graph.subgraphs == null) return null;
    const needle = std.mem.span(id);
    for (graph.subgraphs[0..graph.subgraph_count], 0..) |*sg, idx| {
        if (sg.id == null) continue;
        if (std.mem.eql(u8, std.mem.span(sg.id), needle)) return idx;
    }
    return null;
}

pub fn subgraphBelongsToSubgraph(graph: *const StudioEditableGraph, child_idx: usize, ancestor_idx: usize) bool {
    if (child_idx >= graph.subgraph_count or ancestor_idx >= graph.subgraph_count or graph.subgraphs == null) return false;
    return parentIdBelongsToSubgraph(graph, graph.subgraphs[child_idx].parent_subgraph_id, ancestor_idx);
}

pub fn nodeBelongsToSubgraph(graph: *const StudioEditableGraph, node_idx: usize, ancestor_idx: usize) bool {
    if (node_idx >= graph.node_count or ancestor_idx >= graph.subgraph_count or graph.nodes == null) return false;
    return parentIdBelongsToSubgraph(graph, graph.nodes[node_idx].parent_subgraph_id, ancestor_idx);
}

pub fn objectIdBelongsToSubgraph(graph: *const StudioEditableGraph, id: [*c]const u8, ancestor_idx: usize) bool {
    if (id == null or ancestor_idx >= graph.subgraph_count or graph.subgraphs == null) return false;
    const ancestor_id = std.mem.span(graph.subgraphs[ancestor_idx].id);
    const object_id = std.mem.span(id);
    if (std.mem.eql(u8, object_id, ancestor_id)) return true;

    if (graph.nodes != null) {
        for (graph.nodes[0..graph.node_count], 0..) |*node, idx| {
            if (node.id == null) continue;
            if (std.mem.eql(u8, std.mem.span(node.id), object_id)) {
                return nodeBelongsToSubgraph(graph, idx, ancestor_idx);
            }
        }
    }

    if (graph.subgraphs != null) {
        for (graph.subgraphs[0..graph.subgraph_count], 0..) |*subgraph, idx| {
            if (subgraph.id == null) continue;
            if (std.mem.eql(u8, std.mem.span(subgraph.id), object_id)) {
                return idx == ancestor_idx or subgraphBelongsToSubgraph(graph, idx, ancestor_idx);
            }
        }
    }

    return false;
}

pub fn edgeBelongsToSubgraph(graph: *const StudioEditableGraph, edge_idx: usize, ancestor_idx: usize) bool {
    if (edge_idx >= graph.edge_count or graph.edges == null) return false;
    const edge = &graph.edges[edge_idx];
    return objectIdBelongsToSubgraph(graph, edge.source_id, ancestor_idx) and
        objectIdBelongsToSubgraph(graph, edge.target_id, ancestor_idx);
}

pub fn moveSubgraphWithContents(graph: *StudioEditableGraph, subgraph_idx: usize, dx: f64, dy: f64) void {
    if (subgraph_idx >= graph.subgraph_count or graph.subgraphs == null) return;

    graph.subgraphs[subgraph_idx].x += dx;
    graph.subgraphs[subgraph_idx].y += dy;
    graph.subgraphs[subgraph_idx].title_x += dx;
    graph.subgraphs[subgraph_idx].title_y += dy;

    if (graph.nodes != null) {
        for (graph.nodes[0..graph.node_count], 0..) |*node, idx| {
            if (!nodeBelongsToSubgraph(graph, idx, subgraph_idx)) continue;
            node.x += dx;
            node.y += dy;
        }
    }

    if (graph.subgraphs != null) {
        for (graph.subgraphs[0..graph.subgraph_count], 0..) |*subgraph, idx| {
            if (!subgraphBelongsToSubgraph(graph, idx, subgraph_idx)) continue;
            subgraph.x += dx;
            subgraph.y += dy;
            subgraph.title_x += dx;
            subgraph.title_y += dy;
        }
    }
}

pub fn subgraphContentBounds(graph: *const StudioEditableGraph, subgraph_idx: usize) ?ContentBounds {
    if (subgraph_idx >= graph.subgraph_count or graph.subgraphs == null) return null;

    var have_bounds = false;
    var min_x: f64 = 0;
    var min_y: f64 = 0;
    var max_x: f64 = 0;
    var max_y: f64 = 0;

    const selected = &graph.subgraphs[subgraph_idx];
    const title_rect = estimatedSubgraphTitleBounds(@ptrCast(selected));
    extendBounds(&have_bounds, &min_x, &min_y, &max_x, &max_y, title_rect.min_x, title_rect.min_y, title_rect.max_x, title_rect.max_y);

    if (graph.nodes != null) {
        for (graph.nodes[0..graph.node_count], 0..) |*node, idx| {
            if (!nodeBelongsToSubgraph(graph, idx, subgraph_idx)) continue;
            extendBounds(&have_bounds, &min_x, &min_y, &max_x, &max_y, node.x, node.y, node.x + node.width, node.y + node.height);
        }
    }

    if (graph.subgraphs != null) {
        for (graph.subgraphs[0..graph.subgraph_count], 0..) |*subgraph, idx| {
            if (!subgraphBelongsToSubgraph(graph, idx, subgraph_idx)) continue;
            extendBounds(&have_bounds, &min_x, &min_y, &max_x, &max_y, subgraph.x, subgraph.y, subgraph.x + subgraph.width, subgraph.y + subgraph.height);

            const child_title = estimatedSubgraphTitleBounds(@ptrCast(subgraph));
            extendBounds(&have_bounds, &min_x, &min_y, &max_x, &max_y, child_title.min_x, child_title.min_y, child_title.max_x, child_title.max_y);
        }
    }

    if (!have_bounds) return null;
    return .{ .min_x = min_x, .min_y = min_y, .max_x = max_x, .max_y = max_y };
}

fn parentIdBelongsToSubgraph(graph: *const StudioEditableGraph, parent_id: [*c]const u8, ancestor_idx: usize) bool {
    if (parent_id == null or ancestor_idx >= graph.subgraph_count or graph.subgraphs == null) return false;
    const ancestor_id = std.mem.span(graph.subgraphs[ancestor_idx].id);

    var current_parent = parent_id;
    while (current_parent != null) {
        const current_id = std.mem.span(current_parent);
        if (std.mem.eql(u8, current_id, ancestor_id)) return true;
        const parent_idx = subgraphIndexById(graph, current_parent) orelse return false;
        current_parent = graph.subgraphs[parent_idx].parent_subgraph_id;
    }
    return false;
}

fn extendBounds(have_bounds: *bool, min_x: *f64, min_y: *f64, max_x: *f64, max_y: *f64, left: f64, top: f64, right: f64, bottom: f64) void {
    if (!have_bounds.*) {
        min_x.* = left;
        min_y.* = top;
        max_x.* = right;
        max_y.* = bottom;
        have_bounds.* = true;
        return;
    }

    min_x.* = @min(min_x.*, left);
    min_y.* = @min(min_y.*, top);
    max_x.* = @max(max_x.*, right);
    max_y.* = @max(max_y.*, bottom);
}

fn estimatedSubgraphTitleBounds(subgraph: *const StudioEditableSubgraph) ContentBounds {
    const title_len: usize = if (subgraph.title != null) std.mem.span(subgraph.title).len else 0;
    const font_size = @as(f64, @floatCast(std.math.clamp(subgraph.title_font_size, 6.0, 48.0)));
    const half_w = @max(16.0, @as(f64, @floatFromInt(title_len)) * font_size * 0.30);
    const half_h = font_size * 1.4;
    return .{
        .min_x = subgraph.title_x - half_w,
        .min_y = subgraph.title_y - half_h,
        .max_x = subgraph.title_x + half_w,
        .max_y = subgraph.title_y + half_h,
    };
}

// ---------------------------------------------------------------------------
// Drag state
// ---------------------------------------------------------------------------

pub const DragKind = enum(u8) {
    none,
    pan,
    /// Mouse is down on an object but hasn't moved past the dead-zone yet.
    /// If the user releases without exceeding the threshold this is a
    /// click-to-select; if they exceed it, it becomes move_object.
    pending_select,
    move_object,
    resize_object,
};

pub const DragState = struct {
    kind: DragKind = .none,
    /// Screen pixel position where the drag started.
    start_screen_x: i32 = 0,
    start_screen_y: i32 = 0,
    /// Canvas position of the object's origin at drag start (move / resize).
    object_origin_x: f64 = 0,
    object_origin_y: f64 = 0,
    /// Canvas size of the object at drag start (resize).
    object_origin_w: f64 = 0,
    object_origin_h: f64 = 0,
    /// Which handle is being dragged (resize).
    handle: HandlePos = .bot_right,
    /// Last mouse position (any drag kind).
    last_screen_x: i32 = 0,
    last_screen_y: i32 = 0,
};

// ---------------------------------------------------------------------------
// Insertion mode
// ---------------------------------------------------------------------------

pub const InsertionKind = enum(u8) {
    none,
    node,
    subgraph,
    connector_source,
    connector_target,
};

pub const InsertionState = struct {
    kind: InsertionKind = .none,
    /// Shape code for node insertion (values mirror the Zig StudioEditableNode.shape field).
    node_shape: u32 = 0,
    /// When inserting a connector, the source object id (null-terminated).
    connector_source_id: ?[*:0]const u8 = null,
};

// ---------------------------------------------------------------------------
// Top-level canvas state
// ---------------------------------------------------------------------------

pub const CanvasState = struct {
    allocator: std.mem.Allocator,

    /// The live graph loaded from a Mermaid source.  Owned and freed by this struct.
    graph: ?*StudioEditableGraph = null,

    selection: Selection = .{},
    hover: Selection = .{},
    viewport: Viewport = .{},
    drag: DragState = .{},
    insertion: InsertionState = .{},

    pub fn init(allocator: std.mem.Allocator) CanvasState {
        return .{ .allocator = allocator };
    }

    pub fn deinit(self: *CanvasState) void {
        self.freeGraph();
    }

    /// Replace the graph.  Takes ownership of the pointer (calls merrow_studio_free_editable_graph).
    pub fn setGraph(self: *CanvasState, new_graph: ?*StudioEditableGraph) void {
        self.freeGraph();
        self.graph = new_graph;
        self.selection = .{};
        self.hover = .{};
        self.insertion = .{};
    }

    pub fn clearGraph(self: *CanvasState) void {
        self.freeGraph();
        self.selection = .{};
        self.hover = .{};
        self.insertion = .{};
    }

    // -----------------------------------------------------------------------
    // Selection helpers
    // -----------------------------------------------------------------------

    pub fn selectNode(self: *CanvasState, index: usize) void {
        self.selection = .{ .kind = .node, .index = index };
    }

    pub fn selectSubgraph(self: *CanvasState, index: usize) void {
        self.selection = .{ .kind = .subgraph, .index = index };
    }

    pub fn selectEdge(self: *CanvasState, index: usize) void {
        self.selection = .{ .kind = .edge, .index = index };
    }

    pub fn clearSelection(self: *CanvasState) void {
        self.selection = .{};
    }

    pub fn setHoverNode(self: *CanvasState, index: usize) void {
        self.hover = .{ .kind = .node, .index = index };
    }

    pub fn setHoverSubgraph(self: *CanvasState, index: usize) void {
        self.hover = .{ .kind = .subgraph, .index = index };
    }

    pub fn setHoverEdge(self: *CanvasState, index: usize) void {
        self.hover = .{ .kind = .edge, .index = index };
    }

    pub fn clearHover(self: *CanvasState) void {
        self.hover = .{};
    }

    pub fn hasSelection(self: *const CanvasState) bool {
        return self.selection.kind != .none;
    }

    pub fn selectedNode(self: *const CanvasState) ?*StudioEditableNode {
        const g = self.graph orelse return null;
        if (self.selection.kind != .node) return null;
        if (self.selection.index >= g.node_count) return null;
        return &g.nodes[self.selection.index];
    }

    pub fn selectedSubgraph(self: *const CanvasState) ?*StudioEditableSubgraph {
        const g = self.graph orelse return null;
        if (self.selection.kind != .subgraph) return null;
        if (self.selection.index >= g.subgraph_count) return null;
        return &g.subgraphs[self.selection.index];
    }

    pub fn selectedEdge(self: *const CanvasState) ?*StudioEditableEdge {
        const g = self.graph orelse return null;
        if (self.selection.kind != .edge) return null;
        if (self.selection.index >= g.edge_count) return null;
        return &g.edges[self.selection.index];
    }

    /// Replace the current selection's user-visible label/title. The provided
    /// buffer must be allocated with `c_allocator`; ownership transfers here.
    pub fn replaceSelectedLabelOwned(self: *CanvasState, text: [:0]u8) bool {
        switch (self.selection.kind) {
            .node => {
                const node = self.selectedNode() orelse {
                    std.heap.c_allocator.free(text);
                    return false;
                };
                replaceCString(&node.label, text);
                return true;
            },
            .subgraph => {
                const subgraph = self.selectedSubgraph() orelse {
                    std.heap.c_allocator.free(text);
                    return false;
                };
                replaceCString(&subgraph.title, text);
                return true;
            },
            .edge => {
                const edge = self.selectedEdge() orelse {
                    std.heap.c_allocator.free(text);
                    return false;
                };
                replaceCString(&edge.label, text);
                return true;
            },
            .none => {
                std.heap.c_allocator.free(text);
                return false;
            },
        }
    }

    // -----------------------------------------------------------------------
    // Viewport helpers
    // -----------------------------------------------------------------------

    /// Fit the configured page width into the given screen viewport.
    ///
    /// For document-sized canvases the page is intentionally allowed to be
    /// taller than the viewport; the page top is aligned near the top edge
    /// of the view instead of shrinking everything to fit the full height.
    pub fn fitToViewport(self: *CanvasState, screen_w: f64, screen_h: f64) void {
        const g = self.graph orelse return;
        if (screen_w <= 0 or screen_h <= 0) return;

        const bounds = graphBounds(g) orelse return;
        const page_w = @max(if (g.width > 0) g.width else bounds.width(), 1.0);
        const page_h = @max(if (g.height > 0) g.height else bounds.height(), 1.0);

        const padding_frac: f64 = 0.05;
        const available_w = screen_w * (1.0 - 2.0 * padding_frac);
        const available_h = screen_h * (1.0 - 2.0 * padding_frac);
        self.viewport.zoom = available_w / page_w;

        const page_screen_w = page_w * self.viewport.zoom;
        const page_screen_h = page_h * self.viewport.zoom;

        const margin_x = (screen_w - page_screen_w) / 2.0;
        const margin_y = if (page_screen_h <= available_h)
            (screen_h - page_screen_h) / 2.0
        else
            screen_h * padding_frac;

        self.viewport.pan_x = -margin_x / self.viewport.zoom;
        self.viewport.pan_y = -margin_y / self.viewport.zoom;
    }

    // -----------------------------------------------------------------------
    // Insertion helpers
    // -----------------------------------------------------------------------

    pub fn beginInsertingNode(self: *CanvasState, shape: u32) void {
        self.insertion = .{ .kind = .node, .node_shape = shape };
    }

    pub fn beginInsertingSubgraph(self: *CanvasState) void {
        self.insertion = .{ .kind = .subgraph };
    }

    pub fn cancelInsertion(self: *CanvasState) void {
        self.insertion = .{};
    }

    pub fn insertionModeActive(self: *const CanvasState) bool {
        return self.insertion.kind != .none;
    }

    // -----------------------------------------------------------------------
    // Private
    // -----------------------------------------------------------------------

    fn freeGraph(self: *CanvasState) void {
        if (self.graph) |g| {
            merrow_studio_free_editable_graph(g);
            self.graph = null;
        }
    }
};

fn replaceCString(target: *[*c]const u8, text: [:0]u8) void {
    freeCString(target.*);
    target.* = text.ptr;
}

fn freeCString(ptr: [*c]const u8) void {
    if (ptr == null) return;
    std.heap.c_allocator.free(std.mem.sliceTo(ptr, 0));
}

// FFI declaration — defined in app/preview.zig.
extern fn merrow_studio_free_editable_graph(graph: ?*StudioEditableGraph) callconv(.c) void;
