const std = @import("std");
const windows_canvas = @import("platform/windows/canvas.zig");

pub const StudioColor = windows_canvas.StudioColor;
pub const StudioEditableGraph = windows_canvas.StudioEditableGraph;
pub const StudioEditableNode = windows_canvas.StudioEditableNode;
pub const StudioEditableSubgraph = windows_canvas.StudioEditableSubgraph;
pub const StudioEditableEdge = windows_canvas.StudioEditableEdge;
pub const StudioMermaidSourceRecord = windows_canvas.state.StudioMermaidSourceRecord;

// Direction constants: 0=TD, 1=LR, 2=BT, 3=RL
// Graph type constants: 0=flowchart, 1=sequence, 2=class, 3=er, 4=state

pub fn serializeGraph(allocator: std.mem.Allocator, graph: *const StudioEditableGraph) ![]u8 {
    var buffer = std.ArrayList(u8){};
    errdefer buffer.deinit(allocator);

    const writer = buffer.writer(allocator);

    switch (graph.graph_type) {
        0 => try writeFlowchart(writer, graph),
        1 => try writeSequenceDiagram(writer, graph),
        2 => try writeClassDiagram(writer, graph),
        3 => try writeErDiagram(writer, graph),
        4 => try writeStateDiagram(writer, graph),
        else => try writer.writeAll("graph TD\n"),
    }

    return buffer.toOwnedSlice(allocator);
}

const mermaid_record_kind_raw: u32 = 0;
const mermaid_record_kind_header: u32 = 1;
const mermaid_record_kind_node: u32 = 2;
const mermaid_record_kind_edge: u32 = 3;
const mermaid_record_kind_subgraph_start: u32 = 4;
const mermaid_record_kind_subgraph_end: u32 = 5;

const OpenSubgraph = struct {
    id: ?[]const u8,
    emitted: bool,
    indent: usize,
};

fn writeRawSourceRecords(writer: anytype, records: []const StudioMermaidSourceRecord) !void {
    for (records, 0..) |record, idx| {
        if (idx > 0) try writer.writeByte('\n');
        try writer.writeAll(cStr(record.text));
    }
}

fn writeFlowchartFromSourceRecords(allocator: std.mem.Allocator, writer: anytype, graph: *const StudioEditableGraph, records: []const StudioMermaidSourceRecord) !bool {
    const subgraphs = if (graph.subgraphs) |items| items[0..graph.subgraph_count] else &[_]StudioEditableSubgraph{};
    const nodes = if (graph.nodes) |items| items[0..graph.node_count] else &[_]StudioEditableNode{};
    const edges = if (graph.edges) |items| items[0..graph.edge_count] else &[_]StudioEditableEdge{};

    const seen_subgraphs = try allocator.alloc(bool, subgraphs.len);
    defer allocator.free(seen_subgraphs);
    @memset(seen_subgraphs, false);

    const seen_nodes = try allocator.alloc(bool, nodes.len);
    defer allocator.free(seen_nodes);
    @memset(seen_nodes, false);

    const seen_edges = try allocator.alloc(bool, edges.len);
    defer allocator.free(seen_edges);
    @memset(seen_edges, false);

    var open_stack = std.ArrayListUnmanaged(OpenSubgraph){};
    defer open_stack.deinit(allocator);

    var wrote_any = false;
    var wrote_header = false;
    var header_keyword: []const u8 = "graph";
    var suppress_depth: usize = 0;

    for (records) |record| {
        const raw_text = cStr(record.text);
        const active_parent = currentOpenParent(open_stack.items);

        if (suppress_depth > 0) {
            switch (record.kind) {
                mermaid_record_kind_subgraph_start => {
                    suppress_depth += 1;
                    try open_stack.append(allocator, .{ .id = null, .emitted = false, .indent = recordIndent(raw_text) });
                },
                mermaid_record_kind_subgraph_end => {
                    if (open_stack.items.len > 0) _ = open_stack.pop();
                    suppress_depth -= 1;
                },
                else => {},
            }
            continue;
        }

        switch (record.kind) {
            mermaid_record_kind_raw => {
                try writeRecordedLine(writer, raw_text, &wrote_any);
            },
            mermaid_record_kind_header => {
                header_keyword = headerKeyword(raw_text);
                wrote_header = true;
                if (headerDirectionMatches(raw_text, graph.direction)) {
                    try writeRecordedLine(writer, raw_text, &wrote_any);
                } else {
                    try writeFlowchartHeaderLine(writer, header_keyword, graph.direction, &wrote_any);
                }
            },
            mermaid_record_kind_subgraph_start => {
                const sg_id = if (record.object_id) |ptr| std.mem.span(ptr) else continue;
                const sg_idx = findSubgraphIndexById(subgraphs, sg_id) orelse {
                    suppress_depth = 1;
                    try open_stack.append(allocator, .{ .id = null, .emitted = false, .indent = recordIndent(raw_text) });
                    continue;
                };
                const subgraph = &subgraphs[sg_idx];
                if (!parentIdMatches(subgraph.parent_subgraph_id, active_parent)) {
                    suppress_depth = 1;
                    try open_stack.append(allocator, .{ .id = null, .emitted = false, .indent = recordIndent(raw_text) });
                    continue;
                }
                seen_subgraphs[sg_idx] = true;
                if (wrote_any) try writer.writeByte('\n');
                try writeSubgraphAnnotation(writer, subgraph, recordIndent(raw_text));
                try writeIndent(writer, recordIndent(raw_text));
                try writer.writeAll(std.mem.trimLeft(u8, raw_text, " \t"));
                wrote_any = true;
                try open_stack.append(allocator, .{ .id = sg_id, .emitted = true, .indent = recordIndent(raw_text) });
            },
            mermaid_record_kind_subgraph_end => {
                const open = if (open_stack.items.len > 0) open_stack.pop().? else OpenSubgraph{ .id = null, .emitted = false, .indent = recordIndent(raw_text) };
                if (!open.emitted) continue;
                try writeRemainingFlowchartChildren(writer, graph, open.id, open.indent + 1, seen_subgraphs, seen_nodes, &wrote_any);
                try writeRecordedLine(writer, raw_text, &wrote_any);
            },
            mermaid_record_kind_node => {
                const node_id = if (record.object_id) |ptr| std.mem.span(ptr) else continue;
                const node_idx = findNodeIndexById(nodes, node_id) orelse continue;
                const node = &nodes[node_idx];
                if (!parentIdMatches(node.parent_subgraph_id, active_parent)) continue;
                seen_nodes[node_idx] = true;
                if (wrote_any) try writer.writeByte('\n');
                try writeNodeAnnotation(writer, node, recordIndent(raw_text));
                try writeIndent(writer, recordIndent(raw_text));
                try writer.writeAll(std.mem.trimLeft(u8, raw_text, " \t"));
                wrote_any = true;
            },
            mermaid_record_kind_edge => {
                const edge_idx = findEdgeRecordMatch(edges, record, seen_edges) orelse continue;
                const edge = &edges[edge_idx];
                markBoundEdgeEndpointNodesSeen(nodes, seen_nodes, record);
                seen_edges[edge_idx] = true;
                if (wrote_any) try writer.writeByte('\n');
                try writeEdgeAnnotation(writer, edges, edge_idx, edge, recordIndent(raw_text));
                try writeIndent(writer, recordIndent(raw_text));
                try writer.writeAll(std.mem.trimLeft(u8, raw_text, " \t"));
                wrote_any = true;
            },
            else => try writeRecordedLine(writer, raw_text, &wrote_any),
        }
    }

    while (open_stack.items.len > 0) {
        const open = open_stack.pop().?;
        if (!open.emitted) continue;
        try writeRemainingFlowchartChildren(writer, graph, open.id, open.indent + 1, seen_subgraphs, seen_nodes, &wrote_any);
        try writeIndent(writer, open.indent);
        if (wrote_any) try writer.writeByte('\n');
        try writer.writeAll("end");
        wrote_any = true;
    }

    if (!wrote_header) {
        try writeFlowchartHeaderLine(writer, header_keyword, graph.direction, &wrote_any);
    }

    try writeRemainingFlowchartChildren(writer, graph, null, 1, seen_subgraphs, seen_nodes, &wrote_any);
    try writeRemainingFlowchartEdges(writer, graph, seen_edges, 1, &wrote_any);
    return true;
}

