const std = @import("std");
const exit = std.process.exit;

pub const std_options = std.Options{
    .log_level = .debug,
};
pub const help_str = "usage: simple-example {{--help|--version}}";
pub fn main() !void {
    var arena_alloc = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    const arena = arena_alloc.allocator();
    defer arena_alloc.deinit();

    const args = try std.process.argsAlloc(arena);
    defer std.process.argsFree(arena, args);
    if (args.len < 2) {
        std.log.err(help_str, .{});
        exit(1);
    }

    if (std.mem.eql(u8, args[1], "--help")) {
        std.log.info(help_str, .{});
        exit(0);
    }

    if (std.mem.eql(u8, args[1], "--version")) {
        const stdout_fd = std.fs.File.stdout();
        var stdout_buf: [4096]u8 = undefined;
        var stdout_writer = stdout_fd.writer(&stdout_buf);
        const stdout = &stdout_writer.interface;
        try stdout.writeAll("1.0.0\n");
        try stdout.flush();
        exit(0);
    }
    std.log.err(help_str, .{});
    exit(1);
}
