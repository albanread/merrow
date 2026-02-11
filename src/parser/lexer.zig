const std = @import("std");

pub const TokenType = enum {
    eof,
    newline,
    whitespace,
    comment,

    // Keywords
    keyword_graph,
    keyword_flowchart,
    keyword_subgraph,
    keyword_end,
    keyword_classDef, // classDef
    keyword_class, // class (apply style class to nodes)
    keyword_linkStyle, // linkStyle
    keyword_style, // style (inline node styling)
    keyword_click, // click (hyperlink/callback)

    // Directions
    dir_td,
    dir_lr,
    dir_bt,
    dir_rl,

    // Symbols
    arrow_right, // -->
    arrow_left, // <--
    arrow_both, // <-->
    line, // ---
    dotted_arrow_right, // -.->
    dotted_arrow_both, // <-.->
    thick_arrow_right, // ==>
    thick_arrow_both, // <==>
    pipe, // |
    triple_colon, // :::
    semicolon, // ;
    colon, // :
    comma, // ,
    hash, // #

    // Node delimiters
    l_bracket, // [
    r_bracket, // ]
    l_paren, // (
    r_paren, // )
    l_brace, // {
    r_brace, // }
    l_double_paren, // ((
    r_double_paren, // ))

    identifier,
    string_literal, // "..."
};

pub const Token = struct {
    type: TokenType,
    loc: Loc,
    text: []const u8,
};

pub const Loc = struct {
    start: usize,
    end: usize,
};

