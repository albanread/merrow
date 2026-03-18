const std = @import("std");
const Allocator = std.mem.Allocator;
const Canvas = @import("canvas.zig").Canvas;
const text_mod = @import("text.zig");
pub const Font = text_mod.Font;
const Digraph = @import("../graph/digraph.zig").Digraph;
const model = @import("../model.zig");
const NodeData = model.NodeData;
const EdgeData = model.EdgeData;
const GraphData = model.GraphData;
const NodeShape = model.NodeShape;
const LineStyle = model.LineStyle;

const Graph = Digraph(NodeData, EdgeData, GraphData);

// ---------------------------------------------------------------------------
// Label collision avoidance
// ---------------------------------------------------------------------------

/// A pending label to be drawn after collision resolution.
pub const LabelPlacement = struct {
    /// Label text (borrowed from edge data — valid for the duration of rendering).
    text: []const u8,
    /// Current position (centre of label) — modified during solving.
    x: f64,
    y: f64,
    /// Original position before solving — used as spring anchor.
    orig_x: f64,
    orig_y: f64,
    /// Bounding box half-extents (including padding).
    half_w: f64,
    half_h: f64,
    /// Unit tangent of the edge at the label point — used to compute
    /// a perpendicular nudge direction for collision resolution.
    tangent_x: f64,
    tangent_y: f64,
    /// Font size for this label.
    font_size: f32,
    /// Text color.
    color: [4]u8,
};

/// Axis-aligned bounding-box overlap test for two label placements.
/// Returns true when the two AABBs intersect.
fn labelsOverlap(a: LabelPlacement, b: LabelPlacement) bool {
    return (a.x - a.half_w) < (b.x + b.half_w) and
        (a.x + a.half_w) > (b.x - b.half_w) and
        (a.y - a.half_h) < (b.y + b.half_h) and
        (a.y + a.half_h) > (b.y - b.half_h);
}

/// Compute the AABB overlap depth between two labels.
/// Returns (overlap_x, overlap_y) — both positive when overlapping.
/// If either axis has no overlap the values are <= 0.
fn overlapDepth(a: LabelPlacement, b: LabelPlacement) struct { x: f64, y: f64 } {
    const ox = (a.half_w + b.half_w) - @abs(a.x - b.x);
    const oy = (a.half_h + b.half_h) - @abs(a.y - b.y);
    return .{ .x = ox, .y = oy };
}

/// Node AABB for collision testing (pre-computed once).
pub const NodeRect = struct {
    cx: f64,
    cy: f64,
    hw: f64,
    hh: f64,
};

// -----------------------------------------------------------------------
// Force-directed label placement solver
// -----------------------------------------------------------------------
//
// The solver applies three kinds of forces every iteration:
//
//  1. **Spring attraction** to each label's original position so labels
//     don't drift far from where they semantically belong.
//
//  2. **Label–label repulsion** when two label AABBs overlap.  The force
//     pushes them apart along the axis of *minimum* penetration so they
//     separate as quickly as possible.
//
//  3. **Label–node repulsion** when a label overlaps a node's bounding
//     box.  Same minimum-penetration push, but only the label moves.
//
// Forces are accumulated per label, scaled by a step size that decays
// (damping) over iterations for stable convergence.

/// Unified force-directed collision resolver for edge labels.
///
/// `node_rects` contains the pre-computed AABB of every non-dummy node
/// (in canvas coordinates, i.e. with offset already applied).
fn resolveLabelsForceDirected(
    labels: []LabelPlacement,
    node_rects: []const NodeRect,
) void {
    if (labels.len == 0) return;

    // Solver parameters — tuned for typical diagram densities.
    const max_iterations: usize = 40;
    const initial_step: f64 = 1.0;
    const damping: f64 = 0.92; // multiplicative decay per iteration
    const spring_k: f64 = 0.15; // attraction strength to original pos
    const repel_strength: f64 = 1.2; // label–label repulsion multiplier
    const node_repel_strength: f64 = 1.5; // label–node repulsion multiplier
    const convergence_threshold: f64 = 0.5; // stop when max displacement < this

    // Per-label force accumulators (stack-allocated up to 128 labels,
    // which is more than enough for any realistic diagram).
    var fx_buf: [128]f64 = undefined;
    var fy_buf: [128]f64 = undefined;
    const n = @min(labels.len, 128);

    var step = initial_step;

    var iter: usize = 0;
    while (iter < max_iterations) : (iter += 1) {
        // Zero forces
        for (0..n) |i| {
            fx_buf[i] = 0;
            fy_buf[i] = 0;
        }

        // --- 1. Spring attraction to original position -----------------
        for (0..n) |i| {
            const dx = labels[i].orig_x - labels[i].x;
            const dy = labels[i].orig_y - labels[i].y;
            fx_buf[i] += dx * spring_k;
            fy_buf[i] += dy * spring_k;
        }

        // --- 2. Label–label repulsion ----------------------------------
        for (0..n) |i| {
            for (i + 1..n) |j| {
                if (!labelsOverlap(labels[i], labels[j])) continue;

                const depth = overlapDepth(labels[i], labels[j]);
                if (depth.x <= 0 or depth.y <= 0) continue;

                var push_x: f64 = 0;
                var push_y: f64 = 0;

                const avg_tan_x_raw = labels[i].tangent_x + labels[j].tangent_x;
                const avg_tan_y_raw = labels[i].tangent_y + labels[j].tangent_y;
                const avg_tan_len = @sqrt(avg_tan_x_raw * avg_tan_x_raw + avg_tan_y_raw * avg_tan_y_raw);

                if (avg_tan_len > 0.001) {
                    const avg_tan_x = avg_tan_x_raw / avg_tan_len;
                    const avg_tan_y = avg_tan_y_raw / avg_tan_len;

                    if (@abs(avg_tan_x) >= @abs(avg_tan_y)) {
                        const dir: f64 = if (labels[i].x <= labels[j].x) -1.0 else 1.0;
                        push_x = dir * depth.x;
                    } else {
                        const dir: f64 = if (labels[i].y <= labels[j].y) -1.0 else 1.0;
                        push_y = dir * depth.y;
                    }
                } else if (depth.x < depth.y) {
                    push_x = if (labels[i].x < labels[j].x) -depth.x else depth.x;
                } else {
                    push_y = if (labels[i].y < labels[j].y) -depth.y else depth.y;
                }

                // If both labels are at the exact same position, use the
                // edge tangent perpendicular as a tie-breaker.
                if (@abs(push_x) < 0.001 and @abs(push_y) < 0.001) {
                    push_x = -labels[i].tangent_y;
                    push_y = labels[i].tangent_x;
                    const plen = @sqrt(push_x * push_x + push_y * push_y);
                    if (plen > 0.001) {
                        push_x = push_x / plen * 8.0;
                        push_y = push_y / plen * 8.0;
                    } else {
                        push_x = 8.0;
                        push_y = 0;
                    }
                }

                const half = repel_strength * 0.5;
                fx_buf[i] += push_x * half;
                fy_buf[i] += push_y * half;
                fx_buf[j] -= push_x * half;
                fy_buf[j] -= push_y * half;
            }
        }

        // --- 3. Label–node repulsion -----------------------------------
        for (0..n) |i| {
            for (node_rects) |nr| {
                // AABB overlap test
                const ox = (labels[i].half_w + nr.hw) - @abs(labels[i].x - nr.cx);
                const oy = (labels[i].half_h + nr.hh) - @abs(labels[i].y - nr.cy);
                if (ox <= 0 or oy <= 0) continue;

                // Push label out along minimum-penetration axis
                if (ox < oy) {
                    const dir: f64 = if (labels[i].x < nr.cx) -1.0 else 1.0;
                    fx_buf[i] += dir * ox * node_repel_strength;
                } else {
                    const dir: f64 = if (labels[i].y < nr.cy) -1.0 else 1.0;
                    fy_buf[i] += dir * oy * node_repel_strength;
                }
            }
        }

        // --- Apply forces with current step size -----------------------
        var max_disp: f64 = 0;
        for (0..n) |i| {
            const dx = fx_buf[i] * step;
            const dy = fy_buf[i] * step;
            labels[i].x += dx;
            labels[i].y += dy;
            const disp = @abs(dx) + @abs(dy);
            if (disp > max_disp) max_disp = disp;
        }

        // --- Check convergence ----------------------------------------
        if (max_disp < convergence_threshold) break;

        // --- Decay step size ------------------------------------------
        step *= damping;
    }

    if (node_rects.len == 0) return;

    var min_x = node_rects[0].cx - node_rects[0].hw;
    var max_x = node_rects[0].cx + node_rects[0].hw;
    for (node_rects[1..]) |nr| {
        min_x = @min(min_x, nr.cx - nr.hw);
        max_x = @max(max_x, nr.cx + nr.hw);
    }

    for (labels) |*lbl| {
        lbl.x = std.math.clamp(lbl.x, min_x + lbl.half_w, max_x - lbl.half_w);
    }

    applyHorizontalNodeClearance(labels, node_rects, min_x, max_x);
}

fn applyHorizontalNodeClearance(
    labels: []LabelPlacement,
    node_rects: []const NodeRect,
    min_x: f64,
    max_x: f64,
) void {
    const clearance: f64 = 10.0;

    var pass: usize = 0;
    while (pass < 6) : (pass += 1) {
        var moved = false;

        for (labels) |*lbl| {
            for (node_rects) |nr| {
                const vertical_gap = @abs(lbl.y - nr.cy) - (lbl.half_h + nr.hh);
                if (vertical_gap > 6.0) continue;

                const node_left = nr.cx - nr.hw;
                const node_right = nr.cx + nr.hw;
                const label_left = lbl.x - lbl.half_w;
                const label_right = lbl.x + lbl.half_w;

                const target_left_x = node_left - clearance - lbl.half_w;
                const target_right_x = node_right + clearance + lbl.half_w;

                const overlaps_horizontally = label_right > node_left and label_left < node_right;
                const too_close_left = label_right <= node_left and (node_left - label_right) < clearance;
                const too_close_right = label_left >= node_right and (label_left - node_right) < clearance;

                if (overlaps_horizontally or too_close_left or too_close_right) {
                    const dist_left = @abs(lbl.orig_x - target_left_x);
                    const dist_right = @abs(lbl.orig_x - target_right_x);
                    const target_x = if (dist_left <= dist_right) target_left_x else target_right_x;
                    const clamped_x = std.math.clamp(target_x, min_x + lbl.half_w, max_x - lbl.half_w);

                    if (@abs(clamped_x - lbl.x) > 0.1) {
                        lbl.x = clamped_x;
                        moved = true;
                    }
                }
            }
        }

        if (!moved) break;
    }
}

