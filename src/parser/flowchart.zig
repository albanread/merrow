const std = @import("std");
const lexer_mod = @import("lexer.zig");
const digraph_mod = @import("../graph/digraph.zig");
const model_mod = @import("../model.zig");

const Lexer = lexer_mod.Lexer;
const Token = lexer_mod.Token;
const TokenType = lexer_mod.TokenType;
const GraphData = model_mod.GraphData;
const NodeData = model_mod.NodeData;
const EdgeData = model_mod.EdgeData;
const NodeShape = model_mod.NodeShape;
const LineStyle = model_mod.LineStyle;
const EdgeKey = digraph_mod.EdgeKey;

pub const FlowchartGraph = digraph_mod.Digraph(NodeData, EdgeData, GraphData);

pub const ParserError = error{
    UnexpectedToken,
    OutOfMemory,
    InvalidSyntax,
    SourceNodeMissing, // Should be handled internally but exposed for safety
    TargetNodeMissing,
};

/// Maximum nesting depth for subgraphs.
const max_subgraph_depth: usize = 16;

/// A style class definition parsed from `classDef className fill:#f9f,...`
pub const StyleClass = struct {
    fill_color: ?[4]u8 = null,
    stroke_color: ?[4]u8 = null,
    stroke_width: ?i32 = null,
    text_color: ?[4]u8 = null,
};

/// Parse a CSS hex color string into RGBA.
/// Supports: `#RGB`, `#RRGGBB`, `#RRGGBBAA`, and bare `RGB`/`RRGGBB`/`RRGGBBAA`.
pub fn parseHexColor(raw: []const u8) ?[4]u8 {
    var hex = raw;
    // Strip leading '#' if present
    if (hex.len > 0 and hex[0] == '#') {
        hex = hex[1..];
    }

    if (hex.len == 3) {
        // #RGB → expand to RRGGBB
        const r = hexDigit(hex[0]) orelse return null;
        const g = hexDigit(hex[1]) orelse return null;
        const b = hexDigit(hex[2]) orelse return null;
        return .{ r | (r << 4), g | (g << 4), b | (b << 4), 255 };
    } else if (hex.len == 4) {
        // #RGBA → expand
        const r = hexDigit(hex[0]) orelse return null;
        const g = hexDigit(hex[1]) orelse return null;
        const b = hexDigit(hex[2]) orelse return null;
        const a = hexDigit(hex[3]) orelse return null;
        return .{ r | (r << 4), g | (g << 4), b | (b << 4), a | (a << 4) };
    } else if (hex.len == 6) {
        // #RRGGBB
        const r = hexByte(hex[0], hex[1]) orelse return null;
        const g = hexByte(hex[2], hex[3]) orelse return null;
        const b = hexByte(hex[4], hex[5]) orelse return null;
        return .{ r, g, b, 255 };
    } else if (hex.len == 8) {
        // #RRGGBBAA
        const r = hexByte(hex[0], hex[1]) orelse return null;
        const g = hexByte(hex[2], hex[3]) orelse return null;
        const b = hexByte(hex[4], hex[5]) orelse return null;
        const a = hexByte(hex[6], hex[7]) orelse return null;
        return .{ r, g, b, a };
    }

    // Try named colors
    return namedColor(raw);
}

fn hexDigit(c: u8) ?u8 {
    if (c >= '0' and c <= '9') return c - '0';
    if (c >= 'a' and c <= 'f') return c - 'a' + 10;
    if (c >= 'A' and c <= 'F') return c - 'A' + 10;
    return null;
}

fn hexByte(hi: u8, lo: u8) ?u8 {
    const h = hexDigit(hi) orelse return null;
    const l = hexDigit(lo) orelse return null;
    return (h << 4) | l;
}

/// A small set of CSS named colors commonly used in Mermaid diagrams.
fn namedColor(name: []const u8) ?[4]u8 {
    const Entry = struct { key: []const u8, val: [4]u8 };
    const table = [_]Entry{
        .{ .key = "red", .val = .{ 255, 0, 0, 255 } },
        .{ .key = "green", .val = .{ 0, 128, 0, 255 } },
        .{ .key = "blue", .val = .{ 0, 0, 255, 255 } },
        .{ .key = "yellow", .val = .{ 255, 255, 0, 255 } },
        .{ .key = "orange", .val = .{ 255, 165, 0, 255 } },
        .{ .key = "purple", .val = .{ 128, 0, 128, 255 } },
        .{ .key = "pink", .val = .{ 255, 192, 203, 255 } },
        .{ .key = "cyan", .val = .{ 0, 255, 255, 255 } },
        .{ .key = "magenta", .val = .{ 255, 0, 255, 255 } },
        .{ .key = "white", .val = .{ 255, 255, 255, 255 } },
        .{ .key = "black", .val = .{ 0, 0, 0, 255 } },
        .{ .key = "gray", .val = .{ 128, 128, 128, 255 } },
        .{ .key = "grey", .val = .{ 128, 128, 128, 255 } },
        .{ .key = "lightgray", .val = .{ 211, 211, 211, 255 } },
        .{ .key = "lightgrey", .val = .{ 211, 211, 211, 255 } },
        .{ .key = "darkgray", .val = .{ 169, 169, 169, 255 } },
        .{ .key = "darkgrey", .val = .{ 169, 169, 169, 255 } },
        .{ .key = "lightblue", .val = .{ 173, 216, 230, 255 } },
        .{ .key = "lightgreen", .val = .{ 144, 238, 144, 255 } },
        .{ .key = "darkgreen", .val = .{ 0, 100, 0, 255 } },
        .{ .key = "darkblue", .val = .{ 0, 0, 139, 255 } },
        .{ .key = "darkred", .val = .{ 139, 0, 0, 255 } },
        .{ .key = "coral", .val = .{ 255, 127, 80, 255 } },
        .{ .key = "salmon", .val = .{ 250, 128, 114, 255 } },
        .{ .key = "gold", .val = .{ 255, 215, 0, 255 } },
        .{ .key = "tomato", .val = .{ 255, 99, 71, 255 } },
        .{ .key = "navy", .val = .{ 0, 0, 128, 255 } },
        .{ .key = "teal", .val = .{ 0, 128, 128, 255 } },
        .{ .key = "olive", .val = .{ 128, 128, 0, 255 } },
        .{ .key = "maroon", .val = .{ 128, 0, 0, 255 } },
        .{ .key = "aqua", .val = .{ 0, 255, 255, 255 } },
        .{ .key = "lime", .val = .{ 0, 255, 0, 255 } },
        .{ .key = "silver", .val = .{ 192, 192, 192, 255 } },
        .{ .key = "transparent", .val = .{ 0, 0, 0, 0 } },
        .{ .key = "none", .val = .{ 0, 0, 0, 0 } },
    };

    // Case-insensitive comparison via lowercased copy
    var lower_buf: [32]u8 = undefined;
    if (name.len > lower_buf.len) return null;
    for (name, 0..) |c, i| {
        lower_buf[i] = if (c >= 'A' and c <= 'Z') c + 32 else c;
    }
    const lower = lower_buf[0..name.len];

    for (table) |entry| {
        if (std.mem.eql(u8, entry.key, lower)) return entry.val;
    }
    return null;
}

