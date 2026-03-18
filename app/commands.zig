const std = @import("std");
const merrow = @import("merrow");

const Parser = merrow.flowchart.Parser;
const normalize = merrow.layout.normalize;
const NodeData = merrow.NodeData;
const EdgeData = merrow.EdgeData;
const GraphData = merrow.GraphData;
const Digraph = merrow.Digraph;
const NodeShape = merrow.NodeShape;

const Graph = Digraph(NodeData, EdgeData, GraphData);

const NodeReference = struct {
    name: []const u8,
    scope: ?[]const u8 = null,
};

pub const ApplyError = error{
    EmptyCommand,
    UnsupportedDiagramType,
    UnsupportedCommand,
    InvalidDirection,
    MissingContextReference,
    NodeNotFound,
    AmbiguousNodeReference,
    ContainerNotFound,
    AmbiguousContainerReference,
    EdgeAlreadyExists,
    EdgeNotFound,
    ComplexEdgeStatement,
    InvalidRename,
};

const Command = union(enum) {
    connect: struct { from: NodeReference, to: NodeReference, label: ?[]const u8 },
    disconnect: struct { from: NodeReference, to: NodeReference },
    delete_connector: struct { from: NodeReference, to: NodeReference },
    add_node: struct { label: []const u8, shape: NodeShape, parent: ?[]const u8 },
    delete_node: NodeReference,
    rename_node: struct { node: NodeReference, new_label: []const u8 },
    rename_connector: struct { from: NodeReference, to: NodeReference, new_label: []const u8 },
    set_direction: struct { direction: []const u8 },
};

const AddSpec = struct {
    label: []const u8,
    shape: NodeShape,
};

pub const ApplyResult = struct {
    source: []u8,
    message: []const u8,
};

pub const ApplyResultWithState = struct {
    source: []u8,
    message: []const u8,
    current_node_id: ?[]u8 = null,
};

const CommandContext = struct {
    last_node_id: ?[]u8 = null,

    fn deinit(self: *CommandContext, allocator: std.mem.Allocator) void {
        if (self.last_node_id) |id| allocator.free(id);
        self.last_node_id = null;
    }
};

pub fn describeError(err: anyerror) []const u8 {
    return switch (err) {
        error.EmptyCommand => "Enter a command first",
        error.UnsupportedDiagramType => "Commands currently support flowcharts only",
        error.UnsupportedCommand => "Unsupported command. Try connect, disconnect, add, delete, rename, or direction",
        error.InvalidDirection => "Direction must be LR, RL, TB, TD, or BT",
        error.MissingContextReference => "Couldn't resolve 'it' yet",
        error.NodeNotFound => "Couldn't find a matching node",
        error.AmbiguousNodeReference => "That node reference matches more than one node",
        error.ContainerNotFound => "Couldn't find a matching subgraph",
        error.AmbiguousContainerReference => "That subgraph reference matches more than one group",
        error.EdgeAlreadyExists => "That connection already exists",
        error.EdgeNotFound => "Couldn't find that connection",
        error.ComplexEdgeStatement => "That edit touches a chained or complex edge statement; edit it manually first",
        error.InvalidRename => "Rename commands need a target node and a new label",
        error.OutOfMemory => "Out of memory",
        else => "Command failed",
    };
}

pub fn applyCommand(allocator: std.mem.Allocator, source: []const u8, raw_command: []const u8) !ApplyResult {
    const result = try applyCommandWithState(allocator, source, raw_command, null);
    if (result.current_node_id) |id| allocator.free(id);
    return .{ .source = result.source, .message = result.message };
}

pub fn applyCommandWithState(allocator: std.mem.Allocator, source: []const u8, raw_command: []const u8, previous_context_id: ?[]const u8) !ApplyResultWithState {
    var clauses = try splitCommandChain(allocator, raw_command);
    defer clauses.deinit(allocator);

    var context = CommandContext{};
    defer context.deinit(allocator);
    if (previous_context_id) |id| {
        context.last_node_id = try allocator.dupe(u8, id);
    }

    if (clauses.items.len == 1) {
        const result = try applySingleCommand(allocator, source, clauses.items[0], &context);
        return .{
            .source = result.source,
            .message = result.message,
            .current_node_id = if (context.last_node_id) |id| try allocator.dupe(u8, id) else null,
        };
    }

    var current_source = try allocator.dupe(u8, source);
    errdefer allocator.free(current_source);

    var combined_message = std.ArrayList(u8){};
    defer combined_message.deinit(allocator);

    for (clauses.items, 0..) |clause, index| {
        const result = try applySingleCommand(allocator, current_source, clause, &context);
        if (index > 0) try combined_message.appendSlice(allocator, "; ");
        try combined_message.appendSlice(allocator, result.message);

        allocator.free(result.message);
        allocator.free(current_source);
        current_source = result.source;
    }

    return .{
        .source = current_source,
        .message = try combined_message.toOwnedSlice(allocator),
        .current_node_id = if (context.last_node_id) |id| try allocator.dupe(u8, id) else null,
    };
}

fn applySingleCommand(allocator: std.mem.Allocator, source: []const u8, raw_command: []const u8, context: *CommandContext) !ApplyResult {
    if (detectSequenceDiagram(source)) return error.UnsupportedDiagramType;

    var parser = Parser.init(allocator, source) catch return error.UnsupportedDiagramType;
    defer parser.deinit();

    var graph = parser.parse() catch return error.UnsupportedDiagramType;
    defer {
        normalize.freeDummyIds(allocator, &graph);
        graph.deinitDeep();
    }

    const command = try parseCommand(raw_command);

    return switch (command) {
        .connect => |payload| try applyConnect(allocator, source, &graph, payload.from, payload.to, payload.label, context),
        .disconnect => |payload| try applyDisconnect(allocator, source, &graph, payload.from, payload.to, context),
        .delete_connector => |payload| try applyDeleteConnector(allocator, source, &graph, payload.from, payload.to, context),
        .add_node => |payload| try applyAddNode(allocator, source, &graph, payload.label, payload.shape, payload.parent, context),
        .delete_node => |payload| try applyDeleteNode(allocator, source, &graph, payload, context),
        .rename_node => |payload| try applyRenameNode(allocator, source, &graph, payload.node, payload.new_label, context),
        .rename_connector => |payload| try applyRenameConnector(allocator, source, &graph, payload.from, payload.to, payload.new_label, context),
        .set_direction => |payload| try applyDirection(allocator, source, payload.direction),
    };
}

fn splitCommandChain(allocator: std.mem.Allocator, raw_command: []const u8) !std.ArrayList([]const u8) {
    const command = std.mem.trim(u8, raw_command, " \t\r\n");
    if (command.len == 0) return error.EmptyCommand;

    var clauses = std.ArrayList([]const u8){};
    errdefer clauses.deinit(allocator);

    var start: usize = 0;
    while (true) {
        if (findNextClauseBoundary(command, start)) |boundary| {
            const clause = std.mem.trim(u8, command[start..boundary.split_index], " \t\r\n,;");
            if (clause.len == 0) return error.UnsupportedCommand;
            try clauses.append(allocator, clause);
            start = boundary.next_clause_index;
            continue;
        }

        const clause = std.mem.trim(u8, command[start..], " \t\r\n,;");
        if (clause.len == 0) return error.UnsupportedCommand;
        try clauses.append(allocator, clause);
        break;
    }

    return clauses;
}

const ClauseBoundary = struct {
    split_index: usize,
    next_clause_index: usize,
};

fn findNextClauseBoundary(command: []const u8, start: usize) ?ClauseBoundary {
    const separators = [_][]const u8{ " and ", " then ", "; ", ";", ", and ", ", then ", ", " };

    var index = start;
    while (index < command.len) : (index += 1) {
        if (isInsideQuotes(command, index)) continue;
        for (separators) |separator| {
            if (index + separator.len > command.len) continue;
            if (!std.ascii.eqlIgnoreCase(command[index .. index + separator.len], separator)) continue;

            const next_index = index + separator.len;
            if (hasCommandStarter(command[next_index..])) {
                return .{ .split_index = index, .next_clause_index = next_index };
            }
        }
    }

    return null;
}

fn hasCommandStarter(text: []const u8) bool {
    const trimmed = std.mem.trimLeft(u8, text, " \t\r\n");
    const starters = [_][]const u8{ "connect ", "disconnect ", "add ", "delete ", "remove ", "rename ", "set direction ", "direction " };
    for (starters) |starter| {
        if (startsWithInsensitive(trimmed, starter)) return true;
    }
    return false;
}

fn detectSequenceDiagram(source: []const u8) bool {
    var idx: usize = 0;
    while (idx < source.len and std.ascii.isWhitespace(source[idx])) : (idx += 1) {}
    return std.mem.startsWith(u8, source[idx..], "sequenceDiagram");
}

