const builtin = @import("builtin");
const std = @import("std");
const merrow = @import("merrow");

const Digraph = merrow.Digraph;
const NodeData = merrow.NodeData;
const NodeShape = merrow.NodeShape;
const EdgeData = merrow.EdgeData;
const GraphData = merrow.GraphData;
const LineStyle = merrow.LineStyle;
const dagre = merrow.layout.dagre;
const normalize = merrow.layout.normalize;
const Parser = merrow.flowchart.Parser;
const ClassParser = merrow.class.parser;
const ClassSvgRender = merrow.class.svg_render;
const ClassPngRender = merrow.class.png_render;
const ErParser = merrow.er.parser;
const ErSvgRender = merrow.er.svg_render;
const ErPngRender = merrow.er.png_render;
const StateParser = merrow.state.parser;
const StateSvgRender = merrow.state.svg_render;
const StatePngRender = merrow.state.png_render;
const SeqParser = merrow.sequence.parser.Parser;
const SeqLayout = merrow.sequence.seq_layout;
const SeqSvgRender = merrow.sequence.svg_render;
const SeqPngRender = merrow.sequence.png_render;
const graph_render = merrow.render.graph;
const svg_render = merrow.render.svg_render;
const commands = @import("commands.zig");
const Font = graph_render.Font;
const RenderConfig = graph_render.RenderConfig;
const LabelPlacement = graph_render.LabelPlacement;
const Vec2 = graph_render.Vec2;
const seq_model = merrow.sequence.model;
const class_model = merrow.class.model;
const er_model = merrow.er.model;
const state_model = merrow.state.model;

const Graph = Digraph(NodeData, EdgeData, GraphData);

const node_padding_h: f64 = 40.0;
const node_padding_v: f64 = 22.0;
const min_node_width: f64 = 84.0;
const min_node_height: f64 = 44.0;
const font_size: f32 = 16.0;
const max_label_width: f32 = 220.0;
const wrapped_text_safety_w: f64 = 12.0;
const c_allocator = std.heap.c_allocator;
const preview_raster_scale: f64 = 4.0;
const preview_page_target_width: u32 = 1800;
const preview_page_target_height: u32 = 1200;

const NodeSize = struct { w: f64, h: f64 };

const LoadedFont = struct {
    data: []u8,
    font: Font,

    fn deinit(self: *LoadedFont, allocator: std.mem.Allocator) void {
        self.font.deinit();
        allocator.free(self.data);
    }
};

pub const StudioColor = extern struct {
    r: u8,
    g: u8,
    b: u8,
    a: u8,
};

pub const StudioGraphType = enum(u32) {
    flowchart = 0,
    sequence = 1,
    class = 2,
    er = 3,
    state = 4,
};

pub const StudioPoint = extern struct {
    x: f64,
    y: f64,
};

pub const StudioSubgraph = extern struct {
    x: f64,
    y: f64,
    width: f64,
    height: f64,
    corner_radius: f64,
    fill: StudioColor,
    stroke: StudioColor,
    stroke_width: f32,
    title: [*c]const u8,
    title_x: f64,
    title_y: f64,
    title_font_size: f32,
    title_color: StudioColor,
};

pub const StudioNode = extern struct {
    shape: u32,
    x: f64,
    y: f64,
    width: f64,
    height: f64,
    fill: StudioColor,
    stroke: StudioColor,
    stroke_width: f32,
    label: [*c]const u8,
    label_color: StudioColor,
    label_font_size: f32,
    max_text_width: f64,
    subtitle: [*c]const u8,
    attributes_text: [*c]const u8,
    methods_text: [*c]const u8,
    body_fill: StudioColor,
    body_text_color: StudioColor,
};

pub const StudioEdge = extern struct {
    points: [*c]StudioPoint,
    point_count: usize,
    color: StudioColor,
    thickness: f32,
    line_style: u32,
    has_arrow: u8,
    has_source_arrow: u8,
    target_from: StudioPoint,
    target_tip: StudioPoint,
    source_from: StudioPoint,
    source_tip: StudioPoint,
};

pub const StudioEdgeLabel = extern struct {
    text: [*c]const u8,
    x: f64,
    y: f64,
    half_w: f64,
    half_h: f64,
    font_size: f32,
    color: StudioColor,
};

