const std = @import("std");
const document_model = @import("document_model.zig");

pub const Block = document_model.Block;
pub const DiagramBlock = document_model.DiagramBlock;
pub const MarkdownDocument = document_model.MarkdownDocument;
pub const TextBlock = document_model.TextBlock;

pub fn parseSourceDocument(allocator: std.mem.Allocator, source: []const u8, source_path: ?[]const u8) !MarkdownDocument {
    if (isMarkdownPath(source_path)) {
        return parse(allocator, source, source_path);
    }
    return wrapSingleDiagramDocument(allocator, source, source_path);
}

const HeadingRef = struct {
    text: []const u8,
    line: usize,
};

pub fn parse(allocator: std.mem.Allocator, source: []const u8, source_path: ?[]const u8) !MarkdownDocument {
    const owned_source = try allocator.dupe(u8, source);
    errdefer allocator.free(owned_source);

    const owned_path = if (source_path) |path|
        try allocator.dupe(u8, path)
    else
        null;
    errdefer if (owned_path) |path| allocator.free(path);

    var blocks = std.ArrayList(Block){};
    errdefer blocks.deinit(allocator);

    var state = ParseState{};

    while (state.cursor < owned_source.len) {
        const line_start = state.cursor;
        const line_end, const next_cursor = lineBounds(owned_source, state.cursor);
        const raw_line = owned_source[line_start..line_end];
        const line = trimLineEnding(raw_line);

        if (!state.in_mermaid_block) {
            if (isMermaidFence(line)) {
                try appendTextBlock(allocator, &blocks, owned_source, state.text_start, line_start, state.text_start_line, state.line_number);
                state.in_mermaid_block = true;
                state.diagram_name = if (state.last_heading) |heading| heading.text else null;
                state.diagram_content_start = next_cursor;
                state.diagram_start_line = state.line_number + 1;
            } else if (parseHeading(line)) |heading_text| {
                state.last_heading = .{ .text = heading_text, .line = state.line_number };
            }
        } else if (isClosingFence(line)) {
            try appendDiagramBlock(allocator, &blocks, owned_source, state.diagram_content_start, line_start, state.diagram_name, state.diagram_start_line, state.line_number);
            state.in_mermaid_block = false;
            state.text_start = next_cursor;
            state.text_start_line = state.line_number + 1;
        }

        state.cursor = next_cursor;
        state.line_number += 1;
    }

    if (state.in_mermaid_block) {
        try appendDiagramBlock(allocator, &blocks, owned_source, state.diagram_content_start, owned_source.len, state.diagram_name, state.diagram_start_line, state.line_number);
    } else {
        try appendTextBlock(allocator, &blocks, owned_source, state.text_start, owned_source.len, state.text_start_line, state.line_number);
    }

    const owned_blocks = try blocks.toOwnedSlice(allocator);
    var diagram_count: usize = 0;
    for (owned_blocks) |block| {
        if (block == .diagram) diagram_count += 1;
    }

    return .{
        .allocator = allocator,
        .source = owned_source,
        .source_path = owned_path,
        .blocks = owned_blocks,
        .diagram_count = diagram_count,
    };
}

pub fn computeContentHash(allocator: std.mem.Allocator, source: []const u8) !u64 {
    const normalized = try normalizeForHash(allocator, source);
    defer allocator.free(normalized);
    return std.hash.Wyhash.hash(0, normalized);
}

fn isMarkdownPath(source_path: ?[]const u8) bool {
    const path = source_path orelse return false;
    const extension = std.fs.path.extension(path);
    return std.ascii.eqlIgnoreCase(extension, ".md") or std.ascii.eqlIgnoreCase(extension, ".markdown");
}

fn wrapSingleDiagramDocument(allocator: std.mem.Allocator, source: []const u8, source_path: ?[]const u8) !MarkdownDocument {
    const owned_source = try allocator.dupe(u8, source);
    errdefer allocator.free(owned_source);

    const owned_path = if (source_path) |path|
        try allocator.dupe(u8, path)
    else
        null;
    errdefer if (owned_path) |path| allocator.free(path);

    const content_hash = try computeContentHash(allocator, owned_source);
    const blocks = try allocator.alloc(Block, 1);
    errdefer allocator.free(blocks);

    blocks[0] = .{ .diagram = .{
        .name = null,
        .mermaid_source = owned_source,
        .content_hash = content_hash,
        .start_offset = 0,
        .end_offset = owned_source.len,
        .start_line = 1,
        .end_line = countLines(owned_source),
    } };

    return .{
        .allocator = allocator,
        .source = owned_source,
        .source_path = owned_path,
        .blocks = blocks,
        .diagram_count = 1,
    };
}

