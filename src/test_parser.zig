const std = @import("std");
const parser_mod = @import("parser/flowchart.zig");
const model_mod = @import("model.zig");

const Parser = parser_mod.Parser;
const NodeShape = model_mod.NodeShape;

test "basic parser graph TD" {
    const source = "graph TD\n    A --> B";
    var parser = try Parser.init(std.testing.allocator, source);
    defer parser.deinit();

    var graph = try parser.parse();
    defer graph.deinitDeep();

    try std.testing.expectEqualStrings("TD", graph.getGraphLabel().rankdir);
    try std.testing.expect(graph.hasNode("A"));
    try std.testing.expect(graph.hasNode("B"));

    const edge = graph.edge("A", "B", null);
    try std.testing.expect(edge != null);
}

test "node shapes and labels" {
    const source = "graph LR\n    id1[Box Node] --> id2((Circle Node))";
    var parser = try Parser.init(std.testing.allocator, source);
    defer parser.deinit();

    var graph = try parser.parse();
    defer graph.deinitDeep();

    const n1 = graph.getNode("id1").?;
    try std.testing.expectEqualStrings("Box Node", n1.label.?);
    try std.testing.expectEqual(NodeShape.box, n1.shape);

    const n2 = graph.getNode("id2").?;
    try std.testing.expectEqualStrings("Circle Node", n2.label.?);
    try std.testing.expectEqual(NodeShape.circle, n2.shape);
}

test "chained edges" {
    const source = "A --> B --> C";
    var parser = try Parser.init(std.testing.allocator, source);
    defer parser.deinit();

    var graph = try parser.parse();
    defer graph.deinitDeep();

    try std.testing.expect(graph.hasNode("A"));
    try std.testing.expect(graph.hasNode("B"));
    try std.testing.expect(graph.hasNode("C"));

    try std.testing.expect(graph.edge("A", "B", null) != null);
    try std.testing.expect(graph.edge("B", "C", null) != null);
}

test "subgraph parsing" {
    const source =
        \\graph TB
        \\  subgraph Container
        \\    A
        \\    B
        \\  end
        \\  A --> B
        \\  C
    ;
    var parser = try Parser.init(std.testing.allocator, source);
    defer parser.deinit();

    var graph = try parser.parse();
    defer graph.deinitDeep();

    try std.testing.expect(graph.hasNode("A"));
    try std.testing.expect(graph.hasNode("B"));
    try std.testing.expect(graph.hasNode("C"));
    try std.testing.expect(graph.hasNode("Container"));

    try std.testing.expectEqualStrings("Container", graph.getParent("A").?);
    try std.testing.expectEqualStrings("Container", graph.getParent("B").?);

    // C should not have a parent
    try std.testing.expect(graph.getParent("C") == null);
}

// ---------------------------------------------------------------------------
// Style class tests
// ---------------------------------------------------------------------------

test "parseHexColor - 3-digit hex" {
    const c = parser_mod.parseHexColor("#f9f").?;
    try std.testing.expectEqual(@as(u8, 0xff), c[0]);
    try std.testing.expectEqual(@as(u8, 0x99), c[1]);
    try std.testing.expectEqual(@as(u8, 0xff), c[2]);
    try std.testing.expectEqual(@as(u8, 255), c[3]);
}

test "parseHexColor - 6-digit hex" {
    const c = parser_mod.parseHexColor("#4CAF50").?;
    try std.testing.expectEqual(@as(u8, 0x4C), c[0]);
    try std.testing.expectEqual(@as(u8, 0xAF), c[1]);
    try std.testing.expectEqual(@as(u8, 0x50), c[2]);
    try std.testing.expectEqual(@as(u8, 255), c[3]);
}

test "parseHexColor - 8-digit hex with alpha" {
    const c = parser_mod.parseHexColor("#FF000080").?;
    try std.testing.expectEqual(@as(u8, 0xFF), c[0]);
    try std.testing.expectEqual(@as(u8, 0x00), c[1]);
    try std.testing.expectEqual(@as(u8, 0x00), c[2]);
    try std.testing.expectEqual(@as(u8, 0x80), c[3]);
}

test "parseHexColor - without hash prefix" {
    const c = parser_mod.parseHexColor("abc").?;
    try std.testing.expectEqual(@as(u8, 0xaa), c[0]);
    try std.testing.expectEqual(@as(u8, 0xbb), c[1]);
    try std.testing.expectEqual(@as(u8, 0xcc), c[2]);
}

test "parseHexColor - named color" {
    const c = parser_mod.parseHexColor("red").?;
    try std.testing.expectEqual(@as(u8, 255), c[0]);
    try std.testing.expectEqual(@as(u8, 0), c[1]);
    try std.testing.expectEqual(@as(u8, 0), c[2]);
    try std.testing.expectEqual(@as(u8, 255), c[3]);
}

