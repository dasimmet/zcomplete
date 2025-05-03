# zcomplete

a python argcomplete inspired shell completion engine for zig argument parsers.

Traditionally, [bash-completion](https://github.com/scop/bash-completion/)
works by command line programs shipping their own `bash` code to handle
suggestions when users type the command and hit `<TAB>` on the keyboard.

Since these scripts are:

- `bash` specific
- maintained separately from the binary and might not match the behaviour
  of it.

Zcomplete instead works like this:

- Generate a separate `.wasm` version of your program's argument parser
- embed the `.wasm` in a special `zcomplete.wasm` ELF section using a linker script
- provides a generic tool called `zcomp` that needs to be installed in `PATH`
  once, along with a simple `zcomplete.bash` completion script.
- when pressing `<TAB>` in bash, `zcomp` will try to 
  extract and instanciate the `zcomplete.wasm` section with a [Webassembly Runtime](https://github.com/malcolmstill/zware),
  then pass in the current command line and the current arg to be completed.
- evaluate the response and generate bash completion
- SUCCESS!

## Zcomplete vs argcomplete

Python's [argcomplete](https://pypi.org/project/argcomplete/) works
by running the actual python script until the `argparse` instance is created,
and uses the contained info to generate the completion suggestions.
It's main shortcomings are:

- needs to run the actual python script. We cannot do that on a native binary
  safely. It uses a `PYTHON_ARGCOMPLETE_OK` magic string to determine a
  script's eligibility for completion.
- May take longer than bearable by users on each `<TAB>` press,
  since starting python and reading all source code is slow.

## TODOs

This project is in a Proof-of-concept stage. It barely generates 
useful completion for itself.

### Support other shells than `bash`

- [`zsh`](https://github.com/zsh-users/zsh-completions)
- [`fish`](https://fishshell.com/docs/current/completions.html)
- [`powershell`](https://learn.microsoft.com/en-us/powershell/scripting/learn/shell/tab-completion?view=powershell-7.5)

### Povide completion for file paths in the filesystem

- Offer a way for `.wasm` to query filesystem files?
- report back valid extensions or magic numbers from `.wasm` to `zcomp`?

### Alternatives if embedding in ELF is not an option.

- Embedded Windows Resource files?
- MachO?
- Support `.wasm` separate from the binary?
  This needs a reasonably fast way of associating a binary and the `.wasm`.
  Optionally, a single `.wasm` core could serve completions for multiple
  binaries, like and `zcomplete` could use the `.wasm` files like a plugin system.

### make a non-mvp target it work with zig master

at the moment we set an explicit generic target (which means only `mvp`
wasm features are on):

```zig
.target = b.resolveTargetQuery(.{
    .cpu_arch = .wasm32,
    .os_tag = .freestanding,
    .abi = .none,
    .cpu_model = .{
        .explicit = std.Target.Cpu.Model.generic(.wasm32),
    },
}),
```

zware works always with 0.14.0, on master with only `wasm32-freestanding`
it fails. Maybe only `mvp` wasm32 should be supported, but this is the
error:

```
error: ValidatorCallIndirectNoTable
/home/dasimmet/.cache/zig/p/zware-0.0.1-ZA7j6X3jBABhBIltmAF9N6OP7VTsgFP3O1xPkgiaCY_t/src/module/parser.zig:384:68: 0x11c7aec in next (zcomp)
                if (tableidx >= self.module.tables.list.items.len) return error.ValidatorCallIndirectNoTable;
                                                                   ^
/home/dasimmet/.cache/zig/p/zware-0.0.1-ZA7j6X3jBABhBIltmAF9N6OP7VTsgFP3O1xPkgiaCY_t/src/module/parser.zig:63:16: 0x11d9292 in parseFunction (zcomp)
        while (try self.next()) |instr| {
               ^
/home/dasimmet/.cache/zig/p/zware-0.0.1-ZA7j6X3jBABhBIltmAF9N6OP7VTsgFP3O1xPkgiaCY_t/src/module.zig:798:9: 0x11d973a in readFunction (zcomp)
        return parser.parseFunction(funcidx, locals, code);
        ^
/home/dasimmet/.cache/zig/p/zware-0.0.1-ZA7j6X3jBABhBIltmAF9N6OP7VTsgFP3O1xPkgiaCY_t/src/module.zig:686:33: 0x11d9e27 in decodeCodeSection (zcomp)
            const parsed_code = try self.readFunction(module, locals, function_index_start + i);
                                ^
/home/dasimmet/.cache/zig/p/zware-0.0.1-ZA7j6X3jBABhBIltmAF9N6OP7VTsgFP3O1xPkgiaCY_t/src/module.zig:174:22: 0x11dade0 in decodeSection (zcomp)
            .Code => try self.decodeCodeSection(module),
                     ^
/home/dasimmet/.cache/zig/p/zware-0.0.1-ZA7j6X3jBABhBIltmAF9N6OP7VTsgFP3O1xPkgiaCY_t/src/module.zig:106:25: 0x11dba05 in decode (zcomp)
                else => return err,
                        ^
/home/dasimmet/repos/zig/zcomplete/src/zcomp.zig:69:5: 0x11fc840 in complete (zcomp)
    try module.decode();
    ^

```
