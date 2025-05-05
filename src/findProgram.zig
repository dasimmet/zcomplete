const std = @import("std");
const fs = std.fs;
const mem = std.mem;
const builtin = @import("builtin");

pub fn findProgram(gpa: std.mem.Allocator, names: []const []const u8, paths: []const []const u8, debug: bool) ![]const u8 {
    // arena for intermediate allocations
    var arena_alloc = std.heap.ArenaAllocator.init(gpa);
    defer arena_alloc.deinit();
    const arena = arena_alloc.allocator();

    for (names) |name| {
        if (fs.path.isAbsolute(name)) {
            return gpa.dupe(u8, name);
        }
        if (builtin.os.tag == .windows or std.mem.startsWith(u8, name, "." ++ fs.path.sep_str)) {
            if (fs.realpathAlloc(gpa, name)) |p| {
                return p;
            } else |err| switch (err) {
                error.OutOfMemory => @panic("OOM"),
                else => {
                    if (debug) std.log.warn("rp: {s} {}", .{ name, err });
                },
            }
        }
    }

    if (std.process.getEnvVarOwned(arena, "PATH") catch null) |PATH| {
        for (names) |name| {
            var it = mem.tokenizeScalar(u8, PATH, fs.path.delimiter);
            while (it.next()) |p| {
                return tryFindProgram(
                    gpa,
                    arena,
                    try std.fs.path.join(arena, &.{ p, name }),
                    debug,
                ) orelse continue;
            }
        }
    }
    for (names) |name| {
        for (paths) |p| {
            return tryFindProgram(
                gpa,
                arena,
                try fs.path.join(arena, &.{ p, name }),
                debug,
            ) orelse continue;
        }
    }
    return error.FileNotFound;
}

fn tryFindProgram(gpa: std.mem.Allocator, arena: std.mem.Allocator, full_path: []const u8, debug: bool) ?[]const u8 {
    if (debug) std.log.warn("fp: {s}", .{full_path});
    if (fs.realpathAlloc(gpa, full_path)) |p| {
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
