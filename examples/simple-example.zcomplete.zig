const zcomplete = @import("zcomplete");
const std = @import("std");

pub fn zcomp(a: *zcomplete.AutoComplete) !void {
    a.respond(switch (a.cur) {
        0 => .unknown,
        1 => .fillOptions(&.{
            "--help",
            "--version",
        }),
        else => .unknown,
    });
}