fn writeRemainingFlowchartChildren(writer: anytype, graph: *const StudioEditableGraph, parent_id: ?[]const u8, indent: usize, seen_subgraphs: []bool, seen_nodes: []bool, wrote_any: *bool) !void {
    const subgraphs = if (graph.subgraphs) |items| items[0..graph.subgraph_count] else &[_]StudioEditableSubgraph{};
    const nodes = if (graph.nodes) |items| items[0..graph.node_count] else &[_]StudioEditableNode{};

    for (subgraphs, 0..) |*sg, idx| {
        if (seen_subgraphs[idx]) continue;
        if (!parentIdMatches(sg.parent_subgraph_id, parent_id)) continue;
        seen_subgraphs[idx] = true;
        if (wrote_any.*) try writer.writeByte('\n');
        try writeSubgraphAnnotation(writer, sg, indent);
        try writeCanonicalSubgraphStartAfterAnnotation(writer, sg, indent);
        wrote_any.* = true;
        try writeRemainingFlowchartChildren(writer, graph, cStr(sg.id), indent + 1, seen_subgraphs, seen_nodes, wrote_any);
        if (wrote_any.*) try writer.writeByte('\n');
        try writeIndent(writer, indent);
        try writer.writeAll("end");
        wrote_any.* = true;
    }

    for (nodes, 0..) |*node, idx| {
        if (seen_nodes[idx]) continue;
        if (!parentIdMatches(node.parent_subgraph_id, parent_id)) continue;
        seen_nodes[idx] = true;
        if (wrote_any.*) try writer.writeByte('\n');
        try writeNodeAnnotation(writer, node, indent);
        try writeCanonicalNodeLineAfterAnnotation(writer, node, indent);
        wrote_any.* = true;
    }
}

fn writeRemainingFlowchartEdges(writer: anytype, graph: *const StudioEditableGraph, seen_edges: []bool, indent: usize, wrote_any: *bool) !void {
    const edges = if (graph.edges) |items| items[0..graph.edge_count] else &[_]StudioEditableEdge{};
    for (edges, 0..) |*edge, idx| {
        if (seen_edges[idx]) continue;
        if (wrote_any.*) try writer.writeByte('\n');
        try writeEdgeAnnotation(writer, edges, idx, edge, indent);
        try writeCanonicalEdgeLineAfterAnnotation(writer, edge, indent);
        wrote_any.* = true;
    }
}

fn writeRecordedLine(writer: anytype, text: []const u8, wrote_any: *bool) !void {
    if (wrote_any.*) try writer.writeByte('\n');
    try writer.writeAll(text);
    wrote_any.* = true;
}

fn writeFlowchartHeaderLine(writer: anytype, keyword: []const u8, direction: u32, wrote_any: *bool) !void {
    if (wrote_any.*) try writer.writeByte('\n');
    try writer.writeAll(keyword);
    try writer.writeByte(' ');
    try writer.writeAll(directionStr(direction));
    wrote_any.* = true;
}

fn writeCanonicalNodeLine(writer: anytype, node: *const StudioEditableNode, indent: usize, wrote_any: *bool) !void {
    if (wrote_any.*) try writer.writeByte('\n');
    try writeIndent(writer, indent);
    try writeNodeDecl(writer, node);
    wrote_any.* = true;
}

fn writeCanonicalNodeLineAfterAnnotation(writer: anytype, node: *const StudioEditableNode, indent: usize) !void {
    try writeIndent(writer, indent);
    try writeNodeDecl(writer, node);
}

fn writeCanonicalEdgeLine(writer: anytype, edge: *const StudioEditableEdge, indent: usize, wrote_any: *bool) !void {
    if (wrote_any.*) try writer.writeByte('\n');
    try writeIndent(writer, indent);
    try writeFlowchartEdge(writer, edge);
    wrote_any.* = true;
}

fn writeCanonicalEdgeLineAfterAnnotation(writer: anytype, edge: *const StudioEditableEdge, indent: usize) !void {
    try writeIndent(writer, indent);
    try writeFlowchartEdge(writer, edge);
}

fn writeCanonicalSubgraphStart(writer: anytype, sg: *const StudioEditableSubgraph, indent: usize, wrote_any: *bool) !void {
    if (wrote_any.*) try writer.writeByte('\n');
    try writeIndent(writer, indent);
    try writer.writeAll("subgraph ");
    try writeQuotedId(writer, cStr(sg.id));
    if (sg.title) |t| {
        const title = std.mem.span(t);
        if (title.len > 0) {
            try writer.writeAll(" [");
            try writer.writeAll(title);
            try writer.writeByte(']');
        }
    }
    wrote_any.* = true;
}

fn writeCanonicalSubgraphStartAfterAnnotation(writer: anytype, sg: *const StudioEditableSubgraph, indent: usize) !void {
    try writeIndent(writer, indent);
    try writer.writeAll("subgraph ");
    try writeQuotedId(writer, cStr(sg.id));
    if (sg.title) |t| {
        const title = std.mem.span(t);
        if (title.len > 0) {
            try writer.writeAll(" [");
            try writer.writeAll(title);
            try writer.writeByte(']');
        }
    }
}

fn currentOpenParent(open_stack: []const OpenSubgraph) ?[]const u8 {
    var idx = open_stack.len;
    while (idx > 0) {
        idx -= 1;
        if (open_stack[idx].emitted) return open_stack[idx].id;
    }
    return null;
}

fn parentIdMatches(parent_ptr: [*c]const u8, expected_parent: ?[]const u8) bool {
    const actual_parent = if (parent_ptr) |ptr| std.mem.span(ptr) else null;
    if (expected_parent) |expected| {
        if (actual_parent) |actual| return std.mem.eql(u8, actual, expected);
        return false;
    }
    return actual_parent == null;
}

fn findSubgraphIndexById(subgraphs: []const StudioEditableSubgraph, id: []const u8) ?usize {
    for (subgraphs, 0..) |item, idx| {
        if (std.mem.eql(u8, cStr(item.id), id)) return idx;
    }
    return null;
}

fn findNodeIndexById(nodes: []const StudioEditableNode, id: []const u8) ?usize {
    for (nodes, 0..) |item, idx| {
        if (std.mem.eql(u8, cStr(item.id), id)) return idx;
    }
    return null;
}

fn findEdgeRecordMatch(edges: []const StudioEditableEdge, record: StudioMermaidSourceRecord, seen_edges: []bool) ?usize {
    const source_id = if (record.object_id) |ptr| std.mem.span(ptr) else return null;
    const target_id = if (record.secondary_id) |ptr| std.mem.span(ptr) else return null;
    const label = if (record.aux_text) |ptr| std.mem.span(ptr) else "";

    for (edges, 0..) |edge, idx| {
        if (seen_edges[idx]) continue;
        if (!std.mem.eql(u8, cStr(edge.source_id), source_id)) continue;
        if (!std.mem.eql(u8, cStr(edge.target_id), target_id)) continue;
        if (!std.mem.eql(u8, std.mem.trim(u8, cStr(edge.label), " \t\r\""), std.mem.trim(u8, label, " \t\r\""))) continue;
        if (edgeSemanticDuplicateIndex(edges, idx) != record.match_index) continue;
        return idx;
    }
    return null;
}