/// Build the node-rect list and run the force-directed solver.
pub fn resolveLabelPlacements(
    allocator: Allocator,
    labels: []LabelPlacement,
    graph: *Graph,
    offset_x: f64,
    offset_y: f64,
) !void {
    // Snapshot original positions into the label structs (they were set
    // when the label was first placed; copy to orig_x/orig_y now so
    // the solver can use them as spring anchors).
    for (labels) |*lbl| {
        lbl.orig_x = lbl.x;
        lbl.orig_y = lbl.y;
    }

    // Collect non-dummy node AABBs for collision avoidance.
    const node_ids = try graph.allNodes(allocator);
    defer {
        for (node_ids) |id| allocator.free(id);
        allocator.free(node_ids);
    }

    var rects = std.ArrayListUnmanaged(NodeRect){};
    defer rects.deinit(allocator);

    for (node_ids) |id| {
        const node = graph.getNode(id) orelse continue;
        if (node.dummy) continue;
        if (node.is_subgraph) continue;
        try rects.append(allocator, .{
            .cx = node.x + offset_x,
            .cy = node.y + offset_y,
            .hw = node.width / 2.0,
            .hh = node.height / 2.0,
        });
    }

    resolveLabelsForceDirected(labels, rects.items);
}

/// Draw all collected labels (called after collision resolution).
fn drawLabels(
    labels: []const LabelPlacement,
    canvas: *Canvas,
    font: *Font,
) !void {
    for (labels) |lbl| {
        // Background box
        const box_x = lbl.x - lbl.half_w;
        const box_y = lbl.y - lbl.half_h;
        canvas.fillRect(box_x, box_y, lbl.half_w * 2.0, lbl.half_h * 2.0, 255, 255, 255, 230);

        // Text centred at the placement position
        const tw = font.measureText(lbl.text, lbl.font_size);
        const text_x: f32 = @floatCast(lbl.x - @as(f64, @floatCast(tw)) / 2.0);
        const text_y: f32 = @floatCast(lbl.y);

        try font.drawText(
            canvas,
            lbl.text,
            text_x,
            text_y,
            lbl.font_size,
            lbl.color[0],
            lbl.color[1],
            lbl.color[2],
            lbl.color[3],
        );
    }
}

/// Render a graph to a PNG file
pub fn renderGraphToPNG(
    allocator: Allocator,
    graph: *Graph,
    filename: []const u8,
    config: RenderConfig,
) !void {
    return renderGraphToPNGWithFont(allocator, graph, filename, config, null);
}

/// Render a graph to a PNG file with optional font
pub fn renderGraphToPNGWithFont(
    allocator: Allocator,
    graph: *Graph,
    filename: []const u8,
    config: RenderConfig,
    font: ?*Font,
) !void {
    // Calculate bounding box
    const bounds = try calculateBounds(allocator, graph, config);

    // Create canvas with padding and HD scale
    const canvas_width = @as(usize, @intFromFloat(bounds.width + config.padding * 2));
    const canvas_height = @as(usize, @intFromFloat(bounds.height + config.padding * 2));

    var canvas = try Canvas.initWithScale(allocator, canvas_width, canvas_height, config.scale_factor);
    defer canvas.deinit();

    // Calculate offset to center the graph
    const offset_x = config.padding - bounds.min_x;
    const offset_y = config.padding - bounds.min_y;

    // Draw subgraph boxes first (behind everything)
    try drawSubgraphs(allocator, graph, &canvas, offset_x, offset_y, config, font);

    // Draw edges (behind nodes but on top of subgraph boxes)
    try drawEdges(allocator, graph, &canvas, offset_x, offset_y, config, font);

    // Draw nodes on top
    try drawNodes(allocator, graph, &canvas, offset_x, offset_y, config, font);

    // Save to file
    try canvas.saveToPNG(filename);
}

/// Configuration for rendering
pub const RenderConfig = struct {
    padding: f64 = 20.0,
    scale_factor: f64 = 2.0, // HD rendering: 2.0 for retina, 3.0 for ultra-HD
    node_fill_color: [4]u8 = .{ 200, 220, 255, 255 }, // Light blue
    node_stroke_color: [4]u8 = .{ 50, 100, 200, 255 }, // Dark blue
    node_stroke_width: i32 = 2,
    edge_color: [4]u8 = .{ 100, 100, 100, 255 }, // Gray
    edge_width: i32 = 2,
    text_color: [4]u8 = .{ 0, 0, 0, 255 }, // Black
    text_size: f32 = 14.0,
    arrow_size: f64 = 10.0, // Arrowhead size in pixels

    // Subgraph styling
    subgraph_fill_color: [4]u8 = .{ 245, 245, 250, 255 }, // Very light gray-blue
    subgraph_stroke_color: [4]u8 = .{ 140, 140, 170, 255 }, // Medium gray-blue
    subgraph_stroke_width: i32 = 2,
    subgraph_title_color: [4]u8 = .{ 60, 60, 80, 255 }, // Dark gray-blue
    subgraph_corner_radius: f64 = 8.0, // Rounded corner radius
};

pub const Bounds = struct {
    min_x: f64,
    min_y: f64,
    max_x: f64,
    max_y: f64,
    width: f64,
    height: f64,
};

pub fn calculateBounds(allocator: Allocator, graph: *Graph, config: RenderConfig) !Bounds {
    const nodes = try graph.allNodes(allocator);
    defer {
        for (nodes) |id| allocator.free(id);
        allocator.free(nodes);
    }

    if (nodes.len == 0) {
        return Bounds{
            .min_x = 0,
            .min_y = 0,
            .max_x = 100,
            .max_y = 100,
            .width = 100,
            .height = 100,
        };
    }

    var min_x: f64 = std.math.floatMax(f64);
    var min_y: f64 = std.math.floatMax(f64);
    var max_x: f64 = -std.math.floatMax(f64);
    var max_y: f64 = -std.math.floatMax(f64);

    for (nodes) |id| {
        if (graph.getNode(id)) |node| {
            // Skip dummy nodes for bounds calculation — they are routing
            // artifacts, not visual elements.  However their positions still
            // influence edge routing, so we include them to make sure bend
            // points are within the canvas.
            const w = if (node.dummy) @as(f64, 0) else node.width;
            const h = if (node.dummy) @as(f64, 0) else node.height;

            const left = node.x - w / 2.0;
            const right = node.x + w / 2.0;
            const top = node.y - h / 2.0;
            const bottom = node.y + h / 2.0;

            if (left < min_x) min_x = left;
            if (right > max_x) max_x = right;
            if (top < min_y) min_y = top;
            if (bottom > max_y) max_y = bottom;
        }
    }

    // Add extra padding for edge arrows/labels
    const extra = config.padding / 2;
    min_x -= extra;
    min_y -= extra;
    max_x += extra;
    max_y += extra;

    return Bounds{
        .min_x = min_x,
        .min_y = min_y,
        .max_x = max_x,
        .max_y = max_y,
        .width = max_x - min_x,
        .height = max_y - min_y,
    };
}

// ---------------------------------------------------------------------------
// Geometry helpers
// ---------------------------------------------------------------------------

pub const Vec2 = struct {
    x: f64,
    y: f64,

    pub fn lerp(a: Vec2, b: Vec2, t: f64) Vec2 {
        return .{ .x = a.x + (b.x - a.x) * t, .y = a.y + (b.y - a.y) * t };
    }

    pub fn dist(a: Vec2, b: Vec2) f64 {
        const dx = b.x - a.x;
        const dy = b.y - a.y;
        return @sqrt(dx * dx + dy * dy);
    }
};

/// Walk along a polyline of sampled points and return the point that is
/// `target_dist` pixels from the start (measured as arc-length along the
/// curve).  If the total curve is shorter than `target_dist`, returns the
/// midpoint instead.
pub fn pointAlongCurve(pts: []const Vec2, target_dist: f64) Vec2 {
    if (pts.len < 2) return pts[0];

    // Compute total arc length first so we can fall back to midpoint.
    var total_len: f64 = 0;
    for (0..pts.len - 1) |i| {
        total_len += Vec2.dist(pts[i], pts[i + 1]);
    }

    // If the edge is short, place label at the midpoint.
    if (total_len < target_dist * 2.0) {
        return pts[pts.len / 2];
    }

    // Walk forward until we've covered target_dist.
    var accum: f64 = 0;
    for (0..pts.len - 1) |i| {
        const seg_len = Vec2.dist(pts[i], pts[i + 1]);
        if (accum + seg_len >= target_dist) {
            // Interpolate within this segment.
            const remainder = target_dist - accum;
            const t = if (seg_len > 0.001) remainder / seg_len else 0.5;
            return Vec2.lerp(pts[i], pts[i + 1], t);
        }
        accum += seg_len;
    }

    // Fallback (shouldn't reach here).
    return pts[pts.len / 2];
}

// ---------------------------------------------------------------------------
// Catmull-Rom spline helpers
// ---------------------------------------------------------------------------

/// Evaluate a Catmull-Rom spline segment defined by four control points
/// (p0, p1, p2, p3) at parameter t ∈ [0, 1].  The curve passes through
/// p1 (at t=0) and p2 (at t=1), with p0 and p3 influencing the tangents.
/// `alpha` controls spline tension (0.5 = centripetal, good default).
pub fn catmullRomPoint(p0: Vec2, p1: Vec2, p2: Vec2, p3: Vec2, t: f64) Vec2 {
    const t2 = t * t;
    const t3 = t2 * t;

    // Standard Catmull-Rom basis matrix (alpha = 0.5)
    const a = 0.5;

    const x = a * ((2.0 * p1.x) +
        (-p0.x + p2.x) * t +
        (2.0 * p0.x - 5.0 * p1.x + 4.0 * p2.x - p3.x) * t2 +
        (-p0.x + 3.0 * p1.x - 3.0 * p2.x + p3.x) * t3);

    const y = a * ((2.0 * p1.y) +
        (-p0.y + p2.y) * t +
        (2.0 * p0.y - 5.0 * p1.y + 4.0 * p2.y - p3.y) * t2 +
        (-p0.y + 3.0 * p1.y - 3.0 * p2.y + p3.y) * t3);

    return .{ .x = x, .y = y };
}

