# zcomplete

a python argcomplete inspired completion engine for zig argument parsers.
Works like this:

- Generate a separate .wasm version of your program's argument parser
- embed `wasm` in a special `zcomplete` ELF section using linker script
- extract and instanciate `wasm` with `zware` -> pass in the current command
  line and the current arg to be completed
- evaluate the response and generate bash completion
- SUCCESS!

## TODOs

This project is in a Proof-of-concept stage. It barely generates 
useful completion for itself.

### Support other shells than `bash`


### Povide completion for files in the filesystem

- Offer a way for `.wasm` to query filesystem files?
- report back valid extensions or magic numbers from `.wasm` to `zcomp`?

### Alternatives if embedding in ELF is not an option.

- Embedded Windows Resource files?
- MachO?
- Support separate .wasm files.
  This needs some kind of "friendship check" between a binary and the `.wasm`.

### make a non-generic target it work with zig master

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
