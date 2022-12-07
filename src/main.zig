const clap = @import("clap");
const std = @import("std");

const debug = std.debug;
const io = std.io;
const MAX_FIND_FILESIZE = 1e6;
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
    .{.name="run", .func=run},
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
            if (std.mem.eql(u8, res.positionals[0], sc.name)) sc.func(res.args,res.positionals[1..]);
            return;
        }
    }
    debug.print("{s}\n", .{help_head});
    debug.print("{s}\n", .{help_args});

}

fn run(globals: anytype, cli:[]const []const u8) void {
    _ = globals;

    println("", .{});
    if (std.os.getenv("ZIG_CLAPCOMPLETE_COMMANDS")) |envvar| {
        println("ENVVAR {s}", .{envvar});
    }
    if (clapcomplete_find_magic(cli[0]) catch false) {
        println("REGISTER:", .{});
    }
    println("CLI: ", .{});
    for (cli) |arg| {
        println("<{s}>", .{arg});
    }
}

fn clapcomplete_find_magic(filename: []const u8) !bool {

    var file = try std.fs.cwd().openFile(filename, .{});
    defer file.close();

    var buf_reader = std.io.bufferedReader(file.reader());
    var in_stream = buf_reader.reader();

    var bufA: [2048]u8 = undefined;
    var bufActive: []u8 = &bufA;
    bufActive.len = 1024;
    var total: u64 = 0;
    while (true) {
        // const bufPassive = bufActive;
        if (bufActive.ptr == &bufA) {
            bufActive.ptr += bufActive.len;
        } else {
            bufActive.ptr -= bufActive.len;
        }
        var count = in_stream.read(bufActive) catch |err| return err;
        if (count==0) break;
        const magic_pos = std.mem.indexOf(u8, bufActive[0..count], "ZIG_CLAP_AUTOCOMPLETE_RUN");
        if (magic_pos != null) {
            // printjson(.{.pos=magic_pos,.t="test"}, .{});
            println("POS: {d}", .{total + magic_pos.?});
            return true;
        }
        total += count;
        if (total > MAX_FIND_FILESIZE) break;
    }
    println("NOTFOUND: {} {}", .{total, MAX_FIND_FILESIZE});
    return false;
}

fn println(comptime fmt: []const u8, args: anytype) void {
    debug.print("PRINT: "++fmt++"\n", args);
}

fn printjson(value: anytype, options: std.json.StringifyOptions) void {
    const writer = std.io.getStdOut();
    _ = writer.write("PRINT:JSON:") catch unreachable;
    std.json.stringify(value, options, writer.writer()) catch unreachable;
    _ = writer.write("\n") catch unreachable;
}

pub fn autocomplete(args: anytype) void {
    _ = args;
    const autocomplete_run = std.os.getenv("ZIG_CLAP_AUTOCOMPLETE_RUN");
    if (autocomplete_run != null) {
        const out = std.io.getStdOut();
        _ = out.write("ZIG_CLAP_AUTOCOMPLETE_DONE\n") catch unreachable;
        std.os.exit(0);
    }
}