/// Estimate the number of subdivisions needed for a Catmull-Rom span by
/// sampling curvature at a few points.  Returns a value between
/// `min_segs` and `max_segs`.
///
/// The heuristic works by evaluating the spline at 0.0, 0.25, 0.5, 0.75,
/// and 1.0 and measuring the maximum angular deviation between consecutive
/// chord segments.  Larger angles ⇒ more subdivisions.
fn adaptiveSegments(p0: Vec2, p1: Vec2, p2: Vec2, p3: Vec2) usize {
    const min_segs: usize = 4;
    const max_segs: usize = 24;

    // Sample 5 evenly-spaced points on the span.
    const s0 = catmullRomPoint(p0, p1, p2, p3, 0.0);
    const s1 = catmullRomPoint(p0, p1, p2, p3, 0.25);
    const s2 = catmullRomPoint(p0, p1, p2, p3, 0.5);
    const s3 = catmullRomPoint(p0, p1, p2, p3, 0.75);
    const s4 = catmullRomPoint(p0, p1, p2, p3, 1.0);

    const samples = [_]Vec2{ s0, s1, s2, s3, s4 };

    // Measure the maximum angular deviation between consecutive chords.
    var max_angle: f64 = 0;
    for (0..3) |k| {
        const ax = samples[k + 1].x - samples[k].x;
        const ay = samples[k + 1].y - samples[k].y;
        const bx = samples[k + 2].x - samples[k + 1].x;
        const by = samples[k + 2].y - samples[k + 1].y;

        const dot = ax * bx + ay * by;
        const cross = ax * by - ay * bx;
        const angle = @abs(std.math.atan2(cross, dot)); // radians

        if (angle > max_angle) max_angle = angle;
    }

    // Also factor in the chord length — longer spans need more samples
    // even if they're almost straight, to keep segment pixel-length bounded.
    const chord_len = Vec2.dist(p1, p2);
    const len_segs: usize = @intFromFloat(@ceil(chord_len / 40.0)); // ~1 sample per 40px

    // Map angle to segment count:  0 rad → min_segs,  π rad → max_segs.
    const angle_ratio = @min(max_angle / std.math.pi, 1.0);
    const angle_segs: usize = @intFromFloat(@ceil(
        @as(f64, @floatFromInt(min_segs)) +
            angle_ratio * @as(f64, @floatFromInt(max_segs - min_segs)),
    ));

    return @min(max_segs, @max(min_segs, @max(angle_segs, len_segs)));
}

/// Tessellate a polyline of waypoints into a smooth Catmull-Rom spline.
/// Returns a densely-sampled list of points.  The caller must free the
/// returned list with `allocator`.
///
/// For 2-point polylines (straight edges) this just returns those 2 points.
/// For 3+ point polylines it adaptively samples each span based on
/// curvature — fewer samples for nearly-straight segments, more for sharp
/// bends — producing a smooth curve that passes through every original
/// waypoint.
pub fn tessellateSpline(
    allocator: std.mem.Allocator,
    waypoints: []const Vec2,
) !std.ArrayListUnmanaged(Vec2) {
    var result = std.ArrayListUnmanaged(Vec2){};
    errdefer result.deinit(allocator);

    if (waypoints.len < 2) return result;

    // Straight edge — no interpolation needed.
    if (waypoints.len == 2) {
        try result.append(allocator, waypoints[0]);
        try result.append(allocator, waypoints[1]);
        return result;
    }

    // For each span (p[i] → p[i+1]), evaluate the Catmull-Rom curve using
    // the surrounding four points.  At the boundaries we duplicate the
    // first/last point to provide the needed tangent reference.
    const n = waypoints.len;
    for (0..n - 1) |i| {
        const p0 = if (i == 0) waypoints[0] else waypoints[i - 1];
        const p1 = waypoints[i];
        const p2 = waypoints[i + 1];
        const p3 = if (i + 2 < n) waypoints[i + 2] else waypoints[n - 1];

        // Always include the span start point (avoid duplicates for i > 0).
        if (i == 0) {
            try result.append(allocator, p1);
        }

        // Adaptively choose the number of subdivisions for this span.
        const segs = adaptiveSegments(p0, p1, p2, p3);

        for (1..segs + 1) |s| {
            const t = @as(f64, @floatFromInt(s)) / @as(f64, @floatFromInt(segs));
            try result.append(allocator, catmullRomPoint(p0, p1, p2, p3, t));
        }
    }

    return result;
}

/// Clip a line segment (from `src` toward `dst`) against a rectangle centered
/// at (`cx`, `cy`) with half-extents `hw` and `hh`.  Returns the intersection
/// point on the rectangle border closest to `src`.
///
/// If the line has zero length or no intersection is found, returns the
/// centre of the rectangle as a fallback.
pub fn clipLineToRect(src: Vec2, dst: Vec2, cx: f64, cy: f64, hw: f64, hh: f64) Vec2 {
    const dx = src.x - dst.x;
    const dy = src.y - dst.y;

    if (@abs(dx) < 0.0001 and @abs(dy) < 0.0001) {
        return .{ .x = cx, .y = cy };
    }

    // We test four edges of the rectangle and pick the intersection with the
    // smallest positive parameter `t` (closest to `dst`, the centre).
    var best_t: f64 = std.math.floatMax(f64);
    var best: Vec2 = .{ .x = cx, .y = cy };

    // Right edge  (x = cx + hw)
    if (@abs(dx) > 0.0001) {
        const t = (cx + hw - dst.x) / dx;
        if (t >= 0.0 and t <= 1.0) {
            const iy = dst.y + t * dy;
            if (iy >= cy - hh and iy <= cy + hh and t < best_t) {
                best_t = t;
                best = .{ .x = cx + hw, .y = iy };
            }
        }
    }
    // Left edge  (x = cx - hw)
    if (@abs(dx) > 0.0001) {
        const t = (cx - hw - dst.x) / dx;
        if (t >= 0.0 and t <= 1.0) {
            const iy = dst.y + t * dy;
            if (iy >= cy - hh and iy <= cy + hh and t < best_t) {
                best_t = t;
                best = .{ .x = cx - hw, .y = iy };
            }
        }
    }
    // Bottom edge (y = cy + hh)
    if (@abs(dy) > 0.0001) {
        const t = (cy + hh - dst.y) / dy;
        if (t >= 0.0 and t <= 1.0) {
            const ix = dst.x + t * dx;
            if (ix >= cx - hw and ix <= cx + hw and t < best_t) {
                best_t = t;
                best = .{ .x = ix, .y = cy + hh };
            }
        }
    }
    // Top edge (y = cy - hh)
    if (@abs(dy) > 0.0001) {
        const t = (cy - hh - dst.y) / dy;
        if (t >= 0.0 and t <= 1.0) {
            const ix = dst.x + t * dx;
            if (ix >= cx - hw and ix <= cx + hw and t < best_t) {
                best_t = t;
                best = .{ .x = ix, .y = cy - hh };
            }
        }
    }

    return best;
}

/// Clip a line segment against an ellipse centered at (`cx`, `cy`) with
/// radii `hw` (horizontal) and `hh` (vertical).  Returns the border point
/// closest to `src`.
pub fn clipLineToEllipse(src: Vec2, dst: Vec2, cx: f64, cy: f64, hw: f64, hh: f64) Vec2 {
    // Direction from dst (centre) toward src.
    const dx = src.x - dst.x;
    const dy = src.y - dst.y;
    const len = @sqrt(dx * dx + dy * dy);
    if (len < 0.0001) return .{ .x = cx, .y = cy };

    // Normalise and scale by radii to find border point.
    const nx = dx / len;
    const ny = dy / len;

    // Parametric: point on ellipse in direction (nx, ny) is at
    //   t where (t*nx/hw)^2 + (t*ny/hh)^2 = 1
    //   t = 1 / sqrt((nx/hw)^2 + (ny/hh)^2)
    const ex = nx / hw;
    const ey = ny / hh;
    const denom = @sqrt(ex * ex + ey * ey);
    if (denom < 0.0001) return .{ .x = cx, .y = cy };
    const t = 1.0 / denom;

    return .{ .x = cx + nx * t, .y = cy + ny * t };
}

/// Clip a line segment against a diamond (rhombus) centered at (`cx`, `cy`)
/// with half-widths `hw` and `hh`.  The four edges are:
///   top-right:    x/hw + y/(-hh) = 1  (from top to right)
///   bottom-right: x/hw + y/hh   = 1  (from right to bottom)
///   bottom-left: -x/hw + y/hh   = 1  (from bottom to left)
///   top-left:    -x/hw + y/(-hh)= 1  (from left to top)
pub fn clipLineToDiamond(src: Vec2, dst: Vec2, cx: f64, cy: f64, hw: f64, hh: f64) Vec2 {
    const dx = src.x - dst.x;
    const dy = src.y - dst.y;
    if (@abs(dx) < 0.0001 and @abs(dy) < 0.0001) {
        return .{ .x = cx, .y = cy };
    }

    // The diamond boundary in local coords (relative to centre) satisfies
    // |lx|/hw + |ly|/hh <= 1.  We find the intersection of the ray from
    // centre toward src with this boundary.
    const dir_x = src.x - cx;
    const dir_y = src.y - cy;
    const dir_len = @sqrt(dir_x * dir_x + dir_y * dir_y);
    if (dir_len < 0.0001) return .{ .x = cx, .y = cy };

    const nx = dir_x / dir_len;
    const ny = dir_y / dir_len;

    // t where |t*nx|/hw + |t*ny|/hh = 1  →  t = 1/(|nx|/hw + |ny|/hh)
    const denom = @abs(nx) / hw + @abs(ny) / hh;
    if (denom < 0.0001) return .{ .x = cx, .y = cy };
    const t = 1.0 / denom;

    return .{ .x = cx + nx * t, .y = cy + ny * t };
}

/// Shape-aware edge clipping: dispatches to the correct clipping function
/// based on the node's shape.
pub fn clipLineToShape(src: Vec2, dst: Vec2, cx: f64, cy: f64, hw: f64, hh: f64, shape: NodeShape) Vec2 {
    return switch (shape) {
        .box, .subroutine => clipLineToRect(src, dst, cx, cy, hw, hh),
        .round, .trapezoid, .trapezoid_alt, .parallelogram, .parallelogram_alt => clipLineToRect(src, dst, cx, cy, hw, hh),
        .circle, .stadium, .cylinder => clipLineToEllipse(src, dst, cx, cy, hw, hh),
        .diamond, .hexagon => clipLineToDiamond(src, dst, cx, cy, hw, hh),
    };
}

