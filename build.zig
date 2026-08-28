const std = @import("std");
const LazyPath = std.Build.LazyPath;

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const known_folders = b.dependency("known_folders", .{}).module("known-folders");

    const zcomplete_options = b.addOptions();
    zcomplete_options.addOption(bool, "wasm_mode", false);

    const zcomplete = b.addModule("zcomplete", .{
        .root_source_file = b.path("src/root.zig"),
        .imports = &.{
            .{ .name = "options", .module = zcomplete_options.createModule() },
        },
    });

    const simple_exe = b.addExecutable(.{
        .name = "simple-example",
        .root_module = b.createModule(.{
            .root_source_file = b.path("examples/simple-example.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "zcomplete", .module = zcomplete },
                .{
                    .name = "zcomplete_bin",
                    .module = ZComplete.builtinModule(
                        b,
                        "simple-example-zcomplete",
                        zcomplete,
                        b.path("examples/simple-example.zcomplete.zig"),
                    ),
                },
            },
        }),
    });
    simple_exe.use_llvm = true;
    const example_step = b.step("example", "build an example with embedded completion");
    example_step.dependOn(&b.addInstallArtifact(simple_exe, .{}).step);

    const wasmbackend = b.option(
        enum { zware, wasmz, zwasm },
        "wasmbackend",
        "WASM execution backend (zware, wasmz, zwasm)",
    ) orelse .zware;

    const wasmbackend_mod = switch (wasmbackend) {
        .zware => b.createModule(.{
            .root_source_file = b.path("src/backend/zware.zig"),
            .imports = if (b.lazyDependency("zware", .{
                .target = target,
                .optimize = optimize,
            })) |zware| &.{
                .{ .name = "zcomplete", .module = zcomplete },
                .{ .name = "zware", .module = zware.module("zware") },
            } else &.{
                .{ .name = "zcomplete", .module = zcomplete },
            },
        }),
        .wasmz => b.createModule(.{
            .root_source_file = b.path("src/backend/wasmz.zig"),
            .imports = if (b.lazyDependency("wasmz", .{
                .target = target,
                .optimize = optimize,
            })) |wasmz| &.{
                .{ .name = "zcomplete", .module = zcomplete },
                .{ .name = "wasmz", .module = wasmz.module("wasmz") },
            } else &.{
                .{ .name = "zcomplete", .module = zcomplete },
            },
        }),
        .zwasm => b.createModule(.{
            .root_source_file = b.path("src/backend/zwasm.zig"),
            .imports = if (b.lazyDependency("zwasm", .{
                .target = target,
                .optimize = optimize,
            })) |zwasm| &.{
                .{ .name = "zcomplete", .module = zcomplete },
                .{ .name = "zwasm", .module = zwasm.module("zwasm") },
            } else &.{
                .{ .name = "zcomplete", .module = zcomplete },
            },
        }),
    };

    const exe = b.addExecutable(.{
        .name = "zcomp",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/zcomp.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "known-folders", .module = known_folders },
                .{ .name = "zcomplete", .module = zcomplete },
                .{ .name = "wasmbackend", .module = wasmbackend_mod },
                .{
                    .name = "zcomplete_bin",
                    .module = ZComplete.builtinModule(
                        b,
                        "zcomp-zcomplete",
                        zcomplete,
                        b.path("src/zcomp.zcomplete.zig"),
                    ),
                },
            },
        }),
    });
    exe.use_llvm = true;
    b.installArtifact(exe);

    const add_completion = b.addInstallFile(
        b.path("src/share/zcomplete.bash"),
        "share/bash-completion/completions/zcomplete.bash",
    );
    b.getInstallStep().dependOn(&add_completion.step);

    const run_cmd = b.addRunArtifact(exe);
    run_cmd.has_side_effects = true;
    if (b.args) |args| {
        run_cmd.addArgs(args);
    } else {
        run_cmd.addArg("complete");
        run_cmd.addFileArg(simple_exe.getEmittedBin());
        run_cmd.addArg("--");
    }
    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);

    const zcomp_zcomplete_test = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/zcomp.zcomplete.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "zcomplete", .module = zcomplete },
                .{ .name = "known-folders", .module = known_folders },
                .{ .name = "wasmbackend", .module = wasmbackend_mod },
                .{
                    .name = "zcomplete_bin",
                    .module = ZComplete.builtinModule(
                        b,
                        "zcomp-zcomplete",
                        zcomplete,
                        b.path("src/zcomp.zcomplete.zig"),
                    ),
                },
            },
        }),
    });
    const run_test = b.addRunArtifact(zcomp_zcomplete_test);

    const test_complete_step = b.step("test-complete", "Run zcomp complete tests covering all features");

    // 1. complete root commands & flags
    const run_complete_root = b.addRunArtifact(exe);
    run_complete_root.addArg("complete");
    run_complete_root.addFileArg(exe.getEmittedBin());
    test_complete_step.dependOn(&run_complete_root.step);

    // 2. complete positional file option on extract
    const run_complete_extract = b.addRunArtifact(exe);
    run_complete_extract.addArg("complete");
    run_complete_extract.addFileArg(exe.getEmittedBin());
    run_complete_extract.addArg("extract");
    run_complete_extract.addArg("");
    test_complete_step.dependOn(&run_complete_extract.step);

    // 3. complete positional file option on complete
    const run_complete_complete = b.addRunArtifact(exe);
    run_complete_complete.addArg("complete");
    run_complete_complete.addFileArg(exe.getEmittedBin());
    run_complete_complete.addArg("complete");
    run_complete_complete.addArg("");
    test_complete_step.dependOn(&run_complete_complete.step);

    // 4. complete int range option on bash
    const run_complete_bash = b.addRunArtifact(exe);
    run_complete_bash.addArg("complete");
    run_complete_bash.addFileArg(exe.getEmittedBin());
    run_complete_bash.addArg("bash");
    run_complete_bash.addArg("");
    test_complete_step.dependOn(&run_complete_bash.step);

    // 5. complete subcommands on help
    const run_complete_help = b.addRunArtifact(exe);
    run_complete_help.addArg("complete");
    run_complete_help.addFileArg(exe.getEmittedBin());
    run_complete_help.addArg("help");
    run_complete_help.addArg("");
    test_complete_step.dependOn(&run_complete_help.step);

    // 6. bash mode: root commands completion
    const run_bash_root = b.addRunArtifact(exe);
    run_bash_root.addArg("bash");
    run_bash_root.addArg("1");
    run_bash_root.addFileArg(exe.getEmittedBin());
    test_complete_step.dependOn(&run_bash_root.step);

    // 7. bash mode: path completion with directory
    const run_bash_path_dir = b.addRunArtifact(exe);
    run_bash_path_dir.addArg("bash");
    run_bash_path_dir.addArg("2");
    run_bash_path_dir.addFileArg(exe.getEmittedBin());
    run_bash_path_dir.addArg("extract");
    run_bash_path_dir.addArg("src/");
    test_complete_step.dependOn(&run_bash_path_dir.step);

    // 8. bash mode: path completion with prefix
    const run_bash_path_prefix = b.addRunArtifact(exe);
    run_bash_path_prefix.addArg("bash");
    run_bash_path_prefix.addArg("2");
    run_bash_path_prefix.addFileArg(exe.getEmittedBin());
    run_bash_path_prefix.addArg("extract");
    run_bash_path_prefix.addArg("src/z");
    test_complete_step.dependOn(&run_bash_path_prefix.step);

    // 9. bash mode: int range completion
    const run_bash_range = b.addRunArtifact(exe);
    run_bash_range.addArg("bash");
    run_bash_range.addArg("2");
    run_bash_range.addFileArg(exe.getEmittedBin());
    run_bash_range.addArg("bash");
    test_complete_step.dependOn(&run_bash_range.step);

    const simple_example_test = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("examples/simple-example.zcomplete.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "zcomplete", .module = zcomplete },
            },
        }),
    });
    const run_simple_test = b.addRunArtifact(simple_example_test);

    // 10. complete simple-example root
    const run_complete_simple_root = b.addRunArtifact(exe);
    run_complete_simple_root.addArg("complete");
    run_complete_simple_root.addFileArg(simple_exe.getEmittedBin());
    test_complete_step.dependOn(&run_complete_simple_root.step);

    // 11. complete simple-example nested build
    const run_complete_simple_build = b.addRunArtifact(exe);
    run_complete_simple_build.addArg("complete");
    run_complete_simple_build.addFileArg(simple_exe.getEmittedBin());
    run_complete_simple_build.addArg("build");
    run_complete_simple_build.addArg("");
    test_complete_step.dependOn(&run_complete_simple_build.step);

    // 12. complete simple-example nested build wasm (pattern *.zig)
    const run_complete_simple_wasm = b.addRunArtifact(exe);
    run_complete_simple_wasm.addArg("complete");
    run_complete_simple_wasm.addFileArg(simple_exe.getEmittedBin());
    run_complete_simple_wasm.addArg("build");
    run_complete_simple_wasm.addArg("wasm");
    run_complete_simple_wasm.addArg("");
    test_complete_step.dependOn(&run_complete_simple_wasm.step);

    // 13. bash mode: pattern filtered path completion on simple-example
    const run_bash_simple_zig = b.addRunArtifact(exe);
    run_bash_simple_zig.addArg("bash");
    run_bash_simple_zig.addArg("3");
    run_bash_simple_zig.addFileArg(simple_exe.getEmittedBin());
    run_bash_simple_zig.addArg("build");
    run_bash_simple_zig.addArg("wasm");
    run_bash_simple_zig.addArg("src/");
    test_complete_step.dependOn(&run_bash_simple_zig.step);

    // 14. cross-platform tests: Windows PE executable extraction & completion
    const win_target = b.resolveTargetQuery(.{
        .cpu_arch = .x86_64,
        .os_tag = .windows,
    });
    const simple_exe_win = b.addExecutable(.{
        .name = "simple-example-win",
        .root_module = b.createModule(.{
            .root_source_file = b.path("examples/simple-example.zig"),
            .target = win_target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "zcomplete", .module = zcomplete },
                .{
                    .name = "zcomplete_bin",
                    .module = ZComplete.builtinModule(
                        b,
                        "simple-example-zcomplete-win",
                        zcomplete,
                        b.path("examples/simple-example.zcomplete.zig"),
                    ),
                },
            },
        }),
    });
    simple_exe_win.use_llvm = true;

    const run_complete_win = b.addRunArtifact(exe);
    run_complete_win.addArg("complete");
    run_complete_win.addFileArg(simple_exe_win.getEmittedBin());
    run_complete_win.addArg("");
    test_complete_step.dependOn(&run_complete_win.step);

    const run_extract_win = b.addRunArtifact(exe);
    run_extract_win.addArg("extract");
    run_extract_win.addFileArg(simple_exe_win.getEmittedBin());
    const win_extracted = run_extract_win.addOutputFileArg("win_extracted.wasm");
    test_complete_step.dependOn(&run_extract_win.step);
    _ = win_extracted;

    // 15. cross-platform tests: macOS Mach-O executable extraction & completion
    const macos_target = b.resolveTargetQuery(.{
        .cpu_arch = .aarch64,
        .os_tag = .macos,
    });
    const simple_exe_macos = b.addExecutable(.{
        .name = "simple-example-macos",
        .root_module = b.createModule(.{
            .root_source_file = b.path("examples/simple-example.zig"),
            .target = macos_target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "zcomplete", .module = zcomplete },
                .{
                    .name = "zcomplete_bin",
                    .module = ZComplete.builtinModule(
                        b,
                        "simple-example-zcomplete-macos",
                        zcomplete,
                        b.path("examples/simple-example.zcomplete.zig"),
                    ),
                },
            },
        }),
    });

    const run_complete_macos = b.addRunArtifact(exe);
    run_complete_macos.addArg("complete");
    run_complete_macos.addFileArg(simple_exe_macos.getEmittedBin());
    run_complete_macos.addArg("");
    test_complete_step.dependOn(&run_complete_macos.step);

    const run_extract_macos = b.addRunArtifact(exe);
    run_extract_macos.addArg("extract");
    run_extract_macos.addFileArg(simple_exe_macos.getEmittedBin());
    const macos_extracted = run_extract_macos.addOutputFileArg("macos_extracted.wasm");
    test_complete_step.dependOn(&run_extract_macos.step);
    _ = macos_extracted;

    const section_test = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/section.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    const run_section_test = b.addRunArtifact(section_test);

    const test_step = b.step("test", "Run unit tests and completion tests");
    test_step.dependOn(&run_test.step);
    test_step.dependOn(&run_simple_test.step);
    test_step.dependOn(&run_section_test.step);
    test_step.dependOn(test_complete_step);
}

