# Container-Edges-First Layout Redesign

## Problem Statement

The current layout pipeline treats all nodes as flat peers, runs the full
Dagre pipeline (ranking, ordering, coordinate assignment) on the entire
graph, and then tries to retrofit container (subgraph) bounding boxes
around wherever the nodes ended up.  This causes two serious visual
defects:

1. **Containers are too wide.**  Because nodes from different containers
   share ranks, a container's children can end up spread across the full
   width of the graph.  Post-hoc compaction (`compactSubgraphChildren`)
   helps but can never fully fix the root cause: children were positioned
   without any awareness of container boundaries.

2. **Edges drawn across containers.**  Inter-container edges are rendered
   as straight lines (or splines through dummy chain nodes) that cut
   directly through any container boxes that happen to sit between the
   source and target.  This looks terrible — lines scribble across
   containers that have nothing to do with the edge.

### Root Cause

The Dagre pipeline was designed for flat graphs.  The original Dagre.js
handles compound (nested) graphs by inserting border dummy nodes and
parent dummy chains that constrain children within parent rank ranges.
Those phases (3, 3.5, 5b–11, 13.5–17) are marked "NOT YET PORTED" in
the Zig codebase.

Rather than porting all of those phases (which is a large, intricate
effort), we can solve both problems with a higher-level architectural
change: **lay out containers first, then lay out their internals**.

---

## Design: Hierarchical Container-First Layout

### Core Idea

> Lay out containers as opaque boxes based on their inter-container
> connections.  Lay out each container's internal nodes independently.
> Then place the internal layouts inside the positioned containers.
> Finally, route inter-container edges through the gaps between
> containers so they never cross a foreign container.

This is a two-level hierarchical layout.  It generalises to N levels for
nested subgraphs by recursing.

### Overview of Phases

```
┌─────────────────────────────────────────────────────┐
│  Phase 1: Classify                                  │
│  - Identify root-level subgraphs (containers)       │
│  - Identify free nodes (not inside any container)   │
│  - Classify edges as intra-container or inter-container │
└─────────────────────┬───────────────────────────────┘
                      │
┌─────────────────────▼───────────────────────────────┐
│  Phase 2: Internal Layout (per container)           │
│  - For each container, build a sub-graph with just  │
│    its children + intra-container edges              │
│  - Run the standard Dagre pipeline on the sub-graph │
│  - Record each container's internal bounding box    │
│  - (Recurse for nested subgraphs)                   │
└─────────────────────┬───────────────────────────────┘
                      │
┌─────────────────────▼───────────────────────────────┐
│  Phase 3: Meta-Graph Layout                         │
│  - Build a meta-graph where each container is a     │
│    single node (sized by its internal bounding box) │
│  - Free nodes appear as regular nodes               │
│  - Inter-container edges become meta-edges           │
│  - Run Dagre on the meta-graph to position          │
│    containers relative to each other                │
└─────────────────────┬───────────────────────────────┘
                      │
┌─────────────────────▼───────────────────────────────┐
│  Phase 4: Position Mapping                          │
│  - Translate each container's internal node         │
│    positions by the container's meta-graph position │
│  - Set container node (x, y, width, height) from    │
│    internal bounds + padding                        │
└─────────────────────┬───────────────────────────────┘
                      │
┌─────────────────────▼───────────────────────────────┐
│  Phase 5: Inter-Container Edge Routing              │
│  - For each inter-container edge, compute waypoints │
│    that exit the source container, travel through    │
│    gaps between containers, and enter the target     │
│    container — never crossing a foreign container   │
│  - Store waypoints in EdgeData.points               │
└─────────────────────┬───────────────────────────────┘
                      │
┌─────────────────────▼───────────────────────────────┐
│  Phase 6: Coordinate System Undo + Diagnostics      │
│  - Apply LR/RL/BT transforms as today              │
│  - Print diagnostics                                │
└─────────────────────────────────────────────────────┘
```

---

## Detailed Phase Design

### Phase 1: Classify

Walk every node and edge in the graph once.