fn parseCommand(raw_command: []const u8) !Command {
    const command = std.mem.trim(u8, raw_command, " \t\r\n");
    if (command.len == 0) return error.EmptyCommand;

    if (sliceAfterPrefixInsensitive(command, "rename connector ")) |rest| {
        const renamed = try parseConnectorRename(rest);
        return .{ .rename_connector = .{ .from = renamed.from, .to = renamed.to, .new_label = renamed.new_label } };
    }

    if (sliceAfterPrefixInsensitive(command, "delete connector ")) |rest| {
        const edge_ref = try parseConnectorReference(rest);
        return .{ .delete_connector = .{ .from = edge_ref.from, .to = edge_ref.to } };
    }

    if (sliceAfterPrefixInsensitive(command, "remove connector ")) |rest| {
        const edge_ref = try parseConnectorReference(rest);
        return .{ .delete_connector = .{ .from = edge_ref.from, .to = edge_ref.to } };
    }

    if (sliceAfterPrefixInsensitive(command, "connect ")) |rest| {
        const clean = trimReferenceLead(rest);
        const to_idx = indexOfInsensitiveOutsideQuotes(clean, " to ") orelse return error.UnsupportedCommand;
        const from_ref = std.mem.trim(u8, clean[0..to_idx], " \t\r\n");
        const connect_target = splitConnectTarget(std.mem.trim(u8, clean[to_idx + 4 ..], " \t\r\n"));
        const to_ref = connect_target.target;
        if (from_ref.len == 0 or to_ref.len == 0) return error.UnsupportedCommand;
        return .{ .connect = .{ .from = parseNodeReference(from_ref), .to = parseNodeReference(to_ref), .label = connect_target.label } };
    }

    if (sliceAfterPrefixInsensitive(command, "disconnect ")) |rest| {
        const clean = trimReferenceLead(rest);
        const from_idx = indexOfInsensitiveOutsideQuotes(clean, " from ") orelse return error.UnsupportedCommand;
        const left_ref = std.mem.trim(u8, clean[0..from_idx], " \t\r\n");
        const right_ref = std.mem.trim(u8, clean[from_idx + 6 ..], " \t\r\n");
        if (left_ref.len == 0 or right_ref.len == 0) return error.UnsupportedCommand;
        return .{ .disconnect = .{ .from = parseNodeReference(left_ref), .to = parseNodeReference(right_ref) } };
    }

    if (sliceAfterPrefixInsensitive(command, "add ")) |rest| {
        if (splitAddScopedCommand(rest)) |parts| {
            const add_spec = try parseAddSpec(parts.thing);
            return .{ .add_node = .{ .label = add_spec.label, .shape = add_spec.shape, .parent = parts.scope } };
        }

        const add_spec = try parseAddSpec(rest);
        return .{ .add_node = .{ .label = add_spec.label, .shape = add_spec.shape, .parent = null } };
    }

    if (sliceAfterPrefixInsensitive(command, "delete ")) |rest| {
        if (splitScopedCommand(rest)) |parts| {
            return .{ .delete_node = .{ .name = parts.thing, .scope = parts.scope } };
        }

        const node_ref = std.mem.trim(u8, trimReferenceLead(rest), " \t\r\n");
        if (node_ref.len == 0) return error.UnsupportedCommand;
        return .{ .delete_node = .{ .name = node_ref, .scope = null } };
    }

    if (sliceAfterPrefixInsensitive(command, "remove ")) |rest| {
        if (splitScopedCommand(rest)) |parts| {
            return .{ .delete_node = .{ .name = parts.thing, .scope = parts.scope } };
        }

        const node_ref = std.mem.trim(u8, trimReferenceLead(rest), " \t\r\n");
        if (node_ref.len == 0) return error.UnsupportedCommand;
        return .{ .delete_node = .{ .name = node_ref, .scope = null } };
    }

    if (sliceAfterPrefixInsensitive(command, "rename ")) |rest| {
        const clean = trimReferenceLead(rest);
        const to_idx = indexOfInsensitiveOutsideQuotes(clean, " to ") orelse return error.InvalidRename;
        const node_ref = std.mem.trim(u8, clean[0..to_idx], " \t\r\n");
        const new_label = trimOuterQuotes(std.mem.trim(u8, clean[to_idx + 4 ..], " \t\r\n"));
        if (node_ref.len == 0 or new_label.len == 0) return error.InvalidRename;
        return .{ .rename_node = .{ .node = parseNodeReference(node_ref), .new_label = new_label } };
    }

    if (parseDirectionCommand(command)) |direction| {
        return .{ .set_direction = .{ .direction = direction } };
    }

    return error.UnsupportedCommand;
}

fn parseDirectionCommand(command: []const u8) ?[]const u8 {
    if (sliceAfterPrefixInsensitive(command, "direction ")) |rest| {
        return canonicalDirection(std.mem.trim(u8, rest, " \t\r\n"));
    }
    if (sliceAfterPrefixInsensitive(command, "set direction ")) |rest| {
        return canonicalDirection(std.mem.trim(u8, rest, " \t\r\n"));
    }
    if (indexOfInsensitive(command, "left to right") != null) return "LR";
    if (indexOfInsensitive(command, "right to left") != null) return "RL";
    if (indexOfInsensitive(command, "top to bottom") != null) return "TB";
    if (indexOfInsensitive(command, "bottom to top") != null) return "BT";
    return null;
}

const ScopedCommand = struct {
    thing: []const u8,
    scope: []const u8,
};

const ConnectorReference = struct {
    from: NodeReference,
    to: NodeReference,
};

const ConnectorRename = struct {
    from: NodeReference,
    to: NodeReference,
    new_label: []const u8,
};

fn parseConnectorReference(text: []const u8) !ConnectorReference {
    const clean = trimReferenceLead(text);
    const without_from = if (sliceAfterPrefixInsensitive(clean, "from ")) |rest| rest else clean;
    const to_idx = indexOfInsensitiveOutsideQuotes(without_from, " to ") orelse return error.UnsupportedCommand;
    const from_ref = std.mem.trim(u8, without_from[0..to_idx], " \t\r\n");
    const to_ref = std.mem.trim(u8, without_from[to_idx + 4 ..], " \t\r\n");
    if (from_ref.len == 0 or to_ref.len == 0) return error.UnsupportedCommand;
    return .{ .from = parseNodeReference(from_ref), .to = parseNodeReference(to_ref) };
}

fn parseConnectorRename(text: []const u8) !ConnectorRename {
    const clean = trimReferenceLead(text);
    const without_from = if (sliceAfterPrefixInsensitive(clean, "from ")) |rest| rest else clean;
    const first_to_idx = indexOfInsensitiveOutsideQuotes(without_from, " to ") orelse return error.InvalidRename;
    const from_ref = std.mem.trim(u8, without_from[0..first_to_idx], " \t\r\n");
    const remainder = std.mem.trim(u8, without_from[first_to_idx + 4 ..], " \t\r\n");
    const second_to_idx = indexOfInsensitiveOutsideQuotes(remainder, " to ") orelse return error.InvalidRename;
    const to_ref = std.mem.trim(u8, remainder[0..second_to_idx], " \t\r\n");
    const new_label = trimOuterQuotes(std.mem.trim(u8, remainder[second_to_idx + 4 ..], " \t\r\n"));
    if (from_ref.len == 0 or to_ref.len == 0 or new_label.len == 0) return error.InvalidRename;
    return .{ .from = parseNodeReference(from_ref), .to = parseNodeReference(to_ref), .new_label = new_label };
}

fn splitScopedCommand(rest: []const u8) ?ScopedCommand {
    const clean = trimReferenceLead(rest);
    const separators = [_][]const u8{ " in ", " from " };

    for (separators) |separator| {
        if (lastIndexOfInsensitiveOutsideQuotes(clean, separator)) |sep_idx| {
            const thing = std.mem.trim(u8, clean[0..sep_idx], " \t\r\n");
            const scope = std.mem.trim(u8, trimContainerLead(clean[sep_idx + separator.len ..]), " \t\r\n");
            if (thing.len == 0 or scope.len == 0) return null;
            return .{ .thing = thing, .scope = scope };
        }
    }
    return null;
}

fn splitAddScopedCommand(rest: []const u8) ?ScopedCommand {
    const clean = trimReferenceLead(rest);
    const separators = [_][]const u8{ " in ", " to " };

    for (separators) |separator| {
        if (lastIndexOfInsensitiveOutsideQuotes(clean, separator)) |sep_idx| {
            const thing = std.mem.trim(u8, clean[0..sep_idx], " \t\r\n");
            const scope = std.mem.trim(u8, trimContainerLead(clean[sep_idx + separator.len ..]), " \t\r\n");
            if (thing.len == 0 or scope.len == 0) return null;
            return .{ .thing = thing, .scope = scope };
        }
    }
    return null;
}

