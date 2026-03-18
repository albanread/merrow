# Subgroups Work Tracker

Tracks implementation progress for the compound-routing plan in [subgroupsplan.md](./subgroupsplan.md).

## Overall Status

- Status: In progress
- Focus area: Flowchart subgraphs and cross-group edge routing
- Target outcome: Make group boundaries first-class in layout so connectors route correctly between items in groups

## Work Items

| ID | Work Item | Status | Notes |
| --- | --- | --- | --- |
| 1 | Confirm current failure cases with subgraph/group routing | Not started | Reproduce with nested subgraphs, sibling groups, and edges crossing group boundaries |
| 2 | Audit current flowchart subgraph parsing and parent assignment | Not started | Verify parser output is sufficient for compound layout phases |
| 3 | Extend compound metadata in `NodeData` | Complete | Added explicit top/bottom border refs plus dummy and border kind metadata |
| 4 | Add nesting-graph pass before ranking | Complete | Grouped graphs now use the compound layout path by default, and it runs nesting before ranking |
| 5 | Scale rank spacing by nesting depth | Complete | Grouped graphs now apply `node_rank_factor`/`minlen` scaling through the live compound layout path |
| 6 | Assign `min_rank` and `max_rank` for compound nodes | Complete | Grouped graphs now derive rank bounds from real top/bottom border dummies in the live compound path |
| 7 | Add left/right border segments per rank | Complete | Grouped graphs now build left/right border chains per rank in the live compound path |
| 8 | Replace heuristic type-2 conflict detection | Complete | BK conflict detection now uses explicit border metadata, and the live grouped path creates real border nodes before positioning |
| 9 | Redirect edges touching compound nodes to border entry/exit nodes | Complete | The live compound path now redirects subgraph-touching edges through top/bottom border nodes before ranking and restores original edges with explicit boundary points after positioning |
| 10 | Reduce `routeInterContainerEdges` to secondary routing only | Partial | The new default grouped path no longer depends on the hierarchical router; it remains only on the legacy fallback path, though boundary-anchor logic, vertical target docking, and other explicit waypoint fixes now feed the live compound path |
| 11 | Fix inter-edge classification to respect nested boundaries | Partial | Routing now preserves immediate boundary containers while meta-graph still uses root containers |
| 12 | Scope lane spacing per routing corridor | Complete | Routing lane counters are now tracked per obstacle corridor instead of globally |
| 13 | Update design docs | Not started | Revise `container-edges-first.md` based on chosen direction |
| 14 | Add unit tests for border nodes and rank bounds | Partial | Added unit tests for border dummy creation, nesting edges, cleanup, rank-bound derivation, left/right border segment creation, the live grouped compound path, normalized redirect metadata, and long-edge denormalization |
| 15 | Add regression tests for cross-group connector routing | Partial | Added regression coverage for corridor lane isolation, nested immediate-boundary classification, simple boundary anchors, nested boundary-anchor sequences, restored edges that touch subgraphs, and point preservation through long-edge undo |
| 16 | Render before/after diagrams for visual verification | Partial | Rendered grouped SVG check artifacts in `visual-checks/2026-03-16-compound/`; the Rust-style normalize/undo phase is now live, empty nesting ranks are now collapsed, several downward inter-container target approaches are now explicitly vertical, and sibling subgraph overlap is resolved again, though grouped flowcharts are still wider than ideal |

## Milestones

### Milestone 1: Compound Graph Foundations

- [ ] Items 1-5 complete
- [ ] Border dummy nodes exist in the graph
- [ ] Nesting edges participate in ranking

### Milestone 2: Compound-Aware Positioning

- [x] Items 6-9 complete
- [ ] Compound rank ranges are populated
- [ ] Type-2 conflicts use explicit border nodes

### Milestone 3: Routing Cleanup and Validation

- [ ] Items 10-16 complete
- [ ] Cross-group connectors no longer cut through unrelated groups
- [ ] Tests cover nested and sibling subgroup cases

## Risks

- The current hierarchical container-first path may conflict with a full compound Dagre port.
- Other diagram types may share the same layout path and need guarding to avoid regressions.
- Spline rendering may still visually bow into groups even after waypoint logic is corrected.

## Decision Log

- Preferred direction: port the Rust/dagre-style compound graph machinery instead of extending the current workaround.
- Transitional fallback: keep the existing inter-container router only as a secondary refinement pass.

## Update Log