fn recordIndent(text: []const u8) usize {
    var spaces: usize = 0;
    for (text) |char| {
        if (char == ' ') {
            spaces += 1;
        } else if (char == '\t') {
            spaces += 4;
        } else {
            break;
        }
    }
    return spaces / 4;
}

fn headerKeyword(text: []const u8) []const u8 {
    const trimmed = std.mem.trimLeft(u8, text, " \t");
    if (std.mem.startsWith(u8, trimmed, "flowchart ")) return "flowchart";
    return "graph";
}

fn headerDirectionMatches(text: []const u8, direction: u32) bool {
    const trimmed = std.mem.trimLeft(u8, text, " \t");
    var tokens = std.mem.tokenizeAny(u8, trimmed, " \t");
    _ = tokens.next() orelse return false;
    const dir = tokens.next() orelse return false;
    return std.mem.eql(u8, dir, directionStr(direction));
}

const ParsedFlowchartNodeDecl = struct {
    id: []const u8,
    label: []const u8,
    shape: u32,
};

fn flowchartNodeMatchesRecord(node: *const StudioEditableNode, line: []const u8) bool {
    const parsed = parseFlowchartNodeDecl(line) orelse return false;
    if (!std.mem.eql(u8, cStr(node.id), parsed.id)) return false;
    if (node.shape != parsed.shape) return false;
    const label = if (node.label) |ptr| std.mem.span(ptr) else cStr(node.id);
    return std.mem.eql(u8, label, parsed.label);
}

fn parseFlowchartNodeDecl(line: []const u8) ?ParsedFlowchartNodeDecl {
    const trimmed = std.mem.trim(u8, line, " \t\r");
    const leading = parseLeadingIdForNode(trimmed) orelse return null;
    const suffix = std.mem.trimLeft(u8, trimmed[leading.end..], " \t");
    if (suffix.len == 0) return .{ .id = leading.id, .label = leading.id, .shape = 0 };

    const patterns = [_]struct { open: []const u8, close: []const u8, shape: u32 }{
        .{ .open = "[[", .close = "]]", .shape = 11 },
        .{ .open = "([", .close = "])", .shape = 6 },
        .{ .open = "((", .close = "))", .shape = 3 },
        .{ .open = "{{", .close = "}}", .shape = 4 },
        .{ .open = "[(", .close = ")]", .shape = 5 },
        .{ .open = "[/", .close = "/]", .shape = 7 },
        .{ .open = "[\\", .close = "\\]", .shape = 8 },
        .{ .open = "[/", .close = "\\]", .shape = 9 },
        .{ .open = "[\\", .close = "/]", .shape = 10 },
        .{ .open = "(", .close = ")", .shape = 1 },
        .{ .open = "{", .close = "}", .shape = 2 },
        .{ .open = "[", .close = "]", .shape = 0 },
    };

    for (patterns) |pattern| {
        if (!std.mem.startsWith(u8, suffix, pattern.open)) continue;
        if (!std.mem.endsWith(u8, suffix, pattern.close)) continue;
        return .{
            .id = leading.id,
            .label = suffix[pattern.open.len .. suffix.len - pattern.close.len],
            .shape = pattern.shape,
        };
    }
    return null;
}

const ParsedLeadingNodeId = struct {
    id: []const u8,
    end: usize,
};

fn parseLeadingIdForNode(line: []const u8) ?ParsedLeadingNodeId {
    if (line.len == 0) return null;
    if (line[0] == '"') {
        const end_quote = std.mem.indexOfScalar(u8, line[1..], '"') orelse return null;
        return .{ .id = line[1 .. 1 + end_quote], .end = end_quote + 2 };
    }
    var end: usize = 0;
    while (end < line.len) : (end += 1) {
        switch (line[end]) {
            'a'...'z', 'A'...'Z', '0'...'9', '_', '-', '.', '/' => {},
            else => break,
        }
    }
    if (end == 0) return null;
    return .{ .id = line[0..end], .end = end };
}

fn flowchartSubgraphMatchesRecord(sg: *const StudioEditableSubgraph, line: []const u8) bool {
    const trimmed = std.mem.trim(u8, line, " \t\r");
    if (!std.mem.startsWith(u8, trimmed, "subgraph ")) return false;
    const after = std.mem.trimLeft(u8, trimmed["subgraph".len..], " \t");
    const id = parseLeadingIdForNode(after) orelse return false;
    if (!std.mem.eql(u8, id.id, cStr(sg.id))) return false;
    const remainder = std.mem.trimLeft(u8, after[id.end..], " \t");
    const title = if (remainder.len >= 2 and remainder[0] == '[' and remainder[remainder.len - 1] == ']') remainder[1 .. remainder.len - 1] else "";
    return std.mem.eql(u8, cStr(sg.title), title);
}

const ParsedFlowchartEdgeDecl = struct {
    source_id: []const u8,
    target_id: []const u8,
    label: []const u8,
    line_style: u32,
    has_arrow: bool,
    has_source_arrow: bool,
};

const ParsedFlowchartEdgeLine = struct {
    edge: ParsedFlowchartEdgeDecl,
    source_node: ?ParsedFlowchartNodeDecl,
    target_node: ?ParsedFlowchartNodeDecl,
};

fn flowchartEdgeMatchesRecord(edge: *const StudioEditableEdge, line: []const u8) bool {
    const parsed = parseFlowchartEdgeLine(line) orelse return false;
    const edge_decl = parsed.edge;
    if (!std.mem.eql(u8, cStr(edge.source_id), edge_decl.source_id)) return false;
    if (!std.mem.eql(u8, cStr(edge.target_id), edge_decl.target_id)) return false;
    if (!std.mem.eql(u8, std.mem.trim(u8, cStr(edge.label), " \t\r\""), std.mem.trim(u8, edge_decl.label, " \t\r\""))) return false;
    const style_matches = if (edge_decl.line_style == 1) edge.line_style == 1 or edge.line_style == 2 else edge.line_style == edge_decl.line_style;
    return style_matches and edge.has_arrow == @intFromBool(edge_decl.has_arrow) and edge.has_source_arrow == @intFromBool(edge_decl.has_source_arrow);
}

fn parseFlowchartEdgeLine(line: []const u8) ?ParsedFlowchartEdgeLine {
    const trimmed = std.mem.trim(u8, line, " \t\r");
    const relation_start = findFlowchartRelationStart(trimmed) orelse return null;
    const source_segment = std.mem.trimRight(u8, trimmed[0..relation_start], " \t");
    const target = parseTrailingIdRange(trimmed) orelse return null;
    const target_segment = std.mem.trimLeft(u8, trimmed[target.start..], " \t");
    const source_node = parseFlowchartNodeDecl(source_segment);
    const target_node = parseFlowchartNodeDecl(target_segment);
    const source_id = if (source_node) |parsed| parsed.id else (parseLeadingIdForNode(source_segment) orelse return null).id;
    const target_id = if (target_node) |parsed| parsed.id else target.id;
    var relation = std.mem.trim(u8, trimmed[relation_start..target.start], " \t");
    var label: []const u8 = "";
    var has_source_arrow = false;
    var has_arrow = false;

    if (relation.len > 0 and relation[0] == '<') {
        has_source_arrow = true;
        relation = relation[1..];
    }
    if (relation.len > 0 and relation[relation.len - 1] == '>') {
        has_arrow = true;
        relation = relation[0 .. relation.len - 1];
    }
    if (std.mem.indexOfScalar(u8, relation, '|')) |start_bar| {
        if (std.mem.lastIndexOfScalar(u8, relation, '|')) |end_bar| {
            if (end_bar > start_bar) {
                label = relation[start_bar + 1 .. end_bar];
                const before = std.mem.trimRight(u8, relation[0..start_bar], " \t");
                const after = std.mem.trimLeft(u8, relation[end_bar + 1 ..], " \t");
                relation = if (before.len > 0) before else after;
            }
        }
    }
    relation = std.mem.trim(u8, relation, " \t");
    const line_style: u32 = if (std.mem.eql(u8, relation, "-.-")) 1 else if (std.mem.eql(u8, relation, "===")) 3 else 0;
    return .{
        .edge = .{
            .source_id = source_id,
            .target_id = target_id,
            .label = label,
            .line_style = line_style,
            .has_arrow = has_arrow,
            .has_source_arrow = has_source_arrow,
        },
        .source_node = source_node,
        .target_node = target_node,
    };
}

