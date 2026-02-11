//! Class diagram data model.
//!
//! Represents all the elements of a Mermaid class diagram:
//! classes (with members, methods, annotations), relationships
//! between classes, and diagram-level settings.

const std = @import("std");
const Allocator = std.mem.Allocator;

// -----------------------------------------------------------------------
// Visibility
// -----------------------------------------------------------------------

/// UML visibility modifier for class members.
pub const Visibility = enum {
    none,
    public, // +
    private, // -
    protected, // #
    internal, // ~

    /// Parse visibility from the first character of a member string.
    pub fn fromChar(c: u8) ?Visibility {
        return switch (c) {
            '+' => .public,
            '-' => .private,
            '#' => .protected,
            '~' => .internal,
            else => null,
        };
    }

    /// Display prefix string.
    pub fn symbol(self: Visibility) []const u8 {
        return switch (self) {
            .none => "",
            .public => "+",
            .private => "-",
            .protected => "#",
            .internal => "~",
        };
    }
};

// -----------------------------------------------------------------------
// Member type & classifier
// -----------------------------------------------------------------------

/// Whether a class member is an attribute or a method.
pub const MemberType = enum {
    attribute,
    method,
};

/// Classifier for static or abstract members.
pub const Classifier = enum {
    none,
    static_member, // $
    abstract_member, // *

    pub fn fromChar(c: u8) ?Classifier {
        return switch (c) {
            '$' => .static_member,
            '*' => .abstract_member,
            else => null,
        };
    }
};

// -----------------------------------------------------------------------
// ClassMember
// -----------------------------------------------------------------------

/// A single member (attribute or method) of a class.
pub const ClassMember = struct {
    /// Raw text as written in the diagram source.
    text: []const u8,
    text_owned: bool = false,

    /// Parsed visibility.
    visibility: Visibility = .none,

    /// Whether this is an attribute or method.
    member_type: MemberType = .attribute,

    /// Classifier (static / abstract).
    classifier: Classifier = .none,

    pub fn deinit(self: *ClassMember, allocator: Allocator) void {
        if (self.text_owned) {
            allocator.free(self.text);
        }
    }
};

// -----------------------------------------------------------------------
// Relationship types
// -----------------------------------------------------------------------

/// The type of arrowhead at one end of a relationship.
pub const RelationEndType = enum {
    none,
    extension, // |>  (inheritance / generalisation)
    composition, // *   (filled diamond)
    aggregation, // o   (open diamond)
    dependency, // >   (open arrow)
    lollipop, // ()  (interface realisation)
};

/// Line style for a relationship.
pub const LineType = enum {
    solid, // --
    dotted, // ..
};

/// Details about a relationship's visual representation.
pub const RelationDetails = struct {
    type1: RelationEndType = .none, // left / source end
    type2: RelationEndType = .none, // right / target end
    line_type: LineType = .solid,
};

/// A relationship between two classes.
pub const ClassRelation = struct {
    /// Source class id.
    id1: []const u8,
    id1_owned: bool = false,
    /// Target class id.
    id2: []const u8,
    id2_owned: bool = false,

    /// Cardinality label on the source side (e.g. "1").
    cardinality1: ?[]const u8 = null,
    cardinality1_owned: bool = false,
    /// Cardinality label on the target side (e.g. "*").
    cardinality2: ?[]const u8 = null,
    cardinality2_owned: bool = false,

    /// Relationship label (text after the colon).
    label: ?[]const u8 = null,
    label_owned: bool = false,

    /// Visual details (arrow types, line style).
    relation: RelationDetails = .{},

    pub fn deinit(self: *ClassRelation, allocator: Allocator) void {
        if (self.id1_owned) allocator.free(self.id1);
        if (self.id2_owned) allocator.free(self.id2);
        if (self.cardinality1_owned) {
            if (self.cardinality1) |c| allocator.free(c);
        }
        if (self.cardinality2_owned) {
            if (self.cardinality2) |c| allocator.free(c);
        }
        if (self.label_owned) {
            if (self.label) |l| allocator.free(l);
        }
    }
};

// -----------------------------------------------------------------------
// ClassNode
// -----------------------------------------------------------------------

