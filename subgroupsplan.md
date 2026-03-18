## Plan: Compound Routing Review

Merrow's poor connector routing around groups is not primarily a spline-rendering issue; it stems from treating compound/group structure as a post-layout concern instead of a first-class layout constraint. The recommended approach is to move group boundaries into the Dagre pipeline itself by adding real border dummy nodes, nesting edges, compound rank tracking, and compound-aware conflict detection, then reduce the obstacle router to a secondary refinement pass rather than the main correctness mechanism.

**Steps**
1. Confirm the current failure mode and freeze scope around flowchart/subgraph routing first. Reuse the existing hierarchical path in `/Volumes/SSK SSD/merrow/src/layout/dagre.zig`, but treat it as transitional rather than final. Included: subgraph/group creation, rank/position interactions, and edge routing through nested containers. Excluded initially: unrelated diagram families unless they share the same layout graph.
2. Phase 1: make compound metadata real in the graph model. Extend the current `NodeData` compound fields in `/Volumes/SSK SSD/merrow/src/model.zig` so border nodes are explicit rather than inferred. Add missing top/bottom border references and a border kind marker instead of relying on `dummy` plus string-prefix heuristics.
3. Phase 2: add a nesting-graph pass before ranking, modeled on the Rust port's approach. In `/Volumes/SSK SSD/merrow/src/layout/dagre.zig` (or a new `src/layout/dagre/nesting.zig` helper), create root, top, and bottom border dummies for each compound node; insert nesting edges that constrain descendants between parent borders; and scale `minlen` by nesting depth. This step blocks the later compound fixes because rank ranges and conflict detection depend on it.
4. Phase 3: derive compound rank extents and add left/right border segments after ranking and before ordering/positioning. Reuse the existing `min_rank`, `max_rank`, `border_left`, and `border_right` fields in `/Volumes/SSK SSD/merrow/src/model.zig`. Populate them from actual border nodes, then create left/right border chains per rank so Brandes-Kopf can respect container walls during x-assignment. This depends on Step 3.
5. Phase 4: replace heuristic type-2 conflict detection with real compound-aware detection. Update `/Volumes/SSK SSD/merrow/src/layout/dagre/position.zig` so type-2 conflicts recognize explicit border dummies, mirroring the Rust algorithm. Remove the `_border` name test and use structural metadata instead. This depends on Steps 2 and 3.
6. Phase 5: redirect edges that touch compound nodes to border entry/exit nodes before ranking, then restore original endpoints after layout. This prevents edges to or from groups from collapsing through container centers and gives the ranker a valid graph. Implement in the Dagre pipeline near normalization/ranking in `/Volumes/SSK SSD/merrow/src/layout/dagre.zig`.
7. Phase 6: narrow the responsibility of `routeInterContainerEdges` in `/Volumes/SSK SSD/merrow/src/layout/dagre.zig`. After compound layout is correct, keep the router only for residual obstacle avoidance or cosmetic lane spreading. If it remains, change classification so it works per nesting boundary rather than collapsing everything to `findRootContainer`, and scope lane counters per obstacle set instead of globally. This can be done incrementally after Steps 2-5.
8. Phase 7: simplify or retire the current container-first workaround once the compound pipeline is stable. The design note in `/Volumes/SSK SSD/merrow/container-edges-first.md` documents why the workaround was introduced; update it to reflect whether the project keeps a hybrid layout path or fully returns to a Dagre-style compound layout.
9. Add focused tests and fixtures. Start with diagrams that expose the current bug: nested subgraphs, siblings with cross-group edges, edges to/from group nodes, and multiple parallel cross-group edges. Use `/Volumes/SSK SSD/merrow/test-diagrams/flowchart_subgraphs.mmd` plus new minimal fixtures, and add assertions in Zig tests around rank ranges, border node presence, and edge waypoint validity.

**Relevant files**
- `/Volumes/SSK SSD/merrow/src/layout/dagre.zig` - current hierarchical classifier, root-level meta-graph construction, and `routeInterContainerEdges`; primary location of the architectural mismatch.
- `/Volumes/SSK SSD/merrow/src/layout/dagre/position.zig` - current type-2 conflict detection is heuristic and effectively inactive because real border nodes are never created.
- `/Volumes/SSK SSD/merrow/src/model.zig` - already contains partial compound fields (`min_rank`, `max_rank`, `border_left`, `border_right`) that should become the canonical source of compound metadata.
- `/Volumes/SSK SSD/merrow/src/parser/flowchart.zig` - subgraph parsing and parent assignment; confirm this remains compatible with the stronger compound layout model.
- `/Volumes/SSK SSD/merrow/container-edges-first.md` - documents the current workaround and should be revised once the preferred direction is chosen.

**Verification**
1. Add unit tests proving that a parsed subgraph produces explicit border nodes and non-null rank bounds after ranking.
2. Add layout tests showing edges between nodes in nested/sibling groups do not cross foreign group rectangles.
3. Add a regression test for type-2 conflicts by constructing a graph where a dummy chain would previously cross a group boundary.
4. Render representative diagrams before/after and visually confirm that cross-group edges enter and exit along group boundaries instead of passing through centers.
5. If the project has image or SVG snapshot tests, add one for nested subgraphs with multiple inter-group edges; otherwise record expected waypoint geometry in a text assertion.

**Decisions**
- Recommended direction: port the Rust/dagre-style compound graph machinery instead of iterating further on the post-layout obstacle router.
- Keep the current container-first router only as a transitional fallback or final cosmetic pass; it should not remain the primary correctness mechanism.
- Address flowchart/subgraph behavior first, because that is where group semantics are strongest and the current design note is already focused.

**Further Considerations**
1. Incremental option: if a full compound-graph port is too large for one pass, first fix the inactive border-node logic and root-container edge collapsing, then phase in nesting edges and border segments.
2. Compatibility risk: confirm whether class, state, and ER diagrams share the same Dagre graph path; if they do, guard new compound behavior behind `is_subgraph`-aware logic so flat layouts remain unchanged.
3. Rendering risk: smooth spline tessellation can visually bow back into boxes even with correct waypoints, so keep one verification step specifically for rendered curves, not only control points.