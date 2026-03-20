/// Inspector panel for the freeform canvas.
///
/// Call `registerInspectorClass` once during app init, then `createInspector`
/// to build the panel.  After creation call `setCanvasRef` so the inspector
/// can write property changes back and invalidate the canvas.
const std = @import("std");
const win32 = @import("win32");
const common = @import("../common.zig");
const state = @import("state.zig");

const foundation = win32.foundation;
const ui = win32.ui.windows_and_messaging;
const gdi = win32.graphics.gdi;
const dialogs = win32.ui.controls.dialogs;

const CanvasState = state.CanvasState;
const SelectionKind = state.SelectionKind;
const StudioColor = state.StudioColor;

// Class-specific style bits (zigwin32 defines these as i32).
const cbs_dropdownlist: u32 = @intCast(ui.CBS_DROPDOWNLIST);
const es_readonly: u32 = @intCast(ui.ES_READONLY);

const COLOR_3DFACE: usize = 15;

const inspector_class_name: [*:0]const u8 = "MerrowInspectorPanel";

// ---------------------------------------------------------------------------
// Control IDs
// ---------------------------------------------------------------------------

const ID = struct {
    const btn_fit: u16 = 4001;
    // Node / Subgraph
    const edt_ns_label: u16 = 4010;
    const cmb_ns_shape: u16 = 4011;
    const edt_ns_x: u16 = 4012;
    const edt_ns_y: u16 = 4013;
    const edt_ns_w: u16 = 4014;
    const edt_ns_h: u16 = 4015;
    const btn_ns_fill: u16 = 4016;
    const btn_ns_stroke: u16 = 4017;
    const edt_ns_border: u16 = 4018;
    // Edge
    const edt_e_label: u16 = 4030;
    const btn_e_color: u16 = 4031;
    const edt_e_thick: u16 = 4032;
    const cmb_e_line: u16 = 4033;
    const cmb_e_arrows: u16 = 4034;
};

// ---------------------------------------------------------------------------
// Module globals
// ---------------------------------------------------------------------------

var g_canvas_state: ?*CanvasState = null;
var g_canvas_hwnd: ?foundation.HWND = null;
var g_controls: ?*const InspectorControls = null;
var g_suppress: bool = false;
var g_custom_colors: [16]u32 = [_]u32{0x00FFFFFF} ** 16;

// ---------------------------------------------------------------------------
// Inspector controls (HWND handles for every child window)
// ---------------------------------------------------------------------------

pub const InspectorControls = struct {
    panel: ?foundation.HWND = null,
    // Header
    lbl_header: ?foundation.HWND = null,
    btn_fit: ?foundation.HWND = null,
    // -- Node / Subgraph section --
    lbl_ns_label: ?foundation.HWND = null,
    edt_ns_label: ?foundation.HWND = null,
    lbl_ns_shape: ?foundation.HWND = null,
    cmb_ns_shape: ?foundation.HWND = null,
    lbl_ns_pos: ?foundation.HWND = null,
    lbl_ns_x: ?foundation.HWND = null,
    edt_ns_x: ?foundation.HWND = null,
    lbl_ns_y: ?foundation.HWND = null,
    edt_ns_y: ?foundation.HWND = null,
    lbl_ns_size: ?foundation.HWND = null,
    lbl_ns_w: ?foundation.HWND = null,
    edt_ns_w: ?foundation.HWND = null,
    lbl_ns_h: ?foundation.HWND = null,
    edt_ns_h: ?foundation.HWND = null,
    lbl_ns_appear: ?foundation.HWND = null,
    lbl_ns_fill: ?foundation.HWND = null,
    btn_ns_fill: ?foundation.HWND = null,
    lbl_ns_stroke: ?foundation.HWND = null,
    btn_ns_stroke: ?foundation.HWND = null,
    lbl_ns_border: ?foundation.HWND = null,
    edt_ns_border: ?foundation.HWND = null,
    // -- Edge section --
    lbl_e_label: ?foundation.HWND = null,
    edt_e_label: ?foundation.HWND = null,
    lbl_e_style: ?foundation.HWND = null,
    lbl_e_color: ?foundation.HWND = null,
    btn_e_color: ?foundation.HWND = null,
    lbl_e_thick: ?foundation.HWND = null,
    edt_e_thick: ?foundation.HWND = null,
    lbl_e_line: ?foundation.HWND = null,
    cmb_e_line: ?foundation.HWND = null,
    lbl_e_arrows: ?foundation.HWND = null,
    cmb_e_arrows: ?foundation.HWND = null,
};

