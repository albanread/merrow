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
const renderGraphToSVG = merrow.render.svg_render.renderGraphToSVG;
const renderGraphToSVGWithFont = merrow.render.svg_render.renderGraphToSVGWithFont;
const RenderConfig = merrow.render.graph.RenderConfig;
const Font = merrow.render.graph.Font;
const Parser = merrow.flowchart.Parser;

// Sequence diagram imports
const SeqParser = merrow.sequence.parser.Parser;
const SeqLayout = merrow.sequence.seq_layout;
const SeqSvgRender = merrow.sequence.svg_render;
const SeqPngRender = merrow.sequence.png_render;

// Pie chart imports
const PieParser = merrow.pie.parser;
const PieData = merrow.pie.model.PieData;
const PieSvgRender = merrow.pie.svg_render;
const PiePngRender = merrow.pie.png_render;

// Class diagram imports
const ClassParser = merrow.class.parser;
const ClassDiagram = merrow.class.model.ClassDiagram;
const ClassSvgRender = merrow.class.svg_render;
const ClassPngRender = merrow.class.png_render;

// State diagram imports
const StateParser = merrow.state.parser;
const StateDiagram = merrow.state.model.StateDiagram;
const StateSvgRender = merrow.state.svg_render;
const StatePngRender = merrow.state.png_render;

// Journey diagram imports
const JourneyParser = merrow.journey.parser;
const JourneyDiagram = merrow.journey.model.JourneyDiagram;
const JourneySvgRender = merrow.journey.svg_render;
const JourneyPngRender = merrow.journey.png_render;

// ER diagram imports
const ErParser = merrow.er.parser;
const ErDiagram = merrow.er.model.ErDiagram;
const ErSvgRender = merrow.er.svg_render;
const ErPngRender = merrow.er.png_render;

// Gantt diagram imports
const GanttParser = merrow.gantt.parser;
const GanttDiagram = merrow.gantt.model.GanttDiagram;
const GanttSvgRender = merrow.gantt.svg_render;
const GanttPngRender = merrow.gantt.png_render;

const Graph = Digraph(NodeData, EdgeData, GraphData);

/// Padding around text inside a node box.
const node_padding_h: f64 = 24.0; // horizontal (left + right total)
const node_padding_v: f64 = 16.0; // vertical  (top + bottom total)
const min_node_width: f64 = 60.0;
const min_node_height: f64 = 36.0;
const font_size: f32 = 16.0;
/// Maximum label width (logical pixels) before text wraps to the next line.
const max_label_width: f32 = 180.0;

const NodeSize = struct { w: f64, h: f64 };

/// Estimate a node's width from its label text when no font is available.
/// Uses a rough heuristic of ~8px per character.
fn estimateNodeSize(label: []const u8, shape: NodeShape) NodeSize {
    const char_width: f64 = 8.0;
    const line_height: f64 = 20.0;
    const text_w = @as(f64, @floatFromInt(label.len)) * char_width;
    var w = @max(min_node_width, text_w + node_padding_h);
    var h = @max(min_node_height, line_height + node_padding_v);

    applyShapeScaling(&w, &h, shape);
    return .{ .w = w, .h = h };
}

/// Measure a node's dimensions using a real font, with text wrapping for
/// labels that exceed `max_label_width`.
fn measureNodeSize(font: *Font, label: []const u8, shape: NodeShape) NodeSize {
    // Check if text needs wrapping
    const single_line_w = font.measureText(label, font_size);
    var text_w: f64 = undefined;
    var text_h: f64 = undefined;

    if (single_line_w > max_label_width) {
        // Wrap text and use the wrapped dimensions
        const wrapped = font.measureWrappedText(label, font_size, max_label_width) catch {
            // Fallback to single-line measurement on error
            text_w = @floatCast(single_line_w);
            text_h = @as(f64, @floatCast(font_size)) * 1.4;
            var w = @max(min_node_width, text_w + node_padding_h);
            var h = @max(min_node_height, text_h + node_padding_v);
            applyShapeScaling(&w, &h, shape);
            return .{ .w = w, .h = h };
        };
        text_w = @floatCast(wrapped.width);
        text_h = @floatCast(wrapped.height);
    } else {
        text_w = @floatCast(single_line_w);
        text_h = @as(f64, @floatCast(font_size)) * 1.4;
    }

    var w = @max(min_node_width, text_w + node_padding_h);
    var h = @max(min_node_height, text_h + node_padding_v);

    applyShapeScaling(&w, &h, shape);
    return .{ .w = w, .h = h };
}

