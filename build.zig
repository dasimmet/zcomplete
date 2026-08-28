const std = @import("std");
const LazyPath = std.Build.LazyPath;

pub const Backend = enum {
    no_backend,
    clap,
};

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const known_folders = b.dependency("known_folders", .{}).module("known-folders");

    const backend = b.option(
        Backend,
        "backend",
        "the argument backend type to use",
    ) orelse .no_backend;

    var backend_module = if (b.option(
        std.Build.LazyPath,
        "backend_module",
        "provide your own backend as a LazyPath",
    )) |backend_module_path| b.addModule("backend", .{
        .root_source_file = backend_module_path,
        .target = target,
        .optimize = optimize,
    }) else null;

    if (backend_module == null) {
        switch (backend) {
            .no_backend => {},
            .clap => {
                if (b.lazyDependency("clap", .{})) |clap| {
                    backend_module = clap.module("clap");
                } else {
                    // we assume to have a backend module after this...but zig might need to download it.
                    backend_module = b.addModule("lazy fallback module", .{
                        .root_source_file = b.path("lazy fallback module"),
                    });
                }
            },
        }
    }

    const zcomplete_options = b.addOptions();
    zcomplete_options.addOption(Backend, "backend", backend);
    zcomplete_options.addOption(bool, "wasm_mode", false);

    const zcomplete = b.addModule("zcomplete", .{
        .root_source_file = b.path("src/root.zig"),
        .imports = if (backend_module) |bm| &.{
            .{ .name = "backend", .module = bm },
            .{ .name = "options", .module = zcomplete_options.createModule() },
        } else &.{
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
                        "simples",
                        zcomplete,
                        b.path("examples/simple-example.zcomplete.zig"),
                    ),
                },
            },
        }),
    });
    // ZComplete.addLazyPath(b, simple_exe, zcomplete, b.path("examples/simple-example.zcomplete.zig"));
    const example_step = b.step("example", "build an example with embedded completion");
    example_step.dependOn(&b.addInstallArtifact(simple_exe, .{}).step);

    const wasmbackend = b.option(
        enum { zware, wasmz },
        "wasmbackend",
        "",
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

    const run_complete_self = b.addRunArtifact(exe);
    run_complete_self.addArg("complete");
    run_complete_self.addFileArg(exe.getEmittedBin());

    const test_complete_step = b.step("test-complete", "Run zcomp complete on itself");
    test_complete_step.dependOn(&run_complete_self.step);

    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_test.step);
    test_step.dependOn(&run_complete_self.step);
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