pub const StudioScene = extern struct {
    width: f64,
    height: f64,
    background: StudioColor,
    subgraphs: [*c]StudioSubgraph,
    subgraph_count: usize,
    nodes: [*c]StudioNode,
    node_count: usize,
    edges: [*c]StudioEdge,
    edge_count: usize,
    edge_labels: [*c]StudioEdgeLabel,
    edge_label_count: usize,
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
    title_position: u32,
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

const SceneBuffers = struct {
    subgraphs: std.ArrayListUnmanaged(StudioSubgraph) = .{},
    nodes: std.ArrayListUnmanaged(StudioNode) = .{},
    edges: std.ArrayListUnmanaged(StudioEdge) = .{},
    edge_labels: std.ArrayListUnmanaged(StudioEdgeLabel) = .{},

    fn deinit(self: *SceneBuffers, allocator: std.mem.Allocator) void {
        for (self.subgraphs.items) |item| freeCString(allocator, item.title);
        self.subgraphs.deinit(allocator);

        for (self.nodes.items) |item| freeCString(allocator, item.label);
        for (self.nodes.items) |item| {
            freeCString(allocator, item.subtitle);
            freeCString(allocator, item.attributes_text);
            freeCString(allocator, item.methods_text);
        }
        self.nodes.deinit(allocator);

        for (self.edges.items) |item| {
            if (item.points) |points| allocator.free(points[0..item.point_count]);
        }
        self.edges.deinit(allocator);

        for (self.edge_labels.items) |item| freeCString(allocator, item.text);
        self.edge_labels.deinit(allocator);
    }
};

const EditableGraphBuffers = struct {
    subgraphs: std.ArrayListUnmanaged(StudioEditableSubgraph) = .{},
    nodes: std.ArrayListUnmanaged(StudioEditableNode) = .{},
    edges: std.ArrayListUnmanaged(StudioEditableEdge) = .{},

    fn deinit(self: *EditableGraphBuffers, allocator: std.mem.Allocator) void {
        for (self.subgraphs.items) |item| {
            freeCString(allocator, item.id);
            freeCString(allocator, item.title);
            freeCString(allocator, item.parent_subgraph_id);
        }
        self.subgraphs.deinit(allocator);

        for (self.nodes.items) |item| {
            freeCString(allocator, item.id);
            freeCString(allocator, item.label);
            freeCString(allocator, item.subtitle);
            freeCString(allocator, item.attributes_text);
            freeCString(allocator, item.methods_text);
            freeCString(allocator, item.parent_subgraph_id);
        }
        self.nodes.deinit(allocator);

        for (self.edges.items) |item| {
            freeCString(allocator, item.source_id);
            freeCString(allocator, item.target_id);
            freeCString(allocator, item.label);
        }
        self.edges.deinit(allocator);
    }
};

fn studioColor(rgba: [4]u8) StudioColor {
    return .{ .r = rgba[0], .g = rgba[1], .b = rgba[2], .a = rgba[3] };
}

fn dupCString(allocator: std.mem.Allocator, text: []const u8) ![*c]const u8 {
    const buf = try allocator.alloc(u8, text.len + 1);
    @memcpy(buf[0..text.len], text);
    buf[text.len] = 0;
    return buf.ptr;
}

fn freeCString(allocator: std.mem.Allocator, text: [*c]const u8) void {
    if (text == null) return;
    const slice = std.mem.span(text);
    allocator.free(@constCast(text)[0 .. slice.len + 1]);
}

fn optionalCStringSlice(text: [*c]const u8) ?[]const u8 {
    if (text == null) return null;
    return std.mem.span(text);
}

fn studioColorRgba(color: StudioColor) [4]u8 {
    return .{ color.r, color.g, color.b, color.a };
}

fn copyCString(dst: [*]u8, dst_len: usize, text: []const u8) void {
    if (dst_len == 0) return;
    const n = @min(text.len, dst_len - 1);
    @memcpy(dst[0..n], text[0..n]);
    dst[n] = 0;
}

fn fileExists(path: []const u8) bool {
    std.fs.cwd().access(path, .{}) catch return false;
    return true;
}

fn resolveRepoPath(allocator: std.mem.Allocator, relative_path: []const u8) ![]u8 {
    if (fileExists(relative_path)) return allocator.dupe(u8, relative_path);

    var exe_dir_buf: [std.fs.max_path_bytes]u8 = undefined;
    const exe_dir = std.fs.selfExeDirPath(&exe_dir_buf) catch return error.FileNotFound;
    const prefixes = [_][]const u8{ "/../../", "/../", "/" };

    for (prefixes) |prefix| {
        const candidate = try std.fmt.allocPrint(allocator, "{s}{s}{s}", .{ exe_dir, prefix, relative_path });
        if (fileExists(candidate)) return candidate;
        allocator.free(candidate);
    }

    return error.FileNotFound;
}

fn loadFont(allocator: std.mem.Allocator) !?LoadedFont {
    const font_path = resolveRepoPath(allocator, "fonts/Lato-Regular.ttf") catch return null;
    defer allocator.free(font_path);

    const font_data = std.fs.cwd().readFileAlloc(allocator, font_path, 1024 * 1024) catch return null;
    errdefer allocator.free(font_data);

    const font = Font.initFromMemory(allocator, font_data) catch {
        allocator.free(font_data);
        return null;
    };

    return .{ .data = font_data, .font = font };
}

fn detectSequenceDiagram(source: []const u8) bool {
    var idx: usize = 0;
    while (idx < source.len and std.ascii.isWhitespace(source[idx])) : (idx += 1) {}

    const keyword = "sequenceDiagram";
    if (idx + keyword.len > source.len) return false;
    return std.mem.eql(u8, source[idx .. idx + keyword.len], keyword);
}

fn detectClassDiagram(source: []const u8) bool {
    return ClassParser.isClassDiagram(source);
}

fn detectErDiagram(source: []const u8) bool {
    return ErParser.isErDiagram(source);
}

fn detectStateDiagram(source: []const u8) bool {
    return StateParser.isStateDiagram(source);
}

fn rankDirFromText(text: []const u8) dagre.RankDir {
    if (std.mem.eql(u8, text, "LR")) return .LR;
    if (std.mem.eql(u8, text, "RL")) return .RL;
    if (std.mem.eql(u8, text, "BT")) return .BT;
    return .TB;
}

fn rankDirText(rankdir: dagre.RankDir) []const u8 {
    return switch (rankdir) {
        .LR => "LR",
        .RL => "RL",
        .BT => "BT",
        .TB => "TB",
    };
}

const RankedSegment = struct {
    from: []const u8,
    to: []const u8,
    a: Vec2,
    b: Vec2,
};

fn pointDistance(a: Vec2, b: Vec2) f64 {
    const dx = b.x - a.x;
    const dy = b.y - a.y;
    return @sqrt(dx * dx + dy * dy);
}

fn orientation(a: Vec2, b: Vec2, c: Vec2) f64 {
    return (b.x - a.x) * (c.y - a.y) - (b.y - a.y) * (c.x - a.x);
}

fn segmentsIntersect(a0: Vec2, a1: Vec2, b0: Vec2, b1: Vec2) bool {
    const epsilon = 0.001;
    const a_min_x = @min(a0.x, a1.x) - epsilon;
    const a_max_x = @max(a0.x, a1.x) + epsilon;
    const a_min_y = @min(a0.y, a1.y) - epsilon;
    const a_max_y = @max(a0.y, a1.y) + epsilon;
    const b_min_x = @min(b0.x, b1.x) - epsilon;
    const b_max_x = @max(b0.x, b1.x) + epsilon;
    const b_min_y = @min(b0.y, b1.y) - epsilon;
    const b_max_y = @max(b0.y, b1.y) + epsilon;

    if (a_max_x < b_min_x or b_max_x < a_min_x or a_max_y < b_min_y or b_max_y < a_min_y) {
        return false;
    }

    const o1 = orientation(a0, a1, b0);
    const o2 = orientation(a0, a1, b1);
    const o3 = orientation(b0, b1, a0);
    const o4 = orientation(b0, b1, a1);

    if (@abs(o1) <= epsilon or @abs(o2) <= epsilon or @abs(o3) <= epsilon or @abs(o4) <= epsilon) {
        return false;
    }

    return (o1 > 0) != (o2 > 0) and (o3 > 0) != (o4 > 0);
}

fn edgesShareEndpoint(a: RankedSegment, b: RankedSegment) bool {
    return std.mem.eql(u8, a.from, b.from) or
        std.mem.eql(u8, a.from, b.to) or
        std.mem.eql(u8, a.to, b.from) or
        std.mem.eql(u8, a.to, b.to);
}

fn layoutFlowchartForDirection(allocator: std.mem.Allocator, source: []const u8, rankdir: dagre.RankDir) !Graph {
    var parser = try Parser.init(allocator, source);
    defer parser.deinit();

    var graph = try parser.parse();
    errdefer {
        normalize.freeDummyIds(allocator, &graph);
        graph.deinitDeep();
    }

    const node_ids = try graph.allNodes(allocator);
    defer {
        for (node_ids) |id| allocator.free(id);
        allocator.free(node_ids);
    }

    for (node_ids) |id| {
        if (graph.getNodePtr(id)) |node| {
            if (node.width > 0 or node.is_subgraph) continue;
            const display_text = node.label orelse id;
            const size = estimateNodeSize(display_text, node.shape);
            node.width = size.w;
            node.height = size.h;
        }
    }

    graph.getGraphLabel().rankdir = rankDirText(rankdir);
    try dagre.layout(allocator, &graph, .{
        .rankdir = rankdir,
        .ranker = .network_simplex,
        .nodesep = 50,
        .ranksep = 50,
    });
    return graph;
}

fn scoreFlowchartDirection(allocator: std.mem.Allocator, source: []const u8, rankdir: dagre.RankDir) !f64 {
    var graph = try layoutFlowchartForDirection(allocator, source, rankdir);
    defer {
        normalize.freeDummyIds(allocator, &graph);
        graph.deinitDeep();
    }

    var segments = std.ArrayList(RankedSegment){};
    defer segments.deinit(allocator);

    var total_length: f64 = 0.0;
    var bend_penalty: f64 = 0.0;

    var edge_it = graph.edgeIterator();
    while (edge_it.next()) |entry| {
        const from_node = graph.getNode(entry.v) orelse continue;
        const to_node = graph.getNode(entry.w) orelse continue;
        if (from_node.dummy or to_node.dummy or std.mem.eql(u8, entry.v, entry.w)) continue;

        const edge_data = graph.edge(entry.v, entry.w, entry.name) orelse continue;
        if (edge_data.points.items.len >= 2) {
            for (edge_data.points.items[0 .. edge_data.points.items.len - 1], edge_data.points.items[1..]) |p0, p1| {
                const a = Vec2{ .x = p0.x, .y = p0.y };
                const b = Vec2{ .x = p1.x, .y = p1.y };
                total_length += pointDistance(a, b);
                if (pointDistance(a, b) > 0.01) {
                    try segments.append(allocator, .{ .from = entry.v, .to = entry.w, .a = a, .b = b });
                }
            }
            if (edge_data.points.items.len > 2) {
                bend_penalty += @as(f64, @floatFromInt(edge_data.points.items.len - 2)) * 120.0;
            }
        } else {
            const a = Vec2{ .x = from_node.x, .y = from_node.y };
            const b = Vec2{ .x = to_node.x, .y = to_node.y };
            total_length += pointDistance(a, b);
            if (pointDistance(a, b) > 0.01) {
                try segments.append(allocator, .{ .from = entry.v, .to = entry.w, .a = a, .b = b });
            }
        }
    }

    var crossing_count: usize = 0;
    for (segments.items, 0..) |lhs, i| {
        for (segments.items[i + 1 ..]) |rhs| {
            if (edgesShareEndpoint(lhs, rhs)) continue;
            if (segmentsIntersect(lhs.a, lhs.b, rhs.a, rhs.b)) crossing_count += 1;
        }
    }

    const bounds = try graph_render.calculateBounds(allocator, &graph, defaultRenderConfig());
    const safe_width = @max(bounds.width, 1.0);
    const safe_height = @max(bounds.height, 1.0);
    const aspect_ratio = @max(safe_width / safe_height, safe_height / safe_width);
    const aspect_penalty = (aspect_ratio - 1.0) * 180.0;

    return @as(f64, @floatFromInt(crossing_count)) * 100000.0 + bend_penalty + total_length + aspect_penalty;
}

fn currentFlowchartRankDir(allocator: std.mem.Allocator, source: []const u8) !dagre.RankDir {
    var parser = try Parser.init(allocator, source);
    defer parser.deinit();

    var graph = try parser.parse();
    defer {
        normalize.freeDummyIds(allocator, &graph);
        graph.deinitDeep();
    }

    return rankDirFromText(graph.getGraphLabel().rankdir);
}

fn bestShuffleDirection(allocator: std.mem.Allocator, source: []const u8) !dagre.RankDir {
    const candidates = [_]dagre.RankDir{ .TB, .LR, .BT, .RL };

    var best_dir: dagre.RankDir = .TB;
    var best_score = std.math.inf(f64);

    for (candidates) |candidate| {
        const score = try scoreFlowchartDirection(allocator, source, candidate);
        if (score < best_score) {
            best_score = score;
            best_dir = candidate;
        }
    }

    return best_dir;
}

fn createTempPreviewPath(allocator: std.mem.Allocator, suffix: []const u8) ![]u8 {
    const temp_dir = try getTempDirectoryPath(allocator);
    defer allocator.free(temp_dir);

    const stamp = @as(u64, @intCast(@abs(std.time.nanoTimestamp())));
    const file_name = try std.fmt.allocPrint(allocator, "merrow-studio-preview-{d}{s}", .{ stamp, suffix });
    defer allocator.free(file_name);

    return std.fs.path.join(allocator, &.{ temp_dir, file_name });
}

fn getTempDirectoryPath(allocator: std.mem.Allocator) ![]u8 {
    const env_vars = switch (builtin.os.tag) {
        .windows => [_][]const u8{ "TEMP", "TMP" },
        else => [_][]const u8{ "TMPDIR", "TMP", "TEMP" },
    };

    for (env_vars) |name| {
        return std.process.getEnvVarOwned(allocator, name) catch |err| switch (err) {
            error.EnvironmentVariableNotFound => continue,
            else => return err,
        };
    }

    return allocator.dupe(u8, switch (builtin.os.tag) {
        .windows => ".",
        else => "/tmp",
    });
}

fn renderSequenceDiagramToFile(
    allocator: std.mem.Allocator,
    source: []const u8,
    output_path: []const u8,
    is_svg_output: bool,
    maybe_font_data: ?[]const u8,
    raster_scale: f64,
) !void {
    var parser = SeqParser.init(allocator, source);
    var diagram = try parser.parse();
    defer diagram.deinit();

    const layout_config = SeqLayout.LayoutConfig{};
    const layout = SeqLayout.layout(&diagram, layout_config);

    if (is_svg_output) {
        const render_config = SeqSvgRender.SeqRenderConfig{};
        try SeqSvgRender.renderToSVGFile(allocator, &diagram, layout, output_path, layout_config, render_config);
        return;
    }

    var maybe_font: ?Font = if (maybe_font_data) |data|
        Font.initFromMemory(allocator, data) catch null
    else
        null;
    defer if (maybe_font) |*font| font.deinit();

    var render_config = SeqPngRender.SeqPngRenderConfig{};
    render_config.scale_factor = raster_scale;
    try SeqPngRender.renderToPNGFile(
        allocator,
        &diagram,
        layout,
        output_path,
        layout_config,
        render_config,
        if (maybe_font) |*font| font else null,
    );
}

fn renderSequenceDiagramToBytes(
    allocator: std.mem.Allocator,
    source: []const u8,
    maybe_font_data: ?[]const u8,
    raster_scale: f64,
) ![]u8 {
    var parser = SeqParser.init(allocator, source);
    var diagram = try parser.parse();
    defer diagram.deinit();

    const layout_config = SeqLayout.LayoutConfig{};
    const layout = SeqLayout.layout(&diagram, layout_config);

    var maybe_font: ?Font = if (maybe_font_data) |data|
        Font.initFromMemory(allocator, data) catch null
    else
        null;
    defer if (maybe_font) |*font| font.deinit();

    var render_config = SeqPngRender.SeqPngRenderConfig{};
    render_config.scale_factor = raster_scale;
    return SeqPngRender.renderToPNGBytes(
        allocator,
        &diagram,
        layout,
        layout_config,
        render_config,
        if (maybe_font) |*font| font else null,
    );
}

fn estimateNodeSize(label: []const u8, shape: NodeShape) NodeSize {
    const char_width: f64 = 8.0;
    const line_height: f64 = 20.0;
    const text_w = @as(f64, @floatFromInt(label.len)) * char_width;
    var w = @max(min_node_width, text_w + node_padding_h);
    var h = @max(min_node_height, line_height + node_padding_v);
    applyShapeScaling(&w, &h, shape);
    return .{ .w = w, .h = h };
}

fn measureNodeSize(font: *Font, label: []const u8, shape: NodeShape) NodeSize {
    const single_line_w = font.measureText(label, font_size);
    var text_w: f64 = undefined;
    var text_h: f64 = undefined;
    const wrap_width = maxWrapWidth(shape);

    if (single_line_w > wrap_width) {
        const wrapped = font.measureWrappedText(label, font_size, wrap_width) catch {
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

fn applyShapeScaling(w: *f64, h: *f64, shape: NodeShape) void {
    switch (shape) {
        .diamond => {
            w.* *= 1.45;
            h.* *= 1.45;
        },
        .hexagon => w.* *= 1.35,
        .circle => {
            w.* *= 1.3;
            h.* *= 1.3;
            const side = @max(w.*, h.*);
            w.* = side;
            h.* = side;
        },
        .stadium => w.* += h.* * 0.5,
        .cylinder => h.* *= 1.35,
        .trapezoid, .trapezoid_alt => w.* *= 1.25,
        .parallelogram, .parallelogram_alt => w.* *= 1.25,
        .subroutine => w.* += 24.0,
        .round, .box => {},
    }
}

fn maxWrapWidth(shape: NodeShape) f32 {
    return switch (shape) {
        .diamond, .circle => 180.0,
        .hexagon, .trapezoid, .trapezoid_alt, .parallelogram, .parallelogram_alt => 220.0,
        .box, .round, .cylinder, .stadium, .subroutine => max_label_width,
    };
}

fn lineStyleTag(style: LineStyle) u32 {
    return switch (style) {
        .solid => 0,
        .dashed => 1,
        .dotted => 2,
        .thick => 3,
    };
}

fn editableLineStyleTag(dashed: bool) u32 {
    return if (dashed) 1 else 0;
}

fn editableNodeShape(tag: u32) NodeShape {
    return switch (tag) {
        1 => .round,
        2 => .diamond,
        3 => .circle,
        4 => .hexagon,
        5 => .cylinder,
        6 => .stadium,
        7 => .trapezoid,
        8 => .trapezoid_alt,
        9 => .parallelogram,
        10 => .parallelogram_alt,
        11 => .subroutine,
        else => .box,
    };
}

fn editableLineStyle(tag: u32) LineStyle {
    return switch (tag) {
        1 => .dashed,
        2 => .dotted,
        3 => .thick,
        else => .solid,
    };
}

fn editableGraphEdgeHasTargetArrow(edge: StudioEditableEdge) bool {
    return edge.has_arrow != 0 or edge.target_end_style != 0;
}

fn editableGraphEdgeHasSourceArrow(edge: StudioEditableEdge) bool {
    return edge.has_source_arrow != 0 or edge.source_end_style != 0;
}

fn editableNodeText(allocator: std.mem.Allocator, node: StudioEditableNode) !struct {
    text: []const u8,
    owned: bool,
} {
    const base_text = blk: {
        const label = std.mem.span(node.label);
        if (label.len > 0) break :blk label;
        break :blk std.mem.span(node.id);
    };
    const subtitle = optionalCStringSlice(node.subtitle);
    const attributes = optionalCStringSlice(node.attributes_text);
    const methods = optionalCStringSlice(node.methods_text);

    if (subtitle == null and attributes == null and methods == null) {
        return .{ .text = base_text, .owned = false };
    }

    var buffer = std.ArrayList(u8){};
    errdefer buffer.deinit(allocator);

    try buffer.appendSlice(allocator, base_text);
    if (subtitle) |text| {
        if (text.len > 0) {
            try buffer.append(allocator, '\n');
            try buffer.appendSlice(allocator, text);
        }
    }
    if (attributes) |text| {
        if (text.len > 0) {
            try buffer.append(allocator, '\n');
            try buffer.appendSlice(allocator, text);
        }
    }
    if (methods) |text| {
        if (text.len > 0) {
            try buffer.append(allocator, '\n');
            try buffer.appendSlice(allocator, text);
        }
    }

    return .{ .text = try buffer.toOwnedSlice(allocator), .owned = true };
}

fn classRelationEndStyleTag(end_type: class_model.RelationEndType) u32 {
    return switch (end_type) {
        .none => 0,
        .extension => 1,
        .composition => 2,
        .aggregation => 3,
        .dependency => 4,
        .lollipop => 5,
    };
}

fn classLineStyleTag(line_type: class_model.LineType) u32 {
    return switch (line_type) {
        .solid => 0,
        .dotted => 2,
    };
}

fn erCardinalityEndStyleTag(cardinality: er_model.Cardinality) u32 {
    return switch (cardinality) {
        .only_one => 6,
        .zero_or_one => 7,
        .zero_or_more => 8,
        .one_or_more => 9,
    };
}

fn dupErEntitySubtitle(entity: *const er_model.Entity) !?[*c]const u8 {
    const alias = entity.alias orelse return null;
    if (alias.len == 0) return null;
    if (std.mem.eql(u8, alias, entity.label)) return null;
    return try dupCString(c_allocator, entity.label);
}

fn dupJoinedErAttributes(allocator: std.mem.Allocator, entity: *const er_model.Entity) !?[*c]const u8 {
    if (entity.attributes.items.len == 0) return null;

    var buffer = std.ArrayList(u8){};
    defer buffer.deinit(allocator);

    for (entity.attributes.items, 0..) |attr, idx| {
        if (idx > 0) try buffer.append(allocator, '\n');
        try buffer.appendSlice(allocator, attr.attr_type);
        try buffer.append(allocator, '\t');
        try buffer.appendSlice(allocator, attr.name);
        try buffer.append(allocator, '\t');

        for (attr.keys.items, 0..) |key, key_idx| {
            if (key_idx > 0) try buffer.append(allocator, ',');
            try buffer.appendSlice(allocator, key.asStr());
        }
    }

    return try dupCString(c_allocator, buffer.items);
}

const ErEditableEntityDimensions = struct {
    width: f64,
    height: f64,
};

const er_editable_margin: f64 = 50.0;
const er_editable_header_height: f64 = 42.75;
const er_editable_attr_row_height: f64 = 28.0;
const er_editable_entity_min_width: f64 = 120.0;
const er_editable_entity_padding: f64 = 12.0;
const er_editable_node_sep: f64 = 80.0;
const er_editable_rank_sep: f64 = 80.0;
const er_editable_char_width: f64 = 8.0;
const er_editable_attr_char_width: f64 = 7.2;

fn erEntityBoxSize(entity: *const er_model.Entity) ErEditableEntityDimensions {
    const display_name = entity.displayName();
    const name_width = @as(f64, @floatFromInt(display_name.len)) * er_editable_char_width + er_editable_entity_padding * 2.0;

    if (entity.attributes.items.len == 0) {
        return .{
            .width = @max(name_width, er_editable_entity_min_width),
            .height = er_editable_header_height,
        };
    }

    var type_max: f64 = 40.0;
    var name_max: f64 = 40.0;
    var key_max: f64 = 30.0;

    for (entity.attributes.items) |attr| {
        const type_width = @as(f64, @floatFromInt(attr.attr_type.len)) * er_editable_attr_char_width + er_editable_entity_padding * 2.0;
        if (type_width > type_max) type_max = type_width;

        const attr_name_width = @as(f64, @floatFromInt(attr.name.len)) * er_editable_attr_char_width + er_editable_entity_padding * 2.0;
        if (attr_name_width > name_max) name_max = attr_name_width;

        var key_len: usize = 0;
        for (attr.keys.items, 0..) |key, key_idx| {
            key_len += key.asStr().len;
            if (key_idx > 0) key_len += 1;
        }
        if (key_len > 0) {
            const key_width = @as(f64, @floatFromInt(key_len)) * er_editable_attr_char_width + er_editable_entity_padding * 2.0;
            if (key_width > key_max) key_max = key_width;
        }
    }

    return .{
        .width = @max(@max(type_max + name_max + key_max, name_width), er_editable_entity_min_width),
        .height = er_editable_header_height + @as(f64, @floatFromInt(entity.attributes.items.len)) * er_editable_attr_row_height,
    };
}

const ErEditablePosition = struct {
    x: f64,
    y: f64,
};

fn layoutErEntities(
    allocator: std.mem.Allocator,
    diagram: *const er_model.ErDiagram,
    sorted_names: []const []const u8,
    widths: *const std.StringHashMap(f64),
    heights: *const std.StringHashMap(f64),
    positions: *std.StringHashMap(ErEditablePosition),
) !void {
    if (sorted_names.len == 0) return;

    var connected_to = std.StringHashMap(std.ArrayListUnmanaged([]const u8)).init(allocator);
    defer {
        var iter = connected_to.iterator();
        while (iter.next()) |entry| {
            entry.value_ptr.deinit(allocator);
        }
        connected_to.deinit();
    }

    var in_rel = std.StringHashMap(bool).init(allocator);
    defer in_rel.deinit();

    for (diagram.relationships.items) |rel| {
        try in_rel.put(rel.entity_a, true);
        try in_rel.put(rel.entity_b, true);

        const entry = try connected_to.getOrPut(rel.entity_a);
        if (!entry.found_existing) entry.value_ptr.* = .{};
        try entry.value_ptr.append(allocator, rel.entity_b);
    }

    var layer_map = std.StringHashMap(usize).init(allocator);
    defer layer_map.deinit();

    var queue = std.ArrayListUnmanaged([]const u8){};
    defer queue.deinit(allocator);

    for (sorted_names) |name| {
        if (in_rel.contains(name) and !layer_map.contains(name)) {
            try layer_map.put(name, 0);
            try queue.append(allocator, name);

            var qi: usize = 0;
            while (qi < queue.items.len) : (qi += 1) {
                const current = queue.items[qi];
                const current_layer = layer_map.get(current) orelse 0;

                if (connected_to.getPtr(current)) |neighbors| {
                    for (neighbors.items) |neighbor| {
                        if (!layer_map.contains(neighbor)) {
                            try layer_map.put(neighbor, current_layer + 1);
                            try queue.append(allocator, neighbor);
                        }
                    }
                }
            }
        }
    }

    var max_layer: usize = 0;
    {
        var iter = layer_map.iterator();
        while (iter.next()) |entry| {
            if (entry.value_ptr.* > max_layer) max_layer = entry.value_ptr.*;
        }
    }

    for (sorted_names) |name| {
        if (!layer_map.contains(name)) {
            try layer_map.put(name, max_layer + 1);
        }
    }

    const total_layers = max_layer + 2;
    var layers = try allocator.alloc(std.ArrayListUnmanaged([]const u8), total_layers);
    defer {
        for (layers) |*layer| layer.deinit(allocator);
        allocator.free(layers);
    }
    for (layers) |*layer| layer.* = .{};

    for (sorted_names) |name| {
        const layer_index = layer_map.get(name) orelse 0;
        if (layer_index < total_layers) {
            try layers[layer_index].append(allocator, name);
        }
    }

    const is_horizontal = diagram.direction == .LR or diagram.direction == .RL;

    var layer_offset: f64 = 0.0;
    for (layers) |layer_entities| {
        if (layer_entities.items.len == 0) continue;

        var cross_offset: f64 = 0.0;
        var max_primary: f64 = 0.0;

        for (layer_entities.items) |name| {
            const width = widths.get(name) orelse er_editable_entity_min_width;
            const height = heights.get(name) orelse er_editable_header_height;

            if (is_horizontal) {
                try positions.put(name, .{ .x = layer_offset, .y = cross_offset });
                cross_offset += height + er_editable_node_sep;
                if (width > max_primary) max_primary = width;
            } else {
                try positions.put(name, .{ .x = cross_offset, .y = layer_offset });
                cross_offset += width + er_editable_node_sep;
                if (height > max_primary) max_primary = height;
            }
        }

        layer_offset += max_primary + er_editable_rank_sep;
    }
}

fn appendErEditableGraph(
    allocator: std.mem.Allocator,
    diagram: *const er_model.ErDiagram,
    buffers: *EditableGraphBuffers,
) !struct { width: f64, height: f64 } {
    const sorted_names = try diagram.sortedEntityNames();
    defer allocator.free(sorted_names);

    var entity_widths = std.StringHashMap(f64).init(allocator);
    defer entity_widths.deinit();
    var entity_heights = std.StringHashMap(f64).init(allocator);
    defer entity_heights.deinit();
    var positions = std.StringHashMap(ErEditablePosition).init(allocator);
    defer positions.deinit();

    for (sorted_names) |name| {
        const entity = diagram.getEntity(name) orelse continue;
        const dims = erEntityBoxSize(entity);
        try entity_widths.put(name, dims.width);
        try entity_heights.put(name, dims.height);
    }

    try layoutErEntities(allocator, diagram, sorted_names, &entity_widths, &entity_heights, &positions);

    var min_x: f64 = std.math.inf(f64);
    var min_y: f64 = std.math.inf(f64);
    var max_x: f64 = -std.math.inf(f64);
    var max_y: f64 = -std.math.inf(f64);

    for (sorted_names) |name| {
        const pos = positions.get(name) orelse continue;
        const width = entity_widths.get(name) orelse er_editable_entity_min_width;
        const height = entity_heights.get(name) orelse er_editable_header_height;
        if (pos.x < min_x) min_x = pos.x;
        if (pos.y < min_y) min_y = pos.y;
        if (pos.x + width > max_x) max_x = pos.x + width;
        if (pos.y + height > max_y) max_y = pos.y + height;
    }

    if (min_x == std.math.inf(f64) or min_y == std.math.inf(f64)) {
        min_x = 0.0;
        min_y = 0.0;
        max_x = 200.0;
        max_y = 120.0;
    }

    const offset_x = er_editable_margin - min_x;
    const offset_y = er_editable_margin - min_y;

    for (sorted_names) |name| {
        const entity = diagram.getEntity(name) orelse continue;
        const pos = positions.get(name) orelse continue;
        const width = entity_widths.get(name) orelse er_editable_entity_min_width;
        const height = entity_heights.get(name) orelse er_editable_header_height;
        try buffers.nodes.append(c_allocator, .{
            .id = try dupCString(c_allocator, name),
            .label = try dupCString(c_allocator, entity.displayName()),
            .subtitle = (try dupErEntitySubtitle(entity)) orelse null,
            .attributes_text = (try dupJoinedErAttributes(allocator, entity)) orelse null,
            .methods_text = null,
            .parent_subgraph_id = null,
            .shape = 0,
            .x = pos.x + offset_x + width / 2.0,
            .y = pos.y + offset_y + height / 2.0,
            .width = width,
            .height = height,
            .fill = studioColor(er_model.entity_header_fill),
            .body_fill = studioColor(er_model.entity_row_odd_fill),
            .stroke = studioColor(er_model.entity_stroke),
            .stroke_width = 1.5,
            .label_color = studioColor(er_model.entity_name_color),
            .label_font_size = 14.0,
        });
    }

    for (diagram.relationships.items) |rel| {
        try buffers.edges.append(c_allocator, .{
            .source_id = try dupCString(c_allocator, rel.entity_a),
            .target_id = try dupCString(c_allocator, rel.entity_b),
            .label = if (rel.role.len > 0) try dupCString(c_allocator, rel.role) else null,
            .label_font_size = 11.0,
            .color = studioColor(er_model.rel_line_color),
            .thickness = 1.5,
            .line_style = if (rel.rel_spec.rel_type == .non_identifying) 1 else 0,
            .has_arrow = 0,
            .has_source_arrow = 0,
            .source_end_style = erCardinalityEndStyleTag(rel.rel_spec.card_a),
            .target_end_style = erCardinalityEndStyleTag(rel.rel_spec.card_b),
        });
    }

    return .{
        .width = (max_x - min_x) + er_editable_margin * 2.0,
        .height = (max_y - min_y) + er_editable_margin * 2.0,
    };
}

fn classBoxSizeForEditable(cls: *const class_model.ClassNode) NodeSize {
    const char_width: f64 = 8.0;
    const header_char_width: f64 = 9.0;
    const line_height: f64 = 22.0;
    const section_pad: f64 = 8.0;
    const horiz_pad: f64 = 16.0;
    const min_box_width: f64 = 120.0;
    const min_box_height: f64 = 40.0;

    var header_lines: usize = 1;
    header_lines += cls.annotations.items.len;

    var max_text_width: f64 = 0.0;
    const name = cls.displayName();
    var name_width = @as(f64, @floatFromInt(name.len)) * header_char_width;
    if (cls.generic) |g| {
        name_width += @as(f64, @floatFromInt(g.len + 2)) * header_char_width;
    }
    if (name_width > max_text_width) max_text_width = name_width;

    for (cls.annotations.items) |ann| {
        const ann_width = (@as(f64, @floatFromInt(ann.len)) + 4.0) * char_width;
        if (ann_width > max_text_width) max_text_width = ann_width;
    }
    for (cls.members.items) |member| {
        const width = @as(f64, @floatFromInt(member.text.len)) * char_width;
        if (width > max_text_width) max_text_width = width;
    }
    for (cls.methods.items) |method| {
        const width = @as(f64, @floatFromInt(method.text.len)) * char_width;
        if (width > max_text_width) max_text_width = width;
    }

    const box_width = @max(min_box_width, max_text_width + horiz_pad * 2.0);

    var total_height: f64 = 0.0;
    total_height += @as(f64, @floatFromInt(header_lines)) * line_height + section_pad * 2.0;
    total_height += if (cls.members.items.len > 0)
        @as(f64, @floatFromInt(cls.members.items.len)) * line_height + section_pad * 2.0
    else
        section_pad * 2.0;
    total_height += if (cls.methods.items.len > 0)
        @as(f64, @floatFromInt(cls.methods.items.len)) * line_height + section_pad * 2.0
    else
        section_pad * 2.0;

    return .{ .w = box_width, .h = @max(min_box_height, total_height) };
}

fn dupJoinedClassAnnotations(allocator: std.mem.Allocator, cls: *const class_model.ClassNode) ![*c]const u8 {
    if (cls.annotations.items.len == 0) return null;

    var buffer = std.ArrayList(u8){};
    defer buffer.deinit(allocator);

    for (cls.annotations.items, 0..) |ann, idx| {
        if (idx > 0) try buffer.append(allocator, '\n');
        try buffer.appendSlice(allocator, "<<");
        try buffer.appendSlice(allocator, ann);
        try buffer.appendSlice(allocator, ">>");
    }

    return try dupCString(c_allocator, buffer.items);
}

fn joinedClassAnnotationsText(allocator: std.mem.Allocator, cls: *const class_model.ClassNode) !?[]u8 {
    if (cls.annotations.items.len == 0) return null;

    var buffer = std.ArrayList(u8){};
    defer buffer.deinit(allocator);

    for (cls.annotations.items, 0..) |ann, idx| {
        if (idx > 0) try buffer.append(allocator, '\n');
        try buffer.appendSlice(allocator, "<<");
        try buffer.appendSlice(allocator, ann);
        try buffer.appendSlice(allocator, ">>");
    }

    const text = try buffer.toOwnedSlice(allocator);
    return text;
}

fn joinedClassMembersTextOwned(allocator: std.mem.Allocator, items: []const class_model.ClassMember) !?[]u8 {
    if (items.len == 0) return null;

    var buffer = std.ArrayList(u8){};
    defer buffer.deinit(allocator);

    for (items, 0..) |item, idx| {
        if (idx > 0) try buffer.append(allocator, '\n');
        try buffer.appendSlice(allocator, item.text);
    }

    const text = try buffer.toOwnedSlice(allocator);
    return text;
}

fn dupJoinedClassMembers(allocator: std.mem.Allocator, items: []const class_model.ClassMember) ![*c]const u8 {
    if (items.len == 0) return null;

    var buffer = std.ArrayList(u8){};
    defer buffer.deinit(allocator);

    for (items, 0..) |item, idx| {
        if (idx > 0) try buffer.append(allocator, '\n');
        try buffer.appendSlice(allocator, item.text);
    }

    return try dupCString(c_allocator, buffer.items);
}

fn buildClassSceneFromSource(temp_allocator: std.mem.Allocator, source: []const u8) !*StudioScene {
    var diagram = try ClassParser.parse(temp_allocator, source);
    defer diagram.deinit();

    var graph = Graph.init(temp_allocator);
    defer {
        normalize.freeDummyIds(temp_allocator, &graph);
        graph.deinitDeep();
    }

    var class_ids = std.ArrayListUnmanaged([]const u8){};
    defer {
        for (class_ids.items) |id| temp_allocator.free(id);
        class_ids.deinit(temp_allocator);
    }

    var class_iter = diagram.classes.iterator();
    while (class_iter.next()) |entry| {
        const cls = entry.value_ptr;
        const id = entry.key_ptr.*;
        const size = classBoxSizeForEditable(cls);

        try graph.setNode(id, .{
            .label = id,
            .width = size.w,
            .height = size.h,
            .shape = .box,
            .fill_color = class_model.class_body_color,
            .stroke_color = class_model.class_border_color,
            .text_color = class_model.class_text_color,
            .stroke_width = 2,
        });
        try class_ids.append(temp_allocator, try temp_allocator.dupe(u8, id));
    }

    var graph_label = graph.getGraphLabel();
    graph_label.rankdir = diagram.direction;
    graph_label.nodesep = 60.0;
    graph_label.ranksep = 60.0;

    for (diagram.relations.items) |rel| {
        const edge_label = rel.label orelse "";
        try graph.setEdge(rel.id1, rel.id2, .{
            .label = if (edge_label.len > 0) edge_label else null,
            .minlen = 1,
            .line_style = if (rel.relation.line_type == .dotted) .dotted else .solid,
            .color = class_model.relation_color,
            .thickness = 2,
            .arrowhead = if (rel.relation.type2 != .none) "normal" else "none",
            .arrowtail = if (rel.relation.type1 != .none) "normal" else "none",
        }, null);
    }

    try dagre.layout(temp_allocator, &graph, .{
        .rankdir = rankDirFromText(diagram.direction),
        .ranker = .network_simplex,
        .nodesep = 60,
        .ranksep = 60,
    });

    var min_x: f64 = std.math.floatMax(f64);
    var min_y: f64 = std.math.floatMax(f64);
    var max_x: f64 = -std.math.floatMax(f64);
    var max_y: f64 = -std.math.floatMax(f64);

    for (class_ids.items) |id| {
        if (graph.getNode(id)) |node| {
            const left = node.x - node.width / 2.0;
            const right = node.x + node.width / 2.0;
            const top = node.y - node.height / 2.0;
            const bottom = node.y + node.height / 2.0;
            if (left < min_x) min_x = left;
            if (right > max_x) max_x = right;
            if (top < min_y) min_y = top;
            if (bottom > max_y) max_y = bottom;
        }
    }

    var edge_iter = graph.edgeIterator();
    while (edge_iter.next()) |entry| {
        for (entry.data.points.items) |pt| {
            if (pt.x < min_x) min_x = pt.x;
            if (pt.x > max_x) max_x = pt.x;
            if (pt.y < min_y) min_y = pt.y;
            if (pt.y > max_y) max_y = pt.y;
        }
    }

    if (min_x > max_x) {
        min_x = 0.0;
        min_y = 0.0;
        max_x = 200.0;
        max_y = 100.0;
    }

    const config = defaultRenderConfig();
    const offset_x = config.padding - min_x;
    const offset_y = config.padding - min_y;

    var buffers = SceneBuffers{};
    errdefer buffers.deinit(c_allocator);

    try appendEdges(temp_allocator, c_allocator, &graph, &buffers, null, offset_x, offset_y, config);

    for (class_ids.items) |id| {
        const node = graph.getNode(id) orelse continue;
        const cls = diagram.classes.getPtr(id) orelse continue;

        const subtitle_text = try joinedClassAnnotationsText(temp_allocator, cls);
        defer if (subtitle_text) |text| temp_allocator.free(text);

        const attributes_text = try joinedClassMembersTextOwned(temp_allocator, cls.members.items);
        defer if (attributes_text) |text| temp_allocator.free(text);

        const methods_text = try joinedClassMembersTextOwned(temp_allocator, cls.methods.items);
        defer if (methods_text) |text| temp_allocator.free(text);

        try buffers.nodes.append(c_allocator, .{
            .shape = 12,
            .x = node.x + offset_x,
            .y = node.y + offset_y,
            .width = node.width,
            .height = node.height,
            .fill = studioColor(class_model.class_header_color),
            .stroke = studioColor(class_model.class_border_color),
            .stroke_width = 2.0,
            .label = try dupCString(c_allocator, cls.displayName()),
            .label_color = studioColor(class_model.class_header_text_color),
            .label_font_size = 15.0,
            .max_text_width = @max(40.0, node.width - 32.0),
            .subtitle = if (subtitle_text) |text| try dupCString(c_allocator, text) else null,
            .attributes_text = if (attributes_text) |text| try dupCString(c_allocator, text) else null,
            .methods_text = if (methods_text) |text| try dupCString(c_allocator, text) else null,
            .body_fill = studioColor(class_model.class_body_color),
            .body_text_color = studioColor(class_model.class_text_color),
        });
    }

    return finalizeScene(c_allocator, &buffers, (max_x - min_x) + config.padding * 2.0, (max_y - min_y) + config.padding * 2.0);
}

fn appendClassEditableGraph(
    allocator: std.mem.Allocator,
    diagram: *const class_model.ClassDiagram,
    buffers: *EditableGraphBuffers,
) !struct { width: f64, height: f64 } {
    var graph = Graph.init(allocator);
    defer {
        normalize.freeDummyIds(allocator, &graph);
        graph.deinitDeep();
    }

    var class_ids = std.ArrayListUnmanaged([]const u8){};
    defer {
        for (class_ids.items) |id| allocator.free(id);
        class_ids.deinit(allocator);
    }

    var class_iter = diagram.classes.iterator();
    while (class_iter.next()) |entry| {
        const cls = entry.value_ptr;
        const id = entry.key_ptr.*;
        const size = classBoxSizeForEditable(cls);

        try graph.setNode(id, .{
            .label = cls.displayName(),
            .width = size.w,
            .height = size.h,
            .shape = .round,
        });
        try class_ids.append(allocator, try allocator.dupe(u8, id));
    }

    var graph_label = graph.getGraphLabel();
    graph_label.rankdir = diagram.direction;
    graph_label.nodesep = 60.0;
    graph_label.ranksep = 60.0;

    for (diagram.relations.items) |rel| {
        const edge_label = rel.label orelse "";
        try graph.setEdge(rel.id1, rel.id2, .{
            .label = if (edge_label.len > 0) edge_label else null,
            .minlen = 1,
        }, null);
    }

    try dagre.layout(allocator, &graph, .{
        .rankdir = rankDirFromText(diagram.direction),
        .ranker = .network_simplex,
        .nodesep = 60,
        .ranksep = 60,
    });

    var min_x: f64 = std.math.floatMax(f64);
    var min_y: f64 = std.math.floatMax(f64);
    var max_x: f64 = -std.math.floatMax(f64);
    var max_y: f64 = -std.math.floatMax(f64);

    for (class_ids.items) |id| {
        if (graph.getNode(id)) |node| {
            const left = node.x - node.width / 2.0;
            const right = node.x + node.width / 2.0;
            const top = node.y - node.height / 2.0;
            const bottom = node.y + node.height / 2.0;
            if (left < min_x) min_x = left;
            if (right > max_x) max_x = right;
            if (top < min_y) min_y = top;
            if (bottom > max_y) max_y = bottom;
        }
    }

    var edge_iter = graph.edgeIterator();
    while (edge_iter.next()) |entry| {
        for (entry.data.points.items) |pt| {
            if (pt.x < min_x) min_x = pt.x;
            if (pt.x > max_x) max_x = pt.x;
            if (pt.y < min_y) min_y = pt.y;
            if (pt.y > max_y) max_y = pt.y;
        }
    }

    if (min_x > max_x) {
        min_x = 0.0;
        min_y = 0.0;
        max_x = 200.0;
        max_y = 100.0;
    }

    const padding = 50.0;
    const offset_x = padding - min_x;
    const offset_y = padding - min_y;

    for (class_ids.items) |id| {
        const node = graph.getNode(id) orelse continue;
        const cls = diagram.classes.getPtr(id) orelse continue;
        try buffers.nodes.append(c_allocator, .{
            .id = try dupCString(c_allocator, id),
            .label = try dupCString(c_allocator, cls.displayName()),
            .subtitle = try dupJoinedClassAnnotations(allocator, cls),
            .attributes_text = try dupJoinedClassMembers(allocator, cls.members.items),
            .methods_text = try dupJoinedClassMembers(allocator, cls.methods.items),
            .parent_subgraph_id = null,
            .shape = 1,
            .x = node.x + offset_x,
            .y = node.y + offset_y,
            .width = node.width,
            .height = node.height,
            .fill = studioColor(class_model.class_header_color),
            .body_fill = studioColor(class_model.class_body_color),
            .stroke = studioColor(class_model.class_border_color),
            .stroke_width = 2.0,
            .label_color = studioColor(class_model.class_header_text_color),
            .label_font_size = 15.0,
        });
    }

    for (diagram.relations.items) |rel| {
        try buffers.edges.append(c_allocator, .{
            .source_id = try dupCString(c_allocator, rel.id1),
            .target_id = try dupCString(c_allocator, rel.id2),
            .label = if (rel.label) |text| if (text.len > 0) try dupCString(c_allocator, text) else null else null,
            .label_font_size = 11.0,
            .color = studioColor(class_model.relation_color),
            .thickness = 1.5,
            .line_style = classLineStyleTag(rel.relation.line_type),
            .has_arrow = if (rel.relation.type2 != .none) 1 else 0,
            .has_source_arrow = if (rel.relation.type1 != .none) 1 else 0,
            .source_end_style = classRelationEndStyleTag(rel.relation.type1),
            .target_end_style = classRelationEndStyleTag(rel.relation.type2),
        });
    }

    return .{
        .width = (max_x - min_x) + padding * 2.0,
        .height = (max_y - min_y) + padding * 2.0,
    };
}

fn nodeShapeTag(shape: NodeShape) u32 {
    return switch (shape) {
        .box => 0,
        .round => 1,
        .diamond => 2,
        .circle => 3,
        .hexagon => 4,
        .cylinder => 5,
        .stadium => 6,
        .trapezoid => 7,
        .trapezoid_alt => 8,
        .parallelogram => 9,
        .parallelogram_alt => 10,
        .subroutine => 11,
    };
}

fn sequenceParticipantShapeTag(kind: seq_model.ParticipantKind) u32 {
    return switch (kind) {
        .box => 1,
        .actor => 3,
    };
}

fn sequenceFragmentKindName(kind: seq_model.FragmentKind) []const u8 {
    return switch (kind) {
        .loop_block => "loop",
        .alt_block => "alt",
        .opt_block => "opt",
        .par_block => "par",
        .critical_block => "critical",
        .break_block => "break",
        .rect_block => "rect",
    };
}

fn sequenceFragmentParentId(
    allocator: std.mem.Allocator,
    diag: *const seq_model.SequenceDiagram,
    fragment_index: usize,
) !?[*c]const u8 {
    const frag = &diag.fragments.items[fragment_index];
    var best_parent: ?usize = null;
    var best_span: usize = std.math.maxInt(usize);

    for (diag.fragments.items, 0..) |*candidate, idx| {
        if (idx == fragment_index) continue;
        if (candidate.start_event > frag.start_event or candidate.end_event < frag.end_event) continue;

        const span = candidate.end_event - candidate.start_event;
        if (span >= best_span) continue;
        best_parent = idx;
        best_span = span;
    }

    if (best_parent) |parent_idx| {
        const id = try std.fmt.allocPrint(allocator, "fragment-{d}", .{parent_idx});
        defer allocator.free(id);
        return try dupCString(c_allocator, id);
    }
    return null;
}

fn appendSequenceEditableGraph(
    allocator: std.mem.Allocator,
    diag: *seq_model.SequenceDiagram,
    layout: SeqLayout.LayoutResult,
    buffers: *EditableGraphBuffers,
) !void {
    const participant_fill = studioColor(.{ 173, 216, 230, 255 });
    const participant_stroke = studioColor(.{ 70, 130, 180, 255 });
    const lifeline_color = studioColor(.{ 140, 140, 140, 255 });
    const note_fill = studioColor(.{ 255, 255, 210, 255 });
    const note_stroke = studioColor(.{ 200, 180, 80, 255 });
    const activation_fill = studioColor(.{ 173, 216, 230, 181 });
    const activation_stroke = studioColor(.{ 70, 130, 180, 255 });
    const fragment_fill = studioColor(.{ 240, 240, 245, 61 });
    const fragment_stroke = studioColor(.{ 100, 100, 100, 255 });
    const text_color = studioColor(.{ 40, 40, 40, 255 });
    const title_color = studioColor(.{ 60, 60, 60, 255 });
    const anchor_clear = studioColor(.{ 0, 0, 0, 0 });

    for (diag.fragments.items, 0..) |*frag, idx| {
        const fragment_id = try std.fmt.allocPrint(allocator, "fragment-{d}", .{idx});
        defer allocator.free(fragment_id);

        const fragment_kind_name = sequenceFragmentKindName(frag.kind);
        const first_label = if (frag.sections.items.len > 0) frag.sections.items[0].label else null;
        const title_text = if (first_label) |label|
            if (label.len > 0)
                try std.fmt.allocPrint(allocator, "{s} [{s}]", .{ fragment_kind_name, label })
            else
                try allocator.dupe(u8, fragment_kind_name)
        else
            try allocator.dupe(u8, fragment_kind_name);
        defer allocator.free(title_text);

        try buffers.subgraphs.append(c_allocator, .{
            .id = try dupCString(c_allocator, fragment_id),
            .title = try dupCString(c_allocator, title_text),
            .parent_subgraph_id = (try sequenceFragmentParentId(allocator, diag, idx)) orelse null,
            .x = frag.x,
            .y = frag.y,
            .width = frag.width,
            .height = frag.height,
            .corner_radius = 8.0,
            .fill = studioColor(frag.bg_color orelse .{ fragment_fill.r, fragment_fill.g, fragment_fill.b, fragment_fill.a }),
            .stroke = fragment_stroke,
            .stroke_width = 1.5,
            .title_x = frag.x + 12.0,
            .title_y = frag.y + 16.0,
            .title_font_size = 12.0,
            .title_color = title_color,
            .title_position = 0,
        });
    }

    for (diag.participants.items) |*participant| {
        try buffers.nodes.append(c_allocator, .{
            .id = try dupCString(c_allocator, participant.id),
            .label = try dupCString(c_allocator, participant.displayName()),
            .subtitle = null,
            .attributes_text = null,
            .methods_text = null,
            .parent_subgraph_id = null,
            .shape = sequenceParticipantShapeTag(participant.kind),
            .x = participant.center_x,
            .y = layout.header_y + participant.box_height / 2.0,
            .width = participant.box_width,
            .height = participant.box_height,
            .fill = participant_fill,
            .body_fill = participant_fill,
            .stroke = participant_stroke,
            .stroke_width = 2.0,
            .label_color = text_color,
            .label_font_size = 14.0,
        });

        const footer_participant_id = try std.fmt.allocPrint(allocator, "{s}-footer", .{participant.id});
        defer allocator.free(footer_participant_id);

        try buffers.nodes.append(c_allocator, .{
            .id = try dupCString(c_allocator, footer_participant_id),
            .label = try dupCString(c_allocator, participant.displayName()),
            .subtitle = null,
            .attributes_text = null,
            .methods_text = null,
            .parent_subgraph_id = null,
            .shape = sequenceParticipantShapeTag(participant.kind),
            .x = participant.center_x,
            .y = layout.footer_y + participant.box_height / 2.0,
            .width = participant.box_width,
            .height = participant.box_height,
            .fill = participant_fill,
            .body_fill = participant_fill,
            .stroke = participant_stroke,
            .stroke_width = 2.0,
            .label_color = text_color,
            .label_font_size = 14.0,
        });

        try buffers.edges.append(c_allocator, .{
            .source_id = try dupCString(c_allocator, participant.id),
            .target_id = try dupCString(c_allocator, footer_participant_id),
            .label = null,
            .label_font_size = 11.0,
            .color = lifeline_color,
            .thickness = 1.0,
            .line_style = editableLineStyleTag(true),
            .has_arrow = 0,
            .has_source_arrow = 0,
            .source_end_style = 0,
            .target_end_style = 0,
        });
    }

    for (diag.notes.items, 0..) |*note, idx| {
        const note_id = try std.fmt.allocPrint(allocator, "note-{d}", .{idx});
        defer allocator.free(note_id);

        const x = switch (note.position) {
            .left_of => diag.participants.items[note.participant1].center_x - note.width / 2.0 - 48.0,
            .right_of => diag.participants.items[note.participant1].center_x + note.width / 2.0 + 48.0,
            .over => (diag.participants.items[note.participant1].center_x + diag.participants.items[note.participant2].center_x) / 2.0,
        };

        try buffers.nodes.append(c_allocator, .{
            .id = try dupCString(c_allocator, note_id),
            .label = try dupCString(c_allocator, note.text orelse ""),
            .subtitle = null,
            .attributes_text = null,
            .methods_text = null,
            .parent_subgraph_id = null,
            .shape = 1,
            .x = x,
            .y = note.y,
            .width = note.width,
            .height = note.height,
            .fill = note_fill,
            .body_fill = note_fill,
            .stroke = note_stroke,
            .stroke_width = 1.0,
            .label_color = studioColor(.{ 50, 50, 50, 255 }),
            .label_font_size = 12.0,
        });
    }

    for (diag.activations.items, 0..) |*activation, idx| {
        const activation_id = try std.fmt.allocPrint(allocator, "activation-{d}", .{idx});
        defer allocator.free(activation_id);
        const participant = &diag.participants.items[activation.participant];
        const height = @max(activation.end_y - activation.start_y, 20.0);
        const x = participant.center_x + @as(f64, @floatFromInt(activation.depth)) * 6.0;

        try buffers.nodes.append(c_allocator, .{
            .id = try dupCString(c_allocator, activation_id),
            .label = null,
            .subtitle = null,
            .attributes_text = null,
            .methods_text = null,
            .parent_subgraph_id = null,
            .shape = 0,
            .x = x,
            .y = activation.start_y + height / 2.0,
            .width = 16.0,
            .height = height,
            .fill = activation_fill,
            .body_fill = activation_fill,
            .stroke = activation_stroke,
            .stroke_width = 1.5,
            .label_color = text_color,
            .label_font_size = 10.0,
        });
    }

    for (diag.messages.items, 0..) |*message, idx| {
        const source_participant = &diag.participants.items[message.from];
        const target_participant = &diag.participants.items[message.to];

        const source_anchor_id = if (message.isSelfMessage())
            try std.fmt.allocPrint(allocator, "message-{d}-anchor", .{idx})
        else
            try std.fmt.allocPrint(allocator, "message-{d}-from", .{idx});
        defer allocator.free(source_anchor_id);

        try buffers.nodes.append(c_allocator, .{
            .id = try dupCString(c_allocator, source_anchor_id),
            .label = null,
            .subtitle = null,
            .attributes_text = null,
            .methods_text = null,
            .parent_subgraph_id = null,
            .shape = 0,
            .x = source_participant.center_x,
            .y = message.y,
            .width = 8.0,
            .height = 8.0,
            .fill = anchor_clear,
            .body_fill = anchor_clear,
            .stroke = anchor_clear,
            .stroke_width = 0.0,
            .label_color = anchor_clear,
            .label_font_size = 10.0,
        });

        const target_anchor_id = if (message.isSelfMessage()) blk: {
            break :blk source_anchor_id;
        } else blk: {
            const value = try std.fmt.allocPrint(allocator, "message-{d}-to", .{idx});
            errdefer allocator.free(value);
            try buffers.nodes.append(c_allocator, .{
                .id = try dupCString(c_allocator, value),
                .label = null,
                .subtitle = null,
                .attributes_text = null,
                .methods_text = null,
                .parent_subgraph_id = null,
                .shape = 0,
                .x = target_participant.center_x,
                .y = message.y,
                .width = 8.0,
                .height = 8.0,
                .fill = anchor_clear,
                .body_fill = anchor_clear,
                .stroke = anchor_clear,
                .stroke_width = 0.0,
                .label_color = anchor_clear,
                .label_font_size = 10.0,
            });
            break :blk value;
        };
        defer if (!message.isSelfMessage()) allocator.free(target_anchor_id);

        try buffers.edges.append(c_allocator, .{
            .source_id = try dupCString(c_allocator, source_anchor_id),
            .target_id = try dupCString(c_allocator, target_anchor_id),
            .label = if (message.text) |text| try dupCString(c_allocator, text) else null,
            .label_font_size = 11.0,
            .color = studioColor(.{ 60, 60, 60, 255 }),
            .thickness = 2.0,
            .line_style = editableLineStyleTag(message.arrow_type.isDashed()),
            .has_arrow = if (message.arrow_type.hasArrowhead() or message.arrow_type.isOpenArrow()) 1 else 0,
            .has_source_arrow = 0,
            .source_end_style = 0,
            .target_end_style = if (message.arrow_type.hasArrowhead() or message.arrow_type.isOpenArrow()) classRelationEndStyleTag(.dependency) else 0,
        });
    }
}

fn defaultRenderConfig() RenderConfig {
    return .{
        .padding = 40.0,
        .scale_factor = 1.0,
        .node_fill_color = .{ 240, 240, 250, 255 },
        .node_stroke_color = .{ 100, 100, 150, 255 },
        .node_stroke_width = 2,
        .edge_color = .{ 80, 80, 80, 255 },
        .edge_width = 2,
        .text_color = .{ 40, 40, 40, 255 },
        .text_size = font_size,
    };
}

fn scaledStrokeWidth(value: i32, scale: f64) i32 {
    return @max(1, @as(i32, @intFromFloat(@round(@as(f64, @floatFromInt(value)) * scale))));
}

fn scaledTextSize(value: f32, scale: f64) f32 {
    return @floatCast(@as(f64, @floatCast(value)) * scale);
}

fn exportRenderConfig(layout_scale: f64, raster_scale: f64) RenderConfig {
    var config = defaultRenderConfig();
    config.padding *= layout_scale;
    config.scale_factor = raster_scale;
    config.node_stroke_width = scaledStrokeWidth(config.node_stroke_width, layout_scale);
    config.edge_width = scaledStrokeWidth(config.edge_width, layout_scale);
    config.subgraph_stroke_width = scaledStrokeWidth(config.subgraph_stroke_width, layout_scale);
    config.text_size = scaledTextSize(config.text_size, layout_scale);
    config.arrow_size *= layout_scale;
    config.subgraph_corner_radius *= layout_scale;
    return config;
}

fn layoutScaleForTargetCanvas(base_pixel_width: f64, base_pixel_height: f64, target_width: u32, target_height: u32) f64 {
    if (target_width == 0 or target_height == 0) return 1.0;
    if (base_pixel_width <= 1.0 or base_pixel_height <= 1.0) return 1.0;

    const target_w = @as(f64, @floatFromInt(target_width));
    const target_h = @as(f64, @floatFromInt(target_height));
    const fit = @min(target_w / base_pixel_width, target_h / base_pixel_height);
    return std.math.clamp(fit, 0.25, 8.0);
}

fn downscaleForTargetCanvas(base_pixel_width: f64, base_pixel_height: f64, target_width: u32, target_height: u32) f64 {
    if (target_width == 0 or target_height == 0) return 1.0;
    if (base_pixel_width <= 1.0 or base_pixel_height <= 1.0) return 1.0;

    const target_w = @as(f64, @floatFromInt(target_width));
    const target_h = @as(f64, @floatFromInt(target_height));
    const fit = @min(target_w / base_pixel_width, target_h / base_pixel_height);
    return std.math.clamp(@min(fit, 1.0), 0.25, 1.0);
}

fn scaleGraphGeometry(temp_allocator: std.mem.Allocator, graph: *Graph, scale: f64) !void {
    if (@abs(scale - 1.0) < 0.001) return;

    const node_ids = try graph.allNodes(temp_allocator);
    defer {
        for (node_ids) |id| temp_allocator.free(id);
        temp_allocator.free(node_ids);
    }

    for (node_ids) |id| {
        if (graph.getNodePtr(id)) |node| {
            node.x *= scale;
            node.y *= scale;
            node.width *= scale;
            node.height *= scale;
        }
    }

    var edge_it = graph.edgeIterator();
    while (edge_it.next()) |entry| {
        if (graph.getEdgePtr(entry.v, entry.w, entry.name)) |edge| {
            edge.width *= scale;
            edge.height *= scale;
            edge.x *= scale;
            edge.y *= scale;
            for (edge.points.items) |*point| {
                point.x *= scale;
                point.y *= scale;
            }
        }
    }
}

fn measureTextWidth(maybe_font: ?*Font, text: []const u8, size: f32) f32 {
    if (maybe_font) |font| return font.measureText(text, size);
    return @as(f32, @floatFromInt(text.len)) * size * 0.56;
}

fn pointSliceToOwned(allocator: std.mem.Allocator, points: []const Vec2) ![*c]StudioPoint {
    const buf = try allocator.alloc(StudioPoint, points.len);
    for (points, 0..) |point, idx| {
        buf[idx] = .{ .x = point.x, .y = point.y };
    }
    return buf.ptr;
}

fn edgeThickness(base: i32, style: LineStyle) i32 {
    return if (style == .thick) @max(base * 2, 3) else base;
}

fn appendSubgraphs(temp_allocator: std.mem.Allocator, scene_allocator: std.mem.Allocator, graph: *Graph, buffers: *SceneBuffers, offset_x: f64, offset_y: f64, config: RenderConfig) !void {
    const nodes = try graph.allNodes(temp_allocator);
    defer {
        for (nodes) |id| temp_allocator.free(id);
        temp_allocator.free(nodes);
    }

    const Entry = struct { id: []const u8, depth: usize };
    var subgraphs = std.ArrayListUnmanaged(Entry){};
    defer subgraphs.deinit(temp_allocator);

    for (nodes) |id| {
        const node = graph.getNode(id) orelse continue;
        if (!node.is_subgraph or node.width < 0.1) continue;

        var depth: usize = 0;
        var cursor: ?[]const u8 = graph.getParent(id);
        while (cursor) |parent_id| {
            depth += 1;
            cursor = graph.getParent(parent_id);
        }

        try subgraphs.append(temp_allocator, .{ .id = id, .depth = depth });
    }

    std.mem.sort(Entry, subgraphs.items, {}, struct {
        fn lessThan(_: void, a: Entry, b: Entry) bool {
            return a.depth < b.depth;
        }
    }.lessThan);

    const depth_tints = [_][4]u8{
        .{ 245, 245, 250, 255 },
        .{ 235, 240, 250, 255 },
        .{ 225, 235, 248, 255 },
        .{ 218, 228, 245, 255 },
    };

    for (subgraphs.items) |entry| {
        const node = graph.getNode(entry.id) orelse continue;
        const title = node.subgraph_title orelse (node.label orelse entry.id);
        const tint_idx = @min(entry.depth, depth_tints.len - 1);

        try buffers.subgraphs.append(scene_allocator, .{
            .x = node.x + offset_x - node.width / 2.0,
            .y = node.y + offset_y - node.height / 2.0,
            .width = node.width,
            .height = node.height,
            .corner_radius = config.subgraph_corner_radius,
            .fill = studioColor(depth_tints[tint_idx]),
            .stroke = studioColor(config.subgraph_stroke_color),
            .stroke_width = @floatFromInt(config.subgraph_stroke_width),
            .title = if (title.len > 0) try dupCString(scene_allocator, title) else null,
            .title_x = node.x + offset_x - node.width / 2.0 + config.subgraph_corner_radius + 6.0,
            .title_y = node.y + offset_y - node.height / 2.0 + 16.0,
            .title_font_size = config.text_size * 0.9,
            .title_color = studioColor(config.subgraph_title_color),
        });
    }
}

fn appendNodes(temp_allocator: std.mem.Allocator, scene_allocator: std.mem.Allocator, graph: *Graph, buffers: *SceneBuffers, offset_x: f64, offset_y: f64, config: RenderConfig) !void {
    const nodes = try graph.allNodes(temp_allocator);
    defer {
        for (nodes) |id| temp_allocator.free(id);
        temp_allocator.free(nodes);
    }

    for (nodes) |id| {
        const node = graph.getNode(id) orelse continue;
        if (node.dummy or node.is_subgraph) continue;

        const fill_color = node.fill_color orelse config.node_fill_color;
        const stroke_color = node.stroke_color orelse config.node_stroke_color;
        const label_color = node.text_color orelse config.text_color;
        const display_text = node.label orelse id;
        const shape_shrink: f64 = switch (node.shape) {
            .diamond => 0.55,
            .hexagon => 0.65,
            .circle => 0.65,
            .trapezoid, .trapezoid_alt => 0.70,
            .parallelogram, .parallelogram_alt => 0.70,
            .subroutine => 0.75,
            .cylinder => 0.80,
            .stadium => 0.80,
            .round, .box => 1.0,
        };
        const max_text_w = @max(40.0, (node.width - 16.0) * shape_shrink);

        try buffers.nodes.append(scene_allocator, .{
            .shape = nodeShapeTag(node.shape),
            .x = node.x + offset_x,
            .y = node.y + offset_y,
            .width = node.width,
            .height = node.height,
            .fill = studioColor(fill_color),
            .stroke = studioColor(stroke_color),
            .stroke_width = @floatFromInt(node.stroke_width orelse config.node_stroke_width),
            .label = if (display_text.len > 0) try dupCString(scene_allocator, display_text) else null,
            .label_color = studioColor(label_color),
            .label_font_size = config.text_size,
            .max_text_width = max_text_w,
            .subtitle = null,
            .attributes_text = null,
            .methods_text = null,
            .body_fill = studioColor(fill_color),
            .body_text_color = studioColor(label_color),
        });
    }
}

fn appendEdgeLabel(scene_allocator: std.mem.Allocator, buffers: *SceneBuffers, label: LabelPlacement) !void {
    try buffers.edge_labels.append(scene_allocator, .{
        .text = try dupCString(scene_allocator, label.text),
        .x = label.x,
        .y = label.y,
        .half_w = label.half_w,
        .half_h = label.half_h,
        .font_size = label.font_size,
        .color = studioColor(label.color),
    });
}

fn appendSelfEdge(temp_allocator: std.mem.Allocator, scene_allocator: std.mem.Allocator, buffers: *SceneBuffers, v_node: NodeData, edge_data: ?EdgeData, maybe_font: ?*Font, offset_x: f64, offset_y: f64, config: RenderConfig, label_placements: *std.ArrayListUnmanaged(LabelPlacement)) !void {
    const edge_color = if (edge_data) |ed| ed.color orelse config.edge_color else config.edge_color;
    const line_style = if (edge_data) |ed| ed.line_style else LineStyle.solid;
    const thickness = edgeThickness(if (edge_data) |ed| ed.thickness orelse config.edge_width else config.edge_width, line_style);
    const has_arrow = if (edge_data) |ed| blk: {
        if (ed.arrowhead) |ah| break :blk !std.mem.eql(u8, ah, "none");
        break :blk true;
    } else true;

    const cx = v_node.x + offset_x;
    const cy = v_node.y + offset_y;
    const hw = v_node.width / 2.0;
    const hh = v_node.height / 2.0;
    const loop_offset_x = @max(hw * 0.6, 20.0);
    const loop_offset_y = @max(hh * 0.6, 15.0);
    const start_x = cx + hw;
    const start_y = cy - loop_offset_y;
    const end_x = cx + hw;
    const end_y = cy + loop_offset_y;
    const bulge_x = cx + hw + loop_offset_x;

    const num_segments: usize = 20;
    var points = std.ArrayListUnmanaged(Vec2){};
    defer points.deinit(temp_allocator);
    try points.ensureTotalCapacity(temp_allocator, num_segments + 1);

    for (0..num_segments + 1) |idx| {
        const t = @as(f64, @floatFromInt(idx)) / @as(f64, @floatFromInt(num_segments));
        const angle = -std.math.pi / 2.0 + t * std.math.pi;
        const px = cx + hw + loop_offset_x * @cos(angle) * @cos(angle);
        const py = cy + (loop_offset_y + loop_offset_x * 0.3) * @sin(angle);
        const border_pull = 1.0 - 4.0 * (t - 0.5) * (t - 0.5);
        const final_x = start_x + (px - start_x) * border_pull + (bulge_x - start_x) * border_pull * 0.3;
        points.appendAssumeCapacity(.{ .x = final_x, .y = py });
    }

    points.items[0] = .{ .x = start_x, .y = start_y };
    points.items[num_segments] = .{ .x = end_x, .y = end_y };

    var target_tip = StudioPoint{ .x = end_x, .y = end_y };
    var target_from = StudioPoint{ .x = end_x, .y = end_y };
    if (has_arrow and points.items.len >= 2) {
        const last_idx = points.items.len - 1;
        target_tip = .{ .x = points.items[last_idx].x, .y = points.items[last_idx].y };
        target_from = .{ .x = points.items[last_idx - 1].x, .y = points.items[last_idx - 1].y };
        graph_render.shortenPolylineEnd(&points, config.arrow_size);
    }

    try buffers.edges.append(scene_allocator, .{
        .points = try pointSliceToOwned(scene_allocator, points.items),
        .point_count = points.items.len,
        .color = studioColor(edge_color),
        .thickness = @floatFromInt(thickness),
        .line_style = lineStyleTag(line_style),
        .has_arrow = if (has_arrow) 1 else 0,
        .has_source_arrow = 0,
        .target_from = target_from,
        .target_tip = target_tip,
        .source_from = .{ .x = 0, .y = 0 },
        .source_tip = .{ .x = 0, .y = 0 },
    });

    if (edge_data) |ed| {
        if (ed.label) |label_text| {
            if (label_text.len > 0) {
                const label_font_size = config.text_size * 0.85;
                const text_w = measureTextWidth(maybe_font, label_text, label_font_size);
                try label_placements.append(temp_allocator, .{
                    .text = label_text,
                    .x = bulge_x + 8.0,
                    .y = cy,
                    .orig_x = bulge_x + 8.0,
                    .orig_y = cy,
                    .half_w = @as(f64, @floatCast(text_w)) / 2.0 + 4.0,
                    .half_h = @as(f64, @floatCast(label_font_size * 1.3)) / 2.0 + 2.0,
                    .tangent_x = 0.0,
                    .tangent_y = 1.0,
                    .font_size = label_font_size,
                    .color = config.text_color,
                });
            }
        }
    }
}

fn appendEdges(temp_allocator: std.mem.Allocator, scene_allocator: std.mem.Allocator, graph: *Graph, buffers: *SceneBuffers, maybe_font: ?*Font, offset_x: f64, offset_y: f64, config: RenderConfig) !void {
    var label_placements = std.ArrayListUnmanaged(LabelPlacement){};
    defer label_placements.deinit(temp_allocator);

    var iter = graph.edgeIterator();
    while (iter.next()) |entry| {
        const v_node = graph.getNode(entry.v) orelse continue;
        if (v_node.dummy) continue;

        const edge_data = graph.edge(entry.v, entry.w, entry.name);
        if (std.mem.eql(u8, entry.v, entry.w)) {
            try appendSelfEdge(temp_allocator, scene_allocator, buffers, v_node, edge_data, maybe_font, offset_x, offset_y, config, &label_placements);
            continue;
        }

        var waypoints = std.ArrayListUnmanaged(Vec2){};
        defer waypoints.deinit(temp_allocator);

        try waypoints.append(temp_allocator, .{ .x = v_node.x + offset_x, .y = v_node.y + offset_y });

        var current_target: []const u8 = entry.w;
        while (true) {
            const t_node = graph.getNode(current_target) orelse break;
            if (!t_node.dummy) {
                try waypoints.append(temp_allocator, .{ .x = t_node.x + offset_x, .y = t_node.y + offset_y });
                break;
            }
            try waypoints.append(temp_allocator, .{ .x = t_node.x + offset_x, .y = t_node.y + offset_y });
            const next = graph_render.nextInChain(graph, current_target) orelse break;
            current_target = next;
        }

        if (waypoints.items.len < 2) continue;

        if (edge_data) |ed| {
            if (ed.points.items.len >= 2) {
                waypoints.clearRetainingCapacity();
                for (ed.points.items) |pt| {
                    try waypoints.append(temp_allocator, .{ .x = pt.x + offset_x, .y = pt.y + offset_y });
                }
            }
        }

        const src_center = waypoints.items[0];
        const src_next = waypoints.items[1];
        waypoints.items[0] = graph_render.clipLineToShape(src_next, src_center, src_center.x, src_center.y, v_node.width / 2.0, v_node.height / 2.0, v_node.shape);

        const last_idx = waypoints.items.len - 1;
        if (graph.getNode(current_target)) |tgt_node| {
            if (!tgt_node.dummy) {
                const tgt_center = waypoints.items[last_idx];
                const prev = waypoints.items[last_idx - 1];
                waypoints.items[last_idx] = graph_render.clipLineToShape(prev, tgt_center, tgt_center.x, tgt_center.y, tgt_node.width / 2.0, tgt_node.height / 2.0, tgt_node.shape);
            }
        }

        const edge_color = if (edge_data) |ed| ed.color orelse config.edge_color else config.edge_color;
        const line_style = if (edge_data) |ed| ed.line_style else LineStyle.solid;
        const thickness = edgeThickness(if (edge_data) |ed| ed.thickness orelse config.edge_width else config.edge_width, line_style);
        const has_arrow = if (edge_data) |ed| blk: {
            if (ed.arrowhead) |ah| break :blk !std.mem.eql(u8, ah, "none");
            break :blk true;
        } else true;
        const has_source_arrow = if (edge_data) |ed| blk: {
            if (ed.arrowtail) |at| break :blk !std.mem.eql(u8, at, "none");
            break :blk false;
        } else false;

        const has_explicit_route = if (edge_data) |ed| ed.points.items.len >= 2 else false;
        var smooth = std.ArrayListUnmanaged(Vec2){};
        defer smooth.deinit(temp_allocator);
        if (has_explicit_route) {
            try smooth.appendSlice(temp_allocator, waypoints.items);
        } else {
            smooth = try graph_render.tessellateSpline(temp_allocator, waypoints.items);
        }

        var target_tip = StudioPoint{ .x = 0, .y = 0 };
        var target_from = StudioPoint{ .x = 0, .y = 0 };
        var source_tip = StudioPoint{ .x = 0, .y = 0 };
        var source_from = StudioPoint{ .x = 0, .y = 0 };

        if (has_arrow and smooth.items.len >= 2) {
            const idx = smooth.items.len - 1;
            target_tip = .{ .x = smooth.items[idx].x, .y = smooth.items[idx].y };
            target_from = .{ .x = smooth.items[idx - 1].x, .y = smooth.items[idx - 1].y };
        }
        if (has_source_arrow and smooth.items.len >= 2) {
            source_tip = .{ .x = smooth.items[0].x, .y = smooth.items[0].y };
            source_from = .{ .x = smooth.items[1].x, .y = smooth.items[1].y };
        }

        if (has_arrow) graph_render.shortenPolylineEnd(&smooth, config.arrow_size);
        if (has_source_arrow) graph_render.shortenPolylineStart(&smooth, config.arrow_size);

        try buffers.edges.append(scene_allocator, .{
            .points = try pointSliceToOwned(scene_allocator, smooth.items),
            .point_count = smooth.items.len,
            .color = studioColor(edge_color),
            .thickness = @floatFromInt(thickness),
            .line_style = lineStyleTag(line_style),
            .has_arrow = if (has_arrow) 1 else 0,
            .has_source_arrow = if (has_source_arrow) 1 else 0,
            .target_from = target_from,
            .target_tip = target_tip,
            .source_from = source_from,
            .source_tip = source_tip,
        });

        if (edge_data) |ed| {
            if (ed.label) |label_text| {
                if (label_text.len > 0) {
                    const label_font_size = config.text_size * 0.85;
                    const mid = if (smooth.items.len >= 2) graph_render.pointAlongCurve(smooth.items, 22.0) else Vec2.lerp(waypoints.items[0], waypoints.items[1], 0.15);

                    var tan_x: f64 = 0;
                    var tan_y: f64 = 1;
                    if (smooth.items.len >= 2) {
                        const t_idx = @min(@as(usize, 1), smooth.items.len - 1);
                        tan_x = smooth.items[t_idx].x - smooth.items[0].x;
                        tan_y = smooth.items[t_idx].y - smooth.items[0].y;
                        const tlen = @sqrt(tan_x * tan_x + tan_y * tan_y);
                        if (tlen > 0.001) {
                            tan_x /= tlen;
                            tan_y /= tlen;
                        }
                    }

                    const text_w = measureTextWidth(maybe_font, label_text, label_font_size);
                    try label_placements.append(temp_allocator, .{
                        .text = label_text,
                        .x = mid.x,
                        .y = mid.y,
                        .orig_x = mid.x,
                        .orig_y = mid.y,
                        .half_w = @as(f64, @floatCast(text_w)) / 2.0 + 4.0,
                        .half_h = @as(f64, @floatCast(label_font_size * 1.3)) / 2.0 + 2.0,
                        .tangent_x = tan_x,
                        .tangent_y = tan_y,
                        .font_size = label_font_size,
                        .color = config.text_color,
                    });
                }
            }
        }
    }

    if (label_placements.items.len > 0) {
        try graph_render.resolveLabelPlacements(temp_allocator, label_placements.items, graph, offset_x, offset_y);
        for (label_placements.items) |label| try appendEdgeLabel(scene_allocator, buffers, label);
    }
}

fn finalizeScene(allocator: std.mem.Allocator, buffers: *SceneBuffers, width: f64, height: f64) !*StudioScene {
    const subgraphs_len = buffers.subgraphs.items.len;
    const nodes_len = buffers.nodes.items.len;
    const edges_len = buffers.edges.items.len;
    const labels_len = buffers.edge_labels.items.len;

    const subgraphs = if (subgraphs_len > 0) try buffers.subgraphs.toOwnedSlice(allocator) else &[_]StudioSubgraph{};
    const nodes = if (nodes_len > 0) try buffers.nodes.toOwnedSlice(allocator) else &[_]StudioNode{};
    const edges = if (edges_len > 0) try buffers.edges.toOwnedSlice(allocator) else &[_]StudioEdge{};
    const labels = if (labels_len > 0) try buffers.edge_labels.toOwnedSlice(allocator) else &[_]StudioEdgeLabel{};

    const subgraphs_ptr: [*c]StudioSubgraph = if (subgraphs_len > 0) @ptrCast(@constCast(subgraphs.ptr)) else null;
    const nodes_ptr: [*c]StudioNode = if (nodes_len > 0) @ptrCast(@constCast(nodes.ptr)) else null;
    const edges_ptr: [*c]StudioEdge = if (edges_len > 0) @ptrCast(@constCast(edges.ptr)) else null;
    const labels_ptr: [*c]StudioEdgeLabel = if (labels_len > 0) @ptrCast(@constCast(labels.ptr)) else null;

    const scene = try allocator.create(StudioScene);
    scene.* = .{
        .width = width,
        .height = height,
        .background = studioColor(.{ 255, 255, 255, 255 }),
        .subgraphs = subgraphs_ptr,
        .subgraph_count = subgraphs_len,
        .nodes = nodes_ptr,
        .node_count = nodes_len,
        .edges = edges_ptr,
        .edge_count = edges_len,
        .edge_labels = labels_ptr,
        .edge_label_count = labels_len,
    };
    return scene;
}

fn appendEditableSubgraphs(temp_allocator: std.mem.Allocator, scene_allocator: std.mem.Allocator, graph: *Graph, buffers: *EditableGraphBuffers, offset_x: f64, offset_y: f64, config: RenderConfig) !void {
    const nodes = try graph.allNodes(temp_allocator);
    defer {
        for (nodes) |id| temp_allocator.free(id);
        temp_allocator.free(nodes);
    }

    const Entry = struct {
        id: []const u8,
        depth: usize,
    };

    var subgraphs = std.ArrayListUnmanaged(Entry){};
    defer subgraphs.deinit(temp_allocator);

    for (nodes) |id| {
        const node = graph.getNode(id) orelse continue;
        if (!node.is_subgraph or node.width < 0.1 or node.height < 0.1) continue;

        var depth: usize = 0;
        var parent_id = graph.getParent(id);
        while (parent_id) |current_id| {
            depth += 1;
            parent_id = graph.getParent(current_id);
        }

        try subgraphs.append(temp_allocator, .{ .id = id, .depth = depth });
    }

    std.mem.sort(Entry, subgraphs.items, {}, struct {
        fn lessThan(_: void, lhs: Entry, rhs: Entry) bool {
            if (lhs.depth != rhs.depth) return lhs.depth < rhs.depth;
            return std.mem.order(u8, lhs.id, rhs.id) == .lt;
        }
    }.lessThan);

    for (subgraphs.items) |entry| {
        const node = graph.getNode(entry.id) orelse continue;
        const title = node.subgraph_title orelse (node.label orelse entry.id);
        const parent_subgraph_id = graph.getParent(entry.id);

        try buffers.subgraphs.append(scene_allocator, .{
            .id = try dupCString(scene_allocator, entry.id),
            .title = try dupCString(scene_allocator, title),
            .parent_subgraph_id = if (parent_subgraph_id) |parent| try dupCString(scene_allocator, parent) else null,
            .x = node.x + offset_x - node.width / 2.0,
            .y = node.y + offset_y - node.height / 2.0,
            .width = node.width,
            .height = node.height,
            .corner_radius = config.subgraph_corner_radius,
            .fill = studioColor(config.subgraph_fill_color),
            .stroke = studioColor(config.subgraph_stroke_color),
            .stroke_width = @floatFromInt(config.subgraph_stroke_width),
            .title_x = node.x + offset_x - node.width / 2.0 + config.subgraph_corner_radius + 6.0,
            .title_y = node.y + offset_y - node.height / 2.0 + 16.0,
            .title_font_size = config.text_size * 0.9,
            .title_color = studioColor(config.subgraph_title_color),
            .title_position = 0,
        });
    }
}

fn appendEditableNodes(temp_allocator: std.mem.Allocator, scene_allocator: std.mem.Allocator, graph: *Graph, buffers: *EditableGraphBuffers, offset_x: f64, offset_y: f64, config: RenderConfig) !void {
    const nodes = try graph.allNodes(temp_allocator);
    defer {
        for (nodes) |id| temp_allocator.free(id);
        temp_allocator.free(nodes);
    }

    for (nodes) |id| {
        const node = graph.getNode(id) orelse continue;
        if (node.dummy or node.is_subgraph) continue;
        const parent_subgraph_id = graph.getParent(id);

        try buffers.nodes.append(scene_allocator, .{
            .id = try dupCString(scene_allocator, id),
            .label = try dupCString(scene_allocator, node.label orelse id),
            .subtitle = null,
            .attributes_text = null,
            .methods_text = null,
            .parent_subgraph_id = if (parent_subgraph_id) |parent| try dupCString(scene_allocator, parent) else null,
            .shape = nodeShapeTag(node.shape),
            .x = node.x + offset_x,
            .y = node.y + offset_y,
            .width = node.width,
            .height = node.height,
            .fill = studioColor(node.fill_color orelse config.node_fill_color),
            .body_fill = studioColor(node.fill_color orelse config.node_fill_color),
            .stroke = studioColor(node.stroke_color orelse config.node_stroke_color),
            .stroke_width = @floatFromInt(node.stroke_width orelse config.node_stroke_width),
            .label_color = studioColor(node.text_color orelse config.text_color),
            .label_font_size = config.text_size,
        });
    }
}

fn appendEditableEdges(scene_allocator: std.mem.Allocator, graph: *Graph, buffers: *EditableGraphBuffers, config: RenderConfig) !void {
    var iter = graph.edgeIterator();
    while (iter.next()) |entry| {
        const source_node = graph.getNode(entry.v) orelse continue;
        if (source_node.dummy) continue;

        var target_id = entry.w;
        while (true) {
            const target_node = graph.getNode(target_id) orelse break;
            if (!target_node.dummy) break;
            target_id = graph_render.nextInChain(graph, target_id) orelse break;
        }

        const target_node = graph.getNode(target_id) orelse continue;
        if (target_node.dummy) continue;

        const edge_data = graph.edge(entry.v, entry.w, entry.name);
        const edge_color = if (edge_data) |ed| ed.color orelse config.edge_color else config.edge_color;
        const line_style = if (edge_data) |ed| ed.line_style else LineStyle.solid;
        const thickness = edgeThickness(if (edge_data) |ed| ed.thickness orelse config.edge_width else config.edge_width, line_style);
        const has_arrow = if (edge_data) |ed| blk: {
            if (ed.arrowhead) |ah| break :blk !std.mem.eql(u8, ah, "none");
            break :blk true;
        } else true;
        const has_source_arrow = if (edge_data) |ed| blk: {
            if (ed.arrowtail) |at| break :blk !std.mem.eql(u8, at, "none");
            break :blk false;
        } else false;

        try buffers.edges.append(scene_allocator, .{
            .source_id = try dupCString(scene_allocator, entry.v),
            .target_id = try dupCString(scene_allocator, target_id),
            .label = if (edge_data) |ed|
                if (ed.label) |text|
                    try dupCString(scene_allocator, text)
                else
                    null
            else
                null,
            .label_font_size = config.text_size * 0.85,
            .color = studioColor(edge_color),
            .thickness = @floatFromInt(thickness),
            .line_style = lineStyleTag(line_style),
            .has_arrow = if (has_arrow) 1 else 0,
            .has_source_arrow = if (has_source_arrow) 1 else 0,
            .source_end_style = if (has_source_arrow) classRelationEndStyleTag(.dependency) else 0,
            .target_end_style = if (has_arrow) classRelationEndStyleTag(.dependency) else 0,
        });
    }
}

// ---------------------------------------------------------------------------
// State diagram editable graph
// ---------------------------------------------------------------------------

const state_editable_margin: f64 = 50.0;
const state_editable_nodesep: f64 = 50.0;
const state_editable_ranksep: f64 = 60.0;
const state_editable_fixed_width: f64 = 180.0;
const state_editable_min_width: f64 = 80.0;
const state_editable_min_height: f64 = 40.0;
const state_editable_padding_v: f64 = 12.0;
const state_editable_char_width: f64 = 8.0;
const state_editable_line_height: f64 = 20.0;
const state_editable_start_size: f64 = 20.0;
const state_editable_end_size: f64 = 24.0;
const state_editable_fork_w: f64 = 70.0;
const state_editable_fork_h: f64 = 12.0;
const state_editable_choice_size: f64 = 36.0;
const state_editable_composite_padding: f64 = 16.0;

fn stateNodeSizeForEditable(s: *const state_model.State) NodeSize {
    return switch (s.state_type) {
        .start => .{ .w = state_editable_start_size, .h = state_editable_start_size },
        .end => .{ .w = state_editable_end_size, .h = state_editable_end_size },
        .fork, .join => .{ .w = state_editable_fork_w, .h = state_editable_fork_h },
        .choice => .{ .w = state_editable_choice_size, .h = state_editable_choice_size },
        .divider => .{ .w = 60.0, .h = 8.0 },
        .default => {
            const label = s.displayLabel();
            const iw: f64 = @floatFromInt(label.len);
            const w = @max(state_editable_fixed_width, @max(state_editable_min_width, iw * state_editable_char_width + 40.0));
            var desc_lines: usize = 0;
            if (s.description != null) desc_lines += 1;
            desc_lines += s.descriptions.items.len;
            const h_base = state_editable_padding_v * 2.0 + state_editable_line_height;
            const h_desc: f64 = if (desc_lines > 0) @as(f64, @floatFromInt(desc_lines)) * state_editable_line_height + 8.0 else 0.0;
            return .{ .w = w, .h = @max(state_editable_min_height, h_base + h_desc) };
        },
    };
}

fn stateShapeTagForEditable(state_type: state_model.StateType) u32 {
    return switch (state_type) {
        .start => 3, // solid filled circle
        .end => 12, // circle within a circle
        .fork, .join => 0, // rectangle (black filled)
        .choice => 2, // diamond
        .divider => 0, // rectangle
        .default => 1, // rounded_rectangle
    };
}

fn stateFillColorForEditable(state_type: state_model.StateType) StudioColor {
    return switch (state_type) {
        .start, .end, .fork, .join => studioColor(.{ 30, 30, 30, 255 }),
        .choice => studioColor(.{ 255, 255, 255, 255 }),
        .divider => studioColor(.{ 80, 80, 80, 255 }),
        .default => studioColor(.{ 254, 254, 254, 255 }),
    };
}

fn stateStrokeColorForEditable(state_type: state_model.StateType) StudioColor {
    return switch (state_type) {
        .start, .end, .fork, .join => studioColor(.{ 20, 20, 20, 255 }),
        .choice => studioColor(.{ 40, 40, 40, 255 }),
        .divider => studioColor(.{ 60, 60, 60, 255 }),
        .default => studioColor(.{ 102, 102, 102, 255 }),
    };
}

fn stateLabelColorForEditable(state_type: state_model.StateType) StudioColor {
    return switch (state_type) {
        .start, .end, .fork, .join, .divider => studioColor(.{ 255, 255, 255, 255 }),
        .default, .choice => studioColor(.{ 40, 40, 40, 255 }),
    };
}

fn appendStateEditableGraph(
    allocator: std.mem.Allocator,
    diagram: *state_model.StateDiagram,
    buffers: *EditableGraphBuffers,
) !struct { width: f64, height: f64 } {
    // Identify composite states (any state that is a parent of another state).
    var composite_set = std.StringHashMap(void).init(allocator);
    defer composite_set.deinit();

    {
        var iter = diagram.states.iterator();
        while (iter.next()) |entry| {
            if (entry.value_ptr.parent) |p| try composite_set.put(p, {});
        }
    }

    // Build a Dagre graph with composite states as subgraph containers.
    var graph = Graph.init(allocator);
    defer {
        normalize.freeDummyIds(allocator, &graph);
        graph.deinitDeep();
    }

    var node_ids = std.ArrayListUnmanaged([]const u8){};
    defer {
        for (node_ids.items) |id| allocator.free(id);
        node_ids.deinit(allocator);
    }

    {
        var iter = diagram.states.iterator();
        while (iter.next()) |entry| {
            const id = entry.key_ptr.*;
            const state = entry.value_ptr;
            try node_ids.append(allocator, try allocator.dupe(u8, id));

            if (composite_set.contains(id)) {
                try graph.setNode(id, .{
                    .label = state.displayLabel(),
                    .width = 0,
                    .height = 0,
                    .is_subgraph = true,
                    .subgraph_title = state.displayLabel(),
                    .subgraph_padding = state_editable_composite_padding,
                });
            } else {
                const size = stateNodeSizeForEditable(state);
                try graph.setNode(id, .{
                    .label = state.displayLabel(),
                    .width = size.w,
                    .height = size.h,
                });
            }
        }
    }

    // Set parent relationships.
    {
        var iter = diagram.states.iterator();
        while (iter.next()) |entry| {
            if (entry.value_ptr.parent) |p| {
                if (graph.getNode(p) != null) {
                    try graph.setParent(entry.key_ptr.*, p);
                }
            }
        }
    }

    // Deterministic ordering.
    std.mem.sort([]const u8, node_ids.items, {}, struct {
        fn cmp(_: void, a: []const u8, b: []const u8) bool {
            return std.mem.order(u8, a, b) == .lt;
        }
    }.cmp);

    // Direction and edges.
    var graph_label = graph.getGraphLabel();
    graph_label.rankdir = switch (diagram.direction) {
        .LR => "LR",
        .RL => "RL",
        .BT => "BT",
        .TB => "TB",
    };

    for (diagram.relations.items) |rel| {
        if (graph.getNode(rel.from) != null and graph.getNode(rel.to) != null) {
            try graph.setEdge(rel.from, rel.to, .{
                .label = rel.label,
                .minlen = 1,
            }, null);
        }
    }

    try dagre.layout(allocator, &graph, .{
        .rankdir = rankDirFromText(graph_label.rankdir),
        .ranker = .network_simplex,
        .nodesep = state_editable_nodesep,
        .ranksep = state_editable_ranksep,
    });

    // Compute canvas bounds.
    var min_x: f64 = std.math.inf(f64);
    var min_y: f64 = std.math.inf(f64);
    var max_x: f64 = -std.math.inf(f64);
    var max_y: f64 = -std.math.inf(f64);

    for (node_ids.items) |id| {
        const node = graph.getNode(id) orelse continue;
        if (node.width < 0.1 or node.height < 0.1) continue;
        const left = node.x - node.width / 2.0;
        const right = node.x + node.width / 2.0;
        const top = node.y - node.height / 2.0;
        const bottom = node.y + node.height / 2.0;
        if (left < min_x) min_x = left;
        if (right > max_x) max_x = right;
        if (top < min_y) min_y = top;
        if (bottom > max_y) max_y = bottom;
    }

    if (min_x == std.math.inf(f64)) {
        min_x = 0.0;
        min_y = 0.0;
        max_x = 200.0;
        max_y = 100.0;
    }

    const offset_x = state_editable_margin - min_x;
    const offset_y = state_editable_margin - min_y;

    // Emit composite states as subgraphs.
    for (node_ids.items) |id| {
        const node = graph.getNode(id) orelse continue;
        if (!node.is_subgraph or node.width < 0.1 or node.height < 0.1) continue;

        const state = diagram.states.getPtr(id) orelse continue;
        const parent_id = graph.getParent(id);

        try buffers.subgraphs.append(c_allocator, .{
            .id = try dupCString(c_allocator, id),
            .title = try dupCString(c_allocator, state.displayLabel()),
            .parent_subgraph_id = if (parent_id) |pid| try dupCString(c_allocator, pid) else null,
            .x = node.x + offset_x - node.width / 2.0,
            .y = node.y + offset_y - node.height / 2.0,
            .width = node.width,
            .height = node.height,
            .corner_radius = 8.0,
            .fill = studioColor(.{ 242, 247, 255, 255 }),
            .stroke = studioColor(.{ 102, 140, 200, 255 }),
            .stroke_width = 1.5,
            .title_x = node.x + offset_x - node.width / 2.0 + 10.0,
            .title_y = node.y + offset_y - node.height / 2.0 + 16.0,
            .title_font_size = 13.0,
            .title_color = studioColor(.{ 60, 80, 120, 255 }),
            .title_position = 0,
        });
    }

    // Emit regular states as nodes.
    for (node_ids.items) |id| {
        const node = graph.getNode(id) orelse continue;
        if (node.is_subgraph) continue;

        const state = diagram.states.getPtr(id) orelse continue;
        const parent_id = graph.getParent(id);

        const subtitle: [*c]const u8 = if (state.description) |desc|
            try dupCString(c_allocator, desc)
        else
            null;

        const stroke_w: f32 = switch (state.state_type) {
            .default => 1.5,
            else => 2.0,
        };
        const label_font_size: f32 = switch (state.state_type) {
            .default => 13.0,
            else => 0.0, // special shapes: no text label drawn
        };

        try buffers.nodes.append(c_allocator, .{
            .id = try dupCString(c_allocator, id),
            .label = try dupCString(c_allocator, state.displayLabel()),
            .subtitle = subtitle,
            .attributes_text = null,
            .methods_text = null,
            .parent_subgraph_id = if (parent_id) |pid| try dupCString(c_allocator, pid) else null,
            .shape = stateShapeTagForEditable(state.state_type),
            .x = node.x + offset_x,
            .y = node.y + offset_y,
            .width = node.width,
            .height = node.height,
            .fill = stateFillColorForEditable(state.state_type),
            .body_fill = stateFillColorForEditable(state.state_type),
            .stroke = stateStrokeColorForEditable(state.state_type),
            .stroke_width = stroke_w,
            .label_color = stateLabelColorForEditable(state.state_type),
            .label_font_size = label_font_size,
        });
    }

    // Emit transitions as edges.
    for (diagram.relations.items) |rel| {
        try buffers.edges.append(c_allocator, .{
            .source_id = try dupCString(c_allocator, rel.from),
            .target_id = try dupCString(c_allocator, rel.to),
            .label = if (rel.label) |l| (if (l.len > 0) try dupCString(c_allocator, l) else null) else null,
            .label_font_size = 11.0,
            .color = studioColor(.{ 80, 80, 80, 255 }),
            .thickness = 1.5,
            .line_style = 0,
            .has_arrow = 1,
            .has_source_arrow = 0,
            .source_end_style = 0,
            .target_end_style = 0,
        });
    }

    return .{
        .width = (max_x - min_x) + state_editable_margin * 2.0,
        .height = (max_y - min_y) + state_editable_margin * 2.0,
    };
}

fn finalizeEditableGraph(allocator: std.mem.Allocator, graph_type: StudioGraphType, buffers: *EditableGraphBuffers, width: f64, height: f64) !*StudioEditableGraph {
    const subgraphs_len = buffers.subgraphs.items.len;
    const nodes_len = buffers.nodes.items.len;
    const edges_len = buffers.edges.items.len;

    const subgraphs = if (subgraphs_len > 0) try buffers.subgraphs.toOwnedSlice(allocator) else &[_]StudioEditableSubgraph{};
    const nodes = if (nodes_len > 0) try buffers.nodes.toOwnedSlice(allocator) else &[_]StudioEditableNode{};
    const edges = if (edges_len > 0) try buffers.edges.toOwnedSlice(allocator) else &[_]StudioEditableEdge{};

    const graph = try allocator.create(StudioEditableGraph);
    graph.* = .{
        .graph_type = @intFromEnum(graph_type),
        .width = width,
        .height = height,
        .background = studioColor(.{ 255, 255, 255, 255 }),
        .subgraphs = if (subgraphs_len > 0) @ptrCast(@constCast(subgraphs.ptr)) else null,
        .subgraph_count = subgraphs_len,
        .nodes = if (nodes_len > 0) @ptrCast(@constCast(nodes.ptr)) else null,
        .node_count = nodes_len,
        .edges = if (edges_len > 0) @ptrCast(@constCast(edges.ptr)) else null,
        .edge_count = edges_len,
    };
    return graph;
}

fn buildEditableGraphFromSource(temp_allocator: std.mem.Allocator, source: []const u8) !*StudioEditableGraph {
    if (detectSequenceDiagram(source)) {
        var parser = SeqParser.init(temp_allocator, source);
        var diag = try parser.parse();
        defer diag.deinit();

        const layout_config = SeqLayout.LayoutConfig{};
        const layout = SeqLayout.layout(&diag, layout_config);

        var buffers = EditableGraphBuffers{};
        errdefer buffers.deinit(c_allocator);

        try appendSequenceEditableGraph(temp_allocator, &diag, layout, &buffers);
        return finalizeEditableGraph(c_allocator, .sequence, &buffers, layout.width, layout.height);
    }

    if (detectClassDiagram(source)) {
        var diagram = try ClassParser.parse(temp_allocator, source);
        defer diagram.deinit();

        var buffers = EditableGraphBuffers{};
        errdefer buffers.deinit(c_allocator);

        const layout = try appendClassEditableGraph(temp_allocator, &diagram, &buffers);
        return finalizeEditableGraph(c_allocator, .class, &buffers, layout.width, layout.height);
    }

    if (detectErDiagram(source)) {
        var diagram = try ErParser.parse(temp_allocator, source);
        defer diagram.deinit();

        var buffers = EditableGraphBuffers{};
        errdefer buffers.deinit(c_allocator);

        const layout = try appendErEditableGraph(temp_allocator, &diagram, &buffers);
        return finalizeEditableGraph(c_allocator, .er, &buffers, layout.width, layout.height);
    }

    if (detectStateDiagram(source)) {
        var diagram = try StateParser.parse(temp_allocator, source);
        defer diagram.deinit();

        var buffers = EditableGraphBuffers{};
        errdefer buffers.deinit(c_allocator);

        const layout = try appendStateEditableGraph(temp_allocator, &diagram, &buffers);
        return finalizeEditableGraph(c_allocator, .state, &buffers, layout.width, layout.height);
    }

    var parser = try Parser.init(temp_allocator, source);
    defer parser.deinit();

    var graph = try parser.parse();
    defer {
        normalize.freeDummyIds(temp_allocator, &graph);
        graph.deinitDeep();
    }

    const node_ids = try graph.allNodes(temp_allocator);
    defer {
        for (node_ids) |id| temp_allocator.free(id);
        temp_allocator.free(node_ids);
    }

    var maybe_font = try loadFont(temp_allocator);
    defer if (maybe_font) |*loaded| loaded.deinit(temp_allocator);

    for (node_ids) |id| {
        if (graph.getNodePtr(id)) |node| {
            if (node.width > 0 or node.is_subgraph) continue;
            const display_text = node.label orelse id;
            const size = if (maybe_font) |*loaded| measureNodeSize(&loaded.font, display_text, node.shape) else estimateNodeSize(display_text, node.shape);
            node.width = size.w;
            node.height = size.h;
        }
    }

    try dagre.layout(temp_allocator, &graph, .{
        .rankdir = rankDirFromText(graph.getGraphLabel().rankdir),
        .ranker = .network_simplex,
        .nodesep = 50,
        .ranksep = 50,
    });

    const config = defaultRenderConfig();
    const bounds = try graph_render.calculateBounds(temp_allocator, &graph, config);
    const offset_x = config.padding - bounds.min_x;
    const offset_y = config.padding - bounds.min_y;

    var buffers = EditableGraphBuffers{};
    errdefer buffers.deinit(c_allocator);

    try appendEditableSubgraphs(temp_allocator, c_allocator, &graph, &buffers, offset_x, offset_y, config);
    try appendEditableNodes(temp_allocator, c_allocator, &graph, &buffers, offset_x, offset_y, config);
    try appendEditableEdges(c_allocator, &graph, &buffers, config);

    return finalizeEditableGraph(c_allocator, .flowchart, &buffers, bounds.width + config.padding * 2.0, bounds.height + config.padding * 2.0);
}

fn buildSceneFromSource(temp_allocator: std.mem.Allocator, source: []const u8) !*StudioScene {
    if (detectSequenceDiagram(source) or detectErDiagram(source)) return error.UnsupportedPreviewScene;

    if (detectClassDiagram(source)) {
        return buildClassSceneFromSource(temp_allocator, source);
    }

    var parser = try Parser.init(temp_allocator, source);
    defer parser.deinit();

    var graph = try parser.parse();
    defer {
        normalize.freeDummyIds(temp_allocator, &graph);
        graph.deinitDeep();
    }

    const node_ids = try graph.allNodes(temp_allocator);
    defer {
        for (node_ids) |id| temp_allocator.free(id);
        temp_allocator.free(node_ids);
    }

    var maybe_font = try loadFont(temp_allocator);
    defer if (maybe_font) |*loaded| loaded.deinit(temp_allocator);

    for (node_ids) |id| {
        if (graph.getNodePtr(id)) |node| {
            if (node.width > 0 or node.is_subgraph) continue;
            const display_text = node.label orelse id;
            const size = if (maybe_font) |*loaded| measureNodeSize(&loaded.font, display_text, node.shape) else estimateNodeSize(display_text, node.shape);
            node.width = size.w;
            node.height = size.h;
        }
    }

    const graph_label = graph.getGraphLabel();
    const rankdir: dagre.RankDir = blk: {
        if (std.mem.eql(u8, graph_label.rankdir, "LR")) break :blk .LR;
        if (std.mem.eql(u8, graph_label.rankdir, "RL")) break :blk .RL;
        if (std.mem.eql(u8, graph_label.rankdir, "BT")) break :blk .BT;
        break :blk .TB;
    };

    try dagre.layout(temp_allocator, &graph, .{
        .rankdir = rankdir,
        .ranker = .network_simplex,
        .nodesep = 50,
        .ranksep = 50,
    });

    const config = defaultRenderConfig();
    const bounds = try graph_render.calculateBounds(temp_allocator, &graph, config);
    const offset_x = config.padding - bounds.min_x;
    const offset_y = config.padding - bounds.min_y;

    var buffers = SceneBuffers{};
    errdefer buffers.deinit(c_allocator);

    try appendSubgraphs(temp_allocator, c_allocator, &graph, &buffers, offset_x, offset_y, config);
    try appendEdges(temp_allocator, c_allocator, &graph, &buffers, if (maybe_font) |*loaded| &loaded.font else null, offset_x, offset_y, config);
    try appendNodes(temp_allocator, c_allocator, &graph, &buffers, offset_x, offset_y, config);

    return finalizeScene(c_allocator, &buffers, bounds.width + config.padding * 2.0, bounds.height + config.padding * 2.0);
}

fn renderGenericGraphDiagramToFile(
    allocator: std.mem.Allocator,
    source: []const u8,
    output_path: []const u8,
    export_svg: bool,
    maybe_font: ?*LoadedFont,
    raster_scale: f64,
    layout_scale: f64,
    target_width: u32,
    target_height: u32,
) !void {
    var parser = Parser.init(allocator, source) catch |err| {
        return err;
    };
    defer parser.deinit();

    var graph = parser.parse() catch |err| {
        return err;
    };
    defer {
        normalize.freeDummyIds(allocator, &graph);
        graph.deinitDeep();
    }

    const node_ids = graph.allNodes(allocator) catch |err| {
        return err;
    };
    defer {
        for (node_ids) |id| allocator.free(id);
        allocator.free(node_ids);
    }

    for (node_ids) |id| {
        if (graph.getNodePtr(id)) |node| {
            if (node.width > 0 or node.is_subgraph) continue;
            const display_text = node.label orelse id;
            const size = if (maybe_font) |loaded| measureNodeSize(&loaded.font, display_text, node.shape) else estimateNodeSize(display_text, node.shape);
            node.width = size.w;
            node.height = size.h;
        }
    }

    const graph_label = graph.getGraphLabel();
    const rankdir: dagre.RankDir = blk: {
        if (std.mem.eql(u8, graph_label.rankdir, "LR")) break :blk .LR;
        if (std.mem.eql(u8, graph_label.rankdir, "RL")) break :blk .RL;
        if (std.mem.eql(u8, graph_label.rankdir, "BT")) break :blk .BT;
        break :blk .TB;
    };

    try dagre.layout(allocator, &graph, .{
        .rankdir = rankdir,
        .ranker = .network_simplex,
        .nodesep = 50,
        .ranksep = 50,
    });

    const base_config = exportRenderConfig(1.0, raster_scale);
    const base_bounds = try graph_render.calculateBounds(allocator, &graph, base_config);
    const scaled_layout = layout_scale * downscaleForTargetCanvas(
        (base_bounds.width + base_config.padding * 2.0) * raster_scale,
        (base_bounds.height + base_config.padding * 2.0) * raster_scale,
        target_width,
        target_height,
    );

    try scaleGraphGeometry(allocator, &graph, scaled_layout);

    const config = exportRenderConfig(scaled_layout, raster_scale);
    const maybe_export_font = if (maybe_font) |loaded| &loaded.font else null;

    if (export_svg) {
        try svg_render.renderGraphToSVGWithFont(allocator, &graph, output_path, config, maybe_export_font);
    } else {
        try graph_render.renderGraphToPNGWithFont(allocator, &graph, output_path, config, maybe_export_font);
    }
}

fn renderGenericGraphDiagramToBytes(
    allocator: std.mem.Allocator,
    source: []const u8,
    maybe_font: ?*LoadedFont,
    raster_scale: f64,
    layout_scale: f64,
    target_width: u32,
    target_height: u32,
) ![]u8 {
    var parser = Parser.init(allocator, source) catch |err| {
        return err;
    };
    defer parser.deinit();

    var graph = parser.parse() catch |err| {
        return err;
    };
    defer {
        normalize.freeDummyIds(allocator, &graph);
        graph.deinitDeep();
    }

    const node_ids = graph.allNodes(allocator) catch |err| {
        return err;
    };
    defer {
        for (node_ids) |id| allocator.free(id);
        allocator.free(node_ids);
    }

    for (node_ids) |id| {
        if (graph.getNodePtr(id)) |node| {
            if (node.width > 0 or node.is_subgraph) continue;
            const display_text = node.label orelse id;
            const size = if (maybe_font) |loaded| measureNodeSize(&loaded.font, display_text, node.shape) else estimateNodeSize(display_text, node.shape);
            node.width = size.w;
            node.height = size.h;
        }
    }

    const graph_label = graph.getGraphLabel();
    const rankdir: dagre.RankDir = blk: {
        if (std.mem.eql(u8, graph_label.rankdir, "LR")) break :blk .LR;
        if (std.mem.eql(u8, graph_label.rankdir, "RL")) break :blk .RL;
        if (std.mem.eql(u8, graph_label.rankdir, "BT")) break :blk .BT;
        break :blk .TB;
    };

    try dagre.layout(allocator, &graph, .{
        .rankdir = rankdir,
        .ranker = .network_simplex,
        .nodesep = 50,
        .ranksep = 50,
    });

    const base_config = exportRenderConfig(1.0, raster_scale);
    const base_bounds = try graph_render.calculateBounds(allocator, &graph, base_config);
    const scaled_layout = layout_scale * downscaleForTargetCanvas(
        (base_bounds.width + base_config.padding * 2.0) * raster_scale,
        (base_bounds.height + base_config.padding * 2.0) * raster_scale,
        target_width,
        target_height,
    );

    try scaleGraphGeometry(allocator, &graph, scaled_layout);

    const config = exportRenderConfig(scaled_layout, raster_scale);
    const maybe_export_font = if (maybe_font) |loaded| &loaded.font else null;
    return graph_render.renderGraphToPNGBytesWithFont(allocator, &graph, config, maybe_export_font);
}

fn renderEditableGraphToBytes(
    allocator: std.mem.Allocator,
    editable_graph: *const StudioEditableGraph,
    maybe_font: ?*LoadedFont,
    raster_scale: f64,
    target_width: u32,
    target_height: u32,
) ![]u8 {
    var graph = Graph.init(allocator);
    defer graph.deinitDeep();

    const graph_label = graph.getGraphLabel();
    graph_label.width = editable_graph.width;
    graph_label.height = editable_graph.height;

    if (editable_graph.subgraphs) |subgraphs| {
        for (subgraphs[0..editable_graph.subgraph_count]) |subgraph| {
            const subgraph_id = std.mem.span(subgraph.id);
            const title = optionalCStringSlice(subgraph.title);

            try graph.setNode(subgraph_id, .{
                .label = if (title) |text| text else subgraph_id,
                .width = subgraph.width,
                .height = subgraph.height,
                .x = subgraph.x + subgraph.width / 2.0,
                .y = subgraph.y + subgraph.height / 2.0,
                .shape = .round,
                .is_subgraph = true,
                .subgraph_title = title,
                .fill_color = studioColorRgba(subgraph.fill),
                .stroke_color = studioColorRgba(subgraph.stroke),
                .stroke_width = @intFromFloat(@round(subgraph.stroke_width)),
                .text_color = studioColorRgba(subgraph.title_color),
            });
        }
    }

    if (editable_graph.nodes) |nodes| {
        for (nodes[0..editable_graph.node_count]) |node| {
            const node_id = std.mem.span(node.id);
            const node_text = try editableNodeText(allocator, node);
            errdefer if (node_text.owned) allocator.free(node_text.text);

            try graph.setNode(node_id, .{
                .label = node_text.text,
                .label_owned = node_text.owned,
                .width = node.width,
                .height = node.height,
                .shape = editableNodeShape(node.shape),
                .fill_color = studioColorRgba(node.fill),
                .stroke_color = studioColorRgba(node.stroke),
                .stroke_width = @intFromFloat(@round(node.stroke_width)),
                .text_color = studioColorRgba(node.label_color),
                .x = node.x,
                .y = node.y,
            });
        }
    }

    if (editable_graph.subgraphs) |subgraphs| {
        for (subgraphs[0..editable_graph.subgraph_count]) |subgraph| {
            if (optionalCStringSlice(subgraph.parent_subgraph_id)) |parent_id| {
                try graph.setParent(std.mem.span(subgraph.id), parent_id);
            }
        }
    }

    if (editable_graph.nodes) |nodes| {
        for (nodes[0..editable_graph.node_count]) |node| {
            if (optionalCStringSlice(node.parent_subgraph_id)) |parent_id| {
                try graph.setParent(std.mem.span(node.id), parent_id);
            }
        }
    }

    if (editable_graph.edges) |edges| {
        for (edges[0..editable_graph.edge_count]) |edge| {
            try graph.setEdge(std.mem.span(edge.source_id), std.mem.span(edge.target_id), .{
                .label = optionalCStringSlice(edge.label),
                .line_style = editableLineStyle(edge.line_style),
                .color = studioColorRgba(edge.color),
                .thickness = @intFromFloat(@round(edge.thickness)),
                .arrowhead = if (editableGraphEdgeHasTargetArrow(edge)) "normal" else "none",
                .arrowtail = if (editableGraphEdgeHasSourceArrow(edge)) "normal" else "none",
            }, null);
        }
    }

    const base_config = exportRenderConfig(1.0, raster_scale);
    const base_bounds = try graph_render.calculateBounds(allocator, &graph, base_config);
    const scaled_layout = downscaleForTargetCanvas(
        (base_bounds.width + base_config.padding * 2.0) * raster_scale,
        (base_bounds.height + base_config.padding * 2.0) * raster_scale,
        target_width,
        target_height,
    );

    try scaleGraphGeometry(allocator, &graph, scaled_layout);

    const config = exportRenderConfig(scaled_layout, raster_scale);
    const maybe_export_font = if (maybe_font) |loaded| &loaded.font else null;
    return graph_render.renderGraphToPNGBytesWithFont(allocator, &graph, config, maybe_export_font);
}

pub export fn merrow_studio_render_preview_png_bytes(
    source_ptr: [*]const u8,
    source_len: u32,
    target_width: u32,
    target_height: u32,
    out_png_len: *u32,
    out_message: [*]u8,
    out_message_len: u32,
) callconv(.c) [*c]u8 {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    out_png_len.* = 0;
    const source = source_ptr[0..source_len];

    var maybe_font = loadFont(allocator) catch |err| {
        copyCString(out_message, out_message_len, @errorName(err));
        return null;
    };
    defer if (maybe_font) |*loaded| loaded.deinit(allocator);

    var preview_bytes: []u8 = undefined;
    if (detectSequenceDiagram(source)) {
        const rendered = renderSequenceDiagramToBytes(
            allocator,
            source,
            if (maybe_font) |*loaded| loaded.data else null,
            preview_raster_scale,
        ) catch |err| {
            copyCString(out_message, out_message_len, @errorName(err));
            return null;
        };
        preview_bytes = rendered;
    } else if (detectStateDiagram(source)) {
        var diagram = StateParser.parse(allocator, source) catch |err| {
            copyCString(out_message, out_message_len, @errorName(err));
            return null;
        };
        defer diagram.deinit();
        const rendered = StatePngRender.renderStateToPNGBytes(
            allocator,
            &diagram,
            if (maybe_font) |*loaded| &loaded.font else null,
        ) catch |err| {
            copyCString(out_message, out_message_len, @errorName(err));
            return null;
        };
        preview_bytes = rendered;
    } else if (detectClassDiagram(source)) {
        var diagram = ClassParser.parse(allocator, source) catch |err| {
            copyCString(out_message, out_message_len, @errorName(err));
            return null;
        };
        defer diagram.deinit();
        const rendered = ClassPngRender.renderClassToPNGBytes(
            allocator,
            &diagram,
            if (maybe_font) |*loaded| &loaded.font else null,
        ) catch |err| {
            copyCString(out_message, out_message_len, @errorName(err));
            return null;
        };
        preview_bytes = rendered;
    } else if (detectErDiagram(source)) {
        var diagram = ErParser.parse(allocator, source) catch |err| {
            copyCString(out_message, out_message_len, @errorName(err));
            return null;
        };
        defer diagram.deinit();
        const rendered = ErPngRender.renderErToPNGBytes(
            allocator,
            &diagram,
            if (maybe_font) |*loaded| &loaded.font else null,
        ) catch |err| {
            copyCString(out_message, out_message_len, @errorName(err));
            return null;
        };
        preview_bytes = rendered;
    } else {
        const rendered = renderGenericGraphDiagramToBytes(
            allocator,
            source,
            if (maybe_font) |*loaded| loaded else null,
            preview_raster_scale,
            1.0,
            target_width,
            target_height,
        ) catch |err| {
            copyCString(out_message, out_message_len, @errorName(err));
            return null;
        };
        preview_bytes = rendered;
    }
    defer allocator.free(preview_bytes);

    const owned = c_allocator.alloc(u8, preview_bytes.len) catch {
        copyCString(out_message, out_message_len, "OutOfMemory");
        return null;
    };
    @memcpy(owned, preview_bytes);
    out_png_len.* = @intCast(preview_bytes.len);
    copyCString(out_message, out_message_len, "Preview render complete");
    return owned.ptr;
}

pub export fn merrow_studio_render_editable_graph_png_bytes(
    graph: ?*const StudioEditableGraph,
    target_width: u32,
    target_height: u32,
    out_png_len: *u32,
    out_message: [*]u8,
    out_message_len: u32,
) callconv(.c) [*c]u8 {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    out_png_len.* = 0;
    const editable_graph = graph orelse {
        copyCString(out_message, out_message_len, "GraphUnavailable");
        return null;
    };

    var maybe_font = loadFont(allocator) catch |err| {
        copyCString(out_message, out_message_len, @errorName(err));
        return null;
    };
    defer if (maybe_font) |*loaded| loaded.deinit(allocator);

    const preview_bytes = renderEditableGraphToBytes(
        allocator,
        editable_graph,
        if (maybe_font) |*loaded| loaded else null,
        preview_raster_scale,
        target_width,
        target_height,
    ) catch |err| {
        copyCString(out_message, out_message_len, @errorName(err));
        return null;
    };
    defer allocator.free(preview_bytes);

    const owned = c_allocator.alloc(u8, preview_bytes.len) catch {
        copyCString(out_message, out_message_len, "OutOfMemory");
        return null;
    };
    @memcpy(owned, preview_bytes);
    out_png_len.* = @intCast(preview_bytes.len);
    copyCString(out_message, out_message_len, "Preview render complete");
    return owned.ptr;
}

pub export fn merrow_studio_create_default_scene(out_source_path: [*]u8, out_source_path_len: u32) callconv(.c) ?*StudioScene {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const source_path = resolveRepoPath(allocator, "test-diagrams/flowchart_subgraphs.mmd") catch return null;
    defer allocator.free(source_path);

    const source = std.fs.cwd().readFileAlloc(allocator, source_path, 10 * 1024 * 1024) catch return null;
    defer allocator.free(source);

    copyCString(out_source_path, out_source_path_len, source_path);
    return buildSceneFromSource(allocator, source) catch null;
}

pub export fn merrow_studio_build_scene(source_ptr: [*]const u8, source_len: u32) callconv(.c) ?*StudioScene {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    return buildSceneFromSource(allocator, source_ptr[0..source_len]) catch null;
}

pub export fn merrow_studio_build_editable_graph(
    source_ptr: [*]const u8,
    source_len: u32,
    out_message: [*]u8,
    out_message_len: u32,
) callconv(.c) ?*StudioEditableGraph {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const source = source_ptr[0..source_len];
    const graph = buildEditableGraphFromSource(allocator, source) catch |err| {
        copyCString(out_message, out_message_len, @errorName(err));
        return null;
    };

    copyCString(out_message, out_message_len, "Editable canvas ready");
    return graph;
}

pub export fn merrow_studio_render_preview_png(
    source_ptr: [*]const u8,
    source_len: u32,
    out_png_path: [*]u8,
    out_png_path_len: u32,
    out_message: [*]u8,
    out_message_len: u32,
) callconv(.c) c_int {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const source = source_ptr[0..source_len];

    const preview_path = createTempPreviewPath(allocator, ".png") catch |err| {
        copyCString(out_message, out_message_len, @errorName(err));
        return 3;
    };
    defer allocator.free(preview_path);

    var maybe_font = loadFont(allocator) catch |err| {
        copyCString(out_message, out_message_len, @errorName(err));
        return 3;
    };
    defer if (maybe_font) |*loaded| loaded.deinit(allocator);

    if (detectSequenceDiagram(source)) {
        renderSequenceDiagramToFile(
            allocator,
            source,
            preview_path,
            false,
            if (maybe_font) |*loaded| loaded.data else null,
            2.0,
        ) catch |err| {
            copyCString(out_message, out_message_len, @errorName(err));
            return 4;
        };
    } else if (detectStateDiagram(source)) {
        var diagram = StateParser.parse(allocator, source) catch |err| {
            copyCString(out_message, out_message_len, @errorName(err));
            return 1;
        };
        defer diagram.deinit();

        StatePngRender.renderStateToPNG(
            allocator,
            &diagram,
            preview_path,
            if (maybe_font) |*loaded| &loaded.font else null,
        ) catch |err| {
            copyCString(out_message, out_message_len, @errorName(err));
            return 4;
        };
    } else if (detectClassDiagram(source)) {
        var diagram = ClassParser.parse(allocator, source) catch |err| {
            copyCString(out_message, out_message_len, @errorName(err));
            return 1;
        };
        defer diagram.deinit();

        ClassPngRender.renderClassToPNG(
            allocator,
            &diagram,
            preview_path,
            if (maybe_font) |*loaded| &loaded.font else null,
        ) catch |err| {
            copyCString(out_message, out_message_len, @errorName(err));
            return 4;
        };
    } else if (detectErDiagram(source)) {
        var diagram = ErParser.parse(allocator, source) catch |err| {
            copyCString(out_message, out_message_len, @errorName(err));
            return 1;
        };
        defer diagram.deinit();

        ErPngRender.renderErToPNG(
            allocator,
            &diagram,
            preview_path,
            if (maybe_font) |*loaded| &loaded.font else null,
        ) catch |err| {
            copyCString(out_message, out_message_len, @errorName(err));
            return 4;
        };
    } else {
        renderGenericGraphDiagramToFile(
            allocator,
            source,
            preview_path,
            false,
            if (maybe_font) |*loaded| loaded else null,
            1.0,
            1.0,
            preview_page_target_width,
            preview_page_target_height,
        ) catch |err| {
            copyCString(out_message, out_message_len, @errorName(err));
            return 4;
        };
    }

    copyCString(out_png_path, out_png_path_len, preview_path);
    copyCString(out_message, out_message_len, "Preview render complete");
    return 0;
}

pub export fn merrow_studio_export_diagram(
    source_ptr: [*]const u8,
    source_len: u32,
    output_path_ptr: [*:0]const u8,
    format: u32,
    raster_scale: f64,
    layout_scale: f64,
    out_message: [*]u8,
    out_message_len: u32,
) callconv(.c) c_int {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const source = source_ptr[0..source_len];
    const output_path = std.mem.span(output_path_ptr);
    if (source.len == 0 or output_path.len == 0) {
        copyCString(out_message, out_message_len, "Missing source or export path");
        return 2;
    }

    var maybe_font = loadFont(allocator) catch |err| {
        copyCString(out_message, out_message_len, @errorName(err));
        return 3;
    };
    defer if (maybe_font) |*loaded| loaded.deinit(allocator);

    const safe_raster_scale = if (raster_scale > 0.0) raster_scale else 1.0;

    if (detectSequenceDiagram(source)) {
        renderSequenceDiagramToFile(
            allocator,
            source,
            output_path,
            format == 1,
            if (maybe_font) |*loaded| loaded.data else null,
            safe_raster_scale,
        ) catch |err| {
            copyCString(out_message, out_message_len, @errorName(err));
            return 4;
        };
        copyCString(out_message, out_message_len, if (format == 0) "PNG export complete" else "SVG export complete");
        return 0;
    }

    if (detectStateDiagram(source)) {
        var diagram = StateParser.parse(allocator, source) catch |err| {
            copyCString(out_message, out_message_len, @errorName(err));
            return 1;
        };
        defer diagram.deinit();

        switch (format) {
            0 => StatePngRender.renderStateToPNG(
                allocator,
                &diagram,
                output_path,
                if (maybe_font) |*loaded| &loaded.font else null,
            ) catch |err| {
                copyCString(out_message, out_message_len, @errorName(err));
                return 4;
            },
            1 => StateSvgRender.renderStateToSVG(
                allocator,
                &diagram,
                output_path,
            ) catch |err| {
                copyCString(out_message, out_message_len, @errorName(err));
                return 4;
            },
            else => {
                copyCString(out_message, out_message_len, "Unsupported export format");
                return 2;
            },
        }

        copyCString(out_message, out_message_len, if (format == 0) "PNG export complete" else "SVG export complete");
        return 0;
    }

    if (detectClassDiagram(source)) {
        var diagram = ClassParser.parse(allocator, source) catch |err| {
            copyCString(out_message, out_message_len, @errorName(err));
            return 1;
        };
        defer diagram.deinit();

        switch (format) {
            0 => ClassPngRender.renderClassToPNG(
                allocator,
                &diagram,
                output_path,
                if (maybe_font) |*loaded| &loaded.font else null,
            ) catch |err| {
                copyCString(out_message, out_message_len, @errorName(err));
                return 4;
            },
            1 => ClassSvgRender.renderClassToSVG(
                allocator,
                &diagram,
                output_path,
                if (maybe_font) |*loaded| &loaded.font else null,
            ) catch |err| {
                copyCString(out_message, out_message_len, @errorName(err));
                return 4;
            },
            else => {
                copyCString(out_message, out_message_len, "Unsupported export format");
                return 2;
            },
        }

        copyCString(out_message, out_message_len, if (format == 0) "PNG export complete" else "SVG export complete");
        return 0;
    }

    if (detectErDiagram(source)) {
        var diagram = ErParser.parse(allocator, source) catch |err| {
            copyCString(out_message, out_message_len, @errorName(err));
            return 1;
        };
        defer diagram.deinit();

        switch (format) {
            0 => ErPngRender.renderErToPNG(
                allocator,
                &diagram,
                output_path,
                if (maybe_font) |*loaded| &loaded.font else null,
            ) catch |err| {
                copyCString(out_message, out_message_len, @errorName(err));
                return 4;
            },
            1 => ErSvgRender.renderErToSVG(
                allocator,
                &diagram,
                output_path,
            ) catch |err| {
                copyCString(out_message, out_message_len, @errorName(err));
                return 4;
            },
            else => {
                copyCString(out_message, out_message_len, "Unsupported export format");
                return 2;
            },
        }

        copyCString(out_message, out_message_len, if (format == 0) "PNG export complete" else "SVG export complete");
        return 0;
    }

    const safe_layout_scale = if (layout_scale > 0.0) layout_scale else 1.0;

    if (format != 0 and format != 1) {
        copyCString(out_message, out_message_len, "Unsupported export format");
        return 2;
    }

    renderGenericGraphDiagramToFile(
        allocator,
        source,
        output_path,
        format == 1,
        if (maybe_font) |*loaded| loaded else null,
        safe_raster_scale,
        safe_layout_scale,
        preview_page_target_width,
        preview_page_target_height,
    ) catch |err| {
        copyCString(out_message, out_message_len, @errorName(err));
        return 4;
    };

    copyCString(out_message, out_message_len, if (format == 0) "PNG export complete" else "SVG export complete");
    return 0;
}

pub export fn merrow_studio_apply_command(
    source_ptr: [*]const u8,
    source_len: u32,
    command_ptr: [*]const u8,
    command_len: u32,
    context_id_ptr: [*]const u8,
    context_id_len: u32,
    out_context_id: [*]u8,
    out_context_id_len: u32,
    out_context_display: [*]u8,
    out_context_display_len: u32,
    out_message: [*]u8,
    out_message_len: u32,
) callconv(.c) [*c]u8 {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const source = source_ptr[0..source_len];
    const command = command_ptr[0..command_len];
    const context_id = if (context_id_len > 0) context_id_ptr[0..context_id_len] else null;

    const result = commands.applyCommandWithState(allocator, source, command, context_id) catch |err| {
        copyCString(out_message, out_message_len, commands.describeError(err));
        copyCString(out_context_id, out_context_id_len, "");
        copyCString(out_context_display, out_context_display_len, "");
        return null;
    };
    defer allocator.free(result.source);
    defer allocator.free(result.message);
    defer if (result.current_node_id) |id| allocator.free(id);

    const owned = c_allocator.alloc(u8, result.source.len + 1) catch {
        copyCString(out_message, out_message_len, "Out of memory");
        copyCString(out_context_id, out_context_id_len, "");
        copyCString(out_context_display, out_context_display_len, "");
        return null;
    };
    @memcpy(owned[0..result.source.len], result.source);
    owned[result.source.len] = 0;

    if (result.current_node_id) |id| {
        copyCString(out_context_id, out_context_id_len, id);
        const display = describeContextNode(allocator, result.source, id) catch allocator.dupe(u8, id) catch null;
        if (display) |text| {
            defer allocator.free(text);
            copyCString(out_context_display, out_context_display_len, text);
        } else {
            copyCString(out_context_display, out_context_display_len, id);
        }
    } else {
        copyCString(out_context_id, out_context_id_len, "");
        copyCString(out_context_display, out_context_display_len, "");
    }

    copyCString(out_message, out_message_len, result.message);
    return owned.ptr;
}

pub export fn merrow_studio_shuffle_diagram(
    source_ptr: [*]const u8,
    source_len: u32,
    out_message: [*]u8,
    out_message_len: u32,
) callconv(.c) [*c]u8 {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const source = source_ptr[0..source_len];
    if (detectSequenceDiagram(source)) {
        copyCString(out_message, out_message_len, "Shuffle currently supports flowcharts only");
        return null;
    }

    const current_dir = currentFlowchartRankDir(allocator, source) catch {
        copyCString(out_message, out_message_len, "Shuffle couldn't parse the current flowchart");
        return null;
    };
    const best_dir = bestShuffleDirection(allocator, source) catch {
        copyCString(out_message, out_message_len, "Shuffle couldn't evaluate layout alternatives");
        return null;
    };

    if (best_dir == current_dir) {
        const message = std.fmt.allocPrint(allocator, "Shuffle kept direction {s}; it already scores best", .{rankDirText(current_dir)}) catch null;
        if (message) |text| {
            defer allocator.free(text);
            copyCString(out_message, out_message_len, text);
        } else {
            copyCString(out_message, out_message_len, "Shuffle kept the current direction");
        }
        return null;
    }

    const command = std.fmt.allocPrint(allocator, "direction {s}", .{rankDirText(best_dir)}) catch {
        copyCString(out_message, out_message_len, "Out of memory");
        return null;
    };
    defer allocator.free(command);

    const result = commands.applyCommand(allocator, source, command) catch {
        copyCString(out_message, out_message_len, "Shuffle couldn't rewrite the diagram source");
        return null;
    };
    defer allocator.free(result.source);
    defer allocator.free(result.message);

    const owned = c_allocator.alloc(u8, result.source.len + 1) catch {
        copyCString(out_message, out_message_len, "Out of memory");
        return null;
    };
    @memcpy(owned[0..result.source.len], result.source);
    owned[result.source.len] = 0;

    const message = std.fmt.allocPrint(allocator, "Shuffled layout by setting direction to {s}", .{rankDirText(best_dir)}) catch null;
    if (message) |text| {
        defer allocator.free(text);
        copyCString(out_message, out_message_len, text);
    } else {
        copyCString(out_message, out_message_len, result.message);
    }
    return owned.ptr;
}

fn describeContextNode(allocator: std.mem.Allocator, source: []const u8, node_id: []const u8) ![]u8 {
    var parser = Parser.init(allocator, source) catch return allocator.dupe(u8, node_id);
    defer parser.deinit();

    var graph = parser.parse() catch return allocator.dupe(u8, node_id);
    defer {
        normalize.freeDummyIds(allocator, &graph);
        graph.deinitDeep();
    }

    const node = graph.getNodePtr(node_id) orelse return allocator.dupe(u8, node_id);
    if (node.label) |label| {
        return allocator.dupe(u8, label);
    }
    return allocator.dupe(u8, node_id);
}

pub export fn merrow_studio_free_string(text: [*c]u8) callconv(.c) void {
    if (text == null) return;
    const ptr = text;
    const slice = std.mem.span(ptr);
    c_allocator.free(ptr[0 .. slice.len + 1]);
}

pub export fn merrow_studio_free_buffer(buffer: [*c]u8, buffer_len: u32) callconv(.c) void {
    if (buffer == null) return;
    c_allocator.free(buffer[0..buffer_len]);
}

pub export fn merrow_studio_free_scene(scene: ?*StudioScene) callconv(.c) void {
    const s = scene orelse return;

    if (s.subgraphs) |subgraphs| {
        for (subgraphs[0..s.subgraph_count]) |item| freeCString(c_allocator, item.title);
        c_allocator.free(subgraphs[0..s.subgraph_count]);
    }

    if (s.nodes) |nodes| {
        for (nodes[0..s.node_count]) |item| {
            freeCString(c_allocator, item.label);
            freeCString(c_allocator, item.subtitle);
            freeCString(c_allocator, item.attributes_text);
            freeCString(c_allocator, item.methods_text);
        }
        c_allocator.free(nodes[0..s.node_count]);
    }

    if (s.edges) |edges| {
        for (edges[0..s.edge_count]) |item| if (item.points) |points| c_allocator.free(points[0..item.point_count]);
        c_allocator.free(edges[0..s.edge_count]);
    }

    if (s.edge_labels) |labels| {
        for (labels[0..s.edge_label_count]) |item| freeCString(c_allocator, item.text);
        c_allocator.free(labels[0..s.edge_label_count]);
    }

    c_allocator.destroy(s);
}

pub export fn merrow_studio_free_editable_graph(graph: ?*StudioEditableGraph) callconv(.c) void {
    const g = graph orelse return;

    if (g.subgraphs) |subgraphs| {
        for (subgraphs[0..g.subgraph_count]) |item| {
            freeCString(c_allocator, item.id);
            freeCString(c_allocator, item.title);
            freeCString(c_allocator, item.parent_subgraph_id);
        }
        c_allocator.free(subgraphs[0..g.subgraph_count]);
    }

    if (g.nodes) |nodes| {
        for (nodes[0..g.node_count]) |item| {
            freeCString(c_allocator, item.id);
            freeCString(c_allocator, item.label);
            freeCString(c_allocator, item.subtitle);
            freeCString(c_allocator, item.attributes_text);
            freeCString(c_allocator, item.methods_text);
            freeCString(c_allocator, item.parent_subgraph_id);
        }
        c_allocator.free(nodes[0..g.node_count]);
    }

    if (g.edges) |edges| {
        for (edges[0..g.edge_count]) |item| {
            freeCString(c_allocator, item.source_id);
            freeCString(c_allocator, item.target_id);
            freeCString(c_allocator, item.label);
        }
        c_allocator.free(edges[0..g.edge_count]);
    }

    c_allocator.destroy(g);
}

pub export fn merrow_studio_check_mermaid_syntax(source_ptr: [*]const u8, source_len: u32, out_message: [*]u8, out_message_len: u32) callconv(.c) c_int {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const source = source_ptr[0..source_len];

    if (detectClassDiagram(source)) {
        var diagram = ClassParser.parse(allocator, source) catch |err| {
            copyCString(out_message, out_message_len, @errorName(err));
            return 1;
        };
        defer diagram.deinit();

        copyCString(out_message, out_message_len, "Syntax OK");
        return 0;
    }

    if (detectSequenceDiagram(source)) {
        var parser = SeqParser.init(allocator, source);
        var diagram = parser.parse() catch |err| {
            copyCString(out_message, out_message_len, @errorName(err));
            return 1;
        };
        defer diagram.deinit();

        copyCString(out_message, out_message_len, "Syntax OK");
        return 0;
    }

    if (detectErDiagram(source)) {
        var diagram = ErParser.parse(allocator, source) catch |err| {
            copyCString(out_message, out_message_len, @errorName(err));
            return 1;
        };
        defer diagram.deinit();

        copyCString(out_message, out_message_len, "Syntax OK");
        return 0;
    }

    if (detectStateDiagram(source)) {
        var diagram = StateParser.parse(allocator, source) catch |err| {
            copyCString(out_message, out_message_len, @errorName(err));
            return 1;
        };
        defer diagram.deinit();

        copyCString(out_message, out_message_len, "Syntax OK");
        return 0;
    }

    var parser = Parser.init(allocator, source) catch |err| {
        copyCString(out_message, out_message_len, @errorName(err));
        return 2;
    };
    defer parser.deinit();

    var graph = parser.parse() catch |err| {
        copyCString(out_message, out_message_len, @errorName(err));
        return 1;
    };
    defer {
        normalize.freeDummyIds(allocator, &graph);
        graph.deinitDeep();
    }

    copyCString(out_message, out_message_len, "Syntax OK");
    return 0;
}

fn editableGraphHasSubgraph(graph: *const StudioEditableGraph, expected_id: []const u8) bool {
    const subgraphs = graph.subgraphs orelse return false;
    for (subgraphs[0..graph.subgraph_count]) |item| {
        if (std.mem.eql(u8, std.mem.span(item.id), expected_id)) return true;
    }
    return false;
}

fn editableGraphHasEdge(graph: *const StudioEditableGraph, expected_source: []const u8, expected_target: []const u8) bool {
    const edges = graph.edges orelse return false;
    for (edges[0..graph.edge_count]) |item| {
        if (!std.mem.eql(u8, std.mem.span(item.source_id), expected_source)) continue;
        if (!std.mem.eql(u8, std.mem.span(item.target_id), expected_target)) continue;
        return true;
    }
    return false;
}

fn editableGraphEdgeMatches(
    graph: *const StudioEditableGraph,
    expected_source: []const u8,
    expected_target: []const u8,
    expected_line_style: u32,
    expected_has_arrow: bool,
    expected_has_source_arrow: bool,
) bool {
    const edges = graph.edges orelse return false;
    for (edges[0..graph.edge_count]) |item| {
        if (!std.mem.eql(u8, std.mem.span(item.source_id), expected_source)) continue;
        if (!std.mem.eql(u8, std.mem.span(item.target_id), expected_target)) continue;
        return item.line_style == expected_line_style and
            item.has_arrow == @intFromBool(expected_has_arrow) and
            item.has_source_arrow == @intFromBool(expected_has_source_arrow);
    }
    return false;
}

fn editableGraphEdgeMatchesEndStyles(
    graph: *const StudioEditableGraph,
    expected_source: []const u8,
    expected_target: []const u8,
    expected_line_style: u32,
    expected_source_end_style: u32,
    expected_target_end_style: u32,
) bool {
    const edges = graph.edges orelse return false;
    for (edges[0..graph.edge_count]) |item| {
        if (!std.mem.eql(u8, std.mem.span(item.source_id), expected_source)) continue;
        if (!std.mem.eql(u8, std.mem.span(item.target_id), expected_target)) continue;
        return item.line_style == expected_line_style and
            item.source_end_style == expected_source_end_style and
            item.target_end_style == expected_target_end_style;
    }
    return false;
}

fn editableGraphHasNode(graph: *const StudioEditableGraph, expected_id: []const u8) bool {
    const nodes = graph.nodes orelse return false;
    for (nodes[0..graph.node_count]) |item| {
        if (std.mem.eql(u8, std.mem.span(item.id), expected_id)) return true;
    }
    return false;
}

fn editableGraphNodeHasShape(graph: *const StudioEditableGraph, node_id: []const u8, expected_shape: u32) bool {
    const nodes = graph.nodes orelse return false;
    for (nodes[0..graph.node_count]) |item| {
        if (!std.mem.eql(u8, std.mem.span(item.id), node_id)) continue;
        return item.shape == expected_shape;
    }
    return false;
}

fn editableGraphNodeFieldMatches(
    graph: *const StudioEditableGraph,
    node_id: []const u8,
    subtitle: ?[]const u8,
    attributes_text: ?[]const u8,
    methods_text: ?[]const u8,
) bool {
    const nodes = graph.nodes orelse return false;
    for (nodes[0..graph.node_count]) |item| {
        if (!std.mem.eql(u8, std.mem.span(item.id), node_id)) continue;

        const item_subtitle = if (item.subtitle) |text| std.mem.span(text) else null;
        const item_attributes = if (item.attributes_text) |text| std.mem.span(text) else null;
        const item_methods = if (item.methods_text) |text| std.mem.span(text) else null;

        const subtitle_matches = if (subtitle) |expected| blk: {
            if (item_subtitle) |actual| break :blk std.mem.eql(u8, actual, expected);
            break :blk false;
        } else item_subtitle == null;

        const attributes_matches = if (attributes_text) |expected| blk: {
            if (item_attributes) |actual| break :blk std.mem.eql(u8, actual, expected);
            break :blk false;
        } else item_attributes == null;

        const methods_matches = if (methods_text) |expected| blk: {
            if (item_methods) |actual| break :blk std.mem.eql(u8, actual, expected);
            break :blk false;
        } else item_methods == null;

        return subtitle_matches and attributes_matches and methods_matches;
    }
    return false;
}

fn editableGraphNodeY(graph: *const StudioEditableGraph, node_id: []const u8) ?f64 {
    const nodes = graph.nodes orelse return null;
    for (nodes[0..graph.node_count]) |item| {
        if (std.mem.eql(u8, std.mem.span(item.id), node_id)) return item.y;
    }
    return null;
}

fn editableGraphNodeParentIs(graph: *const StudioEditableGraph, node_id: []const u8, expected_parent: []const u8) bool {
    const nodes = graph.nodes orelse return false;
    for (nodes[0..graph.node_count]) |item| {
        if (!std.mem.eql(u8, std.mem.span(item.id), node_id)) continue;
        if (item.parent_subgraph_id == null) return false;
        return std.mem.eql(u8, std.mem.span(item.parent_subgraph_id), expected_parent);
    }
    return false;
}

fn editableGraphSubgraphParentIs(graph: *const StudioEditableGraph, subgraph_id: []const u8, expected_parent: []const u8) bool {
    const subgraphs = graph.subgraphs orelse return false;
    for (subgraphs[0..graph.subgraph_count]) |item| {
        if (!std.mem.eql(u8, std.mem.span(item.id), subgraph_id)) continue;
        if (item.parent_subgraph_id == null) return false;
        return std.mem.eql(u8, std.mem.span(item.parent_subgraph_id), expected_parent);
    }
    return false;
}

fn loadTestDiagramFixture(allocator: std.mem.Allocator, relative_path: []const u8) ![]u8 {
    const fixture_path = try resolveRepoPath(allocator, relative_path);
    defer allocator.free(fixture_path);
    return std.fs.cwd().readFileAlloc(allocator, fixture_path, 1024 * 1024);
}

fn expectEditableGraphFixtureBuilds(relative_path: []const u8) !void {
    const source = try loadTestDiagramFixture(std.testing.allocator, relative_path);
    defer std.testing.allocator.free(source);

    const graph = try buildEditableGraphFromSource(std.testing.allocator, source);
    defer merrow_studio_free_editable_graph(graph);

    try std.testing.expect(graph.width > 0);
    try std.testing.expect(graph.height > 0);
    try std.testing.expect(graph.node_count > 0 or graph.subgraph_count > 0);
}

test "editable graph conversion preserves nested subgraphs and container edges" {
    const source =
        "flowchart LR\n" ++
        "    subgraph Customer_Tenant[Customer Tenant]\n" ++
        "        User[User]\n" ++
        "    end\n" ++
        "    subgraph LexisNexis_Cloud[LexisNexis Cloud]\n" ++
        "        subgraph LN_Services[LN Services]\n" ++
        "            API[API]\n" ++
        "        end\n" ++
        "        subgraph Foundation_Models[Foundation Models]\n" ++
        "            Model[Model]\n" ++
        "        end\n" ++
        "    end\n" ++
        "    User --> LN_Services\n" ++
        "    API --> Foundation_Models\n" ++
        "    Foundation_Models --> Model\n";

    const graph = try buildEditableGraphFromSource(std.testing.allocator, source);
    defer merrow_studio_free_editable_graph(graph);

    try std.testing.expect(graph.subgraph_count >= 4);
    try std.testing.expect(graph.node_count >= 3);
    try std.testing.expect(graph.edge_count >= 3);
    try std.testing.expect(graph.width > 0);
    try std.testing.expect(graph.height > 0);

    try std.testing.expect(editableGraphHasSubgraph(graph, "Customer_Tenant"));
    try std.testing.expect(editableGraphHasSubgraph(graph, "LexisNexis_Cloud"));
    try std.testing.expect(editableGraphHasSubgraph(graph, "LN_Services"));
    try std.testing.expect(editableGraphHasSubgraph(graph, "Foundation_Models"));
    try std.testing.expect(editableGraphNodeParentIs(graph, "User", "Customer_Tenant"));
    try std.testing.expect(editableGraphNodeParentIs(graph, "API", "LN_Services"));
    try std.testing.expect(editableGraphNodeParentIs(graph, "Model", "Foundation_Models"));
    try std.testing.expect(editableGraphSubgraphParentIs(graph, "LN_Services", "LexisNexis_Cloud"));
    try std.testing.expect(editableGraphSubgraphParentIs(graph, "Foundation_Models", "LexisNexis_Cloud"));

    try std.testing.expect(editableGraphHasEdge(graph, "User", "LN_Services"));
    try std.testing.expect(editableGraphHasEdge(graph, "API", "Foundation_Models"));
    try std.testing.expect(editableGraphHasEdge(graph, "Foundation_Models", "Model"));
}

test "editable graph conversion fixture flowchart simple" {
    try expectEditableGraphFixtureBuilds("test-diagrams/flowchart_simple.mmd");
}

test "editable graph conversion fixture flowchart subgraphs" {
    try expectEditableGraphFixtureBuilds("test-diagrams/flowchart_subgraphs.mmd");
}

test "editable graph conversion fixture flowchart nested" {
    try expectEditableGraphFixtureBuilds("test-diagrams/flowchart_nested.mmd");
}

test "editable graph conversion fixture ai platform" {
    const source = try loadTestDiagramFixture(std.testing.allocator, "test-diagrams/ai_platform.mmd");
    defer std.testing.allocator.free(source);

    const graph = try buildEditableGraphFromSource(std.testing.allocator, source);
    defer merrow_studio_free_editable_graph(graph);

    try std.testing.expect(graph.subgraph_count >= 2);
    try std.testing.expect(editableGraphHasSubgraph(graph, "LNE"));
    try std.testing.expect(editableGraphHasSubgraph(graph, "FP"));
    try std.testing.expect(editableGraphHasEdge(graph, "PROXY", "LLM"));
    try std.testing.expect(editableGraphHasEdge(graph, "U", "UI"));
}

test "editable graph conversion fixture sequence features" {
    const source = try loadTestDiagramFixture(std.testing.allocator, "test-diagrams/sequence_features.mmd");
    defer std.testing.allocator.free(source);

    const graph = try buildEditableGraphFromSource(std.testing.allocator, source);
    defer merrow_studio_free_editable_graph(graph);

    const first_message_y = editableGraphNodeY(graph, "message-0-from") orelse return error.TestUnexpectedResult;
    const second_message_y = editableGraphNodeY(graph, "message-1-from") orelse return error.TestUnexpectedResult;
    const self_message_y = editableGraphNodeY(graph, "message-4-anchor") orelse return error.TestUnexpectedResult;
    const footer_participant_y = editableGraphNodeY(graph, "U-footer") orelse return error.TestUnexpectedResult;

    try std.testing.expectEqual(@as(u32, @intFromEnum(StudioGraphType.sequence)), graph.graph_type);
    try std.testing.expect(graph.node_count >= 19);
    try std.testing.expect(graph.edge_count >= 12);
    try std.testing.expect(graph.subgraph_count >= 3);
    try std.testing.expect(editableGraphHasNode(graph, "U"));
    try std.testing.expect(editableGraphHasNode(graph, "U-footer"));
    try std.testing.expect(editableGraphHasNode(graph, "API"));
    try std.testing.expect(editableGraphHasNode(graph, "W"));
    try std.testing.expect(editableGraphHasNode(graph, "DB"));
    try std.testing.expect(editableGraphHasNode(graph, "note-0"));
    try std.testing.expect(editableGraphHasNode(graph, "message-0-from"));
    try std.testing.expect(editableGraphHasNode(graph, "message-0-to"));
    try std.testing.expect(editableGraphHasNode(graph, "message-4-anchor"));
    try std.testing.expect(editableGraphNodeHasShape(graph, "U", 3));
    try std.testing.expect(editableGraphHasSubgraph(graph, "fragment-0"));
    try std.testing.expect(editableGraphHasEdge(graph, "U", "U-footer"));
    try std.testing.expect(editableGraphHasEdge(graph, "API", "API-footer"));
    try std.testing.expect(editableGraphEdgeMatches(graph, "U", "U-footer", 1, false, false));
    try std.testing.expect(editableGraphHasEdge(graph, "message-0-from", "message-0-to"));
    try std.testing.expect(editableGraphHasEdge(graph, "message-4-anchor", "message-4-anchor"));
    try std.testing.expect(second_message_y > first_message_y);
    try std.testing.expect(self_message_y > second_message_y);
    try std.testing.expect(footer_participant_y > self_message_y);
}

test "editable graph conversion fixture class simple preserves compartments and relation styles" {
    const source = try loadTestDiagramFixture(std.testing.allocator, "test-diagrams/class_simple.mmd");
    defer std.testing.allocator.free(source);

    const graph = try buildEditableGraphFromSource(std.testing.allocator, source);
    defer merrow_studio_free_editable_graph(graph);

    try std.testing.expectEqual(@as(u32, @intFromEnum(StudioGraphType.class)), graph.graph_type);
    try std.testing.expectEqual(@as(usize, 3), graph.node_count);
    try std.testing.expectEqual(@as(usize, 2), graph.edge_count);
    try std.testing.expect(editableGraphNodeFieldMatches(
        graph,
        "Animal",
        null,
        "+String name\n+int age",
        "+makeSound()\n+move(int distance)",
    ));
    try std.testing.expect(editableGraphNodeFieldMatches(
        graph,
        "Dog",
        null,
        "+String breed",
        "+bark()\n+fetch(String item)",
    ));
    try std.testing.expect(editableGraphEdgeMatchesEndStyles(
        graph,
        "Animal",
        "Dog",
        0,
        1,
        0,
    ));
    try std.testing.expect(editableGraphEdgeMatchesEndStyles(
        graph,
        "Animal",
        "Cat",
        0,
        1,
        0,
    ));
}

test "editable graph conversion fixture er simple preserves entities and cardinalities" {
    const source = try loadTestDiagramFixture(std.testing.allocator, "test-diagrams/er_simple.mmd");
    defer std.testing.allocator.free(source);

    const graph = try buildEditableGraphFromSource(std.testing.allocator, source);
    defer merrow_studio_free_editable_graph(graph);

    try std.testing.expectEqual(@as(u32, @intFromEnum(StudioGraphType.er)), graph.graph_type);
    try std.testing.expectEqual(@as(usize, 3), graph.node_count);
    try std.testing.expectEqual(@as(usize, 2), graph.edge_count);
    try std.testing.expect(editableGraphNodeFieldMatches(
        graph,
        "CUSTOMER",
        null,
        "int\tid\tPK\nstring\tname\t\nstring\temail\t",
        null,
    ));
    try std.testing.expect(editableGraphEdgeMatchesEndStyles(
        graph,
        "CUSTOMER",
        "ORDER",
        0,
        6,
        8,
    ));
    try std.testing.expect(editableGraphEdgeMatchesEndStyles(
        graph,
        "ORDER",
        "LINE-ITEM",
        0,
        6,
        9,
    ));
}

test "editable graph conversion fixture er complex builds" {
    try expectEditableGraphFixtureBuilds("test-diagrams/er_complex.mmd");
}

test "editable graph conversion fixture saas architecture" {
    try expectEditableGraphFixtureBuilds("test-diagrams/saas_architecture.mmd");
}

test "editable graph can render to png bytes" {
    const source =
        \\flowchart TB
        \\    subgraph API["API"]
        \\        gateway[Gateway]
        \\    end
        \\    user((User)) --> gateway
    ;

    const graph = try buildEditableGraphFromSource(std.testing.allocator, source);
    defer merrow_studio_free_editable_graph(graph);

    var maybe_font = try loadFont(std.testing.allocator);
    defer if (maybe_font) |*loaded| loaded.deinit(std.testing.allocator);

    const png = try renderEditableGraphToBytes(
        std.testing.allocator,
        graph,
        if (maybe_font) |*loaded| loaded else null,
        2.0,
        1200,
        900,
    );
    defer std.testing.allocator.free(png);

    try std.testing.expect(png.len > 0);
}
