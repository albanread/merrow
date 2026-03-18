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
const node_padding_h: f64 = 40.0; // horizontal (left + right total)
const node_padding_v: f64 = 16.0; // vertical  (top + bottom total)
const min_node_width: f64 = 60.0;
const min_node_height: f64 = 36.0;
const font_size: f32 = 16.0;
/// Maximum label width (logical pixels) before text wraps to the next line.
const max_label_width: f32 = 220.0;
const wrapped_text_safety_w: f64 = 12.0;

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
        text_w = @floatCast(wrapped.width + @as(f32, @floatCast(wrapped_text_safety_w)));
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
        printUsage(args[0]);
        return error.InvalidArguments;
    }

    // ---------------------------------------------------------------
    // Scan all arguments for flags and positionals
    // ---------------------------------------------------------------
    var bulk_mode = false;
    var force_svg = false;
    var verbose = false;
    var positional_buf: [8][]const u8 = undefined;
    var positional_count: usize = 0;

    for (args[1..]) |arg| {
        if (std.mem.eql(u8, arg, "--bulk")) {
            bulk_mode = true;
        } else if (std.mem.eql(u8, arg, "--svg")) {
            force_svg = true;
        } else if (std.mem.eql(u8, arg, "--verbose") or std.mem.eql(u8, arg, "-v")) {
            verbose = true;
        } else if (!std.mem.startsWith(u8, arg, "--")) {
            if (positional_count < positional_buf.len) {
                positional_buf[positional_count] = arg;
                positional_count += 1;
            }
        }
    }

    // ---------------------------------------------------------------
    // Check for --bulk mode (position-independent)
    // ---------------------------------------------------------------
    if (bulk_mode) {
        try runBulk(allocator, args);
        return;
    }

    if (positional_count == 0) {
        printUsage(args[0]);
        return error.InvalidArguments;
    }

    const input_file = positional_buf[0];

    // Find the output file argument (second positional, if any)
    var explicit_output: ?[]const u8 = null;
    if (positional_count >= 2) {
        explicit_output = positional_buf[1];
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
    // Verbose layout analysis
    // ---------------------------------------------------------------
    if (verbose) {
        std.debug.print("\n=== VERBOSE LAYOUT ANALYSIS ===\n\n", .{});

        // 1. List all containers (subgraph nodes) with sizes
        std.debug.print("--- Containers (subgraph nodes) ---\n", .{});
        var container_count: usize = 0;
        for (node_ids) |id| {
            if (graph.getNode(id)) |node| {
                if (node.is_subgraph) {
                    const title = node.subgraph_title orelse node.label orelse id;
                    std.debug.print("  Container '{s}' (id='{s}')\n", .{ title, id });
                    std.debug.print("    Position: ({d:.1}, {d:.1})\n", .{ node.x, node.y });
                    std.debug.print("    Size:     {d:.1} x {d:.1}\n", .{ node.width, node.height });
                    const left = node.x - node.width / 2.0;
                    const right = node.x + node.width / 2.0;
                    const top = node.y - node.height / 2.0;
                    const bottom = node.y + node.height / 2.0;
                    std.debug.print("    Bounds:   left={d:.1} right={d:.1} top={d:.1} bottom={d:.1}\n", .{
                        left, right, top, bottom,
                    });

                    // List children inside this container
                    const children = graph.getChildren(id);
                    std.debug.print("    Children ({d}):\n", .{children.len});
                    var all_inside = true;
                    for (children) |cid| {
                        if (graph.getNode(cid)) |child| {
                            if (child.is_subgraph or child.dummy) continue;
                            const clabel = child.label orelse cid;
                            const c_left = child.x - child.width / 2.0;
                            const c_right = child.x + child.width / 2.0;
                            const c_top = child.y - child.height / 2.0;
                            const c_bottom = child.y + child.height / 2.0;
                            const inside = c_left >= left - 1.0 and c_right <= right + 1.0 and
                                c_top >= top - 1.0 and c_bottom <= bottom + 1.0;
                            if (!inside) all_inside = false;
                            std.debug.print("      {s}: ({d:.1}, {d:.1}) [{d:.0}x{d:.0}] {s}\n", .{
                                clabel,                                       child.x, child.y, child.width, child.height,
                                if (inside) "✓ inside" else "✗ OUTSIDE!",
                            });
                        }
                    }
                    std.debug.print("    => All children contained: {s}\n\n", .{
                        if (all_inside) "YES ✓" else "NO ✗ — PROBLEM",
                    });
                    container_count += 1;
                }
            }
        }
        if (container_count == 0) {
            std.debug.print("  (no containers — flat graph)\n\n", .{});
        }

        // 2. Check container-container overlap
        std.debug.print("--- Container overlap check ---\n", .{});
        {
            // Collect container bounding boxes
            const ContRect = struct { id: []const u8, left: f64, right: f64, top: f64, bottom: f64 };
            var rects = std.ArrayListUnmanaged(ContRect){};
            defer rects.deinit(allocator);

            for (node_ids) |id| {
                if (graph.getNode(id)) |node| {
                    if (node.is_subgraph and node.width > 1.0) {
                        try rects.append(allocator, .{
                            .id = id,
                            .left = node.x - node.width / 2.0,
                            .right = node.x + node.width / 2.0,
                            .top = node.y - node.height / 2.0,
                            .bottom = node.y + node.height / 2.0,
                        });
                    }
                }
            }

            var overlap_found = false;
            for (rects.items, 0..) |a, i| {
                for (rects.items[i + 1 ..]) |b| {
                    // Check if one is an ancestor of the other (skip nested).
                    const is_nested = blk: {
                        // Walk a's parent chain to see if b is an ancestor.
                        var cursor: ?[]const u8 = graph.getParent(a.id);
                        while (cursor) |pid| {
                            if (std.mem.eql(u8, pid, b.id)) break :blk true;
                            cursor = graph.getParent(pid);
                        }
                        // Walk b's parent chain to see if a is an ancestor.
                        cursor = graph.getParent(b.id);
                        while (cursor) |pid| {
                            if (std.mem.eql(u8, pid, a.id)) break :blk true;
                            cursor = graph.getParent(pid);
                        }
                        break :blk false;
                    };
                    if (is_nested) continue;

                    const h_overlap = a.left < b.right and a.right > b.left;
                    const v_overlap = a.top < b.bottom and a.bottom > b.top;
                    if (h_overlap and v_overlap) {
                        std.debug.print("  ✗ OVERLAP: '{s}' and '{s}'\n", .{ a.id, b.id });
                        overlap_found = true;
                    }
                }
            }
            if (!overlap_found) {
                std.debug.print("  ✓ No container overlaps\n", .{});
            }
        }

        // 3. Analyse inter-container edges
        std.debug.print("\n--- Inter-container edge analysis ---\n", .{});
        {
            var edge_it = graph.edgeIterator();
            var inter_count: usize = 0;
            var intra_count: usize = 0;
            while (edge_it.next()) |entry| {
                const v_parent = graph.getParent(entry.v);
                const w_parent = graph.getParent(entry.w);
                const v_node = graph.getNode(entry.v);
                const w_node = graph.getNode(entry.w);
                if (v_node == null or w_node == null) continue;
                // Skip dummy nodes
                if (v_node.?.dummy or w_node.?.dummy) continue;

                const same_parent = blk: {
                    if (v_parent == null and w_parent == null) break :blk true;
                    if (v_parent) |vp| {
                        if (w_parent) |wp| {
                            break :blk std.mem.eql(u8, vp, wp);
                        }
                    }
                    break :blk false;
                };

                if (same_parent) {
                    intra_count += 1;
                } else {
                    inter_count += 1;
                    const v_label = v_node.?.label orelse entry.v;
                    const w_label = w_node.?.label orelse entry.w;
                    const v_cont = v_parent orelse "(root)";
                    const w_cont = w_parent orelse "(root)";

                    // Check if edge has pre-computed points
                    const has_points = entry.data.points.items.len > 0;
                    std.debug.print("  {s}[{s}] -> {s}[{s}]", .{
                        v_label, v_cont, w_label, w_cont,
                    });
                    if (has_points) {
                        std.debug.print(" ({d} waypoints)\n", .{entry.data.points.items.len});
                        if (entry.data.points.items.len > 2) {
                            for (entry.data.points.items, 0..) |pt, pi| {
                                std.debug.print("    wp[{d}] = ({d:.1}, {d:.1})\n", .{ pi, pt.x, pt.y });
                            }
                        }
                    } else {
                        std.debug.print(" (no waypoints — uses dummy chain)\n", .{});
                    }
                }
            }
            std.debug.print("  Summary: {d} intra-container, {d} inter-container edges\n", .{
                intra_count, inter_count,
            });
        }

        // 4. Success criteria summary
        std.debug.print("\n--- Success criteria (from container-edges-first.md) ---\n", .{});
        std.debug.print("  1. Containers tightly sized:  (check sizes above)\n", .{});
        std.debug.print("  2. No edge crosses foreign container: (check edge routing above)\n", .{});
        std.debug.print("  3. Flat diagrams unchanged:   (flat path = no subgraphs)\n", .{});
        std.debug.print("  4. Subgraph diagrams clean:   (visual inspection needed)\n", .{});
        std.debug.print("  5. zig build test passes:     (run separately)\n", .{});
        std.debug.print("\n=== END VERBOSE ===\n\n", .{});
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
// Usage / help
// ===================================================================

fn printUsage(prog: []const u8) void {
    std.debug.print("Usage:\n", .{});
    std.debug.print("  {s} <input.mmd> [output.png|output.svg] [--svg] [--verbose]\n", .{prog});
    std.debug.print("  {s} --bulk <infolder> <outfolder> [--force] [--svg]\n\n", .{prog});
    std.debug.print("Renders Mermaid diagrams to PNG or SVG images.\n", .{});
    std.debug.print("Supports: flowchart/graph, sequenceDiagram, pie, classDiagram,\n", .{});
    std.debug.print("          stateDiagram, journey, erDiagram, gantt\n\n", .{});
    std.debug.print("Options:\n", .{});
    std.debug.print("  --svg       Force SVG output\n", .{});
    std.debug.print("  --verbose   Print detailed layout analysis (containers, edges, overlaps)\n", .{});
    std.debug.print("  -v          Short form of --verbose\n\n", .{});
    std.debug.print("Single file mode:\n", .{});
    std.debug.print("  Output format is auto-detected from the file extension.\n", .{});
    std.debug.print("  Use --svg to force SVG output when no extension is given.\n\n", .{});
    std.debug.print("  Examples:\n", .{});
    std.debug.print("    {s} diagram.mmd diagram.png    (PNG output)\n", .{prog});
    std.debug.print("    {s} diagram.mmd diagram.svg    (SVG output)\n", .{prog});
    std.debug.print("    {s} diagram.mmd --svg          (SVG to diagram.svg)\n", .{prog});
    std.debug.print("    {s} diagram.mmd                (PNG to diagram.png)\n\n", .{prog});
    std.debug.print("Bulk mode:\n", .{});
    std.debug.print("  Renders all .mmd files in <infolder> to <outfolder>.\n", .{});
    std.debug.print("  --force   Re-render all files regardless of timestamps.\n", .{});
    std.debug.print("  (default) Only render when .mmd is newer than existing output.\n", .{});
    std.debug.print("  --svg     Output SVG instead of PNG.\n\n", .{});
    std.debug.print("  Examples:\n", .{});
    std.debug.print("    {s} --bulk docs/diagrams out/images\n", .{prog});
    std.debug.print("    {s} --bulk docs/diagrams out/images --force\n", .{prog});
    std.debug.print("    {s} --bulk src out --svg --force\n", .{prog});
}

// ===================================================================
// Bulk workflow mode
// ===================================================================

/// Run bulk rendering: scan infolder for .mmd files, render each to
/// outfolder as PNG or SVG.  With --force, re-render everything;
/// otherwise only render when the .mmd is newer than the output
/// (or the output doesn't exist).
fn runBulk(allocator: std.mem.Allocator, args: []const []const u8) !void {
    // ---- Parse bulk arguments ----
    // Expected: --bulk <infolder> <outfolder> [--force] [--svg]
    var infolder: ?[]const u8 = null;
    var outfolder: ?[]const u8 = null;
    var force = false;
    var svg_output = false;

    // Skip args[0] (program name); --bulk may appear anywhere
    var positional_count: usize = 0;
    for (args[1..]) |arg| {
        if (std.mem.eql(u8, arg, "--bulk")) {
            continue;
        } else if (std.mem.eql(u8, arg, "--force")) {
            force = true;
        } else if (std.mem.eql(u8, arg, "--svg")) {
            svg_output = true;
        } else if (!std.mem.startsWith(u8, arg, "--")) {
            if (positional_count == 0) {
                infolder = arg;
            } else if (positional_count == 1) {
                outfolder = arg;
            }
            positional_count += 1;
        }
    }

    const in_path = infolder orelse {
        std.debug.print("Error: --bulk requires <infolder> <outfolder>\n\n", .{});
        printUsage(args[0]);
        return error.InvalidArguments;
    };
    const out_path = outfolder orelse {
        std.debug.print("Error: --bulk requires <infolder> <outfolder>\n\n", .{});
        printUsage(args[0]);
        return error.InvalidArguments;
    };

    const out_ext: []const u8 = if (svg_output) ".svg" else ".png";
    const format_name: []const u8 = if (svg_output) "SVG" else "PNG";
    const mode_name: []const u8 = if (force) "force" else "update";

    // ---- Print header ----
    std.debug.print("\n=== Merrow Bulk Render ===\n\n", .{});
    std.debug.print("  Input folder:  {s}\n", .{in_path});
    std.debug.print("  Output folder: {s}\n", .{out_path});
    std.debug.print("  Format:        {s}\n", .{format_name});
    std.debug.print("  Mode:          {s}\n\n", .{mode_name});

    // ---- Start overall timer ----
    var overall_timer = try std.time.Timer.start();

    // ---- Ensure output directory exists ----
    std.fs.cwd().makePath(out_path) catch |err| {
        std.debug.print("Error: cannot create output folder '{s}': {}\n", .{ out_path, err });
        return err;
    };

    // ---- Load font once for all renders ----
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

    // ---- Scan input folder for .mmd files ----
    var dir = std.fs.cwd().openDir(in_path, .{ .iterate = true }) catch |err| {
        std.debug.print("Error: cannot open input folder '{s}': {}\n", .{ in_path, err });
        return err;
    };
    defer dir.close();

    // Collect .mmd filenames (sorted for deterministic output)
    var mmd_files = std.ArrayList([]const u8){};
    defer {
        for (mmd_files.items) |name| allocator.free(name);
        mmd_files.deinit(allocator);
    }

    var dir_iter = dir.iterate();
    while (try dir_iter.next()) |entry| {
        if (entry.kind != .file) continue;
        const ext = std.fs.path.extension(entry.name);
        if (!std.ascii.eqlIgnoreCase(ext, ".mmd")) continue;
        const owned_name = try allocator.dupe(u8, entry.name);
        try mmd_files.append(allocator, owned_name);
    }

    // Sort alphabetically for deterministic order
    std.mem.sort([]const u8, mmd_files.items, {}, struct {
        fn lessThan(_: void, a: []const u8, b: []const u8) bool {
            return std.mem.order(u8, a, b) == .lt;
        }
    }.lessThan);

    if (mmd_files.items.len == 0) {
        std.debug.print("  No .mmd files found in '{s}'.\n\n", .{in_path});
        return;
    }

    std.debug.print("  Found {d} .mmd file(s)\n\n", .{mmd_files.items.len});

    // ---- Process each file ----
    var rendered_count: usize = 0;
    var skipped_count: usize = 0;
    var error_count: usize = 0;
    var total_render_ns: u64 = 0;

    for (mmd_files.items) |mmd_name| {
        // Build input and output paths
        const input_path = try std.fmt.allocPrint(allocator, "{s}/{s}", .{ in_path, mmd_name });
        defer allocator.free(input_path);

        // Replace .mmd extension with output extension
        const dot_idx = std.mem.lastIndexOf(u8, mmd_name, ".") orelse mmd_name.len;
        const stem = mmd_name[0..dot_idx];
        const output_name = try std.fmt.allocPrint(allocator, "{s}{s}", .{ stem, out_ext });
        defer allocator.free(output_name);
        const output_path = try std.fmt.allocPrint(allocator, "{s}/{s}", .{ out_path, output_name });
        defer allocator.free(output_path);

        // ---- Timestamp check (unless --force) ----
        if (!force) {
            const should_skip = blk: {
                // Get mtime of the .mmd source
                const in_stat = std.fs.cwd().statFile(input_path) catch break :blk false;
                // Get mtime of the output file
                const out_stat = std.fs.cwd().statFile(output_path) catch break :blk false;
                // Skip if output is newer than or equal to source
                break :blk out_stat.mtime >= in_stat.mtime;
            };

            if (should_skip) {
                skipped_count += 1;
                std.debug.print("  skip  {s}  (up to date)\n", .{mmd_name});
                continue;
            }
        }

        // ---- Read source ----
        const source = std.fs.cwd().readFileAlloc(allocator, input_path, 10 * 1024 * 1024) catch |err| {
            error_count += 1;
            std.debug.print("  ERROR {s}  read failed: {}\n", .{ mmd_name, err });
            continue;
        };
        defer allocator.free(source);

        // ---- Render ----
        var file_timer = try std.time.Timer.start();

        renderSourceToFile(allocator, source, output_path, svg_output, font_data) catch |err| {
            error_count += 1;
            std.debug.print("  ERROR {s}  render failed: {}\n", .{ mmd_name, err });
            continue;
        };

        const file_ns = file_timer.read();
        total_render_ns += file_ns;
        rendered_count += 1;
        const file_ms = @as(f64, @floatFromInt(file_ns)) / 1_000_000.0;
        std.debug.print("  ok    {s} -> {s}  ({d:.0}ms)\n", .{ mmd_name, output_name, file_ms });
    }

    // ---- Summary ----
    const overall_ns = overall_timer.read();
    const overall_ms = @as(f64, @floatFromInt(overall_ns)) / 1_000_000.0;
    const render_ms = @as(f64, @floatFromInt(total_render_ns)) / 1_000_000.0;

    std.debug.print("\n--- Summary ---\n", .{});
    std.debug.print("  Rendered: {d} file(s)\n", .{rendered_count});
    if (skipped_count > 0) {
        std.debug.print("  Skipped:  {d} file(s)  (up to date)\n", .{skipped_count});
    }
    if (error_count > 0) {
        std.debug.print("  Errors:   {d} file(s)\n", .{error_count});
    }
    std.debug.print("  Render time:  {d:.0}ms\n", .{render_ms});
    std.debug.print("  Total time:   {d:.0}ms\n\n", .{overall_ms});
}

// ===================================================================
// Quiet single-source rendering (used by bulk mode)
// ===================================================================

/// Render a source buffer to an output file without printing verbose
/// progress messages.  Detects the diagram type, parses, lays out,
/// and renders.  `maybe_font_data` is optional pre-loaded font data
/// that avoids re-reading the font file from disk for each render.
fn renderSourceToFile(
    allocator: std.mem.Allocator,
    source: []const u8,
    output_file: []const u8,
    is_svg_output: bool,
    maybe_font_data: ?[]const u8,
) !void {
    // ---- Detect diagram type and delegate ----
    if (detectSequenceDiagram(source)) {
        return renderSequenceDiagramQuiet(allocator, source, output_file, is_svg_output, maybe_font_data);
    }
    if (PieParser.isPieDiagram(source)) {
        return renderPieDiagramQuiet(allocator, source, output_file, is_svg_output, maybe_font_data);
    }
    if (ClassParser.isClassDiagram(source)) {
        return renderClassDiagramQuiet(allocator, source, output_file, is_svg_output, maybe_font_data);
    }
    if (StateParser.isStateDiagram(source)) {
        return renderStateDiagramQuiet(allocator, source, output_file, is_svg_output, maybe_font_data);
    }
    if (JourneyParser.isJourneyDiagram(source)) {
        return renderJourneyDiagramQuiet(allocator, source, output_file, is_svg_output, maybe_font_data);
    }
    if (ErParser.isErDiagram(source)) {
        return renderErDiagramQuiet(allocator, source, output_file, is_svg_output, maybe_font_data);
    }
    if (GanttParser.isGanttDiagram(source)) {
        return renderGanttDiagramQuiet(allocator, source, output_file, is_svg_output, maybe_font_data);
    }

    // Default: flowchart/graph
    return renderFlowchartQuiet(allocator, source, output_file, is_svg_output, maybe_font_data);
}

/// Initialise a Font from pre-loaded data or by searching standard paths.
/// Returns null if no font could be loaded.
fn initFont(allocator: std.mem.Allocator, maybe_font_data: ?[]const u8) ?Font {
    if (maybe_font_data) |data| {
        return Font.initFromMemory(allocator, data) catch null;
    }
    return null;
}

// ---- Quiet renderers for each diagram type ----

fn renderFlowchartQuiet(
    allocator: std.mem.Allocator,
    source: []const u8,
    output_file: []const u8,
    is_svg_output: bool,
    maybe_font_data: ?[]const u8,
) !void {
    var parser = try Parser.init(allocator, source);
    defer parser.deinit();
    var graph = try parser.parse();
    defer {
        normalize.freeDummyIds(allocator, &graph);
        graph.deinitDeep();
    }

    var maybe_font: ?Font = initFont(allocator, maybe_font_data);
    defer if (maybe_font) |*f| f.deinit();

    // Size nodes
    const node_ids = try graph.allNodes(allocator);
    defer {
        for (node_ids) |id| allocator.free(id);
        allocator.free(node_ids);
    }
    for (node_ids) |id| {
        if (graph.getNodePtr(id)) |node| {
            if (node.width > 0) continue;
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

    // Layout
    const graph_label = graph.getGraphLabel();
    const rankdir: dagre.RankDir = blk: {
        if (std.mem.eql(u8, graph_label.rankdir, "LR")) break :blk .LR;
        if (std.mem.eql(u8, graph_label.rankdir, "RL")) break :blk .RL;
        if (std.mem.eql(u8, graph_label.rankdir, "BT")) break :blk .BT;
        break :blk .TB;
    };
    const config = dagre.DagreConfig{
        .rankdir = rankdir,
        .ranker = .network_simplex,
        .nodesep = 50,
        .ranksep = 50,
    };
    try dagre.layout(allocator, &graph, config);

    // Render
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
        if (maybe_font) |*font| {
            try renderGraphToSVGWithFont(allocator, &graph, output_file, render_config, font);
        } else {
            try renderGraphToSVG(allocator, &graph, output_file, render_config);
        }
    } else {
        if (maybe_font) |*font| {
            try renderGraphToPNGWithFont(allocator, &graph, output_file, render_config, font);
        } else {
            try renderGraphToPNG(allocator, &graph, output_file, render_config);
        }
    }
}

fn renderSequenceDiagramQuiet(
    allocator: std.mem.Allocator,
    source: []const u8,
    output_file: []const u8,
    is_svg_output: bool,
    maybe_font_data: ?[]const u8,
) !void {
    var seq_parser = SeqParser.init(allocator, source);
    var diag = try seq_parser.parse();
    defer diag.deinit();

    const layout_config = SeqLayout.LayoutConfig{};
    const layout_result = SeqLayout.layout(&diag, layout_config);

    if (is_svg_output) {
        const render_config = SeqSvgRender.SeqRenderConfig{};
        try SeqSvgRender.renderToSVGFile(allocator, &diag, layout_result, output_file, layout_config, render_config);
    } else {
        const SeqFont = merrow.render.text.Font;
        var maybe_font: ?SeqFont = if (maybe_font_data) |data|
            SeqFont.initFromMemory(allocator, data) catch null
        else
            null;
        defer if (maybe_font) |*f| f.deinit();
        const font_ptr: ?*SeqFont = if (maybe_font) |*f| f else null;
        const png_config = SeqPngRender.SeqPngRenderConfig{};
        try SeqPngRender.renderToPNGFile(allocator, &diag, layout_result, output_file, layout_config, png_config, font_ptr);
    }
}

fn renderPieDiagramQuiet(
    allocator: std.mem.Allocator,
    source: []const u8,
    output_file: []const u8,
    is_svg_output: bool,
    maybe_font_data: ?[]const u8,
) !void {
    var pie = try PieParser.parse(allocator, source);
    defer pie.deinit();

    if (is_svg_output) {
        try PieSvgRender.renderPieToSVG(allocator, &pie, output_file);
    } else {
        var maybe_font: ?Font = initFont(allocator, maybe_font_data);
        defer if (maybe_font) |*f| f.deinit();
        var font_ptr: ?*Font = if (maybe_font) |*f| f else null;
        _ = &font_ptr;
        try PiePngRender.renderPieToPNG(allocator, &pie, output_file, font_ptr);
    }
}

fn renderClassDiagramQuiet(
    allocator: std.mem.Allocator,
    source: []const u8,
    output_file: []const u8,
    is_svg_output: bool,
    maybe_font_data: ?[]const u8,
) !void {
    var diagram = try ClassParser.parse(allocator, source);
    defer diagram.deinit();

    if (is_svg_output) {
        try ClassSvgRender.renderClassToSVG(allocator, &diagram, output_file, null);
    } else {
        var maybe_font: ?Font = initFont(allocator, maybe_font_data);
        defer if (maybe_font) |*f| f.deinit();
        var font_ptr: ?*Font = if (maybe_font) |*f| f else null;
        _ = &font_ptr;
        try ClassPngRender.renderClassToPNG(allocator, &diagram, output_file, font_ptr);
    }
}

fn renderStateDiagramQuiet(
    allocator: std.mem.Allocator,
    source: []const u8,
    output_file: []const u8,
    is_svg_output: bool,
    maybe_font_data: ?[]const u8,
) !void {
    var diagram = try StateParser.parse(allocator, source);
    defer diagram.deinit();

    if (is_svg_output) {
        try StateSvgRender.renderStateToSVG(allocator, &diagram, output_file);
    } else {
        var maybe_font: ?Font = initFont(allocator, maybe_font_data);
        defer if (maybe_font) |*f| f.deinit();
        const font_ptr: ?*Font = if (maybe_font) |*f| f else null;
        try StatePngRender.renderStateToPNG(allocator, &diagram, output_file, font_ptr);
    }
}

fn renderJourneyDiagramQuiet(
    allocator: std.mem.Allocator,
    source: []const u8,
    output_file: []const u8,
    is_svg_output: bool,
    maybe_font_data: ?[]const u8,
) !void {
    var diagram = try JourneyParser.parse(allocator, source);
    defer diagram.deinit();

    if (is_svg_output) {
        try JourneySvgRender.renderJourneyToSVG(allocator, &diagram, output_file);
    } else {
        var maybe_font: ?Font = initFont(allocator, maybe_font_data);
        defer if (maybe_font) |*f| f.deinit();
        const font_ptr: ?*Font = if (maybe_font) |*f| f else null;
        try JourneyPngRender.renderJourneyToPNG(allocator, &diagram, output_file, font_ptr);
    }
}

fn renderErDiagramQuiet(
    allocator: std.mem.Allocator,
    source: []const u8,
    output_file: []const u8,
    is_svg_output: bool,
    maybe_font_data: ?[]const u8,
) !void {
    var diagram = try ErParser.parse(allocator, source);
    defer diagram.deinit();

    if (is_svg_output) {
        try ErSvgRender.renderErToSVG(allocator, &diagram, output_file);
    } else {
        var maybe_font: ?Font = initFont(allocator, maybe_font_data);
        defer if (maybe_font) |*f| f.deinit();
        const font_ptr: ?*Font = if (maybe_font) |*f| f else null;
        try ErPngRender.renderErToPNG(allocator, &diagram, output_file, font_ptr);
    }
}

fn renderGanttDiagramQuiet(
    allocator: std.mem.Allocator,
    source: []const u8,
    output_file: []const u8,
    is_svg_output: bool,
    maybe_font_data: ?[]const u8,
) !void {
    var diagram = try GanttParser.parse(allocator, source);
    defer diagram.deinit();

    if (is_svg_output) {
        try GanttSvgRender.renderGanttToSVG(allocator, &diagram, output_file);
    } else {
        var maybe_font: ?Font = initFont(allocator, maybe_font_data);
        defer if (maybe_font) |*f| f.deinit();
        const font_ptr: ?*Font = if (maybe_font) |*f| f else null;
        try GanttPngRender.renderGanttToPNG(allocator, &diagram, output_file, font_ptr);
    }
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
