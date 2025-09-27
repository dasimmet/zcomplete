const std = @import("std");
const zware = @import("zware");
const zcomplete = @import("zcomplete");
store: zware.Store,
module: zware.Module,
instance: zware.Instance,

pub inline fn init(gpa: std.mem.Allocator, bytes: []const u8) !@This() {
    var self: @This() = .{
        .store = zware.Store.init(gpa),
        .module = undefined,
        .instance = undefined,
    };
    self.module = zware.Module.init(gpa, bytes);
    try self.module.decode();

    self.instance = zware.Instance.init(gpa, &self.store, self.module);
    try self.instance.instantiate();
    return self;
}

pub fn deinit(self: *@This()) void {
    self.instance.deinit();
    self.module.deinit();
    self.store.deinit();
}

pub fn alloc(self: *@This(), count: usize) !zcomplete.WasmSlice {
    var in: [1]u64 = @splat(count);
    var out: [1]u64 = @splat(0);
    try self.instance.invoke("alloc", &in, &out, .{});
    return self.deref(out[0], count);
}

pub fn run(self: *@This(), inbuf: zcomplete.WasmSlice) !*zcomplete.Response.Serialized {
    var in: [1]u64 = @splat(inbuf.ptr);
    var out: [1]u64 = undefined;
    try self.instance.invoke("run", &in, &out, .{});
    const res = try self.deref(out[0], @sizeOf(zcomplete.Response.Serialized));
    return @ptrCast(@alignCast(res.buf));
}

pub fn deref(self: *@This(), ptr: usize, len: usize) !zcomplete.WasmSlice {
    const mem = try self.instance.getMemory(0);
    return .{
        .ptr = ptr,
        .buf = mem.memory()[ptr .. ptr + len],
    };
}
