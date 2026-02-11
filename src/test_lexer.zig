const std = @import("std");
const lexer_mod = @import("parser/lexer.zig");
const Lexer = lexer_mod.Lexer;
const TokenType = lexer_mod.TokenType;

test "basic flowchart lexing" {
    const source = "graph TD\n    A --> B";
    var lexer = Lexer.init(source);

    try expectToken(&lexer, .keyword_graph, "graph");
    try expectToken(&lexer, .whitespace, " ");
    try expectToken(&lexer, .dir_td, "TD");
    try expectToken(&lexer, .newline, "\n");
    try expectToken(&lexer, .whitespace, "    ");
    try expectToken(&lexer, .identifier, "A");
    try expectToken(&lexer, .whitespace, " ");
    try expectToken(&lexer, .arrow_right, "-->");
    try expectToken(&lexer, .whitespace, " ");
    try expectToken(&lexer, .identifier, "B");
    try expectToken(&lexer, .eof, "");
}

test "complex flowchart syntax" {
    const source = "A[Start] -.-> B((End))";
    var lexer = Lexer.init(source);

    try expectToken(&lexer, .identifier, "A");
    try expectToken(&lexer, .l_bracket, "[");
    try expectToken(&lexer, .identifier, "Start");
    try expectToken(&lexer, .r_bracket, "]");
    try expectToken(&lexer, .whitespace, " ");
    try expectToken(&lexer, .dotted_arrow_right, "-.->");
    try expectToken(&lexer, .whitespace, " ");
    try expectToken(&lexer, .identifier, "B");
    try expectToken(&lexer, .l_double_paren, "((");
    try expectToken(&lexer, .identifier, "End");
    try expectToken(&lexer, .r_double_paren, "))");
    try expectToken(&lexer, .eof, "");
}

test "strings and comments" {
    const source =
        \\id1 "This is a string" %% comment
    ;
    var lexer = Lexer.init(source);

    try expectToken(&lexer, .identifier, "id1");
    try expectToken(&lexer, .whitespace, " ");
    try expectToken(&lexer, .string_literal, "This is a string");
    try expectToken(&lexer, .whitespace, " ");
    try expectToken(&lexer, .comment, "%% comment");
    try expectToken(&lexer, .eof, "");
}

test "left arrow lexing" {
    const source = "A <-- B";
    var lexer = Lexer.init(source);

    try expectToken(&lexer, .identifier, "A");
    try expectToken(&lexer, .whitespace, " ");
    try expectToken(&lexer, .arrow_left, "<--");
    try expectToken(&lexer, .whitespace, " ");
    try expectToken(&lexer, .identifier, "B");
    try expectToken(&lexer, .eof, "");
}

test "bidirectional arrow lexing" {
    const source = "A <--> B";
    var lexer = Lexer.init(source);

    try expectToken(&lexer, .identifier, "A");
    try expectToken(&lexer, .whitespace, " ");
    try expectToken(&lexer, .arrow_both, "<-->");
    try expectToken(&lexer, .whitespace, " ");
    try expectToken(&lexer, .identifier, "B");
    try expectToken(&lexer, .eof, "");
}

test "dotted bidirectional arrow lexing" {
    const source = "A <-.-> B";
    var lexer = Lexer.init(source);

    try expectToken(&lexer, .identifier, "A");
    try expectToken(&lexer, .whitespace, " ");
    try expectToken(&lexer, .dotted_arrow_both, "<-.->");
    try expectToken(&lexer, .whitespace, " ");
    try expectToken(&lexer, .identifier, "B");
    try expectToken(&lexer, .eof, "");
}

test "thick bidirectional arrow lexing" {
    const source = "A <==> B";
    var lexer = Lexer.init(source);

    try expectToken(&lexer, .identifier, "A");
    try expectToken(&lexer, .whitespace, " ");
    try expectToken(&lexer, .thick_arrow_both, "<==>");
    try expectToken(&lexer, .whitespace, " ");
    try expectToken(&lexer, .identifier, "B");
    try expectToken(&lexer, .eof, "");
}

test "bidirectional arrow not confused with left arrow" {
    // <--> must be matched before <-- to avoid consuming only <--
    const source = "<-->";
    var lexer = Lexer.init(source);

    try expectToken(&lexer, .arrow_both, "<-->");
    try expectToken(&lexer, .eof, "");
}

test "mixed arrow types in sequence" {
    const source = "A --> B <--> C <-- D -.-> E <-.-> F ==> G <==> H";
    var lexer = Lexer.init(source);

    try expectToken(&lexer, .identifier, "A");
    try expectToken(&lexer, .whitespace, " ");
    try expectToken(&lexer, .arrow_right, "-->");
    try expectToken(&lexer, .whitespace, " ");
    try expectToken(&lexer, .identifier, "B");
    try expectToken(&lexer, .whitespace, " ");
    try expectToken(&lexer, .arrow_both, "<-->");
    try expectToken(&lexer, .whitespace, " ");
    try expectToken(&lexer, .identifier, "C");
    try expectToken(&lexer, .whitespace, " ");
    try expectToken(&lexer, .arrow_left, "<--");
    try expectToken(&lexer, .whitespace, " ");
    try expectToken(&lexer, .identifier, "D");
    try expectToken(&lexer, .whitespace, " ");
    try expectToken(&lexer, .dotted_arrow_right, "-.->");
    try expectToken(&lexer, .whitespace, " ");
    try expectToken(&lexer, .identifier, "E");
    try expectToken(&lexer, .whitespace, " ");
    try expectToken(&lexer, .dotted_arrow_both, "<-.->");
    try expectToken(&lexer, .whitespace, " ");
    try expectToken(&lexer, .identifier, "F");
    try expectToken(&lexer, .whitespace, " ");
    try expectToken(&lexer, .thick_arrow_right, "==>");
    try expectToken(&lexer, .whitespace, " ");
    try expectToken(&lexer, .identifier, "G");
    try expectToken(&lexer, .whitespace, " ");
    try expectToken(&lexer, .thick_arrow_both, "<==>");
    try expectToken(&lexer, .whitespace, " ");
    try expectToken(&lexer, .identifier, "H");
    try expectToken(&lexer, .eof, "");
}

test "left arrow with label" {
    const source = "A <-- |label| B";
    var lexer = Lexer.init(source);

    try expectToken(&lexer, .identifier, "A");
    try expectToken(&lexer, .whitespace, " ");
    try expectToken(&lexer, .arrow_left, "<--");
    try expectToken(&lexer, .whitespace, " ");
    try expectToken(&lexer, .pipe, "|");
    try expectToken(&lexer, .identifier, "label");
    try expectToken(&lexer, .pipe, "|");
    try expectToken(&lexer, .whitespace, " ");
    try expectToken(&lexer, .identifier, "B");
    try expectToken(&lexer, .eof, "");
}

fn expectToken(lexer: *Lexer, expected_type: TokenType, expected_text: []const u8) !void {
    const token = lexer.next();
    try std.testing.expectEqual(expected_type, token.type);
    try std.testing.expectEqualStrings(expected_text, token.text);
}
