const std = @import("std");
const win32 = @import("win32");
const document_model = @import("../../document_model.zig");

const foundation = win32.foundation;
const gdi = win32.graphics.gdi;
const loader = win32.system.library_loader;
const rich_edit = win32.ui.controls.rich_edit;
const ui = win32.ui.windows_and_messaging;

pub const EditorTheme = struct {
    background: u32,
    default_text: u32,
    heading_text: u32,
    fence_text: u32,
    fence_background: u32,
    mermaid_background: u32,
    keyword_text: u32,
    direction_text: u32,
    comment_text: u32,
    string_text: u32,
    symbol_text: u32,
    identifier_text: u32,
    error_text: u32,
    error_background: u32,
};

pub const EditorDiagnostic = struct {
    message: []const u8,
    line: ?usize = null,
    column: ?usize = null,
    start: usize = 0,
    end: usize = 0,
};

pub const EditorTokenStyle = struct {
    color: u32,
    bold: bool,
    italic: bool = false,
    back_color: ?u32 = null,
    font_height: ?i32 = null,
};

pub const editor_theme = EditorTheme{
    .background = 0x00f4f6f8,
    .default_text = 0x003a3128,
    .heading_text = 0x002b2118,
    .fence_text = 0x00715c4a,
    .fence_background = 0x00e5ecef,
    .mermaid_background = 0x00eef3f6,
    .keyword_text = 0x003069b8,
    .direction_text = 0x00856700,
    .comment_text = 0x00807a74,
    .string_text = 0x00824716,
    .symbol_text = 0x00914e7e,
    .identifier_text = 0x003a3128,
    .error_text = 0x002640ba,
    .error_background = 0x00d7e8ff,
};

const SpanKind = enum {
    keyword,
    direction,
    comment,
    annotation,
    string_literal,
    symbol,
    identifier,
};

const Span = struct {
    start: usize,
    end: usize,
    kind: SpanKind,
};

const OffsetRange = struct {
    start: usize,
    end: usize,
};

const Delimiter = struct {
    char: u8,
    offset: usize,
};

const MermaidScanner = struct {
    source: []const u8,
    index: usize = 0,
    at_line_start: bool = true,

    fn init(source: []const u8) MermaidScanner {
        return .{ .source = source };
    }

    fn next(self: *MermaidScanner) ?Span {
        while (self.index < self.source.len) {
            const start = self.index;
            const char = self.source[self.index];

            switch (char) {
                ' ', '\t', '\r' => {
                    self.index += 1;
                    continue;
                },
                '\n' => {
                    self.index += 1;
                    self.at_line_start = true;
                    continue;
                },
                '%' => {
                    if (self.at_line_start and self.peek(1) == '%') {
                        self.index += 2;
                        // Skip whitespace after %%
                        while (self.index < self.source.len and (self.source[self.index] == ' ' or self.source[self.index] == '\t')) {
                            self.index += 1;
                        }
                        // Check for Merrow annotation: %% @keyword=...
                        const is_annotation = self.index < self.source.len and self.source[self.index] == '@';
                        while (self.index < self.source.len and self.source[self.index] != '\n') {
                            self.index += 1;
                        }
                        self.at_line_start = false;
                        return .{ .start = start, .end = self.index, .kind = if (is_annotation) .annotation else .comment };
                    }
                },
                '"' => {
                    self.index += 1;
                    while (self.index < self.source.len) {
                        if (self.source[self.index] == '\\' and self.index + 1 < self.source.len) {
                            self.index += 2;
                            continue;
                        }
                        if (self.source[self.index] == '"') {
                            self.index += 1;
                            break;
                        }
                        self.index += 1;
                    }
                    self.at_line_start = false;
                    return .{ .start = start, .end = self.index, .kind = .string_literal };
                },
                else => {},
            }

            if (isIdentifierStart(char)) {
                self.index += 1;
                while (self.index < self.source.len and isIdentifierContinue(self.source[self.index])) {
                    self.index += 1;
                }
                const word = self.source[start..self.index];
                const kind = classifyWord(word, self.at_line_start);
                self.at_line_start = false;
                return .{ .start = start, .end = self.index, .kind = kind };
            }

            if (self.matchLongestSymbol()) |symbol_end| {
                self.index = symbol_end;
                self.at_line_start = false;
                return .{ .start = start, .end = symbol_end, .kind = .symbol };
            }

            if (isSingleSymbol(char)) {
                self.index += 1;
                self.at_line_start = false;
                return .{ .start = start, .end = self.index, .kind = .symbol };
            }

            self.index += 1;
            self.at_line_start = false;
        }
        return null;
    }

    fn peek(self: *const MermaidScanner, offset: usize) ?u8 {
        if (self.index + offset >= self.source.len) return null;
        return self.source[self.index + offset];
    }

    fn matchLongestSymbol(self: *const MermaidScanner) ?usize {
        const symbols = [_][]const u8{
            "<-.->",
            "<==>",
            "<-->",
            "-.->",
            "==>",
            "-->",
            "---",
            "<--",
            ":::",
        };
        for (symbols) |symbol| {
            if (self.index + symbol.len <= self.source.len and std.mem.eql(u8, self.source[self.index .. self.index + symbol.len], symbol)) {
                return self.index + symbol.len;
            }
        }
        return null;
    }
};