// ---------------------------------------------------------------------------
// Polygon drawing helpers (for hexagon, trapezoid, parallelogram, etc.)
// ---------------------------------------------------------------------------

/// Fill a convex polygon defined by its vertices using scanline rasterization.
/// `vertices` is a slice of [2]f64 pairs (x, y) in order around the polygon.
fn drawPolygonFill(
    canvas: *Canvas,
    cx: f64,
    cy: f64,
    vertices: []const [2]f64,
    r: u8,
    g: u8,
    b: u8,
    a: u8,
) void {
    _ = cx;
    _ = cy;
    if (vertices.len < 3) return;

    // Find bounding box
    var min_y: f64 = vertices[0][1];
    var max_y: f64 = vertices[0][1];
    for (vertices) |v| {
        if (v[1] < min_y) min_y = v[1];
        if (v[1] > max_y) max_y = v[1];
    }

    const scale = canvas.scale_factor;
    const sy_start = @as(i32, @intFromFloat(@floor(min_y * scale)));
    const sy_end = @as(i32, @intFromFloat(@ceil(max_y * scale)));

    var scan_y = sy_start;
    while (scan_y <= sy_end) : (scan_y += 1) {
        const fy = @as(f64, @floatFromInt(scan_y)) / scale;

        // Find all x-intersections of the scanline with polygon edges
        var x_ints: [16]f64 = undefined;
        var x_count: usize = 0;

        for (0..vertices.len) |i| {
            const j = (i + 1) % vertices.len;
            const y0 = vertices[i][1];
            const y1 = vertices[j][1];

            // Check if scanline crosses this edge
            if ((y0 <= fy and y1 > fy) or (y1 <= fy and y0 > fy)) {
                const t = (fy - y0) / (y1 - y0);
                const xi = vertices[i][0] + t * (vertices[j][0] - vertices[i][0]);
                if (x_count < x_ints.len) {
                    x_ints[x_count] = xi;
                    x_count += 1;
                }
            }
        }

        // Sort intersections
        if (x_count >= 2) {
            // Simple bubble sort (max 16 elements)
            for (0..x_count) |ii| {
                for (ii + 1..x_count) |jj| {
                    if (x_ints[jj] < x_ints[ii]) {
                        const tmp = x_ints[ii];
                        x_ints[ii] = x_ints[jj];
                        x_ints[jj] = tmp;
                    }
                }
            }

            // Fill between pairs
            var p: usize = 0;
            while (p + 1 < x_count) : (p += 2) {
                const sx0 = @as(i32, @intFromFloat(@ceil(x_ints[p] * scale)));
                const sx1 = @as(i32, @intFromFloat(@floor(x_ints[p + 1] * scale)));
                var sx = sx0;
                while (sx <= sx1) : (sx += 1) {
                    canvas.setPixel(sx, scan_y, r, g, b, a);
                }
            }
        }
    }
}

/// Stroke (outline) a polygon defined by its vertices.
fn drawPolygonStroke(
    canvas: *Canvas,
    cx: f64,
    cy: f64,
    vertices: []const [2]f64,
    thickness: i32,
    r: u8,
    g: u8,
    b: u8,
    a: u8,
) void {
    _ = cx;
    _ = cy;
    if (vertices.len < 2) return;

    for (0..vertices.len) |i| {
        const j = (i + 1) % vertices.len;
        canvas.drawLine(
            vertices[i][0],
            vertices[i][1],
            vertices[j][0],
            vertices[j][1],
            thickness,
            r,
            g,
            b,
            a,
        );
    }
}

// ---------------------------------------------------------------------------
// Polyline shortening (for clean arrowhead connections)
// ---------------------------------------------------------------------------

/// Shorten a polyline from its **end** by `amount` pixels (arc-length).
/// The last point is moved inward along the curve so the line stops at the
/// base of an arrowhead rather than running through its tip.
pub fn shortenPolylineEnd(points: *std.ArrayListUnmanaged(Vec2), amount: f64) void {
    if (points.items.len < 2) return;
    var remaining = amount;
    while (points.items.len >= 2) {
        const last = points.items[points.items.len - 1];
        const prev = points.items[points.items.len - 2];
        const dx = last.x - prev.x;
        const dy = last.y - prev.y;
        const seg_len = @sqrt(dx * dx + dy * dy);

        if (seg_len >= remaining and seg_len > 0.001) {
            // Interpolate within this segment
            const t = remaining / seg_len;
            points.items[points.items.len - 1] = .{
                .x = last.x - dx * t,
                .y = last.y - dy * t,
            };
            return;
        }
        // Entire segment is within the arrow zone — remove the last point
        remaining -= seg_len;
        points.items.len -= 1;
    }
}

/// Shorten a polyline from its **start** by `amount` pixels (arc-length).
/// The first point is moved forward along the curve so the line begins at
/// the base of a source-side arrowhead.
pub fn shortenPolylineStart(points: *std.ArrayListUnmanaged(Vec2), amount: f64) void {
    if (points.items.len < 2) return;
    var remaining = amount;
    while (points.items.len >= 2) {
        const first = points.items[0];
        const second = points.items[1];
        const dx = second.x - first.x;
        const dy = second.y - first.y;
        const seg_len = @sqrt(dx * dx + dy * dy);

        if (seg_len >= remaining and seg_len > 0.001) {
            // Interpolate within this segment
            const t = remaining / seg_len;
            points.items[0] = .{
                .x = first.x + dx * t,
                .y = first.y + dy * t,
            };
            return;
        }
        // Entire segment is within the arrow zone — remove the first point
        remaining -= seg_len;
        const len = points.items.len;
        std.mem.copyForwards(Vec2, points.items[0 .. len - 1], points.items[1..len]);
        points.items.len -= 1;
    }
}

// ---------------------------------------------------------------------------
// Drawing helpers
// ---------------------------------------------------------------------------

/// Draw a filled triangle (arrowhead) at `tip` pointing in the direction
/// given by the angle from `from` → `tip`.
fn drawArrowhead(
    canvas: *Canvas,
    from: Vec2,
    tip: Vec2,
    size: f64,
    scale: f64,
    r: u8,
    g: u8,
    b: u8,
    a: u8,
) void {
    const dx = tip.x - from.x;
    const dy = tip.y - from.y;
    const len = @sqrt(dx * dx + dy * dy);
    if (len < 0.001) return;

    // Unit vector along the edge direction
    const ux = dx / len;
    const uy = dy / len;

    // Perpendicular
    const px = -uy;
    const py = ux;

    const half_w = size * 0.45; // half-width of the arrowhead base

    // The three vertices of the arrowhead triangle
    const p0x = tip.x; // tip
    const p0y = tip.y;
    const p1x = tip.x - ux * size + px * half_w; // base left
    const p1y = tip.y - uy * size + py * half_w;
    const p2x = tip.x - ux * size - px * half_w; // base right
    const p2y = tip.y - uy * size - py * half_w;

    // Fill the triangle using scanline rasterisation
    fillTriangle(canvas, p0x * scale, p0y * scale, p1x * scale, p1y * scale, p2x * scale, p2y * scale, r, g, b, a);
}

/// Simple filled-triangle rasteriser (scanline).
fn fillTriangle(
    canvas: *Canvas,
    x0: f64,
    y0: f64,
    x1: f64,
    y1: f64,
    x2: f64,
    y2: f64,
    r: u8,
    g: u8,
    b: u8,
    a: u8,
) void {
    // Bounding box
    const min_x_f = @min(x0, @min(x1, x2));
    const max_x_f = @max(x0, @max(x1, x2));
    const min_y_f = @min(y0, @min(y1, y2));
    const max_y_f = @max(y0, @max(y1, y2));

    const min_xi: i32 = @intFromFloat(@floor(min_x_f));
    const max_xi: i32 = @intFromFloat(@ceil(max_x_f));
    const min_yi: i32 = @intFromFloat(@floor(min_y_f));
    const max_yi: i32 = @intFromFloat(@ceil(max_y_f));

    var py: i32 = min_yi;
    while (py <= max_yi) : (py += 1) {
        var px: i32 = min_xi;
        while (px <= max_xi) : (px += 1) {
            const fx = @as(f64, @floatFromInt(px)) + 0.5;
            const fy = @as(f64, @floatFromInt(py)) + 0.5;
            if (pointInTriangle(fx, fy, x0, y0, x1, y1, x2, y2)) {
                canvas.setPixel(px, py, r, g, b, a);
            }
        }
    }
}

/// Barycentric point-in-triangle test.
fn pointInTriangle(px: f64, py: f64, x0: f64, y0: f64, x1: f64, y1: f64, x2: f64, y2: f64) bool {
    const d00 = (x1 - x0) * (x1 - x0) + (y1 - y0) * (y1 - y0);
    const d01 = (x1 - x0) * (x2 - x0) + (y1 - y0) * (y2 - y0);
    const d11 = (x2 - x0) * (x2 - x0) + (y2 - y0) * (y2 - y0);
    const d20 = (px - x0) * (x1 - x0) + (py - y0) * (y1 - y0);
    const d21 = (px - x0) * (x2 - x0) + (py - y0) * (y2 - y0);

    const denom = d00 * d11 - d01 * d01;
    if (@abs(denom) < 1e-10) return false;

    const u = (d11 * d20 - d01 * d21) / denom;
    const v = (d00 * d21 - d01 * d20) / denom;

    return (u >= -0.01) and (v >= -0.01) and (u + v <= 1.01);
}

// ---------------------------------------------------------------------------
// Subgraph drawing
// ---------------------------------------------------------------------------

