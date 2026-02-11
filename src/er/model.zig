//! ER (Entity-Relationship) diagram model types.
//!
//! Mirrors the Rust selkie implementation:
//!   selkie/src/diagrams/er/types.rs

const std = @import("std");

// -----------------------------------------------------------------------
// Enums
// -----------------------------------------------------------------------

/// Cardinality types for ER relationships
pub const Cardinality = enum {
    zero_or_one,
    zero_or_more,
    one_or_more,
    only_one,

    pub fn fromStr(s: []const u8) Cardinality {
        if (s.len == 2) {
            if (eql(s, "|o") or eql(s, "o|")) return .zero_or_one;
            if (eql(s, "}o") or eql(s, "o{")) return .zero_or_more;
            if (eql(s, "}|") or eql(s, "|{")) return .one_or_more;
            if (eql(s, "||")) return .only_one;
        }
        if (eqlIgnoreCase(s, "ZERO_OR_ONE") or eqlIgnoreCase(s, "ZERO OR ONE")) return .zero_or_one;
        if (eqlIgnoreCase(s, "ZERO_OR_MORE") or eqlIgnoreCase(s, "ZERO OR MORE")) return .zero_or_more;
        if (eqlIgnoreCase(s, "ONE_OR_MORE") or eqlIgnoreCase(s, "ONE OR MORE")) return .one_or_more;
        if (eqlIgnoreCase(s, "ONLY_ONE") or eqlIgnoreCase(s, "ONLY ONE")) return .only_one;
        return .zero_or_one;
    }

    pub fn asStr(self: Cardinality) []const u8 {
        return switch (self) {
            .zero_or_one => "ZERO_OR_ONE",
            .zero_or_more => "ZERO_OR_MORE",
            .one_or_more => "ONE_OR_MORE",
            .only_one => "ONLY_ONE",
        };
    }
};

/// Identification type — solid vs dashed relationship line
pub const Identification = enum {
    identifying,
    non_identifying,

    pub fn fromStr(s: []const u8) Identification {
        if (eql(s, "--")) return .identifying;
        if (eqlIgnoreCase(s, "IDENTIFYING")) return .identifying;
        return .non_identifying;
    }

    pub fn asStr(self: Identification) []const u8 {
        return switch (self) {
            .identifying => "IDENTIFYING",
            .non_identifying => "NON_IDENTIFYING",
        };
    }
};

/// Attribute key types (PK, FK, UK)
pub const AttributeKey = enum {
    primary_key,
    foreign_key,
    unique_key,

    pub fn fromStr(s: []const u8) ?AttributeKey {
        if (eqlIgnoreCase(s, "PK")) return .primary_key;
        if (eqlIgnoreCase(s, "FK")) return .foreign_key;
        if (eqlIgnoreCase(s, "UK")) return .unique_key;
        return null;
    }

    pub fn asStr(self: AttributeKey) []const u8 {
        return switch (self) {
            .primary_key => "PK",
            .foreign_key => "FK",
            .unique_key => "UK",
        };
    }
};

/// Diagram direction
pub const Direction = enum {
    TB,
    BT,
    LR,
    RL,

    pub fn fromStr(s: []const u8) Direction {
        if (s.len >= 2) {
            const c0 = std.ascii.toUpper(s[0]);
            const c1 = std.ascii.toUpper(s[1]);
            if (c0 == 'T' and c1 == 'B') return .TB;
            if (c0 == 'B' and c1 == 'T') return .BT;
            if (c0 == 'L' and c1 == 'R') return .LR;
            if (c0 == 'R' and c1 == 'L') return .RL;
        }
        return .TB;
    }
};

// -----------------------------------------------------------------------
// Attribute
// -----------------------------------------------------------------------