/// Apply shape-specific scaling to width/height so text fits inside
/// non-rectangular shapes (diamond, hexagon, circle, etc.).
fn applyShapeScaling(w: *f64, h: *f64, shape: NodeShape) void {
    switch (shape) {
        .diamond => {
            w.* *= 1.45;
            h.* *= 1.45;
        },
        .hexagon => {
            w.* *= 1.35;
        },
        .circle => {
            w.* *= 1.3;
            h.* *= 1.3;
            const side = @max(w.*, h.*);
            w.* = side;
            h.* = side;
        },
        .stadium => {
            w.* += h.* * 0.5;
        },
        .cylinder => {
            h.* *= 1.35;
        },
        .trapezoid, .trapezoid_alt => {
            w.* *= 1.25;
        },
        .parallelogram, .parallelogram_alt => {
            w.* *= 1.25;
        },
        .subroutine => {
            w.* += 24.0;
        },
        .round, .box => {},
    }
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
        std.debug.print("Usage: {s} <input.mmd> [output.png|output.svg] [--svg]\n", .{args[0]});
        std.debug.print("\nRenders a Mermaid diagram to a PNG or SVG image.\n", .{});
        std.debug.print("Supports: flowchart/graph, sequenceDiagram, pie, classDiagram, stateDiagram, journey, erDiagram, gantt\n\n", .{});
        std.debug.print("Output format is auto-detected from the file extension.\n", .{});
        std.debug.print("Use --svg to force SVG output when no extension is given.\n\n", .{});
        std.debug.print("Examples:\n", .{});
        std.debug.print("  {s} diagram.mmd diagram.png    (PNG output)\n", .{args[0]});
        std.debug.print("  {s} diagram.mmd diagram.svg    (SVG output)\n", .{args[0]});
        std.debug.print("  {s} diagram.mmd --svg          (SVG output to diagram.svg)\n", .{args[0]});
        std.debug.print("  {s} diagram.mmd                (PNG output to diagram.png)\n", .{args[0]});
        return error.InvalidArguments;
    }

    const input_file = args[1];

    // Check for --svg flag anywhere in args
    var force_svg = false;
    for (args[1..]) |arg| {
        if (std.mem.eql(u8, arg, "--svg")) {
            force_svg = true;
        }
    }

    // Find the output file argument (first arg after input that isn't a flag)
    var explicit_output: ?[]const u8 = null;
    if (args.len >= 3) {
        for (args[2..]) |arg| {
            if (!std.mem.startsWith(u8, arg, "--")) {
                explicit_output = arg;
                break;
            }
        }
    }

    const output_file = if (explicit_output) |out| out else blk: {
        const base = std.fs.path.basename(input_file);
        const dot_index = std.mem.lastIndexOf(u8, base, ".");
        const name_without_ext = if (dot_index) |idx| base[0..idx] else base;
        const ext = if (force_svg) ".svg" else ".png";
        break :blk try std.fmt.allocPrint(allocator, "{s}{s}", .{ name_without_ext, ext });
    };
    defer if (explicit_output == null) allocator.free(output_file);

    // Determine output format from extension (SVG if .svg, otherwise PNG)
    const is_svg_output = force_svg or blk: {
        const ext = std.fs.path.extension(output_file);
        break :blk std.ascii.eqlIgnoreCase(ext, ".svg");
    };

    std.debug.print("\n=== Mermaid Diagram Renderer ===\n\n", .{});
    std.debug.print("Input:  {s}\n", .{input_file});
    std.debug.print("Output: {s} ({s})\n\n", .{ output_file, if (is_svg_output) "SVG" else "PNG" });

    // ---------------------------------------------------------------
    // Read the Mermaid source file
    // ---------------------------------------------------------------
    std.debug.print("Reading Mermaid file...\n", .{});
    const source = try std.fs.cwd().readFileAlloc(allocator, input_file, 10 * 1024 * 1024);
    defer allocator.free(source);

    // ---------------------------------------------------------------
    // Detect diagram type
    // ---------------------------------------------------------------
    const is_sequence = detectSequenceDiagram(source);
    if (is_sequence) {
        std.debug.print("Detected diagram type: sequenceDiagram\n", .{});
        try renderSequenceDiagram(allocator, source, output_file, is_svg_output);
        return;
    }

    const is_pie = PieParser.isPieDiagram(source);
    if (is_pie) {
        std.debug.print("Detected diagram type: pie\n", .{});
        try renderPieDiagram(allocator, source, output_file, is_svg_output);
        return;
    }

    const is_class = ClassParser.isClassDiagram(source);
    if (is_class) {
        std.debug.print("Detected diagram type: classDiagram\n", .{});
        try renderClassDiagram(allocator, source, output_file, is_svg_output);
        return;
    }

    const is_state = StateParser.isStateDiagram(source);
    if (is_state) {
        std.debug.print("Detected diagram type: stateDiagram\n", .{});
        try renderStateDiagram(allocator, source, output_file, is_svg_output);
        return;
    }

    const is_journey = JourneyParser.isJourneyDiagram(source);
    if (is_journey) {
        std.debug.print("Detected diagram type: journey\n", .{});
        try renderJourneyDiagram(allocator, source, output_file, is_svg_output);
        return;
    }

    const is_er = ErParser.isErDiagram(source);
    if (is_er) {
        std.debug.print("Detected diagram type: erDiagram\n", .{});
        try renderErDiagram(allocator, source, output_file, is_svg_output);
        return;
    }

    const is_gantt = GanttParser.isGanttDiagram(source);
    if (is_gantt) {
        std.debug.print("Detected diagram type: gantt\n", .{});
        try renderGanttDiagram(allocator, source, output_file, is_svg_output);
        return;
    }

    std.debug.print("Detected diagram type: flowchart/graph\n", .{});

    // ---------------------------------------------------------------
    // Parse the diagram into a graph (flowchart path)
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
        .ranker = .network_simplex,
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
    // Render to output format
    // ---------------------------------------------------------------
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

    if (is_svg_output) {
        std.debug.print("\nRendering to SVG...\n", .{});
        if (maybe_font) |*font| {
            try renderGraphToSVGWithFont(allocator, &graph, output_file, render_config, font);
        } else {
            try renderGraphToSVG(allocator, &graph, output_file, render_config);
        }
        std.debug.print("\n✓ Successfully rendered to {s}\n", .{output_file});
        std.debug.print("   - Scalable vector graphics\n", .{});
        std.debug.print("   - Text rendered as SVG <text> elements\n", .{});
        std.debug.print("   - Open in any browser or SVG viewer\n", .{});
    } else {
        std.debug.print("\nRendering to PNG (HD quality)...\n", .{});
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
    }

    std.debug.print("\nOpen '{s}' to view your diagram!\n", .{output_file});
}

