const std = @import("std");
const Pkg = std.build.Pkg;

const packages = [_]Pkg{
    Pkg{
        .name = "clap",
        .source = .{ .path = "libs/clap/clap.zig" },
    },
};

pub fn build(b: *std.build.Builder) void {
    // Standard target options allows the person running `zig build` to choose
    // what target to build for. Here we do not override the defaults, which
    // means any target is allowed, and the default is native. Other options
    // for restricting supported target set are available.
    const target = b.standardTargetOptions(.{});

    // Standard release options allow the person running `zig build` to select
    // between Debug, ReleaseSafe, ReleaseFast, and ReleaseSmall.
    const mode = b.standardReleaseOptions();

    inline for (.{
        .{ .sub="clapcomplete", .src="src/main.zig" , .default=true },
        .{ .sub="example", .src="src/example.zig" , .default=false },
    }) |sub| {
        const exe = b.addExecutable(sub.sub, sub.src);
        exe.setTarget(target);
        exe.setBuildMode(mode);
        inline for (packages) |pac| {
            exe.addPackage(pac);
        }
        exe.install();
        const build_step = b.step(sub.sub, "build "++sub.sub);
        build_step.dependOn(&exe.step);
        const run_cmd = exe.run();
        run_cmd.step.dependOn(&exe.step);
        if (b.args) |args| {
            run_cmd.addArgs(args);
        }
        const run_step = b.step("run-"++sub.sub, "Run the app "++sub.sub);
        run_step.dependOn(&run_cmd.step);
        const exe_tests = b.addTest(sub.src);
        exe_tests.setTarget(target);
        exe_tests.setBuildMode(mode);
        const test_step = b.step("test"++sub.sub, "Run unit tests");
        test_step.dependOn(&exe_tests.step);

        if (sub.default) {
            const run_default_cmd = exe.run();
            run_default_cmd.step.dependOn(&exe.step);
            if (b.args) |args| {
                run_default_cmd.addArgs(args);
            }
            const run_default_step = b.step("run", "Run the app "++sub.sub);
            run_default_step.dependOn(&run_cmd.step);

            const exe_default_tests = b.addTest(sub.src);
            exe_default_tests.setTarget(target);
            exe_tests.setBuildMode(mode);

            const test_default_step = b.step("test", "Run unit tests");
            test_default_step.dependOn(&exe_tests.step);

        }
    }
}
