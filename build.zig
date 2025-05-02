const std = @import("std");
const LazyPath = std.Build.LazyPath;

pub const Backend = enum {
    no_backend,
    clap,
};

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const backend = b.option(
        Backend,
        "backend",
        "the argument backend type to use",
    ) orelse .clap;

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

    const no_backend_exe = b.addExecutable(.{
        .name = "no_backend-example",
        .root_source_file = b.path("examples/no_backend.zig"),
        .target = target,
        .optimize = optimize,
    });
    addZComplete(b, no_backend_exe, zcomplete, b.path("examples/no_backend.zcomplete.zig"));
    b.installArtifact(no_backend_exe);

    const example = switch (backend) {
        .clap => blk: {
            const clap_exe = b.addExecutable(.{
                .name = "clap-example",
                .root_source_file = b.path("examples/clap.zig"),
                .target = target,
                .optimize = optimize,
            });
            clap_exe.root_module.addImport("clap", backend_module.?);
            addZComplete(b, clap_exe, zcomplete, b.path("examples/clap.zcomplete.zig"));
            b.installArtifact(clap_exe);
            break :blk clap_exe;
        },
        .no_backend => no_backend_exe,
    };

    const exe = b.addExecutable(.{
        .name = "zcomp",
        .root_source_file = b.path("src/zcomp.zig"),
        .target = target,
        .optimize = optimize,
    });
    exe.root_module.addImport("zcomplete", zcomplete);
    exe.root_module.addImport("zware", b.dependency("zware", .{
        .target = target,
        .optimize = optimize,
    }).module("zware"));
    b.installArtifact(exe);

    const run_cmd = b.addRunArtifact(exe);
    run_cmd.has_side_effects = true;
    if (b.args) |args| {
        run_cmd.addArgs(args);
    } else {
        run_cmd.addFileArg(example.getEmittedBin());
        b.getInstallStep().dependOn(
            &b.addInstallFile(
                run_cmd.addOutputFileArg("example.wasm"),
                "bin/example.wasm",
            ).step,
        );
        run_cmd.addArg("as");
        run_cmd.addArg("abc5");
        run_cmd.addArg("abc5");
    }
    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);
}

pub fn addZComplete(b: *std.Build, exe: *std.Build.Step.Compile, zcomplete: *std.Build.Module, specfile: LazyPath) void {
    const spec_mod = b.addModule("specfile", .{
        .root_source_file = specfile,
    });
    spec_mod.addImport("zcomplete", zcomplete);

    const spec_exe = b.addExecutable(.{
        .name = b.fmt("{s}-zcomplete", .{exe.name}),
        .root_source_file = b.path("src/module.zig"),
        .target = b.resolveTargetQuery(.{
            .cpu_arch = .wasm32,
            .os_tag = .freestanding,
        }),
        .optimize = .ReleaseSmall,
        .strip = true,
    });
    spec_exe.rdynamic = true;
    spec_exe.export_table = true;
    spec_exe.entry = .disabled;
    spec_exe.root_module.addImport("specfile", spec_mod);
    spec_exe.root_module.addImport("zcomplete", zcomplete);

    exe.setLinkerScript(zcomplete_ldgen(b, spec_exe.getEmittedBin()));

    // if (b.option(bool, "wat", "wat") orelse false) {
    //     if (b.lazyImport(@This(), "wabt")) |wabt| {
    //         const my_wat: LazyPath = wabt.wasm2wat(
    //             b,
    //             spec_exe.getEmittedBin(),
    //             "spec.wat",
    //             &.{},
    //         );
    //         b.getInstallStep().dependOn(
    //             &b.addInstallFile(my_wat, "bin/spec.wat").step,
    //         );
    //     }
    // }
}

pub fn zcomplete_ldgen(b: *std.Build, src_exe: LazyPath) LazyPath {
    const ldgen = b.addExecutable(.{
        .name = "ldgen",
        .target = b.graph.host,
        .optimize = .Debug,
        .root_source_file = b.path("src/ldgen.zig"),
    });
    const run = b.addRunArtifact(ldgen);
    run.addFileArg(src_exe);
    return run.addOutputFileArg("ldgen.ld");
}
