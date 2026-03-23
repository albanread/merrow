const std = @import("std");
const preview = @import("preview.zig");
const mermaid_serializer = @import("mermaid_serializer.zig");
const windows_canvas = @import("platform/windows/canvas.zig");

const StudioMermaidSourceRecord = windows_canvas.state.StudioMermaidSourceRecord;

pub fn graphHasSourceRecords(graph: *const windows_canvas.StudioEditableGraph) bool {
    return graph.source_record_count > 0 and graph.source_records != null;
}

fn canonicalGraph(graph: *const windows_canvas.StudioEditableGraph) windows_canvas.StudioEditableGraph {
    var canonical = graph.*;
    canonical.source_records = null;
    canonical.source_record_count = 0;
    return canonical;
}

pub fn serializeForMenuExport(
    allocator: std.mem.Allocator,
    active_graph: *const windows_canvas.StudioEditableGraph,
    fallback_source: ?[]const u8,
) ![]u8 {
    if (graphHasSourceRecords(active_graph)) {
        var canonical_graph = canonicalGraph(active_graph);
        return mermaid_serializer.serializeGraph(allocator, &canonical_graph);
    }

    const source = fallback_source orelse {
        var canonical_graph = canonicalGraph(active_graph);
        return mermaid_serializer.serializeGraph(allocator, &canonical_graph);
    };
    const rebuilt = try preview.buildEditableGraphForZigCaller(allocator, source);
    defer preview.freeEditableGraphForZigCaller(rebuilt);
    const rebuilt_canvas: *const windows_canvas.StudioEditableGraph = @ptrCast(rebuilt);
    var rebuilt_canonical = canonicalGraph(rebuilt_canvas);
    return mermaid_serializer.serializeGraph(allocator, &rebuilt_canonical);
}

fn stripAnnotationCommentsForTest(allocator: std.mem.Allocator, source: []const u8) ![]u8 {
    var buffer = std.ArrayList(u8){};
    errdefer buffer.deinit(allocator);

    var line_iter = std.mem.splitScalar(u8, source, '\n');
    var wrote_any = false;
    while (line_iter.next()) |raw_line| {
        const line_no_cr = std.mem.trimRight(u8, raw_line, "\r");
        const trimmed = std.mem.trim(u8, line_no_cr, " \t");
        if (std.mem.startsWith(u8, trimmed, "%% @")) continue;
        if (wrote_any) try buffer.append(allocator, '\n');
        try buffer.appendSlice(allocator, std.mem.trimRight(u8, line_no_cr, " \t"));
        wrote_any = true;
    }
    return buffer.toOwnedSlice(allocator);
}

