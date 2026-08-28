//! Example CLI application demonstrating embedded zcomplete auto-completion.
//! Implements multi-nested subcommands, flags, and arguments matching simple-example.zcomplete.zig.

const std = @import("std");
const zcomplete = @import("zcomplete");
const spec = @import("simple-example.zcomplete.zig");

pub const std_options = std.Options{
    .log_level = .debug,
};

pub const usage =
    \\Usage: simple-example <command> [subcommand] [options] [args]
    \\
    \\Commands:
    \\  build    Build targets (wasm, image)
    \\  config   Manage configuration (get, set, load, reset)
    \\  package  Create and verify distribution packages (bundle, verify)
    \\  help     Show help information
    \\
    \\Options:
    \\  -h, --help     Show help
    \\  -v, --version  Show version
    \\
;

const embedded_bin = @embedFile("zcomplete_bin");
const prog: [embedded_bin.len]u8 linksection(zcomplete.linker_section_name) = embedded_bin[0..embedded_bin.len].*;

pub fn main(init: std.process.Init) !void {
    _ = prog;
    const args = try init.minimal.args.toSlice(init.arena.allocator());
    const stdout_fd = std.Io.File.stdout();
    var stdout_buf: [4096]u8 = undefined;
    var stdout_writer = stdout_fd.writer(init.io, &stdout_buf);
    const stdout = &stdout_writer.interface;

    if (args.len < 2) {
        try stdout.writeAll(usage);
        try stdout.flush();
        return;
    }

    const root_cmd = spec.RootCommand.parse(args[1]) orelse {
        std.log.err("Unknown command: {s}\n", .{args[1]});
        try stdout.writeAll(usage);
        try stdout.flush();
        return;
    };

    switch (root_cmd) {
        .@"--help", .@"-h", .help => {
            try stdout.writeAll(usage);
            try stdout.flush();
        },
        .@"--version", .@"-v" => {
            try stdout.writeAll("simple-example 2.0.0\n");
            try stdout.flush();
        },
        .build => {
            if (args.len < 3) {
                try stdout.writeAll("Usage: simple-example build <wasm|image> [options] <input_file>\n");
                try stdout.flush();
                return;
            }
            const sub = spec.BuildCommand.parse(args[2]) orelse {
                std.log.err("Unknown build target: {s}\n", .{args[2]});
                return;
            };
            switch (sub) {
                .wasm => {
                    const input = if (args.len >= 4) args[3] else "main.zig";
                    try stdout.print("Building WebAssembly module from {s}...\n", .{input});
                },
                .image => {
                    const input = if (args.len >= 4) args[3] else "icon.png";
                    try stdout.print("Optimizing image {s}...\n", .{input});
                },
                else => {
                    try stdout.writeAll("Building all targets...\n");
                },
            }
            try stdout.flush();
        },
        .config => {
            if (args.len < 3) {
                try stdout.writeAll("Usage: simple-example config <get|set|load|reset> [args]\n");
                try stdout.flush();
                return;
            }
            const sub = spec.ConfigCommand.parse(args[2]) orelse {
                std.log.err("Unknown config command: {s}\n", .{args[2]});
                return;
            };
            switch (sub) {
                .get => {
                    const key = if (args.len >= 4) args[3] else "all";
                    try stdout.print("Config {s} = default\n", .{key});
                },
                .set => {
                    const key = if (args.len >= 4) args[3] else "<key>";
                    const val = if (args.len >= 5) args[4] else "<value>";
                    try stdout.print("Setting {s} = {s}\n", .{ key, val });
                },
                .load => {
                    const file = if (args.len >= 4) args[3] else "config.json";
                    try stdout.print("Loaded config from {s}\n", .{file});
                },
                .reset => {
                    try stdout.writeAll("Reset all settings to default.\n");
                },
                .@"--help", .@"-h" => {
                    try stdout.writeAll("Usage: simple-example config <get|set|load|reset>\n");
                },
            }
            try stdout.flush();
        },
        .package => {
            if (args.len < 3) {
                try stdout.writeAll("Usage: simple-example package <bundle|verify> [args]\n");
                try stdout.flush();
                return;
            }
            const sub = spec.PackageCommand.parse(args[2]) orelse {
                std.log.err("Unknown package command: {s}\n", .{args[2]});
                return;
            };
            switch (sub) {
                .bundle => {
                    const src_dir = if (args.len >= 4) args[3] else ".";
                    const out_file = if (args.len >= 5) args[4] else "dist.tar.gz";
                    try stdout.print("Bundling {s} -> {s}\n", .{ src_dir, out_file });
                },
                .verify => {
                    const file = if (args.len >= 4) args[3] else "dist.tar.gz";
                    try stdout.print("Verifying package integrity: {s} [OK]\n", .{file});
                },
                else => {
                    try stdout.writeAll("Package command completed.\n");
                },
            }
            try stdout.flush();
        },
    }
}