- 2026-03-16: Tracker created from `subgroupsplan.md`.
- 2026-03-16: Added explicit compound dummy metadata, switched BK border detection from id-prefix heuristics to metadata, and preserved immediate containers for inter-edge routing.
- 2026-03-16: Scoped inter-container lane spacing per obstacle corridor and added regression tests for corridor isolation plus nested boundary classification.
- 2026-03-16: Added boundary anchor waypoints so grouped edges leave and enter via container walls in the current router, plus regression coverage for that behavior.
- 2026-03-16: Extended boundary anchors across nested container ancestry up to the lowest common container, with regression coverage for nested subgroup routing.
- 2026-03-16: Added a tested compound nesting helper module with root/top/bottom border dummy creation, nesting-edge cleanup, and `minlen` scaling groundwork for future live pipeline integration.
- 2026-03-16: Added a tested compound helper module for `min_rank`/`max_rank` derivation and left/right border segment creation, laying the remaining groundwork before BK integration.
- 2026-03-16: Added a green compound-layout prototype path that runs nesting, ranking, rank-bound derivation, and border-segment creation together, with end-to-end tests for rank ranges and explicit border dummy nodes.
- 2026-03-16: Switched grouped graphs to the compound layout path by default, fixed a use-after-free and dummy-node respacing bug exposed by that change, and left the old hierarchical router behind a legacy escape hatch.
- 2026-03-16: Added rank-time redirection for edges touching subgraphs so the live compound path routes through border entry/exit nodes before ranking, restores original edges with explicit boundary points after positioning, and covers the behavior with normalization plus integration tests.
- 2026-03-16: Rendered SVG visual-check artifacts for `flowchart_subgraphs`, `flowchart_nested`, and `state_complex` in `visual-checks/2026-03-16-compound/` and opened them for manual inspection in the workspace.
- 2026-03-16: Removed legacy post-layout subgraph shifting from the live compound path, moved restored compound-edge point generation until after final subgraph bounds are known, and regenerated the grouped SVG fixtures.
- 2026-03-16: Simplified restored compound-edge waypoint chains to stop replaying every internal dummy/border segment in the final SVG, which materially cleaned up state-diagram compound edges.
- 2026-03-16: Ported nested boundary-anchor insertion onto the live compound path for normal visible edges after layout so cross-container node-to-node edges can pick up ancestor wall entry/exit waypoints without relying on the legacy hierarchical router.
- 2026-03-16: Added a true normalize/undo phase modeled on the Rust reference, so long edges are restored from dummy chains with collected waypoint lists before final cleanup and rendering.
- 2026-03-16: Reordered the compound pipeline to clean up nesting edges before normalization, reverse explicit point lists before `acyclic.undo`, and regenerate grouped flowchart SVGs against the new denormalized path.
- 2026-03-16: Confirmed the missing `normalize.undo` was real, but the regenerated `flowchart_subgraphs.svg` still shows at least one cross-container flowchart edge with a bad waypoint sequence, so the remaining work is now focused on point assembly/routing rather than missing denormalization.
- 2026-03-16: Fixed the overlapping-container waypoint ordering bug for simple cross-container edges and verified on a rebuilt binary that `State Manager -> API Gateway` now has monotonic waypoints in `flowchart_subgraphs`.
- 2026-03-16: Re-enabled sibling subgraph separation in the compound path before final edge restoration/routing, added regression coverage for non-overlapping sibling subgraphs, and regenerated grouped flowchart SVGs with root-level container overlap removed.
- 2026-03-16: Added Rust-style empty-rank compaction after compound ranking so nesting `node_rank_factor` spacing no longer inflates grouped diagrams with unused vertical layers.
- 2026-03-16: Added a guarded vertical target-docking pass for inter-container routes so downward edges can enter lower targets with a vertical final segment when no foreign container would be crossed, and regenerated `flowchart_subgraphs.svg` to verify the new waypoint geometry.
- 2026-03-16: Refined vertical target docking to skip same-source fan-out edges that enter the same destination boundary, restoring separation between `API Gateway -> Log Aggregator` and `API Gateway -> Metrics Collector` while keeping the lone `State Manager -> API Gateway` orthogonal entry.
- 2026-03-16: Promoted ordinary nodes to inter-container routing obstacles so cross-container edges also route around sibling nodes like `Business Logic`, not just around container boxes, and regenerated `flowchart_subgraphs.svg` to verify the new detours.
- 2026-03-16: Added source-side orthogonal docking for inter-container routes when the first leg can break out cleanly, so edges like `API Gateway -> Metrics Collector` can leave horizontally from the source side before turning, and relaxed the fan-out regression to assert separation without overfitting waypoint counts.
- 2026-03-16: Generalized target-side docking into a semantic orthogonal entry pass that prefers horizontal or vertical final approach from the overall source-target offset, while keeping the same same-source fan-out suppression for shared destination boundaries.
- 2026-03-16: Fixed long-edge denormalization to restore source and target endpoints around dummy bend points, which corrected collapsed same-container edges like `Router -> State Manager` in `flowchart_subgraphs.svg`.