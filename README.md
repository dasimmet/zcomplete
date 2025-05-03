# zcomplete

a python argcomplete inspired completion engine for zig argument parsers

- Generate a separate .wasm version of your program's argument parser
- embed `wasm` in a special `.zcomplete` ELF section using linker script
- extract and instanciate `wasm` with `zware` -> pass in the arguments
- evaluate the response and generate bash completion
- SUCCESS! 
