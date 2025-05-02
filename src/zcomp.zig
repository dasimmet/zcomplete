const std = @import("std");
const zcomplete = @import("zcomplete");
const zware = @import("zware");

const Store = zware.Store;
const Module = zware.Module;
const Instance = zware.Instance;

const Object = @import("elf/Object.zig");
const zelf = @import("elf/zelf.zig");

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

    const n = 39;
    var in = [1]u64{n};
    var out = [1]u64{0};

    try instance.invoke("fib", in[0..], out[0..], .{});

    const result: i32 = @bitCast(@as(u32, @truncate(out[0])));
    std.debug.print("fib({}) = {}\n", .{ n, result });
}