pub const ZComplete = struct {
    pub fn addLazyPath(b: *std.Build, exe: *std.Build.Step.Compile, zcomplete: *std.Build.Module, specfile: LazyPath) void {
        exe.root_module.addImport(
            "zcomplete_bin",
            builtinModule(b, b.fmt("{s}-zcomplete", .{exe.name}), zcomplete, specfile),
        );
    }

    pub fn builtinModule(b: *std.Build, name: []const u8, zcomplete: *std.Build.Module, specfile: LazyPath) *std.Build.Module {
        return builtinModuleFromMod(b, name, zcomplete, b.createModule(.{
            .root_source_file = specfile,
            .imports = &.{
                .{ .name = "zcomplete", .module = zcomplete },
            },
        }));
    }

    pub fn builtinModuleFromMod(b: *std.Build, name: []const u8, zcomplete: *std.Build.Module, spec_mod: *std.Build.Module) *std.Build.Module {
        const exe = buildExe(b, name, zcomplete, spec_mod);
        return b.createModule(.{
            .root_source_file = exe.getEmittedBin(),
        });
    }

    pub fn buildExe(b: *std.Build, name: []const u8, zcomplete: *std.Build.Module, spec_mod: *std.Build.Module) *std.Build.Step.Compile {
        const exe = b.addExecutable(.{
            .name = name,
            .root_module = b.createModule(.{
                .root_source_file = b.path("src/module.zig"),
                .target = b.resolveTargetQuery(.{
                    .cpu_arch = .wasm32,
                    .os_tag = .freestanding,
                    .abi = .none,
                    .cpu_model = .{
                        .explicit = std.Target.Cpu.Model.generic(.wasm32),
                    },
                }),
                .optimize = .ReleaseSmall,
                .imports = &.{
                    .{ .name = "specfile", .module = spec_mod },
                    .{ .name = "zcomplete", .module = zcomplete },
                },
            }),
        });
        exe.rdynamic = true;
        exe.entry = .disabled;
        exe.use_llvm = true;

        return exe;
    }
};
