const std = @import("std");

fn addOptionalInstallFile(b: *std.Build, source_path: []const u8, dest_path: []const u8) void {
    std.fs.cwd().access(source_path, .{}) catch return;
    _ = b.addInstallFile(b.path(source_path), dest_path);
}

fn addFirstExistingInstallFile(b: *std.Build, candidates: []const []const u8, dest_path: []const u8) void {
    for (candidates) |candidate| {
        if (std.fs.cwd().access(candidate, .{})) |_| {
            _ = b.addInstallFile(b.path(candidate), dest_path);
            return;
        } else |_| {}
    }
}

// Although this function looks imperative, it does not perform the build
// directly and instead it mutates the build graph (`b`) that will be then
// executed by an external runner. The functions in `std.Build` implement a DSL
// for defining build steps and express dependencies between them, allowing the
// build runner to parallelize the build automatically (and the cache system to
// know when a step doesn't need to be re-run).
pub fn build(b: *std.Build) void {
    // Standard target options allow the person running `zig build` to choose
    // what target to build for. Here we do not override the defaults, which
    // means any target is allowed, and the default is native. Other options
    // for restricting supported target set are available.
    const target = b.standardTargetOptions(.{});
    // Standard optimization options allow the person running `zig build` to select
    // between Debug, ReleaseSafe, ReleaseFast, and ReleaseSmall. Here we do not
    // set a preferred release mode, allowing the user to decide how to optimize.
    const optimize = b.standardOptimizeOption(.{});
    const target_query = target.result;
    const win32_dep = if (target_query.os.tag == .windows) b.dependency("zigwin32", .{}) else null;
    // It's also possible to define more custom flags to toggle optional features
    // of this build script using `b.option()`. All defined flags (including
    // target and optimize options) will be listed when running `zig build --help`
    // in this directory.

    // This creates a module, which represents a collection of source files alongside
    // some compilation options, such as optimization mode and linked system libraries.
    // Zig modules are the preferred way of making Zig code available to consumers.
    // addModule defines a module that we intend to make available for importing
    // to our consumers. We must give it a name because a Zig package can expose
    // multiple modules and consumers will need to be able to specify which
    // module they want to access.
    const mod = b.addModule("merrow", .{
        // The root source file is the "entry point" of this module. Users of
        // this module will only be able to access public declarations contained
        // in this file, which means that if you have declarations that you
        // intend to expose to consumers that were defined in other files part
        // of this module, you will have to make sure to re-export them from
        // the root file.
        .root_source_file = b.path("src/root.zig"),
        // Later on we'll use this module as the root module of a test executable
        // which requires us to specify a target.
        .target = target,
    });

    // Add stb_image_write C library (only once)
    mod.addIncludePath(b.path("deps"));
    mod.addCSourceFile(.{
        .file = b.path("deps/stb_impl.c"),
        .flags = &[_][]const u8{"-std=c99"},
    });
    mod.link_libc = true;

    // Here we define an executable. An executable needs to have a root module
    // which needs to expose a `main` function. While we could add a main function
    // to the module defined above, it's sometimes preferable to split business
    // logic and the CLI into two separate modules.
    //
    // If your goal is to create a Zig library for others to use, consider if
    // it might benefit from also exposing a CLI tool. A parser library for a
    // data serialization format could also bundle a CLI syntax checker, for example.
    //
    // If instead your goal is to create an executable, consider if users might
    // be interested in also being able to embed the core functionality of your
    // program in their own executable in order to avoid the overhead involved in
    // subprocessing your CLI tool.
    //
    // If neither case applies to you, feel free to delete the declaration you
    // don't need and to put everything under a single module.
    const exe = b.addExecutable(.{
        .name = "merrow",
        .root_module = b.createModule(.{
            // b.createModule defines a new module just like b.addModule but,
            // unlike b.addModule, it does not expose the module to consumers of
            // this package, which is why in this case we don't have to give it a name.
            .root_source_file = b.path("src/main.zig"),
            // Target and optimization levels must be explicitly wired in when
            // defining an executable or library (in the root module), and you
            // can also hardcode a specific target for an executable or library
            // definition if desireable (e.g. firmware for embedded devices).
            .target = target,
            .optimize = optimize,
            // List of modules available for import in source files part of the
            // root module.
            .imports = &.{
                // Here "merrow" is the name you will use in your source code to
                // import this module (e.g. `@import("merrow")`). The name is
                // repeated because you are allowed to rename your imports, which
                // can be extremely useful in case of collisions (which can happen
                // importing modules from different packages).
                .{ .name = "merrow", .module = mod },
            },
        }),
    });

    // This declares intent for the executable to be installed into the
    // install prefix when running `zig build` (i.e. when executing the default
    // step). By default the install prefix is `zig-out/` but can be overridden
    // by passing `--prefix` or `-p`.
    b.installArtifact(exe);

    if (target_query.os.tag == .macos) {
        const macos_app_exe = b.addExecutable(.{
            .name = "merrow-studio",
            .root_module = b.createModule(.{
                .root_source_file = b.path("app/main.zig"),
                .target = target,
                .optimize = optimize,
                .imports = &.{
                    .{ .name = "merrow", .module = mod },
                },
            }),
        });
        macos_app_exe.addCSourceFile(.{
            .file = b.path("app/platform/macos_app.m"),
            .flags = &[_][]const u8{"-fobjc-arc"},
        });
        macos_app_exe.addCSourceFile(.{
            .file = b.path("app/platform/merrow_freeform_canvas.m"),
            .flags = &[_][]const u8{"-fobjc-arc"},
        });
        macos_app_exe.linkLibC();
        macos_app_exe.linkFramework("AppKit");
        macos_app_exe.linkFramework("Foundation");
        macos_app_exe.linkFramework("Metal");
        macos_app_exe.linkFramework("MetalKit");
        macos_app_exe.linkFramework("QuartzCore");
        b.installArtifact(macos_app_exe);

        const macos_app_step = b.step("studio", "Run the macOS Mermaid viewer/editor scaffold");
        const macos_app_cmd = b.addRunArtifact(macos_app_exe);
        macos_app_cmd.step.dependOn(b.getInstallStep());
        if (b.args) |args| {
            macos_app_cmd.addArgs(args);
        }
        macos_app_step.dependOn(&macos_app_cmd.step);
    } else if (target_query.os.tag == .windows) {
        const windows_build_options = b.addOptions();
        windows_build_options.addOption([]const u8, "app_version", "0.0.0");

        const windows_app_exe = b.addExecutable(.{
            .name = "merrow-studio",
            .win32_manifest = b.path("app/platform/windows_app.manifest"),
            .root_module = b.createModule(.{
                .root_source_file = b.path("app/main.zig"),
                .target = target,
                .optimize = optimize,
                .imports = &.{
                    .{ .name = "merrow", .module = mod },
                    .{ .name = "build_options", .module = windows_build_options.createModule() },
                    .{ .name = "win32", .module = win32_dep.?.module("win32") },
                },
            }),
        });
        windows_app_exe.addIncludePath(b.path("deps"));
        windows_app_exe.addCSourceFile(.{
            .file = b.path("deps/sqlite3.c"),
            .flags = &[_][]const u8{
                "-DSQLITE_THREADSAFE=0",
                "-DSQLITE_OMIT_LOAD_EXTENSION",
            },
        });
        windows_app_exe.linkLibC();
        windows_app_exe.linkSystemLibrary("kernel32");
        windows_app_exe.linkSystemLibrary("user32");
        windows_app_exe.linkSystemLibrary("gdi32");
        windows_app_exe.linkSystemLibrary("comctl32");
        windows_app_exe.linkSystemLibrary("comdlg32");
        windows_app_exe.linkSystemLibrary("advapi32");
        windows_app_exe.linkSystemLibrary("d2d1");
        windows_app_exe.linkSystemLibrary("dwrite");
        windows_app_exe.linkSystemLibrary("ole32");
        windows_app_exe.linkSystemLibrary("oleaut32");
        windows_app_exe.linkSystemLibrary("windowscodecs");
        b.installArtifact(windows_app_exe);
        _ = b.addInstallFile(b.path("wordcomglue/build/wordcomglue.dll"), "bin/wordcomglue.dll");
        addFirstExistingInstallFile(b, &.{
            "s3glue/build/Release/s3glue.dll",
            "s3glue/build/RelWithDebInfo/s3glue.dll",
            "s3glue/build/MinSizeRel/s3glue.dll",
            "s3glue/build/Debug/s3glue.dll",
        }, "bin/s3glue.dll");
        addOptionalInstallFile(b, "../aws-sdk-cpp-install/bin/aws-c-auth.dll", "bin/aws-c-auth.dll");
        addOptionalInstallFile(b, "../aws-sdk-cpp-install/bin/aws-c-cal.dll", "bin/aws-c-cal.dll");
        addOptionalInstallFile(b, "../aws-sdk-cpp-install/bin/aws-c-common.dll", "bin/aws-c-common.dll");
        addOptionalInstallFile(b, "../aws-sdk-cpp-install/bin/aws-c-compression.dll", "bin/aws-c-compression.dll");
        addOptionalInstallFile(b, "../aws-sdk-cpp-install/bin/aws-c-event-stream.dll", "bin/aws-c-event-stream.dll");
        addOptionalInstallFile(b, "../aws-sdk-cpp-install/bin/aws-c-http.dll", "bin/aws-c-http.dll");
        addOptionalInstallFile(b, "../aws-sdk-cpp-install/bin/aws-c-io.dll", "bin/aws-c-io.dll");
        addOptionalInstallFile(b, "../aws-sdk-cpp-install/bin/aws-c-mqtt.dll", "bin/aws-c-mqtt.dll");
        addOptionalInstallFile(b, "../aws-sdk-cpp-install/bin/aws-c-s3.dll", "bin/aws-c-s3.dll");
        addOptionalInstallFile(b, "../aws-sdk-cpp-install/bin/aws-c-sdkutils.dll", "bin/aws-c-sdkutils.dll");
        addOptionalInstallFile(b, "../aws-sdk-cpp-install/bin/aws-checksums.dll", "bin/aws-checksums.dll");
        addOptionalInstallFile(b, "../aws-sdk-cpp-install/bin/aws-cpp-sdk-core.dll", "bin/aws-cpp-sdk-core.dll");
        addOptionalInstallFile(b, "../aws-sdk-cpp-install/bin/aws-cpp-sdk-s3.dll", "bin/aws-cpp-sdk-s3.dll");
        addOptionalInstallFile(b, "../aws-sdk-cpp-install/bin/aws-crt-cpp.dll", "bin/aws-crt-cpp.dll");
        _ = b.addInstallFile(b.path("app/assets/diagrams_header.png"), "bin/assets/diagrams_header.png");
        _ = b.addInstallFile(b.path("app/assets/diagrams_trailer.png"), "bin/assets/diagrams_trailer.png");

        const windows_app_step = b.step("studio", "Run the Windows Mermaid viewer/editor scaffold");
        const windows_app_cmd = b.addRunArtifact(windows_app_exe);
        windows_app_cmd.step.dependOn(b.getInstallStep());
        if (b.args) |args| {
            windows_app_cmd.addArgs(args);
        }
        windows_app_step.dependOn(&windows_app_cmd.step);
    }

    // This creates a top level step. Top level steps have a name and can be
    // invoked by name when running `zig build` (e.g. `zig build run`).
    // This will evaluate the `run` step rather than the default step.
    // For a top level step to actually do something, it must depend on other
    // steps (e.g. a Run step, as we will see in a moment).
    const run_step = b.step("run", "Run the app");

    // This creates a RunArtifact step in the build graph. A RunArtifact step
    // invokes an executable compiled by Zig. Steps will only be executed by the
    // runner if invoked directly by the user (in the case of top level steps)
    // or if another step depends on it, so it's up to you to define when and
    // how this Run step will be executed. In our case we want to run it when
    // the user runs `zig build run`, so we create a dependency link.
    const run_cmd = b.addRunArtifact(exe);
    run_step.dependOn(&run_cmd.step);

    // By making the run step depend on the default step, it will be run from the
    // installation directory rather than directly from within the cache directory.
    run_cmd.step.dependOn(b.getInstallStep());

    // This allows the user to pass arguments to the application in the build
    // command itself, like this: `zig build run -- arg1 arg2 etc`
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    // Render test executable
    const render_test_exe = b.addExecutable(.{
        .name = "render_test",
        .root_module = b.createModule(.{
            .root_source_file = b.path("examples/render_test.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "merrow", .module = mod },
            },
        }),
    });
    // C library already linked through module
    b.installArtifact(render_test_exe);

    const render_step = b.step("render", "Run the graph rendering test");
    const render_cmd = b.addRunArtifact(render_test_exe);
    render_cmd.step.dependOn(b.getInstallStep());
    render_step.dependOn(&render_cmd.step);

    // Mermaid file renderer executable
    const mermaid_render_exe = b.addExecutable(.{
        .name = "mermaid_render",
        .root_module = b.createModule(.{
            .root_source_file = b.path("examples/mermaid_render.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "merrow", .module = mod },
            },
        }),
    });
    b.installArtifact(mermaid_render_exe);

    const mermaid_step = b.step("mermaid", "Run the Mermaid file renderer");
    const mermaid_cmd = b.addRunArtifact(mermaid_render_exe);
    mermaid_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        mermaid_cmd.addArgs(args);
    }
    mermaid_step.dependOn(&mermaid_cmd.step);

    // HD render demo executable
    const hd_demo_exe = b.addExecutable(.{
        .name = "hd_render_demo",
        .root_module = b.createModule(.{
            .root_source_file = b.path("examples/hd_render_demo.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "merrow", .module = mod },
            },
        }),
    });
    b.installArtifact(hd_demo_exe);

    const hd_demo_step = b.step("hd-demo", "Run the HD rendering demo");
    const hd_demo_cmd = b.addRunArtifact(hd_demo_exe);
    hd_demo_cmd.step.dependOn(b.getInstallStep());
    hd_demo_step.dependOn(&hd_demo_cmd.step);

    // Alignment test executable
    const alignment_test_exe = b.addExecutable(.{
        .name = "test_alignment",
        .root_module = b.createModule(.{
            .root_source_file = b.path("test_alignment.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "merrow", .module = mod },
            },
        }),
    });
    b.installArtifact(alignment_test_exe);

    const alignment_step = b.step("test-alignment", "Run the box-line alignment test");
    const alignment_cmd = b.addRunArtifact(alignment_test_exe);
    alignment_cmd.step.dependOn(b.getInstallStep());
    alignment_step.dependOn(&alignment_cmd.step);

    // Creates an executable that will run `test` blocks from the provided module.
    // Here `mod` needs to define a target, which is why earlier we made sure to
    // set the releative field.
    const mod_tests = b.addTest(.{
        .root_module = mod,
    });

    // Tests don't need separate C compilation - they use the module

    // A run step that will run the test executable.
    const run_mod_tests = b.addRunArtifact(mod_tests);

    // Creates an executable that will run `test` blocks from the executable's
    // root module. Note that test executables only test one module at a time,
    // hence why we have to create two separate ones.
    const exe_tests = b.addTest(.{
        .root_module = exe.root_module,
    });

    // A run step that will run the second test executable.
    const run_exe_tests = b.addRunArtifact(exe_tests);

    const preview_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("app/preview.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "merrow", .module = mod },
            },
        }),
        .filters = &.{"editable graph conversion"},
    });

    const run_preview_tests = b.addRunArtifact(preview_tests);
    const preview_test_step = b.step("preview-test", "Run filtered preview freeform conversion tests");
    preview_test_step.dependOn(&run_preview_tests.step);

    const preview_roundtrip_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("app/preview.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "merrow", .module = mod },
            },
        }),
        .filters = &.{"editable graph roundtrip export"},
    });

    const run_preview_roundtrip_tests = b.addRunArtifact(preview_roundtrip_tests);
    const preview_roundtrip_test_step = b.step("preview-roundtrip-test", "Run Mermaid export/import round-trip tests");
    preview_roundtrip_test_step.dependOn(&run_preview_roundtrip_tests.step);

    const preview_lossless_roundtrip_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("app/preview.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "merrow", .module = mod },
            },
        }),
        .filters = &.{"editable graph lossless roundtrip"},
    });

    const run_preview_lossless_roundtrip_tests = b.addRunArtifact(preview_lossless_roundtrip_tests);
    const preview_lossless_roundtrip_test_step = b.step("preview-lossless-roundtrip-test", "Run lossless Mermaid round-trip tests");
    preview_lossless_roundtrip_test_step.dependOn(&run_preview_lossless_roundtrip_tests.step);

    const markdown_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("app/markdown_parser.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });

    const run_markdown_tests = b.addRunArtifact(markdown_tests);
    const markdown_test_step = b.step("markdown-test", "Run markdown document parser tests");
    markdown_test_step.dependOn(&run_markdown_tests.step);

    const windows_credentials_test_step = b.step("windows-credentials-test", "Run Windows credential storage tests");
    if (target_query.os.tag == .windows) {
        const windows_credentials_tests = b.addTest(.{
            .root_module = b.createModule(.{
                .root_source_file = b.path("app/platform/windows/credentials.zig"),
                .target = target,
                .optimize = optimize,
                .imports = &.{
                    .{ .name = "win32", .module = win32_dep.?.module("win32") },
                },
            }),
        });
        windows_credentials_tests.linkSystemLibrary("advapi32");

        const run_windows_credentials_tests = b.addRunArtifact(windows_credentials_tests);
        windows_credentials_test_step.dependOn(&run_windows_credentials_tests.step);
    }

    // A top level step for running all tests. dependOn can be called multiple
    // times and since the two run steps do not depend on one another, this will
    // make the two of them run in parallel.
    const test_step = b.step("test", "Run tests");
    test_step.dependOn(&run_mod_tests.step);
    test_step.dependOn(&run_exe_tests.step);
    test_step.dependOn(&run_preview_tests.step);
    test_step.dependOn(&run_preview_roundtrip_tests.step);
    test_step.dependOn(&run_preview_lossless_roundtrip_tests.step);
    test_step.dependOn(&run_markdown_tests.step);
    if (target_query.os.tag == .windows) {
        test_step.dependOn(windows_credentials_test_step);
    }

    // Just like flags, top level steps are also listed in the `--help` menu.
    //
    // The Zig build system is entirely implemented in userland, which means
    // that it cannot hook into private compiler APIs. All compilation work
    // orchestrated by the build system will result in other Zig compiler
    // subcommands being invoked with the right flags defined. You can observe
    // these invocations when one fails (or you pass a flag to increase
    // verbosity) to validate assumptions and diagnose problems.
    //
    // Lastly, the Zig build system is relatively simple and self-contained,
    // and reading its source code will allow you to master it.
}