// ---------------------------------------------------------------------------
// Window class registration
// ---------------------------------------------------------------------------

pub fn registerInspectorClass(h_instance: ?foundation.HINSTANCE) bool {
    const wc = ui.WNDCLASSEXA{
        .cbSize = @sizeOf(ui.WNDCLASSEXA),
        .style = .{},
        .lpfnWndProc = inspectorWndProc,
        .cbClsExtra = 0,
        .cbWndExtra = 0,
        .hInstance = h_instance,
        .hIcon = null,
        .hCursor = ui.LoadCursorW(null, ui.IDC_ARROW),
        .hbrBackground = @ptrFromInt(COLOR_3DFACE + 1),
        .lpszMenuName = null,
        .lpszClassName = inspector_class_name,
        .hIconSm = null,
    };
    return ui.RegisterClassExA(&wc) != 0;
}

// ---------------------------------------------------------------------------
// Inspector window procedure
// ---------------------------------------------------------------------------

fn inspectorWndProc(
    hwnd: ?foundation.HWND,
    message: u32,
    w_param: foundation.WPARAM,
    l_param: foundation.LPARAM,
) callconv(.winapi) foundation.LRESULT {
    switch (message) {
        ui.WM_COMMAND => {
            if (g_suppress) return 0;
            const id: u16 = @truncate(w_param & 0xffff);
            const code: u32 = @as(u32, @truncate((w_param >> 16) & 0xffff));
            handleCommand(id, code, hwnd);
            return 0;
        },
        else => return ui.DefWindowProcA(hwnd, message, w_param, l_param),
    }
}

// ---------------------------------------------------------------------------
// Control creation helpers
// ---------------------------------------------------------------------------

const vis_child: u32 = common.styleBits(ui.WS_CHILD) | common.styleBits(ui.WS_VISIBLE);

fn mkLabel(
    p: ?foundation.HWND,
    hi: ?foundation.HINSTANCE,
    text: [*:0]const u8,
    x: i32,
    y: i32,
    w: i32,
    h: i32,
) ?foundation.HWND {
    return ui.CreateWindowExA(.{}, "STATIC", text, @bitCast(vis_child), x, y, w, h, p, null, hi, null);
}

fn mkEdit(
    p: ?foundation.HWND,
    hi: ?foundation.HINSTANCE,
    x: i32,
    y: i32,
    w: i32,
    h: i32,
    id: u16,
    readonly: bool,
) ?foundation.HWND {
    var style = vis_child | common.styleBits(ui.WS_BORDER) | common.styleBits(ui.WS_TABSTOP);
    if (readonly) style |= es_readonly;
    return ui.CreateWindowExA(
        common.makeExStyle(common.exStyleBits(ui.WS_EX_CLIENTEDGE)),
        "EDIT",
        "",
        @bitCast(style),
        x,
        y,
        w,
        h,
        p,
        @ptrFromInt(@as(usize, id)),
        hi,
        null,
    );
}

fn mkButton(
    p: ?foundation.HWND,
    hi: ?foundation.HINSTANCE,
    text: [*:0]const u8,
    x: i32,
    y: i32,
    w: i32,
    h: i32,
    id: u16,
) ?foundation.HWND {
    return ui.CreateWindowExA(
        .{},
        "BUTTON",
        text,
        @bitCast(vis_child | common.styleBits(ui.WS_TABSTOP)),
        x,
        y,
        w,
        h,
        p,
        @ptrFromInt(@as(usize, id)),
        hi,
        null,
    );
}

fn mkCombo(
    p: ?foundation.HWND,
    hi: ?foundation.HINSTANCE,
    x: i32,
    y: i32,
    w: i32,
    drop_h: i32,
    id: u16,
) ?foundation.HWND {
    const style = vis_child | common.styleBits(ui.WS_TABSTOP) | common.styleBits(ui.WS_VSCROLL) | cbs_dropdownlist;
    return ui.CreateWindowExA(
        .{},
        "COMBOBOX",
        null,
        @bitCast(style),
        x,
        y,
        w,
        drop_h,
        p,
        @ptrFromInt(@as(usize, id)),
        hi,
        null,
    );
}