fn parseNodeReference(text: []const u8) NodeReference {
    const clean = std.mem.trim(u8, trimReferenceLead(text), " \t\r\n");
    if (lastIndexOfInsensitiveOutsideQuotes(clean, " in ")) |scope_idx| {
        const name = trimOuterQuotes(std.mem.trim(u8, clean[0..scope_idx], " \t\r\n"));
        const scope = trimOuterQuotes(std.mem.trim(u8, trimContainerLead(clean[scope_idx + 4 ..]), " \t\r\n"));
        if (name.len > 0 and scope.len > 0) {
            return .{ .name = name, .scope = scope };
        }
    }
    return .{ .name = trimOuterQuotes(clean), .scope = null };
}

const ConnectTarget = struct {
    target: []const u8,
    label: ?[]const u8,
};

fn splitConnectTarget(text: []const u8) ConnectTarget {
    const separators = [_][]const u8{ " with label ", " labeled ", " as " };
    const clean = std.mem.trim(u8, text, " \t\r\n");

    for (separators) |separator| {
        if (lastIndexOfInsensitiveOutsideQuotes(clean, separator)) |idx| {
            const target = std.mem.trim(u8, clean[0..idx], " \t\r\n");
            const label = trimOuterQuotes(std.mem.trim(u8, clean[idx + separator.len ..], " \t\r\n"));
            if (target.len > 0 and label.len > 0) {
                return .{ .target = target, .label = label };
            }
        }
    }

    return .{ .target = clean, .label = null };
}

fn parseAddSpec(text: []const u8) !AddSpec {
    const clean = std.mem.trim(u8, trimReferenceLead(text), " \t\r\n");
    if (clean.len == 0) return error.UnsupportedCommand;

    if (splitLeadingWord(clean)) |parts| {
        if (shapeForWord(parts.word)) |shape| {
            const remainder = trimOuterQuotes(std.mem.trim(u8, parts.rest, " \t\r\n"));
            if (remainder.len == 0) return error.UnsupportedCommand;
            return .{ .label = remainder, .shape = shape };
        }
    }

    return .{ .label = trimOuterQuotes(clean), .shape = .box };
}

const LeadingWord = struct {
    word: []const u8,
    rest: []const u8,
};

fn splitLeadingWord(text: []const u8) ?LeadingWord {
    const clean = std.mem.trim(u8, text, " \t\r\n");
    if (clean.len == 0) return null;
    const first_space = std.mem.indexOfScalar(u8, clean, ' ') orelse return .{ .word = clean, .rest = "" };
    return .{
        .word = clean[0..first_space],
        .rest = clean[first_space + 1 ..],
    };
}

fn shapeForWord(word: []const u8) ?NodeShape {
    if (std.ascii.eqlIgnoreCase(word, "box")) return .box;
    if (std.ascii.eqlIgnoreCase(word, "node")) return .box;
    if (std.ascii.eqlIgnoreCase(word, "round")) return .round;
    if (std.ascii.eqlIgnoreCase(word, "decision")) return .diamond;
    if (std.ascii.eqlIgnoreCase(word, "diamond")) return .diamond;
    if (std.ascii.eqlIgnoreCase(word, "circle")) return .circle;
    if (std.ascii.eqlIgnoreCase(word, "hexagon")) return .hexagon;
    if (std.ascii.eqlIgnoreCase(word, "database")) return .cylinder;
    if (std.ascii.eqlIgnoreCase(word, "cylinder")) return .cylinder;
    if (std.ascii.eqlIgnoreCase(word, "stadium")) return .stadium;
    if (std.ascii.eqlIgnoreCase(word, "subroutine")) return .subroutine;
    if (std.ascii.eqlIgnoreCase(word, "trapezoid")) return .trapezoid;
    if (std.ascii.eqlIgnoreCase(word, "parallelogram")) return .parallelogram;
    return null;
}

fn canonicalDirection(direction: []const u8) ?[]const u8 {
    if (std.ascii.eqlIgnoreCase(direction, "LR")) return "LR";
    if (std.ascii.eqlIgnoreCase(direction, "RL")) return "RL";
    if (std.ascii.eqlIgnoreCase(direction, "TB") or std.ascii.eqlIgnoreCase(direction, "TD")) return "TB";
    if (std.ascii.eqlIgnoreCase(direction, "BT")) return "BT";
    return null;
}

fn applyConnect(allocator: std.mem.Allocator, source: []const u8, graph: *Graph, from_ref: NodeReference, to_ref: NodeReference, label: ?[]const u8, context: *CommandContext) !ApplyResult {
    const from_id = try resolveScopedNodeReference(allocator, graph, from_ref, context);
    const to_id = try resolveScopedNodeReference(allocator, graph, to_ref, context);

    var edge_iter = graph.edgeIterator();
    while (edge_iter.next()) |edge| {
        if (std.mem.eql(u8, edge.v, from_id) and std.mem.eql(u8, edge.w, to_id)) {
            return error.EdgeAlreadyExists;
        }
    }

    const newline = detectNewline(source);
    const separator = if (source.len == 0 or std.mem.endsWith(u8, source, newline)) "" else newline;
    const appended = if (label) |edge_label| blk: {
        const clean_label = try sanitizeEdgeLabel(allocator, edge_label);
        defer allocator.free(clean_label);
        break :blk try std.fmt.allocPrint(allocator, "{s}{s}    {s} -->|{s}| {s}{s}", .{ source, separator, from_id, clean_label, to_id, newline });
    } else try std.fmt.allocPrint(allocator, "{s}{s}    {s} --> {s}{s}", .{ source, separator, from_id, to_id, newline });
    const message = if (label) |edge_label|
        try std.fmt.allocPrint(allocator, "Connected {s} to {s} as {s}", .{ from_id, to_id, edge_label })
    else
        try std.fmt.allocPrint(allocator, "Connected {s} to {s}", .{ from_id, to_id });
    try rememberNodeId(allocator, context, to_id);
    return .{ .source = appended, .message = message };
}

fn applyAddNode(allocator: std.mem.Allocator, source: []const u8, graph: *Graph, label: []const u8, shape: NodeShape, parent_ref: ?[]const u8, context: *CommandContext) !ApplyResult {
    const trimmed_label = std.mem.trim(u8, label, " \t\r\n");
    if (trimmed_label.len == 0) return error.UnsupportedCommand;

    const newline = detectNewline(source);
    const parent_id = if (parent_ref) |scope| try resolveContainerReference(allocator, graph, scope) else null;
    const node_id = try createNodeId(allocator, graph, trimmed_label);
    defer allocator.free(node_id);

    const rendered = try renderNodeDefinition(allocator, node_id, trimmed_label, shape);
    defer allocator.free(rendered);

    const edited = if (parent_id) |pid|
        try insertNodeIntoSubgraph(allocator, source, pid, rendered, newline)
    else
        try appendTopLevelNode(allocator, source, rendered, newline);

    const message = if (parent_id) |pid|
        try std.fmt.allocPrint(allocator, "Added {s} in {s}", .{ node_id, pid })
    else
        try std.fmt.allocPrint(allocator, "Added {s}", .{node_id});

    try rememberNodeId(allocator, context, node_id);

    return .{ .source = edited, .message = message };
}

fn applyDisconnect(allocator: std.mem.Allocator, source: []const u8, graph: *Graph, from_ref: NodeReference, to_ref: NodeReference, context: *CommandContext) !ApplyResult {
    const from_id = try resolveScopedNodeReference(allocator, graph, from_ref, context);
    const to_id = try resolveScopedNodeReference(allocator, graph, to_ref, context);
    const newline = detectNewline(source);
    const had_trailing_newline = std.mem.endsWith(u8, source, newline);

    var kept_lines = std.ArrayList([]const u8){};
    defer kept_lines.deinit(allocator);

    var removed_count: usize = 0;
    var complex_match = false;
    var iter = std.mem.splitSequence(u8, source, newline);
    while (iter.next()) |line| {
        if (matchesSimpleEdgeLine(line, from_id, to_id)) {
            removed_count += 1;
            continue;
        }
        if (containsComplexEdgePair(line, from_id, to_id)) {
            complex_match = true;
        }
        try kept_lines.append(allocator, line);
    }

    if (removed_count == 0) {
        if (complex_match) return error.ComplexEdgeStatement;
        return error.EdgeNotFound;
    }

    const edited = try joinLines(allocator, kept_lines.items, newline, had_trailing_newline);
    const message = try std.fmt.allocPrint(allocator, "Disconnected {s} from {s}", .{ from_id, to_id });
    try rememberNodeId(allocator, context, to_id);
    return .{ .source = edited, .message = message };
}

fn applyDeleteConnector(allocator: std.mem.Allocator, source: []const u8, graph: *Graph, from_ref: NodeReference, to_ref: NodeReference, context: *CommandContext) !ApplyResult {
    const result = try applyDisconnect(allocator, source, graph, from_ref, to_ref, context);
    allocator.free(result.message);
    const from_id = try resolveScopedNodeReference(allocator, graph, from_ref, context);
    const to_id = try resolveScopedNodeReference(allocator, graph, to_ref, context);
    const message = try std.fmt.allocPrint(allocator, "Deleted connector from {s} to {s}", .{ from_id, to_id });
    return .{ .source = result.source, .message = message };
}

