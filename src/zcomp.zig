const std = @import("std");
const zcomplete = @import("zcomplete");
const zware = @import("zware");

const Store = zware.Store;
const Module = zware.Module;
const Instance = zware.Instance;

const Object = @import("elf/Object.zig");
const findProgram = @import("findProgram.zig").findProgram;

pub const usage =
    \\zcomp {--help|eval|bash|complete}
    \\
    \\
;

pub const std_options: std.Options = .{
    .log_level = .debug,
};

pub const Commands = &.{
    .{ "eval", eval },
    .{ "extract", extract },
    .{ "bash", bash },
    .{ "complete", complete },
    .{ "-h", help },
    .{ "-?", help },
    .{ "--help", help },
};

pub fn main() !void {
    var gpa_alloc = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa_alloc.deinit();
    const gpa = gpa_alloc.allocator();

    const args = try std.process.argsAlloc(gpa);
    defer std.process.argsFree(gpa, args);

    if (args.len < 2) {
        return help(gpa, &.{});
    }

    inline for (Commands) |cmd| {
        if (std.mem.eql(u8, cmd[0], args[1])) {
            return cmd[1](gpa, args[2..]);
        }
    }

    return error.UnknownCommand;
}

pub fn help(gpa: std.mem.Allocator, args: []const [:0]const u8) !void {
    _ = gpa;
    _ = args;
    const stdout = std.io.getStdOut();
    try stdout.writeAll(usage);
}

pub fn eval(gpa: std.mem.Allocator, args: []const [:0]const u8) !void {
    _ = gpa;
    _ = args;
    const stdout = std.io.getStdOut();
    try stdout.writeAll(@embedFile("share/zcomplete.bash"));
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

    const stderr = std.io.getStdErr().writer();

    const argv = args[2..];
    const parsed = getCompletion(gpa, cmd, cur, argv) catch |err| switch (err) {
        else => {
            try stderr.print("error: {}", .{err});
            return;
        },
    };
    defer parsed.deinit(gpa);

    const stdout = std.io.getStdOut().writer();
    const cur_arg = if (cur == 0 or argv.len < cur) "" else argv[cur - 1];

    switch (parsed.options) {
        .unknown => {},
        .fill_options => |opts| {
            if (cur > 0) {
                outer: for (opts) |opt| {
                    if (std.mem.startsWith(u8, opt, cur_arg)) {
                        for (opt) |c| {
                            if (std.ascii.isWhitespace(c)) {
                                try stdout.print("\"{s}\"\n", .{opt});
                                continue :outer;
                            }
                        }
                        try stdout.print("{s}\n", .{opt});
                    }
                }
            }
        },
        .int_range => |range| {
            for (@as(usize, @intCast(range.min orelse 0))..@as(usize, @intCast(range.max orelse 10))) |i| {
                var i_buf: [64]u8 = undefined;
                const i_str = try std.fmt.bufPrint(&i_buf, "{d}", .{i});
                if (std.mem.startsWith(u8, i_str, cur_arg)) {
                    try stdout.print("{d}\n", .{i});
                }
            }
        },
        .zcomperror => |msg| {
            try stderr.print("\nzcomp error:\n{s}\n", .{msg});
            std.process.exit(1);
        },
        else => @panic("response not implemented!"),
    }
}

pub fn complete(gpa: std.mem.Allocator, args: []const [:0]const u8) !void {
    if (args.len < 1) return error.NotEnoughArguments;
    const cmd = args[0];
    const cur = @max(1, args.len - 1);

    std.debug.print("cmd: {s} cur: {d} args: {s}\n", .{ cmd, cur, args[1..] });

    const parsed = try getCompletion(gpa, cmd, cur, args[1..]);
    defer parsed.deinit(gpa);

    std.debug.print("out: {any}\n", .{
        parsed,
    });

    const stderr = std.io.getStdErr().writer();

    switch (parsed.options) {
        .fill_options => |opts| {
            try stderr.print("opt: {s}\n", .{opts});
        },
        .zcomperror => |msg| {
            try stderr.print("\nzcomp error:\n{s}\n", .{msg});
            std.process.exit(1);
        },
        else => {},
    }
}

pub fn getCompletion(gpa: std.mem.Allocator, raw_cmd: []const u8, cur: usize, args: []const [:0]const u8) !zcomplete.Response {
    const cmd = try findProgram(gpa, &.{raw_cmd}, &.{});
    defer gpa.free(cmd);
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

    // var has_alloc = false;
    // var has_run = false;
    // for (instance.module.exports.itemsSlice()) |it| {
    //     if (it.name == )
    // }

    const mem = try instance.getMemory(0);

    const size = zcomplete.Args.size(cmd, args);

    const wbuf = try Wasm.alloc(mem, &instance, size);

    // std.debug.print("buf: {s}\n", .{
    //     wbuf.buf,
    // });

    _ = zcomplete.Args.serialize(wbuf.buf, cmd, cur, args);

    // std.debug.print("buf: {s} size: {d} args: {d}\n", .{
    //     wbuf.buf[@sizeOf(zcomplete.Args)..], wbuf.buf.len, args[1..].len,
    // });

    const serialized = try Wasm.run(mem, &instance, wbuf);

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

pub const Wasm = struct {
    pub const Slice = struct {
        ptr: usize, // pointer in wasm memory space
        buf: []u8, // host slice
    };

    pub fn alloc(mem: *zware.Memory, instance: *zware.Instance, count: usize) !Slice {
        var in: [1]u64 = @splat(count);
        var out: [1]u64 = @splat(0);
        try instance.invoke("alloc", &in, &out, .{});
        return deref(mem, out[0], count);
    }

    pub fn run(mem: *zware.Memory, instance: *zware.Instance, inbuf: Slice) !*zcomplete.Response.Serialized {
        var in: [1]u64 = @splat(inbuf.ptr);
        var out: [1]u64 = undefined;
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
};
