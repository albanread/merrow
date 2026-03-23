const std = @import("std");
const windows_canvas = @import("platform/windows/canvas.zig");

pub const StudioColor = windows_canvas.StudioColor;
pub const StudioEditableGraph = windows_canvas.StudioEditableGraph;
pub const StudioEditableNode = windows_canvas.StudioEditableNode;
pub const StudioEditableSubgraph = windows_canvas.StudioEditableSubgraph;
pub const StudioEditableEdge = windows_canvas.StudioEditableEdge;
pub const StudioMermaidSourceRecord = windows_canvas.state.StudioMermaidSourceRecord;

pub const magic = "MROW-FFM";
pub const version: u16 = 5;
const null_string_len = std.math.maxInt(u32);

pub const DeserializeError = error{
    InvalidMagic,
    UnsupportedVersion,
    TruncatedData,
    Overflow,
};

pub fn serializeGraph(allocator: std.mem.Allocator, graph: *const StudioEditableGraph) ![]u8 {
    var buffer = std.ArrayList(u8){};
    errdefer buffer.deinit(allocator);

    try buffer.appendSlice(allocator, magic);
    try appendU16(&buffer, allocator, version);
    try appendU32(&buffer, allocator, graph.graph_type);
    try appendU32(&buffer, allocator, graph.direction);
    try appendF64(&buffer, allocator, graph.width);
    try appendF64(&buffer, allocator, graph.height);
    try appendColor(&buffer, allocator, graph.background);

    try appendU32(&buffer, allocator, try castCount(graph.subgraph_count));
    if (graph.subgraphs) |subgraphs| {
        for (subgraphs[0..graph.subgraph_count]) |item| {
            try appendOptionalCString(&buffer, allocator, item.id);
            try appendOptionalCString(&buffer, allocator, item.title);
            try appendOptionalCString(&buffer, allocator, item.parent_subgraph_id);
            try appendF64(&buffer, allocator, item.x);
            try appendF64(&buffer, allocator, item.y);
            try appendF64(&buffer, allocator, item.width);
            try appendF64(&buffer, allocator, item.height);
            try appendF64(&buffer, allocator, item.corner_radius);
            try appendColor(&buffer, allocator, item.fill);
            try appendColor(&buffer, allocator, item.stroke);
            try appendF32(&buffer, allocator, item.stroke_width);
            try appendF64(&buffer, allocator, item.title_x);
            try appendF64(&buffer, allocator, item.title_y);
            try appendF32(&buffer, allocator, item.title_font_size);
            try appendColor(&buffer, allocator, item.title_color);
            try appendU32(&buffer, allocator, item.title_position);
        }
    }

    try appendU32(&buffer, allocator, try castCount(graph.node_count));
    if (graph.nodes) |nodes| {
        for (nodes[0..graph.node_count]) |item| {
            try appendOptionalCString(&buffer, allocator, item.id);
            try appendOptionalCString(&buffer, allocator, item.label);
            try appendOptionalCString(&buffer, allocator, item.subtitle);
            try appendOptionalCString(&buffer, allocator, item.attributes_text);
            try appendOptionalCString(&buffer, allocator, item.methods_text);
            try appendOptionalCString(&buffer, allocator, item.parent_subgraph_id);
            try appendU32(&buffer, allocator, item.shape);
            try appendF64(&buffer, allocator, item.x);
            try appendF64(&buffer, allocator, item.y);
            try appendF64(&buffer, allocator, item.width);
            try appendF64(&buffer, allocator, item.height);
            try appendColor(&buffer, allocator, item.fill);
            try appendColor(&buffer, allocator, item.body_fill);
            try appendColor(&buffer, allocator, item.stroke);
            try appendF32(&buffer, allocator, item.stroke_width);
            try appendColor(&buffer, allocator, item.label_color);
            try appendF32(&buffer, allocator, item.label_font_size);
        }
    }

    try appendU32(&buffer, allocator, try castCount(graph.edge_count));
    if (graph.edges) |edges| {
        for (edges[0..graph.edge_count]) |item| {
            try appendOptionalCString(&buffer, allocator, item.source_id);
            try appendOptionalCString(&buffer, allocator, item.target_id);
            try appendOptionalCString(&buffer, allocator, item.label);
            try appendF32(&buffer, allocator, item.label_font_size);
            try appendColor(&buffer, allocator, item.color);
            try appendF32(&buffer, allocator, item.thickness);
            try appendU32(&buffer, allocator, item.line_style);
            try appendU8(&buffer, allocator, item.has_arrow);
            try appendU8(&buffer, allocator, item.has_source_arrow);
            try appendU32(&buffer, allocator, item.source_end_style);
            try appendU32(&buffer, allocator, item.target_end_style);
        }
    }

    try appendU32(&buffer, allocator, try castCount(graph.source_record_count));
    if (graph.source_records) |records| {
        for (records[0..graph.source_record_count]) |item| {
            try appendU32(&buffer, allocator, item.kind);
            try appendOptionalCString(&buffer, allocator, item.object_id);
            try appendOptionalCString(&buffer, allocator, item.secondary_id);
            try appendOptionalCString(&buffer, allocator, item.aux_text);
            try appendU32(&buffer, allocator, item.match_index);
            try appendOptionalCString(&buffer, allocator, item.text);
        }
    }

    return buffer.toOwnedSlice(allocator);
}