fn inlineEdgeNodesMatch(nodes: []const StudioEditableNode, parsed_line: ?ParsedFlowchartEdgeLine) bool {
    const parsed = parsed_line orelse return true;
    if (parsed.source_node) |source_node| {
        const idx = findNodeIndexById(nodes, source_node.id) orelse return false;
        if (!flowchartNodeDeclMatchesNode(&nodes[idx], source_node)) return false;
    }
    if (parsed.target_node) |target_node| {
        const idx = findNodeIndexById(nodes, target_node.id) orelse return false;
        if (!flowchartNodeDeclMatchesNode(&nodes[idx], target_node)) return false;
    }
    return true;
}

fn markInlineEdgeNodesSeen(nodes: []const StudioEditableNode, seen_nodes: []bool, parsed_line: ParsedFlowchartEdgeLine) void {
    if (parsed_line.source_node) |source_node| {
        if (findNodeIndexById(nodes, source_node.id)) |idx| seen_nodes[idx] = true;
    }
    if (parsed_line.target_node) |target_node| {
        if (findNodeIndexById(nodes, target_node.id)) |idx| seen_nodes[idx] = true;
    }
}

fn markBoundEdgeEndpointNodesSeen(nodes: []const StudioEditableNode, seen_nodes: []bool, record: StudioMermaidSourceRecord) void {
    if (record.object_id) |ptr| {
        if (findNodeIndexById(nodes, std.mem.span(ptr))) |idx| seen_nodes[idx] = true;
    }
    if (record.secondary_id) |ptr| {
        if (findNodeIndexById(nodes, std.mem.span(ptr))) |idx| seen_nodes[idx] = true;
    }
}

fn flowchartNodeDeclMatchesNode(node: *const StudioEditableNode, parsed: ParsedFlowchartNodeDecl) bool {
    if (!std.mem.eql(u8, cStr(node.id), parsed.id)) return false;
    if (node.shape != parsed.shape) return false;
    const label = if (node.label) |ptr| std.mem.span(ptr) else cStr(node.id);
    return std.mem.eql(u8, label, parsed.label);
}

fn findFlowchartRelationStart(line: []const u8) ?usize {
    var square_depth: usize = 0;
    var paren_depth: usize = 0;
    var brace_depth: usize = 0;
    var idx: usize = 0;
    while (idx < line.len) : (idx += 1) {
        switch (line[idx]) {
            '[' => square_depth += 1,
            ']' => {
                if (square_depth > 0) square_depth -= 1;
            },
            '(' => paren_depth += 1,
            ')' => {
                if (paren_depth > 0) paren_depth -= 1;
            },
            '{' => brace_depth += 1,
            '}' => {
                if (brace_depth > 0) brace_depth -= 1;
            },
            '<', '-' => {
                if (square_depth == 0 and paren_depth == 0 and brace_depth == 0 and looksLikeRelationToken(line[idx..])) {
                    return idx;
                }
            },
            else => {},
        }
    }
    return null;
}

fn looksLikeRelationToken(text: []const u8) bool {
    if (text.len == 0) return false;
    if (text[0] == '<') return text.len > 1 and (text[1] == '-' or text[1] == '.');
    if (text[0] != '-') return false;
    return text.len > 1 and (text[1] == '-' or text[1] == '.' or text[1] == '=');
}

const ParsedTrailingIdRange = struct {
    id: []const u8,
    start: usize,
};

fn parseTrailingIdRange(line: []const u8) ?ParsedTrailingIdRange {
    const trimmed = std.mem.trimRight(u8, line, " \t\r");
    if (trimmed.len == 0) return null;
    if (trimmed[trimmed.len - 1] == '"') {
        const start_quote = std.mem.lastIndexOfScalar(u8, trimmed[0 .. trimmed.len - 1], '"') orelse return null;
        return .{ .id = trimmed[start_quote + 1 .. trimmed.len - 1], .start = start_quote };
    }
    var start = trimmed.len;
    while (start > 0) : (start -= 1) {
        switch (trimmed[start - 1]) {
            'a'...'z', 'A'...'Z', '0'...'9', '_', '-', '.', '/' => {},
            else => break,
        }
    }
    if (start == trimmed.len) return null;
    return .{ .id = trimmed[start..], .start = start };
}

// ---------------------------------------------------------------------------
// Flowchart
// ---------------------------------------------------------------------------

fn writeFlowchart(writer: anytype, graph: *const StudioEditableGraph) !void {
    try writer.writeAll("graph ");
    try writer.writeAll(directionStr(graph.direction));
    try writer.writeByte('\n');

    // Subgraphs: need to nest properly. Write root-level subgraphs first,
    // then recursively nest children.
    const subgraphs = if (graph.subgraphs) |s| s[0..graph.subgraph_count] else &[_]StudioEditableSubgraph{};
    const nodes = if (graph.nodes) |n| n[0..graph.node_count] else &[_]StudioEditableNode{};
    const edges = if (graph.edges) |e| e[0..graph.edge_count] else &[_]StudioEditableEdge{};

    // Write subgraphs (root-level first, recurse into children)
    for (subgraphs, 0..) |*sg, i| {
        if (sg.parent_subgraph_id == null) {
            try writeSubgraph(writer, graph, subgraphs, nodes, i, 1);
        }
    }

    // Write nodes not in any subgraph
    for (nodes) |*node| {
        if (node.parent_subgraph_id == null) {
            try writeNodeAnnotation(writer, node, 1);
            try writeIndent(writer, 1);
            try writeNodeDecl(writer, node);
            try writer.writeByte('\n');
        }
    }

    // Write edges
    for (edges, 0..) |*edge, edge_idx| {
        try writeEdgeAnnotation(writer, edges, edge_idx, edge, 1);
        try writeIndent(writer, 1);
        try writeFlowchartEdge(writer, edge);
        try writer.writeByte('\n');
    }
}

fn writeSubgraph(writer: anytype, graph: *const StudioEditableGraph, subgraphs: []const StudioEditableSubgraph, nodes: []const StudioEditableNode, sg_idx: usize, indent: usize) !void {
    const sg = &subgraphs[sg_idx];

    // Annotation for subgraph position/style
    try writeSubgraphAnnotation(writer, sg, indent);

    try writeIndent(writer, indent);
    try writer.writeAll("subgraph ");
    try writeQuotedId(writer, cStr(sg.id));
    if (sg.title) |t| {
        const title = std.mem.span(t);
        if (title.len > 0) {
            try writer.writeAll(" [");
            try writer.writeAll(title);
            try writer.writeByte(']');
        }
    }
    try writer.writeByte('\n');

    // Child subgraphs
    for (subgraphs, 0..) |*child, i| {
        if (child.parent_subgraph_id) |pid| {
            if (std.mem.eql(u8, std.mem.span(pid), cStr(sg.id))) {
                try writeSubgraph(writer, graph, subgraphs, nodes, i, indent + 1);
            }
        }
    }

    // Child nodes
    for (nodes) |*node| {
        if (node.parent_subgraph_id) |pid| {
            if (std.mem.eql(u8, std.mem.span(pid), cStr(sg.id))) {
                try writeNodeAnnotation(writer, node, indent + 1);
                try writeIndent(writer, indent + 1);
                try writeNodeDecl(writer, node);
                try writer.writeByte('\n');
            }
        }
    }

    try writeIndent(writer, indent);
    try writer.writeAll("end\n");
}

