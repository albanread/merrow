//! Merrow - Mermaid diagram renderer in Zig
//! Extracted and ported from the MIT-licensed Merrow (Rust) project

const std = @import("std");

// Core modules
pub const Digraph = @import("graph/digraph.zig").Digraph;
pub const model = @import("model.zig");
pub const GraphData = model.GraphData;

// Parser modules
pub const lexer = @import("parser/lexer.zig");
pub const flowchart = @import("parser/flowchart.zig");
pub const directives = @import("parser/directives.zig");

// Pie chart modules
pub const pie = struct {
    pub const model = @import("pie/model.zig");
    pub const parser = @import("pie/parser.zig");
    pub const svg_render = @import("pie/svg_render.zig");
    pub const png_render = @import("pie/png_render.zig");
};

// Class diagram modules
pub const class = struct {
    pub const model = @import("class/model.zig");
    pub const parser = @import("class/parser.zig");
    pub const svg_render = @import("class/svg_render.zig");
    pub const png_render = @import("class/png_render.zig");
};

// State diagram modules
pub const state = struct {
    pub const model = @import("state/model.zig");
    pub const parser = @import("state/parser.zig");
    pub const svg_render = @import("state/svg_render.zig");
    pub const png_render = @import("state/png_render.zig");
};

// ER diagram modules
pub const er = struct {
    pub const model = @import("er/model.zig");
    pub const parser = @import("er/parser.zig");
    pub const svg_render = @import("er/svg_render.zig");
    pub const png_render = @import("er/png_render.zig");
};

// Gantt chart modules
pub const gantt = struct {
    pub const model = @import("gantt/model.zig");
    pub const parser = @import("gantt/parser.zig");
    pub const svg_render = @import("gantt/svg_render.zig");
    pub const png_render = @import("gantt/png_render.zig");
};

// Journey diagram modules
pub const journey = struct {
    pub const model = @import("journey/model.zig");
    pub const parser = @import("journey/parser.zig");
    pub const svg_render = @import("journey/svg_render.zig");
    pub const png_render = @import("journey/png_render.zig");
};

// Sequence diagram modules
pub const sequence = struct {
    pub const model = @import("sequence/model.zig");
    pub const parser = @import("sequence/parser.zig");
    pub const seq_layout = @import("sequence/layout.zig");
    pub const svg_render = @import("sequence/svg_render.zig");
    pub const png_render = @import("sequence/png_render.zig");
};

// Layout modules
pub const layout = struct {
    pub const dagre = @import("layout/dagre.zig");
    pub const acyclic = @import("layout/dagre/acyclic.zig");
    pub const normalize = @import("layout/dagre/normalize.zig");
    pub const order = @import("layout/dagre/order.zig");
    pub const position = @import("layout/dagre/position.zig");
};

// Render modules
pub const render = struct {
    pub const canvas = @import("render/canvas.zig");
    pub const graph = @import("render/graph.zig");
    pub const text = @import("render/text.zig");
    pub const colors = @import("render/colors.zig");
    pub const svg = @import("render/svg.zig");
    pub const svg_render = @import("render/svg_render.zig");
};

// Re-export commonly used types
pub const NodeData = model.NodeData;
pub const EdgeData = model.EdgeData;
pub const Point = model.Point;
pub const NodeShape = model.NodeShape;
pub const LineStyle = model.LineStyle;
pub const StyleClass = flowchart.StyleClass;
pub const parseHexColor = flowchart.parseHexColor;

// Re-export pie types
pub const PieData = pie.model.PieData;
pub const isPieDiagram = pie.parser.isPieDiagram;

// Re-export class types
pub const ClassDiagram = class.model.ClassDiagram;
pub const isClassDiagram = class.parser.isClassDiagram;

// Re-export state types
pub const StateDiagram = state.model.StateDiagram;
pub const isStateDiagram = state.parser.isStateDiagram;

// Re-export er types
pub const ErDiagram = er.model.ErDiagram;
pub const isErDiagram = er.parser.isErDiagram;

// Re-export gantt types
pub const GanttDiagram = gantt.model.GanttDiagram;
pub const isGanttDiagram = gantt.parser.isGanttDiagram;