fn applyRenameConnector(allocator: std.mem.Allocator, source: []const u8, graph: *Graph, from_ref: NodeReference, to_ref: NodeReference, new_label: []const u8, context: *CommandContext) !ApplyResult {
    const from_id = try resolveScopedNodeReference(allocator, graph, from_ref, context);
    const to_id = try resolveScopedNodeReference(allocator, graph, to_ref, context);
    const newline = detectNewline(source);
    const had_trailing_newline = std.mem.endsWith(u8, source, newline);
    const clean_label = try sanitizeEdgeLabel(allocator, new_label);
    defer allocator.free(clean_label);

    var updated_lines = std.ArrayList([]const u8){};
    defer updated_lines.deinit(allocator);
    var owned_lines = std.ArrayList([]const u8){};
    defer {
        for (owned_lines.items) |line| allocator.free(line);
        owned_lines.deinit(allocator);
    }

    var renamed = false;
    var complex_match = false;
    var iter = std.mem.splitSequence(u8, source, newline);
    while (iter.next()) |line| {
        if (matchesSimpleEdgeLine(line, from_id, to_id)) {
            const indent_len = line.len - std.mem.trimLeft(u8, line, " \t").len;
            const replacement = try std.fmt.allocPrint(allocator, "{s}{s} -->|{s}| {s}", .{ line[0..indent_len], from_id, clean_label, to_id });
            try owned_lines.append(allocator, replacement);
            try updated_lines.append(allocator, replacement);
            renamed = true;
            continue;
        }
        if (containsComplexEdgePair(line, from_id, to_id)) {
            complex_match = true;
        }
        try updated_lines.append(allocator, line);
    }

    if (!renamed) {
        if (complex_match) return error.ComplexEdgeStatement;
        return error.EdgeNotFound;
    }

    const edited = try joinLines(allocator, updated_lines.items, newline, had_trailing_newline);
    const message = try std.fmt.allocPrint(allocator, "Renamed connector from {s} to {s} as {s}", .{ from_id, to_id, clean_label });
    try rememberNodeId(allocator, context, to_id);
    return .{ .source = edited, .message = message };
}

fn applyDeleteNode(allocator: std.mem.Allocator, source: []const u8, graph: *Graph, node_ref: NodeReference, context: *CommandContext) !ApplyResult {
    const node_id = try resolveScopedNodeReference(allocator, graph, node_ref, context);
    const newline = detectNewline(source);
    const had_trailing_newline = std.mem.endsWith(u8, source, newline);

    var kept_lines = std.ArrayList([]const u8){};
    defer kept_lines.deinit(allocator);

    var removed_any = false;
    var complex_match = false;
    var iter = std.mem.splitSequence(u8, source, newline);
    while (iter.next()) |line| {
        if (matchesNodeDefinitionLine(line, node_id) or matchesSimpleEdgeLineForNode(line, node_id) or matchesClickLine(line, node_id)) {
            removed_any = true;
            continue;
        }
        if (containsComplexNodeEdge(line, node_id)) {
            complex_match = true;
        }
        try kept_lines.append(allocator, line);
    }

    if (!removed_any) {
        if (complex_match) return error.ComplexEdgeStatement;
        return error.NodeNotFound;
    }

    const edited = try joinLines(allocator, kept_lines.items, newline, had_trailing_newline);
    const message = try std.fmt.allocPrint(allocator, "Deleted {s}", .{node_id});
    if (context.last_node_id) |last_id| {
        if (std.mem.eql(u8, last_id, node_id)) {
            allocator.free(last_id);
            context.last_node_id = null;
        }
    }
    return .{ .source = edited, .message = message };
}

fn applyRenameNode(allocator: std.mem.Allocator, source: []const u8, graph: *Graph, node_ref: NodeReference, new_label: []const u8, context: *CommandContext) !ApplyResult {
    const node_id = try resolveScopedNodeReference(allocator, graph, node_ref, context);
    const node = graph.getNodePtr(node_id) orelse return error.NodeNotFound;

    const newline = detectNewline(source);
    const separator = if (source.len == 0 or std.mem.endsWith(u8, source, newline)) "" else newline;
    const rendered = try renderNodeDefinition(allocator, node_id, new_label, node.shape);
    defer allocator.free(rendered);
    const edited = try std.fmt.allocPrint(allocator, "{s}{s}    {s}{s}", .{ source, separator, rendered, newline });
    const message = try std.fmt.allocPrint(allocator, "Renamed {s}", .{node_id});
    try rememberNodeId(allocator, context, node_id);
    return .{ .source = edited, .message = message };
}

fn applyDirection(allocator: std.mem.Allocator, source: []const u8, direction: []const u8) !ApplyResult {
    const canonical = canonicalDirection(direction) orelse return error.InvalidDirection;
    const newline = detectNewline(source);
    const had_trailing_newline = std.mem.endsWith(u8, source, newline);

    var updated_lines = std.ArrayList([]const u8){};
    defer updated_lines.deinit(allocator);
    var owned_lines = std.ArrayList([]const u8){};
    defer {
        for (owned_lines.items) |line| allocator.free(line);
        owned_lines.deinit(allocator);
    }

    var replaced = false;
    var iter = std.mem.splitSequence(u8, source, newline);
    while (iter.next()) |line| {
        const trimmed = std.mem.trimLeft(u8, line, " \t");
        if (!replaced and (startsWithKeyword(trimmed, "flowchart") or startsWithKeyword(trimmed, "graph"))) {
            const indent_len = line.len - trimmed.len;
            const keyword = if (startsWithKeyword(trimmed, "flowchart")) "flowchart" else "graph";
            const replacement = try std.fmt.allocPrint(allocator, "{s}{s} {s}", .{ line[0..indent_len], keyword, canonical });
            try owned_lines.append(allocator, replacement);
            try updated_lines.append(allocator, replacement);
            replaced = true;
            continue;
        }
        try updated_lines.append(allocator, line);
    }

    if (!replaced) {
        const prefix = try std.fmt.allocPrint(allocator, "flowchart {s}", .{canonical});
        try owned_lines.append(allocator, prefix);
        try updated_lines.insert(allocator, 0, prefix);
    }

    const edited = try joinLines(allocator, updated_lines.items, newline, had_trailing_newline or updated_lines.items.len > 0);
    const message = try std.fmt.allocPrint(allocator, "Set direction to {s}", .{canonical});
    return .{ .source = edited, .message = message };
}

fn resolveNodeReference(allocator: std.mem.Allocator, graph: *Graph, node_ref: []const u8, parent_scope: ?[]const u8) ![]const u8 {
    const normalized_ref = try canonicalizeReference(allocator, node_ref);
    defer allocator.free(normalized_ref);

    var best_score: i32 = -1;
    var best_id: ?[]const u8 = null;
    var ambiguous = false;

    var node_iter = graph.nodes.iterator();
    while (node_iter.next()) |entry| {
        const id = entry.key_ptr.*;
        const node = entry.value_ptr;
        if (node.is_subgraph) continue;
        if (parent_scope) |scope| {
            if (!isNodeWithinScope(graph, id, scope)) continue;
        }

        const id_score = try matchScore(allocator, normalized_ref, id, .id);
        const label_score = if (node.label) |label| try matchScore(allocator, normalized_ref, label, .label) else -1;
        const score = @max(id_score, label_score);
        if (score < 0) continue;

        if (score > best_score) {
            best_score = score;
            best_id = id;
            ambiguous = false;
        } else if (score == best_score) {
            if (best_id) |existing| {
                if (!std.mem.eql(u8, existing, id)) ambiguous = true;
            }
        }
    }

    if (best_score < 0 or best_id == null) return error.NodeNotFound;
    if (ambiguous) return error.AmbiguousNodeReference;
    return best_id.?;
}

fn resolveScopedNodeReference(allocator: std.mem.Allocator, graph: *Graph, reference: NodeReference, context: ?*CommandContext) ![]const u8 {
    if (isContextReference(reference.name)) {
        const ctx = context orelse return error.MissingContextReference;
        return ctx.last_node_id orelse return error.MissingContextReference;
    }
    const parent_id = if (reference.scope) |scope| try resolveContainerReference(allocator, graph, scope) else null;
    return resolveNodeReference(allocator, graph, reference.name, parent_id);
}

fn rememberNodeId(allocator: std.mem.Allocator, context: *CommandContext, node_id: []const u8) !void {
    if (context.last_node_id) |existing| allocator.free(existing);
    context.last_node_id = try allocator.dupe(u8, node_id);
}

fn isContextReference(name: []const u8) bool {
    return std.ascii.eqlIgnoreCase(name, "it") or std.ascii.eqlIgnoreCase(name, "that") or std.ascii.eqlIgnoreCase(name, "this");
}

