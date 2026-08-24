const zcomplete = @import("zcomplete");
const streql = zcomplete.streql;
const std = @import("std");
const root = @import("zcomp.zig");

pub fn zcomp(a: *zcomplete.AutoComplete) !void {
    a.name("zcomp");

    const cmd: ?root.Command = switch (a.args.len) {
        0, 1 => null,
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
            if (cmd) |c| switch (c) {
                .extract => a.respond(.unknown),
                .eval => a.respond(.unknown),
                .help, .@"--help", .@"-h", .@"-?" => a.respond(.unknown),
                .complete => a.respond(.unknown),
                .bash => a.respond(.intRangeOptions(
                    1,
                    10,
                )),
            } else a.respond(.unknown);
        },
        else => a.respond(.unknown),
    }
}

test "zcomp name and cur = 0" {
    var a: zcomplete.AutoComplete = .{
        .allocator = std.testing.allocator,
        .cur = 0,
        .cmd = "zcomp",
        .args = &.{},
    };
    try zcomp(&a);
    try std.testing.expectEqualStrings("zcomp", a.response.header.name);
    try std.testing.expectEqual(zcomplete.Response.Options.unknown, a.response.options);
}

test "zcomp cur = 1 returns Command enum options" {
    const args: []const [:0]const u8 = &.{"zcomp"};
    var a: zcomplete.AutoComplete = .{
        .allocator = std.testing.allocator,
        .cur = 1,
        .cmd = "zcomp",
        .args = args,
    };
    try zcomp(&a);
    defer std.testing.allocator.free(a.response.options.fill_options);

    try std.testing.expectEqualStrings("zcomp", a.response.header.name);

    const expected_cmds = comptime std.meta.fieldNames(root.Command);
    try std.testing.expectEqual(expected_cmds.len, a.response.options.fill_options.len);
    for (expected_cmds, 0..) |expected, i| {
        try std.testing.expectEqualStrings(expected, a.response.options.fill_options[i]);
    }
}

test "zcomp cur = 2 bash command returns int range" {
    const args: []const [:0]const u8 = &.{ "zcomp", "bash" };
    var a: zcomplete.AutoComplete = .{
        .allocator = std.testing.allocator,
        .cur = 2,
        .cmd = "zcomp",
        .args = args,
    };
    try zcomp(&a);

    try std.testing.expectEqual(1, a.response.options.int_range.min.?);
    try std.testing.expectEqual(10, a.response.options.int_range.max.?);
}

test "zcomp cur = 2 other commands return unknown" {
    const commands = comptime [_][:0]const u8{
        "extract",
        "eval",
        "help",
        "--help",
        "-h",
        "-?",
        "complete",
    };

    inline for (commands) |cmd_name| {
        const args: []const [:0]const u8 = &.{ "zcomp", cmd_name };
        var a: zcomplete.AutoComplete = .{
            .allocator = std.testing.allocator,
            .cur = 2,
            .cmd = "zcomp",
            .args = args,
        };
        try zcomp(&a);
        try std.testing.expectEqual(zcomplete.Response.Options.unknown, a.response.options);
    }
}

test "zcomp cur = 2 unknown command returns unknown" {
    const args: []const [:0]const u8 = &.{ "zcomp", "nonexistent" };
    var a: zcomplete.AutoComplete = .{
        .allocator = std.testing.allocator,
        .cur = 2,
        .cmd = "zcomp",
        .args = args,
    };
    try zcomp(&a);
    try std.testing.expectEqual(zcomplete.Response.Options.unknown, a.response.options);
}

test "zcomp cur = 2 insufficient args returns unknown" {
    const args: []const [:0]const u8 = &.{"zcomp"};
    var a: zcomplete.AutoComplete = .{
        .allocator = std.testing.allocator,
        .cur = 2,
        .cmd = "zcomp",
        .args = args,
    };
    try zcomp(&a);
    try std.testing.expectEqual(zcomplete.Response.Options.unknown, a.response.options);
}

test "zcomp cur > 2 returns unknown" {
    const args: []const [:0]const u8 = &.{ "zcomp", "bash", "3" };
    var a: zcomplete.AutoComplete = .{
        .allocator = std.testing.allocator,
        .cur = 3,
        .cmd = "zcomp",
        .args = args,
    };
    try zcomp(&a);
    try std.testing.expectEqual(zcomplete.Response.Options.unknown, a.response.options);
}