**Nodes:**
- A node with `is_subgraph == true` and no parent (or whose parent is
  also a subgraph we're currently processing) is a **container**.
- A node with `is_subgraph == false` and no parent is a **free node**.
- A node whose parent is a container is a **child** of that container.

**Edges:**
- If both endpoints share the same innermost container ancestor →
  **intra-container edge**.
- Otherwise → **inter-container edge**.  Record which container each
  endpoint belongs to (or "root" for free nodes).

Data structures:
```
ContainerInfo {
    id: []const u8,           // subgraph node ID
    children: [][]const u8,   // direct child node IDs (non-subgraph)
    child_subgraphs: [][]const u8,  // nested subgraphs (for recursion)
    intra_edges: []EdgeRef,   // edges where both endpoints are children
    internal_bounds: BBox,    // filled in Phase 2
}

InterEdge {
    src_node: []const u8,     // actual source node ID
    tgt_node: []const u8,     // actual target node ID
    src_container: ?[]const u8,  // container ID (null = free node)
    tgt_container: ?[]const u8,  // container ID (null = free node)
    edge_data: *EdgeData,     // pointer to original edge
    edge_name: ?[]const u8,
}
```

### Phase 2: Internal Layout (per container)

For each `ContainerInfo`:

1. Create a temporary `Graph` with just this container's children as
   nodes and its `intra_edges`.
2. Copy node data (label, width, height, shape) into the temp graph.
3. Run the standard flat Dagre pipeline on the temp graph:
   `adjustCoordinateSystem → removeSelfEdges → acyclic → rank →
   normalize → order → position → undo acyclic → restoreSelfEdges`.
4. Read back the (x, y) positions from the temp graph into the
   original graph's nodes.
5. Compute the internal bounding box:
   ```
   min_x = min(child.x - child.width/2)  for all children
   max_x = max(child.x + child.width/2)
   min_y = min(child.y - child.height/2)
   max_y = max(child.y + child.height/2)
   ```
6. Record `internal_bounds` on the `ContainerInfo`.
7. Free the temp graph.

**Nested subgraphs:** If a container has `child_subgraphs`, recurse into
each one first (depth-first, leaf-first).  After the nested subgraph is
internally laid out and sized, it participates in its parent container's
internal layout as a node with the nested subgraph's bounding-box
dimensions.

**Result:** Each container's children now have positions relative to the
container's own local origin.  The container knows its natural width and
height (tight-fitting around content + padding + title).

### Phase 3: Meta-Graph Layout

1. Create a new temporary `Graph` (the "meta-graph").
2. For each container, add a meta-node with:
   - `width = internal_bounds.width + 2 * subgraph_padding`
   - `height = internal_bounds.height + 2 * subgraph_padding + title_height`
3. For each free node, add it as a regular node in the meta-graph
   (with its original width/height).
4. For each `InterEdge`, add an edge in the meta-graph between the
   source's container (or free node) and the target's container (or
   free node).  If multiple inter-edges connect the same pair of
   containers, we can either:
   - Add all of them (preserves minlen/weight semantics), or
   - Add one representative edge with `weight = count` (simpler).
   The former is more correct; start with that.
5. Run the full flat Dagre pipeline on the meta-graph.
6. Read back the (x, y) positions of each meta-node.

**Result:** We now know where each container (and each free node) should
be positioned in the final diagram.

### Phase 4: Position Mapping

For each container:

1. Compute the offset from the container's internal coordinate origin to
   its meta-graph position:
   ```
   internal_center_x = (internal_bounds.min_x + internal_bounds.max_x) / 2
   internal_center_y = (internal_bounds.min_y + internal_bounds.max_y) / 2
   offset_x = meta_node.x - internal_center_x
   offset_y = meta_node.y - internal_center_y + title_height / 2
   ```
2. For every child node of the container in the original graph, apply:
   ```
   child.x += offset_x
   child.y += offset_y
   ```
3. Set the container's subgraph node position and size:
   ```
   container.x = meta_node.x
   container.y = meta_node.y
   container.width = meta_node.width
   container.height = meta_node.height
   ```

For free nodes, copy the position directly from the meta-graph.

### Phase 5: Inter-Container Edge Routing

This is the key phase that prevents edges from scribbling across
containers.

#### Strategy: Use Meta-Graph Dummy Nodes

When we ran the Dagre layout on the meta-graph in Phase 3, Dagre automatically
inserted dummy nodes for any edges that spanned multiple ranks (long edges).
We can use these dummy nodes as the "skeleton" for our inter-container
edge routing.

1. **Iterate meta-graph edges:** correspond to inter-container edges (or groups).
2. **Retrieve path:** If the edge was split into segments by dummy
   nodes in the meta-graph, collect those dummy node positions.
3. **Map to global coordinates:**
   The meta-graph nodes represent the *centers* of the containers.
   The dummy nodes represent routing points *between* containers.
   
   If we have an edge $A \to B$ in the meta-graph with dummy chain
   $d_1 \to d_2 \to \dots$:
   
   - Start at $A$'s border (facing $d_1$).
   - Go through $d_1, d_2, \dots$ (which are already in optimal positions
     to avoid other meta-nodes, i.e., other containers).
   - End at $B$'s border (facing last dummy).

This leverages Dagre's existing routing intelligence (fixing node overlaps,
minimizing crossings) at the container level.  We don't need to manually
implement "Case A/B/C/D" routing heuristics!