fn addComboItem(combo: ?foundation.HWND, text: [*:0]const u8) void {
    _ = ui.SendMessageA(combo, ui.CB_ADDSTRING, 0, @bitCast(@intFromPtr(text)));
}

fn setComboSel(combo: ?foundation.HWND, index: usize) void {
    _ = ui.SendMessageA(combo, ui.CB_SETCURSEL, index, 0);
}

fn getComboSel(combo: ?foundation.HWND) ?usize {
    const r = ui.SendMessageA(combo orelse return null, ui.CB_GETCURSEL, 0, 0);
    if (r < 0) return null;
    return @intCast(r);
}

// ---------------------------------------------------------------------------
// Create the inspector panel and all child controls
// ---------------------------------------------------------------------------

pub fn createInspector(
    parent: ?foundation.HWND,
    h_instance: ?foundation.HINSTANCE,
) InspectorControls {
    var c = InspectorControls{};

    // Panel — custom window class, starts hidden.
    const panel_style = common.styleBits(ui.WS_CHILD) |
        common.styleBits(ui.WS_CLIPCHILDREN) |
        common.styleBits(ui.WS_BORDER);
    c.panel = ui.CreateWindowExA(
        .{},
        inspector_class_name,
        null,
        @bitCast(panel_style),
        0,
        0,
        260,
        600,
        parent,
        null,
        h_instance,
        null,
    ) orelse return c;

    const pnl = c.panel;
    const hi = h_instance;

    // Layout constants
    const pad: i32 = 10;
    const full_w: i32 = 240;
    const row_h: i32 = 22;
    const btn_h: i32 = 24;
    const lbl_h: i32 = 16;
    const sect_h: i32 = 16;
    const short_lbl: i32 = 20;
    const short_edt: i32 = 84;
    const col_gap: i32 = 12;
    const col2_x: i32 = pad + short_lbl + 4 + short_edt + col_gap;

    var y: i32 = 8;

    // ----- Always-visible header -----
    c.lbl_header = mkLabel(pnl, hi, "No selection", pad, y, full_w, 20);
    y += 24;
    c.btn_fit = mkButton(pnl, hi, "Fit Canvas", pad, y, 110, btn_h, ID.btn_fit);
    y += btn_h + 12;

    const section_start: i32 = y;

    // ===== NODE / SUBGRAPH SECTION =====

    // Label
    c.lbl_ns_label = mkLabel(pnl, hi, "Label", pad, y, 50, lbl_h);
    y += lbl_h + 2;
    c.edt_ns_label = mkEdit(pnl, hi, pad, y, full_w, row_h, ID.edt_ns_label, false);
    y += row_h + 6;

    // Shape combo (node only)
    c.lbl_ns_shape = mkLabel(pnl, hi, "Shape", pad, y + 2, 50, lbl_h);
    c.cmb_ns_shape = mkCombo(pnl, hi, pad + 54, y, full_w - 54, 200, ID.cmb_ns_shape);
    y += row_h + 8;

    // POSITION header
    c.lbl_ns_pos = mkLabel(pnl, hi, "POSITION", pad, y, full_w, sect_h);
    y += sect_h + 2;
    c.lbl_ns_x = mkLabel(pnl, hi, "X", pad, y + 2, short_lbl, lbl_h);
    c.edt_ns_x = mkEdit(pnl, hi, pad + short_lbl + 4, y, short_edt, row_h, ID.edt_ns_x, false);
    c.lbl_ns_y = mkLabel(pnl, hi, "Y", col2_x, y + 2, short_lbl, lbl_h);
    c.edt_ns_y = mkEdit(pnl, hi, col2_x + short_lbl + 4, y, short_edt, row_h, ID.edt_ns_y, false);
    y += row_h + 6;

    // SIZE header
    c.lbl_ns_size = mkLabel(pnl, hi, "SIZE", pad, y, full_w, sect_h);
    y += sect_h + 2;
    c.lbl_ns_w = mkLabel(pnl, hi, "W", pad, y + 2, short_lbl, lbl_h);
    c.edt_ns_w = mkEdit(pnl, hi, pad + short_lbl + 4, y, short_edt, row_h, ID.edt_ns_w, false);
    c.lbl_ns_h = mkLabel(pnl, hi, "H", col2_x, y + 2, short_lbl, lbl_h);
    c.edt_ns_h = mkEdit(pnl, hi, col2_x + short_lbl + 4, y, short_edt, row_h, ID.edt_ns_h, false);
    y += row_h + 8;

    // APPEARANCE header
    c.lbl_ns_appear = mkLabel(pnl, hi, "APPEARANCE", pad, y, full_w, sect_h);
    y += sect_h + 4;
    // Fill colour
    c.lbl_ns_fill = mkLabel(pnl, hi, "Fill", pad, y + 2, 44, lbl_h);
    c.btn_ns_fill = mkButton(pnl, hi, "#FFFFFF", pad + 48, y, full_w - 48, btn_h, ID.btn_ns_fill);
    y += btn_h + 4;
    // Stroke colour
    c.lbl_ns_stroke = mkLabel(pnl, hi, "Stroke", pad, y + 2, 44, lbl_h);
    c.btn_ns_stroke = mkButton(pnl, hi, "#000000", pad + 48, y, full_w - 48, btn_h, ID.btn_ns_stroke);
    y += btn_h + 4;
    // Border width
    c.lbl_ns_border = mkLabel(pnl, hi, "Border", pad, y + 2, 44, lbl_h);
    c.edt_ns_border = mkEdit(pnl, hi, pad + 48, y, 60, row_h, ID.edt_ns_border, false);

    // ===== EDGE SECTION (same vertical origin as node section) =====
    y = section_start;

    c.lbl_e_label = mkLabel(pnl, hi, "Label", pad, y, 50, lbl_h);
    y += lbl_h + 2;
    c.edt_e_label = mkEdit(pnl, hi, pad, y, full_w, row_h, ID.edt_e_label, false);
    y += row_h + 8;

    // STYLE header
    c.lbl_e_style = mkLabel(pnl, hi, "STYLE", pad, y, full_w, sect_h);
    y += sect_h + 4;
    // Colour
    c.lbl_e_color = mkLabel(pnl, hi, "Color", pad, y + 2, 44, lbl_h);
    c.btn_e_color = mkButton(pnl, hi, "#000000", pad + 48, y, full_w - 48, btn_h, ID.btn_e_color);
    y += btn_h + 4;
    // Thickness
    c.lbl_e_thick = mkLabel(pnl, hi, "Thickness", pad, y + 2, 60, lbl_h);
    c.edt_e_thick = mkEdit(pnl, hi, pad + 64, y, 60, row_h, ID.edt_e_thick, false);
    y += row_h + 6;
    // Line style combo
    c.lbl_e_line = mkLabel(pnl, hi, "Line", pad, y + 2, 44, lbl_h);
    c.cmb_e_line = mkCombo(pnl, hi, pad + 48, y, full_w - 48, 120, ID.cmb_e_line);
    y += row_h + 6;
    // Arrow mode combo
    c.lbl_e_arrows = mkLabel(pnl, hi, "Arrows", pad, y + 2, 44, lbl_h);
    c.cmb_e_arrows = mkCombo(pnl, hi, pad + 48, y, full_w - 48, 160, ID.cmb_e_arrows);

    populateCombos(&c);
    return c;
}

