//! Executable path resolver.
//! Searches for binaries by name or path across system PATH and custom search directories.

const std = @import("std");
const fs = std.fs;
const mem = std.mem;
const builtin = @import("builtin");

pub fn findProgram(init: std.process.Init, names: []const []const u8, paths: []const []const u8, debug: bool) ![:0]const u8 {
    const gpa = init.gpa;
    const io = init.io;
    const env_map = init.environ_map;
    // arena for intermediate allocations
    var arena_alloc = std.heap.ArenaAllocator.init(gpa);
    defer arena_alloc.deinit();
    const arena = arena_alloc.allocator();

    const cwd = std.Io.Dir.cwd();

    for (names) |name| {
        if (fs.path.isAbsolute(name)) {
            return gpa.dupeZ(u8, name);
        }
        if (builtin.os.tag == .windows or std.mem.startsWith(u8, name, "." ++ fs.path.sep_str)) {
            if (cwd.realPathFileAlloc(io, name, gpa)) |p| {
                return p;
            } else |err| switch (err) {
                error.OutOfMemory => @panic("OOM"),
                else => {
                    if (debug) std.log.warn("realpath error: {s} {}", .{ name, err });
                },
            }
        }
    }

    if (env_map.get("PATH")) |PATH| {
        for (names) |name| {
            var it = mem.tokenizeScalar(u8, PATH, fs.path.delimiter);
            while (it.next()) |p| {
                return tryFindProgram(
                    io,
                    gpa,
                    arena,
                    cwd,
                    try std.fs.path.join(arena, &.{ p, name }),
                    debug,
                ) orelse continue;
            }
        }
    }
    for (names) |name| {
        for (paths) |p| {
            return tryFindProgram(
                io,
                gpa,
                arena,
                cwd,
                try fs.path.join(arena, &.{ p, name }),
                debug,
            ) orelse continue;
        }
    }
    return error.FileNotFound;
}

fn tryFindProgram(
    io: std.Io,
    gpa: std.mem.Allocator,
    arena: std.mem.Allocator,
    cwd: std.Io.Dir,
    full_path: []const u8,
    debug: bool,
) ?[:0]const u8 {
    if (debug) std.log.warn("fp: {s}", .{full_path});
    if (cwd.realPathFileAlloc(io, full_path, gpa)) |p| {
        return p;
    } else |err| switch (err) {
        error.OutOfMemory => @panic("OOM"),
        else => {},
    }

    if (builtin.os.tag == .windows) {
        if (try std.process.getEnvVarOwned(arena, "PATHEXT") catch null) |PATHEXT| {
            var it = mem.tokenizeScalar(u8, PATHEXT, fs.path.delimiter);

            while (it.next()) |ext| {
                if (!supportedWindowsProgramExtension(ext)) continue;

                return fs.realpathAlloc(gpa, std.fmt.allocPrint(
                    arena,
                    "{s}{s}",
                    .{ full_path, ext },
                ) catch @panic("OOM")) catch |err| switch (err) {
                    error.OutOfMemory => @panic("OOM"),
                    else => continue,
                };
            }
        }
    }

    return null;
}

fn supportedWindowsProgramExtension(ext: []const u8) bool {
    inline for (@typeInfo(std.process.Child.WindowsExtension).@"enum".fields) |field| {
        if (std.ascii.eqlIgnoreCase(ext, "." ++ field.name)) return true;
    }
    return false;
}