// ===================================================================
// Pie chart pipeline
// ===================================================================

/// Full pipeline: parse → render for pie charts.
fn renderPieDiagram(
    allocator: std.mem.Allocator,
    source: []const u8,
    output_file: []const u8,
    is_svg_output: bool,
) !void {
    // ---- Parse ----
    std.debug.print("Parsing pie chart...\n", .{});
    var pie = PieParser.parse(allocator, source) catch |err| {
        std.debug.print("Parse error: {}\n", .{err});
        return err;
    };
    defer pie.deinit();

    std.debug.print("  Found {d} sections\n", .{pie.sectionCount()});
    if (pie.title) |t| std.debug.print("  Title: {s}\n", .{t});
    if (pie.show_data) std.debug.print("  showData: enabled\n", .{});
    std.debug.print("  Total value: {d:.2}\n\n", .{pie.total()});

    // ---- Render ----
    if (is_svg_output) {
        std.debug.print("Rendering pie chart to SVG...\n", .{});
        try PieSvgRender.renderPieToSVG(allocator, &pie, output_file);
        std.debug.print("\n✓ Successfully rendered to {s}\n", .{output_file});
        std.debug.print("   - Scalable vector graphics\n", .{});
        std.debug.print("   - Arc-based pie slices with legend\n", .{});
        std.debug.print("   - Open in any browser or SVG viewer\n", .{});
    } else {
        std.debug.print("Rendering pie chart to PNG...\n", .{});

        // Load font for text rendering (same search paths as flowchart)
        const font_paths = [_][]const u8{
            "fonts/Lato-Regular.ttf",
            "../fonts/Lato-Regular.ttf",
            "../../fonts/Lato-Regular.ttf",
        };

        var pie_font_data: ?[]u8 = null;

        var pie_exe_font_buf: [std.fs.max_path_bytes]u8 = undefined;
        const pie_exe_font: ?[]const u8 = blk: {
            const exe_path = std.fs.selfExeDirPath(&pie_exe_font_buf) catch break :blk null;
            const prefixes = [_][]const u8{ "/fonts/Lato-Regular.ttf", "/../fonts/Lato-Regular.ttf", "/../../fonts/Lato-Regular.ttf" };
            for (prefixes) |suffix| {
                if (exe_path.len + suffix.len < pie_exe_font_buf.len) {
                    @memcpy(pie_exe_font_buf[exe_path.len .. exe_path.len + suffix.len], suffix);
                    const full = pie_exe_font_buf[0 .. exe_path.len + suffix.len];
                    pie_font_data = std.fs.cwd().readFileAlloc(allocator, full, 1024 * 1024) catch continue;
                    break :blk full;
                }
            }
            break :blk null;
        };

        if (pie_exe_font) |p| {
            std.debug.print("  Loaded font: {s}\n", .{p});
        } else {
            for (font_paths) |font_path| {
                pie_font_data = std.fs.cwd().readFileAlloc(allocator, font_path, 1024 * 1024) catch |err| {
                    if (err != error.FileNotFound) {
                        std.debug.print("  Warning: Error reading '{s}': {}\n", .{ font_path, err });
                    }
                    continue;
                };
                std.debug.print("  Loaded font: {s}\n", .{font_path});
                break;
            }
        }
        defer if (pie_font_data) |data| allocator.free(data);

        const PieFont = merrow.render.text.Font;
        var maybe_pie_font: ?PieFont = if (pie_font_data) |data|
            PieFont.initFromMemory(allocator, data) catch |err| blk: {
                std.debug.print("  Warning: Could not initialise font: {}\n", .{err});
                break :blk null;
            }
        else
            null;
        defer if (maybe_pie_font) |*f| f.deinit();

        var font_ptr: ?*Font = if (maybe_pie_font) |*f| f else null;
        _ = &font_ptr;

        try PiePngRender.renderPieToPNG(allocator, &pie, output_file, font_ptr);

        std.debug.print("\n✓ Successfully rendered to {s}\n", .{output_file});
        std.debug.print("   - HD quality: 2x scale factor\n", .{});
        std.debug.print("   - Pie slices with legend\n", .{});
        if (maybe_pie_font != null) {
            std.debug.print("   - With text labels\n", .{});
        } else {
            std.debug.print("   - Without text labels (no font found)\n", .{});
        }
    }

    std.debug.print("\nOpen '{s}' to view your diagram!\n", .{output_file});
}

