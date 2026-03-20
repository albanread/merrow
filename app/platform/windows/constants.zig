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
pub const status_placeholder: [*:0]const u8 = "Windows scaffold ready";
pub const file_menu_label: [*:0]const u8 = "&File";
pub const menu_open_label: [*:0]const u8 = "&Open...";
pub const menu_save_label: [*:0]const u8 = "&Save";
pub const menu_save_as_label: [*:0]const u8 = "Save &As...";
pub const open_dialog_title: [*:0]const u8 = "Open Mermaid Source";
pub const save_dialog_title: [*:0]const u8 = "Save Mermaid Source";
pub const default_extension: [*:0]const u8 = "mmd";
pub const mermaid_dialog_filter: [*:0]const u8 = "Mermaid Files (*.mmd)\x00*.mmd\x00All Files (*.*)\x00*.*\x00\x00";
pub const initial_source: [*:0]const u8 =
    "flowchart TD\r\n" ++
    "    Start([Start])\r\n" ++
    "    Step[Windows scaffold]\r\n" ++
    "    Start --> Step\r\n";

pub const menu_id_open: usize = 2001;
pub const menu_id_save: usize = 2002;
pub const menu_id_save_as: usize = 2003;
pub const toolbar_id_reserved_1: usize = 2101;
pub const toolbar_id_reserved_2: usize = 2102;
pub const toolbar_id_reserved_3: usize = 2103;

/// View menu
pub const view_menu_label: [*:0]const u8 = "&View";
pub const menu_id_mode_mermaid: usize = 2010;
pub const menu_id_mode_freeform: usize = 2011;
pub const menu_label_mode_mermaid: [*:0]const u8 = "&Mermaid Source Mode";
pub const menu_label_mode_freeform: [*:0]const u8 = "&Freeform Canvas Mode";

pub const toolbar_slot_1_label: [*:0]const u8 = "Slot 1";
pub const toolbar_slot_2_label: [*:0]const u8 = "Slot 2";
pub const toolbar_slot_3_label: [*:0]const u8 = "Slot 3";

pub const Layout = struct {
    padding: i32 = 12,
    gutter: i32 = 12,
    status_height: i32 = 22,
    command_bar_height: i32 = 40,
    command_button_width: i32 = 88,
    toolbar_button_width: i32 = 76,
    toolbar_inner_padding: i32 = 6,
    min_preview_width: i32 = 420,
    min_editor_width: i32 = 560,
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
