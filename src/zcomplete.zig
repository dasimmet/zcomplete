pub const options = @import("options");
const std = @import("std");
pub const linker_section_name = "zcomplete.wasm";
pub const api_version = 1;

pub const AutoComplete = struct {
    allocator: std.mem.Allocator,

    // the current argument being completed.
    // 0 means the command itself, 1 means args[0]
    cur: u32,

    // the current command
    cmd: [:0]const u8,

    //the current arguments on the command line
    args: []const [:0]const u8,

    // the response provided by the module. use the .respond function to set it.
    response: Response = .{
        .header = .{
            .name = "",
        },
        .options = .unknown,
    },

    pub fn name(self: *@This(), exename: []const u8) void {
        self.response.header.name = exename;
    }
    pub fn respond(self: *@This(), opt: Response.Options) void {
        self.response.options = opt;
    }
    pub fn panic(self: *@This(), comptime fmt: []const u8, args: anytype) void {
        self.response.options = .{
            .zcomperror = std.fmt.allocPrint(
                self.allocator,
                fmt,
                args,
            ) catch unreachable,
        };
    }
    pub fn serialize(self: *@This()) *Response.Serialized {
        return self.response.serialize(self.allocator);
    }
};

pub const Args = extern struct {
    version: u32 = api_version,
    // size of the header
    offset: u32,
    // size of header + payload
    len: u32,
    cur: u32,

    pub fn size(cmd: []const u8, args: []const []const u8) usize {
        var acc: usize = @sizeOf(@This()) + cmd.len + 1;
        for (args) |arg| {
            acc += arg.len + 1;
        }
        return acc;
    }

    pub fn serialize(buf: []u8, cmd: []const u8, cur: usize, args: []const []const u8) *@This() {
        const mysize = Args.size(cmd, args);
        std.debug.assert(buf.len == mysize);
        const self: *@This() = @alignCast(@ptrCast(buf.ptr));
        self.* = .{
            .offset = @intCast(@sizeOf(@This())),
            .len = @intCast(mysize),
            .cur = @intCast(cur),
        };

        var pos: usize = @sizeOf(@This());

        @memcpy(buf[pos .. pos + cmd.len], cmd);
        buf[pos + cmd.len] = 0;
        pos += cmd.len + 1;

        for (args) |arg| {
            @memcpy(buf[pos .. pos + arg.len], arg);
            pos += arg.len;
            buf[pos] = 0;
            pos += 1;
        }
        return self;
    }

    pub fn slice(self: *@This()) []u8 {
        var ptr: [*]u8 = @alignCast(@ptrCast(self));
        return ptr[@intCast(self.offset)..@intCast(self.len)];
    }

    pub fn parse(self: *@This(), gpa: std.mem.Allocator) !struct {
        cmd: [:0]const u8,
        args: []const [:0]const u8,
    } {
        const payload = self.slice();
        var array = std.ArrayListUnmanaged([:0]const u8).empty;
        var cmd: [:0]const u8 = "";
        var last_zero: usize = 0;
        for (payload, 0..) |c, i| {
            if (c == 0) {
                if (last_zero == 0) cmd = @ptrCast(payload[last_zero..i]);
                try array.append(gpa, @ptrCast(payload[last_zero..i]));
                last_zero = i + 1;
            }
        }
        return .{
            .cmd = cmd,
            .args = try array.toOwnedSlice(gpa),
        };
    }
};

