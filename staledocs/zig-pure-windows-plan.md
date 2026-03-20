# Merrow Studio - Pure Zig Windows 11 Port Plan

## 1. Can it be done entirely in Zig 0.15.2?
**Yes, absolutely.** You do *not* need `C#`, `Rust`, or even a `C++` (`.cpp`) shim. Zig can interface directly with the Windows API perfectly.

Because Zig speaks C natively, and the Windows API (Win32) is fundamentally a C API, you can write the entire application window lifecycle, message loop, and Direct2D rendering logic completely in Zig.

## 2. Advantages of a 100% Zig Approach
* **Zero Dependencies:** No Visual Studio installations required. Zig cross-compiles Windows executables directly from a Mac (`zig build -Dtarget=x86_64-windows` or `aarch64-windows`).
* **One Language:** No context switching between Objective-C, C++, and Zig. Everything from Dagre layout to Direct2D brush allocation is inside `.zig` files.
* **Unified Build:** The `build.zig` just builds the Windows `.exe` natively without invoking MSVC.

## 3. How to achieve Direct2D in Zig (COM Interfaces)
The only "trick" is that Direct2D and DirectWrite use **COM (Component Object Model)**, which is inherently C++ with `vtable` virtual function pointers. However, Zig has excellent built-in features to call COM interfaces exactly like C does.

Instead of including `<d2d1.h>` in C++, you use `zig-win32` (or simply define the required COM vtables manually in Zig).

### Example: The COM VTable in Zig
Here is roughly how an `ID2D1Factory` is called purely in Zig:
```zig
const std = @import("std");
const windows = std.os.windows;

// Simplified COM interface mapping
const ID2D1Factory = extern struct {
    vtable: *const VTable,

    const VTable = extern struct {
        // IUnknown methods
        QueryInterface: *const fn (*ID2D1Factory, *const windows.GUID, *?*anyopaque) callconv(.stdcall) windows.HRESULT,
        AddRef: *const fn (*ID2D1Factory) callconv(.stdcall) u32,
        Release: *const fn (*ID2D1Factory) callconv(.stdcall) u32,
        
        // ID2D1Factory methods...
        ReloadSystemMetrics: *const fn (*ID2D1Factory) callconv(.stdcall) windows.HRESULT,
        // ... (other methods mapped to zig fns)
    };
    
    pub fn Release(self: *ID2D1Factory) u32 {
        return self.vtable.Release(self);
    }
};
```

## 4. Execution Plan for Pure Zig 

### Phase 1: Pure Zig Window Loop (`windows_app.zig`)
Because your macOS frontend expects to receive a slice of structs (`MerrowStudioNode`) from `preview.zig`, you create `app/platform/windows_main.zig`.
It will utilize `std.os.windows.user32` to:
1. Call `RegisterClassExA`.
2. Call `CreateWindowExA`.
3. Run the message loop (`GetMessageA`/`DispatchMessageA`).

### Phase 2: Add `zig-win32` Dependency
Mapping hundreds of COM vtables by hand (like Direct2D, DirectWrite, DirectComposition) is tedious. Microsoft officially supports a metadata project that generates Zig bindings for every Win32 and COM API.
Add the incredibly popular `zigwin32` package to your `build.zig.zon`:
```zig
.dependencies = .{
    .zigwin32 = .{
        .url = "https://github.com/marlers/zigwin32/archive/refs/tags/0.2.1.tar.gz",
        // ...
    }
}
```

### Phase 3: Pure Zig Direct2D Render
In your `windows_main.zig` `WM_PAINT` handler:
1. Initialize the `zigwin32` `ID2D1HwndRenderTarget`.
2. Iterate over the same Zig structs that run the Mac App (`MerrowFreeformNodeRecord`).
3. Call `renderTarget.DrawRoundedRectangle()` purely in Zig.

### Phase 4: Build.zig updates
```zig
if (target_query.os.tag == .windows) {
    const win_exe = b.addExecutable(.{
        .name = "merrow-studio",
        .root_source_file = b.path("app/platform/windows_main.zig"), // Pure Zig!
        .target = target,
        .optimize = optimize,
    });
    
    // Using zigwin32
    const win32 = b.dependency("zigwin32", .{}).module("win32");
    win_exe.root_module.addImport("win32", win32);
    
    // Zig magically knows how to link Windows subsystem libs
    win_exe.linkSystemLibrary("user32");
    win_exe.linkSystemLibrary("d2d1");
    win_exe.linkSystemLibrary("dwrite");

    b.installArtifact(win_exe);
}
```

## 5. Conclusion
**Yes.** Because Zig is both a drop-in C-compiler *and* handles COM vtables cleanly, you can build the native Windows 11 GUI using zero C++ files. You get a single, massive advantage: **You can develop and cross-compile the Windows .exe directly from your Mac.**