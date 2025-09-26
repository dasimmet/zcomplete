const std = @import("std");
const zcomplete = @import("zcomplete");

pub fn main() !void {
    var gpa_alloc = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa_alloc.deinit();
    const gpa = gpa_alloc.allocator();

    const args = try std.process.argsAlloc(gpa);
    defer std.process.argsFree(gpa, args);

    if (std.process.getEnvVarOwned(gpa, "LDGEN_VERBOSE") catch |err| switch (err) {
        error.EnvironmentVariableNotFound => null,
        else => return err,
    }) |ldgen_env| {
        defer gpa.free(ldgen_env);
        if (std.mem.eql(u8, ldgen_env, "1")) {
            std.log.info("ldgen args: {f}", .{struct {
                args: []const []const u8,
                pub fn format(self: @This(), w: *std.Io.Writer) !void {
                    for (self.args) |arg| {
                        try w.writeAll(arg);
                        try w.writeAll(" ");
                    }
                }
            }{ .args = args }});
        }
    }

    if (args.len != 3) {
        std.log.err("usage: ldgen {{source}} {{target}}", .{});
        return error.NotEnoughArguments;
    }
    const source = args[1];
    const target = args[2];

    const input = try std.fs.cwd().readFileAlloc(gpa, source, std.math.maxInt(u32));
    defer gpa.free(input);

    const out_fd = try std.fs.cwd().createFile(target, .{});
    defer out_fd.close();
    var out_buf: [4096]u8 = undefined;
    var out_w = out_fd.writer(&out_buf);
    const out_writer = &out_w.interface;

    try out_writer.writeAll(script_header);
    try out_writer.writeAll(zcomplete.linker_section_name);
    try out_writer.writeAll(script_section_header);
    for (input, 0..) |byte, i| {
        if ((i % 4) == 0) {
            try out_writer.writeAll("\n        ");
        } else {
            try out_writer.writeAll(" ");
        }
        try out_writer.print("BYTE(0x{X:0>2})", .{byte});
    }
    try out_writer.writeAll(script_footer);
    try out_writer.flush();
}

const script_header =
    \\SECTIONS
    \\{
    \\    
;

const script_section_header = " (TYPE=SHT_NOTE) : {";

const script_footer =
    \\
    \\    }
    \\}
    \\INSERT AFTER .rodata;
    \\
;
