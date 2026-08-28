//! CLI runner for zcomplete shell auto-completion.
//! Handles command line parsing, ELF .zcomplete section extraction,
//! WebAssembly instantiation via the configured backend, and output formatting for Bash.

const std = @import("std");
const zcomplete = @import("zcomplete");
const known_folders = @import("known-folders");
const WasmBackend = @import("wasmbackend");
const elf = struct {
    pub const main = @import("elf/main.zig");
    pub const Archive = @import("elf/Archive.zig");
    pub const Object = @import("elf/Object.zig");
};

const findProgram = @import("findProgram.zig").findProgram;

const usage =
    \\zcomp {--help|eval|bash|extract|complete}
    \\
    \\
;

pub const std_options: std.Options = .{
    .log_level = .debug,
};

const zcomp_spec = @import("zcomp.zcomplete.zig");
const Command = zcomp_spec.Command;

const CommandFn = struct {
    pub const Type = *const fn (std.process.Init, []const [:0]const u8) anyerror!void;
    pub fn function(self: Command) Type {
        return switch (self) {
            .eval => eval,
            .extract => extract,
            .bash => bash,
            .complete => complete,
            .help => help,
            .@"--help" => help,
            .@"-h" => help,
            .@"-?" => help,
            .@"--version" => version,
            .@"-v" => version,
        };
    }
};

const embedded_bin = @embedFile("zcomplete_bin");
const prog: [embedded_bin.len]u8 linksection(zcomplete.linker_section_name) = embedded_bin[0..embedded_bin.len].*;

pub fn main(init: std.process.Init) !void {
    _ = prog;
    const args = try init.minimal.args.toSlice(init.arena.allocator());

    if (args.len < 2) {
        return help(init, &.{});
    }

    if (Command.parse(args[1])) |cmd| {
        return CommandFn.function(cmd)(init, args[2..]);
    }

    return error.UnknownCommand;
}

fn help(init: std.process.Init, args: []const [:0]const u8) !void {
    _ = args;
    const stdout_fd = std.Io.File.stdout();
    try stdout_fd.writeStreamingAll(init.io, usage);
}

fn version(init: std.process.Init, args: []const [:0]const u8) !void {
    _ = args;
    const stdout_fd = std.Io.File.stdout();
    try stdout_fd.writeStreamingAll(init.io, "zcomp 0.1.0\n");
}

fn eval(init: std.process.Init, args: []const [:0]const u8) !void {
    _ = args;
    const stdout_fd = std.Io.File.stdout();
    try stdout_fd.writeStreamingAll(init.io, @embedFile("share/zcomplete.bash"));
}

fn extract(init: std.process.Init, args: []const [:0]const u8) !void {
    if (args.len < 2) return error.NotEnoughArguments;
    const gpa = init.gpa;
    const io = init.io;

    const bytes = (try findElfbinSection(
        io,
        gpa,
        args[0],
        zcomplete.linker_section_name,
    )) orelse return error.ElfSectionNotFound;
    defer gpa.free(bytes);

    try std.Io.Dir.cwd().writeFile(io, .{
        .sub_path = args[1],
        .data = bytes,
    });
}

fn matchPattern(name: []const u8, pattern: []const u8) bool {
    if (pattern.len == 0) return true;
    if (std.mem.startsWith(u8, pattern, "*")) {
        return std.mem.endsWith(u8, name, pattern[1..]);
    }
    if (std.mem.startsWith(u8, pattern, ".")) {
        return std.mem.endsWith(u8, name, pattern);
    }
    return std.mem.endsWith(u8, name, pattern) or std.mem.indexOf(u8, name, pattern) != null;
}