fn writeNodeDecl(writer: anytype, node: *const StudioEditableNode) !void {
    const id = cStr(node.id);
    const label = if (node.label) |l| std.mem.span(l) else id;
    try writeQuotedId(writer, id);
    try writeShapeBrackets(writer, node.shape, label);
}

fn writeFlowchartEdge(writer: anytype, edge: *const StudioEditableEdge) !void {
    try writeQuotedId(writer, cStr(edge.source_id));

    // Write the complete Mermaid arrow token followed by optional label.
    // The lexer tokenizes arrow sequences like "-->" and "-.->" as single
    // tokens, so we must emit the arrowhead as part of the token — NOT as a
    // separate ">" character after the label (which the lexer would treat as
    // an identifier and create a phantom node named ">").
    try writer.writeAll(" ");
    if (edge.has_source_arrow != 0) try writer.writeAll("<");
    switch (edge.line_style) {
        1, 2 => { // dotted
            if (edge.has_arrow != 0) try writer.writeAll("-.->") else try writer.writeAll("-.-");
        },
        3 => { // thick
            if (edge.has_arrow != 0) try writer.writeAll("==>") else try writer.writeAll("===");
        },
        else => { // solid
            if (edge.has_arrow != 0) try writer.writeAll("-->") else try writer.writeAll("---");
        },
    }
    // Label comes after the full arrow token: -->|label| target
    if (edge.label) |l| {
        const lbl = std.mem.span(l);
        if (lbl.len > 0) {
            try writer.writeAll("|");
            try writer.writeAll(lbl);
            try writer.writeAll("|");
        }
    }

    try writer.writeAll(" ");
    try writeQuotedId(writer, cStr(edge.target_id));
}

// ---------------------------------------------------------------------------
// Sequence diagram
// ---------------------------------------------------------------------------

fn writeSequenceDiagram(writer: anytype, graph: *const StudioEditableGraph) !void {
    try writer.writeAll("sequenceDiagram\n");

    const nodes = if (graph.nodes) |n| n[0..graph.node_count] else &[_]StudioEditableNode{};
    const edges = if (graph.edges) |e| e[0..graph.edge_count] else &[_]StudioEditableEdge{};

    // Participants: nodes with width > 0 and height > 0 (not anchor nodes)
    for (nodes) |*node| {
        if (node.width > 0 and node.height > 0) {
            try writeNodeAnnotation(writer, node, 1);
            try writeIndent(writer, 1);
            if (node.shape == 14) {
                try writer.writeAll("actor ");
            } else {
                try writer.writeAll("participant ");
            }
            try writeQuotedId(writer, cStr(node.id));
            try writer.writeByte('\n');
        }
    }

    // Messages: edges
    for (edges, 0..) |*edge, edge_idx| {
        try writeEdgeAnnotation(writer, edges, edge_idx, edge, 1);
        try writeIndent(writer, 1);
        try writeQuotedId(writer, cStr(edge.source_id));

        // Arrow syntax: bit0=dashed, bit1=open arrow
        const dashed = (edge.line_style & 1) != 0;
        const open_arrow = (edge.line_style & 2) != 0;
        const is_cross = edge.target_end_style == 10;

        if (dashed) {
            if (is_cross) {
                try writer.writeAll("--x");
            } else if (open_arrow) {
                try writer.writeAll("-->>");
            } else {
                try writer.writeAll("-->>");
            }
        } else {
            if (is_cross) {
                try writer.writeAll("-x");
            } else if (open_arrow) {
                try writer.writeAll("->>");
            } else {
                try writer.writeAll("->>");
            }
        }

        try writeQuotedId(writer, cStr(edge.target_id));

        if (edge.label) |l| {
            const lbl = std.mem.span(l);
            if (lbl.len > 0) {
                try writer.writeAll(": ");
                try writer.writeAll(lbl);
            }
        }
        try writer.writeByte('\n');
    }
}

// ---------------------------------------------------------------------------
// Class diagram
// ---------------------------------------------------------------------------

fn writeClassDiagram(writer: anytype, graph: *const StudioEditableGraph) !void {
    try writer.writeAll("classDiagram\n");
    if (graph.direction != 0) {
        try writeIndent(writer, 1);
        try writer.writeAll("direction ");
        try writer.writeAll(directionStr(graph.direction));
        try writer.writeByte('\n');
    }

    const nodes = if (graph.nodes) |n| n[0..graph.node_count] else &[_]StudioEditableNode{};
    const edges = if (graph.edges) |e| e[0..graph.edge_count] else &[_]StudioEditableEdge{};

    // Classes
    for (nodes) |*node| {
        try writeNodeAnnotation(writer, node, 1);
        try writeIndent(writer, 1);
        try writer.writeAll("class ");
        try writeQuotedId(writer, cStr(node.id));

        // Check for attributes/methods
        const attrs = if (node.attributes_text) |a| std.mem.span(a) else "";
        const methods = if (node.methods_text) |m| std.mem.span(m) else "";

        if (attrs.len > 0 or methods.len > 0) {
            try writer.writeAll(" {\n");
            if (attrs.len > 0) {
                var attr_iter = std.mem.splitScalar(u8, attrs, '\n');
                while (attr_iter.next()) |line| {
                    if (line.len > 0) {
                        try writeIndent(writer, 2);
                        try writer.writeAll(line);
                        try writer.writeByte('\n');
                    }
                }
            }
            if (methods.len > 0) {
                var meth_iter = std.mem.splitScalar(u8, methods, '\n');
                while (meth_iter.next()) |line| {
                    if (line.len > 0) {
                        try writeIndent(writer, 2);
                        try writer.writeAll(line);
                        try writer.writeByte('\n');
                    }
                }
            }
            try writeIndent(writer, 1);
            try writer.writeAll("}\n");
        } else {
            try writer.writeByte('\n');
        }
    }

    // Relations
    for (edges, 0..) |*edge, edge_idx| {
        try writeEdgeAnnotation(writer, edges, edge_idx, edge, 1);
        try writeIndent(writer, 1);
        try writeQuotedId(writer, cStr(edge.source_id));
        try writer.writeAll(" ");
        try writeClassRelation(writer, edge);
        try writer.writeAll(" ");
        try writeQuotedId(writer, cStr(edge.target_id));
        if (edge.label) |l| {
            const lbl = std.mem.span(l);
            if (lbl.len > 0) {
                try writer.writeAll(" : ");
                try writer.writeAll(lbl);
            }
        }
        try writer.writeByte('\n');
    }
}

fn writeClassRelation(writer: anytype, edge: *const StudioEditableEdge) !void {
    // Source end
    switch (edge.source_end_style) {
        1 => try writer.writeAll("<|"),
        2 => try writer.writeAll("*"),
        3 => try writer.writeAll("o"),
        4 => try writer.writeAll("<"),
        5 => try writer.writeAll("()"),
        else => {},
    }

    // Line style
    switch (edge.line_style) {
        1 => try writer.writeAll(".."),
        else => try writer.writeAll("--"),
    }

    // Target end
    switch (edge.target_end_style) {
        1 => try writer.writeAll("|>"),
        2 => try writer.writeAll("*"),
        3 => try writer.writeAll("o"),
        4 => try writer.writeAll(">"),
        5 => try writer.writeAll("()"),
        else => {},
    }
}

