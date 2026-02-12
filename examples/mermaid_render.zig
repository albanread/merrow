const std = @import("std");
const merrow = @import("merrow");
const Digraph = merrow.Digraph;
const NodeData = merrow.NodeData;
const NodeShape = merrow.NodeShape;
const EdgeData = merrow.EdgeData;
const GraphData = merrow.GraphData;
const dagre = merrow.layout.dagre;
const normalize = merrow.layout.normalize;
const renderGraphToPNG = merrow.render.graph.renderGraphToPNG;
const renderGraphToPNGWithFont = merrow.render.graph.renderGraphToPNGWithFont;
const RenderConfig = merrow.render.graph.RenderConfig;
const Font = merrow.render.graph.Font;
const Parser = merrow.flowchart.Parser;

const Graph = Digraph(NodeData, EdgeData, GraphData);

/// Padding around text inside a node box.
const node_padding_h: f64 = 24.0; // horizontal (left + right total)
const node_padding_v: f64 = 16.0; // vertical  (top + bottom total)
const min_node_width: f64 = 60.0;
const min_node_height: f64 = 36.0;
const font_size: f32 = 16.0;

const NodeSize = struct { w: f64, h: f64 };

/// Estimate a node's width from its label text when no font is available.
/// Uses a rough heuristic of ~8px per character.
fn estimateNodeSize(label: []const u8, shape: NodeShape) NodeSize {
    const char_width: f64 = 8.0;
    const line_height: f64 = 20.0;
    const text_w = @as(f64, @floatFromInt(label.len)) * char_width;
    var w = @max(min_node_width, text_w + node_padding_h);
    var h = @max(min_node_height, line_height + node_padding_v);

    switch (shape) {
        .diamond => {
            // Diamond usable area is roughly half the bounding box, so
            // scale up by ~√2 so the text fits inside the rhombus.
            w *= 1.45;
            h *= 1.45;
        },
        .hexagon => {
            // Hexagon has pointed sides — widen to fit text
            w *= 1.35;
        },
        .circle => {
            // Make the ellipse large enough that the text fits inside the
            // inscribed rectangle.  For a circle/ellipse the inscribed
            // rect is about 1/√2 of the diameter, so scale up.
            w *= 1.3;
            h *= 1.3;
            // Circles look best when nearly square.
            const side = @max(w, h);
            w = side;
            h = side;
        },
        .stadium => {
            // Stadium has semicircle caps — add padding for the caps
            w += h * 0.5;
        },
        .cylinder => {
            // Cylinder has elliptical caps — add vertical space
            h *= 1.35;
        },
        .trapezoid, .trapezoid_alt => {
            // Trapezoid is narrower on one end — widen to fit text
            w *= 1.25;
        },
        .parallelogram, .parallelogram_alt => {
            // Parallelogram has slanted sides — widen to fit text
            w *= 1.25;
        },
        .subroutine => {
            // Subroutine has inner vertical lines — add horizontal padding
            w += 24.0;
        },
        .round, .box => {},
    }
    return .{ .w = w, .h = h };
}

