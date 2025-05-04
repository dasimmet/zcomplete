const zcomplete = @import("zcomplete");
const std = @import("std");

pub fn zcomp(a: *zcomplete.AutoComplete) !void {
    a.name("simple-example");
    switch (a.cur) {
        0 => a.respond(.unknown),
        1 => a.respond(.fillOptions(&.{
            "--help",
            "--version",
        })),
        else => a.respond(.unknown),
    }
}