pub const Attribute = struct {
    attr_type: []const u8,
    attr_type_owned: bool,
    name: []const u8,
    name_owned: bool,
    keys: std.ArrayListUnmanaged(AttributeKey),
    comment: ?[]const u8,
    comment_owned: bool,

    pub fn init(allocator: std.mem.Allocator, attr_type: []const u8, attr_name: []const u8) !Attribute {
        return .{
            .attr_type = try allocator.dupe(u8, attr_type),
            .attr_type_owned = true,
            .name = try allocator.dupe(u8, attr_name),
            .name_owned = true,
            .keys = .{},
            .comment = null,
            .comment_owned = false,
        };
    }

    pub fn deinit(self: *Attribute, allocator: std.mem.Allocator) void {
        if (self.attr_type_owned) allocator.free(self.attr_type);
        if (self.name_owned) allocator.free(self.name);
        if (self.comment_owned) {
            if (self.comment) |c| allocator.free(c);
        }
        self.keys.deinit(allocator);
    }

    pub fn setComment(self: *Attribute, allocator: std.mem.Allocator, comment: []const u8) !void {
        if (self.comment_owned) {
            if (self.comment) |c| allocator.free(c);
        }
        self.comment = try allocator.dupe(u8, comment);
        self.comment_owned = true;
    }

    pub fn addKey(self: *Attribute, allocator: std.mem.Allocator, key: AttributeKey) !void {
        try self.keys.append(allocator, key);
    }
};

// -----------------------------------------------------------------------
// RelSpec — relationship specification (cardinalities + identification)
// -----------------------------------------------------------------------

pub const RelSpec = struct {
    card_a: Cardinality,
    card_b: Cardinality,
    rel_type: Identification,

    pub fn init(card_a: Cardinality, card_b: Cardinality, rel_type: Identification) RelSpec {
        return .{
            .card_a = card_a,
            .card_b = card_b,
            .rel_type = rel_type,
        };
    }
};

// -----------------------------------------------------------------------
// Entity
// -----------------------------------------------------------------------

pub const Entity = struct {
    id: []const u8,
    id_owned: bool,
    label: []const u8,
    label_owned: bool,
    alias: ?[]const u8,
    alias_owned: bool,
    attributes: std.ArrayListUnmanaged(Attribute),

    pub fn init(allocator: std.mem.Allocator, name: []const u8) !Entity {
        return .{
            .id = try allocator.dupe(u8, name),
            .id_owned = true,
            .label = try allocator.dupe(u8, name),
            .label_owned = true,
            .alias = null,
            .alias_owned = false,
            .attributes = .{},
        };
    }

    pub fn deinit(self: *Entity, allocator: std.mem.Allocator) void {
        if (self.id_owned) allocator.free(self.id);
        if (self.label_owned) allocator.free(self.label);
        if (self.alias_owned) {
            if (self.alias) |a| allocator.free(a);
        }
        for (self.attributes.items) |*attr| {
            attr.deinit(allocator);
        }
        self.attributes.deinit(allocator);
    }

    pub fn displayName(self: *const Entity) []const u8 {
        if (self.alias) |a| {
            if (a.len > 0) return a;
        }
        return self.label;
    }

    pub fn setAlias(self: *Entity, allocator: std.mem.Allocator, alias: []const u8) !void {
        if (self.alias_owned) {
            if (self.alias) |a| allocator.free(a);
        }
        self.alias = try allocator.dupe(u8, alias);
        self.alias_owned = true;
    }

    pub fn addAttribute(self: *Entity, allocator: std.mem.Allocator, attr: Attribute) !void {
        try self.attributes.append(allocator, attr);
    }
};

// -----------------------------------------------------------------------
// Relationship
// -----------------------------------------------------------------------

pub const Relationship = struct {
    entity_a: []const u8,
    entity_a_owned: bool,
    entity_b: []const u8,
    entity_b_owned: bool,
    role: []const u8,
    role_owned: bool,
    rel_spec: RelSpec,

    pub fn init(
        allocator: std.mem.Allocator,
        entity_a: []const u8,
        entity_b: []const u8,
        role: []const u8,
        rel_spec: RelSpec,
    ) !Relationship {
        return .{
            .entity_a = try allocator.dupe(u8, entity_a),
            .entity_a_owned = true,
            .entity_b = try allocator.dupe(u8, entity_b),
            .entity_b_owned = true,
            .role = try allocator.dupe(u8, role),
            .role_owned = true,
            .rel_spec = rel_spec,
        };
    }

    pub fn deinit(self: *Relationship, allocator: std.mem.Allocator) void {
        if (self.entity_a_owned) allocator.free(self.entity_a);
        if (self.entity_b_owned) allocator.free(self.entity_b);
        if (self.role_owned) allocator.free(self.role);
    }
};

// -----------------------------------------------------------------------
// ErDiagram — top-level container
// -----------------------------------------------------------------------

