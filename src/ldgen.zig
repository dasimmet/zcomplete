const std = @import("std");
const zcomplete = @import("zcomplete");

pub fn main() !void {
    var gpa_alloc = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa_alloc.deinit();
    const gpa = gpa_alloc.allocator();

    const args = try std.process.argsAlloc(gpa);
    defer std.process.argsFree(gpa, args);

    std.log.info("args: {s}", .{args});

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

    try out_fd.writeAll(script_header);
    try out_fd.writeAll(zcomplete.linker_section_name);
    try out_fd.writeAll(script_section_header);
    for (input, 0..) |byte, i| {
        if ((i % 4) == 0) {
            try out_fd.writeAll("\n        ");
        } else {
            try out_fd.writeAll(" ");
        }
        try out_fd.writer().print("BYTE(0x{X:0>2})", .{byte});
    }
    try out_fd.writeAll(script_footer);
}

const script_header =
    \\SECTIONS
    \\{
    \\    
;

const script_section_header = " : {";

const script_footer =
    \\
    \\    }
    \\}
    \\INSERT AFTER .rodata;
    \\
;