test "parseHexColor - named color case insensitive" {
    const c = parser_mod.parseHexColor("Red").?;
    try std.testing.expectEqual(@as(u8, 255), c[0]);
    try std.testing.expectEqual(@as(u8, 0), c[1]);
    try std.testing.expectEqual(@as(u8, 0), c[2]);
}

test "parseHexColor - invalid returns null" {
    try std.testing.expect(parser_mod.parseHexColor("zzz") == null);
    try std.testing.expect(parser_mod.parseHexColor("#gg") == null);
    try std.testing.expect(parser_mod.parseHexColor("") == null);
}

test "classDef and triple-colon application" {
    const source =
        \\graph TD
        \\    classDef myStyle fill:#ff0000,stroke:#00ff00,stroke-width:3px,color:#0000ff
        \\    A[Hello]:::myStyle --> B[World]
    ;
    var parser = try Parser.init(std.testing.allocator, source);
    defer parser.deinit();

    var graph = try parser.parse();
    defer graph.deinitDeep();

    try std.testing.expect(graph.hasNode("A"));
    try std.testing.expect(graph.hasNode("B"));

    const a = graph.getNode("A").?;
    // A should have the style class applied
    try std.testing.expect(a.fill_color != null);
    try std.testing.expectEqual(@as(u8, 0xff), a.fill_color.?[0]);
    try std.testing.expectEqual(@as(u8, 0x00), a.fill_color.?[1]);
    try std.testing.expectEqual(@as(u8, 0x00), a.fill_color.?[2]);

    try std.testing.expect(a.stroke_color != null);
    try std.testing.expectEqual(@as(u8, 0x00), a.stroke_color.?[0]);
    try std.testing.expectEqual(@as(u8, 0xff), a.stroke_color.?[1]);
    try std.testing.expectEqual(@as(u8, 0x00), a.stroke_color.?[2]);

    try std.testing.expect(a.stroke_width != null);
    try std.testing.expectEqual(@as(i32, 3), a.stroke_width.?);

    try std.testing.expect(a.text_color != null);
    try std.testing.expectEqual(@as(u8, 0x00), a.text_color.?[0]);
    try std.testing.expectEqual(@as(u8, 0x00), a.text_color.?[1]);
    try std.testing.expectEqual(@as(u8, 0xff), a.text_color.?[2]);

    // B should NOT have any custom style
    const b = graph.getNode("B").?;
    try std.testing.expect(b.fill_color == null);
    try std.testing.expect(b.stroke_color == null);
    try std.testing.expect(b.text_color == null);
}

test "classDef with named colors" {
    const source =
        \\graph TD
        \\    classDef warn fill:orange,stroke:darkred,color:white
        \\    X[Alert]:::warn
    ;
    var parser = try Parser.init(std.testing.allocator, source);
    defer parser.deinit();

    var graph = try parser.parse();
    defer graph.deinitDeep();

    const x = graph.getNode("X").?;
    try std.testing.expect(x.fill_color != null);
    // orange = (255, 165, 0, 255)
    try std.testing.expectEqual(@as(u8, 255), x.fill_color.?[0]);
    try std.testing.expectEqual(@as(u8, 165), x.fill_color.?[1]);
    try std.testing.expectEqual(@as(u8, 0), x.fill_color.?[2]);

    // darkred = (139, 0, 0, 255)
    try std.testing.expect(x.stroke_color != null);
    try std.testing.expectEqual(@as(u8, 139), x.stroke_color.?[0]);

    // white = (255, 255, 255, 255)
    try std.testing.expect(x.text_color != null);
    try std.testing.expectEqual(@as(u8, 255), x.text_color.?[0]);
    try std.testing.expectEqual(@as(u8, 255), x.text_color.?[1]);
    try std.testing.expectEqual(@as(u8, 255), x.text_color.?[2]);
}

test "class statement applies style to existing nodes" {
    const source =
        \\graph TD
        \\    classDef highlight fill:#ffcc00,stroke:#996600
        \\    A[First] --> B[Second]
        \\    B --> C[Third]
        \\    class A,C highlight
    ;
    var parser = try Parser.init(std.testing.allocator, source);
    defer parser.deinit();

    var graph = try parser.parse();
    defer graph.deinitDeep();

    // A and C should have the highlight class applied
    const a = graph.getNode("A").?;
    try std.testing.expect(a.fill_color != null);
    try std.testing.expectEqual(@as(u8, 0xff), a.fill_color.?[0]);
    try std.testing.expectEqual(@as(u8, 0xcc), a.fill_color.?[1]);
    try std.testing.expectEqual(@as(u8, 0x00), a.fill_color.?[2]);

    const c = graph.getNode("C").?;
    try std.testing.expect(c.fill_color != null);
    try std.testing.expectEqual(@as(u8, 0xff), c.fill_color.?[0]);
    try std.testing.expectEqual(@as(u8, 0xcc), c.fill_color.?[1]);

    try std.testing.expect(c.stroke_color != null);
    try std.testing.expectEqual(@as(u8, 0x99), c.stroke_color.?[0]);
    try std.testing.expectEqual(@as(u8, 0x66), c.stroke_color.?[1]);
    try std.testing.expectEqual(@as(u8, 0x00), c.stroke_color.?[2]);

    // B should NOT have any custom style
    const b = graph.getNode("B").?;
    try std.testing.expect(b.fill_color == null);
    try std.testing.expect(b.stroke_color == null);
}

