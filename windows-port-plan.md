# Merrow Studio - Windows 11 Port Plan

## 1. Project Architecture Assessment
The Merrow core (`merrow` CLI, layout engine, parsers) is written purely in Zig and handles cross-platform diagram generation (PNG/SVG). 
The visual editor ("Merrow Studio") has an isolated FFI boundary (`app/preview.zig`). It receives structure layout data and delegates drawing to a fully native macOS frontend (`app/platform/macos_app.m` & `merrow_freeform_canvas.m`).

The macOS UI acts as a thin presentation layer:
- **CoreGraphics / NSView**: Used for rendering vector primitives (nodes, edges).
- **CoreText / AppKit**: Used for native font measuring, text wrapping, and rendering.
- **Cocoa Events**: Drives mouse interactions, routing positional data back to Zig.

## 2. Porting Approaches

### Approach A: Cross-Platform UI Framework (Sokol / Raylib / Mach)
* **Pros**: Write once, runs on macOS, Windows, and Linux. Zero native windowing code.
* **Cons**: Diagram tools require *world-class* text layout and rendering (measuring wrapped bounds precisely, fallback fonts for CJK/Emoji). Generic cross-platform libraries often struggle to match native text stacks. It would also require rewriting the current working macOS frontend.

### Approach B: Native Win32 + Direct2D / DirectWrite (Recommended)
* **Pros**: Direct equivalent to the macOS setup (CoreGraphics -> Direct2D, CoreText -> DirectWrite). It provides pristine text rendering, taps straight into Windows 11's hardware acceleration, and allows the existing Zig core/FFI architecture to remain completely untouched. You write a Windows-specific UI layer exactly how you wrote the macOS-specific one.
* **Cons**: Requires interfacing with C++ COM APIs.

## 3. Recommended Approach Details: Win32 + Direct2D C++ Shim
To match the `macos_app.m` paradigm, we recommend creating a `windows_app.cpp` shim. While Zig *can* call Win32/COM natively via `zig-win32`, Direct2D and DirectWrite are heavily object-oriented C++ COM APIs. Wrapping them in a `.cpp` file that exposes a flat C API to Zig provides the cleanest developer experience and perfectly mirrors how `merrow_freeform_canvas.m` works today.

## 4. Execution Plan (Phases)

### Phase 1: Build System Setup (`build.zig`)
Detect Windows targets and compile the new platform files:
```zig
if (target_query.os.tag == .windows) {
    const win_app_exe = b.addExecutable(.{
        .name = "merrow-studio",
        .root_module = b.createModule(.{ /* ... same imports as macos ... */ }),
    });
    
    // Add the C++ shim providing the Main window and D2D canvas
    win_app_exe.addCSourceFile(.{
        .file = b.path("app/platform/windows_app.cpp"),
        .flags = &[_][]const u8{"-std=c++20"},
    });
    
    // Link C++ standard library
    win_app_exe.linkLibC();
    win_app_exe.linkLibCpp();
    
    // Crucial Windows 11 Graphics / Shell libraries
    win_app_exe.linkSystemLibrary("user32");
    win_app_exe.linkSystemLibrary("d2d1");
    win_app_exe.linkSystemLibrary("dwrite");

    b.installArtifact(win_app_exe);
}
```

### Phase 2: Application Shell (`windows_app.cpp`)
Replicate `macos_app.m`'s application lifecycle:
1. **Entry point**: Export a C function `merrow_studio_main(...)` that Zig's `main()` calls.
2. **Setup**: Register a Win32 Window Class (`RegisterClassEx`).
3. **Window**: Create the main Window (`CreateWindowEx`).
4. **Message Loop**: Implement the target loop: `GetMessage`, `TranslateMessage`, `DispatchMessage`.

### Phase 3: Direct2D Render Canvas
Replicate `merrow_freeform_canvas.m`:
1. **Context Init**: In `WM_CREATE`, initialize an `ID2D1Factory` and an `ID2D1HwndRenderTarget` attached to the window handle (`HWND`).
2. **Brushes**: Pre-allocate `ID2D1SolidColorBrush` items mapped from `StudioColor`.
3. **Drawing Loop**: In `WM_PAINT`, call `BeginDraw()`, iterate over the C API records from `preview.zig` (`MerrowStudioNode`, `MerrowStudioEdge`), and use:
   - `DrawRoundedRectangle` / `FillRoundedRectangle` (for Class/State nodes).
   - `DrawGeometry` mapping Bézier points (for routing layout edges).
   - End with `EndDraw()`.

### Phase 4: Fonts & DirectWrite
DirectWrite (`IDWriteFactory` and `IDWriteTextFormat`) is the Win32 analogue to macOS's NSAttributedString text measuring.
- Implement text drawing using `ID2D1RenderTarget::DrawText`.
- For specific bounds (like diagram Node labels where `max_text_width` is strictly controlled), DirectWrite's layout bounding mechanisms will seamlessly output the exact measurements Zig needs, matching macOS behavior natively.

### Phase 5: Input & Tooling Integrations
- Map Win32 mouse methods (`WM_LBUTTONDOWN`, `WM_MOUSEMOVE` coordinates) to the Zig freeform interaction logic. 
- Setup DPI awareness using Windows 11 High-DPI mechanisms (`GetDpiForWindow`) to ensure diagram shapes render crisply without blur.
- Complement the `package_studio_app.sh` script with a `package_studio_app.ps1` script to zip up the `.exe` and fonts for Windows distribution.

## 5. Next Steps to Begin
1. Define the abstract C-struct interface inside `app/platform/merrow_freeform_canvas.h` to be strictly OS-agnostic if it isn't already (ensure no Apple-specific primitives exist in the shared headers).
2. Scaffold `app/platform/windows_app.cpp` and wire into `build.zig`.
3. Render a hardcoded Direct2D square, then attach it to Zig's `merrow_studio_main`.