fn populateCombos(c: *InspectorControls) void {
    const shapes = [_][*:0]const u8{
        "Rectangle", "Rounded Rect",  "Diamond",    "Circle",
        "Hexagon",   "Parallelogram", "Trapezoid",  "Cylinder",
        "Stadium",   "Subroutine",    "Asymmetric", "Double Circle",
    };
    for (shapes) |s| addComboItem(c.cmb_ns_shape, s);

    addComboItem(c.cmb_e_line, "Solid");
    addComboItem(c.cmb_e_line, "Dashed");
    addComboItem(c.cmb_e_line, "Dotted");

    addComboItem(c.cmb_e_arrows, "None");
    addComboItem(c.cmb_e_arrows, "Target -->");
    addComboItem(c.cmb_e_arrows, "<-- Source");
    addComboItem(c.cmb_e_arrows, "<-- Both -->");
}

// ---------------------------------------------------------------------------
// Set references for write-back
// ---------------------------------------------------------------------------

pub fn setCanvasRef(
    canvas_state: *CanvasState,
    canvas_hwnd: ?foundation.HWND,
    controls: *const InspectorControls,
) void {
    g_canvas_state = canvas_state;
    g_canvas_hwnd = canvas_hwnd;
    g_controls = controls;
}

// ---------------------------------------------------------------------------
// Show / hide
// ---------------------------------------------------------------------------