test "class statement with single node" {
    const source =
        \\graph TD
        \\    classDef ok fill:#00ff00
        \\    N[Node]
        \\    class N ok
    ;
    var parser = try Parser.init(std.testing.allocator, source);
    defer parser.deinit();

    var graph = try parser.parse();
    defer graph.deinitDeep();

    const n = graph.getNode("N").?;
    try std.testing.expect(n.fill_color != null);
    try std.testing.expectEqual(@as(u8, 0x00), n.fill_color.?[0]);
    try std.testing.expectEqual(@as(u8, 0xff), n.fill_color.?[1]);
    try std.testing.expectEqual(@as(u8, 0x00), n.fill_color.?[2]);
}

test "classDef with semicolon terminator" {
    const source =
        \\graph TD
        \\    classDef err fill:#f00,stroke:#800;
        \\    E[Error]:::err
    ;
    var parser = try Parser.init(std.testing.allocator, source);
    defer parser.deinit();

    var graph = try parser.parse();
    defer graph.deinitDeep();

    const e = graph.getNode("E").?;
    try std.testing.expect(e.fill_color != null);
    try std.testing.expectEqual(@as(u8, 0xff), e.fill_color.?[0]);
    try std.testing.expectEqual(@as(u8, 0x00), e.fill_color.?[1]);

    try std.testing.expect(e.stroke_color != null);
    try std.testing.expectEqual(@as(u8, 0x88), e.stroke_color.?[0]);
    try std.testing.expectEqual(@as(u8, 0x00), e.stroke_color.?[1]);
}

test "triple-colon on node without shape" {
    const source =
        \\graph TD
        \\    classDef blue fill:#0000ff,color:#ffffff
        \\    A:::blue --> B
    ;
    var parser = try Parser.init(std.testing.allocator, source);
    defer parser.deinit();

    var graph = try parser.parse();
    defer graph.deinitDeep();

    const a = graph.getNode("A").?;
    try std.testing.expect(a.fill_color != null);
    try std.testing.expectEqual(@as(u8, 0x00), a.fill_color.?[0]);
    try std.testing.expectEqual(@as(u8, 0x00), a.fill_color.?[1]);
    try std.testing.expectEqual(@as(u8, 0xff), a.fill_color.?[2]);

    try std.testing.expect(a.text_color != null);
    try std.testing.expectEqual(@as(u8, 0xff), a.text_color.?[0]);
}

test "multiple classDef definitions" {
    const source =
        \\graph TD
        \\    classDef styleA fill:#ff0000
        \\    classDef styleB fill:#00ff00
        \\    A:::styleA --> B:::styleB
    ;
    var parser = try Parser.init(std.testing.allocator, source);
    defer parser.deinit();

    var graph = try parser.parse();
    defer graph.deinitDeep();

    const a = graph.getNode("A").?;
    try std.testing.expect(a.fill_color != null);
    try std.testing.expectEqual(@as(u8, 0xff), a.fill_color.?[0]);
    try std.testing.expectEqual(@as(u8, 0x00), a.fill_color.?[1]);

    const b = graph.getNode("B").?;
    try std.testing.expect(b.fill_color != null);
    try std.testing.expectEqual(@as(u8, 0x00), b.fill_color.?[0]);
    try std.testing.expectEqual(@as(u8, 0xff), b.fill_color.?[1]);
}

test "undefined class has no effect" {
    const source =
        \\graph TD
        \\    A[Hello]:::nonexistent --> B
    ;
    var parser = try Parser.init(std.testing.allocator, source);
    defer parser.deinit();

    var graph = try parser.parse();
    defer graph.deinitDeep();

    const a = graph.getNode("A").?;
    // No crash, no style applied
    try std.testing.expect(a.fill_color == null);
    try std.testing.expect(a.stroke_color == null);
    try std.testing.expect(a.text_color == null);
}

test "edges preserved with classDef and class statements" {
    const source =
        \\graph TD
        \\    classDef s1 fill:#aaa
        \\    A:::s1 --> B --> C
        \\    class B s1
    ;
    var parser = try Parser.init(std.testing.allocator, source);
    defer parser.deinit();

    var graph = try parser.parse();
    defer graph.deinitDeep();

    try std.testing.expect(graph.edge("A", "B", null) != null);
    try std.testing.expect(graph.edge("B", "C", null) != null);
    const all_nodes = try graph.allNodes(std.testing.allocator);
    defer {
        for (all_nodes) |id| std.testing.allocator.free(id);
        std.testing.allocator.free(all_nodes);
    }
    try std.testing.expectEqual(@as(usize, 3), all_nodes.len);
}

