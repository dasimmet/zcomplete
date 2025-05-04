const zcomplete = @import("zcomplete");
const streql = zcomplete.streql;
const std = @import("std");
// const root = @import("zcomp.zig");

pub fn zcomp(a: *zcomplete.AutoComplete) !void {
    a.name("zcomp");
    switch (a.cur) {
        0 => a.respond(.unknown),
        1 => a.respond(.fillOptions(&.{
            "extract",
            "bash",
            "complete",
            "eval",
            "--help",
        })),
        2 => {
            const cmd = a.args[1];
            if (streql(cmd, "extract")) {
                a.respond(.unknown);
            } else if (streql(cmd, "eval")) {
                a.respond(.unknown);
            } else if (streql(cmd, "--help")) {
                a.respond(.unknown);
            } else if (streql(cmd, "bash")) {
                a.respond(.intRangeOptions(
                    1,
                    10,
                ));
            } else {
                a.panic("UNKNOWN SUBCOMMAND?", .{});
            }
        },
        else => a.respond(.unknown),
    }
}