// ===================================================================
// Sequence diagram pipeline
// ===================================================================

/// Detect whether the source starts with `sequenceDiagram`.
fn renderClassDiagram(
    allocator: std.mem.Allocator,
    source: []const u8,
    output_file: []const u8,
    is_svg_output: bool,
) !void {
    // ---- Parse ----
    std.debug.print("Parsing class diagram...\n", .{});
    var diagram = ClassParser.parse(allocator, source) catch |err| {
        std.debug.print("Parse error: {}\n", .{err});
        return err;
    };
    defer diagram.deinit();

    std.debug.print("  Found {d} classes\n", .{diagram.classCount()});
    std.debug.print("  Found {d} relationships\n", .{diagram.relationCount()});
    if (diagram.title) |t| std.debug.print("  Title: {s}\n", .{t});
    std.debug.print("  Direction: {s}\n\n", .{diagram.direction});

    // ---- Render ----
    if (is_svg_output) {
        std.debug.print("Rendering class diagram to SVG...\n", .{});
        try ClassSvgRender.renderClassToSVG(allocator, &diagram, output_file, null);
        std.debug.print("\n✓ Successfully rendered to {s}\n", .{output_file});
        std.debug.print("   - Scalable vector graphics\n", .{});
        std.debug.print("   - UML class boxes with compartments\n", .{});
        std.debug.print("   - Open in any browser or SVG viewer\n", .{});
    } else {
        std.debug.print("Rendering class diagram to PNG...\n", .{});

        // Load font (same search paths as flowchart).
        const font_paths = [_][]const u8{
            "fonts/Lato-Regular.ttf",
            "../fonts/Lato-Regular.ttf",
            "../../fonts/Lato-Regular.ttf",
        };

        var class_font_data: ?[]u8 = null;

        var class_exe_font_buf: [std.fs.max_path_bytes]u8 = undefined;
        const class_exe_font: ?[]const u8 = blk: {
            const exe_path = std.fs.selfExeDirPath(&class_exe_font_buf) catch break :blk null;
            const prefixes = [_][]const u8{ "/fonts/Lato-Regular.ttf", "/../fonts/Lato-Regular.ttf", "/../../fonts/Lato-Regular.ttf" };
            for (prefixes) |suffix| {
                if (exe_path.len + suffix.len < class_exe_font_buf.len) {
                    @memcpy(class_exe_font_buf[exe_path.len .. exe_path.len + suffix.len], suffix);
                    const full = class_exe_font_buf[0 .. exe_path.len + suffix.len];
                    class_font_data = std.fs.cwd().readFileAlloc(allocator, full, 1024 * 1024) catch continue;
                    break :blk full;
                }
            }
            break :blk null;
        };

        if (class_exe_font) |p| {
            std.debug.print("  Loaded font: {s}\n", .{p});
        } else {
            for (font_paths) |font_path| {
                class_font_data = std.fs.cwd().readFileAlloc(allocator, font_path, 1024 * 1024) catch |err| {
                    if (err != error.FileNotFound) {
                        std.debug.print("  Warning: Error reading '{s}': {}\n", .{ font_path, err });
                    }
                    continue;
                };
                std.debug.print("  Loaded font: {s}\n", .{font_path});
                break;
            }
        }
        defer if (class_font_data) |data| allocator.free(data);

        const ClassFont = merrow.render.text.Font;
        var maybe_class_font: ?ClassFont = if (class_font_data) |data|
            ClassFont.initFromMemory(allocator, data) catch |err| blk: {
                std.debug.print("  Warning: Could not initialise font: {}\n", .{err});
                break :blk null;
            }
        else
            null;
        defer if (maybe_class_font) |*f| f.deinit();

        var font_ptr: ?*Font = if (maybe_class_font) |*f| f else null;
        _ = &font_ptr;

        try ClassPngRender.renderClassToPNG(allocator, &diagram, output_file, font_ptr);

        std.debug.print("\n✓ Successfully rendered to {s}\n", .{output_file});
        std.debug.print("   - HD quality: 2x scale factor\n", .{});
        std.debug.print("   - UML class boxes with compartments\n", .{});
        if (maybe_class_font != null) {
            std.debug.print("   - With text labels\n", .{});
        } else {
            std.debug.print("   - Without text labels (no font found)\n", .{});
        }
    }

    std.debug.print("\nOpen '{s}' to view your diagram!\n", .{output_file});
}

