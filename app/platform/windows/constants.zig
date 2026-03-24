const win32 = @import("win32");

const controls = win32.ui.controls;
const rich_edit = win32.ui.controls.rich_edit;

pub const class_name: [*:0]const u8 = "MerrowStudioWindowClass";
pub const preview_class_name: [*:0]const u8 = "MerrowStudioPreviewWindowClass";
pub const canvas_class_name: [*:0]const u8 = "MerrowStudioCanvasWindowClass";
pub const window_title: [*:0]const u8 = "Merrow Studio (Windows Scaffold)";
pub const static_class: [*:0]const u8 = "STATIC";
pub const edit_class: [*:0]const u8 = "EDIT";
pub const rich_edit_class: [*:0]const u8 = rich_edit.RICHEDIT_CLASSA;
pub const button_class: [*:0]const u8 = "BUTTON";
pub const toolbar_class: [*:0]const u8 = controls.TOOLBARCLASSNAMEA;
pub const combo_box_class: [*:0]const u8 = "COMBOBOX";
pub const status_placeholder: [*:0]const u8 = "Windows scaffold ready";
pub const file_menu_label: [*:0]const u8 = "&File";
pub const menu_open_label: [*:0]const u8 = "&Open...";
pub const menu_open_recent_label: [*:0]const u8 = "Open &Recent";
pub const menu_save_label: [*:0]const u8 = "&Save";
pub const menu_save_as_label: [*:0]const u8 = "Save &As...";
pub const menu_export_word_label: [*:0]const u8 = "Export to &Word...";
pub const menu_export_mermaid_label: [*:0]const u8 = "Export to &Mermaid...";
pub const settings_menu_label: [*:0]const u8 = "&Settings";
pub const help_menu_label: [*:0]const u8 = "&Help";
pub const menu_about_label: [*:0]const u8 = "&About Merrow Studio";
pub const menu_font_settings_label: [*:0]const u8 = "Project &Inspector";
pub const menu_cloud_storage_label: [*:0]const u8 = "&Cloud Storage...";
pub const menu_sync_cloud_label: [*:0]const u8 = "&Sync Cloud";
pub const open_dialog_title: [*:0]const u8 = "Open Mermaid or Markdown Source";
pub const save_dialog_title: [*:0]const u8 = "Save Mermaid or Markdown Source";
pub const export_word_dialog_title: [*:0]const u8 = "Export Document to Word";
pub const export_mermaid_dialog_title: [*:0]const u8 = "Export to Mermaid";
pub const mermaid_export_filter: [*:0]const u8 = "Mermaid Files (*.mmd)\x00*.mmd\x00All Files (*.*)\x00*.*\x00\x00";
pub const mermaid_default_extension: [*:0]const u8 = "mmd";
pub const default_extension: [*:0]const u8 = "mmd";
pub const word_default_extension: [*:0]const u8 = "docx";
pub const mermaid_dialog_filter: [*:0]const u8 = "Diagram Documents (*.mmd;*.md)\x00*.mmd;*.md\x00Markdown Files (*.md)\x00*.md\x00Mermaid Files (*.mmd)\x00*.mmd\x00All Files (*.*)\x00*.*\x00\x00";
pub const word_dialog_filter: [*:0]const u8 = "Word Documents (*.docx)\x00*.docx\x00All Files (*.*)\x00*.*\x00\x00";
pub const initial_source: [*:0]const u8 =
    "flowchart TD\r\n" ++
    "    Start([Start])\r\n" ++
    "    Step[Windows scaffold]\r\n" ++
    "    Start --> Step\r\n";