/// Draw subgraph boxes (containers) behind all other elements.
/// Subgraphs are drawn deepest-first so nested boxes layer correctly.
fn drawSubgraphs(
    allocator: Allocator,
    graph: *Graph,
    canvas: *Canvas,
    offset_x: f64,
    offset_y: f64,
    config: RenderConfig,
    font: ?*Font,
) !void {
    const nodes = try graph.allNodes(allocator);
    defer {
        for (nodes) |id| allocator.free(id);
        allocator.free(nodes);
    }

    // Collect subgraph nodes and sort by nesting depth (deepest first) so
    // inner boxes are drawn on top of outer boxes.
    const SubgraphEntry = struct {
        id: []const u8,
        depth: usize,
    };

    var subgraphs = std.ArrayListUnmanaged(SubgraphEntry){};
    defer subgraphs.deinit(allocator);

    for (nodes) |id| {
        const node = graph.getNode(id) orelse continue;
        if (!node.is_subgraph) continue;
        if (node.width < 0.1) continue; // not sized — skip

        // Compute nesting depth by walking parent chain.
        var depth: usize = 0;
        var cursor: ?[]const u8 = graph.getParent(id);
        while (cursor) |parent_id| {
            depth += 1;
            cursor = graph.getParent(parent_id);
        }

        try subgraphs.append(allocator, .{ .id = id, .depth = depth });
    }

    // Sort: shallowest first (outermost drawn first, so inner overlays on top).
    std.mem.sort(SubgraphEntry, subgraphs.items, {}, struct {
        fn lessThan(_: void, a: SubgraphEntry, b: SubgraphEntry) bool {
            return a.depth < b.depth;
        }
    }.lessThan);

    // Varying tint per nesting depth for visual distinction.
    const depth_tints = [_][4]u8{
        .{ 245, 245, 250, 255 }, // depth 0 — lightest
        .{ 235, 240, 250, 255 }, // depth 1
        .{ 225, 235, 248, 255 }, // depth 2
        .{ 218, 228, 245, 255 }, // depth 3+
    };

    for (subgraphs.items) |entry| {
        const node = graph.getNode(entry.id) orelse continue;

        const x = node.x + offset_x - node.width / 2.0;
        const y = node.y + offset_y - node.height / 2.0;
        const w = node.width;
        const h = node.height;

        // Pick fill tint based on depth.
        const tint_idx = @min(entry.depth, depth_tints.len - 1);
        const fill = depth_tints[tint_idx];

        const r = config.subgraph_corner_radius;

        // Draw rounded-rectangle fill.
        drawRoundedRectFill(canvas, x, y, w, h, r, fill[0], fill[1], fill[2], fill[3]);

        // Draw rounded-rectangle stroke.
        drawRoundedRectStroke(
            canvas,
            x,
            y,
            w,
            h,
            r,
            config.subgraph_stroke_width,
            config.subgraph_stroke_color[0],
            config.subgraph_stroke_color[1],
            config.subgraph_stroke_color[2],
            config.subgraph_stroke_color[3],
        );

        // Draw title label at the top-left of the box.
        if (font) |f| {
            const title_text = node.subgraph_title orelse (node.label orelse entry.id);
            if (title_text.len > 0) {
                const title_size = config.text_size * 0.9;
                const title_x: f32 = @floatCast(x + r + 6.0);
                const title_y: f32 = @floatCast(y + 22.0);

                try f.drawText(
                    canvas,
                    title_text,
                    title_x,
                    title_y,
                    title_size,
                    config.subgraph_title_color[0],
                    config.subgraph_title_color[1],
                    config.subgraph_title_color[2],
                    config.subgraph_title_color[3],
                );
            }
        }
    }
}

/// Fill a rounded rectangle.  Uses the simple approach of filling the
/// interior rect plus four corner-circle quadrants.
fn drawRoundedRectFill(
    canvas: *Canvas,
    x: f64,
    y: f64,
    w: f64,
    h: f64,
    radius: f64,
    r: u8,
    g: u8,
    b: u8,
    a: u8,
) void {
    const scale = canvas.scale_factor;
    const sx = x * scale;
    const sy = y * scale;
    const sw = w * scale;
    const sh = h * scale;
    const sr = radius * scale;

    // Fill main body (three rectangles to avoid corners).
    // Horizontal strip (full width, excluding top/bottom radius bands).
    {
        const iy_start: i32 = @intFromFloat(@floor(sy + sr));
        const iy_end: i32 = @intFromFloat(@ceil(sy + sh - sr));
        const ix_start: i32 = @intFromFloat(@floor(sx));
        const ix_end: i32 = @intFromFloat(@ceil(sx + sw));
        var iy: i32 = iy_start;
        while (iy < iy_end) : (iy += 1) {
            var ix: i32 = ix_start;
            while (ix < ix_end) : (ix += 1) {
                canvas.setPixel(ix, iy, r, g, b, a);
            }
        }
    }
    // Top strip (between corners).
    {
        const iy_start: i32 = @intFromFloat(@floor(sy));
        const iy_end: i32 = @intFromFloat(@ceil(sy + sr));
        const ix_start: i32 = @intFromFloat(@floor(sx + sr));
        const ix_end: i32 = @intFromFloat(@ceil(sx + sw - sr));
        var iy: i32 = iy_start;
        while (iy < iy_end) : (iy += 1) {
            var ix: i32 = ix_start;
            while (ix < ix_end) : (ix += 1) {
                canvas.setPixel(ix, iy, r, g, b, a);
            }
        }
    }
    // Bottom strip (between corners).
    {
        const iy_start: i32 = @intFromFloat(@floor(sy + sh - sr));
        const iy_end: i32 = @intFromFloat(@ceil(sy + sh));
        const ix_start: i32 = @intFromFloat(@floor(sx + sr));
        const ix_end: i32 = @intFromFloat(@ceil(sx + sw - sr));
        var iy: i32 = iy_start;
        while (iy < iy_end) : (iy += 1) {
            var ix: i32 = ix_start;
            while (ix < ix_end) : (ix += 1) {
                canvas.setPixel(ix, iy, r, g, b, a);
            }
        }
    }
    // Four corner quadrants (filled circle sectors).
    const corners = [_][2]f64{
        .{ sx + sr, sy + sr }, // top-left
        .{ sx + sw - sr, sy + sr }, // top-right
        .{ sx + sr, sy + sh - sr }, // bottom-left
        .{ sx + sw - sr, sy + sh - sr }, // bottom-right
    };
    for (corners) |center| {
        const cx = center[0];
        const cy = center[1];
        const iy_start: i32 = @intFromFloat(@floor(cy - sr));
        const iy_end: i32 = @intFromFloat(@ceil(cy + sr));
        var iy: i32 = iy_start;
        while (iy <= iy_end) : (iy += 1) {
            const ix_start: i32 = @intFromFloat(@floor(cx - sr));
            const ix_end: i32 = @intFromFloat(@ceil(cx + sr));
            var ix: i32 = ix_start;
            while (ix <= ix_end) : (ix += 1) {
                const dx = @as(f64, @floatFromInt(ix)) + 0.5 - cx;
                const dy = @as(f64, @floatFromInt(iy)) + 0.5 - cy;
                if (dx * dx + dy * dy <= sr * sr) {
                    canvas.setPixel(ix, iy, r, g, b, a);
                }
            }
        }
    }
}

/// Stroke (outline) a rounded rectangle.
fn drawRoundedRectStroke(
    canvas: *Canvas,
    x: f64,
    y: f64,
    w: f64,
    h: f64,
    radius: f64,
    thickness: i32,
    r: u8,
    g: u8,
    b: u8,
    a: u8,
) void {
    // Top edge
    canvas.drawLine(x + radius, y, x + w - radius, y, thickness, r, g, b, a);
    // Bottom edge
    canvas.drawLine(x + radius, y + h, x + w - radius, y + h, thickness, r, g, b, a);
    // Left edge
    canvas.drawLine(x, y + radius, x, y + h - radius, thickness, r, g, b, a);
    // Right edge
    canvas.drawLine(x + w, y + radius, x + w, y + h - radius, thickness, r, g, b, a);

    // Draw four corner arcs as short line segments.
    const segs: usize = 12;
    const pi_half = std.math.pi / 2.0;

    // Corner centers and start angles (counter-clockwise from 3-o'clock).
    const arc_info = [_]struct { cx: f64, cy: f64, start: f64 }{
        .{ .cx = x + radius, .cy = y + radius, .start = std.math.pi }, // top-left
        .{ .cx = x + w - radius, .cy = y + radius, .start = 3.0 * pi_half }, // top-right
        .{ .cx = x + radius, .cy = y + h - radius, .start = pi_half }, // bottom-left
        .{ .cx = x + w - radius, .cy = y + h - radius, .start = 0.0 }, // bottom-right
    };

    for (arc_info) |arc| {
        var prev_ax = arc.cx + radius * @cos(arc.start);
        var prev_ay = arc.cy + radius * @sin(arc.start);
        for (1..segs + 1) |s| {
            const t = @as(f64, @floatFromInt(s)) / @as(f64, @floatFromInt(segs));
            const angle = arc.start + t * pi_half;
            const ax = arc.cx + radius * @cos(angle);
            const ay = arc.cy + radius * @sin(angle);
            canvas.drawLine(prev_ax, prev_ay, ax, ay, thickness, r, g, b, a);
            prev_ax = ax;
            prev_ay = ay;
        }
    }
}

// ---------------------------------------------------------------------------
// Node drawing
// ---------------------------------------------------------------------------