// ---------------------------------------------------------------------------
// linkStyle tests
// ---------------------------------------------------------------------------

test "linkStyle single index with stroke color" {
    const source =
        \\graph TD
        \\    A --> B
        \\    B --> C
        \\    linkStyle 0 stroke:#ff0000
    ;
    var parser = try Parser.init(std.testing.allocator, source);
    defer parser.deinit();

    var graph = try parser.parse();
    defer graph.deinitDeep();

    // Edge 0 (A-->B) should have the red stroke color
    const ab = graph.edge("A", "B", null).?;
    try std.testing.expect(ab.color != null);
    try std.testing.expectEqual(@as(u8, 0xff), ab.color.?[0]);
    try std.testing.expectEqual(@as(u8, 0x00), ab.color.?[1]);
    try std.testing.expectEqual(@as(u8, 0x00), ab.color.?[2]);

    // Edge 1 (B-->C) should NOT have a custom color
    const bc = graph.edge("B", "C", null).?;
    try std.testing.expect(bc.color == null);
}

test "linkStyle multiple indices" {
    const source =
        \\graph TD
        \\    A --> B
        \\    B --> C
        \\    C --> D
        \\    linkStyle 0,2 stroke:#00ff00,stroke-width:4px
    ;
    var parser = try Parser.init(std.testing.allocator, source);
    defer parser.deinit();

    var graph = try parser.parse();
    defer graph.deinitDeep();

    // Edge 0 (A-->B)
    const ab = graph.edge("A", "B", null).?;
    try std.testing.expect(ab.color != null);
    try std.testing.expectEqual(@as(u8, 0x00), ab.color.?[0]);
    try std.testing.expectEqual(@as(u8, 0xff), ab.color.?[1]);
    try std.testing.expectEqual(@as(u8, 0x00), ab.color.?[2]);
    try std.testing.expect(ab.thickness != null);
    try std.testing.expectEqual(@as(i32, 4), ab.thickness.?);

    // Edge 1 (B-->C) — not targeted
    const bc = graph.edge("B", "C", null).?;
    try std.testing.expect(bc.color == null);
    try std.testing.expect(bc.thickness == null);

    // Edge 2 (C-->D)
    const cd = graph.edge("C", "D", null).?;
    try std.testing.expect(cd.color != null);
    try std.testing.expectEqual(@as(u8, 0x00), cd.color.?[0]);
    try std.testing.expectEqual(@as(u8, 0xff), cd.color.?[1]);
    try std.testing.expect(cd.thickness != null);
    try std.testing.expectEqual(@as(i32, 4), cd.thickness.?);
}

test "linkStyle default applies to all edges" {
    const source =
        \\graph TD
        \\    A --> B
        \\    B --> C
        \\    linkStyle default stroke:#333333,stroke-width:3px
    ;
    var parser = try Parser.init(std.testing.allocator, source);
    defer parser.deinit();

    var graph = try parser.parse();
    defer graph.deinitDeep();

    // Both edges should have the default style
    const ab = graph.edge("A", "B", null).?;
    try std.testing.expect(ab.color != null);
    try std.testing.expectEqual(@as(u8, 0x33), ab.color.?[0]);
    try std.testing.expectEqual(@as(u8, 0x33), ab.color.?[1]);
    try std.testing.expectEqual(@as(u8, 0x33), ab.color.?[2]);
    try std.testing.expect(ab.thickness != null);
    try std.testing.expectEqual(@as(i32, 3), ab.thickness.?);

    const bc = graph.edge("B", "C", null).?;
    try std.testing.expect(bc.color != null);
    try std.testing.expectEqual(@as(u8, 0x33), bc.color.?[0]);
    try std.testing.expect(bc.thickness != null);
    try std.testing.expectEqual(@as(i32, 3), bc.thickness.?);
}

test "linkStyle default applies to edges declared after it" {
    const source =
        \\graph TD
        \\    A --> B
        \\    linkStyle default stroke:#aabbcc
        \\    B --> C
    ;
    var parser = try Parser.init(std.testing.allocator, source);
    defer parser.deinit();

    var graph = try parser.parse();
    defer graph.deinitDeep();

    // Edge before default declaration should also get it
    const ab = graph.edge("A", "B", null).?;
    try std.testing.expect(ab.color != null);
    try std.testing.expectEqual(@as(u8, 0xaa), ab.color.?[0]);
    try std.testing.expectEqual(@as(u8, 0xbb), ab.color.?[1]);
    try std.testing.expectEqual(@as(u8, 0xcc), ab.color.?[2]);

    // Edge after default declaration should also get it
    const bc = graph.edge("B", "C", null).?;
    try std.testing.expect(bc.color != null);
    try std.testing.expectEqual(@as(u8, 0xaa), bc.color.?[0]);
    try std.testing.expectEqual(@as(u8, 0xbb), bc.color.?[1]);
    try std.testing.expectEqual(@as(u8, 0xcc), bc.color.?[2]);
}

