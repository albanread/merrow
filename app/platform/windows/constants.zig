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
pub const menu_save_label: [*:0]const u8 = "&Save";
pub const menu_save_as_label: [*:0]const u8 = "Save &As...";
pub const menu_export_word_label: [*:0]const u8 = "Export to &Word...";
pub const settings_menu_label: [*:0]const u8 = "&Settings";
pub const menu_font_settings_label: [*:0]const u8 = "Project &Inspector";
pub const open_dialog_title: [*:0]const u8 = "Open Mermaid or Markdown Source";
pub const save_dialog_title: [*:0]const u8 = "Save Mermaid or Markdown Source";
pub const export_word_dialog_title: [*:0]const u8 = "Export Document to Word";
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
pub const main_timer_id_editor_refresh: usize = 2301;
pub const main_timer_id_ffm_persist: usize = 2302;

/// View menu
pub const view_menu_label: [*:0]const u8 = "&View";
pub const menu_id_mode_mermaid: usize = 2010;
pub const menu_id_mode_freeform: usize = 2011;
pub const menu_id_toggle_source_panel: usize = 2012;
pub const menu_label_mode_mermaid: [*:0]const u8 = "&Mermaid Source Mode";
pub const menu_label_mode_freeform: [*:0]const u8 = "&Freeform Canvas Mode";
pub const menu_label_toggle_source_panel: [*:0]const u8 = "Show &Source Panel";

pub const toolbar_slot_1_label: [*:0]const u8 = "Fit Page";
pub const toolbar_slot_2_label: [*:0]const u8 = "100%";
pub const toolbar_slot_3_label: [*:0]const u8 = "Center";

pub const Layout = struct {
    padding: i32 = 12,
    gutter: i32 = 12,
    status_height: i32 = 22,
    command_bar_height: i32 = 40,
    diagram_selector_height: i32 = 32,
    diagram_label_width: i32 = 120,
    diagram_nav_button_width: i32 = 56,
    diagram_header_padding: i32 = 8,
    command_button_width: i32 = 88,
    toolbar_button_width: i32 = 76,
    diagram_selector_width: i32 = 180,
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