pub const Response = struct {
    header: Header,
    options: Options,

    pub const Header = struct {
        name: []const u8,
    };
    pub const Options = union(enum(u32)) {
        unknown,
        zcomperror: []const u8,
        fill_options: []const []const u8,
        int_range: struct { min: ?i32, max: ?i32 },
        _,

        pub fn deinit(self: @This(), gpa: std.mem.Allocator) void {
            switch (self) {
                .unknown, .int_range => {},
                .zcomperror => |msg| gpa.free(msg),
                .fill_options => |fo| {
                    for (fo) |opt| gpa.free(opt);
                    gpa.free(fo);
                },
                else => @panic("free unknown message"),
            }
        }

        pub fn fillOptions(fo: []const []const u8) @This() {
            return .{ .fill_options = fo };
        }

        pub fn intRangeOptions(min: ?i32, max: ?i32) @This() {
            return .{ .int_range = .{
                .min = min,
                .max = max,
            } };
        }
    };

    pub fn serialize(self: *@This(), gpa: std.mem.Allocator) *Serialized {
        const header_size = @sizeOf(Serialized);
        var acc = std.ArrayListUnmanaged(u8).initCapacity(
            gpa,
            header_size,
        ) catch unreachable;
        acc.appendNTimesAssumeCapacity(0, header_size);
        const res: *Serialized = @alignCast(@ptrCast(acc.items.ptr));
        res.offset = header_size;
        res.tag = @intFromEnum(self.options);
        switch (self.options) {
            .unknown => {},
            .zcomperror => |msg| {
                acc.appendSlice(gpa, msg) catch @panic("OOM");
            },
            .fill_options => |opts| {
                for (opts) |opt| {
                    acc.appendSlice(gpa, opt) catch @panic("OOM");
                    acc.append(gpa, 0) catch @panic("OOM");
                }
            },
            .int_range => |ir| {
                acc.appendSlice(
                    gpa,
                    &@as([4]u8, @bitCast(ir.min orelse std.math.minInt(i32))),
                ) catch unreachable;
                acc.appendSlice(
                    gpa,
                    &@as([4]u8, @bitCast(ir.max orelse std.math.maxInt(i32))),
                ) catch unreachable;
            },
            else => {
                acc.writer(gpa).print(
                    "serialize msg not implemented: {any}",
                    .{self.*},
                ) catch unreachable;
                res.tag = @intFromEnum(Options.zcomperror);
            },
        }
        res.len = @intCast(acc.items.len);
        return res;
    }

    pub const Serialized = extern struct {
        version: u32 = api_version,
        // size of the header
        offset: u32,
        // size of header + payload
        len: u32,
        tag: @typeInfo(std.meta.Tag(Options)).@"enum".tag_type,

        pub fn deinit(self: *@This(), gpa: std.mem.Allocator) void {
            gpa.free(self.slice());
            gpa.free(self);
        }

        pub fn slice(self: *@This()) []u8 {
            var ptr: [*]u8 = @alignCast(@ptrCast(self));
            return ptr[@intCast(self.offset)..@intCast(self.len)];
        }

        pub fn parse(self: *@This(), gpa: std.mem.Allocator) !Options {
            const payload = self.slice();
            const tag_enum: std.meta.Tag(Options) = @enumFromInt(self.tag);
            // std.log.err("xxxx: {x} {}", .{ slice, tag_enum });
            switch (tag_enum) {
                .unknown => return .unknown,
                .zcomperror => return .{ .zcomperror = try gpa.dupe(u8, payload) },
                .fill_options => {
                    var array = std.ArrayListUnmanaged([]const u8).empty;
                    var slice_start: usize = 0;
                    for (payload, 0..) |c, i| {
                        if (c == 0) {
                            const duped = try gpa.dupe(u8, payload[slice_start..i]);
                            try array.append(gpa, duped);
                            slice_start = i + 1;
                        }
                    }
                    return .{
                        .fill_options = try array.toOwnedSlice(gpa),
                    };
                },
                .int_range => {
                    const min: i32 = @bitCast(payload[0..4].*);
                    const max: i32 = @bitCast(payload[4..8].*);
                    return .{
                        .int_range = .{
                            .min = if (min == std.math.minInt(i32)) null else min,
                            .max = if (max == std.math.maxInt(i32)) null else max,
                        },
                    };
                },
                else => return error.UnknownField,
            }
        }
    };
};

pub fn streql(a: []const u8, b: []const u8) bool {
    return std.mem.eql(u8, a, b);
}