pub fn ensureRichEditLibrary(rich_edit_module: anytype) bool {
    if (rich_edit_module.* != null) return true;
    rich_edit_module.* = loader.LoadLibraryA("Riched20.dll");
    return rich_edit_module.* != null;
}

pub fn releaseEditorFont(editor_font: *?gdi.HFONT) void {
    if (editor_font.*) |font| {
        _ = gdi.DeleteObject(font);
        editor_font.* = null;
    }
}

pub fn ensureEditorFont(editor_font: *?gdi.HFONT) ?gdi.HFONT {
    if (editor_font.* != null) return editor_font.*;

    editor_font.* = gdi.CreateFontA(
        -22,
        0,
        0,
        0,
        400,
        0,
        0,
        0,
        0,
        gdi.OUT_DEFAULT_PRECIS,
        gdi.CLIP_DEFAULT_PRECIS,
        gdi.CLEARTYPE_QUALITY,
        @enumFromInt(0),
        "Cascadia Code",
    );
    if (editor_font.* == null) {
        editor_font.* = gdi.CreateFontA(
            -22,
            0,
            0,
            0,
            400,
            0,
            0,
            0,
            0,
            gdi.OUT_DEFAULT_PRECIS,
            gdi.CLIP_DEFAULT_PRECIS,
            gdi.CLEARTYPE_QUALITY,
            @enumFromInt(0),
            "Consolas",
        );
    }
    return editor_font.*;
}

fn sendEditorMessage(editor_hwnd: ?foundation.HWND, message: u32, w_param: usize, l_param: isize) foundation.LRESULT {
    return ui.SendMessageA(editor_hwnd, message, w_param, l_param);
}

fn richMaskBits(mask: rich_edit.CFM_MASK) u32 {
    return @bitCast(mask);
}

fn makeRichMask(bits: u32) rich_edit.CFM_MASK {
    return @bitCast(bits);
}

fn makeRichEffects(bits: u32) rich_edit.CFE_EFFECTS {
    return @bitCast(bits);
}

fn getEditorSelection(editor_hwnd: ?foundation.HWND) rich_edit.CHARRANGE {
    var range = rich_edit.CHARRANGE{ .cpMin = 0, .cpMax = 0 };
    _ = sendEditorMessage(editor_hwnd, rich_edit.EM_EXGETSEL, 0, @bitCast(@intFromPtr(&range)));
    return range;
}

fn setEditorSelection(editor_hwnd: ?foundation.HWND, start: i32, end: i32) void {
    var range = rich_edit.CHARRANGE{ .cpMin = start, .cpMax = end };
    _ = sendEditorMessage(editor_hwnd, rich_edit.EM_EXSETSEL, 0, @bitCast(@intFromPtr(&range)));
}

