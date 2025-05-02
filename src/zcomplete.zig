pub const backend = @import("backend");
pub const options = @import("options");
const std = @import("std");

pub const AutoComplete = struct {
    args: []const [:0]const u8,
    run: *const Run,
};

pub const Run = fn (*AutoComplete) void;

pub const Args = struct {
    len: isize,
    offsets: isize,
};

// pub const autocomplete = switch (options.backend) {
//     .clap => @import("backend/clap.zig").autocomplete,
// };
