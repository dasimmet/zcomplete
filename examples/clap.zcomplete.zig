const zcomplete = @import("zcomplete");
const clap = zcomplete.backend;
const root = @import("clap.zig");
const std = @import("std");

const main_parsers = .{
    .command = clap.parsers.enumeration(root.SubCommands),
};
const main_clap = clap.parseParamsComptime(root.main_params);

pub fn zcomp(a: *zcomplete.AutoComplete) void {
    // var diag = clap.Diagnostic{};
    // var res = clap.parseEx(
    //     clap.Help,
    //     &main_clap,
    //     main_parsers,
    //     null,
    //     .{
    //         .diagnostic = &diag,
    //         .allocator = a.allocator,
    //         .terminating_positional = 0,
    //     },
    // ) catch |err| {
    //     diag.report(std.io.getStdErr().writer(), err) catch {};
    //     return err;
    // };
    // defer res.deinit();
    a.respond(.unknown);
}