fn resolveContainerReference(allocator: std.mem.Allocator, graph: *Graph, container_ref: []const u8) ![]const u8 {
    const normalized_ref = try canonicalizeReference(allocator, trimContainerLead(container_ref));
    defer allocator.free(normalized_ref);

    var best_score: i32 = -1;
    var best_id: ?[]const u8 = null;
    var ambiguous = false;

    var node_iter = graph.nodes.iterator();
    while (node_iter.next()) |entry| {
        const id = entry.key_ptr.*;
        const node = entry.value_ptr;
        if (!node.is_subgraph) continue;

        const id_score = try matchScore(allocator, normalized_ref, id, .id);
        const label_score = if (node.label) |label| try matchScore(allocator, normalized_ref, label, .label) else -1;
        const title_score = if (node.subgraph_title) |title| try matchScore(allocator, normalized_ref, title, .label) else -1;
        const score = @max(id_score, @max(label_score, title_score));
        if (score < 0) continue;

        if (score > best_score) {
            best_score = score;
            best_id = id;
            ambiguous = false;
        } else if (score == best_score) {
            if (best_id) |existing| {
                if (!std.mem.eql(u8, existing, id)) ambiguous = true;
            }
        }
    }

    if (best_score < 0 or best_id == null) return error.ContainerNotFound;
    if (ambiguous) return error.AmbiguousContainerReference;
    return best_id.?;
}

fn isNodeWithinScope(graph: *Graph, node_id: []const u8, scope_id: []const u8) bool {
    var cursor = graph.getParent(node_id);
    while (cursor) |parent_id| {
        if (std.mem.eql(u8, parent_id, scope_id)) return true;
        cursor = graph.getParent(parent_id);
    }
    return false;
}

const MatchTarget = enum {
    id,
    label,
};

fn matchScore(allocator: std.mem.Allocator, normalized_ref: []const u8, candidate: []const u8, target: MatchTarget) !i32 {
    const normalized_candidate = try canonicalizeReference(allocator, candidate);
    defer allocator.free(normalized_candidate);

    if (std.mem.eql(u8, normalized_ref, normalized_candidate)) {
        return switch (target) {
            .label => 240,
            .id => if (std.mem.indexOfScalar(u8, normalized_candidate, ' ') == null) 200 else 180,
        };
    }

    if (target == .label) {
        if (hasWordBoundaryMatch(normalized_candidate, normalized_ref)) return 170;
        if (std.mem.indexOf(u8, normalized_candidate, normalized_ref) != null) return 150;
        if (std.mem.indexOf(u8, normalized_ref, normalized_candidate) != null) return 130;
    }

    if (std.mem.indexOf(u8, normalized_candidate, normalized_ref) != null) {
        if (std.mem.indexOfScalar(u8, normalized_candidate, ' ') == null) return 110;
        return 90;
    }

    if (target == .id and hasWordBoundaryMatch(normalized_candidate, normalized_ref)) return 80;
    return -1;
}

fn hasWordBoundaryMatch(haystack: []const u8, needle: []const u8) bool {
    var start: usize = 0;
    while (std.mem.indexOfPos(u8, haystack, start, needle)) |idx| {
        const before_ok = idx == 0 or haystack[idx - 1] == ' ';
        const after_idx = idx + needle.len;
        const after_ok = after_idx >= haystack.len or haystack[after_idx] == ' ';
        if (before_ok and after_ok) return true;
        start = idx + 1;
    }
    return false;
}

fn canonicalizeReference(allocator: std.mem.Allocator, text: []const u8) ![]u8 {
    var trimmed = trimOuterQuotes(std.mem.trim(u8, text, " \t\r\n"));
    trimmed = trimReferenceLead(trimmed);

    var out = std.ArrayList(u8){};
    errdefer out.deinit(allocator);

    var last_was_space = false;
    for (trimmed) |byte| {
        const c = std.ascii.toLower(byte);
        if (std.ascii.isWhitespace(c)) {
            if (out.items.len == 0 or last_was_space) continue;
            try out.append(allocator, ' ');
            last_was_space = true;
            continue;
        }
        if (c == '"' or c == '\'' or c == '.' or c == ',' or c == '!' or c == '?') continue;
        try out.append(allocator, c);
        last_was_space = false;
    }

    while (out.items.len > 0 and out.items[out.items.len - 1] == ' ') {
        _ = out.pop();
    }

    return out.toOwnedSlice(allocator);
}

fn trimReferenceLead(text: []const u8) []const u8 {
    var result = std.mem.trim(u8, text, " \t\r\n");
    const prefixes = [_][]const u8{ "the ", "box ", "node ", "shape ", "box named ", "node named " };
    var changed = true;
    while (changed) {
        changed = false;
        for (prefixes) |prefix| {
            if (startsWithInsensitive(result, prefix)) {
                result = std.mem.trim(u8, result[prefix.len..], " \t\r\n");
                changed = true;
                break;
            }
        }
    }
    return result;
}

fn trimContainerLead(text: []const u8) []const u8 {
    var result = std.mem.trim(u8, text, " \t\r\n");
    const prefixes = [_][]const u8{ "subgraph ", "group ", "section ", "cluster ", "inside ", "within " };
    var changed = true;
    while (changed) {
        changed = false;
        for (prefixes) |prefix| {
            if (startsWithInsensitive(result, prefix)) {
                result = std.mem.trim(u8, result[prefix.len..], " \t\r\n");
                changed = true;
                break;
            }
        }
    }
    return result;
}

fn appendTopLevelNode(allocator: std.mem.Allocator, source: []const u8, rendered: []const u8, newline: []const u8) ![]u8 {
    const separator = if (source.len == 0 or std.mem.endsWith(u8, source, newline)) "" else newline;
    return std.fmt.allocPrint(allocator, "{s}{s}    {s}{s}", .{ source, separator, rendered, newline });
}

const StackEntry = struct {
    id: []const u8,
    child_indent: []u8,
};

fn insertNodeIntoSubgraph(allocator: std.mem.Allocator, source: []const u8, subgraph_id: []const u8, rendered: []const u8, newline: []const u8) ![]u8 {
    const had_trailing_newline = std.mem.endsWith(u8, source, newline);
    var lines = std.ArrayList([]const u8){};
    defer lines.deinit(allocator);
    var stack = std.ArrayList(StackEntry){};
    defer {
        for (stack.items) |entry| allocator.free(entry.child_indent);
        stack.deinit(allocator);
    }

    var inserted = false;
    var iter = std.mem.splitSequence(u8, source, newline);
    while (iter.next()) |line| {
        const trimmed = std.mem.trimLeft(u8, line, " \t");

        if (startsWithKeyword(trimmed, "subgraph")) {
            if (parseSubgraphHeaderId(trimmed)) |header_id| {
                const indent_len = line.len - trimmed.len;
                const child_indent = try std.fmt.allocPrint(allocator, "{s}    ", .{line[0..indent_len]});
                try stack.append(allocator, .{ .id = header_id, .child_indent = child_indent });
            }
            try lines.append(allocator, line);
            continue;
        }

        if (startsWithKeyword(trimmed, "end")) {
            if (stack.items.len > 0) {
                const entry = stack.items[stack.items.len - 1];
                if (!inserted and std.mem.eql(u8, entry.id, subgraph_id)) {
                    const inserted_line = try std.fmt.allocPrint(allocator, "{s}{s}", .{ entry.child_indent, rendered });
                    try lines.append(allocator, inserted_line);
                    inserted = true;
                }
                allocator.free(entry.child_indent);
                _ = stack.pop();
            }
            try lines.append(allocator, line);
            continue;
        }

        try lines.append(allocator, line);
    }

    if (!inserted) return error.ContainerNotFound;
    return joinLines(allocator, lines.items, newline, had_trailing_newline);
}

fn parseSubgraphHeaderId(trimmed_line: []const u8) ?[]const u8 {
    if (!startsWithKeyword(trimmed_line, "subgraph")) return null;
    const rest = std.mem.trimLeft(u8, trimmed_line[8..], " \t");
    return leadingIdentifier(rest);
}

fn createNodeId(allocator: std.mem.Allocator, graph: *Graph, label: []const u8) ![]u8 {
    var base = std.ArrayList(u8){};
    defer base.deinit(allocator);

    var last_was_underscore = false;
    for (label) |byte| {
        const lower = std.ascii.toLower(byte);
        if (std.ascii.isAlphanumeric(lower)) {
            try base.append(allocator, lower);
            last_was_underscore = false;
            continue;
        }
        if ((std.ascii.isWhitespace(byte) or byte == '-' or byte == '/' or byte == '.') and base.items.len > 0 and !last_was_underscore) {
            try base.append(allocator, '_');
            last_was_underscore = true;
        }
    }

    while (base.items.len > 0 and base.items[base.items.len - 1] == '_') {
        _ = base.pop();
    }

    if (base.items.len == 0) {
        try base.appendSlice(allocator, "node");
    } else if (!std.ascii.isAlphabetic(base.items[0])) {
        try base.insertSlice(allocator, 0, "node_");
    }

    const base_id = try base.toOwnedSlice(allocator);
    errdefer allocator.free(base_id);
    if (!graph.hasNode(base_id)) return base_id;

    var suffix: usize = 2;
    while (true) : (suffix += 1) {
        const candidate = try std.fmt.allocPrint(allocator, "{s}_{d}", .{ base_id, suffix });
        if (!graph.hasNode(candidate)) {
            allocator.free(base_id);
            return candidate;
        }
        allocator.free(candidate);
    }
}