fn applyEditorFormat(editor_hwnd: ?foundation.HWND, source_text: []const u8, start: usize, end: usize, style: EditorTokenStyle) void {
    if (start >= end) return;

    const cp_start = richEditPositionForSourceOffset(source_text, start);
    const cp_end = richEditPositionForSourceOffset(source_text, end);
    if (cp_start >= cp_end) return;

    var format = std.mem.zeroes(rich_edit.CHARFORMAT2A);
    format.Base.cbSize = @sizeOf(rich_edit.CHARFORMAT2A);
    var mask_bits = richMaskBits(rich_edit.CFM_COLOR);
    if (style.back_color != null) mask_bits |= richMaskBits(rich_edit.CFM_BACKCOLOR);
    if (style.bold) mask_bits |= richMaskBits(rich_edit.CFM_BOLD);
    if (style.italic) mask_bits |= richMaskBits(rich_edit.CFM_ITALIC);
    if (style.font_height != null) mask_bits |= richMaskBits(rich_edit.CFM_SIZE);
    format.Base.dwMask = makeRichMask(mask_bits);
    format.Base.dwEffects = makeRichEffects(0);
    if (style.bold) format.Base.dwEffects.BOLD = 1;
    if (style.italic) format.Base.dwEffects.ITALIC = 1;
    format.Base.crTextColor = style.color;
    format.crBackColor = style.back_color orelse editor_theme.background;
    format.Base.yHeight = @intCast(style.font_height orelse 240);

    setEditorSelection(editor_hwnd, @intCast(cp_start), @intCast(cp_end));
    _ = sendEditorMessage(editor_hwnd, rich_edit.EM_SETCHARFORMAT, rich_edit.SCF_SELECTION, @bitCast(@intFromPtr(&format)));
}

fn applyEditorBaseStyle(editor_hwnd: ?foundation.HWND) void {
    var format = std.mem.zeroes(rich_edit.CHARFORMAT2A);
    format.Base.cbSize = @sizeOf(rich_edit.CHARFORMAT2A);
    format.Base.dwMask = makeRichMask(
        richMaskBits(rich_edit.CFM_COLOR) |
            richMaskBits(rich_edit.CFM_BACKCOLOR) |
            richMaskBits(rich_edit.CFM_FACE) |
            richMaskBits(rich_edit.CFM_SIZE),
    );
    format.Base.dwEffects = makeRichEffects(0);
    format.Base.crTextColor = editor_theme.default_text;
    format.crBackColor = editor_theme.background;
    format.Base.yHeight = 240;
    @memcpy(format.Base.szFaceName[0..13], "Cascadia Code"[0..13]);
    setEditorSelection(editor_hwnd, 0, -1);
    _ = sendEditorMessage(editor_hwnd, rich_edit.EM_SETCHARFORMAT, rich_edit.SCF_ALL, @bitCast(@intFromPtr(&format)));
}

fn styleForSpan(span: Span) EditorTokenStyle {
    return switch (span.kind) {
        .keyword => .{ .color = editor_theme.keyword_text, .bold = true },
        .direction => .{ .color = editor_theme.direction_text, .bold = true },
        .comment => .{ .color = editor_theme.comment_text, .bold = false },
        .annotation => .{ .color = editor_theme.comment_text, .bold = false, .font_height = 160 }, // 8pt (160 twips)
        .string_literal => .{ .color = editor_theme.string_text, .bold = false },
        .symbol => .{ .color = editor_theme.symbol_text, .bold = false },
        .identifier => .{ .color = editor_theme.default_text, .bold = false },
    };
}

pub fn applyEditorSyntaxHighlight(editor_hwnd: ?foundation.HWND, text: []const u8, markdown_document: ?*const document_model.MarkdownDocument, diagnostic: ?EditorDiagnostic) void {
    if (editor_hwnd == null) return;

    const selection = getEditorSelection(editor_hwnd);
    _ = sendEditorMessage(editor_hwnd, ui.WM_SETREDRAW, 0, 0);
    defer {
        setEditorSelection(editor_hwnd, selection.cpMin, selection.cpMax);
        _ = sendEditorMessage(editor_hwnd, ui.WM_SETREDRAW, 1, 0);
        _ = gdi.InvalidateRect(editor_hwnd, null, 1);
    }

    _ = sendEditorMessage(editor_hwnd, rich_edit.EM_HIDESELECTION, 1, 0);
    _ = sendEditorMessage(editor_hwnd, rich_edit.EM_SETBKGNDCOLOR, 0, @intCast(editor_theme.background));
    applyEditorBaseStyle(editor_hwnd);

    if (markdown_document) |document| {
        applyMarkdownStructureHighlight(editor_hwnd, text, document);
    } else {
        applyMermaidBlockHighlight(editor_hwnd, text, 0, text.len, null);
    }

    if (diagnostic) |active_diagnostic| {
        if (active_diagnostic.end > active_diagnostic.start) {
            applyEditorFormat(
                editor_hwnd,
                text,
                active_diagnostic.start,
                active_diagnostic.end,
                .{
                    .color = editor_theme.error_text,
                    .back_color = editor_theme.error_background,
                    .bold = true,
                },
            );
        }
    }

    _ = sendEditorMessage(editor_hwnd, rich_edit.EM_HIDESELECTION, 0, 0);
}

