const std = @import("std");
const bytebox = @import("bytebox");
const zcomplete = @import("zcomplete");

module: *bytebox.ModuleDefinition,
instance: *bytebox.ModuleInstance,

pub fn init(gpa: std.mem.Allocator, bytes: []const u8) !@This() {
    const module = try bytebox.createModuleDefinition(gpa, .{});
    defer module.destroy();
    try module.decode(bytes);

    const instance = try bytebox.createModuleInstance(.Stack, module, gpa);
    defer instance.destroy();
    try instance.instantiate(.{});

    return .{
        .module = module,
        .instance = instance,
    };
}

pub fn deinit(self: *@This()) void {
    self.instance.destroy();
    self.module.destroy();
}

pub fn alloc(self: *@This(), count: usize) !zcomplete.WasmSlice {
    var in: [1]bytebox.Val = @splat(.{ .I64 = @intCast(count) });
    var out: [1]bytebox.Val = @splat(.{ .I64 = 0 });
    const allocH = try self.instance.getFunctionHandle("alloc");
    try self.instance.invoke(allocH, &in, &out, .{});
    return self.deref(out[0], count);
}

pub fn run(self: *@This(), inbuf: zcomplete.WasmSlice) !*zcomplete.Response.Serialized {
    var in: [1]bytebox.Val = @splat(.{ .I64 = @intCast(inbuf.ptr) });
    var out: [1]bytebox.Val = @splat(.{ .I64 = undefined });
    const runH = try self.instance.getFunctionHandle("run");
    try self.instance.invoke(runH, &in, &out, .{});
    const res = try self.deref(out[0], @sizeOf(zcomplete.Response.Serialized));
    return @ptrCast(@alignCast(res.buf));
}

pub fn deref(self: *@This(), ptr: bytebox.Val, len: usize) !zcomplete.WasmSlice {
    return .{
        .ptr = @intCast(ptr.I64),
        .buf = self.instance.memorySlice(@intCast(ptr.I64), len),
    };
}
