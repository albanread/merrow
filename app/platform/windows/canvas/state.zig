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
        return .{ .min_x = min_x, .min_y = min_y, .max_x = max_x, .max_y = max_y };
    }

    if (graph.width > 0 and graph.height > 0) {
        return .{ .min_x = 0, .min_y = 0, .max_x = graph.width, .max_y = graph.height };
    }

    return null;
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

    /// Fit the full canvas into the given screen viewport, with 5 % padding.
    pub fn fitToViewport(self: *CanvasState, screen_w: f64, screen_h: f64) void {
        const g = self.graph orelse return;
        if (screen_w <= 0 or screen_h <= 0) return;

        const bounds = graphBounds(g) orelse return;
        const content_w = @max(bounds.width(), 1.0);
        const content_h = @max(bounds.height(), 1.0);

        const padding_frac: f64 = 0.05;
        const available_w = screen_w * (1.0 - 2.0 * padding_frac);
        const available_h = screen_h * (1.0 - 2.0 * padding_frac);
        const zoom_w = available_w / content_w;
        const zoom_h = available_h / content_h;
        self.viewport.zoom = @min(zoom_w, zoom_h);

        const margin_x = (screen_w - content_w * self.viewport.zoom) / 2.0;
        const margin_y = (screen_h - content_h * self.viewport.zoom) / 2.0;
        self.viewport.pan_x = bounds.min_x - margin_x / self.viewport.zoom;
        self.viewport.pan_y = bounds.min_y - margin_y / self.viewport.zoom;
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