fn detectSequenceDiagram(source: []const u8) bool {
    // Skip leading whitespace.
    var i: usize = 0;
    while (i < source.len and (source[i] == ' ' or source[i] == '\t' or source[i] == '\r' or source[i] == '\n')) {
        i += 1;
    }
    const keyword = "sequenceDiagram";
    if (i + keyword.len > source.len) return false;
    return std.mem.eql(u8, source[i .. i + keyword.len], keyword);
}

/// Full pipeline: parse → layout → render for sequence diagrams.
fn renderStateDiagram(allocator: std.mem.Allocator, source: []const u8, output_file: []const u8, is_svg_output: bool) !void {
    std.debug.print("Parsing state diagram...\n", .{});
    var diagram = try StateParser.parse(allocator, source);
    defer diagram.deinit();

    std.debug.print("  Found {d} states\n", .{diagram.stateCount()});
    std.debug.print("  Found {d} transitions\n\n", .{diagram.relationCount()});

    if (is_svg_output) {
        std.debug.print("Rendering to SVG...\n", .{});
        try StateSvgRender.renderStateToSVG(allocator, &diagram, output_file);
        std.debug.print("\n✓ Successfully rendered state diagram to {s}\n", .{output_file});
    } else {
        std.debug.print("Rendering to PNG (HD quality)...\n", .{});

        // Load font
        var font_data: ?[]u8 = null;
        var exe_font_buf: [std.fs.max_path_bytes]u8 = undefined;
        const exe_dir = std.fs.selfExeDirPath(&exe_font_buf) catch null;
        if (exe_dir) |dir| {
            const suffixes = [_][]const u8{ "/fonts/Lato-Regular.ttf", "/../fonts/Lato-Regular.ttf", "/../../fonts/Lato-Regular.ttf" };
            for (suffixes) |suffix| {
                if (dir.len + suffix.len < exe_font_buf.len) {
                    @memcpy(exe_font_buf[dir.len .. dir.len + suffix.len], suffix);
                    font_data = std.fs.cwd().readFileAlloc(allocator, exe_font_buf[0 .. dir.len + suffix.len], 1024 * 1024) catch continue;
                    break;
                }
            }
        }
        if (font_data == null) {
            const paths = [_][]const u8{ "fonts/Lato-Regular.ttf", "../fonts/Lato-Regular.ttf", "../../fonts/Lato-Regular.ttf" };
            for (paths) |p| {
                font_data = std.fs.cwd().readFileAlloc(allocator, p, 1024 * 1024) catch continue;
                break;
            }
        }
        defer if (font_data) |d| allocator.free(d);

        var maybe_font: ?Font = if (font_data) |d|
            Font.initFromMemory(allocator, d) catch null
        else
            null;
        defer if (maybe_font) |*f| f.deinit();

        const font_ptr: ?*Font = if (maybe_font) |*f| f else null;
        try StatePngRender.renderStateToPNG(allocator, &diagram, output_file, font_ptr);
        std.debug.print("\n✓ Successfully rendered state diagram to {s}\n", .{output_file});
    }

    std.debug.print("\nOpen '{s}' to view your diagram!\n", .{output_file});
}