fn drawNodes(
    allocator: Allocator,
    graph: *Graph,
    canvas: *Canvas,
    offset_x: f64,
    offset_y: f64,
    config: RenderConfig,
    font: ?*Font,
) !void {
    const nodes = try graph.allNodes(allocator);
    defer {
        for (nodes) |id| allocator.free(id);
        allocator.free(nodes);
    }

    for (nodes) |id| {
        if (graph.getNode(id)) |node| {
            // Skip dummy nodes — they are routing artifacts, not real diagram
            // elements.
            if (node.dummy) continue;

            // Skip subgraph nodes — they are drawn as container boxes by
            // drawSubgraphs, not as regular nodes.
            if (node.is_subgraph) continue;

            const cx = node.x + offset_x;
            const cy = node.y + offset_y;
            const x = cx - node.width / 2.0;
            const y = cy - node.height / 2.0;
            const hw = node.width / 2.0;
            const hh = node.height / 2.0;

            // Use custom colors if provided, otherwise use defaults
            const fill_color = node.fill_color orelse config.node_fill_color;
            const stroke_color = node.stroke_color orelse config.node_stroke_color;
            const stroke_width = node.stroke_width orelse config.node_stroke_width;

            switch (node.shape) {
                .box => {
                    // Plain rectangle
                    canvas.fillRect(x, y, node.width, node.height, fill_color[0], fill_color[1], fill_color[2], fill_color[3]);
                    canvas.strokeRect(x, y, node.width, node.height, stroke_width, stroke_color[0], stroke_color[1], stroke_color[2], stroke_color[3]);
                },
                .round => {
                    // Rounded rectangle — corner radius is the smaller of
                    // half the short side or a fixed maximum.
                    const corner_r = @min(@min(hw, hh), 12.0);
                    drawRoundedRectFill(canvas, x, y, node.width, node.height, corner_r, fill_color[0], fill_color[1], fill_color[2], fill_color[3]);
                    drawRoundedRectStroke(canvas, x, y, node.width, node.height, corner_r, stroke_width, stroke_color[0], stroke_color[1], stroke_color[2], stroke_color[3]);
                },
                .circle => {
                    // Ellipse (true circle when width == height).
                    canvas.fillEllipse(cx, cy, hw, hh, fill_color[0], fill_color[1], fill_color[2], fill_color[3]);
                    canvas.strokeEllipse(cx, cy, hw, hh, stroke_width, stroke_color[0], stroke_color[1], stroke_color[2], stroke_color[3]);
                },
                .diamond => {
                    // Diamond / rhombus
                    canvas.fillDiamond(cx, cy, hw, hh, fill_color[0], fill_color[1], fill_color[2], fill_color[3]);
                    canvas.strokeDiamond(cx, cy, hw, hh, stroke_width, stroke_color[0], stroke_color[1], stroke_color[2], stroke_color[3]);
                },
                .hexagon => {
                    // Hexagon — flat top/bottom, pointed sides
                    // Inset on each side is ~1/4 of width
                    const inset = hw * 0.35;
                    drawPolygonFill(canvas, cx, cy, &[_][2]f64{
                        .{ cx - hw + inset, cy - hh }, // top-left
                        .{ cx + hw - inset, cy - hh }, // top-right
                        .{ cx + hw, cy }, // right
                        .{ cx + hw - inset, cy + hh }, // bottom-right
                        .{ cx - hw + inset, cy + hh }, // bottom-left
                        .{ cx - hw, cy }, // left
                    }, fill_color[0], fill_color[1], fill_color[2], fill_color[3]);
                    drawPolygonStroke(canvas, cx, cy, &[_][2]f64{
                        .{ cx - hw + inset, cy - hh },
                        .{ cx + hw - inset, cy - hh },
                        .{ cx + hw, cy },
                        .{ cx + hw - inset, cy + hh },
                        .{ cx - hw + inset, cy + hh },
                        .{ cx - hw, cy },
                    }, stroke_width, stroke_color[0], stroke_color[1], stroke_color[2], stroke_color[3]);
                },
                .cylinder => {
                    // Cylinder (database) — rectangle with elliptical top and bottom caps
                    const cap_h = @min(hh * 0.3, 10.0); // height of the elliptical cap
                    const body_top = cy - hh + cap_h;
                    const body_bot = cy + hh - cap_h;
                    const body_h = body_bot - body_top;
                    // Fill body rectangle
                    canvas.fillRect(cx - hw, body_top, node.width, body_h, fill_color[0], fill_color[1], fill_color[2], fill_color[3]);
                    // Fill top ellipse
                    canvas.fillEllipse(cx, cy - hh + cap_h, hw, cap_h, fill_color[0], fill_color[1], fill_color[2], fill_color[3]);
                    // Fill bottom ellipse
                    canvas.fillEllipse(cx, cy + hh - cap_h, hw, cap_h, fill_color[0], fill_color[1], fill_color[2], fill_color[3]);
                    // Stroke left and right sides
                    canvas.drawLine(cx - hw, body_top, cx - hw, body_bot, stroke_width, stroke_color[0], stroke_color[1], stroke_color[2], stroke_color[3]);
                    canvas.drawLine(cx + hw, body_top, cx + hw, body_bot, stroke_width, stroke_color[0], stroke_color[1], stroke_color[2], stroke_color[3]);
                    // Stroke top ellipse
                    canvas.strokeEllipse(cx, cy - hh + cap_h, hw, cap_h, stroke_width, stroke_color[0], stroke_color[1], stroke_color[2], stroke_color[3]);
                    // Stroke bottom ellipse (only bottom half visible)
                    canvas.strokeEllipse(cx, cy + hh - cap_h, hw, cap_h, stroke_width, stroke_color[0], stroke_color[1], stroke_color[2], stroke_color[3]);
                },
                .stadium => {
                    // Stadium — rectangle with fully rounded (semicircle) ends
                    const corner_r = hh; // full half-height radius gives semicircle caps
                    drawRoundedRectFill(canvas, x, y, node.width, node.height, corner_r, fill_color[0], fill_color[1], fill_color[2], fill_color[3]);
                    drawRoundedRectStroke(canvas, x, y, node.width, node.height, corner_r, stroke_width, stroke_color[0], stroke_color[1], stroke_color[2], stroke_color[3]);
                },
                .trapezoid => {
                    // Trapezoid — wider at bottom, narrower at top
                    const inset = hw * 0.25;
                    drawPolygonFill(canvas, cx, cy, &[_][2]f64{
                        .{ cx - hw + inset, cy - hh }, // top-left (narrower)
                        .{ cx + hw - inset, cy - hh }, // top-right (narrower)
                        .{ cx + hw, cy + hh }, // bottom-right
                        .{ cx - hw, cy + hh }, // bottom-left
                    }, fill_color[0], fill_color[1], fill_color[2], fill_color[3]);
                    drawPolygonStroke(canvas, cx, cy, &[_][2]f64{
                        .{ cx - hw + inset, cy - hh },
                        .{ cx + hw - inset, cy - hh },
                        .{ cx + hw, cy + hh },
                        .{ cx - hw, cy + hh },
                    }, stroke_width, stroke_color[0], stroke_color[1], stroke_color[2], stroke_color[3]);
                },
                .trapezoid_alt => {
                    // Trapezoid alt — wider at top, narrower at bottom
                    const inset = hw * 0.25;
                    drawPolygonFill(canvas, cx, cy, &[_][2]f64{
                        .{ cx - hw, cy - hh }, // top-left
                        .{ cx + hw, cy - hh }, // top-right
                        .{ cx + hw - inset, cy + hh }, // bottom-right (narrower)
                        .{ cx - hw + inset, cy + hh }, // bottom-left (narrower)
                    }, fill_color[0], fill_color[1], fill_color[2], fill_color[3]);
                    drawPolygonStroke(canvas, cx, cy, &[_][2]f64{
                        .{ cx - hw, cy - hh },
                        .{ cx + hw, cy - hh },
                        .{ cx + hw - inset, cy + hh },
                        .{ cx - hw + inset, cy + hh },
                    }, stroke_width, stroke_color[0], stroke_color[1], stroke_color[2], stroke_color[3]);
                },
                .parallelogram => {
                    // Parallelogram — slanted right
                    const slant = hw * 0.25;
                    drawPolygonFill(canvas, cx, cy, &[_][2]f64{
                        .{ cx - hw + slant, cy - hh }, // top-left
                        .{ cx + hw + slant, cy - hh }, // top-right
                        .{ cx + hw - slant, cy + hh }, // bottom-right
                        .{ cx - hw - slant, cy + hh }, // bottom-left
                    }, fill_color[0], fill_color[1], fill_color[2], fill_color[3]);
                    drawPolygonStroke(canvas, cx, cy, &[_][2]f64{
                        .{ cx - hw + slant, cy - hh },
                        .{ cx + hw + slant, cy - hh },
                        .{ cx + hw - slant, cy + hh },
                        .{ cx - hw - slant, cy + hh },
                    }, stroke_width, stroke_color[0], stroke_color[1], stroke_color[2], stroke_color[3]);
                },
                .parallelogram_alt => {
                    // Parallelogram alt — slanted left
                    const slant = hw * 0.25;
                    drawPolygonFill(canvas, cx, cy, &[_][2]f64{
                        .{ cx - hw - slant, cy - hh }, // top-left
                        .{ cx + hw - slant, cy - hh }, // top-right
                        .{ cx + hw + slant, cy + hh }, // bottom-right
                        .{ cx - hw + slant, cy + hh }, // bottom-left
                    }, fill_color[0], fill_color[1], fill_color[2], fill_color[3]);
                    drawPolygonStroke(canvas, cx, cy, &[_][2]f64{
                        .{ cx - hw - slant, cy - hh },
                        .{ cx + hw - slant, cy - hh },
                        .{ cx + hw + slant, cy + hh },
                        .{ cx - hw + slant, cy + hh },
                    }, stroke_width, stroke_color[0], stroke_color[1], stroke_color[2], stroke_color[3]);
                },
                .subroutine => {
                    // Subroutine — rectangle with double vertical lines at left and right
                    canvas.fillRect(x, y, node.width, node.height, fill_color[0], fill_color[1], fill_color[2], fill_color[3]);
                    canvas.strokeRect(x, y, node.width, node.height, stroke_width, stroke_color[0], stroke_color[1], stroke_color[2], stroke_color[3]);
                    // Inner vertical lines at ~10% from each side
                    const inset = @max(hw * 0.15, 6.0);
                    canvas.drawLine(cx - hw + inset, cy - hh, cx - hw + inset, cy + hh, stroke_width, stroke_color[0], stroke_color[1], stroke_color[2], stroke_color[3]);
                    canvas.drawLine(cx + hw - inset, cy - hh, cx + hw - inset, cy + hh, stroke_width, stroke_color[0], stroke_color[1], stroke_color[2], stroke_color[3]);
                },
            }

            // Draw text label if font is available
            if (font) |f| {
                // Use node label if available, otherwise use ID
                const display_text = node.label orelse id;

                // Use per-node text color if set (from style classes), otherwise default
                const label_color = node.text_color orelse config.text_color;

                // Use the node's inner width (minus padding) as the max
                // text width for wrapping.  For non-rectangular shapes the
                // usable area is smaller, so we shrink further.
                const inner_pad: f64 = 28.0; // left+right padding inside node
                const shape_shrink: f64 = switch (node.shape) {
                    .diamond => 0.55,
                    .hexagon => 0.65,
                    .circle => 0.65,
                    .trapezoid, .trapezoid_alt => 0.70,
                    .parallelogram, .parallelogram_alt => 0.70,
                    .subroutine => 0.75,
                    .cylinder => 0.80,
                    .stadium => 0.80,
                    .round, .box => 1.0,
                };
                const max_text_w: f32 = @floatCast(@max(40.0, (node.width - inner_pad) * shape_shrink));

                // Check if text needs wrapping
                const single_w = f.measureText(display_text, config.text_size);

                if (single_w > max_text_w) {
                    // Multi-line wrapped rendering
                    try f.drawWrappedText(
                        canvas,
                        display_text,
                        @floatCast(cx),
                        @floatCast(cy),
                        config.text_size,
                        max_text_w,
                        label_color[0],
                        label_color[1],
                        label_color[2],
                        label_color[3],
                    );
                } else {
                    // Single-line rendering (centred)
                    const centered_x = cx - @as(f64, @floatCast(single_w)) / 2.0;

                    try f.drawText(
                        canvas,
                        display_text,
                        @floatCast(centered_x),
                        @floatCast(cy),
                        config.text_size,
                        label_color[0],
                        label_color[1],
                        label_color[2],
                        label_color[3],
                    );
                }
            }
        }
    }
}

