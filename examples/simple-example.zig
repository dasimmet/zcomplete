const std = @import("std");
const zcomplete = @import("zcomplete");
const exit = std.process.exit;

pub const std_options = std.Options{
    .log_level = .debug,
};
pub const help_str = "usage: simple-example {{--help|--version}}";

const embedded_bin = @embedFile("zcomplete_bin");
const prog: [embedded_bin.len]u8 linksection(zcomplete.linker_section_name) = embedded_bin[0..embedded_bin.len].*;

pub fn main(init: std.process.Init) !void {
    _ = prog;
    const args = try init.minimal.args.toSlice(init.arena.allocator());

    if (args.len < 2) {
        std.log.err(help_str, .{});
        exit(1);
    }

    if (std.mem.eql(u8, args[1], "--help")) {
        std.log.info(help_str, .{});
        exit(0);
    }

    if (std.mem.eql(u8, args[1], "--version")) {
        const stdout_fd = std.Io.File.stdout();
        var stdout_buf: [4096]u8 = undefined;
        var stdout_writer = stdout_fd.writer(init.io, &stdout_buf);
        const stdout = &stdout_writer.interface;
        try stdout.writeAll("1.0.0\n");
        try stdout.flush();
        exit(0);
    }
    std.log.err(help_str, .{});
    exit(1);
}