// ---------------------------------------------------------------------------
// ER diagram
// ---------------------------------------------------------------------------

fn writeErDiagram(writer: anytype, graph: *const StudioEditableGraph) !void {
    try writer.writeAll("erDiagram\n");

    const nodes = if (graph.nodes) |n| n[0..graph.node_count] else &[_]StudioEditableNode{};
    const edges = if (graph.edges) |e| e[0..graph.edge_count] else &[_]StudioEditableEdge{};

    // Entities
    for (nodes) |*node| {
        try writeNodeAnnotation(writer, node, 1);
        try writeIndent(writer, 1);
        try writeQuotedId(writer, cStr(node.id));

        const attrs = if (node.attributes_text) |a| std.mem.span(a) else "";
        if (attrs.len > 0) {
            try writer.writeAll(" {\n");
            var attr_iter = std.mem.splitScalar(u8, attrs, '\n');
            while (attr_iter.next()) |line| {
                if (line.len > 0) {
                    try writeIndent(writer, 2);
                    try writer.writeAll(line);
                    try writer.writeByte('\n');
                }
            }
            try writeIndent(writer, 1);
            try writer.writeAll("}\n");
        } else {
            try writer.writeByte('\n');
        }
    }

    // Relationships
    for (edges, 0..) |*edge, edge_idx| {
        try writeEdgeAnnotation(writer, edges, edge_idx, edge, 1);
        try writeIndent(writer, 1);
        try writeQuotedId(writer, cStr(edge.source_id));
        try writer.writeAll(" ");
        try writeErCardinality(writer, edge.source_end_style);
        try writer.writeAll("--");
        try writeErCardinality(writer, edge.target_end_style);
        try writer.writeAll(" ");
        try writeQuotedId(writer, cStr(edge.target_id));
        if (edge.label) |l| {
            const lbl = std.mem.span(l);
            if (lbl.len > 0) {
                try writer.writeAll(" : ");
                try writer.print("\"{s}\"", .{lbl});
            }
        }
        try writer.writeByte('\n');
    }
}

fn writeErCardinality(writer: anytype, end_style: u32) !void {
    switch (end_style) {
        6 => try writer.writeAll("||"),
        7 => try writer.writeAll("|o"),
        8 => try writer.writeAll("}o"),
        9 => try writer.writeAll("}|"),
        else => try writer.writeAll("||"),
    }
}

// ---------------------------------------------------------------------------
// State diagram
// ---------------------------------------------------------------------------

fn writeStateDiagram(writer: anytype, graph: *const StudioEditableGraph) !void {
    try writer.writeAll("stateDiagram-v2\n");
    if (graph.direction != 0) {
        try writeIndent(writer, 1);
        try writer.writeAll("direction ");
        try writer.writeAll(directionStr(graph.direction));
        try writer.writeByte('\n');
    }

    const subgraphs = if (graph.subgraphs) |s| s[0..graph.subgraph_count] else &[_]StudioEditableSubgraph{};
    const nodes = if (graph.nodes) |n| n[0..graph.node_count] else &[_]StudioEditableNode{};
    const edges = if (graph.edges) |e| e[0..graph.edge_count] else &[_]StudioEditableEdge{};

    // Composite states (subgraphs)
    for (subgraphs) |*sg| {
        try writeSubgraphAnnotation(writer, sg, 1);
        try writeIndent(writer, 1);
        try writer.writeAll("state ");
        try writeQuotedId(writer, cStr(sg.id));
        try writer.writeAll(" {\n");
        // Child nodes in this composite state
        for (nodes) |*node| {
            if (node.parent_subgraph_id) |pid| {
                if (std.mem.eql(u8, std.mem.span(pid), cStr(sg.id))) {
                    try writeStateNode(writer, node, 2);
                }
            }
        }
        try writeIndent(writer, 1);
        try writer.writeAll("}\n");
    }

    // Top-level states (not in subgraph)
    for (nodes) |*node| {
        if (node.parent_subgraph_id == null) {
            try writeStateNode(writer, node, 1);
        }
    }

    // Transitions
    for (edges, 0..) |*edge, edge_idx| {
        try writeEdgeAnnotation(writer, edges, edge_idx, edge, 1);
        try writeIndent(writer, 1);

        const src = cStr(edge.source_id);
        const tgt = cStr(edge.target_id);

        try writeStateId(writer, src);
        try writer.writeAll(" --> ");
        try writeStateId(writer, tgt);

        if (edge.label) |l| {
            const lbl = std.mem.span(l);
            if (lbl.len > 0) {
                try writer.writeAll(" : ");
                try writer.writeAll(lbl);
            }
        }
        try writer.writeByte('\n');
    }
}

fn writeStateNode(writer: anytype, node: *const StudioEditableNode, indent: usize) !void {
    const id = cStr(node.id);
    // start/end states use [*] in Mermaid
    if (node.shape == 12 or node.shape == 3) {
        // end_state or circle — these are [*], skip explicit declaration
        // They'll only appear in transitions as [*]
        return;
    }
    try writeNodeAnnotation(writer, node, indent);
    try writeIndent(writer, indent);
    try writeQuotedId(writer, id);
    if (node.label) |l| {
        const lbl = std.mem.span(l);
        if (lbl.len > 0 and !std.mem.eql(u8, lbl, id)) {
            try writer.writeAll(" : ");
            try writer.writeAll(lbl);
        }
    }
    try writer.writeByte('\n');
}

fn writeStateId(writer: anytype, id: []const u8) !void {
    // Map special state names to [*]
    if (std.mem.eql(u8, id, "[*]") or
        std.mem.eql(u8, id, "start") or
        std.mem.eql(u8, id, "end") or
        std.mem.startsWith(u8, id, "[*]"))
    {
        try writer.writeAll("[*]");
    } else {
        try writeQuotedId(writer, id);
    }
}

// ---------------------------------------------------------------------------
// Annotation helpers
// ---------------------------------------------------------------------------

fn writeNodeAnnotation(writer: anytype, node: *const StudioEditableNode, indent: usize) !void {
    try writeIndent(writer, indent);
    try writer.print("%% @shape={s},{d:.0},{d:.0},{d:.0},{d:.0}", .{
        shapeName(node.shape),
        node.x,
        node.y,
        node.width,
        node.height,
    });
    try writeColorAnnotation(writer, " @fill=", node.fill);
    try writeColorAnnotation(writer, " @body-fill=", node.body_fill);
    try writeColorAnnotation(writer, " @stroke=", node.stroke);
    if (node.stroke_width != 0) {
        try writer.print(" @stroke-width={d:.1}", .{node.stroke_width});
    }
    try writeColorAnnotation(writer, " @ink=", node.label_color);
    if (node.label_font_size != 0) {
        try writer.print(" @font-size={d:.1}", .{node.label_font_size});
    }
    try writer.writeByte('\n');
}

fn writeEdgeAnnotation(writer: anytype, all_edges: []const StudioEditableEdge, edge_idx: usize, edge: *const StudioEditableEdge, indent: usize) !void {
    try writeIndent(writer, indent);
    try writer.writeAll("%% @edge");
    try writer.print(" @match-index={d}", .{edgeSemanticDuplicateIndex(all_edges, edge_idx)});
    try writeColorAnnotation(writer, " @stroke=", edge.color);
    if (edge.thickness != 0) {
        try writer.print(" @thickness={d:.1}", .{edge.thickness});
    }
    try writer.print(" @line-style={s}", .{lineStyleName(edge.line_style)});
    if (edge.label_font_size != 0) {
        try writer.print(" @font-size={d:.1}", .{edge.label_font_size});
    }
    if (edge.source_end_style != 0 or edge.target_end_style != 0) {
        try writer.print(" @end-style={d},{d}", .{ edge.source_end_style, edge.target_end_style });
    }
    try writer.writeByte('\n');
}