pub fn configureEditorControl(editor_hwnd: ?foundation.HWND, editor_font: *?gdi.HFONT) void {
    if (editor_hwnd == null) return;
    if (ensureEditorFont(editor_font)) |font| {
        _ = ui.SendMessageA(editor_hwnd, ui.WM_SETFONT, @intFromPtr(font), 1);
    }
    _ = sendEditorMessage(editor_hwnd, rich_edit.EM_SETBKGNDCOLOR, 0, @intCast(editor_theme.background));
    _ = sendEditorMessage(editor_hwnd, rich_edit.EM_SETEVENTMASK, 0, @intCast(@as(u32, rich_edit.ENM_SELCHANGE)));
}

pub fn setEditorText(allocator: std.mem.Allocator, editor_hwnd: ?foundation.HWND, suppress_editor_change: *bool, text: []const u8) void {
    suppress_editor_change.* = true;
    defer suppress_editor_change.* = false;

    const z_text = allocator.allocSentinel(u8, text.len, 0) catch return;
    defer allocator.free(z_text);
    @memcpy(z_text[0..text.len], text);
    _ = ui.SetWindowTextA(editor_hwnd, z_text.ptr);
}

pub fn setEditorReadOnly(editor_hwnd: ?foundation.HWND, read_only: bool) void {
    _ = sendEditorMessage(editor_hwnd, 0x00CF, @intFromBool(read_only), 0);
}

pub fn getWindowText(allocator: std.mem.Allocator, hwnd: ?foundation.HWND) ![:0]u8 {
    const handle = hwnd orelse return error.WindowNotReady;
    const text_len = ui.GetWindowTextLengthA(handle);
    const safe_len: usize = if (text_len > 0) @intCast(text_len) else 0;
    const buffer = try allocator.allocSentinel(u8, safe_len, 0);
    errdefer allocator.free(buffer);

    const copied_len = ui.GetWindowTextA(handle, buffer.ptr, @intCast(buffer.len + 1));
    if (copied_len < 0) return error.Unexpected;
    return buffer;
}

pub fn getEditorText(allocator: std.mem.Allocator, editor_hwnd: ?foundation.HWND) ![:0]u8 {
    return getWindowText(allocator, editor_hwnd);
}

pub fn getEditorCaretSourceOffset(editor_hwnd: ?foundation.HWND, source_text: []const u8) usize {
    const selection = getEditorSelection(editor_hwnd);
    const rich_edit_offset: usize = if (selection.cpMin < 0) 0 else @intCast(selection.cpMin);
    return sourceOffsetForRichEditPosition(source_text, rich_edit_offset);
}

fn applyMarkdownStructureHighlight(editor_hwnd: ?foundation.HWND, text: []const u8, markdown_document: *const document_model.MarkdownDocument) void {
    applyMarkdownFenceHighlight(editor_hwnd, text);

    for (markdown_document.blocks) |block| {
        switch (block) {
            .text => |text_block| applyTextBlockHighlight(editor_hwnd, text, text_block),
            .diagram => |diagram_block| {
                applyMermaidBlockHighlight(
                    editor_hwnd,
                    text,
                    diagram_block.start_offset,
                    diagram_block.end_offset,
                    editor_theme.mermaid_background,
                );
            },
        }
    }
}

fn applyMarkdownFenceHighlight(editor_hwnd: ?foundation.HWND, text: []const u8) void {
    var line_start: usize = 0;
    while (line_start <= text.len) {
        const line_end = std.mem.indexOfScalarPos(u8, text, line_start, '\n') orelse text.len;
        const line = std.mem.trimRight(u8, text[line_start..line_end], "\r");
        const trimmed = std.mem.trimLeft(u8, line, " \t");
        if (std.mem.eql(u8, trimmed, "```") or std.mem.startsWith(u8, trimmed, "```mermaid")) {
            applyEditorFormat(editor_hwnd, text, line_start, line_end, .{
                .color = editor_theme.fence_text,
                .back_color = editor_theme.fence_background,
                .bold = true,
            });
        }

        if (line_end == text.len) break;
        line_start = line_end + 1;
    }
}

