const zcomplete = @import("zcomplete");
const std = @import("std");

pub fn zcomp(a: *zcomplete.AutoComplete) !void {
    a.respond(switch (a.args.len) {
        0 => .unknown,
        1 => .unknown,
        2, 3, 4, 5, 6, 7 => .fillOptions(&.{
            "--help",
            "--version",
        }),
        else => .unknown,
    });
}