pub fn deserializeGraph(blob: []const u8) !*StudioEditableGraph {
    var reader = Reader{ .blob = blob };

    const file_magic = try reader.readBytes(magic.len);
    if (!std.mem.eql(u8, file_magic, magic)) return DeserializeError.InvalidMagic;

    const file_version = try reader.readU16();
    if (file_version < 2 or file_version > version) return DeserializeError.UnsupportedVersion;

    const graph = try std.heap.c_allocator.create(StudioEditableGraph);
    errdefer std.heap.c_allocator.destroy(graph);

    graph.* = .{
        .graph_type = try reader.readU32(),
        .direction = if (file_version >= 4) try reader.readU32() else 0,
        .width = try reader.readF64(),
        .height = try reader.readF64(),
        .background = try reader.readColor(),
        .subgraphs = null,
        .subgraph_count = 0,
        .nodes = null,
        .node_count = 0,
        .edges = null,
        .edge_count = 0,
        .source_records = null,
        .source_record_count = 0,
    };
    errdefer freeGraph(graph);

    graph.subgraph_count = try reader.readCount();
    if (graph.subgraph_count > 0) {
        const subgraphs = try std.heap.c_allocator.alloc(StudioEditableSubgraph, graph.subgraph_count);
        graph.subgraphs = subgraphs.ptr;
        for (subgraphs, 0..) |*item, index| {
            item.* = .{
                .id = null,
                .title = null,
                .parent_subgraph_id = null,
                .x = 0,
                .y = 0,
                .width = 0,
                .height = 0,
                .corner_radius = 0,
                .fill = .{ .r = 0, .g = 0, .b = 0, .a = 0 },
                .stroke = .{ .r = 0, .g = 0, .b = 0, .a = 0 },
                .stroke_width = 0,
                .title_x = 0,
                .title_y = 0,
                .title_font_size = 0,
                .title_color = .{ .r = 0, .g = 0, .b = 0, .a = 0 },
                .title_position = 0,
            };
            errdefer freeSubgraphs(subgraphs[0 .. index + 1]);

            item.id = try reader.readOptionalCString();
            item.title = try reader.readOptionalCString();
            item.parent_subgraph_id = try reader.readOptionalCString();
            item.x = try reader.readF64();
            item.y = try reader.readF64();
            item.width = try reader.readF64();
            item.height = try reader.readF64();
            item.corner_radius = try reader.readF64();
            item.fill = try reader.readColor();
            item.stroke = try reader.readColor();
            item.stroke_width = try reader.readF32();
            item.title_x = try reader.readF64();
            item.title_y = try reader.readF64();
            item.title_font_size = try reader.readF32();
            item.title_color = try reader.readColor();
            item.title_position = if (file_version >= 3) try reader.readU32() else 0;
        }
    }

    graph.node_count = try reader.readCount();
    if (graph.node_count > 0) {
        const nodes = try std.heap.c_allocator.alloc(StudioEditableNode, graph.node_count);
        graph.nodes = nodes.ptr;
        for (nodes, 0..) |*item, index| {
            item.* = .{
                .id = null,
                .label = null,
                .subtitle = null,
                .attributes_text = null,
                .methods_text = null,
                .parent_subgraph_id = null,
                .shape = 0,
                .x = 0,
                .y = 0,
                .width = 0,
                .height = 0,
                .fill = .{ .r = 0, .g = 0, .b = 0, .a = 0 },
                .body_fill = .{ .r = 0, .g = 0, .b = 0, .a = 0 },
                .stroke = .{ .r = 0, .g = 0, .b = 0, .a = 0 },
                .stroke_width = 0,
                .label_color = .{ .r = 0, .g = 0, .b = 0, .a = 0 },
                .label_font_size = 0,
            };
            errdefer freeNodes(nodes[0 .. index + 1]);

            item.id = try reader.readOptionalCString();
            item.label = try reader.readOptionalCString();
            item.subtitle = try reader.readOptionalCString();
            item.attributes_text = try reader.readOptionalCString();
            item.methods_text = try reader.readOptionalCString();
            item.parent_subgraph_id = try reader.readOptionalCString();
            item.shape = try reader.readU32();
            item.x = try reader.readF64();
            item.y = try reader.readF64();
            item.width = try reader.readF64();
            item.height = try reader.readF64();
            item.fill = try reader.readColor();
            item.body_fill = try reader.readColor();
            item.stroke = try reader.readColor();
            item.stroke_width = try reader.readF32();
            item.label_color = try reader.readColor();
            item.label_font_size = try reader.readF32();
        }
    }

    graph.edge_count = try reader.readCount();
    if (graph.edge_count > 0) {
        const edges = try std.heap.c_allocator.alloc(StudioEditableEdge, graph.edge_count);
        graph.edges = edges.ptr;
        for (edges, 0..) |*item, index| {
            item.* = .{
                .source_id = null,
                .target_id = null,
                .label = null,
                .label_font_size = 0,
                .color = .{ .r = 0, .g = 0, .b = 0, .a = 0 },
                .thickness = 0,
                .line_style = 0,
                .has_arrow = 0,
                .has_source_arrow = 0,
                .source_end_style = 0,
                .target_end_style = 0,
            };
            errdefer freeEdges(edges[0 .. index + 1]);

            item.source_id = try reader.readOptionalCString();
            item.target_id = try reader.readOptionalCString();
            item.label = try reader.readOptionalCString();
            item.label_font_size = try reader.readF32();
            item.color = try reader.readColor();
            item.thickness = try reader.readF32();
            item.line_style = try reader.readU32();
            item.has_arrow = try reader.readU8();
            item.has_source_arrow = try reader.readU8();
            item.source_end_style = try reader.readU32();
            item.target_end_style = try reader.readU32();
        }
    }

    if (file_version >= 5) {
        graph.source_record_count = try reader.readCount();
        if (graph.source_record_count > 0) {
            const records = try std.heap.c_allocator.alloc(StudioMermaidSourceRecord, graph.source_record_count);
            graph.source_records = records.ptr;
            for (records, 0..) |*item, index| {
                item.* = .{
                    .kind = 0,
                    .object_id = null,
                    .secondary_id = null,
                    .aux_text = null,
                    .match_index = 0,
                    .text = null,
                };
                errdefer freeSourceRecords(records[0 .. index + 1]);

                item.kind = try reader.readU32();
                item.object_id = try reader.readOptionalCString();
                item.secondary_id = try reader.readOptionalCString();
                item.aux_text = try reader.readOptionalCString();
                item.match_index = try reader.readU32();
                item.text = try reader.readOptionalCString();
            }
        }
    }

    return graph;
}

