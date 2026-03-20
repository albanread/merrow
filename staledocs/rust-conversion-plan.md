# Merrow Studio - Rust Conversion Plan

## 1. Project Architecture Assessment
Transitioning from Zig to Rust is a more natural jump than to .NET. Rust is a systems language with similar zero-cost abstraction goals, highly mature tooling (`cargo`), and stronger guarantees around memory safety without GC overhead. 

Importantly, your existing `README.md` notes that Merrow's Dagre layout engine shares DNA with **Selkie**, a thorough Rust port of Dagre. This makes the porting of the layout logic extremely viable.

## 2. Does Rust Support Windows GUI?
**Yes, absolutely.** Rust has arguably the healthiest systems-level native wrapper ecosystem right now.

* **For Native Win32/COM Elements:** The `windows-rs` crate (officially maintained by Microsoft) allows you to call Direct2D, DirectWrite, and the core Win32 Window message loop natively from Rust, without needing a C++ shim.
* **For Cross-Platform GUIs:** Rust has highly active ecosystem tools:
  - **Tauri**: React/Web frontend, Rust backend.
  - **Egui / Slint:** Immediate and retained mode GUI frameworks rendered over WGPU/OpenGL/DirectX.

## 3. Recommended Approach: 100% Rust Rewrite
Unlike .NET where we recommended a hybrid FFI, moving to Rust should be a **Full Rewrite**.
* **Why:** Rust is fully capable of the high-performance memory management, FFI, and layout parsing you built in Zig. You do not need to maintain two languages.
* **Prior Art:** You can utilize libraries like `selkie` for your layout engine, and leverage `nom` or `chumsky` for your Mermaid diagram parsers.

## 4. Execution Plan (Phases)

### Phase 1: Core Library (`merrow-core`)
1. **Parsers:** Rewrite the Zig recursive descent parsers (e.g., flowchart, sequence) using `nom`, a highly performant Rust parser combinator.
2. **Layout Engine:** Port your `dagre` Network Simplex and coordinate layout concepts to Rust. Rust's strict mutability rules will fundamentally change how Graph nodes are shared between layouts (often using `petgraph` or arena allocators to avoid cyclical reference borrowing).

### Phase 2: Headless Renderer (merrow CLI)
1. Use `tiny-skia` or `cairo-rs` for exporting `.svg` and `.png` vectors exactly like the Zig `merrow` CLI does.
2. For font rendering in the CLI, `rustybuzz` and `fontdue` handle text sizing without invoking the OS GUI layers natively, producing pixel-perfect standalone images.

### Phase 3: Merrow Studio GUI (Windows / macOS)
There are two distinct paths for the Desktop GUI in Rust:

**Path A: The Native "windows-rs" approach (Recommended for exact parity)**
You can recreate your MacOS `merrow_freeform_canvas.m` using pure Rust on Windows with Microsoft's official bindings:
```rust
// Microsoft's official `windows` crate
use windows::Win32::Graphics::Direct2D::{D2D1CreateFactory, ID2D1Factory};
use windows::Win32::UI::WindowsAndMessaging::{CreateWindowExW, DispatchMessageW, GetMessageW};
```
* **Pros:** Peak native integration. You write a Windows Direct2D UI, and use `objc2` and `core-graphics` crates for the Mac UI. It perfectly mirrors your current Zig methodology.
* **Cons:** Requires writing OS-specific rendering code.

**Path B: Cross-Platform UI (Egui / WGPU)**
Using `egui` (an immediate mode GUI written in Rust):
* You implement the canvas drawing loop *once* in Rust.
* `egui` natively supports WebGL/WGPU drawing on Windows using DirectX under the hood, and Metal on macOS.
* You get interactive node clicking, text rendering, and continuous re-rendering for free across all operating systems.

## 5. Summary
If going with Rust, **drop FFI**. Do a full port to a pure Rust workspace. Use `cargo` instead of `build.zig`. Microsoft's active investment in `.windows-rs` makes pure Rust on Windows 11 a highly viable and modern development path. You can keep your architecture of a unified mathematical core, and an OS-native UI layer.