fn trimOuterQuotes(text: []const u8) []const u8 {
    if (text.len >= 2) {
        const first = text[0];
        const last = text[text.len - 1];
        if ((first == '"' and last == '"') or (first == '\'' and last == '\'')) {
            return text[1 .. text.len - 1];
        }
    }
    return text;
}

fn sanitizeEdgeLabel(allocator: std.mem.Allocator, label: []const u8) ![]u8 {
    var out = std.ArrayList(u8){};
    errdefer out.deinit(allocator);

    for (label) |byte| {
        if (byte == '\n' or byte == '\r' or byte == '|') {
            try out.append(allocator, ' ');
        } else {
            try out.append(allocator, byte);
        }
    }

    const owned = try out.toOwnedSlice(allocator);
    const trimmed = std.mem.trim(u8, owned, " \t");
    if (trimmed.ptr == owned.ptr and trimmed.len == owned.len) return owned;

    const result = try allocator.dupe(u8, trimmed);
    allocator.free(owned);
    return result;
}

fn detectNewline(source: []const u8) []const u8 {
    if (std.mem.indexOf(u8, source, "\r\n") != null) return "\r\n";
    return "\n";
}

fn joinLines(allocator: std.mem.Allocator, lines: []const []const u8, newline: []const u8, had_trailing_newline: bool) ![]u8 {
    var result = std.ArrayList(u8){};
    errdefer result.deinit(allocator);

    for (lines, 0..) |line, index| {
        if (index > 0) try result.appendSlice(allocator, newline);
        try result.appendSlice(allocator, line);
    }
    if (had_trailing_newline and lines.len > 0) try result.appendSlice(allocator, newline);
    return result.toOwnedSlice(allocator);
}

fn startsWithInsensitive(haystack: []const u8, needle: []const u8) bool {
    if (needle.len > haystack.len) return false;
    return std.ascii.eqlIgnoreCase(haystack[0..needle.len], needle);
}

fn startsWithKeyword(line: []const u8, keyword: []const u8) bool {
    if (!startsWithInsensitive(line, keyword)) return false;
    if (line.len == keyword.len) return true;
    return std.ascii.isWhitespace(line[keyword.len]);
}

fn sliceAfterPrefixInsensitive(haystack: []const u8, prefix: []const u8) ?[]const u8 {
    if (!startsWithInsensitive(haystack, prefix)) return null;
    return haystack[prefix.len..];
}

fn indexOfInsensitive(haystack: []const u8, needle: []const u8) ?usize {
    if (needle.len == 0) return 0;
    if (needle.len > haystack.len) return null;
    var index: usize = 0;
    while (index + needle.len <= haystack.len) : (index += 1) {
        if (std.ascii.eqlIgnoreCase(haystack[index .. index + needle.len], needle)) return index;
    }
    return null;
}

fn indexOfInsensitiveOutsideQuotes(haystack: []const u8, needle: []const u8) ?usize {
    if (needle.len == 0) return 0;
    if (needle.len > haystack.len) return null;
    var index: usize = 0;
    while (index + needle.len <= haystack.len) : (index += 1) {
        if (isInsideQuotes(haystack, index)) continue;
        if (std.ascii.eqlIgnoreCase(haystack[index .. index + needle.len], needle)) return index;
    }
    return null;
}

fn lastIndexOfInsensitive(haystack: []const u8, needle: []const u8) ?usize {
    if (needle.len == 0) return haystack.len;
    if (needle.len > haystack.len) return null;
    var index: usize = haystack.len - needle.len;
    while (true) {
        if (std.ascii.eqlIgnoreCase(haystack[index .. index + needle.len], needle)) return index;
        if (index == 0) break;
        index -= 1;
    }
    return null;
}

fn lastIndexOfInsensitiveOutsideQuotes(haystack: []const u8, needle: []const u8) ?usize {
    if (needle.len == 0) return haystack.len;
    if (needle.len > haystack.len) return null;
    var index: usize = haystack.len - needle.len;
    while (true) {
        if (!isInsideQuotes(haystack, index) and std.ascii.eqlIgnoreCase(haystack[index .. index + needle.len], needle)) return index;
        if (index == 0) break;
        index -= 1;
    }
    return null;
}

fn isInsideQuotes(text: []const u8, position: usize) bool {
    var active_quote: ?u8 = null;
    var index: usize = 0;
    while (index < position and index < text.len) : (index += 1) {
        const byte = text[index];
        if (byte != '\'' and byte != '"') continue;
        if (index > 0 and text[index - 1] == '\\') continue;
        if (active_quote) |quote| {
            if (quote == byte) active_quote = null;
        } else {
            active_quote = byte;
        }
    }
    return active_quote != null;
}

fn isIdentifierChar(byte: u8) bool {
    return std.ascii.isAlphanumeric(byte) or byte == '_';
}

fn countArrowTokens(line: []const u8) usize {
    const tokens = [_][]const u8{ "<==>", "<-.->", "<-->", "==>", "-.->", "-->", "---" };
    var count: usize = 0;
    for (tokens) |token| {
        var start: usize = 0;
        while (std.mem.indexOfPos(u8, line, start, token)) |idx| {
            count += 1;
            start = idx + token.len;
        }
    }
    return count;
}

const SimpleEdge = struct {
    from: []const u8,
    to: []const u8,
};

fn extractSimpleEdge(line: []const u8) ?SimpleEdge {
    const trimmed = std.mem.trim(u8, line, " \t\r\n");
    if (trimmed.len == 0 or startsWithInsensitive(trimmed, "%%")) return null;
    if (countArrowTokens(trimmed) != 1) return null;

    const tokens = [_][]const u8{ "<==>", "<-.->", "<-->", "==>", "-.->", "-->", "---" };
    for (tokens) |token| {
        if (std.mem.indexOf(u8, trimmed, token)) |idx| {
            const left = std.mem.trimRight(u8, trimmed[0..idx], " \t");
            var right = std.mem.trimLeft(u8, trimmed[idx + token.len ..], " \t");
            if (right.len > 0 and right[0] == '|') {
                if (std.mem.indexOfScalarPos(u8, right, 1, '|')) |end_idx| {
                    right = std.mem.trimLeft(u8, right[end_idx + 1 ..], " \t");
                }
            }
            const from_id = leadingIdentifier(left) orelse return null;
            const to_id = leadingIdentifier(right) orelse return null;
            return .{ .from = from_id, .to = to_id };
        }
    }
    return null;
}

fn leadingIdentifier(segment: []const u8) ?[]const u8 {
    const trimmed = std.mem.trimLeft(u8, segment, " \t");
    if (trimmed.len == 0 or !isIdentifierChar(trimmed[0])) return null;
    var end: usize = 1;
    while (end < trimmed.len and isIdentifierChar(trimmed[end])) : (end += 1) {}
    return trimmed[0..end];
}

fn matchesSimpleEdgeLine(line: []const u8, from_id: []const u8, to_id: []const u8) bool {
    const edge = extractSimpleEdge(line) orelse return false;
    return std.mem.eql(u8, edge.from, from_id) and std.mem.eql(u8, edge.to, to_id);
}

fn containsComplexEdgePair(line: []const u8, from_id: []const u8, to_id: []const u8) bool {
    if (countArrowTokens(line) <= 1) return false;
    return containsBoundedIdentifier(line, from_id) and containsBoundedIdentifier(line, to_id);
}

fn matchesSimpleEdgeLineForNode(line: []const u8, node_id: []const u8) bool {
    const edge = extractSimpleEdge(line) orelse return false;
    return std.mem.eql(u8, edge.from, node_id) or std.mem.eql(u8, edge.to, node_id);
}

fn containsComplexNodeEdge(line: []const u8, node_id: []const u8) bool {
    if (countArrowTokens(line) <= 1) return false;
    return containsBoundedIdentifier(line, node_id);
}

fn containsBoundedIdentifier(line: []const u8, id: []const u8) bool {
    var start: usize = 0;
    while (std.mem.indexOfPos(u8, line, start, id)) |idx| {
        const before_ok = idx == 0 or !isIdentifierChar(line[idx - 1]);
        const after_idx = idx + id.len;
        const after_ok = after_idx >= line.len or !isIdentifierChar(line[after_idx]);
        if (before_ok and after_ok) return true;
        start = idx + 1;
    }
    return false;
}