fn applyTextBlockHighlight(editor_hwnd: ?foundation.HWND, text: []const u8, text_block: document_model.TextBlock) void {
    var offset = text_block.start_offset;
    while (offset < text_block.end_offset) {
        const line_end = std.mem.indexOfScalarPos(u8, text, offset, '\n') orelse text_block.end_offset;
        const clamped_end = @min(line_end, text_block.end_offset);
        const line = std.mem.trimRight(u8, text[offset..clamped_end], "\r");
        if (parseMarkdownHeading(line)) |heading| {
            applyEditorFormat(editor_hwnd, text, offset, clamped_end, headingStyle(heading.level));
        }

        if (clamped_end >= text_block.end_offset) break;
        offset = clamped_end + 1;
    }
}

fn applyMermaidBlockHighlight(editor_hwnd: ?foundation.HWND, text: []const u8, start: usize, end: usize, back_color: ?u32) void {
    if (start >= end) return;

    if (back_color) |color| {
        applyEditorFormat(editor_hwnd, text, start, end, .{
            .color = editor_theme.default_text,
            .back_color = color,
            .bold = false,
        });
    }

    var scanner = MermaidScanner.init(text[start..end]);
    while (scanner.next()) |span| {
        const style = styleForSpan(span);
        if (style.color == editor_theme.default_text and !style.bold and !style.italic and style.back_color == null and style.font_height == null) continue;
        applyEditorFormat(editor_hwnd, text, start + span.start, start + span.end, .{
            .color = style.color,
            .bold = style.bold,
            .italic = style.italic,
            .back_color = back_color,
            .font_height = style.font_height,
        });
    }
}

const MarkdownHeading = struct {
    level: usize,
};

fn parseMarkdownHeading(line: []const u8) ?MarkdownHeading {
    const trimmed = std.mem.trimLeft(u8, line, " \t");
    if (trimmed.len < 2 or trimmed[0] != '#') return null;

    var level: usize = 0;
    while (level < trimmed.len and trimmed[level] == '#') : (level += 1) {}
    if (level == 0 or level > 6 or level >= trimmed.len or trimmed[level] != ' ') return null;
    if (std.mem.trim(u8, trimmed[level + 1 ..], " \t").len == 0) return null;
    return .{ .level = level };
}

fn headingStyle(level: usize) EditorTokenStyle {
    const font_height: i32 = switch (level) {
        1 => 400,
        2 => 320,
        3 => 280,
        else => 240,
    };
    return .{
        .color = editor_theme.heading_text,
        .bold = true,
        .font_height = font_height,
    };
}

pub fn inferSyntaxDiagnostic(text: []const u8, syntax_message: []const u8) EditorDiagnostic {
    if (findUnterminatedString(text)) |range| {
        return buildDiagnostic(text, syntax_message, range);
    }
    if (findDelimiterMismatch(text)) |range| {
        return buildDiagnostic(text, syntax_message, range);
    }
    if (findSubgraphMismatch(text)) |range| {
        return buildDiagnostic(text, syntax_message, range);
    }
    if (findDanglingConnector(text)) |range| {
        return buildDiagnostic(text, syntax_message, range);
    }
    return buildDiagnostic(text, syntax_message, lastMeaningfulLine(text));
}

fn buildDiagnostic(text: []const u8, syntax_message: []const u8, range: OffsetRange) EditorDiagnostic {
    const line_info = lineAndColumnForOffset(text, range.start);
    return .{
        .message = syntax_message,
        .line = line_info.line,
        .column = line_info.column,
        .start = range.start,
        .end = range.end,
    };
}

fn findUnterminatedString(text: []const u8) ?OffsetRange {
    var index: usize = 0;
    while (index < text.len) {
        if (text[index] == '%' and index + 1 < text.len and text[index + 1] == '%') {
            while (index < text.len and text[index] != '\n') {
                index += 1;
            }
            continue;
        }
        if (text[index] == '"') {
            const start = index;
            index += 1;
            while (index < text.len) {
                if (text[index] == '\\' and index + 1 < text.len) {
                    index += 2;
                    continue;
                }
                if (text[index] == '"') {
                    index += 1;
                    break;
                }
                index += 1;
            }
            if (index >= text.len or text[index - 1] != '"') {
                return lineBoundsAtOffset(text, start);
            }
            continue;
        }
        index += 1;
    }
    return null;
}

