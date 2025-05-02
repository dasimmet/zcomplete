const clap = @import("backend");
const std = @import("std");
const options = @import("options");

pub fn autocomplete(comptime command: []const []const u8, comptime params: []const clap.Param(clap.Help)) void {
    _ = command;
    _ = params;
}