fn renderJourneyDiagram(allocator: std.mem.Allocator, source: []const u8, output_file: []const u8, is_svg_output: bool) !void {
    std.debug.print("Parsing journey diagram...\n", .{});
    var diagram = try JourneyParser.parse(allocator, source);
    defer diagram.deinit();

    std.debug.print("  Found {d} tasks\n", .{diagram.taskCount()});
    std.debug.print("  Found {d} sections\n\n", .{diagram.sectionCount()});

    if (is_svg_output) {
        std.debug.print("Rendering to SVG...\n", .{});
        try JourneySvgRender.renderJourneyToSVG(allocator, &diagram, output_file);
        std.debug.print("\n✓ Successfully rendered journey diagram to {s}\n", .{output_file});
    } else {
        std.debug.print("Rendering to PNG (HD quality)...\n", .{});

        // Load font
        var font_data: ?[]u8 = null;
        var exe_font_buf: [std.fs.max_path_bytes]u8 = undefined;
        const exe_dir = std.fs.selfExeDirPath(&exe_font_buf) catch null;
        if (exe_dir) |dir| {
            const suffixes = [_][]const u8{ "/fonts/Lato-Regular.ttf", "/../fonts/Lato-Regular.ttf", "/../../fonts/Lato-Regular.ttf" };
            for (suffixes) |suffix| {
                if (dir.len + suffix.len < exe_font_buf.len) {
                    @memcpy(exe_font_buf[dir.len .. dir.len + suffix.len], suffix);
                    font_data = std.fs.cwd().readFileAlloc(allocator, exe_font_buf[0 .. dir.len + suffix.len], 1024 * 1024) catch continue;
                    break;
                }
            }
        }
        if (font_data == null) {
            const paths = [_][]const u8{ "fonts/Lato-Regular.ttf", "../fonts/Lato-Regular.ttf", "../../fonts/Lato-Regular.ttf" };
            for (paths) |p| {
                font_data = std.fs.cwd().readFileAlloc(allocator, p, 1024 * 1024) catch continue;
                break;
            }
        }
        defer if (font_data) |d| allocator.free(d);

        var maybe_font: ?Font = if (font_data) |d|
            Font.initFromMemory(allocator, d) catch null
        else
            null;
        defer if (maybe_font) |*f| f.deinit();

        const font_ptr: ?*Font = if (maybe_font) |*f| f else null;
        try JourneyPngRender.renderJourneyToPNG(allocator, &diagram, output_file, font_ptr);
        std.debug.print("\n✓ Successfully rendered journey diagram to {s}\n", .{output_file});
    }

    std.debug.print("\nOpen '{s}' to view your diagram!\n", .{output_file});
}

fn renderErDiagram(
    allocator: std.mem.Allocator,
    source: []const u8,
    output_file: []const u8,
    is_svg: bool,
) !void {
    std.debug.print("Parsing ER diagram...\n", .{});
    var diagram = ErParser.parse(allocator, source) catch |err| {
        std.debug.print("Error parsing ER diagram: {}\n", .{err});
        return err;
    };
    defer diagram.deinit();

    std.debug.print("  Entities: {d}\n", .{diagram.entityCount()});
    std.debug.print("  Relationships: {d}\n", .{diagram.relationshipCount()});

    if (is_svg) {
        std.debug.print("Rendering ER diagram to SVG...\n", .{});
        try ErSvgRender.renderErToSVG(allocator, &diagram, output_file);
    } else {
        std.debug.print("Rendering ER diagram to PNG...\n", .{});

        // Load font
        var font_data: ?[]u8 = null;
        var exe_font_buf: [std.fs.max_path_bytes]u8 = undefined;
        const exe_dir = std.fs.selfExeDirPath(&exe_font_buf) catch null;
        if (exe_dir) |dir| {
            const suffixes = [_][]const u8{ "/fonts/Lato-Regular.ttf", "/../fonts/Lato-Regular.ttf", "/../../fonts/Lato-Regular.ttf" };
            for (suffixes) |suffix| {
                if (dir.len + suffix.len < exe_font_buf.len) {
                    @memcpy(exe_font_buf[dir.len .. dir.len + suffix.len], suffix);
                    font_data = std.fs.cwd().readFileAlloc(allocator, exe_font_buf[0 .. dir.len + suffix.len], 1024 * 1024) catch continue;
                    break;
                }
            }
        }
        if (font_data == null) {
            const paths = [_][]const u8{ "fonts/Lato-Regular.ttf", "../fonts/Lato-Regular.ttf", "../../fonts/Lato-Regular.ttf" };
            for (paths) |p| {
                font_data = std.fs.cwd().readFileAlloc(allocator, p, 1024 * 1024) catch continue;
                break;
            }
        }
        defer if (font_data) |d| allocator.free(d);

        var maybe_font: ?Font = if (font_data) |d|
            Font.initFromMemory(allocator, d) catch null
        else
            null;
        defer if (maybe_font) |*f| f.deinit();

        const font_ptr: ?*Font = if (maybe_font) |*f| f else null;
        try ErPngRender.renderErToPNG(allocator, &diagram, output_file, font_ptr);
    }

    std.debug.print("Done! Output written to {s}\n", .{output_file});
}