pub fn freeGraph(graph: ?*StudioEditableGraph) void {
    const g = graph orelse return;
    if (g.subgraphs) |subgraphs| freeSubgraphs(subgraphs[0..g.subgraph_count]);
    if (g.nodes) |nodes| freeNodes(nodes[0..g.node_count]);
    if (g.edges) |edges| freeEdges(edges[0..g.edge_count]);
    if (g.source_records) |records| freeSourceRecords(records[0..g.source_record_count]);
    std.heap.c_allocator.destroy(g);
}

fn freeSubgraphs(subgraphs: []StudioEditableSubgraph) void {
    for (subgraphs) |item| {
        freeCString(item.id);
        freeCString(item.title);
        freeCString(item.parent_subgraph_id);
    }
    std.heap.c_allocator.free(subgraphs);
}

fn freeNodes(nodes: []StudioEditableNode) void {
    for (nodes) |item| {
        freeCString(item.id);
        freeCString(item.label);
        freeCString(item.subtitle);
        freeCString(item.attributes_text);
        freeCString(item.methods_text);
        freeCString(item.parent_subgraph_id);
    }
    std.heap.c_allocator.free(nodes);
}

fn freeEdges(edges: []StudioEditableEdge) void {
    for (edges) |item| {
        freeCString(item.source_id);
        freeCString(item.target_id);
        freeCString(item.label);
    }
    std.heap.c_allocator.free(edges);
}

