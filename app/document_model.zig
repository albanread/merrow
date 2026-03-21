const std = @import("std");

pub const TextBlock = struct {
    content: []const u8,
    start_offset: usize,
    end_offset: usize,
    start_line: usize,
    end_line: usize,
};

pub const DiagramBlock = struct {
    name: ?[]const u8,
    mermaid_source: []const u8,
    content_hash: u64,
    start_offset: usize,
    end_offset: usize,
    start_line: usize,
    end_line: usize,
};

pub const Block = union(enum) {
    text: TextBlock,
    diagram: DiagramBlock,

    pub fn startLine(self: Block) usize {
        return switch (self) {
            .text => |text| text.start_line,
            .diagram => |diagram| diagram.start_line,
        };
    }

    pub fn endLine(self: Block) usize {
        return switch (self) {
            .text => |text| text.end_line,
            .diagram => |diagram| diagram.end_line,
        };
    }
};

pub const MarkdownDocument = struct {
    allocator: std.mem.Allocator,
    source: []u8,
    source_path: ?[]u8,
    blocks: []Block,
    diagram_count: usize,

    pub fn deinit(self: *MarkdownDocument) void {
        if (self.source_path) |source_path| {
            self.allocator.free(source_path);
        }
        self.allocator.free(self.blocks);
        self.allocator.free(self.source);
        self.* = undefined;
    }

    pub fn diagramAt(self: *const MarkdownDocument, diagram_index: usize) ?*const DiagramBlock {
        var current_index: usize = 0;
        for (self.blocks) |*block| {
            switch (block.*) {
                .diagram => |*diagram| {
                    if (current_index == diagram_index) return diagram;
                    current_index += 1;
                },
                else => {},
            }
        }
        return null;
    }

    pub fn blockIndexForDiagram(self: *const MarkdownDocument, diagram_index: usize) ?usize {
        var current_index: usize = 0;
        for (self.blocks, 0..) |block, block_index| {
            switch (block) {
                .diagram => {
                    if (current_index == diagram_index) return block_index;
                    current_index += 1;
                },
                else => {},
            }
        }
        return null;
    }

    pub fn diagramIndexForOffset(self: *const MarkdownDocument, offset: usize) ?usize {
        var current_index: usize = 0;
        for (self.blocks) |block| {
            switch (block) {
                .diagram => |diagram| {
                    if (offset >= diagram.start_offset and offset < diagram.end_offset) {
                        return current_index;
                    }
                    current_index += 1;
                },
                else => {},
            }
        }
        return null;
    }
};