fn completePaths(
    io: std.Io,
    gpa: std.mem.Allocator,
    stdout: *std.Io.Writer,
    cur_arg: []const u8,
    kind: enum { files, directories, paths },
    pattern: ?[]const u8,
) !void {
    const cwd = std.Io.Dir.cwd();
    var dir_path: []const u8 = "";
    var prefix: []const u8 = cur_arg;

    if (std.mem.lastIndexOfScalar(u8, cur_arg, std.fs.path.sep)) |sep_idx| {
        dir_path = cur_arg[0 .. sep_idx + 1];
        prefix = cur_arg[sep_idx + 1 ..];
    }

    const trimmed_dir = std.mem.trimEnd(u8, dir_path, &.{std.fs.path.sep});
    const open_path = if (trimmed_dir.len == 0) (if (std.fs.path.isAbsolute(dir_path)) "/" else ".") else trimmed_dir;
    var dir = if (std.fs.path.isAbsolute(open_path))
        std.Io.Dir.openDirAbsolute(io, open_path, .{ .iterate = true }) catch return
    else
        cwd.openDir(io, open_path, .{ .iterate = true }) catch return;
    defer dir.close(io);

    var iter = dir.iterate();
    while (try iter.next(io)) |entry| {
        if (entry.name.len > 0 and entry.name[0] == '.' and (prefix.len == 0 or prefix[0] != '.')) {
            continue;
        }

        if (!std.mem.startsWith(u8, entry.name, prefix)) continue;

        const is_dir = entry.kind == .directory;
        if (kind == .directories and !is_dir) continue;
        if (!is_dir and pattern != null and !matchPattern(entry.name, pattern.?)) continue;

        var candidate_buf = std.ArrayListUnmanaged(u8).empty;
        defer candidate_buf.deinit(gpa);

        try candidate_buf.appendSlice(gpa, dir_path);
        try candidate_buf.appendSlice(gpa, entry.name);
        if (is_dir) {
            try candidate_buf.append(gpa, std.fs.path.sep);
        }

        const candidate = candidate_buf.items;
        var has_space = false;
        for (candidate) |c| {
            if (std.ascii.isWhitespace(c)) {
                has_space = true;
                break;
            }
        }

        if (has_space) {
            try stdout.print("\"{s}\"\n", .{candidate});
        } else {
            try stdout.print("{s}\n", .{candidate});
        }
    }
}

