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

    if (args.len < 3) return error.NotEnoughArguments;

    const file_bytes = try std.fs.cwd().readFileAlloc(
        gpa,
        args[1],
        std.math.maxInt(u32),
    );
    defer gpa.free(file_bytes);

    var arena_alloc = std.heap.ArenaAllocator.init(gpa);
    defer arena_alloc.deinit();
    const arena = arena_alloc.allocator();

    var object = Object{
        .arena = arena,
        .data = file_bytes,
        .path = args[1],
        .opts = .{},
    };
    object.parse() catch |err| switch (err) {
        error.InvalidMagic => @panic("not an ELF file - invalid magic bytes"),
        else => |e| return e,
    };

    var bytes: []const u8 = "";
    for (object.shdrs.items) |shdr| {
        const sh_name = object.getShString(shdr.sh_name);
        if (std.mem.eql(u8, sh_name, ".note.zcomplete")) {
            const ofs = shdr.sh_offset;
            std.log.info("here: {s} 0x{x} 0x{x} 0x{x} 0x{x}", .{
                sh_name,
                ofs,
                shdr.sh_addr,
                shdr.sh_offset,
                shdr.sh_size,
            });
            bytes = file_bytes[ofs .. ofs + shdr.sh_size];
            // std.log.info("found: {s}", .{bytes});

            var out_fd = try std.fs.cwd().createFile(args[2], .{});
            defer out_fd.close();
            try out_fd.writeAll(bytes);

            break;
        }
    }
    if (bytes.len == 0) return error.ElfSectionNotFound;

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
    for (args[3..]) |arg| {
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
    for (args[3..]) |arg| {
        @memcpy(wbuf.buf[pos .. pos + arg.len], arg);
        pos += arg.len;
        wbuf.buf[pos] = 0;
        pos += 1;
    }

    for (args[3..]) |arg| {
        size += arg.len + 1;
    }

    std.debug.print("buf: {s} size: {d} args: {d}\n", .{
        wbuf.buf[@sizeOf(zcomplete.Args)..], wbuf.buf.len, args[3..].len,
    });

    const serialized = try run(mem, &instance, wbuf);

    std.debug.print("out: {any}\n", .{
        serialized,
    });
    const parsed = serialized.parse(gpa);
    std.debug.print("out: {any}\n", .{
        parsed,
    });

    switch (parsed.*) {
        .unknown => {},
        .fill_options => |opts| {
            std.log.err("opts: {s}", .{opts});
        },
        else => {},
    }
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