pub fn show(controls_ref: *const InspectorControls, visible: bool) void {
    const cmd = if (visible) ui.SW_SHOWNA else ui.SW_HIDE;
    _ = ui.ShowWindow(controls_ref.panel, cmd);
}

// ---------------------------------------------------------------------------
// Layout
// ---------------------------------------------------------------------------

pub fn layoutInspector(
    controls_ref: *const InspectorControls,
    client_width: i32,
    content_top: i32,
    content_height: i32,
    inspector_width: i32,
) void {
    const panel = controls_ref.panel orelse return;
    _ = ui.SetWindowPos(
        panel,
        null,
        client_width - inspector_width,
        content_top,
        inspector_width,
        content_height,
        ui.SWP_NOZORDER,
    );
}

// ---------------------------------------------------------------------------
// Refresh — update every control from the current selection
// ---------------------------------------------------------------------------

fn swShow(hwnd: ?foundation.HWND, cmd: ui.SHOW_WINDOW_CMD) void {
    _ = ui.ShowWindow(hwnd, cmd);
}

fn showNodeSection(c: *const InspectorControls, vis: bool, is_node: bool) void {
    const cmd = if (vis) ui.SW_SHOWNA else ui.SW_HIDE;
    const shape_cmd = if (vis and is_node) ui.SW_SHOWNA else ui.SW_HIDE;
    swShow(c.lbl_ns_label, cmd);
    swShow(c.edt_ns_label, cmd);
    swShow(c.lbl_ns_shape, shape_cmd);
    swShow(c.cmb_ns_shape, shape_cmd);
    swShow(c.lbl_ns_pos, cmd);
    swShow(c.lbl_ns_x, cmd);
    swShow(c.edt_ns_x, cmd);
    swShow(c.lbl_ns_y, cmd);
    swShow(c.edt_ns_y, cmd);
    swShow(c.lbl_ns_size, cmd);
    swShow(c.lbl_ns_w, cmd);
    swShow(c.edt_ns_w, cmd);
    swShow(c.lbl_ns_h, cmd);
    swShow(c.edt_ns_h, cmd);
    swShow(c.lbl_ns_appear, cmd);
    swShow(c.lbl_ns_fill, cmd);
    swShow(c.btn_ns_fill, cmd);
    swShow(c.lbl_ns_stroke, cmd);
    swShow(c.btn_ns_stroke, cmd);
    swShow(c.lbl_ns_border, cmd);
    swShow(c.edt_ns_border, cmd);
}

fn showEdgeSection(c: *const InspectorControls, vis: bool) void {
    const cmd = if (vis) ui.SW_SHOWNA else ui.SW_HIDE;
    swShow(c.lbl_e_label, cmd);
    swShow(c.edt_e_label, cmd);
    swShow(c.lbl_e_style, cmd);
    swShow(c.lbl_e_color, cmd);
    swShow(c.btn_e_color, cmd);
    swShow(c.lbl_e_thick, cmd);
    swShow(c.edt_e_thick, cmd);
    swShow(c.lbl_e_line, cmd);
    swShow(c.cmb_e_line, cmd);
    swShow(c.lbl_e_arrows, cmd);
    swShow(c.cmb_e_arrows, cmd);
}