test "linkStyle with named color" {
    const source =
        \\graph TD
        \\    A --> B
        \\    linkStyle 0 stroke:red
    ;
    var parser = try Parser.init(std.testing.allocator, source);
    defer parser.deinit();

    var graph = try parser.parse();
    defer graph.deinitDeep();

    const ab = graph.edge("A", "B", null).?;
    try std.testing.expect(ab.color != null);
    try std.testing.expectEqual(@as(u8, 255), ab.color.?[0]);
    try std.testing.expectEqual(@as(u8, 0), ab.color.?[1]);
    try std.testing.expectEqual(@as(u8, 0), ab.color.?[2]);
}

test "linkStyle stroke-dasharray sets dashed line style" {
    const source =
        \\graph TD
        \\    A --> B
        \\    linkStyle 0 stroke-dasharray:5
    ;
    var parser = try Parser.init(std.testing.allocator, source);
    defer parser.deinit();

    var graph = try parser.parse();
    defer graph.deinitDeep();

    const ab = graph.edge("A", "B", null).?;
    try std.testing.expectEqual(model_mod.LineStyle.dashed, ab.line_style);
}

test "linkStyle with semicolon terminator" {
    const source =
        \\graph TD
        \\    A --> B
        \\    linkStyle 0 stroke:#ff0000,stroke-width:5px;
    ;
    var parser = try Parser.init(std.testing.allocator, source);
    defer parser.deinit();

    var graph = try parser.parse();
    defer graph.deinitDeep();

    const ab = graph.edge("A", "B", null).?;
    try std.testing.expect(ab.color != null);
    try std.testing.expectEqual(@as(u8, 0xff), ab.color.?[0]);
    try std.testing.expect(ab.thickness != null);
    try std.testing.expectEqual(@as(i32, 5), ab.thickness.?);
}

test "linkStyle out-of-range index is ignored" {
    const source =
        \\graph TD
        \\    A --> B
        \\    linkStyle 99 stroke:#ff0000
    ;
    var parser = try Parser.init(std.testing.allocator, source);
    defer parser.deinit();

    var graph = try parser.parse();
    defer graph.deinitDeep();

    // Edge should be unaffected
    const ab = graph.edge("A", "B", null).?;
    try std.testing.expect(ab.color == null);
}

test "linkStyle preserves edges and nodes" {
    const source =
        \\graph TD
        \\    A --> B --> C
        \\    linkStyle 0 stroke:#ff0000
        \\    linkStyle 1 stroke:#00ff00
    ;
    var parser = try Parser.init(std.testing.allocator, source);
    defer parser.deinit();

    var graph = try parser.parse();
    defer graph.deinitDeep();

    try std.testing.expect(graph.hasNode("A"));
    try std.testing.expect(graph.hasNode("B"));
    try std.testing.expect(graph.hasNode("C"));
    try std.testing.expect(graph.edge("A", "B", null) != null);
    try std.testing.expect(graph.edge("B", "C", null) != null);

    const ab = graph.edge("A", "B", null).?;
    try std.testing.expectEqual(@as(u8, 0xff), ab.color.?[0]);
    try std.testing.expectEqual(@as(u8, 0x00), ab.color.?[1]);

    const bc = graph.edge("B", "C", null).?;
    try std.testing.expectEqual(@as(u8, 0x00), bc.color.?[0]);
    try std.testing.expectEqual(@as(u8, 0xff), bc.color.?[1]);
}

// ---------------------------------------------------------------------------
// style directive tests
// ---------------------------------------------------------------------------

test "style directive single node with fill and stroke" {
    const source =
        \\graph TD
        \\    A[Hello] --> B[World]
        \\    style A fill:#ff0000,stroke:#00ff00,stroke-width:3px,color:#0000ff
    ;
    var parser = try Parser.init(std.testing.allocator, source);
    defer parser.deinit();

    var graph = try parser.parse();
    defer graph.deinitDeep();

    const a = graph.getNode("A").?;
    try std.testing.expect(a.fill_color != null);
    try std.testing.expectEqual(@as(u8, 0xff), a.fill_color.?[0]);
    try std.testing.expectEqual(@as(u8, 0x00), a.fill_color.?[1]);
    try std.testing.expectEqual(@as(u8, 0x00), a.fill_color.?[2]);

    try std.testing.expect(a.stroke_color != null);
    try std.testing.expectEqual(@as(u8, 0x00), a.stroke_color.?[0]);
    try std.testing.expectEqual(@as(u8, 0xff), a.stroke_color.?[1]);
    try std.testing.expectEqual(@as(u8, 0x00), a.stroke_color.?[2]);

    try std.testing.expect(a.stroke_width != null);
    try std.testing.expectEqual(@as(i32, 3), a.stroke_width.?);

    try std.testing.expect(a.text_color != null);
    try std.testing.expectEqual(@as(u8, 0x00), a.text_color.?[0]);
    try std.testing.expectEqual(@as(u8, 0x00), a.text_color.?[1]);
    try std.testing.expectEqual(@as(u8, 0xff), a.text_color.?[2]);

    // B should NOT have any custom style
    const b = graph.getNode("B").?;
    try std.testing.expect(b.fill_color == null);
    try std.testing.expect(b.stroke_color == null);
}