fn matchesNodeDefinitionLine(line: []const u8, node_id: []const u8) bool {
    const trimmed = std.mem.trimLeft(u8, line, " \t");
    if (trimmed.len == 0 or startsWithInsensitive(trimmed, "%%")) return false;
    if (startsWithKeyword(trimmed, "flowchart") or startsWithKeyword(trimmed, "graph") or startsWithKeyword(trimmed, "subgraph") or startsWithKeyword(trimmed, "direction") or startsWithKeyword(trimmed, "end") or startsWithKeyword(trimmed, "style") or startsWithKeyword(trimmed, "classDef") or startsWithKeyword(trimmed, "class") or startsWithKeyword(trimmed, "linkStyle") or startsWithKeyword(trimmed, "click")) return false;
    if (countArrowTokens(trimmed) > 0) return false;
    const id = leadingIdentifier(trimmed) orelse return false;
    return std.mem.eql(u8, id, node_id);
}

fn matchesClickLine(line: []const u8, node_id: []const u8) bool {
    const trimmed = std.mem.trimLeft(u8, line, " \t");
    if (!startsWithKeyword(trimmed, "click")) return false;
    const rest = std.mem.trimLeft(u8, trimmed[5..], " \t");
    const id = leadingIdentifier(rest) orelse return false;
    return std.mem.eql(u8, id, node_id);
}

fn renderNodeDefinition(allocator: std.mem.Allocator, node_id: []const u8, label: []const u8, shape: NodeShape) ![]u8 {
    const clean_label = try sanitizeLabel(allocator, label, shape);
    defer allocator.free(clean_label);
    return switch (shape) {
        .box => std.fmt.allocPrint(allocator, "{s}[{s}]", .{ node_id, clean_label }),
        .round => std.fmt.allocPrint(allocator, "{s}({s})", .{ node_id, clean_label }),
        .diamond => std.fmt.allocPrint(allocator, "{s}{{{s}}}", .{ node_id, clean_label }),
        .circle => std.fmt.allocPrint(allocator, "{s}(({s}))", .{ node_id, clean_label }),
        .hexagon => std.fmt.allocPrint(allocator, "{s}{{{{{s}}}}}", .{ node_id, clean_label }),
        .cylinder => std.fmt.allocPrint(allocator, "{s}[({s})]", .{ node_id, clean_label }),
        .stadium => std.fmt.allocPrint(allocator, "{s}([{s}])", .{ node_id, clean_label }),
        .trapezoid => std.fmt.allocPrint(allocator, "{s}[/{s}/]", .{ node_id, clean_label }),
        .trapezoid_alt => std.fmt.allocPrint(allocator, "{s}[\\{s}\\]", .{ node_id, clean_label }),
        .parallelogram => std.fmt.allocPrint(allocator, "{s}[/{s}\\]", .{ node_id, clean_label }),
        .parallelogram_alt => std.fmt.allocPrint(allocator, "{s}[\\{s}/]", .{ node_id, clean_label }),
        .subroutine => std.fmt.allocPrint(allocator, "{s}[[{s}]]", .{ node_id, clean_label }),
    };
}

fn sanitizeLabel(allocator: std.mem.Allocator, label: []const u8, shape: NodeShape) ![]u8 {
    var out = std.ArrayList(u8){};
    errdefer out.deinit(allocator);

    for (label) |byte| {
        const replacement: ?u8 = switch (shape) {
            .box, .subroutine => if (byte == ']') ' ' else null,
            .round, .stadium, .circle, .cylinder => if (byte == ')') ' ' else null,
            .diamond, .hexagon => if (byte == '}') ' ' else null,
            .trapezoid, .trapezoid_alt, .parallelogram, .parallelogram_alt => if (byte == '/' or byte == '\\' or byte == ']') ' ' else null,
        };
        if (byte == '\n' or byte == '\r') {
            try out.append(allocator, ' ');
        } else if (replacement) |value| {
            try out.append(allocator, value);
        } else {
            try out.append(allocator, byte);
        }
    }

    const owned = try out.toOwnedSlice(allocator);
    const trimmed = std.mem.trim(u8, owned, " \t");
    if (trimmed.ptr == owned.ptr and trimmed.len == owned.len) return owned;

    const result = try allocator.dupe(u8, trimmed);
    allocator.free(owned);
    return result;
}

test "connect command appends an edge" {
    const source =
        "flowchart TD\n" ++
        "    A[Alpha]\n" ++
        "    B[Beta]\n";
    const result = try applyCommand(std.testing.allocator, source, "connect box alpha to box beta");
    defer std.testing.allocator.free(result.source);
    defer std.testing.allocator.free(result.message);

    try std.testing.expect(std.mem.indexOf(u8, result.source, "A --> B") != null);
}

test "disconnect command removes a simple edge line" {
    const source =
        "flowchart TD\n" ++
        "    A[Alpha]\n" ++
        "    B[Beta]\n" ++
        "    A --> B\n";
    const result = try applyCommand(std.testing.allocator, source, "disconnect alpha from beta");
    defer std.testing.allocator.free(result.source);
    defer std.testing.allocator.free(result.message);

    try std.testing.expect(std.mem.indexOf(u8, result.source, "A --> B") == null);
}

test "delete command removes node definitions and simple incident edges" {
    const source =
        "flowchart TD\n" ++
        "    A[Alpha]\n" ++
        "    B[Beta]\n" ++
        "    A --> B\n";
    const result = try applyCommand(std.testing.allocator, source, "delete box alpha");
    defer std.testing.allocator.free(result.source);
    defer std.testing.allocator.free(result.message);

    try std.testing.expect(std.mem.indexOf(u8, result.source, "A[Alpha]") == null);
    try std.testing.expect(std.mem.indexOf(u8, result.source, "A --> B") == null);
}

test "add command inserts a node inside a subgraph" {
    const source =
        "flowchart TD\n" ++
        "    subgraph backend[Backend]\n" ++
        "        api[API]\n" ++
        "    end\n";
    const result = try applyCommand(std.testing.allocator, source, "add retry storage in backend");
    defer std.testing.allocator.free(result.source);
    defer std.testing.allocator.free(result.message);

    try std.testing.expect(std.mem.indexOf(u8, result.source, "retry_storage[retry storage]") != null);
    try std.testing.expect(std.mem.indexOf(u8, result.source, "retry_storage[retry storage]\n    end") != null);
}

test "add command maps database keyword to cylinder shape" {
    const source =
        "flowchart TD\n" ++
        "    subgraph data[Data]\n" ++
        "    end\n";
    const result = try applyCommand(std.testing.allocator, source, "add database retry storage in data");
    defer std.testing.allocator.free(result.source);
    defer std.testing.allocator.free(result.message);

    try std.testing.expect(std.mem.indexOf(u8, result.source, "retry_storage[(retry storage)]") != null);
}

test "add command maps decision keyword to diamond shape" {
    const source =
        "flowchart TD\n" ++
        "    subgraph processing[Processing]\n" ++
        "    end\n";
    const result = try applyCommand(std.testing.allocator, source, "add decision fraud check in processing");
    defer std.testing.allocator.free(result.source);
    defer std.testing.allocator.free(result.message);

    try std.testing.expect(std.mem.indexOf(u8, result.source, "fraud_check{fraud check}") != null);
}

test "add command supports to-group syntax without changing the label" {
    const source =
        "flowchart TD\n" ++
        "    subgraph security[Security]\n" ++
        "    end\n";
    const result = try applyCommand(std.testing.allocator, source, "add \"AV Checker\" to security");
    defer std.testing.allocator.free(result.source);
    defer std.testing.allocator.free(result.message);

    try std.testing.expect(std.mem.indexOf(u8, result.source, "av_checker[AV Checker]") != null);
    try std.testing.expect(std.mem.indexOf(u8, result.source, "to security") == null);
}

test "add quoted node in subgraph uses stable container id resolution" {
    const source =
        "flowchart TD\n" ++
        "    subgraph backend[Backend]\n" ++
        "        api[API]\n" ++
        "    end\n";
    const result = try applyCommand(std.testing.allocator, source, "ADD \"intent scan\" IN Backend");
    defer std.testing.allocator.free(result.source);
    defer std.testing.allocator.free(result.message);

    try std.testing.expect(std.mem.indexOf(u8, result.source, "intent_scan[intent scan]") != null);
    try std.testing.expect(std.mem.indexOf(u8, result.source, "intent_scan[intent scan]\n    end") != null);
}

test "delete command resolves duplicate labels within a named subgraph" {
    const source =
        "flowchart TD\n" ++
        "    subgraph backend[Backend]\n" ++
        "        api_backend[API]\n" ++
        "    end\n" ++
        "    subgraph frontend[Frontend]\n" ++
        "        api_frontend[API]\n" ++
        "    end\n";
    const result = try applyCommand(std.testing.allocator, source, "delete api from backend");
    defer std.testing.allocator.free(result.source);
    defer std.testing.allocator.free(result.message);

    try std.testing.expect(std.mem.indexOf(u8, result.source, "api_backend[API]") == null);
    try std.testing.expect(std.mem.indexOf(u8, result.source, "api_frontend[API]") != null);
}