pub fn refresh(controls_ref: *const InspectorControls, canvas: *const CanvasState) void {
    g_suppress = true;
    defer g_suppress = false;

    switch (canvas.selection.kind) {
        .none => {
            setLabelText(controls_ref.lbl_header, "No selection");
            showNodeSection(controls_ref, false, false);
            showEdgeSection(controls_ref, false);
        },
        .node => {
            const n = canvas.selectedNode() orelse return;
            setLabelText(controls_ref.lbl_header, "Node");
            showNodeSection(controls_ref, true, true);
            showEdgeSection(controls_ref, false);
            setEditSlice(controls_ref.edt_ns_label, cstrToSlice(n.label));
            setComboSel(controls_ref.cmb_ns_shape, @intCast(n.shape));
            setEditF64(controls_ref.edt_ns_x, n.x);
            setEditF64(controls_ref.edt_ns_y, n.y);
            setEditF64(controls_ref.edt_ns_w, n.width);
            setEditF64(controls_ref.edt_ns_h, n.height);
            setColorButtonText(controls_ref.btn_ns_fill, n.fill);
            setColorButtonText(controls_ref.btn_ns_stroke, n.stroke);
            setEditF32(controls_ref.edt_ns_border, n.stroke_width);
        },
        .subgraph => {
            const sg = canvas.selectedSubgraph() orelse return;
            setLabelText(controls_ref.lbl_header, "Subgraph / Group");
            showNodeSection(controls_ref, true, false);
            showEdgeSection(controls_ref, false);
            setEditSlice(controls_ref.edt_ns_label, cstrToSlice(sg.title));
            setEditF64(controls_ref.edt_ns_x, sg.x);
            setEditF64(controls_ref.edt_ns_y, sg.y);
            setEditF64(controls_ref.edt_ns_w, sg.width);
            setEditF64(controls_ref.edt_ns_h, sg.height);
            setColorButtonText(controls_ref.btn_ns_fill, sg.fill);
            setColorButtonText(controls_ref.btn_ns_stroke, sg.stroke);
            setEditF32(controls_ref.edt_ns_border, sg.stroke_width);
        },
        .edge => {
            const e = canvas.selectedEdge() orelse return;
            setLabelText(controls_ref.lbl_header, "Edge");
            showNodeSection(controls_ref, false, false);
            showEdgeSection(controls_ref, true);
            setEditSlice(controls_ref.edt_e_label, cstrToSlice(e.label));
            setColorButtonText(controls_ref.btn_e_color, e.color);
            setEditF32(controls_ref.edt_e_thick, e.thickness);
            setComboSel(controls_ref.cmb_e_line, @intCast(e.line_style));
            setComboSel(controls_ref.cmb_e_arrows, arrowModeIndex(e));
        },
    }
}

// ---------------------------------------------------------------------------
// Command handling (called from inspectorWndProc)
// ---------------------------------------------------------------------------

fn handleCommand(id: u16, code: u32, owner: ?foundation.HWND) void {
    // Button clicks
    if (code == @as(u32, ui.BN_CLICKED)) {
        switch (id) {
            ID.btn_fit => fitCanvas(),
            ID.btn_ns_fill => pickColor(.node_fill, owner),
            ID.btn_ns_stroke => pickColor(.node_stroke, owner),
            ID.btn_e_color => pickColor(.edge_color, owner),
            else => {},
        }
        return;
    }
    // Combo box selection change
    if (code == ui.CBN_SELCHANGE) {
        switch (id) {
            ID.cmb_ns_shape => applyShape(),
            ID.cmb_e_line => applyLineStyle(),
            ID.cmb_e_arrows => applyArrowMode(),
            else => {},
        }
        return;
    }
    // Edit control lost focus — commit numeric values
    if (code == ui.EN_KILLFOCUS) {
        switch (id) {
            ID.edt_ns_label, ID.edt_e_label => applySelectedLabel(id),
            ID.edt_ns_x, ID.edt_ns_y, ID.edt_ns_w, ID.edt_ns_h, ID.edt_ns_border => applyNodeNumeric(id),
            ID.edt_e_thick => applyEdgeThickness(),
            else => {},
        }
        return;
    }
}

// ---------------------------------------------------------------------------
// Apply helpers
// ---------------------------------------------------------------------------

fn fitCanvas() void {
    const cs = g_canvas_state orelse return;
    const ch = g_canvas_hwnd orelse return;
    var rect = std.mem.zeroes(foundation.RECT);
    if (ui.GetClientRect(ch, &rect) == 0) return;
    const w: f64 = @floatFromInt(@max(1, rect.right - rect.left));
    const h: f64 = @floatFromInt(@max(1, rect.bottom - rect.top));
    cs.fitToViewport(w, h);
    invalidateCanvas();
}

const ColorTarget = enum { node_fill, node_stroke, edge_color };

fn pickColor(target: ColorTarget, owner: ?foundation.HWND) void {
    const cs = g_canvas_state orelse return;

    const current: StudioColor = switch (target) {
        .node_fill => if (cs.selectedNode()) |n| n.fill else if (cs.selectedSubgraph()) |sg| sg.fill else return,
        .node_stroke => if (cs.selectedNode()) |n| n.stroke else if (cs.selectedSubgraph()) |sg| sg.stroke else return,
        .edge_color => if (cs.selectedEdge()) |e| e.color else return,
    };

    const new_col = openColorPicker(owner, current) orelse return;

    switch (target) {
        .node_fill => {
            if (cs.selectedNode()) |n| {
                n.fill = new_col;
            } else if (cs.selectedSubgraph()) |sg| {
                sg.fill = new_col;
            }
        },
        .node_stroke => {
            if (cs.selectedNode()) |n| {
                n.stroke = new_col;
            } else if (cs.selectedSubgraph()) |sg| {
                sg.stroke = new_col;
            }
        },
        .edge_color => {
            if (cs.selectedEdge()) |e| {
                e.color = new_col;
            }
        },
    }
    invalidateCanvas();
    refreshSelf();
}

