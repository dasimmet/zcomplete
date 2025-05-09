const zcomplete = @import("zcomplete");
const streql = zcomplete.streql;
const std = @import("std");
const root = @import("zcomp.zig");

pub fn zcomp(a: *zcomplete.AutoComplete) !void {
    a.name("zcomp");

    const cmd = switch (a.args.len) {
        0 => null,
        else => cmd: {
            inline for (comptime std.meta.fieldNames(root.Command)) |fieldname| {
                if (std.mem.eql(u8, fieldname, a.args[1])) break :cmd @field(root.Command, fieldname);
            }
            break :cmd null;
        },
    };

    switch (a.cur) {
        0 => a.respond(.unknown),
        1 => a.respond(.fillOptions(a.enumNames(root.Command))),
        2 => {
            if (cmd == null) a.respond(.unknown);
            switch (cmd.?) {
                .extract => a.respond(.unknown),
                .eval => a.respond(.unknown),
                .help, .@"--help", .@"-h",
                .@"-?" => a.respond(.unknown),
                .complete => a.respond(.unknown),
                .bash => a.respond(.intRangeOptions(
                    1,
                    10,
                )),
            }
        },
        else => a.respond(.unknown),
    }
}