/// A class in the diagram.
pub const ClassNode = struct {
    /// Unique identifier (class name).
    id: []const u8,
    id_owned: bool = false,

    /// Display label (may differ from id if set via `["Label"]`).
    label: ?[]const u8 = null,
    label_owned: bool = false,

    /// Generic type parameter (e.g. `~T~` → "T").
    generic: ?[]const u8 = null,
    generic_owned: bool = false,

    /// Annotations (e.g. `<<interface>>`, `<<abstract>>`).
    annotations: std.ArrayListUnmanaged([]const u8) = .{},

    /// Attribute members.
    members: std.ArrayListUnmanaged(ClassMember) = .{},

    /// Method members.
    methods: std.ArrayListUnmanaged(ClassMember) = .{},

    pub fn deinit(self: *ClassNode, allocator: Allocator) void {
        if (self.id_owned) allocator.free(self.id);
        if (self.label_owned) {
            if (self.label) |l| allocator.free(l);
        }
        if (self.generic_owned) {
            if (self.generic) |g| allocator.free(g);
        }
        for (self.annotations.items) |ann| {
            allocator.free(ann);
        }
        self.annotations.deinit(allocator);

        for (self.members.items) |*m| {
            var member = m.*;
            member.deinit(allocator);
        }
        self.members.deinit(allocator);

        for (self.methods.items) |*m| {
            var method = m.*;
            method.deinit(allocator);
        }
        self.methods.deinit(allocator);
    }

    /// Get the display name for this class (label if set, else id).
    pub fn displayName(self: *const ClassNode) []const u8 {
        return self.label orelse self.id;
    }

    /// Return the total number of members + methods (for sizing).
    pub fn totalMembers(self: *const ClassNode) usize {
        return self.members.items.len + self.methods.items.len;
    }
};

// -----------------------------------------------------------------------
// ClassDiagram — top-level container
// -----------------------------------------------------------------------

/// Complete class diagram parsed from Mermaid syntax.
pub const ClassDiagram = struct {
    /// All classes, keyed by id.
    classes: std.StringArrayHashMapUnmanaged(ClassNode) = .{},

    /// All relationships in declaration order.
    relations: std.ArrayListUnmanaged(ClassRelation) = .{},

    /// Layout direction ("TB", "BT", "LR", "RL").
    direction: []const u8 = "TB",

    /// Optional title.
    title: ?[]const u8 = null,
    title_owned: bool = false,

    allocator: Allocator,

    pub fn init(allocator: Allocator) ClassDiagram {
        return .{ .allocator = allocator };
    }

    pub fn deinit(self: *ClassDiagram) void {
        // Free all class nodes.
        var it = self.classes.iterator();
        while (it.next()) |entry| {
            // Free the key (we own it).
            self.allocator.free(entry.key_ptr.*);
            entry.value_ptr.deinit(self.allocator);
        }
        self.classes.deinit(self.allocator);

        // Free all relations.
        for (self.relations.items) |*rel| {
            rel.deinit(self.allocator);
        }
        self.relations.deinit(self.allocator);

        if (self.title_owned) {
            if (self.title) |t| self.allocator.free(t);
        }
    }

    /// Ensure a class exists in the diagram. If it doesn't exist, creates it.
    /// Returns a pointer to the (possibly new) ClassNode.
    pub fn ensureClass(self: *ClassDiagram, id: []const u8) !*ClassNode {
        const gop = try self.classes.getOrPut(self.allocator, id);
        if (!gop.found_existing) {
            // We need to own the key.
            const owned_key = try self.allocator.dupe(u8, id);
            gop.key_ptr.* = owned_key;
            gop.value_ptr.* = .{
                .id = owned_key,
                .id_owned = false, // key is owned by the map
            };
        }
        return gop.value_ptr;
    }

    /// Add a member to a class (creates the class if needed).
    /// Determines method vs attribute by presence of '('.
    pub fn addMember(self: *ClassDiagram, class_id: []const u8, text: []const u8) !void {
        const node = try self.ensureClass(class_id);

        // Parse visibility from the first character.
        var vis: Visibility = .none;
        var clean_text = text;
        if (text.len > 0) {
            if (Visibility.fromChar(text[0])) |v| {
                vis = v;
                clean_text = text[1..];
            }
        }

        // Parse classifier from last character.
        var cls: Classifier = .none;
        if (clean_text.len > 0) {
            if (Classifier.fromChar(clean_text[clean_text.len - 1])) |c| {
                cls = c;
                clean_text = clean_text[0 .. clean_text.len - 1];
            }
        }

        const is_method = std.mem.indexOf(u8, text, "(") != null;
        const owned_text = try self.allocator.dupe(u8, text);

        const member = ClassMember{
            .text = owned_text,
            .text_owned = true,
            .visibility = vis,
            .member_type = if (is_method) .method else .attribute,
            .classifier = cls,
        };

        if (is_method) {
            try node.methods.append(self.allocator, member);
        } else {
            try node.members.append(self.allocator, member);
        }
    }

    /// Add an annotation (e.g. "interface", "abstract") to a class.
    pub fn addAnnotation(self: *ClassDiagram, class_id: []const u8, annotation: []const u8) !void {
        const node = try self.ensureClass(class_id);
        const owned = try self.allocator.dupe(u8, annotation);
        try node.annotations.append(self.allocator, owned);
    }

    /// Add a relationship.
    pub fn addRelation(self: *ClassDiagram, rel: ClassRelation) !void {
        // Ensure both classes exist.
        _ = try self.ensureClass(rel.id1);
        _ = try self.ensureClass(rel.id2);
        try self.relations.append(self.allocator, rel);
    }

    /// Set the diagram direction.
    pub fn setDirection(self: *ClassDiagram, dir: []const u8) void {
        self.direction = dir;
    }

    /// Set the diagram title.
    pub fn setTitle(self: *ClassDiagram, t: []const u8) !void {
        if (self.title_owned) {
            if (self.title) |old| self.allocator.free(old);
        }
        self.title = try self.allocator.dupe(u8, t);
        self.title_owned = true;
    }

    /// Number of classes.
    pub fn classCount(self: *const ClassDiagram) usize {
        return self.classes.count();
    }

    /// Number of relationships.
    pub fn relationCount(self: *const ClassDiagram) usize {
        return self.relations.items.len;
    }
};