fn freeSourceRecords(records: []StudioMermaidSourceRecord) void {
    for (records) |item| {
        freeCString(item.object_id);
        freeCString(item.secondary_id);
        freeCString(item.aux_text);
        freeCString(item.text);
    }
    std.heap.c_allocator.free(records);
}

fn freeCString(text: [*c]const u8) void {
    if (text == null) return;
    std.heap.c_allocator.free(@constCast(std.mem.span(text))[0 .. std.mem.span(text).len + 1]);
}

fn dupCString(text: []const u8) ![*c]const u8 {
    const buf = try std.heap.c_allocator.alloc(u8, text.len + 1);
    @memcpy(buf[0..text.len], text);
    buf[text.len] = 0;
    return buf.ptr;
}

fn castCount(count: usize) !u32 {
    return std.math.cast(u32, count) orelse DeserializeError.Overflow;
}

fn appendU8(buffer: *std.ArrayList(u8), allocator: std.mem.Allocator, value: u8) !void {
    try buffer.append(allocator, value);
}

fn appendU16(buffer: *std.ArrayList(u8), allocator: std.mem.Allocator, value: u16) !void {
    const le = std.mem.nativeToLittle(u16, value);
    try buffer.appendSlice(allocator, std.mem.asBytes(&le));
}

fn appendU32(buffer: *std.ArrayList(u8), allocator: std.mem.Allocator, value: u32) !void {
    const le = std.mem.nativeToLittle(u32, value);
    try buffer.appendSlice(allocator, std.mem.asBytes(&le));
}

fn appendF32(buffer: *std.ArrayList(u8), allocator: std.mem.Allocator, value: f32) !void {
    try appendU32(buffer, allocator, @bitCast(value));
}

fn appendF64(buffer: *std.ArrayList(u8), allocator: std.mem.Allocator, value: f64) !void {
    const bits: u64 = @bitCast(value);
    const le = std.mem.nativeToLittle(u64, bits);
    try buffer.appendSlice(allocator, std.mem.asBytes(&le));
}

fn appendColor(buffer: *std.ArrayList(u8), allocator: std.mem.Allocator, color: StudioColor) !void {
    try buffer.appendSlice(allocator, &.{ color.r, color.g, color.b, color.a });
}

