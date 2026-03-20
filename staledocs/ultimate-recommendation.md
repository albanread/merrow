# Merrow Studio - Ultimate Architectural Recommendation

## The Verdict: Keep the Zig Core, Write the Windows GUI in C++
Based on the current architecture of Merrow, **the best outcome is not a language conversion at all, but completing your current architectural vision.**

Your `windows-port-plan.md` outlines the most practical, highest-performing, and least-disruptive path: **Approach B: Native Win32 + Direct2D / DirectWrite C++ Shim.**

### Why You Shouldn't Rewrite in .NET or Rust

1. **The Math is Already Done:** The hardest part of diagramming tools is not drawing rectangles; it is the parsing of Mermaid syntax and the Dagre network simplex layout logic. You have already built this in Zig. A rewrite in C# or Rust throws away months of complex algorithmic work for no tangible performance or feature gain.
2. **Zero-Cost FFI:** Zig's C-compatibility is its superpower. Your current setup (`preview.zig` exporting data to `macos_app.m`) is brilliant. You feed the macOS GUI flat, predictable C-structs (`MerrowStudioNode`). 
3. **No Garbage Collection:** Diagramming tools need to be snappy. By keeping the core in Zig, allocating arena memory for layouts, and immediately freeing it after the GUI draws, you guarantee a 60FPS memory-stable tool.

### Why the C++ Win32/Direct2D Shim is the Best Path

1. **Symmetry:** Writing a `windows_app.cpp` shim perfectly mirrors your `macos_app.m` shim. 
   - CoreText becomes DirectWrite.
   - CoreGraphics becomes Direct2D.
   - AppKit/NSWindow becomes Win32 HWND.
2. **True Native Feel:** Cross-platform UI ecosystems (Avalonia, MAUI, Egui) often feel slightly "off" to native desktop users (wrong scroll physics, weird font anti-aliasing). By using Direct2D, Merrow Studio on Windows will feel unequivocally like a native Windows 11 app, just as it feels unequivocally native on a Mac.
3. **Pristine Text Rendering:** Diagram rendering lives and dies by text measuring. By tapping into OS-native CoreText (Mac) and DirectWrite (Win), you get emoji support, RTL sub-pixel measuring, and fallback fonts completely for free, without having to ship a huge font engine.

### The Recommended Action Plan

1. Keep `.zig` as the heartbeat of the project.
2. Follow the `windows-port-plan.md` exactly.
3. Write `app/platform/windows_app.cpp`.
4. Compile it in `build.zig` just for Windows:
   ```zig
   if (target_query.os.tag == .windows) {
       win_app_exe.addCSourceFile(.{
           .file = b.path("app/platform/windows_app.cpp"),
           .flags = &[_][]const u8{"-std=c++20"},
       });
       win_app_exe.linkSystemLibrary("d2d1");
       win_app_exe.linkSystemLibrary("dwrite");
   }
   ```
5. You now have a hyper-fast, zero-dependency, native-feeling app on both major desktop platforms.