/// Measure a node's dimensions using a real font.
fn measureNodeSize(font: *Font, label: []const u8, shape: NodeShape) NodeSize {
    const text_w: f64 = @floatCast(font.measureText(label, font_size));
    const line_height: f64 = @as(f64, @floatCast(font_size)) * 1.4;
    var w = @max(min_node_width, text_w + node_padding_h);
    var h = @max(min_node_height, line_height + node_padding_v);

    switch (shape) {
        .diamond => {
            w *= 1.45;
            h *= 1.45;
        },
        .hexagon => {
            w *= 1.35;
        },
        .circle => {
            w *= 1.3;
            h *= 1.3;
            const side = @max(w, h);
            w = side;
            h = side;
        },
        .stadium => {
            w += h * 0.5;
        },
        .cylinder => {
            h *= 1.35;
        },
        .trapezoid, .trapezoid_alt => {
            w *= 1.25;
        },
        .parallelogram, .parallelogram_alt => {
            w *= 1.25;
        },
        .subroutine => {
            w += 24.0;
        },
        .round, .box => {},
    }
    return .{ .w = w, .h = h };
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // ---------------------------------------------------------------
    // Parse command-line arguments
    // ---------------------------------------------------------------
    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    if (args.len < 2) {
        std.debug.print("Usage: {s} <input.mmd> [output.png]\n", .{args[0]});
        std.debug.print("\nExample:\n", .{});
        std.debug.print("  {s} diagram.mmd diagram.png\n", .{args[0]});
        std.debug.print("  {s} diagram.mmd (outputs to diagram.png)\n", .{args[0]});
        return error.InvalidArguments;
    }

    const input_file = args[1];
    const output_file = if (args.len >= 3) args[2] else blk: {
        const base = std.fs.path.basename(input_file);
        const dot_index = std.mem.lastIndexOf(u8, base, ".");
        const name_without_ext = if (dot_index) |idx| base[0..idx] else base;
        break :blk try std.fmt.allocPrint(allocator, "{s}.png", .{name_without_ext});
    };
    defer if (args.len < 3) allocator.free(output_file);

    std.debug.print("\n=== Mermaid Diagram Renderer ===\n\n", .{});
    std.debug.print("Input:  {s}\n", .{input_file});
    std.debug.print("Output: {s}\n\n", .{output_file});

    // ---------------------------------------------------------------
    // Read the Mermaid source file
    // ---------------------------------------------------------------
    std.debug.print("Reading Mermaid file...\n", .{});
    const source = try std.fs.cwd().readFileAlloc(allocator, input_file, 10 * 1024 * 1024);
    defer allocator.free(source);

    // ---------------------------------------------------------------
    // Parse the diagram into a graph
    // ---------------------------------------------------------------
    std.debug.print("Parsing diagram...\n", .{});
    var parser = try Parser.init(allocator, source);
    defer parser.deinit();

    var graph = try parser.parse();
    defer {
        normalize.freeDummyIds(allocator, &graph);
        graph.deinitDeep();
    }

    // Snapshot node IDs (for iteration — the list is stable before layout
    // mutates the graph with dummy nodes).
    const node_ids = try graph.allNodes(allocator);
    defer {
        for (node_ids) |id| allocator.free(id);
        allocator.free(node_ids);
    }

    std.debug.print("  Found {d} nodes\n", .{node_ids.len});
    std.debug.print("  Found {d} edges\n\n", .{graph.edgeCount()});

    // ---------------------------------------------------------------
    // Load font (before sizing so we can measure text)
    // ---------------------------------------------------------------
    std.debug.print("Loading font...\n", .{});
    const font_paths = [_][]const u8{
        "fonts/Lato-Regular.ttf",
        "../fonts/Lato-Regular.ttf",
        "../../fonts/Lato-Regular.ttf",
    };

    var font_data: ?[]u8 = null;

    // First, try paths relative to the executable location.
    // This allows the binary to find its fonts regardless of the working directory.
    var exe_font_buf: [std.fs.max_path_bytes]u8 = undefined;
    const exe_relative_font: ?[]const u8 = blk: {
        const exe_path = std.fs.selfExeDirPath(&exe_font_buf) catch break :blk null;
        // exe is in zig-out/bin/, fonts are in fonts/ (two levels up from exe)
        const prefixes = [_][]const u8{ "/fonts/Lato-Regular.ttf", "/../fonts/Lato-Regular.ttf", "/../../fonts/Lato-Regular.ttf" };
        for (prefixes) |suffix| {
            if (exe_path.len + suffix.len < exe_font_buf.len) {
                @memcpy(exe_font_buf[exe_path.len .. exe_path.len + suffix.len], suffix);
                const full = exe_font_buf[0 .. exe_path.len + suffix.len];
                font_data = std.fs.cwd().readFileAlloc(allocator, full, 1024 * 1024) catch continue;
                break :blk full;
            }
        }
        break :blk null;
    };

    if (exe_relative_font) |p| {
        std.debug.print("  Loaded font: {s}\n", .{p});
    } else {
        // Fall back to CWD-relative paths
        for (font_paths) |font_path| {
            font_data = std.fs.cwd().readFileAlloc(allocator, font_path, 1024 * 1024) catch |err| {
                if (err != error.FileNotFound) {
                    std.debug.print("  Warning: Error reading '{s}': {}\n", .{ font_path, err });
                }
                continue;
            };
            std.debug.print("  Loaded font: {s}\n", .{font_path});
            break;
        }
    }
    defer if (font_data) |data| allocator.free(data);

    // Try to initialise the font object (may fail even if file was found).
    var maybe_font: ?Font = if (font_data) |data|
        Font.initFromMemory(allocator, data) catch |err| blk: {
            std.debug.print("  Warning: Could not initialise font: {}\n", .{err});
            break :blk null;
        }
    else
        null;
    defer if (maybe_font) |*f| f.deinit();

    // ---------------------------------------------------------------
    // Size nodes based on label text
    // ---------------------------------------------------------------
    std.debug.print("Sizing nodes...\n", .{});
    for (node_ids) |id| {
        if (graph.getNodePtr(id)) |node| {
            // Only size nodes that don't already have a width set.
            if (node.width > 0) continue;

            // Skip subgraph nodes — their dimensions are computed after
            // layout from the bounding box of their children.
            if (node.is_subgraph) continue;

            const display_text = node.label orelse id;

            const size = if (maybe_font) |*font|
                measureNodeSize(font, display_text, node.shape)
            else
                estimateNodeSize(display_text, node.shape);

            node.width = size.w;
            node.height = size.h;
        }
    }

    // ---------------------------------------------------------------
    // Run Dagre layout
    // ---------------------------------------------------------------
    std.debug.print("Running layout algorithm...\n", .{});

    // Read the parsed direction from the graph label (set by the parser
    // from `graph LR` / `graph TD` / etc.) and convert the string to
    // the DagreConfig enum.
    const graph_label = graph.getGraphLabel();
    const rankdir: dagre.RankDir = blk: {
        if (std.mem.eql(u8, graph_label.rankdir, "LR")) break :blk .LR;
        if (std.mem.eql(u8, graph_label.rankdir, "RL")) break :blk .RL;
        if (std.mem.eql(u8, graph_label.rankdir, "BT")) break :blk .BT;
        break :blk .TB; // TD and default
    };
    std.debug.print("Graph direction: {s} -> rankdir={s}\n", .{ graph_label.rankdir, @tagName(rankdir) });

    const config = dagre.DagreConfig{
        .rankdir = rankdir,
        .ranker = .longest_path,
        .nodesep = 50,
        .ranksep = 50,
    };

    try dagre.layout(allocator, &graph, config);

    // Print node positions for debugging
    std.debug.print("\nNode positions after layout:\n", .{});
    for (node_ids) |id| {
        if (graph.getNode(id)) |node| {
            const label = if (node.label) |lbl| lbl else id;
            std.debug.print("  {s}: ({d:.1}, {d:.1}) [{d:.0}x{d:.0}]\n", .{
                label,
                node.x,
                node.y,
                node.width,
                node.height,
            });
        }
    }

    // ---------------------------------------------------------------
    // Render to PNG
    // ---------------------------------------------------------------
    std.debug.print("\nRendering to PNG (HD quality)...\n", .{});
    const render_config = RenderConfig{
        .padding = 40.0,
        .scale_factor = 2.0,
        .node_fill_color = .{ 240, 240, 250, 255 },
        .node_stroke_color = .{ 100, 100, 150, 255 },
        .node_stroke_width = 2,
        .edge_color = .{ 80, 80, 80, 255 },
        .edge_width = 2,
        .text_color = .{ 40, 40, 40, 255 },
        .text_size = font_size,
    };

    if (maybe_font) |*font| {
        try renderGraphToPNGWithFont(allocator, &graph, output_file, render_config, font);
        std.debug.print("\n✓ Successfully rendered to {s}\n", .{output_file});
        std.debug.print("   - HD quality: {d:.0}x scale factor\n", .{render_config.scale_factor});
        std.debug.print("   - Antialiased lines and text\n", .{});
        std.debug.print("   - Text-measured node sizes\n", .{});
        std.debug.print("   - With labels\n", .{});
    } else {
        std.debug.print("  No usable font — rendering without text labels...\n", .{});
        try renderGraphToPNG(allocator, &graph, output_file, render_config);
        std.debug.print("\n✓ Successfully rendered to {s} (no labels, HD quality)\n", .{output_file});
    }

    std.debug.print("\nOpen '{s}' to view your HD diagram!\n", .{output_file});
}
