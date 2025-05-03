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

pub fn complete(gpa: std.mem.Allocator, args: []const [:0]const u8) !void {
    if (args.len < 1) return error.NotEnoughArguments;

    const bytes = (try findElfbin(
        gpa,
        args[0],
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

    var size: usize = @sizeOf(zcomplete.Args);
    for (args[1..]) |arg| {
        size += arg.len + 1;
    }

    const wbuf = try alloc(mem, &instance, size);

    std.debug.print("buf: {s}\n", .{
        wbuf.buf,
    });

    const autocomp: *zcomplete.Args = @alignCast(@ptrCast(wbuf.buf.ptr));
    autocomp.* = .{
        .offset = @intCast(@sizeOf(zcomplete.Args)),
        .len = @as(i32, @intCast(size)) - @sizeOf(zcomplete.Args),
    };

    var pos: usize = @sizeOf(zcomplete.Args);
    for (args[1..]) |arg| {
        @memcpy(wbuf.buf[pos .. pos + arg.len], arg);
        pos += arg.len;
        wbuf.buf[pos] = 0;
        pos += 1;
    }

    for (args[1..]) |arg| {
        size += arg.len + 1;
    }

    std.debug.print("buf: {s} size: {d} args: {d}\n", .{
        wbuf.buf[@sizeOf(zcomplete.Args)..], wbuf.buf.len, args[1..].len,
    });

    const serialized = try run(mem, &instance, wbuf);

    std.debug.print("out: {any}\n", .{
        serialized,
    });

    const parsed = try serialized.parse(gpa);
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

pub fn findElfbin(gpa: std.mem.Allocator, file: [:0]const u8, section_name: []const u8) !?[]u8 {
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
        if (std.mem.eql(u8, sh_name, section_name)) {
            const ofs = shdr.sh_offset;
            std.log.info("here: {s} 0x{x} 0x{x} 0x{x} 0x{x}", .{
                sh_name,
                ofs,
                shdr.sh_addr,
                shdr.sh_offset,
                shdr.sh_size,
            });
            return try gpa.dupe(u8, file_bytes[ofs .. ofs + shdr.sh_size]);
        }
    }
    return null;
}

pub const Slice = struct {
    ptr: usize,
    buf: []u8,
};

pub fn alloc(mem: *zware.Memory, instance: *zware.Instance, count: usize) !Slice {
    var in: [1]u64 = @splat(count);
    var out: [1]u64 = @splat(0);
    try instance.invoke("alloc", &in, &out, .{});
    return deref(mem, out[0], count);
}

pub fn run(mem: *zware.Memory, instance: *zware.Instance, inbuf: Slice) !*zcomplete.Response.Serialized {
    var in: [1]u64 = @splat(inbuf.ptr);
    var out: [1]u64 = @splat(0);
    try instance.invoke("run", &in, &out, .{});
    const res = try deref(mem, out[0], @sizeOf(zcomplete.Response.Serialized));
    return @alignCast(@ptrCast(res.buf));
}

pub fn deref(mem: *zware.Memory, ptr: usize, len: usize) !Slice {
    return .{
        .ptr = ptr,
        .buf = mem.memory()[ptr .. ptr + len],
    };
}