// -----------------------------------------------------------------------
// Relationship arrow parsing helper
// -----------------------------------------------------------------------

/// Parse a Mermaid relationship arrow string (e.g. "<|--", "--*", "..|>")
/// into a `RelationDetails`.
pub fn parseRelationArrow(arrow: []const u8) RelationDetails {
    var result = RelationDetails{};

    // Determine line type.
    if (std.mem.indexOf(u8, arrow, "..") != null) {
        result.line_type = .dotted;
    } else {
        result.line_type = .solid;
    }

    // Parse left end (prefixes).
    if (startsWith(arrow, "<|")) {
        result.type1 = .extension;
    } else if (startsWith(arrow, "<")) {
        result.type1 = .dependency;
    } else if (startsWith(arrow, "*")) {
        result.type1 = .composition;
    } else if (startsWith(arrow, "o")) {
        result.type1 = .aggregation;
    } else if (startsWith(arrow, "()")) {
        result.type1 = .lollipop;
    }

    // Parse right end (suffixes).
    if (endsWith(arrow, "|>")) {
        result.type2 = .extension;
    } else if (endsWith(arrow, ">")) {
        result.type2 = .dependency;
    } else if (endsWith(arrow, "*")) {
        result.type2 = .composition;
    } else if (endsWith(arrow, "o")) {
        result.type2 = .aggregation;
    } else if (endsWith(arrow, "()")) {
        result.type2 = .lollipop;
    }

    return result;
}

// -----------------------------------------------------------------------
// Utility helpers
// -----------------------------------------------------------------------

fn startsWith(haystack: []const u8, prefix: []const u8) bool {
    if (haystack.len < prefix.len) return false;
    return std.mem.eql(u8, haystack[0..prefix.len], prefix);
}

fn endsWith(haystack: []const u8, suffix: []const u8) bool {
    if (haystack.len < suffix.len) return false;
    return std.mem.eql(u8, haystack[haystack.len - suffix.len ..], suffix);
}

// -----------------------------------------------------------------------
// Colors for class diagram rendering
// -----------------------------------------------------------------------

/// Default class node colors (UML style).
pub const class_header_color = [4]u8{ 38, 94, 151, 255 }; // #265e97 dark blue header
pub const class_body_color = [4]u8{ 240, 244, 248, 255 }; // #f0f4f8 light blue-gray body
pub const class_border_color = [4]u8{ 38, 94, 151, 255 }; // #265e97 border
pub const class_text_color = [4]u8{ 51, 51, 51, 255 }; // #333333 dark text
pub const class_header_text_color = [4]u8{ 255, 255, 255, 255 }; // white header text
pub const relation_color = [4]u8{ 51, 51, 51, 255 }; // #333333 dark lines
pub const label_color = [4]u8{ 80, 80, 80, 255 }; // #505050 label text

// -----------------------------------------------------------------------
// Tests
// -----------------------------------------------------------------------

test "class model: basic diagram operations" {
    const allocator = std.testing.allocator;
    var diagram = ClassDiagram.init(allocator);
    defer diagram.deinit();

    _ = try diagram.ensureClass("Animal");
    _ = try diagram.ensureClass("Dog");

    try std.testing.expectEqual(@as(usize, 2), diagram.classCount());
}

test "class model: add members" {
    const allocator = std.testing.allocator;
    var diagram = ClassDiagram.init(allocator);
    defer diagram.deinit();

    try diagram.addMember("Animal", "+name: string");
    try diagram.addMember("Animal", "-age: int");
    try diagram.addMember("Animal", "+speak()");

    const node = diagram.classes.get("Animal").?;
    try std.testing.expectEqual(@as(usize, 2), node.members.items.len);
    try std.testing.expectEqual(@as(usize, 1), node.methods.items.len);

    // Check visibility parsing.
    try std.testing.expectEqual(Visibility.public, node.members.items[0].visibility);
    try std.testing.expectEqual(Visibility.private, node.members.items[1].visibility);
    try std.testing.expectEqual(Visibility.public, node.methods.items[0].visibility);
}