// ---------------------------------------------------------------------------
// Edge drawing
// ---------------------------------------------------------------------------

/// Represents a resolved visual edge: a polyline from a real source node,
/// optionally through dummy bend-points, to a real target node.
pub const VisualEdge = struct {
    /// Waypoints from source to target (including source and target centres).
    points: std.ArrayListUnmanaged(Vec2),
    /// Whether to draw an arrowhead at the target end.
    has_arrow: bool,
    /// Whether to draw an arrowhead at the source end (for bidirectional edges).
    has_source_arrow: bool = false,
    /// Edge color.
    color: [4]u8,
    /// Edge thickness.
    thickness: i32,
    /// Line style (solid, dashed, dotted, thick).
    line_style: LineStyle = .solid,

    fn deinit(self: *VisualEdge, alloc: Allocator) void {
        self.points.deinit(alloc);
    }
};

/// Walk forward from a dummy node along its single outgoing edge to find the
/// next node in the chain.  Returns null if ambiguous or missing.
pub fn nextInChain(graph: *Graph, node_id: []const u8) ?[]const u8 {
    const out = graph.outEdges(node_id) orelse return null;
    if (out.len != 1) return null;
    return out[0].w;
}

fn drawEdges(
    allocator: Allocator,
    graph: *Graph,
    canvas: *Canvas,
    offset_x: f64,
    offset_y: f64,
    config: RenderConfig,
    font: ?*Font,
) !void {
    // Collect label placements so we can resolve collisions after drawing
    // all edge lines.
    var label_placements = std.ArrayListUnmanaged(LabelPlacement){};
    defer label_placements.deinit(allocator);

    // We want to draw each *visual* edge exactly once.  Edges that were split
    // into dummy chains during normalisation should be drawn as a single
    // polyline from the real source to the real target, bending through each
    // intermediate dummy node position.
    //
    // Strategy: iterate all edges in the graph.  If the edge's *source* is a
    // dummy node, skip it — we will reach it when we process the chain's
    // originating non-dummy source.  If the edge's source is a real node, walk
    // the chain forward through any dummy targets collecting waypoints until
    // we reach another real node.

    var iter = graph.edgeIterator();
    while (iter.next()) |entry| {
        const v_node = graph.getNode(entry.v) orelse continue;

        // Only process edges originating from real (non-dummy) nodes.
        if (v_node.dummy) continue;

        const edge_data = graph.edge(entry.v, entry.w, entry.name);

        // Determine colours/thickness/style from edge data or defaults
        const edge_color = if (edge_data) |ed| ed.color orelse config.edge_color else config.edge_color;
        const line_style: LineStyle = if (edge_data) |ed| ed.line_style else .solid;
        const base_thickness = if (edge_data) |ed| ed.thickness orelse config.edge_width else config.edge_width;
        // Thick style doubles the line width
        const edge_thickness = if (line_style == .thick) @max(base_thickness * 2, 3) else base_thickness;
        const has_arrow = if (edge_data) |ed| blk: {
            if (ed.arrowhead) |ah| {
                break :blk !std.mem.eql(u8, ah, "none");
            }
            break :blk true; // default: draw arrow
        } else true;
        const has_source_arrow = if (edge_data) |ed| blk: {
            if (ed.arrowtail) |at| {
                break :blk !std.mem.eql(u8, at, "none");
            }
            break :blk false; // default: no source arrow
        } else false;

        // -----------------------------------------------------------------
        // Self-edge: v == w — draw as a loop arc on the right side
        // -----------------------------------------------------------------
        if (std.mem.eql(u8, entry.v, entry.w)) {
            try drawSelfEdgeLoop(
                allocator,
                canvas,
                v_node,
                offset_x,
                offset_y,
                edge_color,
                edge_thickness,
                has_arrow,
                config,
                font,
                edge_data,
                &label_placements,
                line_style,
            );
            continue;
        }

        // Build waypoint list: source centre → (dummy centres …) → target centre
        var waypoints = std.ArrayListUnmanaged(Vec2){};
        defer waypoints.deinit(allocator);

        // Start with source centre
        try waypoints.append(allocator, .{
            .x = v_node.x + offset_x,
            .y = v_node.y + offset_y,
        });

        // Walk through dummy chain
        var current_target: []const u8 = entry.w;
        while (true) {
            const t_node = graph.getNode(current_target) orelse break;
            if (!t_node.dummy) {
                // Reached a real target node — add its centre and stop.
                try waypoints.append(allocator, .{
                    .x = t_node.x + offset_x,
                    .y = t_node.y + offset_y,
                });
                break;
            }
            // Dummy node — record its position as a bend point.
            try waypoints.append(allocator, .{
                .x = t_node.x + offset_x,
                .y = t_node.y + offset_y,
            });
            // Follow the chain.
            const next = nextInChain(graph, current_target) orelse break;
            current_target = next;
        }

        if (waypoints.items.len < 2) continue;

        // -----------------------------------------------------------------
        // If the layout router has set explicit waypoints on this edge
        // (e.g. to route around containers), use those instead of the
        // simple source→target straight line.
        // -----------------------------------------------------------------
        if (edge_data) |ed| {
            if (ed.points.items.len >= 2) {
                waypoints.clearRetainingCapacity();
                for (ed.points.items) |pt| {
                    try waypoints.append(allocator, .{
                        .x = pt.x + offset_x,
                        .y = pt.y + offset_y,
                    });
                }
            }
        }

        // -----------------------------------------------------------------
        // Clip the first segment to the source node's border
        // -----------------------------------------------------------------
        const src_node = v_node;
        const src_hw = src_node.width / 2.0;
        const src_hh = src_node.height / 2.0;
        const src_centre = waypoints.items[0];
        const next_pt = waypoints.items[1];

        const clipped_start = clipLineToShape(
            next_pt,
            src_centre,
            src_centre.x,
            src_centre.y,
            src_hw,
            src_hh,
            src_node.shape,
        );
        waypoints.items[0] = clipped_start;

        // -----------------------------------------------------------------
        // Clip the last segment to the target node's border
        // -----------------------------------------------------------------
        const last_idx = waypoints.items.len - 1;
        const tgt_id = current_target;
        if (graph.getNode(tgt_id)) |tgt_node| {
            if (!tgt_node.dummy) {
                const tgt_hw = tgt_node.width / 2.0;
                const tgt_hh = tgt_node.height / 2.0;
                const tgt_centre = waypoints.items[last_idx];
                const prev_pt = waypoints.items[last_idx - 1];

                const clipped_end = clipLineToShape(
                    prev_pt,
                    tgt_centre,
                    tgt_centre.x,
                    tgt_centre.y,
                    tgt_hw,
                    tgt_hh,
                    tgt_node.shape,
                );
                waypoints.items[last_idx] = clipped_end;
            }
        }

        // -----------------------------------------------------------------
        // Preserve explicit routed waypoints as-is. Smoothing them back
        // into Catmull-Rom splines can bow valid obstacle routes into
        // container boxes again.
        // -----------------------------------------------------------------
        const has_explicit_route = if (edge_data) |ed| ed.points.items.len >= 2 else false;
        var smooth = std.ArrayListUnmanaged(Vec2){};
        defer smooth.deinit(allocator);
        if (has_explicit_route) {
            try smooth.appendSlice(allocator, waypoints.items);
        } else {
            smooth = try tessellateSpline(allocator, waypoints.items);
        }

        // -----------------------------------------------------------------
        // Save arrowhead anchor points before shortening the polyline
        // -----------------------------------------------------------------
        var target_tip: Vec2 = undefined;
        var target_from: Vec2 = undefined;
        var source_tip: Vec2 = undefined;
        var source_from: Vec2 = undefined;

        if (has_arrow and smooth.items.len >= 2) {
            const s_last = smooth.items.len - 1;
            target_tip = smooth.items[s_last];
            target_from = smooth.items[s_last - 1];
        }
        if (has_source_arrow and smooth.items.len >= 2) {
            source_tip = smooth.items[0];
            source_from = smooth.items[1];
        }

        // Shorten the polyline so the line stops at each arrowhead's base
        // instead of poking through the tip.
        if (has_arrow) {
            shortenPolylineEnd(&smooth, config.arrow_size);
        }
        if (has_source_arrow) {
            shortenPolylineStart(&smooth, config.arrow_size);
        }

        // -----------------------------------------------------------------
        // Draw the (now smooth) polyline, respecting line style
        // -----------------------------------------------------------------
        if (smooth.items.len >= 2) {
            switch (line_style) {
                .dashed => {
                    // Long dashes: 10px on, 6px off
                    for (0..smooth.items.len - 1) |i| {
                        const p0 = smooth.items[i];
                        const p1 = smooth.items[i + 1];
                        canvas.drawDashedLine(
                            p0.x,
                            p0.y,
                            p1.x,
                            p1.y,
                            edge_thickness,
                            edge_color[0],
                            edge_color[1],
                            edge_color[2],
                            edge_color[3],
                            10.0,
                            6.0,
                        );
                    }
                },
                .dotted => {
                    // Short dashes: 4px on, 4px off
                    for (0..smooth.items.len - 1) |i| {
                        const p0 = smooth.items[i];
                        const p1 = smooth.items[i + 1];
                        canvas.drawDashedLine(
                            p0.x,
                            p0.y,
                            p1.x,
                            p1.y,
                            edge_thickness,
                            edge_color[0],
                            edge_color[1],
                            edge_color[2],
                            edge_color[3],
                            4.0,
                            4.0,
                        );
                    }
                },
                .solid, .thick => {
                    for (0..smooth.items.len - 1) |i| {
                        const p0 = smooth.items[i];
                        const p1 = smooth.items[i + 1];
                        canvas.drawLine(
                            p0.x,
                            p0.y,
                            p1.x,
                            p1.y,
                            edge_thickness,
                            edge_color[0],
                            edge_color[1],
                            edge_color[2],
                            edge_color[3],
                        );
                    }
                },
            }
        }

        // -----------------------------------------------------------------
        // Draw arrowhead at the target end
        // -----------------------------------------------------------------
        if (has_arrow and smooth.items.len >= 1) {
            drawArrowhead(
                canvas,
                target_from,
                target_tip,
                config.arrow_size,
                canvas.scale_factor,
                edge_color[0],
                edge_color[1],
                edge_color[2],
                edge_color[3],
            );
        }

        // -----------------------------------------------------------------
        // Draw arrowhead at the source end (bidirectional / left arrows)
        // -----------------------------------------------------------------
        if (has_source_arrow and smooth.items.len >= 1) {
            drawArrowhead(
                canvas,
                source_from,
                source_tip,
                config.arrow_size,
                canvas.scale_factor,
                edge_color[0],
                edge_color[1],
                edge_color[2],
                edge_color[3],
            );
        }

        // -----------------------------------------------------------------
        // Collect edge label placement (drawn later after collision resolve)
        // -----------------------------------------------------------------
        if (font) |f| {
            const label_text: ?[]const u8 = if (edge_data) |ed| ed.label else null;
            if (label_text) |lbl| {
                if (lbl.len > 0) {
                    // Place label a short distance along the curve from the
                    // source node border.  This keeps labels like |Yes| / |No|
                    // close to the decision point rather than drifting to the
                    // middle of a long routed edge.
                    const label_offset: f64 = 22.0; // pixels from source border
                    const mid: Vec2 = if (smooth.items.len >= 2)
                        pointAlongCurve(smooth.items, label_offset)
                    else
                        Vec2.lerp(waypoints.items[0], waypoints.items[1], 0.15);

                    // Compute tangent at the label point for perpendicular nudging
                    var tan_x: f64 = 0;
                    var tan_y: f64 = 1;
                    if (smooth.items.len >= 2) {
                        // Use the first two samples after the clipped start
                        // to approximate the tangent near the source.
                        const t_idx = @min(@as(usize, 1), smooth.items.len - 1);
                        tan_x = smooth.items[t_idx].x - smooth.items[0].x;
                        tan_y = smooth.items[t_idx].y - smooth.items[0].y;
                        const tlen = @sqrt(tan_x * tan_x + tan_y * tan_y);
                        if (tlen > 0.001) {
                            tan_x /= tlen;
                            tan_y /= tlen;
                        }
                    }

                    const label_font_size = config.text_size * 0.85;
                    const tw = f.measureText(lbl, label_font_size);
                    const th: f32 = label_font_size * 1.3;

                    const pad_x: f64 = 4.0;
                    const pad_y: f64 = 2.0;

                    try label_placements.append(allocator, .{
                        .text = lbl,
                        .x = mid.x,
                        .y = mid.y,
                        .orig_x = mid.x,
                        .orig_y = mid.y,
                        .half_w = @as(f64, @floatCast(tw)) / 2.0 + pad_x,
                        .half_h = @as(f64, @floatCast(th)) / 2.0 + pad_y,
                        .tangent_x = tan_x,
                        .tangent_y = tan_y,
                        .font_size = label_font_size,
                        .color = config.text_color,
                    });
                }
            }
        }
    }

    // -----------------------------------------------------------------
    // Resolve label-vs-label and label-vs-node collisions, then draw.
    // -----------------------------------------------------------------
    if (label_placements.items.len > 0) {
        try resolveLabelPlacements(allocator, label_placements.items, graph, offset_x, offset_y);

        if (font) |f| {
            try drawLabels(label_placements.items, canvas, f);
        }
    }
}

