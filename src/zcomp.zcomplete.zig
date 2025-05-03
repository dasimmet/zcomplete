const zcomplete = @import("zcomplete");
const std = @import("std");

pub fn zcomp(a: *zcomplete.AutoComplete) !void {
    switch (a.cur) {
        0 => a.respond(.unknown),
        1 => a.respond(.fillOptions(&.{
            "extract",
            "bash",
            "complete",
        })),
        2 => {
            if (std.mem.eql(u8, a.args[1], "extract")) {
                a.respond(.unknown);
            } else if (std.mem.eql(u8, a.args[1], "bash")) {
                a.respond(.intRangeOptions(
                    1,
                    null,
                ));
            } else {
                a.panic("WTF IS THIS?", .{});
            }
        },
        else => a.respond(.unknown),
    }
}