fn renderGanttDiagram(
    allocator: std.mem.Allocator,
    source: []const u8,
    output_file: []const u8,
    is_svg: bool,
) !void {
    std.debug.print("Parsing Gantt diagram...\n", .{});
    var diagram = GanttParser.parse(allocator, source) catch |err| {
        std.debug.print("Error parsing Gantt diagram: {}\n", .{err});
        return err;
    };
    defer diagram.deinit();

    std.debug.print("  Tasks: {d}\n", .{diagram.taskCount()});
    std.debug.print("  Sections: {d}\n", .{diagram.sectionCount()});

    if (is_svg) {
        std.debug.print("Rendering Gantt diagram to SVG...\n", .{});
        try GanttSvgRender.renderGanttToSVG(allocator, &diagram, output_file);
    } else {
        std.debug.print("Rendering Gantt diagram to PNG...\n", .{});

        // Load font
        var font_data: ?[]u8 = null;
        var exe_font_buf: [std.fs.max_path_bytes]u8 = undefined;
        const exe_dir = std.fs.selfExeDirPath(&exe_font_buf) catch null;
        if (exe_dir) |dir| {
            const suffixes = [_][]const u8{ "/fonts/Lato-Regular.ttf", "/../fonts/Lato-Regular.ttf", "/../../fonts/Lato-Regular.ttf" };
            for (suffixes) |suffix| {
                if (dir.len + suffix.len < exe_font_buf.len) {
                    @memcpy(exe_font_buf[dir.len .. dir.len + suffix.len], suffix);
                    font_data = std.fs.cwd().readFileAlloc(allocator, exe_font_buf[0 .. dir.len + suffix.len], 1024 * 1024) catch continue;
                    break;
                }
            }
        }
        if (font_data == null) {
            const paths = [_][]const u8{ "fonts/Lato-Regular.ttf", "../fonts/Lato-Regular.ttf", "../../fonts/Lato-Regular.ttf" };
            for (paths) |p| {
                font_data = std.fs.cwd().readFileAlloc(allocator, p, 1024 * 1024) catch continue;
                break;
            }
        }
        defer if (font_data) |d| allocator.free(d);

        var maybe_font: ?Font = if (font_data) |d|
            Font.initFromMemory(allocator, d) catch null
        else
            null;
        defer if (maybe_font) |*f| f.deinit();

        const font_ptr: ?*Font = if (maybe_font) |*f| f else null;
        try GanttPngRender.renderGanttToPNG(allocator, &diagram, output_file, font_ptr);
    }

    std.debug.print("Done! Output written to {s}\n", .{output_file});
}

