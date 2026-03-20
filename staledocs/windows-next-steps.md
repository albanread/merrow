# Windows Port Next Steps

When you pull this repository on your Windows machine, here is your kickoff plan for building the Pure Zig Windows App:

## 1. Setup Environment
1. Ensure Zig `0.15.2` (or later) is installed and on your PATH.
2. Ensure you have `git` available.
3. Clone the repo and switch into the directory.

## 2. Add `zigwin32` Dependency
In your `build.zig.zon`, fetch the metadata wrapper for Win32 (this gives you COM interfaces without boilerplate):
```sh
zig fetch --save https://github.com/marlers/zigwin32/archive/refs/tags/0.2.1.tar.gz
```

*Note: You may need a newer/different tag depending on API coverage, but `marlers/zigwin32` is the community standard.*

## 3. Wire Up `build.zig`
At the top of `build.zig` (where you configure `b`), grab the module:
```zig
const win32 = b.dependency("zigwin32", .{}).module("zigwin32");
```

Modify the OS check for Windows:
```zig
if (target_query.os.tag == .windows) {
    const win_app_exe = b.addExecutable(.{
        .name = "merrow-studio",
        .root_module = b.createModule(.{
            .root_source_file = b.path("app/platform/windows_main.zig"), // <-- Create this
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "merrow", .module = mod },
                .{ .name = "win32", .module = win32 },
            },
        }),
    });

    win_app_exe.linkSystemLibrary("user32");
    win_app_exe.linkSystemLibrary("d2d1");
    win_app_exe.linkSystemLibrary("dwrite");
    win_app_exe.linkLibC();

    b.installArtifact(win_app_exe);

    const win_app_step = b.step("studio", "Run the Windows Mermaid viewer/editor scaffold");
    const win_app_cmd = b.addRunArtifact(win_app_exe);
    win_app_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        win_app_cmd.addArgs(args);
    }
    win_app_step.dependOn(&win_app_cmd.step);
}
```

## 4. Scaffold `app/platform/windows_main.zig`
Create the entry point file. Here is the absolute minimum to get a window on screen.

```zig
const std = @import("std");
const win32 = @import("win32");
// const preview = @import("../preview.zig"); // Add this back once UI works

const WINAPI = win32.system.system_services.WINAPI;
const ui = win32.ui.windows_and_messaging;
const c = win32.foundation;

// 1. Define Message Loop / Window Proc
fn WindowProc(
    hwnd: c.HWND,
    uMsg: u32,
    wParam: c.WPARAM,
    lParam: c.LPARAM,
) callconv(WINAPI) c.LRESULT {
    switch (uMsg) {
        ui.WM_DESTROY => {
            ui.PostQuitMessage(0);
            return 0;
        },
        ui.WM_PAINT => {
            // TODO: Initialize Direct2D here and call render logic
            _ = ui.ValidateRect(hwnd, null);
            return 0;
        },
        else => return ui.DefWindowProcA(hwnd, uMsg, wParam, lParam),
    }
}

// 2. The Main Entry Point
pub fn main() !void {
    const hInstance = win32.system.library_loader.GetModuleHandleA(null);
    const className = "MerrowStudioWin32Class";
    
    var wc = std.mem.zeroes(ui.WNDCLASSEXA);
    wc.cbSize = @sizeOf(ui.WNDCLASSEXA);
    wc.lpfnWndProc = WindowProc;
    wc.hInstance = hInstance;
    wc.lpszClassName = className;

    if (ui.RegisterClassExA(&wc) == 0) {
        return error.RegisterClassFailed;
    }

    const hwnd = ui.CreateWindowExA(
        0, className, "Merrow Studio (Direct2D)",
        ui.WS_OVERLAPPEDWINDOW,
        ui.CW_USEDEFAULT, ui.CW_USEDEFAULT, 1024, 768,
        null, null, hInstance, null,
    );

    if (hwnd == null) return error.CreateWindowFailed;
    _ = ui.ShowWindow(hwnd, ui.SW_SHOW);

    var msg: ui.MSG = undefined;
    while (ui.GetMessageA(&msg, null, 0, 0) > 0) {
        _ = ui.TranslateMessage(&msg);
        _ = ui.DispatchMessageA(&msg);
    }
}
```

## 5. First Run on Windows
1. Run `zig build studio`.
2. A blank native Windows 11 window will appear.
3. From there, implement `ui.WM_PAINT` using `win32.graphics.direct2d.ID2D1Factory` and iterate over `preview.get_nodes()`.