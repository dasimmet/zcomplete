const zcomplete = @import("zcomplete");
const specfile = @import("specfile");
const std = @import("std");

var arena = std.heap.ArenaAllocator.init(std.heap.wasm_allocator);
const allocator = arena.allocator();

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
    const ptr = allocator.alloc(
        u8,
        @bitCast(len),
    ) catch unreachable;
    return @alignCast(@ptrCast(ptr.ptr));
}

fn zcomplete_run(run: *zcomplete.Args) callconv(.C) isize {
    _ = run;
    var zc: zcomplete.AutoComplete = .{
        .allocator = std.heap.wasm_allocator,
        .run = &specfile.run_zcomplete,
        .args = &.{},
    };
    zc.run(&zc);
    return 0;
}
