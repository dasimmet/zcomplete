const std = @import("std");
const zware = @import("zware");
const zcomplete = @import("zcomplete");

store: *zware.Store,
module: *zware.Module,
instance: *zware.Instance,

pub fn init(gpa: std.mem.Allocator, bytes: []const u8) !@This() {
    const store = try gpa.create(zware.Store);
    const module = try gpa.create(zware.Module);
    const instance = try gpa.create(zware.Instance);
    store.* = zware.Store.init(gpa);
    module.* = zware.Module.init(gpa, bytes);
    try module.decode();

    instance.* = zware.Instance.init(gpa, store, module.*);
    try instance.instantiate();
    return .{
        .store = store,
        .module = module,
        .instance = instance,
    };
}

pub fn deinit(self: *@This()) void {
    const allocator = self.instance.alloc;
    self.instance.deinit();
    self.module.deinit();
    self.store.deinit();
    allocator.destroy(self.instance);
    allocator.destroy(self.module);
    allocator.destroy(self.store);
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
