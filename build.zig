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

    const zcomplete = b.addModule("zcomplete", .{
        .root_source_file = b.path("src/zcomplete.zig"),
    });
    if (backend_module) |bm| {
        zcomplete.addImport("backend", bm);
    }
    const zcomplete_options = b.addOptions();
    zcomplete_options.addOption(Backend, "backend", backend);
    zcomplete_options.addOption(bool, "wasm_mode", false);
    zcomplete.addOptions("options", zcomplete_options);

    const simple_exe = b.addExecutable(.{
        .name = "simple-example",
        .root_source_file = b.path("examples/simple-example.zig"),
        .target = target,
        .optimize = optimize,
    });
    ZComplete.addLazyPath(b, simple_exe, zcomplete, b.path("examples/simple-example.zcomplete.zig"));
    const example_step = b.step("example", "build an example with embedded completion");
    example_step.dependOn(&b.addInstallArtifact(simple_exe, .{}).step);

    const example = switch (backend) {
        .clap => blk: {
            const clap_exe = b.addExecutable(.{
                .name = "clap-example",
                .root_source_file = b.path("examples/clap.zig"),
                .target = target,
                .optimize = optimize,
            });
            clap_exe.root_module.addImport("clap", backend_module.?);
            {
                const clap_exe_complete = b.addModule("clap-example-zcomplete", .{
                    .root_source_file = b.path("examples/clap.zcomplete.zig"),
                });
                clap_exe_complete.addImport("clap", backend_module.?);
                clap_exe_complete.addImport("zcomplete", zcomplete);
                ZComplete.addModule(b, clap_exe, zcomplete, clap_exe_complete);
            }
            example_step.dependOn(&b.addInstallArtifact(clap_exe, .{}).step);
            break :blk clap_exe;
        },
        .no_backend => simple_exe,
    };

    const exe = b.addExecutable(.{
        .name = "zcomp",
        .root_source_file = b.path("src/zcomp.zig"),
        .target = target,
        .optimize = optimize,
    });
    exe.root_module.addImport("known-folders", known_folders);
    exe.root_module.addImport("zcomplete", zcomplete);
    exe.root_module.addImport("zware", b.dependency("zware", .{
        .target = target,
        .optimize = optimize,
    }).module("zware"));
    ZComplete.addLazyPath(b, exe, zcomplete, b.path("src/zcomp.zcomplete.zig"));
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
        run_cmd.addFileArg(example.getEmittedBin());
        run_cmd.addArg("--");
    }
    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);
}

pub const ZComplete = struct {
    pub fn addLazyPath(b: *std.Build, exe: *std.Build.Step.Compile, zcomplete: *std.Build.Module, specfile: LazyPath) void {
        const spec_mod = b.addModule("specfile", .{
            .root_source_file = specfile,
        });
        spec_mod.addImport("zcomplete", zcomplete);
        return addModule(b, exe, zcomplete, spec_mod);
    }

    pub fn addModule(b: *std.Build, exe: *std.Build.Step.Compile, zcomplete: *std.Build.Module, spec_mod: *std.Build.Module) void {
        const spec_exe = buildExe(
            b,
            b.fmt("{s}-zcomplete", .{exe.name}),
            zcomplete,
            spec_mod,
        );
        exe.setLinkerScript(zcomplete_ldgen(b, zcomplete, spec_exe.getEmittedBin()));
    }

    pub fn buildExe(b: *std.Build, name: []const u8, zcomplete: *std.Build.Module, spec_mod: *std.Build.Module) *std.Build.Step.Compile {
        const exe = b.addExecutable(.{
            .name = name,
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
        });
        exe.rdynamic = true;
        exe.entry = .disabled;
        exe.root_module.addImport("specfile", spec_mod);
        exe.root_module.addImport("zcomplete", zcomplete);

        return exe;
    }
};

pub fn zcomplete_ldgen(b: *std.Build, zcomplete: *std.Build.Module, src_exe: LazyPath) LazyPath {
    const ldgen = b.addExecutable(.{
        .name = "ldgen",
        .target = b.graph.host,
        .optimize = .Debug,
        .root_source_file = b.path("src/ldgen.zig"),
    });
    ldgen.root_module.addImport("zcomplete", zcomplete);
    const run = b.addRunArtifact(ldgen);
    if (b.verbose) {
        run.setEnvironmentVariable("LDGEN_VERBOSE", "1");
    }
    run.addFileArg(src_exe);
    return run.addOutputFileArg("ldgen.ld");
}
