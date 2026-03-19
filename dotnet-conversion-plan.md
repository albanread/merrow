# Merrow Studio - .NET Conversion Plan

## 1. Project Architecture Assessment
Currently, Merrow is a high-performance Zig project with a thin native macOS FFI layer. A "complete conversion to .NET" fundamentally changes the architecture. 

There are two primary ways to approach a .NET conversion:
1. **Full Rewrite (100% C#):** Port the Parsers, Dagre Layout Engine, rendering logic, and UI entirely to C#.
2. **.NET Frontend + Zig Core (P/Invoke):** Keep the complex layout and diagram parsing in Zig (compiled to a `.dll`/`.dylib`/`.so`), and build the UI layer in .NET.

## 2. Approach A: Full Rewrite in C# (100% .NET)
* **Pros**: 
  - A single, unified language across the entire stack.
  - Access to advanced cross-platform visual frameworks like **Avalonia UI** or **.NET MAUI**.
  - **SkiaSharp** (the .NET wrapper for Google's Skia rendering engine) natively solves all vector drawing and complex text measurement (CoreText/DirectWrite) across all platforms.
  - Easier to distribute via NuGet or as packed self-contained executables.
* **Cons**:
  - The Dagre layout engine (which incorporates complex network simplex and coordinate assignments) and the Mermaid parsers will need to be ported from Zig to C#, which is a massive undertaking.
  - Loss of Zig's predictable zero-allocation behavior, though modern C# (using `Span<T>` and `ref struct`) can be made highly performant.

## 3. Approach B: .NET Frontend + Zig Backend (.NET Wrapper)
Keep Zig for what it does best (parsing, DAG layout, FFI modeling) and use .NET strictly for the OS integration and drawing.
* **Architecture**: 
  - Zig builds `merrow_core.dll` (Windows), `libmerrow_core.dylib` (macOS).
  - C# application uses `[DllImport]` (P/Invoke) to call `merrow_studio_main(...)`.
  - The C# UI implements the callbacks/data structs expected by Zig and handles the drawing.
* **Pros**:
  - Preserves 100% of the existing Zig mathematical/parsing code.
  - Replaces the need for writing Objective-C (macOS) and Win32 C++ (Windows). One Avalonia/Skia UI covers both.
* **Cons**:
  - Managing memory across the FFI boundary between garbage-collected .NET and manually-managed Zig can lead to memory leaks or use-after-free errors if not carefully modeled.

## 4. Recommended Framework: Avalonia UI + SkiaSharp
If moving to .NET, **Avalonia UI** is the strongest candidate for a node-based diagram editor.
- It is OS-independent (unlike WPF or WinForms).
- It uses **Skia** under the hood, meaning node measurements, corner radiuses, font tracking, and line breaking will look pixel-identically the same on macOS Native, Windows 11, and Linux.
- Supports highly customized "Canvas" drawing out of the box (e.g., `CustomDrawOp`), which maps perfectly to Merrow's `MerrowFreeformNodeRecord` and `MerrowFreeformEdgeRecord`.

## 5. Execution Plan (Assuming Approach B: GUI Rewrite Only)

### Phase 1: Expose Zig as a Shared Library
Modify `build.zig` to output a dynamic library (`.dll` on Windows, `.dylib` on macOS):
```zig
const lib = b.addSharedLibrary(.{
    .name = "merrow_core",
    .root_source_file = b.path("app/preview.zig"), // Expose only FFI boundaries
    .target = target,
    .optimize = optimize,
});
b.installArtifact(lib);
```

### Phase 2: C# Interop Layer (P/Invoke)
Create `MerrowInterop.cs` to map `merrow_freeform_canvas.h`:
```csharp
[StructLayout(LayoutLayoutKind.Sequential)]
public struct MerrowStudioNode {
    public double x, y, width, height;
    public StudioColor fill, stroke;
    public IntPtr label;
    // ...
}

public class MerrowPInvoke {
    [DllImport("merrow_core", CallingConvention = CallingConvention.Cdecl)]
    public static extern void InitializeDiagram(string diagramText);
}
```

### Phase 3: Avalonia UI Canvas
Create an Avalonia `Control` overriding `Render(DrawingContext context)`:
1. Call Zig FFI to get the current list of nodes/edges.
2. Iterate through `MerrowStudioNode`s.
3. Draw them using Avalonia's `context.DrawRectangle` or direct SkiaSharp calls (`SKCanvas`).

### Phase 4: App Lifecycle & Distribution
- Replace `package_studio_app.sh` with `dotnet publish -c Release -r win-x64 --self-contained`.
- Ship a single `.exe` (and native `.dll`) for Windows, and a `.app` bundle via .NET MAUI/MacCatalyst or Avalonia native packaging on macOS.