pub const Lexer = struct {
    source: []const u8,
    index: usize,

    pub fn init(source: []const u8) Lexer {
        return .{
            .source = source,
            .index = 0,
        };
    }

    pub fn next(self: *Lexer) Token {
        if (self.index >= self.source.len) {
            return .{ .type = .eof, .loc = .{ .start = self.index, .end = self.index }, .text = "" };
        }

        const start = self.index;
        const char = self.source[self.index];

        // Whitespace (excluding newline)
        if (char == ' ' or char == '\t' or char == '\r') {
            while (self.index < self.source.len) {
                const c = self.source[self.index];
                if (c != ' ' and c != '\t' and c != '\r') break;
                self.index += 1;
            }
            return .{ .type = .whitespace, .loc = .{ .start = start, .end = self.index }, .text = self.source[start..self.index] };
        }

        // Newline
        if (char == '\n') {
            self.index += 1;
            return .{ .type = .newline, .loc = .{ .start = start, .end = self.index }, .text = self.source[start..self.index] };
        }

        // Comments (%%)
        if (char == '%' and self.peek(1) == '%') {
            while (self.index < self.source.len and self.source[self.index] != '\n') {
                self.index += 1;
            }
            return .{ .type = .comment, .loc = .{ .start = start, .end = self.index }, .text = self.source[start..self.index] };
        }

        // Strings
        if (char == '"') {
            self.index += 1; // skip opening quote
            const content_start = self.index;
            while (self.index < self.source.len) {
                const c = self.source[self.index];
                if (c == '"') {
                    break;
                }
                if (c == '\\' and self.index + 1 < self.source.len) {
                    self.index += 2; // skip escaped char
                } else {
                    self.index += 1;
                }
            }
            const content_end = self.index;
            if (self.index < self.source.len) {
                self.index += 1; // skip closing quote
            }
            return .{ .type = .string_literal, .loc = .{ .start = start, .end = self.index }, .text = self.source[content_start..content_end] };
        }

        // Edges
        // <-->, <--, -->, ---, <-.->, -.->, <==>, ==>
        if (char == '<') {
            if (self.match("<-->")) {
                self.index += 4;
                return .{ .type = .arrow_both, .loc = .{ .start = start, .end = self.index }, .text = "<-->" };
            }
            if (self.match("<--")) {
                self.index += 3;
                return .{ .type = .arrow_left, .loc = .{ .start = start, .end = self.index }, .text = "<--" };
            }
            if (self.match("<-.->")) {
                self.index += 5;
                return .{ .type = .dotted_arrow_both, .loc = .{ .start = start, .end = self.index }, .text = "<-.->" };
            }
            if (self.match("<==>")) {
                self.index += 4;
                return .{ .type = .thick_arrow_both, .loc = .{ .start = start, .end = self.index }, .text = "<==>" };
            }
        }
        if (char == '-') {
            if (self.match("-->")) {
                self.index += 3;
                return .{ .type = .arrow_right, .loc = .{ .start = start, .end = self.index }, .text = "-->" };
            }
            if (self.match("-.->")) {
                self.index += 4;
                return .{ .type = .dotted_arrow_right, .loc = .{ .start = start, .end = self.index }, .text = "-.->" };
            }
            if (self.match("---")) {
                self.index += 3;
                return .{ .type = .line, .loc = .{ .start = start, .end = self.index }, .text = "---" };
            }
        }
        if (char == '=') {
            if (self.match("==>")) {
                self.index += 3;
                return .{ .type = .thick_arrow_right, .loc = .{ .start = start, .end = self.index }, .text = "==>" };
            }
        }

        // Triple colon (:::) — must be checked before single colon
        if (char == ':') {
            if (self.peek(1) == ':' and self.peek(2) == ':') {
                self.index += 3;
                return .{ .type = .triple_colon, .loc = .{ .start = start, .end = self.index }, .text = ":::" };
            }
            self.index += 1;
            return .{ .type = .colon, .loc = .{ .start = start, .end = self.index }, .text = ":" };
        }

        // Semicolon
        if (char == ';') {
            self.index += 1;
            return .{ .type = .semicolon, .loc = .{ .start = start, .end = self.index }, .text = ";" };
        }

        // Comma
        if (char == ',') {
            self.index += 1;
            return .{ .type = .comma, .loc = .{ .start = start, .end = self.index }, .text = "," };
        }

        // Hash
        if (char == '#') {
            self.index += 1;
            return .{ .type = .hash, .loc = .{ .start = start, .end = self.index }, .text = "#" };
        }

        // Brackets
        if (char == '[') {
            self.index += 1;
            return .{ .type = .l_bracket, .loc = .{ .start = start, .end = self.index }, .text = "[" };
        }
        if (char == ']') {
            self.index += 1;
            return .{ .type = .r_bracket, .loc = .{ .start = start, .end = self.index }, .text = "]" };
        }
        if (char == '(') {
            if (self.peek(1) == '(') {
                self.index += 2;
                return .{ .type = .l_double_paren, .loc = .{ .start = start, .end = self.index }, .text = "((" };
            }
            self.index += 1;
            return .{ .type = .l_paren, .loc = .{ .start = start, .end = self.index }, .text = "(" };
        }
        if (char == ')') {
            if (self.peek(1) == ')') {
                self.index += 2;
                return .{ .type = .r_double_paren, .loc = .{ .start = start, .end = self.index }, .text = "))" };
            }
            self.index += 1;
            return .{ .type = .r_paren, .loc = .{ .start = start, .end = self.index }, .text = ")" };
        }
        if (char == '{') {
            self.index += 1;
            return .{ .type = .l_brace, .loc = .{ .start = start, .end = self.index }, .text = "{" };
        }
        if (char == '}') {
            self.index += 1;
            return .{ .type = .r_brace, .loc = .{ .start = start, .end = self.index }, .text = "}" };
        }
        if (char == '|') {
            self.index += 1;
            return .{ .type = .pipe, .loc = .{ .start = start, .end = self.index }, .text = "|" };
        }

        // Identifiers / Keywords
        if (isAlphaNumeric(char) or char == '_') {
            while (self.index < self.source.len and (isAlphaNumeric(self.source[self.index]) or self.source[self.index] == '_')) {
                self.index += 1;
            }
            const text = self.source[start..self.index];
            const token_type = getKeyword(text) orelse .identifier;
            return .{ .type = token_type, .loc = .{ .start = start, .end = self.index }, .text = text };
        }

        // Punctuation / Unknown
        // Return single char as identifier to be safe
        self.index += 1;
        return .{ .type = .identifier, .loc = .{ .start = start, .end = self.index }, .text = self.source[start..self.index] };
    }

    fn peek(self: *Lexer, offset: usize) ?u8 {
        if (self.index + offset >= self.source.len) return null;
        return self.source[self.index + offset];
    }

    fn match(self: *Lexer, str: []const u8) bool {
        if (self.index + str.len > self.source.len) return false;
        return std.mem.eql(u8, self.source[self.index .. self.index + str.len], str);
    }
};

fn isAlphaNumeric(c: u8) bool {
    return (c >= 'a' and c <= 'z') or (c >= 'A' and c <= 'Z') or (c >= '0' and c <= '9');
}

fn getKeyword(text: []const u8) ?TokenType {
    if (std.mem.eql(u8, text, "graph")) return .keyword_graph;
    if (std.mem.eql(u8, text, "flowchart")) return .keyword_flowchart;
    if (std.mem.eql(u8, text, "subgraph")) return .keyword_subgraph;
    if (std.mem.eql(u8, text, "end")) return .keyword_end;
    if (std.mem.eql(u8, text, "classDef")) return .keyword_classDef;
    if (std.mem.eql(u8, text, "class")) return .keyword_class;
    if (std.mem.eql(u8, text, "linkStyle")) return .keyword_linkStyle;
    if (std.mem.eql(u8, text, "style")) return .keyword_style;
    if (std.mem.eql(u8, text, "click")) return .keyword_click;
    if (std.mem.eql(u8, text, "TD")) return .dir_td;
    if (std.mem.eql(u8, text, "TB")) return .dir_td;
    if (std.mem.eql(u8, text, "LR")) return .dir_lr;
    if (std.mem.eql(u8, text, "BT")) return .dir_bt;
    if (std.mem.eql(u8, text, "RL")) return .dir_rl;
    return null;
}
