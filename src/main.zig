const clap = @import("clap");
const std = @import("std");
const magic = @import("magic.zig");

const debug = std.debug;
const io = std.io;

const help_head =
\\clapcomplete
\\
;
const help_args =
\\-h, --help        Display this help and exit.
\\-s, --shell <str> the name of the invoking shell
\\<str>        the file to return completion for
\\
;


fn Shell(comptime n: []u8) void {
    return struct {
        name: []u8 = n,
    };
}

const SubCommand = struct {
    name: []const u8,
    // subcommand function receives args and rest of positionals
    func: fn (anytype,[]const []const u8) void,
};

const commands = [_]SubCommand{
    .{.name="run", .func=@import("run.zig").run},
    .{.name="source", .func=@import("source.zig").src},
};

pub fn main() !void {
    // First we specify what parameters our program can take.
    // We can use `parseParamsComptime` to parse a string into an array of `Param(Help)`
    const params = comptime clap.parseParamsComptime(help_args);

    var diag = clap.Diagnostic{};
    var res = clap.parse(clap.Help, &params, clap.parsers.default, .{
        .diagnostic = &diag,
    }) catch |err| {
        diag.report(io.getStdErr().writer(), err) catch {};
        return err;
    };
    defer res.deinit();
    // call autocomplete to enable autocompletion. when called with env ZIG_CLAP_AUTOCOMPLETE_RUN it will exit here
    autocomplete(res);

    // debug.print("{any}\n", .{res.args.help});
    if (res.args.help) {
        debug.print("{s}\n", .{help_head});
        debug.print("{s}\n", .{help_args});
        return;
    }
    if (res.args.shell) |s| {
        debug.print("--shell = {s}\n", .{s});
    }
    if (res.positionals.len > 0) {
        inline for (commands) |sc| {
            if (std.mem.eql(u8, res.positionals[0], sc.name)) {
                sc.func(res.args,res.positionals[1..]);
                return;
            }
        }
    }
    debug.print("{s}\n", .{help_head});
    debug.print("{s}\n", .{help_args});

}

pub fn autocomplete(args: anytype) void {
    _ = args;
    const autocomplete_run = std.os.getenv(magic.ARGCOMPLETE_ENV);
    if (autocomplete_run != null) {
        const out = std.io.getStdOut();
        _ = out.write("ZIG_CLAP_AUTOCOMPLETE_DONE\n") catch unreachable;
        std.os.exit(0);
    }
}