fn renderSequenceDiagram(
    allocator: std.mem.Allocator,
    source: []const u8,
    output_file: []const u8,
    is_svg_output: bool,
) !void {
    // ---- Parse ----
    std.debug.print("Parsing sequence diagram...\n", .{});
    var seq_parser = SeqParser.init(allocator, source);
    var diag = seq_parser.parse() catch |err| {
        std.debug.print("Parse error: {}\n", .{err});
        return err;
    };
    defer diag.deinit();

    std.debug.print("  Found {d} participants\n", .{diag.participants.items.len});
    std.debug.print("  Found {d} messages\n", .{diag.messages.items.len});
    std.debug.print("  Found {d} notes\n", .{diag.notes.items.len});
    std.debug.print("  Found {d} activations\n", .{diag.activations.items.len});
    std.debug.print("  Found {d} fragments\n", .{diag.fragments.items.len});
    if (diag.autonumber) std.debug.print("  Autonumber: enabled\n", .{});
    if (diag.title) |t| std.debug.print("  Title: {s}\n", .{t});
    std.debug.print("\n", .{});

    // ---- Layout ----
    std.debug.print("Running sequence layout...\n", .{});
    const layout_config = SeqLayout.LayoutConfig{};
    const layout_result = SeqLayout.layout(&diag, layout_config);

    std.debug.print("  Canvas: {d:.0} x {d:.0}\n", .{ layout_result.width, layout_result.height });

    // Print participant positions.
    for (diag.participants.items) |p| {
        std.debug.print("  {s}: x={d:.1}\n", .{ p.displayName(), p.center_x });
    }
    std.debug.print("\n", .{});

    // ---- Render ----
    if (is_svg_output) {
        std.debug.print("Rendering sequence diagram to SVG...\n", .{});
        const render_config = SeqSvgRender.SeqRenderConfig{};
        try SeqSvgRender.renderToSVGFile(
            allocator,
            &diag,
            layout_result,
            output_file,
            layout_config,
            render_config,
        );
        std.debug.print("\n✓ Successfully rendered to {s}\n", .{output_file});
        std.debug.print("   - Scalable vector graphics\n", .{});
        std.debug.print("   - Participants, lifelines, messages, notes\n", .{});
        std.debug.print("   - Open in any browser or SVG viewer\n", .{});
    } else {
        std.debug.print("Rendering sequence diagram to PNG...\n", .{});

        // Load font for text rendering (same search paths as flowchart)
        const font_paths = [_][]const u8{
            "fonts/Lato-Regular.ttf",
            "../fonts/Lato-Regular.ttf",
            "../../fonts/Lato-Regular.ttf",
        };

        var seq_font_data: ?[]u8 = null;

        var seq_exe_font_buf: [std.fs.max_path_bytes]u8 = undefined;
        const seq_exe_font: ?[]const u8 = blk: {
            const exe_path = std.fs.selfExeDirPath(&seq_exe_font_buf) catch break :blk null;
            const prefixes = [_][]const u8{ "/fonts/Lato-Regular.ttf", "/../fonts/Lato-Regular.ttf", "/../../fonts/Lato-Regular.ttf" };
            for (prefixes) |suffix| {
                if (exe_path.len + suffix.len < seq_exe_font_buf.len) {
                    @memcpy(seq_exe_font_buf[exe_path.len .. exe_path.len + suffix.len], suffix);
                    const full = seq_exe_font_buf[0 .. exe_path.len + suffix.len];
                    seq_font_data = std.fs.cwd().readFileAlloc(allocator, full, 1024 * 1024) catch continue;
                    break :blk full;
                }
            }
            break :blk null;
        };

        if (seq_exe_font) |p| {
            std.debug.print("  Loaded font: {s}\n", .{p});
        } else {
            for (font_paths) |font_path| {
                seq_font_data = std.fs.cwd().readFileAlloc(allocator, font_path, 1024 * 1024) catch |err| {
                    if (err != error.FileNotFound) {
                        std.debug.print("  Warning: Error reading '{s}': {}\n", .{ font_path, err });
                    }
                    continue;
                };
                std.debug.print("  Loaded font: {s}\n", .{font_path});
                break;
            }
        }
        defer if (seq_font_data) |data| allocator.free(data);

        const SeqFont = merrow.render.text.Font;
        var maybe_seq_font: ?SeqFont = if (seq_font_data) |data|
            SeqFont.initFromMemory(allocator, data) catch |err| blk: {
                std.debug.print("  Warning: Could not initialise font: {}\n", .{err});
                break :blk null;
            }
        else
            null;
        defer if (maybe_seq_font) |*f| f.deinit();

        const png_config = SeqPngRender.SeqPngRenderConfig{};
        const font_ptr: ?*SeqFont = if (maybe_seq_font) |*f| f else null;

        try SeqPngRender.renderToPNGFile(
            allocator,
            &diag,
            layout_result,
            output_file,
            layout_config,
            png_config,
            font_ptr,
        );

        std.debug.print("\n✓ Successfully rendered to {s}\n", .{output_file});
        std.debug.print("   - HD quality: {d:.0}x scale factor\n", .{png_config.scale_factor});
        std.debug.print("   - Participants, lifelines, messages, notes\n", .{});
        if (maybe_seq_font != null) {
            std.debug.print("   - With text labels\n", .{});
        } else {
            std.debug.print("   - Without text labels (no font found)\n", .{});
        }
    }

    std.debug.print("\nOpen '{s}' to view your diagram!\n", .{output_file});
}