fn appendOptionalCString(buffer: *std.ArrayList(u8), allocator: std.mem.Allocator, text: [*c]const u8) !void {
    if (text == null) {
        try appendU32(buffer, allocator, null_string_len);
        return;
    }

    const slice = std.mem.span(text);
    try appendU32(buffer, allocator, try castCount(slice.len));
    try buffer.appendSlice(allocator, slice);
}

const Reader = struct {
    blob: []const u8,
    offset: usize = 0,

    fn readBytes(self: *Reader, len: usize) ![]const u8 {
        if (self.offset + len > self.blob.len) return DeserializeError.TruncatedData;
        const bytes = self.blob[self.offset .. self.offset + len];
        self.offset += len;
        return bytes;
    }

    fn readU8(self: *Reader) !u8 {
        return (try self.readBytes(1))[0];
    }

    fn readU16(self: *Reader) !u16 {
        const bytes = try self.readBytes(@sizeOf(u16));
        return std.mem.readInt(u16, bytes[0..@sizeOf(u16)], .little);
    }

    fn readU32(self: *Reader) !u32 {
        const bytes = try self.readBytes(@sizeOf(u32));
        return std.mem.readInt(u32, bytes[0..@sizeOf(u32)], .little);
    }

    fn readF32(self: *Reader) !f32 {
        return @bitCast(try self.readU32());
    }

    fn readF64(self: *Reader) !f64 {
        const bytes = try self.readBytes(@sizeOf(u64));
        const bits = std.mem.readInt(u64, bytes[0..@sizeOf(u64)], .little);
        return @bitCast(bits);
    }

    fn readColor(self: *Reader) !StudioColor {
        const bytes = try self.readBytes(4);
        return .{ .r = bytes[0], .g = bytes[1], .b = bytes[2], .a = bytes[3] };
    }

    fn readCount(self: *Reader) !usize {
        return std.math.cast(usize, try self.readU32()) orelse DeserializeError.Overflow;
    }

    fn readOptionalCString(self: *Reader) ![*c]const u8 {
        const len = try self.readU32();
        if (len == null_string_len) return null;
        const count = std.math.cast(usize, len) orelse return DeserializeError.Overflow;
        const bytes = try self.readBytes(count);
        return dupCString(bytes);
    }
};

test "ffm serializer round-trips editable graph" {
    const graph = try makeTestGraph();
    defer freeGraph(graph);

    const blob = try serializeGraph(std.testing.allocator, graph);
    defer std.testing.allocator.free(blob);

    const decoded = try deserializeGraph(blob);
    defer freeGraph(decoded);

    try std.testing.expectEqual(version, std.mem.readInt(u16, blob[magic.len .. magic.len + 2], .little));
    try std.testing.expectEqual(graph.graph_type, decoded.graph_type);
    try std.testing.expectEqual(graph.subgraph_count, decoded.subgraph_count);
    try std.testing.expectEqual(graph.node_count, decoded.node_count);
    try std.testing.expectEqual(graph.edge_count, decoded.edge_count);
    try std.testing.expectEqualDeep(graph.background, decoded.background);

    try std.testing.expectEqualStrings("group-1", std.mem.span(decoded.subgraphs[0].id));
    try std.testing.expectEqualStrings("Node One", std.mem.span(decoded.nodes[0].label));
    try std.testing.expectEqualStrings("node-1", std.mem.span(decoded.edges[0].source_id));
    try std.testing.expectEqualStrings("node-2", std.mem.span(decoded.edges[0].target_id));
    try std.testing.expectEqual(@as(u32, 3), decoded.edges[0].target_end_style);
}

test "ffm serializer rejects invalid magic" {
    var blob = [_]u8{ 0, 1, 2, 3, 4, 5, 6, 7, 0, 0 };
    try std.testing.expectError(DeserializeError.InvalidMagic, deserializeGraph(&blob));
}