test "style directive multiple nodes" {
    const source =
        \\graph TD
        \\    A --> B --> C
        \\    style A,C fill:#ffcc00,stroke:#996600
    ;
    var parser = try Parser.init(std.testing.allocator, source);
    defer parser.deinit();

    var graph = try parser.parse();
    defer graph.deinitDeep();

    const a = graph.getNode("A").?;
    try std.testing.expect(a.fill_color != null);
    try std.testing.expectEqual(@as(u8, 0xff), a.fill_color.?[0]);
    try std.testing.expectEqual(@as(u8, 0xcc), a.fill_color.?[1]);
    try std.testing.expectEqual(@as(u8, 0x00), a.fill_color.?[2]);

    try std.testing.expect(a.stroke_color != null);
    try std.testing.expectEqual(@as(u8, 0x99), a.stroke_color.?[0]);
    try std.testing.expectEqual(@as(u8, 0x66), a.stroke_color.?[1]);
    try std.testing.expectEqual(@as(u8, 0x00), a.stroke_color.?[2]);

    const c = graph.getNode("C").?;
    try std.testing.expect(c.fill_color != null);
    try std.testing.expectEqual(@as(u8, 0xff), c.fill_color.?[0]);
    try std.testing.expectEqual(@as(u8, 0xcc), c.fill_color.?[1]);

    try std.testing.expect(c.stroke_color != null);
    try std.testing.expectEqual(@as(u8, 0x99), c.stroke_color.?[0]);

    // B should NOT have any custom style
    const b = graph.getNode("B").?;
    try std.testing.expect(b.fill_color == null);
    try std.testing.expect(b.stroke_color == null);
}

test "style directive with named colors" {
    const source =
        \\graph TD
        \\    A[Alert] --> B
        \\    style A fill:orange,stroke:darkred,color:white
    ;
    var parser = try Parser.init(std.testing.allocator, source);
    defer parser.deinit();

    var graph = try parser.parse();
    defer graph.deinitDeep();

    const a = graph.getNode("A").?;
    // orange = (255, 165, 0, 255)
    try std.testing.expect(a.fill_color != null);
    try std.testing.expectEqual(@as(u8, 255), a.fill_color.?[0]);
    try std.testing.expectEqual(@as(u8, 165), a.fill_color.?[1]);
    try std.testing.expectEqual(@as(u8, 0), a.fill_color.?[2]);

    // darkred = (139, 0, 0, 255)
    try std.testing.expect(a.stroke_color != null);
    try std.testing.expectEqual(@as(u8, 139), a.stroke_color.?[0]);

    // white = (255, 255, 255, 255)
    try std.testing.expect(a.text_color != null);
    try std.testing.expectEqual(@as(u8, 255), a.text_color.?[0]);
    try std.testing.expectEqual(@as(u8, 255), a.text_color.?[1]);
    try std.testing.expectEqual(@as(u8, 255), a.text_color.?[2]);
}

test "style directive with semicolon terminator" {
    const source =
        \\graph TD
        \\    A --> B
        \\    style A fill:#f00,stroke:#800;
    ;
    var parser = try Parser.init(std.testing.allocator, source);
    defer parser.deinit();

    var graph = try parser.parse();
    defer graph.deinitDeep();

    const a = graph.getNode("A").?;
    try std.testing.expect(a.fill_color != null);
    try std.testing.expectEqual(@as(u8, 0xff), a.fill_color.?[0]);
    try std.testing.expectEqual(@as(u8, 0x00), a.fill_color.?[1]);

    try std.testing.expect(a.stroke_color != null);
    try std.testing.expectEqual(@as(u8, 0x88), a.stroke_color.?[0]);
    try std.testing.expectEqual(@as(u8, 0x00), a.stroke_color.?[1]);
}

test "style directive preserves edges" {
    const source =
        \\graph TD
        \\    A --> B --> C
        \\    style A fill:#ff0000
        \\    style C fill:#00ff00
    ;
    var parser = try Parser.init(std.testing.allocator, source);
    defer parser.deinit();

    var graph = try parser.parse();
    defer graph.deinitDeep();

    try std.testing.expect(graph.edge("A", "B", null) != null);
    try std.testing.expect(graph.edge("B", "C", null) != null);

    const a = graph.getNode("A").?;
    try std.testing.expectEqual(@as(u8, 0xff), a.fill_color.?[0]);
    try std.testing.expectEqual(@as(u8, 0x00), a.fill_color.?[1]);

    const c = graph.getNode("C").?;
    try std.testing.expectEqual(@as(u8, 0x00), c.fill_color.?[0]);
    try std.testing.expectEqual(@as(u8, 0xff), c.fill_color.?[1]);
}