// Re-export journey types
pub const JourneyDiagram = journey.model.JourneyDiagram;
pub const isJourneyDiagram = journey.parser.isJourneyDiagram;

test "import all modules" {
    std.testing.refAllDecls(@This());
    _ = @import("pie/model.zig");
    _ = @import("pie/parser.zig");
    _ = @import("pie/svg_render.zig");
    _ = @import("pie/png_render.zig");
    _ = @import("class/model.zig");
    _ = @import("class/parser.zig");
    _ = @import("class/svg_render.zig");
    _ = @import("class/png_render.zig");
    _ = @import("state/model.zig");
    _ = @import("state/parser.zig");
    _ = @import("state/svg_render.zig");
    _ = @import("state/png_render.zig");
    _ = @import("journey/model.zig");
    _ = @import("journey/parser.zig");
    _ = @import("journey/svg_render.zig");
    _ = @import("journey/png_render.zig");
    _ = @import("gantt/model.zig");
    _ = @import("gantt/parser.zig");
    _ = @import("gantt/svg_render.zig");
    _ = @import("gantt/png_render.zig");
    _ = @import("er/model.zig");
    _ = @import("er/parser.zig");
    _ = @import("er/svg_render.zig");
    _ = @import("er/png_render.zig");
    _ = @import("layout/dagre/order/init_order.zig");
    _ = @import("layout/dagre/order/cross_count.zig");
    _ = @import("layout/dagre/order/barycenter.zig");
    _ = @import("layout/dagre/order/sort.zig");
    _ = @import("layout/dagre/position.zig");
    _ = @import("render/canvas.zig");
    _ = @import("render/graph.zig");
    _ = @import("render/text.zig");
    _ = @import("render/svg.zig");
    _ = @import("render/svg_render.zig");
    _ = @import("sequence/model.zig");
    _ = @import("sequence/parser.zig");
    _ = @import("sequence/layout.zig");
    _ = @import("sequence/svg_render.zig");
    _ = @import("sequence/png_render.zig");
}

test "basic graph operations" {
    var graph = Digraph(NodeData, EdgeData, GraphData).init(std.testing.allocator);
    defer graph.deinit();

    try graph.setNode("A", .{ .width = 100, .height = 50 });
    try graph.setNode("B", .{ .width = 100, .height = 50 });
    try graph.setEdge("A", "B", .{}, null);

    try std.testing.expect(graph.hasNode("A"));
    try std.testing.expect(graph.hasNode("B"));
    try std.testing.expect(graph.hasEdge("A", "B", null));
}

test "acyclic module integration" {
    var graph = Digraph(NodeData, EdgeData, GraphData).init(std.testing.allocator);
    defer graph.deinit();

    // Create a simple cycle
    try graph.setNode("a", .{ .width = 50, .height = 50 });
    try graph.setNode("b", .{ .width = 50, .height = 50 });
    try graph.setNode("c", .{ .width = 50, .height = 50 });

    try graph.setEdge("a", "b", .{}, null);
    try graph.setEdge("b", "c", .{}, null);
    try graph.setEdge("c", "a", .{}, null);

    // Break the cycle
    try layout.acyclic.run(std.testing.allocator, &graph, .dfs);

    // Should still have 3 edges but at least one reversed
    try std.testing.expectEqual(@as(usize, 3), graph.edgeCount());

    var has_reversed = false;
    var iter = graph.edgeIterator();
    while (iter.next()) |entry| {
        if (entry.data.reversed) {
            has_reversed = true;
            break;
        }
    }
    try std.testing.expect(has_reversed);
}

test "dagre layout placeholder" {
    var graph = Digraph(NodeData, EdgeData, GraphData).init(std.testing.allocator);
    defer graph.deinit();

    try graph.setNode("A", .{ .width = 100, .height = 50 });
    try graph.setNode("B", .{ .width = 100, .height = 50 });
    try graph.setEdge("A", "B", .{}, null);

    const config = layout.dagre.DagreConfig{};
    try layout.dagre.layout(std.testing.allocator, &graph, config);
}
