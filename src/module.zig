const zcomplete = @import("zcomplete");
const specfile = @import("specfile");
const std = @import("std");

comptime {
    // if (std.meta.hasFn(root, "run_zcomplete")) {
    @export(&zcomplete_alloc, .{
        .section = "zcomplete",
        .name = "alloc",
    });
    @export(&zcomplete_run, .{
        .section = "zcomplete",
        .name = "run",
    });
    // }
}

fn zcomplete_alloc(len: isize) callconv(.C) [*]u8 {
    const ptr = std.heap.wasm_allocator.alloc(
        u8,
        @bitCast(len),
    ) catch unreachable;
    return @alignCast(@ptrCast(ptr.ptr));
}

fn zcomplete_run(run: *zcomplete.Args) callconv(.C) isize {
    _ = run;
    var zc: zcomplete.AutoComplete = undefined;
    zc.run = &specfile.run_zcomplete;
    zc.run(&zc);
    return 0;
}