test "style directive combined with classDef" {
    // style directive should override classDef properties
    const source =
        \\graph TD
        \\    classDef blue fill:#0000ff
        \\    A:::blue --> B
        \\    style A fill:#ff0000
    ;
    var parser = try Parser.init(std.testing.allocator, source);
    defer parser.deinit();

    var graph = try parser.parse();
    defer graph.deinitDeep();

    // A was initially blue via classDef, but style directive overrides fill
    const a = graph.getNode("A").?;
    try std.testing.expect(a.fill_color != null);
    try std.testing.expectEqual(@as(u8, 0xff), a.fill_color.?[0]);
    try std.testing.expectEqual(@as(u8, 0x00), a.fill_color.?[1]);
    try std.testing.expectEqual(@as(u8, 0x00), a.fill_color.?[2]);
}

test "style directive combined with linkStyle" {
    const source =
        \\graph TD
        \\    A --> B --> C
        \\    style A fill:#ff0000
        \\    linkStyle 0 stroke:#0000ff,stroke-width:3px
    ;
    var parser = try Parser.init(std.testing.allocator, source);
    defer parser.deinit();

    var graph = try parser.parse();
    defer graph.deinitDeep();

    // Node style from style directive
    const a = graph.getNode("A").?;
    try std.testing.expect(a.fill_color != null);
    try std.testing.expectEqual(@as(u8, 0xff), a.fill_color.?[0]);

    // Edge style from linkStyle
    const ab = graph.edge("A", "B", null).?;
    try std.testing.expect(ab.color != null);
    try std.testing.expectEqual(@as(u8, 0x00), ab.color.?[0]);
    try std.testing.expectEqual(@as(u8, 0x00), ab.color.?[1]);
    try std.testing.expectEqual(@as(u8, 0xff), ab.color.?[2]);
    try std.testing.expect(ab.thickness != null);
    try std.testing.expectEqual(@as(i32, 3), ab.thickness.?);
}

test "style directive on unknown node is a no-op" {
    const source =
        \\graph TD
        \\    A --> B
        \\    style Z fill:#ff0000
    ;
    var parser = try Parser.init(std.testing.allocator, source);
    defer parser.deinit();

    var graph = try parser.parse();
    defer graph.deinitDeep();

    // No crash; A and B unaffected
    const a = graph.getNode("A").?;
    try std.testing.expect(a.fill_color == null);
    const b = graph.getNode("B").?;
    try std.testing.expect(b.fill_color == null);
}

// ---------------------------------------------------------------------------
// click directive tests
// ---------------------------------------------------------------------------

test "click directive basic URL" {
    const source =
        \\graph TD
        \\    A[Homepage] --> B[About]
        \\    click A "https://example.com"
    ;
    var parser = try Parser.init(std.testing.allocator, source);
    defer parser.deinit();

    var graph = try parser.parse();
    defer graph.deinitDeep();

    const a = graph.getNode("A").?;
    try std.testing.expect(a.link_url != null);
    try std.testing.expectEqualStrings("https://example.com", a.link_url.?);
    // Default target should be _blank
    try std.testing.expect(a.link_target != null);
    try std.testing.expectEqualStrings("_blank", a.link_target.?);
    // No tooltip
    try std.testing.expect(a.link_tooltip == null);

    // B should NOT have a link
    const b = graph.getNode("B").?;
    try std.testing.expect(b.link_url == null);
}

test "click directive with tooltip" {
    const source =
        \\graph TD
        \\    A[Click Me] --> B
        \\    click A "https://example.com" "Visit Example"
    ;
    var parser = try Parser.init(std.testing.allocator, source);
    defer parser.deinit();

    var graph = try parser.parse();
    defer graph.deinitDeep();

    const a = graph.getNode("A").?;
    try std.testing.expect(a.link_url != null);
    try std.testing.expectEqualStrings("https://example.com", a.link_url.?);
    try std.testing.expect(a.link_tooltip != null);
    try std.testing.expectEqualStrings("Visit Example", a.link_tooltip.?);
}

test "click directive with href keyword" {
    const source =
        \\graph TD
        \\    A[Link] --> B
        \\    click A href "https://example.com/page"
    ;
    var parser = try Parser.init(std.testing.allocator, source);
    defer parser.deinit();

    var graph = try parser.parse();
    defer graph.deinitDeep();

    const a = graph.getNode("A").?;
    try std.testing.expect(a.link_url != null);
    try std.testing.expectEqualStrings("https://example.com/page", a.link_url.?);
}

test "click directive with href and tooltip" {
    const source =
        \\graph TD
        \\    A --> B
        \\    click A href "https://example.com" "Go to Example"
    ;
    var parser = try Parser.init(std.testing.allocator, source);
    defer parser.deinit();

    var graph = try parser.parse();
    defer graph.deinitDeep();

    const a = graph.getNode("A").?;
    try std.testing.expect(a.link_url != null);
    try std.testing.expectEqualStrings("https://example.com", a.link_url.?);
    try std.testing.expect(a.link_tooltip != null);
    try std.testing.expectEqualStrings("Go to Example", a.link_tooltip.?);
}

