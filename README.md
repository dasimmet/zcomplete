# zcomplete

A fast, safe, WebAssembly-powered shell completion engine for Zig CLI applications.

Inspired by Python's [argcomplete](https://pypi.org/project/argcomplete/), `zcomplete` lets command-line tools define their argument parsing and auto-completion logic directly in Zig without maintaining separate shell-specific scripts.

---

## How It Works

1. **Standalone WASM Specification**: Your CLI's completion logic is compiled into a lightweight WebAssembly module (`wasm32-freestanding-none`).
2. **Embedded in Native Executables**: The compiled `.wasm` is embedded directly into the executable's dedicated linksection (`.zcomplete` on ELF/PE-COFF, `__DATA,__zcomplete` on Mach-O) using Zig's `linksection` attribute with zero runtime overhead.
3. **Single Generic Runner (`zcomp`)**: When you type a command and hit `<TAB>`, Bash calls `zcomp`, which:
   - Reads the embedded `.zcomplete` section directly from ELF, Mach-O (macOS), or PE/COFF (Windows) executables.
   - Executes the completion function inside a fast, isolated WebAssembly sandbox ([zware](https://github.com/dasimmet/zware), [wasmz](https://github.com/Ray-D-Song/wasmz), or [zwasm](https://github.com/zwasm/zwasm)).
   - Resolves subcommands, flags, values, integer ranges, or filesystem paths.
   - Outputs suggestions directly to Bash.

---

## Features

- **Zero Shell Scripts to Maintain**: Write completion logic once in Zig.
- **Nested Subcommands**: Full support for deeply nested commands and subcommands (e.g. `tool package bundle ...`).
- **Short & Long Options**: Complete `-h`, `-v`, `-O`, `--help`, `--version`, `--verbose`, etc.
- **Path & Directory Completion**:
  - `a.files()` — auto-completes files in the filesystem.
  - `a.filesPattern("*.zig")` — pattern-filtered file completions while maintaining directory traversal.
  - `a.directories()` — auto-completes directories only (e.g. for output destinations or source roots).
  - `a.paths()` — generic filesystem path completion.
- **Fixed Value Lists**: Suggest values from enums or string arrays (e.g. `json`, `yaml`, `toml`).
- **Integer Ranges**: Dynamic numerical range completion (e.g. `1..10`).
- **Safe & Sandboxed**: Execution happens inside WebAssembly memory without executing native code from the binary.

---

## Setup & Bash Integration

### 1. Build and Install `zcomp`

```bash
git clone https://github.com/dasimmet/zcomplete.git
cd zcomplete
zig build -Doptimize=ReleaseFast
```

Copy the resulting `zcomp` binary to your `PATH` (e.g. `~/.local/bin` or `/usr/local/bin`):

```bash
cp zig-out/bin/zcomp ~/.local/bin/
```

### 2. Enable Bash Completion

Add the following hook to your `~/.bashrc`:

```bash
eval "$(zcomp eval)"
```

Alternatively, install the bash completion script globally or into your user directory:

```bash
# User installation:
mkdir -p ~/.local/share/bash-completion/completions
cp src/share/zcomplete.bash ~/.local/share/bash-completion/completions/zcomplete

# Or system-wide:
sudo cp src/share/zcomplete.bash /etc/bash_completion.d/zcomplete
```

Once loaded, `zcomp` will dynamically handle completions for **any** binary built with `zcomplete`.

---

## Adding `zcomplete` to Your Zig Project

### 1. Add Dependency (`build.zig.zon`)

```zig
.{
    .name = .my_project,
    .version = "0.1.0",
    .fingerprint = 0x1234567890abcdef,
    .minimum_zig_version = "0.16.0",
    .dependencies = .{
        .zcomplete = .{
            .url = "git+https://github.com/dasimmet/zcomplete.git#<commit_hash>",
            .hash = "<hash>",
        },
    },
    .paths = .{ "build.zig", "build.zig.zon", "src" },
}
```

### 2. Configure `build.zig`

Use `ZComplete.builtinModule` to build your completion specification into a WASM module and link it to your executable:

```zig
const std = @import("std");
const zcomplete_pkg = @import("zcomplete");
const ZComplete = zcomplete_pkg.ZComplete;

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const zcomplete = b.dependency("zcomplete", .{
        .target = target,
        .optimize = optimize,
    }).module("zcomplete");

    const exe = b.addExecutable(.{
        .name = "mycli",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "zcomplete", .module = zcomplete },
                .{
                    .name = "zcomplete_bin",
                    .module = ZComplete.builtinModule(
                        b,
                        "mycli-zcomplete",
                        zcomplete,
                        b.path("src/mycli.zcomplete.zig"),
                    ),
                },
            },
        }),
    });
    exe.use_llvm = true;
    b.installArtifact(exe);
}
```

### 3. Embed Completion in Your Binary (`src/main.zig`)

In your CLI source file, include the embedded WASM section:

```zig
const std = @import("std");
const zcomplete = @import("zcomplete");

// Embed the compiled WASM parser in the .zcomplete section
const embedded_bin = @embedFile("zcomplete_bin");
const prog: [embedded_bin.len]u8 linksection(zcomplete.linker_section_name) = embedded_bin[0..embedded_bin.len].*;

pub fn main() !void {
    _ = prog; // Keep symbol referenced
    
    // Your regular CLI execution code here...
}
```

---

## Writing a Completion Specification

Create `src/mycli.zcomplete.zig` to define how your commands, flags, and arguments are completed:

```zig
const std = @import("std");
const zcomplete = @import("zcomplete");

pub const Command = enum {
    build,
    config,
    package,
    help,
    @"--help",
    @"--version",
    @"-h",
    @"-v",

    pub fn parse(str: []const u8) ?Command {
        inline for (comptime std.meta.fields(Command)) |field| {
            if (std.mem.eql(u8, field.name, str)) return @field(Command, field.name);
        }
        return null;
    }
};

pub const BuildTarget = enum {
    wasm,
    image,
    @"--release",
    @"--verbose",
    @"-v",

    pub fn parse(str: []const u8) ?BuildTarget {
        inline for (comptime std.meta.fields(BuildTarget)) |field| {
            if (std.mem.eql(u8, field.name, str)) return @field(BuildTarget, field.name);
        }
        return null;
    }
};

pub fn zcomp(a: *zcomplete.AutoComplete) !void {
    a.name("mycli");

    const root_cmd: ?Command = if (a.args.len >= 2) Command.parse(a.args[1]) else null;

    switch (a.cur) {
        0 => a.respond(.unknown),
        1 => a.respond(.fillOptions(a.enumNames(Command))),
        2 => {
            if (root_cmd) |rc| switch (rc) {
                .build => a.respond(.fillOptions(a.enumNames(BuildTarget))),
                .config => a.respond(.fillOptions(&.{ "get", "set", "load", "reset" })),
                .package => a.respond(.fillOptions(&.{ "bundle", "verify", "--dry-run" })),
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
                    const target = if (a.args.len >= 3) BuildTarget.parse(a.args[2]) else null;
                    if (target) |t| switch (t) {
                        .wasm => a.filesPattern("*.zig"), // Only show .zig files & dirs
                        .image => a.filesPattern("*.png"), // Only show .png files & dirs
                        else => a.files(),
                    } else a.files();
                },
                .config => a.respond(.fillOptions(&.{ "theme", "editor", "timeout" })),
                .package => a.directories(), // Complete source directory
                else => a.respond(.unknown),
            } else a.respond(.unknown);
        },
        4 => {
            if (root_cmd) |rc| switch (rc) {
                .package => a.filesPattern("*.tar.gz"), // Complete destination archive
                else => a.respond(.unknown),
            } else a.respond(.unknown);
        },
        else => a.respond(.unknown),
    }
}
```

---

## `zcomp` CLI Reference

The `zcomp` runner provides tools for inspecting, testing, and debugging completions:

| Command                                      | Description                                                       |
| -------------------------------------------- | ----------------------------------------------------------------- |
| `zcomp complete <binary> [args...]`          | Inspect completions for a binary at the given argument position.  |
| `zcomp bash <cur_index> <command> [args...]` | Generate Bash completion candidate lines.                         |
| `zcomp extract <binary> [output.wasm]`       | Extract the embedded `.zcomplete` WASM module from an ELF binary. |
| `zcomp eval`                                 | Output the Bash hook snippet for `eval "$(zcomp eval)"`.          |

### Examples

Test completions on your binary directly in your terminal:

```bash
# Complete top-level subcommands and options
zcomp complete ./zig-out/bin/mycli

# Complete nested subcommand
zcomp complete ./zig-out/bin/mycli build ""

# Test bash path completion for .zig files
zcomp bash 3 ./zig-out/bin/mycli build wasm src/
```

---

## Building & Testing

```bash
# Run unit tests
zig build test

# Run end-to-end completion tests with default (zware) engine
zig build test-complete

# Run end-to-end completion tests with wasmz engine
zig build test-complete -Dwasmbackend=wasmz

# Run end-to-end completion tests with zwasm engine
zig build test-complete -Dwasmbackend=zwasm

# Build example binary
zig build example
```

---

## License

MIT License. See [LICENSE](LICENSE) for details.
