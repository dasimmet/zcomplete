pub const options = @import("options");
const std = @import("std");
pub const linker_section_name = "zcomplete.wasm";

pub const AutoComplete = struct {
    allocator: std.mem.Allocator,
    cur: i32,
    cmd: [:0]const u8,
    args: []const [:0]const u8,
    response: Response.Options = .unknown,

    pub fn respond(self: *@This(), opt: Response.Options) void {
        self.response = opt;
    }
    pub fn serialize(self: *@This()) *Response.Serialized {
        return self.response.serialize(self.allocator);
    }
};

pub const Args = extern struct {
    version: u8 = 1,
    offset: i32,
    len: i32,
    cur: i32,

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
        const autocomp: *@This() = @alignCast(@ptrCast(buf.ptr));
        autocomp.* = .{
            .offset = @intCast(@sizeOf(@This())),
            .len = @as(i32, @intCast(mysize)) - @sizeOf(@This()),
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
        return autocomp;
    }

    pub fn readSlice(self: *@This()) []u8 {
        var ptr: [*]u8 = @alignCast(@ptrCast(self));
        return ptr[@intCast(self.offset)..@intCast(self.offset + self.len)];
    }

    pub fn parse(self: *@This(), gpa: std.mem.Allocator) !struct {
        cmd: [:0]const u8,
        args: []const [:0]const u8,
    } {
        const slice = self.readSlice();
        var array = std.ArrayListUnmanaged([:0]const u8).empty;
        var cmd: [:0]const u8 = undefined;
        var last_zero: usize = 0;
        for (slice, 0..) |c, i| {
            if (c == 0) {
                if (last_zero == 0) cmd = @ptrCast(slice[last_zero..i]);
                try array.append(gpa, @ptrCast(slice[last_zero..i]));
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
    pub const Options = union(enum(i32)) {
        unknown,
        zcomperror,
        fill_options: []const []const u8,
        _,

        pub fn deinit(self: @This(), gpa: std.mem.Allocator) void {
            switch (self) {
                else => {},
                .fill_options => |fo| {
                    for (fo) |opt| gpa.free(opt);
                    gpa.free(fo);
                },
            }
        }

        pub fn fillOptions(fo: []const []const u8) @This() {
            return .{ .fill_options = fo };
        }

        pub fn serialize(self: *@This(), gpa: std.mem.Allocator) *Serialized {
            const header_size = @sizeOf(Serialized);
            var acc = std.ArrayListUnmanaged(u8).initCapacity(
                gpa,
                header_size,
            ) catch unreachable;
            acc.appendNTimesAssumeCapacity(0, header_size);
            const res: *Serialized = @alignCast(@ptrCast(acc.items.ptr));
            res.offset = header_size;
            acc.appendSlice(gpa, &@as([4]u8, @bitCast(@intFromEnum(self.*)))) catch unreachable;
            switch (self.*) {
                .unknown => {},
                .fill_options => |opts| {
                    for (opts) |opt| {
                        acc.appendSlice(gpa, opt) catch unreachable;
                        acc.append(gpa, 0) catch unreachable;
                    }
                },
                else => {},
            }
            res.len = @intCast(acc.items.len - header_size);
            return res;
        }
    };

    pub const Serialized = extern struct {
        version: u8 = 1,
        offset: i32,
        len: i32,

        pub fn deinit(self: *@This(), gpa: std.mem.Allocator) void {
            gpa.free(self.readSlice());
            gpa.free(self);
        }

        pub fn readSlice(self: *@This()) []u8 {
            var ptr: [*]u8 = @alignCast(@ptrCast(self));
            return ptr[@intCast(self.offset)..@intCast(self.offset + self.len)];
        }

        pub fn parse(self: *@This(), gpa: std.mem.Allocator) !Options {
            const slice = self.readSlice();
            const tag: i32 = @as(*i32, @alignCast(@ptrCast(slice[0..4]))).*;
            const tag_enum: std.meta.Tag(Options) = @enumFromInt(tag);
            // std.log.err("xxxx: {x} {}", .{ slice, tag_enum });
            switch (tag_enum) {
                .unknown => return .unknown,
                .zcomperror => return .zcomperror,
                .fill_options => {
                    var array = std.ArrayListUnmanaged([]const u8).empty;
                    var slice_start: usize = 0;
                    for (slice[4..], 0..) |c, i| {
                        if (c == 0) {
                            const duped = try gpa.dupe(u8, slice[4 + slice_start .. 4 + i]);
                            try array.append(gpa, duped);
                            slice_start = i + 1;
                        }
                    }
                    return .{
                        .fill_options = try array.toOwnedSlice(gpa),
                    };
                },
                else => return error.UnknownField,
            }
        }
    };
};

pub fn pack_args(args: []const []const u8, out: []u8) void {
    var pos: usize = 0;
    for (args) |arg| {
        @memcpy(out[pos .. pos + arg.len], arg);
        pos += arg.len;
        out[pos] = 0;
        pos += 1;
    }
}
