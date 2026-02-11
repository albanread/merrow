const std = @import("std");

/// Graph data for Dagre layout
pub const GraphData = struct {
    rankdir: []const u8 = "TB",
    nodesep: f64 = 50.0,
    edgesep: f64 = 10.0,
    ranksep: f64 = 50.0,
    marginx: f64 = 0.0,
    marginy: f64 = 0.0,
    acyclicer: []const u8 = "",
    ranker: []const u8 = "network-simplex",

    // Computed
    width: f64 = 0.0,
    height: f64 = 0.0,
    dummy_chains: std.ArrayListUnmanaged([]const u8) = .{},
};

pub const NodeShape = enum {
    box,
    round,
    diamond,
    circle,
    hexagon,
    cylinder,
    stadium,
    trapezoid,
    trapezoid_alt,
    parallelogram,
    parallelogram_alt,
    subroutine,
};

/// Line style for edges.
pub const LineStyle = enum {
    solid,
    dashed,
    dotted,
    thick,
};

/// Node data for Dagre layout
pub const NodeData = struct {
    // Basic
    label: ?[]const u8 = null,
    label_owned: bool = false,
    width: f64 = 0.0,
    height: f64 = 0.0,
    shape: NodeShape = .box,

    // Visual styling
    fill_color: ?[4]u8 = null, // Custom fill color (RGBA)
    stroke_color: ?[4]u8 = null, // Custom stroke color (RGBA)
    stroke_width: ?i32 = null, // Custom stroke width
    text_color: ?[4]u8 = null, // Custom text/label color (RGBA)

    // Hyperlink (from `click` directive)
    link_url: ?[]const u8 = null, // URL for click navigation
    link_url_owned: bool = false,
    link_tooltip: ?[]const u8 = null, // Tooltip text on hover
    link_tooltip_owned: bool = false,
    link_target: ?[]const u8 = null, // Target: "_blank", "_self", etc.

    // Layout Output
    x: f64 = 0.0,
    y: f64 = 0.0,

    // Algorithmic (Dagre internals)
    rank: ?i32 = null,
    order: ?usize = null,
    low: ?i32 = null,
    lim: ?i32 = null,
    parent: ?[]const u8 = null,

    // Compound graph support
    min_rank: ?i32 = null,
    max_rank: ?i32 = null,
    border_left: std.ArrayListUnmanaged(?[]const u8) = .{},
    border_right: std.ArrayListUnmanaged(?[]const u8) = .{},

    // For subgraph (compound) nodes
    is_subgraph: bool = false,
    subgraph_title: ?[]const u8 = null, // Display title (e.g., "Database Layer")
    subgraph_title_owned: bool = false,
    subgraph_padding: f64 = 40.0, // Padding around children inside the box

    // For dummy nodes
    dummy: bool = false,
    dummy_edge: ?struct { v: []const u8, w: []const u8, name: ?[]const u8 } = null,
    label_pos: ?[]const u8 = null, // "l", "r", "c"

    pub fn deinit(self: *NodeData, allocator: std.mem.Allocator) void {
        if (self.label_owned) {
            if (self.label) |l| allocator.free(l);
        }
        if (self.subgraph_title_owned) {
            if (self.subgraph_title) |t| allocator.free(t);
        }
        if (self.link_url_owned) {
            if (self.link_url) |u| allocator.free(u);
        }
        if (self.link_tooltip_owned) {
            if (self.link_tooltip) |t| allocator.free(t);
        }
        self.border_left.deinit(allocator);
        self.border_right.deinit(allocator);
    }
};

/// Edge data for Dagre layout
pub const EdgeData = struct {
    // User Input
    label: ?[]const u8 = null,
    label_owned: bool = false,
    style: ?[]const u8 = null,
    arrowhead: ?[]const u8 = null, // "normal", "vee", "none"
    arrowtail: ?[]const u8 = null, // "normal", "vee", "none" — arrow at source end
    line_style: LineStyle = .solid, // solid, dashed, dotted, thick

    // Visual styling
    color: ?[4]u8 = null, // Custom edge color (RGBA)
    thickness: ?i32 = null, // Custom line thickness

    // Layout Input/Output
    minlen: i32 = 1,
    weight: i32 = 1,
    width: f64 = 0.0,
    height: f64 = 0.0,
    x: f64 = 0.0,
    y: f64 = 0.0,
    points: std.ArrayListUnmanaged(Point) = .{},

    // Internals
    labelpos: ?[]const u8 = "c", // l, r, c
    reversed: bool = false, // Edge was reversed during acyclic phase
    forward_name: ?[]const u8 = null, // Original edge name before reversal
    cutvalue: ?i32 = null, // For network simplex
    label_rank: ?i32 = null, // Rank where label should be placed
    nesting_edge: bool = false, // Is this a nesting edge (compound graph support)

    pub fn deinit(self: *EdgeData, allocator: std.mem.Allocator) void {
        if (self.label_owned) {
            if (self.label) |l| allocator.free(l);
        }
        self.points.deinit(allocator);
    }
};

pub const Point = struct {
    x: f64,
    y: f64,
};
