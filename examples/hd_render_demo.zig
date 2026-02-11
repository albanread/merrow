const std = @import("std");
const merrow = @import("merrow");
const Digraph = merrow.Digraph;
const NodeData = merrow.NodeData;
const EdgeData = merrow.EdgeData;
const GraphData = merrow.GraphData;
const dagre = merrow.layout.dagre;
const normalize = merrow.layout.normalize;
const renderGraphToPNGWithFont = merrow.render.graph.renderGraphToPNGWithFont;
const RenderConfig = merrow.render.graph.RenderConfig;
const Font = merrow.render.graph.Font;
const colors = merrow.render.colors;

const Graph = Digraph(NodeData, EdgeData, GraphData);

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    std.debug.print("\n=== HD Diagram Rendering Demo ===\n\n", .{});

    // Create a colorful workflow diagram
    var graph = Graph.init(allocator);
    defer {
        normalize.freeDummyIds(allocator, &graph);
        graph.deinitDeep();
    }

    std.debug.print("Building colorful workflow diagram...\n\n", .{});

    // Start node (green)
    try graph.setNode("Start", .{
        .width = 140,
        .height = 50,
        .label = "Start Process",
        .fill_color = colors.Palette.LIGHT_GREEN.toArray(),
        .stroke_color = colors.Palette.DARK_GREEN.toArray(),
        .stroke_width = 3,
    });

    // Input validation (blue)
    try graph.setNode("Validate", .{
        .width = 140,
        .height = 50,
        .label = "Validate Input",
        .fill_color = colors.Palette.LIGHT_BLUE.toArray(),
        .stroke_color = colors.Palette.DARK_BLUE.toArray(),
        .stroke_width = 3,
    });

    // Processing nodes (cyan)
    try graph.setNode("ProcessA", .{
        .width = 140,
        .height = 50,
        .label = "Process A",
        .fill_color = colors.Palette.LIGHT_CYAN.toArray(),
        .stroke_color = colors.Palette.DARK_CYAN.toArray(),
        .stroke_width = 2,
    });

    try graph.setNode("ProcessB", .{
        .width = 140,
        .height = 50,
        .label = "Process B",
        .fill_color = colors.Palette.LIGHT_CYAN.toArray(),
        .stroke_color = colors.Palette.DARK_CYAN.toArray(),
        .stroke_width = 2,
    });

    // Warning node (orange)
    try graph.setNode("Warning", .{
        .width = 140,
        .height = 50,
        .label = "Needs Review",
        .fill_color = colors.Palette.LIGHT_ORANGE.toArray(),
        .stroke_color = colors.Palette.DARK_ORANGE.toArray(),
        .stroke_width = 3,
    });

    // Error node (red)
    try graph.setNode("Error", .{
        .width = 140,
        .height = 50,
        .label = "Handle Error",
        .fill_color = colors.Palette.LIGHT_RED.toArray(),
        .stroke_color = colors.Palette.DARK_RED.toArray(),
        .stroke_width = 3,
    });

    // Success node (dark green)
    try graph.setNode("Success", .{
        .width = 140,
        .height = 50,
        .label = "Complete",
        .fill_color = colors.Palette.GREEN.toArray(),
        .stroke_color = colors.Palette.DARK_GREEN.toArray(),
        .stroke_width = 3,
    });

    // End node (yellow)
    try graph.setNode("End", .{
        .width = 140,
        .height = 50,
        .label = "End",
        .fill_color = colors.Palette.LIGHT_YELLOW.toArray(),
        .stroke_color = colors.Palette.DARK_YELLOW.toArray(),
        .stroke_width = 2,
    });

    // Add edges with varying thickness
    try graph.setEdge("Start", "Validate", .{
        .thickness = 2,
        .color = colors.Palette.DARK_GREEN.toArray(),
    }, null);

    try graph.setEdge("Validate", "ProcessA", .{
        .thickness = 2,
        .color = colors.Palette.DARK_BLUE.toArray(),
    }, null);

    try graph.setEdge("Validate", "ProcessB", .{
        .thickness = 2,
        .color = colors.Palette.DARK_BLUE.toArray(),
    }, null);

    try graph.setEdge("ProcessA", "Warning", .{
        .thickness = 2,
        .color = colors.Palette.ORANGE.toArray(),
    }, null);

    try graph.setEdge("ProcessB", "Success", .{
        .thickness = 3,
        .color = colors.Palette.GREEN.toArray(),
    }, null);

    try graph.setEdge("Validate", "Error", .{
        .thickness = 2,
        .color = colors.Palette.RED.toArray(),
    }, null);

    try graph.setEdge("Warning", "Success", .{
        .thickness = 2,
        .color = colors.Palette.DARK_GREEN.toArray(),
    }, null);

    try graph.setEdge("Error", "End", .{
        .thickness = 2,
        .color = colors.Palette.DARK_RED.toArray(),
    }, null);

    try graph.setEdge("Success", "End", .{
        .thickness = 3,
        .color = colors.Palette.DARK_GREEN.toArray(),
    }, null);

    // Run Dagre layout
    const config = dagre.DagreConfig{
        .ranker = .longest_path,
        .nodesep = 60,
        .ranksep = 80,
    };

    std.debug.print("Running layout algorithm...\n", .{});
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
            const label = node.label orelse id;
            std.debug.print("  {s}: ({d:.1}, {d:.1})\n", .{
                label,
                node.x,
                node.y,
            });
        }
    }

    // Load font
    std.debug.print("\nLoading font...\n", .{});
    const font_paths = [_][]const u8{
        "fonts/Lato-Regular.ttf",
        "../fonts/Lato-Regular.ttf",
        "../../fonts/Lato-Regular.ttf",
    };

    var font_data: ?[]u8 = null;
    for (font_paths) |font_path| {
        font_data = std.fs.cwd().readFileAlloc(allocator, font_path, 1024 * 1024) catch continue;
        std.debug.print("  Loaded: {s}\n", .{font_path});
        break;
    }
    defer if (font_data) |data| allocator.free(data);

    if (font_data == null) {
        std.debug.print("  Warning: No font found, will render without labels\n", .{});
    }

    // Render with HD quality (3x scale for ultra-sharp output)
    const output_file = "hd_demo.png";
    std.debug.print("\nRendering to {s}...\n", .{output_file});
    std.debug.print("  Scale factor: 3.0x (HD quality)\n", .{});
    std.debug.print("  Antialiasing: Enabled\n", .{});

    const render_config = RenderConfig{
        .padding = 60.0,
        .scale_factor = 3.0, // 3x for ultra-HD rendering
        .node_fill_color = .{ 240, 240, 250, 255 },
        .node_stroke_color = .{ 100, 100, 150, 255 },
        .node_stroke_width = 2,
        .edge_color = .{ 80, 80, 80, 255 },
        .edge_width = 2,
        .text_color = .{ 20, 20, 20, 255 },
        .text_size = 16.0,
    };

    if (font_data) |data| {
        var font = Font.initFromMemory(allocator, data) catch |err| {
            std.debug.print("  Error initializing font: {}\n", .{err});
            return err;
        };
        defer font.deinit();

        try renderGraphToPNGWithFont(allocator, &graph, output_file, render_config, &font);
        std.debug.print("\n✓ HD rendering complete!\n", .{});
    } else {
        std.debug.print("\n✗ Cannot render without font\n", .{});
        return error.NoFont;
    }

    std.debug.print("\nOutput: {s}\n", .{output_file});
    std.debug.print("\nFeatures demonstrated:\n", .{});
    std.debug.print("  ✓ 3x scale factor for HD rendering\n", .{});
    std.debug.print("  ✓ Antialiased lines (Xiaolin Wu's algorithm)\n", .{});
    std.debug.print("  ✓ Custom node colors (red, orange, green, yellow, blue, cyan)\n", .{});
    std.debug.print("  ✓ Custom stroke widths (2-3px)\n", .{});
    std.debug.print("  ✓ Custom edge colors and thickness\n", .{});
    std.debug.print("  ✓ Alpha blending for smooth rendering\n", .{});
    std.debug.print("\nOpen the file to see the HD diagram!\n", .{});
}
