//! WebAssembly execution backend powered by the `zwasm` runtime.
//! Provides sandboxed execution of embedded .zcomplete WASM modules.

const std = @import("std");
const zwasm = @import("zwasm");
const zcomplete = @import("zcomplete");

const Runtime = struct {
    engine: zwasm.Engine,
    module: zwasm.Module,
    instance: zwasm.Instance,
};

runtime: *Runtime,

pub fn init(gpa: std.mem.Allocator, bytes: []const u8) !@This() {
    const runtime = try gpa.create(Runtime);
    errdefer gpa.destroy(runtime);

    runtime.engine = try zwasm.Engine.init(gpa, .{});
    errdefer runtime.engine.deinit();

    runtime.module = try runtime.engine.compile(bytes);
    errdefer runtime.module.deinit();

    runtime.instance = try runtime.module.instantiate(.{});
    errdefer runtime.instance.deinit();

    return .{
        .runtime = runtime,
    };
}

pub fn deinit(self: *@This()) void {
    const gpa = self.runtime.engine.alloc;
    self.runtime.instance.deinit();
    self.runtime.module.deinit();
    self.runtime.engine.deinit();
    gpa.destroy(self.runtime);
}

pub fn alloc(self: *@This(), count: usize) !zcomplete.WasmSlice {
    const ptr = try self.runtime.instance.call(fn (i32) i32, "alloc", .{@as(i32, @intCast(count))});
    return self.deref(@as(usize, @intCast(ptr)), count);
}

pub fn run(self: *@This(), inbuf: zcomplete.WasmSlice) !*zcomplete.Response.Serialized {
    const ptr = try self.runtime.instance.call(fn (i32) i32, "run", .{@as(i32, @intCast(inbuf.ptr))});
    const slice = try self.deref(@as(usize, @intCast(ptr)), @sizeOf(zcomplete.Response.Serialized));
    return @ptrCast(@alignCast(slice.buf));
}

fn deref(self: *@This(), ptr: usize, len: usize) !zcomplete.WasmSlice {
    const memory = self.runtime.instance.memory() orelse return error.NoMemory;
    const mem_bytes = memory.slice();
    if (ptr + len > mem_bytes.len) return error.OutOfBoundsMemoryAccess;
    return .{
        .ptr = ptr,
        .buf = mem_bytes[ptr .. ptr + len],
    };
}