const ParseState = struct {
    cursor: usize = 0,
    line_number: usize = 1,
    text_start: usize = 0,
    text_start_line: usize = 1,
    in_mermaid_block: bool = false,
    diagram_content_start: usize = 0,
    diagram_start_line: usize = 0,
    diagram_name: ?[]const u8 = null,
    last_heading: ?HeadingRef = null,
};

fn appendTextBlock(allocator: std.mem.Allocator, blocks: *std.ArrayList(Block), source: []const u8, start_offset: usize, end_offset: usize, start_line: usize, next_line: usize) !void {
    if (end_offset <= start_offset) return;

    try blocks.append(allocator, .{ .text = .{
        .content = source[start_offset..end_offset],
        .start_offset = start_offset,
        .end_offset = end_offset,
        .start_line = start_line,
        .end_line = lineRangeEnd(start_line, next_line),
    } });
}

fn appendDiagramBlock(allocator: std.mem.Allocator, blocks: *std.ArrayList(Block), source: []const u8, start_offset: usize, end_offset: usize, name: ?[]const u8, start_line: usize, next_line: usize) !void {
    const mermaid_source = source[start_offset..end_offset];
    const content_hash = try computeContentHash(allocator, mermaid_source);
    try blocks.append(allocator, .{ .diagram = .{
        .name = name,
        .mermaid_source = mermaid_source,
        .content_hash = content_hash,
        .start_offset = start_offset,
        .end_offset = end_offset,
        .start_line = start_line,
        .end_line = lineRangeEnd(start_line, next_line),
    } });
}

fn lineBounds(source: []const u8, cursor: usize) struct { usize, usize } {
    const maybe_newline = std.mem.indexOfScalarPos(u8, source, cursor, '\n');
    if (maybe_newline) |newline_index| {
        return .{ newline_index, newline_index + 1 };
    }
    return .{ source.len, source.len };
}

fn trimLineEnding(line: []const u8) []const u8 {
    return std.mem.trimRight(u8, line, "\r");
}

fn isMermaidFence(line: []const u8) bool {
    const trimmed = std.mem.trimLeft(u8, line, " \t");
    if (!std.mem.startsWith(u8, trimmed, "```mermaid")) return false;
    if (trimmed.len == "```mermaid".len) return true;
    return std.ascii.isWhitespace(trimmed["```mermaid".len]);
}

fn isClosingFence(line: []const u8) bool {
    return std.mem.eql(u8, std.mem.trim(u8, line, " \t"), "```");
}

fn parseHeading(line: []const u8) ?[]const u8 {
    const trimmed = std.mem.trimLeft(u8, line, " \t");
    if (trimmed.len < 2 or trimmed[0] != '#') return null;

    var index: usize = 0;
    while (index < trimmed.len and trimmed[index] == '#') : (index += 1) {}
    if (index == 0 or index == trimmed.len or trimmed[index] != ' ') return null;

    const heading = std.mem.trim(u8, trimmed[index + 1 ..], " \t");
    if (heading.len == 0) return null;
    return heading;
}

fn lineRangeEnd(start_line: usize, next_line: usize) usize {
    if (next_line <= start_line) return start_line;
    return next_line - 1;
}

fn normalizeForHash(allocator: std.mem.Allocator, source: []const u8) ![]u8 {
    var buffer = std.ArrayList(u8){};
    errdefer buffer.deinit(allocator);

    var line_iter = std.mem.splitScalar(u8, source, '\n');
    var wrote_any = false;
    var pending_blank = false;

    while (line_iter.next()) |raw_line| {
        const line = trimLineEnding(raw_line);
        const is_blank = std.mem.trim(u8, line, " \t").len == 0;

        if (is_blank) {
            if (wrote_any) pending_blank = true;
            continue;
        }

        if (wrote_any) {
            try buffer.append(allocator, '\n');
            if (pending_blank) {
                try buffer.append(allocator, '\n');
                pending_blank = false;
            }
        }

        try buffer.appendSlice(allocator, line);
        wrote_any = true;
    }

    return buffer.toOwnedSlice(allocator);
}

