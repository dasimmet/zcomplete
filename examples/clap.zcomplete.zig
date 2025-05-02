const zcomplete = @import("zcomplete");
const clap = zcomplete.backend;
pub const root = @import("clap.zig");
const std = @import("std");

pub fn run_zcomplete(a: *zcomplete.AutoComplete) void {
    _ = root.main;
    _ = a;
}
