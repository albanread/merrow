# Windows C++ Toolchains

This repo can be developed with several Windows-side C and C++ toolchains, but they are not equivalent.

## Current Options In This Workspace

- MSVC via Visual Studio 2022 Community
- LLVM/Clang 22.1.1
- Rust via rustup
- WSL 2 for Linux-side compilers

Helper scripts in [scripts](c:/projects/zig/merrow/scripts):

- [scripts/enable_msvc.ps1](c:/projects/zig/merrow/scripts/enable_msvc.ps1)
- [scripts/enable_clang.ps1](c:/projects/zig/merrow/scripts/enable_clang.ps1)
- [scripts/enable_rust.ps1](c:/projects/zig/merrow/scripts/enable_rust.ps1)

## Recommendation

For Windows work that involves Zig plus COM automation of Microsoft Word, the best default choice is:

- `MSVC` for the Windows SDK, linker, import libraries, debugger compatibility, and ABI stability
- optionally `clang-cl` on top of the MSVC environment if you want Clang diagnostics but still need the Microsoft ABI and libraries

In practice:

1. Load MSVC first.
2. Use Zig as the main build tool.
3. Use `clang-cl` only if you have a specific reason to compile C or C++ helper code with Clang semantics.

## Why MSVC Is The Best Fit For Word COM Automation

Microsoft Word automation on Windows depends on standard Windows COM infrastructure such as:

- `ole32`
- `oleaut32`
- COM interfaces and GUIDs from the Windows SDK
- Office type libraries, headers, and examples that are primarily documented in the Microsoft toolchain ecosystem

MSVC is the least surprising option here because:

- it matches the ABI that the Windows SDK and most native Windows samples assume
- Visual Studio debugging for COM-heavy processes is better supported
- the surrounding Microsoft docs, samples, and troubleshooting paths are MSVC-first
- if you need to mix Zig with a small native helper DLL or static library, MSVC avoids unnecessary portability fights on Windows

## Why `clang-cl` Is Still A Good Secondary Choice

`clang-cl` is a strong option when you want:

- Clang warnings and diagnostics
- better compatibility with Clang-based tooling
- the Microsoft ABI instead of the GNU/MinGW ABI

This is the right way to use Clang for Windows COM work:

- run [scripts/enable_msvc.ps1](c:/projects/zig/merrow/scripts/enable_msvc.ps1)
- then run [scripts/enable_clang.ps1](c:/projects/zig/merrow/scripts/enable_clang.ps1)

That keeps you in the MSVC ecosystem while using the Clang front end.

## Why GCC Or MinGW Are Not The Default Recommendation

GCC or MinGW can work for some Windows native code, but they are not the best fit for Office COM automation work.

Main reasons:

- more room for ABI mismatches versus the Microsoft toolchain ecosystem
- less alignment with Office and COM sample code from Microsoft
- more friction when debugging integration issues that involve COM apartments, registration, typelibs, or marshaling
- less value if the final target is a Windows-native app already built around Zig and Win32 APIs

If your goal is specifically Microsoft Word automation on Windows, MinGW is usually extra risk without offsetting benefit.

## What This Means For Zig

For Zig itself, the situation is simpler than for C++:

- Zig already knows how to target Windows directly
- Zig can call Win32 and COM APIs without requiring a large C++ wrapper layer
- if you do need external native code, keep that layer small and use the MSVC ABI

Recommended pattern:

1. Keep the main application logic in Zig.
2. Use the Windows SDK definitions Zig already exposes where practical.
3. Add a tiny C or C++ shim only if a specific COM or Office interop scenario becomes awkward in pure Zig.
4. Build that shim with `cl` or `clang-cl`, not MinGW GCC.

## Suggested Setup Commands

PowerShell for MSVC:

```powershell
. .\scripts\enable_msvc.ps1
```

PowerShell for LLVM/Clang after MSVC:

```powershell
. .\scripts\enable_msvc.ps1
. .\scripts\enable_clang.ps1
```

PowerShell for Rust:

```powershell
. .\scripts\enable_rust.ps1
```

## Short Version

If you are choosing one Windows toolchain for Zig plus Microsoft Word COM automation, use `MSVC`.

If you want Clang, use `clang-cl` in the MSVC environment.

Do not choose MinGW GCC as the default for this use case unless you already have a hard requirement for it.