fn countLines(source: []const u8) usize {
    if (source.len == 0) return 1;

    var total: usize = 1;
    for (source) |char| {
        if (char == '\n') total += 1;
    }
    return total;
}

test "markdown parser captures text and multiple mermaid blocks" {
    const source =
        \\# System Overview
        \\
        \\Intro paragraph.
        \\
        \\## Authentication Flow
        \\```mermaid
        \\sequenceDiagram
        \\  Alice->>Bob: Hello
        \\```
        \\
        \\Further discussion.
        \\
        \\## Data Model
        \\```mermaid
        \\erDiagram
        \\  USER ||--o{ ORDER : places
        \\```
    ;

    var document = try parse(std.testing.allocator, source, "example.md");
    defer document.deinit();

    try std.testing.expectEqual(@as(usize, 4), document.blocks.len);
    try std.testing.expectEqual(@as(usize, 2), document.diagram_count);
    try std.testing.expectEqualStrings("example.md", document.source_path.?);

    try std.testing.expect(document.blocks[0] == .text);
    try std.testing.expect(document.blocks[1] == .diagram);
    try std.testing.expect(document.blocks[2] == .text);
    try std.testing.expect(document.blocks[3] == .diagram);

    const first_diagram = document.diagramAt(0).?;
    try std.testing.expectEqualStrings("Authentication Flow", first_diagram.name.?);
    try std.testing.expect(std.mem.indexOf(u8, first_diagram.mermaid_source, "sequenceDiagram") != null);

    const second_diagram = document.diagramAt(1).?;
    try std.testing.expectEqualStrings("Data Model", second_diagram.name.?);
    try std.testing.expect(std.mem.indexOf(u8, second_diagram.mermaid_source, "erDiagram") != null);
}

test "markdown parser leaves unnamed diagrams unnamed" {
    const source =
        \\Before
        \\```mermaid
        \\graph TD
        \\  A --> B
        \\```
    ;

    var document = try parse(std.testing.allocator, source, null);
    defer document.deinit();

    const diagram = document.diagramAt(0).?;
    try std.testing.expect(diagram.name == null);
    try std.testing.expectEqual(@as(usize, 3), diagram.start_line);
}

test "content hash normalizes line endings and blank lines" {
    const source_a =
        "graph TD\r\n" ++
        "\r\n" ++
        "  A --> B\r\n" ++
        "\r\n" ++
        "\r\n";
    const source_b =
        "graph TD\n" ++
        "\n" ++
        "  A --> B\n";

    const hash_a = try computeContentHash(std.testing.allocator, source_a);
    const hash_b = try computeContentHash(std.testing.allocator, source_b);

    try std.testing.expectEqual(hash_a, hash_b);
}

test "unterminated mermaid block parses to end of file" {
    const source =
        \\## Broken Diagram
        \\```mermaid
        \\graph TD
        \\  A --> B
    ;

    var document = try parse(std.testing.allocator, source, null);
    defer document.deinit();

    try std.testing.expectEqual(@as(usize, 1), document.diagram_count);
    const diagram = document.diagramAt(0).?;
    try std.testing.expectEqualStrings("Broken Diagram", diagram.name.?);
    try std.testing.expect(std.mem.endsWith(u8, std.mem.trimRight(u8, diagram.mermaid_source, "\r\n"), "A --> B"));
}

test "non-markdown sources are wrapped as a single diagram document" {
    const source =
        "flowchart TD\n" ++
        "  Start --> End\n";

    var document = try parseSourceDocument(std.testing.allocator, source, "diagram.mmd");
    defer document.deinit();

    try std.testing.expectEqual(@as(usize, 1), document.diagram_count);
    try std.testing.expectEqual(@as(usize, 1), document.blocks.len);
    const diagram = document.diagramAt(0).?;
    try std.testing.expect(diagram.name == null);
    try std.testing.expectEqualStrings(source, diagram.mermaid_source);
}