fn applyShape() void {
    const cs = g_canvas_state orelse return;
    const ctrl = g_controls orelse return;
    const n = cs.selectedNode() orelse return;
    const sel = getComboSel(ctrl.cmb_ns_shape) orelse return;
    n.shape = @intCast(sel);
    invalidateCanvas();
}

fn applySelectedLabel(id: u16) void {
    const cs = g_canvas_state orelse return;
    const ctrl = g_controls orelse return;
    const hwnd = switch (id) {
        ID.edt_ns_label => ctrl.edt_ns_label,
        ID.edt_e_label => ctrl.edt_e_label,
        else => return,
    };
    const text = readEditTextOwned(hwnd) orelse return;
    if (!cs.replaceSelectedLabelOwned(text)) return;
    invalidateCanvas();
    refreshSelf();
}

fn applyLineStyle() void {
    const cs = g_canvas_state orelse return;
    const ctrl = g_controls orelse return;
    const e = cs.selectedEdge() orelse return;
    const sel = getComboSel(ctrl.cmb_e_line) orelse return;
    e.line_style = @intCast(sel);
    invalidateCanvas();
}

fn applyArrowMode() void {
    const cs = g_canvas_state orelse return;
    const ctrl = g_controls orelse return;
    const e = cs.selectedEdge() orelse return;
    const sel = getComboSel(ctrl.cmb_e_arrows) orelse return;
    e.has_arrow = if (sel & 1 != 0) 1 else 0;
    e.has_source_arrow = if (sel & 2 != 0) 1 else 0;
    invalidateCanvas();
}

fn applyNodeNumeric(id: u16) void {
    const cs = g_canvas_state orelse return;
    const ctrl = g_controls orelse return;
    if (cs.selection.kind == .node) {
        const n = cs.selectedNode() orelse return;
        switch (id) {
            ID.edt_ns_x => n.x = readEditF64(ctrl.edt_ns_x) orelse return,
            ID.edt_ns_y => n.y = readEditF64(ctrl.edt_ns_y) orelse return,
            ID.edt_ns_w => n.width = readEditF64(ctrl.edt_ns_w) orelse return,
            ID.edt_ns_h => n.height = readEditF64(ctrl.edt_ns_h) orelse return,
            ID.edt_ns_border => n.stroke_width = @floatCast(readEditF64(ctrl.edt_ns_border) orelse return),
            else => return,
        }
    } else if (cs.selection.kind == .subgraph) {
        const sg = cs.selectedSubgraph() orelse return;
        switch (id) {
            ID.edt_ns_x => sg.x = readEditF64(ctrl.edt_ns_x) orelse return,
            ID.edt_ns_y => sg.y = readEditF64(ctrl.edt_ns_y) orelse return,
            ID.edt_ns_w => sg.width = readEditF64(ctrl.edt_ns_w) orelse return,
            ID.edt_ns_h => sg.height = readEditF64(ctrl.edt_ns_h) orelse return,
            ID.edt_ns_border => sg.stroke_width = @floatCast(readEditF64(ctrl.edt_ns_border) orelse return),
            else => return,
        }
    } else return;
    invalidateCanvas();
}

fn applyEdgeThickness() void {
    const cs = g_canvas_state orelse return;
    const ctrl = g_controls orelse return;
    const e = cs.selectedEdge() orelse return;
    e.thickness = @floatCast(readEditF64(ctrl.edt_e_thick) orelse return);
    invalidateCanvas();
}

// ---------------------------------------------------------------------------
// Colour picker dialog
// ---------------------------------------------------------------------------