/// Parse a CSS property value string for style classes.
/// Expects comma-separated key:value pairs like:
///   "fill:#f9f,stroke:#333,stroke-width:4px,color:#fff"
/// Also handles semicolons as separators and trailing semicolons.
fn parseStyleProperties(raw: []const u8) StyleClass {
    var style = StyleClass{};

    // Split on comma or semicolon
    var rest = raw;
    while (rest.len > 0) {
        // Find next separator (, or ;) or end
        var sep_idx: usize = rest.len;
        for (rest, 0..) |c, i| {
            if (c == ',' or c == ';') {
                sep_idx = i;
                break;
            }
        }

        const pair = trimWhitespace(rest[0..sep_idx]);
        if (sep_idx < rest.len) {
            rest = rest[sep_idx + 1 ..];
        } else {
            rest = rest[rest.len..];
        }

        if (pair.len == 0) continue;

        // Split on first ':'
        var colon_idx: ?usize = null;
        for (pair, 0..) |c, i| {
            if (c == ':') {
                colon_idx = i;
                break;
            }
        }

        if (colon_idx) |ci| {
            const key = trimWhitespace(pair[0..ci]);
            const val = trimWhitespace(pair[ci + 1 ..]);

            if (std.mem.eql(u8, key, "fill")) {
                style.fill_color = parseHexColor(val);
            } else if (std.mem.eql(u8, key, "stroke")) {
                style.stroke_color = parseHexColor(val);
            } else if (std.mem.eql(u8, key, "stroke-width")) {
                style.stroke_width = parsePixelValue(val);
            } else if (std.mem.eql(u8, key, "color")) {
                style.text_color = parseHexColor(val);
            }
        }
    }

    return style;
}

/// Parse a pixel value like "4px" or "2" into an integer.
fn parsePixelValue(raw: []const u8) ?i32 {
    var s = raw;
    // Strip trailing "px" if present
    if (s.len >= 2 and std.mem.eql(u8, s[s.len - 2 ..], "px")) {
        s = s[0 .. s.len - 2];
    }
    return std.fmt.parseInt(i32, s, 10) catch null;
}

fn trimWhitespace(s: []const u8) []const u8 {
    var start: usize = 0;
    while (start < s.len and (s[start] == ' ' or s[start] == '\t' or s[start] == '\r')) {
        start += 1;
    }
    var end: usize = s.len;
    while (end > start and (s[end - 1] == ' ' or s[end - 1] == '\t' or s[end - 1] == '\r')) {
        end -= 1;
    }
    return s[start..end];
}

/// Maximum number of style class definitions supported.
const max_style_classes: usize = 64;

/// An edge reference recorded in declaration order (for `linkStyle` indexing).
const EdgeRef = struct {
    v: []const u8,
    w: []const u8,
    name: ?[]const u8,
};

/// Parsed style properties from a `linkStyle` declaration.
const LinkStyleProps = struct {
    color: ?[4]u8 = null,
    thickness: ?i32 = null,
    line_style: ?LineStyle = null,
};

