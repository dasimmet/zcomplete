const zcomplete = @import("zcomplete");
const streql = zcomplete.streql;
const std = @import("std");

pub const Command = enum {
    eval,
    extract,
    bash,
    complete,
    help,
    @"--help",
    @"--version",
    @"-h",
    @"-v",
    @"-?",

    pub fn parse(str: []const u8) ?Command {
        inline for (comptime std.meta.fields(Command)) |field| {
            if (std.mem.eql(u8, field.name, str)) return @field(Command, field.name);
        }
        return null;
    }
};

pub fn zcomp(a: *zcomplete.AutoComplete) !void {
    a.name("zcomp");

    const cmd: ?Command = switch (a.args.len) {
        0, 1 => null,
        else => Command.parse(a.args[1]),
    };

    switch (a.cur) {
        0 => a.respond(.unknown),
        1 => a.respond(.fillOptions(a.enumNames(Command))),
        2 => {
            if (cmd) |c| switch (c) {
                .extract => a.files(),
                .complete => a.files(),
                .eval => a.respond(.unknown),
                .help, .@"--help", .@"--version", .@"-h", .@"-v", .@"-?" => a.respond(.fillOptions(&.{
                    "eval",
                    "extract",
                    "bash",
                    "complete",
                    "help",
                })),
                .bash => a.respond(.intRangeOptions(
                    1,
                    10,
                )),
            } else a.respond(.unknown);
        },
        3 => {
            if (cmd) |c| switch (c) {
                .extract => a.files(),
                .bash => a.files(),
                else => a.respond(.unknown),
            } else a.respond(.unknown);
        },
        else => a.respond(.unknown),
    }
}

test "Command.parse" {
    try std.testing.expectEqual(Command.eval, Command.parse("eval"));
    try std.testing.expectEqual(Command.extract, Command.parse("extract"));
    try std.testing.expectEqual(Command.bash, Command.parse("bash"));
    try std.testing.expectEqual(Command.complete, Command.parse("complete"));
    try std.testing.expectEqual(Command.help, Command.parse("help"));
    try std.testing.expectEqual(Command.@"--help", Command.parse("--help"));
    try std.testing.expectEqual(Command.@"--version", Command.parse("--version"));
    try std.testing.expectEqual(Command.@"-h", Command.parse("-h"));
    try std.testing.expectEqual(Command.@"-v", Command.parse("-v"));
    try std.testing.expectEqual(Command.@"-?", Command.parse("-?"));
    try std.testing.expectEqual(@as(?Command, null), Command.parse("nonexistent"));
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

    const expected_cmds = comptime std.meta.fieldNames(Command);
    try std.testing.expectEqual(expected_cmds.len, a.response.options.fill_options.len);
    for (expected_cmds, 0..) |expected, i| {
        try std.testing.expectEqualStrings(expected, a.response.options.fill_options[i]);
    }
}

test "zcomp cur = 2 positional file completion for extract and complete" {
    const extract_args: []const [:0]const u8 = &.{ "zcomp", "extract" };
    var a1: zcomplete.AutoComplete = .{
        .allocator = std.testing.allocator,
        .cur = 2,
        .cmd = "zcomp",
        .args = extract_args,
    };
    try zcomp(&a1);
    try std.testing.expectEqual(std.meta.Tag(zcomplete.Response.Options).files, std.meta.activeTag(a1.response.options));

    const complete_args: []const [:0]const u8 = &.{ "zcomp", "complete" };
    var a2: zcomplete.AutoComplete = .{
        .allocator = std.testing.allocator,
        .cur = 2,
        .cmd = "zcomp",
        .args = complete_args,
    };
    try zcomp(&a2);
    try std.testing.expectEqual(std.meta.Tag(zcomplete.Response.Options).files, std.meta.activeTag(a2.response.options));
}

test "zcomp cur = 3 positional file completion for extract and bash" {
    const extract_args: []const [:0]const u8 = &.{ "zcomp", "extract", "bin.elf" };
    var a1: zcomplete.AutoComplete = .{
        .allocator = std.testing.allocator,
        .cur = 3,
        .cmd = "zcomp",
        .args = extract_args,
    };
    try zcomp(&a1);
    try std.testing.expectEqual(std.meta.Tag(zcomplete.Response.Options).files, std.meta.activeTag(a1.response.options));

    const bash_args: []const [:0]const u8 = &.{ "zcomp", "bash", "1" };
    var a2: zcomplete.AutoComplete = .{
        .allocator = std.testing.allocator,
        .cur = 3,
        .cmd = "zcomp",
        .args = bash_args,
    };
    try zcomp(&a2);
    try std.testing.expectEqual(std.meta.Tag(zcomplete.Response.Options).files, std.meta.activeTag(a2.response.options));
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

test "zcomp cur = 2 help command returns subcommands" {
    const help_args: []const [:0]const u8 = &.{ "zcomp", "help" };
    var a: zcomplete.AutoComplete = .{
        .allocator = std.testing.allocator,
        .cur = 2,
        .cmd = "zcomp",
        .args = help_args,
    };
    try zcomp(&a);
    try std.testing.expectEqual(5, a.response.options.fill_options.len);
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

test "zcomp cur > 3 returns unknown" {
    const args: []const [:0]const u8 = &.{ "zcomp", "bash", "3", "zcomp", "extra" };
    var a: zcomplete.AutoComplete = .{
        .allocator = std.testing.allocator,
        .cur = 4,
        .cmd = "zcomp",
        .args = args,
    };
    try zcomp(&a);
    try std.testing.expectEqual(zcomplete.Response.Options.unknown, a.response.options);
}
