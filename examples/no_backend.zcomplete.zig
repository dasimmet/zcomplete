const zcomplete = @import("zcomplete");
const std = @import("std");

pub fn run_zcomplete(a: *zcomplete.AutoComplete) void {
    a.respond(switch (a.args.len) {
        0 => .unknown,
        1 => .unknown,
        4 => .fillOptions(&.{
            "--help",
            "--version",
        }),
        else => .unknown,
    });
}