pub const ErDiagram = struct {
    entities: std.StringHashMap(Entity),
    relationships: std.ArrayListUnmanaged(Relationship),
    direction: Direction,
    title: ?[]const u8,
    title_owned: bool,
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) ErDiagram {
        return .{
            .entities = std.StringHashMap(Entity).init(allocator),
            .relationships = .{},
            .direction = .TB,
            .title = null,
            .title_owned = false,
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *ErDiagram) void {
        var iter = self.entities.iterator();
        while (iter.next()) |entry| {
            var entity = entry.value_ptr;
            entity.deinit(self.allocator);
        }
        self.entities.deinit();

        for (self.relationships.items) |*rel| {
            rel.deinit(self.allocator);
        }
        self.relationships.deinit(self.allocator);

        if (self.title_owned) {
            if (self.title) |t| self.allocator.free(t);
        }
    }

    pub fn setTitle(self: *ErDiagram, title: []const u8) !void {
        if (self.title_owned) {
            if (self.title) |t| self.allocator.free(t);
        }
        self.title = try self.allocator.dupe(u8, title);
        self.title_owned = true;
    }

    /// Ensure an entity exists, creating it if necessary. Returns a pointer.
    pub fn ensureEntity(self: *ErDiagram, name: []const u8) !*Entity {
        const result = self.entities.getPtr(name);
        if (result) |ptr| return ptr;

        const entity = try Entity.init(self.allocator, name);
        // We need a stable key — use the entity's own id slice
        const key = entity.id;
        try self.entities.put(key, entity);
        return self.entities.getPtr(name).?;
    }

    /// Add an entity with an optional alias
    pub fn addEntity(self: *ErDiagram, name: []const u8, alias: ?[]const u8) !*Entity {
        const entity = try self.ensureEntity(name);
        if (alias) |a| {
            if (entity.alias == null) {
                try entity.setAlias(self.allocator, a);
            }
        }
        return entity;
    }

    /// Get an entity by name (read-only)
    pub fn getEntity(self: *const ErDiagram, name: []const u8) ?*const Entity {
        // StringHashMap doesn't have a const getPtr, so cast
        const mutable = @constCast(self);
        return mutable.entities.getPtr(name);
    }

    /// Add attributes to an entity (creates entity if needed)
    pub fn addAttributes(self: *ErDiagram, entity_name: []const u8, attrs: []const Attribute) !void {
        const entity = try self.ensureEntity(entity_name);
        for (attrs) |attr| {
            try entity.addAttribute(self.allocator, attr);
        }
    }

    /// Add a relationship between two entities
    pub fn addRelationship(
        self: *ErDiagram,
        entity_a: []const u8,
        entity_b: []const u8,
        role: []const u8,
        rel_spec: RelSpec,
    ) !void {
        // Ensure both entities exist
        _ = try self.ensureEntity(entity_a);
        _ = try self.ensureEntity(entity_b);

        const rel = try Relationship.init(self.allocator, entity_a, entity_b, role, rel_spec);
        try self.relationships.append(self.allocator, rel);
    }

    /// Get count of entities
    pub fn entityCount(self: *const ErDiagram) usize {
        return self.entities.count();
    }

    /// Get count of relationships
    pub fn relationshipCount(self: *const ErDiagram) usize {
        return self.relationships.items.len;
    }

    /// Get all entity names (sorted for deterministic output). Caller owns returned slice.
    pub fn sortedEntityNames(self: *const ErDiagram) ![][]const u8 {
        const mutable = @constCast(self);
        var names = std.ArrayListUnmanaged([]const u8){};
        var iter = mutable.entities.iterator();
        while (iter.next()) |entry| {
            try names.append(self.allocator, entry.key_ptr.*);
        }
        std.mem.sort([]const u8, names.items, {}, struct {
            fn cmp(_: void, a: []const u8, b: []const u8) bool {
                return std.mem.order(u8, a, b) == .lt;
            }
        }.cmp);
        return names.toOwnedSlice(self.allocator);
    }
};

// -----------------------------------------------------------------------
// Color constants for ER rendering
// -----------------------------------------------------------------------

