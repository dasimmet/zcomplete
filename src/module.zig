const zcomplete = @import("zcomplete");
const specfile = @import("specfile");
const std = @import("std");

var arena = std.heap.ArenaAllocator.init(std.heap.wasm_allocator);
const allocator = arena.allocator();

comptime {
    @export(&zcomplete_alloc, .{
        .section = "zcomplete",
        .name = "alloc",
    });
    @export(&zcomplete_run, .{
        .section = "zcomplete",
        .name = "run",
    });
}

fn zcomplete_alloc(len: isize) callconv(.C) [*]u8 {
    const ptr = allocator.alloc(
        u8,
        @bitCast(len),
    ) catch unreachable;
    @memset(ptr, 48);
    return @alignCast(@ptrCast(ptr.ptr));
}

fn zcomplete_run(args: *zcomplete.Args) callconv(.C) *zcomplete.Response.Serialized {
    var autocomplete = allocator.create(zcomplete.AutoComplete) catch unreachable;
    autocomplete.allocator = allocator;
    const ptr: [*]u8 = @ptrFromInt(@intFromPtr(args) + @as(usize, @intCast(args.offset)));
    var array = std.ArrayListUnmanaged([:0]const u8).empty;
    var last_zero: usize = 0;
    for (ptr[0..@intCast(args.len)], 0..) |c, i| {
        if (c == 0) {
            array.append(allocator, @ptrCast(ptr[last_zero..i])) catch unreachable;
            last_zero = i + 1;
        }
    }
    autocomplete.args = array.toOwnedSlice(allocator) catch unreachable;
    specfile.run_zcomplete(autocomplete);
    return autocomplete.serialize();
}