test "menu export rebuilds from source when active graph is legacy garbage" {
    const allocator = std.testing.allocator;
    const source =
        "flowchart TD\n" ++
        "    subgraph Cloud[Cloud Platform]\n" ++
        "        subgraph Frontend[Frontend Tier]\n" ++
        "            WebApp[React App]\n" ++
        "            CDN[CDN Cache]\n" ++
        "            WebApp --> CDN\n" ++
        "        end\n" ++
        "        subgraph Backend[Backend Tier]\n" ++
        "            subgraph API[API Layer]\n" ++
        "                Gateway[API Gateway]\n" ++
        "                Auth[Auth Service]\n" ++
        "                Gateway --> Auth\n" ++
        "            end\n" ++
        "            subgraph Workers[Worker Pool]\n" ++
        "                W1[Worker 1]\n" ++
        "                W2[Worker 2]\n" ++
        "                W3[Worker 3]\n" ++
        "            end\n" ++
        "            Auth --> W1\n" ++
        "            Auth --> W2\n" ++
        "        end\n" ++
        "        subgraph Data[Data Tier]\n" ++
        "            DB[(Database)]\n" ++
        "            Cache[(Redis)]\n" ++
        "            DB --> Cache\n" ++
        "        end\n" ++
        "    end\n\n" ++
        "    User[User] --> WebApp\n" ++
        "    CDN --> Gateway\n" ++
        "    W1 --> DB\n" ++
        "    W2 --> DB\n" ++
        "    W3 --> Cache\n";

    var bad_nodes = [_]windows_canvas.StudioEditableNode{
        .{
            .id = ">",
            .label = ">",
            .subtitle = null,
            .attributes_text = null,
            .methods_text = null,
            .parent_subgraph_id = null,
            .shape = 0,
            .x = 10,
            .y = 10,
            .width = 84,
            .height = 44,
            .fill = .{ .r = 255, .g = 255, .b = 255, .a = 255 },
            .body_fill = .{ .r = 255, .g = 255, .b = 255, .a = 255 },
            .stroke = .{ .r = 0, .g = 0, .b = 0, .a = 255 },
            .stroke_width = 1.0,
            .label_color = .{ .r = 0, .g = 0, .b = 0, .a = 255 },
            .label_font_size = 14.0,
        },
        .{
            .id = "Auth",
            .label = "Auth Service",
            .subtitle = null,
            .attributes_text = null,
            .methods_text = null,
            .parent_subgraph_id = null,
            .shape = 0,
            .x = 120,
            .y = 10,
            .width = 100,
            .height = 44,
            .fill = .{ .r = 255, .g = 255, .b = 255, .a = 255 },
            .body_fill = .{ .r = 255, .g = 255, .b = 255, .a = 255 },
            .stroke = .{ .r = 0, .g = 0, .b = 0, .a = 255 },
            .stroke_width = 1.0,
            .label_color = .{ .r = 0, .g = 0, .b = 0, .a = 255 },
            .label_font_size = 14.0,
        },
    };
    var bad_edges = [_]windows_canvas.StudioEditableEdge{
        .{
            .source_id = "Auth",
            .target_id = ">",
            .label = null,
            .label_font_size = 11.0,
            .color = .{ .r = 0x50, .g = 0x50, .b = 0x50, .a = 255 },
            .thickness = 2.0,
            .line_style = 0,
            .has_arrow = 0,
            .has_source_arrow = 0,
            .source_end_style = 0,
            .target_end_style = 0,
        },
    };
    var legacy_graph = windows_canvas.StudioEditableGraph{
        .width = 300,
        .height = 150,
        .graph_type = 0,
        .direction = 0,
        .background = .{ .r = 255, .g = 255, .b = 255, .a = 255 },
        .subgraphs = null,
        .subgraph_count = 0,
        .nodes = &bad_nodes,
        .node_count = bad_nodes.len,
        .edges = &bad_edges,
        .edge_count = bad_edges.len,
        .source_records = null,
        .source_record_count = 0,
    };

    const exported = try serializeForMenuExport(allocator, &legacy_graph, source);
    defer allocator.free(exported);

    const normalized = try stripAnnotationCommentsForTest(allocator, exported);
    defer allocator.free(normalized);

    try std.testing.expect(std.mem.indexOf(u8, normalized, "\">\"") == null);
    try std.testing.expect(std.mem.indexOf(u8, normalized, "Auth --- \">\"") == null);
    try std.testing.expect(std.mem.indexOf(u8, normalized, "Auth --> W1") != null);
    try std.testing.expect(std.mem.indexOf(u8, normalized, "User[User]") != null);
    try std.testing.expect(std.mem.indexOf(u8, normalized, "User --> WebApp") != null);
}

test "menu export flowchart captures edited inline node state" {
    const allocator = std.testing.allocator;

    var nodes = [_]windows_canvas.StudioEditableNode{
        .{
            .id = "User",
            .label = "User",
            .subtitle = null,
            .attributes_text = null,
            .methods_text = null,
            .parent_subgraph_id = null,
            .shape = 0,
            .x = 10,
            .y = 10,
            .width = 100,
            .height = 44,
            .fill = .{ .r = 0xff, .g = 0xcc, .b = 0xaa, .a = 255 },
            .body_fill = .{ .r = 0xff, .g = 0xcc, .b = 0xaa, .a = 255 },
            .stroke = .{ .r = 0x64, .g = 0x64, .b = 0x96, .a = 255 },
            .stroke_width = 2.0,
            .label_color = .{ .r = 0x28, .g = 0x28, .b = 0x28, .a = 255 },
            .label_font_size = 14.0,
        },
        .{
            .id = "WebApp",
            .label = "React App",
            .subtitle = null,
            .attributes_text = null,
            .methods_text = null,
            .parent_subgraph_id = null,
            .shape = 0,
            .x = 140,
            .y = 10,
            .width = 100,
            .height = 44,
            .fill = .{ .r = 240, .g = 240, .b = 250, .a = 255 },
            .body_fill = .{ .r = 240, .g = 240, .b = 250, .a = 255 },
            .stroke = .{ .r = 100, .g = 100, .b = 150, .a = 255 },
            .stroke_width = 2.0,
            .label_color = .{ .r = 40, .g = 40, .b = 40, .a = 255 },
            .label_font_size = 16.0,
        },
    };
    var edges = [_]windows_canvas.StudioEditableEdge{
        .{
            .source_id = "User",
            .target_id = "WebApp",
            .label = null,
            .label_font_size = 11.0,
            .color = .{ .r = 0x50, .g = 0x50, .b = 0x50, .a = 255 },
            .thickness = 2.0,
            .line_style = 0,
            .has_arrow = 1,
            .has_source_arrow = 0,
            .source_end_style = 0,
            .target_end_style = 4,
        },
    };
    var records = [_]StudioMermaidSourceRecord{
        .{ .kind = 1, .object_id = null, .secondary_id = null, .aux_text = null, .match_index = 0, .text = "flowchart TD" },
        .{ .kind = 3, .object_id = "User", .secondary_id = "WebApp", .aux_text = null, .match_index = 0, .text = "    User[User] --> WebApp" },
    };
    var graph = windows_canvas.StudioEditableGraph{
        .width = 260,
        .height = 120,
        .graph_type = 0,
        .direction = 0,
        .background = .{ .r = 255, .g = 255, .b = 255, .a = 255 },
        .subgraphs = null,
        .subgraph_count = 0,
        .nodes = &nodes,
        .node_count = nodes.len,
        .edges = &edges,
        .edge_count = edges.len,
        .source_records = &records,
        .source_record_count = records.len,
    };

    const exported = try serializeForMenuExport(allocator, &graph, null);
    defer allocator.free(exported);

    try std.testing.expect(std.mem.indexOf(u8, exported, "%% @shape=rect,10,10,100,44 @fill=#ffccaa") != null);
    try std.testing.expect(std.mem.indexOf(u8, exported, "User[User]") != null);
    try std.testing.expect(std.mem.indexOf(u8, exported, "User --> WebApp") != null);
}

