const clap = @import("clap");
const std = @import("std");
const clapcomplete = @import("main.zig");

const debug = std.debug;
const io = std.io;

pub fn main() !void {
    // Example from zig-clap
    const params = comptime clap.parseParamsComptime(
        \\-h, --help             Display this help and exit.
        \\-n, --number <usize>   An option parameter, which takes a value.
        \\-s, --string <str>...  An option parameter which can be specified multiple times.
        \\<str>...
        \\
    );
    
    var diag = clap.Diagnostic{};
    var res = clap.parse(clap.Help, &params, clap.parsers.default, .{
        .diagnostic = &diag,
    }) catch |err| {
        diag.report(io.getStdErr().writer(), err) catch {};
        return err;
    };
    defer res.deinit();
    // call autocomplete to enable autocompletion
    clapcomplete.autocomplete(res);

    if (res.args.help)
        debug.print("--help\n", .{});
    if (res.args.number) |n|
        debug.print("--number = {}\n", .{n});
    for (res.args.string) |s|
        debug.print("--string = {s}\n", .{s});
    for (res.positionals) |pos| {
        debug.print("{s}\n", .{pos});
    }
}
