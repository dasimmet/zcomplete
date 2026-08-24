const std = @import("std");
const wasmz = @import("wasmz");
const zcomplete = @import("zcomplete");

const Runtime = struct {
    engine: wasmz.Engine,
    module: wasmz.Module,
    store: wasmz.Store,
    instance: wasmz.Instance,
};

runtime: *Runtime,

pub fn init(gpa: std.mem.Allocator, bytes: []const u8) !@This() {
    const runtime = try gpa.create(Runtime);
    runtime.engine = try wasmz.Engine.init(gpa, .{});
    runtime.module = try wasmz.Module.compile(runtime.engine, bytes);
    runtime.store = try wasmz.Store.init(gpa, runtime.engine, std.Io.Threaded.global_single_threaded.io());
    runtime.instance = try wasmz.Instance.init(&runtime.store, runtime.module, .empty);

    return .{
        .runtime = runtime,
    };
}

pub fn deinit(self: *@This()) void {
    const gpa = self.runtime.store.allocator;
    self.runtime.instance.deinit();
    self.runtime.store.deinit();
    self.runtime.module.deinit();
    self.runtime.engine.deinit();
    gpa.destroy(self.runtime);
}

// var store = try wasmz.Store.init(allocator, engine);
// defer store.deinit();

// const result = try instance.call("add", &.{ .{ .i32 = 1 }, .{ .i32 = 2 } });