test "menu export class diagram captures edited node annotations even with source records" {
    const allocator = std.testing.allocator;

    var nodes = [_]windows_canvas.StudioEditableNode{
        .{
            .id = "User",
            .label = "User",
            .subtitle = null,
            .attributes_text = null,
            .methods_text = null,
            .parent_subgraph_id = null,
            .shape = 0,
            .x = 24,
            .y = 30,
            .width = 120,
            .height = 52,
            .fill = .{ .r = 0xff, .g = 0xdd, .b = 0x88, .a = 255 },
            .body_fill = .{ .r = 0xff, .g = 0xdd, .b = 0x88, .a = 255 },
            .stroke = .{ .r = 0x44, .g = 0x55, .b = 0x66, .a = 255 },
            .stroke_width = 3.0,
            .label_color = .{ .r = 0x11, .g = 0x22, .b = 0x33, .a = 255 },
            .label_font_size = 15.0,
        },
        .{
            .id = "Account",
            .label = "Account",
            .subtitle = null,
            .attributes_text = null,
            .methods_text = null,
            .parent_subgraph_id = null,
            .shape = 0,
            .x = 210,
            .y = 30,
            .width = 140,
            .height = 52,
            .fill = .{ .r = 0xee, .g = 0xee, .b = 0xf8, .a = 255 },
            .body_fill = .{ .r = 0xee, .g = 0xee, .b = 0xf8, .a = 255 },
            .stroke = .{ .r = 0x55, .g = 0x55, .b = 0x88, .a = 255 },
            .stroke_width = 2.0,
            .label_color = .{ .r = 0x20, .g = 0x20, .b = 0x20, .a = 255 },
            .label_font_size = 14.0,
        },
    };
    var edges = [_]windows_canvas.StudioEditableEdge{
        .{
            .source_id = "User",
            .target_id = "Account",
            .label = null,
            .label_font_size = 11.0,
            .color = .{ .r = 0x50, .g = 0x50, .b = 0x50, .a = 255 },
            .thickness = 2.0,
            .line_style = 0,
            .has_arrow = 1,
            .has_source_arrow = 0,
            .source_end_style = 0,
            .target_end_style = 4,
        },
    };
    var records = [_]StudioMermaidSourceRecord{
        .{ .kind = 1, .object_id = null, .secondary_id = null, .aux_text = null, .match_index = 0, .text = "classDiagram" },
        .{ .kind = 3, .object_id = "User", .secondary_id = "Account", .aux_text = null, .match_index = 0, .text = "    User --> Account" },
    };
    var graph = windows_canvas.StudioEditableGraph{
        .width = 380,
        .height = 120,
        .graph_type = 2,
        .direction = 0,
        .background = .{ .r = 255, .g = 255, .b = 255, .a = 255 },
        .subgraphs = null,
        .subgraph_count = 0,
        .nodes = &nodes,
        .node_count = nodes.len,
        .edges = &edges,
        .edge_count = edges.len,
        .source_records = &records,
        .source_record_count = records.len,
    };

    const exported = try serializeForMenuExport(allocator, &graph, null);
    defer allocator.free(exported);

    try std.testing.expect(std.mem.indexOf(u8, exported, "%% @shape=rect,24,30,120,52 @fill=#ffdd88") != null);
    try std.testing.expect(std.mem.indexOf(u8, exported, "@stroke=#445566") != null);
    try std.testing.expect(std.mem.indexOf(u8, exported, "@ink=#112233") != null);
    try std.testing.expect(std.mem.indexOf(u8, exported, "class User") != null);
}