fn makeTestGraph() !*StudioEditableGraph {
    const graph = try std.heap.c_allocator.create(StudioEditableGraph);
    errdefer std.heap.c_allocator.destroy(graph);

    const subgraphs = try std.heap.c_allocator.alloc(StudioEditableSubgraph, 1);
    errdefer std.heap.c_allocator.free(subgraphs);
    subgraphs[0] = .{
        .id = try dupCString("group-1"),
        .title = try dupCString("Group One"),
        .parent_subgraph_id = null,
        .x = 10,
        .y = 20,
        .width = 200,
        .height = 120,
        .corner_radius = 8,
        .fill = .{ .r = 240, .g = 241, .b = 242, .a = 255 },
        .stroke = .{ .r = 50, .g = 60, .b = 70, .a = 255 },
        .stroke_width = 2.5,
        .title_x = 30,
        .title_y = 28,
        .title_font_size = 16,
        .title_color = .{ .r = 10, .g = 20, .b = 30, .a = 255 },
    };

    const nodes = try std.heap.c_allocator.alloc(StudioEditableNode, 2);
    errdefer std.heap.c_allocator.free(nodes);
    nodes[0] = .{
        .id = try dupCString("node-1"),
        .label = try dupCString("Node One"),
        .subtitle = try dupCString("Subtitle"),
        .attributes_text = try dupCString("id:int"),
        .methods_text = try dupCString("run()"),
        .parent_subgraph_id = try dupCString("group-1"),
        .shape = 4,
        .x = 40,
        .y = 60,
        .width = 90,
        .height = 48,
        .fill = .{ .r = 255, .g = 250, .b = 240, .a = 255 },
        .body_fill = .{ .r = 250, .g = 245, .b = 235, .a = 255 },
        .stroke = .{ .r = 20, .g = 30, .b = 40, .a = 255 },
        .stroke_width = 1.5,
        .label_color = .{ .r = 5, .g = 6, .b = 7, .a = 255 },
        .label_font_size = 13,
    };
    nodes[1] = .{
        .id = try dupCString("node-2"),
        .label = try dupCString("Node Two"),
        .subtitle = null,
        .attributes_text = null,
        .methods_text = null,
        .parent_subgraph_id = null,
        .shape = 2,
        .x = 180,
        .y = 60,
        .width = 100,
        .height = 52,
        .fill = .{ .r = 230, .g = 240, .b = 250, .a = 255 },
        .body_fill = .{ .r = 230, .g = 240, .b = 250, .a = 255 },
        .stroke = .{ .r = 40, .g = 50, .b = 60, .a = 255 },
        .stroke_width = 2,
        .label_color = .{ .r = 11, .g = 12, .b = 13, .a = 255 },
        .label_font_size = 14,
    };

    const edges = try std.heap.c_allocator.alloc(StudioEditableEdge, 1);
    errdefer std.heap.c_allocator.free(edges);
    edges[0] = .{
        .source_id = try dupCString("node-1"),
        .target_id = try dupCString("node-2"),
        .label = try dupCString("connects"),
        .label_font_size = 12,
        .color = .{ .r = 90, .g = 91, .b = 92, .a = 255 },
        .thickness = 1.75,
        .line_style = 1,
        .has_arrow = 1,
        .has_source_arrow = 0,
        .source_end_style = 0,
        .target_end_style = 3,
    };

    graph.* = .{
        .width = 320,
        .height = 180,
        .graph_type = 2,
        .direction = 0,
        .background = .{ .r = 255, .g = 255, .b = 255, .a = 255 },
        .subgraphs = subgraphs.ptr,
        .subgraph_count = subgraphs.len,
        .nodes = nodes.ptr,
        .node_count = nodes.len,
        .edges = edges.ptr,
        .edge_count = edges.len,
        .source_records = null,
        .source_record_count = 0,
    };
    return graph;
}
