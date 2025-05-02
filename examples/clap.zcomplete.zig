const zcomplete = @import("zcomplete");
const clap = zcomplete.backend;
const root = @import("clap.zig");
const std = @import("std");

pub fn run_zcomplete(a: *zcomplete.AutoComplete) void {
    _ = root.main;
    _ = a;
    // var diag = clap.Diagnostic{};
    // var res = clap.parseEx(
    //     clap.Help,
    //     &root.main_params,
    //     root.main_parsers,
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
}