pub const menu_id_open: usize = 2001;
pub const menu_id_save: usize = 2002;
pub const menu_id_save_as: usize = 2003;
pub const menu_id_font_settings: usize = 2004;
pub const menu_id_export_word: usize = 2005;
pub const menu_id_export_mermaid: usize = 2006;
pub const menu_id_open_recent_empty: usize = 2007;
pub const menu_id_cloud_storage: usize = 2008;
pub const menu_id_sync_cloud: usize = 2015;
pub const menu_id_open_recent_first: usize = 2060;
pub const menu_id_open_recent_last: usize = 2069;
pub const toolbar_id_reserved_1: usize = 2101;
pub const toolbar_id_reserved_2: usize = 2102;
pub const toolbar_id_reserved_3: usize = 2103;
pub const control_id_editor: usize = 2201;
pub const control_id_command: usize = 2202;
pub const control_id_apply_button: usize = 2203;
pub const control_id_diagram_selector: usize = 2204;
pub const control_id_diagram_prev: usize = 2205;
pub const control_id_diagram_next: usize = 2206;
pub const control_id_diagram_label: usize = 2207;
pub const control_id_about_image: usize = 2208;
pub const control_id_about_title: usize = 2209;
pub const control_id_about_version: usize = 2210;
pub const control_id_about_license: usize = 2211;
pub const control_id_about_ok: usize = 2212;
pub const control_id_cloud_storage_api_label: usize = 2213;
pub const control_id_cloud_storage_api_edit: usize = 2214;
pub const control_id_cloud_storage_key_label: usize = 2215;
pub const control_id_cloud_storage_key_edit: usize = 2216;
pub const control_id_cloud_storage_ok: usize = 2217;
pub const control_id_cloud_storage_region_label: usize = 2218;
pub const control_id_cloud_storage_region_edit: usize = 2219;
pub const control_id_cloud_storage_bucket_label: usize = 2220;
pub const control_id_cloud_storage_bucket_edit: usize = 2221;
pub const main_timer_id_editor_refresh: usize = 2301;
pub const main_timer_id_ffm_persist: usize = 2302;
pub const main_timer_id_graph_source_writeback: usize = 2303;

/// View menu
pub const view_menu_label: [*:0]const u8 = "&View";
pub const menu_id_toggle_source_panel: usize = 2012;
pub const menu_id_about: usize = 2013;
pub const menu_id_toggle_snap_to_grid: usize = 2014;
pub const menu_label_toggle_source_panel: [*:0]const u8 = "Show &Source Panel";
pub const menu_label_toggle_snap_to_grid: [*:0]const u8 = "Snap To &Grid";

pub const toolbar_slot_1_label: [*:0]const u8 = "Fit";
pub const toolbar_slot_2_label: [*:0]const u8 = "2x";
pub const toolbar_slot_3_label: [*:0]const u8 = "4x";

/// Canvas right-click context menu — flowchart "Add ..." items.
/// IDs map 1:1 to NodeShape enum values (shape code in low 8 bits, 0x25xx prefix).
pub const ctx_menu_add_box: usize = 2501; // NodeShape.box
pub const ctx_menu_add_round: usize = 2502; // NodeShape.round
pub const ctx_menu_add_diamond: usize = 2503; // NodeShape.diamond
pub const ctx_menu_add_circle: usize = 2504; // NodeShape.circle
pub const ctx_menu_add_hexagon: usize = 2505; // NodeShape.hexagon
pub const ctx_menu_add_cylinder: usize = 2506; // NodeShape.cylinder
pub const ctx_menu_add_stadium: usize = 2507; // NodeShape.stadium
pub const ctx_menu_add_subgraph: usize = 2508; // inserts a subgraph group
/// Context menu for selected objects.
pub const ctx_menu_delete: usize = 2509;
pub const ctx_menu_begin_link: usize = 2510;
pub const ctx_menu_end_link: usize = 2511;
pub const ctx_menu_cancel_link: usize = 2512;

pub const Layout = struct {
    padding: i32 = 12,
    gutter: i32 = 12,
    status_height: i32 = 22,
    command_bar_height: i32 = 40,
    diagram_selector_height: i32 = 32,
    diagram_label_width: i32 = 72,
    diagram_nav_button_width: i32 = 56,
    diagram_header_padding: i32 = 8,
    command_button_width: i32 = 88,
    toolbar_button_width: i32 = 56,
    diagram_selector_width: i32 = 120,
    toolbar_inner_padding: i32 = 6,
    min_preview_width: i32 = 420,
    min_editor_width: i32 = 780,
    min_content_height: i32 = 320,
    min_command_width: i32 = 220,
    left_ratio_num: i32 = 3,
    left_ratio_den: i32 = 5,
    /// Width of the freeform-mode inspector panel on the right side.
    inspector_width: i32 = 260,
};

pub const ViewAnchor = struct {
    x: i32,
    y: i32,
};

pub const WindowSize = struct {
    width: i32,
    height: i32,
};

pub const empty_c_string: [1]u8 = .{0};
pub const font_family_name_w = [_:0]u16{ 'L', 'a', 't', 'o' };
pub const locale_name_w = [_:0]u16{ 'e', 'n', '-', 'U', 'S' };