pub const Parser = struct {
    allocator: std.mem.Allocator,
    lexer: Lexer,
    curr: Token,
    peeked: Token,
    graph: FlowchartGraph,
    current_subgraph: ?[]const u8,

    /// Stack of nested subgraph IDs (outermost first).
    subgraph_stack_buf: [max_subgraph_depth][]const u8 = undefined,
    subgraph_stack_len: usize = 0,

    /// Style class definitions: maps class name → StyleClass.
    /// We use parallel arrays for simplicity (no hashmap needed for small N).
    class_names: [max_style_classes][]const u8 = undefined,
    class_styles: [max_style_classes]StyleClass = undefined,
    class_count: usize = 0,

    /// Edges in declaration order (for `linkStyle N` indexing).
    edge_order: std.ArrayListUnmanaged(EdgeRef) = .{},

    /// Default link style (applied to all edges without an explicit linkStyle).
    default_link_style: ?LinkStyleProps = null,

    pub fn init(allocator: std.mem.Allocator, source: []const u8) !Parser {
        var lexer = Lexer.init(source);
        const first = lexer.next();
        const second = lexer.next();

        return Parser{
            .allocator = allocator,
            .lexer = lexer,
            .curr = first,
            .peeked = second,
            .graph = FlowchartGraph.init(allocator),
            .current_subgraph = null,
            .subgraph_stack_len = 0,
            .class_count = 0,
        };
    }

    pub fn deinit(self: *Parser) void {
        self.edge_order.deinit(self.allocator);
        // We do not deinit the graph here because we usually want to return it.
        // The caller is responsible for the graph.
        // If parsing fails, the caller should deinit the graph if they retrieved it,
        // or we should handle cleanup on error.
    }

    fn advance(self: *Parser) void {
        self.curr = self.peeked;
        self.peeked = self.lexer.next();
    }

    fn match(self: *Parser, expected: TokenType) bool {
        if (self.curr.type == expected) {
            self.advance();
            return true;
        }
        return false;
    }

    fn expect(self: *Parser, expected: TokenType) !Token {
        if (self.curr.type == expected) {
            const token = self.curr;
            self.advance();
            return token;
        }
        return ParserError.UnexpectedToken;
    }

    fn skipNewlines(self: *Parser) void {
        while (self.curr.type == .newline or self.curr.type == .whitespace or self.curr.type == .comment) {
            self.advance();
        }
    }

    /// Skip to end of current line (consumes everything until newline or EOF).
    fn skipToEndOfLine(self: *Parser) void {
        while (self.curr.type != .newline and self.curr.type != .eof) {
            self.advance();
        }
    }

    pub fn parse(self: *Parser) !FlowchartGraph {
        // Parse Header: graph TD / flowchart LR
        try self.parseHeader();

        while (self.curr.type != .eof) {
            self.skipNewlines();
            if (self.curr.type == .eof) break;

            try self.parseStatement();
        }

        return self.graph;
    }

    fn parseHeader(self: *Parser) !void {
        self.skipNewlines();

        // Optional "graph" or "flowchart" keyword
        if (self.curr.type == .keyword_graph or self.curr.type == .keyword_flowchart) {
            self.advance();

            // Optional whitespace
            if (self.curr.type == .whitespace) self.advance();

            // Optional Direction
            if (self.isDirection(self.curr.type)) {
                var gd = self.graph.getGraphLabel();
                gd.rankdir = self.curr.text;
                self.advance();
            }
        }
    }

    fn isDirection(self: *Parser, t: TokenType) bool {
        _ = self;
        return switch (t) {
            .dir_td, .dir_lr, .dir_bt, .dir_rl => true,
            else => false,
        };
    }

    fn parseStatement(self: *Parser) !void {
        if (self.curr.type == .keyword_subgraph) {
            try self.parseSubgraph();
        } else if (self.curr.type == .keyword_end) {
            // End of subgraph — pop from stack
            if (self.subgraph_stack_len > 0) {
                self.subgraph_stack_len -= 1;
            }
            // Restore parent subgraph context (or null if at top level)
            self.current_subgraph = if (self.subgraph_stack_len > 0)
                self.subgraph_stack_buf[self.subgraph_stack_len - 1]
            else
                null;
            self.advance();
        } else if (self.curr.type == .keyword_classDef) {
            try self.parseClassDef();
        } else if (self.curr.type == .keyword_class) {
            try self.parseClassStatement();
        } else if (self.curr.type == .keyword_linkStyle) {
            try self.parseLinkStyle();
        } else if (self.curr.type == .keyword_style) {
            try self.parseStyleDirective();
        } else if (self.curr.type == .keyword_click) {
            try self.parseClick();
        } else if (self.curr.type == .identifier) {
            try self.parseNodeStatement();
        } else {
            // Skip unknown or error
            self.advance();
        }
    }

    fn parseSubgraph(self: *Parser) !void {
        self.advance(); // consume 'subgraph'

        if (self.curr.type == .whitespace) self.advance();

        const id_token = try self.expect(.identifier);
        const subgraph_id = id_token.text;

        // Skip optional whitespace between ID and title bracket
        if (self.curr.type == .whitespace) self.advance();

        // Parse optional [Title] for the subgraph display label
        var title: ?[]const u8 = null;
        var title_owned: bool = false;
        if (self.curr.type == .l_bracket) {
            self.advance(); // consume '['

            var title_buf = std.ArrayListUnmanaged(u8){};
            defer title_buf.deinit(self.allocator);

            while (self.curr.type != .r_bracket and self.curr.type != .eof and self.curr.type != .newline) {
                try title_buf.appendSlice(self.allocator, self.curr.text);
                self.advance();
            }

            if (self.curr.type == .r_bracket) {
                self.advance(); // consume ']'
            }

            if (title_buf.items.len > 0) {
                title = try self.allocator.dupe(u8, title_buf.items);
                title_owned = true;
            }
        }

        // If setNode or setParent fails below, free the duped title so it
        // doesn't leak (it hasn't been stored in the graph yet).
        errdefer {
            if (title_owned) {
                if (title) |t| self.allocator.free(t);
            }
        }

        // Register subgraph as a special node
        const node_data = NodeData{
            .label = title orelse subgraph_id,
            .label_owned = false, // label points to title or source; title is owned via subgraph_title
            .shape = .box,
            .is_subgraph = true,
            .subgraph_title = title,
            .subgraph_title_owned = title_owned,
        };
        try self.graph.setNode(subgraph_id, node_data);

        // Push onto subgraph stack and set as current context
        if (self.current_subgraph) |parent_sg| {
            // Nested subgraph — set parent relationship
            try self.graph.setParent(subgraph_id, parent_sg);
        }
        if (self.subgraph_stack_len < max_subgraph_depth) {
            self.subgraph_stack_buf[self.subgraph_stack_len] = subgraph_id;
            self.subgraph_stack_len += 1;
        }
        self.current_subgraph = subgraph_id;
    }

    /// Parse a `classDef` statement:
    ///   classDef className fill:#f9f,stroke:#333,stroke-width:4px,color:#fff
    ///   classDef className fill:#f9f,stroke:#333,stroke-width:4px;
    fn parseClassDef(self: *Parser) !void {
        self.advance(); // consume 'classDef'

        if (self.curr.type == .whitespace) self.advance();

        // Class name
        if (self.curr.type != .identifier) {
            self.skipToEndOfLine();
            return;
        }
        const class_name = self.curr.text;
        self.advance();

        if (self.curr.type == .whitespace) self.advance();

        // Collect the rest of the line as the raw style property string.
        // We concatenate all token texts until newline/eof/semicolon(at line level).
        var prop_buf = std.ArrayListUnmanaged(u8){};
        defer prop_buf.deinit(self.allocator);

        while (self.curr.type != .newline and self.curr.type != .eof) {
            // A semicolon at the end of a classDef line terminates it
            if (self.curr.type == .semicolon) {
                self.advance();
                break;
            }
            try prop_buf.appendSlice(self.allocator, self.curr.text);
            self.advance();
        }

        // Parse the collected property string
        const style = parseStyleProperties(prop_buf.items);

        // Store the class definition
        if (self.class_count < max_style_classes) {
            self.class_names[self.class_count] = class_name;
            self.class_styles[self.class_count] = style;
            self.class_count += 1;
        }
    }

    /// Parse a `class` statement:
    ///   class nodeId1,nodeId2 className
    ///   class A,B,C myStyle;
    fn parseClassStatement(self: *Parser) !void {
        self.advance(); // consume 'class'

        if (self.curr.type == .whitespace) self.advance();

        // Collect comma-separated node IDs.  The list ends when we see no
        // comma after an identifier — at that point the *next* identifier
        // (separated by whitespace) is the class name.
        var node_ids_buf: [128][]const u8 = undefined;
        var node_count: usize = 0;

        while (self.curr.type == .identifier and node_count < node_ids_buf.len) {
            node_ids_buf[node_count] = self.curr.text;
            node_count += 1;
            self.advance();

            // Check for comma (with optional surrounding whitespace).
            if (self.curr.type == .whitespace) self.advance();
            if (self.curr.type == .comma) {
                self.advance(); // consume ','
                if (self.curr.type == .whitespace) self.advance();
                // Continue collecting comma-separated node IDs.
            } else {
                // No comma — the comma-separated list has ended.
                // The *current* token (if identifier) is the class name.
                break;
            }
        }

        // After the comma-separated node list, the current token should be
        // the class name identifier.
        var class_name: ?[]const u8 = null;
        if (self.curr.type == .identifier) {
            class_name = self.curr.text;
            self.advance();
        }

        if (class_name == null) {
            // Could not determine class name — skip
            self.skipToEndOfLine();
            return;
        }

        if (node_count == 0) {
            self.skipToEndOfLine();
            return;
        }

        // Look up the class and apply to each node
        const style = self.lookupClass(class_name.?);
        if (style) |s| {
            for (node_ids_buf[0..node_count]) |node_id| {
                self.applyStyleToNode(node_id, s);
            }
        }

        // Consume optional trailing semicolon
        if (self.curr.type == .whitespace) self.advance();
        if (self.curr.type == .semicolon) self.advance();
    }

    /// Look up a style class by name.
    fn lookupClass(self: *Parser, name: []const u8) ?StyleClass {
        for (0..self.class_count) |i| {
            if (std.mem.eql(u8, self.class_names[i], name)) {
                return self.class_styles[i];
            }
        }
        return null;
    }

    /// Apply a style class's properties to an existing node in the graph.
    fn applyStyleToNode(self: *Parser, node_id: []const u8, style: StyleClass) void {
        if (self.graph.getNodePtr(node_id)) |node| {
            if (style.fill_color) |c| node.fill_color = c;
            if (style.stroke_color) |c| node.stroke_color = c;
            if (style.stroke_width) |w| node.stroke_width = w;
            if (style.text_color) |c| node.text_color = c;
        }
    }

    /// Parse a `style` directive (inline node styling):
    ///   style nodeId fill:#f9f,stroke:#333,stroke-width:4px,color:#fff
    ///   style nodeId1,nodeId2 fill:#f9f,stroke:#333;
    fn parseStyleDirective(self: *Parser) !void {
        self.advance(); // consume 'style'
        if (self.curr.type == .whitespace) self.advance();

        // Collect comma-separated node IDs until we hit a token that
        // looks like a style property (contains ':' when we accumulate
        // the rest of the line) or whitespace followed by a non-id/comma.
        var node_ids_buf: [128][]const u8 = undefined;
        var node_count: usize = 0;

        while (self.curr.type == .identifier and node_count < node_ids_buf.len) {
            node_ids_buf[node_count] = self.curr.text;
            node_count += 1;
            self.advance();

            // Check for comma (with optional surrounding whitespace).
            if (self.curr.type == .whitespace) self.advance();
            if (self.curr.type == .comma) {
                self.advance(); // consume ','
                if (self.curr.type == .whitespace) self.advance();
                // Continue collecting comma-separated node IDs.
            } else {
                // No comma — the comma-separated list has ended.
                // The rest of the line is style properties.
                break;
            }
        }

        if (node_count == 0) {
            self.skipToEndOfLine();
            return;
        }

        // Accumulate the rest of the line as style properties string
        var prop_buf = std.ArrayListUnmanaged(u8){};
        defer prop_buf.deinit(self.allocator);

        while (self.curr.type != .newline and self.curr.type != .eof) {
            if (self.curr.type == .semicolon) {
                self.advance();
                break;
            }
            try prop_buf.appendSlice(self.allocator, self.curr.text);
            self.advance();
        }

        // Parse the collected property string (reuses classDef property parser)
        const style = parseStyleProperties(prop_buf.items);

        // Apply directly to each named node
        for (node_ids_buf[0..node_count]) |node_id| {
            self.applyStyleToNode(node_id, style);
        }
    }

    /// Parse a `click` directive (hyperlink/callback):
    ///   click nodeId "url"
    ///   click nodeId "url" "tooltip"
    ///   click nodeId href "url"
    ///   click nodeId href "url" "tooltip"
    ///   click nodeId href "url" _blank
    fn parseClick(self: *Parser) !void {
        self.advance(); // consume 'click'
        if (self.curr.type == .whitespace) self.advance();

        // Node ID
        if (self.curr.type != .identifier) {
            self.skipToEndOfLine();
            return;
        }
        const node_id = self.curr.text;
        self.advance();
        if (self.curr.type == .whitespace) self.advance();

        // Optional "href" keyword (skip if present — it's just syntactic sugar)
        if (self.curr.type == .identifier and std.mem.eql(u8, self.curr.text, "href")) {
            self.advance();
            if (self.curr.type == .whitespace) self.advance();
        }

        // URL — must be a string literal
        if (self.curr.type != .string_literal) {
            // Could also be "callback" form which we don't support — skip
            self.skipToEndOfLine();
            return;
        }
        const url_text = self.curr.text;
        self.advance();
        if (self.curr.type == .whitespace) self.advance();

        // Optional tooltip (string literal) or target (_blank, _self, etc.)
        var tooltip_text: ?[]const u8 = null;
        var target_text: ?[]const u8 = null;

        if (self.curr.type == .string_literal) {
            tooltip_text = self.curr.text;
            self.advance();
            if (self.curr.type == .whitespace) self.advance();
        }

        // Optional target after tooltip or URL
        if (self.curr.type == .identifier) {
            const t = self.curr.text;
            if (t.len > 0 and t[0] == '_') {
                target_text = t;
                self.advance();
            }
        }

        // Consume optional trailing semicolon
        if (self.curr.type == .whitespace) self.advance();
        if (self.curr.type == .semicolon) self.advance();

        // Apply to the node
        if (self.graph.getNodePtr(node_id)) |node| {
            // Duplicate URL string so we own it
            const url_owned = self.allocator.dupe(u8, url_text) catch return;
            // Free previous URL if any
            if (node.link_url_owned) {
                if (node.link_url) |old| self.allocator.free(old);
            }
            node.link_url = url_owned;
            node.link_url_owned = true;

            if (tooltip_text) |tt| {
                const tooltip_owned = self.allocator.dupe(u8, tt) catch return;
                if (node.link_tooltip_owned) {
                    if (node.link_tooltip) |old| self.allocator.free(old);
                }
                node.link_tooltip = tooltip_owned;
                node.link_tooltip_owned = true;
            }

            // Target is a borrowed slice from source — no need to dupe
            // (it points into the original source text which outlives the graph usage)
            if (target_text) |tt| {
                node.link_target = tt;
            } else {
                // Default target for links: open in new tab
                node.link_target = "_blank";
            }
        }
    }

    fn parseNodeStatement(self: *Parser) !void {
        var source_id = try self.parseNode();

        while (true) {
            if (self.curr.type == .whitespace) self.advance();

            if (!self.isArrow(self.curr.type)) {
                break;
            }

            const edge_type = self.curr.type;
            self.advance();

            if (self.curr.type == .whitespace) self.advance();

            // Parse optional edge label: |label text|
            var edge_label: ?[]const u8 = null;
            if (self.curr.type == .pipe) {
                self.advance(); // consume opening |

                var label_buf = std.ArrayListUnmanaged(u8){};
                defer label_buf.deinit(self.allocator);

                while (self.curr.type != .pipe and self.curr.type != .eof and self.curr.type != .newline) {
                    try label_buf.appendSlice(self.allocator, self.curr.text);
                    self.advance();
                }

                if (self.curr.type == .pipe) {
                    self.advance(); // consume closing |
                }

                if (label_buf.items.len > 0) {
                    edge_label = try self.allocator.dupe(u8, label_buf.items);
                }

                if (self.curr.type == .whitespace) self.advance();
            }

            // If parseNode or setEdge fails below, free the duped edge
            // label so it doesn't leak (it hasn't been stored yet).
            errdefer {
                if (edge_label) |lbl| self.allocator.free(lbl);
            }

            const target_id = try self.parseNode();

            var edge_data = EdgeData{};
            if (edge_label) |lbl| {
                edge_data.label = lbl;
                edge_data.label_owned = true;
            }
            // Determine whether this is a left-arrow (swap direction) or
            // bidirectional (arrows on both ends).
            const is_left = (edge_type == .arrow_left);
            const is_bidi = (edge_type == .arrow_both or
                edge_type == .dotted_arrow_both or
                edge_type == .thick_arrow_both);

            switch (edge_type) {
                .arrow_right => {
                    edge_data.arrowhead = "normal";
                },
                .arrow_left => {
                    // Left arrow: edge direction is reversed (target → source
                    // in the graph) so the arrowhead renders at the original
                    // source node.
                    edge_data.arrowhead = "normal";
                },
                .arrow_both => {
                    edge_data.arrowhead = "normal";
                    edge_data.arrowtail = "normal";
                },
                .dotted_arrow_right => {
                    edge_data.arrowhead = "normal";
                    edge_data.style = "stroke-dasharray: 5, 5;";
                    edge_data.line_style = .dotted;
                },
                .dotted_arrow_both => {
                    edge_data.arrowhead = "normal";
                    edge_data.arrowtail = "normal";
                    edge_data.style = "stroke-dasharray: 5, 5;";
                    edge_data.line_style = .dotted;
                },
                .thick_arrow_right => {
                    edge_data.arrowhead = "normal";
                    edge_data.style = "stroke-width: 2px;";
                    edge_data.line_style = .thick;
                },
                .thick_arrow_both => {
                    edge_data.arrowhead = "normal";
                    edge_data.arrowtail = "normal";
                    edge_data.style = "stroke-width: 2px;";
                    edge_data.line_style = .thick;
                },
                .line => {
                    edge_data.arrowhead = "none";
                },
                else => {},
            }

            if (is_left) {
                // Left arrow: swap source and target so the graph edge goes
                // from the right-hand node to the left-hand node, giving the
                // correct rank ordering in layout.
                try self.graph.setEdge(target_id, source_id, edge_data, null);
                const ref = EdgeRef{ .v = target_id, .w = source_id, .name = null };
                try self.edge_order.append(self.allocator, ref);
                if (self.default_link_style) |props| {
                    applyLinkStyleToEdge(&self.graph, ref, props);
                }
            } else {
                try self.graph.setEdge(source_id, target_id, edge_data, null);
                const ref = EdgeRef{ .v = source_id, .w = target_id, .name = null };
                try self.edge_order.append(self.allocator, ref);
                if (self.default_link_style) |props| {
                    applyLinkStyleToEdge(&self.graph, ref, props);
                }
            }

            // For bidirectional arrows the chain continues from the target
            // as written (the node on the right).  For left arrows the
            // "next source" is still the right-hand node (target_id) so
            // chaining like `A <-- B --> C` works naturally.
            _ = is_bidi;

            source_id = target_id;
        }
    }

    // ================================================================
    // linkStyle parsing
    // ================================================================

    /// Parse a `linkStyle` statement:
    ///   linkStyle 0 stroke:#ff3,stroke-width:4px
    ///   linkStyle 0,1,2 stroke:red,stroke-width:2px
    ///   linkStyle default stroke:#333,stroke-width:2px
    fn parseLinkStyle(self: *Parser) !void {
        self.advance(); // consume 'linkStyle'
        if (self.curr.type == .whitespace) self.advance();

        // Determine target indices or "default"
        var indices = std.ArrayListUnmanaged(usize){};
        defer indices.deinit(self.allocator);
        var is_default = false;

        if (self.curr.type == .identifier and std.mem.eql(u8, self.curr.text, "default")) {
            is_default = true;
            self.advance();
        } else {
            // Parse comma-separated list of integer indices.
            // Indices may be plain identifiers containing digits (e.g. "0", "12").
            while (self.curr.type == .identifier or self.curr.type == .comma) {
                if (self.curr.type == .comma) {
                    self.advance();
                    if (self.curr.type == .whitespace) self.advance();
                    continue;
                }
                const idx = std.fmt.parseInt(usize, self.curr.text, 10) catch {
                    // Not a valid integer — this is the start of style
                    // properties (e.g. "stroke:..."), so stop index parsing.
                    break;
                };
                try indices.append(self.allocator, idx);
                self.advance();
                // Allow optional comma or whitespace between indices
                if (self.curr.type == .whitespace) self.advance();
                if (self.curr.type == .comma) {
                    self.advance();
                    if (self.curr.type == .whitespace) self.advance();
                }
            }
        }

        if (self.curr.type == .whitespace) self.advance();

        // Accumulate the rest of the line as style properties string
        var prop_buf = std.ArrayListUnmanaged(u8){};
        defer prop_buf.deinit(self.allocator);

        while (self.curr.type != .newline and self.curr.type != .eof) {
            if (self.curr.type == .semicolon) {
                self.advance();
                break;
            }
            try prop_buf.appendSlice(self.allocator, self.curr.text);
            self.advance();
        }

        // Parse the CSS-like style properties
        const props = parseLinkStyleProperties(prop_buf.items);

        if (is_default) {
            // Store as default and apply to all edges that have already been added
            self.default_link_style = props;
            for (self.edge_order.items) |ref| {
                applyLinkStyleToEdge(&self.graph, ref, props);
            }
        } else {
            for (indices.items) |idx| {
                if (idx < self.edge_order.items.len) {
                    applyLinkStyleToEdge(&self.graph, self.edge_order.items[idx], props);
                }
            }
        }
    }

    /// Apply link style properties to a specific edge in the graph.
    fn applyLinkStyleToEdge(graph: *FlowchartGraph, ref: EdgeRef, props: LinkStyleProps) void {
        if (graph.getEdgePtr(ref.v, ref.w, ref.name)) |ed| {
            if (props.color) |c| ed.color = c;
            if (props.thickness) |t| ed.thickness = t;
            if (props.line_style) |ls| ed.line_style = ls;
        }
    }

    /// Parse CSS-like style properties from a linkStyle value string.
    /// Supports: stroke, stroke-width, stroke-dasharray
    fn parseLinkStyleProperties(raw: []const u8) LinkStyleProps {
        var result = LinkStyleProps{};
        // Split on commas, but be careful — commas also appear inside
        // stroke-dasharray values like "5, 5".  Strategy: split on commas
        // that are followed by a property name (contain ':'), otherwise
        // treat the whole thing as one segment.  Simpler approach: split
        // on commas and rejoin segments that don't contain ':' with the
        // previous one.  For now, use a simpler heuristic: iterate through
        // comma-separated tokens and parse each as key:value.

        var iter = std.mem.splitScalar(u8, raw, ',');
        while (iter.next()) |segment_raw| {
            const segment = trimWhitespace(segment_raw);
            if (segment.len == 0) continue;

            // Find the colon separator
            if (std.mem.indexOfScalar(u8, segment, ':')) |colon_pos| {
                const key = trimWhitespace(segment[0..colon_pos]);
                const value = trimWhitespace(segment[colon_pos + 1 ..]);

                if (std.mem.eql(u8, key, "stroke")) {
                    // Parse color value
                    if (parseHexColor(value)) |c| {
                        result.color = c;
                    } else if (namedColor(value)) |c| {
                        result.color = c;
                    }
                } else if (std.mem.eql(u8, key, "stroke-width")) {
                    result.thickness = parsePixelValue(value);
                } else if (std.mem.eql(u8, key, "stroke-dasharray")) {
                    // If a dash array is specified, treat as dashed
                    if (value.len > 0) {
                        result.line_style = .dashed;
                    }
                }
            }
        }

        return result;
    }

    fn isArrow(self: *Parser, t: TokenType) bool {
        _ = self;
        return switch (t) {
            .arrow_right,
            .arrow_left,
            .arrow_both,
            .line,
            .dotted_arrow_right,
            .dotted_arrow_both,
            .thick_arrow_right,
            .thick_arrow_both,
            => true,
            else => false,
        };
    }

    /// Parses a node definition: ID or ID[Label] or ID((Label)) etc.
    /// Also handles :::className suffix for style class application.
    /// Adds node to graph if not exists.
    /// Returns the Node ID.
    fn parseNode(self: *Parser) ![]const u8 {
        const id_token = try self.expect(.identifier);
        const id = id_token.text;

        var label = id;
        var shape = NodeShape.box;
        var has_shape = false;

        // Check for Shape Definition immediately after ID
        // Note: Lexer might put whitespace between ID and [.
        // Standard Mermaid `A[B]` usually has no space, but `A [B]` might work?
        // Merrow lexer seems to handle them as separate tokens.

        // If next is start of shape
        if (self.curr.type == .l_bracket or self.curr.type == .l_paren or
            self.curr.type == .l_double_paren or self.curr.type == .l_brace)
        {
            has_shape = true;
            const open_type = self.curr.type;
            self.advance();

            // -----------------------------------------------------------------
            // Detect compound shape delimiters by looking at the second token
            // after the opening bracket/brace/paren.
            //
            // Mermaid shape syntax:
            //   [text]     → box           (l_bracket ... r_bracket)
            //   (text)     → round         (l_paren ... r_paren)
            //   ((text))   → circle        (l_double_paren ... r_double_paren)
            //   {text}     → diamond       (l_brace ... r_brace)
            //   {{text}}   → hexagon       (l_brace + l_brace ... r_brace + r_brace)
            //   [(text)]   → cylinder      (l_bracket + l_paren ... r_paren + r_bracket)
            //   ([text])   → stadium       (l_paren + l_bracket ... r_bracket + r_paren)
            //   [[text]]   → subroutine    (l_bracket + l_bracket ... r_bracket + r_bracket)
            //   [/text/]   → trapezoid     (l_bracket + "/" ... "/" + r_bracket)
            //   [\text\]   → trapezoid_alt (l_bracket + "\" ... "\" + r_bracket)
            //   [/text\]   → parallelogram (l_bracket + "/" ... "\" + r_bracket)
            //   [\text/]   → parallelogram_alt (l_bracket + "\" ... "/" + r_bracket)
            // -----------------------------------------------------------------

            // Determine shape and closers from opener + possible second token
            var closer: TokenType = undefined;
            var closer2: ?TokenType = null; // second closing token for compound delimiters
            var slash_closer: ?u8 = null; // '/' or '\\' closer for trapezoid/parallelogram

            if (open_type == .l_brace and self.curr.type == .l_brace) {
                // {{ → hexagon
                shape = .hexagon;
                self.advance(); // consume second {
                closer = .r_brace;
                closer2 = .r_brace; // expect }} at close
            } else if (open_type == .l_bracket and self.curr.type == .l_paren) {
                // [( → cylinder
                shape = .cylinder;
                self.advance(); // consume (
                closer = .r_paren;
                closer2 = .r_bracket; // expect )] at close
            } else if (open_type == .l_paren and self.curr.type == .l_bracket) {
                // ([ → stadium
                shape = .stadium;
                self.advance(); // consume [
                closer = .r_bracket;
                closer2 = .r_paren; // expect ]) at close
            } else if (open_type == .l_bracket and self.curr.type == .l_bracket) {
                // [[ → subroutine
                shape = .subroutine;
                self.advance(); // consume second [
                closer = .r_bracket;
                closer2 = .r_bracket; // expect ]] at close
            } else if (open_type == .l_bracket and self.curr.type == .identifier and self.curr.text.len == 1 and (self.curr.text[0] == '/' or self.curr.text[0] == '\\')) {
                // [/ → trapezoid or parallelogram
                // [\ → trapezoid_alt or parallelogram_alt
                // We don't know the exact shape until we see the closing slash.
                const open_slash = self.curr.text[0];
                self.advance(); // consume '/' or '\'
                closer = .r_bracket; // the outer closer is always ]

                // We need to find the closing slash before ].
                // We'll accumulate text and detect the slash at the end.
                // Set a placeholder shape; we'll refine after reading content.
                if (open_slash == '/') {
                    shape = .trapezoid; // may become .parallelogram
                    slash_closer = '/'; // default; will be refined
                } else {
                    shape = .trapezoid_alt; // may become .parallelogram_alt
                    slash_closer = '\\'; // default; will be refined
                }

                // Accumulate label text, stopping when we see an identifier
                // that is "/" or "\" followed by r_bracket (the close pattern).
                var label_buf_slash = std.ArrayListUnmanaged(u8){};
                defer label_buf_slash.deinit(self.allocator);

                while (self.curr.type != .eof) {
                    // Check if current token is a slash/backslash followed by ]
                    if (self.curr.type == .identifier and self.curr.text.len == 1 and
                        (self.curr.text[0] == '/' or self.curr.text[0] == '\\'))
                    {
                        // Peek: is the next non-whitespace token r_bracket?
                        // We use a simple check: next token is r_bracket
                        // (possibly after whitespace, but Mermaid typically has no space)
                        const close_slash = self.curr.text[0];
                        // Save position in case this isn't the real closer
                        const saved_type = self.curr.type;
                        const saved_text = self.curr.text;
                        self.advance();
                        if (self.curr.type == .r_bracket) {
                            // This is the closing pattern — determine final shape
                            if (open_slash == '/' and close_slash == '/') {
                                shape = .trapezoid;
                            } else if (open_slash == '\\' and close_slash == '\\') {
                                shape = .trapezoid_alt;
                            } else if (open_slash == '/' and close_slash == '\\') {
                                shape = .parallelogram;
                            } else {
                                // open_slash == '\' and close_slash == '/'
                                shape = .parallelogram_alt;
                            }
                            self.advance(); // consume ]
                            label = try self.allocator.dupe(u8, label_buf_slash.items);
                            // Skip the normal label accumulation below
                            break;
                        } else {
                            // Not the closer — include the slash in the label
                            _ = saved_type;
                            try label_buf_slash.append(self.allocator, saved_text[0]);
                            // Don't advance again; continue with current token
                        }
                    } else if (self.curr.type == .r_bracket) {
                        // Closing ] without slash — treat as box fallback
                        self.advance();
                        label = try self.allocator.dupe(u8, label_buf_slash.items);
                        break;
                    } else {
                        try label_buf_slash.appendSlice(self.allocator, self.curr.text);
                        self.advance();
                    }
                }

                // Skip the normal label/closer handling below
                has_shape = true;

                // Check for :::className suffix
                var applied_class_name_inner: ?[]const u8 = null;
                if (self.curr.type == .triple_colon) {
                    self.advance();
                    if (self.curr.type == .identifier) {
                        applied_class_name_inner = self.curr.text;
                        self.advance();
                    }
                }

                if (!self.graph.hasNode(id) or true) {
                    errdefer {
                        self.allocator.free(label);
                    }

                    var node_data = NodeData{
                        .label = label,
                        .label_owned = true,
                        .width = 0,
                        .height = 0,
                        .shape = shape,
                        .parent = self.current_subgraph,
                    };

                    if (applied_class_name_inner) |cn| {
                        if (self.lookupClass(cn)) |style_inner| {
                            if (style_inner.fill_color) |c| node_data.fill_color = c;
                            if (style_inner.stroke_color) |c| node_data.stroke_color = c;
                            if (style_inner.stroke_width) |w| node_data.stroke_width = w;
                            if (style_inner.text_color) |c| node_data.text_color = c;
                        }
                    }

                    try self.graph.setNode(id, node_data);
                } else if (applied_class_name_inner) |cn| {
                    if (self.lookupClass(cn)) |style_inner| {
                        self.applyStyleToNode(id, style_inner);
                    }
                }

                if (self.current_subgraph) |parent| {
                    try self.graph.setParent(id, parent);
                }

                return id;
            } else {
                // Simple single-delimiter shapes
                closer = switch (open_type) {
                    .l_bracket => TokenType.r_bracket,
                    .l_paren => TokenType.r_paren,
                    .l_double_paren => TokenType.r_double_paren,
                    .l_brace => TokenType.r_brace,
                    else => unreachable,
                };

                shape = switch (open_type) {
                    .l_bracket => .box,
                    .l_paren => .round,
                    .l_double_paren => .circle,
                    .l_brace => .diamond,
                    else => .box,
                };
            }

            // Accumulate label text until the primary closer token
            var label_buf = std.ArrayListUnmanaged(u8){};
            defer label_buf.deinit(self.allocator);

            while (self.curr.type != closer and self.curr.type != .eof) {
                try label_buf.appendSlice(self.allocator, self.curr.text);
                self.advance();
            }

            // Copy label to persistent memory
            label = try self.allocator.dupe(u8, label_buf.items);

            // Consume primary closer
            if (self.curr.type == closer) {
                self.advance();
            }

            // Consume secondary closer for compound delimiters (e.g., the
            // second } in {{}}, the ] in [()] cylinder, etc.)
            if (closer2) |c2| {
                if (self.curr.type == c2) {
                    self.advance();
                }
            }
        }

        // Check for :::className suffix (style class application)
        var applied_class_name: ?[]const u8 = null;
        if (self.curr.type == .triple_colon) {
            self.advance(); // consume ':::'
            if (self.curr.type == .identifier) {
                applied_class_name = self.curr.text;
                self.advance();
            }
        }

        // Add/Update node in graph
        // Only update if it's a definition (has_shape) or if it doesn't exist.
        if (has_shape or !self.graph.hasNode(id)) {
            // If setNode fails (OOM), free the duped label so it doesn't
            // leak — it hasn't been stored in the graph yet.
            errdefer {
                if (has_shape) self.allocator.free(label);
            }

            var node_data = NodeData{
                .label = label,
                .label_owned = has_shape,
                .width = 0, // Calculated later
                .height = 0,
                .shape = shape,
                .parent = self.current_subgraph,
            };

            // Apply style class if specified via :::
            if (applied_class_name) |cn| {
                if (self.lookupClass(cn)) |style| {
                    if (style.fill_color) |c| node_data.fill_color = c;
                    if (style.stroke_color) |c| node_data.stroke_color = c;
                    if (style.stroke_width) |w| node_data.stroke_width = w;
                    if (style.text_color) |c| node_data.text_color = c;
                }
            }

            try self.graph.setNode(id, node_data);
        } else if (applied_class_name) |cn| {
            // Node already exists but we have a ::: class to apply
            if (self.lookupClass(cn)) |style| {
                self.applyStyleToNode(id, style);
            }
        }

        // Set compound relationship when inside a subgraph, but only if
        // the node doesn't already belong to a (more specific) subgraph.
        // Without this guard, edge statements like `API --> DB` inside an
        // outer subgraph would reparent nodes out of their inner subgraphs.
        if (self.current_subgraph) |parent_id| {
            if (self.graph.getParent(id) == null) {
                try self.graph.setParent(id, parent_id);
            }
        }

        return id;
    }
};