fn bash(init: std.process.Init, args: []const [:0]const u8) !void {
    if (args.len < 2) return error.NotEnoughArguments;
    const gpa = init.gpa;
    const io = init.io;

    const cur = try std.fmt.parseInt(usize, args[0], 10);
    const cmd = args[1];

    const stderr_fd = std.Io.File.stderr();
    var stderr_buf: [4096]u8 = undefined;
    var stderr_writer = stderr_fd.writer(io, &stderr_buf);
    const stderr = &stderr_writer.interface;

    const stdout_fd = std.Io.File.stdout();
    var stdout_buf: [4096]u8 = undefined;
    var stdout_writer = stdout_fd.writer(io, &stdout_buf);
    const stdout = &stdout_writer.interface;

    const argv = args[2..];

    const maybe_log_fd = openLog(init) catch null;
    defer if (maybe_log_fd) |lfd| lfd.close(io);
    var log_buf: [4096]u8 = undefined;
    var log_w = if (maybe_log_fd) |lfd| lfd.writer(io, &log_buf) else null;
    const log: ?*std.Io.Writer = if (log_w) |*lw| &lw.interface else null;
    if (log) |l| l.print("completing: {s} {f}\n", .{ cmd, std.json.fmt(argv, .{}) }) catch {};

    const parsed = getCompletion(
        init,
        cmd,
        cur,
        argv,
        false,
    ) catch |err| switch (err) {
        else => {
            if (log) |l| l.print("getCompletion error: {}\n", .{err}) catch {};
            return;
        },
    };
    defer parsed.deinit(gpa);

    if (log) |l| l.print("response: {any}\n", .{parsed}) catch {};

    const cur_arg = if (cur == 0 or argv.len < cur) "" else argv[cur - 1];

    switch (parsed.options) {
        .unknown => {},
        .fill_options => |opts| {
            if (log) |l| l.print("opts: {f}\n", .{std.json.fmt(opts, .{})}) catch {};
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
        .files => |f| {
            try completePaths(io, gpa, stdout, cur_arg, .files, f.pattern);
        },
        .directories => |d| {
            try completePaths(io, gpa, stdout, cur_arg, .directories, d.pattern);
        },
        .paths => |p| {
            try completePaths(io, gpa, stdout, cur_arg, .paths, p.pattern);
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
    try stdout.flush();
    try stderr.flush();
}

fn complete(init: std.process.Init, args: []const [:0]const u8) !void {
    if (args.len < 1) return error.NotEnoughArguments;
    const gpa = init.gpa;

    const cmd = args[0];
    const cur = @max(1, args.len - 1);

    std.debug.print("cmd: {s} cur: {d} args: {f}\n", .{ cmd, cur, std.json.fmt(args[1..], .{}) });

    const parsed = try getCompletion(
        init,
        cmd,
        cur,
        args[1..],
        true,
    );
    defer parsed.deinit(gpa);

    std.debug.print("out: {any}\n", .{
        parsed,
    });

    const stderr_fd = std.Io.File.stderr();
    var stderr_buf: [4096]u8 = undefined;
    var stderr_writer = stderr_fd.writer(init.io, &stderr_buf);
    const stderr = &stderr_writer.interface;

    switch (parsed.options) {
        .fill_options => |opts| {
            try stderr.print("opt: {f}\n", .{std.json.fmt(opts, .{})});
            try stderr.flush();
        },
        .files => |f| {
            if (f.pattern) |p| {
                try stderr.print("opt: [files matching '{s}']\n", .{p});
            } else {
                try stderr.print("opt: [files]\n", .{});
            }
            try stderr.flush();
        },
        .directories => |d| {
            if (d.pattern) |p| {
                try stderr.print("opt: [directories matching '{s}']\n", .{p});
            } else {
                try stderr.print("opt: [directories]\n", .{});
            }
            try stderr.flush();
        },
        .paths => |p| {
            if (p.pattern) |pat| {
                try stderr.print("opt: [paths matching '{s}']\n", .{pat});
            } else {
                try stderr.print("opt: [paths]\n", .{});
            }
            try stderr.flush();
        },
        .zcomperror => |msg| {
            try stderr.print("\nzcomp error:\n{s}\n", .{msg});
            try stderr.flush();
            std.process.exit(1);
        },
        else => {},
    }
}

fn getCompletion(
    init: std.process.Init,
    raw_cmd: []const u8,
    cur: usize,
    args: []const [:0]const u8,
    debug: bool,
) !zcomplete.Response {
    const gpa = init.gpa;
    const cmd = try findProgram(init, &.{raw_cmd}, &.{}, debug);
    defer gpa.free(cmd);
    const bytes = (try findElfbinSection(
        init.io,
        gpa,
        cmd,
        zcomplete.linker_section_name,
    )) orelse return error.ElfSectionNotFound;
    defer gpa.free(bytes);

    var wasm = try WasmBackend.init(gpa, bytes);
    defer wasm.deinit();

    const size = zcomplete.Args.size(cmd, args);

    const wbuf = try wasm.alloc(size);

    // std.debug.print("buf: {s}\n", .{
    //     wbuf.buf,
    // });

    _ = zcomplete.Args.serialize(wbuf.buf, cmd, cur, args);

    // std.debug.print("buf: {s} size: {d} args: {d}\n", .{
    //     wbuf.buf[@sizeOf(zcomplete.Args)..], wbuf.buf.len, args[1..].len,
    // });

    const serialized = try wasm.run(wbuf);

    // std.debug.print("out: {any}\n", .{
    //     serialized,
    // });
    return serialized.parse(gpa);
}

///reads a file and returns elf section. caller owns memory.
fn findElfbinSection(io: std.Io, gpa: std.mem.Allocator, file: []const u8, section_name: []const u8) !?[]u8 {
    var arena_alloc = std.heap.ArenaAllocator.init(gpa);
    defer arena_alloc.deinit();
    const arena = arena_alloc.allocator();

    const file_bytes = try std.Io.Dir.cwd().readFileAlloc(
        io,
        file,
        arena,
        .unlimited,
    );

    var object = elf.Object{
        .arena = arena,
        .data = file_bytes,
        .path = file,
        .opts = .{},
    };
    try object.parse();

    for (object.shdrs.items) |shdr| {
        const sh_name = object.getShString(shdr.sh_name);
        const ofs = shdr.sh_offset;
        // std.log.info("here: {s} 0x{x} 0x{x} 0x{x} 0x{x} 0x{x}", .{
        //     sh_name,
        //     ofs,
        //     shdr.sh_addr,
        //     shdr.sh_offset,
        //     shdr.sh_size,
        //     shdr.sh_entsize,
        // });
        if (std.mem.eql(u8, sh_name, section_name)) {
            return try gpa.dupe(u8, file_bytes[ofs .. ofs + shdr.sh_size]);
        }
    }
    return null;
}

fn openLog(init: std.process.Init) !std.Io.File {
    const runtime_dir: ?std.Io.Dir = try known_folders.open(
        init.io,
        init.arena.allocator(),
        init.environ_map,
        .cache,
        .{},
    );

    if (runtime_dir) |dir| {
        dir.createDirPath(init.io, "zcomp") catch |err| switch (err) {
            error.PathAlreadyExists => {},
            else => return err,
        };
        return dir.openFile(
            init.io,
            "zcomp/zcomp.log",
            .{ .mode = .write_only },
        ) catch |err| switch (err) {
            error.FileNotFound => {
                return dir.createFile(init.io, "zcomp/zcomp.log", .{
                    .truncate = false,
                });
            },
            else => return err,
        };
    }
    return error.NoRuntimePathAvailable;
}