/// Entity header fill
pub const entity_header_fill: [4]u8 = .{ 236, 236, 255, 255 }; // #ececff
/// Entity body fill (odd rows)
pub const entity_row_odd_fill: [4]u8 = .{ 255, 255, 222, 255 }; // #ffffde
/// Entity body fill (even rows)
pub const entity_row_even_fill: [4]u8 = .{ 255, 255, 255, 255 }; // #ffffff
/// Entity stroke
pub const entity_stroke: [4]u8 = .{ 147, 147, 210, 255 }; // #9393d2
/// Entity name text color
pub const entity_name_color: [4]u8 = .{ 51, 51, 51, 255 }; // #333333
/// Attribute text color
pub const attr_text_color: [4]u8 = .{ 51, 51, 51, 255 }; // #333333
/// Relationship line color
pub const rel_line_color: [4]u8 = .{ 51, 51, 51, 255 }; // #333333
/// Relationship label color
pub const rel_label_color: [4]u8 = .{ 51, 51, 51, 255 }; // #333333
/// Label background
pub const label_bg_color: [4]u8 = .{ 232, 232, 232, 230 }; // #e8e8e8

// -----------------------------------------------------------------------
// Helpers
// -----------------------------------------------------------------------

fn eql(a: []const u8, b: []const u8) bool {
    return std.mem.eql(u8, a, b);
}

fn eqlIgnoreCase(a: []const u8, b: []const u8) bool {
    if (a.len != b.len) return false;
    for (a, b) |ca, cb| {
        if (std.ascii.toLower(ca) != std.ascii.toLower(cb)) return false;
    }
    return true;
}

// -----------------------------------------------------------------------
// Tests
// -----------------------------------------------------------------------

test "er model: Cardinality fromStr" {
    try std.testing.expectEqual(Cardinality.only_one, Cardinality.fromStr("||"));
    try std.testing.expectEqual(Cardinality.zero_or_one, Cardinality.fromStr("|o"));
    try std.testing.expectEqual(Cardinality.zero_or_one, Cardinality.fromStr("o|"));
    try std.testing.expectEqual(Cardinality.zero_or_more, Cardinality.fromStr("}o"));
    try std.testing.expectEqual(Cardinality.zero_or_more, Cardinality.fromStr("o{"));
    try std.testing.expectEqual(Cardinality.one_or_more, Cardinality.fromStr("}|"));
    try std.testing.expectEqual(Cardinality.one_or_more, Cardinality.fromStr("|{"));
}

test "er model: Identification fromStr" {
    try std.testing.expectEqual(Identification.identifying, Identification.fromStr("--"));
    try std.testing.expectEqual(Identification.non_identifying, Identification.fromStr(".."));
}

test "er model: AttributeKey fromStr" {
    try std.testing.expectEqual(AttributeKey.primary_key, AttributeKey.fromStr("PK").?);
    try std.testing.expectEqual(AttributeKey.foreign_key, AttributeKey.fromStr("FK").?);
    try std.testing.expectEqual(AttributeKey.unique_key, AttributeKey.fromStr("UK").?);
    try std.testing.expect(AttributeKey.fromStr("XX") == null);
}

test "er model: create ErDiagram" {
    const allocator = std.testing.allocator;
    var diagram = ErDiagram.init(allocator);
    defer diagram.deinit();

    try std.testing.expectEqual(@as(usize, 0), diagram.entityCount());
    try std.testing.expectEqual(@as(usize, 0), diagram.relationshipCount());
}

test "er model: add entity" {
    const allocator = std.testing.allocator;
    var diagram = ErDiagram.init(allocator);
    defer diagram.deinit();

    _ = try diagram.addEntity("CUSTOMER", null);
    try std.testing.expectEqual(@as(usize, 1), diagram.entityCount());

    // Adding same entity again should not duplicate
    _ = try diagram.addEntity("CUSTOMER", null);
    try std.testing.expectEqual(@as(usize, 1), diagram.entityCount());
}

test "er model: entity with alias" {
    const allocator = std.testing.allocator;
    var diagram = ErDiagram.init(allocator);
    defer diagram.deinit();

    _ = try diagram.addEntity("CUSTOMER", "The Customer");
    const entity = diagram.getEntity("CUSTOMER").?;
    try std.testing.expectEqualStrings("The Customer", entity.displayName());
}

