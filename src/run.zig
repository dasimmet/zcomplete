
const std = @import("std");
const debug = std.debug;
const magic = @import("magic.zig");

pub fn run(globals: anytype, cli:[]const []const u8) void {
    _ = globals;

    if (cli.len == 0) return;

    println("", .{});
    if (std.os.getenv("ZIG_CLAPCOMPLETE_COMMANDS")) |envvar| {
        println("ENVVAR {s}", .{envvar});
    }
    if (clapcomplete_find_magic(cli[0]) catch false) {
        debug.print("REGISTER:", .{});
    }
    println("CLI: ", .{});
    for (cli) |arg| {
        println("<{s}>", .{arg});
    }
}


fn println(comptime fmt: []const u8, args: anytype) void {
    debug.print("PRINT: "++fmt++"\n", args);
}

fn printjson(value: anytype, options: std.json.StringifyOptions) void {
    const writer = std.io.getStdOut();
    _ = writer.write("PRINT:JSON:") catch unreachable;
    std.json.stringify(value, options, writer.writer()) catch unreachable;
    _ = writer.write("\n") catch unreachable;
}

fn clapcomplete_find_magic(filename: []const u8) !bool {

    var file = try std.fs.cwd().openFile(filename, .{});
    defer file.close();

    var buf_reader = std.io.bufferedReader(file.reader());
    var in_stream = buf_reader.reader();

    var bufA: [2048]u8 = undefined;
    var bufActive: []u8 = &bufA;
    bufActive.len = 1024;
    var total: u64 = 0;
    while (total < magic.MAX_FIND_FILESIZE) {
        // const bufPassive = bufActive;
        if (bufActive.ptr == &bufA) {
            bufActive.ptr += bufActive.len;
        } else {
            bufActive.ptr -= bufActive.len;
        }
        var count = in_stream.read(bufActive) catch |err| return err;
        if (count==0) break;
        const magic_pos = std.mem.indexOf(u8, bufActive[0..count], magic.ARGCOMPLETE_MAGIC);
        if (magic_pos != null) {
            // printjson(.{.pos=magic_pos,.t="test"}, .{});
            println("POS: {d}", .{total + magic_pos.?});
            return true;
        }
        total += count;
    }
    println("NOTFOUND: {} {}", .{total, magic.MAX_FIND_FILESIZE});
    return false;
}