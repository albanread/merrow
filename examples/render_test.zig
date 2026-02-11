const std = @import("std");
const merrow = @import("merrow");
const Digraph = merrow.Digraph;
const NodeData = merrow.NodeData;
const EdgeData = merrow.EdgeData;
const GraphData = merrow.GraphData;
const dagre = merrow.layout.dagre;
const normalize = merrow.layout.normalize;
const renderGraphToPNG = merrow.render.graph.renderGraphToPNG;
const renderGraphToPNGWithFont = merrow.render.graph.renderGraphToPNGWithFont;
const RenderConfig = merrow.render.graph.RenderConfig;
const Font = merrow.render.graph.Font;

const Graph = Digraph(NodeData, EdgeData, GraphData);

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    std.debug.print("\n=== Graph Rendering Test ===\n\n", .{});

    // Create a diamond graph: A → B, A → C, B → D, C → D
    var graph = Graph.init(allocator);
    defer {
        normalize.freeDummyIds(allocator, &graph);
        graph.deinitDeep();
    }

    std.debug.print("Building graph:\n", .{});
    std.debug.print("  Start → Parse\n", .{});
    std.debug.print("  Parse → Validate\n", .{});
    std.debug.print("  Validate → Process\n", .{});
    std.debug.print("  Validate → Cache\n", .{});
    std.debug.print("  Process → Output\n", .{});
    std.debug.print("  Cache → Output\n", .{});
    std.debug.print("  Output → End\n\n", .{});

    try graph.setNode("Start", .{ .width = 100, .height = 40 });
    try graph.setNode("Parse", .{ .width = 100, .height = 40 });
    try graph.setNode("Validate", .{ .width = 100, .height = 40 });
    try graph.setNode("Process", .{ .width = 100, .height = 40 });
    try graph.setNode("Cache", .{ .width = 100, .height = 40 });
    try graph.setNode("Output", .{ .width = 100, .height = 40 });
    try graph.setNode("End", .{ .width = 100, .height = 40 });

    try graph.setEdge("Start", "Parse", .{}, null);
    try graph.setEdge("Parse", "Validate", .{}, null);
    try graph.setEdge("Validate", "Process", .{}, null);
    try graph.setEdge("Validate", "Cache", .{}, null);
    try graph.setEdge("Process", "Output", .{}, null);
    try graph.setEdge("Cache", "Output", .{}, null);
    try graph.setEdge("Output", "End", .{}, null);

    // Run Dagre layout
    const config = dagre.DagreConfig{
        .ranker = .longest_path,
        .nodesep = 50,
        .ranksep = 50,
    };

    std.debug.print("Running layout...\n", .{});
    try dagre.layout(allocator, &graph, config);

    // Print node positions
    std.debug.print("\nNode positions:\n", .{});
    const nodes = try graph.allNodes(allocator);
    defer {
        for (nodes) |id| allocator.free(id);
        allocator.free(nodes);
    }

    for (nodes) |id| {
        if (graph.getNode(id)) |node| {
            std.debug.print("  {s}: ({d:.1}, {d:.1}) size: {d:.0}x{d:.0}\n", .{
                id,
                node.x,
                node.y,
                node.width,
                node.height,
            });
        }
    }

    // Load font
    std.debug.print("\nLoading font...\n", .{});
    const font_path = "fonts/Lato-Regular.ttf";
    const font_data = std.fs.cwd().readFileAlloc(allocator, font_path, 1024 * 1024) catch |err| {
        std.debug.print("Warning: Could not load font '{s}': {}\n", .{ font_path, err });
        std.debug.print("Rendering without text labels...\n", .{});

        // Render without font
        const output_file = "output.png";
        std.debug.print("\nRendering to {s}...\n", .{output_file});
        const render_config = RenderConfig{};
        try renderGraphToPNG(allocator, &graph, output_file, render_config);
        std.debug.print("✓ Successfully rendered graph to {s}\n", .{output_file});
        std.debug.print("\nOpen the file to see the rendered graph!\n", .{});
        return;
    };
    defer allocator.free(font_data);

    var font = Font.initFromMemory(allocator, font_data) catch |err| {
        std.debug.print("Warning: Could not initialize font: {}\n", .{err});
        std.debug.print("Rendering without text labels...\n", .{});

        // Render without font
        const output_file = "output.png";
        std.debug.print("\nRendering to {s}...\n", .{output_file});
        const render_config = RenderConfig{};
        try renderGraphToPNG(allocator, &graph, output_file, render_config);
        std.debug.print("✓ Successfully rendered graph to {s}\n", .{output_file});
        std.debug.print("\nOpen the file to see the rendered graph!\n", .{});
        return;
    };
    defer font.deinit();

    // Render to PNG with text
    const output_file = "output.png";
    std.debug.print("\nRendering to {s} with text labels...\n", .{output_file});

    const render_config = RenderConfig{};
    try renderGraphToPNGWithFont(allocator, &graph, output_file, render_config, &font);

    std.debug.print("✓ Successfully rendered graph with text to {s}\n", .{output_file});
    std.debug.print("\nOpen the file to see the rendered graph with labels!\n", .{});
}