test "er model: add attributes" {
    const allocator = std.testing.allocator;
    var diagram = ErDiagram.init(allocator);
    defer diagram.deinit();

    _ = try diagram.ensureEntity("ORDER");
    var attr = try Attribute.init(allocator, "int", "order_id");
    try attr.addKey(allocator, .primary_key);
    try diagram.addAttributes("ORDER", &.{attr});

    const entity = diagram.getEntity("ORDER").?;
    try std.testing.expectEqual(@as(usize, 1), entity.attributes.items.len);
    try std.testing.expectEqualStrings("int", entity.attributes.items[0].attr_type);
    try std.testing.expectEqualStrings("order_id", entity.attributes.items[0].name);
    try std.testing.expectEqual(@as(usize, 1), entity.attributes.items[0].keys.items.len);
    try std.testing.expectEqual(AttributeKey.primary_key, entity.attributes.items[0].keys.items[0]);
}

test "er model: add relationship" {
    const allocator = std.testing.allocator;
    var diagram = ErDiagram.init(allocator);
    defer diagram.deinit();

    try diagram.addRelationship(
        "CUSTOMER",
        "ORDER",
        "places",
        RelSpec.init(.only_one, .zero_or_more, .non_identifying),
    );

    try std.testing.expectEqual(@as(usize, 2), diagram.entityCount());
    try std.testing.expectEqual(@as(usize, 1), diagram.relationshipCount());

    const rel = &diagram.relationships.items[0];
    try std.testing.expectEqualStrings("CUSTOMER", rel.entity_a);
    try std.testing.expectEqualStrings("ORDER", rel.entity_b);
    try std.testing.expectEqualStrings("places", rel.role);
    try std.testing.expectEqual(Cardinality.only_one, rel.rel_spec.card_a);
    try std.testing.expectEqual(Cardinality.zero_or_more, rel.rel_spec.card_b);
}

test "er model: set title" {
    const allocator = std.testing.allocator;
    var diagram = ErDiagram.init(allocator);
    defer diagram.deinit();

    try diagram.setTitle("My ER Diagram");
    try std.testing.expectEqualStrings("My ER Diagram", diagram.title.?);
}

test "er model: sorted entity names" {
    const allocator = std.testing.allocator;
    var diagram = ErDiagram.init(allocator);
    defer diagram.deinit();

    _ = try diagram.ensureEntity("ZEBRA");
    _ = try diagram.ensureEntity("ALPHA");
    _ = try diagram.ensureEntity("MIDDLE");

    const names = try diagram.sortedEntityNames();
    defer allocator.free(names);

    try std.testing.expectEqual(@as(usize, 3), names.len);
    try std.testing.expectEqualStrings("ALPHA", names[0]);
    try std.testing.expectEqualStrings("MIDDLE", names[1]);
    try std.testing.expectEqualStrings("ZEBRA", names[2]);
}

test "er model: entity display name" {
    const allocator = std.testing.allocator;
    var diagram = ErDiagram.init(allocator);
    defer diagram.deinit();

    // Without alias
    _ = try diagram.addEntity("ORDER", null);
    const e1 = diagram.getEntity("ORDER").?;
    try std.testing.expectEqualStrings("ORDER", e1.displayName());

    // With alias
    _ = try diagram.addEntity("CUST", "Customer");
    const e2 = diagram.getEntity("CUST").?;
    try std.testing.expectEqualStrings("Customer", e2.displayName());
}

test "er model: attribute with comment" {
    const allocator = std.testing.allocator;
    var diagram = ErDiagram.init(allocator);
    defer diagram.deinit();

    _ = try diagram.ensureEntity("PRODUCT");
    var attr = try Attribute.init(allocator, "string", "name");
    try attr.setComment(allocator, "Product name");
    try diagram.addAttributes("PRODUCT", &.{attr});

    const entity = diagram.getEntity("PRODUCT").?;
    try std.testing.expectEqualStrings("Product name", entity.attributes.items[0].comment.?);
}

test "er model: direction" {
    const allocator = std.testing.allocator;
    var diagram = ErDiagram.init(allocator);
    defer diagram.deinit();

    try std.testing.expectEqual(Direction.TB, diagram.direction);
    diagram.direction = .LR;
    try std.testing.expectEqual(Direction.LR, diagram.direction);
}

test "er model: self-referencing relationship" {
    const allocator = std.testing.allocator;
    var diagram = ErDiagram.init(allocator);
    defer diagram.deinit();

    try diagram.addRelationship(
        "EMPLOYEE",
        "EMPLOYEE",
        "manages",
        RelSpec.init(.only_one, .zero_or_more, .non_identifying),
    );

    try std.testing.expectEqual(@as(usize, 1), diagram.entityCount());
    try std.testing.expectEqual(@as(usize, 1), diagram.relationshipCount());
}