test "connect command resolves duplicate labels within scoped subgraphs" {
    const source =
        "flowchart TD\n" ++
        "    subgraph backend[Backend]\n" ++
        "        api_backend[API]\n" ++
        "    end\n" ++
        "    subgraph data[Data]\n" ++
        "        storage_data[(Storage)]\n" ++
        "    end\n" ++
        "    subgraph frontend[Frontend]\n" ++
        "        api_frontend[API]\n" ++
        "        storage_front[(Storage)]\n" ++
        "    end\n";
    const result = try applyCommand(std.testing.allocator, source, "connect api in backend to storage in data");
    defer std.testing.allocator.free(result.source);
    defer std.testing.allocator.free(result.message);

    try std.testing.expect(std.mem.indexOf(u8, result.source, "api_backend --> storage_data") != null);
    try std.testing.expect(std.mem.indexOf(u8, result.source, "api_frontend --> storage_front") == null);
}

test "compound command can add and then connect in one sentence" {
    const source =
        "flowchart TD\n" ++
        "    subgraph backend[Backend]\n" ++
        "        api_backend[API]\n" ++
        "    end\n" ++
        "    subgraph data[Data]\n" ++
        "    end\n";
    const result = try applyCommand(std.testing.allocator, source, "add database retry storage in data and connect api in backend to retry storage in data");
    defer std.testing.allocator.free(result.source);
    defer std.testing.allocator.free(result.message);

    try std.testing.expect(std.mem.indexOf(u8, result.source, "retry_storage[(retry storage)]") != null);
    try std.testing.expect(std.mem.indexOf(u8, result.source, "api_backend --> retry_storage") != null);
    try std.testing.expect(std.mem.indexOf(u8, result.message, "Added retry_storage") != null);
    try std.testing.expect(std.mem.indexOf(u8, result.message, "Connected api_backend to retry_storage") != null);
}

test "compound command resolves quoted names and pronoun reference" {
    const source =
        "flowchart TD\n" ++
        "    rag_platform[RAG platform]\n";
    const result = try applyCommand(std.testing.allocator, source, "add \"AV Checker\" and connect it to \"RAG platform\"");
    defer std.testing.allocator.free(result.source);
    defer std.testing.allocator.free(result.message);

    try std.testing.expect(std.mem.indexOf(u8, result.source, "av_checker[AV Checker]") != null);
    try std.testing.expect(std.mem.indexOf(u8, result.source, "av_checker --> rag_platform") != null);
}

test "connect command supports quoted connector labels" {
    const source =
        "flowchart TD\n" ++
        "    av_checker[AV Checker]\n" ++
        "    rag_platform[RAG platform]\n";
    const result = try applyCommand(std.testing.allocator, source, "connect \"AV Checker\" to \"RAG platform\" as \"checks\"");
    defer std.testing.allocator.free(result.source);
    defer std.testing.allocator.free(result.message);

    try std.testing.expect(std.mem.indexOf(u8, result.source, "av_checker -->|checks| rag_platform") != null);
    try std.testing.expect(std.mem.indexOf(u8, result.message, "Connected av_checker to rag_platform as checks") != null);
}

test "rename connector command relabels a simple edge" {
    const source =
        "flowchart TD\n" ++
        "    av_checker[AV Checker]\n" ++
        "    rag_platform[RAG platform]\n" ++
        "    av_checker --> rag_platform\n";
    const result = try applyCommand(std.testing.allocator, source, "rename connector from \"AV Checker\" to \"RAG platform\" to \"screens requests\"");
    defer std.testing.allocator.free(result.source);
    defer std.testing.allocator.free(result.message);

    try std.testing.expect(std.mem.indexOf(u8, result.source, "av_checker -->|screens requests| rag_platform") != null);
}

test "delete connector command removes a simple edge" {
    const source =
        "flowchart TD\n" ++
        "    av_checker[AV Checker]\n" ++
        "    rag_platform[RAG platform]\n" ++
        "    av_checker -->|checks| rag_platform\n";
    const result = try applyCommand(std.testing.allocator, source, "delete connector from \"AV Checker\" to \"RAG platform\"");
    defer std.testing.allocator.free(result.source);
    defer std.testing.allocator.free(result.message);

    try std.testing.expect(std.mem.indexOf(u8, result.source, "av_checker -->|checks| rag_platform") == null);
}

test "connect remembers the target as the last major object" {
    const source =
        "flowchart TD\n" ++
        "    av_checker[AV Checker]\n" ++
        "    rag_platform[RAG platform]\n";
    const result = try applyCommand(std.testing.allocator, source, "connect \"AV Checker\" to \"RAG platform\" and rename it to \"Knowledge Platform\"");
    defer std.testing.allocator.free(result.source);
    defer std.testing.allocator.free(result.message);

    try std.testing.expect(std.mem.indexOf(u8, result.source, "av_checker --> rag_platform") != null);
    try std.testing.expect(std.mem.indexOf(u8, result.source, "rag_platform[Knowledge Platform]") != null);
}

test "disconnect remembers the target as the last major object" {
    const source =
        "flowchart TD\n" ++
        "    av_checker[AV Checker]\n" ++
        "    rag_platform[RAG platform]\n" ++
        "    av_checker --> rag_platform\n";
    const result = try applyCommand(std.testing.allocator, source, "disconnect \"AV Checker\" from \"RAG platform\" and rename it to \"Knowledge Platform\"");
    defer std.testing.allocator.free(result.source);
    defer std.testing.allocator.free(result.message);

    try std.testing.expect(std.mem.indexOf(u8, result.source, "av_checker --> rag_platform") == null);
    try std.testing.expect(std.mem.indexOf(u8, result.source, "rag_platform[Knowledge Platform]") != null);
}

test "disconnect command resolves duplicate labels within scoped subgraphs" {
    const source =
        "flowchart TD\n" ++
        "    subgraph backend[Backend]\n" ++
        "        api_backend[API]\n" ++
        "    end\n" ++
        "    subgraph data[Data]\n" ++
        "        storage_data[(Storage)]\n" ++
        "    end\n" ++
        "    subgraph frontend[Frontend]\n" ++
        "        api_frontend[API]\n" ++
        "    end\n" ++
        "    api_backend --> storage_data\n" ++
        "    api_frontend --> storage_data\n";
    const result = try applyCommand(std.testing.allocator, source, "disconnect api in backend from storage in data");
    defer std.testing.allocator.free(result.source);
    defer std.testing.allocator.free(result.message);

    try std.testing.expect(std.mem.indexOf(u8, result.source, "api_backend --> storage_data") == null);
    try std.testing.expect(std.mem.indexOf(u8, result.source, "api_frontend --> storage_data") != null);
}

test "rename command preserves the node id and appends a replacement definition" {
    const source =
        "flowchart TD\n" ++
        "    A[Alpha]\n";
    const result = try applyCommand(std.testing.allocator, source, "rename alpha to Payments API");
    defer std.testing.allocator.free(result.source);
    defer std.testing.allocator.free(result.message);

    try std.testing.expect(std.mem.indexOf(u8, result.source, "A[Payments API]") != null);
}

test "rename command resolves duplicate labels within a named subgraph" {
    const source =
        "flowchart TD\n" ++
        "    subgraph backend[Backend]\n" ++
        "        api_backend[API]\n" ++
        "    end\n" ++
        "    subgraph frontend[Frontend]\n" ++
        "        api_frontend[API]\n" ++
        "    end\n";
    const result = try applyCommand(std.testing.allocator, source, "rename api in backend to Payments API");
    defer std.testing.allocator.free(result.source);
    defer std.testing.allocator.free(result.message);

    try std.testing.expect(std.mem.indexOf(u8, result.source, "api_backend[Payments API]") != null);
    try std.testing.expect(std.mem.indexOf(u8, result.source, "api_frontend[Payments API]") == null);
}

test "direction command rewrites the top directive" {
    const source =
        "flowchart TD\n" ++
        "    A[Alpha]\n";
    const result = try applyCommand(std.testing.allocator, source, "set direction LR");
    defer std.testing.allocator.free(result.source);
    defer std.testing.allocator.free(result.message);

    try std.testing.expect(std.mem.startsWith(u8, result.source, "flowchart LR"));
}

test "connect command resolves multi-word visible captions" {
    const source =
        "flowchart TD\n" ++
        "    llm_proxy[LLM Proxy]\n" ++
        "    retry_store[(Retry Storage)]\n";
    const result = try applyCommand(std.testing.allocator, source, "connect llm proxy to retry storage");
    defer std.testing.allocator.free(result.source);
    defer std.testing.allocator.free(result.message);

    try std.testing.expect(std.mem.indexOf(u8, result.source, "llm_proxy --> retry_store") != null);
}

test "visible label match beats internal id match" {
    const source =
        "flowchart TD\n" ++
        "    gateway[Internal Gateway]\n" ++
        "    service_node[Gateway]\n" ++
        "    target[Target]\n";
    const result = try applyCommand(std.testing.allocator, source, "connect gateway to target");
    defer std.testing.allocator.free(result.source);
    defer std.testing.allocator.free(result.message);

    try std.testing.expect(std.mem.indexOf(u8, result.source, "service_node --> target") != null);
    try std.testing.expect(std.mem.indexOf(u8, result.source, "gateway --> target") == null);
}
