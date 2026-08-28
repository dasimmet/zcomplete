const std = @import("std");
const zcomplete = @import("zcomplete");

pub const RootCommand = enum {
    build,
    config,
    package,
    help,
    @"--help",
    @"--version",
    @"-h",
    @"-v",

    pub fn parse(str: []const u8) ?RootCommand {
        inline for (comptime std.meta.fields(RootCommand)) |field| {
            if (std.mem.eql(u8, field.name, str)) return @field(RootCommand, field.name);
        }
        return null;
    }
};

pub const BuildCommand = enum {
    wasm,
    image,
    @"--all",
    @"-a",
    @"--release",
    @"--verbose",
    @"-v",
    @"--help",
    @"-h",

    pub fn parse(str: []const u8) ?BuildCommand {
        inline for (comptime std.meta.fields(BuildCommand)) |field| {
            if (std.mem.eql(u8, field.name, str)) return @field(BuildCommand, field.name);
        }
        return null;
    }
};

pub const ConfigCommand = enum {
    get,
    set,
    load,
    reset,
    @"--help",
    @"-h",

    pub fn parse(str: []const u8) ?ConfigCommand {
        inline for (comptime std.meta.fields(ConfigCommand)) |field| {
            if (std.mem.eql(u8, field.name, str)) return @field(ConfigCommand, field.name);
        }
        return null;
    }
};

pub const PackageCommand = enum {
    bundle,
    verify,
    @"--dry-run",
    @"--verbose",
    @"-v",
    @"--help",
    @"-h",

    pub fn parse(str: []const u8) ?PackageCommand {
        inline for (comptime std.meta.fields(PackageCommand)) |field| {
            if (std.mem.eql(u8, field.name, str)) return @field(PackageCommand, field.name);
        }
        return null;
    }
};

pub const ConfigKeys = [_][]const u8{
    "theme",
    "editor",
    "timeout",
    "log_level",
    "output_dir",
};

pub fn zcomp(a: *zcomplete.AutoComplete) !void {
    a.name("simple-example");

    const root_cmd: ?RootCommand = if (a.args.len >= 2) RootCommand.parse(a.args[1]) else null;

    switch (a.cur) {
        0 => a.respond(.unknown),
        1 => a.respond(.fillOptions(a.enumNames(RootCommand))),
        2 => {
            if (root_cmd) |rc| switch (rc) {
                .build => a.respond(.fillOptions(a.enumNames(BuildCommand))),
                .config => a.respond(.fillOptions(a.enumNames(ConfigCommand))),
                .package => a.respond(.fillOptions(a.enumNames(PackageCommand))),
                .help, .@"--help", .@"--version", .@"-h", .@"-v" => a.respond(.fillOptions(&.{
                    "build",
                    "config",
                    "package",
                    "help",
                })),
            } else a.respond(.unknown);
        },
        3 => {
            if (root_cmd) |rc| switch (rc) {
                .build => {
                    const sub = if (a.args.len >= 3) BuildCommand.parse(a.args[2]) else null;
                    if (sub) |s| switch (s) {
                        .wasm => a.filesPattern("*.zig"),
                        .image => a.filesPattern("*.png"),
                        else => a.filesPattern("*.zig"),
                    } else a.filesPattern("*.zig");
                },
                .config => {
                    const sub = if (a.args.len >= 3) ConfigCommand.parse(a.args[2]) else null;
                    if (sub) |s| switch (s) {
                        .get, .set => a.respond(.fillOptions(&ConfigKeys)),
                        .load => a.filesPattern("*.json"),
                        .reset => a.respond(.fillOptions(&.{ "--all", "--force" })),
                        else => a.respond(.unknown),
                    } else a.respond(.unknown);
                },
                .package => {
                    const sub = if (a.args.len >= 3) PackageCommand.parse(a.args[2]) else null;
                    if (sub) |s| switch (s) {
                        .bundle => a.directories(),
                        .verify => a.filesPattern("*.tar.gz"),
                        else => a.respond(.unknown),
                    } else a.respond(.unknown);
                },
                else => a.respond(.unknown),
            } else a.respond(.unknown);
        },
        4 => {
            if (root_cmd) |rc| switch (rc) {
                .package => {
                    const sub = if (a.args.len >= 3) PackageCommand.parse(a.args[2]) else null;
                    if (sub) |s| switch (s) {
                        .bundle => a.filesPattern("*.tar.gz"),
                        else => a.respond(.unknown),
                    } else a.respond(.unknown);
                },
                .config => {
                    const sub = if (a.args.len >= 3) ConfigCommand.parse(a.args[2]) else null;
                    if (sub) |s| switch (s) {
                        .set => a.respond(.unknown),
                        else => a.respond(.unknown),
                    } else a.respond(.unknown);
                },
                else => a.respond(.unknown),
            } else a.respond(.unknown);
        },
        else => a.respond(.unknown),
    }
}

test "simple-example root completion" {
    var a: zcomplete.AutoComplete = .{
        .allocator = std.testing.allocator,
        .cur = 1,
        .cmd = "simple-example",
        .args = &.{"simple-example"},
    };
    try zcomp(&a);
    defer std.testing.allocator.free(a.response.options.fill_options);
    try std.testing.expectEqualStrings("simple-example", a.response.header.name);
    try std.testing.expectEqual(std.meta.fields(RootCommand).len, a.response.options.fill_options.len);
}

test "simple-example nested build wasm completion with zig pattern" {
    const args: []const [:0]const u8 = &.{ "simple-example", "build", "wasm" };
    var a: zcomplete.AutoComplete = .{
        .allocator = std.testing.allocator,
        .cur = 3,
        .cmd = "simple-example",
        .args = args,
    };
    try zcomp(&a);
    try std.testing.expectEqual(std.meta.Tag(zcomplete.Response.Options).files, std.meta.activeTag(a.response.options));
    try std.testing.expectEqualStrings("*.zig", a.response.options.files.pattern.?);
}

test "simple-example config get keys completion" {
    const args: []const [:0]const u8 = &.{ "simple-example", "config", "get" };
    var a: zcomplete.AutoComplete = .{
        .allocator = std.testing.allocator,
        .cur = 3,
        .cmd = "simple-example",
        .args = args,
    };
    try zcomp(&a);
    try std.testing.expectEqual(5, a.response.options.fill_options.len);
}

test "simple-example package bundle directory and tar.gz pattern" {
    const args_dir: []const [:0]const u8 = &.{ "simple-example", "package", "bundle" };
    var a1: zcomplete.AutoComplete = .{
        .allocator = std.testing.allocator,
        .cur = 3,
        .cmd = "simple-example",
        .args = args_dir,
    };
    try zcomp(&a1);
    try std.testing.expectEqual(std.meta.Tag(zcomplete.Response.Options).directories, std.meta.activeTag(a1.response.options));

    const args_file: []const [:0]const u8 = &.{ "simple-example", "package", "bundle", "src/" };
    var a2: zcomplete.AutoComplete = .{
        .allocator = std.testing.allocator,
        .cur = 4,
        .cmd = "simple-example",
        .args = args_file,
    };
    try zcomp(&a2);
    try std.testing.expectEqual(std.meta.Tag(zcomplete.Response.Options).files, std.meta.activeTag(a2.response.options));
    try std.testing.expectEqualStrings("*.tar.gz", a2.response.options.files.pattern.?);
}