#### Storing waypoints

The computed waypoints are stored in `edge_data.points`:

```zig
edge_data.points.clearRetainingCapacity();
for (waypoints) |wp| {
    try edge_data.points.append(allocator, .{ .x = wp.x, .y = wp.y });
}
```

### Phase 6: Renderer Integration

The renderers (`graph.zig` drawEdges, `svg_render.zig` drawEdges) need
a small change at the waypoint-building step:

```zig
// NEW: If the edge has pre-computed waypoints from the layout phase,
// use those instead of building from dummy chains.
if (edge_data) |ed| {
    if (ed.points.items.len >= 2) {
        for (ed.points.items) |pt| {
            try waypoints.append(allocator, .{
                .x = pt.x + offset_x,
                .y = pt.y + offset_y,
            });
        }
        // Skip the dummy-chain walk — we have explicit waypoints.
        // Still clip to source/target node borders and tessellate.
        ...
        continue;
    }
}
// EXISTING: dummy chain walk (fallback for non-container edges)
```

This is a minimal, backwards-compatible change.  Intra-container edges
(which have no pre-computed points) continue to use the existing dummy
chain logic.  Only inter-container edges with layout-computed waypoints
use the new path.

---

## What This Replaces

The following existing post-hoc fixup phases become **unnecessary** and
can be removed or greatly simplified:

| Current Phase | Function | Why It's Unnecessary |
|---|---|---|
| 18b | `compactSubgraphChildren` | Children are laid out within their container; no cross-container spreading |
| 19 | `computeSubgraphBounds` | Bounds are computed from internal layout + padding in Phase 4 |
| 19a | `orderSiblingsByConnectivity` | Meta-graph layout handles container ordering via edge connectivity |
| 19b | `separateSiblingSubgraphs` | Meta-graph layout places containers with proper separation |
| 19c | `finalContainerAdjustment` | No free-node / container overlap because they're co-laid-out |

These phases total ~900 lines of complex, fragile code.  Removing them
in favor of the hierarchical approach is a net simplification.

---

## Implementation Plan

### Step 1: `layoutHierarchical` function

Refactor `layout()` to split coordinate system handling from the core logic.

1. Rename the existing monolithic logic (phases 1–19, excluding 0 and 20)
   to `layoutCore(allocator, graph, config)`.
2. Update `layout()` to be the wrapper:

```zig
pub fn layout(allocator, graph, config) !void {
    // Phase 0: Global Adjust for LR/RL
    try adjustCoordinateSystem(allocator, graph, config.rankdir);
    
    // Check if graph has any subgraphs
    if (hasSubgraphs(graph)) {
        // Recursive layout. 
        // NOTE: We pass 'TB' as rankdir to children because we are already
        // in the adjusted coordinate space!
        var child_config = config;
        child_config.rankdir = .TB; 
        try layoutHierarchical(allocator, graph, child_config);
    } else {
        try layoutCore(allocator, graph, config);
    }

    // Phase 20: Undo Global Adjust
    try undoCoordinateSystem(allocator, graph, config.rankdir);
}
```

This prevents "double-flipping" coordinates when we recurse. The entire hierarchy
layout happens in the normalized TB space.

### Step 2: Classification helpers

Implement the classification logic:
- `classifyNodesAndEdges(allocator, graph)` → returns containers,
  free nodes, intra-edges per container, inter-edges.
