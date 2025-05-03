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
    ) catch @panic("OOM");
    return @alignCast(@ptrCast(ptr.ptr));
}

fn zcomplete_run(args: *zcomplete.Args) callconv(.C) *zcomplete.Response.Serialized {
    var autocomplete = allocator.create(zcomplete.AutoComplete) catch @panic("OOM");
    autocomplete.allocator = allocator;
    autocomplete.args = args.parse(allocator) catch @panic("OOM");
    if (function_returns_error(@TypeOf(specfile.zcomp))) {
        specfile.zcomp(autocomplete) catch autocomplete.respond(.zcomperror);
    } else {
        specfile.zcomp(autocomplete);
    }
    return autocomplete.serialize();
}

inline fn function_returns_error(T: type) bool {
    const return_type = @typeInfo(T).@"fn".return_type orelse return false;
    return switch (@typeInfo(return_type)) {
        .error_union => true,
        else => false,
    };
}
