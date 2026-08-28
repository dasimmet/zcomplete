const std = @import("std");
const wasmz = @import("wasmz");
const zcomplete = @import("zcomplete");

const Runtime = struct {
    engine: wasmz.Engine,
    store: wasmz.Store,
    instance: wasmz.Instance,
};

runtime: *Runtime,

pub fn init(gpa: std.mem.Allocator, bytes: []const u8) !@This() {
    const runtime = try gpa.create(Runtime);
    errdefer gpa.destroy(runtime);

    runtime.engine = try wasmz.Engine.init(gpa, .{});
    errdefer runtime.engine.deinit();

    const arc_module = try wasmz.Module.compileArc(runtime.engine, bytes);
    errdefer {
        if (arc_module.releaseUnwrap()) |m| {
            var mod = m;
            mod.deinit();
        }
    }

    runtime.store = try wasmz.Store.init(gpa, runtime.engine, std.Io.Threaded.global_single_threaded.io());
    errdefer runtime.store.deinit();

    runtime.instance = try wasmz.Instance.init(&runtime.store, arc_module, .empty);
    errdefer runtime.instance.deinit();

    return .{
        .runtime = runtime,
    };
}

pub fn deinit(self: *@This()) void {
    const gpa = self.runtime.store.allocator;
    self.runtime.instance.deinit();
    self.runtime.store.deinit();
    self.runtime.engine.deinit();
    gpa.destroy(self.runtime);
}

pub fn alloc(self: *@This(), count: usize) !zcomplete.WasmSlice {
    const res = try self.runtime.instance.call("alloc", &.{wasmz.RawVal.from(@as(i32, @intCast(count)))});
    switch (res) {
        .ok => |val| {
            const ptr = (val orelse return error.NullPointer).readAs(u32);
            return self.deref(ptr, count);
        },
        .trap => return error.WasmTrap,
    }
}

pub fn run(self: *@This(), inbuf: zcomplete.WasmSlice) !*zcomplete.Response.Serialized {
    const res = try self.runtime.instance.call("run", &.{wasmz.RawVal.from(@as(i32, @intCast(inbuf.ptr)))});
    switch (res) {
        .ok => |val| {
            const ptr = (val orelse return error.NullPointer).readAs(u32);
            const slice = try self.deref(ptr, @sizeOf(zcomplete.Response.Serialized));
            return @ptrCast(@alignCast(slice.buf));
        },
        .trap => return error.WasmTrap,
    }
}

fn deref(self: *@This(), ptr: usize, len: usize) !zcomplete.WasmSlice {
    const mem = self.runtime.instance.memory.bytes();
    if (ptr + len > mem.len) return error.OutOfBoundsMemoryAccess;
    return .{
        .ptr = ptr,
        .buf = mem[ptr .. ptr + len],
    };
}