fn edgeSemanticDuplicateIndex(edges: []const StudioEditableEdge, edge_idx: usize) usize {
    if (edge_idx >= edges.len) return 0;

    const target = &edges[edge_idx];
    const source_id = cStr(target.source_id);
    const target_id = cStr(target.target_id);
    const label = cStr(target.label);

    var duplicate_index: usize = 0;
    for (edges[0..edge_idx]) |candidate| {
        if (!std.mem.eql(u8, cStr(candidate.source_id), source_id)) continue;
        if (!std.mem.eql(u8, cStr(candidate.target_id), target_id)) continue;
        if (!std.mem.eql(u8, cStr(candidate.label), label)) continue;
        duplicate_index += 1;
    }
    return duplicate_index;
}

fn writeSubgraphAnnotation(writer: anytype, sg: *const StudioEditableSubgraph, indent: usize) !void {
    try writeIndent(writer, indent);
    try writer.print("%% @pos={d:.0},{d:.0},{d:.0},{d:.0}", .{
        sg.x,
        sg.y,
        sg.width,
        sg.height,
    });
    try writeColorAnnotation(writer, " @fill=", sg.fill);
    try writeColorAnnotation(writer, " @stroke=", sg.stroke);
    if (sg.stroke_width != 0) {
        try writer.print(" @stroke-width={d:.1}", .{sg.stroke_width});
    }
    if (sg.corner_radius != 0) {
        try writer.print(" @corner-radius={d:.0}", .{sg.corner_radius});
    }
    try writeColorAnnotation(writer, " @title-color=", sg.title_color);
    if (sg.title_font_size != 0) {
        try writer.print(" @title-font-size={d:.1}", .{sg.title_font_size});
    }
    try writer.writeByte('\n');
}

fn writeColorAnnotation(writer: anytype, prefix: []const u8, color: StudioColor) !void {
    try writer.writeAll(prefix);
    try writer.print("#{x:0>2}{x:0>2}{x:0>2}", .{ color.r, color.g, color.b });
    if (color.a != 255) {
        try writer.print("{x:0>2}", .{color.a});
    }
}

// ---------------------------------------------------------------------------
// Utility helpers
// ---------------------------------------------------------------------------

fn writeIndent(writer: anytype, level: usize) !void {
    for (0..level) |_| {
        try writer.writeAll("    ");
    }
}

fn writeQuotedId(writer: anytype, id: []const u8) !void {
    if (needsQuoting(id)) {
        try writer.writeByte('"');
        try writer.writeAll(id);
        try writer.writeByte('"');
    } else {
        try writer.writeAll(id);
    }
}

fn needsQuoting(id: []const u8) bool {
    if (id.len == 0) return true;
    for (id) |c| {
        switch (c) {
            'a'...'z', 'A'...'Z', '0'...'9', '_', '-' => {},
            else => return true,
        }
    }
    return false;
}

fn writeShapeBrackets(writer: anytype, shape: u32, label: []const u8) !void {
    switch (shape) {
        0 => { // rect
            try writer.writeByte('[');
            try writer.writeAll(label);
            try writer.writeByte(']');
        },
        1 => { // round
            try writer.writeAll("(");
            try writer.writeAll(label);
            try writer.writeAll(")");
        },
        2 => { // diamond
            try writer.writeByte('{');
            try writer.writeAll(label);
            try writer.writeByte('}');
        },
        3 => { // circle
            try writer.writeAll("((");
            try writer.writeAll(label);
            try writer.writeAll("))");
        },
        4 => { // hexagon
            try writer.writeAll("{{");
            try writer.writeAll(label);
            try writer.writeAll("}}");
        },
        5 => { // cylinder
            try writer.writeAll("[(");
            try writer.writeAll(label);
            try writer.writeAll(")]");
        },
        6 => { // stadium
            try writer.writeAll("([");
            try writer.writeAll(label);
            try writer.writeAll("])");
        },
        7 => { // trapezoid
            try writer.writeAll("[/");
            try writer.writeAll(label);
            try writer.writeAll("/]");
        },
        8 => { // trapezoid alt
            try writer.writeAll("[\\");
            try writer.writeAll(label);
            try writer.writeAll("\\]");
        },
        9 => { // parallelogram
            try writer.writeAll("[/");
            try writer.writeAll(label);
            try writer.writeAll("\\]");
        },
        10 => { // parallelogram alt
            try writer.writeAll("[\\");
            try writer.writeAll(label);
            try writer.writeAll("/]");
        },
        11 => { // subroutine
            try writer.writeAll("[[");
            try writer.writeAll(label);
            try writer.writeAll("]]");
        },
        else => { // default rect for unknown shapes
            try writer.writeByte('[');
            try writer.writeAll(label);
            try writer.writeByte(']');
        },
    }
}

fn cStr(ptr: [*c]const u8) []const u8 {
    if (ptr) |p| return std.mem.span(p);
    return "";
}

fn directionStr(dir: u32) []const u8 {
    return switch (dir) {
        1 => "LR",
        2 => "BT",
        3 => "RL",
        else => "TD",
    };
}

fn shapeName(shape: u32) []const u8 {
    return switch (shape) {
        0 => "rect",
        1 => "round",
        2 => "diamond",
        3 => "circle",
        4 => "hexagon",
        5 => "cylinder",
        6 => "stadium",
        7 => "trapezoid",
        8 => "trap_alt",
        9 => "parallelogram",
        10 => "para_alt",
        11 => "subroutine",
        12 => "end_state",
        13 => "note",
        14 => "actor",
        else => "rect",
    };
}