fn findDelimiterMismatch(text: []const u8) ?OffsetRange {
    var stack = std.ArrayListUnmanaged(Delimiter){};
    defer stack.deinit(std.heap.c_allocator);

    var index: usize = 0;
    while (index < text.len) {
        const char = text[index];
        if (char == '%' and index + 1 < text.len and text[index + 1] == '%') {
            while (index < text.len and text[index] != '\n') {
                index += 1;
            }
            continue;
        }
        if (char == '"') {
            index += 1;
            while (index < text.len) {
                if (text[index] == '\\' and index + 1 < text.len) {
                    index += 2;
                    continue;
                }
                if (text[index] == '"') {
                    index += 1;
                    break;
                }
                index += 1;
            }
            continue;
        }

        if (char == '[' or char == '(' or char == '{') {
            stack.append(std.heap.c_allocator, .{ .char = char, .offset = index }) catch return null;
            index += 1;
            continue;
        }
        if (char == ']' or char == ')' or char == '}') {
            if (stack.items.len == 0) {
                return singleCharRange(index, text.len);
            }
            const opener = stack.pop().?;
            if (!isMatchingDelimiter(opener.char, char)) {
                return singleCharRange(index, text.len);
            }
        }
        index += 1;
    }

    if (stack.items.len > 0) {
        return singleCharRange(stack.items[stack.items.len - 1].offset, text.len);
    }
    return null;
}

fn findSubgraphMismatch(text: []const u8) ?OffsetRange {
    var stack = std.ArrayListUnmanaged(OffsetRange){};
    defer stack.deinit(std.heap.c_allocator);

    var line_start: usize = 0;
    while (line_start <= text.len) {
        const line_end = std.mem.indexOfScalarPos(u8, text, line_start, '\n') orelse text.len;
        const line = text[line_start..line_end];
        const trimmed = std.mem.trim(u8, line, " \t\r");

        if (trimmed.len > 0 and !std.mem.startsWith(u8, trimmed, "%%")) {
            if (std.mem.startsWith(u8, trimmed, "subgraph")) {
                stack.append(std.heap.c_allocator, .{ .start = line_start, .end = line_end }) catch return null;
            } else if (std.mem.eql(u8, trimmed, "end")) {
                if (stack.items.len == 0) return .{ .start = line_start, .end = line_end };
                _ = stack.pop();
            }
        }

        if (line_end == text.len) break;
        line_start = line_end + 1;
    }

    if (stack.items.len > 0) {
        return stack.items[stack.items.len - 1];
    }
    return null;
}

fn findDanglingConnector(text: []const u8) ?OffsetRange {
    const connectors = [_][]const u8{ "-->", "---", "-.->", "==>", "<--", "<-->", "<-.->", "<==>", "|", ":::" };

    var line_start: usize = 0;
    var last_candidate: ?OffsetRange = null;
    while (line_start <= text.len) {
        const line_end = std.mem.indexOfScalarPos(u8, text, line_start, '\n') orelse text.len;
        const line = text[line_start..line_end];
        const trimmed = std.mem.trim(u8, line, " \t\r");

        if (trimmed.len > 0 and !std.mem.startsWith(u8, trimmed, "%%")) {
            for (connectors) |connector| {
                if (std.mem.endsWith(u8, trimmed, connector)) {
                    last_candidate = .{ .start = line_start, .end = line_end };
                    break;
                }
            }
        }

        if (line_end == text.len) break;
        line_start = line_end + 1;
    }
    return last_candidate;
}

fn lastMeaningfulLine(text: []const u8) OffsetRange {
    var line_start: usize = 0;
    var fallback = OffsetRange{ .start = 0, .end = @min(@as(usize, 1), text.len) };

    while (line_start <= text.len) {
        const line_end = std.mem.indexOfScalarPos(u8, text, line_start, '\n') orelse text.len;
        const line = text[line_start..line_end];
        const trimmed = std.mem.trim(u8, line, " \t\r");
        if (trimmed.len > 0 and !std.mem.startsWith(u8, trimmed, "%%")) {
            fallback = .{ .start = line_start, .end = if (line_end > line_start) line_end else @min(line_start + 1, text.len) };
        }

        if (line_end == text.len) break;
        line_start = line_end + 1;
    }

    return fallback;
}