fn openColorPicker(owner: ?foundation.HWND, current: StudioColor) ?StudioColor {
    var cc = std.mem.zeroes(dialogs.CHOOSECOLORA);
    cc.lStructSize = @sizeOf(dialogs.CHOOSECOLORA);
    cc.hwndOwner = owner;
    cc.rgbResult = colorToRef(current);
    cc.lpCustColors = &g_custom_colors[0];
    cc.Flags = @bitCast(@as(u32, @bitCast(dialogs.CC_RGBINIT)) | @as(u32, @bitCast(dialogs.CC_FULLOPEN)));
    if (dialogs.ChooseColorA(&cc) != 0) {
        return refToColor(cc.rgbResult);
    }
    return null;
}

fn colorToRef(c: StudioColor) u32 {
    return @as(u32, c.r) | (@as(u32, c.g) << 8) | (@as(u32, c.b) << 16);
}

fn refToColor(cr: u32) StudioColor {
    return .{
        .r = @truncate(cr),
        .g = @truncate(cr >> 8),
        .b = @truncate(cr >> 16),
        .a = 255,
    };
}

// ---------------------------------------------------------------------------
// Arrow mode helpers
// ---------------------------------------------------------------------------

fn arrowModeIndex(e: *const state.StudioEditableEdge) usize {
    const t: usize = if (e.has_arrow != 0) 1 else 0;
    const s: usize = if (e.has_source_arrow != 0) 2 else 0;
    return t | s;
}

// ---------------------------------------------------------------------------
// Text / number utility functions
// ---------------------------------------------------------------------------

fn setEditSlice(hwnd: ?foundation.HWND, text: []const u8) void {
    const tmp = std.heap.c_allocator.allocSentinel(u8, text.len, 0) catch return;
    defer std.heap.c_allocator.free(tmp);
    @memcpy(tmp[0..text.len], text);
    _ = ui.SetWindowTextA(hwnd, tmp.ptr);
}

fn setEditF64(hwnd: ?foundation.HWND, value: f64) void {
    var buf: [32]u8 = undefined;
    const s = std.fmt.bufPrint(&buf, "{d:.1}", .{value}) catch return;
    setEditSlice(hwnd, s);
}

fn setEditF32(hwnd: ?foundation.HWND, value: f32) void {
    setEditF64(hwnd, @floatCast(value));
}

fn setLabelText(hwnd: ?foundation.HWND, text: [*:0]const u8) void {
    _ = ui.SetWindowTextA(hwnd, text);
}

fn setColorButtonText(hwnd: ?foundation.HWND, color: StudioColor) void {
    var buf: [10]u8 = undefined;
    const s = std.fmt.bufPrint(&buf, "#{X:0>2}{X:0>2}{X:0>2}", .{ color.r, color.g, color.b }) catch return;
    setEditSlice(hwnd, s);
}

fn cstrToSlice(ptr: [*c]const u8) []const u8 {
    if (ptr == null) return "";
    return std.mem.span(ptr);
}

fn readEditF64(hwnd: ?foundation.HWND) ?f64 {
    const h = hwnd orelse return null;
    const text_len = ui.GetWindowTextLengthA(h);
    if (text_len <= 0) return null;
    const safe_len: usize = @intCast(text_len);
    const buffer = std.heap.c_allocator.allocSentinel(u8, safe_len, 0) catch return null;
    defer std.heap.c_allocator.free(buffer);
    const copied = ui.GetWindowTextA(h, buffer.ptr, @intCast(buffer.len + 1));
    if (copied <= 0) return null;
    const ulen: usize = @intCast(copied);
    return std.fmt.parseFloat(f64, buffer[0..ulen]) catch null;
}

fn readEditTextOwned(hwnd: ?foundation.HWND) ?[:0]u8 {
    const h = hwnd orelse return null;
    const text_len = ui.GetWindowTextLengthA(h);
    if (text_len < 0) return null;
    const safe_len: usize = @intCast(text_len);
    const buffer = std.heap.c_allocator.allocSentinel(u8, safe_len, 0) catch return null;
    const copied = ui.GetWindowTextA(h, buffer.ptr, @intCast(buffer.len + 1));
    if (copied < 0) {
        std.heap.c_allocator.free(buffer);
        return null;
    }
    return buffer;
}

fn invalidateCanvas() void {
    if (g_canvas_hwnd) |ch| {
        _ = gdi.InvalidateRect(ch, null, 0);
    }
}

fn refreshSelf() void {
    const ctrl = g_controls orelse return;
    const cs = g_canvas_state orelse return;
    refresh(ctrl, cs);
}