fn lineStyleName(style: u32) []const u8 {
    return switch (style) {
        1 => "dashed",
        2 => "dotted",
        3 => "thick",
        else => "solid",
    };
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

test "serializeGraph flowchart" {
    const allocator = std.testing.allocator;

    var nodes_buf = [_]StudioEditableNode{
        .{
            .id = "A",
            .label = "Start",
            .subtitle = null,
            .attributes_text = null,
            .methods_text = null,
            .parent_subgraph_id = null,
            .shape = 1,
            .x = 10,
            .y = 20,
            .width = 100,
            .height = 50,
            .fill = .{ .r = 255, .g = 255, .b = 255, .a = 255 },
            .body_fill = .{ .r = 255, .g = 255, .b = 255, .a = 255 },
            .stroke = .{ .r = 0, .g = 0, .b = 0, .a = 255 },
            .stroke_width = 1.0,
            .label_color = .{ .r = 0, .g = 0, .b = 0, .a = 255 },
            .label_font_size = 14.0,
        },
        .{
            .id = "B",
            .label = "End",
            .subtitle = null,
            .attributes_text = null,
            .methods_text = null,
            .parent_subgraph_id = null,
            .shape = 0,
            .x = 10,
            .y = 120,
            .width = 100,
            .height = 50,
            .fill = .{ .r = 255, .g = 255, .b = 255, .a = 255 },
            .body_fill = .{ .r = 255, .g = 255, .b = 255, .a = 255 },
            .stroke = .{ .r = 0, .g = 0, .b = 0, .a = 255 },
            .stroke_width = 1.0,
            .label_color = .{ .r = 0, .g = 0, .b = 0, .a = 255 },
            .label_font_size = 14.0,
        },
    };

    var edges_buf = [_]StudioEditableEdge{
        .{
            .source_id = "A",
            .target_id = "B",
            .label = "go",
            .label_font_size = 12.0,
            .color = .{ .r = 0, .g = 0, .b = 0, .a = 255 },
            .thickness = 1.5,
            .line_style = 0,
            .has_arrow = 1,
            .has_source_arrow = 0,
            .source_end_style = 0,
            .target_end_style = 0,
        },
    };

    var graph = StudioEditableGraph{
        .width = 200,
        .height = 200,
        .graph_type = 0,
        .direction = 0,
        .background = .{ .r = 255, .g = 255, .b = 255, .a = 255 },
        .subgraphs = null,
        .subgraph_count = 0,
        .nodes = &nodes_buf,
        .node_count = 2,
        .edges = &edges_buf,
        .edge_count = 1,
        .source_records = null,
        .source_record_count = 0,
    };

    const result = try serializeGraph(allocator, &graph);
    defer allocator.free(result);

    // Verify it starts with "graph TD"
    try std.testing.expect(std.mem.startsWith(u8, result, "graph TD\n"));
    // Verify it contains the node declarations
    try std.testing.expect(std.mem.indexOf(u8, result, "A(Start)") != null);
    try std.testing.expect(std.mem.indexOf(u8, result, "B[End]") != null);
    // Verify it contains annotations
    try std.testing.expect(std.mem.indexOf(u8, result, "%% @shape=round,10,20,100,50") != null);
    try std.testing.expect(std.mem.indexOf(u8, result, "%% @edge @match-index=0") != null);
    // Verify it contains edge
    try std.testing.expect(std.mem.indexOf(u8, result, "A ---|go|> B") != null);
}

test "colorToHex" {
    const allocator = std.testing.allocator;
    var buf = std.ArrayList(u8){};
    defer buf.deinit(allocator);
    const writer = buf.writer(allocator);

    try writeColorAnnotation(writer, " @fill=", .{ .r = 255, .g = 128, .b = 0, .a = 255 });
    try std.testing.expectEqualStrings(" @fill=#ff8000", buf.items);
}

test "needsQuoting" {
    try std.testing.expect(!needsQuoting("hello"));
    try std.testing.expect(!needsQuoting("my-node_1"));
    try std.testing.expect(needsQuoting("hello world"));
    try std.testing.expect(needsQuoting("a+b"));
    try std.testing.expect(needsQuoting(""));
}

test "directionStr" {
    try std.testing.expectEqualStrings("TD", directionStr(0));
    try std.testing.expectEqualStrings("LR", directionStr(1));
    try std.testing.expectEqualStrings("BT", directionStr(2));
    try std.testing.expectEqualStrings("RL", directionStr(3));
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

test "serializeGraph flowchart source records survive add delete" {
    const allocator = std.testing.allocator;

    var delete_nodes = [_]StudioEditableNode{
        .{
            .id = "A",
            .label = "Start",
            .subtitle = null,
            .attributes_text = null,
            .methods_text = null,
            .parent_subgraph_id = null,
            .shape = 0,
            .x = 10,
            .y = 20,
            .width = 100,
            .height = 50,
            .fill = .{ .r = 255, .g = 255, .b = 255, .a = 255 },
            .body_fill = .{ .r = 255, .g = 255, .b = 255, .a = 255 },
            .stroke = .{ .r = 0, .g = 0, .b = 0, .a = 255 },
            .stroke_width = 1.0,
            .label_color = .{ .r = 0, .g = 0, .b = 0, .a = 255 },
            .label_font_size = 14.0,
        },
    };
    var base_records = [_]StudioMermaidSourceRecord{
        .{ .kind = mermaid_record_kind_header, .object_id = null, .secondary_id = null, .aux_text = null, .match_index = 0, .text = "flowchart TD" },
        .{ .kind = mermaid_record_kind_edge, .object_id = "A", .secondary_id = "B", .aux_text = null, .match_index = 0, .text = "    A[Start] --> B[End]" },
    };
    var deleted_graph = StudioEditableGraph{
        .width = 200,
        .height = 120,
        .graph_type = 0,
        .direction = 0,
        .background = .{ .r = 255, .g = 255, .b = 255, .a = 255 },
        .subgraphs = null,
        .subgraph_count = 0,
        .nodes = &delete_nodes,
        .node_count = delete_nodes.len,
        .edges = null,
        .edge_count = 0,
        .source_records = &base_records,
        .source_record_count = base_records.len,
    };

    const deleted_export = try serializeGraph(allocator, &deleted_graph);
    defer allocator.free(deleted_export);
    const deleted_normalized = try stripAnnotationCommentsForTest(allocator, deleted_export);
    defer allocator.free(deleted_normalized);
    try std.testing.expectEqualStrings("graph TD\n    A[Start]", deleted_normalized);

    var add_nodes = [_]StudioEditableNode{
        delete_nodes[0],
        .{
            .id = "C",
            .label = "Extra",
            .subtitle = null,
            .attributes_text = null,
            .methods_text = null,
            .parent_subgraph_id = null,
            .shape = 0,
            .x = 120,
            .y = 20,
            .width = 100,
            .height = 50,
            .fill = .{ .r = 255, .g = 255, .b = 255, .a = 255 },
            .body_fill = .{ .r = 255, .g = 255, .b = 255, .a = 255 },
            .stroke = .{ .r = 0, .g = 0, .b = 0, .a = 255 },
            .stroke_width = 1.0,
            .label_color = .{ .r = 0, .g = 0, .b = 0, .a = 255 },
            .label_font_size = 14.0,
        },
    };
    var added_graph = StudioEditableGraph{
        .width = 260,
        .height = 120,
        .graph_type = 0,
        .direction = 0,
        .background = .{ .r = 255, .g = 255, .b = 255, .a = 255 },
        .subgraphs = null,
        .subgraph_count = 0,
        .nodes = &add_nodes,
        .node_count = add_nodes.len,
        .edges = null,
        .edge_count = 0,
        .source_records = &base_records,
        .source_record_count = base_records.len,
    };

    const added_export = try serializeGraph(allocator, &added_graph);
    defer allocator.free(added_export);
    const added_normalized = try stripAnnotationCommentsForTest(allocator, added_export);
    defer allocator.free(added_normalized);
    try std.testing.expect(std.mem.indexOf(u8, added_normalized, "A[Start]") != null);
    try std.testing.expect(std.mem.indexOf(u8, added_normalized, "C[Extra]") != null);
    try std.testing.expect(std.mem.indexOf(u8, added_normalized, "B[End]") == null);
}

test "serializeGraph class source records still exports node annotations" {
    const allocator = std.testing.allocator;

    var nodes = [_]StudioEditableNode{
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
    var edges = [_]StudioEditableEdge{
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
        .{ .kind = mermaid_record_kind_header, .object_id = null, .secondary_id = null, .aux_text = null, .match_index = 0, .text = "classDiagram" },
        .{ .kind = mermaid_record_kind_edge, .object_id = "User", .secondary_id = "Account", .aux_text = null, .match_index = 0, .text = "    User --> Account" },
    };
    var graph = StudioEditableGraph{
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

    const exported = try serializeGraph(allocator, &graph);
    defer allocator.free(exported);

    try std.testing.expect(std.mem.indexOf(u8, exported, "%% @shape=rect,24,30,120,52 @fill=#ffdd88") != null);
    try std.testing.expect(std.mem.indexOf(u8, exported, "@stroke=#445566") != null);
    try std.testing.expect(std.mem.indexOf(u8, exported, "@ink=#112233") != null);
    try std.testing.expect(std.mem.indexOf(u8, exported, "class User") != null);
}