- `findContainerOf(graph, node_id)` → returns the root-level container
  a node belongs to (walking parent chain), or null for free nodes.

### Step 3: Internal container layout

Implement `layoutContainerInternal(allocator, graph, container, config)`:
- Builds temp graph, runs flat pipeline, reads positions back.
- Returns bounding box.

### Step 4: Meta-graph construction and layout

Implement `buildAndLayoutMetaGraph(allocator, graph, containers,
free_nodes, inter_edges, config)`:
- Creates meta-graph, runs flat pipeline.
- Returns container positions.

### Step 5: Position mapping

Implement `applyMetaPositions(allocator, graph, containers,
free_node_positions)`:
- Offsets all children by container position.
- Sets container node bounds.

### Step 6: Inter-container edge routing

Implement `routeInterContainerEdges(allocator, graph, inter_edges,
container_bounds)`:
- Computes waypoints per inter-edge.
- Stores in `edge_data.points`.

### Step 7: Renderer changes

Modify `drawEdges` in `src/render/graph.zig`, `src/class/svg_render.zig` and others
to check for pre-computed `edge_data.points` before building waypoints from
dummy chains.

In `src/render/graph.zig`:
```zig
        // Build waypoint list
        var waypoints = std.ArrayListUnmanaged(Vec2){};
        defer waypoints.deinit(allocator);

        // NEW: Check for explicit layout points first
        if (edge_data) |ed| {
            if (ed.points.items.len > 0) {
                 for (ed.points.items) |pt| {
                     try waypoints.append(allocator, .{
                         .x = pt.x + offset_x,
                         .y = pt.y + offset_y,
                     });
                 }
                 // Proceed to clipping/drawing...
            }
        }
        
        // If no explicit points, fall back to dummy chain walking:
        if (waypoints.items.len == 0) {
             // ... existing dummy chain walking code ...
        }
```

This makes the change backwards-compatible. Intra-container edges (managed by
inner flat layouts) will still rely on dummy chains if we don't denormalize
them. Inter-container edges (managed by this new pipeline) will provide
explicit points.

Remove or gate the old post-hoc fixup phases behind a flag.  They
should only run for the flat (no-subgraph) path.

---

## Edge Cases

- **Empty containers:** Container with no children gets a default
  minimum size (e.g. 80×40).

- **Nested subgraphs:** Handled by recursion.  Lay out the innermost
  containers first, then treat each as a sized node in its parent
  container's layout.

- **Subgraph-to-subgraph edges (where the endpoint IS the subgraph
  ID):** Map these to a representative child node or a virtual
  ingress/egress port on the container boundary.  For now, emit a
  warning and pick the container's first child.

- **Self-edges within a container:** Handled by the container's
  internal flat layout (self-edge removal/restoration).

- **Inter-container self-edges (both endpoints in the same
  container):** These are actually intra-container — classification
  should catch this.

- **Free nodes connected to containers:** Free nodes participate in
  the meta-graph as regular nodes and are positioned by the meta
  layout.

- **LR/RL/BT directions:** The coordinate system adjustment
  (`adjustCoordinateSystem` / `undoCoordinateSystem`) wraps the entire
  hierarchical pipeline.  Internal layouts also use TB mode internally,
  and we apply the undo once at the end.

---

## Risks and Mitigations

| Risk | Mitigation |
|---|---|
| Internal layout ignores inter-container edges, so internal node ordering may not optimize for good inter-container edge routing | Accept this initially; can later add "port hints" based on inter-container edge directions |
| Multiple inter-container edges between the same pair of containers may bunch up | The edge routing can assign slightly different x offsets for parallel edges (channel spreading) |
| Very many containers could make the meta-graph layout slow | Dagre is fast for small graphs; even 50 containers is trivial |
| Temp graph allocation churn | Each temp graph is short-lived; Zig's allocator model handles this well |

---

## Success Criteria

1. Containers are tightly sized around their content (no more 500px-wide
   boxes for 3 nodes).
2. Edges between containers route cleanly through gaps — no line ever
   crosses through a container that it doesn't originate from or
   terminate in.
3. Existing test diagrams without subgraphs render identically (flat
   layout path is unchanged).
4. The `flowchart_subgraphs.mmd` and `saas_architecture.mmd` test
   diagrams render with clean, readable container layouts.
5. `zig build test` passes.