fn lineBoundsAtOffset(text: []const u8, offset: usize) OffsetRange {
    if (text.len == 0) return .{ .start = 0, .end = 0 };

    var start = @min(offset, text.len - 1);
    while (start > 0 and text[start - 1] != '\n') {
        start -= 1;
    }

    var end = @min(offset, text.len);
    while (end < text.len and text[end] != '\n') {
        end += 1;
    }

    return .{ .start = start, .end = if (end > start) end else @min(start + 1, text.len) };
}

fn lineAndColumnForOffset(text: []const u8, offset: usize) struct { line: usize, column: usize } {
    var line: usize = 1;
    var column: usize = 1;
    var index: usize = 0;
    const safe_offset = @min(offset, text.len);

    while (index < safe_offset) : (index += 1) {
        if (text[index] == '\n') {
            line += 1;
            column = 1;
        } else {
            column += 1;
        }
    }

    return .{ .line = line, .column = column };
}

fn singleCharRange(offset: usize, len: usize) OffsetRange {
    return .{ .start = offset, .end = @min(offset + 1, len) };
}

fn isMatchingDelimiter(opening: u8, closing: u8) bool {
    return (opening == '[' and closing == ']') or
        (opening == '(' and closing == ')') or
        (opening == '{' and closing == '}');
}

fn classifyWord(word: []const u8, at_line_start: bool) SpanKind {
    if (isDirection(word)) return .direction;
    if (isKeyword(word, at_line_start)) return .keyword;
    return .identifier;
}

fn isIdentifierStart(char: u8) bool {
    return std.ascii.isAlphabetic(char) or std.ascii.isDigit(char) or char == '_';
}

fn isIdentifierContinue(char: u8) bool {
    return isIdentifierStart(char);
}

fn isSingleSymbol(char: u8) bool {
    return switch (char) {
        '[', ']', '(', ')', '{', '}', '|', ':', ';', ',', '#', '<', '>', '=', '-' => true,
        else => false,
    };
}

fn isDirection(word: []const u8) bool {
    return std.mem.eql(u8, word, "TD") or
        std.mem.eql(u8, word, "TB") or
        std.mem.eql(u8, word, "LR") or
        std.mem.eql(u8, word, "RL") or
        std.mem.eql(u8, word, "BT");
}

fn isKeyword(word: []const u8, at_line_start: bool) bool {
    _ = at_line_start;
    return std.mem.eql(u8, word, "graph") or
        std.mem.eql(u8, word, "flowchart") or
        std.mem.eql(u8, word, "subgraph") or
        std.mem.eql(u8, word, "end") or
        std.mem.eql(u8, word, "classDef") or
        std.mem.eql(u8, word, "class") or
        std.mem.eql(u8, word, "style") or
        std.mem.eql(u8, word, "click") or
        std.mem.eql(u8, word, "linkStyle");
}

fn richEditPositionForSourceOffset(source_text: []const u8, offset: usize) usize {
    var source_index: usize = 0;
    var rich_edit_index: usize = 0;
    const safe_offset = @min(offset, source_text.len);

    while (source_index < safe_offset) {
        if (source_text[source_index] == '\r' and source_index + 1 < safe_offset and source_text[source_index + 1] == '\n') {
            source_index += 2;
            rich_edit_index += 1;
            continue;
        }
        source_index += 1;
        rich_edit_index += 1;
    }

    return rich_edit_index;
}

fn sourceOffsetForRichEditPosition(source_text: []const u8, rich_edit_offset: usize) usize {
    var source_index: usize = 0;
    var rich_edit_index: usize = 0;

    while (source_index < source_text.len and rich_edit_index < rich_edit_offset) {
        if (source_text[source_index] == '\r' and source_index + 1 < source_text.len and source_text[source_index + 1] == '\n') {
            source_index += 2;
            rich_edit_index += 1;
            continue;
        }
        source_index += 1;
        rich_edit_index += 1;
    }

    return source_index;
}
