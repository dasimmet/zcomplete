const std = @import("std");
const zcomplete = @import("zcomplete");
const zware = @import("zware");

const Store = zware.Store;
const Module = zware.Module;
const Instance = zware.Instance;

const Object = @import("elf/Object.zig");
const zelf = @import("elf/zelf.zig");

pub const std_options: std.Options = .{
    .log_level = .debug,
};

pub fn main() !void {
    var gpa_alloc = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa_alloc.deinit();
    const gpa = gpa_alloc.allocator();

    const args = try std.process.argsAlloc(gpa);
    defer std.process.argsFree(gpa, args);

    if (args.len < 2) return error.NotEnoughArguments;

    inline for (&.{
        .{ "extract", extract },
        .{ "bash", bash },
        .{ "complete", complete },
    }) |cmd| {
        if (std.mem.eql(u8, cmd[0], args[1])) {
            return cmd[1](gpa, args[2..]);
        }
    }

    return error.UnknownCommand;
}

pub fn extract(gpa: std.mem.Allocator, args: []const [:0]const u8) !void {
    if (args.len < 2) return error.NotEnoughArguments;

    const bytes = (try findElfbin(
        gpa,
        args[0],
        zcomplete.linker_section_name,
    )) orelse return error.ElfSectionNotFound;
    defer gpa.free(bytes);

    try std.fs.cwd().writeFile(.{
        .sub_path = args[1],
        .data = bytes,
    });
}

pub fn bash(gpa: std.mem.Allocator, args: []const [:0]const u8) !void {
    if (args.len < 2) return error.NotEnoughArguments;
    const cur = try std.fmt.parseInt(usize, args[0], 10);
    const cmd = args[1];

    const parsed = try getComletion(gpa, cmd, cur, args[2..]);
    defer parsed.deinit(gpa);

    const stdout = std.io.getStdOut().writer();
    switch (parsed) {
        .unknown => {},
        .fill_options => |opts| {
            for (opts) |opt| {
                try stdout.print("{s}\n", .{opt});
            }
        },
        else => {},
    }
}

pub fn complete(gpa: std.mem.Allocator, args: []const [:0]const u8) !void {
    if (args.len < 1) return error.NotEnoughArguments;
    const cmd = args[0];

    const parsed = try getComletion(gpa, cmd, args.len, args);
    defer parsed.deinit(gpa);

    std.debug.print("out: {any}\n", .{
        parsed,
    });

    switch (parsed) {
        .unknown => {},
        .fill_options => |opts| {
            std.log.err("opts: {s}", .{opts});
        },
        else => {},
    }
}

pub fn getComletion(gpa: std.mem.Allocator, cmd: []const u8, cur: usize, args: []const [:0]const u8) !zcomplete.Response.Options {
    const bytes = (try findElfbin(
        gpa,
        cmd,
        zcomplete.linker_section_name,
    )) orelse return error.ElfSectionNotFound;
    defer gpa.free(bytes);

    var store = Store.init(gpa);
    defer store.deinit();

    var module = Module.init(gpa, bytes);
    defer module.deinit();
    try module.decode();

    var instance = Instance.init(gpa, &store, module);
    try instance.instantiate();
    defer instance.deinit();
    const mem = try instance.getMemory(0);

    const size = zcomplete.Args.size(cmd, args);

    const wbuf = try wasm_alloc(mem, &instance, size);

    // std.debug.print("buf: {s}\n", .{
    //     wbuf.buf,
    // });

    _ = zcomplete.Args.serialize(wbuf.buf, cmd, cur, args);

    // std.debug.print("buf: {s} size: {d} args: {d}\n", .{
    //     wbuf.buf[@sizeOf(zcomplete.Args)..], wbuf.buf.len, args[1..].len,
    // });

    const serialized = try run(mem, &instance, wbuf);

    // std.debug.print("out: {any}\n", .{
    //     serialized,
    // });
    return serialized.parse(gpa);
}

pub fn findElfbin(gpa: std.mem.Allocator, file: []const u8, section_name: []const u8) !?[]u8 {
    var arena_alloc = std.heap.ArenaAllocator.init(gpa);
    defer arena_alloc.deinit();
    const arena = arena_alloc.allocator();

    const file_bytes = try std.fs.cwd().readFileAlloc(
        arena,
        file,
        std.math.maxInt(u32),
    );

    var object = Object{
        .arena = arena,
        .data = file_bytes,
        .path = file,
        .opts = .{},
    };
    object.parse() catch |err| switch (err) {
        error.InvalidMagic => @panic("not an ELF file - invalid magic bytes"),
        else => |e| return e,
    };

    for (object.shdrs.items) |shdr| {
        const sh_name = object.getShString(shdr.sh_name);
        if (shdr.sh_type == std.elf.SHT_NOTE and std.mem.eql(u8, sh_name, section_name)) {
            const ofs = shdr.sh_offset;
            // std.log.info("here: {s} 0x{x} 0x{x} 0x{x} 0x{x} 0x{x}", .{
            //     sh_name,
            //     ofs,
            //     shdr.sh_addr,
            //     shdr.sh_offset,
            //     shdr.sh_size,
            //     shdr.sh_entsize,
            // });
            return try gpa.dupe(u8, file_bytes[ofs .. ofs + shdr.sh_size]);
        }
    }
    return null;
}

pub const WasmSlice = struct {
    ptr: usize, // pointer in wasm memory space
    buf: []u8, // host slice
};

pub fn wasm_alloc(mem: *zware.Memory, instance: *zware.Instance, count: usize) !WasmSlice {
    var in: [1]u64 = @splat(count);
    var out: [1]u64 = @splat(0);
    try instance.invoke("alloc", &in, &out, .{});
    return deref(mem, out[0], count);
}

pub fn run(mem: *zware.Memory, instance: *zware.Instance, inbuf: WasmSlice) !*zcomplete.Response.Serialized {
    var in: [1]u64 = @splat(inbuf.ptr);
    var out: [1]u64 = @splat(0);
    try instance.invoke("run", &in, &out, .{});
    const res = try deref(mem, out[0], @sizeOf(zcomplete.Response.Serialized));
    return @alignCast(@ptrCast(res.buf));
}

pub fn deref(mem: *zware.Memory, ptr: usize, len: usize) !WasmSlice {
    return .{
        .ptr = ptr,
        .buf = mem.memory()[ptr .. ptr + len],
    };
}
