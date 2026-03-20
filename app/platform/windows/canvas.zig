/// Public façade for the freeform canvas subsystem.
///
/// windows_main.zig imports only this file.  Individual sub-modules
/// (state, hit_test, draw, interaction, inspector) are not imported
/// directly by the main window.
///
/// Responsibility split:
///   state       — pure data: graph, selection, viewport, drag, insertion
///   hit_test    — pure geometry: pick a canvas point against graph objects
///   draw        — D2D rendering: nodes, edges, subgraphs, handles
///   interaction — Win32 mouse/keyboard → CanvasState mutations
///   inspector   — Win32 child-window panel with property fields
pub const state = @import("canvas/state.zig");
pub const hit_test = @import("canvas/hit_test.zig");
pub const draw = @import("canvas/draw.zig");
pub const interaction = @import("canvas/interaction.zig");
pub const inspector = @import("canvas/inspector.zig");

// Re-export the most-used types at the top level for ergonomics.
pub const CanvasState = state.CanvasState;
pub const Viewport = state.Viewport;
pub const Selection = state.Selection;
pub const SelectionKind = state.SelectionKind;
pub const InsertionKind = state.InsertionKind;
pub const StudioEditableGraph = state.StudioEditableGraph;
pub const StudioEditableNode = state.StudioEditableNode;
pub const StudioEditableSubgraph = state.StudioEditableSubgraph;
pub const StudioEditableEdge = state.StudioEditableEdge;
pub const StudioColor = state.StudioColor;

pub const DrawContext = draw.DrawContext;
pub const InteractionResult = interaction.InteractionResult;
pub const InspectorControls = inspector.InspectorControls;
