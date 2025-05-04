const zcomplete = @import("zcomplete");
const root = @import("clap.zig");
const clap = @import("clap");
const std = @import("std");

const main_parsers = .{
    .command = clap.parsers.enumeration(root.SubCommands),
};
const main_clap = clap.parseParamsComptime(root.main_params);

pub fn zcomp(a: *zcomplete.AutoComplete) void {
    a.name("clap-example");

    var names: [main_clap.len + std.meta.fields(root.SubCommands).len][]const u8 = undefined;
    for (main_clap, 0..) |param, i| {
        names[i] = a.fmt("--{s}", .{param.names.longest().name});
    }
    inline for (std.meta.fields(root.SubCommands), main_clap.len..) |cmd, i| {
        names[i] = a.fmt("--{s}", .{cmd.name});
    }

    switch (a.cur) {
        0 => a.respond(.unknown),
        1 => a.respond(.fillOptions(&names)),
        else => a.respond(.unknown),
    }
}