// ---------------------------------------------------------------------------
// Self-edge loop rendering
// ---------------------------------------------------------------------------

/// Draw a self-referencing edge as a curved loop arc on the right side of
/// the node.  The loop exits from the right-top of the node, arcs outward
/// to the right, and re-enters at the right-bottom with an arrowhead.
fn drawSelfEdgeLoop(
    allocator: Allocator,
    canvas: *Canvas,
    node: NodeData,
    offset_x: f64,
    offset_y: f64,
    edge_color: [4]u8,
    edge_thickness: i32,
    has_arrow: bool,
    config: RenderConfig,
    font: ?*Font,
    edge_data: ?EdgeData,
    label_placements: *std.ArrayListUnmanaged(LabelPlacement),
    line_style: LineStyle,
) !void {
    const cx = node.x + offset_x;
    const cy = node.y + offset_y;
    const hw = node.width / 2.0;
    const hh = node.height / 2.0;

    // Loop geometry — exits from right side, arcs outward.
    // The loop is drawn as a series of points approximating an elliptical
    // arc from the top-right to the bottom-right of the node.
    const loop_offset_x: f64 = @max(hw * 0.6, 20.0); // how far the loop extends to the right
    const loop_offset_y: f64 = @max(hh * 0.6, 15.0); // vertical spread at the node border

    // Start point: right side, slightly above centre
    const start_x = cx + hw;
    const start_y = cy - loop_offset_y;

    // End point: right side, slightly below centre
    const end_x = cx + hw;
    const end_y = cy + loop_offset_y;

    // Control points for the loop bulge (rightward)
    const bulge_x = cx + hw + loop_offset_x;

    // Generate smooth loop points using a simple cubic-like parametric curve.
    // We sample an arc that goes: start → bulge_top → bulge_right → bulge_bottom → end
    const num_segments: usize = 20;
    var loop_points = std.ArrayListUnmanaged(Vec2){};
    defer loop_points.deinit(allocator);

    try loop_points.ensureTotalCapacity(allocator, num_segments + 1);

    for (0..num_segments + 1) |i| {
        const t = @as(f64, @floatFromInt(i)) / @as(f64, @floatFromInt(num_segments));

        // Parametric arc: use a half-ellipse on the right side
        // Angle goes from -π/2 (top) to +π/2 (bottom)
        const angle = -std.math.pi / 2.0 + t * std.math.pi;
        const px = cx + hw + loop_offset_x * @cos(angle) * @cos(angle); // bulge outward
        const py = cy + (loop_offset_y + loop_offset_x * 0.3) * @sin(angle); // vertical spread

        // Blend toward a more natural teardrop shape:
        // Near t=0 and t=1, pull x back toward the node border
        const border_pull = 1.0 - 4.0 * (t - 0.5) * (t - 0.5); // peaks at t=0.5
        const final_x = start_x + (px - start_x) * border_pull + (bulge_x - start_x) * border_pull * 0.3;
        const final_y = py;

        loop_points.appendAssumeCapacity(.{ .x = final_x, .y = final_y });
    }

    // Override first and last points to exactly match start/end
    loop_points.items[0] = .{ .x = start_x, .y = start_y };
    loop_points.items[num_segments] = .{ .x = end_x, .y = end_y };

    // Save arrowhead anchor points and shorten the polyline so the line
    // stops at the arrowhead base instead of poking through its tip.
    var loop_tip: Vec2 = undefined;
    var loop_before_tip: Vec2 = undefined;
    if (has_arrow and loop_points.items.len >= 2) {
        const s_last = loop_points.items.len - 1;
        loop_tip = loop_points.items[s_last];
        loop_before_tip = loop_points.items[s_last - 1];
        shortenPolylineEnd(&loop_points, config.arrow_size);
    }

    // Draw the loop polyline, respecting line style
    if (loop_points.items.len >= 2) {
        for (0..loop_points.items.len - 1) |i| {
            const p0 = loop_points.items[i];
            const p1 = loop_points.items[i + 1];
            switch (line_style) {
                .dashed => {
                    canvas.drawDashedLine(
                        p0.x,
                        p0.y,
                        p1.x,
                        p1.y,
                        edge_thickness,
                        edge_color[0],
                        edge_color[1],
                        edge_color[2],
                        edge_color[3],
                        10.0,
                        6.0,
                    );
                },
                .dotted => {
                    canvas.drawDashedLine(
                        p0.x,
                        p0.y,
                        p1.x,
                        p1.y,
                        edge_thickness,
                        edge_color[0],
                        edge_color[1],
                        edge_color[2],
                        edge_color[3],
                        4.0,
                        4.0,
                    );
                },
                .solid, .thick => {
                    canvas.drawLine(
                        p0.x,
                        p0.y,
                        p1.x,
                        p1.y,
                        edge_thickness,
                        edge_color[0],
                        edge_color[1],
                        edge_color[2],
                        edge_color[3],
                    );
                },
            }
        }
    }

    // Draw arrowhead at the end point using the saved (unshortened) positions.
    if (has_arrow and loop_points.items.len >= 1) {
        drawArrowhead(
            canvas,
            loop_before_tip,
            loop_tip,
            config.arrow_size,
            canvas.scale_factor,
            edge_color[0],
            edge_color[1],
            edge_color[2],
            edge_color[3],
        );
    }

    // Collect label placement at the rightmost point of the loop
    if (font) |f| {
        const label_text: ?[]const u8 = if (edge_data) |ed| ed.label else null;
        if (label_text) |lbl| {
            if (lbl.len > 0) {
                // Place the label at the apex of the loop (rightmost point)
                const label_x = bulge_x + 8.0; // slightly right of the loop apex
                const label_y = cy;

                const label_font_size = config.text_size * 0.85;
                const tw = f.measureText(lbl, label_font_size);
                const th: f32 = label_font_size * 1.3;

                const pad_x: f64 = 4.0;
                const pad_y: f64 = 2.0;

                try label_placements.append(allocator, .{
                    .text = lbl,
                    .x = label_x,
                    .orig_x = label_x,
                    .orig_y = label_y,
                    .y = label_y,
                    .half_w = @as(f64, @floatCast(tw)) / 2.0 + pad_x,
                    .half_h = @as(f64, @floatCast(th)) / 2.0 + pad_y,
                    .tangent_x = 0.0,
                    .tangent_y = 1.0, // vertical tangent for perpendicular nudging
                    .font_size = label_font_size,
                    .color = config.text_color,
                });
            }
        }
    }
}