test "click directive with explicit target" {
    const source =
        \\graph TD
        \\    A --> B
        \\    click A "https://example.com" "Tip" _self
    ;
    var parser = try Parser.init(std.testing.allocator, source);
    defer parser.deinit();

    var graph = try parser.parse();
    defer graph.deinitDeep();

    const a = graph.getNode("A").?;
    try std.testing.expect(a.link_url != null);
    try std.testing.expectEqualStrings("https://example.com", a.link_url.?);
    try std.testing.expect(a.link_tooltip != null);
    try std.testing.expectEqualStrings("Tip", a.link_tooltip.?);
    try std.testing.expect(a.link_target != null);
    try std.testing.expectEqualStrings("_self", a.link_target.?);
}

test "click directive on unknown node is a no-op" {
    const source =
        \\graph TD
        \\    A --> B
        \\    click Z "https://example.com"
    ;
    var parser = try Parser.init(std.testing.allocator, source);
    defer parser.deinit();

    var graph = try parser.parse();
    defer graph.deinitDeep();

    // No crash; A and B unaffected
    const a = graph.getNode("A").?;
    try std.testing.expect(a.link_url == null);
    const b = graph.getNode("B").?;
    try std.testing.expect(b.link_url == null);
}

test "click directive preserves edges and styles" {
    const source =
        \\graph TD
        \\    classDef blue fill:#0000ff
        \\    A:::blue --> B --> C
        \\    click A "https://example.com/a" "Node A"
        \\    click C "https://example.com/c"
        \\    linkStyle 0 stroke:#ff0000
    ;
    var parser = try Parser.init(std.testing.allocator, source);
    defer parser.deinit();

    var graph = try parser.parse();
    defer graph.deinitDeep();

    // Edges preserved
    try std.testing.expect(graph.edge("A", "B", null) != null);
    try std.testing.expect(graph.edge("B", "C", null) != null);

    // Node style from classDef
    const a = graph.getNode("A").?;
    try std.testing.expect(a.fill_color != null);
    try std.testing.expectEqual(@as(u8, 0x00), a.fill_color.?[0]);
    try std.testing.expectEqual(@as(u8, 0x00), a.fill_color.?[1]);
    try std.testing.expectEqual(@as(u8, 0xff), a.fill_color.?[2]);

    // Click on A
    try std.testing.expect(a.link_url != null);
    try std.testing.expectEqualStrings("https://example.com/a", a.link_url.?);
    try std.testing.expect(a.link_tooltip != null);
    try std.testing.expectEqualStrings("Node A", a.link_tooltip.?);

    // Click on C
    const c = graph.getNode("C").?;
    try std.testing.expect(c.link_url != null);
    try std.testing.expectEqualStrings("https://example.com/c", c.link_url.?);

    // B has no click
    const b = graph.getNode("B").?;
    try std.testing.expect(b.link_url == null);

    // Edge style from linkStyle
    const ab = graph.edge("A", "B", null).?;
    try std.testing.expect(ab.color != null);
    try std.testing.expectEqual(@as(u8, 0xff), ab.color.?[0]);
}

test "multiple click directives on same node overwrites" {
    const source =
        \\graph TD
        \\    A --> B
        \\    click A "https://first.com" "First"
        \\    click A "https://second.com" "Second"
    ;
    var parser = try Parser.init(std.testing.allocator, source);
    defer parser.deinit();

    var graph = try parser.parse();
    defer graph.deinitDeep();

    // Second click should overwrite
    const a = graph.getNode("A").?;
    try std.testing.expect(a.link_url != null);
    try std.testing.expectEqualStrings("https://second.com", a.link_url.?);
    try std.testing.expect(a.link_tooltip != null);
    try std.testing.expectEqualStrings("Second", a.link_tooltip.?);
}

test "linkStyle combined with classDef" {
    const source =
        \\graph TD
        \\    classDef red fill:#ff0000
        \\    A:::red --> B --> C
        \\    linkStyle 0 stroke:#0000ff,stroke-width:3px
    ;
    var parser = try Parser.init(std.testing.allocator, source);
    defer parser.deinit();

    var graph = try parser.parse();
    defer graph.deinitDeep();

    // Node style from classDef
    const a = graph.getNode("A").?;
    try std.testing.expect(a.fill_color != null);
    try std.testing.expectEqual(@as(u8, 0xff), a.fill_color.?[0]);

    // Edge style from linkStyle
    const ab = graph.edge("A", "B", null).?;
    try std.testing.expect(ab.color != null);
    try std.testing.expectEqual(@as(u8, 0x00), ab.color.?[0]);
    try std.testing.expectEqual(@as(u8, 0x00), ab.color.?[1]);
    try std.testing.expectEqual(@as(u8, 0xff), ab.color.?[2]);
    try std.testing.expect(ab.thickness != null);
    try std.testing.expectEqual(@as(i32, 3), ab.thickness.?);
}