test "class model: add annotation" {
    const allocator = std.testing.allocator;
    var diagram = ClassDiagram.init(allocator);
    defer diagram.deinit();

    try diagram.addAnnotation("Animal", "interface");

    const node = diagram.classes.get("Animal").?;
    try std.testing.expectEqual(@as(usize, 1), node.annotations.items.len);
    try std.testing.expectEqualStrings("interface", node.annotations.items[0]);
}

test "class model: add relation" {
    const allocator = std.testing.allocator;
    var diagram = ClassDiagram.init(allocator);
    defer diagram.deinit();

    const rel = ClassRelation{
        .id1 = "Dog",
        .id2 = "Animal",
        .relation = .{ .type1 = .none, .type2 = .extension, .line_type = .solid },
    };
    try diagram.addRelation(rel);

    try std.testing.expectEqual(@as(usize, 1), diagram.relationCount());
    try std.testing.expectEqual(@as(usize, 2), diagram.classCount()); // both auto-created
}

test "class model: parse relation arrows" {
    // Extension: --|>
    {
        const r = parseRelationArrow("--|>");
        try std.testing.expectEqual(RelationEndType.none, r.type1);
        try std.testing.expectEqual(RelationEndType.extension, r.type2);
        try std.testing.expectEqual(LineType.solid, r.line_type);
    }
    // Reverse extension: <|--
    {
        const r = parseRelationArrow("<|--");
        try std.testing.expectEqual(RelationEndType.extension, r.type1);
        try std.testing.expectEqual(RelationEndType.none, r.type2);
        try std.testing.expectEqual(LineType.solid, r.line_type);
    }
    // Composition: *--
    {
        const r = parseRelationArrow("*--");
        try std.testing.expectEqual(RelationEndType.composition, r.type1);
        try std.testing.expectEqual(RelationEndType.none, r.type2);
    }
    // Aggregation dotted: o..
    {
        const r = parseRelationArrow("o..");
        try std.testing.expectEqual(RelationEndType.aggregation, r.type1);
        try std.testing.expectEqual(LineType.dotted, r.line_type);
    }
    // Dependency: ..>
    {
        const r = parseRelationArrow("..>");
        try std.testing.expectEqual(RelationEndType.dependency, r.type2);
        try std.testing.expectEqual(LineType.dotted, r.line_type);
    }
    // Simple solid: --
    {
        const r = parseRelationArrow("--");
        try std.testing.expectEqual(RelationEndType.none, r.type1);
        try std.testing.expectEqual(RelationEndType.none, r.type2);
        try std.testing.expectEqual(LineType.solid, r.line_type);
    }
}

test "class model: display name" {
    const allocator = std.testing.allocator;
    var diagram = ClassDiagram.init(allocator);
    defer diagram.deinit();

    const node = try diagram.ensureClass("MyClass");
    try std.testing.expectEqualStrings("MyClass", node.displayName());
}

test "class model: set title" {
    const allocator = std.testing.allocator;
    var diagram = ClassDiagram.init(allocator);
    defer diagram.deinit();

    try diagram.setTitle("Animal Kingdom");
    try std.testing.expect(diagram.title != null);
    try std.testing.expectEqualStrings("Animal Kingdom", diagram.title.?);
}

test "class model: set direction" {
    const allocator = std.testing.allocator;
    var diagram = ClassDiagram.init(allocator);
    defer diagram.deinit();

    diagram.setDirection("LR");
    try std.testing.expectEqualStrings("LR", diagram.direction);
}

test "class model: duplicate class" {
    const allocator = std.testing.allocator;
    var diagram = ClassDiagram.init(allocator);
    defer diagram.deinit();

    _ = try diagram.ensureClass("Foo");
    _ = try diagram.ensureClass("Foo");

    try std.testing.expectEqual(@as(usize, 1), diagram.classCount());
}

test "class model: visibility fromChar" {
    try std.testing.expectEqual(Visibility.public, Visibility.fromChar('+').?);
    try std.testing.expectEqual(Visibility.private, Visibility.fromChar('-').?);
    try std.testing.expectEqual(Visibility.protected, Visibility.fromChar('#').?);
    try std.testing.expectEqual(Visibility.internal, Visibility.fromChar('~').?);
    try std.testing.expect(Visibility.fromChar('x') == null);
}

test "class model: classifier" {
    try std.testing.expectEqual(Classifier.static_member, Classifier.fromChar('$').?);
    try std.testing.expectEqual(Classifier.abstract_member, Classifier.fromChar('*').?);
    try std.testing.expect(Classifier.fromChar('x') == null);
}
