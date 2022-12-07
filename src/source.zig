const std = @import("std");

const Shell = struct {
    name: []const u8,
    file: []const u8,
};

const shells = [_]Shell{
    .{.name="bash", .file=@embedFile("shell/bash")},
};

pub fn src(globals: anytype, cli:[]const []const u8) void {
    _ = globals;
    if (cli.len == 0) return;
    const writer = std.io.getStdOut();

    for (shells) |s| {
        if (std.mem.eql(u8, cli[0], s.name)) {
            _ = writer.write(s.file) catch null;
            _ = writer.write("\n") catch null;
        }
    }
}